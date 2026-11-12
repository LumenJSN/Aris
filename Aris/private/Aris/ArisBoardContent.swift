//
//  ArisBoardContent.swift
//  Aris
//
//  What the AI puts on the Aris board ("오른쪽 화면에 띄워줘"), the reader's saved results and the notch's answers (the user's
//  pick A, mockups/answer-format.html): Markdown split into the blocks they draw (headings, `###` labels, paragraphs,
//  lists, `- [ ]` checklists, numbered lists, quotes, tables, code), and which screen it goes on. A table has a header
//  only when a divider row follows its first row; a cell that is all **bold** is the better value. Pure, so it's tested.
//

import CoreGraphics
import Foundation

enum ArisBoardContent {
    /// A checklist item: its words, and whether it was written ticked (`- [x]`).
    struct Check: Equatable {
        let text: String
        let done: Bool
    }

    enum Block: Equatable {
        /// `#` and `##`.
        case heading(level: Int, text: String)
        /// `###` and deeper: a section's small label (비교, 추천 이유).
        case label(String)
        case paragraph(String)
        case bullets([String])
        case checklist([Check])
        case numbered([String])
        case quote(String)
        case table(header: [String], rows: [[String]])
        case code(String)
    }

    /// How tall the reader's panel is. `needed`: what the whole document takes, its bar included (nil: too long to be
    /// worth measuring); `base`: the panel's own height; `tallest`: the most it grows to. A document that fits in the
    /// panel leaves it as it is; one a little taller gets a panel as tall as itself, so its last line is never half
    /// under the lower edge (a short answer's was, fading as if more followed); a longer one is read in the panel at
    /// its own height, scrolling.
    static func readerHeight(needed: CGFloat?, base: CGFloat, tallest: CGFloat) -> CGFloat {
        guard let needed, needed > base, needed <= tallest else { return base }
        return needed.rounded(.up)
    }

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var lines = markdown.components(separatedBy: .newlines)[...]
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                lines = lines.dropFirst()
            } else if trimmed.hasPrefix("```") {
                let body = lines.dropFirst().prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
                blocks.append(.code(body.joined(separator: "\n")))
                lines = lines.dropFirst(body.count + 2)
            } else if let hashes = trimmed.range(of: "^#{1,6} ", options: .regularExpression) {
                let level = trimmed[hashes].count - 1
                let text = String(trimmed[hashes.upperBound...])
                blocks.append(level >= 3 ? .label(text) : .heading(level: level, text: text))
                lines = lines.dropFirst()
            } else if trimmed.hasPrefix(">") {
                let quoted = lines.prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
                blocks.append(.quote(quoted.map(unquote).joined(separator: "\n")))
                lines = lines.dropFirst(quoted.count)
            } else if trimmed.hasPrefix("|") {
                let count = lines.prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }.count
                // Only what's drawn is read: the header, its divider and tableRows rows (a few more for other dividers).
                let rows = lines.prefix(min(count, tableRows + 8)).map(cells(of:))
                let header = rows.count > 1 && isDivider(rows[1]) ? rows[0] : []
                let body = rows.dropFirst(header.isEmpty ? 0 : 1).filter { !isDivider($0) }
                let kept = Array(body.prefix(tableRows)) + (body.count > tableRows || count > rows.count ? [["…"]] : [])
                if !header.isEmpty || !kept.isEmpty { blocks.append(.table(header: header, rows: kept)) }
                lines = lines.dropFirst(count)
            } else if check(trimmed) != nil {
                let items = lines.prefix { check($0.trimmingCharacters(in: .whitespaces)) != nil }
                blocks.append(.checklist(items.compactMap { check($0.trimmingCharacters(in: .whitespaces)) }))
                lines = lines.dropFirst(items.count)
            } else if isBullet(trimmed) {
                let numbered = isNumbered(trimmed)
                let items = lines.prefix { line in
                    let text = line.trimmingCharacters(in: .whitespaces)
                    return isBullet(text) && isNumbered(text) == numbered && check(text) == nil
                }
                let words = items.map { item in
                    item.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^([-*+•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
                }
                blocks.append(numbered ? .numbered(words) : .bullets(words))
                lines = lines.dropFirst(items.count)
            } else {
                // At least this line ("#태그" is no heading, and would otherwise be read forever).
                let paragraph = lines.prefix(1) + lines.dropFirst().prefix { line in
                    let text = line.trimmingCharacters(in: .whitespaces)
                    return !text.isEmpty && !text.hasPrefix("#") && !text.hasPrefix("|") && !text.hasPrefix("```") && !text.hasPrefix(">")
                        && !isBullet(text)
                }
                blocks.append(.paragraph(paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")))
                lines = lines.dropFirst(paragraph.count)
            }
        }
        return blocks
    }

    /// The screen for "here" (where the pointer is), "left", "right" or "main"; anything else is "here".
    static func screenIndex(for choice: String, screens: [CGRect], pointer: CGPoint, main: Int) -> Int {
        guard !screens.isEmpty else { return 0 }
        switch choice {
        case "left": return screens.indices.min { screens[$0].minX < screens[$1].minX } ?? 0
        case "right": return screens.indices.max { screens[$0].minX < screens[$1].minX } ?? 0
        case "main": return min(max(main, 0), screens.count - 1)
        default: return screens.firstIndex { $0.contains(pointer) } ?? min(max(main, 0), screens.count - 1)
        }
    }

    /// A table cell that is all bold (`**189만 원**`): the better value, as its words; nil for any other cell.
    static func winCell(_ cell: String) -> String? {
        let text = cell.trimmingCharacters(in: .whitespaces)
        guard text.count > 4, text.hasPrefix("**"), text.hasSuffix("**") else { return nil }
        let inner = text.dropFirst(2).dropLast(2)
        guard !inner.contains("**"), !inner.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return String(inner)
    }

    /// `- [ ] words` or `- [x] words`; a box still arriving (`- [`, `- [ `) is an empty item, so a streaming item is a
    /// ring from the start instead of a dot that turns into one.
    private static func check(_ text: String) -> Check? {
        guard let marker = text.range(of: #"^[-*+]\s+\["#, options: .regularExpression) else { return nil }
        let rest = text[marker.upperBound...]
        if rest.isEmpty || rest == " " || rest == "x" || rest == "X" { return Check(text: "", done: false) }
        guard let box = rest.range(of: #"^[ xX]\](\s+|$)"#, options: .regularExpression) else { return nil }
        return Check(text: String(rest[box.upperBound...]), done: rest.first != " ")
    }

    private static func isDivider(_ cells: [String]) -> Bool {
        cells.allSatisfy { $0.range(of: "^:?-+:?$", options: .regularExpression) != nil }
    }

    private static func isBullet(_ text: String) -> Bool {
        text.range(of: #"^([-*+•]|\d+[.)])\s+"#, options: .regularExpression) != nil
    }

    private static func isNumbered(_ text: String) -> Bool {
        text.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil
    }

    private static func unquote(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces).dropFirst()
        if text.first == " " { text = text.dropFirst() }
        return String(text)
    }

    /// A table is drawn with at most this many columns and rows, and this many characters a cell; the rest is "…"
    /// (a 20,000-pipe row must not become 20,000 views on the main thread).
    static let tableColumns = 8
    static let tableRows = 60
    static let cellLength = 300

    private static func cells(of row: String) -> [String] {
        var text = row.trimmingCharacters(in: .whitespaces)[...]
        if text.hasPrefix("|") { text = text.dropFirst() }
        if text.hasSuffix("|") { text = text.dropLast() }
        let parts = text.split(separator: "|", maxSplits: tableColumns, omittingEmptySubsequences: false)
        let cells = parts.prefix(tableColumns).map { part -> String in
            let cell = part.trimmingCharacters(in: .whitespaces)
            return cell.count > cellLength ? String(cell.prefix(cellLength)) + "…" : cell
        }
        return parts.count > tableColumns ? Array(cells.dropLast()) + ["…"] : cells
    }
}
