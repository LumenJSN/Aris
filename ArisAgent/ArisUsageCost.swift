//
//  ArisUsageCost.swift
//  aris-agent
//
//  What Claude and Codex have cost, from the logs they leave on this Mac, priced at API rates (after CodexBar's
//  cost scanner, github.com/steipete/CodexBar, MIT). One long-lived scanner reads only what was appended since its
//  last pass (a byte offset per file), keeps the events in memory, and answers from them: today, 30 days, daily
//  buckets, the last three weekly windows. Claude's repeated streaming lines count once (the last of each
//  message + request); Codex's cumulative token totals are turned into deltas, and forked sessions' copied history
//  counts once. Aris's own Codex turns run on ephemeral threads that leave no session log; the driver counts them into
//  ArisCodexUsageLedger, which is read here beside the logs.
//

import Foundation

struct ArisClaudeRaw: Equatable {
    var at: Date
    var model: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheCreation: Int
    var cache1h: Int
}

struct ArisCodexTotals: Equatable {
    var input = 0
    var cached = 0
    var cacheWrite = 0
    var output = 0
    var total = 0

    init() {}

    init?(_ json: Any?) {
        guard let raw = json as? [String: Any] else { return nil }
        let value = { (key: String) in (raw[key] as? NSNumber)?.intValue ?? 0 }
        input = value("input_tokens")
        cached = value("cached_input_tokens")
        cacheWrite = value("cache_write_input_tokens")
        output = value("output_tokens")
        total = value("total_tokens")
    }

    func decreased(from previous: ArisCodexTotals) -> Bool {
        input < previous.input || cached < previous.cached || cacheWrite < previous.cacheWrite || output < previous.output
    }

    func minus(_ previous: ArisCodexTotals) -> ArisCodexTotals {
        var delta = ArisCodexTotals()
        delta.input = input - previous.input
        delta.cached = cached - previous.cached
        delta.cacheWrite = cacheWrite - previous.cacheWrite
        delta.output = output - previous.output
        delta.total = total - previous.total
        return delta
    }

    var isZero: Bool { input == 0 && output == 0 && cached == 0 && cacheWrite == 0 }
}

struct ArisCodexRaw: Equatable {
    var at: Date
    var model: String
    var usage: ArisCodexTotals
}

/// Where a Codex file's reading stands between passes.
struct ArisCodexFileState {
    var model: String?
    var previous: ArisCodexTotals?
}

enum ArisUsageLog {
    nonisolated(unsafe) private static let timestamps: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return timestamps.date(from: text) ?? ArisUsageParse.isoDate(text)
    }

    /// A Claude transcript line: dedupe key and usage, or nil when it isn't an assistant message with usage.
    static func claude(line: Data) -> (key: String, raw: ArisClaudeRaw)? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let at = date(json["timestamp"] as? String) else { return nil }
        let value = { (key: String) in (usage[key] as? NSNumber)?.intValue ?? 0 }
        let cache1h = ((usage["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"] as? NSNumber)?.intValue ?? 0
        let key = (message["id"] as? String ?? "") + ":" + (json["requestId"] as? String ?? "")
        return (key, ArisClaudeRaw(at: at, model: model, input: value("input_tokens"), output: value("output_tokens"),
                                   cacheRead: value("cache_read_input_tokens"), cacheCreation: value("cache_creation_input_tokens"),
                                   cache1h: cache1h))
    }

    /// One Codex log line, in file order: a turn_context sets the model; a token_count gives the delta since the
    /// file's last total (or its last_token_usage when a total went down).
    static func codex(line: Data, state: inout ArisCodexFileState) -> (key: String, raw: ArisCodexRaw)? {
        guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = json["payload"] as? [String: Any] else { return nil }
        if json["type"] as? String == "turn_context" {
            if let model = payload["model"] as? String { state.model = model }
            return nil
        }
        guard json["type"] as? String == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any], let total = ArisCodexTotals(info["total_token_usage"]) else { return nil }
        let delta: ArisCodexTotals
        if let previous = state.previous {
            delta = total.decreased(from: previous) ? (ArisCodexTotals(info["last_token_usage"]) ?? ArisCodexTotals()) : total.minus(previous)
        } else {
            delta = total
        }
        state.previous = total
        guard !delta.isZero, let stamp = json["timestamp"] as? String, let at = date(stamp) else { return nil }
        return ("\(stamp):\(total.total)", ArisCodexRaw(at: at, model: state.model ?? "unknown", usage: delta))
    }
}

