//
//  ArisOnboardingScore.swift
//  Aris
//
//  The intro's score and the flight, as pure functions of time (mockups/onboarding2/js/intro.js, the owner's approved
//  mockup, 2026-11-07). Every track is a window in ms on a named curve; tracks overlap on purpose and land together.
//  Beat lengths: 7.4 s to the CTA, the CTA at centre + 104.
//
//    0 ─ veil 1800 sineInOut ─┐   300 ─ kicker + tagline in 1500 ─┐            4500 ─ tagline out ─ 5200
//    0 ─ rise ─────────── 3400        the star comes up over the bottom edge as a defocused sun
//             3000 ─ condense ─────── 5400   12× → 1×, climbs to centre; the tagline drifts up and recedes
//                  3500 ─ focus ──── 5400    rack focus: soft until late, then snaps
//                                     5400 LOCK: the chime; the glint (D 글린트) catches the top tip, settle wobble
//                                     6400 ─ drift 700 ─ 7100 the star slides to its slot; letters from 6460 + 70·i
//                                                         8100 ─ 시작하기 500 (the glint again)        12000 skip
//
//  The light is the owner's pick D "글린트": no halo, no spikes; one small four-point glint on the top tip, twice.
//

import CoreGraphics
import Foundation

enum ArisOnboardingScore {
    typealias M = ArisOnboardingMotion

    // MARK: - Times (ms from the first frame)

    static let veil: ClosedRange<Double> = 0...1800
    static let tagIn: ClosedRange<Double> = 300...1800
    static let tagOut: ClosedRange<Double> = 4500...5200
    static let rise: ClosedRange<Double> = 0...3400
    static let condense: ClosedRange<Double> = 3000...5400
    static let focus: ClosedRange<Double> = 3500...5400
    /// The chime's hit; the star is in focus and at size.
    static let lock: Double = 5400
    static let drift: ClosedRange<Double> = 6400...7100
    static let letters: Double = 6460
    static let letterStep: Double = 70
    static let letterDuration: Double = 520
    static let ctaIn: ClosedRange<Double> = 8100...8600
    /// Skip shows 12 s after the overlay mounts.
    static let skip: Double = 12000
    /// The glint's two 700 ms windows: the focus frame, and as 시작하기 arrives.
    static let glints: [Double] = [5450, 8250]
    static let glintLength: Double = 700
    /// Defocus of the rising sun, on-screen points (glow D).
    static let sunBlur: Double = 34

    /// The flight after 시작하기 (ms from the click).
    struct FlightTimes: Equatable {
        let squash: ClosedRange<Double>
        let launch: ClosedRange<Double>
        let land: Double
        let whoosh: Double
        let notch: Double
        let voice: Double
    }

    static let flightTimes = FlightTimes(squash: 0...240, launch: 240...1000, land: 1000, whoosh: 600, notch: 520, voice: 1450)

    /// The hero star's box (its body spans ~80 % of it) and the notch star's box (≈ the 18-pt notch orb).
    static let base: Double = 96
    static let dock: Double = 22
    static let starBody: Double = 0.8

    // MARK: - Layout

    struct Layout: Equatable {
        var width: Double
        var height: Double
        var lockY: Double
        var vis: Double
        var lockX: Double
        var wordX: Double
        var wordY: Double
        var ctaX: Double
        var ctaY: Double
        var sunS: Double
    }

    /// The lockup (star + "Aris"): `word` is the wordmark's measured size.
    static func layout(screen: CGSize, word: CGSize) -> Layout {
        let w = Double(screen.width), h = Double(screen.height)
        let vis = base * starBody, gap = 22.0, total = vis + gap + Double(word.width)
        let left = w / 2 - total / 2, lockY = (h * 0.5).rounded()
        return Layout(width: w, height: h, lockY: lockY, vis: vis, lockX: left + vis / 2, wordX: left + vis + gap,
                      wordY: lockY - 12 - Double(word.height) / 2 + 3, ctaX: w / 2 - 140, ctaY: lockY + 104 - 12, sunS: h / vis)
    }

    // MARK: - Frames

    enum Anchor: Equatable { case center, top, bottom }

    struct Hero: Equatable {
        var x: Double
        var y: Double
        /// Scale of the 96-pt box.
        var scale: Double
        /// On-screen defocus.
        var blur: Double = 0
        var sx: Double = 1
        var sy: Double = 1
        /// Radians: squash and stretch run along this direction.
        var angle: Double = 0
        var opacity: Double = 1
        var anchor: Anchor = .center
    }

    struct Letter: Equatable {
        var opacity: Double
        var blur: Double
        var dx: Double
    }

    struct Fade: Equatable {
        var opacity: Double
        var y: Double
        var scale: Double
    }

    struct Frame: Equatable {
        var veil: Double
        var hero: Hero
        /// The glint's progress 0…1, or -1 when there is none.
        var glint: Double
        /// The star body's on-screen size (for the glint and the trail).
        var size: Double
        var tagline: Fade
        var letters: [Letter]
        var cta: Fade
    }

    /// The glint's progress inside one of its windows, else -1.
    static func glint(at t: Double) -> Double {
        for a in glints where t >= a && t <= a + glintLength { return (t - a) / glintLength }
        return -1
    }

    static func frame(at t: Double, layout L: Layout, reduced: Bool) -> Frame {
        reduced ? reducedFrame(at: t, layout: L) : fullFrame(at: t, layout: L)
    }

