//
//  ArisUsageFetch.swift
//  aris-agent
//
//  POST /usage: each AI's plan limits, the way CodexBar gets them (github.com/steipete/CodexBar, MIT), as a
//  registry of sources (ArisUsageSource, asked by ArisUsageDesk) each kept for its own interval.
//  Claude: its OAuth usage endpoint with Claude Code's own login (read only, never refreshed here: Claude Code owns
//  the refresh token). Codex: ChatGPT's usage endpoint with the Codex CLI's login (~/.codex/auth.json, read only);
//  offline, the newest session log's rate_limits. Antigravity: `agy -p /usage`, which sends no prompt, with
//  auto-update off and the browser blocked so a lapsed login can't open a sign-in page. Claude's and Codex's
//  cost comes from ArisUsageScanner. No token is ever logged, stored or put in an error.
//

import Foundation

enum ArisUsageFetch {
    static let sources: [ArisUsageSource] = [ArisClaudeUsage(), ArisCodexUsage(), ArisAntigravityUsage()]
    private static let desk = ArisUsageDesk(sources: sources)

    /// What is known now; due sources are asked first, each on its own (ArisUsageDesk). Claude and Codex are waited for
    /// a few seconds (ArisUsagePatience.report), Antigravity not at all: what is still being asked is named in the
    /// report's `pending`, for the app to ask again.
    static func report(now: Date = Date(), waitForAll: Bool = false) -> ArisUsageReport {
        ArisUsageScanner.shared.kick(now: now)
        let known = desk.report(now: now, wait: waitForAll ? ArisUsageDesk.waitForAll : ArisUsagePatience.report, waitForAll: waitForAll)
        return ArisUsageReport(providers: known.providers.map { withCost($0, now: now) }, pending: known.pending)
    }

    private static func withCost(_ provider: ArisUsageProvider, now: Date) -> ArisUsageProvider {
        guard provider.id == "claude" || provider.id == "codex" else { return provider }
        var provider = provider
        let reset = provider.lanes.first?.weekly?.resetsAt
        provider.cost = ArisUsageScanner.shared.cost(provider: provider.id, weekEnd: reset, now: now)
        return provider
    }

    /// `aris-agent --usage-report`: every source, one whole cost pass, the report as JSON on stdout.
    static func printReport() {
        ArisUsageScanner.shared.runBlocking()
        let report = report(waitForAll: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) { FileHandle.standardOutput.write(data + Data("\n".utf8)) }
    }

    /// GET with a hard timeout; the status, body and Retry-After seconds.
    static func get(_ url: URL, headers: [String: String], timeout: TimeInterval = 15) -> (status: Int, body: Data?, retryAfter: TimeInterval?)? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: (Int, Data?, TimeInterval?)?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                result = (http.statusCode, data, (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init))
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return result.map { (status: $0.0, body: $0.1, retryAfter: $0.2) }
    }

    /// A command's stdout, or nil when it fails or runs past `timeout`.
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? ArisChildren.run(process)) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { ArisProcessEnd.end(process) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}

// MARK: - Claude

final class ArisClaudeUsage: ArisUsageSource, @unchecked Sendable {
    let id = "claude"
    let every: TimeInterval = 180
    private var last: ArisUsageProvider?
    private var backoffUntil = Date.distantPast
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func limits(now: Date) -> ArisUsageProvider? {
        guard let credentials = loadCredentials() else { return last }
        let account = (identity()?["emailAddress"] as? String) ?? last?.account
        let plan = credentials.plan ?? ArisUsageParse.claudePlan(organizationType: identity()?["organizationType"] as? String)
        let base = ArisUsageProvider(id: "claude", title: "Claude", account: account, plan: plan, lanes: [], updatedAt: now)
        if let expires = credentials.expiresAt, expires <= now {
            return remember(base, note: "Claude Code를 한 번 열면 한도를 다시 받아와요")
        }
        if now < backoffUntil { return last }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage"),
              let response = ArisUsageFetch.get(url, headers: [
                  "Authorization": "Bearer \(credentials.token)", "anthropic-beta": "oauth-2025-04-20",
                  "Accept": "application/json", "User-Agent": "claude-code/2.1.0"]) else {
            return remember(last.map { stale($0, plan: plan, account: account) } ?? base, note: "연결이 안 돼서 마지막 값이에요")
        }
        switch response.status {
        case 200:
            guard var fresh = response.body.flatMap({ ArisUsageParse.claude(oauth: $0, now: now) }) else { return last }
            fresh.account = account
            fresh.plan = plan
            return remember(fresh, note: nil)
        case 401, 403:
            return remember(base, note: "Claude 로그인을 다시 확인해야 해요")
        case 429:
            backoffUntil = now.addingTimeInterval(max(response.retryAfter ?? 300, 60))
            return last
        default:
            return last
        }
    }

