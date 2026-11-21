//
//  ArisController+Stats.swift
//  Aris
//
//  Each turn's numbers (ArisTurnStats) go to aris-agent's turns.jsonl when the turn ends, however it ends.
//

import Foundation

extension ArisController {
    /// The words are final and Aris picked a way to answer.
    func understood(_ text: String, path: String, tier: ArisTier) {
        stats?.heard(text, path: path, tier: tier.rawValue, at: .now)
        turnHeard = true
        ArisReceiptModel.shared.turnBegan()
        // Only a turn that goes to the AI can send the screen, and only when its words point at it (ArisScreenNeed):
        // the capture starts here, now that the words are final. Any other path (a local intent, a task) holds nothing.
        if path.hasPrefix("brain:") || path == "screen" { seeWords(text) } else { seeEnded() }
        // Answered another way than by the brain: a request sent at the plausible end goes (it did nothing yet).
        if !path.hasPrefix("brain:") { dropEarlyRequest() }
    }

    /// Sends this turn's line once; later calls for the same turn do nothing.
    func finishTurn(_ outcome: String) {
        seeEnded()
        ArisReceiptModel.shared.turnEnded()
        dropEarlyRequest()
        writeTurnLine(outcome)
    }

    /// The turn before was replaced before it ended (its task returns on cancellation without a line): only its line
    /// is written, as `replaced`; the new turn's capture, receipt and early request are left alone.
    func writeReplacedTurnLine() {
        writeTurnLine("replaced")
    }

    /// Typed turns have no listening to start the stage clock: it starts at submit, so the request, the first piece of
    /// the answer, its first sentence and its first audio are timed too (the voice-only stages stay absent).
    func startTypedTurnClock(_ turn: ArisTurnID) {
        turnHearing.begin(since: .now)
        turnHearing.turnId = turn
    }

    private func writeTurnLine(_ outcome: String) {
        guard var stats else { return }
        self.stats = nil
        // The turn's stages and how its end went (ArisStageClock), then forgotten: a typed turn after it has none.
        let hearing = turnHearing
        if let recognized = hearing.recognized { stats.recognized(apple: recognized.apple, whisper: recognized.whisper) }
        stats.hearing(stages: hearing.clock.fields(), endCase: hearing.endCase?.rawValue, speculations: hearing.turn?.requestsSent ?? 0,
                      cancelled: hearing.turn?.requestsCancelled ?? 0)
        hearing.clock = ArisStageClock()
        ArisAgentClient.log(stats.line(outcome: outcome, at: .now))
    }
}
