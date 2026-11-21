//
//  ArisSteerableDriver.swift
//  aris-agent
//
//  A brain that takes a note into the turn under way (ArisTaskSteer.Support.midTurn): Codex's app-server (turn/steer
//  with the turn's id, the call its read judge already uses) and Claude Code's stream-json (a user message written
//  during the turn; checked live on 2.1.327: one written while a tool ran joined that same turn, and its one result
//  answered it). agy and the API helper can't: their notes wait for the task's next turn (ArisSteerDesk).
//  A note that came too late for the turn is said at the answer (`takeLateSteer`): Claude has it queued as its next
//  turn (the runner waits for that turn's result), Codex refused it (the runner asks it as the next turn).
//

import Foundation

/// What became of the notes sent into a turn, read once at its answer.
enum ArisSteerLate: Equatable {
    case none
    /// The brain has it queued and runs it as its next turn in the same process.
    case queuedByBrain
    /// The brain refused it: these are asked as the next turn.
    case dropped([String])
}

protocol ArisSteerableDriver: AnyObject {
    /// The lines that put `note` into the turn under way; nil when no turn is open.
    func steerLines(_ note: String) -> [Data]?
    func takeLateSteer() -> ArisSteerLate
}

extension ArisCodexDriver: ArisSteerableDriver {}
extension ArisClaudeDriver: ArisSteerableDriver {}
