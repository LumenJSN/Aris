//
//  ArisOnboardingFront.swift
//  Aris
//
//  Which of Aris's windows is in front while the first-run setup shows, pure so the tests check it: what comes forward
//  when the setup opens, when one of macOS's prompts closes, on the way back from System Settings, when Aris is opened
//  again (the Dock, Launchpad, Spotlight) and when its settings window closes; whether Aris is an app with a Dock icon
//  and a menu bar of its own; and when the setup takes the front back from another app.
//
//  Why the last two (VM run of 2026-11-10, bug 5): Aris is a menu-bar app, and to macOS such an app is never the one
//  "in front": the menu bar kept Terminal's menus over the setup window, and each time one of macOS's prompts closed
//  macOS handed the screen back to Terminal, so the speech recognition prompt sat on Terminal's window with the setup
//  behind it. While a window of the guide is open Aris is therefore an ordinary app (as it already is while its
//  settings window is open), and should another app still come forward during the prompts, or a moment after the
//  setup did, the setup window takes its place again. System Settings and macOS's own prompts are never covered
//  (fresh install F7–F9: ArisOnboardingStage.comesForward).
//

import Foundation

enum ArisOnboardingFront {
    // MARK: - What comes forward

    /// What happened.
    enum Event: Equatable {
        /// The setup window opens: at the first launch, or at a later one for the pages left (`quiet`), which a
        /// Quit & Reopen makes the user's own return (`reopened`).
        case opened(quiet: Bool, reopened: Bool)
        /// A moment of the permission page: macOS's prompt answered, a permission turned on, System Settings opened.
        case permission(ArisOnboardingStage.Forward)
        /// Aris was opened again while it runs: a click in the Dock, Launchpad, Spotlight, `open -a`.
        case reopened
        /// Aris's own settings window closed.
        case settingsClosed
    }

    /// What is in front afterwards.
    enum Front: Equatable {
        /// The guide's window (the veil in the intro, the setup window after it), with the keyboard.
        case guide
        /// The setup window in front of the other apps' windows, the keyboard left where it is.
        case guideQuietly
        /// Aris's settings window.
        case settings
        /// Nothing of Aris's moves.
        case nothing
    }

    static func front(after event: Event, phase: ArisOnboardingPhase) -> Front {
        switch event {
        case .opened(let quiet, let reopened):
            return ArisOnboardingStage.activates(quiet: quiet, reopened: reopened) ? .guide : .guideQuietly
        case .permission(let moment):
            return ArisOnboardingStage.comesForward(after: moment, phase: phase) ? .guide : .nothing
        case .reopened:
            // Unfinished, the setup is what the user came back for (VM bug 6: Settings opened over it); after it,
            // opening Aris again opens Settings as it always did.
            return unfinished(phase) ? .guide : .settings
        case .settingsClosed:
            return unfinished(phase) ? .guide : .nothing
        }
    }

    /// The guide still has a window of its own: the veil or the setup window. At the finish (the window is closing and
    /// the notch says its line) the setup is over.
    static func unfinished(_ phase: ArisOnboardingPhase) -> Bool { phase != .closed && phase != .finish }

    // MARK: - An app of its own while a window is open

    /// Whether Aris has a Dock icon and a menu bar of its own: exactly while a window of the guide or its settings
    /// window is open. Otherwise it is the menu-bar app it always was.
    static func regularApp(guideWindow: Bool, settingsOpen: Bool) -> Bool { guideWindow || settingsOpen }

    // MARK: - Taking the front back

    /// Who came to the front.
    enum Taker: Equatable {
        case aris
        /// System Settings: the user is sent there for Accessibility and Screen Recording, and it stays in front.
        case systemSettings
        /// Another app with a Dock icon and windows of its own.
        case app
        /// A process with no Dock icon: macOS's prompts and password windows are put up by these.
        case agent
    }

    /// System Settings, under its name before and since macOS 13.
    static let systemSettingsIDs: Set<String> = ["com.apple.systempreferences", "com.apple.SystemSettings"]

    static func taker(bundleID: String?, own: String?, regular: Bool) -> Taker {
        if let bundleID, bundleID == own { return .aris }
        if let bundleID, systemSettingsIDs.contains(bundleID) { return .systemSettings }
        return regular ? .app : .agent
    }

    /// For this long after the setup window came forward, another app coming forward is macOS handing the screen back
    /// late; after it, it is the user switching apps.
    static let settle: Double = 2
    /// The setup takes the front back at most this many times in a row, so two apps never fight over it.
    static let maxHolds = 4
    /// macOS may refuse the activation, or finish the other app's a moment later: the front is looked at once more.
    static let recheck: Double = 0.3

    /// Whether the setup window takes the front back from what just came forward. Only from another app, only while
    /// the setup window shows, and only while macOS's own prompts for a card are being answered (`prompting`: Terminal
    /// came forward between the microphone's prompt and the speech recognition one) or within `settle` of the setup
    /// coming forward itself (`sinceForward`, nil when it never did or System Settings was opened since).
    static func holds(against taker: Taker, phase: ArisOnboardingPhase, prompting: Bool, sinceForward: Double?, held: Int) -> Bool {
        guard taker == .app, phase == .setup || phase == .handoff, held < maxHolds else { return false }
        if prompting { return true }
        guard let sinceForward else { return false }
        return sinceForward >= 0 && sinceForward < settle
    }
}
