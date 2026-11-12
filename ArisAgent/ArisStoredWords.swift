//
//  ArisStoredWords.swift
//  aris-agent
//
//  What a to-do or a note will hold, for its confirm card (security review 2 M1). The to-do card showed only the
//  plain words: a new title, a note, a due date, a list and any word that began with "@" or "-" were stored without
//  being shown, so a yes to "우유" could rename a to-do to anything. And a note whose lines a Claude wrote as \n was
//  one long line, cut after 80 characters. Here the words are read exactly as aris-tools reads them (ArisTodoCommand's
//  todoOptions, ArisActions.noteRequest), and every one of them is on the card. Pure, so the tests run it.
//

import Foundation

enum ArisStoredWords {
    /// The flags aris-tools stores for a to-do, as the card names them.
    private static let todoLabels: [String: (korean: String, english: String)] = [
        "title": ("제목", "Title"), "note": ("메모", "Note"), "due": ("기한", "Due"), "list": ("목록", "List"),
    ]

    /// A to-do's words after its subcommand, as aris-tools splits them: every "--flag value" pair is a flag, anything
    /// else (a flag with nothing after it too) is part of the text.
    static func todo(_ words: [String]) -> (text: String, flags: [(name: String, value: String)]) {
        var text: [String] = [], flags: [(String, String)] = []
        var index = 0
        while index < words.count {
            if words[index].hasPrefix("--"), index + 1 < words.count {
                flags.append((String(words[index].dropFirst(2)), words[index + 1]))
                index += 2
            } else {
                text.append(words[index])
                index += 1
            }
        }
        return (text.joined(separator: " "), flags)
    }

    /// The to-do card's details: the text, then one line per flag with its whole value ("제목: …", "메모: …", "기한: …",
    /// "목록: …"; a flag aris-tools doesn't know as it was written). Nothing is cut, and anything invisible is shown.
    static func todoDetail(_ words: [String], english: Bool) -> String {
        let read = todo(words)
        let lines = [read.text] + read.flags.map { flag in
            let label = todoLabels[flag.name].map { english ? $0.english : $0.korean } ?? "--" + flag.name
            return label + ": " + flag.value
        }
        return lines.filter { !$0.isEmpty }.map(ArisDesktopCard.shown).joined(separator: "\n")
    }

    /// A note's text as Notes will hold it, from the words after `note`: `--markdown` (first) and `--checklist` only
    /// say which kind of note it is; every other word is the note's, one that begins with "--" too. A markdown note's
    /// line breaks written as \n are its lines (ArisNoteMarkdown reads them so).
    static func note(_ words: [String]) -> String {
        if words.first == "--markdown" {
            return words.dropFirst().joined(separator: " ").replacingOccurrences(of: #"(?<!\\)\\n"#, with: "\n", options: .regularExpression)
        }
        var kept = words
        if let flag = kept.firstIndex(of: "--checklist") { kept.remove(at: flag) }
        return kept.joined(separator: " ")
    }
}
