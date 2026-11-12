//
//  ArisFixTurns+Live.swift
//  aris-agent
//
//  ArisFixTurns against this Mac: aris-tools' notes are read from their file, and "another AI can take it" is asked
//  of the same table that moves a turn when an AI is at its limit (ArisTurnFallback, with the agent's own record of
//  who is out). Called on the server queue, where every line of a stream is sent.
//

import Foundation

extension ArisFixTurns {
    /// The AI that could take the same request now instead of `failing` (ArisTurnFallback); nil when none can.
    private static func another(_ failing: ArisBrain) -> ArisBrain? {
        ArisTurnFallback.route(insteadOf: failing, turn: ArisTurnFallback.Turn(), apiVision: ArisAPIActive.profile()?.takesImages == true,
                               usable: ArisSealedOneShot.available, available: { brainHealth.isAvailable($0) })?.brain
    }

    /// The `{"fix": …}` line to send before `reply`; nil when the turn earned no button.
    func closingLine(_ reply: ArisAgentReply, on stream: AnyObject) -> Data? {
        guard reply.isLast else { return nil }
        let dropped = ArisFixDrop.read(ArisFixDrop.file(home: FileManager.default.homeDirectoryForCurrentUser.path))
        return closing(reply, on: stream, dropped: dropped, another: Self.another)?.line
    }

    /// A routine stopped on one of the agent's own failure lines: its last line is the routine's account, no longer
    /// the line itself, so the button that line earns is noted for the turn (ArisRoutineTurn). Under an account that
    /// is an answer only a fix for something that stays wrong is shown, as under any answer (`closing`).
    func note(forFailureLine line: String) {
        if let fix = ArisBrainFix.fix(forLine: line, another: Self.another) { note(fix) }
    }
}
