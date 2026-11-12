//
//  ArisVocabulary.swift
//  Aris
//
//  The user's own words (people, courses, apps, names) in ~/.config/aris/aris/vocabulary.txt, one a
//  line, # for comments. Apple's recognizer is told to expect them, so "노션" isn't heard as "노선".
//  (Whisper takes a prompt only with its language fixed in advance, which would lose Korean and English mixed.)
//

import Foundation

enum ArisVocabulary {
    static let path = ArisKeyFile.folder + "aris/vocabulary.txt"
    /// More than this and the hints stop helping.
    static let limit = 100
    static let wordLimit = 40

    /// The words in the file: trimmed, no comments or blanks, each once, too-long lines skipped.
    static func words(from text: String?) -> [String] {
        var seen = Set<String>()
        let words = (text ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.count <= wordLimit }
            .filter { seen.insert($0.lowercased()).inserted }
        return Array(words.prefix(limit))
    }

    /// Names everyone says to an assistant, expected even when the file leaves them out.
    static let builtIn = ["유튜브", "YouTube"]

    /// The user's own words: the file's, then those dictation learned from their fixes. The built-in names aren't
    /// theirs, and 단어장's count leaves them out (it said "2" on a new install).
    static func own(file: String?, learned: [String]) -> [String] {
        words(from: (file ?? "") + "\n" + learned.joined(separator: "\n"))
    }

    /// What the recognisers are told to expect: the user's words, then the built-in names they don't already have.
    static func expected(own: [String]) -> [String] {
        let known = Set(own.map { $0.lowercased() })
        return Array((own + builtIn.filter { !known.contains($0.lowercased()) }).prefix(limit))
    }

    static func loadOwn() -> [String] {
        let learned = ArisLearnedDictionary.load(from: ArisLearnedDictionary.file(home: UserHome.path)).texts
        return own(file: try? String(contentsOfFile: path, encoding: .utf8), learned: learned)
    }

    /// The file's words, then those dictation learned from the user's fixes (ArisLearnedDictionary), then the built-in ones.
    static func load() -> [String] { expected(own: loadOwn()) }
}

/// Words the recognizers keep mishearing even with the hints (Scribe heard 노션 as 로션 and 우유 as 모유, Apple heard
/// YouTube as 뉴큐브; 2026-11-02), put right after the turn. A real word is only replaced when the rest of the
/// sentence shows which was meant: "로션 사야 돼" stays.
enum ArisHeardFix {
    private struct Confusion {
        let meant: String
        let heard: [String]
        /// Words one of which must be in the sentence; nil: the misheard form is never meant.
        let context: [String]?
    }

    private static let confusions = [
        Confusion(meant: "노션", heard: ["로션", "노선"],
                  context: ["정리", "적어", "기록", "저장", "메모", "페이지", "열어", "에서 찾", "캘린더", "데이터베이스", "워크스페이스"]),
        Confusion(meant: "유튜브", heard: ["뉴큐브", "뉴튜브", "유투브", "유트브", "유큐브"], context: nil),
        Confusion(meant: "우유", heard: ["모유"], context: ["사기", "사야", "사 와", "사와", "장보", "마트", "할 일", "할일", "추가", "리스트", "목록"]),
    ]

    static func corrected(_ text: String) -> String {
        confusions.reduce(text) { text, confusion in
            if let context = confusion.context, !context.contains(where: text.contains) { return text }
            return confusion.heard.reduce(text) { $0.replacingOccurrences(of: $1, with: confusion.meant) }
        }
    }
}
