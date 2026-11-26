//
//  ArisScheduleStore.swift
//  aris-agent, aris-tools
//
//  Where scheduled work is kept: ~/.config/aris/aris/schedules.json (the jobs) and inbox.jsonl (what they produced,
//  until the app has told the user). Both are 0600 in a 0700 folder, replaced whole (written beside, then renamed over),
//  never read or written through a link (the file or its folder), and read entry by entry so one damaged entry never
//  hides the rest. A file that isn't the user's own, or that others could read or write, counts for nothing.
//

import Foundation

/// Private files in Aris's folder: one writer at a time, replaced atomically, never through a link.
enum ArisPrivateFile {
    /// The folder 0700 (created that way; an existing one is narrowed). False when it is a link or not a folder:
    /// nothing is then read or written in it.
    @discardableResult
    static func prepareFolder(_ folder: URL) -> Bool {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard isRealFolder(folder) else { return false }
        chmod(folder.path, 0o700)
        return true
    }

    /// A folder itself, not a link to one.
    static func isRealFolder(_ folder: URL) -> Bool {
        var info = stat()
        return lstat(folder.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// The user's own file that nobody else may read or write.
    static func isPrivate(uid: uid_t, mode: mode_t) -> Bool {
        uid == getuid() && mode & 0o077 == 0
    }

    /// The file's bytes; nil when it is missing, a link (or in a linked folder), not a regular file, not the user's, or open
    /// to others.
    static func read(_ file: URL) -> Data? {
        guard isRealFolder(file.deletingLastPathComponent()) else { return nil }
        let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, isPrivate(uid: info.st_uid, mode: info.st_mode & 0o777) else {
            return nil
        }
        return try? handle.readToEnd() ?? Data()
    }

    /// Writes `data` beside the file (0600, a new file that can't be a link), flushes it and renames it over the file.
    static func write(_ data: Data, to file: URL) throws {
        let folder = file.deletingLastPathComponent()
        guard prepareFolder(folder) else { throw ArisScheduleError(message: "\(folder.lastPathComponent) isn't a plain folder") }
        let temp = folder.appendingPathComponent(".\(file.lastPathComponent)-\(UUID().uuidString).tmp")
        let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ArisScheduleError(message: "couldn't write \(file.lastPathComponent): \(String(cString: strerror(errno)))") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            unlink(temp.path)
            throw ArisScheduleError(message: "couldn't write \(file.lastPathComponent): \(error.localizedDescription)")
        }
        guard rename(temp.path, file.path) == 0 else {
            let reason = String(cString: strerror(errno))
            unlink(temp.path)
            throw ArisScheduleError(message: "couldn't save \(file.lastPathComponent): \(reason)")
        }
    }

    /// aris-tools and the agent both write these files: one at a time (`<file>.lock`).
    static func withLock<T>(_ file: URL, _ work: () throws -> T) rethrows -> T {
        // A linked folder: no lock is taken there (nothing will be read or written in it either).
        guard prepareFolder(file.deletingLastPathComponent()) else { return try work() }
        let descriptor = open(file.path + ".lock", O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return try work() }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN); close(descriptor) }
        return try work()
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func folder(home: String) -> URL {
        URL(fileURLWithPath: home).appendingPathComponent(".config/aris/aris")
    }

    // MARK: - Entries that can't be read

    /// Entries a .bad file keeps at most (the newest).
    static let badLimit = 200

    /// `<file>.bad`: where `file`'s entries that can't be read are kept.
    static func badFile(_ file: URL) -> URL { URL(fileURLWithPath: file.path + ".bad") }

