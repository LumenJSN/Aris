//
//  ArisDictationPillParts.swift
//  Aris
//
//  The pill's pieces, drawn to the measured numbers: the shell (vertical gradient 22,22,27 → 12,12,15 at .96 over a
//  behind-window blur, radius 24, the 1 px gradient ring or the solid .18 line), the level bars and the ring
//  (ArisDictationPillMotion), the round 18 buttons (✕ and ↑ on white .15, .3 on hover; the hands-free lock on clear that
//  turns into ↑ on hover), the hover hint popup (radius 10, the tooltip surface) and the recovered words' copy button.
//

import AppKit
import SwiftUI

// MARK: - Shell

/// The pill's surface behind its content.
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

/// The pill's outline: a capsule while 24 is more than half its height, else 24 continuous corners. Read from the rect
/// it is drawn in, so it stays right while the size animates.
struct ArisDictationPillShape: InsettableShape {
    var size: CGSize = .zero
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let outer = rect.size
        let r = ArisDictationPillRules.cornerRadius(outer)
        let box = rect.insetBy(dx: inset, dy: inset)
        if r * 2 >= min(outer.width, outer.height) - 0.001 { return Capsule(style: .circular).path(in: box) }
        return RoundedRectangle(cornerRadius: max(0, r - inset), style: .continuous).path(in: box)
    }

    func inset(by amount: CGFloat) -> ArisDictationPillShape {
        ArisDictationPillShape(size: size, inset: inset + amount)
    }
}

// MARK: - Level bars

/// The level while listening: 7 bars in an 18-tall slot, newest on the right.
struct ArisDictationPillBarsView: View {
    @ObservedObject var audio: ArisAudioLevel
    /// Fixed heights instead of the live level (offscreen renders).
    var preset: [CGFloat]?
    /// 3 either side in the hands-free row, none beside the app's icon.
    var margin: CGFloat = 0

    @State private var bars = ArisDictationPillBars()

    var body: some View {
        TimelineView(.animation(paused: preset != nil)) { context in
            Canvas { canvas, size in
                let heights: [CGFloat]
                if let preset { heights = preset } else {
                    bars.step(at: context.date.timeIntervalSinceReferenceDate, level: audio.value)
                    heights = bars.heights
                }
                Self.draw(heights, in: &canvas, size: size)
            }
        }
        .frame(width: ArisDictationPillBars.width, height: ArisDictationPillBars.slotHeight)
        .padding(.horizontal, margin)
        .allowsHitTesting(false)
    }

    static func draw(_ heights: [CGFloat], in canvas: inout GraphicsContext, size: CGSize) {
        let pitch = ArisDictationPillBars.barWidth + 2 * ArisDictationPillBars.gap
        for (index, height) in heights.enumerated() {
            let x = CGFloat(index) * pitch + ArisDictationPillBars.gap
            let rect = CGRect(x: x, y: (size.height - height) / 2, width: ArisDictationPillBars.barWidth, height: height)
            canvas.fill(Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                        with: .color(Color(white: ArisDictationPillBars.grey(height))))
        }
    }
}

// MARK: - Ring

/// The ring while the words are written down and typed.
struct ArisDictationPillRingView: View {
    let stage: ArisDictationPillRing.Stage
    let recordingSeconds: Double
    /// A fixed share instead of the motion (offscreen renders).
    var preset: Double?

    /// The motion, made at the first frame with this dictation's recording length (the view is new per dictation).
    private final class Holder { var motion: ArisDictationPillRingMotion? }
    @State private var holder = Holder()

    var body: some View {
        TimelineView(.animation(paused: preset != nil)) { context in
            Canvas { canvas, size in
                let share: Double
                if let preset { share = preset } else {
                    let motion = holder.motion ?? ArisDictationPillRingMotion(recordingSeconds: recordingSeconds)
                    holder.motion = motion
                    share = motion.step(at: context.date.timeIntervalSinceReferenceDate, stage: stage)
                }
                Self.draw(share, in: &canvas, size: size)
            }
        }
        .frame(width: ArisDictationPillRing.size, height: ArisDictationPillRing.size)
        .allowsHitTesting(false)
    }

    static func draw(_ share: Double, in canvas: inout GraphicsContext, size: CGSize) {
        let stroke = ArisDictationPillRing.stroke
        let radius = (min(size.width, size.height) - stroke) / 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let circle = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius))
        canvas.stroke(circle, with: .color(.white.opacity(ArisDictationPillRing.trackWhite)), lineWidth: stroke)
        guard share > 0 else { return }
        var arc = Path()
        arc.addArc(center: centre, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * share), clockwise: false)
        canvas.stroke(arc, with: .color(Color(white: ArisDictationPillRing.arcGrey)),
                      style: StrokeStyle(lineWidth: stroke, lineCap: .round))
    }
}

// MARK: - Buttons

/// A round button of the recording row.
struct ArisDictationPillButton: View {
    enum Glyph { case cancel, submit, lock }

    let glyph: Glyph
    var size: CGFloat = 18
    let label: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(fill))
                switch glyph {
                case .cancel: ArisDictationPillGlyphs.cross.frame(width: 10, height: 10)
                case .submit: ArisDictationPillGlyphs.arrow.frame(width: 12, height: 12)
                case .lock:
                    ArisDictationPillGlyphs.lock.frame(width: 12, height: 15).opacity(hovered ? 0 : 1)
                    ArisDictationPillGlyphs.arrow.frame(width: 12, height: 12).opacity(hovered ? 1 : 0)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15), value: hovered)
    }

    /// ✕ and ↑ sit on white .15 (.3 on hover); the lock on nothing (.3 on hover).
    private var fill: Double { hovered ? 0.3 : (glyph == .lock ? 0 : 0.15) }
}

