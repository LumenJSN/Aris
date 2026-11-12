//
//  ArisSettingsTheme.swift
//  Aris
//
//  The settings window's colours, light and dark, and its motion: the values in mockup settings-redesign.html.
//

import AppKit
import SwiftUI

extension Color {
    /// `0xRRGGBB` at `alpha`, in sRGB.
    init(arisHex hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }

    /// "#RRGGBB", or nil.
    init?(arisHexString text: String) {
        let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(arisHex: value)
    }
}

/// The window's palette for one appearance (mockup `.win` / `.win.dark`).
struct ArisPalette {
    let dark: Bool

    private func pick(_ light: Color, _ dark: Color) -> Color { self.dark ? dark : light }
    private func black(_ a: Double) -> Color { .black.opacity(a) }
    private func white(_ a: Double) -> Color { .white.opacity(a) }

    // Text and icons (--ink, --ink2, --ink3, --icon).
    var title: Color { pick(Color(arisHex: 0x101828), Color(arisHex: 0xf3f4f6)) }
    var desc: Color { pick(Color(arisHex: 0x6a7282), Color(arisHex: 0x99a1af)) }
    var ink3: Color { pick(Color(arisHex: 0x99a1af), Color(arisHex: 0x6a7282)) }
    var icon: Color { pick(Color(arisHex: 0x4a5565), Color(arisHex: 0xd1d5dc)) }

    // Sidebar (--navOn, --navIdle, --navHover, --navFill, --groupLbl, --sidebar).
    var navOn: Color { pick(black(0.9), white(0.98)) }
    var navIdle: Color { pick(black(0.5), white(0.6)) }
    var navHover: Color { pick(black(0.7), white(0.8)) }
    var navFill: Color { pick(black(0.04), white(0.04)) }
    var groupLabel: Color { pick(black(0.45), white(0.4)) }
    var sidebarTint: Color { pick(Color(arisHex: 0xeceff4, 0.8), Color(arisHex: 0x1e2128, 0.82)) }

    // Content pane (--wash, --pane, --fade).
    var wash: Color { pick(Color(arisHex: 0xf3f7fe, 0.15), Color(arisHex: 0x242424, 0.15)) }
    var pane: LinearGradient {
        dark ? LinearGradient(colors: [Color(arisHex: 0x18191d), Color(arisHex: 0x16171a)], startPoint: .top, endPoint: .bottom)
            : LinearGradient(stops: [.init(color: Color(arisHex: 0xf4f5f7), location: 0), .init(color: Color(arisHex: 0xf5f6f7), location: 0.48),
                                     .init(color: Color(arisHex: 0xf7f7f7), location: 1)], startPoint: .top, endPoint: .bottom)
    }
    var fade: Color { pick(Color(arisHex: 0xf5f5f5), Color(arisHex: 0x16191f)) }

    // Cards (--card at 165°, --cardBorder, --cardBorderH, --cardShadow).
    var cardFill: AnyShapeStyle {
        dark ? AnyShapeStyle(Color(arisHex: 0x222327))
            : AnyShapeStyle(LinearGradient(colors: [Color(arisHex: 0xfcfcfc), Color(arisHex: 0xf8f8f8)], startPoint: UnitPoint(x: 0.37, y: 0), endPoint: UnitPoint(x: 0.63, y: 1)))
    }
    var cardBorder: Color { pick(.white, Color(arisHex: 0xdfe2e8, 0.06)) }
    var cardBorderHover: Color { pick(black(0.08), Color(arisHex: 0xdfe2e8, 0.18)) }
    /// Dark cards cast `0 1px 6px rgba(0,0,0,.2)`; light ones none.
    var cardShadow: Color { pick(.clear, black(0.2)) }
    var cardTopLight: Color { pick(.clear, Color(arisHex: 0xeff1f5, 0.024)) }

    // Lines and fills (--hair, --rowHover, --swOff, --segTrack, --chip, --well, --tile, --tileRing).
    var hairline: Color { pick(black(0.06), white(0.06)) }
    var rowHover: Color { pick(black(0.038), white(0.055)) }
    var rowSelected: Color { segTrack }
    var switchOff: Color { pick(black(0.12), white(0.15)) }
    var segTrack: Color { pick(black(0.045), white(0.055)) }
    var chip: Color { pick(black(0.055), white(0.09)) }
    var well: Color { pick(black(0.025), white(0.03)) }
    var appTile: Color { pick(black(0.05), white(0.08)) }
    var appTileRing: Color { pick(black(0.08), white(0.1)) }

