//
//  ArisNoteMarkdown.swift
//  aris-tools
//
//  `note --markdown "<md>"`: the answer shape (the owner's pick A) as an Apple Notes note. The first line is the title, then
//  `###` labels as subheadings, `-` bullets and numbered lists as Notes lists, **bold** and *italics*, tables as Notes
//  tables, and `- [ ]` items as plain lines that ArisNoteCommand turns into real checklists with Notes' own ⇧⌘L.
//  Notes' AppleScript can't make checklist items, so the plan also says which paragraphs each checklist is and the keys
//  that select exactly them: counted from the end (⌘↓, ⌥↑ per paragraph, ⌥⇧↑ per item, the old way) or, when that's
//  shorter or a table is in the way, from the top (⌘↑, ⌥↓, ⌥⇧↓). Keys never count across a table (how many
//  paragraphs Notes makes of one isn't known). Words are escaped: nothing in them is markup. Pure, so it's tested.
//

import Foundation

enum ArisNoteMarkdown {
    /// Paragraphs `start ..< start + count` (0 is the title) become one checklist.
    struct Group: Equatable {
        let start: Int
        let count: Int
    }

    struct Plan: Equatable {
        let title: String
        let html: String
        /// Each paragraph's words as the note shows them, the title first; a table's place holds "".
        let paragraphs: [String]
        let groups: [Group]
        /// The paragraph places that are tables.
        let tables: [Int]
    }

    /// The most keys pressed for one checklist (a far-away list stays plain lines).
    static let keyLimit = 80
    /// At most this many checklists get keys in one note, and this many keys in all; the rest stay plain lines.
    static let listLimit = 4
    static let keyBudget = 200
    /// A line is cut at this many characters (no pattern ever runs over more), a note at this many lines.
    static let lineLength = 2_000
    static let lineCount = 1_000

