//
//  ArisRecord.swift
//  aris-agent
//
//  The record's uses: writing a call's line (and its actions.log line), undoing (`undo(last n)` and `undo(id)`, both
//  capabilities of effect change-reversible), and the views the old features read when `arisCore2` is on: the activity
//  list ("한 일", POST /activity's rows), "why did you do that" (what a turn did), and actions.log's line.
//

import Foundation

enum ArisRecord {
    /// "되돌려" without naming one only reaches this far back (as the activity log's undo).
    static let recentWindow = ArisUndoScope.recentWindow

    /// The audit line writer (ArisAgentRunner.writeAudit in the helper; the tests collect lines).
    nonisolated(unsafe) static var audit: (String) -> Void = { _ in }

    /// Writes the entry and its actions.log line. False when the record couldn't be written.
    @discardableResult
    static func write(_ entry: ArisRecordEntry, home: String) -> Bool {
        let written = ArisRecordJournal.append(entry, home: home)
        audit(auditLine(entry))
        return written
    }

    // MARK: - Undo

    struct Undone: Equatable {
        let id: String
        let line: String
    }

    /// Undoes one entry, no questions (the caller's scope was decided by ArisUndoScope); its line, or why not. An entry is
    /// undone once; the undo is a new line naming it.
    static func perform(id: String, home: String, store: ArisUndoStore, hands: ArisUndoHands = .live, now: Date = Date()) throws -> Undone {
        let state = ArisRecordJournal.state(home: home)
        guard let entry = state.calls.first(where: { $0.id == id.lowercased() }) else { throw ArisUndoError(message: "no entry with that id") }
        guard !state.isUndone(entry, loggedUndone: loggedUndone()) else { throw ArisUndoError(message: "that was already undone") }
        guard entry.ok == true, ArisUndoScope.canUndo(entry) else { throw ArisUndoError(message: "that can't be undone") }
        guard let recipe = entry.undo else {
            // A rename, a trash or a move aris-tools kept in the activity log: taken back there, by exactly its lines.
            guard let undoLogged = hands.undoLogged else { throw ArisUndoError(message: "undoing that isn't available in this helper yet") }
            try undoLogged(entry.logged ?? [])
            let line = undoneLine(entry)
            write(.undone(entry.id, at: now, result: line), home: home)
            return Undone(id: entry.id, line: line)
        }
        let line = try ArisUndoRecipes.perform(recipe, home: home, store: store, hands: hands)
        write(.undone(entry.id, at: now, result: journalLine(line, entry: entry, recipe: recipe)), home: home)
        return Undone(id: entry.id, line: line)
    }

    /// What was taken back, from the record itself (never the model's guess): "되돌렸어요: 이름 바꾸기: rename-me.txt".
    static func undoneLine(_ entry: ArisRecordEntry) -> String { "되돌렸어요: " + ArisRecordQuery.ownerSummary(entry) }

    /// The activity log's undone entries, read where the helper runs (ArisMindUndoHooks.register); none until then.
    nonisolated(unsafe) static var loggedUndone: () -> Set<String> = { [] }

    /// The journal's own line for an undo: text typed or replaced in an app is said in the UI's language, with the
    /// lesson whose run it was part of when this helper ran it (eighth VM run, item 6); any other undo as its recipe
    /// says it. The line handed back to the caller is unchanged.
    static func journalLine(_ line: String, entry: ArisRecordEntry, recipe: ArisUndoRecipe, english: Bool = ArisSkillLanguage.english,
                            names: ArisTeachRunNames = .shared) -> String {
        guard case .textInserted(let app, _, _) = recipe else { return line }
        let said = ArisJournalWords.textUndone(app: app, restored: ArisJournalWords.replaced(recipe), lesson: unit(of: entry).flatMap(names.name(of:)), english: english)
        return said.hasSuffix(".") ? String(said.dropLast()) : said
    }

