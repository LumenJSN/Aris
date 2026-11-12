//
//  ArisTodos.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  The to-do list (the notch's 할 일 tab): your items live in Apple Reminders (ArisReminders, in the app; here
//  ArisTodoItem is one of them, with the grouping and matching the tab and the voice path share), plus Canvas
//  deadlines still to hand in. ArisTodoList is the older to-do file (aris/todos.json), now only read to import its
//  items once, and where ticked-off Canvas deadlines are remembered. Pure: values in, values out.
//

import Foundation

struct ArisTodo: Codable, Equatable, Identifiable {
    let id: String
    var text: String
    var done: Bool
    let created: Date
    var doneAt: Date?
    /// "내일까지", "금요일 3시": when it's due (ArisTodoDate), if the words said.
    var due: Date?
}

/// A Canvas deadline in the list (from aris-tools canvas --json).
struct ArisDue: Codable, Equatable, Identifiable {
    let id: String
    let course: String
    let title: String
    let at: Date
    let url: String?
}

struct ArisTodoList: Codable, Equatable {
    var todos: [ArisTodo] = []
    /// Canvas deadlines ticked off here ("다 했어"): hidden from the list and from the alerts. Nothing is handed in.
    var hiddenDue: [String] = []

    static let textLimit = 200
    /// What /todos says was finished when "<…> 다 했어" named a Canvas deadline (never its title).
    static let dueTicked = "마감 하나"
    static let keptDays = 7

    func adding(_ raw: String, now: Date, id: String = UUID().uuidString, calendar: Calendar = .current) -> ArisTodoList {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        let (text, due) = ArisTodoDate.titled(trimmed, now: now, calendar: calendar)
        guard !text.isEmpty, !todos.contains(where: { !$0.done && Self.key($0.text) == Self.key(text) }) else { return self }
        var list = self
        list.todos.append(ArisTodo(id: id, text: text, done: false, created: now, doneAt: nil, due: due))
        return list
    }

    /// New words for an item (its date read again from them).
    func editing(_ id: String, to raw: String, now: Date, calendar: Calendar = .current) -> ArisTodoList {
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        let (text, due) = ArisTodoDate.titled(trimmed, now: now, calendar: calendar)
        guard !text.isEmpty, let index = todos.firstIndex(where: { $0.id == id }) else { return self }
        var list = self
        list.todos[index].text = text
        list.todos[index].due = due
        return list
    }

    /// Open items with a due time, as deadlines (for the 24 h / 3 h alerts).
    func dueItems() -> [ArisDue] {
        todos.filter { !$0.done }.compactMap { todo in
            todo.due.map { ArisDue(id: "todo-\(todo.id)", course: "할 일", title: todo.text, at: $0, url: nil) }
        }
    }

    func toggling(_ id: String, now: Date) -> ArisTodoList {
        var list = self
        guard let index = list.todos.firstIndex(where: { $0.id == id }) else { return self }
        list.todos[index].done.toggle()
        list.todos[index].doneAt = list.todos[index].done ? now : nil
        return list
    }

    func removing(_ id: String) -> ArisTodoList {
        var list = self
        list.todos.removeAll { $0.id == id }
        return list
    }

    func hidingDue(_ id: String) -> ArisTodoList {
        guard !hiddenDue.contains(id) else { return self }
        var list = self
        list.hiddenDue.append(id)
        return list
    }

    /// "우유 사기 다 했어": the open item those words name (either contains the other, spaces ignored), done.
    /// Nil when no item, or more than one, matches.
    func finishing(_ words: String, now: Date) -> (list: ArisTodoList, done: ArisTodo)? {
        let said = Self.key(words)
        guard said.count >= 2 else { return nil }
        let matches = todos.filter { !$0.done && (Self.key($0.text).contains(said) || said.contains(Self.key($0.text))) }
        guard matches.count == 1, let match = matches.first else { return nil }
        let list = toggling(match.id, now: now)
        return (list, list.todos.first { $0.id == match.id }!)
    }

