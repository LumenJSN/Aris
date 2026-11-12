//
//  ArisGlidePath.swift
//  Aris
//
//  The glide style's geometry, the owner's pick "스르륵" at 0.75× (mockup travel-styles.html, option G): one smooth slide
//  down a gentle invisible slope, straight from the notch to the perch. The path is a cubic Bézier with its controls
//  35% and 75% of the way across, the first a little under the higher end, the second 10 pt above the perch, so it
//  leaves the notch going down and comes onto the perch from just above. Its progress follows cubic-bezier(0.42, 0,
//  0.18, 1). It leans up to 8° forward as it speeds up and 6.4° back as it brakes, then rocks back about 1.5° and
//  settles. It turns to face the way it goes, capped at 30° (at 45° the star's eye slides off its edge). Every
//  duration of the mockup is stretched by 1 / 0.75.
//
//  A route of more legs (a gate on a shared edge, displays apart) is one curve through all of them: the same ends as G,
//  smooth through the joins, played on the one easing by distance along it, so it eases only out of the notch and onto
//  the perch. The jump between displays apart takes no time. Pure.
//

import CoreGraphics
import Foundation

enum ArisGlidePath {
    /// The owner's 0.75× speed: every duration of the mockup over this.
    static let speed = 0.75
    /// A slide takes `base + dx / pointsPerSecond` seconds at 1×, then `settle` seconds on the perch.
    static let base = 0.55
    static let pointsPerSecond: CGFloat = 650
    static let settle = 0.32 / speed
    /// The lean, in degrees: forward while it speeds up, back (at 0.8 of it) while it brakes; the rock on the perch.
    static let lean = 8.0
    static let brake = 0.8
    static let rock = 3.0
    /// Turning to face the way it goes, and back to the front at the end (the facing grid's cap).
    static let turnIn = 0.15 / speed
    static let turnOut = 0.2 / speed
    static var facing: CGFloat { ArisSpriteFacing.maxYaw }

    /// The slide's time over `legs`: each leg's width counts once, the gaps between displays not at all.
    static func slideDuration(_ legs: [ArisTravelLeg]) -> Double {
        (base + Double(legs.reduce(0) { $0 + abs($1.end.x - $1.start.x) } / pointsPerSecond)) / speed
    }

    static func duration(of leg: ArisTravelLeg) -> Double { slideDuration([leg]) }

    /// One leg's slide at `progress` (time over its duration, 0–1), as the mockup plays it; exactly its ends at 0 and 1.
    static func position(in leg: ArisTravelLeg, progress: Double) -> CGPoint {
        ArisGlideCurve([leg]).position(at: ease(progress))
    }

    /// The slide's easing.
    static func ease(_ u: Double) -> Double { ArisEase.cubic(0.42, 0, 0.18, 1, u) }

    /// The time (0–1) at which the slide eased by `ease` (G's own unless given) reaches `s`.
    static func uneased(_ s: Double, ease: (Double) -> Double = ease) -> Double {
        var lo = 0.0, hi = 1.0
        for _ in 0..<50 { let mid = (lo + hi) / 2; if ease(mid) < s { lo = mid } else { hi = mid } }
        return (lo + hi) / 2
    }

    /// G's Bézier controls for a leg (AppKit, y up; the mockup's y-down formula turned over).
    static func controls(_ leg: ArisTravelLeg) -> (CGPoint, CGPoint) {
        let low = min(leg.start.y, leg.end.y), high = max(leg.start.y, leg.end.y), dx = leg.end.x - leg.start.x
        return (CGPoint(x: leg.start.x + 0.35 * dx, y: 0.35 * low + 0.65 * high - 10), CGPoint(x: leg.start.x + 0.75 * dx, y: leg.end.y + 10))
    }

    /// The lean `u` (0–1) through the slide, in radians (counter-clockwise; forward is clockwise going right).
    static func lean(direction: Double, progress u: Double) -> CGFloat {
        let u = min(1, max(0, u))
        return CGFloat(-direction * lean * sin(2 * .pi * u) * (u < 0.5 ? 1 : brake) * .pi / 180)
    }

    /// Rocking back on the perch, `progress` through the settle.
    static func rock(direction: Double, progress: Double) -> CGFloat {
        let u = min(1, max(0, progress))
        guard u < 1 else { return 0 }
        return CGFloat(direction * rock * exp(-5 * u) * sin(3 * .pi * u) * .pi / 180)
    }

    static func direction(from: CGPoint, to: CGPoint) -> Double { to.x > from.x ? 1 : to.x < from.x ? -1 : 0 }
}

/// The glide's path over a route's legs: G's own Bézier for one leg; for more, a Bézier a leg with G's controls at the
/// two ends and a shared tangent at each join, walked by distance along it.
struct ArisGlideCurve {
    private struct Segment {
        let p0, c1, c2, p3: CGPoint
        /// Distance along the segment at evenly spaced parameters.
        let table: [CGFloat]
        var length: CGFloat { table.last ?? 0 }

