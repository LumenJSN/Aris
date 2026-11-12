//
//  ArisCodexUsageLedger.swift
//  aris-agent
//
//  Aris's own Codex turns, counted. Aris runs `codex app-server` on ephemeral threads, so Codex writes no session log
//  for them and the cost scanner (ArisUsageScanner), which reads ~/.codex/sessions, never saw them: 사용량 › Codex said
//  "오늘 $0.00 · 오늘 토큰 0" after about 40 turns (QA 2026-11-09). The driver hands each `thread/tokenUsage/updated` here;
//  one line per change goes to ~/.config/aris/aris/codex-usage.jsonl (0600): when, which model, and the token counts
//  since the last update. Never a word of the conversation, never a thread id.
//

import Foundation

enum ArisCodexUsageLedger {
    static let fileName = "codex-usage.jsonl"
    /// Where the lines go (the agent's own folder); tests point it at a fixture.
    nonisolated(unsafe) static var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris")
    static var file: URL { directory.appendingPathComponent(fileName) }

    /// A `thread/tokenUsage/updated` notification's params: the thread and its running total (and the latest turn's own
    /// use, for when a total goes down). Nil for anything else.
    static func update(_ params: [String: Any]) -> (thread: String, total: ArisCodexTotals, last: ArisCodexTotals?)? {
        guard let thread = params["threadId"] as? String, let usage = params["tokenUsage"] as? [String: Any],
              let total = totals(usage["total"]) else { return nil }
        return (thread, total, totals(usage["last"]))
    }

    /// The app-server's camelCase counts (inputTokens includes the cached ones, as in Codex's session logs).
    static func totals(_ json: Any?) -> ArisCodexTotals? {
        guard let raw = json as? [String: Any] else { return nil }
        let value = { (key: String) in (raw[key] as? NSNumber)?.intValue ?? 0 }
        var totals = ArisCodexTotals()
        totals.input = value("inputTokens")
        totals.cached = value("cachedInputTokens")
        totals.cacheWrite = value("cacheWriteInputTokens")
        totals.output = value("outputTokens")
        totals.total = value("totalTokens")
        return totals
    }

    /// What this update adds: the change since the thread's last total, or the latest turn's own use when the total
    /// went down (a compacted thread).
    static func delta(_ total: ArisCodexTotals, last: ArisCodexTotals?, previous: ArisCodexTotals?) -> ArisCodexTotals {
        guard let previous else { return total }
        return total.decreased(from: previous) ? (last ?? ArisCodexTotals()) : total.minus(previous)
    }

    /// One ledger line: counts, the model and the time only.
    static func line(_ delta: ArisCodexTotals, model: String, at: Date) -> Data? {
        let object: [String: Any] = ["at": ISO8601DateFormatter().string(from: at), "model": String(model.prefix(80)),
                                     "input": delta.input, "cached": delta.cached, "cacheWrite": delta.cacheWrite,
                                     "output": delta.output, "total": delta.total]
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        data.append(0x0A)
        return data
    }

    /// A ledger line back as a cost event; nil for a line that isn't one.
    static func raw(_ line: Substring) -> ArisCodexRaw? {
        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let stamp = json["at"] as? String, let at = ISO8601DateFormatter().date(from: stamp),
              let model = json["model"] as? String else { return nil }
        let value = { (key: String) in max(0, (json[key] as? NSNumber)?.intValue ?? 0) }
        var usage = ArisCodexTotals()
        usage.input = value("input")
        usage.cached = value("cached")
        usage.cacheWrite = value("cacheWrite")
        usage.output = value("output")
        usage.total = value("total")
        return usage.isZero ? nil : ArisCodexRaw(at: at, model: model, usage: usage)
    }

    /// Every event in the ledger at or after `cutoff`.
    static func events(in ledger: URL? = nil, since cutoff: Date) -> [ArisCodexRaw] {
        guard let text = try? String(contentsOf: ledger ?? file, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap(raw).filter { $0.at >= cutoff }
    }

    /// Appends one update's line (the file 0600, rotated as the other logs).
    static func record(_ delta: ArisCodexTotals, model: String, at: Date = Date()) {
        guard !delta.isZero, let data = line(delta, model: model, at: at) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        ArisLogRotation.rotate(file)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }
}
