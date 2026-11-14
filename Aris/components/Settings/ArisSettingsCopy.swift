//
//  ArisSettingsCopy.swift
//  Aris
//
//  The settings window in English (fresh install F5: on an English Mac the guide was English and every settings page
//  Korean). The pages stay written in Korean, as they are in the code; where a page is drawn, each title, line,
//  heading, chip, option and toast is looked up in the settings string catalog (Settings.xcstrings: the Korean string
//  is the key, its English the value) and shown in English when the UI is English.
//
//  A sentence with a name or a number in it is one catalog entry with `%@` (anything) or `%d` (a number) where the
//  value goes: "권한 %d개가 더 필요해요" → "%d more permissions needed". The English may put the values in another
//  order with `%1$@`, `%2$@`.
//
//  A line of parts joined by " · " ("취향 · 11월 3일 · 내가 말함") is said part by part, and a value that is itself a
//  sentence of the catalog (a key's name inside a longer line) is said in English inside it. A value the Korean
//  writes in quotation marks (‘%@’ 넣을까요?) is a name or the user's own word, and stays as it is.
//
//  A page is English only once all of it is (translatedPages): a page with half its rows translated is worse than a
//  Korean one. Every page has its English now; a page added later stays wholly Korean until it is listed there. What
//  the user named or typed (a Reminders list, a calendar, a memory, a learned word) is never translated. The window's
//  frame (the sidebar, the search) is English whenever the UI is. Foundation only (tested).
//

import Foundation

enum ArisSettingsCopy {
    /// The pages drawn in English on an English Mac: all of them. A page whose strings aren't all in the catalog yet
    /// is left out here, and is then drawn wholly in Korean.
    static let translatedPages = Set(ArisSettingsPage.allCases)

    /// The compiled catalog's name in the app (en.lproj/Settings.strings).
    static let tableName = "Settings"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var table: ArisSettingsCopyTable?

    /// Replaces the table (the tests install the catalog's pairs; the app reads its compiled catalog on first use).
    static func install(_ pairs: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        table = ArisSettingsCopyTable(withMore(pairs))
    }

    /// The catalog's pairs and the rows' own (ArisSettingsCopyMore), the catalog's first: one table, so a row's own pair
    /// with a number in it ("기록 %d개") is a pattern too, and a part of a dotted line finds it (seventh VM pass: "기록
    /// 1개" stayed Korean on an English Mac).
    static func withMore(_ pairs: [String: String]) -> [String: String] {
        pairs.merging(ArisSettingsCopyMore.english) { catalog, _ in catalog }
    }

    /// The English for a Korean string, or nil when the catalog has none.
    static func english(_ korean: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if table == nil { table = ArisSettingsCopyTable(withMore(compiled())) }
        // Rows added since the catalog was last written carry their English beside them (ArisSettingsCopyMore).
        return table?.english(korean) ?? ArisSettingsCopyMore.english[korean]
    }

    /// The English when there is one, else the string as it is (a name, a number, a line with no entry yet).
    static func t(_ korean: String) -> String { english(korean) ?? korean }

