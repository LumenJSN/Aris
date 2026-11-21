//
//  ArisTextClip.swift
//  Shared/Core/Trust (aris-agent, Aris, tests, swift test)
//
//  A card line made shorter: it ends at a whole word with "…", never mid-word and never without a mark that more was
//  there (sixth VM run, item 5: a collapsed English replace card read "‘Replaced all’ (what was there", cut at 90
//  characters with nothing to say it was cut). The whole line is always on the card's 전체 보기 / Show all. Pure.
//

import Foundation

enum ArisTextClip {
    static let mark = "…"

    /// `text` in at most `limit` characters (the "…" counted): whole when it fits; else cut at the last space or
    /// break within the limit (when that keeps at least half of it; a long word or a line with no spaces, as Korean
    /// often is not, is cut at the limit), with what dangles at the cut (an opening bracket or quote, a comma, a
    /// space) taken off, then "…".
    static func clip(_ text: String, _ limit: Int) -> String {
        guard text.count > limit else { return text }
        guard limit > 1 else { return mark }
        let room = Array(text.prefix(limit - 1))
        var end = room.count
        // The cut falls inside a word: back to the space before it.
        let next = text[text.index(text.startIndex, offsetBy: limit - 1)]
        if !isBreak(next), let space = room.lastIndex(where: isBreak), space >= room.count / 2 { end = space }
        var kept = String(room[..<end])
        while let last = kept.last, isBreak(last) || dangling.contains(last) { kept.removeLast() }
        return kept + mark
    }

    private static func isBreak(_ character: Character) -> Bool { character.isWhitespace }

    /// What is left hanging at a cut: an opening bracket or quote, a joiner.
    private static let dangling: Set<Character> = ["(", "[", "{", "“", "‘", "「", "『", "\"", "'", ",", ";", ":", "-", "–", "—", "/", "·"]
}
