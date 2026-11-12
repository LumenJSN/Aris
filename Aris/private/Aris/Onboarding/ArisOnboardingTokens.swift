//
//  ArisOnboardingTokens.swift
//  Aris
//
//  The onboarding's look (mockups/onboarding2/css), with Aris's star gold where the mockup tints them: the setup
//  window's light and dark palettes, the dark glass pill (시작하기, 280 × 68), the glass rect button (r14 h44) in its
//  light and dark variants, the back button, the quiet text button.
//

import SwiftUI

enum ArisOBColor {
    static func hex(_ rgb: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double(rgb >> 16 & 0xff) / 255, green: Double(rgb >> 8 & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: alpha)
    }

    /// An 8-digit CSS colour, #rrggbbaa.
    static func hexa(_ rgba: UInt32) -> Color { hex(rgba >> 8, Double(rgba & 0xff) / 255) }

    /// Aris's star, #EFDB8E (the Bot Avatars star's own body colour).
    static let star = hex(0xefdb8e)
    static let blue = hex(0x126ff6)
    /// macOS's accent in the previews.
    static let macBlue = hex(0x0a84ff)
}

/// The setup window's palette (window.css .appwin and [data-theme="dark"]).
struct ArisSetupPalette {
    let dark: Bool

    var background: AnyShapeStyle {
        dark ? AnyShapeStyle(LinearGradient(colors: [ArisOBColor.hex(0x18191d), ArisOBColor.hex(0x16171a)], startPoint: .top, endPoint: .bottom))
            : AnyShapeStyle(Color.white)
    }
    var fg: Color { dark ? ArisOBColor.hex(0xf3f4f6) : ArisOBColor.hex(0x171717) }
    /// gray-900 / gray-500 / gray-600 / gray-800 (light); gray-100 / gray-400 (dark).
    var t1: Color { dark ? ArisOBColor.hex(0xf3f4f6) : ArisOBColor.hex(0x101828) }
    var t2: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x6a7282) }
    var t3: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x4a5565) }
    var t4: Color { dark ? ArisOBColor.hex(0xe5e7eb) : ArisOBColor.hex(0x1e2939) }
    var lead: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x364153) }
    var card: Color { dark ? ArisOBColor.hex(0x222327) : .white }
    var cardLine: Color { dark ? ArisOBColor.hexa(0xdfe2e80f) : ArisOBColor.hex(0xf3f4f6) }
    var tile: Color { dark ? ArisOBColor.hex(0x222327) : .white }
    var tileLine: Color { dark ? ArisOBColor.hexa(0xdfe2e812) : ArisOBColor.hex(0xe5e7eb) }
    var well: Color { dark ? ArisOBColor.hex(0x1f2024) : ArisOBColor.hex(0xf9fafb) }
    var wellLine: Color { dark ? ArisOBColor.hexa(0xdfe2e80f) : ArisOBColor.hex(0xf3f4f6) }
    var stage: Color { dark ? ArisOBColor.hex(0x1b1c1f) : ArisOBColor.hex(0xe5e7eb) }
    var imageLine: Color { dark ? ArisOBColor.hexa(0xdfe2e812) : ArisOBColor.hex(0xe5e7eb) }
    var back: Color { dark ? ArisOBColor.hexa(0xffffff0e) : ArisOBColor.hex(0xeceef1) }
    var backInk: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x687082) }
    var backHover: Color { dark ? ArisOBColor.hexa(0xffffff1f) : ArisOBColor.hex(0xe2e5e9) }
    var backHoverInk: Color { dark ? ArisOBColor.hex(0xe5e7eb) : ArisOBColor.hex(0x414958) }
    var backActive: Color { dark ? ArisOBColor.hexa(0xffffff26) : ArisOBColor.hex(0xd9dde2) }
    var track: [Gradient.Stop] {
        dark ? [.init(color: ArisOBColor.hexa(0xffffff12), location: 0), .init(color: ArisOBColor.hexa(0xffffff0a), location: 0.54), .init(color: ArisOBColor.hexa(0xffffff10), location: 1)]
            : [.init(color: ArisOBColor.hex(0xfbfcfd), location: 0), .init(color: ArisOBColor.hex(0xeceef1), location: 0.54), .init(color: ArisOBColor.hex(0xf6f7f8), location: 1)]
    }
    /// The bottom glow strip, h-32: rgba(12,140,233,.15) → .05 at 50% → none (dark .08 / .025).
    var glow: [Gradient.Stop] {
        let a = dark ? 0.08 : 0.15, b = dark ? 0.025 : 0.05
        return [.init(color: ArisOBColor.hex(0x0c8ce9, a), location: 0), .init(color: ArisOBColor.hex(0x0c8ce9, b), location: 0.5), .init(color: .clear, location: 1)]
    }
    var key: Color { dark ? ArisOBColor.hex(0x222327) : .white }
    var keyLine: Color { dark ? ArisOBColor.hexa(0xdfe2e82e) : ArisOBColor.hex(0xcccccc) }
    var keyInk: Color { dark ? ArisOBColor.hex(0xf3f4f6) : ArisOBColor.hex(0x333333) }
    var keySub: Color { dark ? ArisOBColor.hex(0x99a1af) : ArisOBColor.hex(0x666666) }
    /// Keycaps while held: blue-100 / blue-300.
    var keyOn: Color { dark ? ArisOBColor.hex(0x126ff6, 0.28) : ArisOBColor.hex(0xdbeafe) }
    var keyOnLine: Color { dark ? ArisOBColor.hex(0x126ff6) : ArisOBColor.hex(0x93c5fd) }
    var practice: Color { dark ? ArisOBColor.hex(0x1f2024) : ArisOBColor.hex(0xf5f5f7) }
    var windowLine: Color { dark ? .white.opacity(0.12) : .black.opacity(0.22) }
}