    /// The app's compiled catalog: Korean → English.
    private static func compiled() -> [String: String] {
        guard let url = Bundle.main.url(forResource: tableName, withExtension: "strings", subdirectory: nil, localization: "en"),
              let data = try? Data(contentsOf: url),
              let pairs = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String] else { return [:] }
        return pairs
    }

    /// The pairs of a string catalog file (.xcstrings), as the app's compiled table has them (the tests read the file).
    static func pairs(catalog data: Data) -> [String: String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let strings = root["strings"] as? [String: Any] else { return [:] }
        return strings.reduce(into: [:]) { pairs, entry in
            let places = (entry.value as? [String: Any])?["localizations"] as? [String: Any]
            let unit = (places?["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            if let value = unit?["value"] as? String { pairs[entry.key] = value }
        }
    }
}

/// The catalog's pairs, with the entries that carry `%@` or `%d` kept as patterns.
struct ArisSettingsCopyTable {
    private let exact: [String: String]
    /// `quoted`: for each value, whether the Korean writes it in quotation marks.
    private let patterns: [(regex: NSRegularExpression, english: String, quoted: [Bool])]
    private var found: [String: String?] = [:]

    init(_ pairs: [String: String]) {
        exact = pairs.filter { !Self.hasPlaceholder($0.key) }
        // The longest key first: the most specific sentence wins over a short one that would also fit.
        patterns = pairs.filter { Self.hasPlaceholder($0.key) }.sorted { ($0.key.count, $0.key) > ($1.key.count, $1.key) }
            .compactMap { key, english in Self.regex(key).map { ($0, english, Self.quoted(key)) } }
    }

    static func hasPlaceholder(_ key: String) -> Bool { key.contains("%@") || key.contains("%d") }

    /// "권한 %d개가 더 필요해요" as a pattern: the literal parts as they are, `%d` a number, `%@` anything.
    static func regex(_ key: String) -> NSRegularExpression? {
        var pattern = "^", rest = Substring(key)
        while true {
            // The earlier of the two kinds.
            let any = rest.range(of: "%@"), number = rest.range(of: "%d")
            guard let next = [any, number].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            pattern += NSRegularExpression.escapedPattern(for: String(rest[..<next.lowerBound]))
            pattern += rest[next] == "%d" ? #"(-?[0-9]+(?:[.,][0-9]+)?)"# : "(.+?)"
            rest = rest[next.upperBound...]
        }
        pattern += NSRegularExpression.escapedPattern(for: String(rest)) + "$"
        return try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
    }

    /// For each value of `key`, in order: whether it comes right after an opening quotation mark (‘%@’, “%@ 스킬로 해줘”).
    static func quoted(_ key: String) -> [Bool] {
        var marks: [Bool] = [], rest = Substring(key)
        while let next = [rest.range(of: "%@"), rest.range(of: "%d")].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) {
            marks.append(rest[..<next.lowerBound].last.map { "‘“".contains($0) } ?? false)
            rest = rest[next.upperBound...]
        }
        return marks
    }

    mutating func english(_ korean: String) -> String? {
        if let known = exact[korean] { return known }
        if let cached = found[korean] { return cached }
        let result = matched(korean, depth: 0) ?? parts(korean)
        // Sentences with a value in them come back many times while a page is on screen.
        if found.count < 2_000 { found[korean] = result }
        return result
    }

    private func matched(_ korean: String, depth: Int) -> String? {
        let whole = NSRange(korean.startIndex..., in: korean)
        for (regex, english, quoted) in patterns {
            guard let match = regex.firstMatch(in: korean, range: whole) else { continue }
            let values = (1..<match.numberOfRanges).map { index -> String in
                guard let range = Range(match.range(at: index), in: korean) else { return "" }
                // A name or the user's own word in quotation marks is never translated.
                return quoted[index - 1] ? String(korean[range]) : value(String(korean[range]), depth: depth)
            }
            return Self.filled(english, values)
        }
        return nil
    }

    /// A value that is itself one of the catalog's words (a tab's name, an AI's), a sentence of it (a key's line inside
    /// a longer one), or a list of its words, is said in English too; any other stays as it is.
    private func value(_ text: String, depth: Int) -> String {
        if let known = exact[text] { return known }
        if depth < Self.deepest, let sentence = matched(text, depth: depth + 1) { return sentence }
        return text.components(separatedBy: ", ").map { exact[$0] ?? $0 }.joined(separator: ", ")
    }

    /// A sentence inside a sentence inside a sentence is as far as any line goes.
    private static let deepest = 2

    /// A line of parts joined by " · " ("취향 · 11월 3일 · 내가 말함"), each part said in English; a part with no English
    /// stays as it is (a name, a number). Nil when none of them has any.
    private func parts(_ korean: String) -> String? {
        let pieces = korean.components(separatedBy: Self.joint)
        guard pieces.count > 1 else { return nil }
        let said = pieces.map { exact[$0] ?? matched($0, depth: 0) }
        guard said.contains(where: { $0 != nil }) else { return nil }
        return zip(pieces, said).map { $1 ?? $0 }.joined(separator: Self.joint)
    }

    private static let joint = " · "

    /// The English with its values in: `%1$@`, `%2$d` by position; plain `%@` and `%d` in order.
    static func filled(_ english: String, _ values: [String]) -> String {
        var out = english
        for (index, value) in values.enumerated() {
            out = out.replacingOccurrences(of: "%\(index + 1)$@", with: value).replacingOccurrences(of: "%\(index + 1)$d", with: value)
        }
        for value in values {
            let any = out.range(of: "%@"), number = out.range(of: "%d")
            guard let next = [any, number].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { break }
            out.replaceSubrange(next, with: value)
        }
        return out
    }
}

