//
//  ArisEventCard.swift
//  aris-agent
//
//  The user's card for `aris-tools event delete|change` (QA BUG-53): the exact event, in plain words, from the command's
//  own --title and --start, which aris-tools checks against the event's id when it runs (ArisEventEdit.named).
//

import Foundation

enum ArisEventCard {
    /// Whether these aris-tools words (after `event`) change or remove an event: always the user's card.
    static func isEdit(_ words: [String]) -> Bool { ["delete", "change"].contains(words.first ?? "") }

    /// The card's words for `event delete|change --id … --title … --start …` (the command's own text, which `named`
    /// checks against the event when it runs).
    static func card(_ words: [String]) -> (title: String, detail: String)? {
        guard let verb = words.first, verb == "delete" || verb == "change" else { return nil }
        var rest = Array(words.dropFirst())
        guard let title = option("--title", in: &rest).map(clean), let start = option("--start", in: &rest).map(clean), option("--id", in: &rest) != nil else { return nil }
        if verb == "delete" { return ("일정 지우기", "“\(title)” · \(start)\n이 일정 하나만 지워요") }
        var lines = ["“\(title)” · \(start)"]
        if let to = option("--to", in: &rest).map(clean) { lines.append("시간: \(start) → \(to)") }
        if let name = option("--rename", in: &rest).map(clean) { lines.append("이름: “\(title)” → “\(name)”") }
        return ("일정 바꾸기", lines.joined(separator: "\n"))
    }

    /// The words as given, in full (never cut: a rename shortened on the card could hide what it really becomes, security
    /// review of batch 3), with control, bidi and zero-width characters made visible. aris-tools caps them (200).
    private static func clean(_ text: String) -> String { ArisDesktopCard.shown(text) }

    static func option(_ flag: String, in words: inout [String]) -> String? {
        guard let index = words.firstIndex(of: flag), index + 1 < words.count else { return nil }
        let value = words[index + 1]
        words.removeSubrange(index...(index + 1))
        return value
    }
}
