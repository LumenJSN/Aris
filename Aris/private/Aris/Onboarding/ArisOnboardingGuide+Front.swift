//
//  ArisOnboardingGuide+Front.swift
//  Aris
//
//  The guide's window in front (ArisOnboardingFront decides; these are the AppKit calls): Aris is an app with a Dock
//  icon and a menu bar of its own while a window of the guide is open, the setup window comes forward after macOS's
//  prompts and a permission turning on, when Aris is opened again and when its settings window closes, and it takes
//  the front back when macOS hands the screen to the app that was in front before (VM run of 2026-11-10, bugs 5 and 6).
//

import AppKit

extension ArisOnboardingGuide {
    /// The veil or the setup window is open.
    var hasWindow: Bool { overlay != nil || window != nil }

    /// Aris with a Dock icon and its own menu bar while a window of the guide or the settings window is open, the
    /// menu-bar app otherwise. Called as the guide's windows open and close.
    func applyPolicy() {
        let settingsOpen = NSApp.windows.contains { $0.identifier?.rawValue == "ArisSettingsWindow" && ($0.isVisible || $0.isMiniaturized) }
        let regular = ArisOnboardingFront.regularApp(guideWindow: hasWindow, settingsOpen: settingsOpen)
        let policy: NSApplication.ActivationPolicy = regular ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    /// The setup window is coming forward on purpose: from now, for a moment, another app covering it is macOS's doing.
    func claimFront() {
        forwardAt = Self.now()
        frontHolds = 0
        lookAgain()
    }

    /// macOS may drop an activation, or finish another app's a moment later: who is in front is looked at once more.
    private func lookAgain() {
        after(ArisOnboardingFront.recheck, name: "front") { guide in
            let front = NSWorkspace.shared.frontmostApplication
            guide.appCameForward(bundleID: front?.bundleIdentifier, regular: front?.activationPolicy == .regular)
        }
    }

    /// macOS's prompt was answered, or a permission turned on: the setup window is in front again with the keyboard
    /// (fresh install F7: after the microphone's prompts the app that was active before covered it). Only while the
    /// setup window shows, and never while System Settings is up for a permission.
    func comeForward(after event: ArisOnboardingStage.Forward) {
        // Sent to System Settings: whatever comes forward next is the user's doing there.
        if event == .settingsOpened { forwardAt = nil }
        guard let window, ArisOnboardingFront.front(after: .permission(event), phase: phase) == .guide else { return }
        claimFront()
        window.bringForward()
    }

    /// Aris was opened again while it runs (the Dock, Launchpad, Spotlight, `open -a`). While the setup is unfinished
    /// its window comes forward and nothing else opens (VM bug 6: Settings opened over it); false once it is over,
    /// and the app opens Settings as it always did.
    func openedAgain() -> Bool {
        guard ArisOnboardingFront.front(after: .reopened, phase: phase) == .guide else { return false }
        surface()
        return true
    }

    /// Aris's settings window closed (opened from the guide to change the talk key): the guide is in front again.
    func settingsClosed() {
        guard ArisOnboardingFront.front(after: .settingsClosed, phase: phase) == .guide else { return }
        surface()
    }

    /// An app came to the front. While macOS's prompts for a card are being answered, or a moment after the setup
    /// window came forward, another app there is macOS handing the screen back to what was in front before (VM bug 5:
    /// Terminal covered the setup under the speech recognition prompt): the setup window takes its place again, behind
    /// the prompt. Never over System Settings or macOS's own prompts, and only a few times in a row.
    func appCameForward(bundleID: String?, regular: Bool) {
        guard let window else { return }
        let taker = ArisOnboardingFront.taker(bundleID: bundleID, own: Bundle.main.bundleIdentifier, regular: regular)
        guard ArisOnboardingFront.holds(against: taker, phase: phase, prompting: model?.prompting ?? false,
                                        sinceForward: forwardAt.map { Self.now() - $0 }, held: frontHolds) else { return }
        frontHolds += 1
        window.bringForward()
        lookAgain()
    }
}
