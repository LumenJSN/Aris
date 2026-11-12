//
//  ArisRouterKeyHealth.swift
//  Aris
//
//  Whether the quick commands' key (TypeSafe's Jev, ArisRouter) works, as its last answers said (second upgrade run,
//  bug 2: a made-up TypeSafe key left the sidebar at "Everything is working" while every request's router call came
//  back 401 in the log only). A key counts only after it answered once, as the thinking AI's key does: a saved key is
//  checked at once; until an answer comes it "hasn't answered yet", a 401 or 403 makes it "not accepted", and any
//  answer clears that. Network trouble says nothing about the key. Kept in Aris's preferences. Pure but the store.
//

import Foundation

enum ArisRouterKeyHealth {
    static let preferenceKey = "arisRouterKeyState"

    enum State: String, Equatable {
        /// Saved, no answer yet.
        case unchecked
        /// TypeSafe refused the key (401, 403).
        case rejected
    }

    /// What an answer of TypeSafe's says about the key: nil leaves the state as it was (no answer, or a server error).
    /// `.some(nil)`: it works.
    static func after(status: Int?) -> State?? {
        guard let status else { return .none }
        if status == 401 || status == 403 { return .some(.rejected) }
        if (200..<300).contains(status) { return .some(nil) }
        return .none
    }

    static func read(_ defaults: UserDefaults = .standard) -> State? {
        defaults.string(forKey: preferenceKey).flatMap(State.init(rawValue:))
    }

    static func write(_ state: State?, _ defaults: UserDefaults = .standard) {
        if let state { defaults.set(state.rawValue, forKey: preferenceKey) } else { defaults.removeObject(forKey: preferenceKey) }
    }

    /// Records what an answer said (an HTTP status; nil: none came).
    static func note(status: Int?, _ defaults: UserDefaults = .standard) {
        guard case .some(let state) = after(status: status) else { return }
        write(state, defaults)
    }
}

extension ArisRouterKeyHealth {
    /// The check's request: an everyday one that Jev answers with its own action (nothing is done with the answer).
    static let checkWords = "what time is it"
}