    /// Keeps `entries` aside in `<file>.bad` (a JSON list, 0600, each entry once), so a store rewritten without them
    /// loses nothing. How many were new there (0: all were kept before, so the user was told already); nil when they
    /// couldn't be kept (the .bad file isn't the user's private file or a list, or couldn't be written).
    static func setAside(_ entries: [Any], beside file: URL) -> Int? {
        let bad = badFile(file)
        return withLock(bad) { () -> Int? in
            var kept: [Any] = []
            if let data = read(bad) {
                guard data.isEmpty || ((try? JSONSerialization.jsonObject(with: data)) as? [Any]) != nil else { return nil }
                kept = data.isEmpty ? [] : ((try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? [])
            } else {
                var info = stat()
                if lstat(bad.path, &info) == 0 { return nil }
            }
            func key(_ entry: Any) -> Data? { try? JSONSerialization.data(withJSONObject: [entry], options: [.sortedKeys]) }
            var seen = Set(kept.compactMap(key)), added = 0
            for entry in entries {
                guard let entryKey = key(entry) else { return nil }
                if seen.insert(entryKey).inserted {
                    kept.append(entry)
                    added += 1
                }
            }
            guard added > 0 else { return 0 }
            guard let data = try? JSONSerialization.data(withJSONObject: Array(kept.suffix(badLimit)), options: [.sortedKeys, .prettyPrinted]),
                  (try? write(data, to: bad)) != nil else { return nil }
            try? FileHandle.standardError.write(contentsOf: Data("aris: \(added) unreadable entr\(added == 1 ? "y" : "ies") of \(file.lastPathComponent) kept in \(bad.lastPathComponent)\n".utf8))
            return added
        }
    }

    /// Tells the user once, in the inbox beside `file` (said when the app is there), that `count` of its entries (`what`:
    /// "예약", "스킬") were kept aside. In Korean, as the scheduler's other notes with no words of his to go by.
    static func reportSetAside(_ count: Int, what: String, file: URL) {
        let name = file.lastPathComponent
        let text = "읽을 수 없는 \(what) 기록 \(count)개를 \(name).bad 파일에 따로 보관했어요. 지우지 않았으니, 필요하면 다시 만들거나 그 파일을 확인해 주세요."
        ArisInbox.append(ArisInboxEntry(id: UUID(), date: Date(), kind: .note, schedule: nil, title: "읽을 수 없는 \(what) 기록", text: text, file: nil, confirm: nil),
                         file: file.deletingLastPathComponent().appendingPathComponent("inbox.jsonl"))
    }
}

// MARK: - Schedules

enum ArisScheduleStore {
    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("schedules.json")
    }

