//
//  ArisIconTile.swift
//  Aris
//
//  The measured app-icon tile (SETTINGS-REA.md §5.2, §6): a squircle of radius
//  round(size × .2237) (36 → 8, 56 → 13, 88 → 20) with a 1-pt ring, a plain, gradient or image fill, and the glass on
//  top (a 152° white sheen .34 → .13 → .02 → 0, a soft radial light at the foot, a white .45 line at the top, a black
//  .1 line at the foot and a white .18 rim inside). Elevated tiles (the detail sheet's 88) cast `0 18 36` black .16 /
//  .5. The glyph is a line icon at size × .46, stroke 2 (1.8 from 96): white with a small shadow on a gradient tile,
//  else black .55 / white .65. Used where the measured window uses it: list rows (36), detail sheets (88); settings
//  rows keep their bare 20-pt glyphs.
//

import SwiftUI

/// What fills a tile.
enum ArisIconTileFill: Equatable {
    /// White .08 (dark) / black .05 (light): a feature's own tile.
    case plain
    /// Top to bottom: a skill's colour, an app's.
    case gradient(top: Color, bottom: Color)
    /// #1d1d1f (dark) / white (light), under an app's logo.
    case image

    /// A gradient from one tint: a lighter top easing into the tint.
    static func tinted(_ hex: UInt32) -> ArisIconTileFill {
        .gradient(top: Color(arisHex: lighter(hex, by: 0.22)), bottom: Color(arisHex: hex))
    }

