//
//  ArisMemoryEntities.swift
//  aris-agent, aris-tools
//
//  People and project pages: one entity per person or project the user talks about, with
//  - a short summary (what is true about them now), which only the user's own words or a write they approved change: their
//    기억해 about someone with no summary yet, the weekly tidy-up from his own words (ArisMemoryConsolidation, listed
//    in 설정 › 기억 and undoable), never a learned, tool-written or imported line;
//  - a dated timeline that is only ever added to, each entry with where it came from (직접 말함 / 추정 / 가져옴) and
//    the memory it came with; forgetting that memory takes its entries too, and its words from the page: a summary
//    holding them (or one the tidy-up made) is built again from what is left, the names it gave and the tidy-up's
//    change rows go, and a page with nothing left goes (a hard delete stays hard);
//  - aliases: the names the user uses for them ("민수", "MS").
//  The card a turn gets ("who is X, what's still open with them") is built here with no model, in about 60 tokens.
//  Foundation only (tested).
//

import Foundation

enum ArisEntityKind: String, CaseIterable, Sendable {
    case person, project

    func label(korean: Bool) -> String {
        switch self {
        case .person: korean ? "사람" : "person"
        case .project: korean ? "프로젝트" : "project"
        }
    }
}

struct ArisEntity: Equatable, Sendable {
    let id: String
    var kind: ArisEntityKind
    var name: String
    var summary: String
    /// Who last wrote the summary: "said" (his 기억해), "approved" (their yes in Settings), "consolidated" (the weekly
    /// tidy-up, from his own words); "" while there is none.
    var summarySource: String
    var aliases: [String]
    var createdAt: Date
    var updatedAt: Date
}

struct ArisTimelineEntry: Equatable, Sendable {
    let id: Int
    let entity: String
    let at: Date
    let text: String
    let source: ArisMemorySource
    /// The memory it came with (forgetting that memory takes this entry too).
    let memory: String?
}

/// A summary change the weekly tidy-up made, for 설정 › 기억 and its 되돌리기.
struct ArisEntityChange: Equatable, Sendable {
    let id: Int
    let at: Date
    let entity: String
    let name: String
    let before: String
    let after: String
    let evidence: Int
}

enum ArisEntities {
    /// Most entities kept, and timeline entries per entity.
    static let capacity = 200
    static let timelineLimit = 60
    /// A card is about this many tokens at most (ArisMemoryText.tokenEstimate).
    static let cardBudget = 70
    /// Open items a card names at most.
    static let openOnCard = 2

    /// Particles a name may carry ("민수한테", "민수는").
    private static let particles = ["에게서", "한테서", "에게", "한테", "께서", "이랑", "랑", "하고", "이는", "이가", "이를", "은", "는", "이", "가", "을", "를", "의", "와", "과", "도", "께", "야", "아"]

    /// The form a name is matched in: normalized, a trailing particle off ("민수한테" → 민수).
    static func key(_ name: String) -> String {
        let plain = ArisMemoryText.normalized(name)
        guard ArisMemoryText.isKorean(plain), let particle = particles.first(where: { plain.hasSuffix($0) && plain.count > $0.count + 1 }) else { return plain }
        return String(plain.dropLast(particle.count))
    }

    /// A name worth matching: two or more letters (one syllable is too often part of another word).
    static func matchable(_ key: String) -> Bool { key.count >= 2 }

