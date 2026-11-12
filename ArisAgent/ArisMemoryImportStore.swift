//
//  ArisMemoryImportStore.swift
//  aris-agent
//
//  Writing an import into the person memory (ArisMemoryImport), and taking it back.
//  - Each ticked line goes through the store's own merge (ArisMemoryMerge): the same thing already remembered stays
//    one memory and gets a little surer (never among the memories every turn gets by import alone); the same subject
//    in other words is replaced only when the line's own date is newer than what Aris has, whatever order things were
//    imported in; anything else is a new memory, as sure as a memory.md line (0.7), dated as the line was. A secret is
//    never written (the strict rule the store keeps for anything it didn't hear from the user).
//  - A memory from an import says where it came from (the name the user typed or picked: "imported (Claude)"); a ticked
//    instruction is a preference marked as an instruction, as sure as a spoken 기억해 (0.75); a line too long for a
//    memory keeps its whole text beside its short title.
//  - Every row an import touched is journalled with what it was before, so 되돌리기 removes exactly that batch: the
//    rows it added go, the rows it changed are put back as they were.
//  - POST /memory's part for the page (ArisImportRoute): the request to copy, the preview, the import, the undo.
//  The extra columns and the journal live in memory.sqlite under the store's own lock (ArisMemoryStore.locked).
//

import Foundation

struct ArisImportResult: Equatable, Sendable {
    var batch: String
    var added = 0
    /// An older wording replaced by the line's newer one.
    var updated = 0
    /// Already remembered: made a little surer.
    var known = 0
    /// Not written: a secret, an older wording than what Aris has, or a line the store wouldn't take.
    var skipped = 0

    var written: Int { added + updated + known }
}

/// What an import adds to a memory's row.
struct ArisImportExtra: Equatable, Sendable {
    /// The AI it came from, as the user named it.
    var via: String?
    /// "instruction" for a ticked instruction.
    var mark: String?
    /// The whole line when the memory's text is its short title.
    var detail: String?
}

extension ArisMemoryStore {
    static let instructionMark = "instruction"
    /// What the same thing imported again raises a memory to at most: just under the memories every turn gets (0.8).
    static let importedCeiling = 0.79
    static let importedGain = 0.1
    static let journalDays = 30.0
    static let mostSourceName = 40