    /// `hex` moved `share` of the way to white.
    static func lighter(_ hex: UInt32, by share: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let value = Double(hex >> shift & 0xff)
            return UInt32((value + (255 - value) * share).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

struct ArisIconTile<Glyph: View>: View {
    @Environment(\.arisPalette) private var palette
    let size: CGFloat
    var fill = ArisIconTileFill.plain
    var elevated = false
    @ViewBuilder let glyph: () -> Glyph

    static func radius(_ size: CGFloat) -> CGFloat { (size * 0.2237).rounded() }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius(size), style: .continuous)
        let dark = palette.dark
        ZStack {
            shape.fill(fillStyle(dark))
            glyph()
            ArisIconGlass(shape: shape, size: size)
            if case .gradient = fill {
                ArisInsetShade(shape: shape, shadow: .init(y: 1, blur: 0, spread: 0, shade: .init(0xffffff, 0.25), inset: true))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // `0 0 0 1px`: a ring just outside the tile.
        .overlay(shape.inset(by: -0.5).stroke(dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1))
        .compositingGroup()
        .shadow(color: elevated ? .black.opacity(dark ? 0.5 : 0.16) : .clear, radius: elevated ? 18 : 0, y: elevated ? 18 : 0)
        .accessibilityHidden(true)
    }

    private func fillStyle(_ dark: Bool) -> AnyShapeStyle {
        switch fill {
        case .plain: AnyShapeStyle(dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        case .gradient(let top, let bottom): AnyShapeStyle(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
        case .image: AnyShapeStyle(dark ? Color(arisHex: 0x1d1d1f) : .white)
        }
    }
}

extension ArisIconTile where Glyph == ArisIconTileGlyph {
    /// A tile with a line glyph (a feature's, a skill's, Aris's own notch or star).
    init(_ icon: String, size: CGFloat, fill: ArisIconTileFill = .plain, elevated: Bool = false) {
        self.init(size: size, fill: fill, elevated: elevated) { ArisIconTileGlyph(icon: icon, size: size, onGradient: fill.isGradient) }
    }
}

extension ArisIconTileFill {
    var isGradient: Bool { if case .gradient = self { true } else { false } }
}

/// The glyph on a tile: size × .46, stroke 2 (1.8 from 96); white with `drop-shadow(0 1px 1px black .18)` on a
/// gradient, else black .55 / white .65.
struct ArisIconTileGlyph: View {
    @Environment(\.arisPalette) private var palette
    let icon: String
    let size: CGFloat
    let onGradient: Bool

    var body: some View {
        ArisLineIcon(icon, size: size * 0.46, stroke: size >= 96 ? 1.8 : 2)
            .foregroundStyle(onGradient ? Color.white : palette.dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55))
            .shadow(color: onGradient ? .black.opacity(0.18) : .clear, radius: 0.5, y: 1)
    }
}

/// The tile's glass: `linear-gradient(152deg, white .34 0%, .13 20%, .02 36%, 0 50%)`, `radial-gradient(125% 82% at 50%
/// 112%, white .12 0%, 0 62%)`, and three inset lines (white .45 at the top, black .1 at the foot, a white .18 rim).
struct ArisIconGlass<S: InsettableShape>: View {
    let shape: S
    let size: CGFloat

    var body: some View {
        // 152° on a square: the gradient line runs down and to the right, as long as the box's extent along it.
        let angle = 152.0 * Double.pi / 180
        let dx = sin(angle), dy = -cos(angle), half = (abs(dx) + abs(dy)) / 2
        ZStack {
            shape.fill(LinearGradient(stops: [.init(color: .white.opacity(0.34), location: 0), .init(color: .white.opacity(0.13), location: 0.2),
                                              .init(color: .white.opacity(0.02), location: 0.36), .init(color: .white.opacity(0), location: 0.5)],
                                      startPoint: UnitPoint(x: 0.5 - dx * half, y: 0.5 - dy * half), endPoint: UnitPoint(x: 0.5 + dx * half, y: 0.5 + dy * half)))
            // The radial light: an ellipse 125% × 82% of the tile (radii), centred 112% down, fading by 62%.
            EllipticalGradient(colors: [.white.opacity(0.12), .white.opacity(0)], center: .center, startRadiusFraction: 0, endRadiusFraction: 0.62)
                .frame(width: size * 2.5, height: size * 1.64)
                .position(x: size / 2, y: size * 1.12)
                .frame(width: size, height: size)
                .clipShape(shape)
            ArisInsetShade(shape: shape, shadow: .init(y: 1, blur: 0, spread: 0, shade: .init(0xffffff, 0.45), inset: true))
            ArisInsetShade(shape: shape, shadow: .init(y: -1, blur: 0, spread: 0, shade: .init(0x000000, 0.1), inset: true))
            ArisInsetShade(shape: shape, shadow: .init(y: 0, blur: 0, spread: 1, shade: .init(0xffffff, 0.18), inset: true))
        }
        .allowsHitTesting(false)
    }
}

/// A small link to a feature's detail sheet, as the measured card-header link buttons: `px-2.5 py-1.5 rounded-lg`
/// 11 / 500 on the select's gradient and 4% line (8% and darker text under the pointer), with a chevron.
struct ArisFeatureLink: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @Environment(\.arisSettingsHandlers) private var handlers
    let feature: ArisFeature
    @State private var hovering = false

    var body: some View {
        let dark = palette.dark
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Button { handlers.perform(.feature(feature)) } label: {
            HStack(spacing: 3) {
                Text(w("알아보기")).font(.system(size: 11, weight: .medium))
                ArisLineIcon("chevron-right", size: 11, stroke: 2.25)
            }
            .foregroundStyle(hovering ? ArisMenuLook.selectTextHover.color(dark) : ArisMenuLook.selectText.color(dark))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(shape.fill(LinearGradient(colors: [ArisMenuLook.selectFillTop.color(dark), ArisMenuLook.selectFillBottom.color(dark)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(hovering ? ArisMenuLook.selectBorderHover.color(dark) : ArisMenuLook.selectBorder.color(dark), lineWidth: 1))
            .contentShape(shape)
            .animation(ArisSettingsMotion.hover, value: hovering)
        }
        .buttonStyle(ArisPressScale(scale: ArisPressScale.measured))
        .onHover { hovering = $0 }
        .help(w(feature.content.title))
        .accessibilityLabel(w(feature.content.title) + " · " + w("알아보기"))
    }
}
