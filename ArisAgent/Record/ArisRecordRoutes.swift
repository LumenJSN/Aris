//
//  ArisRecordRoutes.swift
//  aris-agent
//
//  The existing undo features reading from the record when `arisCore2` is on (with it off none of this is reached):
//  POST /activity lists the record's changes after the activity log's (each row marked "record"), POST /undo undoes a
//  record entry by its id, or, with no id, the latest change when the record's is newer than the log's (ArisController+
//  Undo's "되돌려" and the activity list's Undo button both go through it), and POST /undo-folder names the protected
//  folder a record entry's undo touches. "Why did you do that" adds the record's lines for the turn (ArisWhyDesk).
//

import Foundation

enum ArisRecordRoutes {
    /// The activity log's rows (aris-tools' JSON) and the record's, oldest first.
    static func activity(logBody: Data, today: Bool, home: String, now: Date = Date()) -> Data {
        let since = today ? Calendar.current.startOfDay(for: now) : .distantPast
        let log = (try? JSONSerialization.jsonObject(with: logBody)) as? [[String: Any]] ?? []
        let rows = log + ArisRecord.activityRows(ArisRecordJournal.state(home: home), since: since)
        let formatter = ISO8601DateFormatter()
        let sorted = rows.enumerated().sorted { left, right in
            let a = (left.element["date"] as? String).flatMap(formatter.date(from:)) ?? .distantPast
            let b = (right.element["date"] as? String).flatMap(formatter.date(from:)) ?? .distantPast
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
        return (try? JSONSerialization.data(withJSONObject: Array(sorted.suffix(500)), options: [.sortedKeys])) ?? Data("[]".utf8)
    }

    /// An undo the record answers: (status, body) as /undo replies; nil when it is the activity log's (the old path).
    /// `logLatest`: when the log's latest change not undone was made (nil: none in the last day).
    /// `dryRun`: only whether the record would answer (nothing is undone).
    /// `unit`: the entry is a step of a taught procedure's run, and every step of that run with an undo is taken back,
    /// newest first (third VM run, D3).
    static func undo(id: String?, unit: Bool = false, home: String, logLatest: Date?, store: ArisUndoStore? = nil, hands: ArisUndoHands = .live,
                     now: Date = Date(), dryRun: Bool = false) -> (status: Int, body: String)? {
        let state = ArisRecordJournal.state(home: home)
        let store = store ?? ArisUndoStore(home: home)
        let chosen: ArisRecordEntry
        if let id {
            guard let entry = state.calls.first(where: { $0.id == id.lowercased() }) else { return nil }
            chosen = entry
        } else {
            // A call whose aris-tools run wrote its own lines in the activity log is undone there, by those lines (the
            // same action: one "되돌려" never takes it back twice, and the log then says it was undone).
            let recent = state.calls.filter { $0.ok == true && $0.effect != .observe && !state.isUndone($0.id) && ($0.logged ?? []).isEmpty
                && $0.at >= now.addingTimeInterval(-ArisRecord.recentWindow) && !ArisRecord.passesOver($0, state) }
            guard let latest = recent.max(by: { $0.at < $1.at }), logLatest.map({ latest.at >= $0 }) ?? true else { return nil }
            chosen = latest
        }
        if dryRun { return (200, "") }
        // The app's own Undo (a row the owner pressed, or "되돌려" said to Aris): the owner's own request on what he saw.
        let caller = ArisUndoCaller(session: nil, provenance: .ownerSaid, approved: true)
        if unit, let run = ArisRecord.unit(of: chosen) {
            let steps = state.calls.filter { ArisRecord.unit(of: $0) == run && $0.ok == true && $0.undo != nil && !state.isUndone($0.id) }
                .sorted { $0.at > $1.at }
            var lines: [String] = []
            var undid: [String] = []
            for step in steps {
                let result = ArisRecord.undo(id: step.id, caller: caller, home: home, store: store, hands: hands, now: now)
                if let done = result.undone.first, result.failed == nil {
                    lines.append(done.line)
                    if let code = step.undo.flatMap(undidCode) { undid.append(code) }
                    continue
                }
                let said = lines.isEmpty ? "" : " (" + lines.joined(separator: ", ") + ")"
                return (500, json(["error": "couldn't undo \"\(ArisRecordQuery.ownerSummary(step))\": \(result.failed ?? "")" + said]))
            }
            guard !lines.isEmpty else { return (500, json(["error": "can't be undone"])) }
            var reply = ["summary": steps.map(ArisRecordQuery.ownerSummary).joined(separator: ", ") + " — " + lines.joined(separator: ", ")]
            // What the run did that no undo takes back stays, and is said (fourth VM run, D7: after a replay that made a
            // new document, "되돌려" refused everything; now the typing goes and the document stays, and Aris says so).
            if let kept = kept(state.calls.filter { ArisRecord.unit(of: $0) == run }) { reply["kept"] = kept }
            // What was undone, for the reply to name it (seventh VM run, item 5: "Undid “TextEdit” (Typed into an app).").
            if !undid.isEmpty { reply["undid"] = undid.joined(separator: "\n") }
            if let lesson = ArisTeachRunNames.shared.name(of: run) { reply["lesson"] = lesson }
            return (200, json(reply))
        }
        let result = ArisRecord.undo(id: chosen.id, caller: caller, home: home, store: store, hands: hands, now: now)
        if let done = result.undone.first, result.failed == nil {
            var reply = ["summary": ArisRecordQuery.ownerSummary(chosen) + " — " + done.line]
            if let code = chosen.undo.flatMap(undidCode) { reply["undid"] = code }
            return (200, json(reply))
        }
        return (500, json(["error": "couldn't undo \"\(ArisRecordQuery.ownerSummary(chosen))\": \(result.failed ?? "")"]))
    }

    /// What of a run's steps stays after its undo: "window" when a step opened a new document or window (app.do's File ›
    /// New), "other" when another step changed something no undo takes back; nil when nothing stays. A step that
    /// changed nothing lasting (`changesNothing`) isn't counted; any other step that ran and has no undo stays, a kind
    /// not known here included (seventh VM run, item 4: Edit › Select All made "the other steps stay as they are").
    static func kept(_ steps: [ArisRecordEntry]) -> String? {
        let stays = steps.filter { $0.ok == true && $0.undo == nil && !changesNothing($0) }
        guard !stays.isEmpty else { return nil }
        return stays.contains { ($0.result ?? "").contains("a new window") } ? "window" : "other"
    }

    /// A step that changed nothing that remains, by the effect class the gate gave it and an allowlist: a look (observe);
    /// opening or bringing an app forward; a menu command that only selects (Edit › Select All). Anything else, and a
    /// step with no effect class, stays.
    static func changesNothing(_ entry: ArisRecordEntry) -> Bool {
        guard let effect = entry.effect else { return false }
        if effect == .observe { return true }
        guard effect == .changeReversible else { return false }
        let capability = entry.capability ?? ""
        if ArisRecord.notAChange.contains(capability) { return true }
        if capability == "app.do", let command = entry.arguments?.first(where: { $0.kind == .command })?.value {
            let item = ArisApps.Exact.parse(command).text.components(separatedBy: "›").last ?? ""
            return selectionCommands.contains(item.trimmingCharacters(in: .whitespaces).lowercased())
        }
        return false
    }

    /// Menu commands that only change the selection, by their item's name (English and Korean, as the apps name them).
    static let selectionCommands: Set<String> = ["select all", "deselect all", "select none", "모두 선택", "전체 선택", "선택 해제", "모두 선택 해제"]

    /// What an undo took back, for the app's reply: "typed\t<app>" (the text typed is gone) or "restored\t<app>" (a
    /// replace's erased text is back); nil for any other kind (the reply names it from the entry, as before).
    static func undidCode(_ recipe: ArisUndoRecipe) -> String? {
        guard case .textInserted(let app, let element, _) = recipe else { return nil }
        return (ArisApps.TextUndo.mark(element)?.erased != nil ? "restored\t" : "typed\t") + app
    }

    /// When the activity log's latest change from the last day that isn't undone was made.
    static func logLatest(file: URL = ArisActivityBridge.defaultLog, now: Date = Date()) -> Date? {
        guard let data = ArisPrivateFile.read(file) else { return nil }
        let formatter = ISO8601DateFormatter()
        return data.split(separator: 0x0A).compactMap { line -> Date? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any], object["undone"] as? Bool != true,
                  let date = (object["date"] as? String).flatMap(formatter.date(from:)), date >= now.addingTimeInterval(-ArisRecord.recentWindow) else { return nil }
            return date
        }.max()
    }

    /// The protected folder (Desktop, Documents, Downloads) a record entry's undo touches; nil when it isn't one.
    static func folder(ofEntry id: String?, home: String) -> String? {
        let state = ArisRecordJournal.state(home: home)
        let entry: ArisRecordEntry?
        if let id { entry = state.calls.first { $0.id == id.lowercased() } } else { entry = state.undoable.first }
        guard let paths = entry?.undo?.paths else { return nil }
        return ArisFolderAccess.folder(ofUndo: ["paths": paths], home: home)
    }

    /// What the record says a turn did, for "왜 그렇게 했어?".
    static func why(session: String?, from: Date, to: Date, home: String) -> [String] {
        guard ArisTrustSwitch.isOn() else { return [] }
        return ArisRecord.whyLines(ArisRecordJournal.state(home: home), session: session, from: from, to: to)
    }

    private static func json(_ fields: [String: String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: fields.mapValues { String($0.prefix(300)) }, options: [.sortedKeys])) ?? Data("{}".utf8),
               as: UTF8.self)
    }
}
