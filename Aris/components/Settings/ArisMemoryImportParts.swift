//
//  ArisMemoryImportParts.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기: the pieces the settings window has no component for:
//  - the tick row and its box: r12 with an edge, 12 at the sides and 10 above and below, rows 8 apart, a 16-pt box
//    rounded 5, blue-500 with a white check;
//  - the paste box: r12, 16 at the sides and 12 above and below, 14 pt, an inset shadow;
//  - the request: a transcript well (r12, the same insets, a 2–3 % fill);
//  - notes, the receipt and errors: a callout (r12, 14 at the sides and 12 above and below, a 16-pt icon, a medium
//    title and a 12-pt body), one sentence a line;
//  - lists that scroll fade in and out over 20 pt (as the settings modal's body does).
//  Colours not in ArisPalette are named below.
//

import SwiftUI

extension ArisPalette {
    /// Tailwind v4 blue-500, oklch(62.3% .214 259.815) = #2b7fff: the ticked box.
    var tickBlue: Color { Color(arisHex: 0x2b7fff) }
    /// The empty box's edge: gray-300 / white 25 %, on hover gray-400 / white 40 %.
    var boxEdge: Color { dark ? .white.opacity(0.25) : Color(arisHex: 0xd1d5dc) }
    var boxEdgeHover: Color { dark ? .white.opacity(0.4) : Color(arisHex: 0x99a1af) }
    /// A ticked row: white with a gray-300 edge and a small shadow / white 6 % with a white 15 % edge.
    var tickedRow: Color { dark ? .white.opacity(0.06) : .white }
    var tickedRowEdge: Color { dark ? .white.opacity(0.15) : Color(arisHex: 0xd1d5dc) }
    /// An unticked row: no fill, a gray-200 / white 6 % edge, drawn at 55 %.
    var plainRowEdge: Color { dark ? .white.opacity(0.06) : Color(arisHex: 0xe5e7eb) }
    /// The callout's words: title gray-800 / gray-200, body gray-600 / gray-300; its icon blue-500 / blue-300.
    var calloutTitle: Color { dark ? Color(arisHex: 0xe5e7eb) : Color(arisHex: 0x1e2939) }
    var calloutBody: Color { dark ? Color(arisHex: 0xd1d5dc) : Color(arisHex: 0x4a5565) }
    var calloutIcon: Color { dark ? Color(arisHex: 0x8ec5ff) : tickBlue }
    /// The textarea's placeholder: gray-400 / gray-600.
    var pasteHint: Color { dark ? Color(arisHex: 0x4a5565) : Color(arisHex: 0x99a1af) }
}

/// The import sheet's measures.
enum ArisImportMetric {
    /// The radius of the row, the box of text and the callout.
    static let radius: CGFloat = 12
    /// The row: 12 at the sides, 10 above and below, 12 between its parts, rows 8 apart.
    static let rowSide: CGFloat = 12, rowTop: CGFloat = 10, rowGap: CGFloat = 12, rowSpacing: CGFloat = 8
    /// The box: 16 square, rounded 5, a 12-pt check drawn at stroke 3 (on a 24 grid: 1.5 pt here).
    static let box: CGFloat = 16, boxRadius: CGFloat = 5
    /// The textarea and the well: 16 at the sides, 12 above and below.
    static let fieldSide: CGFloat = 16, fieldTop: CGFloat = 12
    /// A scrolling list's fade at each end, 20 pt.
    static let fade: CGFloat = 20
    /// The review list's most height before it scrolls.
    static let listMost: CGFloat = 320
}

// MARK: - The box

/// The tick box: empty with an edge, or blue with a white check that draws itself. `level` runs 0 → 1 as it ticks,
/// so the fill (150 ms, Tailwind's default curve) and the mark (150 ms strong ease-out) are drawn from one clock.
struct ArisImportBox: View {
    typealias P = ArisMemoryImportPacing
    @Environment(\.arisPalette) private var palette
    let level: Double
    var hovering = false
    /// Reduce Motion: the mark fades in with the fill instead of drawing itself.
    var reduced = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ArisImportMetric.boxRadius, style: .continuous)
        let seconds = level * P.tick.duration
        let fill = P.tick.progress(at: seconds)
        ZStack {
            shape.fill(palette.tickBlue.opacity(fill))
            shape.strokeBorder(hovering && level < 1 ? palette.boxEdgeHover : palette.boxEdge, lineWidth: 1).opacity(1 - fill)
            ArisImportCheckMark()
                .trim(from: 0, to: reduced ? (level > 0 ? 1 : 0) : P.draw.progress(at: seconds))
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .opacity(reduced ? fill : 1)
                .frame(width: 8, height: 5.5)
        }
        .frame(width: ArisImportMetric.box, height: ArisImportMetric.box)
    }
}

