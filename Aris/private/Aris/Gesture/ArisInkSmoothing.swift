//
//  ArisInkSmoothing.swift
//  Aris
//
//  The ink's clean line (the owner's pick E, mockups/ink-styles.html "다듬기 알고리즘"), pure so the tests run it:
//  1. a point within 1.5 pt of the last kept one is dropped;
//  2. a One Euro filter per axis (minCutoff 1.5 Hz, β 0.05, dCutoff 2 Hz), afresh each stroke: slow strokes lose
//     their shake, and the head stays within a few points of the pointer (1.2 Hz, β 0.015, 1 Hz trailed it by 8 pt
//     on average and 15 at most);
//  3. a centripetal Catmull-Rom (α 0.5) between the filtered points, resampled every 3 pt along the arc; live, a
//     segment is resampled once and never again (Stroke);
//  4. a ribbon of quads and round joins, all wound the same way, so filling it once covers every pixel once: alpha
//     goes on once and a stroke crossing itself never darkens into a bead;
//  5. the width tapers with age, (1 − age/life)^0.8, and over the head's last 10 pt to 0.6.
//

import CoreGraphics
import Foundation

enum ArisInkSmoothing {
    static let minDistance: CGFloat = 1.5
    static let resampleStep: CGFloat = 3
    /// How finely the curve is walked to find each 3 pt mark.
    static let walkStep: CGFloat = 0.25
    /// The head narrows over this much of the stroke behind it, to this share of the width.
    static let headTaperLength: CGFloat = 10
    static let headWidthShare: CGFloat = 0.6
    static let tailExponent = 0.8

    // MARK: - 1. Dropping near points

    static func dedupe(_ points: [ArisGesturePoint]) -> [ArisGesturePoint] {
        var out: [ArisGesturePoint] = []
        for p in points {
            if let last = out.last, hypot(p.x - last.x, p.y - last.y) < minDistance { continue }
            out.append(p)
        }
        return out
    }

    // MARK: - 2. One Euro

    /// Casiez et al. 2012, per axis, on milliseconds. The first point of a stroke passes unchanged.
    struct OneEuro {
        static let minCutoff = 1.5
        static let beta = 0.05
        static let dCutoff = 2.0

        private var last: ArisGesturePoint?
        private var dx = 0.0, dy = 0.0

        mutating func reset() {
            last = nil
            dx = 0
            dy = 0
        }

        mutating func filter(_ p: ArisGesturePoint) -> ArisGesturePoint {
            guard let prev = last else {
                last = p
                return p
            }
            let dt = max(1e-3, (p.t - prev.t) / 1000)
            let ad = Self.alpha(cutoff: Self.dCutoff, dt: dt)
            dx += ad * (Double(p.x - prev.x) / dt - dx)
            dy += ad * (Double(p.y - prev.y) / dt - dy)
            let a = CGFloat(Self.alpha(cutoff: Self.minCutoff + Self.beta * hypot(dx, dy), dt: dt))
            let out = ArisGesturePoint(x: prev.x + a * (p.x - prev.x), y: prev.y + a * (p.y - prev.y), t: p.t)
            last = out
            return out
        }

        private static func alpha(cutoff: Double, dt: Double) -> Double {
            let tau = 1 / (2 * Double.pi * cutoff)
            return 1 / (1 + tau / dt)
        }
    }

    static func oneEuro(_ points: [ArisGesturePoint]) -> [ArisGesturePoint] {
        var filter = OneEuro()
        return points.map { filter.filter($0) }
    }

    /// The live stroke, as points arrive. Steps 1 and 2 on each point, then step 3 a segment at a time: a Catmull-Rom
    /// segment is resampled into `committed` once the point after it is known (its shape can't change after that), with
    /// the 3 pt spacing carried on, so nothing already drawn ever moves (the owner, 2026-11-04: "약간 가다가 꺾여"; the whole
    /// curve used to be rebuilt every frame, its last segment bending as each point came and its samples sliding as old
    /// points went). Only `tail`, the open last segment up to the newest point, is redrawn each frame. `reset` starts a
    /// new stroke.
    struct Stroke {
        /// Two samples closer in time than this are one pump tick heard twice (ticks bunch when the main thread is
        /// busy): the second would read as a speed spike and snap the filter, a kink in the line.
        static let minInterval = 2.5

        private var lastRaw: ArisGesturePoint?
        private var euro = OneEuro()
        /// The filtered points not yet wholly committed: the one before the open segments, then the open ones.
        private(set) var points: [ArisGesturePoint] = []
        /// Where in `points` the next segment to commit starts (0 or 1).
        private var next = 0
        /// The curve drawn so far that never changes again, oldest first.
        private(set) var committed: [ArisGesturePoint] = []
        /// Arc length since the last committed sample.
        private var carry: CGFloat = 0

