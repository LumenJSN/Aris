//
//  ArisNoticeSurface.swift
//  Aris
//
//  What a notification card is made of, with the measured values. On macOS 26, with every private part of the notch's
//  glass taking (ArisGlassFallback), it is AppKit's own Liquid Glass per card: regular style, radius 22, the notch's
//  private variant and lensing, under a thin skin (a fill, a hairline rim, a light top edge). It follows the system's
//  appearance as measured, live: dark, a tint sRGB(.055, .055, .065) at .2 and white text; light, a white tint at
//  .06 and dark text, with the light skin, buttons and close circle. With Reduce Transparency the glass card is solid
//  (#2C2C2E dark, #E8EDF2 light). Anywhere else (older macOS, a private part missing) it is an opaque dark gradient,
//  165° from (46, 46, 52) to (20, 20, 24), with white text in either appearance. The peeking layers behind the front
//  card are the same colours, solid (never a glass view: ArisNoticeFill), only their bottom band showing.
//

import AppKit
import SwiftUI

/// Which surface the cards have.
enum ArisNoticeMaterial: Equatable {
    case glass
    case opaque

    /// Glass only where AppKit's glass exists and every private part took (Reduce Transparency makes the glass card
    /// solid, ArisNoticePalette.solid; it is still the glass card's colours).
    static func choose(glassView: Bool, privateGlass: Bool) -> ArisNoticeMaterial {
        glassView && privateGlass ? .glass : .opaque
    }
}

/// Every colour a card takes from its appearance: the glass card dark or light, and the opaque card (always dark).
struct ArisNoticePalette {
    var light: Bool
    var title: Color
    var body: Color
    var subtitle: Color
    var snippet: Color
    /// The glass's own tint (sRGB components and alpha).
    var tint: (red: Double, green: Double, blue: Double, alpha: Double)
    var skin: Color
    var rim: Color
    var topEdge: Color
    var lowEdge: Color
    /// The glass card with Reduce Transparency, and its rim.
    var solid: Color
    var solidRim: Color
    var secondaryFill: Color
    var secondaryText: Color
    var secondaryRing: Color
    var closeFill: Color
    var closeHover: Color
    var closeGlyph: Color
    var closeRing: Color
    var moreFill: Color
    var moreText: Color
    var moreRim: Color
    /// The front card's shadow alone and with layers under it.
    var shadowAlone: Double
    var shadowStacked: Double

    private static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    static let dark = ArisNoticePalette(
        light: false, title: .white.opacity(ArisNoticeLayout.titleOpacity), body: .white.opacity(ArisNoticeLayout.bodyOpacity),
        subtitle: .white.opacity(ArisNoticeLayout.subtitleOpacity), snippet: .white.opacity(ArisNoticeLayout.snippetOpacity),
        tint: (0.055, 0.055, 0.065, 0.2), skin: rgb(18, 18, 20, 0.16), rim: .white.opacity(0.24), topEdge: .white.opacity(0.22),
        lowEdge: .black.opacity(0.3), solid: rgb(44, 44, 46, 1), solidRim: .white.opacity(0.2),
        secondaryFill: rgb(58, 58, 64, 1), secondaryText: .white.opacity(0.92), secondaryRing: .white.opacity(0.14),
        closeFill: rgb(86, 86, 92, 0.76), closeHover: rgb(104, 104, 110, 0.86), closeGlyph: .white.opacity(0.9), closeRing: .white.opacity(0.2),
        moreFill: rgb(44, 44, 48, 0.72), moreText: .white.opacity(0.66), moreRim: .white.opacity(0.16),
        shadowAlone: 0.28, shadowStacked: 0.2)

    static let light = ArisNoticePalette(
        light: true, title: rgb(24, 31, 39, 0.96), body: rgb(38, 47, 57, 0.68), subtitle: rgb(38, 47, 57, 0.68), snippet: rgb(38, 47, 57, 0.76),
        tint: (1, 1, 1, 0.06), skin: .white.opacity(0.1), rim: .white.opacity(0.58), topEdge: .white.opacity(0.52),
        lowEdge: rgb(70, 82, 96, 0.12), solid: rgb(232, 237, 242, 1), solidRim: .white.opacity(0.72),
        secondaryFill: .white.opacity(0.34), secondaryText: rgb(24, 31, 39, 0.92), secondaryRing: .white.opacity(0.5),
        closeFill: rgb(239, 244, 248, 0.72), closeHover: rgb(246, 249, 252, 0.86), closeGlyph: rgb(24, 31, 39, 0.82), closeRing: .white.opacity(0.68),
        moreFill: .white.opacity(0.34), moreText: rgb(24, 31, 39, 0.62), moreRim: .white.opacity(0.5),
        shadowAlone: 0.14, shadowStacked: 0.08)

