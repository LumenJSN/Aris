//
//  ArisOnboardingGuide+Leave.swift
//  Aris
//
//  What is left in front when the setup's window closes (ArisSetupLeave decides; these are the AppKit calls). The
//  setup sends the user to System Settings for Accessibility and Screen Recording, and after Finish that window was
//  what they were left looking at (VM run 2026-11-11, bug 5). A System Settings the setup started, and the user has not
//  gone back to since, is hidden as the window closes (Aris is sandboxed and can't quit another app; hidden, it is off
//  the screen and still open in the Dock), and the app the user last had comes forward. Anything else is left as it is.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "onboarding")

extension ArisOnboardingGuide {
    /// System Settings, if it is running.
    private static var systemSettings: NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            !app.isTerminated && app.bundleIdentifier.map(ArisOnboardingFront.systemSettingsIDs.contains) == true
        }
    }

    // MARK: - Remembering

    /// As the guide opens: the app the user has in front now, and (back from Quit & Reopen) the System Settings the
    /// setup had started before the quit.
    func beginLeave() {
        let defaults = UserDefaults.standard
        let front = NSWorkspace.shared.frontmostApplication
        let taker = ArisOnboardingFront.taker(bundleID: front?.bundleIdentifier, own: Bundle.main.bundleIdentifier, regular: front?.activationPolicy == .regular)
        leave = ArisSetupLeave.restored(saved: defaults.dictionary(forKey: ArisSetupLeave.key), runningPid: Self.systemSettings?.processIdentifier,
                                        frontApp: taker == .app ? front?.bundleIdentifier : nil)
        keepLeave()
    }

    /// What the setup started is kept as it changes, not only at a tidy quit: macOS's Quit & Reopen after Screen
    /// Recording ends Aris mid-setup, and the setup that comes back must still know that System Settings is its own.
    /// It counts later only while that same process runs (ArisSetupLeave.restored), and goes when the guide closes.
    private func keepLeave() {
        if let saved = leave.saved {
            UserDefaults.standard.set(saved, forKey: ArisSetupLeave.key)
        } else {
            UserDefaults.standard.removeObject(forKey: ArisSetupLeave.key)
        }
    }

    /// The guide closed for good (not a quit mid-way): nothing is kept.
    func forgetLeave() { UserDefaults.standard.removeObject(forKey: ArisSetupLeave.key) }

    /// A card's 허용 is about to open System Settings: its list for Accessibility or Screen Recording, or the pane of
    /// a permission macOS won't ask for twice.
    func sendingToSettings(for card: ArisPermissionCard) {
        let refused = card.steps.contains { model?.live[$0] == .denied }
        guard card.way == .settings || refused else { return }
        leave.sending(runningPid: Self.systemSettings?.processIdentifier)
        keepLeave()
    }

    /// An app came to the front (ArisOnboardingWatch): who the user is with now.
    func noteFront(bundleID: String?, regular: Bool) {
        let taker = ArisOnboardingFront.taker(bundleID: bundleID, own: Bundle.main.bundleIdentifier, regular: regular)
        let before = leave
        leave.cameForward(taker, bundleID: bundleID, settingsPid: Self.systemSettings?.processIdentifier,
                          sinceForward: forwardAt.map { Self.now() - $0 })
        if leave != before { keepLeave() }
    }

    // MARK: - As the window closes

    /// The window is about to go: a System Settings that is only there because the setup opened it steps out of the
    /// way, and the app to bring forward once the window is gone is remembered (`handBack`).
    func stepBackFromSettings() {
        let settings = Self.systemSettings
        let plan = leave.plan(runningPid: settings?.processIdentifier, quitting: quitting)
        guard plan.hidesSettings else { return }
        let asked = settings?.hide() ?? false
        // hide() answers before the app is hidden (it said "hidden: false" for a System Settings that then was): the
        // log line is written from what the app says a moment later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            log.notice("setup closing: System Settings (opened by the setup, not used since) hidden: \(settings?.isHidden ?? asked, privacy: .public)")
        }
        handBackTo = plan.activates
        leave.done()
        keepLeave()
    }

    /// The window is gone: the app the user last had is in front again (only after `stepBackFromSettings` had
    /// something to step back from; otherwise macOS's own order stands).
    func handBack() {
        guard let bundleID = handBackTo else { return }
        handBackTo = nil
        guard let app = NSWorkspace.shared.runningApplications.first(where: { !$0.isTerminated && $0.bundleIdentifier == bundleID }) else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}
