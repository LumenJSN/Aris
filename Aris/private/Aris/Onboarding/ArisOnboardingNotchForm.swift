//
//  ArisOnboardingNotchForm.swift
//  Aris
//
//  The real notch, extended by Aris during the onboarding (mockups/onboarding2/js/notch.js), on the notch's own
//  geometry and clocks: a flat top, concave "ear" shoulders of radius r flaring into the bezel, convex bottom corners
//  r. talk = the listening band (270 × 32 r13 on a 185-pt camera, ArisBand's width), message = the expanded body 440
//  with a 37-pt band and one line (r31), rest = 8 narrower than talk. Open 280 ms (.2,.8,.2,1), close 200 ms
//  (.45,0,.55,1). One thing more: the band flexes when the star lands. Pure.
//

import CoreGraphics
import Foundation

struct ArisNotchForm: Equatable {
    var w: Double
    var h: Double
    var r: Double

    /// The camera housing as it is (nothing to draw on a display without one: the band grows out of the edge).
    static func hardware(closed: CGSize, hasNotch: Bool) -> ArisNotchForm {
        hasNotch ? ArisNotchForm(w: Double(closed.width), h: Double(closed.height), r: 8) : ArisNotchForm(w: 0, h: Double(closed.height), r: 0)
    }

    /// The voice band while Aris speaks or listens.
    static func talk(band: Double, height: Double) -> ArisNotchForm { ArisNotchForm(w: band, h: height, r: 13) }

    /// At rest with the star docked.
    static func rest(band: Double, height: Double) -> ArisNotchForm { ArisNotchForm(w: band - 8, h: height, r: 13) }

    /// One line under the band (the expanded body 440, band 37 + the line); wider when a longer line (another
    /// language's) needs it, 20 in each side, so it never truncates.
    static func message(height: Double, lineWidth: Double = 0) -> ArisNotchForm {
        ArisNotchForm(w: max(440, lineWidth.rounded(.up) + 40), h: max(69, height + 37), r: 31)
    }

    /// The band's line: the star and the bars sit on it.
    var bandY: Double { min(h, 37) / 2 }

    /// The left slot's centre (the 28-pt orb box at 9), where the star docks.
    func slot(cx: Double) -> CGPoint { CGPoint(x: cx - w / 2 + 9 + 14, y: bandY) }

    /// The line's top-left (20 in, under the band).
    func lineOrigin(cx: Double) -> CGPoint { CGPoint(x: cx - w / 2 + 20, y: 39) }

    /// The five voice bars' left edge (14 in from the right, 2.5 wide, 2.5 apart).
    func barsX(cx: Double) -> Double { cx + w / 2 - 14 - (5 * 2.5 + 4 * 2.5) }

    /// The silhouette about the centre line `cx`, hanging from y 0.
    func outline(cx: Double) -> CGPath {
        let r = min(self.r, w / 4, h / 2)
        let l = cx - w / 2, rt = cx + w / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: l - r, y: 0))
        path.addArc(tangent1End: CGPoint(x: l, y: 0), tangent2End: CGPoint(x: l, y: r), radius: max(r, 0.001))
        path.addLine(to: CGPoint(x: l, y: h - r))
        path.addArc(tangent1End: CGPoint(x: l, y: h), tangent2End: CGPoint(x: l + r, y: h), radius: max(r, 0.001))
        path.addLine(to: CGPoint(x: rt - r, y: h))
        path.addArc(tangent1End: CGPoint(x: rt, y: h), tangent2End: CGPoint(x: rt, y: h - r), radius: max(r, 0.001))
        path.addLine(to: CGPoint(x: rt, y: r))
        path.addArc(tangent1End: CGPoint(x: rt, y: 0), tangent2End: CGPoint(x: rt + r, y: 0), radius: max(r, 0.001))
        path.closeSubpath()
        return path
    }
}

/// The notch's outline over time: one morph at a time on the open/close clocks, plus the landing's flex.
struct ArisNotchMorph: Equatable {
    private(set) var from: ArisNotchForm
    private(set) var to: ArisNotchForm
    /// Seconds (the media clock).
    private(set) var start: Double = 0
    private(set) var ms: Double = 280
    private(set) var opens = true
    private(set) var kickAt: Double = -1e9
    private(set) var kickAmp: Double = 0

    init(_ form: ArisNotchForm) {
        from = form
        to = form
    }

    /// Morphs from wherever it is now: growing opens (280 ms), shrinking closes (200 ms); Reduce Motion 120 ms.
    mutating func go(to next: ArisNotchForm, at now: Double, reduced: Bool) {
        let current = shape(at: now)
        from = current
        to = next
        start = now
        opens = !reduced && next.w * next.h >= current.w * current.h
        ms = reduced ? 120 : (opens ? 280 : 200)
    }

    mutating func snap(_ form: ArisNotchForm) {
        from = form
        to = form
        start = 0
    }

    /// The landing: the band flexes wider for a beat (`amp` points).
    mutating func kick(at now: Double, amp: Double) {
        kickAt = now
        kickAmp = amp
    }

    private func shape(at now: Double) -> ArisNotchForm {
        let p = ArisOnboardingMotion.clamp((now - start) * 1000 / ms)
        let e = opens ? ArisOnboardingMotion.notchOpen(p) : ArisOnboardingMotion.notchClose(p)
        return ArisNotchForm(w: from.w + (to.w - from.w) * e, h: from.h + (to.h - from.h) * e, r: from.r + (to.r - from.r) * e)
    }

    func form(at now: Double) -> ArisNotchForm {
        var f = shape(at: now)
        f.w += kickAmp * abs(ArisOnboardingMotion.wobble((now - kickAt) * 1000, amp: 1, tau: 110, period: 260))
        return f
    }
}
