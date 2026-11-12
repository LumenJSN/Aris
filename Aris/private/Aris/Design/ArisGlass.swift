//
//  ArisGlass.swift
//  Aris
//
//  The notch's material: AppKit's Liquid Glass tinted sRGB(0, 0, .02, .18) in every state but hidden,
//  under a black that is full from the top (where it meets the camera housing) to 53 % and thins to half at the
//  lower edge, a soft drop shadow and a faint cool rim. Which glass and which black is the look's (ArisGlassLook: the
//  shipped one is private-glass, drawn by ArisNotchGlass; where this macOS lacks a private part, clear-glass).
//  With macOS's Reduce Transparency the notch is solid black, with no glass.
//

import AppKit
import SwiftUI

enum ArisGlass {
    /// What tints the glass: sRGB(0, 0, .02) at .18.
    static let tint = Color(.sRGB, red: 0, green: 0, blue: ArisGlassRecipe.tintBlue, opacity: ArisGlassRecipe.tintAlpha)
    /// rgba(235, 245, 255, 0.22) at 0.9 pt: the rim.
    static let rim = Color(.sRGB, red: 235.0 / 255, green: 245.0 / 255, blue: 1, opacity: 0.22)
    static let text = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.5)

    /// The input row: white 6%, radius 19, inset 12 from the edge (so the panel's corners are 19 + 12).
    static let composerFill = Color.white.opacity(0.06)
    static let pillRadius: CGFloat = 19
    static let inset: CGFloat = 12
    /// One line for everything inside the inset: the band's mark and buttons, the tags' icons, your words and the answer.
    static let textInset: CGFloat = 16
    static let cornerRadius: CGFloat = pillRadius + inset
    /// The open notch's inset under its content.
    static let bottomInset: CGFloat = 8
    /// Your words above the answer: white 7% (9% while it's live).
    static let promptFill = Color.white.opacity(0.07)
    static let promptFillActive = Color.white.opacity(0.09)
    /// The open top notch's body (its shoulders add a corner radius each side).
    static let bodyWidth: CGFloat = 440
    /// What's inside the body's 12-point inset.
    static let contentWidth: CGFloat = bodyWidth - 2 * inset
    /// Claude's cards (diffs, questions) get more room.
    static let claudeWidth: CGFloat = 540
    /// Side panels: 232 × 580, shoulders 31.
    static let sideSize = CGSize(width: 232, height: 580)
    static let sideShoulder: CGFloat = 31

    /// Size changes: 340 ms, ease-in-out (0.45, 0, 0.55, 1). Opening: 280 ms (0.2, 0.8, 0.2, 1).
    static let resize = Animation.timingCurve(0.45, 0, 0.55, 1, duration: 0.34)
    static let opening = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    /// Side notches: open 280 ms (0.2, 0.8, 0.2, 1), close 200 ms
    /// (0.45, 0, 0.55, 1); the sliver appears and goes in 180 ms (0.4, 0, 0.2, 1).
    static let sideOpening = opening
    static let sideClosing = Animation.timingCurve(0.45, 0, 0.55, 1, duration: 0.2)
    static let sliverVisibility = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.18)
}

/// The glass behind the notch. `open` and `hidden` are the notch's state; which glass and which black is the look's
/// (ArisGlassLook, a hidden preference read each time the notch opens; unset, the shipped one).
struct ArisGlassSurface: View {
    let shape: NotchShape
    let open: Bool
    /// The notch is hidden (a full-screen app): the deep-black looks draw no glass then, only the black.
    var hidden = false
    /// Side panels fade toward the screen edge they hang from, not downward.
    var fade: (start: UnitPoint, end: UnitPoint) = (.top, .bottom)
    /// Side panels: an even dark wash over the glass instead of the fade (rgba(0, 0, 6, x)).
    var wash: Double?
    /// The display's safe-area top (0 without a camera housing): the black spans at least this / 0.53.
    var safeTop: CGFloat = 0
    /// The outline's body for the public AppKit glass: how far in from each side it starts and its bottom corners.
    var glassBody: (inset: CGFloat, corner: CGFloat) = (0, 0)
    /// macOS's Reduce Transparency: solid black, and no glass is drawn at all.
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var chosen = ArisGlassLook.current()
    @ObservedObject private var health = ArisGlassHealth.shared