    /// The entities `words` name (an alias as one of its words, a particle allowed), best first: the longest alias.
    static func mentioned(_ entities: [ArisEntity], in words: String) -> [ArisEntity] {
        let tokens = Set(ArisMemoryText.words(words).map(key))
        let squashed = ArisMemoryText.normalized(words)
        return entities.compactMap { entity -> (ArisEntity, Int)? in
            let hits = ([entity.name] + entity.aliases).map(key).filter(matchable).filter { alias in
                tokens.contains(alias) || (!ArisMemoryText.isKorean(alias) && alias.count >= 4 && squashed.contains(alias))
            }
            return hits.isEmpty ? nil : (entity, hits.map(\.count).max() ?? 0)
        }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    /// Names the user gives someone in a memory: "민수를 MS라고 불러", "I call them Max".
    static func calledNames(_ text: String) -> [String] {
        var names: [String] = []
        let patterns = [#"(\S{1,20})(?:이라고|라고) ?(?:불러|부르|해)"#, #"(?i)\bcall (?:him|her|them|it) ([A-Za-z][A-Za-z.'-]{0,19})"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                guard let found = Range(match.range(at: 1), in: text) else { continue }
                let name = String(text[found]).trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces))
                if matchable(key(name)), !names.contains(name) { names.append(name) }
            }
        }
        return names
    }

    /// The memories still open with an entity: its commitments, and its events of the last week, newest first.
    static func openItems(_ entity: ArisEntity, memories: [ArisMemoryRecord], now: Date) -> [ArisMemoryRecord] {
        memories.filter { record in
            guard record.isCurrent(at: now), about(record, entity) else { return false }
            switch record.kind {
            case .commitment: return true
            case .event: return now.timeIntervalSince(record.validFrom ?? record.turnAt) <= 7 * 86_400
            default: return false
            }
        }.sorted { $0.turnAt > $1.turnAt }
    }

    /// Whether a memory is about `entity`: its subject is one of the names, or one of its words is.
    static func about(_ record: ArisMemoryRecord, _ entity: ArisEntity) -> Bool {
        let names = Set(([entity.name] + entity.aliases).map(key).filter(matchable))
        if names.contains(key(record.subject)) { return true }
        return !Set(ArisMemoryText.words(record.text).map(key)).isDisjoint(with: names)
    }

    /// "- (03-11) …" as a card's open item, with its source.
    private static func openLine(_ record: ArisMemoryRecord, korean: Bool) -> String {
        "\(ArisMemoryText.cleaned(record.text)) (\(shortDay(record.turnAt)), \(record.source.label(korean: korean)))"
    }

    static func shortDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", parts.month ?? 0, parts.day ?? 0)
    }

    /// The card a turn gets for `entity`: who it is (the summary, with its source) and what is still open, inside
    /// `cardBudget` tokens; no < or >.
    static func card(_ entity: ArisEntity, memories: [ArisMemoryRecord], now: Date) -> String {
        let korean = ArisMemoryText.isKorean(entity.name + entity.summary)
        let others = entity.aliases.filter { key($0) != key(entity.name) }.prefix(2)
        let head = "\(entity.name) (\(entity.kind.label(korean: korean))\(others.isEmpty ? "" : (korean ? ", 다른 이름: " : ", also: ") + others.joined(separator: ", ")))"
        let open = openItems(entity, memories: memories, now: now).prefix(openOnCard).map { openLine($0, korean: korean) }
        let openPart = open.isEmpty ? "" : " " + (korean ? "남은 일: " : "Still open: ") + open.joined(separator: "; ") + "."
        let source = entity.summarySource == "consolidated" ? (korean ? "직접 한 말에서 정리" : "summed up from what you said")
            : ArisMemorySource.said.label(korean: korean)
        // Inside the budget: the summary is cut, word by word, before anything else.
        let room = cardBudget - ArisMemoryText.tokenEstimate(head + openPart + " [\(source)]")
        var words = entity.summary.split(separator: " ").map(String.init)
        var cut = false
        while !words.isEmpty, ArisMemoryText.tokenEstimate(words.joined(separator: " ")) > room { words.removeLast(); cut = true }
        let summary = words.isEmpty ? (korean ? "요약 없음." : "No summary yet.") : words.joined(separator: " ") + (cut ? "…" : "") + " [\(source)]."
        let text = head + ": " + summary + openPart
        return defused(text)
    }

    static func defused(_ text: String) -> String { text.replacingOccurrences(of: "<", with: "‹").replacingOccurrences(of: ">", with: "›") }
}