    /// Open items first (soonest due first, then the undated oldest first), then today's done ones; older done
    /// ones are dropped after a week.
    func shown(now: Date, calendar: Calendar = .current) -> [ArisTodo] {
        let open = todos.filter { !$0.done }.sorted {
            ($0.due ?? .distantFuture, $0.created) < ($1.due ?? .distantFuture, $1.created)
        }
        let doneToday = todos.filter { $0.done && $0.doneAt.map { calendar.isDate($0, inSameDayAs: now) } == true }
        return open + doneToday
    }

    func pruned(now: Date) -> ArisTodoList {
        var list = self
        let cutoff = now.addingTimeInterval(-Double(Self.keptDays) * 86_400)
        list.todos.removeAll { $0.done && ($0.doneAt ?? $0.created) < cutoff }
        return list
    }

    private static func key(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }
}

/// "PS3 다 했어" about a Canvas deadline: the one whose title (or course and title) those words name.
enum ArisDueMatch {
    static func one(_ words: String, in due: [ArisDue]) -> ArisDue? {
        let key = { (text: String) in text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation } }
        let said = key(words)
        guard said.count >= 2 else { return nil }
        let matches = due.filter { key($0.title).contains(said) || said.contains(key($0.title)) || key($0.course + $0.title).contains(said) }
        return matches.count == 1 ? matches.first : nil
    }
}

/// When a deadline alert is due: 24 hours before (blue) and 3 hours before (red), once each.
enum ArisDueAlert: String, Equatable {
    case dayBefore = "24h", hoursBefore = "3h"

    static let dayBeforeWindow: TimeInterval = 24 * 3_600
    static let hoursBeforeWindow: TimeInterval = 3 * 3_600

    /// The alert to show now for `due`, given the ones already shown ("<id>:24h").
    static func pending(for due: ArisDue, now: Date, shown: Set<String>) -> ArisDueAlert? {
        let left = due.at.timeIntervalSince(now)
        guard left > 0 else { return nil }
        if left <= hoursBeforeWindow { return shown.contains(key(due, .hoursBefore)) ? nil : .hoursBefore }
        if left <= dayBeforeWindow { return shown.contains(key(due, .dayBefore)) ? nil : .dayBefore }
        return nil
    }

    static func key(_ due: ArisDue, _ alert: ArisDueAlert) -> String { "\(due.id):\(alert.rawValue)" }
}

/// When a to-do is due, from its own words: "내일까지 보고서", "금요일 3시 발표 준비", "오늘 오후 2시 반 회의",
/// "다음주 월요일", "11월 5일 시험", "3시에 전화" (a bare hour 1-7 is the afternoon; a time already past is tomorrow;
/// a day without a time is its end). The date words come out of the text. Nothing is guessed from other numbers.
enum ArisTodoDate {
    private static let weekdays: [String: Int] = ["일": 1, "월": 2, "화": 3, "수": 4, "목": 5, "금": 6, "토": 7]