    /// The look as drawn on this macOS: private-glass only while every private part took, else clear-glass.
    private var look: ArisGlassLook { chosen.resolved(health.parts) }

    var body: some View {
        Group {
            if #available(macOS 26.0, *), look.usesPrivateParts, wash == nil, !reduceTransparency {
                privateGlassStack
            } else {
                drawn
            }
        }
        // The look is read as the notch opens, so a changed preference shows the next time it opens.
        .onChange(of: open) { _, opened in
            if opened { chosen = ArisGlassLook.current() }
        }
    }

    /// The private stack (ArisNotchGlass): AppKit's glass with the outline as its path, the black and the shadow, in
    /// one view that fills the notch window's area, hung from the surface's top centre. The surface's size and corner
    /// radii reach it as animatable data, so every frame of an open, a close or a growth redraws all three together.
    @available(macOS 26.0, *)
    private var privateGlassStack: some View {
        GeometryReader { proxy in
            ArisNotchGlass(sample: ArisNotchGlassSample(width: proxy.size.width, height: proxy.size.height, top: shape.topCornerRadius,
                                                        bottom: shape.bottomCornerRadius, openness: open ? 1 : 0),
                           safeTop: safeTop, active: look.showsGlass(open: open, hidden: hidden, reduceTransparency: reduceTransparency))
                .frame(width: windowSize.width, height: windowSize.height)
                .position(x: proxy.size.width / 2, y: windowSize.height / 2)
                .allowsHitTesting(false)
        }
        // On the notch's own clock (280 ms out, 200 ms in), as the content is.
        .animation(open ? StandardAnimations.open : StandardAnimations.close, value: open)
    }

    /// Every other look, and Reduce Transparency: SwiftUI's glass (or none) under the look's black.
    private var drawn: some View {
        ZStack {
            if !reduceTransparency {
                glass.opacity(look.showsGlass(open: open, hidden: hidden, reduceTransparency: reduceTransparency) ? 1 : 0)
            }
            if let wash {
                shape.fill(Color(.sRGB, red: 0, green: 0, blue: 6.0 / 255, opacity: reduceTransparency ? 1 : wash))
            } else {
                // The black over the glass: its stops depend on the look and the height (ArisGlassLook; the deep
                // black is full to 53 % and half at the bottom edge in every state).
                GeometryReader { proxy in
                    let along = fade.start.y == fade.end.y ? proxy.size.width : proxy.size.height
                    // The deep-black looks run the gradient past a short notch's edge (its span rule); the others
                    // end on it.
                    let reach = along > 0 ? look.span(height: along, safeTop: safeTop) / along : 1
                    let black = Color(.sRGB, red: 0, green: 0, blue: look.blackBlue, opacity: 1)
                    LinearGradient(stops: look.stops(height: along, safeTop: safeTop, open: open, glass: !reduceTransparency).map {
                        .init(color: black.opacity($0.alpha), location: $0.location)
                    }, startPoint: fade.start, endPoint: UnitPoint(x: fade.start.x + (fade.end.x - fade.start.x) * reach,
                                                                  y: fade.start.y + (fade.end.y - fade.start.y) * reach))
                }
                .clipShape(shape)
            }
        }
        .compositingGroup()
        .shadow(color: open ? ArisGlass.rim : .clear, radius: 0.9)
        .shadow(color: .black.opacity(open ? 0.28 : 0.25), radius: open ? 12 : 6, y: open ? 5 : 2)
        // On the notch's own clock (280 ms out, 200 ms in): on a slower curve the content arrived over
        // bare wallpaper before the glass behind it.
        .animation(open ? StandardAnimations.open : StandardAnimations.close, value: open)
    }

    private var tint: Color { Color(.sRGB, red: 0, green: 0, blue: look.tintBlue, opacity: look.tintAlpha) }

    @ViewBuilder
    private var glass: some View {
        if #available(macOS 26.0, *) {
            if look.regularMaterial {
                // The comparison look `regularGlass`: AppKit's regular glass with public API only (ArisNativeGlass).
                ArisNativeGlass(tint: NSColor(srgbRed: 0, green: 0, blue: look.tintBlue, alpha: look.tintAlpha),
                                inset: glassBody.inset, corner: glassBody.corner)
                    .id(look)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            } else {
                // The public clear glass in the outline: what private-glass falls back to, and Aris's older looks.
                Color.clear.glassEffect(.clear.tint(tint), in: shape)
            }
        } else {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(tint)
                .clipShape(shape)
        }
    }
}