        func point(_ t: CGFloat) -> CGPoint {
            let r = 1 - t
            func b(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat { r * r * r * a + 3 * r * r * t * b + 3 * r * t * t * c + t * t * t * d }
            return CGPoint(x: b(p0.x, c1.x, c2.x, p3.x), y: b(p0.y, c1.y, c2.y, p3.y))
        }

        /// The parameter at `distance` along the segment.
        func parameter(at distance: CGFloat) -> CGFloat {
            guard length > 0 else { return distance > 0 ? 1 : 0 }
            var lo = 0, hi = table.count - 1
            while hi - lo > 1 { let mid = (lo + hi) / 2; if table[mid] <= distance { lo = mid } else { hi = mid } }
            let span = table[hi] - table[lo], f = span > 0 ? (distance - table[lo]) / span : 0
            return (CGFloat(lo) + min(1, max(0, f))) / CGFloat(table.count - 1)
        }
    }

    let legs: [ArisTravelLeg]
    /// Where each leg starts, as a share of the whole path.
    let legStarts: [Double]
    private let segments: [Segment]
    private let total: CGFloat

    init(_ legs: [ArisTravelLeg]) {
        self.legs = legs
        let n = legs.count
        // The tangent through each join: the two legs' directions averaged, so the path never kinks there.
        let joins: [CGVector] = (0..<max(0, n - 1)).map { i in
            let a = legs[i], b = legs[i + 1]
            let la = max(1e-9, hypot(a.end.x - a.start.x, a.end.y - a.start.y)), lb = max(1e-9, hypot(b.end.x - b.start.x, b.end.y - b.start.y))
            let d = CGVector(dx: (a.end.x - a.start.x) / la + (b.end.x - b.start.x) / lb, dy: (a.end.y - a.start.y) / la + (b.end.y - b.start.y) / lb)
            let m = max(1e-9, hypot(d.dx, d.dy))
            return CGVector(dx: d.dx / m, dy: d.dy / m)
        }
        let segments: [Segment] = legs.enumerated().map { i, leg in
            let g = ArisGlidePath.controls(leg), length = hypot(leg.end.x - leg.start.x, leg.end.y - leg.start.y)
            let c1 = i == 0 ? g.0 : CGPoint(x: leg.start.x + joins[i - 1].dx * length / 3, y: leg.start.y + joins[i - 1].dy * length / 3)
            let c2 = i == n - 1 ? g.1 : CGPoint(x: leg.end.x - joins[i].dx * length / 3, y: leg.end.y - joins[i].dy * length / 3)
            return Self.segment(leg.start, c1, c2, leg.end)
        }
        let total = segments.reduce(0) { $0 + $1.length }
        var at: CGFloat = 0
        var starts: [Double] = []
        for segment in segments {
            starts.append(total > 0 ? Double(at / total) : 0)
            at += segment.length
        }
        self.segments = segments
        self.total = total
        legStarts = starts
    }

    /// The point `s` (0–1) of the way: G's parameter for one leg, the share of the distance for more.
    func position(at s: Double) -> CGPoint {
        guard let first = legs.first, let last = legs.last else { return .zero }
        if s <= 0 { return first.start }
        if s >= 1 { return last.end }
        if segments.count == 1 { return segments[0].point(CGFloat(s)) }
        let d = CGFloat(s) * total
        let i = legStarts.lastIndex { CGFloat($0) * total <= d } ?? 0
        let segment = segments[i]
        return segment.point(segment.parameter(at: d - CGFloat(legStarts[i]) * total))
    }

    private static func segment(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint) -> Segment {
        let probe = Segment(p0: p0, c1: c1, c2: c2, p3: p3, table: [0])
        var table: [CGFloat] = [0], last = p0
        for k in 1...128 {
            let p = probe.point(CGFloat(k) / 128)
            table.append(table[k - 1] + hypot(p.x - last.x, p.y - last.y))
            last = p
        }
        return Segment(p0: p0, c1: c1, c2: c2, p3: p3, table: table)
    }
}

/// CSS-style cubic-bezier timing curves.
enum ArisEase {
    /// The progress `cubic-bezier(x1, y1, x2, y2)` gives at time `t` (0–1).
    static func cubic(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        func f(_ u: Double, _ a: Double, _ b: Double) -> Double { 3 * a * u * (1 - u) * (1 - u) + 3 * b * u * u * (1 - u) + u * u * u }
        var lo = 0.0, hi = 1.0, u = t
        for _ in 0..<40 {
            u = (lo + hi) / 2
            if f(u, x1, x2) < t { lo = u } else { hi = u }
        }
        return f(u, y1, y2)
    }

    /// The effortful start and stop, cubic-bezier(0.45, 0, 0.55, 1).
    static func symmetric(_ t: Double) -> Double { cubic(0.45, 0, 0.55, 1, t) }
}
