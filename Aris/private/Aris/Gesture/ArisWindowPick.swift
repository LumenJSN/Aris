//
//  ArisWindowPick.swift
//  Aris
//
//  Picking windows to ask about (the owner's ①B, mockups/new-features.html §1): while the talk key is held, or in the
//  circle mode (⌥⇧ held or hands-free), a click on a window picks it and a second click lets it go. A picked window
//  gets a light yellow wash over the whole of it in ink E's yellow: one sweep from the left, then still (no numbers,
//  nothing blinks). The picked windows go with the question as numbered shots (`[img N]` chips), each captured on its
//  own, so nothing else on the screen is sent. A private app's window (or one whose owner is unknown) is refused with
//  the red refusal; the cap is 8 shots, circles included. While picking is on, an overlay takes the clicks, and
//  Aris's own windows stay out of every shot. Pure, so the tests run it; ArisWindowPicker runs it on screen.
//

import CoreGraphics
import Foundation

enum ArisWindowPick {
    /// The shot cap, shared with the circles.
    static let maxShots = ArisGestureSession.maxShots

    /// Whether clicks pick windows now. The talk key picks only while held past the commit window (a tap is
    /// hands-free voice, and clicks reach the apps); the circle mode picks held and hands-free.
    static func arms(gestureKey: Bool, committed: Bool, handsFree: Bool) -> Bool {
        guard committed else { return false }
        return gestureKey || !handsFree
    }

    /// Whether a turn may pick at all: the same gate as circling (the setting, the grant, no secure input).
    static func listens(setting: Bool, permission: Bool, secureInput: Bool) -> Bool {
        ArisGestureGate.allows(setting: setting, permission: permission, secureInput: secureInput)
    }

    /// At capture the window's owner is checked again: never Aris, a private app or an owner with no bundle id.
    static func mayCapture(bundleId: String?, pid: Int32, ownPid: Int32, ownBundleId: String) -> Bool {
        guard let bundleId, !bundleId.isEmpty else { return false }
        return ArisCaptureRules.fallbackKeeps(bundleId: bundleId, pid: pid, ownPid: ownPid, ownBundleId: ownBundleId)
    }
}

/// The picked windows, in the order they were picked.
struct ArisWindowPickState {
    struct Pick: Equatable {
        let hit: ArisWindowHit
        /// Voiced time at the click, for the `[img N]` marker.
        let voicedMs: Double
        let at: Double
        let display: UInt32
    }

    enum Outcome: Equatable {
        case added(Pick)
        case removed(ArisWindowHit)
        /// A private window (or an unknown owner): the red refusal, nothing captured.
        case refused(ArisWindowHit)
        /// Over the cap: the 8/8 capsule.
        case full(ArisWindowHit)
        case ignored
    }

    private(set) var picks: [Pick] = []
    private(set) var armed = false

    var ids: [UInt32] { picks.map(\.hit.id) }

    mutating func arm() { armed = true }
    /// Clicks do nothing any more; the picks stay for the turn.
    mutating func disarm() { armed = false }
    mutating func reset() {
        picks = []
        armed = false
    }

    /// A click on `hit` (nil: the desktop). `otherShots` is how many circled shots the turn holds.
    mutating func toggle(_ hit: ArisWindowHit?, otherShots: Int, voicedMs: Double, at: Double, display: UInt32) -> Outcome {
        guard armed, let hit else { return .ignored }
        if let i = picks.firstIndex(where: { $0.hit.id == hit.id }) {
            picks.remove(at: i)
            return .removed(hit)
        }
        if ArisGestureSession.refuses(hit) || hit.bundleId == nil { return .refused(hit) }
        guard picks.count + max(0, otherShots) < ArisWindowPick.maxShots else { return .full(hit) }
        let pick = Pick(hit: hit, voicedMs: voicedMs, at: at, display: display)
        picks.append(pick)
        return .added(pick)
    }

