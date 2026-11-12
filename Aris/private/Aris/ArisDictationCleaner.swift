//
//  ArisDictationCleaner.swift
//  Aris
//
//  Dictation types what you meant, not every sound: fillers (어, 음, um, uh) go, and a word you took back
//  goes with the take-back ("6시, 아니 7시로" is "7시로"; "6, I mean 7" is "7"). Rules only, no AI, so it's
//  instant. A take-back counts only after a comma or between two numbers: "아니 근데…" at the start of a
//  sentence, or "그거 아니 이거", is how you talk and stays.
//

import Foundation

enum ArisDictationCleaner {
    struct Word: Equatable {
        let text: String
        let kept: Bool
    }

    private static let fillers: Set<String> = ["어", "음", "으음", "음음", "어어", "um", "umm", "uh", "uhm", "erm", "hmm"]
    private static let takeBacks: Set<String> = ["아니", "아니아니"]
    private static let trailing = CharacterSet(charactersIn: ",.!?…")

    /// Each word as said, and whether it's typed.
    static func marked(_ text: String) -> [Word] {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept = words.map { !fillers.contains(core($0).lowercased()) }
        var index = 0
        while index < words.count {
            let length = takeBackLength(words, at: index)
            if length > 0, let before = (0..<index).last(where: { kept[$0] }), index + length < words.count,
               corrects(words[before], with: words[index + length]) {
                kept[before] = false
                (index..<index + length).forEach { kept[$0] = false }
            }
            index += max(length, 1)
        }
        return zip(words, kept).map { Word(text: $0, kept: $1) }
    }

    /// The words to type, with a full stop when the sentence has no ending of its own (unless `endStop` is off: chat
    /// and code styles); "" when nothing's left.
    static func clean(_ text: String, endStop: Bool = true) -> String {
        var typed = marked(text).filter(\.kept).map(\.text).joined(separator: " ")
        while let last = typed.last, last == "," { typed.removeLast() }
        typed = typed.trimmingCharacters(in: .whitespaces)
        guard typed.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) else { return "" }
        if endStop, let last = typed.unicodeScalars.last, !trailing.contains(last) { typed += "." }
        return typed
    }

    /// "아니", "아니 아니", or "I mean" starting at `index`: how many words it takes; 0 when it isn't one.
    private static func takeBackLength(_ words: [String], at index: Int) -> Int {
        let word = core(words[index]).lowercased()
        if takeBacks.contains(word) {
            return index + 1 < words.count && takeBacks.contains(core(words[index + 1])) ? 2 : 1
        }
        if word == "i", index + 1 < words.count, core(words[index + 1]).lowercased() == "mean" { return 2 }
        return 0
    }

    /// The word before a take-back is replaced when it was followed by a comma, or both sides are numbers.
    private static func corrects(_ before: String, with after: String) -> Bool {
        let digits = { (word: String) in word.contains(where: \.isNumber) }
        return before.hasSuffix(",") || (digits(before) && digits(after))
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: trailing)
    }
}
