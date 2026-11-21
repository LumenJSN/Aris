//
//  ArisListenOutlook.swift
//  Aris (ArisCore)
//
//  Whether the dictation and gesture key taps can listen to keys in this process, after a relaunch, or not yet.
//  macOS answers the listen check (CGPreflightListenEventAccess, IOHIDCheckAccess) once per process: a grant made while
//  Aris runs is not seen until it is reopened. Accessibility given in System Settings counts for listening too, so
//  Accessibility turned on during the first setup left the keys dead until a relaunch with nothing said (VM run
//  2026-11-18, D1: no Input Monitoring row at all, the keys worked after quit and reopen). Pure.
//

import Foundation

enum ArisListenOutlook: Equatable, Sendable {
    /// The taps can start now.
    case ready
    /// Allowed, but this process still has the old answer: the taps start once Aris is reopened.
    case afterRelaunch
    /// Not allowed (Input Monitoring is asked once, after the first setup).
    case notAllowed

    /// `listenNow`: the listen check in this process. `trustedNow` and `trustedAtLaunch`: Accessibility (read live)
    /// now and when this process began.
    static func of(listenNow: Bool, trustedNow: Bool, trustedAtLaunch: Bool) -> ArisListenOutlook {
        if listenNow { return .ready }
        // Accessibility was turned on since launch: a new process gets to listen, this one doesn't.
        return trustedNow && !trustedAtLaunch ? .afterRelaunch : .notAllowed
    }

    /// Input Monitoring as the permission layer reads it: on (needing a reopen when only a new process sees it), or
    /// what macOS's own listen check said.
    func reading(listenState: ArisPermissionState) -> ArisPermissionReading {
        switch self {
        case .ready: ArisPermissionReading(state: .granted)
        case .afterRelaunch: ArisPermissionReading(state: .granted, needsRelaunch: true)
        case .notAllowed: ArisPermissionReading(state: listenState == .granted ? .notAsked : listenState)
        }
    }
}