enum ArisOBCurve {
    /// Framer's house ease (.22, 1, .36, 1).
    static func settle(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
    /// The cards' and pages' clock: .3 s ease-in-out.
    static let card = Animation.easeInOut(duration: 0.3)
    /// The window's entrance: scale 1.3 → 1 over 920 ms (.16, 1, .3, 1).
    static let handoff = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.92)
    /// The check: grows over 350 ms (.4, 0, .2, 1).
    static let checkGrow = Animation.timingCurve(0.4, 0, 0.2, 1, duration: 0.35)
    /// Reduce Motion: a short cross-fade.
    static let fade = Animation.easeInOut(duration: 0.15)
}

// MARK: - Buttons

/// The intro's dark glass pill tinted to starlight: 280 × 68, a radial and −75° sheen body, inset highlights, a warm
/// conic rim masked to 1 pt turning once every 14 s (the only motion while the intro waits), a caustic sheen; hover
/// .975, press .96.
struct ArisGlassPill: View {
    let title: String
    var turning = true
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .regular, design: .default))
                .tracking(-0.18)
                .foregroundStyle(ArisOBColor.hexa(0xfffaf0f5))
                .shadow(color: ArisOBColor.hexa(0xf7dc8a1f), radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 24)
                .frame(width: 280, height: 68)
                .background { ArisGlassPillBody(turning: turning) }
                .contentShape(Capsule())
        }
        .buttonStyle(ArisGlassPress(hoverScale: 0.975, pressScale: 0.96, hover: hover))
        .onHover { hover = $0 }
    }
}

private struct ArisGlassPillBody: View {
    let turning: Bool

    var body: some View {
        let shape = Capsule()
        ZStack {
            shape.fill(RadialGradient(stops: [.init(color: ArisOBColor.hexa(0xffffff22), location: 0), .init(color: ArisOBColor.hexa(0xf4ecdc14), location: 0.45),
                                              .init(color: ArisOBColor.hexa(0xf4ecdc09), location: 0.72)],
                                      center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 190))
            shape.fill(LinearGradient(colors: [ArisOBColor.hexa(0xfff5e60d), ArisOBColor.hexa(0xffffff1b), ArisOBColor.hexa(0xfff5e60d)],
                                      startPoint: UnitPoint(x: 0.13, y: 0), endPoint: UnitPoint(x: 0.87, y: 1)))
            // inset 0 0 1.6 4 warm, inset 0 2 2 dark on top, inset 0 −2 2 light under.
            shape.stroke(ArisOBColor.hexa(0xebdcb51f), lineWidth: 8).blur(radius: 1.6).clipShape(shape)
            shape.stroke(LinearGradient(colors: [.black.opacity(0.05), .clear, ArisOBColor.hexa(0xf6ecd84d)], startPoint: .top, endPoint: .bottom), lineWidth: 4)
                .blur(radius: 1).clipShape(shape)
            ArisGlassRim(shape: shape, turning: turning,
                         dark: ArisOBColor.hexa(0x1a160c80), light: ArisOBColor.hexa(0xf3e3b81a),
                         top: ArisOBColor.hexa(0xefe2c25c), bottom: ArisOBColor.hexa(0xfbf3e05e), inner: ArisOBColor.hexa(0xf2e3bd47))
            // The caustic sheen, in screen blend.
            shape.fill(LinearGradient(stops: [.init(color: .clear, location: 0.1), .init(color: ArisOBColor.hexa(0xf5e7c22e), location: 0.3),
                                              .init(color: ArisOBColor.hexa(0xf5e7c22e), location: 0.36), .init(color: .clear, location: 0.42)],
                                      startPoint: .topTrailing, endPoint: .bottomLeading))
                .blendMode(.screen)
        }
        .shadow(color: ArisOBColor.hexa(0x1e1e1e26), radius: 1, y: 3)
    }
}