    /// The opaque card: the dark gradient and white text whatever the appearance.
    static let opaque: ArisNoticePalette = {
        var palette = dark
        palette.rim = .white.opacity(0.06)
        palette.topEdge = .white.opacity(0.1)
        palette.moreFill = rgb(28, 28, 32, 0.99)
        palette.moreText = .white.opacity(0.62)
        palette.moreRim = .white.opacity(0.06)
        return palette
    }()

    /// The palette for `material` in the system's `scheme`.
    static func of(_ material: ArisNoticeMaterial, _ scheme: ColorScheme) -> ArisNoticePalette {
        material == .opaque ? opaque : scheme == .light ? light : dark
    }
}

enum ArisNoticeLook {
    /// The opaque card: three stops at 0, 52 and 100 %.
    static let opaqueStops: [Gradient.Stop] = [
        .init(color: Color(.sRGB, red: 46.0 / 255, green: 46.0 / 255, blue: 52.0 / 255, opacity: 0.985), location: 0),
        .init(color: Color(.sRGB, red: 28.0 / 255, green: 28.0 / 255, blue: 32.0 / 255, opacity: 0.99), location: 0.52),
        .init(color: Color(.sRGB, red: 20.0 / 255, green: 20.0 / 255, blue: 24.0 / 255, opacity: 0.995), location: 1),
    ]
    /// 165°: down and a little to the right.
    static let opaqueStart = UnitPoint(x: 0.371, y: 0.017)
    static let opaqueEnd = UnitPoint(x: 0.629, y: 0.983)
    /// The front card's shadow: 0 4 12 alone, 0 1 2 with layers under it.
    static func shadow(stacked: Bool, _ palette: ArisNoticePalette) -> (radius: CGFloat, y: CGFloat, opacity: Double) {
        stacked ? (1, 1, palette.shadowStacked) : (6, 4, palette.shadowAlone)
    }
    /// The light line along the card's top, 15 % in from each side: white .22 at its middle.
    static let highlight = Color.white.opacity(0.22)
}

/// The card's material and skin, `stacked`: layers peek under it (a smaller shadow).
struct ArisNoticeSurface: View {
    let material: ArisNoticeMaterial
    var stacked = false
    /// A peeking layer: a hairline shadow.
    var layer = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: ArisNoticeLayout.cornerRadius, style: .continuous) }

    var body: some View {
        let palette = ArisNoticePalette.of(material, scheme)
        let shadow = ArisNoticeLook.shadow(stacked: stacked || layer, palette)
        let fill = ArisNoticeFill.of(glassMaterial: material == .glass, reduceTransparency: reduceTransparency, layer: layer)
        let solid = fill == .solid
        ZStack {
            switch fill {
            case .solid:
                shape.fill(palette.solid)
            case .glass:
                if #available(macOS 26.0, *) { ArisNoticeGlass() }
                shape.fill(palette.skin)
            case .gradient:
                shape.fill(LinearGradient(stops: ArisNoticeLook.opaqueStops, startPoint: ArisNoticeLook.opaqueStart, endPoint: ArisNoticeLook.opaqueEnd))
            }
        }
        .overlay(alignment: .top) {
            // The top edge: a light inner line 1 point high.
            shape.strokeBorder(LinearGradient(colors: [palette.topEdge, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.06)), lineWidth: 1)
        }
        .overlay {
            shape.strokeBorder(solid ? palette.solidRim : palette.rim, lineWidth: 0.5)
        }
        .overlay(alignment: .bottom) {
            if material == .glass {
                shape.strokeBorder(LinearGradient(colors: [.clear, palette.lowEdge], startPoint: UnitPoint(x: 0.5, y: 0.97), endPoint: .bottom),
                                   lineWidth: 0.5)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}
