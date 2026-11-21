//
//  ArisSpeakableDates.swift
//  Aris
//
//  A date written as digits ("2026-11-20") said the way people say it, for the voice only (tenth VM run, item 12: an
//  answer was read out as "이천이십육 십일 이십에서 …"): "11월 20일" in a Korean sentence, "November 20" in any other,
//  with the year only when it isn't this one. Whatever the model writes, ArisSpeakable.speakable passes through here;
//  the text on screen is not changed. Only a whole, real date is read this way (never part of a longer number, a
//  version or a time stamp's clock). Foundation only (tested).
//

import Foundation

enum ArisSpeakableDates {
    private static let pattern = try? NSRegularExpression(pattern: #"(?<![\d.\-/])(\d{4})-(\d{2})-(\d{2})(?![\d\-/]|\.\d)"#)
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let monthDays = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    static func hasHangul(_ text: String) -> Bool { text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }

    /// `thisYear`: the year that goes unsaid.
    static func natural(_ text: String, thisYear: Int = Calendar(identifier: .gregorian).component(.year, from: Date())) -> String {
        guard let pattern, text.contains("-") else { return text }
        let korean = hasHangul(text)
        var out = text
        for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: out), let y = Range(match.range(at: 1), in: text), let m = Range(match.range(at: 2), in: text),
                  let d = Range(match.range(at: 3), in: text), let year = Int(text[y]), let month = Int(text[m]), let day = Int(text[d]),
                  (1...12).contains(month), day >= 1, day <= monthDays[month - 1], (1900...2200).contains(year) else { continue }
            let said: String
            if korean {
                said = (year == thisYear ? "" : "\(year)년 ") + "\(month)월 \(day)일"
            } else {
                said = "\(months[month - 1]) \(day)" + (year == thisYear ? "" : ", \(year)")
            }
            out.replaceSubrange(whole, with: said)
        }
        return out
    }
}
