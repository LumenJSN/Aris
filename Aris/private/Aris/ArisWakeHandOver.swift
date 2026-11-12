//
//  ArisWakeHandOver.swift
//  Aris
//
//  A wake-word listener becoming a turn's listener. When the voice print is sure, Aris wakes at once, before the
//  recogniser has started: beginTurn() then comes first and start() second, and start() used to put the listener
//  back into its waiting state (every finished phrase forgotten, the recording a rolling four seconds), so without
//  Scribe the turn came back empty or cut (audit voice-2). The order no longer matters. Also what to do when that
//  recogniser can't start at all (audit voice-7). Pure, so both are tested without a microphone.
//

import Foundation

struct ArisWakeHandOver: Equatable {
    /// beginTurn() was called: from here on the listener is a turn's, whatever start() is asked for afterwards.
    private(set) var turnBegan = false

    mutating func beginTurn() { turnBegan = true }

    /// Whether start() comes up waiting for the wake word (phrases without the name forgotten, a rolling recording).
    func startsWaiting(asked: Bool) -> Bool { asked && !turnBegan }

    /// How much of the recording was made before the turn began (the phrase the detector had already caught), for
    /// Whisper's timing: what is recorded now, less the time since the turn began. Never negative.
    static func lead(recordedSeconds: Double, sinceTurnBegan: Duration) -> Duration {
        let lead = Duration.milliseconds(Int(recordedSeconds * 1000)) - sinceTurnBegan
        return lead > .zero ? lead : .zero
    }
}

/// The recogniser that checks a likely "아리스" couldn't start (the speech model isn't installed yet, or starting took
/// too long).
enum ArisWakeStartFailure: Equatable {
    /// Aris already woke on this listener (the voice print was sure): the turn fails with the reason, as a key
    /// press's does, instead of listening to nothing for eight seconds and saying "못 들었어요".
    case failTurn
    /// Still checking the phrase: nothing else may wake Aris into this listener (Whisper hearing the name would open
    /// a turn nobody hears); the check ends as "not 아리스" on its own clock.
    case dropCheck
    /// Another check or turn has the microphone now: nothing to do.
    case nothing

    static func after(isTurnListener: Bool, isWakeListener: Bool) -> ArisWakeStartFailure {
        if isTurnListener { return .failTurn }
        return isWakeListener ? .dropCheck : .nothing
    }
}
