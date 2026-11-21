//
//  ArisMindBook.swift
//  aris-agent
//
//  The parts that were built apart, joined in the capability book (ARCHITECTURE Part 2, Hands): the fleet's capabilities
//  (jv-fleet: list, status, say, interrupt, answer, start, stop, each `aris-tools session …` with its own effect per call)
//  and the record's two undo capabilities (jv-trust: undo_last, undo_entry, run with the caller's session and
//  provenance). Both are sections of ArisCapabilityBook, so the MCP face and the Mind offer them like every other entry.
//  Also here: the few entries whose route asks the owner on its own card every time it acts (a session's prompt, a
//  fleet allow or stop), proven by tests. For those the trust decision still refuses what it refuses, and its "ask" is
//  that route's one card, never a second card in front of it; every other entry gets the trust gate's card.
//

import Foundation

extension ArisCapabilityBook {
    static let fleet: [ArisCapabilityEntry] = ArisFleetCapabilities.all.map { capability in
        ArisCapabilityEntry(id: capability.id, name: capability.name, description: capability.description, parameters: capability.parameters,
                            effect: capability.effect, run: .arisTools(argv: capability.argv, stdin: nil))
    }

    /// The record's undo capabilities. Run as a helper capability they reach only what an undo of Aris's own step may
    /// (its own session's entries of the last day: ArisUndoScope); the Mind runs them with the call's real caller.
    static let record: [ArisCapabilityEntry] = ArisRecord.capabilities.map { capability in
        ArisCapabilityEntry(id: capability.id, name: capability.name, description: capability.description, parameters: capability.parameters,
                            effect: { _ in capability.effect },
                            run: .helper({ arguments, context in
                                let caller = ArisUndoCaller(session: context.environment[ArisMindBook.sessionKey], provenance: .ownStep)
                                let done = capability.run(arguments, caller, context.home)
                                return ArisToolResult(text: done.text, isError: done.isError)
                            }))
    }
}

enum ArisMindBook {
    /// Where a helper capability finds the caller's session (the Mind sets it in the context's environment).
    static let sessionKey = "ARIS_MIND_SESSION"

    /// The entries whose route puts this very action on the owner's card every time it acts, whatever the arguments,
    /// the taint or a remembered yes: a prompt typed into a session (ArisSessionSend asks before every paste), a
    /// session ended (ArisFleetCalls.stop asks before the signal), a session's permission allowed (ArisFleetCalls.answer
    /// asks with the whole request before the app lets it through). Each is proven by mind-tests (mindCardProofTests:
    /// every reference, words and answer, the card always before the act and the act only after a yes). Only for these
    /// is the trust decision's ask that route's card; every other entry, a new one included, keeps the gate's own card
    /// (fail closed: an extra card at worst, never a lost one).
    static let alwaysCarded: [String: @Sendable ([String: Any]) -> Bool] = [
        "fleet.say": { _ in true },
        "fleet.stop": { _ in true },
        "fleet.answer": { ($0["decision"] as? String) == "allow" },
    ]

    /// Whether this call's own route always asks the owner on its own card before it acts.
    static func routeCardsEveryTime(_ entry: ArisCapabilityEntry, arguments: [String: Any]) -> Bool {
        alwaysCarded[entry.id]?(arguments) ?? false
    }
}

// MARK: - The adapter

/// ArisTrustGate.verdict as the registry's port (ArisTrustDeciding), for one session: what the MCP face's server uses
/// with `arisCore2` on when it decides in its own process. A call that waits for the owner comes back `.ask` with its
/// question, for the caller to put on a card (the Mind's judge, ArisMindJudge, does that through the same gate).
struct ArisTrustGateDecider: ArisTrustDeciding {
    let gate: ArisTrustGate
    let session: String
    var task: String?

    func decide(_ call: ArisTrustCall) -> ArisTrustVerdict {
        let answer = gate.verdict(session: session, call: call.id, capability: call.entry.id, effect: call.effect, arguments: call.arguments,
                                  argv: call.argv, stdin: call.stdin, payment: call.entry.payment(call.arguments))
        return Self.verdict(kind: answer.kind, text: answer.text)
    }

    static func verdict(kind: String, text: String?) -> ArisTrustVerdict {
        switch kind {
        case "run": return .run
        case "runWithUndo": return .runWithUndo
        case "ask": return .ask(text ?? "")
        default: return .refuse(text ?? ArisCapabilityGate.neverLine)
        }
    }
}

enum ArisMindTrust {
    /// The trust policy the MCP face's server asks: with `arisCore2` on, the helper's trust gate for the call's turn
    /// (ArisMindRemote: the owner's words, the cards and the record are the helper's); with it off, today's answer
    /// (ArisTodayTrust), byte for byte.
    static func decider(environment: [String: String], judge: @escaping (ArisReadCall) -> ArisReadVerdict) -> ArisTrustDeciding {
        ArisCore2.isOn() ? ArisMindRemote(environment: environment) : ArisTodayTrust(judge: judge)
    }
}
