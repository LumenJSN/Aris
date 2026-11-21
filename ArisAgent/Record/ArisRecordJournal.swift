//
//  ArisRecordJournal.swift
//  aris-agent
//
//  The record (ARCHITECTURE Part 2, Record): one append-only journal of every capability call when `arisCore2` is on,
//  in the helper's folder as the task journals are: record/<yyyy-mm>.jsonl under ~/.config/aris/aris, 0600 in a 0700
//  folder (ArisPrivateFile), appended a line at a time, never through a link, read only when it is the user's and closed
//  to others. Every line is sealed in a chain with the task journal's key and scheme (ArisTaskSeal, purpose "record"
//  and the month): a line the helper didn't write, moved, reordered or repeated ends what counts, and a tail that
//  doesn't hold is cut before the next line goes on. One file a month; months older than `keptDays` go. The folder is
//  on the never-list for every capability (ArisNeverList.ownPlaces), so no model call reads or writes it.
//

import CryptoKit
import Darwin
import Foundation

enum ArisRecordJournal {
    /// How long the record is kept (whole months older than this go).
    static let keptDays = 90
    /// At most this many lines are read back (the newest months first).
    static let readLimit = 20_000

    static func folder(home: String) -> URL { ArisPrivateFile.folder(home: home).appendingPathComponent("record") }

    static func month(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 1970, parts.month ?? 1)
    }

    static func file(month: String, home: String) -> URL { folder(home: home).appendingPathComponent(month + ".jsonl") }

    private static func verifier(month: String, key: SymmetricKey) -> (Data, String, Int, String) -> Bool {
        { json, seal, index, previous in ArisTaskSeal.verifies(ArisTaskSeal.context("record", month, String(index), previous) + json, seal: seal, key: key) }
    }

    /// Adds one entry, sealed in its place in its month's chain. False when it couldn't be written (no key, a link, a
    /// folder that isn't one, a file that isn't the user's private one).
    @discardableResult
    static func append(_ entry: ArisRecordEntry, home: String) -> Bool {
        let month = month(entry.at)
        let file = file(month: month, home: home)
        guard let key = ArisTaskSeal.key(home: home), ArisPrivateFile.prepareFolder(file.deletingLastPathComponent()) else { return false }
        let descriptor = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, ArisPrivateFile.isPrivate(uid: info.st_uid, mode: info.st_mode & 0o777) else {
            return false
        }
        flock(descriptor, LOCK_EX)
        defer { flock(descriptor, LOCK_UN) }
        let existing = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).readDataToEndOfFile()
        let chain = ArisRecordEntry.chained(in: existing, verify: verifier(month: month, key: key))
        if chain.goodBytes < existing.count {
            FileHandle.standardError.write(Data("aris-agent: the record for \(month) had \(existing.count - chain.goodBytes) byte(s) after its last good line; cut\n".utf8))
            guard ftruncate(descriptor, off_t(chain.goodBytes)) == 0 else { return false }
        }
        let line = entry.line(sealedWith: { ArisTaskSeal.seal(ArisTaskSeal.context("record", month, String(chain.good), chain.last) + $0, key: key) })
        guard lseek(descriptor, 0, SEEK_END) >= 0, line.withUnsafeBytes({ Darwin.write(descriptor, $0.baseAddress, $0.count) }) == line.count else { return false }
        return true
    }

    /// Every entry that holds its place, oldest first, from the months kept.
    static func entries(home: String) -> [ArisRecordEntry] {
        guard let key = ArisTaskSeal.key(home: home), ArisPrivateFile.isRealFolder(folder(home: home)),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder(home: home).path) else { return [] }
        let months = names.filter { $0.range(of: #"^\d{4}-\d{2}\.jsonl$"#, options: .regularExpression) != nil }.map { String($0.dropLast(6)) }.sorted()
        var all: [ArisRecordEntry] = []
        for month in months.reversed() {
            guard let data = ArisPrivateFile.read(file(month: month, home: home)) else { continue }
            all.insert(contentsOf: ArisRecordEntry.chained(in: data, verify: verifier(month: month, key: key)).entries, at: 0)
            if all.count >= readLimit { break }
        }
        return Array(all.suffix(readLimit))
    }

    static func state(home: String) -> ArisRecordState { ArisRecordState(entries(home: home)) }

    /// Months wholly older than `keptDays` are removed.
    static func prune(home: String, now: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder(home: home).path) else { return }
        let oldest = month(now.addingTimeInterval(-Double(keptDays) * 86_400))
        for name in names where name.hasSuffix(".jsonl") && String(name.dropLast(6)) < oldest {
            unlink(folder(home: home).appendingPathComponent(name).path)
        }
    }
}