    /// The jobs; a damaged entry is kept aside (schedules.json.bad, reported once) and skipped, and a missing or
    /// unreadable store is empty.
    static func load(file: URL) -> [ArisScheduledJob] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return read(data, file: file).jobs
    }

    /// Why the store that is there can't be used (it isn't the user's private file, it is a link or sits in a linked
    /// folder): every schedule stops then, and the scheduler says so in the inbox. Nil when it is fine or not there.
    static func refusal(file: URL) -> String? {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { return nil }
        guard ArisPrivateFile.read(file) == nil else { return nil }
        if info.st_mode & S_IFMT == S_IFLNK { return "it is a link" }
        if !ArisPrivateFile.isRealFolder(file.deletingLastPathComponent()) { return "its folder is a link" }
        if info.st_uid != getuid() { return "it belongs to another user" }
        return String(format: "others may read or change it (mode %o)", info.st_mode & 0o777)
    }

    /// The jobs to change, and the entries kept as they are (written by a newer Aris): like `load`, but a store that
    /// is there and isn't the user's private file (or sits in a linked folder) is refused, never replaced by a new list.
    private static func loadForChange(file: URL) throws -> (jobs: [ArisScheduledJob], newer: [Any]) {
        if let data = ArisPrivateFile.read(file) {
            let found = read(data, file: file)
            guard found.writable else { throw ArisScheduleError(message: "\(file.lastPathComponent) can't be read and couldn't be kept aside: left as it is") }
            return (found.jobs, found.newer)
        }
        var info = stat()
        guard lstat(file.path, &info) != 0, ArisPrivateFile.isRealFolder(file.deletingLastPathComponent()) else {
            try? FileHandle.standardError.write(contentsOf: Data("aris: \(file.path) isn't a private file of yours: left as it is\n".utf8))
            throw ArisScheduleError(message: "the schedule store isn't private (check \(file.lastPathComponent)'s owner and permissions)")
        }
        return ([], [])
    }

    /// The store's entries: the jobs this build reads; `newer`, entries of a newer store version (kept in the file as
    /// they are); `bad`, entries that can't be read (or the whole file, when it isn't a list).
    static func entries(in data: Data) -> (jobs: [ArisScheduledJob], newer: [Any], bad: [Any]) {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            let blank = data.allSatisfy { [0x20, 0x0A, 0x0D, 0x09].contains($0) }
            return ([], [], blank ? [] : [["unreadable store": String(decoding: data.prefix(1_048_576), as: UTF8.self)]])
        }
        var jobs: [ArisScheduledJob] = [], newer: [Any] = [], bad: [Any] = []
        for entry in entries {
            if let object = entry as? [String: Any], let version = object["version"] as? Int, version > ArisSchedule.storeVersion {
                newer.append(entry)
                continue
            }
            guard JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry),
                  let job = try? ArisPrivateFile.decoder.decode(ArisScheduledJob.self, from: one) else {
                bad.append(entry)
                continue
            }
            jobs.append(job)
        }
        return (jobs, newer, bad)
    }

    /// `entries(in:)`, with the unreadable ones kept aside in `<file>.bad` and the user told once, in the inbox.
    /// `writable`: false when the store must not be written over (it isn't a list, and couldn't be kept aside).
    private static func read(_ data: Data, file: URL) -> (jobs: [ArisScheduledJob], newer: [Any], writable: Bool) {
        let found = entries(in: data)
        guard !found.bad.isEmpty else { return (found.jobs, found.newer, true) }
        // Not kept aside (the .bad file couldn't be written): they stay in the store as they are, never dropped, and a
        // store that isn't a list at all is never written over.
        guard let kept = ArisPrivateFile.setAside(found.bad, beside: file) else {
            let list = (try? JSONSerialization.jsonObject(with: data)) is [Any]
            return (found.jobs, found.newer + (list ? found.bad : []), list)
        }
        if kept > 0 { ArisPrivateFile.reportSetAside(kept, what: "예약", file: file) }
        return (found.jobs, found.newer, true)
    }

    /// Adds a job; refused past ArisSchedule.maxSchedules (one-time jobs that already ran don't count, and leave).
    static func add(_ job: ArisScheduledJob, file: URL) throws {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            let jobs = ArisSchedule.pruned(stored.jobs)
            guard jobs.filter(ArisSchedule.isEnabled).count < ArisSchedule.maxSchedules else {
                throw ArisScheduleError(message: "there are already \(ArisSchedule.maxSchedules) schedules: remove one first")
            }
            guard !jobs.contains(where: { $0.id == job.id }) else { throw ArisScheduleError(message: "that schedule is already there") }
            try save(jobs + [job], newer: stored.newer, file: file)
        }
    }

    /// Puts a removed job back (undoing a remove): its next run counted from `now`, nothing running or parked. Refused
    /// when it would never run again, is already there, or the cap is reached.
    static func restore(_ job: ArisScheduledJob, now: Date, calendar: Calendar, file: URL) throws {
        guard let next = ArisSchedule.next(job.rule, after: now, calendar: calendar) else {
            throw ArisScheduleError(message: "that schedule's time has passed")
        }
        var copy = job
        copy.nextRun = next
        copy.runningSince = nil
        copy.parked = []
        copy.tries = nil
        copy.stopped = nil
        try add(copy, file: file)
    }

    /// Removes job `id` and returns it; throws when there is none.
    @discardableResult
    static func remove(id: UUID, file: URL) throws -> ArisScheduledJob {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            guard let found = stored.jobs.first(where: { $0.id == id }) else { throw ArisScheduleError(message: "no schedule with that id") }
            try save(stored.jobs.filter { $0.id != id }, newer: stored.newer, file: file)
            return found
        }
    }

    /// Changes the jobs under the lock; the file is written only when something changed. The jobs after, or nil when
    /// the change couldn't be saved (nothing that depends on it may happen then).
    @discardableResult
    static func update(file: URL, _ change: ([ArisScheduledJob]) -> [ArisScheduledJob]) -> [ArisScheduledJob]? {
        ArisPrivateFile.withLock(file) {
            guard let stored = try? loadForChange(file: file) else { return nil }
            let before = stored.jobs
            let after = change(before)
            guard after != before else { return after }
            do { try save(after, newer: stored.newer, file: file) } catch {
                try? FileHandle.standardError.write(contentsOf: Data("aris: couldn't save schedules: \(error.localizedDescription)\n".utf8))
                return nil
            }
            return after
        }
    }

    /// The jobs, then the entries kept as they are (a newer Aris's), as one list.
    private static func save(_ jobs: [ArisScheduledJob], newer: [Any], file: URL) throws {
        let encoder = ArisPrivateFile.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var data = try encoder.encode(jobs)
        if !newer.isEmpty, let written = try JSONSerialization.jsonObject(with: data) as? [Any] {
            data = try JSONSerialization.data(withJSONObject: written + newer, options: [.sortedKeys, .prettyPrinted])
        }
        try ArisPrivateFile.write(data, to: file)
    }
}