    // The glass segmented control (--gTrack, --gTrackB, --gInd, --gIndB, --gOn, --gIdle).
    var glassTrack: Color { pick(black(0.04), white(0.05)) }
    var glassTrackBorder: Color { pick(black(0.06), white(0.07)) }
    var glassThumb: LinearGradient {
        LinearGradient(colors: dark ? [white(0.14), white(0.06)] : [white(0.95), white(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var glassThumbBorder: Color { pick(white(0.6), white(0.12)) }
    var glassThumbShadow: Color { pick(black(0.06), black(0.25)) }
    var glassOn: Color { pick(.black, .white) }
    var glassIdle: Color { pick(black(0.38), white(0.42)) }

    // Liquid glass, the sidebar's chosen row (a -75° sheen, inner shades, a conic rim).
    var sheen: LinearGradient {
        let edge = dark ? Color(arisHex: 0x8c96aa, 0.05) : Color(arisHex: 0xe6f5ff, 0.08)
        let middle = dark ? white(0.08) : white(0.2)
        return LinearGradient(colors: [edge, middle, edge], startPoint: UnitPoint(x: 0.13, y: 0.98), endPoint: UnitPoint(x: 0.87, y: 0.02))
    }
    var rim: [Color] {
        dark ? [Color(arisHex: 0x505f78, 0.4), Color(arisHex: 0x96aac8, 0.15), Color(arisHex: 0xb4c8e6, 0.25)]
            : [Color(arisHex: 0x142850, 0.45), Color(arisHex: 0x96c8ff, 0.15), Color(arisHex: 0xb4dcff, 0.3)]
    }

    // Buttons (--ghost*, --primary*).
    var buttonText: Color { pick(Color(arisHex: 0x4a5565), Color(arisHex: 0xd1d5dc)) }
    var buttonTextHover: Color { pick(Color(arisHex: 0x1e2939), Color(arisHex: 0xe5e7eb)) }
    var buttonFill: LinearGradient {
        LinearGradient(colors: dark ? [white(0.05), white(0.01)] : [.white, black(0.015)], startPoint: .top, endPoint: .bottom)
    }
    var buttonBorder: Color { pick(black(0.03), white(0.03)) }
    var buttonBorderHover: Color { pick(black(0.06), white(0.06)) }
    var primary: Color { pick(Color(arisHex: 0x0a0a0a), Color(arisHex: 0xf3f6fa)) }
    var primaryHover: Color { pick(Color(arisHex: 0x1e2939), Color(arisHex: 0xe5e7eb)) }
    var primaryInk: Color { pick(.white, Color(arisHex: 0x0c1118)) }

    // States (--red*, --ok*, --warn, --bad).
    var red: Color { pick(Color(arisHex: 0xdc2626), Color(arisHex: 0xf87171)) }
    var redFill: Color { pick(Color(arisHex: 0xfef2f2), Color(arisHex: 0xef4444, 0.1)) }
    var redFillHover: Color { pick(Color(arisHex: 0xfee2e2), Color(arisHex: 0xef4444, 0.2)) }
    var redBorder: Color { Color(arisHex: 0xef4444, dark ? 0.3 : 0.2) }
    var solidRed: Color { Color(arisHex: 0xdc2626) }
    var ok: Color { pick(Color(arisHex: 0x16a34a), Color(arisHex: 0x4ade80)) }
    var okText: Color { ok }
    var okFill: Color { pick(Color(arisHex: 0xf0fdf4), Color(arisHex: 0x14271c)) }
    var warn: Color { pick(Color(arisHex: 0xd97706), Color(arisHex: 0xfbbf24)) }
    var bad: Color { pick(Color(arisHex: 0xdc2626), Color(arisHex: 0xf87171)) }
    /// AppleSwitch's on colour, both appearances.
    var switchOn: Color { Color(arisHex: 0x30d158) }

    // Fields (--field, --fieldB, --fieldFocus, --fieldRing).
    var field: Color { pick(.white, Color(arisHex: 0x1f2024)) }
    var fieldBorder: Color { pick(Color(arisHex: 0xe5e7eb), Color(arisHex: 0xdfe2e8, 0.067)) }
    var fieldFocus: Color { pick(Color(arisHex: 0x99a1af), Color(arisHex: 0xdfe2e8, 0.13)) }
    var fieldRing: Color { pick(Color(arisHex: 0x99a1af, 0.2), Color(arisHex: 0xdfe2e8, 0.055)) }
    var fieldShadow: Color { pick(black(0.05), black(0.18)) }

    // Menus and sheets (--menu*, --modal*, --backdrop, --divider).
    var menu: Color { pick(white(0.95), Color(arisHex: 0x1f2024)) }
    var menuBorder: Color { pick(Color(arisHex: 0xe5e7eb, 0.8), Color(arisHex: 0xdfe2e8, 0.07)) }
    var menuHover: Color { pick(Color(arisHex: 0xf3f4f6), white(0.1)) }
    var menuShadow: Color { pick(black(0.1), black(0.5)) }
    var modal: Color { pick(Color(arisHex: 0xfafafa), Color(arisHex: 0x1a1b1e)) }
    var modalBorder: Color { pick(white(0.9), Color(arisHex: 0xdfe2e8, 0.07)) }
    var backdrop: Color { black(dark ? 0.78 : 0.38) }
    var line: Color { pick(black(0.08), Color(arisHex: 0xdfe2e8, 0.055)) }
    var line2: Color { fieldBorder }

    // Key caps (--kcBg, --kcB, --kcOn*).
    var capFill: Color { pick(white(0.25), white(0.1)) }
    var capBorder: Color { pick(.white, white(0.02)) }
    var capShadow: Color { pick(black(0.07), Color(arisHex: 0x222222, 0.3)) }
    var capRecording: Color { pick(Color(arisHex: 0xdbeafe, 0.9), Color(arisHex: 0x3b82f6, 0.3)) }
    var capRecordingBorder: Color { pick(Color(arisHex: 0xbfdbfe), Color(arisHex: 0x60a5fa, 0.5)) }
    var capRecordingInk: Color { pick(Color(arisHex: 0x1e3a8a), Color(arisHex: 0xdbeafe)) }

    /// The focus ring and the highlight a search result lands with (the accent, #126ff6 unless the user picks one).
    var accent: Color { Color(arisHex: 0x126ff6) }

    // Kept for the team page and sheets.
    var soft: Color { pick(black(0.035), white(0.04)) }
    var faint: Color { ink3 }
    var elev: Color { field }
    var tile: Color { well }
    var ink: Color { pick(black(0.9), white(0.95)) }
    var focusRing: Color { accent.opacity(0.25) }
}

/// The window's measurements: one set for every page, the AI 서비스 page's (mockup D): sections 32 apart, cards 16,
/// a card's rows 20 inside with a 20-pt icon, card radius 18.
enum ArisSettingsMetrics {
    /// A section's title to what is above it; the title to its card; a card to the next.
    static let sectionGap: CGFloat = 32
    static let headingGap: CGFloat = 12
    static let cardGap: CGFloat = 16
    /// The page's title to its first section.
    static let titleGap: CGFloat = 24
    /// A row inside its card: 20 all round, a 20-pt icon column, 12 to the text, the control after it.
    static let rowInset: CGFloat = 20
    static let iconBox: CGFloat = 20
    static let iconGap: CGFloat = 12
    static let rowMinHeight: CGFloat = 60
    static let cardRadius: CGFloat = 18
    /// The small line under a card (mockup `.fine`: 12 pt, 8 above, 4 in).
    static let fineGap: CGFloat = 8
    static let fineInset: CGFloat = 4
}

private struct StillKey: EnvironmentKey { static let defaultValue = false }
private struct EnteringKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// The palette for the current appearance.
    var arisPalette: ArisPalette { ArisPalette(dark: colorScheme == .dark) }

    /// The window is opening: the page's elements rise in one after the other (ArisRise). False once a page is chosen.
    var arisSettingsEntering: Bool {
        get { self[EnteringKey.self] }
        set { self[EnteringKey.self] = newValue }
    }

    /// Drawn once, offscreen (the design renders): no scrolling, no AppKit fields, nothing still to animate in.
    var arisSettingsStill: Bool {
        get { self[StillKey.self] }
        set { self[StillKey.self] = newValue }
    }
}

/// The window's curves (mockup :root), named for what uses them.
enum ArisSettingsMotion {
    /// --house (0.22, 1, 0.36, 1): sliding indicators (0.4 s), entrances (0.34 s).
    static func house(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }
    /// --switch (0.32, 0.72, 0, 1), 220 ms: the switch.
    static let toggle = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.22)
    /// --open (0.2, 0.8, 0.2, 1), 280 ms: the preview notch growing.
    static let open = Animation.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.28)
    /// --close (0.45, 0, 0.55, 1), 200 ms: shrinking.
    static let close = Animation.timingCurve(0.45, 0, 0.55, 1, duration: 0.2)
    /// A page's cards coming in when another page is chosen: 150 ms ease-out, opacity only (pick 4-A).
    static let swap = Animation.easeOut(duration: 0.15)
    /// How long the window's entrance takes: the last element starts at 0.32 s and lands 0.34 s later.
    static let entrance = 0.7
    /// Colour changes on hover: plain ease.
    static let hover = Animation.easeInOut(duration: 0.15)
    /// Press feedback: scale .98 with a strong ease-out (emil-design-eng).
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

    /// Reduce Motion: the system's, or Aris's own 모션 줄이기.
    static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || UserDefaults.standard.bool(forKey: "arisReduceMotion")
    }
}

/// Chips that wrap onto new lines (also the to-do and timeline tags).
struct ArisFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 400, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(bounds.width, subviews).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), origins)
    }
}
