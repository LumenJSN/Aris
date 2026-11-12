//
//  ArisWorkMemoryStore.swift
//  aris-agent, aris-tools
//
//  Where the work memory lives: two tables, work_episodes and work_lessons, in the person memory's own file
//  (memory.sqlite: ArisMemoryStore opens it, never through a link, 0600 in a 0700 folder, WAL, secure_delete) and
//  under its lock, so the agent and aris-tools share them as they share the memories. One switch (설정 › 기억 ›
//  한 일에서 배우기, on by default) is kept in the same file's settings.
//
//  The teaching rule is enforced here too, not only by the callers: a lesson is saved only when every episode it is
//  based on is in the table as a conversation turn that may teach (rule 2 of ArisWorkMemory), and it carries the
//  outside mark whenever one of them read outside content (rule 3), whatever the caller said. The lists a turn's
//  context and the lessons are made from are read with that rule in the query itself; tainted episodes themselves are
//  listed only when asked for (the user's history, `recall --tainted`).
//
//  Keeping: an episode's steps go after `compactDays` (its one-line stub stays), a stub goes after `stubDays` unless a
//  lesson still rests on it, and past `capacity` the oldest that no lesson rests on go first. A delete overwrites the
//  rows on disk and empties the write-ahead log, as the person memory's does.
//

import Foundation

final class ArisWorkStore: @unchecked Sendable {
    /// Episodes kept at most, and lessons.
    static let capacity = 2_000
    static let lessonCapacity = 200
    /// An episode keeps its steps this long (the activity log keeps its entries as long), then only its stub.
    static let compactDays = 30.0
    static let stubDays = 180.0

    let memory: ArisMemoryStore
    /// Whether the tables were made on this file (read and written with the memory store's lock held).
    private var ready = false

    init(memory: ArisMemoryStore) { self.memory = memory }

    /// The agent's and aris-tools' own: ~/.config/aris/aris/memory.sqlite.
    static let live = ArisWorkStore(memory: .live)

    private static let schema = [
        """
        CREATE TABLE IF NOT EXISTS work_episodes (id INTEGER PRIMARY KEY AUTOINCREMENT, at REAL NOT NULL, seconds REAL NOT NULL DEFAULT 0,
            kind TEXT NOT NULL, asked TEXT NOT NULL, key TEXT NOT NULL, brain TEXT NOT NULL, steps TEXT NOT NULL, made TEXT NOT NULL,
            acts TEXT NOT NULL, outcome TEXT NOT NULL, error TEXT NOT NULL DEFAULT '', taint INTEGER NOT NULL, title TEXT NOT NULL DEFAULT '',
            tokens INTEGER, offered TEXT NOT NULL DEFAULT '[]', followed INTEGER, teammate TEXT NOT NULL DEFAULT '',
            place TEXT NOT NULL DEFAULT '', result TEXT NOT NULL DEFAULT '', compacted INTEGER NOT NULL DEFAULT 0,
            teaches INTEGER NOT NULL DEFAULT 0)
        """,
        "CREATE INDEX IF NOT EXISTS work_episodes_at ON work_episodes(at)",
        """
        CREATE TABLE IF NOT EXISTS work_lessons (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, key TEXT NOT NULL, asked TEXT NOT NULL,
            works TEXT NOT NULL, fails TEXT NOT NULL, evidence TEXT NOT NULL, confidence REAL NOT NULL, created_at REAL NOT NULL,
            updated_at REAL NOT NULL, expired INTEGER NOT NULL DEFAULT 0, use_count INTEGER NOT NULL DEFAULT 0,
            outside INTEGER NOT NULL DEFAULT 0)
        """,
    ]

    private typealias Value = ArisMemoryStore.Value
    private typealias Statements = ArisMemoryStore.Statements

