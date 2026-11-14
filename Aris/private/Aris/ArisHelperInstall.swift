//
//  ArisHelperInstall.swift
//  Aris
//
//  At launch the app makes its own helper the one that runs: the XPC helper writes the LaunchAgent for the aris-agent
//  inside this app, loads it and waits until it answers with this app's build (ArisAgentInstall). A new Mac needs no
//  script, an app that was moved gets its job rewritten, and an install made the old way is switched over. The same
//  call repairs a helper that runs another build than the app (ArisAgentMonitor asks for it), which used to be only a
//  warning in the log. What the user is told, and when, is ArisHelperInstallWords'.
//

import AppKit
import ApplicationServices
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "install")

@MainActor
final class ArisHelperInstall {
    static let shared = ArisHelperInstall()

    private(set) var outcome: ArisAgentInstallOutcome?
    private var running: Task<ArisAgentInstallOutcome, Never>?
    /// Long enough after launch that the notch is on screen (ArisPrerequisiteNotice's own wait).
    static let sayAfter: Duration = .seconds(3)

    private init() {}

    func atLaunch(defaults: UserDefaults = .standard) {
        guard !ArisPrerequisites.current().contains(.helper) else { return log.error("this Aris.app has no helper inside it: nothing to install") }
        Task {
            // Before the switch: could the helper that runs now read Messages and Mail? (Only that user is told
            // about Full Disk Access afterwards.) No helper running is "not known".
            let hadDisk = await ArisAgentClient.agentHasDiskAccess()
            let outcome = await install()
            if let line = ArisHelperInstallWords.atLaunch(outcome) { await say(line) }
            guard outcome.isUp else { return }
            // The old helper's rows: due once for an install that had (or may have had) the old helper; said when the
            // notch is quiet, at this launch or a later one.
            if ArisHelperInstallWords.oldRowsBecomeDue(outcome, checkedBefore: defaults.bool(forKey: ArisHelperInstallWords.oldRowsCheckedKey),
                                                       wasSetUp: defaults.bool(forKey: ArisOnboarding.seenKey)) {
                defaults.set(true, forKey: ArisHelperInstallWords.oldRowsDueKey)
            }
            defaults.set(true, forKey: ArisHelperInstallWords.oldRowsCheckedKey)
            defer { Task { await self.sayOldRows(defaults: defaults) } }
            let appSwitchOn = AXIsProcessTrusted(), helperSays = await ArisAgentClient.agentHasAccessibility()
            if ArisHelperInstallWords.mappingLost(appSwitchOn: appSwitchOn, helperSays: helperSays) {
                log.error("\(ArisHelperInstallWords.mappingLostLog, privacy: .public)")
            } else {
                log.notice("accessibility: Aris's switch \(appSwitchOn ? "on" : "off", privacy: .public), the helper says \(helperSays.map { $0 ? "on" : "off" } ?? "nothing", privacy: .public)")
            }
            guard outcome == .switched else { return }
            let hasDisk = await ArisAgentClient.agentHasDiskAccess()
            let word = { (access: Bool?) in access.map { $0 ? "on" : "off" } ?? "not known" }
            log.notice("switched to the helper inside the app (Full Disk Access before: \(word(hadDisk), privacy: .public), now: \(word(hasDisk), privacy: .public))")
            guard ArisHelperInstallWords.diskLineDue(outcome, hadBefore: hadDisk, hasNow: hasDisk,
                                                    saidBefore: defaults.bool(forKey: ArisHelperInstallWords.diskSaidKey)) else { return }
            if await say(ArisHelperInstallWords.diskAfterSwitch()) { defaults.set(true, forKey: ArisHelperInstallWords.diskSaidKey) }
        }
    }

    /// How often, and how many times, the old rows' line looks for a quiet notch at one launch.
    static let oldRowsLook: Duration = .seconds(20)
    static let oldRowsLooks = 30

    /// Says the old rows' line once the notch is quiet (after any other line of this launch); kept due for the next
    /// launch when it never was.
    private func sayOldRows(defaults: UserDefaults) async {
        guard ArisHelperInstallWords.oldRowsSaidNow(due: defaults.bool(forKey: ArisHelperInstallWords.oldRowsDueKey),
                                                    saidBefore: defaults.bool(forKey: ArisHelperInstallWords.oldRowsSaidKey)) else { return }
        for _ in 0..<Self.oldRowsLooks {
            try? await Task.sleep(for: Self.oldRowsLook)
            guard ArisController.shared.session.reply.isEmpty else { continue }
            if await say(ArisHelperInstallWords.oldRows()) {
                defaults.set(true, forKey: ArisHelperInstallWords.oldRowsSaidKey)
                defaults.set(false, forKey: ArisHelperInstallWords.oldRowsDueKey)
                return log.notice("said once: the old helper's rows can be removed")
            }
        }
    }

    /// Installs or repairs; calls made while one is under way wait for that one.
    @discardableResult
    func install() async -> ArisAgentInstallOutcome {
        if let running { return await running.value }
        let task = Task { await ArisHelperClient.shared.installArisAgent() }
        running = task
        let outcome = await task.value
        running = nil
        self.outcome = outcome
        if outcome.isUp {
            log.notice("helper install: \(outcome.word, privacy: .public)")
        } else {
            log.error("helper install: \(outcome.word, privacy: .public)")
        }
        return outcome
    }

    /// One line on a card under the notch with its button (ArisAppFix, the same press the button under the line made),
    /// never over the setup or a turn already under way: it waits for them (ArisController.notify). True once it is up.
    @discardableResult
    private func say(_ line: String) async -> Bool {
        try? await Task.sleep(for: Self.sayAfter)
        return await ArisController.shared.notify(ArisNoticeRoute.problem(line: line, english: ArisUIWords.english))
    }
}
