//
//  ClaudeEarDots.swift
//  Aris
//
//  Where the session dots sit in the ear ring's bottom opening (mockup claude-usage.html, 틈 넓히기). Only sessions
//  at work, waiting, failed or just done take a dot; idle ones merge into the ring. The opening is today's ±0.9 rad
//  for one to three dots and widens only as far as more need, keeping three dots' clearance off the arc's round caps;
//  with no dot it closes completely (a full ring). The arc never drops under 60 % of the circle (gap ≤ 0.4π): past
//  that the clearance holds and the dots draw closer, down to 0.6 pt apart, then shrink, down to 2.2 pt. An idle
//  session's dot waits, invisible, in the arc end nearer its slot: it slides there and melts into the cap when the
//  session rests, and springs back out of it when the session wakes.
//  Angles are from the ring's centre, y down: π/2 is the bottom, more is to the left. Foundation only (tested).
//

import Foundation

enum ClaudeEarDots {
    struct Session: Equatable {
        let id: String
        let active: Bool
    }

    struct Dot: Equatable {
        let id: String
        let angle: Double
        let diameter: Double
        /// Resting: drawn in the arc's end, the line's width, faded out.
        let merged: Bool
        /// The end it is nearer to: +1 left (π/2 + gap, where the fill starts), −1 right (π/2 − gap, the track's end).
        let side: Int
    }

    struct Layout: Equatable {
        /// Half-width of the bottom opening, in radians (0: a full ring).
        let gap: Double
        /// Every session in the order given, merged ones included.
        let dots: [Dot]
    }

    /// The opening with any dot at all: today's ±0.9 rad, which fits up to three.
    static let gap = 0.9
    /// The step between dot centres (radians).
    static let step = 0.5
    /// The arc never under 60 % of the circle.
    static let maxGap = 0.4 * .pi
    /// Points at the ear's size: the space kept between dots, and the smallest a dot gets.
    static let clear = 0.6
    static let minDot = 2.2

    /// Done keeps its dot until the session turns idle (ClaudeStore's 4-second Stop → idle); idle and asleep merge.
    static func isActive(_ state: ClaudeState) -> Bool { state.tone != .rest }

    /// The ring's line, its radius and the reach of its round cap into the opening (radians), for a ring `size` wide.
    static func lineWidth(_ size: Double) -> Double { size * 0.08 }
    static func radius(_ size: Double) -> Double { (size - lineWidth(size)) / 2 }
    static func capReach(_ size: Double) -> Double { (lineWidth(size) / 2) / radius(size) }

    /// The breathing room between the outer dot's edge and the arc's cap at three dots in today's opening (≈0.172 rad
    /// at 22.5 pt): every opening keeps at least this much, more dots or fewer.
    static func clearance(_ size: Double) -> Double {
        gap - capReach(size) - step - (size * 0.13 / 2) / radius(size)
    }

    /// The opening for `count` dots, the step between them and their diameter. Up to three: today's ±0.9 rad. More:
    /// half the row, half a dot, the cap and the clearance, up to 0.4π; past it the clearance holds, the dots draw
    /// closer (to 0.6 pt apart), then shrink (to 2.2 pt), and only at the floor does the space between them give.
    static func slots(count: Int, size: Double) -> (gap: Double, step: Double, diameter: Double) {
        guard count > 0 else { return (0, 0, 0) }
        let r = radius(size), keep = capReach(size) + clearance(size), room = maxGap - keep
        var d = size * 0.13, s = count > 1 ? step : 0
        let need = max(gap, Double(count - 1) / 2 * s + (d / 2) / r + keep)
        guard need > maxGap else { return (need, s, d) }
        s = count > 1 ? 2 * (room - (d / 2) / r) / Double(count - 1) : 0
        if count > 1, s * r < d + clear {
            d = max(minDot, (room * 2 * r - clear * Double(count - 1)) / Double(count))
            s = 2 * (room - (d / 2) / r) / Double(count - 1)
        }
        return (maxGap, s, d)
    }

    static func layout(_ sessions: [Session], size: Double) -> Layout {
        let active = sessions.filter(\.active)
        let fit = slots(count: active.count, size: size)
        func angle(_ index: Int, of count: Int, step: Double) -> Double { .pi / 2 + (Double(count - 1) / 2 - Double(index)) * step }
        var slot: [String: Double] = [:]
        for (i, s) in active.enumerated() { slot[s.id] = angle(i, of: active.count, step: fit.step) }
        let dots = sessions.map { session -> Dot in
            if let a = slot[session.id] {
                return Dot(id: session.id, angle: a, diameter: fit.diameter, merged: false, side: a > .pi / 2 + 1e-9 ? 1 : -1)
            }
            // Where it would sit among the active ones (where it was, or will be): its nearer end.
            let with = sessions.filter { $0.active || $0.id == session.id }
            let own = slots(count: with.count, size: size)
            let index = with.firstIndex { $0.id == session.id } ?? 0
            let side = angle(index, of: with.count, step: own.step) > .pi / 2 + 1e-9 ? 1 : -1
            return Dot(id: session.id, angle: .pi / 2 + Double(side) * fit.gap, diameter: lineWidth(size), merged: true, side: side)
        }
        return Layout(gap: fit.gap, dots: dots)
    }

    /// The ring's arc for an opening of `gap` either side of the bottom: where it starts (π/2 + gap, on the left) and
    /// how far it turns clockwise, the whole track at `fraction` 1 (it ends at π/2 − gap). One value moves the start
    /// and the length together, so the ring opens and closes as one piece; with no gap it is a full turn.
    static func arc(gap: Double, fraction: Double) -> (start: Double, sweep: Double) {
        (.pi / 2 + gap, (2 * .pi - 2 * gap) * min(max(fraction, 0), 1))
    }

    /// The share of the track a percent fills: a sliver at 0 %, so the ring's start always shows, and all of it from 100 %.
    static func fill(percent: Double) -> Double { max(0.003, min(percent, 100) / 100) }

    /// How strong a merging dot is in the cap it melts into: the fill's own at the left end when the ring has a fill,
    /// the track's (0.22) otherwise.
    static func capOpacity(side: Int, filled: Bool) -> Double { side > 0 && filled ? 1 : 0.22 }
}