    static func plan(_ markdown: String) -> Plan? {
        var lines = newlines(markdown).components(separatedBy: .newlines).prefix(lineCount * 2)
            .map { String(clean($0).prefix(lineLength)).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("```") }.prefix(lineCount)[...]
        guard let first = lines.first else { return nil }
        let title = words(first.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression))
        guard !title.isEmpty else { return nil }
        var builder = Builder(title: title)
        lines = lines.dropFirst()
        while let line = lines.first {
            if line.hasPrefix("|") {
                let rows = lines.prefix { $0.hasPrefix("|") }
                builder.table(Array(rows))
                lines = lines.dropFirst(rows.count)
            } else if let kind = listKind(line) {
                let items = lines.prefix { listKind($0) == kind }
                if kind == .checklist { builder.checklist(items.map(itemWords)) } else { builder.list(items.map(itemWords), ordered: kind == .numbered) }
                lines = lines.dropFirst(items.count)
            } else {
                builder.line(line)
                lines = lines.dropFirst()
            }
        }
        return builder.plan
    }

    /// A literal \n (as the board takes it) is a new line only in markdown written on one line, and never after another
    /// backslash: markdown with real line breaks keeps every backslash as written (a path, code).
    static func newlines(_ markdown: String) -> String {
        guard !markdown.contains(where: \.isNewline) else { return markdown }
        return markdown.replacingOccurrences(of: #"(?<!\\)\\n"#, with: "\n", options: .regularExpression)
    }

    /// No control or format characters (a bidi override, a zero-width space) except tabs.
    static func clean(_ line: String) -> String {
        String(String.UnicodeScalarView(line.unicodeScalars.filter { scalar in
            scalar == "\t" || ![.control, .format].contains(scalar.properties.generalCategory)
        }))
    }

    /// Which checklists get keys: in order, those with a safe way to them, at most listLimit and keyBudget keys in all;
    /// `skipped` stay plain lines.
    static func pressing(_ plan: Plan) -> (lists: [(group: Group, keys: [String])], skipped: Int) {
        var lists: [(group: Group, keys: [String])] = []
        var used = 0
        for group in plan.groups {
            guard lists.count < listLimit, let keys = keys(for: group, in: plan), used + keys.count <= keyBudget else { continue }
            lists.append((group, keys))
            used += keys.count
        }
        return (lists, plan.groups.count - lists.count)
    }

    /// Whether what Notes has selected, right before ⇧⌘L, is exactly the list's items.
    static func selectionMatches(_ selected: String, group: Group, plan: Plan) -> Bool {
        var lines = selected.components(separatedBy: .newlines).map(shown)
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines == plan.paragraphs[group.start..<(group.start + group.count)].map(shown)
    }

    /// The keys that select exactly `group`'s paragraphs and make them a checklist; nil when no safe, short way exists.
    static func keys(for group: Group, in plan: Plan) -> [String]? {
        guard (1...ArisActions.checklistLimit).contains(group.count) else { return nil }
        switch route(for: group, in: plan) {
        case .fromEnd(let back):
            return ["cmd+down"] + Array(repeating: "opt+up", count: back) + (back > 0 ? ["left"] : [])
                + Array(repeating: "opt+shift+up", count: group.count) + ["cmd+shift+l"]
        case .fromTop:
            return ["cmd+up"] + Array(repeating: "opt+down", count: group.start) + ["right"]
                + Array(repeating: "opt+shift+down", count: group.count) + ["cmd+shift+l"]
        case nil:
            return nil
        }
    }

    /// Whether the note's text on screen is the planned one, up to the end the keys come from: its title, and every
    /// paragraph between that end and the last item, in place. List markers and spacing aren't compared.
    static func matchesGroup(text: String, group: Group, plan: Plan) -> Bool {
        var lines = text.components(separatedBy: .newlines).map(shown)
        while lines.last?.isEmpty == true { lines.removeLast() }
        let planned = plan.paragraphs.map(shown)
        guard let route = route(for: group, in: plan), lines.first == planned.first else { return false }
        switch route {
        case .fromEnd:
            let tail = planned.count - group.start
            return lines.count >= tail && Array(lines.suffix(tail)) == Array(planned.suffix(tail))
        case .fromTop:
            let head = group.start + group.count
            return lines.count >= head && Array(lines.prefix(head)) == Array(planned.prefix(head))
        }
    }

    /// A titled checklist (`note "<title>" --checklist …`): the same note it always made, as a plan.
    static func checklist(title: String, items: [String]) -> Plan {
        Plan(title: title, html: ArisActions.noteBody(title: title, lines: items), paragraphs: [title] + items,
             groups: [Group(start: 1, count: items.count)], tables: [])
    }

    // MARK: - Routes

    private enum Route: Equatable {
        /// From the end, `back` paragraphs up to the one after the items.
        case fromEnd(back: Int)
        case fromTop
    }

    /// From the end (the old way) unless a table is after the items or it's too far; then from the top, unless a table
    /// is before them or that's too far too.
    private static func route(for group: Group, in plan: Plan) -> Route? {
        let last = group.start + group.count - 1
        guard group.start >= 1, last < plan.paragraphs.count else { return nil }
        let back = plan.paragraphs.count - 1 - last
        if !plan.tables.contains(where: { $0 > last }), 1 + back + (back > 0 ? 1 : 0) + group.count + 1 <= keyLimit {
            return .fromEnd(back: back)
        }
        if !plan.tables.contains(where: { $0 < group.start }), 1 + group.start + 1 + group.count + 1 <= keyLimit {
            return .fromTop
        }
        return nil
    }

    /// A line as compared: no list marker, single spaces.
    private static func shown(_ line: String) -> String {
        line.replacingOccurrences(of: #"^[\s\t]*([•◦▪●○\-–·]|\d{1,3}[.)])[\s\t]+"#, with: "", options: .regularExpression)
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Lines

    private enum ListKind { case bullets, numbered, checklist }

    private static func listKind(_ line: String) -> ListKind? {
        if line.range(of: #"^[-*+]\s+\[[ xX]\]\s+\S"#, options: .regularExpression) != nil { return .checklist }
        if line.range(of: #"^[-*+•]\s+\S"#, options: .regularExpression) != nil { return .bullets }
        if line.range(of: #"^\d{1,3}[.)]\s+\S"#, options: .regularExpression) != nil { return .numbered }
        return nil
    }

    private static func itemWords(_ line: String) -> String {
        line.replacingOccurrences(of: #"^([-*+•]\s+\[[ xX]\]|[-*+•]|\d{1,3}[.)])\s+"#, with: "", options: .regularExpression)
    }

    private struct Builder {
        var html: String
        var paragraphs: [String]
        var groups: [Group] = []
        var tables: [Int] = []
        let title: String

        init(title: String) {
            self.title = title
            html = "<div><h1>\(escaped(title))</h1></div>"
            paragraphs = [title]
        }

        var plan: Plan { Plan(title: title, html: html, paragraphs: paragraphs, groups: groups, tables: tables) }

        mutating func line(_ line: String) {
            if let hashes = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                let text = String(line[hashes.upperBound...])
                guard !words(text).isEmpty else { return }
                let tag = line[hashes].filter { $0 == "#" }.count >= 3 ? "h3" : "h2"
                add("<div><\(tag)>\(inline(text))</\(tag)></div>", words: words(text))
            } else {
                let text = line.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
                add("<div>\(inline(text))</div>", words: words(text))
            }
        }

        mutating func list(_ items: [String], ordered: Bool) {
            let tag = ordered ? "ol" : "ul"
            html += "<\(tag)>" + items.map { "<li>\(inline($0))</li>" }.joined() + "</\(tag)>"
            paragraphs += items.map(words)
        }

        /// `- [ ]` items stay plain lines; ⇧⌘L makes them a checklist.
        mutating func checklist(_ items: [String]) {
            groups.append(Group(start: paragraphs.count, count: items.count))
            for item in items { add("<div>\(inline(item))</div>", words: words(item)) }
        }

        mutating func table(_ rows: [String]) {
            let cells = rows.map(Self.cells)
            let divider = { (row: [String]) in row.allSatisfy { $0.range(of: "^:?-+:?$", options: .regularExpression) != nil } }
            let header = cells.count > 1 && divider(cells[1])
            let body = cells.enumerated().filter { !divider($0.element) }
            html += "<table>" + body.map { index, row in
                "<tr>" + row.map { "<td>" + (header && index == 0 ? "<b>\(inline($0))</b>" : inline($0)) + "</td>" }.joined() + "</tr>"
            }.joined() + "</table>"
            tables.append(paragraphs.count)
            paragraphs.append("")
        }

        private mutating func add(_ piece: String, words: String) {
            html += piece
            paragraphs.append(words)
        }

        private static func cells(_ row: String) -> [String] {
            var text = row
            if text.hasPrefix("|") { text.removeFirst() }
            if text.hasSuffix("|") { text.removeLast() }
            return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    // MARK: - Inline

    /// Links as their words and address, images as their words, code without its marks: what's left of the line.
    private static func flattened(_ text: String) -> String {
        text.replacingOccurrences(of: #"!\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]*)\]\(([^)\s]*)\)"#, with: "$1 ($2)", options: .regularExpression)
            .replacingOccurrences(of: "`", with: "")
    }

    /// The words a line shows in Notes.
    static func words(_ text: String) -> String {
        emphasis(flattened(text), bold: ("", ""), italic: ("", "")).trimmingCharacters(in: .whitespaces)
    }

    /// The line as Notes' HTML: escaped first, so only these tags are ever markup.
    static func inline(_ text: String) -> String {
        emphasis(escaped(flattened(text).trimmingCharacters(in: .whitespaces)), bold: ("<b>", "</b>"), italic: ("<i>", "</i>"))
    }

    /// `**bold**` and `*italic*` matched in one pass, left to right, each one's inside done the same way (so tags always
    /// nest: `**a *b* c**`, `*a **b** c*`); a marker with no partner stays as written.
    private static let emphasisPattern = try! NSRegularExpression(pattern: #"\*\*(\S(?:.*?\S)?)\*\*|(?<!\*)\*(?!\*)(\S(?:.*?\S)?)(?<!\*)\*(?!\*)"#)

    private static func emphasis(_ text: String, bold: (String, String), italic: (String, String), depth: Int = 0) -> String {
        guard depth < 3, text.contains("*") else { return text }
        let source = text as NSString
        var out = ""
        var at = 0
        for match in emphasisPattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: at, length: match.range.location - at))
            let isBold = match.range(at: 1).location != NSNotFound
            let inner = source.substring(with: match.range(at: isBold ? 1 : 2))
            let (open, close) = isBold ? bold : italic
            out += open + emphasis(inner, bold: bold, italic: italic, depth: depth + 1) + close
            at = match.range.location + match.range.length
        }
        return out + source.substring(from: at)
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
