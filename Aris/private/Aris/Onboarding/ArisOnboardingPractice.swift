//
//  ArisOnboardingPractice.swift
//  Aris
//
//  The onboarding's 눌러서 말하기 turn, sandboxed (QA BUG-31): it is answered here and nothing else. No router, no
//  hand-off, no AI with tools, and of the Mac's actions only Aris's own timer (the owner's pick 1-A, 2026-11-11: the first
//  request is "3분 타이머 맞춰 줘", done by the app itself; music, volume, apps and to-dos stay out): a timer set,
//  stopped, paused, resumed or lengthened, the time, the date, or the calendar for a day (read through EventKit, never
//  changed); anything else gets one line saying the practice does only these. Pure: the controller sets the timer,
//  reads the events and speaks the line.
//

import Foundation

enum ArisOnboardingPractice {
    enum Part: Equatable { case wholeDay, morning, afternoon, evening }

    enum Question: Equatable {
        /// A request about Aris's own timer, as the intent the app carries out.
        case timer(ArisIntent)
        case time
        case date
        /// `day`: 0 today, 1 tomorrow.
        case calendar(day: Int, part: Part)
        case other
    }

    /// An event as the answer needs it.
    struct Event: Equatable {
        let title: String
        let start: Date
        let isAllDay: Bool
    }

    static func question(_ text: String) -> Question {
        let said = text.lowercased()
        let has = { (words: [String]) in words.contains { said.contains($0) } }
        if has(["일정", "캘린더", "약속", "미팅", "회의", "스케줄", "calendar", "schedule", "meeting", "agenda", "plans"]) {
            let day = has(["내일", "tomorrow"]) ? 1 : 0
            let part: Part = has(["오전", "아침", "morning"]) ? .morning
                : has(["오후", "점심", "afternoon"]) ? .afternoon
                : has(["저녁", "밤", "evening", "tonight", "night"]) ? .evening : .wholeDay
            return .calendar(day: day, part: part)
        }
        // The one guard every local action passes ("should I set a timer?" is a question, not a timer).
        switch ArisIntent.guarded(ArisIntent.parse(text), said: text) {
        case .tellTime: return .time
        case .tellDate: return .date
        // A plain timer only: a focus session or a pomodoro is more than the practice shows.
        case .timer(let seconds, false): return .timer(.timer(seconds: seconds, focus: false))
        case .cancelTimer: return .timer(.cancelTimer)
        case .pauseTimer: return .timer(.pauseTimer)
        case .resumeTimer: return .timer(.resumeTimer)
        case .addTime(let seconds): return .timer(.addTime(seconds))
        default: return .other
        }
    }

    /// Whether the practice answers this request by itself, with no AI and no permission: a timer, the time or the
    /// date. The calendar needs its permission, and anything else only gets the line that the practice does no more.
    static func answersAlone(_ text: String) -> Bool {
        switch question(text) {
        case .timer, .time, .date: true
        case .calendar, .other: false
        }
    }

    /// The hours a part of the day covers: morning 6–12, afternoon 12–18, evening 18–24; the whole day 0–24.
    static func hours(_ part: Part) -> (from: Int, to: Int) {
        switch part {
        case .wholeDay: (0, 24)
        case .morning: (6, 12)
        case .afternoon: (12, 18)
        case .evening: (18, 24)
        }
    }

    static func window(day: Int, part: Part, now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let midnight = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)) ?? now
        let (from, to) = hours(part)
        let start = calendar.date(byAdding: .hour, value: from, to: midnight) ?? midnight
        let end = calendar.date(byAdding: .hour, value: to, to: midnight) ?? midnight
        return (start, end)
    }

    /// Events of a part of the day: timed ones only, except the whole day, which names all-day ones too.
    static func agenda(_ events: [Event], day: Int, part: Part, korean: Bool, calendar: Calendar = .current) -> String {
        let shown = events.filter { part == .wholeDay || !$0.isAllDay }.sorted { $0.start < $1.start }
        let when = korean ? dayKorean(day) + partKorean(part) : english(day: day, part: part)
        guard !shown.isEmpty else { return korean ? "\(when)엔 일정이 없어요." : "Nothing on your calendar \(when)." }
        let items = shown.prefix(3).map { event in
            event.isAllDay ? event.title : "\(clock(event.start, korean: korean, calendar: calendar)) \(event.title)"
        }
        let more = shown.count > 3 ? (korean ? " 외 \(shown.count - 3)개" : ", and \(shown.count - 3) more") : ""
        if korean { return "\(when) 일정은 \(shown.count)개예요: \(items.joined(separator: ", "))\(more)." }
        return "\(shown.count) on your calendar \(when): \(items.joined(separator: ", "))\(more)."
    }

    static func noCalendar(korean: Bool) -> String {
        korean ? "캘린더 권한이 없어서 일정을 못 봤어요." : "I can't see your calendar without access to it."
    }

    /// Anything but a timer, the time, the date or the calendar: the practice does nothing with it.
    static func answersOnly(korean: Bool) -> String {
        korean ? "연습 중이라 지금은 타이머와 시간만 돼요. 설정을 마치면 뭐든 시켜 보세요."
            : "This is practice, so for now I only do timers and the time. Once setup is done, ask me anything."
    }

    private static func dayKorean(_ day: Int) -> String { day == 1 ? "내일" : "오늘" }
    private static func partKorean(_ part: Part) -> String {
        switch part {
        case .wholeDay: ""
        case .morning: " 오전"
        case .afternoon: " 오후"
        case .evening: " 저녁"
        }
    }

    /// "this afternoon", "tomorrow morning", "today".
    private static func english(day: Int, part: Part) -> String {
        let piece: String
        switch part {
        case .wholeDay: return day == 1 ? "tomorrow" : "today"
        case .morning: piece = "morning"
        case .afternoon: piece = "afternoon"
        case .evening: piece = "evening"
        }
        return (day == 1 ? "tomorrow " : "this ") + piece
    }

    private static func clock(_ date: Date, korean: Bool, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date), minute = calendar.component(.minute, from: date)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        if korean { return (hour < 12 ? "오전 " : "오후 ") + (minute == 0 ? "\(twelve)시" : "\(twelve)시 \(minute)분") }
        return minute == 0 ? "\(twelve) \(hour < 12 ? "am" : "pm")" : String(format: "%d:%02d %@", twelve, minute, hour < 12 ? "am" : "pm")
    }
}
