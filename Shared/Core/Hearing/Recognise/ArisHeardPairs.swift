//
//  ArisHeardPairs.swift
//  Aris (Shared/Core, Foundation only)
//
//  The owner's own dictionary (Settings › 단어장, ~/.config/aris/aris/vocabulary.txt): one entry a line. A plain line is
//  a word Aris should know ("Notion"). A line with an arrow is a pair, how it is heard and how it is meant
//  ("로션 -> 노션", also → or =>). The words (a pair's written form is one too) go to the recognisers as hints; the pairs
//  are put right in what was heard, and the repair pass is told them. At most 100 of each, 40 characters a side.
//

import Foundation

struct ArisHeardPair: Equatable, Sendable {
    let heard: String
    let meant: String
}

enum ArisHeardPairs {
    static let limit = 100
    static let length = 40
    /// A heard form shorter than this is told to the repair pass but never replaced by itself: one syllable is inside too many words.
    static let shortestApplied = 2
    private static let arrows = ["->", "=>", "→"]

    struct Entries: Equatable, Sendable {
        var words: [String]
        var pairs: [ArisHeardPair]
    }

    static func entries(from text: String?) -> Entries {
        var entries = Entries(words: [], pairs: [])
        var seen = Set<String>()
        for line in (text ?? "").split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            var word = line
            if let arrow = arrows.first(where: line.contains), let range = line.range(of: arrow) {
                let heard = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let meant = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !heard.isEmpty, !meant.isEmpty, heard.count <= length, meant.count <= length else { continue }
                if entries.pairs.count < limit, !entries.pairs.contains(where: { $0.heard.caseInsensitiveCompare(heard) == .orderedSame }) {
                    entries.pairs.append(ArisHeardPair(heard: heard, meant: meant))
                }
                word = meant
            }
            guard word.count <= length, entries.words.count < limit, seen.insert(word.lowercased()).inserted else { continue }
            entries.words.append(word)
        }
        return entries
    }

    /// `text` with every heard form written as it was meant, the longest heard form first.
    static func applied(_ text: String, pairs: [ArisHeardPair]) -> String {
        pairs.filter { $0.heard.count >= shortestApplied }.sorted { $0.heard.count > $1.heard.count }.reduce(text) { text, pair in
            text.replacingOccurrences(of: pair.heard, with: pair.meant, options: .caseInsensitive)
        }
    }
}