    private func stale(_ old: ArisUsageProvider, plan: String?, account: String?) -> ArisUsageProvider {
        var provider = old
        provider.plan = plan ?? old.plan
        provider.account = account ?? old.account
        return provider
    }

    private func remember(_ provider: ArisUsageProvider, note: String?) -> ArisUsageProvider {
        var provider = provider
        provider.note = note
        last = provider
        return provider
    }

    /// The login Claude Code keeps: the keychain item its own CLI writes (/usr/bin/security reads it without a
    /// prompt), else ~/.claude/.credentials.json.
    private func loadCredentials() -> (token: String, expiresAt: Date?, plan: String?)? {
        if let data = ArisUsageFetch.run("/usr/bin/security", ["find-generic-password", "-a", NSUserName(), "-s", "Claude Code-credentials", "-w"], timeout: 3),
           let found = ArisUsageParse.claudeCredentials(data) { return found }
        return (try? Data(contentsOf: home.appendingPathComponent(".claude/.credentials.json"))).flatMap(ArisUsageParse.claudeCredentials)
    }

    private func identity() -> [String: Any]? {
        guard let data = try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["oauthAccount"] as? [String: Any]
    }
}

// MARK: - Codex

final class ArisCodexUsage: ArisUsageSource, @unchecked Sendable {
    let id = "codex"
    let every: TimeInterval = 120

    func limits(now: Date) -> ArisUsageProvider? { ArisUsageFetch.fetchCodex(now: now) }
}

// MARK: - Antigravity

final class ArisAntigravityUsage: ArisUsageSource, @unchecked Sendable {
    let id = "antigravity"
    let every: TimeInterval = 600
    var background: Bool { true }

    func limits(now: Date) -> ArisUsageProvider? { ArisUsageFetch.fetchAntigravity() }
}

extension ArisUsageFetch {
    private static let agyTimeout: TimeInterval = 60

    // MARK: - Codex

    private static var codexHome: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty { return URL(fileURLWithPath: home) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }

    static func fetchCodex(now: Date) -> ArisUsageProvider? {
        fetchCodexAPI(now: now) ?? codexFromSessions(now: now)
    }

    private static func fetchCodexAPI(now: Date) -> ArisUsageProvider? {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent("auth.json")),
              let tokens = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["tokens"] as? [String: Any],
              let access = tokens["access_token"] as? String, !access.isEmpty,
              let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        if let account = tokens["account_id"] as? String { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue("codex_cli_rs", forHTTPHeaderField: "User-Agent")
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var body: Data?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { body = data }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 16)
        return body.flatMap { ArisUsageParse.codex(api: $0, now: now) }
    }

    /// The last rate_limits line of the newest session log (sessions/YYYY/MM/DD/*.jsonl).
    private static func codexFromSessions(now: Date) -> ArisUsageProvider? {
        let root = codexHome.appendingPathComponent("sessions")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        let newest = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
            .max { modified($0) < modified($1) }
        guard let newest else { return nil }
        let at = modified(newest)
        var latest: ArisUsageProvider?
        _ = ArisLineStream.forEachLine(inFile: newest, from: 0, flushTail: true) { line in
            guard ArisLineStream.contains(line, "\"rate_limits\"") else { return }
            if let usage = ArisUsageParse.codex(sessionLine: String(decoding: line, as: UTF8.self), now: at) { latest = usage }
        }
        return latest
    }

    private static func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    // MARK: - Antigravity

    private static func agyPath() -> String? { ArisPrograms.find("agy")?.path }

    static func fetchAntigravity() -> ArisUsageProvider? {
        guard let agy = agyPath() else { return nil }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-agy-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: agy)
        process.arguments = ["-p", "/usage", "--output-format", "json"]
        process.currentDirectoryURL = folder
        var environment = ProcessInfo.processInfo.environment
        environment["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
        environment["BROWSER"] = "/usr/bin/false"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? ArisChildren.run(process)) != nil else { return nil }
        let deadline = DispatchTime.now() + agyTimeout
        DispatchQueue.global().asyncAfter(deadline: deadline) { ArisProcessEnd.end(process) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, data.count < 1_048_576 else { return nil }
        return ArisUsageParse.antigravity(data, now: Date())
    }
}
