//
//  ArisTravelRoute.swift
//  Aris
//
//  Where a teammate goes on its way from the notch to a window: the waypoints, apart from how it moves between them
//  (ArisTravelStyle). Pure; AppKit coordinates (y up), every point the character's centre.
//
//  `direct` is the glide's: one leg straight to the perch, on one display or over a shared edge; out over an edge and
//  in at the target's between displays apart. `legs` is the hop's route: it runs along the top of the screens, its feet
//  96 pt under the top edge (mockup 9-hop.html: a full 60-pt apex plus the 28-pt body plus 8 pt clear), to 64 pt before
//  the perch, then one leg onto it. From anywhere above the route (the notch home) the first leg is a drop onto it.
//  Side by side displays share the line under both tops and the route crosses their common edge; other displays are
//  left over the source's edge and entered at the target's facing edge, each on its own line (over the other edge when
//  another display is there, so it never pops up on a third).
//

import CoreGraphics

/// One stretch between two waypoints. How the character covers it is the style's.
struct ArisTravelLeg: Equatable {
    enum Kind: Equatable {
        /// Down onto the route from above it (out of the notch): it never rises.
        case drop
        /// Along the route (and the climb up to it from a window, and the legs over a display's edge).
        case route
        /// Onto the perch.
        case perch
    }

    let start: CGPoint
    let end: CGPoint
    let kind: Kind
}

enum ArisTravelRoute {
    /// The route's feet line, under the top edge of the screen.
    static let edgeInset: CGFloat = 96
    /// The longest step along the route.
    static let maxStep: CGFloat = 220
    /// The route ends this far before the perch, for the last leg onto it.
    static let approach: CGFloat = 64
    /// The drop out of the notch covers this share of the first step.
    static let dropShare: CGFloat = 0.45
    /// Shorter stretches aren't worth a step of their own.
    static let minStep: CGFloat = 40

    /// The centre's height on the route of `screen`.
    static func routeY(on screen: CGRect, size: CGFloat, edgeInset: CGFloat = edgeInset) -> CGFloat {
        screen.maxY - edgeInset + size / 2
    }

    /// The legs from `from` to the perch `to`; empty with no screens or nowhere to go.
    static func legs(from: CGPoint, to: CGPoint, screens: [CGRect], size: CGFloat = 28, maxStep: CGFloat = maxStep,
                     edgeInset: CGFloat = edgeInset) -> [ArisTravelLeg] {
        guard hypot(to.x - from.x, to.y - from.y) > 0.5, let source = screen(of: from, screens),
              let target = screen(of: to, screens) else { return [] }
        let dir: CGFloat = to.x >= from.x ? 1 : -1
        let step = Step(maxStep: maxStep)
        var legs: [ArisTravelLeg]
        if source == target || sharesEdge(source, target, dir: dir, size: size, edgeInset: edgeInset) {
            let line = min(routeY(on: source, size: size, edgeInset: edgeInset), routeY(on: target, size: size, edgeInset: edgeInset))
            legs = step.along(from: from, toX: approachX(from: from.x, to: to.x, dir: dir), y: line, mustReach: false)
        } else {
            let (exit, entry) = crossing(from: source, to: target, dir: dir, screens: screens, size: size, edgeInset: edgeInset)
            let out = step.along(from: from, toX: exit.x, y: exit.y, mustReach: true)
            let inY = entry.y
            let inwardDir: CGFloat = to.x >= entry.x ? 1 : -1
            let inward = step.along(from: entry, toX: approachX(from: entry.x, to: to.x, dir: inwardDir), y: inY, mustReach: false)
            // Coming in at the edge with no step to take, the leg onto the perch starts there.
            legs = out + (inward.isEmpty ? [ArisTravelLeg(start: entry, end: entry, kind: .route)] : inward)
        }
        let last = legs.last?.end ?? from
        if hypot(to.x - last.x, to.y - last.y) > 0.5 { legs.append(ArisTravelLeg(start: last, end: to, kind: .perch)) }
        return legs.filter { $0.start != $0.end }
    }

