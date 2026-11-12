//
//  ArisInsertRefusal.swift
//  aris-agent
//
//  Why aris-agent would not press ⌘V, said so the app can tell the one reason the user can fix from the rest. Typing
//  is a keystroke aris-agent posts itself, so macOS wants aris-agent's own switch in Accessibility; Aris.app's switch
//  does not count for it. That refusal used to reach the app as an English sentence only, which went to the log while
//  the notch said "nowhere to type". Now the reply also names what is missing (`needs`), and the app says it in the
//  user's language with the button that opens the list (ArisHelperRow). Foundation only (tested).
//

import Foundation

enum ArisInsertRefusal {
    /// aris-agent has no Accessibility of its own.
    static var needsAccessibility: String { "Aris needs \(ArisFix.Pane.accessibility.title(english: true)) (System Settings → Privacy & Security)" }
    /// What `needs` says for it: the word the look uses in its own `needs` list.
    static let accessibility = "accessibility"

    /// Apps ⌘V never goes into: password apps and Aris itself.
    static let refusedApps: Set<String> = ["com.apple.keychainaccess", "com.apple.passwords", "com.1password.1password",
                                           "com.agilebits.onepassword7", "com.lumenjsn.aris"]
    /// Said when Accessibility can't tell which app has the keyboard at this moment.
    static let noKeyboardApp = "no app has the keyboard right now (Accessibility couldn't tell which), so nothing was typed"

    /// Why ⌘V mustn't be pressed now, or nil when it may. `front`: the app Accessibility says has the keyboard at this
    /// moment, never a guess from the window order (security review 9, L4: after a click on the desktop, or a switch to
    /// an app with no window, the old app's window is still the topmost one).
    static func refusal(trusted: Bool, secureInput: Bool, front: ArisFrontLive.App?) -> String? {
        guard trusted else { return needsAccessibility }
        guard !secureInput else { return "a password field has the keyboard" }
        guard let front else { return noKeyboardApp }
        if let id = front.bundleId?.lowercased(), refusedApps.contains(id) || ArisCaptureRules.isPrivate(id) { return "won't type into \(front.name)" }
        return nil
    }

    /// The body of /insert's and /paste's answer when nothing was typed.
    static func reply(_ failure: String) -> [String: Any] {
        failure == needsAccessibility ? ["error": failure, "needs": accessibility] : ["error": failure]
    }
}
