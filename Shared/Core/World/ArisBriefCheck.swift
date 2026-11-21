//
//  ArisBriefCheck.swift
//  Aris
//
//  Whether the morning brief opens the notch at the day's first unlock (ArisController+Brief). It used to open on every
//  first unlock of the day, whatever there was to tell and whatever the user was doing. Now: only once it is due (once a
//  day, from 5 in the morning, ArisBrief.isDue), only when it has something to tell (a timed event still to come
//  today, a deadline this week, a new announcement, or rain likely), and only at a moment the interruption policy
//  lets it come up (not in a call, not while the user or Aris is talking, not on a locked screen). "브리핑 해줘" still
//  shows it whatever it holds. Foundation only.
//

import Foundation

enum ArisBriefCheck {
    /// What the brief would hold, counted.
    struct Facts: Equatable, Sendable {
        var eventsLaterToday = 0
        var dueThisWeek = 0
        var announcements = 0
        /// The chance of rain in percent, when the weather came.
        var rainChance: Int?
    }

    /// Rain this likely is worth telling (ArisBrief's umbrella line).
    static let rainWorthTelling = 50

    /// From aris-agent's /brief JSON (due, dueCount, announcements, weather.rain) and today's timed events' starts, as
    /// ArisBrief.make reads them.
    static func facts(agent: [String: Any], eventStarts: [Date], now: Date, calendar: Calendar = .current) -> Facts {
        let later = eventStarts.filter { $0 >= now && calendar.isDate($0, inSameDayAs: now) }.count
        let dueList = (agent["due"] as? [[String: Any]]) ?? []
        let due = dueList.isEmpty ? 0 : (agent["dueCount"] as? Int ?? dueList.count)
        let weather = agent["weather"] as? [String: Any]
        let rain = weather.flatMap { $0["temp"] is Int ? ($0["rain"] as? Int ?? 0) : nil }
        return Facts(eventsLaterToday: later, dueThisWeek: due, announcements: agent["announcements"] as? Int ?? 0, rainChance: rain)
    }

    static func hasNews(_ facts: Facts) -> Bool {
        facts.eventsLaterToday > 0 || facts.dueThisWeek > 0 || facts.announcements > 0 || (facts.rainChance ?? 0) >= rainWorthTelling
    }

    enum Step: Equatable, Sendable {
        /// Not today (shown already, or before 5): nothing happens.
        case notDue
        /// Due, but nothing to tell: the day is marked as done without opening the notch.
        case nothingToTell
        /// Not now: looked at again until the moment comes or the wait runs out.
        case wait(ArisInterruption.Condition)
        case show
    }

    /// What the day's first unlock does with the brief.
    static func step(isDue: Bool, facts: Facts, moment: ArisInterruption.Moment) -> Step {
        guard isDue else { return .notDue }
        let want = ArisInterruption.Want(kind: .brief, urgency: .low, empty: !hasNews(facts))
        switch ArisInterruption.decide(want, moment) {
        case .drop: return .nothingToTell
        case .hold(let condition): return .wait(condition)
        case .speak, .show: return .show
        }
    }

    /// How long the brief waits for its moment after the unlock before it gives the day up for now (the next unlock
    /// tries again).
    static let longestWait: TimeInterval = 15 * 60
    /// How often a waiting brief looks at the moment again.
    static let recheck: TimeInterval = 3
}
