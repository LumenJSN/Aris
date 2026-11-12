//
//  ArisScheduleCard.swift
//  aris-agent
//
//  The user's card for `aris-tools schedule add …` (QA BUG-28: it was a "Mac 작업" card whose body was the CLI line, flags,
//  path and all): 예약 추가, when it runs, the job's title, what it will do (the command's own whole prompt, never
//  from what the AI says it is doing), and the teammate who runs it (ArisCodexDriver.scheduledAs). Korean, or English
//  when the user's request has no Hangul. The Codex card and the API gate both come here through ArisCodexDriver.describe.
//  Pure, so the tests run it.
//

import Foundation

enum ArisScheduleCard {
    /// The user's request has words and none of them Korean: the card is in English.
    static func isEnglish(_ request: String) -> Bool {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value) || (0x3130...0x318F).contains($0.value) }
    }

    /// (title, detail) for `schedule add <arguments>`, read exactly as aris-tools will read them. `teammate`: the line
    /// naming who runs it, if any.
    static func card(_ arguments: [String], english: Bool, teammate: String?, now: Date = Date(), calendar: Calendar = .current) -> (String, String) {
        let title = english ? "Add a schedule" : "예약 추가"
        guard let parsed = try? ArisScheduleArguments.parse(arguments, now: now, calendar: calendar) else {
            return (title, english ? "This schedule isn't written the way Aris takes it, so nothing would be scheduled even if you allow it."
                                   : "이 예약은 형식이 맞지 않아서, 허용해도 만들어지지 않아요.")
        }
        var lines = [(english ? "When: " : "언제: ") + when(parsed.rule, english: english, calendar: calendar),
                     (english ? "Title: " : "제목: ") + parsed.title,
                     (english ? "Does: " : "할 일: ") + summary(parsed.prompt, english: english)]
        if let teammate { lines.append(teammate) }
        return (title, lines.joined(separator: "\n"))
    }

    /// (title, detail) for `schedule remove <id>`: the schedule's own name and when it runs, looked up by its id among
    /// `jobs` (the helper's own list), never the bare id (fourth VM run, bug 3: the card read "Mac action · Remove"
    /// over a UUID). An id that names no schedule, or words that are no id, say so on the card.
    static func removal(_ arguments: [String], jobs: [ArisScheduledJob], english: Bool, calendar: Calendar = .current) -> (String, String) {
        let title = english ? "Remove a schedule" : "예약 지우기"
        guard arguments.count == 1, let id = UUID(uuidString: arguments[0]), let job = jobs.first(where: { $0.id == id }) else {
            return (title, english ? "No schedule has this id, so nothing would be removed even if you allow it."
                                   : "이 id로 된 예약이 없어서, 허용해도 지워지는 게 없어요.")
        }
        return (title, [(english ? "Title: " : "제목: ") + job.title,
                        (english ? "When: " : "언제: ") + when(job.rule, english: english, calendar: calendar),
                        english ? "It won't run any more." : "더는 실행되지 않아요."].joined(separator: "\n"))
    }

    /// What the run will do: the whole stored prompt, never cut (the card wraps and scrolls, so the user reads all of what
    /// he allows: QA follow-up to BUG-28), a "Say: …" prompt as words.
    static func summary(_ prompt: String, english: Bool) -> String {
        let line = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if line.lowercased().hasPrefix("say:") {
            let said = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if !said.isEmpty { return english ? "says “\(said)”" : "“\(said)”라고 말해요" }
        }
        return line
    }

    private static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// When it runs: ArisSchedule.describe's Korean ("매일 09:00"), or the same in English.
    static func when(_ rule: ArisRepeat, english: Bool, calendar: Calendar) -> String {
        guard english else { return ArisSchedule.describe(rule, calendar: calendar) }
        func clock(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
        switch rule {
        case .once(let date):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "MMM d 'at' HH:mm"
            return "once, " + formatter.string(from: date)
        case .daily(let hour, let minute): return "every day at \(clock(hour, minute))"
        case .weekly(let weekday, let hour, let minute):
            return "every \((1...7).contains(weekday) ? weekdays[weekday - 1] : "week") at \(clock(hour, minute))"
        case .every(let seconds):
            let minutes = max(ArisSchedule.minimumEvery, seconds) / 60
            guard minutes % 60 == 0 else { return "every \(minutes) minutes" }
            return minutes == 60 ? "every hour" : "every \(minutes / 60) hours"
        }
    }
}