    /// Runs `work` on the tables (made first if this file has none yet), with the memory store's lock held.
    private func tables<T>(emptiesLog: Bool = false, _ work: (Statements) -> T) -> T {
        memory.locked(emptiesLog: emptiesLog) { db in
            if !ready {
                var made = true
                for statement in Self.schema where !db.run(statement) { made = false }
                ready = made && Self.addColumns(db)
            }
            return work(db)
        }
    }

    /// Tables made before the teaching rule get its two columns: a clean conversation turn taught then, so it still
    /// does; every other episode doesn't until it is written again, and no lesson carried the outside mark.
    private static func addColumns(_ db: Statements) -> Bool {
        let columns = { (table: String) in Set(db.query("PRAGMA table_info(\(table))", []).compactMap { $0.count > 1 ? $0[1].text : nil }) }
        if !columns("work_episodes").contains("teaches") {
            guard db.run("ALTER TABLE work_episodes ADD COLUMN teaches INTEGER NOT NULL DEFAULT 0", []),
                  db.run("UPDATE work_episodes SET teaches = 1 WHERE taint = 0 AND kind = 'turn'", []) else { return false }
        }
        if !columns("work_lessons").contains("outside") {
            guard db.run("ALTER TABLE work_lessons ADD COLUMN outside INTEGER NOT NULL DEFAULT 0", []) else { return false }
        }
        return true
    }

    // MARK: - The switch

