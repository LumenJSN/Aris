//
//  ArisTurnClosing.swift
//  Aris
//
//  A turn's answer goes into the history once, as soon as its final reply is known (before the voice reads it), so
//  closing the notch mid-speech can't lose it. 닫기 then keeps a delivered answer and only drops a turn still under
//  way, the way Stop does. Pure, so the tests check them.
//

/// Whether this turn's answer is in the history yet. `record()` says yes once per turn.
struct ArisTurnMemory: Equatable {
    private(set) var remembered = false

    /// A new turn: nothing of it remembered.
    mutating func start() { remembered = false }

    /// True the first time in a turn (record it now); false after.
    mutating func record() -> Bool {
        defer { remembered = true }
        return !remembered
    }
}

/// What 닫기 does to the turn behind the answer.
enum ArisTurnClosing: Equatable {
    /// The final answer is up (and remembered) while the voice reads it: stop the voice, keep the answer, log "ok".
    case keep
    /// A turn still under way, or a failure: drop it as Stop does ("cancelled"; an already logged turn stays as it was).
    case drop
    /// Nothing is running (a finished or parked answer): just put it away.
    case putAway

    static func closing(phase: ArisSession.Phase, remembered: Bool) -> ArisTurnClosing {
        switch phase {
        case .idle: return .putAway
        case .speaking: return remembered ? .keep : .drop
        case .listening, .thinking, .failed: return .drop
        }
    }

    /// The turn's outcome for its stats line; nil logs nothing.
    var outcome: String? {
        switch self {
        case .keep: return "ok"
        case .drop: return "cancelled"
        case .putAway: return nil
        }
    }
}