    static func parse(_ raw: String, now: Date, calendar: Calendar = .current) -> (text: String, due: Date?) {
        var text = ArisNumbers.normalize(raw)
        var day: Date?
        var hour: Int?, minute = 0

        func take(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range, in: text) else { return nil }
            let groups = (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
            text.replaceSubrange(range, with: " ")
            return groups
        }

        let today = calendar.startOfDay(for: now)
        if let found = take(#"(오늘|내일|모레|글피)(까지|에)?"#) {
            let offset = ["오늘": 0, "내일": 1, "모레": 2, "글피": 3][found[1]] ?? 0
            day = calendar.date(byAdding: .day, value: offset, to: today)
        } else if let found = take(#"(이번\s?주|다음\s?주)?\s*([월화수목금토일])요일(까지|에)?"#), let weekday = weekdays[found[2]] {
            let thisWeekday = calendar.component(.weekday, from: today)
            if found[1].hasPrefix("다음") {
                let mondayOffset = (thisWeekday + 5) % 7
                let nextMonday = calendar.date(byAdding: .day, value: 7 - mondayOffset, to: today)!
                day = calendar.date(byAdding: .day, value: (weekday + 5) % 7, to: nextMonday)
            } else {
                day = calendar.date(byAdding: .day, value: (weekday - thisWeekday + 7) % 7, to: today)
            }
        } else if let found = take(#"(?:(\d{4})년\s*)?(\d{1,2})월\s*(\d{1,2})일(까지|에)?"#), let month = Int(found[2]), let date = Int(found[3]) {
            // A date said with its year is that day, also when it has gone by (it is what he asked for: overdue).
            // Without a year, a day earlier than today means next year's; today's own date means today.
            let year = Int(found[1])
            var parts = calendar.dateComponents([.year], from: today)
            if let year { parts.year = year }
            parts.month = month
            parts.day = date
            if let candidate = calendar.date(from: parts) {
                day = year == nil && candidate < today ? calendar.date(byAdding: .year, value: 1, to: candidate) : candidate
            }
        } else if let found = take(#"(\d{1,3})\s*(일|주)\s*(후|뒤)(까지|에)?"#), let count = Int(found[1]) {
            day = calendar.date(byAdding: .day, value: count * (found[2] == "주" ? 7 : 1), to: today)
        } else if take(#"이번\s?주말(까지|에)?"#) != nil {
            day = Self.saturday(after: today, weeks: 0, calendar: calendar)
        } else if take(#"다음\s?주말(까지|에)?"#) != nil {
            day = Self.saturday(after: today, weeks: 1, calendar: calendar)
        } else if take(#"다음\s?주(까지|에)?(?![가-힣])"#) != nil {
            day = Self.nextMonday(after: today, calendar: calendar)
        } else if take(#"다음\s?달(까지|에)?(?![가-힣])"#) != nil {
            day = Self.monthStart(after: today, months: 1, calendar: calendar)
        } else if take(#"(?<![가-힣])(이번\s?달\s?말|월말)(까지|에)?(?![가-힣])"#) != nil {
            day = Self.monthEnd(of: today, calendar: calendar)
        }

        if let found = take(#"(오전|오후|아침|저녁|밤)?\s*(\d{1,2})시(\s*(\d{1,2})분|\s*반)?(까지|에)?"#), let value = Int(found[2]), value <= 24 {
            let evening = ["오후", "저녁", "밤"].contains(found[1])
            hour = evening && value < 12 ? value + 12 : (found[1].isEmpty && (1...7).contains(value) ? value + 12 : value)
            minute = found[3].contains("반") ? 30 : Int(found[4]) ?? 0
        }

        // The same in English: "tomorrow", "on friday", "next monday", "at 5", "by 6:30 pm" (never "tomorrow's game", and
        // a bare "at 5" only where the words end, so "meet at 5 guys" keeps its words).
        if day == nil, let found = take(#"(?i)\b(?:(?:by|on|for|until)\s+)?(today|tonight|tomorrow)\b(?!['’])"#) {
            day = calendar.date(byAdding: .day, value: found[1].lowercased() == "tomorrow" ? 1 : 0, to: today)
        } else if day == nil, let found = take(#"(?i)\b(?:(?:on|by|until)\s+(?:(this|next)\s+)?|(this|next)\s+)(sun|mon|tues|wednes|thurs|fri|satur)day\b(?!['’])"#),
                  let weekday = ["sun": 1, "mon": 2, "tues": 3, "wednes": 4, "thurs": 5, "fri": 6, "satur": 7][found[3].lowercased()] {
            let thisWeekday = calendar.component(.weekday, from: today)
            if (found[1] + found[2]).lowercased() == "next" {
                let nextMonday = calendar.date(byAdding: .day, value: 7 - (thisWeekday + 5) % 7, to: today)!
                day = calendar.date(byAdding: .day, value: (weekday + 5) % 7, to: nextMonday)
            } else {
                day = calendar.date(byAdding: .day, value: (weekday - thisWeekday + 7) % 7, to: today)
            }
        } else if day == nil, let found = take(#"(?i)\b(?:(?:by|for|until)\s+)?in\s+(a|an|\d{1,3})\s+(day|week)s?\b"#) {
            let count = Int(found[1]) ?? 1
            day = calendar.date(byAdding: .day, value: count * (found[2].lowercased() == "week" ? 7 : 1), to: today)
        } else if day == nil, let found = take(#"(?i)\b(?:(?:by|on|for|until|over)\s+)?(this|next)\s+weekend\b(?!['’])"#) {
            day = Self.saturday(after: today, weeks: found[1].lowercased() == "next" ? 1 : 0, calendar: calendar)
        } else if day == nil, take(#"(?i)\b(?:(?:by|for|until)\s+)?next\s+week\b(?!['’])"#) != nil {
            day = Self.nextMonday(after: today, calendar: calendar)
        } else if day == nil, take(#"(?i)\b(?:(?:by|for|until)\s+)?next\s+month\b(?!['’])"#) != nil {
            day = Self.monthStart(after: today, months: 1, calendar: calendar)
        } else if day == nil, take(#"(?i)\b(?:(?:by|at|until|before)\s+)?(?:the\s+)?end\s+of\s+(?:the\s+|this\s+)?month\b"#) != nil {
            day = Self.monthEnd(of: today, calendar: calendar)
        }
        if hour == nil, let found = take(#"(?i)\b(?:(?:at|by|until)\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#) ?? take(#"(?i)\b(?:at|by|until)\s+(\d{1,2})(?::(\d{2}))?()\s*$"#),
           let value = Int(found[1]), value <= 24 {
            let half = found[3].lowercased()
            hour = half == "pm" && value < 12 ? value + 12 : half == "am" && value == 12 ? 0 : half.isEmpty && (1...7).contains(value) ? value + 12 : value
            minute = Int(found[2]) ?? 0
        }

        let cleaned = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard day != nil || hour != nil else { return (original, nil) }
        var due: Date?
        if let hour {
            let base = day ?? today
            due = calendar.date(bySettingHour: hour % 24, minute: minute, second: 0, of: base)
            if day == nil, let time = due, time <= now { due = calendar.date(byAdding: .day, value: 1, to: time) }
        } else if let day {
            due = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day)
        }
        return (cleaned.isEmpty ? original : cleaned, due)
    }

    // MARK: - Whole days counted from today

    /// The Monday after `today` (today a Monday: the next one): where "next week" and "다음 주" start.
    static func nextMonday(after today: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: 7 - (calendar.component(.weekday, from: today) + 5) % 7, to: today)
    }

