//
//  ArisRecap.swift
//  Shared/Core (app, tests)
//
//  The day in review (ARCHITECTURE Part 3, F5), said in four or five sentences: how much of what was planned got done,
//  what Aris did (the record's digest, by kind), what finished (the jobs handed over, the coding sessions), what waits
//  for the owner (확인 대기, a session's question), and what is next (tomorrow's first thing, the nearest deadline).
//  "뭐 남았어" asks for the other half: what is left, what is still under way, what waits and what is next. The full
//  list is the day-end card's (ArisDayEnd); this is only how it is said. Made from facts alone, so no AI is told
//  anything for it. Titles are spoken but never kept in the history the AI reads (ArisDayEndCopy.remembered). Pure.
//

import Foundation

enum ArisRecapFocus: Equatable, Sendable {
    /// "오늘 뭐 했어", "오늘 정리해 줘".
    case day
    /// "뭐 남았어", "what's left".
    case left
}

struct ArisRecapFacts: Equatable, Sendable {
    /// The day-end card's plan, counted as the card counts it.
    struct Plan: Equatable, Sendable {
        var planned = 0
        var done = 0
        /// Neither done nor put off (not started, or under way).
        var left = 0
        var moved = 0
        /// What is left, by its title, in the card's order.
        var leftTitles: [String] = []
    }

    /// The jobs handed to Aris or a teammate today.
    struct Tasks: Equatable, Sendable {
        var done = 0
        var failed = 0
        var running = 0
    }

    struct Thing: Equatable, Sendable {
        let title: String
        let at: Date
        /// It has a time of day (else only a day).
        var timed = true
    }

    var plan = Plan()
    /// The record's changes for the day; nil when there is no record to read (Core 2 off, or the helper didn't answer).
    var record: ArisRecordDigest? = nil
    /// Done without having been planned, by the activity log (said when there is no record).
    var extra = 0
    var tasks = Tasks()
    var fleet: [ArisFleetSession] = []
    /// 확인 대기 cards and job questions on their way: what waits for the owner's yes.
    var waiting = 0
    /// Tomorrow's first thing with a time, and how many things tomorrow holds.
    var tomorrowFirst: Thing? = nil
    var tomorrowCount = 0
    /// The nearest open deadline after now.
    var deadline: Thing? = nil
}

/// The coding sessions, counted for the recap.
struct ArisRecapFleet: Equatable, Sendable {
    var finished = 0
    var working = 0
    /// Waiting for the owner's answer or permission.
    var asking = 0
    var failed = 0

    /// `since`: the start of the day being wrapped up. A session "finished" when it was given work, its turn is over
    /// and it was last active today.
    init(_ sessions: [ArisFleetSession], since: Date) {
        for session in sessions {
            switch session.state {
            case .working: working += 1
            case .waitingInput, .waitingPermission: asking += 1
            case .failed: failed += 1
            case .idle, .gone:
                if session.heard, session.firstRequest != nil, session.lastActive >= since { finished += 1 }
            }
        }
    }
}

struct ArisRecap: Equatable, Sendable {
    /// Four or five at most: the rest is on the card.
    static let longest = 5

    let sentences: [String]

    /// What is said and shown above the list.
    var spoken: String { sentences.joined(separator: " ") }

    /// `today`: the first second of the day being wrapped up (ArisDaySpan.today).
    static func make(_ facts: ArisRecapFacts, focus: ArisRecapFocus, today: Date, now: Date, english: Bool, calendar: Calendar = .current) -> ArisRecap {
        let fleet = ArisRecapFleet(facts.fleet, since: today)
        let say = ArisRecapSentences(facts: facts, fleet: fleet, today: today, english: english, calendar: calendar)
        var sentences: [String]
        switch focus {
        case .day:
            // The day always has its four parts, each said even when it is "nothing" (VM run 2026-11-19, D5: a light day
            // was told in one sentence): the plan, what was done, what waits, what is next; what finished when it did.
            let did = [say.didToday(), say.finished()].compactMap { $0 }
            let plan = say.plan() ?? (did.isEmpty ? say.nothingAtAll() : say.nothingPlanned())
            sentences = [plan] + did + [say.waiting() ?? say.nothingWaits(), say.next() ?? say.nothingNext()]
        case .left:
            // "What is left" always says whether anything waits: "nothing" is an answer here.
            sentences = [say.left(), say.underWay(), say.waiting() ?? say.nothingWaits(), say.next()].compactMap { $0 }
        }
        return ArisRecap(sentences: Array(sentences.prefix(longest)))
    }
}
