//
//  ArisPendingUndos.swift
//  aris-agent
//
//  The cards POST /undo gave out. An undo that deletes an event Aris made or brings a removed schedule back answers
//  409 with what the card must show; a yes (`confirmed`) then counts only for an entry that got such a card, within
//  ArisApprovalQueue.lifetime, once, and only when the app echoes exactly the summary that 409 carried
//  (ArisShownCard), not whatever the log says now. Any other yes is refused.
//

import Foundation

struct ArisPendingUndos: Equatable {
    struct Card: Equatable {
        let summary: String
        /// "deleteEvent" or "restoreSchedule".
        let kind: String
        let at: Date
    }

    /// By entry id (a UUID, upper case).
    private(set) var cards: [String: Card] = [:]

    private static func key(_ id: String?) -> String? {
        id.flatMap(UUID.init(uuidString:))?.uuidString
    }

    /// After a 409 for `id`: the card the app will show. Cards past their lifetime go.
    func issuing(id: String, summary: String, kind: String, at now: Date) -> ArisPendingUndos {
        var live = cards.filter { now.timeIntervalSince($0.value.at) <= ArisApprovalQueue.lifetime }
        if let key = Self.key(id) { live[key] = Card(summary: summary, kind: kind, at: now) }
        return ArisPendingUndos(cards: live)
    }

    /// The same, read from the 409 body exactly as it was sent (ArisActivityBridge.undoReply); a body without a valid
    /// id records nothing.
    func issuing(replyBody: String, at now: Date) -> ArisPendingUndos {
        guard let body = (try? JSONSerialization.jsonObject(with: Data(replyBody.utf8))) as? [String: Any],
              let id = body["id"] as? String, Self.key(id) != nil else { return self }
        return issuing(id: id, summary: body["summary"] as? String ?? "", kind: body["kind"] as? String ?? "", at: now)
    }

    /// A yes for `id` that echoes `summary`: allowed only for a live card showing exactly that. The card is spent
    /// either way, so a wrong echo can't be followed by guesses.
    func consuming(id: String?, summary: String?, at now: Date) -> (allowed: Bool, rest: ArisPendingUndos) {
        guard let key = Self.key(id), let card = cards[key] else { return (false, self) }
        var rest = cards
        rest[key] = nil
        let live = now.timeIntervalSince(card.at) <= ArisApprovalQueue.lifetime
        let shown = summary != nil && ArisShownCard.matches(allow: true, detail: summary, full: nil, expectedDetail: card.summary, expectedFull: nil)
        return (live && shown, ArisPendingUndos(cards: rest))
    }
}
