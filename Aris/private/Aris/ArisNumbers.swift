//
//  ArisNumbers.swift
//  Aris
//
//  Spoken Korean numbers as digits, so "볼륨 오십으로", "볼륨 50으로" and "네 개 켜서 사등분" mean what
//  "4개 켜서 4등분" means. Only words that can't be anything else are changed: a number right before a
//  counter (개, 등분, 분, 시) or a particle (으로, 까지). "이 노래", "네 알겠어", "열어줘" stay as they are.
//  Shared by the app (ArisIntent) and aris-agent (shortcut keys).
//

import Foundation

/// The Korean particle a word takes, from its last sound (QA BUG-12: a card said "텍스트 편집기은(는)"): 은/는, 이/가,
/// 을/를, 과/와, and 으로/로 (ㄹ takes 로). Closing marks and spaces at the end are skipped; a digit is read as said
/// (일, 삼, 육…), and a Latin word by its last letter (TextEdit은, Safari는). Shared by the app, aris-agent and aris-tools.
enum ArisJosa {
    private enum Ending { case vowel, rieul, consonant }

    /// What the word ends in, as said; nil for nothing readable (a word of marks only).
    private static func ending(_ word: String) -> Ending? {
        let skipped = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "”\"'’)]}»」』>.…!?"))
        guard let last = word.unicodeScalars.last(where: { !skipped.contains($0) }) else { return nil }
        let value = last.value
        if (0xAC00...0xD7A3).contains(value) {
            let final = (value - 0xAC00) % 28
            return final == 0 ? .vowel : final == 8 ? .rieul : .consonant
        }
        switch Character(last).lowercased() {
        case "1", "7", "8", "l": return .rieul
        case "0", "3", "6", "m", "n", "k", "p", "t", "b", "d", "g", "c": return .consonant
        default: return .vowel
        }
    }

    /// Only the particle: withBatchim after a final consonant, else without.
    static func particle(_ word: String, _ withBatchim: String, _ without: String) -> String {
        guard let ending = ending(word) else { return without }
        return ending == .vowel ? without : withBatchim
    }

    static func attach(_ word: String, _ withBatchim: String, _ without: String) -> String { word + particle(word, withBatchim, without) }

    /// 으로 or 로 (a vowel or ㄹ takes 로).
    static func ro(_ word: String) -> String { ending(word) == .consonant ? "으로" : "로" }
}

