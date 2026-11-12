//
//  ArisSideLook.swift
//  Aris
//
//  The side notch's look as numbers. The views draw these and nothing else (ArisSideLayers the body,
//  ArisSidePanelView the content), and tests/vside-tests.swift pins every one. Foundation and CoreGraphics only.
//
//  What the body is made of: the same AppKit glass as the top notch, tinted sRGB(0, 0, .015, .9), with the
//  outline as its own path, a white rim behind it and an even wash rgba(0, 0, 6, .95) over it, in every state (the
//  sliver too). Here that is drawn only while the notch's own look is `private-glass` and every private part took
//  (ArisGlassLook, ArisGlassFallback: the top notch's own probe, asked once); otherwise the public blur that Aris
//  drew before, under the same wash; with macOS's Reduce Transparency no material at all under a solid wash.
//

import CoreGraphics
import Foundation

enum ArisSideLook {
    // MARK: - Material

    /// The glass's tint, sRGB(0, 0, 0.015, 0.9).
    static let glassTintBlue = 0.015
    static let glassTintAlpha = 0.9
    /// The content wash over the glass: rgba(0, 0, 6, 0.95).
    static let washBlue = 6.0 / 255
    static let washAlpha = 0.95
    /// The rim is the glass layer's shadow: white, no offset, radius 2.
    static let rimRadius = 2.0
    /// The rim's strength on the sliver.
    static let rimPeak = 0.12

    /// The rim per frame, `0.12 × min(1, W/4) × clamp((42 − W)/24, 0, 1)` for an outline W wide:
    /// full on the 16- and 18-point sliver, fading as the panel widens and gone from 42 points (so the open panel
    /// has no rim and, on the glass, no shadow of its own).
    static func rimOpacity(width: Double) -> Double {
        rimPeak * min(1, max(0, width) / 4) * min(1, max(0, (42 - width) / 24))
    }

    /// What is under the wash.
    enum Material: Equatable {
        /// The private glass: AppKit's, with the private parts.
        case glass
        /// The public fallback: a behind-window blur (what Aris drew before).
        case blur
        /// Reduce Transparency: nothing, the wash is solid.
        case solid
    }

    /// The material for the notch's chosen look and the private parts this macOS took. The private glass only for
    /// `private-glass` with every part; any other look (an old hidden preference value) keeps the public blur.
    static func material(look: ArisGlassLook, parts: ArisGlassParts, reduceTransparency: Bool) -> Material {
        if reduceTransparency { return .solid }
        return look.usesPrivateParts && ArisGlassFallback.decide(parts).privateGlass ? .glass : .blur
    }

    // MARK: - Outline

    /// Samples per arc: 10, so the outline is 4 × 10 + 4 = 44 points in every state.
    static let arcSamples = 10
    static let outlinePoints = 4 * arcSamples + 4

    // MARK: - Motion

    /// A cubic-bezier over a duration, the form the glass's motion takes.
    struct Timing: Equatable {
        let duration: Double
        let x1: Double
        let y1: Double
        let x2: Double
        let y2: Double
    }

    /// The opening clock, shared with the top notch: 280 ms (0.2, 0.8, 0.2, 1).
    static let opening = Timing(duration: 0.28, x1: 0.2, y1: 0.8, x2: 0.2, y2: 1)
    /// The closing clock, shared with the top notch: 200 ms (0.45, 0, 0.55, 1).
    static let closing = Timing(duration: 0.2, x1: 0.45, y1: 0, x2: 0.55, y2: 1)
    /// The sliver's clock: 180 ms (0.4, 0, 0.2, 1), coming out and going in, and growing under the pointer.
    static let sliver = Timing(duration: 0.18, x1: 0.4, y1: 0, x2: 0.2, y2: 1)
    /// The sliver's dots show 45 ms into its 180.
    static let dotRevealDelay = 0.045

    /// The cubic-bezier solved for the time by Newton–Raphson (slope floor 1e-4, clamped to 0…1). `t` is the
    /// fraction of the duration gone.
    static func eased(_ t: Double, _ timing: Timing) -> Double {
        let time = min(1, max(0, t))
        func curve(_ a: Double, _ b: Double, _ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s }
        var s = time
        for _ in 0..<12 {
            let slope = 3 * (1 - s) * (1 - s) * timing.x1 + 6 * (1 - s) * s * (timing.x2 - timing.x1) + 3 * s * s * (1 - timing.x2)
            if abs(slope) < 1e-4 { break }
            s = min(1, max(0, s - (curve(timing.x1, timing.x2, s) - time) / slope))
        }
        return curve(timing.y1, timing.y2, s)
    }

