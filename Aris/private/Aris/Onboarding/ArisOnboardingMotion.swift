//
//  ArisOnboardingMotion.swift
//  Aris
//
//  The onboarding's motion primitives (mockups/onboarding2/js/motion.js): every curve the story uses, named, so the
//  timings in ArisOnboardingScore read like a score. Pure, so the tests check the numbers.
//

import CoreGraphics
import Foundation

enum ArisOnboardingMotion {
    static func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(b, max(a, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    /// Progress of `t` through [a, b], clamped.
    static func span(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
    static func span(_ t: Double, _ range: ClosedRange<Double>) -> Double { span(t, range.lowerBound, range.upperBound) }

    /// CSS cubic-bezier(x1, y1, x2, y2), solved by Newton then bisection, as motion.js does.
    struct Bezier: Sendable {
        let x1, y1, x2, y2: Double

        init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
        }

        func callAsFunction(_ x: Double) -> Double {
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
            let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
            func sx(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
            func sy(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
            func dx(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }
            var t = x
            for _ in 0..<6 {
                let e = sx(t) - x, d = dx(t)
                if abs(e) < 1e-5 { return sy(t) }
                if abs(d) < 1e-6 { break }
                t -= e / d
            }
            var lo = 0.0, hi = 1.0
            t = x
            for _ in 0..<20 {
                let v = sx(t)
                if abs(v - x) < 1e-5 { break }
                if v < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
            return sy(t)
        }
    }

    /// Veil, ambient fades.
    static func sineInOut(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * clamp(x)) }
    /// Captions / CTA in: fast start, long settle (Framer's house ease).
    static let settle = Bezier(0.22, 1, 0.36, 1)
    /// On-screen travel (the lockup's drift), symmetric in-out.
    static let move = Bezier(0.65, 0, 0.35, 1)
    /// Sunrise → mark: slow start, decisive middle, soft landing.
    static let condense = Bezier(0.7, 0, 0.18, 1)
    /// The sunrise's climb.
    static let rise = Bezier(0.25, 0.1, 0.25, 1)
    /// Rack focus: stays soft, then snaps sharp late.
    static let focus = Bezier(0.83, 0, 0.17, 1)
    /// The flight: released from the squash, decelerating into the notch.
    static let launch = Bezier(0.3, 0.15, 0.2, 1)
    /// The anticipation's pull-back.
    static let squash = Bezier(0.45, 0, 0.55, 1)
    /// Quick exits (200 ms fades of the intro's layers).
    static let exit = Bezier(0.55, 0, 1, 0.45)
    /// The veil lifting at the handoff (symmetric in-out).
    static let veilLift = Bezier(0.65, 0, 0.35, 1)
    /// Notch open 280 ms / close 200 ms.
    static let notchOpen = Bezier(0.2, 0.8, 0.2, 1)
    static let notchClose = Bezier(0.45, 0, 0.55, 1)

    /// A point and tangent on a cubic Bézier (the flight's path).
    static func bez2d(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double)
        -> (x: Double, y: Double, dx: Double, dy: Double) {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
        let dx = 3 * u * u * (p1.x - p0.x) + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (p3.x - p2.x)
        let dy = 3 * u * u * (p1.y - p0.y) + 6 * u * t * (p2.y - p1.y) + 3 * t * t * (p3.y - p2.y)
        return (x, y, dx, dy)
    }

    /// Impact wobble: a damped sine (squash first, one overshoot, settled in ~420 ms with the landing's numbers).
    static func wobble(_ dtMs: Double, amp: Double = 0.22, tau: Double = 120, period: Double = 300) -> Double {
        guard dtMs >= 0 else { return 0 }
        return amp * exp(-dtMs / tau) * sin(2 * Double.pi * dtMs / period)
    }
}