/// A conic rim (two dark and two light lobes) over a vertical gradient, masked to a 1-pt ring.
struct ArisGlassRim<S: InsettableShape>: View {
    let shape: S
    let turning: Bool
    let dark: Color
    let light: Color
    let top: Color
    let bottom: Color
    let inner: Color
    /// Fixed angle when not turning (−75°; hover turns it to −125°).
    var angle: Double = -75

    var body: some View {
        if turning {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                rim(angle + context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 14) / 14 * 360)
            }
        } else {
            rim(angle)
        }
    }

    private func rim(_ degrees: Double) -> some View {
        ZStack {
            shape.strokeBorder(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            shape.strokeBorder(AngularGradient(stops: [.init(color: dark, location: 0), .init(color: light, location: 0.05), .init(color: light, location: 0.4),
                                                       .init(color: dark, location: 0.5), .init(color: light, location: 0.6), .init(color: light, location: 0.95),
                                                       .init(color: dark, location: 1)],
                                               center: .center, angle: .degrees(degrees - 90)), lineWidth: 1)
            shape.strokeBorder(inner, lineWidth: 0.5)
        }
    }
}

/// Hover and press scales on the glass's own curve (.25, 1, .5, 1), .4 s.
struct ArisGlassPress: ButtonStyle {
    var hoverScale: CGFloat
    var pressScale: CGFloat
    var hover: Bool
    var held = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed || held ? pressScale : hover ? hoverScale : 1)
            .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.4), value: configuration.isPressed || held)
            .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.4), value: hover)
    }
}

/// The glass rect button: r14, h44, min-w 100, padding 0 20, label 16/400,
/// −.18; light and dark variants; hover .98, press .97; disabled .5.
struct ArisGlassRect: View {
    let title: String
    var held = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .tracking(-0.18)
                .foregroundStyle(dark ? ArisOBColor.hexa(0xf4f9fff5) : ArisOBColor.hex(0x323232))
                .shadow(color: dark ? ArisOBColor.hexa(0x8bc4fa1f) : .black.opacity(0.05), radius: dark ? 6 : 0.4, y: dark ? 0 : 0.8)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 20)
                .frame(minWidth: 100, minHeight: 44)
                .background { ArisGlassRectBody(dark: dark, hover: hover) }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ArisGlassPress(hoverScale: 0.98, pressScale: 0.97, hover: hover, held: held))
        .opacity(enabled ? 1 : 0.5)
        .onHover { hover = $0 }
    }
}

