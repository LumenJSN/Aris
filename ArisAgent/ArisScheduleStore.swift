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
}

// MARK: - Schedules

enum ArisScheduleStore {
    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("schedules.json")
    }

    /// The jobs; a damaged entry is skipped, and a missing or unreadable store is empty.
    static func load(file: URL) -> [ArisScheduledJob] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return jobs(in: data)
    }

    /// The jobs to change: like `load`, but a store that is there and isn't the user's private file (or sits in a linked
    /// folder) is refused, never replaced by a new list.
    private static func loadForChange(file: URL) throws -> [ArisScheduledJob] {
        if let data = ArisPrivateFile.read(file) { return jobs(in: data) }
        var info = stat()
        guard lstat(file.path, &info) != 0, ArisPrivateFile.isRealFolder(file.deletingLastPathComponent()) else {
            FileHandle.standardError.write(Data("aris: \(file.path) isn't a private file of yours: left as it is\n".utf8))
            throw ArisScheduleError(message: "the schedule store isn't private (check \(file.lastPathComponent)'s owner and permissions)")
        }
        return []
    }

    private static func jobs(in data: Data) -> [ArisScheduledJob] {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? ArisPrivateFile.decoder.decode(ArisScheduledJob.self, from: one)
        }
    }

    /// Adds a job; refused past ArisSchedule.maxSchedules (one-time jobs that already ran don't count, and leave).
    static func add(_ job: ArisScheduledJob, file: URL) throws {
        try ArisPrivateFile.withLock(file) {
            let jobs = ArisSchedule.pruned(try loadForChange(file: file))
            guard jobs.filter(ArisSchedule.isEnabled).count < ArisSchedule.maxSchedules else {
                throw ArisScheduleError(message: "there are already \(ArisSchedule.maxSchedules) schedules: remove one first")
            }
            guard !jobs.contains(where: { $0.id == job.id }) else { throw ArisScheduleError(message: "that schedule is already there") }
            try save(jobs + [job], file: file)
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
        try add(copy, file: file)
    }

    /// Removes job `id` and returns it; throws when there is none.
    @discardableResult
    static func remove(id: UUID, file: URL) throws -> ArisScheduledJob {
        try ArisPrivateFile.withLock(file) {
            let jobs = try loadForChange(file: file)
            guard let found = jobs.first(where: { $0.id == id }) else { throw ArisScheduleError(message: "no schedule with that id") }
            try save(jobs.filter { $0.id != id }, file: file)
            return found
        }
    }

    /// Changes the jobs under the lock; the file is written only when something changed. The jobs after, or nil when
    /// the change couldn't be saved (nothing that depends on it may happen then).
    @discardableResult
    static func update(file: URL, _ change: ([ArisScheduledJob]) -> [ArisScheduledJob]) -> [ArisScheduledJob]? {
        ArisPrivateFile.withLock(file) {
            guard let before = try? loadForChange(file: file) else { return nil }
            let after = change(before)
            guard after != before else { return after }
            do { try save(after, file: file) } catch {
                FileHandle.standardError.write(Data("aris: couldn't save schedules: \(error.localizedDescription)\n".utf8))
                return nil
            }
            return after
        }
    }

    private static func save(_ jobs: [ArisScheduledJob], file: URL) throws {
        let encoder = ArisPrivateFile.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try ArisPrivateFile.write(try encoder.encode(jobs), to: file)
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
                                   file: entry.file, confirm: entry.confirm)
        ArisPrivateFile.withLock(file) { save(Array((load(file: file) + [clean]).suffix(limit)), file: file) }
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

    /// Every question in the inbox (at the agent's start, none of them can be answered any more).
    @discardableResult
    static func removeAllQuestions(file: URL) -> Int {
        remove(file: file) { $0.kind == .confirm }
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
            FileHandle.standardError.write(Data("aris: couldn't save the inbox: \(error.localizedDescription)\n".utf8))
        }
    }
}