    /// What an undo may do for this caller (ArisUndoScope): which entries, and the policy's decision.
    static func plan(id: String?, count: Int?, caller: ArisUndoCaller, home: String, now: Date = Date()) -> ArisUndoScope.Verdict {
        ArisUndoScope.decide(id: id, count: count, state: ArisRecordJournal.state(home: home), caller: caller,
                             context: ArisTrustSettings.load(home: home, now: now).context(home: home, now: now), loggedUndone: loggedUndone())
    }

    /// undo(id) or undo(last n) for `caller`: done only when the plan runs (or the owner already said yes on its card);
    /// newest first, stopping at the first that can't be undone (an older change under it may depend on it).
    static func undo(id: String? = nil, last count: Int? = nil, caller: ArisUndoCaller, home: String, store: ArisUndoStore,
                     hands: ArisUndoHands = .live, now: Date = Date()) -> (undone: [Undone], failed: String?, verdict: ArisUndoScope.Verdict) {
        let verdict = plan(id: id, count: count, caller: caller, home: home, now: now)
        switch verdict.decision {
        case .refuse(let reason): return ([], reason, verdict)
        case .ask, .readBackThenAsk: return ([], "먼저 여쭤봐야 해요: " + verdict.line, verdict)
        case .run, .runWithUndo, .sayThenRun: break
        }
        var undone: [Undone] = []
        for entry in verdict.ids {
            do { undone.append(try perform(id: entry, home: home, store: store, hands: hands, now: now)) } catch {
                return (undone, error.localizedDescription, verdict)
            }
        }
        return (undone, nil, verdict)
    }

    /// The two undo capabilities as plain descriptors (jv-hands wraps each into an ArisCapabilityEntry in one line). The
    /// caller's session, task, provenance and speaker (the gate's verdict.speaker, F1) go in, so the scope is decided like
    /// every other call.
    struct Capability {
        let id: String
        let name: String
        let description: String
        let parameters: [String: Any]
        let effect: ArisEffectClass
        let run: ([String: Any], ArisUndoCaller, _ home: String) -> (text: String, isError: Bool)
    }

    static func reply(_ result: (undone: [Undone], failed: String?, verdict: ArisUndoScope.Verdict)) -> (text: String, isError: Bool) {
        let lines = result.undone.map(\.line) + (result.failed.map { ["되돌리지 못했어요: " + $0] } ?? [])
        return (lines.joined(separator: "\n"), result.undone.isEmpty)
    }

    static let capabilities: [Capability] = [
        Capability(id: "record.undo_last", name: "undo_last",
                   description: "Undo the last things Aris did (files, calendar, reminders, notes, settings, text typed, windows), newest first.",
                   parameters: ["type": "object", "properties": ["count": ["type": "integer", "description": "How many (1 to 10, default 1)"]], "required": []],
                   effect: .changeReversible,
                   run: { arguments, caller, home in
                       reply(undo(last: (arguments["count"] as? NSNumber)?.intValue ?? 1, caller: caller, home: home, store: ArisUndoStore(home: home)))
                   }),
        Capability(id: "record.undo", name: "undo_entry", description: "Undo one thing Aris did, by its record id.",
                   parameters: ["type": "object", "properties": ["id": ["type": "string", "description": "The record entry's id"]], "required": ["id"]],
                   effect: .changeReversible,
                   run: { arguments, caller, home in
                       guard let id = arguments["id"] as? String else { return ("an id is needed", true) }
                       return reply(undo(id: id, caller: caller, home: home, store: ArisUndoStore(home: home)))
                   }),
    ]

    // MARK: - Views

    /// A call in a few words for the owner: what, where to, which file.
    static func summary(_ entry: ArisRecordEntry) -> String { ArisRecordQuery.summary(entry) }

    /// The activity log's undone entries, by id (lowercased).
    static func loggedUndone(_ entries: [[String: Any]]) -> Set<String> {
        Set(entries.compactMap { $0["undone"] as? Bool == true ? ($0["id"] as? String)?.lowercased() : nil })
    }