private struct ArisGlassRectBody: View {
    let dark: Bool
    let hover: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            if dark {
                shape.fill(RadialGradient(stops: [.init(color: ArisOBColor.hexa(0xffffff22), location: 0), .init(color: ArisOBColor.hexa(0xe4f0fc14), location: 0.45),
                                                  .init(color: ArisOBColor.hexa(0xe4f0fc09), location: 0.72)],
                                          center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 90))
                shape.fill(LinearGradient(colors: [ArisOBColor.hexa(0xe6f5ff0d), ArisOBColor.hexa(0xffffff1b), ArisOBColor.hexa(0xe6f5ff0d)],
                                          startPoint: UnitPoint(x: 0.13, y: 0), endPoint: UnitPoint(x: 0.87, y: 1)))
            } else {
                shape.fill(.white)
                shape.fill(LinearGradient(colors: [ArisOBColor.hexa(0xe6f5ff14), ArisOBColor.hexa(0xffffff33), ArisOBColor.hexa(0xe6f5ff14)],
                                          startPoint: UnitPoint(x: 0.13, y: 0), endPoint: UnitPoint(x: 0.87, y: 1)))
            }
            shape.stroke(dark ? ArisOBColor.hexa(0xaacdeb1f) : ArisOBColor.hexa(0xd2ebff33), lineWidth: 8).blur(radius: hover ? 0.8 : 1.6).clipShape(shape)
            shape.stroke(LinearGradient(colors: [.black.opacity(0.05), .clear, dark ? ArisOBColor.hexa(0xe0f0fc4d) : ArisOBColor.hexa(0xffffff80)],
                                        startPoint: .top, endPoint: .bottom), lineWidth: 4).blur(radius: 1).clipShape(shape)
            if dark {
                ArisGlassRim(shape: shape, turning: false, dark: ArisOBColor.hexa(0x10224475), light: ArisOBColor.hexa(0x87b9e60e),
                             top: ArisOBColor.hexa(0xb4d2ec4d), bottom: ArisOBColor.hexa(0xe1f0fc52), inner: ArisOBColor.hexa(0xb2d6f247), angle: hover ? -125 : -75)
            } else {
                ArisGlassRim(shape: shape, turning: false, dark: ArisOBColor.hexa(0x14285080), light: ArisOBColor.hexa(0x96c8ff14),
                             top: ArisOBColor.hexa(0xdcf0ff80), bottom: ArisOBColor.hexa(0xffffff80), inner: ArisOBColor.hexa(0xdcf0ff80), angle: hover ? -125 : -75)
            }
            shape.fill(LinearGradient(stops: [.init(color: .clear, location: hover ? 0.3 : 0.1), .init(color: dark ? ArisOBColor.hexa(0xdaecfa2e) : ArisOBColor.hexa(0xe6f5ff80), location: hover ? 0.5 : 0.3),
                                              .init(color: dark ? ArisOBColor.hexa(0xdaecfa2e) : ArisOBColor.hexa(0xe6f5ff80), location: hover ? 0.56 : 0.36),
                                              .init(color: .clear, location: hover ? 0.62 : 0.42)],
                                      startPoint: .topTrailing, endPoint: .bottomLeading))
                .blendMode(.screen)
                .animation(.timingCurve(0.25, 1, 0.5, 1, duration: 0.5), value: hover)
        }
        .shadow(color: dark ? .clear : ArisOBColor.hexa(0x1e1e1e26), radius: 1, y: 3)
    }
}

/// .onboarding-back-button: min-w 72, h 38, r11, padding 0 16, 13/600 −.01em, 160 ms.
struct ArisBackButtonStyle: ButtonStyle {
    let palette: ArisSetupPalette

    func makeBody(configuration: Configuration) -> some View {
        ArisBackLabel(configuration: configuration, palette: palette)
    }
}

private struct ArisBackLabel: View {
    let configuration: ButtonStyleConfiguration
    let palette: ArisSetupPalette
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .tracking(-0.13)
            .foregroundStyle(hover ? palette.backHoverInk : palette.backInk)
            .padding(.horizontal, 16)
            .frame(minWidth: 72, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(configuration.isPressed ? palette.backActive : hover ? palette.backHover : palette.back))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.16), value: hover)
    }
}

/// A secondary text action: 14 medium, gray-500, gray-900 on hover.
struct ArisQuietButtonStyle: ButtonStyle {
    let palette: ArisSetupPalette
    var size: CGFloat = 14
    var weight: Font.Weight = .medium

    func makeBody(configuration: Configuration) -> some View {
        ArisQuietLabel(configuration: configuration, palette: palette, size: size, weight: weight)
    }
}

private struct ArisQuietLabel: View {
    let configuration: ButtonStyleConfiguration
    let palette: ArisSetupPalette
    let size: CGFloat
    let weight: Font.Weight
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: size, weight: weight))
            .foregroundStyle(hover ? palette.t1 : palette.t2)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Offscreen renders

private struct ArisOnboardingStillKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The offscreen renders draw a still frame: entrances settled, text fields as their text (ImageRenderer can't
    /// draw AppKit's field editor).
    var arisOnboardingStill: Bool {
        get { self[ArisOnboardingStillKey.self] }
        set { self[ArisOnboardingStillKey.self] = newValue }
    }
}

private struct ArisOnboardingPreviewTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// The offscreen renders pin the permission preview's loop at this time (ms).
    var arisOnboardingPreviewTime: Double? {
        get { self[ArisOnboardingPreviewTimeKey.self] }
        set { self[ArisOnboardingPreviewTimeKey.self] = newValue }
    }
}
