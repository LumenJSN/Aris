//
//  ArisAutomationGate.swift
//  aris-tools (jv-prompts)
//
//  The live half of ArisAutomationAsk: macOS's answer for the target app, read without asking (an app that isn't
//  running is started hidden first, as osascript would start it anyway, so its answer can be read), and the app's one
//  line of why before macOS's first Automation dialog (POST /aris/permission, ArisPermissionRoute).
//

import AppKit
import Foundation

/// Before an Apple Event to `bundleId` that `feature` needs: returns to send it, or fails without sending.
/// `lead`: put before a refusal (a message's "NOT SENT" lead), so the failure reads like the command's others.
func automationGate(_ bundleId: String, app: String, feature: ArisPermissionFeature, lead: String = "") {
    let foreground = ArisAutomationAsk.isForeground(ProcessInfo.processInfo.environment)
    switch ArisAutomationAsk.step(state: automationState(bundleId), foreground: foreground, app: app, feature: feature) {
    case .send:
        return
    case .refuse(let line):
        fail(lead + line, fix: .pane(.automation))
    case .sayThenSend(let name):
        // The app says the feature's line (once, through its permission layer); then the event goes and macOS asks.
        // Whatever the app answers (or if it doesn't), macOS has never been asked: its own dialog decides.
        _ = askPermission(feature: name)
    }
}

/// Whether a fallback channel to `bundleId` may be used: only when the grant is already there (never asks).
func automationAlreadyGranted(_ bundleId: String) -> Bool {
    ArisAutomationAsk.fallbackAllowed(automationState(bundleId))
}

/// macOS's answer for `bundleId`, never asking. `start`: an installed app that isn't running is started hidden and
/// without taking the front first (macOS can't answer about an app that isn't running).
func automationState(_ bundleId: String, start: Bool = true) -> ArisPermissionState {
    let state = ArisAutomationAccess.state(of: bundleId)
    guard state == .unknown, start, NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty,
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return state }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.hides = true
    configuration.addsToRecentItems = false
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in done.signal() }
    _ = done.wait(timeout: .now() + 5)
    return ArisAutomationAccess.state(of: bundleId)
}

/// Asks the Aris app whether `feature` may go ahead (it says the line first); nil when the app didn't answer.
func askPermission(feature: String) -> [String: Any]? {
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23350/aris/permission") else { return nil }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["feature": feature])
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    ArisNoStore.session.dataTask(with: request) { data, response, _ in
        if (response as? HTTPURLResponse)?.statusCode == 200, let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + 11)
    return reply
}

// MARK: - A script that waits on macOS's dialog (tenth VM run, item 6)

/// macOS's answer, never asking, for each app an osascript run drives (its `-e` scripts' `application "…"` targets; an
/// app that isn't on ArisPermissionWait's list is found by its name among the running apps). Nothing is started.
func automationStates(of arguments: [String]) -> [ArisPermissionState] {
    var scripts: [String] = []
    var index = 0
    while index + 1 < arguments.count {
        if arguments[index] == "-e" { scripts.append(arguments[index + 1]) }
        index += 1
    }
    let targets = scripts.flatMap(ArisPermissionWait.scriptTargets)
    return targets.compactMap { target -> ArisPermissionState? in
        guard target.hasPrefix(ArisPermissionWait.namePrefix) else { return automationState(target, start: false) }
        let name = String(target.dropFirst(ArisPermissionWait.namePrefix.count))
        let bundle = NSWorkspace.shared.runningApplications.first { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }?.bundleIdentifier
        return bundle.map { automationState($0, start: false) }
    }
}

/// The look an osascript run takes at its limit (ArisBoundedRun.capture's `atLimit`): while macOS is still asking the
/// owner about an app the script drives, the same script goes on for the rest of his time (ArisPermissionWait.dialog)
/// instead of being stopped and called unanswered. Nil for any other program.
func automationWait(_ program: String, _ arguments: [String]) -> ((TimeInterval) -> TimeInterval?)? {
    guard (program as NSString).lastPathComponent == "osascript" else { return nil }
    // macOS's answer as the script goes: a script sent while it was asking waits out his time even when the look at the
    // limit can't read that it still is (eleventh VM run, P11).
    let before = automationStates(of: arguments)
    return { waited in ArisPermissionWait.automationExtension(before: before, states: automationStates(of: arguments), waited: waited) }
}