/// The measured icons, in their own view boxes.
enum ArisDictationPillGlyphs {
    /// M6 6 L18 18 M6 18 L18 6 in 24, stroke 3 round.
    static var cross: some View {
        Canvas { canvas, size in
            let s = size.width / 24
            var path = Path()
            path.move(to: CGPoint(x: 6 * s, y: 6 * s)); path.addLine(to: CGPoint(x: 18 * s, y: 18 * s))
            path.move(to: CGPoint(x: 6 * s, y: 18 * s)); path.addLine(to: CGPoint(x: 18 * s, y: 6 * s))
            canvas.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
        }
    }

    /// M12 19 V5 M12 5 L6 11 M12 5 L18 11 in 24, stroke 3 round.
    static var arrow: some View {
        Canvas { canvas, size in
            let s = size.width / 24
            var path = Path()
            path.move(to: CGPoint(x: 12 * s, y: 19 * s)); path.addLine(to: CGPoint(x: 12 * s, y: 5 * s))
            path.move(to: CGPoint(x: 6 * s, y: 11 * s)); path.addLine(to: CGPoint(x: 12 * s, y: 5 * s)); path.addLine(to: CGPoint(x: 18 * s, y: 11 * s))
            canvas.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 3 * s, lineCap: .round, lineJoin: .round))
        }
    }

    /// The hands-free lock, in 14 × 18: body 12 × 9.5 r2 at 1, 7.5; shackle M3.5 7.5 V5 a3.5 3.5 0 0 1 7 0 v2.5 (1.6);
    /// the keyhole a 1.5 dot at 7, 11.6 with a 1.5 × 3 stem, in #1c1c1e.
    static var lock: some View {
        Canvas { canvas, size in
            let s = size.width / 14
            canvas.fill(Path(roundedRect: CGRect(x: 1 * s, y: 7.5 * s, width: 12 * s, height: 9.5 * s), cornerRadius: 2 * s), with: .color(.white))
            var shackle = Path()
            shackle.move(to: CGPoint(x: 3.5 * s, y: 7.5 * s))
            shackle.addLine(to: CGPoint(x: 3.5 * s, y: 5 * s))
            shackle.addArc(center: CGPoint(x: 7 * s, y: 5 * s), radius: 3.5 * s, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            shackle.addLine(to: CGPoint(x: 10.5 * s, y: 7.5 * s))
            canvas.stroke(shackle, with: .color(.white), style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
            let hole = Color(.sRGB, red: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255, opacity: 1)
            canvas.fill(Path(ellipseIn: CGRect(x: 5.5 * s, y: 10.1 * s, width: 3 * s, height: 3 * s)), with: .color(hole))
            canvas.fill(Path(roundedRect: CGRect(x: 6.25 * s, y: 11.6 * s, width: 1.5 * s, height: 3 * s), cornerRadius: 0.75 * s), with: .color(hole))
        }
    }
}

// MARK: - Hover hint

/// "Click or hold [key] to dictate" over the hovered sliver: the popup shell (radius 10, the tooltip surface, 0.8 px
/// white .09, its shadow), 12 / 500 white .85, the key as an inline cap.
struct ArisDictationPillHint: View {
    let before: String
    let key: String
    let after: String

    static let surfaceTop = Color(.sRGB, red: 20 / 255, green: 20 / 255, blue: 24 / 255, opacity: 0.98)
    static let surfaceBottom = Color(.sRGB, red: 16 / 255, green: 16 / 255, blue: 20 / 255, opacity: 0.98)

    var body: some View {
        HStack(spacing: 6) {
            if !before.isEmpty { Text(before).foregroundStyle(.white.opacity(0.85)) }
            Text(key)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.02), lineWidth: 1))
            if !after.isEmpty { Text(after).foregroundStyle(.white.opacity(0.85)) }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .fixedSize()
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(LinearGradient(colors: [Self.surfaceTop, Self.surfaceBottom], startPoint: .top, endPoint: .bottom))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.28), radius: 9, y: 6)
        .allowsHitTesting(false)
    }
}

// MARK: - Recovered words

/// The copy button at the recovered words' bottom-right: 28 tall, 0 9, radius 8, 12 / 500.
struct ArisDictationPillCopyButton: View {
    let label: String
    let copied: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12, height: 12)
                Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 9)
            .frame(minHeight: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? Color(.sRGB, red: 56 / 255, green: 56 / 255, blue: 62 / 255, opacity: 0.96)
                              : Color(.sRGB, red: 42 / 255, green: 42 / 255, blue: 47 / 255, opacity: 0.92)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(hovered ? 0.18 : 0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 4, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.15), value: hovered)
    }
}

/// The corner close of the recovered words: a 24 circle out 6 past the top-right corner.
struct ArisDictationPillCloseButton: View {
    let label: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(hovered ? Color(.sRGB, red: 104 / 255, green: 104 / 255, blue: 110 / 255, opacity: 0.86)
                                      : Color(.sRGB, red: 86 / 255, green: 86 / 255, blue: 92 / 255, opacity: 0.76))
                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                ArisDictationPillGlyphs.cross.frame(width: 12, height: 12).opacity(0.9).scaleEffect(0.8)
            }
            .frame(width: 24, height: 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .onHover { hovered = $0 }
    }
}
