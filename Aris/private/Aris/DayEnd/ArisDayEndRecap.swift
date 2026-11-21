//
//  ArisDayEndRecap.swift
//  Aris
//
//  The day in review (F5) over the day-end card: the same facts and the same list (ArisDayEnd), said in four or five
//  sentences (ArisRecap) instead of one, with the record's digest (what Aris did, by kind) and the coding sessions
//  (what finished, what waits) added. Only with `arisRecap` on (ArisRecapSwitch); off, the card says its one sentence
//  as before. Foundation only, so it is tested.
//

import Foundation

enum ArisDayEndRecap {
    /// A deadline this far ahead is "the nearest" worth saying.
    static let deadlineAhead: TimeInterval = 7 * 86_400

    /// The recap's facts from the card and what it was made from. `now`: when the card was made.
    static func facts(_ card: ArisDayEnd, _ facts: ArisDayEndFacts, now: Date, calendar: Calendar = .current) -> ArisRecapFacts {
        let span = ArisDaySpan(now: now, calendar: calendar)
        var recap = ArisRecapFacts()
        let left = card.planned.filter { $0.state == .none || $0.state == .part }
        recap.plan = .init(planned: card.counts.planned, done: card.counts.done, left: card.counts.left, moved: card.counts.moved,
                           leftTitles: left.map(\.title))
        recap.record = facts.record
        recap.extra = card.counts.extra
        for job in facts.jobs {
            switch job.outcome {
            case .done: recap.tasks.done += 1
            case .failed: recap.tasks.failed += 1
            case .running: recap.tasks.running += 1
            case .stopped, .asking: break
            }
        }
        recap.fleet = facts.sessions
        // What waits for their yes: the cards and the questions on their way (the sessions are counted apart).
        recap.waiting = facts.cards.count + facts.jobs.filter { $0.outcome == .asking }.count
        recap.tomorrowFirst = first(tomorrow: facts, span: span)
        recap.tomorrowCount = card.counts.tomorrow
        let nearest = facts.deadlines.filter { $0.at > now && $0.at <= now.addingTimeInterval(deadlineAhead) }.min { $0.at < $1.at }
        if let nearest {
            let title = "\(nearest.course) \(nearest.title)".trimmingCharacters(in: .whitespaces)
            // Tomorrow's first thing already named it.
            if recap.tomorrowFirst?.title != title || recap.tomorrowFirst?.at != nearest.at { recap.deadline = .init(title: title, at: nearest.at) }
        }
        return recap
    }

    /// Tomorrow's first thing with a time: an event, a to-do with a time, or a deadline.
    static func first(tomorrow facts: ArisDayEndFacts, span: ArisDaySpan) -> ArisRecapFacts.Thing? {
        var things: [ArisRecapFacts.Thing] = facts.events.filter { !$0.allDay && span.isTomorrow($0.start) }.map { .init(title: $0.title, at: $0.start) }
        things += facts.todos.compactMap { todo in
            guard todo.completed == nil, todo.hasTime, let due = todo.due, span.isTomorrow(due) else { return nil }
            return .init(title: todo.title, at: due)
        }
        things += facts.deadlines.filter { span.isTomorrow($0.at) }.map { .init(title: "\($0.course) \($0.title)".trimmingCharacters(in: .whitespaces), at: $0.at) }
        return things.enumerated().min { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }?.element
    }

    /// What is said (and shown above the list) for a day-end request with the recap on.
    static func spoken(_ card: ArisDayEnd, _ facts: ArisDayEndFacts, focus: ArisRecapFocus, now: Date, calendar: Calendar = .current) -> String {
        let recap = ArisRecap.make(self.facts(card, facts, now: now, calendar: calendar), focus: focus, today: ArisDaySpan(now: now, calendar: calendar).today,
                                   now: now, english: card.english, calendar: calendar)
        return recap.spoken
    }
}
