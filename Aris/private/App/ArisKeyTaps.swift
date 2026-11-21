//
//  ArisKeyTaps.swift
//  Aris
//
//  The dictation and gesture key taps start only once the first-run guide is through (finished or put off) and macOS
//  lets Aris listen to keys: a tap made without that asks macOS for Input Monitoring at launch, before onboarding (QA
//  BUG-55). Past the guide without the grant, macOS is asked once (CGRequestListenEventAccess); until it is granted
//  the taps are looked at again now and then, and at once when a permission changes (ArisPermissionCenter) or the
//  guide closes. macOS answers the listen check once per process: a grant given while Aris runs (Accessibility during
//  the first setup counts) is offered as the one "reopen" card instead of leaving the keys dead (VM run 2026-11-18, D1).
//

import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "launch")

/// Input Monitoring for the key taps: never asked before the guide (QA BUG-55), asked once after it. Pure (tested).
enum ArisListenAccess {
    static let askedKey = "arisListenAccessAsked"

    static func asks(pastFirstRun: Bool, granted: Bool, askedBefore: Bool) -> Bool { pastFirstRun && !granted && !askedBefore }
}

/// What this process can do about listening to keys now (ArisListenOutlook), read live. Not on the main actor: the
/// permission layer's live checks read it too.
enum ArisListenNow {
    /// Accessibility when this process began: read once, first thing at launch (ArisKeyTaps.startWhenAllowed).
    static let trustedAtLaunch: Bool = AXIsProcessTrusted()

    static var outlook: ArisListenOutlook {
        .of(listenNow: CGPreflightListenEventAccess(), trustedNow: AXIsProcessTrusted(), trustedAtLaunch: trustedAtLaunch)
    }
}

@MainActor
enum ArisKeyTaps {
    private static var started = false
    private static var waiting: Task<Void, Never>?

    /// Pure: the taps may start.
    static func mayStart(onboardingSeen: Bool, listenAllowed: Bool) -> Bool { onboardingSeen && listenAllowed }

    /// At launch, every few seconds while they wait, when a permission changed and when the guide closes.
    static func startWhenAllowed() {
        guard !started else { return }
        _ = ArisListenNow.trustedAtLaunch
        let outlook = ArisListenNow.outlook
        // Through the guide once, finished or put off: closing it early must not leave the taps dead.
        // Input Monitoring itself, checked on its own (CGPreflightListenEventAccess never prompts; a listen tap made on the
        // strength of Accessibility alone could still bring macOS's Input Monitoring prompt: security review of batch 3).
        if mayStart(onboardingSeen: ArisOnboarding.pastFirstRunNow, listenAllowed: outlook == .ready) {
            started = true
            waiting?.cancel()
            waiting = nil
            ArisDictationKeyTap.shared.start()
            ArisGestureKeyTap.shared.start()
            log.notice("key taps: started")
            return
        }
        // Nothing is asked or offered over the guide (it shows from launch on a first run): only once it has closed.
        let seen = ArisOnboarding.pastFirstRunNow && !ArisOnboardingGuide.shared.showing
        if seen, outlook == .afterRelaunch {
            // Allowed, but only a new process sees it: the one "reopen" card, once for this grant.
            ArisPermissionCenter.shared.offerRelaunch(.inputMonitoring, for: .dictationKey)
        } else if ArisListenAccess.asks(pastFirstRun: seen, granted: false, askedBefore: UserDefaults.standard.bool(forKey: ArisListenAccess.askedKey)) {
            // Past the guide and still no Input Monitoring: macOS is asked once (its own prompt, which adds Aris to the
            // list); the taps go on waiting for the grant, and the state is in the log (they never start without it).
            UserDefaults.standard.set(true, forKey: ArisListenAccess.askedKey)
            let granted = CGRequestListenEventAccess()
            log.notice("Input Monitoring asked for: \(granted ? "granted" : "not granted yet", privacy: .public)")
            if granted { return startWhenAllowed() }
        }
        guard waiting == nil else { return }
        let why = !ArisOnboarding.pastFirstRunNow ? "the first-run guide isn't finished"
            : outlook == .afterRelaunch ? "key access was given while Aris runs (macOS lets it listen once Aris is reopened)"
            : "Input Monitoring isn't granted (the dictation and gesture keys do nothing until it is)"
        log.notice("key taps wait: \(why, privacy: .public)")
        waiting = Task { @MainActor in
            while !Task.isCancelled, !started {
                try? await Task.sleep(for: .seconds(5))
                startWhenAllowed()
            }
        }
    }
}