struct ArisCostEvent {
    let at: Date
    let model: String
    let tokens: Int
    let usd: Double
}

enum ArisUsageAggregate {
    /// Today, 30 days, 30 daily buckets and the weekly windows ending at `weekEnd` (the limit's reset; unknown:
    /// the next whole hour).
    static func cost(_ events: [ArisCostEvent], now: Date, weekEnd: Date?, calendar: Calendar = .current) -> ArisUsageCost {
        let today = calendar.startOfDay(for: now)
        let days = (0..<30).map { calendar.date(byAdding: .day, value: $0 - 29, to: today) ?? today }
        var usd = [Double](repeating: 0, count: 30)
        var tokens = [Int](repeating: 0, count: 30)
        let end: Date = {
            if let weekEnd, weekEnd > now { return weekEnd }
            let hour = calendar.dateInterval(of: .hour, for: now)?.end ?? now
            return hour
        }()
        let week: TimeInterval = 7 * 86_400
        var windows = (0..<3).map { (start: end.addingTimeInterval(-week * Double($0 + 1)), end: end.addingTimeInterval(-week * Double($0)), usd: 0.0, tokens: 0) }
        var byModel: [String: (usd: Double, tokens: Int)] = [:]
        for event in events {
            if event.at >= days[0], event.at < (calendar.date(byAdding: .day, value: 1, to: today) ?? now) {
                var index = 29
                while index > 0, event.at < days[index] { index -= 1 }
                usd[index] += event.usd
                tokens[index] += event.tokens
                byModel[event.model, default: (0, 0)].usd += event.usd
                byModel[event.model, default: (0, 0)].tokens += event.tokens
            }
            for index in windows.indices where event.at >= windows[index].start && event.at < windows[index].end {
                windows[index].usd += event.usd
                windows[index].tokens += event.tokens
            }
        }
        let top = byModel.max { ($0.value.usd, $0.value.tokens) < ($1.value.usd, $1.value.tokens) }?.key
        return ArisUsageCost(
            today: ArisUsageSpend(usd: usd[29], tokens: tokens[29]),
            last30: ArisUsageSpend(usd: usd.reduce(0, +), tokens: tokens.reduce(0, +)),
            daily: (0..<30).map { ArisUsageDay(day: days[$0], usd: usd[$0], tokens: tokens[$0]) },
            windows: windows.map { ArisUsageSpendWindow(start: $0.start, end: $0.end, usd: $0.usd, tokens: $0.tokens) },
            topModel: top)
    }
}

final class ArisUsageScanner: @unchecked Sendable {
    static let shared = ArisUsageScanner()

    private struct FileState {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var codex = ArisCodexFileState()
    }

