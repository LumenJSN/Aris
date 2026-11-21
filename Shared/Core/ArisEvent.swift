//
//  ArisEvent.swift
//  Aris
//
//  What happens, as the kernel hears it, and what it decides to do about it (ARCHITECTURE.md 3.1). Only the events
//  routed today are here: the turn's lifecycle, a write of turn state, and a confirm card's wait. Later branches add
//  their cases (voice started, transcript final, brain line, speaker finished, ...) beside these; the reducer's switch
//  then names what each one does.
//

import Foundation

enum ArisEvent: Equatable, Sendable {
    /// A turn begins (the kernel numbers it). The turn before it is over: its work is cancelled, its card closes.
    case turnOpened(ArisTurnOrigin)
    /// The turn ends without a successor (stopped, dismissed): its work is cancelled, its card closes.
    case turnEnded(ArisTurnID, ArisTurnEnd)
    /// Code working for `from` (nil: for no turn) wants to change what the notch shows.
    case sessionWrite(from: ArisTurnID?)
    /// A confirm card is on screen and waits for its answer, for the turn `turn` (nil: the current one).
    case cardShown(card: String, turn: ArisTurnID?)
    /// The user answered the card on screen (a click, Y or N, typed words, the band).
    case cardAnswered(card: String, allow: Bool)
    /// The card's waiter is done with it (it timed out, heard an answer, or its agent stopped waiting).
    case cardClosed(ArisCardKey)
    /// The task waiting on the card was cancelled.
    case cardAbandoned(ArisCardKey)
    /// A stage of `turn` was reached (ArisStageClock: first voice, plausible end, request sent, first audio...), `ms`
    /// after the turn began. Changes nothing; kept in the ring for the turn's timings.
    case turnStage(ArisTurnID, name: String, ms: Int)
    /// The world around Aris changed (ArisWorld: the front app, the lock, the audio route, ...). Changes no turn;
    /// kept in the ring so what happened around a turn can be read beside its stages.
    case world(ArisWorldChange)
}

/// What opened a turn: for the event ring and the log.
enum ArisTurnOrigin: String, Sendable {
    case key, voice, wake, typed, dictation, permission, announcement, brief, dayEnd, preview, practice
}

/// Why a turn ended without a successor.
enum ArisTurnEnd: String, Sendable {
    case cancelled, dismissed, interrupted, failed
}

/// One showing of one card: the same card id shown twice is two waits.
struct ArisCardKey: Hashable, Sendable {
    let card: String
    let turn: ArisTurnID?
    let serial: UInt64
}

/// How a card's wait ends, as the kernel resumes it.
enum ArisCardOutcome: Equatable, Sendable {
    /// The user answered: yes or no.
    case answered(Bool)
    /// Another card took its place on screen before an answer.
    case covered
    /// Its turn ended (stopped, or a new turn began) before an answer. Never a no: nothing follows from it.
    case cancelled
}

/// What the kernel's runners do after an event.
enum ArisEffect: Equatable, Sendable {
    /// The turn's running work is cancelled.
    case cancelWork(ArisTurnID)
    /// A card's waiter gets its outcome (exactly once per showing).
    case resumeCard(ArisCardKey, ArisCardOutcome)
    /// The write goes through.
    case write
    /// The write is dropped: it came from a turn that is no longer current.
    case dropWrite(stale: ArisTurnID)
}
