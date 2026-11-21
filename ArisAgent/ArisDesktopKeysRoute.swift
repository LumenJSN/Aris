//
//  ArisDesktopKeysRoute.swift
//  aris-agent
//
//  POST /desktop-keys {"turn" | "held", "keys": [chord], "times", "app"?}: `aris-tools keys …` through Aris's own
//  engine. The old command brought the app to the front and posted the keys system-wide, outside the desktop lock and
//  the typing-gap rule. Now aris-tools only names the app (its exact-name and no-terminal checks stay there, and the
//  shell gate that rated the command is unchanged); here the turn takes its turn at the keys and pointer (ArisDesktopLock),
//  and the engine presses the keys into the app's focused window in the background, or after a brief turn in front in
//  a gap in the user's input (ArisNativeFocusGap) for an app that takes keys only in front, their front app given back after.
//  The target (the app named, else the one with the keyboard) is checked before anything is sent: keys into a terminal
//  or code runner (which would run them) go through the desktop gate exactly as `desktop press` there does (the user's
//  card with the exact keys for Return and characters); the agent's own held work, which has no card to ask on, never
//  sends into one, and sends only the keys it was given (ArisDesktopKeysPolicy).
//  Checked as /desktop-hold is: the turn's credential and the caller inside the brain's own process tree, or the
//  agent's own held work (a learned shortcut's replay). {"status", "output"}.
//

import AppKit
import ApplicationServices
import Foundation
import Network

