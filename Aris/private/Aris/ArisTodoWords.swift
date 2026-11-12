//
//  ArisTodoWords.swift
//  Aris
//
//  The 할 일 tab's dates and headings in the UI's language (VM run, bug 4). ArisTodos is also compiled into aris-agent
//  and aris-tools, which have no UI language, so its Korean stays there and the English is written here beside it:
//  when an item is due, a Canvas deadline's tag, the groups' headings, the alert's "2시간 남았어요". English dates and
//  lengths of time come from the system's formatters (ArisUIDates). Foundation only (tested).
//

import Foundation

extension ArisTodoItem {
    /// When it is due, on its row: "오늘 오후 3:00", "내일", "11월 5일 (수)"; "Today 3:00 PM", "Tomorrow", "Wed, Nov 5".
    func dueLabel(now: Date = .now, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String? {
        dueText(now: now, calendar: calendar, english: english, locale: locale)
    }
}

extension ArisTodoGroup {
    /// The group's heading in the tab.
    func name(english: Bool = ArisUIWords.english) -> String {
        guard english else { return title }
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .undated: return "No date"
        }
    }
}

extension ArisDue {
    /// A Canvas deadline's tag: ("오늘 17:00", soon), ("내일", false), else the weekday; "Today 17:00", "Tomorrow", "Wed".
    static func whenLabel(_ date: Date, now: Date = .now, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> (String, Bool) {
        guard english else { return when(date, now: now, calendar: calendar) }
        if calendar.isDate(date, inSameDayAs: now) {
            return ("Today " + ArisUIDates.string(date, korean: "", template: "Hmm", english: true, calendar: calendar, locale: locale), true)
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return ("Tomorrow", false) }
        return (ArisUIDates.string(date, korean: "", template: "E", english: true, calendar: calendar, locale: locale), false)
    }
}

enum ArisTodoWords {
    /// What the tab calls a to-do of the user's own where a course's code would stand.
    static func own(english: Bool = ArisUIWords.english) -> String { ArisUIWords.text("할 일", "To-do", english: english) }

    /// The small line of the deadline alert. "Not handed in yet" is said of coursework only; a to-do of his own is
    /// "not done yet" (final check on a new Mac: an ordinary to-do read "To-do · not handed in yet").
    static func alertTag(_ due: ArisDue, shortCourse: String, english: Bool = ArisUIWords.english) -> String {
        due.id.hasPrefix(ownPrefix) ? ArisUIWords.text("\(own(english: english)) · 아직 안 했어요", "\(own(english: english)) · not done yet", english: english)
            : ArisUIWords.text("\(shortCourse) · 아직 안 냈어요", "\(shortCourse) · not handed in yet", english: english)
    }
    /// The id of a deadline made from a to-do of his own (ArisTodoModel).
    static let ownPrefix = "todo-"

    /// The deadline alert's "2시간 남았어요", "45분 남았어요"; "2h left", "45m left".
    static func left(minutes: Int, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        if english { return ArisUIDates.length(minutes: minutes >= 60 ? minutes / 60 * 60 : minutes, locale: locale) + " left" }
        return minutes >= 60 ? "\(minutes / 60)시간 남았어요" : "\(minutes)분 남았어요"
    }

    /// The deadlines' heading: Canvas's, or plain in the demo.
    static func deadlines(demo: Bool, english: Bool = ArisUIWords.english) -> String {
        demo ? ArisUIWords.text("마감", "Due", english: english) : ArisUIWords.text("Canvas 마감", "Canvas deadlines", english: english)
    }

    /// The Reminders errors the tab shows in red, with what the system said after it.
    static func failed(_ what: Failure, _ reason: String? = nil, english: Bool = ArisUIWords.english) -> String {
        let line: String
        switch what {
        case .noTitle: line = ArisUIWords.text("제목을 입력해 주세요.", "Give it a title.", english: english)
        case .missing: line = ArisUIWords.text("항목을 찾지 못했어요. 새로 고친 후 다시 시도해 주세요.", "That item wasn't found. Refresh and try again.", english: english)
        case .save: line = ArisUIWords.text("저장하지 못했어요.", "It couldn't be saved.", english: english)
        case .complete: line = ArisUIWords.text("완료하지 못했어요.", "It couldn't be ticked off.", english: english)
        case .reopen: line = ArisUIWords.text("다시 열지 못했어요.", "It couldn't be opened again.", english: english)
        case .delete: line = ArisUIWords.text("삭제하지 못했어요.", "It couldn't be deleted.", english: english)
        }
        return reason.map { "\(line) \($0)" } ?? line
    }

    enum Failure { case noTitle, missing, save, complete, reopen, delete }
}
