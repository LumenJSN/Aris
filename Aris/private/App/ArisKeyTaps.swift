//
//  ArisKeyTaps.swift
//  Aris
//
//  The dictation and gesture key taps start only once the first-run guide is done and macOS already lets Aris listen to
//  keys: a tap made without that asks macOS for Input Monitoring at launch, before onboarding (QA BUG-55). Until then
//  they're looked at again now and then; nothing here ever asks.
//

import AppKit
import CoreGraphics
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "launch")

@MainActor
enum ArisKeyTaps {
    private static var started = false
    private static var waiting: Task<Void, Never>?

    /// Pure: the taps may start.
    static func mayStart(onboardingSeen: Bool, listenAllowed: Bool) -> Bool { onboardingSeen && listenAllowed }

    static func startWhenAllowed() {
        guard !started else { return }
        let seen = UserDefaults.standard.bool(forKey: ArisOnboarding.seenKey)
        // Input Monitoring itself, checked on its own (CGPreflightListenEventAccess never prompts; a listen tap made on the
        // strength of Accessibility alone could still bring macOS's Input Monitoring prompt: security review of batch 3).
        if mayStart(onboardingSeen: seen, listenAllowed: CGPreflightListenEventAccess()) {
            started = true
            ArisDictationKeyTap.shared.start()
            ArisGestureKeyTap.shared.start()
            return
        }
        guard waiting == nil else { return }
        log.notice("key taps wait: \(seen ? "Input Monitoring isn't allowed yet" : "the first-run guide isn't finished", privacy: .public)")
        waiting = Task { @MainActor in
            while !Task.isCancelled, !started {
                try? await Task.sleep(for: .seconds(5))
                if mayStart(onboardingSeen: UserDefaults.standard.bool(forKey: ArisOnboarding.seenKey), listenAllowed: CGPreflightListenEventAccess()) {
                    waiting = nil
                    startWhenAllowed()
                    return
                }
            }
        }
    }
}
