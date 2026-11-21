//
//  ArisSilenceClock.swift
//  Shared/Core (aris-agent, tests)
//
//  How long a turn may go on: it ends when its brain has said nothing at all (no line, no piece of a line, nothing on
//  stderr) for `silence` seconds, or once it has run `ceiling` seconds in all. A hold (a card waiting on the user, a judge,
//  a long media conversion, Aside) stops the clock: nothing ends before the hold does, the quiet is counted from its
//  end, and the held time doesn't count toward the ceiling. Pure: the runner's watch reads the deadline from here.
//
//  The numbers (ArisTurnLimits):
//  · a chat turn: quiet 120 s, as the whole turn had before, so no turn that lived then dies now; 10 minutes in all, a
//    spoken turn that streams longer has run away (the user can always cut in);
//  · a job: quiet at least 10 minutes, and longer than the longest tool call its brain lets run without a line, with
//    a margin (`job(longestSilentCall:)`: Claude Code's Bash may run 30 minutes, BASH_MAX_TIMEOUT_MS, so a Claude job
//    may be quiet 32; the API helper waits up to 11 minutes on a slow call; Codex streams a command's output as it
//    comes); 4 hours in all.
//

import Foundation

struct ArisTurnLimits: Equatable {
    let silence: TimeInterval
    let ceiling: TimeInterval

    static let chat = ArisTurnLimits(silence: 120, ceiling: 600)
    /// A job's least quiet limit and its ceiling.
    static let job = ArisTurnLimits(silence: 600, ceiling: 4 * 3_600)
    /// What a job may stay quiet past the longest silent tool call its brain allows.
    static let jobMargin: TimeInterval = 120

    /// A job on a brain whose tool calls may run `longestSilentCall` seconds without a line: never ended inside one.
    static func job(longestSilentCall: TimeInterval) -> ArisTurnLimits {
        ArisTurnLimits(silence: max(job.silence, longestSilentCall + jobMargin), ceiling: job.ceiling)
    }
}

struct ArisSilenceClock: Equatable {
    enum Why: String, Equatable {
        /// Nothing came for `silence` seconds.
        case silence
        /// It ran past the ceiling.
        case ceiling
    }

    let limits: ArisTurnLimits
    let began: Date
    private(set) var lastHeard: Date
    private var holdStart: Date?
    private var holdUntil: Date?
    /// Held time already over.
    private var heldBefore: TimeInterval = 0

    init(limits: ArisTurnLimits, at now: Date = Date()) {
        self.limits = limits
        began = now
        lastHeard = now
    }

    /// The brain said something.
    mutating func heard(at now: Date = Date()) {
        lastHeard = max(lastHeard, now)
    }

    /// Nothing ends for `seconds` from now (0 ends the hold now): a card, a judge, a conversion. It counts as activity
    /// now, as the restarted timeout did.
    mutating func hold(for seconds: TimeInterval, at now: Date = Date()) {
        if let holdStart, let holdUntil { heldBefore += max(0, min(now, holdUntil).timeIntervalSince(holdStart)) }
        holdStart = nil
        holdUntil = nil
        if seconds > 0 {
            holdStart = now
            holdUntil = now.addingTimeInterval(seconds)
        }
        heard(at: now)
    }

    /// When the turn ends unless something is heard, and why.
    var deadline: (at: Date, why: Why) {
        let quietFrom = max(lastHeard, holdUntil ?? lastHeard)
        let quietAt = quietFrom.addingTimeInterval(limits.silence)
        let held = heldBefore + ((holdStart.flatMap { start in holdUntil.map { $0.timeIntervalSince(start) } }) ?? 0)
        let ceilingAt = began.addingTimeInterval(limits.ceiling + held)
        return quietAt <= ceilingAt ? (quietAt, .silence) : (ceilingAt, .ceiling)
    }

    /// Whether the turn is over at `now`, and why.
    func expired(at now: Date) -> Why? {
        let end = deadline
        return now >= end.at ? end.why : nil
    }
}