    /// The rim's strength at `steps` + 1 evenly spaced moments of a morph from one width to another: the width goes
    /// linearly by the eased progress and the rim follows it frame by frame.
    static func rimKeyframes(from: Double, to: Double, timing: Timing, steps: Int = 24) -> [Double] {
        let count = max(1, steps)
        return (0...count).map { index in
            rimOpacity(width: from + (to - from) * eased(Double(index) / Double(count), timing))
        }
    }

    // MARK: - Content

    /// The header: shoulder 31 + 60; its padding 49 20 6 14 (the edge side 14).
    static let headerHeight: CGFloat = 91
    static let headerTop: CGFloat = 49
    static let headerEdgeSide: CGFloat = 14
    static let headerFarSide: CGFloat = 20
    /// The search pill's height, and the gap to the lock.
    static let headerPill: CGFloat = 36
    static let headerGap: CGFloat = 8
    /// The list's padding: 95 (header + 4) on top, 13 on the far side, 73 at the end, 7 on the edge side.
    static let listTop: CGFloat = headerHeight + 4
    static let listFarSide: CGFloat = 13
    static let listEdgeSide: CGFloat = 7
    /// The scroll's end padding: shoulder 31 + 42.
    static let scrollEndPadding: CGFloat = 73
    /// The list's mask: clear down to header − 18, whole from header + 14, fading over the last 34.
    static let fadeTopClear: CGFloat = headerHeight - 18
    static let fadeTopWhole: CGFloat = headerHeight + 14
    static let fadeBottom: CGFloat = 34
    /// The panel's own inset under its content, for what is not a list (Aris's: 12 clear of the lower shoulder).
    static let panelBottomInset: CGFloat = 31 + 12

    /// How far a list directly under the header reaches up behind it (to where the mask is clear).
    static let listRise: CGFloat = listTop - fadeTopClear

    /// One stop of the list's mask: how far down its own frame (0…1) and how much of the rows shows.
    struct FadeStop: Equatable {
        let location: Double
        let alpha: Double
    }

    /// The open panel's body ends a shoulder (31) above its frame's lower edge;
    /// below that only the flare toward the screen's edge is inside the outline.
    static let bodyEdgeInset: CGFloat = 31

    /// The mask of a list `height` tall. `underHeader`: its frame starts where the mask is clear (73 down the
    /// panel), so the rows fade over the next 32 as they slide under the header; otherwise the top is whole.
    /// `below`: how much of the frame's end lies under the body's lower edge (31 for a list that runs to the panel's
    /// frame): the 34-point fade ends there, on the edge, so a row is gone where the outline would cut through its
    /// words.
    static func listFade(height: Double, underHeader: Bool, below: Double = 0) -> [FadeStop] {
        guard height > 0 else { return [FadeStop(location: 0, alpha: 1), FadeStop(location: 1, alpha: 1)] }
        let gone = min(1, max(0, 1 - max(0, below) / height))
        let bottom = max(0, gone - Double(fadeBottom) / height)
        let rise = Double(fadeTopWhole - fadeTopClear) / height
        let end = [FadeStop(location: bottom, alpha: 1), FadeStop(location: gone, alpha: 0)] + (gone < 1 ? [FadeStop(location: 1, alpha: 0)] : [])
        guard underHeader, rise < bottom else { return [FadeStop(location: 0, alpha: 1)] + end }
        return [FadeStop(location: 0, alpha: 0), FadeStop(location: rise, alpha: 1)] + end
    }

    /// The empty list's line: 12 / 1.45 at .52, centred, 28 above, 18 beside, 30 below.
    static let emptySize: CGFloat = 12
    static let emptyAlpha = 0.52
    static let emptyInsets = (top: CGFloat(28), side: CGFloat(18), bottom: CGFloat(30))

    /// The search field: 15 on a 22 line at .95; its placeholder and glyph rgba(236, 239, 247, .62) at
    /// weight 450, tracked 0.2.
    static let searchSize: CGFloat = 15
    static let searchLine: CGFloat = 22
    static let searchAlpha = 0.95
    static let searchPlaceholderTracking: CGFloat = 0.2
}
