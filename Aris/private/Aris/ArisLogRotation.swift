//
//  ArisLogRotation.swift
//  Aris (also built into aris-agent and aris-tools)
//
//  Append-only logs (actions.log, turns.jsonl, the tuning logs, agent.log) can't grow for ever on a Mac that stays up
//  for months. A file over its limit is moved whole to <name>.<date> before the next line is appended. The dated
//  copies are pruned only by age (30 days) and by a large total (200 MB), oldest first, never by count: a flood of
//  rotations can't push older evidence out. A file another process keeps open for writing (launchd's agent.log) is
//  copied to a dated file and emptied in place instead.
//

import Foundation

enum ArisLogRotation {
    /// Ten megabytes: a year of actions.log at the user's pace, a few minutes to read.
    static let defaultLimit = 10 * 1_024 * 1_024
    /// Copies older than this go.
    static let defaultMaxAge: TimeInterval = 30 * 86_400
    /// Copies beyond this much, oldest first, go.
    static let defaultTotalCap = 200 * 1_024 * 1_024

    /// The file's size, nil when there is none.
    static func size(of file: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int
    }

    private static var stampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    /// Moves `file` to `<file>.<yyyyMMdd-HHmmss>` when it is over `limit` bytes, then prunes the copies. True when it
    /// moved. The live file is never truncated: its contents are whole in the copy.
    @discardableResult
    static func rotate(_ file: URL, limit: Int = defaultLimit, maxAge: TimeInterval = defaultMaxAge, totalCap: Int = defaultTotalCap,
                       now: Date = Date()) -> Bool {
        guard let size = size(of: file), size > limit else { return false }
        do {
            try FileManager.default.moveItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent(nextName(for: file, now: now)))
        } catch {
            return false
        }
        prune(file, maxAge: maxAge, totalCap: totalCap, now: now)
        return true
    }

    /// For a log another process holds open (its writer carries on from the new end): the contents are copied whole
    /// to a dated file and the live file is emptied in place. True when it was.
    @discardableResult
    static func rotateOpenLog(_ file: URL, limit: Int = defaultLimit, maxAge: TimeInterval = defaultMaxAge, totalCap: Int = defaultTotalCap,
                              now: Date = Date()) -> Bool {
        guard let size = size(of: file), size > limit, let handle = try? FileHandle(forUpdating: file) else { return false }
        defer { try? handle.close() }
        do {
            try FileManager.default.copyItem(at: file, to: file.deletingLastPathComponent().appendingPathComponent(nextName(for: file, now: now)))
            try handle.truncate(atOffset: 0)
        } catch {
            return false
        }
        prune(file, maxAge: maxAge, totalCap: totalCap, now: now)
        return true
    }

    /// The next dated name: several rotations in one second carry on from the highest suffix made so far (a pruned
    /// name is never reused, so the copies keep sorting by age).
    private static func nextName(for file: URL, now: Date) -> String {
        let stamp = file.lastPathComponent + "." + stampFormatter.string(from: now)
        let used = generations(of: file).filter { $0 == stamp || $0.hasPrefix(stamp + "-") }
            .map { name -> Int in name == stamp ? 1 : Int(name.dropFirst(stamp.count + 1)) ?? 1 }
        let n = (used.max() ?? 0) + 1
        return n == 1 ? stamp : "\(stamp)-\(n)"
    }

    /// The dated copies of `file` in its folder, oldest first (by stamp, then by the same-second suffix as a number).
    static func generations(of file: URL) -> [String] {
        let prefix = file.lastPathComponent + "."
        let names = (try? FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasPrefix(prefix) && parts(of: $0, prefix: prefix) != nil }
            .sorted { a, b in
                let (sa, na) = parts(of: a, prefix: prefix)!, (sb, nb) = parts(of: b, prefix: prefix)!
                return sa == sb ? na < nb : sa < sb
            }
    }

    /// The stamp and same-second number of a copy's name; nil when the name isn't one.
    private static func parts(of name: String, prefix: String) -> (String, Int)? {
        let rest = name.dropFirst(prefix.count)
        guard rest.range(of: #"^\d{8}-\d{6}(-\d+)?$"#, options: .regularExpression) != nil else { return nil }
        let stamp = String(rest.prefix(15))
        return (stamp, rest.count > 15 ? Int(rest.dropFirst(16)) ?? 1 : 1)
    }

    /// When a copy was made, from its name.
    static func date(ofCopy name: String, of file: URL) -> Date? {
        parts(of: name, prefix: file.lastPathComponent + ".").flatMap { stampFormatter.date(from: $0.0) }
    }

    /// Drops copies older than `maxAge`, then the oldest until the rest fit `totalCap`. Never the live file.
    static func prune(_ file: URL, maxAge: TimeInterval, totalCap: Int, now: Date) {
        let folder = file.deletingLastPathComponent()
        var copies = generations(of: file)
        for name in copies where (date(ofCopy: name, of: file).map { now.timeIntervalSince($0) > maxAge } ?? false) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        copies = generations(of: file)
        var total = copies.reduce(0) { $0 + (size(of: folder.appendingPathComponent($1)) ?? 0) }
        for name in copies where total > totalCap {
            let path = folder.appendingPathComponent(name)
            total -= size(of: path) ?? 0
            try? FileManager.default.removeItem(at: path)
        }
    }
}
