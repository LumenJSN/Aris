//
//  ArisDictationPillParts.swift
//  Aris
//
//  The pill's pieces, drawn to the numbers measured from the reference pill: its colours (ArisDictationPillLook), its
//  body (flat, one fill in one line, the corners following the size), the level's 10 bars and the spinner
//  (ArisDictationPillMotion), the round 18 ✕ and ■, and the tooltip (14 pt in a black capsule in a #30302f line). The
//  glass shell, its rim and its outline below them are the notice pill's (ArisNoticePillView), kept as they were. The
//  recovered words' card is ArisDictationPillRecoveredCard.
//

import AppKit
import SwiftUI

// MARK: - The notice pill's glass shell

/// The notice pill's surface behind its content: vertical gradient 22,22,27 → 12,12,15 at .96 over a behind-window
/// blur, the 1 px gradient ring or a solid .18 line.
struct ArisDictationPillShell: View {
    let size: CGSize
    let gradientBorder: Bool
    /// The blur behind (14 measured; the system's behind-window blur here). Nil draws none (offscreen renders, which
    /// have nothing behind the window to blur; the .96 gradient covers almost all of it).
    var blending: NSVisualEffectView.BlendingMode? = .behindWindow

    static let top = Color(.sRGB, red: 22 / 255, green: 22 / 255, blue: 27 / 255, opacity: 0.96)
    static let bottom = Color(.sRGB, red: 12 / 255, green: 12 / 255, blue: 15 / 255, opacity: 0.96)