/// How the part of the window being drawn words itself: handed down to every settings view, which passes each Korean
/// string through it where it draws one.
struct ArisSettingsWording: Equatable {
    /// The page's own text is drawn in English (the UI is English and the whole page has its English).
    var pageEnglish = false
    /// The window's frame is: the sidebar, the search, the page names.
    var frameEnglish = false

    static let korean = ArisSettingsWording()

    static func make(page: ArisSettingsPage, english: Bool) -> ArisSettingsWording {
        ArisSettingsWording(pageEnglish: english && ArisSettingsCopy.translatedPages.contains(page), frameEnglish: english)
    }

    /// A string of the page: English on a page that is all English, else as written.
    func callAsFunction(_ korean: String) -> String { pageEnglish ? ArisSettingsCopy.t(korean) : korean }

    func callAsFunction(_ korean: String?) -> String? { korean.map { self($0) } }

    /// A string of the window's frame.
    func frame(_ korean: String) -> String { frameEnglish ? ArisSettingsCopy.t(korean) : korean }

    /// A page's name, its line and anything else that belongs to `page` drawn outside it (a search result): English
    /// only when that page is.
    func of(_ page: ArisSettingsPage, _ korean: String) -> String {
        frameEnglish && ArisSettingsCopy.translatedPages.contains(page) ? ArisSettingsCopy.t(korean) : korean
    }

    // MARK: A page's rows

    /// The sections as the page draws them: every string that is shown, in this wording. Ids, keys, what the user
    /// named or typed and a shortcut's key caps are left as they are.
    func sections(_ sections: [ArisSettingSection]) -> [ArisSettingSection] {
        guard pageEnglish else { return sections }
        return sections.map { section in
            ArisSettingSection(id: section.id, heading: self(section.heading), note: self(section.note), grouped: section.grouped, rows: section.rows.map(row),
                               fold: section.fold.map { ArisSettingFold(title: self($0.title), desc: dotted($0.desc), symbol: $0.symbol) })
        }
    }

    /// A line of parts joined by " · " in this wording: as a whole when the settings catalog has it, else part by part
    /// ("Claude · 대화가 Mac 밖으로 나가요": the name stays, the rest is said in English; a fold's "닫기 · 방향 · 감도").
    /// A name, a model's id or a voice's own description has no entry and is drawn as it is.
    func dotted(_ korean: String) -> String {
        guard pageEnglish else { return korean }
        if let whole = ArisSettingsCopy.english(korean) { return whole }
        let parts = korean.components(separatedBy: " · ")
        return parts.count > 1 ? parts.map { ArisSettingsCopy.t($0) }.joined(separator: " · ") : korean
    }

    func row(_ item: ArisSettingItem) -> ArisSettingItem {
        guard pageEnglish else { return item }
        let own = Self.userWords(item.id)
        return ArisSettingItem(id: item.id, icon: item.icon, title: own.title ? item.title : self(item.title), desc: own.desc ? item.desc : self(item.desc),
                               control: control(item.control), extra: extra(item.extra), danger: item.danger, indexed: item.indexed)
    }

    /// The rows that show the user's own words: a Reminders list and a calendar (its name, its account), a memory and
    /// a learned word (the words themselves; the line under them is Aris's). A list named 캘린더 stays 캘린더.
    static func userWords(_ row: String) -> (title: Bool, desc: Bool) {
        if row.hasPrefix("todo.list.") || row.hasPrefix("calendar.cal.") { return (true, true) }
        if row.hasPrefix("memory.item.") || row.hasPrefix("dictation.learned.") { return (true, false) }
        return (false, false)
    }

