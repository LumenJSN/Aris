//
//  ArisMemoryStore.swift
//  aris-agent, aris-tools
//
//  Aris's long-term memory: one SQLite file, memory.sqlite, in ~/.config/aris/aris (0600, the folder 0700), never
//  opened through a link. It holds the typed memories (ArisMemoryRecord), the day notes (the user's own words from clean
//  turns, for the day summary) and the summaries, and two settings: whether to learn on its own (on by default) and
//  whether memory.md was imported. memory.md is imported once and then left where it is as the backup; deleting a
//  memory that came from it drops its line there too, and deleting everything removes it. Deleted rows are
//  overwritten on disk (secure_delete, and the write-ahead log is checkpointed and emptied after every delete, so no
//  old copy stays in it). aris-agent and aris-tools share the file (WAL, a busy timeout). Two more things live in the
//  same file under the same lock: the work memory's tables (ArisWorkStore) and an import's journal and columns
//  (ArisMemoryImportStore).
//  How sure a memory is: the user's 기억해 starts at 0.75, below the core ones every turn gets (0.8), until they says it again
//  or confirms it in 설정 › 기억; picked-out, tool-written and imported ones start at 0.7.
//

import Foundation
import SQLite3

final class ArisMemoryStore: @unchecked Sendable {
    /// Memories kept at most: past it the least useful learned (never said) ones go first.
    static let capacity = 500
    /// Day notes per day, and how long notes and summaries stay.
    static let notesPerDay = 60
    static let noteDays = 3
    static let summaryDays = 120
    /// Starting confidences (ArisMemoryRecall's core needs 0.8).
    static let saidConfidence = 0.75
    static let learnedConfidence = 0.7
    static let toolConfidence = 0.7
    static let confirmedConfidence = 1.0
    /// Said a second time: at least this sure.
    static let repeatedConfidence = 0.85

    let folder: URL
    var file: URL { folder.appendingPathComponent("memory.sqlite") }
    var backup: URL { folder.appendingPathComponent("memory.md") }

    private let lock = NSLock()
    private var db: OpaquePointer?

    private static let registry = NSLock()
    nonisolated(unsafe) private static var stores: [String: ArisMemoryStore] = [:]

    /// The store in `folder`, one per folder in this process.
    static func at(_ folder: URL) -> ArisMemoryStore {
        registry.withLock {
            if let store = stores[folder.standardizedFileURL.path] { return store }
            let store = ArisMemoryStore(folder: folder)
            stores[folder.standardizedFileURL.path] = store
            return store
        }
    }

