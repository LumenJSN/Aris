//
//  ArisAppCaptureFirst.swift
//  Aris
//
//  The app takes its own smallest capture of the screen before it asks the helper for anything that may read the
//  screen (a look, a turn), whenever macOS's last yes to it is older than about 25 days (ArisFirstCapture.appCaptureDue).
//  macOS keeps one approval for the app and the helper inside it and asks again about monthly; the question names
//  whichever of the two captures first. Taken by the app, it says "Aris". The setup takes the very first one
//  (ArisOnboardingFirstCapture); this keeps it so afterwards. With Screen Recording off nothing is captured.
//  Not covered: a scheduled job that reads the screen while the app is closed, after the approval ran out, is asked
//  about by macOS under the helper's file name.
//

import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "see")

@MainActor
enum ArisAppCaptureFirst {
    private static var lastTry: Date?

    /// macOS said yes to the app's capture just now.
    static func allowed(defaults: UserDefaults = .standard, now: Date = Date()) {
        defaults.set(true, forKey: ArisFirstCapture.allowedKey)
        defaults.set(now, forKey: ArisFirstCapture.allowedAtKey)
    }

    static func ensure(defaults: UserDefaults = .standard) async {
        let now = Date()
        guard ArisFirstCapture.appCaptureDue(screenGranted: CGPreflightScreenCaptureAccess(), lastAllowed: defaults.object(forKey: ArisFirstCapture.allowedAtKey) as? Date,
                                             lastTry: lastTry, now: now) else { return }
        lastTry = now
        let outcome = await ArisScreenCapture.shared.firstCapture()
        log.notice("the app's own capture before the helper's: \(String(describing: outcome), privacy: .public)")
        if outcome == .allowed { allowed(defaults: defaults) }
    }
}
