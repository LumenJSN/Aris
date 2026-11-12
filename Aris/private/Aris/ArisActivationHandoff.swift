//
//  ArisActivationHandoff.swift
//  Aris
//
//  A yes on a card about another app's window gives macOS activation back to that app before the agent acts (QA retest
//  on 8e236bff: clicking 허용 is a real press, so Aris became the active app, and the focus guard and the step checks
//  then found Aris in front: approved typing never landed). The card's keys are released, Aris yields activation to the
//  target (macOS 14's cooperative activation lets the active app hand it over) and activates it; the agent then raises
//  and keys the pinned window and checks it is in front before anything is sent.
//

import AppKit

@MainActor
enum ArisActivationHandoff {
    /// After the user's yes on a card: only a desktop card, only to the process it names, still that same process.
    static func yield(after allow: Bool, on card: ArisConfirmation) {
        guard let aimed = card.desktop, let app = NSRunningApplication(processIdentifier: aimed.pid), !app.isTerminated,
              ArisCardAnswer.yieldsActivation(allow: allow, card: aimed, own: ProcessInfo.processInfo.processIdentifier,
                                              bundle: app.bundleIdentifier, started: ArisProcessStart.of(pid: aimed.pid)) else { return }
        // No panel of Aris's keeps the keyboard: the card's keys go, and the panel the click made key resigns it.
        KeyboardFocus.releaseCard()
        let key = NSApp.windows.first { $0 is ArisKeyPanel && $0.isKeyWindow }
        ArisPanelKeys.closed(key)
        key?.resignKey()
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: aimed.bundle)
            _ = app.activate()
        } else {
            _ = app.activate(options: [])
            NSApp.deactivate()
        }
    }
}
