//
//  ArisMemoryStore+Review.swift
//  aris-agent, aris-tools
//
//  What waits for the user in 설정 › 기억 › 확인할 것:
//  - held: a memory or a work lesson the write gate stopped (ArisMemoryGate). Nothing of it is used until he keeps
//    it (넣기: it is written then, as reviewed); 버리기 removes it, overwritten on disk. At most `heldCapacity`.
//  - conflicts: two current memories where one says yes and the other no about the same thing. Until he settles it
//    the older one isn't recalled; 이게 맞아요 keeps one and the other becomes its history; 둘 다 맞아요 keeps both.
//  Foundation and SQLite only (tested).
//

import Foundation

struct ArisHeldItem: Equatable, Sendable {
    let id: String
    /// "memory" or "lesson".
    let kind: String
    let source: ArisMemorySource
    let text: String
    let family: ArisMemoryGateFamily
    let pattern: String
    let at: Date
}

struct ArisMemoryConflict: Equatable, Sendable {
    let id: String
    let first: ArisMemoryRecord
    let second: ArisMemoryRecord
}

enum ArisMemoryConflicts {
    /// Alike enough to be about the same thing: this similar, or this similar with the same kind and subject.
    static let alike = 0.5
    static let alikeSameSubject = 0.35

    /// Pairs of syllables and words that only say how (a verb, a no), never what about.
    static let howGrams: Set<String> = ["좋아", "아해", "아요", "싫어", "어해", "마셔", "셔요", "먹어", "어요", "않아", "하지", "는다", "해요", "안", "못", "해", "써", "봐",
                                        "like", "love", "hate", "don't", "dont", "doesn't", "not", "no", "never", "drink", "eat", "use", "want"]

    /// What a memory is about: its grams without the endings and fillers recall ignores, and without the how.
    static func about(_ text: String) -> Set<String> { ArisMemoryText.grams(text).subtracting(ArisMemoryRecall.fillerGrams).subtracting(howGrams) }

    /// The current memories `record` contradicts: one says no where the other says yes, about the same thing (they
    /// share what they are about, and are alike).
    static func contradicted(by record: ArisMemoryRecord, among existing: [ArisMemoryRecord]) -> [ArisMemoryRecord] {
        let negated = ArisMemoryText.isNegated(record.text)
        let subject = ArisMemoryText.normalized(record.subject)
        let topic = about(record.text)
        return existing.filter { other in
            guard other.id != record.id, other.supersededBy == nil, ArisMemoryText.isNegated(other.text) != negated,
                  !topic.isDisjoint(with: about(other.text)) else { return false }
            let similarity = ArisMemoryText.similarity(record.text, other.text)
            if similarity >= alike { return true }
            return !subject.isEmpty && other.kind == record.kind && ArisMemoryText.normalized(other.subject) == subject && similarity >= alikeSameSubject
        }.prefix(3).map { $0 }
    }
}

extension ArisMemoryStore {
    static let heldCapacity = 100

    static let reviewSchema = """
        CREATE TABLE IF NOT EXISTS memory_conflicts (id TEXT PRIMARY KEY, a TEXT NOT NULL, b TEXT NOT NULL, created_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS memory_held (id TEXT PRIMARY KEY, kind TEXT NOT NULL, source TEXT NOT NULL, text TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '',
            memory_kind TEXT NOT NULL DEFAULT 'fact', turn_at REAL NOT NULL, payload TEXT, family TEXT NOT NULL, pattern TEXT NOT NULL, created_at REAL NOT NULL);
        """

    // MARK: Held

    func held() -> [ArisHeldItem] {
        locked { db in
            db.query("SELECT id, kind, source, text, family, pattern, created_at FROM memory_held ORDER BY created_at DESC").compactMap { row in
                guard row.count == 7, let id = row[0].text, let kind = row[1].text, let source = row[2].text.flatMap(ArisMemorySource.init(rawValue:)),
                      let text = row[3].text, let family = row[4].text.flatMap(ArisMemoryGateFamily.init(rawValue:)), let at = row[6].real else { return nil }
                return ArisHeldItem(id: id, kind: kind, source: source, text: text, family: family, pattern: row[5].text ?? "", at: Date(timeIntervalSince1970: at))
            }
        }
    }

    /// A work lesson the gate stopped, with what it takes to save it later (`payload`); its id.
    func holdLesson(text: String, payload: String, hit: ArisMemoryGate.Hit, now: Date = Date()) -> String? {
        defer { Self.announceChange() }
        return locked { db in Self.hold(kind: "lesson", source: .learned, text: text, subject: "", memoryKind: .fact, turnAt: now, hit: hit, db, now: now, payload: payload) }
    }

    enum Kept: Equatable {
        case memory(Outcome)
        /// A lesson's payload, for ArisWorkStore to save.
        case lesson(String)
    }

