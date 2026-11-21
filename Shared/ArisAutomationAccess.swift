//
//  ArisAutomationAccess.swift
//  Aris, aris-agent
//
//  Whether Aris may already send Apple Events to an app, asked without ever showing macOS's dialog
//  (AEDeterminePermissionToAutomateTarget with askUserIfNeeded false). The app layer calls it to pick a channel: with
//  no grant yet, an Accessibility channel (menu commands, the AX tree) does the job without a per-app Automation
//  prompt. Blocks while macOS answers, so call it off the main thread. Process-wide: the app and the helper are the
//  same "Aris" row, so either one's answer is the row's.
//

import CoreServices
import Foundation

enum ArisAutomationAccess {
    /// The state macOS's answer means: noErr, errAEEventNotPermitted (-1743), errAEEventWouldRequireUserConsent
    /// (-1744). Anything else, procNotFound (-600) for a target that isn't running among them, is not known.
    static func state(status: OSStatus) -> ArisPermissionState {
        switch status {
        case noErr: .granted
        case OSStatus(errAEEventNotPermitted): .denied
        case OSStatus(errAEEventWouldRequireUserConsent): .notAsked
        default: .unknown
        }
    }

    /// What macOS says about Aris driving `bundleId`, never asking.
    static func state(of bundleId: String) -> ArisPermissionState {
        var target = AEAddressDesc()
        let bytes = Data(bundleId.utf8)
        guard !bytes.isEmpty, bytes.withUnsafeBytes({ AECreateDesc(typeApplicationBundleID, $0.baseAddress, bytes.count, &target) }) == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        return state(status: AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false))
    }

    /// True only when the grant exists now.
    static func granted(_ bundleId: String) -> Bool { state(of: bundleId) == .granted }
}