    /// The menus whose choices are the user's own names: the Reminders lists to pick from.
    static func namesUserWords(_ key: ArisSettingKey) -> Bool { key == .todoDefault }

    /// This wording for a part of the page that shows the user's own words (such a menu's button and its list): drawn
    /// as they are written, whatever the catalog has.
    var verbatim: ArisSettingsWording { ArisSettingsWording(pageEnglish: false, frameEnglish: frameEnglish) }

    private func option(_ option: ArisSettingOption) -> ArisSettingOption {
        ArisSettingOption(id: option.id, title: self(option.title), detail: self(option.detail))
    }

    private func button(_ button: ArisSettingButton) -> ArisSettingButton {
        ArisSettingButton(title: self(button.title), action: button.action, kind: button.kind, enabled: button.enabled)
    }

    private func control(_ control: ArisSettingControl) -> ArisSettingControl {
        switch control {
        case .none, .toggle, .shortcut, .trailing, .custom, .empty, .loading: control
        // A key that can't be changed is named in words (오른쪽 ⌥).
        case .caps(let caps): .caps(caps.map { self($0) })
        case .choice(let key, let options, let selected, let disabled, let lead):
            .choice(key, options.map(option), selected: selected, disabled: disabled, lead: lead.map(button))
        case .menu(let key, _, _) where Self.namesUserWords(key): control
        case .menu(let key, let options, let selected):
            .menu(key, options.map { choice in ArisSettingsCopyMore.option(key, id: choice.id).map { ArisSettingOption(id: choice.id, title: $0) } ?? option(choice) },
                  selected: selected)
        case .buttons(let buttons): .buttons(buttons.map(button))
        case .status(let ok, let next): .status(ok: ok, next.map(button))
        case .link(let action, let value): .link(action, value: self(value))
        case .slider(let key, let value, let min, let max, let unit, let step, let zero):
            .slider(key, value: value, min: min, max: max, unit: self(unit), step: step, zero: self(zero))
        case .chip(let text, let tone): .chip(self(text), tone: tone)
        case .said(let text): .said(self(text))
        case .field(let key, let text, let placeholder, let action): .field(key, text: text, placeholder: self(placeholder), button(action))
        }
    }

    private func extra(_ extra: ArisSettingExtra) -> ArisSettingExtra {
        switch extra {
        case .none, .swatches: extra
        }
    }

    // MARK: What a page shows, for the checks

    /// Every string `sections` puts on screen (the tests look for Korean left in an English page).
    static func shown(_ sections: [ArisSettingSection]) -> [String] {
        sections.flatMap { section in
            [section.heading, section.note, section.fold?.title].compactMap { $0 } + (section.fold?.desc.components(separatedBy: " · ") ?? []) + section.rows.flatMap { row in
                [row.title, row.desc].compactMap { $0 } + shown(row.control)
            }
        }
    }

    private static func shown(_ control: ArisSettingControl) -> [String] {
        switch control {
        case .none, .toggle, .shortcut, .trailing, .custom, .empty, .loading: []
        case .caps(let caps): caps
        case .choice(_, let options, _, _, let lead): options.flatMap { [$0.title, $0.detail].compactMap { $0 } } + (lead.map { [$0.title] } ?? [])
        case .menu(_, let options, _): options.flatMap { [$0.title, $0.detail].compactMap { $0 } }
        case .buttons(let buttons): buttons.map(\.title)
        case .status(_, let next): next.map { [$0.title] } ?? []
        case .link(_, let value): value.map { [$0] } ?? []
        case .slider(_, _, _, _, let unit, _, let zero): [unit] + (zero.map { [$0] } ?? [])
        case .chip(let text, _): [text]
        case .said(let text): [text]
        case .field(_, _, let placeholder, let action): [placeholder, action.title]
        }
    }
}
