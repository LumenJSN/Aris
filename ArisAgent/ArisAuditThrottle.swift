//
//  ArisAuditThrottle.swift
//  aris-agent
//
//  actions.log is the record of what Aris did and what was refused. A caller that is refused over and over (a
//  process with the token but not the app's identity) must not be able to fill it and push older evidence into the
//  rotated copies: an identical refusal line (same caller key, same text, told apart by a SHA-256 of both) is written
//  a few times a minute, the rest are counted, and every count is written out as a summary when its minute ends (on
//  the next write, whoever makes it, or at exit) — nothing held is ever dropped. Each caller key has its own share of
//  distinct refusals; beyond it that caller's new refusals are counted together with a notice once a minute, and no
//  caller's share hides another's. Every summary is stamped with the caller and window it belongs to, never with the
//  caller writing at that moment. Lines that aren't refusals are never held.
//

import CryptoKit
import Foundation

struct ArisAuditThrottle {
    /// Identical refusal lines written as they are, per window.
    static let allowedPerWindow = 5
    static let window: TimeInterval = 60
    /// Distinct refusal lines counted at once for one caller key (beyond this, that caller's new ones share one count).
    static let defaultKeysPerCaller = 200
    /// How much of a line is kept for its summary.
    static let sampleLength = 400
    /// Bytes of refusal lines each budget key may write per window; past it that key's refusals are counted
    /// together. Keys come from a small fixed set (the routes, the gate's own names, "task" for every task runner,
    /// "shared" for anything else: never a task or conversation id), and "shared" has a small ceiling. On top of
    /// those, one global ceiling per window over every key.
    static let bytesPerCallerWindow = 64 * 1_024
    static let sharedBytesPerWindow = 16 * 1_024
    static let globalBytesPerWindow = 256 * 1_024
    static let sharedKey = "shared"
    static let taskKey = "task"
    static let globalKey = "audit"
    static let budgetKeys: Set<String> = ["ask", "images", "confirm", "cancel", "permissions", "open", "warm", "stop", "arrange", "activity",
                                          "undo", "inbox", "todos", "brief", "look", "paste", "insert", "usage", "teammate", "teammates",
                                          "log", "gate", "settings", "app", "local", "schedule", "audit", taskKey, sharedKey]

    /// A line to write, stamped with the caller key and time it belongs to.
    struct Written: Equatable {
        let line: String
        let caller: String
        let at: Date
    }

    private struct Entry {
        let caller: String
        let start: Date
        var last: Date
        var count: Int
        let sample: String
    }

    private struct Overflow {
        let start: Date
        var last: Date
        var count: Int
    }

    let keysPerCaller: Int
    private var seen: [String: Entry] = [:]
    private var perCaller: [String: Int] = [:]
    private var overflow: [String: Overflow] = [:]
    /// Refusal bytes written in the current minute, per budget key (the global ceiling under `globalKey`), and the
    /// refusals held once a budget was spent.
    private var budget: [String: (start: Date, bytes: Int)] = [:]
    private var budgetOverflow: [String: Overflow] = [:]

    init(keysPerCaller: Int = ArisAuditThrottle.defaultKeysPerCaller) {
        self.keysPerCaller = keysPerCaller
    }

