//
//  ArisSpokenDuration.swift
//  Aris (Shared/Core)
//
//  A length of time as it is said, in seconds: "25분", "1시간 30분", "한 시간 반" (the words come with their numbers
//  as digits already: "1시간 반"), "5분 반", "1.5시간", "2.5 minutes", "90 seconds", "an hour and a half". The timer
//  used to read only whole numbers right before a unit, so "1.5시간" was 5 hours and "한 시간 반" one hour.
//  Foundation only (swift test).
//

import Foundation

enum ArisSpokenDuration {
    private static let units: [(pattern: String, seconds: Double)] = [
        (#"시간"#, 3_600), (#"분"#, 60), (#"초"#, 1),
        (#"(?:more\s+)?(?:hours?|hrs?)\b"#, 3_600), (#"(?:more\s+)?(?:minutes?|mins?)\b"#, 60), (#"(?:more\s+)?(?:seconds?|secs?)\b"#, 1),
    ]
    /// A number: whole or with a decimal point ("1.5", "0.5", ".5").
    private static let number = #"(?<![0-9.])([0-9]*\.?[0-9]+)"#
    /// "반" right after a unit ("1시간 반", "5분반"), or "and a half" after an English one.
    private static let half = #"^\s*(?:반(?![가-힣])|반(?=에|만|짜리|동안|뒤|후|으로|로)|and\s+a\s+half\b)"#

    /// The seconds the phrase names, every unit added up; nil when it names none (or only zero).
    static func seconds(in phrase: String) -> Int? {
        let text = phrase.lowercased()
        var total = 0.0
        for unit in units {
            guard let regex = try? NSRegularExpression(pattern: number + #"\s*(?:"# + unit.pattern + ")") else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let value = Range(match.range(at: 1), in: text).flatMap({ Double(text[$0]) }),
                      let end = Range(match.range, in: text)?.upperBound else { continue }
                total += value * unit.seconds
                // "1시간 반": half of that unit more.
                if String(text[end...]).range(of: half, options: .regularExpression) != nil { total += unit.seconds / 2 }
            }
        }
        // "반 시간", "half a minute": half of one unit said without a number.
        if total == 0 {
            if text.range(of: #"(?<![가-힣])반\s*시간"#, options: .regularExpression) != nil { total = 1_800 }
            else if text.range(of: #"\bhalf\s+an?\s+hour\b"#, options: .regularExpression) != nil { total = 1_800 }
            else if text.range(of: #"\bhalf\s+a\s+minute\b"#, options: .regularExpression) != nil { total = 30 }
        }
        let seconds = Int(total.rounded())
        return seconds > 0 ? seconds : nil
    }

    /// The length as Korean says it: "1시간 30분", "5분 30초", "25분".
    static func korean(_ seconds: Int) -> String {
        let parts = [(seconds / 3_600, "시간"), (seconds % 3_600 / 60, "분"), (seconds % 60, "초")].filter { $0.0 > 0 }
        return parts.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }

    /// The length as English says it: "1 hour 30 minutes", "5 minutes 30 seconds", "1 minute".
    static func english(_ seconds: Int) -> String {
        let parts = [(seconds / 3_600, "hour"), (seconds % 3_600 / 60, "minute"), (seconds % 60, "second")].filter { $0.0 > 0 }
        return parts.map { "\($0.0) \($0.1)\($0.0 == 1 ? "" : "s")" }.joined(separator: " ")
    }
}
