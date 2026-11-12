//
//  ArisActionGrants.swift
//  aris-agent
//
//  One-shot grants for calendar and to-do writes (ArisActionGrant): minted in this process when its gate lets the exact
//  action run, consumed only by the Aris app itself (POST /permissions, op consumeGrant, isAppItself) when the write
//  reaches its route. A holder of the hook token can neither mint one nor read one: they live in memory only.
//  A grant minted for a write the automatic check let through (`passedByCheck` just before it) says so when it is
//  consumed: the app then marks the made to-do or event as outside text (ArisOutsideItems, security review 9, M2).
//

import Foundation

final class ArisActionGrants: @unchecked Sendable {
    static let shared = ArisActionGrants()
    /// A grant is good this long: the command runs right after its yes.
    static let lifetime: TimeInterval = 120

    private let lock = NSLock()
    private var grants: [String: [(until: Date, outside: Bool)]] = [:]
    /// Writes an automatic pass let through, by key, until their grant is minted (or `lifetime` passes).
    private var checked: [String: Date] = [:]
    /// The agent's own undo runs of a to-do's entry: each lets one to-do reopen or remove by id through (the app asked
    /// for the undo), until it is used, its run of aris-tools returns, or it is `lifetime` old.
    private var undoRuns: [(id: UUID, until: Date)] = []

    /// A grant for each calendar or to-do write in a shell command the gate let run.
    func mint(command: String, tools: String, now: Date = Date()) {
        for piece in ArisCommandPolicy.segments(command) ?? [command] {
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { continue }
            mint(argv: Array(words.dropFirst()), now: now)
        }
    }

    /// A grant for one aris-tools argv, when it is such a write.
    func mint(argv: [String], now: Date = Date()) {
        guard let key = ArisActionGrant.key(argv: argv) else { return }
        lock.withLock {
            let outside = checked.removeValue(forKey: key).map { $0 > now } ?? false
            grants[key, default: []].append((now.addingTimeInterval(Self.lifetime), outside))
        }
    }

    /// The automatic check let this write run (no card): the grant minted for it next is marked as outside text.
    func passedByCheck(argv: [String], now: Date = Date()) {
        guard let key = ArisActionGrant.key(argv: argv) else { return }
        lock.withLock {
            checked = checked.filter { $0.value > now }
            checked[key] = now.addingTimeInterval(Self.lifetime)
        }
    }

    /// The agent's /undo is about to run aris-tools for an entry whose undo reopens or removes a to-do: that one write
    /// by id may go through. The grant's name is given back, to drop it when the run returns (`dropUndo`).
    @discardableResult
    func mintUndo(now: Date = Date()) -> UUID {
        let id = UUID()
        lock.withLock { undoRuns.append((id, now.addingTimeInterval(Self.lifetime))) }
        return id
    }

    /// The undo's run of aris-tools returned: its grant, if the run didn't use it, is gone (it used to stay good for
    /// `lifetime` for any to-do reopen or removal by id: security review 3, L4).
    func dropUndo(_ id: UUID?) {
        guard let id else { return }
        lock.withLock { undoRuns = undoRuns.filter { $0.id != id } }
    }

    /// How many undo grants are still good (for the tests).
    func undoGrants(now: Date = Date()) -> Int { lock.withLock { undoRuns.filter { $0.until > now }.count } }

    /// Uses one grant for exactly `key`, while it is fresh: true once.
    func consume(_ key: String, now: Date = Date()) -> Bool { take(key, now: now).granted }

    /// The same, and whether the write was let through by the automatic check (its words may be someone else's).
    func take(_ key: String, now: Date = Date()) -> (granted: Bool, outside: Bool) {
        lock.withLock {
            if var left = grants[key]?.filter({ $0.until > now }), !left.isEmpty {
                let used = left.removeFirst()
                grants[key] = left.isEmpty ? nil : left
                return (true, used.outside)
            }
            grants[key] = nil
            undoRuns = undoRuns.filter { $0.until > now }
            if ArisActionGrant.isUndoKey(key), !undoRuns.isEmpty {
                undoRuns.removeFirst()
                return (true, false)
            }
            return (false, false)
        }
    }
}
