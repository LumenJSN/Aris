//
//  ArisReaderBody.swift
//  Aris
//
//  The reader's markdown, as the mockup's .md draws it: 14 on a 1.7 line at .86; h1 20/700 (.97, −.015em) with the
//  saved time under it (11.5, .43); h2 17/700 (.95, −.01em) 18 above and 6 below; paragraphs 8 apart; lists 22 in with
//  markers at .43, items 2 apart; strong at 650 and .97; inline code mono 12.5 on white .1; code blocks mono 12.5 on a
//  1.6 line, white .06, 6 round, 10 × 12 in; quotes behind a 3-point rule at .18 in .6; links mono 12.5 in pale blue.
//  Labels, bullets, checklists and tables as the notch draws them (the owner's pick A, ArisDocumentBlocks).
//  Margins collapse as CSS's do, and each line has CSS's line box (lineBox). Every word is SwiftUI Text from ArisReaderInline's runs: nothing is parsed as HTML.
//

import AppKit
import SwiftUI

struct ArisReaderBody: View {
    let document: ArisReaderDocument

    static let size: CGFloat = 14
    static let textColor = Color.white.opacity(0.86)
    static let linkColor = Color(.sRGB, red: 170.0 / 255, green: 200.0 / 255, blue: 1, opacity: 0.78)

    var body: some View {
        let items = rows
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, row in
                row.view
                    .padding(.top, index == 0 ? 0 : max(items[index - 1].margins.bottom, row.margins.top))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textSelection(.enabled)
        .tint(Self.linkColor)
    }

    private struct Row {
        let view: AnyView
        let margins: (top: CGFloat, bottom: CGFloat)
    }

    /// The blocks, with the saved time right under a first h1.
    private var rows: [Row] {
        var rows: [Row] = []
        for (index, block) in document.blocks.enumerated() {
            rows.append(row(block))
            if index == 0, case .heading(1, _) = block, let meta = document.meta {
                rows.append(Row(view: AnyView(Text(verbatim: meta).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.43))
                    .lineBox(11.5, 1.7)),
                                margins: (0, 14)))
            }
        }
        return rows
    }

    private func row(_ block: ArisBoardContent.Block) -> Row {
        switch block {
        case .heading(let level, let text):
            let (size, weight, opacity, tracking, margins): (CGFloat, CGFloat, Double, CGFloat, (CGFloat, CGFloat)) =
                level == 1 ? (20, 700, 0.97, -0.3, (0, 4)) : level == 2 ? (17, 700, 0.95, -0.17, (18, 6)) : (15, 650, 0.95, -0.1, (14, 4))
            return Row(view: AnyView(Self.text(text, size: size, weight: weight, color: .white.opacity(opacity))
                .tracking(tracking).lineBox(size, level == 1 ? 1.3 : 1.7).fixedSize(horizontal: false, vertical: true)), margins: margins)
        case .label(let text):
            return Row(view: AnyView(ArisDocLabel(text: text)), margins: (18, 7))
        case .paragraph(let text):
            return Row(view: AnyView(Self.paragraph(text)), margins: (0, 8))
        case .bullets(let items):
            return Row(view: AnyView(ArisDocBullets(items: items, metrics: .reader)), margins: (0, 8))
        case .checklist(let items):
            return Row(view: AnyView(ArisDocChecklist(items: items, metrics: .reader)), margins: (0, 8))
        case .numbered(let items):
            return Row(view: AnyView(list(items.enumerated().map { ("\($0.offset + 1).", $0.element) })), margins: (0, 8))
        case .quote(let text):
            return Row(view: AnyView(
                Self.text(text, size: Self.size, color: .white.opacity(0.6)).lineBox(Self.size, 1.7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 0))
                    .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.18)).frame(width: 3) }), margins: (0, 10))
        case .code(let code):
            return Row(view: AnyView(
                Text(verbatim: code).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(.white.opacity(0.82))
                    .lineBox(12.5, 1.6).fixedSize(horizontal: false, vertical: true)
                    .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.06)))), margins: (0, 10))
        case .table(let header, let rows):
            return Row(view: AnyView(ArisDocTable(header: header, rows: rows)), margins: (0, 10))
        }
    }

    private func list(_ items: [(marker: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: item.marker).font(.system(size: Self.size).monospacedDigit()).foregroundStyle(.white.opacity(0.43))
                        .frame(width: 16, alignment: .trailing)
                    Self.paragraph(item.text)
                }
            }
        }
    }

    private static func paragraph(_ words: String) -> some View {
        text(words, size: size, color: textColor).lineBox(size, 1.7).fixedSize(horizontal: false, vertical: true)
    }

    /// `words`' runs as one Text: strong at 650 (or the heading's weight) and .97, code and links in mono 12.5 (links
    /// pale blue, clickable only to be copied: the reader's openURL never opens anything).
    static func text(_ words: String, size: CGFloat, weight: CGFloat = 400, color: Color, strong: Color = .white.opacity(0.97)) -> Text {
        Text(attributed(words, size: size, weight: weight, color: color, strong: strong))
    }

    static func attributed(_ words: String, size: CGFloat, weight: CGFloat = 400, color: Color,
                           strong: Color = .white.opacity(0.97)) -> AttributedString {
        var out = AttributedString()
        for run in ArisReaderInline.runs(words) {
            var piece = AttributedString(run.text)
            switch run.style {
            case .plain:
                piece.font = .system(size: size, weight: named(weight))
                piece.foregroundColor = color
            case .strong:
                piece.font = .system(size: size, weight: named(max(650, weight)))
                piece.foregroundColor = strong
            case .emphasis:
                piece.font = .system(size: size, weight: named(weight)).italic()
                piece.foregroundColor = color
            case .strongEmphasis:
                piece.font = .system(size: size, weight: named(max(650, weight))).italic()
                piece.foregroundColor = strong
            case .code:
                // The mockup's 2 × 6 padding, as thin spaces inside the tint (a copy takes the blocks' words, not these).
                piece = AttributedString("\u{2006}" + run.text + "\u{2006}")
                piece.font = .system(size: size * 12.5 / 14, design: .monospaced)
                piece.foregroundColor = color
                piece.backgroundColor = .white.opacity(0.1)
            case .link(let url):
                piece.font = .system(size: size * 12.5 / 14, design: .monospaced)
                piece.foregroundColor = linkColor
                piece.link = url
            }
            out += piece
        }
        return out
    }

    /// A CSS weight as a named one: Hangul falls back to Apple SD Gothic Neo, which only has named faces (a weight on
    /// SF's variation axis doesn't reach it, and the words would stay regular).
    static func named(_ weight: CGFloat) -> Font.Weight {
        switch weight {
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<690: return .semibold
        default: return .bold
        }
    }
}

extension View {
    /// CSS's line box: `height` × `size` per line, the extra split above and below as half-leading (SwiftUI's own line
    /// is about 1.2 × the size).
    func lineBox(_ size: CGFloat, _ height: CGFloat) -> some View {
        let extra = max(0, size * height - size * 1.2)
        return lineSpacing(extra).padding(.vertical, extra / 2)
    }
}
