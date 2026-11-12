//
//  ArisLookTarget.swift
//  aris-agent
//
//  Which app a look reads. It used to be whatever was frontmost at that instant, and a question typed into the notch
//  makes Aris itself frontmost (its field has the keyboard), as a macOS prompt does for a moment: the helper then
//  "read" Aris or the prompt and found no window (third VM run: "Aris has no window on screen", "UserNotificationCenter
//  has no window on screen"). The app's own screenshot shows the screen without Aris's windows; the look agrees with
//  it: when the app in front is Aris, the helper or one of macOS's own passing panels, it reads the app whose window
//  is topmost under them, which is the app the user was in. Which window that is, and whether it still was when the
//  read was over, is ArisFrontNow's (the window server's order, never NSWorkspace's stale front app: second upgrade
//  run, bug 1). Foundation only, so it is tested.
//

import Foundation

enum ArisLookTarget {
    /// macOS's own programs that are in front only to ask or show something: never what the user was looking at.
    static let passing: Set<String> = ["com.apple.usernotificationcenter", "com.apple.coreservices.uiagent", "com.apple.securityagent",
                                       "com.apple.notificationcenterui", "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.dock",
                                       "com.apple.loginwindow", "com.apple.windowmanager", "com.apple.screencaptureui", "com.apple.tccd"]

    /// Whether the app in front is one a look never reads as "what is on the screen": Aris, its helper, a passing panel.
    static func steppedOver(pid: Int32?, bundleId: String, aris: Int32?, own: Int32) -> Bool {
        guard let pid else { return true }
        // Aris's own windows (the reader, Settings) by its bundle id too, whoever asked.
        let id = bundleId.lowercased()
        return pid == aris || pid == own || passing.contains(id) || id.hasPrefix("com.lumenjsn.aris")
    }

    /// `aris-tools screen` for the app that is read: by its pid, so the tool captures that app's window and not
    /// whatever is frontmost when it starts; with `window`, exactly that window of it (the tool refuses one that is
    /// not that app's own window on screen: ArisScreenTarget.window).
    static func screenArguments(pid: Int32?, window: Int? = nil) -> [String] {
        guard let pid else { return ["screen"] }
        return ["screen", "--pid", String(pid)] + (window.map { ["--window", String($0)] } ?? [])
    }

    /// Set for the look's own `screen --pid` (ArisScreenTarget.helperKey in aris-tools): the tool takes a pid from
    /// nobody else, so no AI's command can name a process to read (security review 3, L1).
    static let helperKey = "ARIS_HELPER_LOOK"

    /// What the look's `aris-tools screen` gets in its environment: the helper's mark only when it names a pid.
    static func screenEnvironment(pid: Int32?) -> [String: String] {
        pid == nil ? [:] : [helperKey: "1"]
    }

    /// `aris-tools tab` for the browser that is read: by its bundle id, so the tool reads that browser's tab and not
    /// the first browser it finds running (with Aris in front it used to: security review 3, M1).
    static func tabArguments(bundleId: String) -> [String] {
        ["tab", "--text", "--app", bundleId]
    }
}
