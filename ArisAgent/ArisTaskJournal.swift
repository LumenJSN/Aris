//
//  ArisTaskJournal.swift
//  aris-agent
//
//  Where each background task's journal is kept: tasks/<job id>.jsonl in the helper's folder (~/.config/aris/aris),
//  0600 in a 0700 folder like every private file there (ArisPrivateFile), appended a line at a time, never through a
//  link, and read only when it is the user's and closed to others. Every line is sealed (ArisTaskSeal): one the helper
//  didn't write is dropped. The folder is on every brain's deny list, as the scheduler's files are. One file per job, named by the app's UUID for it, so a
//  job's whole story is one file and nothing else can be named. Ended journals go after a week; the brain's own
//  transcript of an ended job goes at its end (ArisSessionTranscript).
//  ArisTaskTrail writes one task's journal; ArisTaskRecoveryLive reads them all at start.
//

import Darwin
import Foundation

enum ArisTaskJournal {
    /// Ended journals kept this long, then removed.
    static let keptAfterEnd: TimeInterval = 7 * 86_400
    /// At most this many journals are read (the newest): far more than tasks that could be under way.
    static let readLimit = 500

    static func folder(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("tasks")
    }

    /// The journal of `job` (the app's UUID for it); nil for anything else.
    static func file(job: String, home: String) -> URL? {
        guard let id = UUID(uuidString: job) else { return nil }
        return folder(home: home).appendingPathComponent(id.uuidString.lowercased() + ".jsonl")
    }

    /// Adds one record to `job`'s journal, sealed in its place in the chain (ArisTaskSeal). A tail that doesn't hold
    /// (a crash cut the last line, or anything not the helper's own) is cut off first: nothing after the last good
    /// record is trusted, and the new one follows it. False when it couldn't be written (a link, a folder that isn't
    /// one, a file that isn't the user's private one).
    @discardableResult
    static func append(_ record: ArisTaskRecord, job: String, home: String) -> Bool {
        guard let file = file(job: job, home: home), let key = ArisTaskSeal.key(home: home),
              ArisPrivateFile.prepareFolder(file.deletingLastPathComponent()) else { return false }
        let descriptor = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, ArisPrivateFile.isPrivate(uid: info.st_uid, mode: info.st_mode & 0o777) else {
            return false
        }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        let id = chainId(job)
        let existing = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readDataToEndOfFile()
        let chain = ArisTaskRecord.chained(in: existing) { json, seal, index, previous in
            ArisTaskSeal.verifies(ArisTaskSeal.context("task", id, String(index), previous) + json, seal: seal, key: key)
        }
        if chain.goodBytes < existing.count {
            FileHandle.standardError.write(Data("aris-agent: job \(id.prefix(8))'s journal had \(existing.count - chain.goodBytes) byte(s) after its last good record; cut\n".utf8))
            guard ftruncate(descriptor, off_t(chain.goodBytes)) == 0 else { return false }
        }
        let line = record.line(sealedWith: { ArisTaskSeal.lineSeal($0, job: id, index: chain.good, previous: chain.last, key: key) })
        guard lseek(descriptor, 0, SEEK_END) >= 0, line.withUnsafeBytes({ Darwin.write(descriptor, $0.baseAddress, $0.count) }) == line.count else { return false }
        // How it ended is also kept beside the journal, so a journal cut short never brings a finished or cancelled
        // task back to life.
        if record.kind == .ended, let ending = record.ending,
           let sealed = ArisTaskSeal.sealedFile(Data(ending.rawValue.utf8), purpose: "end\n" + id, home: home) {
            try? ArisPrivateFile.write(sealed, to: endFile(file))
        }
        // An ended job keeps no brain transcript: every session it had goes once its process is gone.
        if record.kind == .ended, let began = chain.records.first?.at {
            ArisSessionTranscript.forgetLater(sessions(in: chain.records), began: began, home: home)
        }
        return true
    }

    /// Every session or thread handle a journal's records name (a job taken back may have had more than one).
    static func sessions(in records: [ArisTaskRecord]) -> [String] {
        records.compactMap { $0.kind == .session ? $0.session : nil }
    }

    /// The job's id as its chain names it.
    static func chainId(_ job: String) -> String { (UUID(uuidString: job)?.uuidString ?? job).lowercased() }

    static func endFile(_ journal: URL) -> URL { journal.deletingPathExtension().appendingPathExtension("end") }

    /// The records up to the first line that doesn't hold its place in the chain.
    static func records(job: String, home: String) -> [ArisTaskRecord] {
        guard let file = file(job: job, home: home), let data = ArisPrivateFile.read(file), let key = ArisTaskSeal.key(home: home) else { return [] }
        let id = chainId(job)
        return ArisTaskRecord.chained(in: data) { json, seal, index, previous in
            ArisTaskSeal.verifies(ArisTaskSeal.context("task", id, String(index), previous) + json, seal: seal, key: key)
        }.records
    }

    /// The task as its journal tells it; one whose journal lost its end (cut short) still ends as its end mark says.
    static func state(job: String, home: String) -> ArisTaskState? {
        guard var state = ArisTaskState.replay(records(job: job, home: home)) else { return nil }
        if state.ending == nil, let file = file(job: job, home: home), let mark = ArisPrivateFile.read(endFile(file)),
           let raw = ArisTaskSeal.opened(mark, purpose: "end\n" + chainId(job), home: home),
           let ending = ArisTaskRecord.Ending(rawValue: String(decoding: raw, as: UTF8.self)) {
            state.ending = ending
            state.ended = state.touched
        }
        return state
    }

    /// Every task with a journal, newest first.
    static func all(home: String) -> [ArisTaskState] {
        let folder = folder(home: home)
        guard ArisPrivateFile.isRealFolder(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.compactMap { name -> String? in
            guard name.hasSuffix(".jsonl") else { return nil }
            let id = String(name.dropLast(6))
            return UUID(uuidString: id) != nil ? id : nil
        }
        .compactMap { state(job: $0, home: home) }
        .sorted { $0.touched > $1.touched }
        .prefix(readLimit)
        .map { $0 }
    }

    /// Journals of tasks that ended more than a week ago are removed; an ended task's brain transcripts a crash left
    /// behind go now (ArisSessionTranscript).
    static func prune(home: String, now: Date = Date()) {
        for state in all(home: home) where !state.isOpen {
            // Only lately ended ones: an older one's went at its end long ago.
            if let ended = state.ended, now.timeIntervalSince(ended) < 2 * 86_400, state.session != nil {
                ArisSessionTranscript.remove(sessions(in: records(job: state.job, home: home)), began: state.created, home: home)
            }
            guard let ended = state.ended, now.timeIntervalSince(ended) > keptAfterEnd, let file = file(job: state.job, home: home) else { continue }
            unlink(file.path)
            unlink(endFile(file).path)
        }
    }
}
