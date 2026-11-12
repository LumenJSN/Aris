//
//  ArisUsageWords.swift
//  Aris
//
//  The 사용량 tab's words in the UI's language (VM run, bug 4: the whole tab was Korean on an English Mac). ArisUsage
//  itself is also compiled into aris-agent, which has no UI language, so its Korean lines stay there and the English
//  is written here beside them. Lengths of time and dates come from the system's formatters in English (ArisUIDates).
//  Foundation only (tested).
//

import Foundation

enum ArisUsageWords {
    static func loading(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("사용량을 불러오는 중…", "Loading usage…", english: english) }
    static func costLoading(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("비용 계산 중…", "Working out the cost…", english: english) }

    /// A limit's name on its row: the five-hour one is the session's, the other the week's.
    static func session(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("세션", "Session", english: english) }
    static func weekly(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("주간", "Weekly", english: english) }

    /// "세션 62% 남음", "Session 62% left".
    static func remaining(_ label: String, percent: Int, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("\(label) \(percent)% 남음", "\(label) \(percent)% left", english: english)
    }

    /// How long until a window resets: "4시간 12분", "4h 12m".
    static func untilReset(_ date: Date?, now: Date, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        guard english else { return ArisUsageParse.untilReset(date, now: now) }
        guard let date else { return "" }
        return ArisUIDates.length(minutes: max(0, Int(date.timeIntervalSince(now) / 60)), locale: locale)
    }

    /// "4시간 12분 후 재설정", "Resets in 4h 12m".
    static func resets(_ date: Date?, now: Date, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let left = untilReset(date, now: now, english: english, locale: locale)
        return ArisUIWords.text("\(left) 후 재설정", "Resets in \(left)", english: english)
    }

    /// The pace line under a bar: "6% 여유 · 재설정까지 유지", "6% to spare · lasts until the reset".
    static func pace(_ pace: ArisUsagePace, now: Date, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        guard english else { return pace.line(now: now) }
        let size = Int(abs(pace.deltaPercent).rounded())
        var text = size == 0 ? "Right on pace" : pace.deltaPercent < 0 ? "\(size)% to spare" : "\(size)% over the pace"
        if pace.willLastToReset {
            text += " · lasts until the reset"
        } else if let eta = pace.etaSeconds {
            text += eta <= 0 ? " · used up" : " · runs out in \(untilReset(now.addingTimeInterval(eta), now: now, english: true, locale: locale))"
        }
        return text
    }

    /// When the numbers were read: "방금 업데이트", "12분 전에 업데이트"; "Updated just now", "Updated 12 min. ago".
    static func updated(minutes: Int, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if minutes < 1 { return ArisUIWords.text("방금 업데이트", "Updated just now", english: english) }
        if english { return "Updated " + ArisUIDates.relative(seconds: -TimeInterval(minutes * 60), locale: locale) }
        if minutes < 60 { return "\(minutes)분 전에 업데이트" }
        if minutes < 1_440 { return "\(minutes / 60)시간 전에 업데이트" }
        return "\(minutes / 1_440)일 전에 업데이트"
    }

    // The spend grid.
    static func today(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("오늘", "Today", english: english) }
    static func thisWeek(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("이번 주간", "This week", english: english) }
    static func todayTokens(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("오늘 토큰", "Tokens today", english: english) }
    static func weekTokens(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("이번 주간 토큰", "Tokens this week", english: english) }
    static func monthCost(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("30일 비용", "Cost, 30 days", english: english) }
    static func monthTokens(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("30일 토큰", "Tokens, 30 days", english: english) }
    static func recentWeeks(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("최근 주간", "Recent weeks", english: english) }

    /// A week's row in the list: this one, the last, then "2주 전".
    static func week(_ index: Int, english: Bool = ArisUIWords.english) -> String {
        switch index {
        case 0: thisWeek(english: english)
        case 1: ArisUIWords.text("지난 주간", "Last week", english: english)
        default: ArisUIWords.text("2주 전", "2 weeks ago", english: english)
        }
    }

    static func topModel(_ model: String, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("많이 쓴 모델: \(model)", "Most used model: \(model)", english: english)
    }

    static func costNote(english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("맥에 남은 기록을 API 가격으로 계산한 값이에요.", "Worked out from the records on this Mac at API prices.", english: english)
    }

    /// A week's dates: "11월 3일 오전 9:00 – 11월 10일 오전 9:00", "Nov 3 at 9:00 AM – Nov 10 at 9:00 AM".
    static func range(_ start: Date, _ end: Date, withTime: Bool, english: Bool = ArisUIWords.english, calendar: Calendar = .current, locale: Locale? = nil) -> String {
        func written(_ date: Date) -> String {
            ArisUIDates.string(date, korean: withTime ? "M월 d일 a h:mm" : "M월 d일", template: withTime ? "MMMdjmm" : "MMMd", english: english, calendar: calendar, locale: locale)
        }
        return "\(written(start)) – \(written(end))"
    }
}
