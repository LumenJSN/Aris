//
//  ArisSessionLive.swift
//  aris-agent
//
//  The live parts of a prompt sent into a Claude Code session (ArisSessionSend): the app's session list (POST
//  /aris/sessions with the shared token), which process is the session (Claude Code's own list of its live sessions,
//  `claude agents --json`, else the process table by folder: libproc and sysctl, read only, a process's folder, its tty
//  and foreground group, and only its terminal variables), and the session's host (ArisSessionHost), reached the
//  host's own way (ArisSessionHostsLive, ArisSessionWindowsLive, ArisSessionDesktopLive). Nothing here decides:
//  ArisSessionSend does.
//

import AppKit
import ApplicationServices
import Carbon
import Darwin
import Foundation
import Vision

enum ArisSessionLive {
    static let appURL = URL(string: "http://127.0.0.1:23350/aris/sessions")!

    static var deps: ArisSessionDeps {
        ArisSessionDeps(sessions: { sessions() },
                        process: process,
                        focus: focus,
                        look: look,
                        paste: paste,
                        submit: submit,
                        submitted: submitted,
                        watch: { id in _ = post(["op": "watch", "session": id]) },
                        hold: { turn in
                            ArisDesktopLock.shared.acquire(ArisDesktopLock.Owner(id: turn.desktopOwner, live: { turn.live })) == .acquired
                        },
                        release: { turn in ArisDesktopLock.shared.done(turn.desktopOwner) },
                        finish: finish)
    }

    // MARK: - The app's sessions

    static func post(_ body: [String: Any], timeout: TimeInterval = 5) -> [String: Any]? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: appURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let configuration = ArisNoStore.configuration()
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let done = DispatchSemaphore(value: 0)
        let box = ArisSessionJSONBox()
        URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
            if let data { box.set((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return box.value
    }

    static func sessions() -> [ArisLiveSession]? {
        guard let reply = post(["op": "list"]), reply["ok"] as? Bool == true, let rows = reply["sessions"] as? [[String: Any]] else { return nil }
        return rows.compactMap(ArisLiveSession.init(json:))
    }

    /// The session took a prompt after `since`: its UserPromptSubmit (or any later working state), within a few seconds.
    static func submitted(_ id: String, since: Date) -> Bool {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if let session = sessions()?.first(where: { $0.id == id }) {
                let fresh = Double(session.secondsAgo) <= Date().timeIntervalSince(since) + 1
                if fresh, session.lastHook == "UserPromptSubmit" || ["thinking", "typing", "building", "juggling"].contains(session.state) { return true }
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    // MARK: - Which process is the session

    /// Claude Code's own list of its live sessions (the `claude` the agent knows; a few seconds at most); nil when it
    /// can't be had (an older Claude Code, no `claude`).
    static func agents() -> [ArisSessionAgents.Entry]? {
        guard let claude = ArisSessionHostsLive.executable([FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path,
                                                             "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]),
              let out = ArisSessionHostsLive.tool(claude, ["agents", "--json"], timeout: 6) else { return nil }
        return ArisSessionAgents.parse(Data(out.utf8))
    }

    /// The session's process: by its id in Claude Code's own list (exact, a terminal or none), else the one `claude`
    /// in its folder that its terminal ids tell apart (ArisSessionProcesses.pick).
    static func process(_ session: ArisLiveSession) -> ArisSessionProcessLook {
        // Not in the list (a Claude Code too old for it, or another copy that keeps its own): the folder way below.
        if let entries = agents(), entries.contains(where: { $0.sessionId == session.id }) {
            guard let entry = ArisSessionAgents.entry(for: session.id, in: entries) else { return .many }
            guard let row = anyRow(entry.pid), row.name == "claude" || row.name.hasPrefix("claude") else { return .none }
            return .found(ArisSessionProcesses.process(row, background: entry.background))
        }
        let known = (sessions() ?? []).filter { ($0.cwd as NSString).standardizingPath == (session.cwd as NSString).standardizingPath }.count
        return ArisSessionProcesses.pick(session, rows: processRows(), known: known)
    }

    // MARK: - Processes (read only)

    /// Every process with a terminal: its name, folder, tty and foreground group, and its terminal variables.
    static func processRows() -> [ArisProcessRow] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).compactMap { pid in pid > 0 ? row(pid) : nil }
    }

    static func row(_ pid: pid_t) -> ArisProcessRow? {
        guard let row = anyRow(pid), row.tty != nil else { return nil }
        return row
    }

    /// A process as the table shows it, with a terminal or none (the Claude app's sessions have none).
    static func anyRow(_ pid: pid_t) -> ArisProcessRow? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, let args = arguments(pid) else { return nil }
        let device = info.kp_eproc.e_tdev
        var tty: String?
        if device != -1, let name = devname(device, S_IFCHR) {
            let path = "/dev/" + String(cString: name)
            tty = ArisSessionProcesses.isTTY(path) ? path : nil
        }
        return ArisProcessRow(pid: pid, parent: info.kp_eproc.e_ppid, name: args.name, cwd: cwd(pid) ?? "", tty: tty,
                              foreground: tty == nil || info.kp_eproc.e_tpgid == info.kp_eproc.e_pgid, stopped: info.kp_proc.p_stat == SSTOP,
                              terminal: args.environment)
    }

    private static func arguments(_ pid: pid_t) -> (name: String, environment: [String: String])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0, size < 4 * 1_024 * 1_024 else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0 else { return nil }
        return ArisSessionProcesses.parseArgs(Array(bytes.prefix(size)), keys: ArisSessionProcesses.terminalKeys)
    }

    private static func cwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }

    /// The app the tty's process runs under: the first ordinary app among its parents.
    static func hostApp(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular { return app }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
            let parent = info.kp_eproc.e_ppid
            guard parent > 1, parent != current else { return nil }
            current = parent
        }
        return nil
    }

