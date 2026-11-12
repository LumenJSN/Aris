//
//  ArisUndoSteps.swift
//  Aris
//
//  How a typed or spoken "undo that" / "방금 거 취소해" reaches aris-agent, in the order the 한 일 tab's and the receipt's
//  Undo already use: the helper is asked first without `confirmed`. An ordinary change (a to-do, the volume, the timer,
//  a file moved or trashed) is undone by that request. One that deletes an event Aris made or brings a removed
//  schedule back is answered with a 409 that says what the card must show; only then, after the user's yes on that card,
//  does a request go with `confirmed` and the 409's own summary. A `confirmed` the helper never asked for is refused
//  by it (ArisPendingUndos), and nothing here sends one. (Third VM run, bug B: the typed path showed its own card and
//  sent `confirmed` straight away, so every typed undo was refused.) Foundation only, so the tests run the whole
//  exchange against the helper's rule.
//

import Foundation

enum ArisUndoSteps {
    /// Whose card comes first for the entry picked.
    enum Start: Equatable {
        /// Aris's own card names the entry ("To undo: …"); its yes sends the plain request.
        case ownCard
        /// The helper will ask about this one itself (an event deleted, a schedule revived): it is asked first, and
        /// its card is the one card.
        case helperAsks
    }

    /// `asks`: the activity list says the entry's undo needs a yes of its own (ArisActivityItem.asks).
    static func start(asks: Bool) -> Start { asks ? .helperAsks : .ownCard }

    /// What follows the helper's answer to the request sent without `confirmed`.
    enum Next: Equatable {
        /// Nothing more to ask: undone, failed or refused, said as it is.
        case say(ArisUndoOutcome)
        /// The helper asks: this card, and after a yes the request with `confirmed` and `echo` (the 409's summary,
        /// exactly as it came).
        case card(ArisConfirmation, echo: String)
        /// The helper asked about another entry than the one picked: nothing is confirmed.
        case otherEntry
    }

    /// `entry`: the one picked. `newest` and `doubt` as for Aris's own card (ArisUndoWords.card): with doubt the
    /// helper's card also says which one stays.
    static func next(after outcome: ArisUndoOutcome, entry: ArisUndoWords.Candidate, newest: ArisUndoWords.Candidate?, doubt: Bool,
                     korean: Bool) -> Next {
        guard case .needsConfirm(let asked, let summary, let revives) = outcome else { return .say(outcome) }
        guard !asked.isEmpty, asked.lowercased() == entry.id.lowercased() else { return .otherEntry }
        let title = ArisActivityTab.confirmation(id: asked, summary: summary, revivesSchedule: revives, english: !korean).title
        var detail = ArisUndoWords.helperDetail(summary, korean: korean)
        if doubt, let newest { detail += "\n" + ArisUndoWords.staysLine(newest, korean: korean) }
        return .card(ArisConfirmation(id: "undo-" + asked, title: title, detail: detail), echo: summary)
    }

    /// The body of POST /undo, before the app adds who it is (its pid and start time). `confirmed` goes only with the
    /// entry's id and the summary the helper's 409 carried: without either it is sent as a plain request.
    static func request(id: String?, confirmed: Bool, echo: String?) -> [String: Any] {
        let yes = confirmed && id != nil && echo != nil
        var body: [String: Any] = ["confirmed": yes]
        if let id { body["id"] = id }
        if yes, let echo { body["summary"] = echo }
        return body
    }

    /// What the helper's answer to POST /undo means: 200 undone, 409 it asks first (with the entry and the summary the
    /// card must show), 403 refused, anything else failed with its reason.
    static func outcome(status: Int, reply: [String: Any]) -> ArisUndoOutcome {
        switch status {
        case 200: return .done(reply["summary"] as? String ?? "")
        case 409: return .needsConfirm(id: reply["id"] as? String ?? "", summary: reply["summary"] as? String ?? "",
                                       revivesSchedule: reply["kind"] as? String == "restoreSchedule")
        case 403: return .refused
        default: return .failed(reply["error"] as? String ?? "couldn't undo")
        }
    }

    /// The folder macOS may be asking about is looked up only once the undo has waited this long (ArisUndoWords.hintAfter):
    /// a quick undo sends no second request. (Bug B's ledger: each refused undo left an "undo-folder … refused (doesn't
    /// hold this connection)" line, from a look-up dropped the moment the undo came back.)
    static func asksFolder(waited: TimeInterval) -> Bool { waited >= ArisUndoWords.hintAfter }
}