    /// The Saturday of this week's weekend (on a Sunday: today, the weekend is on), or of the weekend `weeks` later.
    static func saturday(after today: Date, weeks: Int, calendar: Calendar) -> Date? {
        let weekday = calendar.component(.weekday, from: today)
        guard weeks > 0 else { return weekday == 1 ? today : calendar.date(byAdding: .day, value: 7 - weekday, to: today) }
        return nextMonday(after: today, calendar: calendar).flatMap { calendar.date(byAdding: .day, value: 5 + 7 * (weeks - 1), to: $0) }
    }

    /// The first day of the month `months` after today's.
    static func monthStart(after today: Date, months: Int, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: today)).flatMap { calendar.date(byAdding: .month, value: months, to: $0) }
    }

    /// The last day of today's month.
    static func monthEnd(of today: Date, calendar: Calendar) -> Date? {
        monthStart(after: today, months: 1, calendar: calendar).flatMap { calendar.date(byAdding: .day, value: -1, to: $0) }
    }

    // MARK: - A due date given on its own (`todo add … --due <words>`)

    private static let months = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    /// When `words` say a to-do is due: everything `parse` reads in a to-do's own text, and the forms that are only
    /// safe where the words are nothing but a date: "Nov 20", "20 November", "11/20", "2026-11-20" (each with a time
    /// after it or none). Nil when they can't be read: the caller says so and adds nothing (fourth VM run, bug 6: an
    /// unread "--due 'next week'" was dropped and the to-do added with no date, while the reply said "due next week").
    static func due(_ words: String, now: Date, calendar: Calendar = .current) -> Date? {
        let plain = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return nil }
        return parse(dated(plain), now: now, calendar: calendar).due
    }

    /// A date at the start of the words written with a month's name or in figures, as "M월 D일", or "Y년 M월 D일" when
    /// a year was written (which `parse` reads: final VM run, "--due 2026-11-11" lost its year here and was stored a
    /// year later); any other words as they are.
    static func dated(_ words: String) -> String {
        // A bare weekday is a day here ("friday", "fri 3pm"); in a to-do's own text it needs "on" or "next" before it.
        let short = ["sun": "sunday", "mon": "monday", "tue": "tuesday", "wed": "wednesday", "thu": "thursday", "fri": "friday", "sat": "saturday"]
        if let regex = try? NSRegularExpression(pattern: "^(sun|mon|tue|wed|thu|fri|sat)(?:day|sday|nesday|rsday|urday)?(?=\\s|$)", options: [.caseInsensitive]),
           let match = regex.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)), let whole = Range(match.range, in: words),
           let stem = Range(match.range(at: 1), in: words), let day = short[words[stem].lowercased()] {
            return "on " + day + words[whole.upperBound...]
        }
        let name = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\\.?"
        let forms: [(pattern: String, month: Int, day: Int, year: Int)] = [
            ("^(?:on |by |until )?(\\d{4})-(\\d{1,2})-(\\d{1,2})(?=\\s|$)", 2, 3, 1),
            ("^(?:on |by |until )?(\\d{1,2})/(\\d{1,2})(?:/(\\d{4}|\\d{2}))?(?=\\s|$)", 1, 2, 3),
            ("^(?:on |by |until )?\(name)\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s+(\\d{4}))?(?=\\s|$|,)", 1, 2, 3),
            ("^(?:on |by |until )?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?\(name)(?:,?\\s+(\\d{4}))?(?=\\s|$|,)", 2, 1, 3),
        ]
        for form in forms {
            guard let regex = try? NSRegularExpression(pattern: form.pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: words, range: NSRange(words.startIndex..., in: words)),
                  let whole = Range(match.range, in: words), let monthRange = Range(match.range(at: form.month), in: words),
                  let dayRange = Range(match.range(at: form.day), in: words) else { continue }
            let monthWord = words[monthRange].lowercased()
            guard let month = Int(monthWord) ?? months[String(monthWord.prefix(3))], (1...12).contains(month),
                  let day = Int(words[dayRange]), (1...31).contains(day) else { continue }
            // The year as written ("26" is 2026); none written: none here, and `parse` picks the coming one.
            let year = Range(match.range(at: form.year), in: words).flatMap { Int(words[$0]) }.map { $0 < 100 ? 2000 + $0 : $0 }
            return (year.map { "\($0)년 " } ?? "") + "\(month)월 \(day)일" + words[whole.upperBound...]
        }
        return words
    }

    // MARK: - A to-do typed or said whole ("add a to-do: return the book, due November 11")

    /// Words that are nothing but a date (everything `due` reads): its date, else nil.
    static func whole(_ words: String, now: Date, calendar: Calendar = .current) -> Date? {
        let plain = dated(words.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !plain.isEmpty else { return nil }
        let read = parse(plain, now: now, calendar: calendar)
        // `parse` gives the words back whole when all of them were the date.
        return read.text == plain ? read.due : nil
    }

    /// A to-do's own words and when it is due. A date phrase at the end ("…, due November 11", "… by friday", "…, 11/20")
    /// or at the start ("by friday: …", "tomorrow at 5, …") is read with the reader `--due` uses and taken out of the
    /// title; then the dates `parse` reads inside the words. A phrase that can't be read as a date stays in the title
    /// untouched, and so does "yesterday": it is no day to set (final VM run: "…, due November 11" became the title).
    /// The dates `parse` reads count only at the start or the end of the words ("내일까지 보고서", "우유 사기 내일"): one
    /// in the middle stays in the title (second upgrade run, bug 5: "Check Orlando weather - drizzle today, 70% chance
    /// of rain" was stored as "…drizzle , 70% chance of rain", due today). This is for his own typed or spoken to-do;
    /// a title a tool passes is never read for dates (ArisTodoModel.draft(title:)).
    static func titled(_ raw: String, now: Date, calendar: Calendar = .current) -> (text: String, due: Date?) {
        let words = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let ends = [#"(?i)[,;:]?\s+(?:due(?:\s+(?:on|by))?|by|on|until|before)\s+"#, #"[,;]\s+"#]
        for pattern in ends {
            for cut in cuts(pattern, in: words) {
                let title = words[..<cut.lowerBound].trimmingCharacters(in: .whitespaces)
                if !title.isEmpty, let due = whole(String(words[cut.upperBound...]), now: now, calendar: calendar) { return (title, due) }
            }
        }
        for cut in cuts(#"[,;:]\s+"#, in: words) {
            let head = words[..<cut.lowerBound].replacingOccurrences(of: #"(?i)^(?:due\s+)?(?:(?:on|by)\s+)?"#, with: "", options: .regularExpression)
            let title = words[cut.upperBound...].trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, let due = whole(head, now: now, calendar: calendar) { return (title, due) }
        }
        return atAnEdge(parse(raw, now: now, calendar: calendar), of: raw)
    }

    /// A read whose date words were at the start or the end of `raw` (what is left is one piece of it, from its first
    /// word or up to its last); else the words whole, with no date.
    static func atAnEdge(_ read: (text: String, due: Date?), of raw: String) -> (text: String, due: Date?) {
        let flat = { (text: String) in text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        let whole = flat(raw), left = flat(read.text)
        guard read.due != nil, !left.isEmpty, left != whole else { return read }
        return whole.hasPrefix(left) || whole.hasSuffix(left) ? read : (raw.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    private static func cuts(_ pattern: String, in words: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: words, range: NSRange(words.startIndex..., in: words)).compactMap { Range($0.range, in: words) }
    }

    /// Said to the AI when `--due` can't be read: nothing was added or changed, and how to write it.
    static func unreadDue(_ words: String) -> String {
        "couldn't read the due date \"\(words)\", so nothing was changed. Write --due as a day (today, tomorrow, friday, next week, in 3 days, this weekend, Nov 20, 11/20) with a time after it or none, or leave --due out and say there is no due date."
    }
}

/// One incomplete reminder, as the tab, the voice path and aris-tools see it.
struct ArisTodoItem: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var notes: String?
    var due: Date?
    /// The due date has a time of day (otherwise the whole day).
    var hasTime: Bool
    var listID: String
    var listName: String
    /// The list's colour, "#rrggbb".
    var colorHex: String
    /// When it was made (EventKit's creationDate): the newest are read first. Nil for an item saved before it was kept.
    var created: Date? = nil

    /// "내일로 미루기" makes sense only for an item with no date, one gone by, or one due today: it sets the day to
    /// tomorrow, which would pull a later item in.
    func canPostponeToTomorrow(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due else { return true }
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return false }
        return due < tomorrow
    }

    /// When it is due, in the language of the line it goes into: "오늘 오후 3:00", "내일", "11월 5일 (수)"; "Today 3:00 PM",
    /// "Tomorrow", "Wed, Nov 5". The one wording of a to-do's due date: the tab's rows (dueLabel) and the list Aris
    /// reads out both come here, each saying which language its line is in (final VM run: "show my to-dos" on an
    /// English Mac read "water the plants (오늘)", because the English line took the Korean wording).
    /// `locale`: the English locale to write in (the tests'); otherwise the Mac's own when it is English, else en_US.
    func dueText(now: Date = .now, calendar: Calendar = .current, english: Bool = false, locale: Locale? = nil) -> String? {
        guard let due else { return nil }
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = english ? "Today" : "오늘"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = english ? "Tomorrow" : "내일"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            day = english ? "Yesterday" : "어제"
        } else {
            day = english ? Self.english(due, "MMMdE", calendar, locale) : Self.formatter("M월 d일 (E)").string(from: due)
        }
        guard hasTime else { return day }
        return "\(day) \(english ? Self.english(due, "jmm", calendar, locale) : ArisKoreanTimeLabel.text(due, calendar: calendar))"
    }

    /// The fields of `template` as an English locale writes them ("Wed, Nov 5", "3:00 PM").
    private static func english(_ date: Date, _ template: String, _ calendar: Calendar, _ locale: Locale?) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale ?? (Locale.current.language.languageCode?.identifier == "en" ? Locale.current : Locale(identifier: "en_US"))
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }
}

