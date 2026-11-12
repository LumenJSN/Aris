//
//  ArisDayEndPush.swift
//  Aris
//
//  내일로 넘기기 on the day-end list (ArisDayEnd): what a press does to a to-do, and what the list remembers for the
//  day. The to-do's due date moves to tomorrow (the day after the one being wrapped up, so past midnight that is the
//  day that has just begun), at the same time of day when it had one. It is his own press, so nothing asks: it is the
//  same edit of a reminder a typed "내일로 미뤄 줘" ends in (ArisReminders.update), and it goes in the activity record
//  with its undo (the date it had), so the receipt under the answer carries 되돌리기 and "방금 거 취소해" takes it back.
//  For the day, the list also keeps whether 목록 was left open and which to-dos were put off (they stay on the list,
//  marked 넘겼어요, and still count as planned). Another day's is forgotten. Foundation only, so it is tested.
//

import Foundation

enum ArisDayEndPush {
    /// The activity record's kind for it (ArisActivity.localUndo knows its undo).
    static let logKind = "todo-due"

    /// The due date after the press. `due`: the date it has (nil: none). `tomorrow`: midnight at the start of tomorrow.
    static func due(after due: Date?, hasTime: Bool, tomorrow: Date, calendar: Calendar = .current) -> Date {
        guard hasTime, let due else { return tomorrow }
        let clock = calendar.dateComponents([.hour, .minute], from: due)
        return calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// The record's line: "내일로 넘김: 보고서 초안 쓰기".
    static func logLine(_ title: String) -> String {
        let flat = title.split(whereSeparator: \.isNewline).joined(separator: " ")
        return "\(ArisDayEndPlan.pushLead): " + String(flat.prefix(120))
    }
}

/// What the list remembers until the day it is about is over.
struct ArisDayEndKept: Codable, Equatable {
    /// The day it belongs to (ArisDaySpan.today).
    var day: Date
    /// 목록 was left open.
    var open = false
    /// The to-dos put off until tomorrow from the list (their ids in Reminders).
    var moved: [String] = []

    /// What was stored, when it is `day`'s; else a new day's, with the list folded.
    static func current(_ stored: Data?, day: Date) -> ArisDayEndKept {
        guard let stored, let kept = try? JSONDecoder().decode(ArisDayEndKept.self, from: stored), kept.day == day else { return ArisDayEndKept(day: day) }
        return kept
    }

    var stored: Data? { try? JSONEncoder().encode(self) }

    func opened(_ open: Bool) -> ArisDayEndKept {
        ArisDayEndKept(day: day, open: open, moved: moved)
    }

    func moving(_ id: String) -> ArisDayEndKept {
        ArisDayEndKept(day: day, open: open, moved: moved.contains(id) ? moved : moved + [id])
    }

    /// Without the to-dos that are due before `tomorrow` again (the move was undone) or are gone or ticked off.
    func settled(open todos: [ArisDayEndFacts.Todo], tomorrow: Date) -> ArisDayEndKept {
        let still = Set(todos.filter { todo in todo.completed == nil && (todo.due.map { $0 >= tomorrow } ?? false) }.map(\.id))
        return ArisDayEndKept(day: day, open: open, moved: moved.filter(still.contains))
    }
}
