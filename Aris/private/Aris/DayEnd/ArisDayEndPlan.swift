//
//  ArisDayEndPlan.swift
//  Aris
//
//  What the day-end list (ArisDayEnd) holds, worked out from the day's facts.
//  Planned for today: every to-do due today or overdue (ticked off today is done; one put off from this list stays,
//  marked 넘겼어요), today's calendar events (over is done, going on is under way; an all-day one is left out, it is
//  nothing to finish), a deadline due today, what the user handed to Aris or a teammate (finished is done, still running
//  is under way, failed or stopped is not done), and Aris's schedules that were due today (ran is done, missed, failed
//  or still ahead is not done; one that repeats every few minutes all day is left out).
//  Waiting for him: the 확인 대기 cards, and a job's question on its way to the screen. Those are never also planned.
//  Tomorrow: its first things, by time.
//  Everything else done today (a timer, the volume, a conversion asked for on the spot, a to-do ticked off that wasn't
//  due) is not planned work: it is kept apart as 그 밖, by the activity record's own lines.
//  The same thing is listed once: a to-do Aris ticked off is the to-do (its line in the record is dropped), a schedule's
//  result in the 기록 list is the schedule, the record's lines of a listed job are that job, and a job asked for twice
//  is one row with its best outcome. Foundation only, so it is tested.
//

import Foundation

enum ArisDayEndPlan {
    /// How many of tomorrow's things, and of the unplanned work, are listed before the rest are counted.
    static let tomorrowShown = 4
    static let extrasShown = 12
    /// The record's line for the list's own 내일로 넘기기 (ArisDayEndPush): putting something off is not work done.
    static let pushLead = "내일로 넘김"
    /// The record's line for a to-do ticked off (aris-tools and the app write it).
    static let tickLead = "할 일 완료"

    /// A title as two sources may write the same thing: case, spaces and marks aside.
    static func key(_ title: String) -> String {
        title.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    // MARK: - Planned for today

    /// Done first, then what is under way, what is left, and what was put off; inside each, to-dos, events, deadlines,
    /// jobs and routines in that order, each by its time.
    static func planned(_ facts: ArisDayEndFacts, span: ArisDaySpan, now: Date, time: (Date) -> String) -> [ArisDayEnd.Item] {
        let routines = routineItems(facts.routines)
        let scheduled = Set(routines.map { key($0.title) })
        // A schedule's result in the 기록 list is the schedule's own row.
        let jobs = jobItems(facts.jobs).filter { !scheduled.contains(key($0.title)) }
        let all = todoItems(facts, span: span, now: now) + eventItems(facts.events, span: span, now: now, time: time)
            + deadlineItems(facts.deadlines, span: span) + jobs + routines
        return all.enumerated().sorted { (rank($0.element.state), $0.offset) < (rank($1.element.state), $1.offset) }.map(\.element)
    }

    private static func rank(_ state: ArisDayEnd.State) -> Int {
        switch state {
        case .done: return 0
        case .part: return 1
        case .none: return 2
        case .moved: return 3
        }
    }

    static func todoItems(_ facts: ArisDayEndFacts, span: ArisDaySpan, now: Date) -> [ArisDayEnd.Item] {
        facts.todos.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }.compactMap { todo in
            guard let due = todo.due else { return nil }
            let item = { (state: ArisDayEnd.State) in ArisDayEnd.Item(id: "todo:" + todo.id, title: todo.title, kind: .todo, state: state, todo: todo.id) }
            if let completed = todo.completed { return span.isToday(completed, now: now) && due < span.tomorrow ? item(.done) : nil }
            if due < span.tomorrow { return item(.none) }
            return facts.moved.contains(todo.id) ? item(.moved) : nil
        }
    }