enum ArisTodoGroup: Int, CaseIterable, Comparable {
    case overdue, today, tomorrow, thisWeek, later, undated

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .overdue: "지난 것"
        case .today: "오늘"
        case .tomorrow: "내일"
        case .thisWeek: "이번 주"
        case .later: "나중에"
        case .undated: "날짜 없음"
        }
    }

    /// Where an item goes: past (a time already gone, or an earlier day) first, then today, tomorrow, the rest of this
    /// week, later; none without a date.
    static func of(_ item: ArisTodoItem, now: Date, calendar: Calendar = .current) -> ArisTodoGroup {
        guard let due = item.due else { return .undated }
        if item.hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now) { return .overdue }
        if calendar.isDate(due, inSameDayAs: now) { return .today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) { return .tomorrow }
        if let week = calendar.dateInterval(of: .weekOfYear, for: now), due < week.end { return .thisWeek }
        return .later
    }

    /// The items in groups (empty ones left out), each soonest first.
    static func grouped(_ items: [ArisTodoItem], now: Date, calendar: Calendar = .current) -> [(group: ArisTodoGroup, items: [ArisTodoItem])] {
        let buckets = Dictionary(grouping: items) { of($0, now: now, calendar: calendar) }
        return allCases.compactMap { group in
            guard let list = buckets[group], !list.isEmpty else { return nil }
            return (group, list.sorted { ($0.due ?? .distantFuture, $0.title) < ($1.due ?? .distantFuture, $1.title) })
        }
    }
}

