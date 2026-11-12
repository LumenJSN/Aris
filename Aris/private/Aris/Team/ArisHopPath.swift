//
//  ArisHopPath.swift
//  Aris
//
//  The hop style's geometry (the owner's pick, mockup 9-hop.html): every leg of the route is one hop of 0.42 s, x linear in
//  time and y a true parabola whose vertex is `apex = min(60, 0.35 · length)` above the hop's higher end, never
//  flattened. The drop out of the notch is a parabola whose vertex is its start, so it never rises. Pure.
//

import CoreGraphics

struct ArisHop: Equatable {
    let start: CGPoint
    let end: CGPoint
    /// The vertex's height above the higher end.
    let apex: CGFloat
    let duration: Double
}

enum ArisHopPath {
    static let duration = 0.42
    static let maxApex: CGFloat = 60
    static let apexShare: CGFloat = 0.35

    static func hop(for leg: ArisTravelLeg) -> ArisHop {
        let length = hypot(leg.end.x - leg.start.x, leg.end.y - leg.start.y)
        let apex = leg.kind == .drop ? 0 : min(maxApex, apexShare * length)
        return ArisHop(start: leg.start, end: leg.end, apex: apex, duration: duration)
    }

    /// The route from `from` to the perch `to`, hop by hop.
    static func hops(from: CGPoint, to: CGPoint, screens: [CGRect], size: CGFloat = 28, maxHop: CGFloat = ArisTravelRoute.maxStep,
                     edgeInset: CGFloat = ArisTravelRoute.edgeInset) -> [ArisHop] {
        ArisTravelRoute.legs(from: from, to: to, screens: screens, size: size, maxStep: maxHop, edgeInset: edgeInset).map(hop(for:))
    }

    /// Where the hop is at `progress` (time over its duration, 0–1); exactly its start and end at 0 and 1.
    static func position(in hop: ArisHop, progress: Double) -> CGPoint {
        if progress <= 0 { return hop.start }
        if progress >= 1 { return hop.end }
        let p = CGFloat(progress), arc = arc(hop)
        return CGPoint(x: hop.start.x + (hop.end.x - hop.start.x) * p, y: arc.top - arc.k * (p - arc.vertex) * (p - arc.vertex))
    }

    /// Its velocity per unit of progress.
    static func velocity(in hop: ArisHop, progress: Double) -> CGVector {
        let p = CGFloat(min(1, max(0, progress))), arc = arc(hop)
        return CGVector(dx: hop.end.x - hop.start.x, dy: -2 * arc.k * (p - arc.vertex))
    }

    /// y = top − k·(p − vertex)²: through both ends, its vertex `apex` above the higher one.
    private static func arc(_ hop: ArisHop) -> (top: CGFloat, k: CGFloat, vertex: CGFloat) {
        let top = max(hop.start.y, hop.end.y) + hop.apex
        let r0 = (top - hop.start.y).squareRoot(), r1 = (top - hop.end.y).squareRoot()
        guard r0 + r1 > 0 else { return (top, 0, 0) }
        return (top, (r0 + r1) * (r0 + r1), r0 / (r0 + r1))
    }
}
