//
//  ArisTravelStyle.swift
//  Aris
//
//  How a teammate moves between waypoints, apart from where they are (ArisTravelRoute). Each style is a case with its
//  own route and its own motion. Pure.
//
//  .glidePop is the owner's pick and the default (G1 "스르륵 + 뿅 도착", ArisGlideLanding): G's slide, touching down with a
//  sparkle pop and a squash-settle about the feet.
//
//  .glide is the earlier pick ("스르륵" at 0.75×, ArisGlidePath), kept: one slide from the notch to the perch, leaning
//  into it, a rock and a settle. Both glides play all their legs as one curve on one easing (ArisTravelTimeline).
//
//  .hop is the earlier pick (mockup 9-hop.html), kept: along the route under the top edge, a 0.42-s hop a leg,
//  stretching up to 6% with its vertical speed; a 50-ms contact between hops, pressed 12%; a 260-ms landing, pressed
//  16% and settling (a squash about the feet; the kit's own landing isn't used).
//

import CoreGraphics
import Foundation

/// Where the character is and how it is shaped: scale about its feet, rotation in radians (counter-clockwise), and
/// which way it faces in degrees (0 the front, positive turned to the viewer's right; the facing grid's cells).
struct ArisTravelPose: Equatable {
    var position: CGPoint
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var rotation: CGFloat = 0
    var yaw: CGFloat = 0
}

enum ArisTravelStyle: Equatable {
    case glidePop
    case glide
    case hop

    static let `default` = ArisTravelStyle.glidePop
    static let glideSpeed = ArisGlidePath.speed

    /// One slide over the whole route (G or G1), not a hop a leg.
    var glides: Bool { self != .hop }

    /// The legs this style takes from `from` to the perch `to`. `obstacles` are the camera housings (screen
    /// coordinates), which a glide keeps clear of.
    func legs(from: CGPoint, to: CGPoint, screens: [CGRect], obstacles: [CGRect] = [], size: CGFloat = 28) -> [ArisTravelLeg] {
        switch self {
        case .hop:
            return ArisTravelRoute.legs(from: from, to: to, screens: screens, size: size)
        case .glide, .glidePop:
            // The first that stays on the displays and off the housings: straight, through a gate on a shared top or
            // bottom edge, via a shared side edge; else the first that at least stays on the displays (one that starts
            // beside a housing can't help passing it); else out over an edge and in at the target's.
            let candidates = ArisTravelRoute.glideCandidates(from: from, to: to, screens: screens, obstacles: obstacles, size: size)
            return candidates.first { Self.glidesClear($0, screens: screens, obstacles: obstacles, size: size) }
                ?? candidates.first { Self.glidesClear($0, screens: screens, obstacles: [], size: size) }
                ?? candidates.last ?? []
        }
    }

    /// Whether the glide over `legs` keeps its centre on the displays and its box off the housings (within a box of
    /// where it starts or ends it may touch one: the notch home sits beside its own).
    static func glidesClear(_ legs: [ArisTravelLeg], screens: [CGRect], obstacles: [CGRect], size: CGFloat) -> Bool {
        guard let start = legs.first?.start, let end = legs.last?.end else { return true }
        let curve = ArisGlideCurve(legs)
        func nearEnds(_ p: CGPoint) -> Bool { hypot(p.x - start.x, p.y - start.y) < size || hypot(p.x - end.x, p.y - end.y) < size }
        let keepOut = obstacles.map { o in
            let grown = o.insetBy(dx: -size / 2, dy: -size / 2)
            return ArisTravelRoute.screen(of: CGPoint(x: o.midX, y: o.midY), screens).map { grown.intersection($0) } ?? grown
        }
        return (0...256).allSatisfy { i in
            let p = curve.position(at: Double(i) / 256)
            return screens.contains { $0.minX <= p.x && p.x <= $0.maxX && $0.minY <= p.y && p.y <= $0.maxY }
                && (nearEnds(p) || !keepOut.contains { $0.contains(p) })
        }
    }

    // MARK: the hop's motion, a leg at a time (the glide's is the whole route's, ArisTravelTimeline)

    func duration(of leg: ArisTravelLeg) -> Double {
        switch self {
        case .glide, .glidePop: ArisGlidePath.duration(of: leg)
        case .hop: ArisHopPath.duration
        }
    }

    /// The hop's pose `progress` (0–1) through `leg`.
    func pose(in leg: ArisTravelLeg, progress: Double) -> ArisTravelPose {
        let hop = ArisHopPath.hop(for: leg)
        let speed = abs(ArisHopPath.velocity(in: hop, progress: progress).dy)
        let stretch = 0.06 * min(1, speed / (4 * hop.apex + abs(hop.end.y - hop.start.y) + 1))
        return ArisTravelPose(position: ArisHopPath.position(in: hop, progress: progress), scaleX: 1 - 0.6 * stretch, scaleY: 1 + stretch)
    }

    /// Between two legs, on the ground.
    var pause: Double {
        switch self {
        case .glide, .glidePop: 0
        case .hop: 0.05
        }
    }

    func pausePose(after leg: ArisTravelLeg, progress: Double) -> ArisTravelPose {
        let press = CGFloat(sin(.pi * min(1, max(0, progress))))
        return ArisTravelPose(position: leg.end, scaleX: 1 + 0.10 * press, scaleY: 1 - 0.12 * press)
    }

    /// Settling on the perch.
    var arrival: Double {
        switch self {
        case .glide: ArisGlidePath.settle
        case .glidePop: ArisGlideLanding.settle
        case .hop: 0.26
        }
    }

    func arrivalPose(after leg: ArisTravelLeg, progress: Double) -> ArisTravelPose {
        let u = min(1, max(0, progress))
        let scaleY = CGFloat(1 - 0.16 * exp(-5 * u) * cos(2.6 * .pi * u))
        return ArisTravelPose(position: leg.end, scaleX: 1 + (1 - scaleY) * 0.8, scaleY: scaleY)
    }
}