enum ArisTodoMatch {
    static func key(_ text: String) -> String { text.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation } }

    /// The items those words could name (either contains the other, spaces ignored).
    static func matches(_ words: String, in items: [ArisTodoItem]) -> [ArisTodoItem] {
        let said = key(words)
        guard said.count >= 2 else { return [] }
        return items.filter { key($0.title).contains(said) || said.contains(key($0.title)) }
    }

    /// The one item those words name: the only match, or the only one titled exactly that; nil when none or several.
    static func one(_ words: String, in items: [ArisTodoItem]) -> ArisTodoItem? {
        let found = matches(words, in: items)
        if found.count == 1 { return found.first }
        let exact = found.filter { key($0.title) == key(words) }
        return exact.count == 1 ? exact.first : nil
    }

    /// The one open item whose title is exactly those words (any spacing or case; "PS3는" names "PS3"): what "… 끝났어"
    /// may tick without the AI. A looser match ("회의" for "회의 자료 준비", "드디어 과제" for "과제") is a guess about what
    /// The user meant, and ticking is an act: the AI settles those (audit intent-2).
    static func named(_ words: String, in items: [ArisTodoItem]) -> ArisTodoItem? {
        let found = items.filter { names(words, title: $0.title) }
        return found.count == 1 ? found.first : nil
    }

    /// Those words are that title, with at most a particle after it.
    static func names(_ words: String, title: String) -> Bool {
        let said = key(words), wanted = key(title)
        guard said.count >= 2, !wanted.isEmpty else { return false }
        return said == wanted || ["은", "는", "이", "가", "을", "를", "도"].contains { said == wanted + $0 }
    }

    /// Why no single item was picked, worded for the AI: several matches are named so it asks the user which one.
    static func unclear(_ words: String, in items: [ArisTodoItem]) -> String {
        let found = matches(words, in: items)
        guard found.count > 1 else { return "no open item matches \"\(words)\"" }
        return "several open items match \"\(words)\": " + found.prefix(5).map(\.title).joined(separator: "; ") + ". Ask the user which one."
    }
}

