//
//  ArisAutoMarks.swift
//  aris-agent
//
//  The quiet "확인함" mark: which rows of the 한 일 log were let run by the automatic check (ArisAutoMode: a match). The
//  row is written by aris-tools when the action runs, a moment after the check passed, so the pass is kept here until
//  its row appears: the first row of the conversation, logged at or after the pass, whose undo is the kind that action
//  leaves (a to-do added leaves "remove that to-do"), and that no other pass took. A pass marks nothing when its
//  action failed: a Claude's is only kept once its call worked, a failed step of Codex's or the API brain's drops
//  every pass still waiting, the next turn's start drops what the turn before left, and `wait` bounds the rest. The marked rows' ids are kept in
//  ~/.config/aris/aris/auto-checked.json (ids and dates only, the last 30 days) so the mark survives a restart of the
//  helper. When the app asks for the log (POST /activity) each marked row comes with "checked": true.
//  The matching is pure and tested; only `shared` reads and writes the two files.
//

import Foundation

final class ArisAutoMarks: @unchecked Sendable {
    static let shared = ArisAutoMarks(file: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/auto-checked.json"))

    /// How long a pass waits for its row (the call runs right after its pass; a conversion may take minutes).
    static let wait: TimeInterval = 300
    /// As long as the log itself keeps a row (ArisActivity.keepDays).
    static let keep: TimeInterval = 30 * 86_400
    /// The conversation's job name in the log (ArisAgentRunner's ARIS_JOB).
    static let conversation = "대화"

    struct Pass: Equatable {
        let at: Date
        /// The undo its row carries ("removeTodo"…): every checked kind leaves one.
        let undo: String
    }

    private let file: URL?
    private let lock = NSLock()
    private var passes: [Pass] = []
    private var marked: [String: Date] = [:]
    private var loaded = false

    /// `file`: where the marked ids are kept; nil keeps them in memory only (the tests).
    init(file: URL?) { self.file = file }

    /// The undo each checked kind of call leaves in its row (ArisUndo's case name); nil for a call of no checked kind.
    static func undo(for argv: [String]) -> String? {
        if let tool = argv.first, ArisConvertWords.verbs.contains(tool) { return "trashMade" }
        if argv.starts(with: ["todo", "add"]) { return "removeTodo" }
        if argv.starts(with: ["todo", "done"]) { return "reopenTodo" }
        if argv.starts(with: ["event"]) { return "deleteEvent" }
        if argv.starts(with: ["schedule", "remove"]) { return "restoreSchedule" }
        // No checked kind leaves a row without an undo (ArisAutoScope.kinds).
        return nil
    }

    /// A match let this call run at `now`.
    func passed(_ argv: [String], at now: Date = Date()) {
        guard let undo = Self.undo(for: argv) else { return }
        lock.withLock { passes.append(Pass(at: now, undo: undo)) }
    }

    /// A step of the turn failed: no pass waits any longer (its row may never come, and the mark must not land on
    /// another's). A pass whose row is already there took it at the last read.
    func dropWaiting() { lock.withLock { passes = [] } }

    /// A new conversation turn begins: the passes of the one before take the rows the log has for them, and whatever
    /// still waits is dropped.
    func turnBegan(log rows: [[String: Any]]? = nil, now: Date = Date()) {
        let waiting = lock.withLock { !passes.isEmpty }
        guard waiting else { return }
        _ = resolve(rows ?? Self.logRows(), now: now)
        dropWaiting()
    }

    /// Which rows the passes earn, oldest pass first: for each, the earliest row of the conversation logged at or after
    /// it (the log keeps whole seconds) and within `wait`, with exactly its kind of undo, not already marked or taken.
    /// Returns the ids, and the passes still waiting.
    static func claim(_ passes: [Pass], rows: [[String: Any]], taken: Set<String>, now: Date) -> (ids: [String], left: [Pass]) {
        let formatter = ISO8601DateFormatter()
        var taken = taken, ids: [String] = [], left: [Pass] = []
        for pass in passes.sorted(by: { $0.at < $1.at }) {
            let from = Date(timeIntervalSince1970: pass.at.timeIntervalSince1970.rounded(.down))
            let found = rows.compactMap { row -> (id: String, date: Date)? in
                guard let id = (row["id"] as? String)?.lowercased(), !taken.contains(id), row["job"] as? String == conversation, row["teammate"] == nil || row["teammate"] is NSNull,
                      let date = (row["date"] as? String).flatMap(formatter.date(from:)), date >= from, date.timeIntervalSince(from) <= wait else { return nil }
                let undo = (row["undo"] as? [String: Any])?.keys.first
                return undo == pass.undo ? (id, date) : nil
            }.min { $0.date < $1.date }
            if let found {
                taken.insert(found.id)
                ids.append(found.id)
            } else if now.timeIntervalSince(pass.at) <= wait {
                left.append(pass)
            }
        }
        return (ids, left)
    }

    /// The log's rows as aris-tools printed them (`activity --json`), each marked row with "checked": true. `log`: the
    /// log file's own rows (they carry each row's undo). Anything that isn't a list of rows comes back as it is.
    func annotated(_ printed: Data, log rows: [[String: Any]], now: Date = Date()) -> Data {
        let ids = resolve(rows, now: now)
        guard !ids.isEmpty, var items = (try? JSONSerialization.jsonObject(with: printed)) as? [[String: Any]] else { return printed }
        for index in items.indices where (items[index]["id"] as? String).map({ ids.contains($0.lowercased()) }) == true { items[index]["checked"] = true }
        return (try? JSONSerialization.data(withJSONObject: items)) ?? printed
    }

    /// Every marked row's id (lowercased), after giving the waiting passes their rows.
    func resolve(_ rows: [[String: Any]], now: Date = Date()) -> Set<String> {
        lock.withLock {
            load()
            let claimed = Self.claim(passes, rows: rows, taken: Set(marked.keys), now: now)
            passes = claimed.left
            let before = marked.count
            for id in claimed.ids { marked[id] = now }
            marked = marked.filter { now.timeIntervalSince($0.value) <= Self.keep }
            if marked.count != before || !claimed.ids.isEmpty { save() }
            return Set(marked.keys)
        }
    }

    /// The log file's rows (the user's own private file, never through a link).
    static func logRows(_ file: URL = ArisActivityBridge.defaultLog) -> [[String: Any]] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return data.split(separator: 0x0A).compactMap { (try? JSONSerialization.jsonObject(with: Data($0))) as? [String: Any] }
    }

    // Called with `lock` held.
    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = ArisPrivateFile.read(file), let kept = (try? JSONSerialization.jsonObject(with: data)) as? [String: Double] else { return }
        marked = kept.mapValues(Date.init(timeIntervalSince1970:))
    }

    private func save() {
        guard let file, let data = try? JSONSerialization.data(withJSONObject: marked.mapValues(\.timeIntervalSince1970), options: [.sortedKeys]) else { return }
        try? ArisPrivateFile.write(data, to: file)
    }
}
