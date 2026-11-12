//
//  ArisGestureCapturing.swift
//  Aris
//
//  The seam between the gesture overlay (P1.7) and the capture (P1.8). The controller runs the session reducer and
//  draws; whoever conforms to `ArisGestureCapturing` hit-tests the circled window, takes the crop and keeps or drops
//  the shot. Callbacks may come back synchronously or later, always on the main actor; a late one is matched by its
//  capture id, so a reply from an old session can't land a shot (ArisGestureSession).
//
//  `ArisGestureCapture` (P1.8) is the real one. `ArisGestureLogCapture` finds no window and takes no picture: every
//  accepted circle logs and is dropped without using a badge (for headless use and the tests).
//

import CoreGraphics
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

/// Whether a turn may start a drawing session at all: the "동그라미로 가리키기" setting on, the Screen Recording grant
/// given (without it nothing appears, plan D2), and secure input off (a password field is being typed into: no overlay,
/// no frame, D4).
enum ArisGestureGate {
    static func allows(setting: Bool, permission: Bool, secureInput: Bool) -> Bool {
        setting && permission && !secureInput
    }

    /// The setting is on but the grant is missing: say so (once per launch, `ArisScreenPermissionNotice`) instead of
    /// silently doing nothing. Never under secure input.
    static func needsPermissionLine(setting: Bool, permission: Bool, secureInput: Bool) -> Bool {
        setting && !permission && !secureInput
    }
}

/// A display, by `CGDirectDisplayID`, with its Cocoa frame (global points, bottom-left origin).
struct ArisGestureScreen: Equatable {
    let id: UInt32
    let frame: CGRect
}

/// Everything a capture needs, in the circled display's top-left points.
struct ArisGestureCaptureRequest: Equatable {
    let captureId: Int
    let badge: Int
    let revision: Int
    let gesture: ArisGesture
    let screen: ArisGestureScreen
    /// The window the hit-test picked (nil: none, so the padded region is cropped).
    let hit: ArisWindowHit?
    /// Shot ink starts after this stroke time (the last kept shot's).
    let inkAfterMs: Double
    /// This display's persistent strokes so far.
    let strokes: [[ArisGesturePoint]]
    /// Hands-free frames go stale sooner (1.5 s, not 4 s).
    let handsFree: Bool
}

@MainActor
protocol ArisGestureCapturing: AnyObject {
    /// The pointer armed on a display: take its clean frame now, so a crop doesn't wait for one.
    func strokeStarted(on screen: ArisGestureScreen)
    /// Called at detection, before anything waits: snapshot the voiced time for this capture, then hit-test the
    /// gesture's five samples (plan D5) and report the circled window, or nil for none.
    func pickWindow(captureId: Int, for gesture: ArisGesture, on screen: ArisGestureScreen, handsFree: Bool,
                    done: @escaping (ArisWindowHit?) -> Void)
    /// Crops, inks and badges the shot; reports whether an image was made. Keep it until `keep`.
    func capture(_ request: ArisGestureCaptureRequest, done: @escaping (Bool) -> Void)
    func keep(captureId: Int, badge: Int)
    func drop(captureId: Int, reason: String)
    /// The front app changed or a hands-free click landed: re-take frames before the next crop.
    func markFramesStale()
    /// The session ended with a drawing: build the drawing reference from these strokes (by display) and park the
    /// result for the turn. Called before the overlays close.
    func finalize(strokes: [UInt32: [[ArisGesturePoint]]], handsFree: Bool)
    /// The session was abandoned: release every frame and pending shot.
    func abort()
}

/// P1.7's stand-in: logs and captures nothing.
@MainActor
final class ArisGestureLogCapture: ArisGestureCapturing {
    func strokeStarted(on screen: ArisGestureScreen) {}

    func pickWindow(captureId: Int, for gesture: ArisGesture, on screen: ArisGestureScreen, handsFree: Bool,
                    done: @escaping (ArisWindowHit?) -> Void) {
        done(nil)
    }

    func capture(_ request: ArisGestureCaptureRequest, done: @escaping (Bool) -> Void) {
        done(false)
    }

    func keep(captureId: Int, badge: Int) {}

    func drop(captureId: Int, reason: String) {
        log.debug("gesture capture \(captureId, privacy: .public) dropped: \(reason, privacy: .public)")
    }

    func markFramesStale() {}

    func finalize(strokes: [UInt32: [[ArisGesturePoint]]], handsFree: Bool) {
        let points = strokes.values.reduce(0) { $0 + $1.reduce(0) { $0 + $1.count } }
        log.info("gesture session ended: \(strokes.count, privacy: .public) display(s), \(points, privacy: .public) points")
    }

    func abort() {}
}