enum ArisNumbers {
    private static let sinoDigits: [Character: Int] = ["일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "칠": 7, "팔": 8, "구": 9]
    private static let sinoUnits: [Character: Int] = ["십": 10, "백": 100]
    private static let nativeTens: [String: Int] = ["열": 10, "스물": 20, "스무": 20, "서른": 30, "마흔": 40, "쉰": 50,
                                                    "예순": 60, "일흔": 70, "여든": 80, "아흔": 90]
    private static let nativeOnes: [String: Int] = ["하나": 1, "한": 1, "둘": 2, "두": 2, "셋": 3, "세": 3, "석": 3, "넷": 4, "네": 4,
                                                    "넉": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9]
    /// Forms that stand alone before a particle ("둘로", "넷으로"); 한, 두, 세, 네 only come before a counter.
    private static let nativeAlone: Set = ["하나", "둘", "셋", "넷", "다섯", "여섯", "일곱", "여덟", "아홉"]

    /// Not part of a longer word: nothing Hangul or a digit right before.
    private static let start = "(?<![가-힣0-9])"
    /// A counter that ends there (분 and 시 only before a pause or a small ending: "이분이" is a person).
    private static let sinoCounter = "(개|등분|칸|퍼센트|프로|%|분(?=$|[^가-힣]|뒤|후|동안|짜리|만|에|씩|까지|정도)|초(?=$|[^가-힣]|뒤|후|동안|만|에|씩))"
    private static let nativeCounter = "(개|등분|칸|시간|시(?=$|[^가-힣]|에|까지|반|쯤|로|부터))"
    private static let particle = "(?=으로|로|까지|정도|퍼센트|프로|$|[\\s.,!?])"

    private static let tensPattern = nativeTens.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let onesPattern = nativeOnes.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let native = "((?:\(tensPattern))(?:\(onesPattern))?|\(onesPattern))"
    private static let sino = "([일이삼사오육칠팔구십백]+)"

    static func normalize(_ text: String) -> String {
        var result = text
        // Native first: 일흔 starts like 일.
        result = replace(start + native + "( ?)" + nativeCounter, in: result) { _, _ in true } value: { nativeValue($0) }
        result = replace(start + native + particle, in: result) { word, _ in
            nativeAlone.contains(word) || nativeTens.keys.contains { word.hasPrefix($0) && word.count > $0.count }
        } value: { nativeValue($0) }
        result = replace(start + sino + "( ?)" + sinoCounter, in: result) { word, spaced in
            !spaced || word.count > 1 || word.contains { sinoUnits[$0] != nil }
        } value: { sinoValue($0) }
        result = replace(start + sino + particle, in: result) { word, _ in
            word.contains { sinoUnits[$0] != nil }
        } value: { sinoValue($0) }
        return result
    }

    /// Replaces each match's number word (group 1) by its digits, dropping a space before the counter
    /// (group 2, when the pattern has one), when `accepts` says the word may be a number here.
    private static func replace(_ pattern: String, in text: String, accepts: (String, Bool) -> Bool,
                                value: (String) -> Int?) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let wordRange = match.range(at: 1)
            let word = source.substring(with: wordRange)
            let space = match.numberOfRanges > 3 ? match.range(at: 2) : NSRange(location: NSNotFound, length: 0)
            let spaced = space.location != NSNotFound && space.length > 0
            guard accepts(word, spaced), let number = value(word) else { continue }
            result += source.substring(with: NSRange(location: cursor, length: wordRange.location - cursor)) + String(number)
            cursor = spaced ? space.location + space.length : wordRange.location + wordRange.length
        }
        return result + source.substring(from: cursor)
    }

    /// "삼십오" is 35, "백" 100, "사" 4; nil for runs that aren't one number ("삼사", "십백").
    static func sinoValue(_ word: String) -> Int? {
        var total = 0, digit: Int?, lastUnit = Int.max
        for character in word {
            if let value = sinoDigits[character] {
                guard digit == nil else { return nil }
                digit = value
            } else if let unit = sinoUnits[character], unit < lastUnit {
                total += (digit ?? 1) * unit
                digit = nil
                lastUnit = unit
            } else {
                return nil
            }
        }
        return total + (digit ?? 0)
    }

    /// "스물다섯" is 25, "열" 10, "네" 4.
    static func nativeValue(_ word: String) -> Int? {
        if let ones = nativeOnes[word] { return ones }
        if let tens = nativeTens[word] { return tens }
        guard let prefix = nativeTens.keys.first(where: { word.hasPrefix($0) }),
              let ones = nativeOnes[String(word.dropFirst(prefix.count))] else { return nil }
        return nativeTens[prefix]! + ones
    }
}

/// A time as Korean says it, by the part of the day (QA live: "오전 12시 32분" at 00:32): 밤 12시 N분 just after midnight,
/// 새벽 1–5시, 아침 6–11시, 오후 12–5시, 저녁 6–8시, 밤 9–11시; "N시" on the hour. Shared by the app (the time Aris tells)
/// and aris-tools (a stock quote's time).
enum ArisKoreanClock {
    static func part(hour: Int) -> String {
        switch hour {
        case 1...5: return "새벽"
        case 6...11: return "아침"
        case 12...17: return "오후"
        case 18...20: return "저녁"
        default: return "밤"
        }
    }

    static func phrase(hour: Int, minute: Int) -> String {
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return minute == 0 ? "\(part(hour: hour)) \(twelve)시" : "\(part(hour: hour)) \(twelve)시 \(minute)분"
    }
}