    static func eventItems(_ events: [ArisDayEndFacts.Event], span: ArisDaySpan, now: Date, time: (Date) -> String) -> [ArisDayEnd.Item] {
        events.filter { !$0.allDay && $0.start >= span.today && $0.start < span.tomorrow }.sorted { $0.start < $1.start }.enumerated().map { index, event in
            let state: ArisDayEnd.State = event.end <= now ? .done : event.start <= now ? .part : .none
            return ArisDayEnd.Item(id: "event:\(index):" + event.title, title: time(event.start) + " " + event.title, kind: .event, state: state)
        }
    }

    static func deadlineItems(_ deadlines: [ArisDayEndFacts.Deadline], span: ArisDaySpan) -> [ArisDayEnd.Item] {
        deadlines.filter { $0.at >= span.today && $0.at < span.tomorrow }.sorted { $0.at < $1.at }.enumerated().map { index, deadline in
            ArisDayEnd.Item(id: "deadline:\(index):" + deadline.title, title: "\(deadline.course) \(deadline.title)".trimmingCharacters(in: .whitespaces),
                            kind: .deadline, state: .none)
        }
    }

    /// `jobs`: newest first, as ArisDayEndJobs gives them. Listed oldest first; asked for twice, a job is one row with
    /// its best outcome (a retry that finished is done). A job whose question waits is in the waiting part instead.
    static func jobItems(_ jobs: [ArisDayEndFacts.Job]) -> [ArisDayEnd.Item] {
        let rows = jobs.reversed().compactMap { job -> ArisDayEnd.Item? in
            switch job.outcome {
            case .done: return ArisDayEnd.Item(id: "job:" + job.id, title: job.title, kind: .job, state: .done)
            case .running: return ArisDayEnd.Item(id: "job:" + job.id, title: job.title, kind: .job, state: .part)
            case .failed(let why):
                let reason = ArisDayEnd.short(why)
                return ArisDayEnd.Item(id: "job:" + job.id, title: job.title, kind: .job, state: .none, note: reason.isEmpty ? nil : reason)
            case .stopped: return ArisDayEnd.Item(id: "job:" + job.id, title: job.title, kind: .job, state: .none)
            case .asking: return nil
            }
        }
        return once(rows)
    }

    /// A one-time schedule is something he asked for once (시킨 일); one that comes back is a routine.
    static func routineItems(_ routines: [ArisDayEndFacts.Routine]) -> [ArisDayEnd.Item] {
        once(routines.sorted { $0.at < $1.at }.enumerated().map { index, routine in
            let state: ArisDayEnd.State = routine.state == .done ? .done : routine.state == .running ? .part : .none
            return ArisDayEnd.Item(id: "routine:\(index):" + routine.title, title: routine.title, kind: routine.repeats ? .routine : .job, state: state)
        })
    }

    /// Rows with one title are one row, in the first one's place, with the best state among them.
    private static func once(_ rows: [ArisDayEnd.Item]) -> [ArisDayEnd.Item] {
        rows.reduce(into: [ArisDayEnd.Item]()) { kept, row in
            guard let at = kept.firstIndex(where: { key($0.title) == key(row.title) }) else { return kept.append(row) }
            if rank(row.state) < rank(kept[at].state) { kept[at] = row }
        }
    }

    // MARK: - Waiting for the user

    /// The parked 확인 대기 cards first (oldest first, as their chips are), then a question about to be asked.
    static func waiting(_ facts: ArisDayEndFacts) -> [ArisDayEnd.Waiting] {
        let cards = facts.cards.map { card -> ArisDayEnd.Waiting in
            let action = card.action.trimmingCharacters(in: .whitespacesAndNewlines)
            return ArisDayEnd.Waiting(id: "card:" + card.id, title: action.isEmpty || action == card.title ? card.title : "\(action) · \(card.title)", card: card.id)
        }
        let asking = facts.jobs.filter { $0.outcome == .asking }.map { ArisDayEnd.Waiting(id: "ask:" + $0.id, title: $0.title) }
        return cards + asking
    }

    // MARK: - Tomorrow