    /// The source's name as kept: one short line of letters, digits, spaces and a few marks; "" when there is none.
    static func sourceName(_ raw: String) -> String {
        let line = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let kept = line.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || " .-_+()".unicodeScalars.contains($0) }
        return String(String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).prefix(mostSourceName))
    }

    /// Makes the import's columns and journal on this file when they aren't there (with the lock held).
    private func ensureImport(_ db: Statements) {
        let columns = Set(db.query("PRAGMA table_info(memories)").compactMap { $0.count > 1 ? $0[1].text : nil })
        for column in ["batch", "via", "mark", "detail"] where !columns.contains(column) {
            _ = db.run("ALTER TABLE memories ADD COLUMN \(column) TEXT")
        }
        _ = db.run("CREATE TABLE IF NOT EXISTS import_journal (n INTEGER PRIMARY KEY AUTOINCREMENT, batch TEXT NOT NULL, memory TEXT NOT NULL, before TEXT, at REAL NOT NULL)")
    }

    /// Where each imported memory came from, its mark and its whole text, by the memory's id.
    func importExtras() -> [String: ArisImportExtra] {
        locked { db in
            ensureImport(db)
            var extras: [String: ArisImportExtra] = [:]
            for row in db.query("SELECT id, via, mark, detail FROM memories WHERE via IS NOT NULL OR mark IS NOT NULL OR detail IS NOT NULL") {
                guard row.count == 4, let id = row[0].text else { continue }
                extras[id] = ArisImportExtra(via: row[1].text, mark: row[2].text, detail: row[3].text)
            }
            return extras
        }
    }

    /// Imports the lines the user ticked, in one go. `via`: the AI they came from, as they named it. Each line is judged
    /// again here (the preview's verdict isn't trusted back): a secret is never written, and an older wording than
    /// what Aris has changes nothing.
    func importLines(_ lines: [ArisImportLine], via rawName: String, now: Date = Date()) -> ArisImportResult {
        var result = ArisImportResult(batch: UUID().uuidString)
        let via = Self.sourceName(rawName)
        pruneImportJournal(now: now)
        for raw in lines.prefix(ArisMemoryImport.mostLines) {
            // Defused again here (the sheet sends back what it showed, which isn't trusted back either), and a date
            // later than tomorrow is no date.
            var line = raw
            line.text = ArisMemoryImport.cleaned(raw.text)
            line.date = raw.date.flatMap { $0 <= ArisMemoryImport.latest(now) ? $0 : nil }
            let title = ArisMemoryImport.title(line.text)
            let candidate = ArisMemoryCandidate(kind: line.kind, subject: "", text: title, confidence: Self.toolConfidence)
            guard !ArisMemoryText.normalized(title).isEmpty, !Self.holdsBack(line.text, source: .imported) else { result.skipped += 1; continue }
            let existing = all()
            let extra = ArisImportExtra(via: via.isEmpty ? nil : via, mark: line.category == .instructions ? Self.instructionMark : nil,
                                        detail: ArisMemoryText.cleaned(line.text) == ArisMemoryText.cleaned(title) ? nil : String(line.text.prefix(ArisMemoryImport.mostText)))
            switch ArisMemoryMerge.plan(candidate, existing: existing) {
            case .insert:
                guard case .added(let record) = remember(candidate, source: .imported, turnAt: line.date ?? now, now: now) else { result.skipped += 1; continue }
                journal(result.batch, memory: record.id, before: nil, at: now)
                stamp(record.id, batch: result.batch, extra: extra, confidence: line.category == .instructions ? Self.saidConfidence : nil)
                result.added += 1
            case .duplicate(let id):
                guard let old = existing.first(where: { $0.id == id }) else { result.skipped += 1; continue }
                journal(result.batch, memory: id, before: old, at: now)
                // The same thing from another AI makes it a little surer, never one of the memories every turn gets.
                let surer = max(old.confidence, min(old.confidence + Self.importedGain, Self.importedCeiling))
                locked { db in _ = db.run("UPDATE memories SET confidence = ?, updated_at = ? WHERE id = ?", [.real(surer), .real(now.timeIntervalSince1970), .text(id)]) }
                result.known += 1
            case .update(let id):
                // The newer date wins, not the import's order; a line with no date replaces nothing.
                guard let old = existing.first(where: { $0.id == id }), let date = line.date, date > old.turnAt else { result.skipped += 1; continue }
                journal(result.batch, memory: id, before: old, at: now)
                guard case .updated = remember(candidate, source: .imported, turnAt: date, now: now) else { result.skipped += 1; continue }
                stamp(id, batch: result.batch, extra: extra, confidence: line.category == .instructions ? Self.saidConfidence : nil)
                result.updated += 1
            }
        }
        return result
    }

    /// The journal's rows older than `journalDays` go (after every import, and on each refresh of the memory, so they
    /// don't outlive their 30 days when no other import comes).
    func pruneImportJournal(now: Date = Date()) {
        locked { db in
            ensureImport(db)
            _ = db.run("DELETE FROM import_journal WHERE at < ?", [.real(now.addingTimeInterval(-Self.journalDays * 86_400).timeIntervalSince1970)])
        }
    }

    private func journal(_ batch: String, memory: String, before: ArisMemoryRecord?, at now: Date) {
        let old = before.map { record -> String in
            let extra = importExtras()[record.id]
            let fields: [String: Any] = ["kind": record.kind.rawValue, "subject": record.subject, "text": record.text, "source": record.source.rawValue,
                                         "turnAt": record.turnAt.timeIntervalSince1970, "confidence": record.confidence, "updatedAt": record.updatedAt.timeIntervalSince1970,
                                         "via": extra?.via ?? NSNull(), "mark": extra?.mark ?? NSNull(), "detail": extra?.detail ?? NSNull()]
            return String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
        }
        locked { db in
            _ = db.run("INSERT INTO import_journal (batch, memory, before, at) VALUES (?, ?, ?, ?)",
                       [.text(batch), .text(memory), old.map { .text($0) } ?? .null, .real(now.timeIntervalSince1970)])
        }
    }

    private func stamp(_ id: String, batch: String, extra: ArisImportExtra, confidence: Double?) {
        let text = { (value: String?) -> Value in value.map { .text($0) } ?? .null }
        locked { db in
            _ = db.run("UPDATE memories SET batch = ?, via = ?, mark = ?, detail = ? WHERE id = ?", [.text(batch), text(extra.via), text(extra.mark), text(extra.detail), .text(id)])
            if let confidence { _ = db.run("UPDATE memories SET confidence = ? WHERE id = ?", [.real(confidence), .text(id)]) }
        }
    }

    /// 되돌리기: exactly that batch. The memories it added are removed (overwritten on disk), the ones it changed are as
    /// they were before it. Nil when no such batch is journalled (undone already, or too old).
    func undoImport(batch: String) -> (removed: Int, restored: Int)? {
        locked(emptiesLog: true) { db in
            ensureImport(db)
            let rows = db.query("SELECT memory, before FROM import_journal WHERE batch = ? ORDER BY n DESC", [.text(batch)])
            guard !rows.isEmpty else { return nil }
            var removed = 0, restored = 0
            for row in rows {
                guard let id = row.first?.text else { continue }
                guard let before = row[1].text, let old = (try? JSONSerialization.jsonObject(with: Data(before.utf8))) as? [String: Any] else {
                    if db.run("DELETE FROM memories WHERE id = ?", [.text(id)]) { removed += 1 }
                    continue
                }
                let text = { (key: String) -> Value in (old[key] as? String).map { .text($0) } ?? .null }
                let real = { (key: String) -> Value in .real((old[key] as? NSNumber)?.doubleValue ?? 0) }
                if db.run("UPDATE memories SET kind = ?, subject = ?, text = ?, source = ?, turn_at = ?, confidence = ?, updated_at = ?, via = ?, mark = ?, detail = ?, batch = NULL WHERE id = ?",
                          [text("kind"), text("subject"), text("text"), text("source"), real("turnAt"), real("confidence"), real("updatedAt"), text("via"), text("mark"),
                           text("detail"), .text(id)]) { restored += 1 }
            }
            _ = db.run("DELETE FROM import_journal WHERE batch = ?", [.text(batch)])
            return (removed, restored)
        }
    }
}

