//
//  ArisEndpoint.swift
//  Aris
//
//  Does what you said sound finished? "내일 날씨 알려줘" does; "내일 날씨랑" doesn't.
//  A finished-sounding sentence lets Aris stop listening sooner (ArisTalkKey). When in
//  doubt it says no, which only means waiting as long as before.
//

import Foundation

enum ArisEndpoint {
    /// Last syllables that end a Korean request, question or statement (알려줘, 와요, 몇 시야, 보낼까, 음악 꺼).
    /// Not 어/아/지/다/해: they just as often go on (열어서, 오는지, 끝났다가, 정리해서), and the recognizer's
    /// half-heard guess stops on them mid-word, which ended turns while the user was still talking.
    private static let finishedSyllables: Set<Character> = [
        "줘", "요", "야", "까", "니", "죠", "래", "자", "냐", "봐", "네", "꺼", "켜", "여", "려",
    ]
    /// Words that leave a sentence hanging, whatever comes before them.
    private static let hangingWords: Set<String> = [
        "그리고", "근데", "그런데", "그래서", "그러면", "아니면", "음", "어", "아", "저기", "그",
        "and", "or", "but", "so", "then", "um", "uh", "the", "to",
    ]

    /// Endings that need more after them: 열고, 날씨랑, 파일을, 서울에서, 끝나면, 하는데.
    private static let hangingEndings = ["고", "랑", "을", "를", "에서", "에", "는데", "면", "서", "려고", "도록", "거나", "든지"]

    /// What you said so far can't be the end ("엑셀 네 개 열고"): Aris waits, however finished your voice sounds.
    static func isHanging(_ text: String) -> Bool {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let word = said.split(whereSeparator: { $0 == " " || $0 == "," }).last.map(String.init) else { return false }
        if hangingWords.contains(word.lowercased()) { return true }
        return word.count > 1 && hangingEndings.contains { word.hasSuffix($0) }
    }

    static func looksComplete(_ text: String) -> Bool {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = said.last, !said.hasSuffix("..."), !said.hasSuffix("…") else { return false }
        if "?!.？！。".contains(last) { return said.count > 1 }
        let words = said.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let word = words.last else { return false }
        if hangingWords.contains(word.lowercased()) { return false }
        // A one-syllable word finishes only after another word ("음악 꺼", "봐 줘"); alone ("네", "요") it doesn't.
        return (word.count > 1 || words.count > 1) && finishedSyllables.contains(last)
    }
}
