//
//  ArisMemoryWhen.swift
//  aris-agent, aris-tools
//
//  What kind of thing a plain sentence is about, beyond the user's tastes and habits (ArisMemoryKind.guess): someone in their
//  life ("민수는 디자인팀 팀장이야", "Jisoo is my coworker"), a project ("아리스 프로젝트는 …"), or something on a day
//  ("이번 주 금요일에 부산 가", "dinner with Mina tomorrow"), and when such a day ends: the memory holds until the end of
//  it (or of the end it states: "다음 주까지", "this weekend"), then stops being current (seventh VM pass: both were kept
//  as "About you" with no page and no end). A sentence about the user ("나는 디자인팀 팀장이야", "I'm a designer")
//  stays about him. Foundation only (tested).
//

import Foundation

enum ArisMemoryWhen {
    // MARK: - People

    /// Words that name someone's place in the user's life or work.
    static let koreanRoles = ["팀장", "부장", "과장", "차장", "대리", "사원", "실장", "본부장", "사장", "대표", "이사", "상무", "전무", "매니저", "담당자", "담당",
                              "동료", "상사", "부하", "팀원", "선배", "후배", "동기", "친구", "절친", "여자친구", "남자친구", "애인", "남편", "아내", "와이프",
                              "엄마", "아빠", "어머니", "아버지", "형", "누나", "언니", "오빠", "동생", "아들", "딸", "할머니", "할아버지", "이모", "삼촌",
                              "고모", "외삼촌", "사촌", "조카", "선생님", "교수님", "교수", "코치", "멘토", "이웃", "룸메이트", "고객", "거래처", "의사", "주치의"]
    static let englishRoles = ["boss", "manager", "lead", "colleague", "coworker", "co-worker", "teammate", "team lead", "director", "ceo", "cto",
                               "friend", "best friend", "girlfriend", "boyfriend", "partner", "wife", "husband", "mom", "dad", "mother", "father",
                               "brother", "sister", "son", "daughter", "grandma", "grandpa", "grandmother", "grandfather", "aunt", "uncle", "cousin",
                               "niece", "nephew", "teacher", "professor", "coach", "mentor", "neighbor", "neighbour", "roommate", "client", "doctor",
                               "dentist", "landlord", "intern", "assistant"]
    /// Words that are the user (or a thing, not a person) as a sentence's subject.
    private static let koreanSelf: Set<String> = ["나", "저", "난", "전", "내", "제", "우리", "저희", "이거", "그거", "저거", "이건", "그건", "이게", "그게", "여기", "거기",
                                                  "오늘", "내일", "어제", "지금", "이번", "다음"]
    private static let englishNotNames: Set<String> = ["i", "it", "this", "that", "there", "here", "he", "she", "they", "we", "you", "today", "tomorrow",
                                                       "my", "our", "the", "a", "an", "what", "who", "which", "everything", "nothing", "someone"]
    private static let particles = ["은", "는", "이", "가"]