    /// Its capture failed: the pick goes. False when it wasn't picked.
    mutating func drop(window id: UInt32) -> Bool {
        guard let i = picks.firstIndex(where: { $0.hit.id == id }) else { return false }
        picks.remove(at: i)
        return true
    }
}

enum ArisWindowPickGeometry {
    /// Cocoa global (bottom-left, `NSEvent.mouseLocation`) → Quartz global (top-left, the window list's space).
    static func quartz(_ cocoa: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)
    }

    /// A display's Cocoa frame as Quartz global bounds.
    static func quartzBounds(ofCocoa frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// A window's Quartz frame in a display's top-left panel points, or nil when it isn't on that display. Not
    /// clipped, so the wash's corners stay the window's.
    static func local(_ window: CGRect, display: CGRect) -> CGRect? {
        guard window.intersects(display) else { return nil }
        return window.offsetBy(dx: -display.minX, dy: -display.minY)
    }
}

/// Option B's look and motion (mockup `.hlB`, `.win.hov::after`).
enum ArisWindowPickWash {
    static let color = ArisInkRenderer.markerColor
    static let fillAlpha: CGFloat = 0.13
    static let ringAlpha: CGFloat = ArisGestureConstants.Ink.markerAlpha
    static let ringWidth: CGFloat = 2
    static let hoverAlpha: CGFloat = 0.28
    static let hoverWidth: CGFloat = 1.5
    /// The sweep: clip-path from the left, 340 ms, (.23,1,.32,1).
    static let sweepMs = 340.0
    static let sweepCurve = ArisCubicBezier(0.23, 1, 0.32, 1)
    /// A let-go wash: opacity over 180 ms, `ease`.
    static let fadeMs = 180.0
    /// The hover ring: 160 ms, `ease`.
    static let hoverMs = 160.0
    static let ease = ArisCubicBezier(0.25, 0.1, 0.25, 1)

    /// macOS 26 rounds windows more.
    static func cornerRadius(macOSMajor: Int) -> CGFloat { macOSMajor >= 26 ? 16 : 10 }

    /// How much of the wash is drawn, from the left (0…1).
    static func reveal(ageMs: Double) -> CGFloat {
        sweepCurve.y(atX: CGFloat(max(0, ageMs) / sweepMs))
    }

    static func settled(ageMs: Double) -> Bool { ageMs >= sweepMs }

    /// A let-go wash's opacity factor (1 → 0).
    static func fade(sinceMs: Double) -> CGFloat {
        1 - ease.y(atX: CGFloat(max(0, sinceMs) / fadeMs))
    }

    /// The hover ring's opacity factor, coming (`on`) or going.
    static func hover(sinceMs: Double, on: Bool) -> CGFloat {
        let k = ease.y(atX: CGFloat(max(0, sinceMs) / hoverMs))
        return on ? k : 1 - k
    }
}

/// The picks into the turn's drawing.
enum ArisWindowPickMerge {
    /// Numbers for `count` picks: the smallest of 1…max no circle has, in pick order; only as many as fit.
    static func badges(taken: Set<Int>, count: Int, max: Int = ArisWindowPick.maxShots) -> [Int] {
        Array((1...max).filter { !taken.contains($0) }.prefix(Swift.max(0, count)))
    }

    /// The turn's drawing with the picked windows (already numbered with `badges`). Circles keep their numbers and
    /// references; with picks and no circled shot the screen's drawing reference is dropped, so only the picked
    /// windows go. 8 shots at most. Nil when nothing is left.
    static func merge(_ result: ArisGestureResult?, picks: [ArisGestureShot],
                      speech: (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)?) -> ArisGestureResult? {
        guard !picks.isEmpty else { return result }
        let circles = result?.shots ?? []
        let room = Swift.max(0, ArisWindowPick.maxShots - circles.count)
        let shots = circles + picks.prefix(room)
        let references = circles.isEmpty ? [] : result?.references ?? []
        guard !shots.isEmpty else { return nil }
        return ArisGestureResult(shots: shots, references: references, speech: result?.speech ?? speech,
                                 handsFree: result?.handsFree ?? false)
    }
}
