//
//  ArisMCPCards.swift
//  aris-agent
//
//  Every external-service card waiting for the user, whichever brain's turn put it up (a runner's own turn, or the relay
//  that runs Antigravity's calls). Only the user answers one: POST /confirm from the Aris app itself (ArisPeer), for the
//  card exactly as made (ArisShownCard), with their changes on its fields (the owner's ②A); never a standing permission, a
//  remembered yes or the judge (a countdown only for the user's own dictated message, ArisMessageGate). A card nobody answers in time, or whose turn ends, is a no.
//

import Foundation

final class ArisMCPCards {
    static let shared = ArisMCPCards()

    init() {}
    static let prefix = "mcp-"

    private struct Waiting {
        let detail: String
        let full: String?
        let fields: [ArisCardField]
        let answer: (ArisMCPAnswer) -> Void
    }

    /// Writes one line to actions.log (the agent sets it at start; the tests leave it quiet).
    nonisolated(unsafe) var audit: ([String: String]) -> Void = { _ in }
    private let lock = NSLock()
    private var waiting: [String: Waiting] = [:]
    private var count = 0

    static func owns(_ id: String) -> Bool { id.hasPrefix(prefix) }

    /// The editable card's fields as the app draws them (a field's label is its key, as the card's text says it).
    static func fields(_ fields: [ArisMCPCardField]) -> [ArisCardField] {
        fields.map { ArisCardField(key: $0.key, label: $0.key, role: $0.role == .recipient ? .recipient : .text, value: $0.value) }
    }

    /// Puts a card up: the confirmation to stream to the app. `answer` is called once: the user's yes (with their changes) or
    /// no, or a no after `timeout` or a `cancel`.
    func put(_ card: ArisMCPCard, timeout: TimeInterval, answer: @escaping (ArisMCPAnswer) -> Void) -> ArisConfirmation {
        let fields = Self.fields(card.fields)
        let id = lock.withLock { () -> String in
            count += 1
            let id = "\(Self.prefix)\(count)-\(ArisLaunch.nonce)"
            waiting[id] = Waiting(detail: card.detail, full: card.full, fields: fields, answer: answer)
            return id
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            if self?.settle(id, .unanswered) == true { self?.audit(["answer": "expired", "question": id]) }
        }
        var shown = ArisConfirmation(id: id, title: card.title, detail: card.detail, countdown: card.countdown, spoken: card.spoken, full: card.full,
                                     fields: fields, allow: card.allow, desktop: card.desktop)
        shown.stopped = card.stopped
        return shown
    }

    enum Decision: Equatable { case decided, refused, unknown }

    /// The user's answer from POST /confirm (the caller already checked it's the app itself).
    /// `unanswered`: the app closed the card at its limit with no answer from the user (a no that isn't their).
    func decide(_ id: String, allow: Bool, detail: String?, full: String?, edits: [String: String], shown: String?, unanswered: Bool = false) -> Decision {
        guard let card = lock.withLock({ waiting[id] }) else { return .unknown }
        guard ArisShownCard.matches(allow: allow, detail: detail, full: full, expectedDetail: card.detail, expectedFull: card.full,
                                    fields: card.fields, edits: allow ? edits : [:], shown: allow ? shown : nil) else { return .refused }
        audit(["answer": allow ? (edits.isEmpty ? "yes" : "yes, changed on the card") : unanswered ? "unanswered" : "no", "question": id])
        return settle(id, allow ? .yes(edits) : unanswered ? .unanswered : .no) ? .decided : .unknown
    }

    /// The turn ended: its cards are a no.
    func cancel(_ ids: Set<String>) {
        for id in ids { _ = settle(id, .no) }
    }

    func isWaiting(_ id: String) -> Bool { lock.withLock { waiting[id] != nil } }

    private func settle(_ id: String, _ answer: ArisMCPAnswer) -> Bool {
        guard let card = lock.withLock({ waiting.removeValue(forKey: id) }) else { return false }
        card.answer(answer)
        return true
    }
}
