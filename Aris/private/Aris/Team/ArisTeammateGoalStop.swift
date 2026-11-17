//
//  ArisTeammateGoalStop.swift
//  Aris
//
//  A launched Claude Code job runs under `/goal` (the owner, 2026-11-15): after each turn Claude Code's evaluator decides
//  whether the goal holds, and when it doesn't, the next turn starts on its own. The Stop hook Aris hears comes at the
//  end of every turn, before that verdict, so a job's Stop is only its end once the session has stayed quiet for
//  `quiet`: any later event of that session (a tool, the next Stop) means it went on, and the last Stop's words are
//  the ones said. A session that closes ends the job at once. Pure.
//

import Foundation

struct ArisTeammateGoalStop {
    /// How long a session stays quiet after a Stop before the job counts as finished: the evaluator answers in seconds,
    /// and a turn it starts calls its first tool well within this.
    static let quiet: TimeInterval = 120

    private struct Stopped {
        let session: String
        var at: Date
        var message: String?
        /// The session went on after this Stop (a later event that isn't a Stop): nothing is due until its next Stop.
        var going: Bool
    }

    private var stops: [UUID: Stopped] = [:]

    /// The job's session stopped: its end is due `quiet` after `at`, unless it goes on.
    mutating func stopped(job: UUID, session: String, message: String?, at: Date) {
        stops[job] = Stopped(session: session, at: at, message: message, going: false)
    }

    enum Heard: Equatable {
        /// Not about a job that stopped.
        case none
        /// The job's session went on, or stopped again (its end is due later now).
        case wentOn(UUID)
        /// The job's session closed: the job ends now, with the last Stop's words.
        case closed(UUID, message: String?)
    }

    /// An event of a session whose job stopped.
    mutating func heard(_ event: String, session: String, message: String?, at: Date) -> Heard {
        guard let job = stops.first(where: { $0.value.session == session })?.key, var stop = stops[job] else { return .none }
        switch event {
        case "SessionEnd":
            stops[job] = nil
            return .closed(job, message: stop.message)
        case "Stop":
            stop.at = at
            stop.message = message ?? stop.message
            stop.going = false
        default:
            stop.at = at
            stop.going = true
        }
        stops[job] = stop
        return .wentOn(job)
    }

    /// The words to finish the job with when its end, checked at `now`, is due: quiet since a Stop for `quiet`.
    mutating func due(job: UUID, now: Date) -> String?? {
        guard let stop = stops[job], !stop.going, now.timeIntervalSince(stop.at) >= Self.quiet else { return nil }
        stops[job] = nil
        return .some(stop.message)
    }

    /// When the job's end is next due (nil: none is).
    func dueAt(job: UUID) -> Date? {
        stops[job].flatMap { $0.going ? nil : $0.at.addingTimeInterval(Self.quiet) }
    }

    mutating func forget(job: UUID) { stops[job] = nil }

    func isWaiting(job: UUID) -> Bool { stops[job] != nil }
}
