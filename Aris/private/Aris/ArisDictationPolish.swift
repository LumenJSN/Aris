//
//  ArisDictationPolish.swift
//  Aris
//
//  After the rules (ArisDictationCleaner), Apple's on-device model edits what you dictated:
//  fillers and stutters out, self-corrections ("내일 아니 모레" → "모레"), punctuation, numbers as digits, in the app's
//  writing style, with the user's words spelled their way and the text around the caret as data (ArisPolishPrompt). The words
//  never leave the Mac. The session is made and warmed when dictation starts, and has 2 s after it ends; anything
//  that isn't the same words tidied (an answer, a translation, added content) is thrown away and the rules' text is
//  typed. aris-agent's /polish (a brain with no tools) is the fallback, only when the user turns it on.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum ArisDictationPolish {
    static let timeout: Duration = .seconds(2)

    /// The longest text checked (and so polished), in letters.
    static let longestChecked = 3_000

    /// Whether the model's text is the same words tidied: never longer than a little punctuation adds, at most about
    /// half as short (a self-correction drops words), same scripts, and its letters, in order, are the original's
    /// (digits may stand for number words): nothing added, copied in from the screen or moved around.
    static func acceptable(_ original: String, _ polished: String) -> Bool {
        let a = Array(letters(original).lowercased()), b = Array(letters(polished).lowercased())
        guard !b.isEmpty, a.count <= longestChecked, Double(b.count) <= Double(a.count) * 1.25 + 4,
              Double(b.count) >= Double(a.count) * 0.45 else { return false }
        let hangul = { (text: String) in text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }
        guard hangul(original) == hangul(polished) else { return false }
        let used = b.filter { !$0.isNumber }
        let unmatched = used.count - commonSubsequence(a, used)
        guard unmatched <= max(2, used.count / 10) else { return false }
        return keepsWhatWasMeant(original, polished, a: a, b: b)
    }

    /// Korean and English take-backs: what follows the last one is what was meant.
    private static let takeBacks: Set<String> = ["아니", "아니아니", "말고", "no", "mean"]
    /// Number words, by the digits they're written as (a prefix, so "세시로" is 3).
    private static let numberWords: [String: String] = [
        "한": "1", "하나": "1", "두": "2", "둘": "2", "세": "3", "셋": "3", "네": "4", "넷": "4", "다섯": "5", "여섯": "6",
        "일곱": "7", "여덟": "8", "아홉": "9", "열": "10", "열한": "11", "열두": "12", "일": "1", "이": "2", "삼": "3", "사": "4",
        "오": "5", "육": "6", "칠": "7", "팔": "8", "구": "9", "십": "10",
        "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12",
    ]
    private static let compoundNumbers = ["스물", "서른", "마흔", "쉰", "백", "천", "만", "twenty", "thirty", "forty", "fifty",
                                          "hundred", "thousand", "million"]

    /// Words may be dropped only before a take-back (its correction must stay, in words or digits); with none, only a
    /// few letters may go (stutters, number words turned into digits).
    private static func keepsWhatWasMeant(_ original: String, _ polished: String, a: [Character], b: [Character]) -> Bool {
        let words = original.split(whereSeparator: \.isWhitespace).map { letters(String($0)).lowercased() }
        let target = String(b)
        let marker = words.indices.last { index in
            takeBacks.contains(words[index]) && (words[index] != "mean" || (index > 0 && words[index - 1] == "i"))
        }
        if let marker {
            return words[(marker + 1)...].allSatisfy { word in
                guard !word.isEmpty, !target.contains(word) else { return true }
                if let digits = number(word) { return digits.isEmpty ? polished.contains(where: \.isNumber) : target.contains(digits) }
                return false
            }
        }
        let dropped = a.count - commonSubsequence(a, b)
        let numberLetters = words.filter { number($0) != nil }.reduce(0) { $0 + $1.count }
        return dropped <= max(3, a.count * 15 / 100) + numberLetters
    }

    /// What may follow a number word in the same word: a counter ("세시로", "다섯 개").
    private static let counters = ["시", "분", "초", "월", "년", "개", "명", "번", "살", "원", "달", "주", "층", "일", "권", "장",
                                   "잔", "마리", "o'clock"]

    /// The digits a number word is written as ("" for a compound one, any digits will do); nil when it isn't one:
    /// the word is the number alone, or the number and a counter.
    private static func number(_ word: String) -> String? {
        let candidates = numberWords.map { ($0.key, $0.value) } + compoundNumbers.map { ($0, "") }
        for (name, digits) in candidates.sorted(by: { $0.0.count > $1.0.count }) where word.hasPrefix(name) {
            let rest = word.dropFirst(name.count)
            if rest.isEmpty || counters.contains(where: rest.hasPrefix) { return digits }
        }
        return nil
    }

    /// The length of the longest common subsequence.
    private static func commonSubsequence(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var row = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for j in 1...b.count {
                let above = row[j]
                row[j] = x == b[j - 1] ? diagonal + 1 : max(row[j], row[j - 1])
                diagonal = above
            }
        }
        return row[b.count]
    }

    /// A warmed session for this dictation (made when it starts, so the first words come faster); nil when this Mac
    /// has no model.
    static func prepare(style: ArisWritingStyle, words: [String]) -> AnyObject? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), style.polishes, case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: ArisPolishPrompt.instructions(style: style, words: words))
        session.prewarm()
        return session
        #else
        return nil
        #endif
    }

    /// The edited text, or nil (no model on this Mac, too slow, or not acceptable).
    static func polish(_ text: String, with prepared: AnyObject?, before: String?, after: String?) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), let session = prepared as? LanguageModelSession else { return nil }
        let prompt = ArisPolishPrompt.input(text, before: before, after: after)
        let answer = try? await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy)).content }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
        return checked(text, answer)
        #else
        return nil
        #endif
    }

    /// A model's reply, cleaned of echoed tags, when it is acceptable and does more than echo `text` (an echo isn't
    /// counted as polished, so the brain fallback may still try).
    static func checked(_ text: String, _ answer: String?) -> String? {
        guard let answer else { return nil }
        let polished = ArisPolishPrompt.reply(answer)
        guard echoKey(polished) != echoKey(text) else { return nil }
        return acceptable(text, polished) ? polished : nil
    }

    /// Spacing and a closing full stop aside, the same text.
    private static func echoKey(_ text: String) -> String {
        var key = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while key.hasSuffix(".") { key.removeLast() }
        return key
    }

    private static func letters(_ text: String) -> String {
        String(text.filter { $0.isLetter || $0.isNumber })
    }
}
