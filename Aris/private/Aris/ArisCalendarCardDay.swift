//
//  ArisCalendarCardDay.swift
//  Aris
//
//  Which day the calendar card under an answer shows: the day the answer is about. "What's on my calendar tomorrow"
//  used to get today's card, today's due to-dos and ticked ones among its rows as "All day" events (VM fourth
//  re-check, #3). A day the question names plainly (오늘/내일/모레/어제, today/tomorrow/yesterday, a weekday) is the
//  card's; else the day the brain wrote in its block ("day":"2026-11-13"); else today. A question that names a day this
//  can't place (next Friday, a date, this week) with no day in the block gets no card rather than another day's. The
//  card's rows are calendar events only: a reminder is never one of them (the card has no to-do line).
//

import Foundation

enum ArisCalendarCardDay {
    /// What the question says about the day.
    enum Asked: Equatable {
        /// No day named.
        case none
        /// Today, named.
        case today
        /// That day, as "yyyy-MM-dd".
        case day(String)
        /// A day this can't place: no card.
        case unclear
    }

    /// A block's "day": a real date written "yyyy-MM-dd"; nil for anything else.
    static func valid(_ raw: Any?) -> String? {
        guard let text = (raw as? String)?.trimmingCharacters(in: .whitespaces), text.count == 10,
              text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = date(text), string(date) == text else { return nil }
        return text
    }

    /// The start of that day, in `calendar`'s time zone.
    static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The request the card answers: a calendar card takes the day the question names plainly, else the block's;
    /// nil (no card) when the question names a day that can't be placed and the block names none. Every other card as
    /// it is.
    static func resolve(_ request: ArisWidgetRequest, asked words: String?, now: Date, calendar: Calendar = .current) -> ArisWidgetRequest? {
        guard request.kind == .calendar else { return request }
        var named = request
        switch words.map({ asked($0, now: now, calendar: calendar) }) ?? .none {
        case .none: break
        case .today: named.day = nil
        case .day(let day): named.day = day
        case .unclear: if request.day == nil { return nil }
        }
        if named.day == string(now, calendar: calendar) { named.day = nil }
        return named
    }

    /// The day `words` name, from `now`.
    static func asked(_ words: String, now: Date, calendar: Calendar = .current) -> Asked {
        let said = " " + words.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        if unclearWords.contains(where: { said.contains($0) }) || said.range(of: unclearPattern, options: .regularExpression) != nil { return .unclear }
        if said.range(of: #"\d{1,2}\s*월\s*\d{1,2}\s*일|\d{1,2}\s*일\s*(에|날|은|는|일정)|\d{1,2}(st|nd|rd|th)\b"#, options: .regularExpression) != nil { return .unclear }
        if said.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b"#, options: .regularExpression) != nil { return .unclear }
        for (offset, names) in relative where names.contains(where: { said.contains($0) }) {
            return offset == 0 ? .today : shifted(now, by: offset, calendar: calendar)
        }
        let named = weekdays.filter { _, names in names.contains { said.contains($0) } }.map(\.key)
        guard let weekday = named.first else { return .none }
        guard named.count == 1 else { return .unclear }
        // The coming one: today when it is that day.
        let today = calendar.component(.weekday, from: now)
        return shifted(now, by: (weekday - today + 7) % 7, calendar: calendar)
    }

    private static func shifted(_ now: Date, by days: Int, calendar: Calendar) -> Asked {
        guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) else { return .unclear }
        return days == 0 ? .today : .day(string(day, calendar: calendar))
    }

    /// Checked in this order: "내일모레" and "the day after tomorrow" before "내일" and "tomorrow".
    private static let relative: [(Int, [String])] = [
        (2, ["모레", "day after tomorrow"]),
        (-2, ["그저께", "그제", "day before yesterday"]),
        (1, ["내일", "tomorrow", "tmrw"]),
        (-1, ["어제", "yesterday"]),
        (0, ["오늘", "today", "tonight", "this morning", "this afternoon", "this evening"]),
    ]

    /// Calendar's weekday numbers (Sunday 1).
    private static let weekdays: [Int: [String]] = [
        1: ["일요일", "sunday"], 2: ["월요일", "monday"], 3: ["화요일", "tuesday"], 4: ["수요일", "wednesday"],
        5: ["목요일", "thursday"], 6: ["금요일", "friday"], 7: ["토요일", "saturday"],
    ]

    /// Days a one-day card can't stand for: a week, a weekend, a weekday of another week.
    private static let unclearWords = ["다음 주", "다음주", "지난 주", "지난주", "저번 주", "저번주", "이번 주", "이번주", "주말"]
    private static let unclearPattern = #"\b(next|last|coming|past)\s+(week|weekend|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b|\bthis\s+(week|weekend|month)\b|\bweekend\b"#

    /// The card's rows: the day's calendar events, never a reminder (due or ticked).
    static func rows(_ events: [ArisCalendarEvent]) -> [ArisWidgetEvent] {
        events.filter { !$0.kind.isReminder }
            .map { ArisWidgetEvent(start: $0.start, end: $0.end, title: $0.title, location: $0.location, allDay: $0.isAllDay) }
    }
}
