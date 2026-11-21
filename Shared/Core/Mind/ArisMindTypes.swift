//
//  ArisMindTypes.swift
//  Shared/Core (aris-agent, tests)
//
//  The words of the Mind (ARCHITECTURE Part 2): a model provider only thinks. It gets the conversation, the tools'
//  schemas and a short system text, and streams back text, tool calls and an end. It has no tools of its own: every
//  call it makes is an Aris capability, decided, run and recorded by Aris (ArisMindStep). Arguments travel as JSON text,
//  so every value here is Sendable and the loop is tested with a scripted provider. Pure.
//

import Foundation

/// One tool call as the model made it.
struct ArisMindToolCall: Equatable, Sendable {
    /// The provider's id for the call (its result goes back under it).
    let id: String
    /// The tool's name as the model saw it (ArisCapabilityEntry.name).
    let name: String
    /// The arguments as JSON text.
    let arguments: String

    init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    /// The arguments as an object; nil when they are not a JSON object.
    var object: [String: Any]? {
        guard let data = arguments.data(using: .utf8) else { return nil }
        if arguments.trimmingCharacters(in: .whitespaces).isEmpty { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

/// One tool a provider is offered: its name, its description and its JSON Schema as text.
struct ArisMindToolSpec: Equatable, Sendable {
    let name: String
    let description: String
    let schema: String
}

/// The conversation as the Mind keeps it, whatever the provider.
enum ArisMindMessage: Equatable, Sendable {
    /// The owner's words of a turn.
    case owner(String)
    /// The model's words and the calls it made in one round.
    case assistant(text: String, calls: [ArisMindToolCall])
    /// One call's result, as the model reads it.
    case tool(id: String, name: String, text: String, isError: Bool)
}

/// Why a provider's round ended.
enum ArisMindStop: String, Equatable, Sendable {
    /// The model finished its answer.
    case endTurn
    /// The model asked for tools: their results go back in the next round.
    case toolUse
    /// The answer was cut at the provider's length limit.
    case maxTokens
}

/// What a provider streams while a round is under way.
enum ArisMindProviderEvent: Equatable, Sendable {
    case text(String)
    case toolCall(ArisMindToolCall)
}

/// How a provider's round ended.
enum ArisMindProviderEnd: Equatable, Sendable {
    case done(ArisMindStop)
    /// The provider failed (no key, no network, a quota): said to the owner as it is, never retried behind his back.
    case failed(String)
    case cancelled
}

/// `send(messages, tools) -> stream of {text delta, tool call, done}` (ARCHITECTURE Part 2, Mind). A provider is the
/// user's choice and never changes behind his back: the loop never falls back to another one.
protocol ArisMindProvider: AnyObject {
    /// One round: blocks until it ends, calling `event` as text and calls arrive (on the caller's thread or any other).
    func send(system: String, messages: [ArisMindMessage], tools: [ArisMindToolSpec], event: @escaping (ArisMindProviderEvent) -> Void) -> ArisMindProviderEnd
    /// Ends the round under way (its `send` returns `.cancelled`).
    func cancel()
}

/// What the policy said about one call, in the loop's terms (ArisDecision without the policy's detail).
enum ArisMindVerdict: Equatable, Sendable {
    /// Run it; `undo`: keep its undo in the record; `announce`: say aloud what was done (content suggested it).
    case run(undo: Bool, announce: Bool)
    /// Nothing runs until the owner answers its card (an ask, a read-back, or a countdown he can stop).
    case waits
    case refuse(String)

    init(_ decision: ArisDecision) {
        switch decision {
        case .run: self = .run(undo: false, announce: false)
        case .runWithUndo(let announce): self = .run(undo: true, announce: announce)
        case .sayThenRun, .readBackThenAsk, .ask: self = .waits
        case .refuse(let reason): self = .refuse(reason)
        }
    }
}

/// One call after the decision.
struct ArisMindDecided: Equatable, Sendable {
    let call: ArisMindToolCall
    let verdict: ArisMindVerdict
}

/// One call's result: what the model reads, whether it failed, the content's source when others' words may be in it
/// (the provenance tracker reads it), and how to take the change back.
struct ArisMindResult: Equatable, Sendable {
    var text: String
    var isError = false
    var content: ArisContentSource?
    var undo: ArisUndoRecipe?
    /// The activity log's entries this call's aris-tools run wrote (their ids): the same action, in the old 한 일 list.
    var logged: [String] = []
    /// The text came through a route that wraps what it returns in Aris's own outside-text frame (the desktop, the
    /// connected services: ArisMCPPolicy.wrapped), so the provenance tracker may leave that frame's fixed words out.
    var framed = false

    init(text: String, isError: Bool = false, content: ArisContentSource? = nil, undo: ArisUndoRecipe? = nil) {
        self.text = text
        self.isError = isError
        self.content = content
        self.undo = undo
    }
}

/// What the loop tells the app while a turn goes on.
enum ArisMindOutput: Equatable, Sendable {
    /// The next piece of the answer.
    case delta(String)
    /// Something Aris did that content suggested, said aloud (the table's runWithUndoSaid).
    case said(String)
    /// What it is doing, for the notch.
    case status(String)
}

/// How a turn ended.
enum ArisMindEnd: Equatable, Sendable {
    case answered(String)
    case failed(String)
    /// A newer turn took over: nothing of this one was written after that.
    case stale
    /// A budget ran out (rounds, silence, the ceiling).
    case stopped(String)
}
