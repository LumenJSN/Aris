//
//  ArisDocumentBlocks.swift
//  Aris
//
//  The owner's pick A, "깔끔한 문서" (mockups/answer-format.html), drawn the same in the notch's answer and the
//  reader: a section's label (11 / 650, .06em, white .43), tables on hairlines (.08) with the first column dim (.5)
//  and an all-bold cell in the good green (#4ade80), bullets behind a 4-point dot at .43, and checklist items behind a
//  14-point ring at .3 that a click ticks on screen only (nothing is saved or sent). Every word is SwiftUI Text from
//  ArisReaderInline's runs (ArisReaderBody.attributed): no HTML, no images, only http, https and mailto links, which a
//  click copies.
//

import SwiftUI

enum ArisDocLook {
    static let good = Color(.sRGB, red: 0x4a / 255.0, green: 0xde / 255.0, blue: 0x80 / 255.0, opacity: 1)
    static let hair = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.9)
    static let dim = Color.white.opacity(0.5)
    static let quiet = Color.white.opacity(0.43)
    static let ring = Color.white.opacity(0.3)
    static let strong = Color.white
    /// A tick: CSS `ease-out`-ish (0.23, 1, 0.32, 1) over 180 ms.
    static let tick = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.18)
}

/// Sizes for where the blocks are drawn: the notch's 14 on 21, the reader's 14 on 1.7.
struct ArisDocMetrics: Equatable {
    let size: CGFloat
    let line: CGFloat
    let itemGap: CGFloat

    /// The notch's body text: Aris's 14 on 21, or Siri's 15 on 18 in the siri look (ArisSiriLook.Answer).
    static var notch: ArisDocMetrics {
        ArisSiriLookNow.on ? ArisDocMetrics(size: ArisSiriLook.Answer.fontSize, line: ArisSiriLook.Answer.lineHeight, itemGap: 4)
            : ArisDocMetrics(size: 14, line: 21, itemGap: 5)
    }
    static let reader = ArisDocMetrics(size: 14, line: 14 * 1.7, itemGap: 4)
}

/// `### 비교`.
struct ArisDocLabel: View {
    let text: String

    var body: some View {
        ArisReaderBody.text(text, size: 11, weight: 650, color: ArisDocLook.quiet, strong: ArisDocLook.quiet)
            .tracking(0.66)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `- words`, each behind a 4-point dot (3 in, centred on the first line).
struct ArisDocBullets: View {
    let items: [String]
    var metrics = ArisDocMetrics.notch

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.itemGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                ArisDocLine(words: item, metrics: metrics)
                    .padding(.leading, 16)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(ArisDocLook.quiet).frame(width: 4, height: 4).offset(x: 3, y: metrics.line / 2 - 2)
                    }
            }
        }
    }
}

/// `- [ ] words`: a 14-point ring at .3 before each; a click ticks it (green, the words dimmed and struck through) and
/// another unticks it, on screen only.
struct ArisDocChecklist: View {
    let items: [ArisBoardContent.Check]
    var metrics = ArisDocMetrics.notch

    /// The items clicked since this list appeared (each flips its written state).
    @State private var flipped: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.itemGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let done = item.done != flipped.contains(index)
                ArisDocLine(words: item.text, metrics: metrics, color: done ? ArisDocLook.quiet : ArisDocLook.text, struck: done)
                    .padding(.leading, 24)
                    .overlay(alignment: .topLeading) {
                        ArisDocRing(done: done)
                            .offset(y: metrics.line / 2 - 7)
                            .onTapGesture { withAnimation(ArisDocLook.tick) { flip(index) } }
                    }
            }
        }
    }

    private func flip(_ index: Int) {
        if flipped.contains(index) { flipped.remove(index) } else { flipped.insert(index) }
    }
}

/// The ring, or the green tick in its place.
private struct ArisDocRing: View {
    let done: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(ArisDocLook.ring, lineWidth: 1.5).opacity(done ? 0 : 1)
            Circle().fill(ArisDocLook.good).opacity(done ? 1 : 0)
            Path { path in
                path.move(to: CGPoint(x: 4, y: 7.2))
                path.addLine(to: CGPoint(x: 6.2, y: 9.4))
                path.addLine(to: CGPoint(x: 10.2, y: 5))
            }
            .stroke(.black, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .opacity(done ? 1 : 0)
        }
        .frame(width: 14, height: 14)
        .padding(3)
        .contentShape(Rectangle())
        .padding(-3)
    }
}

/// A list item's or paragraph's words on the metrics' line, strong in white at 650.
struct ArisDocLine: View {
    let words: String
    var metrics = ArisDocMetrics.notch
    var color = ArisDocLook.text
    var struck = false

    var body: some View {
        ArisReaderBody.text(words, size: metrics.size, color: color, strong: struck ? color : ArisDocLook.strong)
            .strikethrough(struck, color: color)
            .lineBox(metrics.size, metrics.line / metrics.size)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A table on hairlines: the header (when it has one) at 12 / 600 and .62, 6 above the first line; every row 7 above
/// and below a hairline on its top; the first column 28% wide and dim, the others sharing the rest; a cell that is all
/// bold is the better value, in green.
struct ArisDocTable: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        // Once per table, not per cell.
        let columns = min(ArisBoardContent.tableColumns, max(header.count, rows.map(\.count).max() ?? 0))
        VStack(alignment: .leading, spacing: 0) {
            if !header.isEmpty {
                ArisTableColumns(columns: columns) {
                    ForEach(0..<columns, id: \.self) { column in
                        cellText(column < header.count ? header[column] : "", size: 12, weight: 600, color: .white.opacity(0.62))
                    }
                }
                .padding(.bottom, 6)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                ArisTableColumns(columns: columns) {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(column < row.count ? row[column] : "", first: column == 0)
                    }
                }
                .padding(.vertical, 7)
                .overlay(alignment: .top) { Rectangle().fill(ArisDocLook.hair).frame(height: 1) }
            }
        }
    }

    @ViewBuilder private func cell(_ words: String, first: Bool) -> some View {
        if let win = ArisBoardContent.winCell(words) {
            cellText(win, size: 13.5, color: ArisDocLook.good, strong: ArisDocLook.good)
        } else {
            cellText(words, size: 13.5, color: first ? ArisDocLook.dim : ArisDocLook.text)
        }
    }

    private func cellText(_ words: String, size: CGFloat, weight: CGFloat = 400, color: Color, strong: Color = ArisDocLook.strong) -> some View {
        ArisReaderBody.text(words, size: size, weight: weight, color: color, strong: strong)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A table row's cells: the first column 28% of the width (the mockup's td:first-child), the others sharing the rest;
/// as tall as its tallest cell.
struct ArisTableColumns: Layout {
    let columns: Int

    static func widths(columns: Int, total: CGFloat) -> [CGFloat] {
        guard columns > 1 else { return [total] }
        let first = (total * 0.28).rounded(.down)
        return [first] + Array(repeating: (total - first) / CGFloat(columns - 1), count: columns - 1)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 0)).width
        let widths = Self.widths(columns: max(columns, 1), total: total)
        let height = subviews.enumerated().map { index, cell in
            cell.sizeThatFits(ProposedViewSize(width: widths[min(index, widths.count - 1)], height: nil)).height
        }.max() ?? 0
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = Self.widths(columns: max(columns, 1), total: bounds.width)
        var x = bounds.minX
        for (index, cell) in subviews.enumerated() {
            let width = widths[min(index, widths.count - 1)]
            cell.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: nil))
            x += width
        }
    }
}
