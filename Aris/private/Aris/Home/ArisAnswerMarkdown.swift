//
//  ArisAnswerMarkdown.swift
//  Aris
//
//  Aris's answer as blocks (ArisAnswerAttributed; the open notch now draws ArisAnswerDocument's): paragraphs (line
//  breaks kept), headings, lists, quotes and fenced code. Inline marks (**bold**, `code`) are left in the text for
//  the renderer. A fence still open while the answer streams runs to the end. Pure, so the tests check it.
//

import Foundation

enum ArisAnswerMarkdown {
    struct Item: Equatable {
        let marker: String
        let text: String
    }

    enum Block: Equatable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case list([Item])
        case quote(String)
        case code(String)
    }

    static func blocks(from markdown: String) -> [Block] {
        var blocks: [Block] = []
        var lines = markdown.components(separatedBy: .newlines)[...]
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isRule(trimmed) {
                lines = lines.dropFirst()
            } else if trimmed.hasPrefix("```") {
                let body = lines.dropFirst().prefix { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
                blocks.append(.code(body.joined(separator: "\n")))
                lines = lines.dropFirst(body.count + 2)
            } else if let heading = heading(trimmed) {
                blocks.append(heading)
                lines = lines.dropFirst()
            } else if item(trimmed) != nil {
                let items = lines.prefix { item($0.trimmingCharacters(in: .whitespaces)) != nil }
                blocks.append(.list(items.compactMap { item($0.trimmingCharacters(in: .whitespaces)) }))
                lines = lines.dropFirst(items.count)
            } else if trimmed.hasPrefix(">") {
                let quoted = lines.prefix { $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
                blocks.append(.quote(quoted.map(unquote).joined(separator: "\n")))
                lines = lines.dropFirst(quoted.count)
            } else {
                let paragraph = lines.prefix { startsParagraphLine($0.trimmingCharacters(in: .whitespaces)) }
                blocks.append(.paragraph(paragraph.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")))
                lines = lines.dropFirst(paragraph.count)
            }
        }
        return blocks
    }

    /// `#` to `######` and a space; deeper than three draws as three.
    private static func heading(_ text: String) -> Block? {
        guard let hashes = text.range(of: "^#{1,6} ", options: .regularExpression) else { return nil }
        return .heading(level: min(3, text[hashes].count - 1), text: String(text[hashes.upperBound...]))
    }

    /// `-`, `*`, `+` or `•` and a space draw as a bullet; `1.` or `1)` keep their number.
    private static func item(_ text: String) -> Item? {
        guard let marker = text.range(of: #"^([-*+•]|\d{1,3}[.)])\s+"#, options: .regularExpression) else { return nil }
        let symbol = text[marker].trimmingCharacters(in: .whitespaces)
        return Item(marker: symbol.first?.isNumber == true ? symbol : "•", text: String(text[marker.upperBound...]))
    }

    private static func isRule(_ text: String) -> Bool {
        text.range(of: #"^([-*_])(\s*\1){2,}$"#, options: .regularExpression) != nil
    }

    private static func unquote(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces).dropFirst()
        if text.first == " " { text = text.dropFirst() }
        return String(text)
    }

    private static func startsParagraphLine(_ text: String) -> Bool {
        !text.isEmpty && !isRule(text) && !text.hasPrefix("```") && !text.hasPrefix(">") && heading(text) == nil && item(text) == nil
    }
}