    static var live: ArisMemoryStore {
        at(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris", isDirectory: true))
    }

    private init(folder: URL) { self.folder = folder }

    deinit { if let db { sqlite3_close_v2(db) } }

    // MARK: - Memories

    func all() -> [ArisMemoryRecord] {
        query("SELECT id, kind, subject, text, source, turn_at, confidence, created_at, updated_at, last_used_at, use_count FROM memories ORDER BY updated_at DESC")
            .compactMap(Self.record)
    }

    func count() -> Int { query("SELECT COUNT(*) FROM memories").first?.first?.int ?? 0 }

    enum Outcome: Equatable {
        case added(ArisMemoryRecord)
        case updated(ArisMemoryRecord, was: String)
        case duplicate(ArisMemoryRecord)
        /// A credential's value (a password, code, card number or key): never written (holdsBack).
        case secret
        case empty
        /// The file couldn't be written.
        case failed
    }

    /// The most a memory from `source` starts with.
    static func ceiling(_ source: ArisMemorySource) -> Double {
        switch source {
        case .said: saidConfidence
        case .learned: learnedConfidence
        case .tool, .imported: toolConfidence
        }
    }

    /// What isn't written. The user's own 기억해 (`said`), and a brain's memory tool, which only runs on their words or their yes
    /// to its card (`tool`), hold back only what is plainly a credential's value (ArisMemoryText.isCredential): his phone
    /// numbers, student number and height are his to keep. What Aris learns or imports on its own stays strict
    /// (ArisMemoryText.isSecret: any long number, any word that names a secret).
    static func holdsBack(_ text: String, source: ArisMemorySource) -> Bool {
        switch source {
        case .said, .tool: ArisMemoryText.isCredential(text)
        case .learned, .imported: ArisMemoryText.isSecret(text)
        }
    }

    /// What the user is told when their 기억해 was a credential: that it wasn't kept, and why (memory is a plain file).
    static func secretLine(korean: Bool) -> String {
        korean ? "비밀번호나 API 키, 카드 번호처럼 보여서 기억에 넣지 않았어요. 기억은 암호화하지 않은 파일이라, 그런 건 암호 앱이나 키체인에 두는 게 안전해요."
               : "That looks like a password, a key or a card number, so I didn't put it in memory: memory is a plain file. A password manager or the Keychain is the safe place for it."
    }

    /// Writes `candidate` (merged with what is there: ArisMemoryMerge) from a turn at `turnAt`.
    @discardableResult
    func remember(_ candidate: ArisMemoryCandidate, source: ArisMemorySource, turnAt: Date, now: Date = Date()) -> Outcome {
        lock.withLock { rememberLocked(candidate, source: source, turnAt: turnAt, now: now) }
    }

    private func rememberLocked(_ candidate: ArisMemoryCandidate, source: ArisMemorySource, turnAt: Date, now: Date) -> Outcome {
        let text = ArisMemoryText.cleaned(candidate.text)
        guard !ArisMemoryText.normalized(text).isEmpty else { return .empty }
        guard !Self.holdsBack(text, source: source), !Self.holdsBack(candidate.subject, source: source) else { return .secret }
        let subject = String(ArisMemoryText.cleaned(candidate.subject).prefix(40))
        let confidence = min(Self.ceiling(source), max(0, candidate.confidence))
        let clean = ArisMemoryCandidate(kind: candidate.kind, subject: subject, text: text, confidence: confidence)
        let existing = allLocked()
        switch ArisMemoryMerge.plan(clean, existing: existing) {
        case .duplicate(let id):
            guard var old = existing.first(where: { $0.id == id }) else { return .failed }
            // The user saying it again confirms it; anything else only touches it.
            if source == .said {
                old.confidence = min(1, max(old.confidence + 0.1, Self.repeatedConfidence))
                old.source = .said
            }
            old.updatedAt = now
            old.turnAt = max(old.turnAt, turnAt)
            guard runLocked("UPDATE memories SET confidence = ?, source = ?, updated_at = ?, turn_at = ? WHERE id = ?",
                            [.real(old.confidence), .text(old.source.rawValue), .real(now.timeIntervalSince1970), .real(old.turnAt.timeIntervalSince1970),
                             .text(id)]) else { return .failed }
            return .duplicate(old)
        case .update(let id):
            guard var old = existing.first(where: { $0.id == id }) else { return .failed }
            let was = old.text
            old.text = clean.text
            if !clean.subject.isEmpty { old.subject = clean.subject }
            old.kind = clean.kind
            // The new words are where it comes from now, as sure as their source.
            old.source = source
            old.confidence = clean.confidence
            old.turnAt = turnAt
            old.updatedAt = now
            guard runLocked("UPDATE memories SET kind = ?, subject = ?, text = ?, source = ?, turn_at = ?, confidence = ?, updated_at = ? WHERE id = ?",
                            [.text(old.kind.rawValue), .text(old.subject), .text(old.text), .text(old.source.rawValue), .real(turnAt.timeIntervalSince1970),
                             .real(old.confidence), .real(now.timeIntervalSince1970), .text(id)]) else { return .failed }
            return .updated(old, was: was)
        case .insert:
            let record = ArisMemoryRecord(id: UUID().uuidString, kind: clean.kind, subject: clean.subject, text: clean.text, source: source, turnAt: turnAt,
                                          confidence: clean.confidence, createdAt: now, updatedAt: now, lastUsedAt: nil, useCount: 0)
            guard insertLocked(record, origin: source == .imported ? candidate.text : nil) else { return .failed }
            trimLocked(now: now)
            return .added(record)
        }
    }

    /// The user's one-tap 확인 in 설정 › 기억: as sure as can be. False when it isn't there.
    @discardableResult
    func confirm(id: String, now: Date = Date()) -> Bool {
        lock.withLock {
            guard queryLocked("SELECT COUNT(*) FROM memories WHERE id = ?", [.text(id)]).first?.first?.int == 1 else { return false }
            return runLocked("UPDATE memories SET confidence = ?, updated_at = ? WHERE id = ?", [.real(Self.confirmedConfidence), .real(now.timeIntervalSince1970), .text(id)])
        }
    }

    /// Removes one memory (and its memory.md line, for an imported one). False when it wasn't there.
    @discardableResult
    func delete(id: String) -> Bool { !delete(ids: [id]).isEmpty }

    /// Removes these memories (their memory.md lines too); the ids removed.
    @discardableResult
    func delete(ids: [String]) -> [String] {
        lock.withLock {
            var gone: [String] = []
            for id in ids {
                let row = queryLocked("SELECT text, origin FROM memories WHERE id = ?", [.text(id)]).first
                guard let text = row?.first?.text, runLocked("DELETE FROM memories WHERE id = ?", [.text(id)]) else { continue }
                // What an import's undo kept of it goes too (ArisMemoryImportStore; nothing happens when no import ever ran).
                _ = runLocked("DELETE FROM import_journal WHERE memory = ?", [.text(id)])
                dropBackupLines(like: text)
                if let origin = row?[1].text { dropBackupLines(like: origin) }
                gone.append(id)
            }
            if !gone.isEmpty { checkpointLocked() }
            return gone
        }
    }

    /// The memories whose subject or text contains `words` (ArisMemoryRecall.containing): what forget would remove.
    func matching(_ words: String) -> [ArisMemoryRecord] { ArisMemoryRecall.containing(all(), words: words) }

    /// The memories that hold every word of `words` loosely (ArisMemoryRecall.overlapping): asked about, never removed at once.
    func overlapping(_ words: String) -> [ArisMemoryRecord] { ArisMemoryRecall.overlapping(all(), words: words) }

    /// Every memory, day note and summary, and the memory.md backup. The settings (learning on or off) stay.
    @discardableResult
    func deleteAll() -> Bool {
        lock.withLock {
            let done = runLocked("DELETE FROM memories") && runLocked("DELETE FROM day_notes") && runLocked("DELETE FROM day_summaries")
            // And what an import's undo kept of the memories it changed (ArisMemoryImportStore).
            _ = runLocked("DELETE FROM import_journal")
            if done { _ = runLocked("VACUUM") }
            checkpointLocked()
            ArisNoFollow.removeFile(backup)
            return done
        }
    }

    /// The memories that went into a turn because they were relevant.
    func markUsed(_ ids: [String], at now: Date) {
        guard !ids.isEmpty else { return }
        lock.withLock {
            for id in ids {
                _ = runLocked("UPDATE memories SET last_used_at = ?, use_count = use_count + 1 WHERE id = ?", [.real(now.timeIntervalSince1970), .text(id)])
            }
        }
    }

    // MARK: - Settings

    /// Whether Aris picks memories out of clean turns on its own (설정 › 기억 › 자동으로 기억하기). On by default.
    var learnsOnItsOwn: Bool {
        get { meta("auto") != "off" }
        set { setMeta("auto", newValue ? "on" : "off") }
    }

    // MARK: - Day notes and summaries

    /// The user's own words from one clean turn, for that day's summary.
    func addNote(_ words: String, at date: Date, calendar: Calendar = .current) {
        let text = ArisMemoryText.cleaned(words)
        guard text.count >= 4, !ArisMemoryText.isSecret(text) else { return }
        let day = ArisMemoryText.day(date, calendar: calendar)
        lock.withLock {
            let today = queryLocked("SELECT COUNT(*) FROM day_notes WHERE day = ?", [.text(day)]).first?.first?.int ?? 0
            guard today < Self.notesPerDay else { return }
            _ = runLocked("INSERT INTO day_notes (day, at, words) VALUES (?, ?, ?)", [.text(day), .real(date.timeIntervalSince1970), .text(text)])
        }
    }

    func notes(day: String) -> [String] {
        query("SELECT words FROM day_notes WHERE day = ? ORDER BY at", [.text(day)]).compactMap { $0.first?.text }
    }

    /// Days before `today` with notes and no summary yet, oldest first.
    func daysToSummarize(before today: String) -> [String] {
        query("SELECT DISTINCT day FROM day_notes WHERE day < ? AND day NOT IN (SELECT day FROM day_summaries) ORDER BY day", [.text(today)])
            .compactMap { $0.first?.text }
    }

    func summary(day: String) -> String? {
        query("SELECT summary FROM day_summaries WHERE day = ?", [.text(day)]).first?.first?.text
    }

    func setSummary(_ text: String, day: String, now: Date = Date()) {
        lock.withLock {
            _ = runLocked("INSERT INTO day_summaries (day, summary, updated_at) VALUES (?, ?, ?) ON CONFLICT(day) DO UPDATE SET summary = excluded.summary, updated_at = excluded.updated_at",
                          [.text(day), .text(String(text.prefix(600))), .real(now.timeIntervalSince1970)])
        }
    }

    /// Notes of summarized days older than `noteDays`, and summaries older than `summaryDays`, go.
    func prune(today: String, now: Date, calendar: Calendar = .current) {
        let noteCut = ArisMemoryText.day(now.addingTimeInterval(-Double(Self.noteDays) * 86_400), calendar: calendar)
        let summaryCut = ArisMemoryText.day(now.addingTimeInterval(-Double(Self.summaryDays) * 86_400), calendar: calendar)
        lock.withLock {
            _ = runLocked("DELETE FROM day_notes WHERE day < ? AND day IN (SELECT day FROM day_summaries)", [.text(noteCut)])
            _ = runLocked("DELETE FROM day_notes WHERE day < ?", [.text(summaryCut)])
            _ = runLocked("DELETE FROM day_summaries WHERE day < ?", [.text(summaryCut)])
        }
    }

    // MARK: - memory.md, once

    /// Imports memory.md's "- fact (yyyy-MM-dd)" lines once (they keep their dates), leaving the file as the backup.
    /// One transaction that takes the write lock first (BEGIN IMMEDIATE), so of the agent and aris-tools only one ever
    /// imports; a memory.md that is a link (or not a file) is left alone and not marked done. Returns how many came in.
    @discardableResult
    func importBackupIfNeeded(now: Date = Date()) -> Int {
        lock.withLock {
            guard openLocked() != nil, metaLocked("imported") == nil else { return 0 }
            var info = stat()
            let present = lstat(backup.path, &info) == 0
            guard !present || ArisNoFollow.isFile(backup) else { return 0 }
            guard runLocked("BEGIN IMMEDIATE") else { return 0 }
            guard metaLocked("imported") == nil else {
                _ = runLocked("ROLLBACK")
                return 0
            }
            var imported = 0
            for (fact, date) in Self.backupFacts(present ? ArisNoFollow.text(backup) ?? "" : "") {
                let candidate = ArisMemoryCandidate(kind: ArisMemoryKind.guess(fact), subject: "", text: fact, confidence: Self.toolConfidence)
                if case .added = rememberLocked(candidate, source: .imported, turnAt: date ?? now, now: date ?? now) { imported += 1 }
            }
            guard setMetaLocked("imported", ArisMemoryText.day(now)), runLocked("COMMIT") else {
                _ = runLocked("ROLLBACK")
                return 0
            }
            return imported
        }
    }

    /// memory.md's facts and their dates: "- 커피 좋아함 (2026-11-01)".
    static func backupFacts(_ text: String) -> [(String, Date?)] {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("-") { line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            var date: Date?
            if let match = line.range(of: #"\s*\((\d{4}-\d{2}-\d{2})\)$"#, options: .regularExpression) {
                date = parser.date(from: String(line[match]).trimmingCharacters(in: CharacterSet(charactersIn: " ()")))
                line.removeSubrange(match)
            }
            let fact = line.trimmingCharacters(in: .whitespaces)
            return fact.isEmpty ? nil : (fact, date)
        }
    }

    /// The memory lines as memory.md wrote them (the data export).
    func exportText() -> String {
        all().reversed().map { "- \($0.line) (\(ArisMemoryText.day($0.turnAt)))" }.joined(separator: "\n")
    }

    /// Called with `lock` held: memory.md's lines close to `text` go (the backup forgets what the user deleted).
    private func dropBackupLines(like text: String) {
        guard ArisNoFollow.isFile(backup), let old = ArisNoFollow.text(backup) else { return }
        let lines = old.split(whereSeparator: \.isNewline).map(String.init)
        let kept = lines.filter { line in
            guard let fact = Self.backupFacts(line).first?.0 else { return true }
            return ArisMemoryText.similarity(fact, text) < ArisMemoryMerge.duplicateAt
        }
        guard kept.count != lines.count else { return }
        if kept.isEmpty {
            ArisNoFollow.removeFile(backup)
            return
        }
        try? ArisNoFollow.replace(backup, with: Data((kept.joined(separator: "\n") + "\n").utf8))
    }

    // MARK: - SQLite

    enum Value: Equatable {
        case text(String), real(Double), int(Int), null

        var text: String? { if case .text(let s) = self { return s }; return nil }
        var real: Double? {
            switch self {
            case .real(let d): return d
            case .int(let i): return Double(i)
            default: return nil
            }
        }
        var int: Int? {
            switch self {
            case .int(let i): return i
            case .real(let d): return Int(d)
            default: return nil
            }
        }
    }

    private static let schema = """
        CREATE TABLE IF NOT EXISTS memories (id TEXT PRIMARY KEY, kind TEXT NOT NULL, subject TEXT NOT NULL DEFAULT '', text TEXT NOT NULL,
            source TEXT NOT NULL, turn_at REAL NOT NULL, confidence REAL NOT NULL, created_at REAL NOT NULL, updated_at REAL NOT NULL,
            last_used_at REAL, use_count INTEGER NOT NULL DEFAULT 0, origin TEXT);
        CREATE TABLE IF NOT EXISTS day_notes (id INTEGER PRIMARY KEY AUTOINCREMENT, day TEXT NOT NULL, at REAL NOT NULL, words TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS day_notes_day ON day_notes(day);
        CREATE TABLE IF NOT EXISTS day_summaries (day TEXT PRIMARY KEY, summary TEXT NOT NULL, updated_at REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        PRAGMA user_version = 2;
        """

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Called with `lock` held (or from `open()`). The folder must be a real folder (made 0700 if missing) and the file
    /// a real file (made 0600): never through a link.
    private func openLocked() -> OpaquePointer? {
        if let db { return db }
        let manager = FileManager.default
        if !manager.fileExists(atPath: folder.path) {
            try? manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        guard ArisNoFollow.isDirectory(folder), Self.tighten(folder.path, to: 0o700, directory: true) else {
            FileHandle.standardError.write(Data("aris: memory folder isn't a real folder; memory is off\n".utf8))
            return nil
        }
        if !manager.fileExists(atPath: file.path) {
            let fd = Darwin.open(file.path, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0o600)
            if fd >= 0 { close(fd) }
        }
        guard ArisNoFollow.isFile(file), Self.tighten(file.path, to: 0o600, directory: false) else {
            FileHandle.standardError.write(Data("aris: memory.sqlite isn't a real file; memory is off\n".utf8))
            return nil
        }
        // SQLite's no-follow refuses a link anywhere in the path (/var is one): the folder and the file were just checked
        // not to be links themselves, so the path is opened through its parents resolved.
        guard let real = realpath(folder.path, nil) else { return nil }
        let path = String(cString: real) + "/" + file.lastPathComponent
        free(real)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX | SQLITE_OPEN_NOFOLLOW
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            FileHandle.standardError.write(Data("aris: couldn't open memory.sqlite (\(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "no handle"))\n".utf8))
            if let handle { sqlite3_close_v2(handle) }
            return nil
        }
        sqlite3_busy_timeout(handle, 3_000)
        for pragma in ["PRAGMA journal_mode = WAL", "PRAGMA secure_delete = ON", "PRAGMA synchronous = NORMAL"] {
            sqlite3_exec(handle, pragma, nil, nil, nil)
        }
        guard sqlite3_exec(handle, Self.schema, nil, nil, nil) == SQLITE_OK else {
            FileHandle.standardError.write(Data("aris: memory.sqlite schema failed: \(String(cString: sqlite3_errmsg(handle)))\n".utf8))
            sqlite3_close_v2(handle)
            return nil
        }
        // Made before origin existed: add it (an error here only means it is there).
        sqlite3_exec(handle, "ALTER TABLE memories ADD COLUMN origin TEXT", nil, nil, nil)
        db = handle
        return handle
    }

    private func query(_ sql: String, _ binds: [Value] = []) -> [[Value]] { lock.withLock { queryLocked(sql, binds) } }

    private func queryLocked(_ sql: String, _ binds: [Value] = []) -> [[Value]] {
        guard let db = openLocked(), let statement = prepare(db, sql, binds) else { return [] }
        defer { sqlite3_finalize(statement) }
        var rows: [[Value]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: return .int(Int(sqlite3_column_int64(statement, column)))
                case SQLITE_FLOAT: return .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: return .text(String(cString: sqlite3_column_text(statement, column)))
                default: return .null
                }
            })
        }
        return rows
    }

    private func runLocked(_ sql: String, _ binds: [Value] = []) -> Bool {
        guard let db = openLocked(), let statement = prepare(db, sql, binds) else { return false }
        defer { sqlite3_finalize(statement) }
        let status = sqlite3_step(statement)
        if status != SQLITE_DONE && status != SQLITE_ROW {
            FileHandle.standardError.write(Data("aris: memory write failed: \(String(cString: sqlite3_errmsg(db)))\n".utf8))
            return false
        }
        return true
    }

    private func prepare(_ db: OpaquePointer, _ sql: String, _ binds: [Value]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        for (index, value) in binds.enumerated() {
            let slot = Int32(index + 1)
            switch value {
            case .text(let s): sqlite3_bind_text(statement, slot, s, -1, Self.transient)
            case .real(let d): sqlite3_bind_double(statement, slot, d)
            case .int(let i): sqlite3_bind_int64(statement, slot, Int64(i))
            case .null: sqlite3_bind_null(statement, slot)
            }
        }
        return statement
    }

    private func allLocked() -> [ArisMemoryRecord] {
        queryLocked("SELECT id, kind, subject, text, source, turn_at, confidence, created_at, updated_at, last_used_at, use_count FROM memories ORDER BY updated_at DESC")
            .compactMap(Self.record)
    }

    /// `origin`: an imported memory's line as memory.md had it (its backup line goes when it is deleted, reworded or not).
    private func insertLocked(_ r: ArisMemoryRecord, origin: String? = nil) -> Bool {
        runLocked("INSERT INTO memories (id, kind, subject, text, source, turn_at, confidence, created_at, updated_at, last_used_at, use_count, origin) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  [.text(r.id), .text(r.kind.rawValue), .text(r.subject), .text(r.text), .text(r.source.rawValue), .real(r.turnAt.timeIntervalSince1970),
                   .real(r.confidence), .real(r.createdAt.timeIntervalSince1970), .real(r.updatedAt.timeIntervalSince1970),
                   r.lastUsedAt.map { .real($0.timeIntervalSince1970) } ?? .null, .int(r.useCount), origin.map { .text($0) } ?? .null])
    }

    /// Past `capacity`: learned memories go first, the least weighty (ArisMemoryRecall.weight) of them; then the rest.
    private func trimLocked(now: Date) {
        let all = allLocked()
        guard all.count > Self.capacity else { return }
        let order = all.sorted { a, b in
            let aLearned = a.source == .learned, bLearned = b.source == .learned
            if aLearned != bLearned { return aLearned }
            return ArisMemoryRecall.weight(a, now: now) < ArisMemoryRecall.weight(b, now: now)
        }
        for record in order.prefix(all.count - Self.capacity) { _ = runLocked("DELETE FROM memories WHERE id = ?", [.text(record.id)]) }
    }

    private func meta(_ key: String) -> String? { lock.withLock { metaLocked(key) } }

    private func metaLocked(_ key: String) -> String? { queryLocked("SELECT value FROM meta WHERE key = ?", [.text(key)]).first?.first?.text }

    private func setMeta(_ key: String, _ value: String) { lock.withLock { _ = setMetaLocked(key, value) } }

    private func setMetaLocked(_ key: String, _ value: String) -> Bool {
        runLocked("INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)])
    }

    /// Copies the write-ahead log into the file and empties it, so a deleted memory's old pages aren't left in the log.
    private func checkpointLocked() { _ = runLocked("PRAGMA wal_checkpoint(TRUNCATE)") }

    /// The work memory's tables live in this same file (ArisWorkStore): its statements run with this store's lock
    /// held, on the file as it is always opened here (never through a link, 0600, WAL, secure_delete). `emptiesLog`:
    /// something was deleted, so the write-ahead log is emptied afterwards as after every delete here.
    func locked<T>(emptiesLog: Bool = false, _ work: (Statements) -> T) -> T {
        lock.withLock {
            let result = work(Statements(store: self))
            if emptiesLog { checkpointLocked() }
            return result
        }
    }

    /// This store's own statements, for `locked`.
    struct Statements {
        fileprivate let store: ArisMemoryStore
        func query(_ sql: String, _ binds: [Value] = []) -> [[Value]] { store.queryLocked(sql, binds) }
        func run(_ sql: String, _ binds: [Value] = []) -> Bool { store.runLocked(sql, binds) }
    }

    /// Sets a real file's or folder's mode through a descriptor opened without following a link; false for a link.
    private static func tighten(_ path: String, to mode: mode_t, directory: Bool) -> Bool {
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return fchmod(fd, mode) == 0
    }

    private static func record(_ row: [Value]) -> ArisMemoryRecord? {
        guard row.count == 11, let id = row[0].text, let kind = row[1].text.flatMap(ArisMemoryKind.init(rawValue:)),
              let text = row[3].text, let source = row[4].text.flatMap(ArisMemorySource.init(rawValue:)),
              let turnAt = row[5].real, let confidence = row[6].real, let created = row[7].real, let updated = row[8].real else { return nil }
        return ArisMemoryRecord(id: id, kind: kind, subject: row[2].text ?? "", text: text, source: source, turnAt: Date(timeIntervalSince1970: turnAt),
                                confidence: confidence, createdAt: Date(timeIntervalSince1970: created), updatedAt: Date(timeIntervalSince1970: updated),
                                lastUsedAt: row[9].real.map(Date.init(timeIntervalSince1970:)), useCount: row[10].int ?? 0)
    }
}
