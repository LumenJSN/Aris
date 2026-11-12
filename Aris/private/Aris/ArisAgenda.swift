//
//  ArisAgenda.swift
//  Aris
//
//  The pure side of the 캘린더 tab: which event the "지금 / 다음" card features, how far along it is, and how times
//  and days read in Korean.
//

import Foundation

struct ArisAgendaSlot: Equatable {
    let id: String
    let start: Date
    let end: Date
    let isAllDay: Bool
}

enum ArisAgenda {
    /// An event in progress, else the next one starting within 12 hours.
    static let lookAhead: TimeInterval = 12 * 3_600
    /// A tap joins the meeting when it's on or starts within this long.
    static let joinWindow: TimeInterval = 10 * 60

    /// Every visible day overlapped by an event. EventKit's end is exclusive, including for all-day events.
    static func days(start: Date, end: Date, now: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        guard count > 0, let limit = calendar.date(byAdding: .day, value: count, to: today) else { return [] }
        var day = max(today, calendar.startOfDay(for: start))
        var result: [Date] = []
        while day < limit && (day < end || (end == start && calendar.isDate(day, inSameDayAs: start))) {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// The event to feature (all-day ones never): the earliest-started one in progress, else the soonest to start.
    static func featured(_ slots: [ArisAgendaSlot], now: Date) -> (slot: ArisAgendaSlot, inProgress: Bool)? {
        let timed = slots.filter { !$0.isAllDay }
        if let current = timed.filter({ $0.start <= now && now < $0.end }).min(by: { $0.start < $1.start }) { return (current, true) }
        if let next = timed.filter({ $0.start > now && $0.start.timeIntervalSince(now) <= lookAhead }).min(by: { $0.start < $1.start }) { return (next, false) }
        return nil
    }

    /// 0…1 of the event gone by.
    static func progress(_ slot: ArisAgendaSlot, now: Date) -> Double {
        let length = slot.end.timeIntervalSince(slot.start)
        guard length > 0 else { return 0 }
        return min(max(now.timeIntervalSince(slot.start) / length, 0), 1)
    }

    /// True when a tap on the event should join its meeting rather than open it.
    static func shouldJoin(_ slot: ArisAgendaSlot, now: Date) -> Bool {
        !slot.isAllDay && now < slot.end && slot.start.timeIntervalSince(now) <= joinWindow
    }

    /// Where a timed event sits on `day`'s timetable, in minutes from midnight, clipped to the day (an event from
    /// 23:00 the night before runs from 0). Nil for all-day events and events on other days.
    static func dayMinutes(_ slot: ArisAgendaSlot, on day: Date, calendar: Calendar = .current) -> (start: Double, end: Double)? {
        guard !slot.isAllDay else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start), slot.start < end, slot.end > start else { return nil }
        let from = max(slot.start, start).timeIntervalSince(start) / 60
        let to = min(slot.end, end).timeIntervalSince(start) / 60
        return (from, max(to, from))
    }

    /// Google Calendar's side-by-side layout: events that overlap share the width, each in the first column free at
    /// its start (one ending exactly when another starts doesn't overlap it). `of` is the column count of its group.
    static func columns(_ items: [(id: String, start: Double, end: Double)]) -> [String: (column: Int, of: Int)] {
        var result: [String: (column: Int, of: Int)] = [:]
        var group: [(id: String, column: Int)] = []
        var columnEnds: [Double] = []
        var groupEnd = -Double.infinity
        func close() {
            for member in group { result[member.id] = (member.column, max(1, columnEnds.count)) }
            group = []
            columnEnds = []
        }
        for item in items.sorted(by: { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }) {
            if item.start >= groupEnd { close() }
            let column = columnEnds.firstIndex { $0 <= item.start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(item.end) } else { columnEnds[column] = item.end }
            group.append((item.id, column))
            groupEnd = max(groupEnd, item.end)
        }
        close()
        return result
    }

    /// How many events (all-day ones included) touch `day`: the date strip's dots.
    static func dots(_ slots: [ArisAgendaSlot], on day: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return slots.filter { $0.start < end && ($0.end > start || ($0.end == $0.start && $0.start >= start)) }.count
    }

    /// True for a calendar account macOS syncs from Google (its source is named by the address or "Google").
    static func isGoogle(account: String) -> Bool {
        let name = account.lowercased()
        return name.contains("google") || name.hasSuffix("@gmail.com")
    }

    /// Google Calendar's web day view for `date`; EventKit doesn't carry the id Google's own event links need.
    static func googleDayURL(_ date: Date, calendar: Calendar = .current) -> URL {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return URL(string: "https://calendar.google.com/calendar/r/day/\(parts.year ?? 1970)/\(parts.month ?? 1)/\(parts.day ?? 1)")!
    }

    /// "32분 후", "2시간 15분 후", "1시간 후".
    static func until(_ date: Date, now: Date, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let minutes = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if english { return "in " + ArisUIDates.length(minutes: minutes, locale: locale) }
        if minutes < 60 { return "\(minutes)분 후" }
        return minutes % 60 == 0 ? "\(minutes / 60)시간 후" : "\(minutes / 60)시간 \(minutes % 60)분 후"
    }

    /// "오후 3:00 – 4:00" (the second half names its own part of the day only when it differs; the hour after midnight
    /// is 밤 12, ArisKoreanTimeLabel).
    static func timeRange(_ start: Date, _ end: Date, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english {
            // The system writes the range ("3:00 – 4:00 PM", "15:00 – 16:00"), naming AM or PM once when both halves share it.
            let formatter = DateIntervalFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale ?? ArisUIDates.englishLocale()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return formatter.string(from: start, to: end)
        }
        let samePeriod = ArisKoreanTimeLabel.period(hour: calendar.component(.hour, from: start)) == ArisKoreanTimeLabel.period(hour: calendar.component(.hour, from: end))
        return "\(ArisKoreanTimeLabel.text(start, calendar: calendar)) – \(ArisKoreanTimeLabel.text(end, calendar: calendar, period: !samePeriod))"
    }

    /// "오늘", "내일", "11월 4일 화요일".
    static func dayTitle(_ day: Date, now: Date = .now, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return ArisUIWords.text("오늘", "Today", english: english) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(day, inSameDayAs: tomorrow) { return ArisUIWords.text("내일", "Tomorrow", english: english) }
        if english { return ArisUIDates.string(day, korean: "", template: "MMMdEEEE", english: true, calendar: calendar, locale: locale) }
        return formatter("M월 d일 EEEE").string(from: day)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }
}
