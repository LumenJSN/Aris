//
//  ArisMindClickReads.swift
//  aris-agent
//
//  What a turn's reads of each app showed, kept in the helper where a call is decided (tenth VM run, item 8). The app
//  layer runs in the brain's own process (the Mind's child, the face's server); its results come back here on
//  POST /mind-call's `done`, and an app.read's elements are kept from there for the turn (ArisApps.Grounding). A click
//  whose target isn't one of them, by its id or its exact name, is refused before the gate's card could go up
//  (ArisMindRoute+Live's `refusesFirst`), with what the model is to do: read, then name the element exactly. Only a
//  read that worked, of this conversation, in this turn counts; anything else (no read, another app, an earlier turn,
//  text that only looks like a read) refuses. This only ever refuses: what it lets through is decided by the trust gate
//  as before. A taught procedure's replay doesn't come this way (its steps carry their own exact names).
//

import Foundation

final class ArisMindClickReads: @unchecked Sendable {
    static let shared = ArisMindClickReads()

    /// The capabilities whose target must be an element that was read.
    static let grounded: Set<String> = ["app.click"]
    /// The capability whose result is a read.
    static let reading = "app.read"
    /// The most elements kept for one app in a turn, and the most conversations kept.
    static let mostElements = 8_000
    static let mostSessions = 32

    /// The app a call's words name, as a read's result names it (the app layer's own name for it).
    var appName: (String) -> String = { said in ArisAppsBook.hands().ranked(said).first?.name ?? said }

    private struct Turn {
        var intent: String
        var apps: [String: [ArisApps.Grounding.Seen]] = [:]
    }

    private let lock = NSLock()
    private var turns: [String: Turn] = [:]

    private static func key(_ app: String) -> String { app.precomposedStringWithCanonicalMapping.lowercased() }

    /// A call of `session` ran in turn `intent`: a read that worked adds what it showed to the turn's (a page after a
    /// page of the same window adds up).
    func note(session: String, intent: String, capability: String, result: String, isError: Bool) {
        guard capability == Self.reading, !isError, let read = ArisApps.Grounding.read(result) else { return }
        lock.withLock {
            if turns[session]?.intent != intent {
                if turns.count >= Self.mostSessions { turns.removeAll() }
                turns[session] = Turn(intent: intent)
            }
            let app = Self.key(read.app)
            var seen = turns[session]?.apps[app] ?? []
            // The newest read of an id is the one kept.
            let fresh = Set(read.elements.map(\.id))
            seen.removeAll { fresh.contains($0.id) }
            seen.append(contentsOf: read.elements)
            turns[session]?.apps[app] = Array(seen.suffix(Self.mostElements))
        }
    }

    /// Why this call isn't run (before any card); nil for a call this doesn't hold, and for a click of something read.
    func refusal(session: String, intent: String, capability: String, arguments: [String: Any]) -> String? {
        guard Self.grounded.contains(capability) else { return nil }
        let said = (arguments["app"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let target = arguments["target"] as? String ?? ""
        let named = said.isEmpty ? said : appName(said)
        let seen = lock.withLock { () -> [ArisApps.Grounding.Seen]? in
            guard let turn = turns[session], turn.intent == intent else { return nil }
            return turn.apps[Self.key(named)] ?? turn.apps[Self.key(said)]
        }
        return ArisApps.Grounding.check(target: target, app: named.isEmpty ? "the app" : named, seen: seen)
    }

    /// What the conversation's reads of `app` printed in the turn they were taken in (the latest turn that read
    /// anything): for what a card calls an element and for finding a field again (ArisTrustGate.readElements). Only
    /// ever a name for something that is then read afresh or shown as a name; nil when nothing is known.
    func elements(session: String, app said: String) -> [ArisApps.Grounding.Seen]? {
        let named = said.isEmpty ? said : appName(said)
        return lock.withLock { turns[session].flatMap { $0.apps[Self.key(named)] ?? $0.apps[Self.key(said)] } }
    }

    /// The conversation is over.
    func end(session: String) { lock.withLock { _ = turns.removeValue(forKey: session) } }
}