    private let lock = NSLock()
    private let passQueue = DispatchQueue(label: "com.lumenjsn.aris.usage.scan", qos: .utility)
    private var running = false
    private var lastPass: Date?
    private var finishedOnce = false
    private var claudeFiles: [String: FileState] = [:]
    private var codexFiles: [String: FileState] = [:]
    private var claudeEvents: [String: (file: String, raw: ArisClaudeRaw)] = [:]
    private var codexEvents: [String: (file: String, raw: ArisCodexRaw)] = [:]
    /// Aris's own Codex turns (ArisCodexUsageLedger), read whole each pass.
    private var ledgerEvents: [ArisCodexRaw] = []

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var codexHome: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(".codex")
    }

    /// A pass in the background unless one ran in the last minute or is running; never waits.
    func kick(now: Date = Date()) {
        lock.lock()
        if running || (lastPass.map { now.timeIntervalSince($0) < 60 } ?? false) { lock.unlock(); return }
        running = true
        lock.unlock()
        passQueue.async { self.pass(now: Date()) }
    }

    /// One whole pass, waiting for it (`--usage-report`).
    func runBlocking(now: Date = Date()) {
        lock.lock(); running = true; lock.unlock()
        passQueue.sync { pass(now: now) }
    }

    var ready: Bool { lock.lock(); defer { lock.unlock() }; return finishedOnce }

    /// nil until the first pass has finished.
    func cost(provider: String, weekEnd: Date?, now: Date = Date()) -> ArisUsageCost? {
        lock.lock()
        guard finishedOnce else { lock.unlock(); return nil }
        let raws: [(Date, String, ArisClaudeRaw?, ArisCodexRaw?)]
        if provider == "claude" {
            raws = claudeEvents.values.map { ($0.raw.at, $0.raw.model, $0.raw, nil) }
        } else {
            raws = Self.codexRaws(logs: codexEvents.values.map(\.raw), ledger: ledgerEvents).map { ($0.at, $0.model, nil, $0) }
        }
        lock.unlock()
        var rates: [String: ArisModelRate?] = [:]
        let events = raws.map { at, model, claude, codex -> ArisCostEvent in
            let pricingProvider = provider == "claude" ? "anthropic" : "openai"
            if rates[model] == nil { rates[model] = .some(ArisUsagePricing.rate(provider: pricingProvider, model: model)) }
            let rate = rates[model] ?? nil
            if let claude {
                let usd = rate.map { ArisUsagePricing.claudeCost($0, input: claude.input, output: claude.output, cacheRead: claude.cacheRead,
                                                                 cacheCreation: claude.cacheCreation, cache1h: claude.cache1h) } ?? 0
                return ArisCostEvent(at: at, model: model, tokens: claude.input + claude.output + claude.cacheRead + claude.cacheCreation, usd: usd)
            }
            guard let usage = codex?.usage else { return ArisCostEvent(at: at, model: model, tokens: 0, usd: 0) }
            let usd = rate.map { ArisUsagePricing.codexCost($0, input: usage.input, cached: usage.cached, cacheWrite: usage.cacheWrite, output: usage.output) } ?? 0
            return ArisCostEvent(at: at, model: model, tokens: usage.input + usage.output, usd: usd)
        }
        return ArisUsageAggregate.cost(events, now: now, weekEnd: weekEnd)
    }

    // MARK: - Passes

    private func pass(now: Date) {
        DispatchQueue.global(qos: .utility).async { ArisUsagePricing.refreshIfStale() }
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -31, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-31 * 86_400)
        let fileCutoff = now.addingTimeInterval(-35 * 86_400)
        scan(root: home.appendingPathComponent(".claude/projects"), fileCutoff: fileCutoff, cutoff: cutoff, claude: true)
        scan(root: codexHome.appendingPathComponent("sessions"), fileCutoff: fileCutoff, cutoff: cutoff, claude: false)
        let ledger = ArisCodexUsageLedger.events(since: cutoff)
        lock.lock()
        ledgerEvents = ledger
        claudeEvents = claudeEvents.filter { $0.value.raw.at >= cutoff }
        codexEvents = codexEvents.filter { $0.value.raw.at >= cutoff }
        finishedOnce = true
        running = false
        lastPass = Date()
        lock.unlock()
    }

    private func scan(root: URL, fileCutoff: Date, cutoff: Date, claude: Bool) {
        var seen: Set<String> = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        if let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) {
            for case let url as URL in walker where Self.isRollout(url.path, compressed: !claude) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), let modified = values.contentModificationDate,
                      modified >= fileCutoff, let size = values.fileSize else { continue }
                seen.insert(Self.logicalPath(url.path))
                read(url, size: UInt64(size), cutoff: cutoff, claude: claude)
            }
        }
        lock.lock()
        let gone = (claude ? claudeFiles : codexFiles).keys.filter { !seen.contains($0) }
        lock.unlock()
        for path in gone { forget(path, claude: claude) }
    }

    private func forget(_ path: String, claude: Bool) {
        lock.lock()
        if claude {
            claudeFiles[path] = nil
            claudeEvents = claudeEvents.filter { $0.value.file != path }
        } else {
            codexFiles[path] = nil
            codexEvents = codexEvents.filter { $0.value.file != path }
        }
        lock.unlock()
    }

    /// Codex's events: the CLI's session logs and Aris's own turns (their threads are ephemeral, so never in both).
    static func codexRaws(logs: [ArisCodexRaw], ledger: [ArisCodexRaw]) -> [ArisCodexRaw] { logs + ledger }

    /// A log file's name without the ".zst" Codex adds when it compresses an old rollout in place.
    static func logicalPath(_ path: String) -> String { path.hasSuffix(".zst") ? String(path.dropLast(4)) : path }

    /// Claude's logs are plain .jsonl; Codex's may also be .jsonl.zst.
    static func isRollout(_ path: String, compressed: Bool) -> Bool {
        path.hasSuffix(".jsonl") || (compressed && path.hasSuffix(".jsonl.zst"))
    }

    private static let zstd = ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }

    private func read(_ url: URL, size: UInt64, cutoff: Date, claude: Bool) {
        let compressed = url.path.hasSuffix(".zst")
        let path = Self.logicalPath(url.path)
        let inode = ((try? FileManager.default.attributesOfItem(atPath: path))?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        lock.lock()
        var state = (claude ? claudeFiles[path] : codexFiles[path]) ?? FileState()
        lock.unlock()
        var claudeFound: [(String, ArisClaudeRaw)] = []
        var codexFound: [(String, ArisCodexRaw)] = []
        var codexState = ArisCodexFileState()
        // Streamed a chunk at a time: transcripts run to hundreds of MB and reading them whole cost ~1.7 GB.
        let collect = { (line: UnsafeRawBufferPointer) in
            if claude {
                guard ArisLineStream.contains(line, "\"type\":\"assistant\""), ArisLineStream.contains(line, "\"usage\"") else { return }
                if let found = ArisUsageLog.claude(line: Data(line)), found.raw.at >= cutoff { claudeFound.append(found) }
            } else {
                guard ArisLineStream.contains(line, "\"turn_context\"") || ArisLineStream.contains(line, "\"token_count\"") else { return }
                if let found = ArisUsageLog.codex(line: Data(line), state: &codexState), found.raw.at >= cutoff { codexFound.append(found) }
            }
        }
        if compressed {
            // Compressed rollouts never change: read once, whole (its events stay if it replaces a plain file).
            if state.offset == size, state.inode == inode { return }
            state = FileState()
            guard let zstd = Self.zstd, ArisLineStream.forEachLine(ofCommand: zstd, ["-dc", url.path], timeout: 20, collect) else { return }
            state.offset = size
        } else {
            if state.offset > 0, size < state.offset || (state.inode != 0 && inode != state.inode) {
                forget(path, claude: claude)
                state = FileState()
            }
            guard size > state.offset else { return }
            codexState = state.codex
            guard let consumed = ArisLineStream.forEachLine(inFile: url, from: state.offset, collect), consumed > 0 else { return }
            state.offset += UInt64(consumed)
        }
        state.codex = codexState
        state.inode = inode
        lock.lock()
        for (key, raw) in claudeFound { claudeEvents[key] = (path, raw) }
        for (key, raw) in codexFound where codexEvents[key] == nil { codexEvents[key] = (path, raw) }
        if claude { claudeFiles[path] = state } else { codexFiles[path] = state }
        lock.unlock()
    }
}