    private static func fullFrame(at t: Double, layout L: Layout) -> Frame {
        let veil = M.sineInOut(M.span(t, Self.veil))
        let sunHalf = 0.5 * L.vis * L.sunS
        let yHidden = L.height + sunHalf + 10, yPeek = L.height * 0.64 + sunHalf
        let rise = M.rise(M.span(t, Self.rise))
        let cond = M.condense(M.span(t, Self.condense))
        let focus = M.focus(M.span(t, Self.focus))
        let drift = M.move(M.span(t, Self.drift))
        var s = M.lerp(L.sunS * 1.04, L.sunS, rise)
        s = M.lerp(s, 1, cond)
        // Momentum carries it a hair small at the lock, then back.
        s *= 1 - M.wobble(t - lock, amp: 0.035, tau: 140, period: 420)
        let y = M.lerp(M.lerp(yHidden, yPeek, rise), L.lockY - 12, cond)
        let x = M.lerp(L.width / 2, L.lockX, drift)
        let letters = (0..<4).map { i -> Letter in
            let a = Self.letters + Double(i) * letterStep
            let p = M.settle(M.span(t, a, a + letterDuration))
            return Letter(opacity: p, blur: 10 * (1 - p), dx: -22 * (1 - p))
        }
        let tag = M.span(t, tagIn) * (1 - M.span(t, tagOut))
        let c = M.settle(M.span(t, ctaIn))
        return Frame(veil: veil,
                     hero: Hero(x: x, y: y, scale: s, blur: sunBlur * (1 - focus), opacity: M.span(t, 120, 900)),
                     glint: glint(at: t), size: L.vis * s,
                     tagline: Fade(opacity: M.sineInOut(tag), y: M.lerp(14, -22, cond), scale: M.lerp(1.035, 0.955, cond)),
                     letters: letters,
                     cta: Fade(opacity: c, y: 12 * (1 - c), scale: 0.96 + 0.04 * c))
    }

    /// Reduce Motion: no travel, no glint; the same beats as cross-fades in 1.2 s.
    private static func reducedFrame(at t: Double, layout L: Layout) -> Frame {
        let f = M.span(t, 400, 800)
        return Frame(veil: M.span(t, 0, 400),
                     hero: Hero(x: L.lockX, y: L.lockY - 12, scale: 1, opacity: f),
                     glint: -1, size: L.vis,
                     tagline: Fade(opacity: 0, y: 0, scale: 1),
                     letters: (0..<4).map { _ in Letter(opacity: M.span(t, 600, 900), blur: 0, dx: 0) },
                     cta: Fade(opacity: M.span(t, 900, 1100), y: 0, scale: 1))
    }

    // MARK: - The flight

    /// `dt` ms after the click; `from` the lockup's star, `to` the notch's left slot.
    static func flight(at dt: Double, from: CGPoint, to: CGPoint, screen: CGSize) -> Hero {
        let times = flightTimes
        let w = Double(screen.width), h = Double(screen.height)
        if dt < times.launch.lowerBound {
            // Anticipation: pulled down and away from the target, squashed against an invisible floor.
            let p = M.squash(M.span(dt, times.squash))
            return Hero(x: from.x + 6 * p, y: from.y + 12 * p, scale: 1, sx: 1 + 0.08 * p, sy: 1 - 0.1 * p, anchor: .bottom)
        }
        let p0 = CGPoint(x: from.x + 6, y: from.y + 12), p1 = CGPoint(x: p0.x - 0.05 * w, y: p0.y - 0.36 * h)
        let p2 = CGPoint(x: to.x + 0.07 * w, y: to.y + 0.2 * h), p3 = to
        if dt < times.land {
            let u = M.launch(M.span(dt, times.launch)), u2 = M.launch(M.span(dt + 8, times.launch))
            let a = M.bez2d(p0, p1, p2, p3, u), b = M.bez2d(p0, p1, p2, p3, u2)
            let speed = hypot(b.x - a.x, b.y - a.y) / 8
            let stretch = min(0.24, speed * 0.06)
            let s = M.lerp(1, dock / base, pow(u, 1.25))
            return Hero(x: a.x, y: a.y, scale: s, blur: stretch * 4 * s, sx: 1 + stretch, sy: 1 - stretch * 0.5, angle: atan2(a.dy, a.dx))
        }
        // The landing pop: squashes against the band (contact at the top), overshoots once, settles (~420 ms).
        let wob = M.wobble(dt - times.land, amp: 0.24, tau: 110, period: 280)
        return Hero(x: to.x, y: to.y, scale: dock / base, sx: 1 + wob, sy: 1 - wob, anchor: .top)
    }

    struct TrailPoint: Equatable {
        var x: Double
        var y: Double
        var size: Double
    }

    /// The shooting star's trail: the last 170 ms of the same curve, every 17 ms, head first (frame-rate independent).
    static func trail(at dt: Double, from: CGPoint, to: CGPoint, screen: CGSize, size: Double) -> [TrailPoint] {
        var points: [TrailPoint] = []
        for k in 0...10 {
            let d = dt - Double(k) * 17
            if d < flightTimes.launch.lowerBound { break }
            let q = flight(at: d, from: from, to: to, screen: screen)
            points.append(TrailPoint(x: q.x, y: q.y, size: size * q.scale))
        }
        return points
    }
}
