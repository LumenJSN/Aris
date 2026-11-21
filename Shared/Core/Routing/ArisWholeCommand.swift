//
//  ArisWholeCommand.swift
//  Aris (Shared/Core)
//
//  Whether a sentence is nothing but one of Aris's own commands. A local action takes a request only when the whole
//  utterance is that command: its words, a number or a length, and around them only what any request may carry
//  (Aris's name, please, particles, filler, a request ending). A keyword inside a longer request, a story or a question
//  about something else ("엄마가 소리 좀 낮춰 달래", "the next song on this album is my favorite", "타이머 10분짜리 영상
//  찾아줘") is the AI's: it can call the same capability as a tool, so a miss costs a second, while a hijack does the
//  wrong thing. Korean words may run together ("볼륨좀올려줘"); English ones are whole words.
//  Foundation only (swift test).
//

import Foundation

enum ArisWholeCommand {
    /// What any request may carry: the wake name, please, particles, filler, request endings, Korean and English.
    static let around: [String] = [
        "아리스", "아리스야", "아리스아", "야", "저기", "음", "어", "그", "그냥", "좀", "좀만", "한번", "한", "번", "빨리", "얼른", "지금", "바로", "당장", "이제", "다시",
        "은", "는", "이", "가", "을", "를", "에", "에서", "으로", "로", "도", "만", "요", "해", "해요", "줘", "줘요", "줄래", "줄래요", "주세요", "주실래요", "주시겠어요",
        "주라", "줘라", "봐", "봐줘", "놔", "놔줘", "둬", "둬줘", "라", "하자", "할래", "해봐", "부탁해", "부탁", "부탁해요", "고마워", "제발", "줄수있어", "수", "있어",
        "aris", "hey", "ok", "okay", "please", "pls", "now", "right", "just", "can", "could", "would", "will", "you", "for", "me", "the", "my", "a", "an",
        "thanks", "thank", "go", "ahead", "and",
    ]

    /// The phrase is one of `core` (at least one) and, around it, only `words`, the shared `around` words and, with
    /// `numbers`, numbers and lengths ("30", "30%", "5분", "1.5시간", "30으로").
    static func isWhole(_ phrase: String, core: [String], words: [String], numbers: Bool = false) -> Bool {
        var rest = phrase.lowercased()
        var found = false
        for word in core.sorted(by: { $0.count > $1.count }) {
            let pattern = ascii(word) ? "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b" : NSRegularExpression.escapedPattern(for: word)
            guard rest.range(of: pattern, options: .regularExpression) != nil else { continue }
            found = true
            rest = rest.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        guard found else { return false }
        let small = words + around
        let english = Set(small.filter(ascii).map { $0.lowercased() })
        let korean = small.filter { !ascii($0) }.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        let run = "^(?:" + korean.joined(separator: "|") + ")+$"
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",.!?~·…:;'\"“”‘’"))
        return rest.components(separatedBy: separators).filter { !$0.isEmpty }.allSatisfy { token in
            var word = token
            if numbers, let digits = word.range(of: #"^[0-9]*\.?[0-9]+(?:%|퍼센트|프로)?"#, options: .regularExpression) {
                word.removeSubrange(digits)
                if word.isEmpty { return true }
            }
            return english.contains(word) || word.range(of: run, options: .regularExpression) != nil
        }
    }

    private static func ascii(_ text: String) -> Bool { text.unicodeScalars.allSatisfy(\.isASCII) }
}