    var body: some View {
        let shape = ArisDictationPillShape(size: size)
        ZStack {
            if let blending { VisualEffectView(material: .hudWindow, blendingMode: blending) }
            LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay {
            if gradientBorder {
                ArisDictationPillRim(shape: shape)
            } else {
                shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// The 1 px masked ring: two radial highlights (.28 → .08 at 30% → clear at 60%) at the top-left and bottom-right
/// corners over white .07.
private struct ArisDictationPillRim: View {
    let shape: ArisDictationPillShape

    /// CSS's farthest-corner ellipse from a corner is √2 × the box each way; SwiftUI's fraction 1 is half the box.
    private static let reach: CGFloat = 2 * 2.0.squareRoot()

    private func highlight(_ corner: UnitPoint) -> EllipticalGradient {
        EllipticalGradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .white.opacity(0.08), location: 0.3),
                                   .init(color: .white.opacity(0), location: 0.6)],
                           center: corner, startRadiusFraction: 0, endRadiusFraction: Self.reach)
    }

    var body: some View {
        ZStack {
            shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
            shape.strokeBorder(highlight(.topLeading), lineWidth: 1)
            shape.strokeBorder(highlight(.bottomTrailing), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// The notice pill's outline: a capsule while 24 is more than half its height, else 24 continuous corners. Read from
/// the rect it is drawn in, so it stays right while the size animates.
struct ArisDictationPillShape: InsettableShape {
    static let radius: CGFloat = 24

    var size: CGSize = .zero
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let outer = rect.size
        let r = min(Self.radius, min(outer.width, outer.height) / 2)
        let box = rect.insetBy(dx: inset, dy: inset)
        if r * 2 >= min(outer.width, outer.height) - 0.001 { return Capsule(style: .circular).path(in: box) }
        return RoundedRectangle(cornerRadius: max(0, r - inset), style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> ArisDictationPillShape {
        ArisDictationPillShape(size: size, inset: inset + amount)
    }
}

/// A colour as numbers (sRGB, 0…1), so a move between two looks can be drawn at any instant.
struct ArisDictationPillRGBA: Equatable {
    var red: Double, green: Double, blue: Double, alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(hex: Int, _ alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xff) / 255, Double((hex >> 8) & 0xff) / 255, Double(hex & 0xff) / 255, alpha)
    }

    /// `t` of the way to `other`, premultiplied as CSS mixes.
    func mixed(_ other: ArisDictationPillRGBA, _ t: Double) -> ArisDictationPillRGBA {
        let a = alpha + (other.alpha - alpha) * t
        guard a > 0 else { return ArisDictationPillRGBA(0, 0, 0, 0) }
        func channel(_ x: Double, _ y: Double) -> Double { (x * alpha + (y * other.alpha - x * alpha) * t) / a }
        return ArisDictationPillRGBA(channel(red, other.red), channel(green, other.green), channel(blue, other.blue), a)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// The dictation pill's colours, measured from the reference pill's palette (its light theme): black in a #30302f
/// line; the sliver black .5 in white .5; under the pointer #30302f in #5b5b59; an error's line #ee6a6a; the level's
/// bars white .4, white while listening; ✕ #fcfcfb on #4d4a42, ■ #1a1a1a on #fcfcfb; tooltips black in #30302f. No
/// blur and no shadow: the pill is flat black, like the closed notch above it.
enum ArisDictationPillLook {
    /// states.css:90 (--shade-black, --vast-900).
    static let black = ArisDictationPillRGBA(0, 0, 0)
    static let grey900 = ArisDictationPillRGBA(hex: 0x30302f)
    /// states.css:117.
    static let sliverFill = ArisDictationPillRGBA(0, 0, 0, 0.5)
    static let sliverLine = ArisDictationPillRGBA(1, 1, 1, 0.5)
    /// states.css:305 (--vast-700).
    static let grey700 = ArisDictationPillRGBA(hex: 0x5b5b59)
    /// states.css:239 (--destructive-500).
    static let red = ArisDictationPillRGBA(hex: 0xee6a6a)

    static let fill = black.color
    static let line = grey900.color
    /// bars.css:2, 17.
    static let bar = Color.white.opacity(0.4)
    static let barLive = Color.white
    /// states.css:310, 328 (--sand-950, --sand-50, --vast-950).
    static let cancelFill = ArisDictationPillRGBA(hex: 0x4d4a42).color
    static let cancelGlyph = ArisDictationPillRGBA(hex: 0xfcfcfb).color
    static let stopFill = ArisDictationPillRGBA(hex: 0xfcfcfb).color
    static let stopGlyph = ArisDictationPillRGBA(hex: 0x1a1a1a).color
    /// The mic on the hover, white (states.css:348).
    static let mic = Color.white
    /// spinner.css:10.
    static func spoke(_ opacity: Double) -> Color {
        ArisDictationPillRGBA(ArisDictationPillSpinner.red, ArisDictationPillSpinner.green, ArisDictationPillSpinner.blue, opacity).color
    }

    static func fill(_ kind: ArisDictationPillLookKind) -> ArisDictationPillRGBA {
        switch kind {
        case .sliver: sliverFill
        case .hovered: grey900
        case .solid, .failed: black
        }
    }

    static func line(_ kind: ArisDictationPillLookKind) -> ArisDictationPillRGBA {
        switch kind {
        case .sliver: sliverLine
        case .hovered: grey700
        case .solid: grey900
        case .failed: red
        }
    }

    static func lineWidth(_ kind: ArisDictationPillLookKind) -> CGFloat {
        kind == .failed ? ArisDictationPillRules.errorLineWidth : ArisDictationPillRules.lineWidth
    }
}

// MARK: - The dictation pill's body

/// The dictation pill's outline: its corners from its height as drawn (ArisDictationPillRules.cornerRadius: the
/// sliver's 6 fits its 8 as 4, a capsule at 30), read from the rect it is drawn in so it stays right while the size
/// animates.
struct ArisDictationPillOutline: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = ArisDictationPillRules.cornerRadius(rect.size)
        let box = rect.insetBy(dx: inset, dy: inset)
        if r * 2 >= min(rect.width, rect.height) - 0.001 { return Capsule(style: .circular).path(in: box) }
        return RoundedRectangle(cornerRadius: max(0, r - inset), style: .circular).path(in: box)
    }

    func inset(by amount: CGFloat) -> ArisDictationPillOutline { ArisDictationPillOutline(inset: inset + amount) }
}

/// A move between two looks at one instant (offscreen renders of the motion).
struct ArisDictationPillLookBlend: Equatable {
    var from: ArisDictationPillLookKind
    var to: ArisDictationPillLookKind
    var progress: Double
}

/// The pill's body: one fill in one line, inside its edge (CSS's border box), no blur, no shadow.
struct ArisDictationPillBody: View {
    typealias Look = ArisDictationPillLook

    let size: CGSize
    let kind: ArisDictationPillLookKind
    var blend: ArisDictationPillLookBlend?

    private var fill: ArisDictationPillRGBA {
        guard let blend else { return Look.fill(kind) }
        return Look.fill(blend.from).mixed(Look.fill(blend.to), blend.progress)
    }

    private var line: ArisDictationPillRGBA {
        guard let blend else { return Look.line(kind) }
        return Look.line(blend.from).mixed(Look.line(blend.to), blend.progress)
    }

    private var lineWidth: CGFloat {
        guard let blend else { return Look.lineWidth(kind) }
        let a = Look.lineWidth(blend.from), b = Look.lineWidth(blend.to)
        return a + (b - a) * blend.progress
    }

    var body: some View {
        let shape = ArisDictationPillOutline()
        ZStack {
            shape.fill(fill.color)
            shape.strokeBorder(line.color, lineWidth: lineWidth)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

// MARK: - Level bars

/// What the bars show: the voice (listening), or standing still (the words are being written, an error).
enum ArisDictationPillBarsMode: Equatable { case live, still }

/// The level: 10 bars 2 wide, 2 apart, 4 in at each end of a 46 × 18 box (ArisDictationPillWave).
struct ArisDictationPillBarsView: View {
    @ObservedObject var audio: ArisAudioLevel
    let level: ArisDictationPillLevel
    var mode: ArisDictationPillBarsMode = .live
    /// Fixed heights instead of the live level (offscreen renders).
    var preset: [CGFloat]?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: preset != nil || mode == .still)) { context in
            Canvas { canvas, size in
                Self.draw(heights(at: context.date.timeIntervalSinceReferenceDate), live: mode == .live, in: &canvas, size: size)
            }
        }
        .frame(width: ArisDictationPillWave.width, height: ArisDictationPillWave.boxHeight)
        .allowsHitTesting(false)
    }

    private func heights(at now: Double) -> [CGFloat] {
        if let preset { return preset }
        guard mode == .live else { return ArisDictationPillWave.heights(audioScale: 1, t: 0, waving: false) }
        // ArisAudioLevel is RMS × 8, up to 1.
        let scale = level.step(at: now, rms: Double(audio.value) / 8)
        let t = now - (level.startedAt ?? now)
        // Reduce Motion: the voice still moves the bars, the wave doesn't.
        return ArisDictationPillWave.heights(audioScale: scale, t: t, waving: !reduceMotion)
    }

    static func draw(_ heights: [CGFloat], live: Bool, in canvas: inout GraphicsContext, size: CGSize) {
        typealias W = ArisDictationPillWave
        let colour = live ? ArisDictationPillLook.barLive : ArisDictationPillLook.bar
        for (index, height) in heights.enumerated() {
            let x = W.sidePadding + CGFloat(index) * (W.barWidth + W.gap)
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: W.barWidth, height: height)
            canvas.fill(Path(roundedRect: rect, cornerRadius: min(W.barRadius, height / 2)), with: .color(colour))
        }
    }
}

// MARK: - Spinner

/// While the words are written down and typed: 8 spokes fading round.
struct ArisDictationPillSpinnerView: View {
    /// A fixed time instead of the clock (offscreen renders).
    var preset: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: preset != nil || reduceMotion)) { context in
            Canvas { canvas, size in
                // Reduce Motion: it holds still at its first instant.
                let t = preset ?? (reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate)
                Self.draw(at: t, in: &canvas, size: size)
            }
        }
        .frame(width: ArisDictationPillSpinner.size, height: ArisDictationPillSpinner.size)
        .allowsHitTesting(false)
    }

    static func draw(at t: Double, in canvas: inout GraphicsContext, size: CGSize) {
        typealias S = ArisDictationPillSpinner
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for spoke in 0..<S.spokes {
            var context = canvas
            context.translateBy(x: centre.x, y: centre.y)
            context.rotate(by: .degrees(S.angle(spoke)))
            let rect = CGRect(x: -S.spokeWidth / 2, y: -S.reach - S.spokeLength / 2, width: S.spokeWidth, height: S.spokeLength)
            context.fill(Path(roundedRect: rect, cornerRadius: S.spokeRadius), with: .color(ArisDictationPillLook.spoke(S.alpha(spoke, at: t))))
        }
    }
}

// MARK: - Buttons

/// The hands-free row's round 18 buttons: ✕ (cancel) and ■ (finish and put it in).
struct ArisDictationPillButton: View {
    enum Glyph { case cancel, stop }