// MARK: - The store's part

extension ArisMemoryStore {
    /// The entity tables (made with the memory schema; this only reads and writes them).
    static let entitySchema = """
        CREATE TABLE IF NOT EXISTS entities (id TEXT PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '',
            summary_source TEXT NOT NULL DEFAULT '', created_at REAL NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS entity_aliases (entity TEXT NOT NULL, alias TEXT NOT NULL, shown TEXT NOT NULL, PRIMARY KEY (entity, alias));
        CREATE INDEX IF NOT EXISTS entity_aliases_alias ON entity_aliases(alias);
        CREATE TABLE IF NOT EXISTS entity_timeline (id INTEGER PRIMARY KEY AUTOINCREMENT, entity TEXT NOT NULL, at REAL NOT NULL, text TEXT NOT NULL,
            source TEXT NOT NULL, memory TEXT, created_at REAL NOT NULL);
        CREATE INDEX IF NOT EXISTS entity_timeline_entity ON entity_timeline(entity);
        CREATE TABLE IF NOT EXISTS entity_changes (id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, entity TEXT NOT NULL, before TEXT NOT NULL,
            before_source TEXT NOT NULL DEFAULT '', after TEXT NOT NULL, evidence INTEGER NOT NULL, undone INTEGER NOT NULL DEFAULT 0);
        """

    func entities() -> [ArisEntity] { locked { db in Self.entities(db) } }

    func entity(id: String) -> ArisEntity? { entities().first { $0.id == id } }

    /// The entity `name` is one of the names of (model-free: aliases, a particle allowed).
    func entity(named name: String) -> ArisEntity? {
        let wanted = ArisEntities.key(name)
        guard ArisEntities.matchable(wanted) else { return nil }
        return entities().first { ([$0.name] + $0.aliases).map(ArisEntities.key).contains(wanted) }
    }

    func timeline(of entity: String) -> [ArisTimelineEntry] {
        locked { db in
            db.query("SELECT id, entity, at, text, source, memory FROM entity_timeline WHERE entity = ? ORDER BY at, id", [.text(entity)]).compactMap(Self.entry)
        }
    }

    /// The card for `name` ("who is X, what's still open"), or nil when no entity has that name.
    func card(_ name: String, now: Date = Date()) -> String? {
        guard let entity = entity(named: name) else { return nil }
        return ArisEntities.card(entity, memories: all(), now: now)
    }

    /// Sets a summary: only from the user's own words (`said`) or their yes in Settings (`approved`). False otherwise, or
    /// when there is no such entity.
    @discardableResult
    func setSummary(entity id: String, to text: String, by source: String, now: Date = Date()) -> Bool {
        guard ["said", "approved"].contains(source) else { return false }
        let clean = ArisMemoryText.cleaned(text)
        guard !ArisMemoryText.isSecret(clean) else { return false }
        return locked { db in
            guard db.query("SELECT COUNT(*) FROM entities WHERE id = ?", [.text(id)]).first?.first?.int == 1 else { return false }
            return db.run("UPDATE entities SET summary = ?, summary_source = ?, updated_at = ? WHERE id = ?",
                          [.text(clean), .text(clean.isEmpty ? "" : source), .real(now.timeIntervalSince1970), .text(id)])
        }
    }

    /// Removes an entity with its names, timeline and tidy-up record (the memories stay). False when it wasn't there.
    @discardableResult
    func deleteEntity(id: String) -> Bool {
        locked(emptiesLog: true) { db in
            guard db.query("SELECT COUNT(*) FROM entities WHERE id = ?", [.text(id)]).first?.first?.int == 1 else { return false }
            for table in ["entity_aliases", "entity_timeline", "entity_changes"] { _ = db.run("DELETE FROM \(table) WHERE entity = ?", [.text(id)]) }
            return db.run("DELETE FROM entities WHERE id = ?", [.text(id)])
        }
    }

    // MARK: The weekly tidy-up's changes (ArisMemoryConsolidation)