/// A side notch's outline: flush against the screen edge, a concave elliptical shoulder top and bottom where it
/// meets the edge, and rounded inner corners. The same 44 points (four arcs of 10 samples, and four more) are the
/// hidden state (width 0), the 16-point sliver
/// (shoulders 4, corners 12, the shoulders 1.5× taller) and the open 232 × 580 panel (shoulders and corners 31), so
/// going between them is each point sliding to its place.
enum ArisSideOutline {
    static let sliverWidth: CGFloat = 16
    static let sliverHoverWidth: CGFloat = 18
    static let sliverShoulder: CGFloat = 4
    /// Samples per arc (ArisSideLook.arcSamples; the tests hold the two equal).
    static let samples = 10

    struct Spec: Equatable {
        var width: CGFloat
        var height: CGFloat
        var shoulder: CGFloat
        var corner: CGFloat
        /// Distance from the panel frame's top to the outline's top.
        var top: CGFloat
        /// The shoulders and corners keep their height when the outline has no width (12 and 31), so the
        /// outline narrows into nothing as a rounded sliver, never a bare rectangle. Nil: from the widths.
        var shoulderY: CGFloat? = nil
        var cornerY: CGFloat? = nil

        /// Gone: no width, the vertical rounding kept.
        static func hidden(height: CGFloat, top: CGFloat) -> Spec {
            Spec(width: 0, height: height, shoulder: 0, corner: 0, top: top,
                 shoulderY: min(12, height / 4), cornerY: ArisGlass.sideShoulder)
        }
    }

    /// For the left edge, x from the screen edge and y down from the panel frame's top.
    static func points(_ spec: Spec) -> [CGPoint] {
        let w = max(0, spec.width), h = max(0, spec.height), s = max(0, spec.shoulder), rx = max(0, spec.corner), t = spec.top
        let sy = spec.shoulderY ?? (w <= sliverHoverWidth ? s * 1.5 : s)
        let ry = max(0, min(spec.cornerY ?? rx, h / 2 - sy))
        var points: [CGPoint] = [CGPoint(x: 0, y: t)]
        for i in 1...samples {
            let a = .pi - Double(i) / Double(samples) * (.pi / 2)
            points.append(CGPoint(x: s + s * cos(a), y: t + sy * sin(a)))
        }
        points.append(CGPoint(x: w - rx, y: t + sy))
        for i in 1...samples {
            let a = -.pi / 2 + Double(i) / Double(samples) * (.pi / 2)
            points.append(CGPoint(x: w - rx + rx * cos(a), y: t + sy + ry + ry * sin(a)))
        }
        points.append(CGPoint(x: w, y: t + h - (sy + ry)))
        for i in 1...samples {
            let a = Double(i) / Double(samples) * (.pi / 2)
            points.append(CGPoint(x: w - rx + rx * cos(a), y: t + h - (sy + ry - ry * sin(a))))
        }
        points.append(CGPoint(x: s, y: t + h - sy))
        for i in 1...samples {
            let a = -.pi / 2 - Double(i) / Double(samples) * (.pi / 2)
            points.append(CGPoint(x: s + s * cos(a), y: t + h + sy * sin(a)))
        }
        return points
    }

    /// The outline as a path in `place`'s coordinates (map each left-edge, y-down point).
    static func path(_ spec: Spec, place: (CGPoint) -> CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points(spec).map(place))
        path.closeSubpath()
        return path
    }
}

/// A key drawn inline on dark: white 12%, a hairline, rounded 8, 10-point
/// semibold at 70%.
struct ArisKeycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.02), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }
}