    /// Everything tomorrow holds: what has a time first, by that time, then what has none.
    static func tomorrow(_ facts: ArisDayEndFacts, span: ArisDaySpan, english: Bool, time: (Date) -> String) -> [ArisDayEnd.Later] {
        var rows: [(clock: Bool, at: Date, row: ArisDayEnd.Later)] = []
        for event in facts.events where span.isTomorrow(event.start) {
            rows.append((!event.allDay, event.start, ArisDayEnd.Later(id: "event:\(rows.count)", time: event.allDay ? ArisDayEndCopy.allDay(english: english) : time(event.start),
                                                                      title: event.title, kind: .event)))
        }
        for todo in facts.todos where todo.completed == nil {
            guard let due = todo.due, span.isTomorrow(due) else { continue }
            rows.append((todo.hasTime, due, ArisDayEnd.Later(id: "todo:" + todo.id, time: todo.hasTime ? time(due) : "", title: todo.title, kind: .todo)))
        }
        for deadline in facts.deadlines where span.isTomorrow(deadline.at) {
            rows.append((true, deadline.at, ArisDayEnd.Later(id: "deadline:\(rows.count)", time: time(deadline.at),
                                                             title: "\(deadline.course) \(deadline.title)".trimmingCharacters(in: .whitespaces), kind: .deadline)))
        }
        for schedule in facts.schedules where span.isTomorrow(schedule.at) {
            let when = schedule.every.map { ArisDayEndCopy.every(seconds: $0, english: english) } ?? time(schedule.at)
            rows.append((schedule.every == nil, schedule.at, ArisDayEnd.Later(id: "schedule:\(rows.count)", time: when, title: schedule.title,
                                                                              kind: schedule.repeats ? .routine : .job)))
        }
        return rows.enumerated().sorted { ($0.element.clock ? 0 : 1, $0.element.at, $0.offset) < ($1.element.clock ? 0 : 1, $1.element.at, $1.offset) }.map(\.element.row)
    }

    // MARK: - Done without having been planned

    /// The record's lead and what follows it: "변환: a.heic → a.pdf" is ("변환", "a.heic → a.pdf").
    static func parts(_ summary: String) -> (lead: String, rest: String) {
        guard let colon = summary.range(of: ": ") else { return (summary, "") }
        return (String(summary[..<colon.lowerBound]), String(summary[colon.upperBound...]))
    }

    /// Today's lines of the activity record that no planned row stands for, and the to-dos ticked off today that
    /// weren't due, newest first, each in the card's language. Something undone again isn't work done.
    static func extras(_ facts: ArisDayEndFacts, span: ArisDaySpan, now: Date, planned: [ArisDayEnd.Item], english: Bool) -> [ArisDayEnd.Extra] {
        let handed = Set(planned.filter { $0.kind == .job || $0.kind == .routine }.map { key($0.title) })
        let ticked = facts.todos.filter { todo in todo.completed.map { span.isToday($0, now: now) } ?? false }
        let tickedTitles = Set(ticked.map { key($0.title) })
        let loose = ticked.filter { todo in todo.due.map { $0 >= span.tomorrow } ?? true }
        let lines = (facts.activity ?? []).filter { row in
            guard span.isToday(row.date, now: now), !row.undone else { return false }
            let line = parts(row.summary)
            if line.lead == pushLead { return false }
            // A to-do Aris ticked off is the to-do itself, planned or not.
            if line.lead == tickLead, tickedTitles.contains(key(line.rest)) { return false }
            return !handed.contains(key(row.job))
        }
        let rows = loose.map { (at: $0.completed ?? now, row: ArisDayEnd.Extra(id: "todo:" + $0.id, title: ArisActivityWords.shown("\(tickLead): \($0.title)", english: english))) }
            + lines.map { (at: $0.date, row: ArisDayEnd.Extra(id: $0.id, title: ArisActivityWords.shown($0.summary, english: english))) }
        return rows.enumerated().sorted { ($1.element.at, $0.offset) < ($0.element.at, $1.offset) }.map(\.element.row)
    }
}
