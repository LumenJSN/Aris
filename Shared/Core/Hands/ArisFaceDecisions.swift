//
//  ArisFaceDecisions.swift
//  Shared/Core (aris-agent, tests)
//
//  The trust gate's own yes for the MCP face's calls of one turn, by the provider's tool-use id (Claude Code sends it with
//  every tools/call as `_meta["claudecode/toolUseId"]`, the id its stream gives the same call). POST /mind-call puts
//  one here when it decided a call "run" (on its own, or on the owner's yes on its card) and the face's server named the
//  call's id; the Claude driver's web-result check (I3) takes it for exactly that call (its function and arguments) in
//  place of the old read judge's yes, which Core 2 never asks. A call with no entry, another turn's, or one whose
//  function or arguments differ, has no yes here: its web result still stops the process.
//

import Foundation

final class ArisFaceDecisions: @unchecked Sendable {
    private struct Decided: Equatable {
        let function: String
        let arguments: String
    }

    /// The most a turn keeps (a call is taken once, at its result).
    static let most = 256
    /// The longest tool-use id kept (Claude's are about 30 characters).
    static let longestID = 100

    private let lock = NSLock()
    private var turn = ""
    private var decided: [String: Decided] = [:]

    init() {}

    /// A turn starts (its credential) or ends (""): what the turn before decided is gone.
    func begin(turn credential: String) {
        lock.withLock {
            turn = credential
            decided = [:]
        }
    }

    /// The trust gate let this call run in turn `credential`; nothing is kept for any other turn than the current one,
    /// for an id that isn't one, or past `most`.
    func ran(turn credential: String, id: String, function: String, arguments: [String: Any]) {
        guard Self.wellFormed(id), !function.isEmpty, let text = Self.canonical(arguments) else { return }
        lock.withLock {
            guard !turn.isEmpty, turn == credential, decided.count < Self.most || decided[id] != nil else { return }
            decided[id] = Decided(function: function, arguments: text)
        }
    }

    /// Whether the trust gate let exactly this call run this turn (taken once).
    func take(id: String, function: String, arguments: [String: Any]) -> Bool {
        guard let text = Self.canonical(arguments) else { return false }
        return lock.withLock {
            guard let found = decided[id], found == Decided(function: function, arguments: text) else { return false }
            decided[id] = nil
            return true
        }
    }

    /// A provider's tool-use id: letters, digits, `_` and `-`, at most `longestID`.
    static func wellFormed(_ id: String) -> Bool {
        !id.isEmpty && id.count <= longestID && id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" }
    }

    /// The arguments as compact JSON with sorted keys (the same object read from the stream and from the call).
    static func canonical(_ arguments: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