    /// Writes a summary the tidy-up made from the user's own words (the caller checked the evidence and the grounding), and
    /// lists the change for 설정 › 기억 and its 되돌리기. `basedOn`: the memories it was made from, each still there as
    /// it was read (one forgotten or reworded while the brain was asked, and nothing is written: a forgotten memory's
    /// words never come back through a summary). False when there is no such entity, nothing changes, or the evidence
    /// is gone.
    @discardableResult
    func applyConsolidation(entity id: String, summary text: String, evidence: Int, basedOn: [ArisMemoryRecord] = [], now: Date = Date()) -> Bool {
        let clean = ArisMemoryText.cleaned(text)
        guard !clean.isEmpty, !ArisMemoryText.isSecret(clean) else { return false }
        return locked { db in
            for record in basedOn {
                guard db.query("SELECT text FROM memories WHERE id = ? AND superseded_by IS NULL", [.text(record.id)]).first?.first?.text == record.text else { return false }
            }
            guard let row = db.query("SELECT summary, summary_source FROM entities WHERE id = ?", [.text(id)]).first, row.count == 2,
                  let before = row[0].text, before != clean else { return false }
            guard db.run("UPDATE entities SET summary = ?, summary_source = 'consolidated', updated_at = ? WHERE id = ?",
                         [.text(clean), .real(now.timeIntervalSince1970), .text(id)]) else { return false }
            return db.run("INSERT INTO entity_changes (at, entity, before, before_source, after, evidence) VALUES (?, ?, ?, ?, ?, ?)",
                          [.real(now.timeIntervalSince1970), .text(id), .text(before), .text(row[1].text ?? ""), .text(clean), .int(evidence)])
        }
    }

    /// The tidy-up's changes not undone, newest first, at most `limit`.
    func changes(limit: Int = 20) -> [ArisEntityChange] {
        locked { db in
            db.query("SELECT c.id, c.at, c.entity, e.name, c.before, c.after, c.evidence FROM entity_changes c JOIN entities e ON e.id = c.entity WHERE c.undone = 0 ORDER BY c.at DESC LIMIT ?",
                     [.int(limit)]).compactMap { row in
                guard row.count == 7, let id = row[0].int, let at = row[1].real, let entity = row[2].text, let name = row[3].text, let before = row[4].text,
                      let after = row[5].text else { return nil }
                return ArisEntityChange(id: id, at: Date(timeIntervalSince1970: at), entity: entity, name: name, before: before, after: after, evidence: row[6].int ?? 0)
            }
        }
    }

    /// 되돌리기: the summary is what it was before that change (when nothing wrote it since). False when there is no
    /// such change, it was undone already, or the summary has changed since.
    @discardableResult
    func undoChange(id: Int, now: Date = Date()) -> Bool {
        locked { db in
            guard let row = db.query("SELECT entity, before, before_source, after FROM entity_changes WHERE id = ? AND undone = 0", [.int(id)]).first, row.count == 4,
                  let entity = row[0].text, let before = row[1].text, let after = row[3].text,
                  db.query("SELECT summary FROM entities WHERE id = ?", [.text(entity)]).first?.first?.text == after else { return false }
            guard db.run("UPDATE entities SET summary = ?, summary_source = ?, updated_at = ? WHERE id = ?",
                         [.text(before), .text(before.isEmpty ? "" : row[2].text ?? ""), .real(now.timeIntervalSince1970), .text(entity)]) else { return false }
            return db.run("UPDATE entity_changes SET undone = 1 WHERE id = ?", [.int(id)])
        }
    }

    // MARK: Called with the lock held (from remember)