extension ArisDesktopRoutes {
    static func keys(_ object: [String: Any], on connection: NWConnection, agentPort: UInt16, lock: ArisDesktopLock = .shared,
                     reply: @escaping (String, Data) -> Void) {
        let refuse = { (why: String) in
            ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why))", "question": "desktop-keys"]), key: "desktop")
            reply("403 Forbidden", ArisMCPRoutes.json(["status": 1, "output": "aris-tools keys works only inside an Aris turn."]))
        }
        // Only keys the engine's chord parser knows: a flag-shaped "key" (--window-id, --pid=…) is refused here, before
        // any routing, so only the window id the route itself finds chooses the target (and the policy checks it again).
        guard let keys = object["keys"] as? [String], !keys.isEmpty, keys.count <= 8, keys.allSatisfy(ArisDesktopKeysPolicy.isKey) else {
            return reply("400 Bad Request", ArisMCPRoutes.json(["status": 1, "output": "usage: keys cmd+shift+t [--app X] [--times N]"]))
        }
        let times = min(20, max(1, object["times"] as? Int ?? 1))
        let bundle = (object["app"] as? String).flatMap { $0.isEmpty || $0.count > 200 ? nil : $0 }
        // The app the keys go to (the one named, else the one with the keyboard), resolved before anything is sent: a
        // terminal or code runner would run them, so its keys go through the desktop gate or not at all.
        let target = { () -> Target? in
            let app = bundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first { !$0.isTerminated } }
                ?? (bundle == nil ? ArisFrontLive.focusedPid().flatMap { NSRunningApplication(processIdentifier: $0) } : nil)
            return app.map { Target(app: $0) }
        }
        let notRunning = ArisTypeReadbackWords.notSentLead + "that app isn't running, so \(keys.joined(separator: " ")) wasn't sent. Don't tell the user it was done."
        // The agent's own work that holds the whole Mac now: only the keys it was given, never into a code runner.
        if let held = object["held"] as? String {
            guard held.count <= 80, lock.holdsForOwnWork(held) else { return refuse("not the agent's own held work") }
            return DispatchQueue.global(qos: .userInitiated).async {
                guard let found = target() else { return reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": notRunning])) }
                switch ArisDesktopKeysPolicy.route(bundle: found.bundle, names: found.names, keys: keys, held: lock.allowedKeys(held)) {
                case .refuse(let why):
                    ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": "refused (\(why.prefix(80)))", "question": "desktop-keys"]), key: "desktop")
                    reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": why]))
                case .send, .gate:
                    let result = press(keys, times: times, app: found, owner: held, job: false)
                    reply("200 OK", ArisMCPRoutes.json(["status": result.ok ? 0 : 1, "output": result.line]))
                }
            }
        }
        guard let credential = object["turn"] as? String, let runner = ArisAgentRunner.runner(forMCPTurn: credential) else { return refuse("no turn credential") }
        let remotePort = ArisTeammateDesk.remotePort(of: connection)
        DispatchQueue.global(qos: .userInitiated).async {
            let now = runner.mcpSnapshot()
            guard now.active else { return refuse("no turn under way") }
            guard runner.brain != .antigravity else { return refuse("Antigravity uses the relay") }
            guard let pid = now.pid, let remotePort, ArisMCPCaller.isInside(root: pid, remotePort: remotePort, agentPort: agentPort) else {
                return refuse("not from the brain's own process")
            }
            let turn = ArisRunnerMCPTurn(runner: runner, handsFree: now.handsFree, screen: now.screen, credential: credential)
            guard let found = target() else { return reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": notRunning])) }
            switch ArisDesktopKeysPolicy.route(bundle: found.bundle, names: found.names, keys: keys, held: nil) {
            case .refuse(let why):
                reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": why]))
            case .gate:
                // As `desktop press` in that app: the one gate decides (the user's card with the exact keys for Return and
                // characters), its lock, its read-back.
                let words = ["press"] + Array(repeating: keys, count: times).flatMap { $0 } + ["--app", found.bundle ?? ""]
                ArisDesktopEngine.shared.handle(words, text: nil, turn: turn) { outcome in
                    reply("200 OK", ArisMCPRoutes.json(["status": Int(outcome.status), "output": outcome.output]))
                }
            case .send:
                let english = ArisDesktopCopy.isEnglish(turn.request)
                let started = Date()
                switch lock.acquire(ArisDesktopLock.Owner(id: turn.desktopOwner, live: { turn.live }), waiting: { turn.quiet(ArisDesktopLockWords.waitingLine(english: english)) }) {
                case .acquired:
                    defer { lock.done(turn.desktopOwner) }
                    let result = press(keys, times: times, app: found, owner: turn.desktopOwner, job: turn.isTask)
                    reply("200 OK", ArisMCPRoutes.json(["status": result.ok ? 0 : 1, "output": result.line]))
                case .refused(let why):
                    reply("200 OK", ArisMCPRoutes.json(["status": 1, "output": ArisDesktopLockWords.refusal(why, waited: Date().timeIntervalSince(started))]))
                }
            }
        }
    }

    /// The app keys go to, as the policy reads it.
    struct Target {
        let app: NSRunningApplication
        var bundle: String? { app.bundleIdentifier }
        var names: [String] { [app.localizedName, app.bundleURL?.deletingPathExtension().lastPathComponent].compactMap { $0 } }
    }

    /// The keys into the app's focused window by the engine.
    private static func press(_ keys: [String], times: Int, app target: Target, owner: String, job: Bool) -> (ok: Bool, line: String) {
        let written = keys.joined(separator: " ")
        let name = target.app.localizedName ?? target.bundle ?? "the app"
        let pid = target.app.processIdentifier
        guard let window = ArisAX.focusedWindowId(pid: pid) ?? ArisDesktopLiveWindows().windows(of: pid).first?.id else {
            return (false, ArisTypeReadbackWords.notSentLead + "\(name) has no window to send \(written) to. Don't tell the user it was done.")
        }
        // The trusted window id first, then `--`: nothing after it is ever read as a flag (ArisNativeCall).
        let words = ["press", "--window-id", String(window), "--json", "--"] + Array(repeating: keys, count: times).flatMap { $0 }
        let started = Date()
        let (_, output) = ArisNativeRunner.shared.run(words, context: ArisNativeContext(job: job, owner: owner, began: started))
        ArisOwnInput.shared.note(from: started, to: Date(), owner: owner)
        return ArisDesktopKeysWords.line(written, times: times, app: name, reply: ArisDesktopEnvelope.parse(output))
    }

    /// /desktop-hold's `"gap": true`: once the turn holds the keys and pointer, a moment with no input from the user before
    /// the command moves or raises windows (ArisNativeFocusGap); nil when it came, else the line that stops it.
    static func gapRefusal(owner: String, job: Bool) -> String? {
        let started = Date()
        guard !ArisNativeOwnerClock(owner: owner).awaitGap(job: job) else { return nil }
        return "The user kept typing or clicking for \(Int(Date().timeIntervalSince(started).rounded())) s, so nothing was moved or opened (Aris never does that under " +
            "their hands). Tell the user; they can ask again in a moment."
    }
}
