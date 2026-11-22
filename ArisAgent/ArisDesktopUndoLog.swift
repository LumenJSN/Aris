//
//  ArisDesktopUndoLog.swift
//  aris-agent
//
//  The undo of text the default path's desktop engine put into an app or erased there (thirteenth VM run: after a type
//  over a selection and a replace of a whole TextEdit document, "방금 거 되돌려" offered an older trash instead, since
//  nothing of the typing was in the activity log). Each typing, replace or erase that worked is kept here with its
//  recipe (ArisApps.TextUndo's mark: where the text went, what the field holds after it, and for a replace the undo
//  store's verified copy of what was there), and shows as a row of POST /activity among the log's own, by time, so a
//  bare "되돌려" takes it when it is the newest change. POST /undo of its id puts the text back the way Core 2's text
//  undo does (ArisAppsTextUndoLive: only while the field still holds exactly what the change left). The text itself is
//  never in a row; it stays in the undo store, 0600 in the helper's own folder.
//

import Foundation

enum ArisDesktopUndoLog {
    struct Entry: Codable, Equatable {
        let id: String
        let date: Date
        let app: String
        /// The row's line, as the activity log words a kind ("글 바꿈: TextEdit").
        let summary: String
        /// ArisApps.TextUndo.Mark as JSON.
        let element: String
        var undone: Bool
    }

    static let fileName = "desktop-undo.json"
    /// How many entries are kept, and for how long (an undo by words reaches back minutes; the 한 일 tab a day).
    static let kept = 50
    static let keptFor: TimeInterval = 86_400

    /// The helper's own folder, set when the helper starts (main.swift); nil: nothing is kept (the tests' engines, until
    /// a test sets its own).
    nonisolated(unsafe) static var folder: URL?
    /// Puts text back (app, mark, the erased text for a replace); a seam for the tests.
    nonisolated(unsafe) static var perform: (String, String, String) throws -> Void = { app, element, restoring in
        try ArisAppsTextUndoLive.remove(app: app, element: element, restoring: restoring)
    }

    private static var file: URL? { folder?.appendingPathComponent(fileName) }

    /// Where a replace's erased text is kept: the helper's undo store (ArisUndoStore(home:)'s folder).
    static var store: ArisUndoStore? { folder.map { ArisUndoStore(folder: $0.appendingPathComponent("undo-store")) } }

    static func load(now: Date = Date()) -> [Entry] {
        guard let file, let data = ArisPrivateFile.read(file), let entries = try? ArisPrivateFile.decoder.decode([Entry].self, from: data) else { return [] }
        return entries.filter { now.timeIntervalSince($0.date) <= keptFor }
    }

    private static func save(_ entries: [Entry]) {
        guard let file, let data = try? ArisPrivateFile.encoder.encode(Array(entries.suffix(kept))) else { return }
        try? ArisPrivateFile.write(data, to: file)
    }

    /// The row's line for a change: a replace, an erase, or text typed (the kind the app's tables name).
    static func summary(app: String, replaced: Bool, typed: Bool) -> String {
        (replaced ? (typed ? "글 바꿈: " : "글 지움: ") : "입력: ") + app
    }

    /// What the change did, in the words "되돌려" picks a kind by (ArisUndoWords.kind: "입력한 거" made, "지운 거" removed).
    static func action(_ summary: String) -> String {
        summary.hasPrefix("입력: ") ? "made" : summary.hasPrefix("글 지움: ") ? "removed" : "changed"
    }

    /// Keeps one change; its id.
    @discardableResult
    static func add(app: String, summary: String, recipe: ArisUndoRecipe, now: Date = Date()) -> String? {
        guard let file, case .textInserted(_, let element, _) = recipe else { return nil }
        let entry = Entry(id: UUID().uuidString, date: now, app: app, summary: summary, element: element, undone: false)
        ArisPrivateFile.withLock(file) { save(load(now: now) + [entry]) }
        return entry.id
    }

    /// The rows POST /activity adds: as aris-tools writes its own (the app reads both alike).
    static func rows(today: Bool, now: Date = Date()) -> [[String: Any]] {
        let since = today ? Calendar.current.startOfDay(for: now) : .distantPast
        let formatter = ISO8601DateFormatter()
        return load(now: now).filter { $0.date >= since }.map { entry in
            ["id": entry.id, "date": formatter.string(from: entry.date), "job": "대화", "worker": "aris", "summary": entry.summary,
             "undoable": !entry.undone, "undone": entry.undone, "asks": false, "action": action(entry.summary)]
        }
    }

    /// POST /activity's body with these rows among the log's, by time.
    static func merged(_ body: Data, today: Bool, now: Date = Date()) -> Data {
        let mine = rows(today: today, now: now)
        guard !mine.isEmpty, let log = (try? JSONSerialization.jsonObject(with: body)) as? [[String: Any]] else { return body }
        let formatter = ISO8601DateFormatter()
        let when = { (row: [String: Any]) in (row["date"] as? String).flatMap(formatter.date(from:)) ?? .distantPast }
        let sorted = (log + mine).enumerated().sorted { left, right in
            when(left.element) == when(right.element) ? left.offset < right.offset : when(left.element) < when(right.element)
        }.map(\.element)
        return (try? JSONSerialization.data(withJSONObject: sorted, options: [.sortedKeys])) ?? body
    }

    /// POST /undo of one of these entries: (status, body) as /undo answers; nil when the id isn't one of them (the old
    /// path's, or the record's). Only by id: a bare undo stays the log's.
    static func undo(id: String?, store: ArisUndoStore, now: Date = Date()) -> (status: Int, body: String)? {
        guard let file, let id, UUID(uuidString: id) != nil else { return nil }
        return ArisPrivateFile.withLock(file) { () -> (status: Int, body: String)? in
            var entries = load(now: now)
            guard let index = entries.firstIndex(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return nil }
            let entry = entries[index]
            guard !entry.undone else { return (500, json(["error": "that was already undone"])) }
            guard let mark = ArisApps.TextUndo.mark(entry.element) else { return (500, json(["error": "that text change isn't one Aris can take back"])) }
            var restoring = ""
            if let copy = mark.erased {
                guard let data = store.copy(copy), let text = String(data: data, encoding: .utf8) else {
                    return (500, json(["error": "the kept copy of the erased text is gone"]))
                }
                restoring = text
            }
            do { try perform(entry.app, entry.element, restoring) } catch let error as ArisUndoError {
                return (500, json(["error": error.message]))
            } catch {
                return (500, json(["error": String(describing: error)]))
            }
            entries[index].undone = true
            save(entries)
            return (200, json(["summary": entry.summary, "undid": (mark.erased != nil ? "restored\t" : "typed\t") + entry.app]))
        }
    }

    /// main.swift's POST /undo: true when it answered (off the server queue; `reply` on any queue).
    static func handle(_ object: [String: Any], reply: @escaping (String, Data) -> Void) -> Bool {
        guard object["confirmed"] as? Bool != true, let id = object["id"] as? String, let store,
              load().contains(where: { $0.id.caseInsensitiveCompare(id) == .orderedSame }) else { return false }
        DispatchQueue.global(qos: .userInitiated).async {
            let answer = undo(id: id, store: store) ?? (500, json(["error": "nothing to undo"]))
            ArisCore2Trust.writeAudit(ArisTrustGate.line(["action": "undo: text in an app", "risk": "spoken", "exit": String(answer.status)]), "app")
            reply(ArisCore2Trust.statusLine(answer.status), Data(answer.body.utf8))
        }
        return true
    }

    private static func json(_ fields: [String: String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}
