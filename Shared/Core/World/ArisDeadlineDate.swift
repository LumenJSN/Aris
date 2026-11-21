//
//  ArisDeadlineDate.swift
//  Aris
//
//  When one of the user's own dated to-dos is due, for its deadline alerts (ArisTodoModel.alertIfDue, ArisDueAlert). A
//  Reminders to-do with a day and no time comes out of EventKit at that day's midnight, its start, and the alerts
//  measured 24 h and 3 h back from there: the "24 h" alert came at midnight a whole day early and the "3 h" one at
//  nine the evening before, and nothing came on the day itself. A day without a time is its end (as ArisTodoDate reads
//  "내일까지"): the deadline is 23:59 that day, and its alerts never come before that day has begun. Foundation only.
//

import Foundation

enum ArisDeadlineDate {
    /// The moment a to-do is due: its own time, or 23:59 on its day when it has none.
    static func deadline(_ due: Date, hasTime: Bool, calendar: Calendar = .current) -> Date {
        guard !hasTime else { return due }
        let start = calendar.startOfDay(for: due)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return due }
        return nextDay.addingTimeInterval(-60)
    }

    /// Whether its alerts may come at `now`: a to-do with no time of day never alerts before its own day.
    static func mayAlert(_ due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        hasTime || now >= calendar.startOfDay(for: due)
    }
}