    static func isRefusal(_ line: String) -> Bool {
        line.contains(#""answer":"refused"#)
    }

    /// SHA-256 of the caller key and the whole line: lines that differ anywhere are never merged.
    static func key(for line: String, caller: String) -> String {
        SHA256.hash(data: Data((caller + "\u{0}" + line).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The lines to write for `line` from `caller` now, in order: summaries of every count whose window ended (each
    /// stamped with its own caller and window start), then the line itself, or nothing when it's held.
    mutating func admit(_ line: String, caller: String, at now: Date) -> [Written] {
        var out = flush(at: now)
        guard Self.isRefusal(line) else { return out + [Written(line: line, caller: caller, at: now)] }
        let key = Self.key(for: line, caller: caller)
        if var entry = seen[key] {
            entry.count += 1
            entry.last = now
            seen[key] = entry
            if entry.count <= Self.allowedPerWindow { emit(line, caller: caller, at: now, into: &out) }
            return out
        }
        guard perCaller[caller, default: 0] < keysPerCaller else {
            // This caller's share is full: its new refusals are counted together, announced once per window.
            if var running = overflow[caller] {
                running.count += 1
                running.last = now
                overflow[caller] = running
            } else {
                overflow[caller] = Overflow(start: now, last: now, count: 1)
                out.append(Written(line: Self.overflowNotice, caller: caller, at: now))
            }
            return out
        }
        seen[key] = Entry(caller: caller, start: now, last: now, count: 1, sample: String(line.prefix(Self.sampleLength)))
        perCaller[caller, default: 0] += 1
        emit(line, caller: caller, at: now, into: &out)
        return out
    }

    /// The budget key for a caller: a name from the fixed set, "task" for a task runner's key, else "shared".
    static func budgetKey(for caller: String) -> String {
        let trimmed = caller.trimmingCharacters(in: .whitespacesAndNewlines)
        if budgetKeys.contains(trimmed) { return trimmed }
        return trimmed.hasPrefix(taskKey) ? taskKey : sharedKey
    }

    static func bytesPerWindow(for key: String) -> Int {
        key == globalKey ? globalBytesPerWindow : key == sharedKey ? sharedBytesPerWindow : bytesPerCallerWindow
    }

    /// A refusal line that may be written now: it is, while its key's byte budget and the global ceiling for the
    /// minute both last; past either, it's counted toward that budget's summary (announced once).
    private mutating func emit(_ line: String, caller: String, at now: Date, into out: inout [Written]) {
        let key = Self.budgetKey(for: caller)
        let bytes = line.utf8.count
        guard spends(bytes, under: Self.globalKey, at: now) else { return hold(under: Self.globalKey, caller: Self.globalKey, at: now, into: &out) }
        guard spends(bytes, under: key, at: now) else { return hold(under: key, caller: caller, at: now, into: &out) }
        out.append(Written(line: line, caller: caller, at: now))
    }

    /// Charges `bytes` to `key`'s budget for the current minute when it fits (a new minute starts the budget over).
    private mutating func spends(_ bytes: Int, under key: String, at now: Date) -> Bool {
        if let running = budget[key], now.timeIntervalSince(running.start) < Self.window {
            guard running.bytes + bytes <= Self.bytesPerWindow(for: key) else { return false }
            budget[key] = (running.start, running.bytes + bytes)
        } else {
            budget[key] = (now, bytes)
        }
        return true
    }

    /// A refusal past a budget: counted toward that budget's summary, with one notice when the first is held.
    private mutating func hold(under key: String, caller: String, at now: Date, into out: inout [Written]) {
        if var held = budgetOverflow[key] {
            held.count += 1
            held.last = now
            budgetOverflow[key] = held
        } else {
            // Counted against the budget's own minute, so the summary comes out with it.
            budgetOverflow[key] = Overflow(start: budget[key]?.start ?? now, last: now, count: 1)
            out.append(Written(line: Self.budgetNotice, caller: caller, at: now))
        }
    }

    /// Summaries for every count whose window has ended (every count, with `all`, as at exit), each stamped with its
    /// own caller and window start, which are then forgotten. A count with nothing held beyond the lines already
    /// written makes no summary.
    mutating func flush(at now: Date, all: Bool = false) -> [Written] {
        var out: [Written] = []
        for (key, entry) in seen.sorted(by: { $0.value.start < $1.value.start }) where all || now.timeIntervalSince(entry.start) >= Self.window {
            let held = entry.count - Self.allowedPerWindow
            if held > 0 { out.append(Written(line: Self.summary(entry.sample, repeated: held, first: entry.start, last: entry.last), caller: entry.caller, at: entry.start)) }
            seen[key] = nil
            perCaller[entry.caller, default: 1] -= 1
            if perCaller[entry.caller] == 0 { perCaller[entry.caller] = nil }
        }
        for (caller, running) in overflow.sorted(by: { $0.value.start < $1.value.start }) where all || now.timeIntervalSince(running.start) >= Self.window {
            out.append(Written(line: Self.summary(Self.overflowNotice, repeated: running.count, first: running.start, last: running.last), caller: caller, at: running.start))
            overflow[caller] = nil
        }
        for (key, held) in budgetOverflow.sorted(by: { $0.value.start < $1.value.start }) where all || now.timeIntervalSince(held.start) >= Self.window {
            out.append(Written(line: Self.summary(Self.budgetNotice, repeated: held.count, first: held.start, last: held.last), caller: key, at: held.start))
            budgetOverflow[key] = nil
        }
        for (key, running) in budget where now.timeIntervalSince(running.start) >= Self.window { budget[key] = nil }
        return out
    }

    /// Written once per window when the minute's refusal bytes are spent; its summary carries how many were held.
    static let budgetNotice = #"{"answer":"refused (this minute's refusal budget is spent: counted together)","question":"audit"}"#

    /// Written once per window when a caller's share of distinct refusals is full; its summary carries how many came.
    static let overflowNotice = #"{"answer":"refused (too many distinct refusals: counted together)","question":"audit"}"#

    /// One JSON line: the capped sample, how many identical lines were held, and the window they fell in.
    static func summary(_ sample: String, repeated: Int, first: Date, last: Date) -> String {
        let formatter = ISO8601DateFormatter()
        let object: [String: Any] = ["answer": "refused (repeated)", "sample": sample, "repeated": repeated,
                                     "first": formatter.string(from: first), "last": formatter.string(from: last)]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}
