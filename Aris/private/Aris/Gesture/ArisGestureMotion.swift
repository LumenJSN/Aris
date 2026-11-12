//
//  ArisGestureMotion.swift
//  Aris
//
//  Every timing, keyframe and placement the gesture overlay animates with, as pure functions of time, so the live
//  CAAnimations, the offscreen renders and the tests all read the same numbers:
//  - the comet fade and the seal (the owner's mockup pick B, `mockups/gesture-ink.html`);
//  - the reject shake, fade and capsule pop;
//  - the hint chip's entrance, fade and placement, and its state.
//  Each curve cites the `emil-design-eng` rule it follows. Pure, so the tests run it.
//

import CoreGraphics
import Foundation

/// A CSS `cubic-bezier(x1, y1, x2, y2)` timing curve, solved for y at a given x (progress in 0…1).
struct ArisCubicBezier: Equatable {
    let x1, y1, x2, y2: CGFloat

    init(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    func y(atX x: CGFloat) -> CGFloat {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // x(t) is monotonic for 0 ≤ x1, x2 ≤ 1: bisect it.
        var lo: CGFloat = 0, hi: CGFloat = 1, t = x
        for _ in 0..<48 {
            let xt = Self.sample(t, x1, x2)
            if abs(xt - x) < 1e-7 { break }
            if xt < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return Self.sample(t, y1, y2)
    }

    private static func sample(_ t: CGFloat, _ p1: CGFloat, _ p2: CGFloat) -> CGFloat {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }
}

enum ArisGestureMotion {
    private typealias Ink = ArisGestureConstants.Ink
    private typealias Shot = ArisGestureConstants.Shot

    /// Opacity, scale and vertical offset (pt, down) of a piece of chrome at one moment.
    struct Pose: Equatable {
        var opacity: CGFloat
        var scale: CGFloat
        var dy: CGFloat
    }

    // MARK: - Comet and seal

    /// The seal (mockup E): when a loop is accepted, it is drawn closed and fades out over 600 ms.
    static let sealLifeMs = 600.0
    static let sealPeak: CGFloat = 0.85

    /// `0.85 · (1 − age/600)²`, nil once over. The square front-loads the fade, an ease-out on the way out
    /// (emil-design-eng: "exiting → ease-out").
    /// A seal whose capture failed is withdrawn over 150 ms (emil-design-eng: exits are quick, ease-out-ish linear
    /// fade on top of the seal's own curve).
    static let sealWithdrawMs = 150.0

    /// 1 → 0 over `sealWithdrawMs` from the moment the seal was withdrawn.
    static func sealWithdrawal(sinceMs: Double) -> CGFloat {
        CGFloat(min(1, max(0, 1 - sinceMs / sealWithdrawMs)))
    }

    static func sealStrength(ageMs: Double) -> CGFloat? {
        guard ageMs < sealLifeMs else { return nil }
        let k = CGFloat(1 - max(0, ageMs) / sealLifeMs)
        return sealPeak * k * k
    }

    // MARK: - Reject (8/8 and private windows)

    /// The reject shake: 380 ms, cubic-bezier(0.36,0.07,0.19,0.97) per keyframe. A shake is on-screen
    /// movement, so it eases in and out (emil-design-eng: "moving on screen → ease-in-out").
    static let shakeDurationMs = Shot.rejectShakeMs
    static let shakeValues: [CGFloat] = [0, -9, 8, -6, 5, -3, 2, 0]
    static let shakeKeyTimes: [CGFloat] = [0, 0.12, 0.28, 0.44, 0.60, 0.76, 0.90, 1]
    static let shakeCurve = ArisCubicBezier(0.36, 0.07, 0.19, 0.97)

    static func shakeOffset(atMs t: Double) -> CGFloat {
        guard t > 0, t < shakeDurationMs else { return 0 }
        return keyframe(shakeValues, at: CGFloat(t / shakeDurationMs), times: shakeKeyTimes, curve: shakeCurve)
    }

    /// The red loop and its capsule hold until 850 ms, then fade over 0.4 s with CSS `ease` and are removed at
    /// 1250 ms. A fade is a colour change (emil-design-eng: "hover/colour change → ease").
    static let rejectFadeAtMs = Shot.rejectFadeMs
    static let rejectFadeDurationMs = 400.0
    static let rejectRemoveAtMs = Shot.rejectRemoveMs
    static let fadeCurve = ArisCubicBezier(0.25, 0.1, 0.25, 1)

    static func rejectOpacity(atMs t: Double) -> CGFloat {
        if t <= rejectFadeAtMs { return 1 }
        if t >= rejectRemoveAtMs { return 0 }
        let u = CGFloat((t - rejectFadeAtMs) / rejectFadeDurationMs)
        return max(0, 1 - fadeCurve.y(atX: u))
    }

    static func rejectRemoved(atMs t: Double) -> Bool { t >= rejectRemoveAtMs }

    /// The capsule's pop: 260 ms cubic-bezier(0.34,1.56,0.64,1), from opacity 0 / y +5 / scale 0.7 to 1.06 at
    /// 64 %, then rest. Entering, so it eases out, with a small overshoot (emil-design-eng: "never
    /// animate from scale(0)", "keep bounce subtle").
    static let capsulePopMs = 260.0
    static let capsuleCurve = ArisCubicBezier(0.34, 1.56, 0.64, 1)
    static let capsuleKeyTimes: [CGFloat] = [0, 0.64, 1]
    static let capsulePoses = [Pose(opacity: 0, scale: 0.7, dy: 5), Pose(opacity: 1, scale: 1.06, dy: 0),
                               Pose(opacity: 1, scale: 1, dy: 0)]

    static func capsulePop(atMs t: Double) -> Pose {
        if t <= 0 { return capsulePoses[0] }
        if t >= capsulePopMs { return capsulePoses[capsulePoses.count - 1] }
        let u = CGFloat(t / capsulePopMs)
        return Pose(opacity: min(1, max(0, keyframe(capsulePoses.map(\.opacity), at: u, times: capsuleKeyTimes, curve: capsuleCurve))),
                    scale: keyframe(capsulePoses.map(\.scale), at: u, times: capsuleKeyTimes, curve: capsuleCurve),
                    dy: keyframe(capsulePoses.map(\.dy), at: u, times: capsuleKeyTimes, curve: capsuleCurve))
    }

    // MARK: - Hint chip

    /// The hint's entrance: 0.22 s CSS `ease-out`, opacity 0 → 1 and a 3 pt rise. Entering → ease-out, under
    /// 300 ms (emil-design-eng).
    static let hintEntranceMs = 220.0
    static let hintRise: CGFloat = 3
    static let hintCurve = ArisCubicBezier(0, 0, 0.58, 1)
    /// The 220 pt travel fade: 150 ms ease-out, quicker than the entrance
    /// (emil-design-eng: "make exit faster than enter").
    static let hintFadeOutMs = 150.0

    static func hintEntrance(atMs t: Double) -> Pose {
        if t <= 0 { return Pose(opacity: 0, scale: 1, dy: hintRise) }
        if t >= hintEntranceMs { return Pose(opacity: 1, scale: 1, dy: 0) }
        let e = hintCurve.y(atX: CGFloat(t / hintEntranceMs))
        return Pose(opacity: e, scale: 1, dy: hintRise * (1 - e))
    }

    struct HintWindow: Equatable {
        let frame: CGRect
        let flippedX: Bool
        let flippedY: Bool
    }

    /// The 280×48 hint window at (+18, +20) from the cursor, flipping left (or up) when it would cross the display's
    /// right (or bottom) edge minus 8. Display-local points, top-left origin.
    static func hintWindow(cursor: CGPoint, display: CGSize) -> HintWindow {
        let size = Ink.hintSize, offset = Ink.hintOffset, edge: CGFloat = 8
        let flipX = cursor.x + offset.width + size.width > display.width - edge
        let flipY = cursor.y + offset.height + size.height > display.height - edge
        let x = flipX ? cursor.x - offset.width - size.width : cursor.x + offset.width
        let y = flipY ? cursor.y - offset.height - size.height : cursor.y + offset.height
        return HintWindow(frame: CGRect(x: x, y: y, width: size.width, height: size.height), flippedX: flipX, flippedY: flipY)
    }

    /// A chip window of `size` at (+18, +20) from the cursor, flipping left or up at the display edge − 8, then kept
    /// on the display (the permission line, which is wider than the hint's 280 pt window).
    static func chipFrame(cursor: CGPoint, size: CGSize, display: CGSize) -> CGRect {
        let offset = Ink.hintOffset, edge: CGFloat = 8
        var x = cursor.x + offset.width + size.width > display.width - edge ? cursor.x - offset.width - size.width : cursor.x + offset.width
        var y = cursor.y + offset.height + size.height > display.height - edge ? cursor.y - offset.height - size.height : cursor.y + offset.height
        x = min(max(x, edge), max(edge, display.width - edge - size.width))
        y = min(max(y, edge), max(edge, display.height - edge - size.height))
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Where the chip sits inside its window: the corner nearest the cursor.
    static func hintChipOrigin(chip: CGSize, in window: HintWindow) -> CGPoint {
        CGPoint(x: window.flippedX ? window.frame.width - chip.width : 0,
                y: window.flippedY ? window.frame.height - chip.height : 0)
    }

    // MARK: - Reject capsule placement

    /// 10 pt above the loop, or 10 pt below it when the loop padded by 26 pt would start within 48 pt of the top;
    /// centred on the loop and kept 8 pt inside the viewport. Top-left points.
    static func capsuleFrame(loop: CGRect, capsule: CGSize, viewport: CGSize) -> CGRect {
        let gap: CGFloat = 10, edge: CGFloat = 8, topRoom: CGFloat = 48
        let below = loop.minY - Shot.rejectPad < topRoom
        let y = below ? loop.maxY + gap : loop.minY - gap - capsule.height
        let x = min(max(loop.midX - capsule.width / 2, edge), viewport.width - edge - capsule.width)
        return CGRect(x: x, y: y, width: capsule.width, height: capsule.height)
    }

    // MARK: - Helpers

    /// CSS keyframes: the timing curve applies to each segment between keyframes.
    private static func keyframe(_ values: [CGFloat], at u: CGFloat, times: [CGFloat], curve: ArisCubicBezier) -> CGFloat {
        guard let last = values.last else { return 0 }
        for i in 1..<times.count where u <= times[i] {
            let span = times[i] - times[i - 1]
            let local = span > 0 ? (u - times[i - 1]) / span : 1
            return values[i - 1] + (values[i] - values[i - 1]) * curve.y(atX: local)
        }
        return last
    }
}

/// The hint chip "동그라미로 가리키세요" through one session: shown once at commit, it follows the cursor; it
/// fades for good after 220 pt of travel, hides instantly (and for good) on the first stroke so it never lands in a
/// capture, and hides while the cursor is on another display.
struct ArisGestureHintState {
    enum Phase: Equatable { case waiting, shown, away, gone }
    enum Action: Equatable { case none, follow, hideInstantly, fadeOut }

    private(set) var phase: Phase = .waiting
    private(set) var shownAtMs: Double?
    private(set) var travel: CGFloat = 0
    private var last: CGPoint?

    /// Shows the chip, once per session. False if it already showed, or a stroke came first.
    mutating func show(at p: CGPoint, now: Double) -> Bool {
        guard phase == .waiting else { return false }
        phase = .shown
        shownAtMs = now
        last = p
        travel = 0
        return true
    }

    mutating func moved(to p: CGPoint) -> Action {
        guard phase == .shown, let previous = last else { return .none }
        travel += hypot(p.x - previous.x, p.y - previous.y)
        last = p
        guard travel < ArisGestureConstants.Ink.tagFadeTravel else {
            phase = .gone
            return .fadeOut
        }
        return .follow
    }

    mutating func firstStroke() -> Action {
        let visible = phase == .shown
        phase = .gone
        return visible ? .hideInstantly : .none
    }

    mutating func leftDisplay() -> Action {
        guard phase == .shown else { return .none }
        phase = .away
        return .hideInstantly
    }

    mutating func returned(at p: CGPoint) -> Action {
        guard phase == .away else { return .none }
        phase = .shown
        last = p
        return .follow
    }
}
