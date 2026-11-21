//
//  ArisRouterModels+Chat.swift
//  Aris
//
//  What a decision model can't do (jv-decision). Jev and the other decision models only pick an option and say how
//  sure they are, so two things the quick model is also used for need a model that writes: the repair of heard words
//  (ArisController+Hear) and the field and value of a spoken change to a card (ArisController+CardIntent). Those go to
//  the chat profile chosen for the quick understanding when one is, else to the cheapest connected one; with none
//  connected they stay off (aris-agent answers "none", said once in the log). Pure (tested).
//

import Foundation

extension ArisRouterModels {
    /// The chat profile asked for what only a chat model can do.
    enum ChatPick: Equatable, Sendable {
        /// The API profile chosen in Settings.
        case profile(String)
        /// aris-agent takes the cheapest connected one.
        case cheapest
    }

    static func chat(_ choice: Choice) -> ChatPick {
        if case .api(let id) = choice { return .profile(id) }
        return .cheapest
    }

    /// `body` as aris-agent's route op takes it for that pick ("id", or "auto").
    static func routeBody(_ pick: ChatPick, _ body: [String: Any]) -> [String: Any] {
        switch pick {
        case .profile(let id): return body.merging(["id": id]) { $1 }
        case .cheapest: return body.merging(["auto": true]) { $1 }
        }
    }
}

extension ArisRouterModels.Route {
    /// Whether who is asked can write a value (a chat profile); a decision model and the rules only pick.
    var writes: Bool {
        if case .api = self { return true }
        return false
    }

    /// Who was asked, for the log.
    var logName: String {
        switch self {
        case .rules: return "rules"
        case .jev: return "jev"
        case .api: return "api"
        case .decision(let id): return id
        }
    }
}
