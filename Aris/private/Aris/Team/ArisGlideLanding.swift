//
//  ArisGlideLanding.swift
//  Aris
//
//  G1 "스르륵 + 뿅 도착", the owner's pick and the default (mockup travel-g-plus.html, card G1): G's slide (ArisGlidePath)
//  at 0.75×, on an easing that is still moving a little at touchdown, so the landing reads; then one sparkle pop and
//  a squash-settle about the feet. Pure.
//

import CoreGraphics
import Foundation

enum ArisGlideLanding {
    /// The slide's progress: cubic-bezier(0.42, 0, 0.4, 0.9), arriving with a sixth of its average speed left.
    static func ease(_ u: Double) -> Double { ArisEase.cubic(0.42, 0, 0.4, 0.9, u) }
    /// The forward lean, in degrees, at its most a third of the way along; upright again by `1 / reach`.
    static let lean = 7.0
    static let reach = 1.6
    /// The squash-settle on the perch: 0.4 s at 1×.
    static let settle = 0.4 / ArisGlidePath.speed
    /// Pressed 16% at touchdown, widened 0.8 of that, settling as the mockup's settle(u, 0.16).
    static let press = 0.16
    static let widen = 0.8

    /// The lean `u` (0–1) through the slide, in radians (counter-clockwise; forward is clockwise going right).
    static func lean(direction: Double, progress u: Double) -> CGFloat {
        let u = min(1, max(0, u))
        return CGFloat(-direction * lean * sin(.pi * min(1, u * reach)) * .pi / 180)
    }

    /// The squash about the feet, `progress` (0–1) through the settle; exactly upright at the end.
    static func squash(progress: Double) -> (x: CGFloat, y: CGFloat) {
        let u = min(1, max(0, progress))
        guard u < 1 else { return (1, 1) }
        let y = 1 - press * exp(-5 * u) * cos(2.6 * .pi * u)
        return (CGFloat(1 + (1 - y) * widen), CGFloat(y))
    }
}

/// G1's sparkle pop: five 4-point sparkles from just above the feet, fanned sideways and a little up, each shrinking,
/// turning and fading once. Its times are wall clock (not stretched by 0.75), under 0.45 s. Sizes are the mockup's, at
/// its 24-pt star, and scale with the star.
enum ArisLandingSparkle {
    static let count = 5
    static let life = 0.42
    static let referenceSize: CGFloat = 24
    /// Each sparkle's box, and where it starts: this far above the feet.
    static let side: CGFloat = 9
    static let rise: CGFloat = 5
    /// The fan, in the mockup's degrees (y down, so negative is up), and how far it reaches sideways and up.
    static let angles: [Double] = [-168, -128, -90, -52, -12]
    static let reach = CGSize(width: 14, height: 8)
    static let scales: (start: CGFloat, end: CGFloat) = (0.95, 0.3)
    static let opacity: CGFloat = 0.95
    /// How far each turns (clockwise, radians) as it goes.
    static let spin: CGFloat = .pi / 4
    /// The colour, #ffe9a8.
    static let rgb: (CGFloat, CGFloat, CGFloat) = (1, 233 / 255, 168 / 255)

    struct Frame: Equatable {
        let time: Double
        /// The sparkle's centre from the feet, y up.
        let offset: CGVector
        let scale: CGFloat
        /// Clockwise, radians.
        let spin: CGFloat
        let opacity: CGFloat
    }

    /// Sparkle `index` at `time` (0 to `life`) after touchdown, for a star `size` points tall.
    static func frame(_ index: Int, at time: Double, size: CGFloat) -> Frame {
        let u = min(1, max(0, time / life)), e = CGFloat(ArisEase.cubic(0.23, 1, 0.32, 1, u)), k = size / referenceSize
        let r = angles[min(max(0, index), angles.count - 1)] * .pi / 180
        let offset = CGVector(dx: CGFloat(cos(r)) * reach.width * e * k, dy: (rise - CGFloat(sin(r)) * reach.height * e) * k)
        return Frame(time: time, offset: offset, scale: scales.start + (scales.end - scales.start) * e, spin: spin * e,
                     opacity: u >= 1 ? 0 : opacity * CGFloat(1 - u * u))
    }

    /// Evenly spaced frames from touchdown to `life`, for the render server (linear between them).
    static func keyframes(_ index: Int, size: CGFloat, rate: Double) -> [Frame] {
        let n = max(1, Int((life * rate).rounded(.up)))
        return (0...n).map { frame(index, at: $0 == n ? life : life * Double($0) / Double(n), size: size) }
    }

    /// The 4-point star in a `side`-point box (the mockup's 10-unit path, scaled).
    static func path(side: CGFloat) -> CGPath {
        let s = side / 10, p = CGMutablePath()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        p.move(to: pt(5, 0))
        p.addCurve(to: pt(10, 5), control1: pt(5.6, 3.4), control2: pt(6.6, 4.4))
        p.addCurve(to: pt(5, 10), control1: pt(6.6, 5.6), control2: pt(5.6, 6.6))
        p.addCurve(to: pt(0, 5), control1: pt(4.4, 6.6), control2: pt(3.4, 5.6))
        p.addCurve(to: pt(5, 0), control1: pt(3.4, 4.4), control2: pt(4.4, 3.4))
        p.closeSubpath()
        return p
    }
}