    /// 설정 › 기억 › 한 일에서 배우기: off, nothing is recorded, offered or printed. On by default.
    var isOn: Bool {
        get { tables { db in db.query("SELECT value FROM meta WHERE key = 'work'", []).first?.first?.text != "off" } }
        set {
            _ = tables { db in
                db.run("INSERT INTO meta (key, value) VALUES ('work', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(newValue ? "on" : "off")])
            }
        }
    }

    // MARK: - Episodes

    private static let episodeColumns = "id, at, seconds, kind, asked, key, brain, steps, made, acts, outcome, error, taint, title, tokens, offered, followed, teammate, place, result, compacted, teaches"

    /// Writes a new episode; its id, or nil when it couldn't be written.
    @discardableResult
    func add(_ episode: ArisWorkEpisode) -> Int? {
        tables { db in
            guard db.run("INSERT INTO work_episodes (at, seconds, kind, asked, key, brain, steps, made, acts, outcome, error, taint, title, tokens, offered, followed, teammate, place, result, compacted, teaches) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                      Self.binds(episode)) else { return nil }
            return db.query("SELECT last_insert_rowid()", []).first?.first?.int
        }
    }

    /// Rewrites the episode with that id (a turn that went on after its first answer: agy's relay).
    @discardableResult
    func update(_ episode: ArisWorkEpisode) -> Bool {
        tables(emptiesLog: true) { db in
            db.run("UPDATE work_episodes SET at = ?, seconds = ?, kind = ?, asked = ?, key = ?, brain = ?, steps = ?, made = ?, acts = ?, outcome = ?, error = ?, taint = ?, title = ?, tokens = ?, offered = ?, followed = ?, teammate = ?, place = ?, result = ?, compacted = ?, teaches = ? WHERE id = ?",
                Self.binds(episode) + [.int(episode.id)])
        }
    }

    func episode(id: Int) -> ArisWorkEpisode? {
        tables { db in db.query("SELECT \(Self.episodeColumns) FROM work_episodes WHERE id = ?", [.int(id)]).first.flatMap(Self.episode) }
    }

    /// The episodes, newest first. `tainted`: also the ones from turns that read outside text (the user's own history and
    /// `recall --tainted`); without it only clean ones, by the query itself.
    func episodes(tainted: Bool, limit: Int = 500) -> [ArisWorkEpisode] {
        tables { db in
            db.query("SELECT \(Self.episodeColumns) FROM work_episodes \(tainted ? "" : "WHERE taint = 0 ")ORDER BY at DESC, id DESC LIMIT ?", [.int(limit)])
                .compactMap(Self.episode)
        }
    }

    /// The episodes a turn's context and the lessons are made from: conversation turns that may teach (rule 2), by
    /// the query itself, clean or not.
    func teachingTurns(limit: Int = 500) -> [ArisWorkEpisode] {
        tables { db in
            db.query("SELECT \(Self.episodeColumns) FROM work_episodes WHERE teaches = 1 AND kind = 'turn' AND compacted = 0 ORDER BY at DESC, id DESC LIMIT ?", [.int(limit)])
                .compactMap(Self.episode)
        }.filter(ArisWorkTaintRule.feedsLessons)
    }

    func count() -> Int { tables { db in db.query("SELECT COUNT(*) FROM work_episodes", []).first?.first?.int ?? 0 } }

    /// A job's result landed after its episode was written: its path (shown as ~).
    func setResult(_ path: String, episode id: Int) {
        _ = tables { db in db.run("UPDATE work_episodes SET result = ? WHERE id = ?", [.text(path), .int(id)]) }
    }

    /// The episodes whose every logged change was undone since: marked undone (their lessons lose them: ArisWorkLessons).
    func markUndone(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        tables { db in
            for id in ids { _ = db.run("UPDATE work_episodes SET outcome = 'undone' WHERE id = ? AND outcome = 'done'", [.int(id)]) }
        }
    }

    /// Removes one episode; a lesson that rested on it alone goes with it, the others lose it as evidence.
    @discardableResult
    func deleteEpisode(id: Int) -> Bool {
        tables(emptiesLog: true) { db in
            guard db.run("DELETE FROM work_episodes WHERE id = ?", [.int(id)]) else { return false }
            for row in db.query("SELECT id, evidence FROM work_lessons", []) {
                guard let lesson = row.first?.int, let ids: [Int] = Self.decoded(row[1].text), ids.contains(id) else { continue }
                let left = ids.filter { $0 != id }
                if left.isEmpty {
                    _ = db.run("DELETE FROM work_lessons WHERE id = ?", [.int(lesson)])
                } else {
                    _ = db.run("UPDATE work_lessons SET evidence = ? WHERE id = ?", [.text(Self.encoded(left)), .int(lesson)])
                }
            }
            return true
        }
    }

    // MARK: - Lessons

    private static let lessonColumns = "id, kind, key, asked, works, fails, evidence, confidence, created_at, updated_at, expired, use_count, outside"

    /// The lessons, surest first. `expired`: also the ones a later failure contradicted (the user's list shows none of them).
    func lessons(expired: Bool = false) -> [ArisWorkLesson] {
        tables { db in
            db.query("SELECT \(Self.lessonColumns) FROM work_lessons \(expired ? "" : "WHERE expired = 0 ")ORDER BY confidence DESC, updated_at DESC", [])
                .compactMap(Self.lesson)
        }
    }

    /// Writes a lesson (a new one, or the one with its id again). Refused (nil) unless every episode it is based on is
    /// in the table as a conversation turn that may teach (rule 2: never a job, a hands-free turn or another caller's);
    /// marked outside when any of them read outside content (rule 3), whatever the lesson said.
    @discardableResult
    func save(_ lesson: ArisWorkLesson) -> ArisWorkLesson? {
        tables { db in
            guard !lesson.evidence.isEmpty else { return nil }
            var outside = lesson.outside
            for id in lesson.evidence {
                let row = db.query("SELECT taint, kind, teaches FROM work_episodes WHERE id = ?", [.int(id)]).first
                guard let row, row.count == 3, row[1].text == ArisWorkEpisode.Kind.turn.rawValue, row[2].int == 1 else { return nil }
                if row[0].int != ArisWorkTaint.clean.rawValue { outside = true }
            }
            let binds: [Value] = [.text(lesson.kind.rawValue), .text(lesson.key), .text(lesson.asked), .text(Self.encoded(lesson.works)),
                                  .text(Self.encoded(lesson.fails)), .text(Self.encoded(lesson.evidence)), .real(min(1, max(0, lesson.confidence))),
                                  .real(lesson.createdAt.timeIntervalSince1970), .real(lesson.updatedAt.timeIntervalSince1970),
                                  .int(lesson.expired ? 1 : 0), .int(lesson.useCount), .int(outside ? 1 : 0)]
            var saved = lesson
            saved.outside = outside
            if lesson.id == 0 {
                guard db.run("INSERT INTO work_lessons (kind, key, asked, works, fails, evidence, confidence, created_at, updated_at, expired, use_count, outside) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", binds),
                      let id = db.query("SELECT last_insert_rowid()", []).first?.first?.int else { return nil }
                saved.id = id
                Self.trimLessons(db)
            } else {
                guard db.run("UPDATE work_lessons SET kind = ?, key = ?, asked = ?, works = ?, fails = ?, evidence = ?, confidence = ?, created_at = ?, updated_at = ?, expired = ?, use_count = ?, outside = ? WHERE id = ?",
                          binds + [.int(lesson.id)]) else { return nil }
            }
            return saved
        }
    }

    /// Past `lessonCapacity`: expired ones go first, then the least sure.
    private static func trimLessons(_ db: Statements) {
        let count = db.query("SELECT COUNT(*) FROM work_lessons", []).first?.first?.int ?? 0
        guard count > lessonCapacity else { return }
        _ = db.run("DELETE FROM work_lessons WHERE id IN (SELECT id FROM work_lessons ORDER BY expired DESC, confidence ASC, updated_at ASC LIMIT ?)",
                [.int(count - lessonCapacity)])
    }

    /// The user's 지우기 (or "…잊어"): the lesson is gone from disk; the episodes it was based on stay as history.
    @discardableResult
    func deleteLesson(id: Int) -> Bool {
        tables(emptiesLog: true) { db in
            guard db.query("SELECT COUNT(*) FROM work_lessons WHERE id = ?", [.int(id)]).first?.first?.int == 1 else { return false }
            return db.run("DELETE FROM work_lessons WHERE id = ?", [.int(id)])
        }
    }

    /// The lessons that went into a turn's context.
    func markUsed(_ ids: [Int]) {
        guard !ids.isEmpty else { return }
        tables { db in
            for id in ids { _ = db.run("UPDATE work_lessons SET use_count = use_count + 1 WHERE id = ?", [.int(id)]) }
        }
    }

    /// Every episode and lesson, overwritten on disk. The switch stays as it is.
    @discardableResult
    func deleteAll() -> Bool {
        tables(emptiesLog: true) { db in
            let done = db.run("DELETE FROM work_lessons", []) && db.run("DELETE FROM work_episodes", [])
            if done { _ = db.run("VACUUM", []) }
            return done
        }
    }

    // MARK: - Keeping

    /// Old episodes lose their steps (the stub stays), old stubs and whatever is past the cap go, except what a lesson
    /// still rests on. Returns how many were compacted and how many removed.
    @discardableResult
    func retain(now: Date = Date()) -> (compacted: Int, removed: Int) {
        tables(emptiesLog: true) { db in
            let compactBefore = now.addingTimeInterval(-Self.compactDays * 86_400).timeIntervalSince1970
            let stubBefore = now.addingTimeInterval(-Self.stubDays * 86_400).timeIntervalSince1970
            let fresh = db.query("SELECT COUNT(*) FROM work_episodes WHERE compacted = 0 AND at < ?", [.real(compactBefore)]).first?.first?.int ?? 0
            _ = db.run("UPDATE work_episodes SET steps = '[]', made = '[]', acts = '[]', offered = '[]', compacted = 1 WHERE compacted = 0 AND at < ?", [.real(compactBefore)])
            // What a lesson that is still alive rests on stays, as its stub.
            var held = Set<Int>()
            for row in db.query("SELECT evidence FROM work_lessons WHERE expired = 0", []) {
                held.formUnion((Self.decoded(row.first?.text) as [Int]?) ?? [])
            }
            var removed = 0
            let old = db.query("SELECT id FROM work_episodes WHERE at < ? ORDER BY at", [.real(stubBefore)]).compactMap { $0.first?.int }
            for id in old where !held.contains(id) {
                if db.run("DELETE FROM work_episodes WHERE id = ?", [.int(id)]) { removed += 1 }
            }
            let count = db.query("SELECT COUNT(*) FROM work_episodes", []).first?.first?.int ?? 0
            if count > Self.capacity {
                let oldest = db.query("SELECT id FROM work_episodes ORDER BY at, id", []).compactMap { $0.first?.int }.filter { !held.contains($0) }
                for id in oldest.prefix(count - Self.capacity) {
                    if db.run("DELETE FROM work_episodes WHERE id = ?", [.int(id)]) { removed += 1 }
                }
            }
            return (fresh, removed)
        }
    }

    // MARK: - Rows

    private static func binds(_ e: ArisWorkEpisode) -> [Value] {
        [.real(e.at.timeIntervalSince1970), .real(e.seconds), .text(e.kind.rawValue), .text(e.asked), .text(e.key), .text(e.brain),
         .text(encoded(e.steps)), .text(encoded(e.made)), .text(encoded(e.acts)), .text(e.outcome.rawValue), .text(e.error.rawValue),
         .int(e.taint.rawValue), .text(e.title), e.tokens.map { .int($0) } ?? .null, .text(encoded(e.offered)),
         e.followed.map { .int($0 ? 1 : 0) } ?? .null, .text(e.teammate), .text(e.place), .text(e.result), .int(e.compacted ? 1 : 0), .int(e.teaches ? 1 : 0)]
    }

    private static func episode(_ row: [Value]) -> ArisWorkEpisode? {
        guard row.count == 22, let id = row[0].int, let at = row[1].real, let kind = row[3].text.flatMap(ArisWorkEpisode.Kind.init(rawValue:)),
              let outcome = row[10].text.flatMap(ArisWorkOutcome.init(rawValue:)), let taint = row[12].int.flatMap(ArisWorkTaint.init(rawValue:)) else { return nil }
        return ArisWorkEpisode(id: id, at: Date(timeIntervalSince1970: at), seconds: row[2].real ?? 0, kind: kind, asked: row[4].text ?? "",
                               key: row[5].text ?? "", brain: row[6].text ?? "", steps: decoded(row[7].text) ?? [], made: decoded(row[8].text) ?? [],
                               acts: decoded(row[9].text) ?? [], outcome: outcome, error: ArisWorkError(rawValue: row[11].text ?? "") ?? .other,
                               taint: taint, title: row[13].text ?? "", tokens: row[14].int, offered: decoded(row[15].text) ?? [],
                               followed: row[16].int.map { $0 == 1 }, teammate: row[17].text ?? "", place: row[18].text ?? "",
                               result: row[19].text ?? "", compacted: row[20].int == 1, teaches: row[21].int == 1)
    }

    private static func lesson(_ row: [Value]) -> ArisWorkLesson? {
        guard row.count == 13, let id = row[0].int, let kind = row[1].text.flatMap(ArisWorkLesson.Kind.init(rawValue:)),
              let works: [ArisWorkStep] = decoded(row[4].text), let evidence: [Int] = decoded(row[6].text), let confidence = row[7].real,
              let created = row[8].real, let updated = row[9].real else { return nil }
        return ArisWorkLesson(id: id, kind: kind, key: row[2].text ?? "", asked: row[3].text ?? "", works: works, fails: decoded(row[5].text) ?? [],
                              evidence: evidence, confidence: confidence, createdAt: Date(timeIntervalSince1970: created),
                              updatedAt: Date(timeIntervalSince1970: updated), expired: row[10].int == 1, useCount: row[11].int ?? 0,
                              outside: row[12].int == 1)
    }

    private static func encoded<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }

    private static func decoded<T: Decodable>(_ text: String?) -> T? {
        text.flatMap { try? JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }
}