    let glyph: Glyph
    let label: String
    let action: () -> Void
    var hovered: (Bool) -> Void = { _ in }

    static let size: CGFloat = 18

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(glyph == .cancel ? ArisDictationPillLook.cancelFill : ArisDictationPillLook.stopFill)
                switch glyph {
                case .cancel: ArisDictationPillGlyphs.cross.frame(width: 8, height: 8)
                case .stop: ArisDictationPillGlyphs.stop.frame(width: 7, height: 7)
                }
            }
            .frame(width: Self.size, height: Self.size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover(perform: hovered)
    }
}

/// Aris's own icons.
enum ArisDictationPillGlyphs {
    /// Two strokes corner to corner, 1.6 round.
    static var cross: some View {
        Canvas { canvas, size in
            var path = Path()
            path.move(to: .zero); path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.move(to: CGPoint(x: 0, y: size.height)); path.addLine(to: CGPoint(x: size.width, y: 0))
            canvas.stroke(path, with: .color(ArisDictationPillLook.cancelGlyph), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    /// A square, round 1.5.
    static var stop: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(ArisDictationPillLook.stopGlyph)
    }

    /// The mic, 16 tall.
    static var mic: some View {
        Image(systemName: "mic.fill").resizable().scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(ArisDictationPillLook.mic)
    }
}

// MARK: - Tooltip

/// A tooltip over the pill: 14 / 20 in white, the key bold, 6 × 14 in, a black capsule in a 1 px #30302f line
/// (states.css:486).
struct ArisDictationPillTooltip: View {
    let before: String
    var key: String = ""
    var after: String = ""

    var body: some View {
        HStack(spacing: 4) {
            if !before.isEmpty { Text(before) }
            if !key.isEmpty { Text(key).fontWeight(.bold) }
            if !after.isEmpty { Text(after) }
        }
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(Color.white)
        .lineLimit(1)
        .fixedSize()
        .frame(height: 20)
        .padding(.vertical, 6).padding(.horizontal, 14)
        .background(Capsule(style: .circular).fill(ArisDictationPillLook.fill))
        .overlay(Capsule(style: .circular).strokeBorder(ArisDictationPillLook.line, lineWidth: 1))
        .allowsHitTesting(false)
    }
}