    /// The person a sentence is about, when it names one by name with their place in the user's life ("민수는 디자인팀
    /// 팀장이야" → 민수; "Jisoo is my coworker" → Jisoo); nil for the user or anything else.
    static func person(in text: String) -> String? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return nil }
        if ArisMemoryText.isKorean(first) {
            guard let particle = particles.first(where: { first.hasSuffix($0) && first.count > $0.count }) else { return nil }
            let name = String(first.dropLast(particle.count))
            guard !koreanSelf.contains(name), name.count <= 8, !koreanRoles.contains(name), !name.hasSuffix("프로젝트") else { return nil }
            let rest = words.dropFirst().joined(separator: " ")
            return koreanRoles.contains(where: rest.contains) ? name : nil
        }
        let pattern = #"^[A-Z][A-Za-z-]{1,24}(?: [A-Z][A-Za-z-]{1,24})?(?: is|'s| was) (?:my|our|a|the)\b.{0,60}$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let line = String(text[match])
        guard let cut = [" is ", "'s ", " was "].compactMap({ line.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        let name = String(line[..<cut.lowerBound])
        guard !englishNotNames.contains(name.lowercased()), !name.split(separator: " ").contains(where: { englishNotNames.contains($0.lowercased()) }) else { return nil }
        let rest = " " + line[cut.upperBound...].lowercased().replacingOccurrences(of: #"[.,!;:]"#, with: " ", options: .regularExpression) + " "
        return englishRoles.contains { rest.contains(" " + $0 + " ") } ? name : nil
    }

    // MARK: - Projects

    /// The project a sentence names ("아리스 프로젝트는 …" → 아리스; "the Lime project ships…" / "project Lime" → Lime).
    static func project(in text: String) -> String? {
        if let match = text.range(of: #"([\p{L}\p{N}_-]{1,24}) ?프로젝트"#, options: .regularExpression) {
            let name = String(text[match]).replacingOccurrences(of: "프로젝트", with: "").trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, !koreanSelf.contains(name), !["이", "그", "저", "새", "비밀", "다음", "이번"].contains(name) { return name }
        }
        for pattern in [#"\b(?:the )?([A-Z][A-Za-z0-9_-]{1,24}) project\b"#, #"\bproject ([A-Z][A-Za-z0-9_-]{1,24})\b"#] {
            guard let range = text.range(of: pattern, options: .regularExpression) else { continue }
            let piece = String(text[range]).replacingOccurrences(of: "the ", with: "").replacingOccurrences(of: "project", with: "")
                .trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty, !englishNotNames.contains(piece.lowercased()) { return piece }
        }
        return nil
    }

    // MARK: - Days

    private static let koreanWeekdays = ["월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7, "일": 1]
    private static let englishWeekdays = ["monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7, "sunday": 1,
                                          "mon": 2, "tue": 3, "tues": 3, "wed": 4, "thu": 5, "thur": 5, "thurs": 5, "fri": 6, "sat": 7, "sun": 1]
    private static let englishMonths = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
                                        "september": 9, "october": 10, "november": 11, "december": 12, "jan": 1, "feb": 2, "mar": 3, "apr": 4,
                                        "jun": 6, "jul": 7, "aug": 8, "sep": 9, "sept": 9, "oct": 10, "nov": 11, "dec": 12]

    /// Whether the sentence is something on a day (or at a time): it names one.
    static func namesDay(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        end(of: text, from: now, calendar: calendar) != nil
    }

    /// The end of the day `text` points at, read from `now` (the last second of that day, or of the stated end: a week,
    /// a weekend, a month); nil when it names no day or time. A habit ("매주 금요일", "every Friday") and a yearly day
    /// ("엄마 생일은 3월 5일") name none.
    static func end(of text: String, from now: Date, calendar: Calendar = .current) -> Date? {
        let lowered = text.lowercased()
        // A habit, or a day that comes back every year (a birthday is a fact about someone, never over).
        if ["매주", "매일", "마다", "every ", "each ", "생일", "생신", "기념일", "birthday", "anniversary"].contains(where: lowered.contains) { return nil }
        guard let day = day(in: lowered, from: now, calendar: calendar) else { return nil }
        return endOf(day, calendar: calendar)
    }

    /// The last moment of the day that holds `date`.
    static func endOf(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func plus(_ days: Int, _ now: Date, _ calendar: Calendar) -> Date? { calendar.date(byAdding: .day, value: days, to: now) }

    /// The given weekday of the week holding `now` moved by `weeks` (weeks start on Monday, as the user's calendar does).
    private static func weekday(_ weekday: Int, weeks: Int, from now: Date, calendar: Calendar) -> Date? {
        var monday = calendar
        monday.firstWeekday = 2
        guard let week = monday.dateInterval(of: .weekOfYear, for: now)?.start,
              let shifted = monday.date(byAdding: .weekOfYear, value: weeks, to: week) else { return nil }
        let offset = (weekday + 5) % 7
        return monday.date(byAdding: .day, value: offset, to: shifted)
    }

    /// This week's `weekday`, or the coming one once this week's has passed (what the user means by it then).
    private static func thisWeek(_ wd: Int, from now: Date, calendar: Calendar) -> Date? {
        guard let day = weekday(wd, weeks: 0, from: now, calendar: calendar) else { return nil }
        return day < calendar.startOfDay(for: now) ? coming(wd, from: now, calendar: calendar) : day
    }

    /// The next `weekday` from today on (today when it is that day).
    private static func coming(_ weekday: Int, from now: Date, calendar: Calendar) -> Date? {
        let today = calendar.component(.weekday, from: now)
        return plus((weekday - today + 7) % 7, now, calendar)
    }

    /// A month and day this year, or next year once it has passed.
    private static func date(month: Int, day: Int, from now: Date, calendar: Calendar) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        let year = calendar.component(.year, from: now)
        guard let this = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return this < calendar.startOfDay(for: now) ? calendar.date(from: DateComponents(year: year + 1, month: month, day: day)) : this
    }

    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }

    private static func day(in text: String, from now: Date, calendar: Calendar) -> Date? {
        // A date as numbers: 2026-11-20, 11/20, 11월 20일.
        if let parts = capture(#"\b(20[0-9]{2})[-./]([0-9]{1,2})[-./]([0-9]{1,2})\b"#, in: text), let y = Int(parts[1]), let m = Int(parts[2]), let d = Int(parts[3]) {
            return calendar.date(from: DateComponents(year: y, month: m, day: d))
        }
        if let parts = capture(#"([0-9]{1,2}) ?월 ?([0-9]{1,2}) ?일"#, in: text), let m = Int(parts[1]), let d = Int(parts[2]) {
            return date(month: m, day: d, from: now, calendar: calendar)
        }
        if let parts = capture(#"(?<![0-9/])([0-9]{1,2})/([0-9]{1,2})(?![0-9/])"#, in: text), let m = Int(parts[1]), let d = Int(parts[2]) {
            return date(month: m, day: d, from: now, calendar: calendar)
        }
        // English month names: "November 20", "20 Nov", "on Nov 20th".
        let monthNames = englishMonths.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let parts = capture(#"\b("# + monthNames + #")\.? ([0-9]{1,2})(?:st|nd|rd|th)?\b"#, in: text), let m = englishMonths[parts[1]], let d = Int(parts[2]) {
            return date(month: m, day: d, from: now, calendar: calendar)
        }
        if let parts = capture(#"\b([0-9]{1,2})(?:st|nd|rd|th)? (?:of )?("# + monthNames + #")\b"#, in: text), let m = englishMonths[parts[2]], let d = Int(parts[1]) {
            return date(month: m, day: d, from: now, calendar: calendar)
        }
        // In N days.
        if let parts = capture(#"([0-9]{1,2}) ?일 ?(?:뒤|후)"#, in: text), let n = Int(parts[1]) { return plus(n, now, calendar) }
        if let parts = capture(#"\bin ([0-9]{1,2}) days?\b"#, in: text), let n = Int(parts[1]) { return plus(n, now, calendar) }
        // Korean weekdays with their week: 이번 주 금요일, 다음 주 월요일, 다다음 주, (이번) 금요일.
        if let parts = capture(#"(다다음|다음|이번|지난) ?주 ?([월화수목금토일])요일"#, in: text), let wd = koreanWeekdays[parts[2]] {
            let weeks = ["다다음": 2, "다음": 1, "이번": 0, "지난": -1][parts[1]] ?? 0
            // "이번 주 금요일" said on a Saturday is the coming one, not yesterday (twelfth VM pass: it was stored ended).
            if weeks == 0 { return thisWeek(wd, from: now, calendar: calendar) }
            return weekday(wd, weeks: weeks, from: now, calendar: calendar)
        }
        if let parts = capture(#"([월화수목금토일])요일"#, in: text), let wd = koreanWeekdays[parts[1]] { return coming(wd, from: now, calendar: calendar) }
        // English weekdays: next Friday (next week's), this Friday, on Friday.
        let weekdays = englishWeekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let parts = capture(#"\bnext ("# + weekdays + #")\b"#, in: text), let wd = englishWeekdays[parts[1]] {
            return weekday(wd, weeks: 1, from: now, calendar: calendar)
        }
        if let parts = capture(#"\b(?:this|on|by|until|till) ("# + weekdays + #")\b"#, in: text), let wd = englishWeekdays[parts[1]] {
            return coming(wd, from: now, calendar: calendar)
        }
        // Whole weeks, weekends and months.
        if text.contains("다음 주말") || text.contains("다음주말") || text.contains("next weekend") { return weekday(1, weeks: 1, from: now, calendar: calendar) }
        if text.contains("주말") || text.contains("this weekend") { return weekday(1, weeks: 0, from: now, calendar: calendar) }
        if text.contains("다음 주") || text.contains("다음주") || text.contains("next week") { return weekday(1, weeks: 1, from: now, calendar: calendar) }
        if text.contains("이번 주") || text.contains("이번주") || text.contains("this week") { return weekday(1, weeks: 0, from: now, calendar: calendar) }
        for (words, months) in [(["다음 달", "다음달", "next month"], 1), (["이번 달", "이번달", "this month"], 0)] where words.contains(where: text.contains) {
            guard let shifted = calendar.date(byAdding: .month, value: months, to: now),
                  let range = calendar.dateInterval(of: .month, for: shifted) else { return nil }
            return range.end.addingTimeInterval(-1)
        }
        // Single days.
        for (words, days) in [(["글피"], 3), (["모레", "day after tomorrow"], 2), (["내일", "tomorrow"], 1), (["오늘", "tonight", "today", "this evening", "this morning", "this afternoon"], 0)]
            where words.contains(where: { text.contains($0) }) {
            return plus(days, now, calendar)
        }
        // A time of day alone: today ("오후 3시에", "3시 반에", "at 3pm", "at 15:30").
        if capture(#"(?:오전|오후|저녁|아침|밤) ?[0-9]{1,2} ?시|[0-9]{1,2} ?시 ?(?:[0-9]{1,2} ?분|반)?에"#, in: text) != nil
            || capture(#"\bat [0-9]{1,2}(?::[0-9]{2})? ?(?:am|pm)\b|\bat [0-9]{1,2}:[0-9]{2}\b"#, in: text) != nil {
            return plus(0, now, calendar)
        }
        return nil
    }
}
