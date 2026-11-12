//
//  ArisTagTimes.swift
//  Aris
//
//  When each running tag of the turn began running, for its clock (ArisTagProgress in ArisTagText.swift: a tag shows
//  the time since it began once that is past ten seconds), and when the turn began working, which is where the stop
//  line's look at the activity record starts (ArisStopLine). Read off the session each time it changes; a value, so
//  it is tested without a clock. Foundation only.
//

import Foundation

/// When each running tag began running, and when the turn began working. A value: each look at the session returns
/// the next one.
struct ArisTagTimes: Equatable {
    /// A running tag's id (its place in the turn) and when it began running. A tag relabelled in place keeps its time;
    /// a finished one has none, and starts from zero if its task runs again.
    private(set) var began: [Int: Date] = [:]
    /// When the turn under way (or the last one) began working: what the record holds since then is this turn's.
    private(set) var turnBegan: Date?
    private var heard = ""
    private var inTurn = false

    /// `running`: the ids of the tags running now. `inTurn`: a turn is under way (working, or waiting on its card).
    func seeing(running: [Int], heard: String, inTurn: Bool, at now: Date) -> ArisTagTimes {
        var next = self
        if inTurn, !self.inTurn || heard != self.heard {
            next.turnBegan = now
            next.began = [:]
        }
        next.heard = heard
        next.inTurn = inTurn
        let kept = next.began
        next.began = Dictionary(uniqueKeysWithValues: (inTurn ? running : []).map { ($0, kept[$0] ?? now) })
        return next
    }

    func seeing(_ session: ArisSession, at now: Date) -> ArisTagTimes {
        let working = session.phase == .thinking
        return seeing(running: working ? session.tags.filter { !$0.done }.map(\.id) : [], heard: session.heard,
                      inTurn: working || session.question != nil, at: now)
    }
}
