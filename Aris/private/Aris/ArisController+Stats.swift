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
    }

    /// Sends this turn's line once; later calls for the same turn do nothing.
    func finishTurn(_ outcome: String) {
        seeEnded()
        ArisReceiptModel.shared.turnEnded()
        guard let stats else { return }
        self.stats = nil
        ArisAgentClient.log(stats.line(outcome: outcome, at: .now))
    }
}
