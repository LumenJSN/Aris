//
//  ArisNoticeWords.swift
//  Aris
//
//  The notice pill's own words, Korean and English (the news itself brings its own). Foundation only (tested).
//

import Foundation

enum ArisNoticeWords {
    static func view(english: Bool) -> String { english ? "View" : "보기" }
    static func close(english: Bool) -> String { english ? "Close" : "닫기" }
    /// A deadline's own page.
    static func open(english: Bool) -> String { english ? "Open" : "열기" }
    /// A Claude Code session's terminal.
    static func openTerminal(english: Bool) -> String { english ? "Open terminal" : "터미널 열기" }
    /// The title of a problem card made from one of the app's own lines.
    static func needsYou(english: Bool) -> String { english ? "Needs your attention" : "확인이 필요해요" }
    static func asks(english: Bool) -> String { english ? "Has a question" : "질문이 있어요" }
    static func helperDownBody(english: Bool) -> String {
        english ? "Restarting it usually brings it back." : "다시 시작하면 보통 돌아와요."
    }

    /// When it came, at the pill's right: "방금" / "now" in its first minute, then minutes, then hours.
    static func ago(_ seconds: TimeInterval, english: Bool) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return english ? "now" : "방금" }
        if minutes < 60 { return english ? "\(minutes)m ago" : "\(minutes)분 전" }
        let hours = minutes / 60
        return english ? "\(hours)h ago" : "\(hours)시간 전"
    }

    /// When a deadline is: the to-do tab's Korean ("오늘 17:00", "내일", "수", ArisDue.when), or the same in English.
    static func dueWhen(_ date: Date, now: Date, english: Bool, calendar: Calendar = .current) -> String {
        guard english else { return ArisDue.when(date, now: now, calendar: calendar).0 }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        if calendar.isDate(date, inSameDayAs: now) {
            format.dateFormat = "HH:mm"
            return "today \(format.string(from: date))"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow" }
        format.dateFormat = "EEE"
        return format.string(from: date)
    }
}
