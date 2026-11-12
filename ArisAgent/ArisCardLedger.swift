//
//  ArisCardLedger.swift
//  aris-agent
//
//  One line in the audit ledger for one card's answer, keyed by the card's id (QA BUG-60: a job's Aside card answered
//  with one click was written twice, a second apart: once as the app's "app card" line, once as the agent's own when it
//  took the answer). A card the agent's own gate answers gets the agent's line only; an app-handled card gets one "app
//  card" line, and the same id told again within a few seconds is the same answer. Pure.
//

import Foundation

struct ArisCardLedger: Equatable {
    /// How many ids are remembered (the newest).
    static let kept = 200
    /// The same app card id told again within this long is the same answer; later it is the card shown anew (an undo
    /// card keeps its entry's id).
    static let sameAnswer: TimeInterval = 5

    /// The cards the agent's own gates took an answer for (POST /confirm), newest last.
    private(set) var agentCards: [String] = []
    /// The app-handled cards written, with when.
    private(set) var appCards: [String: Date] = [:]

    /// The agent took an answer for `id` itself: its gate writes that card's line.
    func agentAnswered(_ id: String) -> ArisCardLedger {
        var next = self
        next.agentCards = Array((agentCards.filter { $0 != id } + [id]).suffix(Self.kept))
        return next
    }

    /// Whether the app's word about `id` gets an "app card" line now. `agentWaits`: the agent still waits for that id
    /// (its own card, about to be answered through POST /confirm).
    func writesAppLine(_ id: String, agentWaits: Bool, at now: Date) -> Bool {
        guard !id.isEmpty, !agentWaits, !agentCards.contains(id) else { return false }
        if let last = appCards[id], now.timeIntervalSince(last) < Self.sameAnswer { return false }
        return true
    }

    /// The ledger once the "app card" line for `id` was written.
    func appWrote(_ id: String, at now: Date) -> ArisCardLedger {
        var next = self
        next.appCards[id] = now
        if next.appCards.count > Self.kept, let oldest = next.appCards.min(by: { $0.value < $1.value })?.key { next.appCards[oldest] = nil }
        return next
    }
}
