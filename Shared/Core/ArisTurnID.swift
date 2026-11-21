//
//  ArisTurnID.swift
//  Aris
//
//  A turn's identity (ARCHITECTURE.md 3.1). The kernel opens turns and nothing else does; each one gets the next
//  number, so a later turn always compares greater. Work started for a turn carries its id in `ArisTurnScope`, and
//  every task it starts inherits it, so a write that arrives after the turn ended is known for what it is.
//  Foundation only: compiled into the app, the helper and the ArisCore package alike.
//

import Foundation

struct ArisTurnID: Hashable, Comparable, Sendable, CustomStringConvertible {
    let value: UInt64

    init(_ value: UInt64) { self.value = value }

    /// Before any turn was opened.
    static let zero = ArisTurnID(0)

    func next() -> ArisTurnID { ArisTurnID(value &+ 1) }

    static func < (lhs: ArisTurnID, rhs: ArisTurnID) -> Bool { lhs.value < rhs.value }

    var description: String { "turn \(value)" }
}

/// The turn the running code works for. Set by the kernel's openers around a turn's work; nil for code that runs for
/// no turn (a key press, a click, a watcher that serves every turn).
enum ArisTurnScope {
    @TaskLocal static var current: ArisTurnID?

    /// `body` runs for `turn`, and so does every task it starts.
    static func within<T>(_ turn: ArisTurnID?, _ body: () throws -> T) rethrows -> T {
        try $current.withValue(turn, operation: body)
    }

    /// `body` runs for `turn` across its awaits.
    nonisolated(nonsending) static func within<T>(_ turn: ArisTurnID?, _ body: nonisolated(nonsending) () async throws -> T) async rethrows -> T {
        try await $current.withValue(turn, operation: body)
    }

    /// `body` runs for no turn: for work that outlives the turn it was started from (a background job, the wake
    /// detector), which must not carry that turn's id into later turns.
    static func outside<T>(_ body: () throws -> T) rethrows -> T {
        try $current.withValue(nil, operation: body)
    }
}
