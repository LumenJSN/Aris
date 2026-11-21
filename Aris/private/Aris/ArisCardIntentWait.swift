//
//  ArisCardIntentWait.swift
//  Aris
//
//  The app's side of a card reply's second layer (ArisCardIntent, Shared/Core): which cards ask the fast model at all,
//  what of a card goes along, when the words heard are asked about, and the request as TypeSafe's Jev takes it. Pure
//  (tested); ArisCardJudge runs it, ArisController.cardWait listens.
//

import Foundation

extension ArisCardIntent {
    /// No fast model is connected: nothing is asked, and the card is read by the word rules alone, as before.
    struct NoModel: Error {}

    /// Cards whose spoken reply the model may read: where a spoken yes may count, and never the dictated message's
    /// countdown, "앞으로 이건 그냥 할까?" (a standing yes keeps its own stricter rules, ArisAskAnswer) or a card the
    /// automatic check stopped.
    static func usesModel(_ ask: ArisConfirmation, voiceYes: Bool) -> Bool {
        voiceYes && !ask.countdown && !ask.proposal && !ask.stopped
    }

    /// What sort of card it is, from what the agent's code set on it (never from its text).
    static func kind(_ ask: ArisConfirmation) -> String {
        if ask.fleetGrant != nil { return "let a coding session go on" }
        if ask.desktop != nil { return "use an app's window" }
        let roles = Set(ask.fields.map(\.role))
        if roles.contains(.recipient) { return "send a message" }
        if roles.contains(.time) { return "save something with a time" }
        if roles.contains(.text) { return "write something" }
        return "do one action"
    }

    /// The card as the model gets it. `ownerContent`: what the card says came from the owner's own request, with no
    /// outside text read in its turn; without it only the kind and the field names (the agent's code's) go.
    static func card(_ ask: ArisConfirmation, ownerContent: Bool) -> Card {
        Card.make(kind: kind(ask), title: ask.title, fields: ask.fields.filter { !$0.fixed }.map(\.label), ownerContent: ownerContent)
    }

    /// The question to Jev, at the router's own endpoint and model.
    static func jevRequest(_ question: Question, key: String) -> URLRequest {
        var request = URLRequest(url: ArisRouter.endpoint, timeoutInterval: timeoutSeconds)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: question.jev.merging(["model": ArisRouter.model]) { $1 })
        return request
    }

    /// The same question for an API profile, as aris-agent's route op takes it (ArisAPIRouterCall).
    static func routeBody(_ question: Question, profile: String?) -> [String: Any] {
        let body: [String: Any] = ["op": "route", "system": question.system, "user": question.user, "schema": question.schema, "timeout": timeoutSeconds]
        return body.merging(profile.map { ["id": $0] } ?? ["auto": true]) { $1 }
    }
}

/// When a listening card asks the model about the words it heard. Words are asked about once, after they held still,
/// one request at a time and a few per card; a reading counts only for words that still stand as they were asked.
struct ArisCardIntentWait: Equatable {
    /// Requests per card: someone talking on is not classified sentence after sentence.
    static let maxAsks = 3
    /// How long past its listening window a card stays open for words that are settling or being read.
    static let grace: Double = 2.5
    /// A request this young shows no "one moment" yet (an answer that comes at once changes nothing on the card).
    static let quietFor: Double = 0.25

    private(set) var asked: [String] = []
    private(set) var pending: String?
    private(set) var askedAt: Double?
    private(set) var heldSince: Double?
    /// No model answered that it exists: nothing more is asked for this card.
    private(set) var off = false

    /// The words to ask about now, if any.
    func next(_ heard: ArisCardListening, at now: Double) -> String? {
        guard !off, pending == nil, asked.count < Self.maxAsks, heard.heldStill(at: now) else { return nil }
        let words = heard.rest
        return !asked.contains(words) && ArisCardIntent.asksModel(words) ? words : nil
    }

    func asking(_ words: String, at now: Double) -> ArisCardIntentWait {
        var next = self
        next.asked = asked + [words]
        next.pending = words
        next.askedAt = now
        return next
    }

    /// The request ended. Its reading counts only when the words heard are still exactly the ones asked about.
    func answered(_ reading: ArisCardIntent.Reading, heard: ArisCardListening) -> (wait: ArisCardIntentWait, reading: ArisCardIntent.Reading?) {
        var next = self
        next.pending = nil
        next.askedAt = nil
        return (next, heard.rest == pending ? reading : nil)
    }

    /// No model: this card asks nothing more.
    func switchedOff() -> ArisCardIntentWait {
        var next = self
        next.pending = nil
        next.askedAt = nil
        next.off = true
        return next
    }

    /// Whether the card says "one moment": a request has been out for `quietFor`.
    func showsThinking(at now: Double) -> Bool { askedAt.map { now - $0 >= Self.quietFor } ?? false }

    /// What the card's hearing note changes to between readings, nil to leave it: "one moment" once a request has been
    /// out a while, and back to listening when that request is gone (answered for other words, or no model).
    static func note(thinking: Bool, shown: ArisCardHearing?) -> ArisCardHearing? {
        if thinking { return shown == .thinking ? nil : .thinking }
        return shown == .thinking ? .listening : nil
    }

    /// Near the end of the listening window (`remaining` seconds): whether the microphone stays open a little longer,
    /// for a request that is out or words that are about to be asked about; never more than `grace` in a row.
    func keeping(_ heard: ArisCardListening, at now: Double, remaining: Double) -> (wait: ArisCardIntentWait, keeps: Bool) {
        var next = self
        let wanted = !off && (pending != nil || (asked.count < Self.maxAsks && !asked.contains(heard.rest) && ArisCardIntent.asksModel(heard.rest)))
        guard remaining < 0.3, wanted else {
            if remaining >= 0.3 { next.heldSince = nil }
            return (next, false)
        }
        next.heldSince = heldSince ?? now
        return (next, now - (next.heldSince ?? now) < Self.grace)
    }
}