    /// 넣기: the held item is written now, as the user has seen it (a memory through `remember`, reviewed; a lesson's
    /// payload is handed back). Nil when there is no such item.
    func keepHeld(id: String, now: Date = Date()) -> Kept? {
        let row = locked { db in
            db.query("SELECT kind, source, text, subject, memory_kind, turn_at, payload FROM memory_held WHERE id = ?", [.text(id)]).first
        }
        guard let row, row.count == 7, let kind = row[0].text, let text = row[2].text else { return nil }
        _ = dropHeld(id: id)
        if kind == "lesson" { return row[6].text.map(Kept.lesson) }
        let source = row[1].text.flatMap(ArisMemorySource.init(rawValue:)) ?? .tool
        let candidate = ArisMemoryCandidate(kind: row[4].text.flatMap(ArisMemoryKind.init(rawValue:)) ?? .fact, subject: row[3].text ?? "", text: text,
                                            confidence: Self.ceiling(source))
        return .memory(remember(candidate, source: source, turnAt: row[5].real.map(Date.init(timeIntervalSince1970:)) ?? now, now: now, reviewed: true))
    }

    /// 버리기: gone, overwritten on disk. False when it wasn't there.
    @discardableResult
    func dropHeld(id: String) -> Bool {
        defer { Self.announceChange() }
        return locked(emptiesLog: true) { db in
            guard db.query("SELECT COUNT(*) FROM memory_held WHERE id = ?", [.text(id)]).first?.first?.int == 1 else { return false }
            return db.run("DELETE FROM memory_held WHERE id = ?", [.text(id)])
        }
    }

    /// Called with the lock held: writes a held item (the oldest go past `heldCapacity`); its id.
    static func hold(kind: String, source: ArisMemorySource, text: String, subject: String, memoryKind: ArisMemoryKind, turnAt: Date,
                     hit: ArisMemoryGate.Hit, _ db: Statements, now: Date, payload: String? = nil) -> String? {
        // The same text held again is the same item.
        if let same = db.query("SELECT id FROM memory_held WHERE kind = ? AND text = ?", [.text(kind), .text(text)]).first?.first?.text { return same }
        let id = UUID().uuidString
        guard db.run("INSERT INTO memory_held (id, kind, source, text, subject, memory_kind, turn_at, payload, family, pattern, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                     [.text(id), .text(kind), .text(source.rawValue), .text(text), .text(subject), .text(memoryKind.rawValue), .real(turnAt.timeIntervalSince1970),
                      payload.map { .text($0) } ?? .null, .text(hit.family.rawValue), .text(hit.name), .real(now.timeIntervalSince1970)]) else { return nil }
        _ = db.run("DELETE FROM memory_held WHERE id NOT IN (SELECT id FROM memory_held ORDER BY created_at DESC LIMIT ?)", [.int(heldCapacity)])
        return id
    }

    // MARK: Conflicts

    func conflicts() -> [ArisMemoryConflict] {
        let current = Dictionary(all().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return locked { db in
            db.query("SELECT id, a, b FROM memory_conflicts ORDER BY created_at DESC").compactMap { row -> ArisMemoryConflict? in
                guard row.count == 3, let id = row[0].text, let a = row[1].text.flatMap({ current[$0] }), let b = row[2].text.flatMap({ current[$0] }) else { return nil }
                // The older one first.
                return a.turnAt <= b.turnAt ? ArisMemoryConflict(id: id, first: a, second: b) : ArisMemoryConflict(id: id, first: b, second: a)
            }
        }
    }

    /// The memories an unsettled conflict keeps from recall: the older of each pair.
    func conflictHeldBack() -> Set<String> { Set(conflicts().map(\.first.id)) }

    /// Settles a conflict: `keep` is the memory that is right now (the other becomes its history), nil keeps both.
    /// False when there is no such conflict, or `keep` isn't one of its two.
    @discardableResult
    func resolveConflict(id: String, keep: String?, now: Date = Date()) -> Bool {
        guard let conflict = conflicts().first(where: { $0.id == id }) else { return false }
        let ids = [conflict.first.id, conflict.second.id]
        if let keep, !ids.contains(keep) { return false }
        defer { Self.announceChange() }
        return locked { db in
            if let keep, let other = ids.first(where: { $0 != keep }) {
                guard db.run("UPDATE memories SET superseded_by = ?, valid_until = ? WHERE id = ?", [.text(keep), .real(now.timeIntervalSince1970), .text(other)]) else { return false }
                _ = db.run("DELETE FROM memory_conflicts WHERE a = ? OR b = ?", [.text(other), .text(other)])
            }
            return db.run("DELETE FROM memory_conflicts WHERE id = ?", [.text(id)])
        }
    }

    /// Called with the lock held.
    static func openConflict(_ a: String, _ b: String, _ db: Statements, now: Date) {
        guard db.query("SELECT COUNT(*) FROM memory_conflicts WHERE (a = ? AND b = ?) OR (a = ? AND b = ?)", [.text(a), .text(b), .text(b), .text(a)]).first?.first?.int == 0 else { return }
        _ = db.run("INSERT INTO memory_conflicts (id, a, b, created_at) VALUES (?, ?, ?, ?)", [.text(UUID().uuidString), .text(a), .text(b), .real(now.timeIntervalSince1970)])
    }

    /// Called with the lock held, for a memory that is deleted (`text`: its words, read before the delete): its
    /// conflicts go, and nothing of its words stays on a person's or project's page (ArisMemoryStore.unlink).
    static func forgetEverywhere(_ id: String, text: String?, _ db: Statements) {
        _ = db.run("DELETE FROM memory_conflicts WHERE a = ? OR b = ?", [.text(id), .text(id)])
        unlink(memory: id, text: text, db)
    }
}
