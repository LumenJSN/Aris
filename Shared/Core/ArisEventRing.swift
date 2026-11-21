//
//  ArisEventRing.swift
//  Aris
//
//  The kernel's memory of what happened lately (ARCHITECTURE.md 3.1, target 8): every event it reduced, with the
//  time it came and the turn that was current then, in a ring of fixed size. A turn's stages (opened, its cards,
//  writes dropped, ended) are read back from it with their times.
//

import Foundation

struct ArisEventRing: Sendable {
    struct Entry: Equatable, Sendable {
        /// Seconds of system uptime when the event came.
        let at: Double
        /// The turn current once the event was reduced.
        let turn: ArisTurnID?
        let event: ArisEvent
        let effects: [ArisEffect]
    }

    /// One stage of a turn and when it happened.
    struct Stage: Equatable, Sendable {
        let name: String
        let at: Double
    }

    let capacity: Int
    private var storage: [Entry] = []
    private var start = 0

    init(capacity: Int) { self.capacity = max(1, capacity) }

    /// Oldest first.
    var entries: [Entry] { Array(storage[start...] + storage[..<start]) }

    mutating func append(_ entry: Entry) {
        if storage.count < capacity { return storage.append(entry) }
        storage[start] = entry
        start = (start + 1) % capacity
    }

    /// The stages of `turn` still in the ring, oldest first.
    func stages(of turn: ArisTurnID) -> [Stage] {
        entries.compactMap { entry in
            switch entry.event {
            case .turnOpened(let origin) where entry.turn == turn:
                return Stage(name: "opened:\(origin.rawValue)", at: entry.at)
            case .turnEnded(let ended, let why) where ended == turn:
                return Stage(name: "ended:\(why.rawValue)", at: entry.at)
            case .cardShown(let card, _) where entry.turn == turn:
                return Stage(name: "card:\(card)", at: entry.at)
            case .cardAnswered(let card, let allow) where entry.turn == turn:
                return Stage(name: "answered:\(card):\(allow ? "yes" : "no")", at: entry.at)
            case .sessionWrite(let from) where from == turn:
                return Stage(name: "write-dropped", at: entry.at)
            case .turnStage(let staged, let name, _) where staged == turn:
                return Stage(name: "stage:\(name)", at: entry.at)
            default:
                return nil
            }
        }
    }
}
