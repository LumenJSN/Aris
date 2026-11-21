//
//  ArisRecapWords.swift
//  Shared/Core (app, tests)
//
//  The small pieces the day's recap (ArisRecap) is said with: numbers as they are spoken ("다섯 가지", "넷", "five"),
//  the particle a Korean word takes after it (을/를, 이에요/예요, 으로/로), a time of day ("오후 2시 30분", "2:30 PM")
//  and a day ("내일", "금요일", "Friday"). The day-end card's own sentence counts with the same numbers
//  (ArisDayEndCopy). Foundation only.
//

import Foundation

enum ArisRecapWords {
    // MARK: - Numbers as they are said

    private static let nativeOnes = ["", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉"]
    private static let aloneOnes = ["", "하나", "둘", "셋", "넷", "다섯", "여섯", "일곱", "여덟", "아홉"]
    private static let nativeTens = ["", "열", "스물", "서른", "마흔", "쉰", "예순", "일흔", "여든", "아흔"]
    private static let englishWords = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen",
                                       "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"]

    /// "다섯 가지", "스무 가지", "스물한 가지"; past ninety-nine in figures ("120가지").
    static func things(_ count: Int) -> String {
        guard (1...99).contains(count) else { return "\(count)가지" }
        if count == 20 { return "스무 가지" }
        return nativeTens[count / 10] + nativeOnes[count % 10] + " 가지"
    }

    /// A count standing by itself: "하나", "둘", "열둘"; past ninety-nine in figures ("120개").
    static func alone(_ count: Int) -> String {
        guard (1...99).contains(count) else { return "\(count)개" }
        return nativeTens[count / 10] + aloneOnes[count % 10]
    }

    /// "three"; past twenty in figures.
    static func number(_ count: Int) -> String {
        englishWords.indices.contains(count) ? englishWords[count] : "\(count)"
    }

    /// "Three" at the start of a sentence.
    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    /// "four file changes", "one message sent".
    static func counted(_ count: Int, _ one: String, _ many: String) -> String { number(count) + " " + (count == 1 ? one : many) }

    /// English items joined as they are said: "a", "a and b", "a, b and c".
    static func and(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + (items.last ?? "")
    }

    // MARK: - Korean particles

    /// Whether the word ends in a closing consonant (받침), as it is read aloud; a figure or a Latin letter by its name.
    static func hasBatchim(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last(where: { !CharacterSet.punctuationCharacters.contains($0) }) else {
            return false
        }
        if (0xAC00...0xD7A3).contains(last.value) { return (last.value - 0xAC00) % 28 != 0 }
        // 영, 일, 삼, 육, 칠, 팔; L, M, N said "엘", "엠", "엔".
        return "0136781lmnLMN".unicodeScalars.contains(last)
    }

    /// The closing consonant is ㄹ (it takes "로", not "으로").
    static func endsInRieul(_ word: String) -> Bool {
        guard let last = word.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.last else { return false }
        if (0xAC00...0xD7A3).contains(last.value) { return (last.value - 0xAC00) % 28 == 8 }
        return "178lL".unicodeScalars.contains(last)
    }

    /// The word with 을/를, 이/가, 은/는, 과/와: `with` after a closing consonant, else `without`.
    static func josa(_ word: String, _ with: String, _ without: String) -> String { word + (hasBatchim(word) ? with : without) }

    /// "회의로", "수업으로", "PS3로".
    static func ro(_ word: String) -> String { word + (hasBatchim(word) && !endsInRieul(word) ? "으로" : "로") }

    /// "둘이에요", "하나예요".
    static func ieyo(_ word: String) -> String { word + (hasBatchim(word) ? "이에요" : "예요") }

    // MARK: - Times and days

    /// "오전 9시", "오후 2시 30분"; "9 AM", "2:30 PM".
    static func time(_ date: Date, english: Bool, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        if english { return (minute == 0 ? "\(twelve)" : String(format: "%d:%02d", twelve, minute)) + (hour < 12 ? " AM" : " PM") }
        return (hour < 12 ? "오전 " : "오후 ") + "\(twelve)시" + (minute == 0 ? "" : " \(minute)분")
    }

    private static let koreanWeekdays = ["일요일", "월요일", "화요일", "수요일", "목요일", "금요일", "토요일"]
    private static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let englishMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The day `date` falls on, from the day being wrapped up (`today`, its midnight): "오늘", "내일", "모레", a weekday
    /// within the week, else "11월 25일"; "today", "tomorrow", "Friday", "Nov 25".
    static func day(_ date: Date, today: Date, english: Bool, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return english ? "today" : "오늘"
        case 1: return english ? "tomorrow" : "내일"
        case 2 where !english: return "모레"
        case 2...6:
            let weekday = calendar.component(.weekday, from: date) - 1
            return english ? englishWeekdays[weekday] : koreanWeekdays[weekday]
        default:
            let month = calendar.component(.month, from: date), dayOfMonth = calendar.component(.day, from: date)
            return english ? "\(englishMonths[month - 1]) \(dayOfMonth)" : "\(month)월 \(dayOfMonth)일"
        }
    }

    /// A title as it is said: one line, at most `limit` letters (cut at a word where it can be).
    static func title(_ text: String, limit: Int = 30) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        let cut = String(flat.prefix(limit))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 { return String(cut[..<space]) }
        return cut
    }
}