    // MARK: - The place, by its host

    /// The sessions reached, by a number handed out here (the look, the keys and the finish use the same one).
    nonisolated(unsafe) private static var reached: [Int: ArisSessionReach] = [:]
    nonisolated(unsafe) private static var nextReach = 1
    private static let lock = NSLock()

    /// The session's host from its process, and the place reached and proven the host's own way.
    static func focus(_ session: ArisLiveSession, _ process: ArisSessionProcess) -> Result<ArisSessionTarget, ArisSessionStop> {
        let app = hostApp(of: process.pid)
        let host = ArisSessionHost.classify(environment: process.environment, tty: process.tty.isEmpty ? nil : process.tty,
                                            hostBundle: app?.bundleIdentifier, hostName: app?.localizedName, background: process.background)
        switch ArisSessionHostsLive.reach(host, process: process, session: session, environment: process.environment) {
        case .failure(let why): return .failure(why)
        case .success(let reach):
            let number = lock.withLock { () -> Int in
                let number = nextReach
                nextReach += 1
                reached[number] = reach
                return number
            }
            return .success(ArisSessionTarget(appPid: app?.processIdentifier ?? process.pid, bundle: host.name, window: number))
        }
    }

    private static func reach(_ target: ArisSessionTarget) -> ArisSessionReach? { lock.withLock { reached[target.window] } }

    // (A reach that is gone is "the place moved"; nil from a reach is its own "ready", never flattened into that.)
    static func look(_ target: ArisSessionTarget) -> ArisSessionStop? {
        guard let reached = reach(target) else { return .focusMoved }
        return reached.look()
    }

    static func paste(_ text: String, _ target: ArisSessionTarget) -> ArisSessionStop? {
        guard !IsSecureEventInputEnabled() else { return .secureInput }
        guard let reached = reach(target) else { return .focusMoved }
        return reached.type(text)
    }

    static func submit(_ target: ArisSessionTarget) -> ArisSessionStop? {
        guard !IsSecureEventInputEnabled() else { return .secureInput }
        guard let reached = reach(target) else { return .focusMoved }
        return reached.submit()
    }

    /// Escape in the proven place (fleet.interrupt).
    static func escape(_ target: ArisSessionTarget) -> ArisSessionStop? {
        guard !IsSecureEventInputEnabled() else { return .secureInput }
        guard let reached = reach(target) else { return .focusMoved }
        return reached.escape()
    }

    /// The send is over: whatever was changed to reach the session is put back.
    static func finish(_ target: ArisSessionTarget) {
        guard let entry = lock.withLock({ reached.removeValue(forKey: target.window) }) else { return }
        entry.finish()
    }

    /// Writes title bytes to the tty's output (the terminal shows them; the program in it reads nothing: measured, zero
    /// bytes reached it in all three terminals). Only ArisSessionMark's sequences (a mark, the push and pop of a title,
    /// a title put back made plain) are ever written.
    static func write(_ bytes: [UInt8], tty: String) -> Bool {
        guard ArisSessionProcesses.isTTY(tty), bytes.first == 0x1B, bytes.last == 0x07 || bytes.last == UInt8(ascii: "t") else { return false }
        let fd = open(tty, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, bytes.count) } == bytes.count
    }

    /// Vision's lines, each with how far down the picture it sits (0 top, 1 bottom).
    static func read(_ image: CGImage) -> [(text: String, y: Double)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first.map { ($0.string, 1 - Double(observation.boundingBox.midY)) }
        }
    }

}

private final class ArisSessionJSONBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Any]?
    func set(_ value: [String: Any]?) { lock.withLock { stored = value } }
    var value: [String: Any]? { lock.withLock { stored } }
}