    /// The glide's waypoints: straight to the perch on one display or side by side displays (or via the shared edge,
    /// under both tops, when asked); between displays apart, out over the source's edge and in from the target's.
    static func direct(from: CGPoint, to: CGPoint, screens: [CGRect], size: CGFloat = 28, edgeInset: CGFloat = edgeInset,
                       viaSharedEdge: Bool = false) -> [ArisTravelLeg] {
        guard hypot(to.x - from.x, to.y - from.y) > 0.5, let source = screen(of: from, screens),
              let target = screen(of: to, screens) else { return [] }
        let dir: CGFloat = to.x >= from.x ? 1 : -1
        if source == target { return [ArisTravelLeg(start: from, end: to, kind: .perch)] }
        if sharesEdge(source, target, dir: dir, size: size, edgeInset: edgeInset) {
            guard viaSharedEdge else { return [ArisTravelLeg(start: from, end: to, kind: .perch)] }
            let edge = CGPoint(x: dir > 0 ? source.maxX : source.minX,
                               y: min(routeY(on: source, size: size, edgeInset: edgeInset), routeY(on: target, size: size, edgeInset: edgeInset)))
            return [ArisTravelLeg(start: from, end: edge, kind: .route), ArisTravelLeg(start: edge, end: to, kind: .perch)]
        }
        let (exit, entry) = crossing(from: source, to: target, dir: dir, screens: screens, size: size, edgeInset: edgeInset)
        return [ArisTravelLeg(start: from, end: exit, kind: .route), ArisTravelLeg(start: entry, end: to, kind: .perch)]
    }

    /// The glide's routes, in the order to try them: straight to the perch; through a gate on a top or bottom edge the
    /// two displays share (stacked, clear of `obstacles`, the camera housings); via a side edge they share; out over
    /// the source's edge and in at the target's (always last).
    static func glideCandidates(from: CGPoint, to: CGPoint, screens: [CGRect], obstacles: [CGRect] = [], size: CGFloat = 28,
                                edgeInset: CGFloat = edgeInset) -> [[ArisTravelLeg]] {
        guard hypot(to.x - from.x, to.y - from.y) > 0.5, let source = screen(of: from, screens),
              let target = screen(of: to, screens) else { return [] }
        var candidates = [[ArisTravelLeg(start: from, end: to, kind: .perch)]]
        guard source != target else { return candidates }
        if let gate = gate(from: from, to: to, source: source, target: target, obstacles: obstacles, size: size) {
            candidates.append([ArisTravelLeg(start: from, end: gate, kind: .route), ArisTravelLeg(start: gate, end: to, kind: .perch)])
        }
        let dir: CGFloat = to.x >= from.x ? 1 : -1
        if sharesEdge(source, target, dir: dir, size: size, edgeInset: edgeInset) {
            candidates.append(direct(from: from, to: to, screens: screens, size: size, edgeInset: edgeInset, viaSharedEdge: true))
        }
        let (exit, entry) = crossing(from: source, to: target, dir: dir, screens: screens, size: size, edgeInset: edgeInset)
        candidates.append([ArisTravelLeg(start: from, end: exit, kind: .route), ArisTravelLeg(start: entry, end: to, kind: .perch)])
        return candidates
    }

    /// A point on the top or bottom edge `source` and `target` share, where the straight line between the two points
    /// crosses it or the nearest place to that which leaves the character's box on both displays and clear of the
    /// housings on that edge; nil when they share no such edge.
    static func gate(from: CGPoint, to: CGPoint, source: CGRect, target: CGRect, obstacles: [CGRect], size: CGFloat) -> CGPoint? {
        let edgeY: CGFloat
        if abs(source.maxY - target.minY) <= 1 { edgeY = source.maxY } else if abs(source.minY - target.maxY) <= 1 { edgeY = source.minY } else { return nil }
        let lo = max(source.minX, target.minX) + size, hi = min(source.maxX, target.maxX) - size
        guard hi > lo else { return nil }
        // The housings on that edge, grown by half the box and a point, cut out of the span.
        let blocked = obstacles.filter { $0.minY <= edgeY + 1 && $0.maxY >= edgeY - 1 }
            .map { ($0.minX - size / 2 - 1, $0.maxX + size / 2 + 1) }.sorted { $0.0 < $1.0 }
        var free: [(CGFloat, CGFloat)] = [], start = lo
        for (a, b) in blocked where b > start {
            if a > start { free.append((start, min(a, hi))) }
            start = max(start, b)
        }
        if start < hi { free.append((start, hi)) }
        free = free.filter { $0.1 > $0.0 }
        let want = abs(to.y - from.y) > 1e-9 ? from.x + (to.x - from.x) * (edgeY - from.y) / (to.y - from.y) : (from.x + to.x) / 2
        let best = free.map { min(max(want, $0.0), $0.1) }.min { abs($0 - want) < abs($1 - want) }
        return best.map { CGPoint(x: $0, y: edgeY) }
    }

