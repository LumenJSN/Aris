//
//  ArisUIDates.swift
//  Aris
//
//  Dates, times and lengths of time in the UI's language (VM run, bug 4: on an English Mac the side panels read
//  "오늘 오전 8:23", "3분 전", "2시간 30분" because each was built by hand in Korean). In Korean each keeps the exact
//  format it always had; in English the system's formatters write it with an English locale, so the order of day and
//  month and the 12- or 24-hour clock are that locale's own. The English locale is the Mac's when the Mac's region
//  is an English one (en_GB keeps "21 Sep" and 10:13), US English otherwise. Foundation only (tested).
//

import Foundation

enum ArisUIDates {
    static let korean = Locale(identifier: "ko_KR")

    /// The locale English dates are written in.
    static func englishLocale(current: Locale = .current) -> Locale {
        current.language.languageCode?.identifier == "en" ? current : Locale(identifier: "en_US")
    }

    static func locale(english: Bool = ArisUIWords.english) -> Locale { english ? englishLocale() : korean }

    /// A date for the UI: in Korean exactly as the date format `korean` writes it, in English as the locale writes the
    /// fields of `template` ("MMMdjmm": Sep 21 at 10:13 AM).
    static func string(_ date: Date, korean format: String, template: String, english: Bool = ArisUIWords.english,
                       calendar: Calendar = .current, locale: Locale? = nil) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale ?? (english ? englishLocale() : korean)
        if english { formatter.setLocalizedDateFormatFromTemplate(template) } else { formatter.dateFormat = format }
        return formatter.string(from: date)
    }

    /// The time of day alone: "오전 8:23", "8:23 AM".
    static func time(_ date: Date, english: Bool = ArisUIWords.english, calendar: Calendar = .current, locale: Locale? = nil) -> String {
        string(date, korean: "a h:mm", template: "jmm", english: english, calendar: calendar, locale: locale)
    }

    /// The day alone: "11월 10일", "Nov 10".
    static func day(_ date: Date, english: Bool = ArisUIWords.english, calendar: Calendar = .current, locale: Locale? = nil) -> String {
        string(date, korean: "M월 d일", template: "MMMd", english: english, calendar: calendar, locale: locale)
    }

    /// A length of time in English, to the minute: "45m", "2h 30m", "1d 2h" (the Korean is written where it is said).
    static func length(minutes: Int, locale: Locale? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale ?? englishLocale()
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = minutes >= 1_440 ? [.day, .hour] : [.hour, .minute]
        return formatter.string(from: TimeInterval(max(0, minutes) * 60)) ?? "\(minutes)m"
    }

    /// A length of time in English as it is said: "25 minutes", "1 hour, 5 minutes", "45 seconds".
    static func lengthInWords(seconds: Int, locale: Locale? = nil) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale ?? englishLocale()
        let formatter = DateComponentsFormatter()
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 60 ? [.hour, .minute] : [.second]
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? "\(seconds) seconds"
    }

    /// How long ago, or how far ahead, in English: "3 min. ago", "in 2 hr." (`seconds` below zero is the past).
    static func relative(seconds: TimeInterval, locale: Locale? = nil) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale ?? englishLocale()
        formatter.unitsStyle = .short
        return formatter.localizedString(fromTimeInterval: seconds)
    }

    /// A whole number in English with its unit's plural: "1 item", "3 items".
    static func count(_ number: Int, _ one: String, _ many: String) -> String { "\(number) \(number == 1 ? one : many)" }
}
