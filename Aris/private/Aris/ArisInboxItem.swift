//
//  ArisInboxItem.swift
//  Aris
//
//  What scheduled work left for the user in aris-agent's inbox (POST /inbox): a result to say, a failure, a note, or a
//  question a run parked until he is at the Mac. The app is sandboxed, so it only sees these through the agent.
//

import Foundation

struct ArisInboxItem: Decodable, Equatable, Identifiable {
    /// A parked question: the confirm card's fields (`id` is what POST /confirm takes).
    struct Question: Decodable, Equatable {
        let id: String
        let title: String
        let detail: String
        let full: String?
    }

    let id: String
    let date: Date
    /// "result", "failure", "confirm" or "note".
    let kind: String
    let title: String
    let text: String
    let file: String?
    let confirm: Question?

    /// The card to ask with, for a parked question.
    var confirmation: ArisConfirmation? {
        guard kind == "confirm", let confirm else { return nil }
        return ArisConfirmation(id: confirm.id, title: confirm.title, detail: confirm.detail, full: confirm.full)
    }

    /// What Aris says: a result or note as it is; a failure in a sentence of its own.
    var spoken: String {
        guard kind == "failure" else { return text }
        return ArisSpeech.language(of: title) == "ko-KR" ? "예약한 일 ‘\(title)’, 못 끝냈어요." : "A scheduled job didn't finish: \(title)."
    }

    /// The body of POST /inbox's answer; nil when it isn't one.
    static func decode(_ data: Data) -> [ArisInboxItem]? {
        struct Body: Decodable { let items: [ArisInboxItem] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(Body.self, from: data))?.items
    }
}