/// What aris-tools says to the app's POST /aris/todos, and what comes back.
enum ArisTodoRoute {
    struct Request: Equatable {
        enum Op: String {
            case list, add, done, edit, remove, reopen
            /// An undo gives a to-do the due date it had (ArisUndo.restoreTodoDue): by its id, `at` and `timed`.
            case setDue = "set-due"
        }
        var op: Op
        var text: String?
        var due: String?
        var list: String?
        var note: String?
        var id: String?
        /// edit: the item's new title.
        var title: String?
        /// set-due: the date in seconds since 1970, and whether it has a time of day.
        var at: Double?
        var timed = false

        init?(json: [String: Any]) {
            guard let raw = json["op"] as? String, let op = Op(rawValue: raw) else { return nil }
            self.op = op
            text = (json["text"] as? String).map { String($0.prefix(ArisTodoList.textLimit)) }
            due = json["due"] as? String
            list = json["list"] as? String
            note = (json["note"] as? String).map { String($0.prefix(2_000)) }
            id = json["id"] as? String
            title = (json["title"] as? String).map { String($0.prefix(ArisTodoList.textLimit)) }
            at = json["at"] as? Double
            timed = json["timed"] as? Bool ?? false
        }
    }

    static func itemJSON(_ item: ArisTodoItem) -> [String: Any] {
        var json: [String: Any] = ["id": item.id, "title": item.title, "list": item.listName]
        if let due = item.due { json["due"] = ISO8601DateFormatter().string(from: due) }
        if let notes = item.notes, !notes.isEmpty { json["note"] = notes }
        return json
    }