    /// Between displays apart: out over the edge toward the target and in at the target's facing edge, each on its
    /// route line, unless another display is there (the character would pop up on it): then over the other edge.
    private static func crossing(from source: CGRect, to target: CGRect, dir: CGFloat, screens: [CGRect], size: CGFloat,
                                 edgeInset: CGFloat) -> (exit: CGPoint, entry: CGPoint) {
        let outY = routeY(on: source, size: size, edgeInset: edgeInset), inY = routeY(on: target, size: size, edgeInset: edgeInset)
        func exit(_ side: CGFloat) -> CGPoint { CGPoint(x: side > 0 ? source.maxX + size : source.minX - size, y: outY) }
        func entry(_ side: CGFloat) -> CGPoint { CGPoint(x: side < 0 ? target.minX - size : target.maxX + size, y: inY) }
        return ([dir, -dir].map(exit).first { clear($0, size: size, screens: screens) } ?? exit(dir),
                [-dir, dir].map(entry).first { clear($0, size: size, screens: screens) } ?? entry(-dir))
    }

    /// The screen holding `p`, or the nearest one.
    static func screen(of p: CGPoint, _ screens: [CGRect]) -> CGRect? {
        if let inside = screens.first(where: { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }) { return inside }
        func distance(_ r: CGRect) -> CGFloat { hypot(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)) }
        return screens.min { distance($0) < distance($1) }
    }

    /// No display under a character of `size` centred on `p`.
    private static func clear(_ p: CGPoint, size: CGFloat, screens: [CGRect]) -> Bool {
        let box = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        return !screens.contains { let o = $0.intersection(box); return !o.isNull && o.width > 0 && o.height > 0 }
    }

    /// Side by side: `b` starts where `a` ends in the direction of travel, and the line under both tops is on both.
    private static func sharesEdge(_ a: CGRect, _ b: CGRect, dir: CGFloat, size: CGFloat, edgeInset: CGFloat) -> Bool {
        let gap = dir > 0 ? abs(a.maxX - b.minX) : abs(a.minX - b.maxX)
        let line = min(routeY(on: a, size: size, edgeInset: edgeInset), routeY(on: b, size: size, edgeInset: edgeInset))
        return gap <= 1 && line - size / 2 >= max(a.minY, b.minY)
    }

    /// Where the route ends: `approach` before the perch, never behind where the character starts.
    private static func approachX(from x: CGFloat, to perchX: CGFloat, dir: CGFloat) -> CGFloat {
        x + dir * max(0, dir * (perchX - x) - approach)
    }

    private struct Step {
        let maxStep: CGFloat

        /// From `p` to `x` on the line `y`: a drop first when `p` is above it, then equal steps of at most `maxStep`.
        /// A stretch under `minStep` is left out unless the leg must reach `x` (over a display's edge).
        func along(from p: CGPoint, toX x: CGFloat, y: CGFloat, mustReach: Bool) -> [ArisTravelLeg] {
            var legs: [ArisTravelLeg] = []
            var at = p
            if p.y > y + 0.5 {
                let span = x - p.x
                let dropX = abs(span) < ArisTravelRoute.minStep ? x : p.x + ArisTravelRoute.dropShare * span / count(span)
                at = CGPoint(x: dropX, y: y)
                legs.append(ArisTravelLeg(start: p, end: at, kind: .drop))
            }
            let rest = x - at.x
            guard abs(rest) >= ArisTravelRoute.minStep || (mustReach && abs(rest) > 0.5) else { return legs }
            let n = count(rest)
            let from = at
            for i in 1...Int(n) {
                let next = CGPoint(x: i == Int(n) ? x : from.x + rest * CGFloat(i) / n, y: y)
                legs.append(ArisTravelLeg(start: at, end: next, kind: .route))
                at = next
            }
            return legs
        }

        private func count(_ span: CGFloat) -> CGFloat { max(1, (abs(span) / maxStep).rounded(.up)) }
    }
}