    static func entities(_ db: Statements) -> [ArisEntity] {
        var aliases: [String: [String]] = [:]
        for row in db.query("SELECT entity, shown FROM entity_aliases ORDER BY rowid") {
            guard row.count == 2, let entity = row[0].text, let shown = row[1].text else { continue }
            aliases[entity, default: []].append(shown)
        }
        return db.query("SELECT id, kind, name, summary, summary_source, created_at, updated_at FROM entities ORDER BY updated_at DESC").compactMap { row in
            guard row.count == 7, let id = row[0].text, let kind = row[1].text.flatMap(ArisEntityKind.init(rawValue:)), let name = row[2].text,
                  let created = row[5].real, let updated = row[6].real else { return nil }
            return ArisEntity(id: id, kind: kind, name: name, summary: row[3].text ?? "", summarySource: row[4].text ?? "", aliases: aliases[id] ?? [name],
                              createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated))
        }
    }

    private static func entry(_ row: [Value]) -> ArisTimelineEntry? {
        guard row.count == 6, let id = row[0].int, let entity = row[1].text, let at = row[2].real, let text = row[3].text,
              let source = row[4].text.flatMap(ArisMemorySource.init(rawValue:)) else { return nil }
        return ArisTimelineEntry(id: id, entity: entity, at: Date(timeIntervalSince1970: at), text: text, source: source, memory: row[5].text)
    }

    /// A memory just written (added or reworded): it joins the entity it is about, which a person's or project's
    /// memory with a subject makes when there is none, as a timeline entry with its source; the user's own 기억해 about
    /// one with no summary yet is its summary; the names he says he calls them by become aliases (their words only).
    static func link(_ record: ArisMemoryRecord, _ db: Statements, now: Date) {
        let all = entities(db)
        let subject = ArisEntities.key(record.subject)
        var entity = ArisEntities.matchable(subject) ? all.first { ([$0.name] + $0.aliases).map(ArisEntities.key).contains(subject) } : nil
        if entity == nil, !ArisEntities.matchable(subject) {
            entity = all.first { ArisEntities.about(record, $0) }
        }
        if entity == nil, ArisEntities.matchable(subject), let kind = ArisEntityKind(rawValue: record.kind.rawValue), all.count < ArisEntities.capacity {
            let made = ArisEntity(id: UUID().uuidString, kind: kind, name: String(record.subject.prefix(40)), summary: "", summarySource: "", aliases: [record.subject],
                                  createdAt: now, updatedAt: now)
            guard db.run("INSERT INTO entities (id, kind, name, summary, summary_source, created_at, updated_at) VALUES (?, ?, ?, '', '', ?, ?)",
                         [.text(made.id), .text(kind.rawValue), .text(made.name), .real(now.timeIntervalSince1970), .real(now.timeIntervalSince1970)]) else { return }
            addAlias(made.name, to: made.id, db)
            entity = made
        }
        guard let entity else { return }
        _ = db.run("INSERT INTO entity_timeline (entity, at, text, source, memory, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                   [.text(entity.id), .real(record.turnAt.timeIntervalSince1970), .text(ArisEntities.defused(record.text)), .text(record.source.rawValue),
                    .text(record.id), .real(now.timeIntervalSince1970)])
        // An entity's timeline keeps its latest entries.
        _ = db.run("DELETE FROM entity_timeline WHERE entity = ? AND id NOT IN (SELECT id FROM entity_timeline WHERE entity = ? ORDER BY at DESC, id DESC LIMIT ?)",
                   [.text(entity.id), .text(entity.id), .int(ArisEntities.timelineLimit)])
        if record.source == .said || record.source == .learned {
            for name in ArisEntities.calledNames(record.text) { addAlias(name, to: entity.id, db) }
        }
        if record.source == .said, entity.summary.isEmpty, [.person, .project].contains(record.kind) {
            _ = db.run("UPDATE entities SET summary = ?, summary_source = 'said' WHERE id = ?", [.text(ArisMemoryText.cleaned(record.text)), .text(entity.id)])
        }
        _ = db.run("UPDATE entities SET updated_at = ? WHERE id = ?", [.real(now.timeIntervalSince1970), .text(entity.id)])
    }

    private static func addAlias(_ name: String, to entity: String, _ db: Statements) {
        let key = ArisEntities.key(name)
        guard ArisEntities.matchable(key) else { return }
        _ = db.run("INSERT OR IGNORE INTO entity_aliases (entity, alias, shown) VALUES (?, ?, ?)", [.text(entity), .text(key), .text(String(name.prefix(40)))])
    }

    /// A memory forgotten (`text`: its words, read before it was deleted): nothing of its words stays on a page. Its
    /// timeline entries go; a page that has none left goes, with its names and its tidy-up record; on a page that
    /// stays, a summary that holds its words, or one the tidy-up made, is built again from the page's remaining
    /// memories (the earliest of the user's own about it, as a new page's is) or cleared, the names it gave go, and the
    /// tidy-up's change rows go (they quote the summaries). The caller checkpoints, so secure_delete overwrites it all.
    static func unlink(memory id: String, text: String?, _ db: Statements) {
        let words = text.map(ArisMemoryText.cleaned) ?? ""
        var touched = Set(db.query("SELECT DISTINCT entity FROM entity_timeline WHERE memory = ?", [.text(id)]).compactMap { $0.first?.text })
        if !words.isEmpty {
            touched.formUnion(db.query("SELECT id FROM entities WHERE instr(summary, ?) > 0", [.text(words)]).compactMap { $0.first?.text })
            touched.formUnion(db.query("SELECT DISTINCT entity FROM entity_changes WHERE instr(before, ?) > 0 OR instr(after, ?) > 0",
                                       [.text(words), .text(words)]).compactMap { $0.first?.text })
        }
        _ = db.run("DELETE FROM entity_timeline WHERE memory = ?", [.text(id)])
        for entity in touched { tidy(entity: entity, forgotten: words, db) }
    }

    /// One page after a memory of it was forgotten (see `unlink`).
    private static func tidy(entity id: String, forgotten words: String, _ db: Statements) {
        _ = db.run("DELETE FROM entity_changes WHERE entity = ?", [.text(id)])
        let left = db.query("SELECT memory FROM entity_timeline WHERE entity = ?", [.text(id)])
        guard !left.isEmpty else {
            for table in ["entity_aliases", "entity_timeline"] { _ = db.run("DELETE FROM \(table) WHERE entity = ?", [.text(id)]) }
            _ = db.run("DELETE FROM entities WHERE id = ?", [.text(id)])
            return
        }
        // The page's remaining memories, as they are now (an older wording stays out), oldest first.
        let ids = Set(left.compactMap { $0.first?.text })
        let remaining = db.query("SELECT \(columns) FROM memories WHERE superseded_by IS NULL ORDER BY turn_at, created_at").compactMap(record)
            .filter { ids.contains($0.id) }
        guard let row = db.query("SELECT name, summary, summary_source FROM entities WHERE id = ?", [.text(id)]).first, row.count == 3 else { return }
        let name = row[0].text ?? "", summary = row[1].text ?? "", source = row[2].text ?? ""
        if source == "consolidated" || (!words.isEmpty && summary.contains(words)) {
            let rebuilt = remaining.first { $0.source == .said && [.person, .project].contains($0.kind) }.map { ArisMemoryText.cleaned($0.text) } ?? ""
            _ = db.run("UPDATE entities SET summary = ?, summary_source = ? WHERE id = ?", [.text(rebuilt), .text(rebuilt.isEmpty ? "" : "said"), .text(id)])
        }
        // The names the forgotten words gave, unless the page's own name or a remaining memory of the user's gives them too.
        guard !words.isEmpty else { return }
        let kept = Set([ArisEntities.key(name)] + remaining.filter { $0.source == .said || $0.source == .learned }
            .flatMap { ArisEntities.calledNames($0.text) }.map(ArisEntities.key))
        for given in ArisEntities.calledNames(words).map(ArisEntities.key) where !kept.contains(given) {
            _ = db.run("DELETE FROM entity_aliases WHERE entity = ? AND alias = ?", [.text(id), .text(given)])
        }
    }
}
