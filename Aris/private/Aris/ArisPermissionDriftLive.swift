//
//  ArisPermissionDriftLive.swift
//  Aris
//
//  ArisPermissionDrift at launch: what macOS grants now, against the last launch's record; a lost one is said once.
//  Reading these never prompts.
//

import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Defaults
import os
import Speech

@MainActor
enum ArisPermissionDriftLive {
    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "permissions")

    /// What macOS grants Aris now, of the lists the check knows.
    static func granted() -> Set<ArisFix.Pane> {
        var on: Set<ArisFix.Pane> = []
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { on.insert(.microphone) }
        if SFSpeechRecognizer.authorizationStatus() == .authorized { on.insert(.speech) }
        if AXIsProcessTrusted() { on.insert(.accessibility) }
        if CGPreflightListenEventAccess() { on.insert(.listen) }
        if CGPreflightScreenCaptureAccess() { on.insert(.screen) }
        return on
    }

    static func checkAtLaunch() {
        let defaults = UserDefaults.standard
        let now = granted()
        let lost = ArisPermissionDrift.lost(needed: ArisPermissionDrift.needed(seesScreen: Defaults[.arisSeesScreen]), granted: now,
                                            before: defaults.stringArray(forKey: ArisPermissionDrift.lastGrantedKey))
        defaults.set(ArisPermissionDrift.record(now), forKey: ArisPermissionDrift.lastGrantedKey)
        guard let notice = ArisPermissionDrift.notice(lost: lost, english: ArisUIWords.english) else { return }
        log.notice("permissions lost since the last launch: \(lost.map(\.rawValue).joined(separator: ","), privacy: .public)")
        _ = ArisNoticeCenter.shared.enqueue(notice)
    }
}