// MARK: - Inbox

/// Something a scheduled job produced for the user: its result, its failure, a question it waits on, or a note.
struct ArisInboxEntry: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case result, failure, confirm, note
    }

    /// A question a scheduled run parked (the confirm card's fields; `id` is what POST /confirm takes).
    struct Question: Codable, Equatable {
        let id: String
        let title: String
        let detail: String
        let full: String?
    }

    let id: UUID
    let date: Date
    let kind: Kind
    /// The scheduled job it came from.
    let schedule: UUID?
    let title: String
    let text: String
    /// A long result saved as a file.
    let file: String?
    let confirm: Question?
    /// The background job it came from (the app's id for it), when it is one's (ArisTaskFollow): the app follows the
    /// job by this id after its stream is gone.
    var job: String? = nil
}

enum ArisInbox {
    /// Entries kept: the newest.
    static let limit = 500
    static let textLimit = 4_000

    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("inbox.jsonl")
    }

    static func load(file: URL) -> [ArisInboxEntry] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? ArisPrivateFile.decoder.decode(ArisInboxEntry.self, from: Data($0)) }
    }

    /// Adds an entry (its text cut to `textLimit`); only the newest `limit` are kept. Best effort.
    static func append(_ entry: ArisInboxEntry, file: URL) {
        let clean = ArisInboxEntry(id: entry.id, date: entry.date, kind: entry.kind, schedule: entry.schedule,
                                   title: ArisSchedule.oneLine(entry.title, limit: ArisSchedule.titleLimit), text: String(entry.text.prefix(textLimit)),
                                   file: entry.file, confirm: entry.confirm, job: entry.job)
        ArisPrivateFile.withLock(file) { save(Array((load(file: file) + [clean]).suffix(limit)), file: file) }
    }

    /// Whether a background job's result or failure is already in the inbox (the app may not have taken it yet).
    static func hasEnd(job: String, file: URL) -> Bool {
        load(file: file).contains { $0.job == job && ($0.kind == .result || $0.kind == .failure) }
    }

    /// The app delivered these: they leave the inbox. How many did.
    @discardableResult
    static func ack(_ ids: Set<UUID>, file: URL) -> Int {
        remove(file: file) { ids.contains($0.id) }
    }

    /// Questions that are settled (their run ended, or the agent restarted): their cards must never show.
    @discardableResult
    static func removeQuestions(_ ids: Set<String>, file: URL) -> Int {
        remove(file: file) { entry in entry.confirm.map { ids.contains($0.id) } ?? false }
    }

    /// Every scheduled run's question in the inbox (at the agent's start, none of them can be answered any more). A
    /// background job's are the task recovery's own (ArisTaskRecoveryLive asks them again under new ids).
    @discardableResult
    static func removeAllQuestions(file: URL) -> Int {
        remove(file: file) { $0.kind == .confirm && $0.job == nil }
    }

    /// Every background job's question (at the agent's start: their ids belong to the last launch).
    @discardableResult
    static func removeJobQuestions(file: URL) -> Int {
        remove(file: file) { $0.kind == .confirm && $0.job != nil }
    }

    private static func remove(file: URL, where gone: (ArisInboxEntry) -> Bool) -> Int {
        ArisPrivateFile.withLock(file) {
            let entries = load(file: file)
            let kept = entries.filter { !gone($0) }
            if kept.count < entries.count { save(kept, file: file) }
            return entries.count - kept.count
        }
    }

    /// POST /inbox's answer: {"items": [...]}, oldest first.
    static func fetchBody(_ entries: [ArisInboxEntry]) -> Data {
        struct Body: Encodable { let items: [ArisInboxEntry] }
        return (try? ArisPrivateFile.encoder.encode(Body(items: entries))) ?? Data(#"{"items":[]}"#.utf8)
    }

    private static func save(_ entries: [ArisInboxEntry], file: URL) {
        let encoder = ArisPrivateFile.encoder
        let lines = entries.compactMap { try? encoder.encode($0) }.map { $0 + Data([0x0A]) }
        do { try ArisPrivateFile.write(lines.reduce(Data(), +), to: file) } catch {
            try? FileHandle.standardError.write(contentsOf: Data("aris: couldn't save the inbox: \(error.localizedDescription)\n".utf8))
        }
    }
}