        mutating func add(_ p: ArisGesturePoint) {
            if let last = lastRaw {
                if hypot(p.x - last.x, p.y - last.y) < ArisInkSmoothing.minDistance { return }
                if p.t - last.t < Self.minInterval { return }
            }
            lastRaw = p
            points.append(euro.filter(p))
            if points.count == 1, committed.isEmpty { committed = [points[0]] }
            // A segment is settled once the point after its end is known.
            while next + 2 < points.count {
                let p0 = points[max(0, next - 1)], p1 = points[next], p2 = points[next + 1], p3 = points[next + 2]
                ArisInkSmoothing.walk(p0, p1, p2, p3, carry: &carry) { committed.append($0) }
                next += 1
                // Only the point before the next segment is still needed behind it.
                if next > 1 {
                    points.removeFirst(next - 1)
                    next = 1
                }
            }
        }

        /// The open part: from the last committed sample through the last segment (its far end continued straight
        /// on, as the next segment will most likely go) to the newest point. Redrawn each frame; short.
        var tail: [ArisGesturePoint] {
            guard points.count >= 2, let head = points.last else { return [] }
            var out: [ArisGesturePoint] = []
            var carry = self.carry
            for i in next..<(points.count - 1) {
                let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1]
                let p3 = i + 2 < points.count ? points[i + 2]
                    : ArisGesturePoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y, t: p2.t)
                ArisInkSmoothing.walk(p0, p1, p2, p3, carry: &carry) { out.append($0) }
            }
            // A sample within a point of the head would leave a stub: the head takes its place.
            if let last = out.last, hypot(last.x - head.x, last.y - head.y) < 1 { out.removeLast() }
            return out + [head]
        }

        /// The whole curve to draw: what's settled, then the tail.
        var curve: [ArisGesturePoint] {
            let open = tail
            guard let first = open.first, let last = committed.last, first == last else { return committed + open }
            return committed + open.dropFirst()
        }

        /// Drops committed samples older than `t`, keeping one before it so the curve still reaches the window's edge.
        mutating func prune(before t: Double) {
            guard let keep = committed.lastIndex(where: { $0.t < t }), keep > 0 else { return }
            committed.removeFirst(keep)
        }

        mutating func reset() {
            lastRaw = nil
            euro.reset()
            points.removeAll()
            committed.removeAll()
            next = 0
            carry = 0
        }
    }

    // MARK: - 3. Centripetal Catmull-Rom

    /// The curve through `points`, sampled every `step` pt of arc (and the last point); each sample keeps its time.
    static func catmullRom(_ points: [ArisGesturePoint], step: CGFloat = resampleStep) -> [ArisGesturePoint] {
        guard points.count >= 2, let lastPoint = points.last else { return points }
        var out = [points[0]]
        var carry: CGFloat = 0
        for i in 0..<(points.count - 1) {
            let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
            walk(p0, p1, p2, p3, step: step, carry: &carry) { out.append($0) }
        }
        if out.last != lastPoint {
            // A sample within a point of the end would leave a stub: the end takes its place.
            if let tail = out.last, out.count > 1, hypot(tail.x - lastPoint.x, tail.y - lastPoint.y) < 1 { out.removeLast() }
            out.append(lastPoint)
        }
        return out
    }

    /// The segment p1→p2 (p0 and p3 its neighbours), walked in quarter-point steps so a sample lands within a step of
    /// every `step` pt of arc; `carry` is the arc since the last sample, carried from segment to segment.
    static func walk(_ p0: ArisGesturePoint, _ p1: ArisGesturePoint, _ p2: ArisGesturePoint, _ p3: ArisGesturePoint,
                     step: CGFloat = resampleStep, carry: inout CGFloat, emit: (ArisGesturePoint) -> Void) {
        let t0 = 0.0, t1 = t0 + knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3)
        let n = max(1, Int((hypot(p2.x - p1.x, p2.y - p1.y) / Self.walkStep).rounded(.up)))
        var prev = CGPoint(x: p1.x, y: p1.y)
        for k in 1...n {
            let f = Double(k) / Double(n)
            let c = point(p0, p1, p2, p3, t0: t0, t1: t1, t2: t2, t3: t3, at: t1 + (t2 - t1) * f)
            carry += hypot(c.x - prev.x, c.y - prev.y)
            prev = c
            if carry >= step {
                emit(ArisGesturePoint(x: c.x, y: c.y, t: p1.t + (p2.t - p1.t) * f))
                carry = 0
            }
        }
    }

    private static func knot(_ a: ArisGesturePoint, _ b: ArisGesturePoint) -> Double {
        pow(max(1e-4, Double(hypot(b.x - a.x, b.y - a.y))), 0.5)
    }

    private static func point(_ p0: ArisGesturePoint, _ p1: ArisGesturePoint, _ p2: ArisGesturePoint, _ p3: ArisGesturePoint,
                              t0: Double, t1: Double, t2: Double, t3: Double, at t: Double) -> CGPoint {
        func lerp(_ a: CGPoint, _ b: CGPoint, _ ta: Double, _ tb: Double) -> CGPoint {
            let u = CGFloat((t - ta) / (tb - ta))
            return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
        }
        let q0 = CGPoint(x: p0.x, y: p0.y), q1 = CGPoint(x: p1.x, y: p1.y), q2 = CGPoint(x: p2.x, y: p2.y), q3 = CGPoint(x: p3.x, y: p3.y)
        let a1 = lerp(q0, q1, t0, t1), a2 = lerp(q1, q2, t1, t2), a3 = lerp(q2, q3, t2, t3)
        let b1 = lerp(a1, a2, t0, t2), b2 = lerp(a2, a3, t1, t3)
        return lerp(b1, b2, t1, t2)
    }

    /// Steps 1–3 on a whole stroke.
    static func smooth(_ points: [ArisGesturePoint]) -> [ArisGesturePoint] {
        catmullRom(oneEuro(dedupe(points)))
    }

    // MARK: - Loops

    /// One lap of a loop: cut where it comes back nearest its start in its last third, so a closed seam never
    /// doubles up.
    static func oneLap(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 12, let start = points.first else { return points }
        var best = points.count - 1, bestDistance = CGFloat.greatestFiniteMagnitude
        for i in (points.count * 2 / 3)..<points.count {
            let d = hypot(points[i].x - start.x, points[i].y - start.y)
            if d < bestDistance { bestDistance = d; best = i }
        }
        return Array(points[...best])
    }

    // MARK: - 4–5. The ribbon

    /// Width at a point: `base` × (1 − age/life)^0.8 × (0.6 + 0.4·smoothstep(0, 10 pt, distance from the head)).
    static func taper(ageMs: Double, lifeMs: Double, head: CGFloat, base: CGFloat) -> CGFloat {
        let tail = pow(max(0, 1 - ageMs / lifeMs), tailExponent)
        let u = min(1, max(0, head / headTaperLength))
        let headShare = headWidthShare + (1 - headWidthShare) * u * u * (3 - 2 * u)
        return base * CGFloat(tail) * headShare
    }

    /// Each point's distance back from the last (the head), along the stroke.
    static func headDistances(_ points: [CGPoint]) -> [CGFloat] {
        var out = Array(repeating: CGFloat(0), count: points.count)
        guard points.count > 1 else { return out }
        for i in stride(from: points.count - 2, through: 0, by: -1) {
            out[i] = out[i + 1] + hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return out
    }

    /// The ribbon as one shape to fill with the non-zero rule: a round join at each point and a quad between
    /// neighbours, every piece wound clockwise (in the path's own space), so overlaps add up and never cancel.
    static func ribbonPath(_ points: [CGPoint], widths: [CGFloat], closed: Bool) -> CGPath {
        let path = CGMutablePath()
        let n = min(points.count, widths.count)
        func radius(_ i: Int) -> CGFloat { max(0, widths[i] / 2) }
        func quad(_ i: Int, _ j: Int) {
            let a = points[i], b = points[j], ra = radius(i), rb = radius(j)
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 1e-3, ra + rb > 0.05 else { return }
            let nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length
            path.addLines(between: [CGPoint(x: a.x + nx * ra, y: a.y + ny * ra), CGPoint(x: b.x + nx * rb, y: b.y + ny * rb),
                                    CGPoint(x: b.x - nx * rb, y: b.y - ny * rb), CGPoint(x: a.x - nx * ra, y: a.y - ny * ra)])
            path.closeSubpath()
        }
        for i in 0..<n {
            let r = radius(i)
            if r > 0.05 {
                path.move(to: CGPoint(x: points[i].x + r, y: points[i].y))
                path.addArc(center: points[i], radius: r, startAngle: 0, endAngle: -2 * .pi, clockwise: true)
                path.closeSubpath()
            }
            if i < n - 1 { quad(i, i + 1) }
        }
        if closed, n > 2 { quad(n - 1, 0) }
        return path
    }
}