    static func response(ok: Bool, message: String, items: [ArisTodoItem] = []) -> Data {
        let json: [String: Any] = ["ok": ok, "message": message, "items": items.map(itemJSON)]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
    }
}

/// "할 일 뭐 있어" out loud (QA BUG-8): the count said is the count read. Up to `readAll` are all read; past that the
/// newest `readSome`, then "외 N개". Newest first by when they were made; one with no date goes last, in its order.
enum ArisTodoSpeech {
    static let readAll = 7
    static let readSome = 5

    static func ordered(_ items: [ArisTodoItem]) -> [ArisTodoItem] {
        items.enumerated().sorted { a, b in
            switch (a.element.created, b.element.created) {
            case let (x?, y?): return x != y ? x > y : a.offset < b.offset
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return a.offset < b.offset
            }
        }.map(\.element)
    }

    static func line(_ open: [ArisTodoItem], korean: Bool, now: Date = .now) -> String {
        guard !open.isEmpty else { return korean ? "할 일은 비어 있어요." : "Nothing on your list." }
        let sorted = ordered(open)
        let read = sorted.count <= readAll ? sorted : Array(sorted.prefix(readSome))
        let names = read.map { item in item.dueText(now: now, english: !korean).map { "\(item.title) (\($0))" } ?? item.title }.joined(separator: ", ")
        let rest = sorted.count - read.count
        if korean { return "할 일 \(sorted.count)개 있어요: \(names)" + (rest > 0 ? " 외 \(rest)개." : ".") }
        return "\(sorted.count) to-dos: \(names)" + (rest > 0 ? ", and \(rest) more." : ".")
    }
}

/// How a Canvas deadline is said and tagged (the side 할 일 tab, "할 일 뭐 있어"), in Korean 24-hour time like the brief
/// tile: "오늘 17:00", never a 12-hour "05:00" without 오전/오후 (QA BUG-32).
extension ArisDue {
    /// ("오늘 17:00", soon) today, ("내일", false) tomorrow, else the weekday ("수").
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> (String, Bool) {
        if calendar.isDate(date, inSameDayAs: now) { return ("오늘 \(format(date, "HH:mm", calendar))", true) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return ("내일", false) }
        return (format(date, "E", calendar), false)
    }

    /// "CSC263H1" -> "CSC263".
    static func shortCourse(_ code: String) -> String {
        code.range(of: #"^[A-Z]{3}\d{3}"#, options: .regularExpression).map { String(code[$0]) } ?? code
    }

    /// "CSC263 Problem Set 3 (오늘 17:00)", for the spoken summary.
    func spoken(now: Date = .now, calendar: Calendar = .current) -> String {
        "\(Self.shortCourse(course)) \(title) (\(Self.when(at, now: now, calendar: calendar).0))"
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// A written short time in Korean: "오후 3:00", "오전 9:05", and from midnight to 0:59 "밤 12:32", never "오전 12:32"
/// (the spoken time says 밤 12시 32분: ArisKoreanClock). The to-do's due time and the agenda's ranges are written with it.
enum ArisKoreanTimeLabel {
    /// 밤 for the hour after midnight, else 오전 or 오후.
    static func period(hour: Int) -> String {
        hour == 0 ? "밤" : hour < 12 ? "오전" : "오후"
    }

    /// `period` false leaves the part of the day out ("4:00", the end of a range in the same part).
    static func text(hour: Int, minute: Int, period: Bool = true) -> String {
        let clock = "\(hour % 12 == 0 ? 12 : hour % 12):" + String(format: "%02d", minute)
        return period ? "\(Self.period(hour: hour)) \(clock)" : clock
    }

    static func text(_ date: Date, calendar: Calendar = .current, period: Bool = true) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return text(hour: parts.hour ?? 0, minute: parts.minute ?? 0, period: period)
    }
}
