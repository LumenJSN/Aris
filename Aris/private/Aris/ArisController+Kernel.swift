//
//  ArisController+Kernel.swift
//  Aris
//
//  The kernel's turns in the controller (ARCHITECTURE.md 3.1, migration steps 1 and 2). A turn is opened here and
//  nowhere else; its work runs in `ArisTurnScope` with the turn's id, so every task it starts carries the id too, and
//  `setSession` (ArisController.swift) drops whatever such work writes once its turn is over. Opening the next turn,
//  or ending this one, cancels the turn's task and resumes its card's wait as cancelled (ArisKernel).
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// Whether the calling code may still act for its turn: the turn it was started for is current, or it works for
    /// no turn at all.
    var turnIsCurrent: Bool { kernel.state.admits(ArisTurnScope.current) }

    /// Opens the next turn. The one before is over: its task is cancelled, its card's wait resumed as cancelled, and
    /// whatever it still writes is dropped.
    @discardableResult
    func openTurn(_ origin: ArisTurnOrigin) -> ArisTurnID {
        // The turn before still owes its line to turns.jsonl (its task returns on cancellation without one): written
        // now, as replaced, before this turn's numbers start.
        writeReplacedTurnLine()
        let id = kernel.openTurn(origin)
        log.notice("\(id.description, privacy: .public) opened (\(origin.rawValue, privacy: .public))")
        // The new turn starts from what the old one really finished: its cut-off step is never ticked under this
        // turn's answer, and its card is gone.
        setSession(session.replaced(), from: id)
        return id
    }

    /// Ends the current turn with no turn after it (stopped, dismissed, failed quietly): as when a turn is replaced.
    func endTurn(_ why: ArisTurnEnd) {
        kernel.endTurn(nil, why)
        turn?.cancel()
    }

    /// Runs `work` as the turn's task (`turn`), for the turn the calling code works for, else the current one, else a
    /// new one. Nothing runs when the calling code works for a turn that is over.
    @discardableResult
    func runTurn(_ origin: ArisTurnOrigin, @_implicitSelfCapture _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        guard turnIsCurrent else {
            log.notice("work for a turn that is over was not started")
            return nil
        }
        let id = ArisTurnScope.current ?? kernel.current ?? openTurn(origin)
        return ArisTurnScope.within(id) {
            let task = Task { @MainActor in await work() }
            turn = task
            return task
        }
    }

    /// Opens a turn and runs `work` as it (the brief, the evening summary, the preview harness).
    @discardableResult
    func startTurn(_ origin: ArisTurnOrigin, @_implicitSelfCapture _ work: @escaping @MainActor () async -> Void) -> Task<Void, Never>? {
        ArisTurnScope.within(openTurn(origin)) { runTurn(origin, work) }
    }
}
