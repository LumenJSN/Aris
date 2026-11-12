//
//  ArisStrainClip.swift
//  Aris
//
//  "낑낑": a teammate dragging a window to its place (mockup 9-hop.html, window drag). It grips the window's leading top
//  corner and leans in, pressed and trembling (0.36 s); pulls it in bursts of 0.42 s, catching its breath for 0.26 s
//  and 0.32 s between; lets go (0.2 s); and gives a proud little hop in place (0.46 s). The window moves only during
//  the pulls, on the same effortful curve. Pure: the clip says where the character is and how far the window has
//  gone; moving the real window is the director's (Task 10).
//

import CoreGraphics
import Foundation

struct ArisStrainClip: ArisMotionTrack {
    struct Puff: Equatable {
        let time: Double
        let text: String
    }

    static let gripTime = 0.36
    static let pullTime = 0.42
    static let breathTime = 0.26
    static let breathExtra = 0.06
    static let releaseTime = 0.2
    static let cheerTime = 0.46
    /// About this far a pull, three pulls at least.
    static let pullSpan: CGFloat = 62
    /// The tremble comes and goes over this long, so it never pops on or off between a pull and a breath.
    static let trembleRamp = 0.05

    let grip: CGPoint
    let move: CGVector
    let pulls: Int
    let duration: Double
    let puffs: [Puff]
    private let dir: CGFloat
    private let segments: [Segment]

    private enum Phase { case grip, pull(Int), breath(Int), release, cheer }
    private struct Segment {
        let phase: Phase
        let start: Double
        let length: Double
    }

    /// The character's centre beside the leading top corner of `window` (AppKit), for a pull in `dir` (±1).
    static func grip(window: CGRect, dir: CGFloat, size: CGFloat) -> CGPoint {
        CGPoint(x: dir > 0 ? window.maxX + 8 : window.minX - 8, y: window.maxY - 26 + size / 2)
    }

    /// Gripping at `grip`, the window to go `move` (AppKit, y up).
    init(grip: CGPoint, move: CGVector) {
        self.grip = grip
        self.move = move
        dir = move.dx >= 0 ? 1 : -1
        pulls = max(3, Int((hypot(move.dx, move.dy) / Self.pullSpan).rounded(.up)))
        var phases: [(Phase, Double)] = [(.grip, Self.gripTime)]
        for i in 0..<pulls {
            phases.append((.pull(i), Self.pullTime))
            if i < pulls - 1 { phases.append((.breath(i), Self.breathTime + Double(i % 2) * Self.breathExtra)) }
        }
        phases += [(.release, Self.releaseTime), (.cheer, Self.cheerTime)]
        var t = 0.0
        segments = phases.map { phase, length in
            defer { t += length }
            return Segment(phase: phase, start: t, length: length)
        }
        duration = t
        puffs = [Puff(time: 0, text: "낑")] + segments.compactMap { segment in
            if case .pull(let i) = segment.phase, i % 2 == 1 { return Puff(time: segment.start, text: "낑!") }
            return nil
        }
    }

    func pose(at time: Double) -> ArisTravelPose {
        let end = CGPoint(x: grip.x + move.dx, y: grip.y + move.dy)
        guard time < duration else { return ArisTravelPose(position: end) }
        let (segment, u) = segment(at: time)
        let lean = { (degrees: Double) in CGFloat(-Double(dir) * degrees * .pi / 180) }
        switch segment.phase {
        case .grip:
            let e = Self.pull(u)
            return ArisTravelPose(position: at(0, shake: 0.7 * e, time: time), scaleX: 1 + 0.06 * e, scaleY: 1 - 0.09 * e, rotation: lean(15 * Double(e)))
        case .pull(let i):
            let done = (CGFloat(i) + Self.pull(u)) / CGFloat(pulls)
            let k = Self.ramp(up: u * segment.length)
            guard i == 0 else {
                return ArisTravelPose(position: at(done, shake: 0.8 * k, time: time), scaleX: 1.07, scaleY: 0.9, rotation: lean(16))
            }
            // The first pull takes over from the grip's lean and press without a step.
            func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { k >= 1 ? b : a + (b - a) * k }
            return ArisTravelPose(position: at(done, shake: mix(0.7, 0.8), time: time), scaleX: mix(1.06, 1.07), scaleY: mix(0.91, 0.9),
                                  rotation: k >= 1 ? lean(16) : lean(15 + Double(k)))
        case .breath(let i):
            let b = CGFloat(sin(.pi * u))
            return ArisTravelPose(position: at(CGFloat(i + 1) / CGFloat(pulls), shake: 0.8 * Self.ramp(down: u * segment.length), time: time),
                                  scaleX: 1.07 - 0.07 * b, scaleY: 0.9 + 0.13 * b, rotation: lean(16 - 9 * Double(b)))
        case .release:
            let e = Self.pull(u)
            return ArisTravelPose(position: at(1, shake: 0.8 * Self.ramp(down: u * segment.length), time: time), scaleX: 1.07 - 0.07 * e,
                                  scaleY: 0.9 + 0.1 * e, rotation: lean(16 * (1 - Double(e))))
        case .cheer:
            let rise = 9 * sin(.pi * min(1, u * 1.4))
            let press = u > 0.72 ? sin(.pi * (u - 0.72) / 0.28) : 0
            return ArisTravelPose(position: CGPoint(x: end.x, y: end.y + CGFloat(max(0, rise))),
                                  scaleX: 1 + 0.08 * CGFloat(press), scaleY: 1 - 0.1 * CGFloat(press))
        }
    }

    /// How far the window has gone at `time`.
    func windowOffset(at time: Double) -> CGVector {
        guard time < duration, time > 0 else { return time <= 0 ? .zero : move }
        let (segment, u) = segment(at: time)
        let done: CGFloat
        switch segment.phase {
        case .grip: done = 0
        case .pull(let i): done = (CGFloat(i) + Self.pull(u)) / CGFloat(pulls)
        case .breath(let i): done = CGFloat(i + 1) / CGFloat(pulls)
        case .release, .cheer: return move
        }
        return CGVector(dx: move.dx * done, dy: move.dy * done)
    }

    private func segment(at time: Double) -> (Segment, Double) {
        let segment = segments.last { $0.start <= time } ?? segments[0]
        return (segment, min(1, max(0, (time - segment.start) / segment.length)))
    }

    /// The grip plus `done` of the move, trembling by `shake` (the mockup's 15 Hz and 21 Hz wobble).
    private func at(_ done: CGFloat, shake: CGFloat, time: Double) -> CGPoint {
        let jx = shake * CGFloat(sin(time * 2 * .pi * 15)), jy = shake * 0.5 * CGFloat(sin(time * 2 * .pi * 21 + 1))
        return CGPoint(x: grip.x + move.dx * done + jx, y: grip.y + move.dy * done - jy)
    }

    private static func ramp(up elapsed: Double) -> CGFloat { CGFloat(min(1, elapsed / trembleRamp)) }
    private static func ramp(down elapsed: Double) -> CGFloat { CGFloat(max(0, 1 - elapsed / trembleRamp)) }

    /// The effortful start and stop: cubic-bezier(0.45, 0, 0.55, 1).
    static func pull(_ t: Double) -> CGFloat { CGFloat(ArisEase.symmetric(t)) }
}