/// POST /memory, the import's part (설정 › 기억 › 다른 AI에서 가져오기; only the Aris app itself: ArisPeer, in main.swift):
///   {"op": "importPrompt"}                                   -> {"ko": "…", "en": "…"}   the request to copy
///   {"op": "importPreview", "text": "<the paste>"}           -> {"lines": [{"n","category","date","text","kind","state","ticked","stored"?,"replaces"?}],
///                                                               "unreadable": ["…"], "complete": true | false | null}
///   {"op": "importApply", "source": "Claude", "lines": [{"category","date","text"}]}
///                                                            -> {"batch","added","updated","known","skipped"}
///   {"op": "importUndo", "batch": "…"}                       -> {"removed": n, "restored": n}
/// Nil for any other op. The pasted text is read by ArisMemoryImport's rules only: no brain sees it here. `audit`:
/// the line for actions.log, never a line's words.
enum ArisImportRoute {
    /// "2025-03-01" for a line's date (kept at noon UTC: ArisMemoryImport.day).
    private static func dayText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func handle(_ object: [String: Any], store: ArisMemoryStore, now: Date = Date()) -> (status: Int, body: Data, audit: String?)? {
        switch object["op"] as? String {
        case "importPrompt":
            return ok(["ko": ArisMemoryImport.prompt(korean: true), "en": ArisMemoryImport.prompt(korean: false)], audit: nil)
        case "importPreview":
            guard let text = object["text"] as? String, text.count <= ArisMemoryImport.mostPaste else { return bad }
            let parsed = ArisMemoryImport.parse(text, now: now)
            let lines = ArisMemoryImport.judged(parsed.lines, existing: store.all(), now: now).map { line -> [String: Any] in
                var row: [String: Any] = ["n": line.number, "category": line.category.rawValue, "date": line.date.map(dayText) ?? "", "text": line.text,
                                          "kind": line.kind.rawValue, "state": line.state.rawValue, "ticked": line.ticked]
                // Exactly what is stored when it isn't the line itself, and the wording a line would replace.
                if let stored = line.stored { row["stored"] = stored }
                if line.state == .updates, let old = line.replaces { row["replaces"] = old }
                // A date later than tomorrow was left out: the row says so (ArisImportCopy "future").
                if line.futureDate { row["future"] = true }
                // Not ticked because it carries a link or an address: the row says that is why.
                if line.look, line.state == .new || line.state == .known || line.state == .updates, ArisMemoryImport.carriesAddress(line.text) { row["address"] = true }
                return row
            }
            return ok(["lines": lines, "unreadable": parsed.unreadable, "complete": parsed.complete.map { $0 as Any } ?? NSNull()], audit: nil)
        case "importApply":
            guard let rows = object["lines"] as? [[String: Any]], !rows.isEmpty, rows.count <= ArisMemoryImport.mostLines else { return bad }
            var lines: [ArisImportLine] = []
            for (index, row) in rows.enumerated() {
                guard let text = row["text"] as? String, !text.isEmpty, text.count <= ArisMemoryImport.mostText,
                      let category = (row["category"] as? String).flatMap(ArisImportCategory.init(rawValue:)) else { return bad }
                var line = ArisImportLine(number: index + 1, category: category, date: (row["date"] as? String).flatMap { ArisMemoryImport.day($0, now: now) },
                                          text: ArisMemoryImport.cleaned(text), kind: .fact)
                line.kind = ArisMemoryImport.kind(of: line)
                lines.append(line)
            }
            let result = store.importLines(lines, via: object["source"] as? String ?? "", now: now)
            return ok(["batch": result.batch, "added": result.added, "updated": result.updated, "known": result.known, "skipped": result.skipped],
                      audit: "memory: imported \(result.written) (\(result.skipped) skipped)")
        case "importUndo":
            guard let batch = object["batch"] as? String, UUID(uuidString: batch) != nil else { return bad }
            guard let undone = store.undoImport(batch: batch) else { return ok(["removed": 0, "restored": 0, "found": false], audit: nil) }
            return ok(["removed": undone.removed, "restored": undone.restored, "found": true], audit: "memory: import undone (\(undone.removed) removed, \(undone.restored) restored)")
        default:
            return nil
        }
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }

    private static let bad: (status: Int, body: Data, audit: String?) = (400, Data("{}".utf8), nil)
}