/// Lucide's check (`M20 6 9 17l-5-5`: 16 × 11 of 24, so 8 × 5.5 in the 12-pt glyph), drawn from its left end so a
/// trim draws it the way a hand would.
struct ArisImportCheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 6 / 11))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.3125, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// MARK: - The callout

/// A note, the receipt or an error, in a callout: an icon, a medium first sentence, the rest in 12 pt.
struct ArisImportCallout<Icon: View>: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    /// Korean, looked up whole for an English Mac, then cut into sentences.
    let text: String
    /// Words already in the page's language (a count, the receipt's breakdown), set under the sentences.
    var detail: String?
    /// False folds the detail away (after 되돌리기), so the height eases instead of jumping.
    var detailShown = true
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        let lines = ArisMemoryImportPacing.sentences(w(text))
        let shape = RoundedRectangle(cornerRadius: ArisImportMetric.radius, style: .continuous)
        HStack(alignment: .top, spacing: 12) {
            icon().frame(width: 16, height: 16).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                if let first = lines.first {
                    Text(first).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.calloutTitle)
                }
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 12)).lineSpacing(3).foregroundStyle(palette.calloutBody)
                }
                if let detail {
                    Text(detail).font(.system(size: 12)).monospacedDigit().foregroundStyle(palette.calloutBody)
                        .frame(height: detailShown ? nil : 0, alignment: .top).clipped().opacity(detailShown ? 1 : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        // bg white / --dark-modal-elevated, a gray-200 / control-border edge, `0 1px 2px rgba(0,0,0,.03)` light.
        .background(shape.fill(palette.field).shadow(color: .black.opacity(palette.dark ? 0 : 0.03), radius: 1, y: 1))
        .overlay(shape.strokeBorder(palette.fieldBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// The callout's plain icon: a 16-pt info glyph in blue (never red: red is kept for a button that destroys).
struct ArisImportInfoIcon: View {
    @Environment(\.arisPalette) private var palette
    var symbol = "info.circle"

    var body: some View {
        Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(palette.calloutIcon)
    }
}

/// The receipt's mark: ArisLandingCheck's green check (16 pt, #30d158, scale .4 → 1 over
/// 460 ms (0.34, 1.56, 0.64, 1), its one overshoot), drawn from `seconds` so a render can show any frame of it.
struct ArisImportLandingMark: View {
    let seconds: Double?

    var body: some View {
        let progress = seconds.map { ArisMemoryImportPacing.land.progress(at: $0) } ?? 1
        Image(systemName: "checkmark").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 16, height: 16).background(Circle().fill(Color(arisHex: 0x30d158)))
            .scaleEffect(0.4 + 0.6 * progress)
            .opacity(min(1, max(0, progress)))
    }
}

/// After 되돌리기: the same slot, a quiet circle with the undo arrow (the toast's info grey).
struct ArisImportUndoneMark: View {
    @Environment(\.arisPalette) private var palette

    var body: some View {
        Image(systemName: "arrow.uturn.backward").font(.system(size: 8, weight: .bold)).foregroundStyle(palette.desc)
            .frame(width: 16, height: 16).background(Circle().fill(palette.chip))
    }
}

// MARK: - Fades and the group heading

extension View {
    /// A scrolling list's ends fade over 20 pt (the settings modal body's mask): content at rest sits inside the
    /// padding the caller gives it, so only what is scrolled under an end fades.
    func arisImportFadedEnds(_ fade: CGFloat = ArisImportMetric.fade) -> some View {
        mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
            }
        )
    }
}

/// A group's name and how many lines it has: a section label (11/600, gray-600 / gray-300) with
/// its quieter neighbour (11, gray-400 / gray-600) for the count.
struct ArisImportHeading: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(w(title)).font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.icon)
            Text("\(count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(palette.pasteHint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
