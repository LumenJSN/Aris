//
//  ArisRimSweep.swift
//  Aris
//
//  Where the listening rim's reflection is (ArisListeningRim), by the time since the rim appeared. Each pass starts with
//  the light's front just short of the U's start (top left), so it fades in there instead of popping, and runs until
//  its whole tail has left the end (top right): the light visibly travels the full U and no pass is cut off; the next
//  one starts only then. It speeds up over the first 15% of a pass, from a quarter of its speed, then runs evenly, so
//  it moves from the first frames.
//

import CoreGraphics
import Foundation

enum ArisRimSweep {
    static let period = 2.6
    /// The tail behind the head: glow = exp(−behind / tail).
    static let tail = 46.0
    /// How far past the end the head goes before the next pass: the tail there is down to 0.5%.
    static let clearance = tail * log(200.0)
    /// Where a pass starts, behind the U's start: the front (exp(−ahead² / 40)) is down to 0.5% at the start.
    static let lead = (40 * log(200.0)).squareRoot()
    private static let easeIn = 0.15
    private static let startSpeed = 0.25

    /// The head's distance along the U (0 at its start) `t` seconds after the rim appeared, for a U `total` points long.
    static func head(at t: Double, total: Double) -> Double {
        let passes = t / period
        var u = passes - passes.rounded(.down)
        // A whole number of passes that floating point puts a hair short of the wrap is the next pass's start.
        if 1 - u < 1e-9 { u = 0 }
        return -lead + progress(u) * (lead + total + clearance)
    }

    /// 0...1 over a pass: speed rising linearly from `startSpeed` to full over `easeIn`, then even.
    private static func progress(_ u: Double) -> Double {
        let speed = 1 / (1 - easeIn * (1 - startSpeed) / 2)
        guard u < easeIn else { return speed * (easeIn * (1 + startSpeed) / 2 + (u - easeIn)) }
        return speed * (startSpeed * u + (1 - startSpeed) * u * u / (2 * easeIn))
    }
}

/// The line the rim's light follows: NotchShape's whole outline from the left shoulder's tip on the screen's top edge,
/// down its shoulder, side, bottom corner, along the bottom and up the other side to the right shoulder's tip, never
/// along the top edge itself. It used to start and end below the shoulders and fade 16 points at each end, which on the
/// closed band (sides 6 points long) hid both sides and part of the corners: the light seemed to start and end partway
/// (the owner, 2026-11-04). Pure, so the tests check its ends against the outline's extremes.
enum ArisRimOutline {
    /// Only this much at each tip fades in or out (where the outline meets the screen's top edge).
    static let fadeLength = 4.0

    static func points(in rect: CGRect, top: CGFloat, bottom: CGFloat, handle: CGFloat, step: CGFloat = 1.5) -> [CGPoint] {
        var points = [CGPoint(x: rect.minX, y: rect.minY)]
        func line(to end: CGPoint) {
            guard let start = points.last else { return }
            let count = max(1, Int((hypot(end.x - start.x, end.y - start.y) / step).rounded(.up)))
            for i in 1...count {
                let t = CGFloat(i) / CGFloat(count)
                points.append(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        func corner(to end: CGPoint, corner: CGPoint, radius: CGFloat) {
            guard let start = points.last else { return }
            let c1 = CGPoint(x: start.x + (corner.x - start.x) * handle, y: start.y + (corner.y - start.y) * handle)
            let c2 = CGPoint(x: end.x + (corner.x - end.x) * handle, y: end.y + (corner.y - end.y) * handle)
            let count = max(4, Int((radius * 1.6 / step).rounded(.up)))
            for i in 1...count {
                let t = CGFloat(i) / CGFloat(count), u = 1 - t
                points.append(CGPoint(x: u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                                      y: u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y))
            }
            points[points.count - 1] = end
        }
        corner(to: CGPoint(x: rect.minX + top, y: rect.minY + top), corner: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
        line(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        corner(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY), corner: CGPoint(x: rect.minX + top, y: rect.maxY), radius: bottom)
        line(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        corner(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom), corner: CGPoint(x: rect.maxX - top, y: rect.maxY), radius: bottom)
        line(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        corner(to: CGPoint(x: rect.maxX, y: rect.minY), corner: CGPoint(x: rect.maxX - top, y: rect.minY), radius: top)
        return points
    }

    /// The tips' short fade (smoothstep over `fadeLength`); 1 everywhere else.
    static func endFade(_ s: Double, total: Double) -> Double {
        let t = min(1, max(0, min(s, total - s) / fadeLength))
        return t * t * (3 - 2 * t)
    }
}