    /// POST /activity's rows (aris-tools activity --json's shape): what ran and changed something, oldest first. A call
    /// whose aris-tools run wrote its own lines in the activity log is listed once, by those lines (their words, their
    /// undo and whether it was undone), never again here (VM run 2026-11-19, D5: a rename and an event undone through the
    /// log stayed "done" in the record's row).
    static func activityRows(_ state: ArisRecordState, since: Date = .distantPast) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        return state.calls.filter { $0.at >= since && $0.ok == true && $0.effect != .observe && ($0.logged ?? []).isEmpty }
            .sorted { $0.at < $1.at }.suffix(500).map { entry in
            var row: [String: Any] = ["id": entry.id, "date": formatter.string(from: entry.at), "job": entry.task ?? "대화", "worker": "Aris",
                                      "summary": ArisRecordQuery.ownerSummary(entry), "undoable": entry.undo != nil && !state.isUndone(entry.id),
                                      "undone": state.isUndone(entry.id), "asks": false, "record": true]
            if let undo = entry.undo { row["action"] = undo.action }
            // A taught procedure's run (its session "teach-…"): the app's "되돌려" takes the run back as one change.
            if let unit = unit(of: entry) { row["unit"] = unit }
            // Nothing of his to take back (an app opened, what is left of a run already undone): "되돌려" goes past it.
            if passesOver(entry, state) { row["passOver"] = true }
            return row
        }
    }

    /// An entry a bare "되돌려" walks past to the change before it (fifth VM run, D6: after a replay's typing was undone,
    /// the next "되돌려" stopped at "App opened: TextEdit can't be undone" and the to-do before it was never offered):
    /// opening an app (it changed nothing of his), and a step of a taught run some step of which was already undone
    /// (that undo took the run back, and said what of it stays). A change with no undo that is neither stops it, as before.
    static func passesOver(_ entry: ArisRecordEntry, _ state: ArisRecordState) -> Bool {
        // A step with an undo of its own (undone or not) is never passed over: it is listed as what it is.
        guard entry.undo == nil else { return false }
        if notAChange.contains(entry.capability ?? "") { return true }
        guard let run = unit(of: entry) else { return false }
        return state.calls.contains { unit(of: $0) == run && state.isUndone($0.id) }
    }

    /// The capabilities that open or bring forward and change nothing of the owner's.
    static let notAChange: Set<String> = ["app.open", "aris.open_app"]

    /// The run of a taught procedure an entry is a step of: its replay's session (ArisTeachRunner's "teach-<run>").
    static func unit(of entry: ArisRecordEntry) -> String? {
        guard let session = entry.session, session.hasPrefix("teach-") else { return nil }
        return session
    }

    /// What a turn did, for "왜 그렇게 했어?": each call with its decision and why, from `from` to `to`.
    static func whyLines(_ state: ArisRecordState, session: String?, from: Date, to: Date) -> [String] {
        state.calls.filter { $0.at >= ArisRecordEntry.whole(from) && $0.at <= to && (session == nil || $0.session == session) }.map { entry in
            let why = (entry.why ?? []).prefix(3).joined(separator: "; ")
            let from = entry.source.map { " (읽은 \($0.spoken)에서)" } ?? ""
            return ArisRecordEntry.cut(ArisRecordQuery.ownerSummary(entry) + " — " + (entry.decision ?? "") + from + (why.isEmpty ? "" : ": " + why), 240)
        }
    }

    /// actions.log's line for an entry (no body text, only its head's length).
    static func auditLine(_ entry: ArisRecordEntry) -> String {
        var fields: [String: Any] = ["record": entry.id, "at": ISO8601DateFormatter().string(from: entry.at)]
        switch entry.kind {
        case .call:
            fields["action"] = summary(entry)
            fields["effect"] = entry.effect?.rawValue ?? ""
            fields["provenance"] = entry.provenance?.rawValue ?? ""
            if let source = entry.source { fields["source"] = source.kind + " " + source.source }
            fields["risk"] = entry.decision ?? ""
            if let answer = entry.answer { fields["answer"] = answer }
            fields["ok"] = entry.ok ?? false
            if entry.undo != nil { fields["undo"] = true }
        case .undone:
            fields["action"] = "undo"
            fields["undid"] = entry.ref ?? ""
        }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}
