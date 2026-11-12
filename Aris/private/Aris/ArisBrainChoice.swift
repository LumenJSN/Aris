//
//  ArisBrainChoice.swift
//  Aris
//
//  Which AI answers when the user hasn't picked one that works here (fresh install F2: a new Mac with no Codex still
//  started on Codex, and the first question failed). aris-agent says which AIs are set up on this Mac (its tool is
//  installed, or an API brain has its key); a new install takes the first of Claude, Codex, Antigravity and the API
//  brain that is. Someone who already has a brain keeps it for as long as it can answer. Foundation only (tested);
//  ArisBrainSetup asks the agent and stores the answer.
//

import Foundation

enum ArisBrainChoice {
    /// The owner's ruling: Claude is the recommended brain; then Codex, Antigravity, and last an API brain.
    static let order: [ArisBrain] = [.claude, .codex, .antigravity, .api]
    static var recommended: ArisBrain { order[0] }

    /// The agent's answer ({"claude": true, …}) by brain; a name that is no brain is dropped.
    static func ready(_ raw: [String: Bool]) -> [ArisBrain: Bool] {
        raw.reduce(into: [:]) { result, entry in
            if let brain = ArisBrain(rawValue: entry.key) { result[brain] = entry.value }
        }
    }

    /// The first brain, in the user's order, that is set up here.
    static func firstReady(_ ready: [ArisBrain: Bool]) -> ArisBrain? { order.first { ready[$0] == true } }

    /// Who answers a request made for `chosen`: that brain, unless the agent says it isn't set up on this Mac, then
    /// the first that is. Not known yet (the agent hasn't answered) is never a reason to move off the chosen one.
    static func answering(_ chosen: ArisBrain, ready: [ArisBrain: Bool]?) -> ArisBrain {
        guard let ready, ready[chosen] == false else { return chosen }
        return firstReady(ready) ?? chosen
    }

    /// The agent answered for every brain and none can answer. Not known yet (nil, or some missing) is never "none".
    static func noneReady(_ ready: [ArisBrain: Bool]?) -> Bool {
        guard let ready else { return false }
        return order.allSatisfy { ready[$0] == false }
    }

    /// No AI can answer, and one is set up that has never answered (a key whose check failed, or that was saved while
    /// offline): the state is "needs checking", not "none", and not "working" either (final check on a new Mac: a
    /// made-up key was counted as a working AI everywhere).
    static func needsCheck(ready: [ArisBrain: Bool]?, unchecked: Set<ArisBrain>) -> Bool {
        noneReady(ready) && !unchecked.isEmpty
    }

    /// Whether the stored brain is let go after its key was removed in Settings: it was that brain, and it can no
    /// longer answer nor is waiting for a check. Only on that act of his own; a look that reads "not set up" never
    /// does this (`resolve`).
    static func forgetsAfterKeyRemoved(stored: String?, ready: [ArisBrain: Bool]?, unchecked: Set<ArisBrain>) -> Bool {
        stored == ArisBrain.api.rawValue && ready?[.api] == false && !unchecked.contains(.api)
    }

    /// The brain to store now; nil leaves what is stored. `stored`: the user's own brain (nil on a new install that
    /// hasn't picked). A brain the user has is never replaced: reading "not set up" can be one slow look for its tool,
    /// and storing another AI then would send every later request to a different company for good, with only a log line
    /// (security review M5). A request made while it can't answer says so, with the way to Settings › AI 서비스.
    static func resolve(stored: String?, ready: [ArisBrain: Bool]) -> ArisBrain? {
        if let stored, ArisBrain(rawValue: stored) != nil { return nil }
        return firstReady(ready)
    }

    /// The user has no brain of their own and the agent says none is set up: whatever the preference reads is only the
    /// key's default (Codex), which nobody chose (VM run 2026-11-10, bug 7: a new Mac with no AI showed Codex as chosen
    /// and its first failure blamed GPT). Nothing is stored or changed here; only what is shown and said.
    static func nobodyChose(stored: String?, ready: [ArisBrain: Bool]?) -> Bool {
        stored.flatMap(ArisBrain.init(rawValue:)) == nil && noneReady(ready)
    }

    /// The brain the settings show as chosen: `value` (the preference), or "" (none) when it is only the default.
    static func shown(_ value: String, stored: String?, ready: [ArisBrain: Bool]?) -> String {
        nobodyChose(stored: stored, ready: ready) ? "" : value
    }

    /// The line a failed turn shows. The agent's "<AI> isn't set up on this Mac" names the AI it was asked for; when
    /// that AI is only the default, the line says what is true for the user instead: no AI is ready here (with the same
    /// way to Settings › AI 서비스). A brain the user stored keeps its own line, as does every other failure.
    static func failureLine(_ line: String, stored: String?, ready: [ArisBrain: Bool]?) -> String {
        guard nobodyChose(stored: stored, ready: ready), let trouble = ArisBrainTrouble.named(in: line), trouble.brain != nil else { return line }
        return ArisBrainTrouble(brain: nil, missing: .any).line(korean: line == trouble.line(korean: true))
    }
}

/// The guide's AI page as data: one row per brain, in the user's order.
enum ArisOnboardingBrainRows {
    enum State: Equatable {
        /// Set up here, and the one that answers.
        case chosen
        /// Set up here.
        case ready
        /// Not set up here: the row says how to get it.
        case missing
        /// The agent hasn't answered: nothing is claimed either way.
        case unknown
    }

    struct Row: Equatable {
        let brain: ArisBrain
        let state: State
        let recommended: Bool
    }

    /// `chosen`: the stored brain. One that isn't set up is never shown as answering.
    static func rows(ready: [ArisBrain: Bool]?, chosen: String?) -> [Row] {
        ArisBrainChoice.order.map { brain in
            let state: State
            switch ready?[brain] {
            case true?: state = brain.rawValue == chosen ? .chosen : .ready
            case false?: state = .missing
            case nil: state = .unknown
            }
            return Row(brain: brain, state: state, recommended: brain == ArisBrainChoice.recommended)
        }
    }

    /// What the page says over the rows.
    enum Heading: Equatable { case some, none, unknown }

    static func heading(ready: [ArisBrain: Bool]?) -> Heading {
        guard let ready, !ready.isEmpty else { return .unknown }
        return ArisBrainChoice.firstReady(ready) == nil ? .none : .some
    }

    static func selectable(_ state: State) -> Bool { state == .ready || state == .chosen }

    enum KeyProblem: Equatable { case empty }

    /// A pasted API key before it is sent to the agent.
    static func keyProblem(_ key: String) -> KeyProblem? {
        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : nil
    }
}
