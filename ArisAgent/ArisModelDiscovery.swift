//
//  ArisModelDiscovery.swift
//  aris-agent
//
//  Which models each brain's own tool offers, and whether it takes a typed id, asked of the tool and never of a model
//  (nothing here sends a question). Checked live on 2026-11-18:
//  - Claude Code 2.1.327: the stream-json `initialize` control request answers with `models` (value, displayName,
//    description, supportedEffortLevels) before any question; `set_model` answers "success" for an id it can use and
//    "error" / not_found ("Model 'x' not found") for one it can't. A process started with `--model x` takes any x.
//  - codex-cli 0.169.0: app-server `model/list` lists the models (id, displayName, supportedReasoningEfforts, hidden);
//    `thread/start` takes any id, and only a turn says "The 'x' model is not supported…", so a typed id is checked
//    against the whole list, hidden ones too, and today's own names.
//  - agy 1.5.3: `agy models` prints "id<TAB>name" lines.
//  The parsers are pure (tested); `live` starts the tool in an empty folder of its own, sealed as the read judge's
//  process is, and ends it once it has answered or at its deadline.
//

import Foundation

enum ArisModelDiscovery {
    /// A typed id, checked.
    enum Check: Equatable {
        case ok(resolved: String?)
        case unknown(String)
        /// The tool couldn't be asked (not installed, slow): the id is taken by its shape only.
        case unchecked
    }

    // MARK: - Claude Code

    static let claudeArguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                                  "--no-session-persistence", "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
                                  "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#, "--tools", ""]

    static func claudeRequest(_ id: String, _ request: [String: Any]) -> Data {
        line(["type": "control_request", "request_id": id, "request": request])
    }

    /// The `initialize` answer's models, in its order; Claude Code's own "default" (its pick, not Aris's 자동) is left out.
    static func claudeModels(_ line: String) -> [ArisModelOption]? {
        guard let response = controlResponse(line, id: "aris-models"), response["subtype"] as? String == "success",
              let models = (response["response"] as? [String: Any])?["models"] as? [[String: Any]] else { return nil }
        return models.compactMap { model in
            guard let id = model["value"] as? String, id != "default", ArisModelChoices.isModelID(id) else { return nil }
            let title = (model["displayName"] as? String).map { String($0.prefix(60)) } ?? id
            let detail = (model["description"] as? String).map { String($0.prefix(120)) }
            let efforts = (model["supportedEffortLevels"] as? [String] ?? []).filter(ArisModelChoices.effortWords.contains)
            return ArisModelOption(id: id, title: title, detail: detail, efforts: efforts)
        }
    }

    /// `set_model`'s answer: the id it resolved to, or the tool's own words for one it can't use.
    static func claudeCheck(_ line: String) -> Check? {
        guard let response = controlResponse(line, id: "aris-check") else { return nil }
        if response["subtype"] as? String == "success" {
            return .ok(resolved: (response["response"] as? [String: Any])?["model"] as? String)
        }
        return .unknown(String((response["error"] as? String ?? "").prefix(160)))
    }

    private static func controlResponse(_ line: String, id: String) -> [String: Any]? {
        guard line.contains(id), let object = json(line), object["type"] as? String == "control_response",
              let response = object["response"] as? [String: Any], response["request_id"] as? String == id else { return nil }
        return response
    }

    // MARK: - Codex

    static func codexRequests(includeHidden: Bool) -> Data {
        line(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "aris", "version": "1"]]])
            + line(["jsonrpc": "2.0", "method": "initialized"])
            + line(["jsonrpc": "2.0", "id": 2, "method": "model/list", "params": ["includeHidden": includeHidden]])
    }

    /// `model/list`'s answer: the models the picker shows (hidden ones only when asked for), the default first.
    static func codexModels(_ line: String, includeHidden: Bool = false) -> [ArisModelOption]? {
        guard let object = json(line), object["id"] as? Int == 2,
              let data = (object["result"] as? [String: Any])?["data"] as? [[String: Any]] else { return nil }
        let shown = data.filter { includeHidden || $0["hidden"] as? Bool != true }
        let ordered = shown.filter { $0["isDefault"] as? Bool == true } + shown.filter { $0["isDefault"] as? Bool != true }
        return ordered.compactMap { model in
            guard let id = (model["model"] as? String) ?? (model["id"] as? String), ArisModelChoices.isModelID(id) else { return nil }
            let efforts = (model["supportedReasoningEfforts"] as? [[String: Any]] ?? []).compactMap { $0["reasoningEffort"] as? String }
                .filter(ArisModelChoices.effortWords.contains)
            let detail = (model["description"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
            return ArisModelOption(id: id, title: (model["displayName"] as? String).map { String($0.prefix(60)) } ?? id, detail: detail, efforts: efforts)
        }
    }

    // MARK: - Antigravity

    /// `agy models`: "id<TAB>name" lines (its "Fetching…" line and anything else are skipped).
    static func agyModels(_ text: String) -> [ArisModelOption] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, ArisModelChoices.isModelID(parts[0]) else { return nil }
            return ArisModelOption(id: parts[0], title: String(parts[1].prefix(60)))
        }
    }

    // MARK: - A typed id

    /// Whether `id` is one a listing tool takes: on its list (hidden ones too), or one of today's own names.
    static func listedCheck(_ id: String, brain: ArisBrain, listed: [ArisModelOption]?) -> Check {
        guard let listed else { return .unchecked }
        let ownNames = ArisModelLists.fixed(brain).map(\.id)
        if listed.contains(where: { $0.id == id }) || ownNames.contains(id) { return .ok(resolved: nil) }
        return .unknown("")
    }

    /// The line under the field for an id that isn't taken.
    static func unknownLine(_ id: String, brain: ArisBrain, korean: Bool = true) -> String {
        korean ? "\(brain.shortTitle)에서 쓸 수 없는 모델이에요: \(id)" : "\(brain.shortTitle(english: true)) can't use this model: \(id)"
    }

    // MARK: - Pieces

    private static func line(_ object: [String: Any]) -> Data {
        ((try? JSONSerialization.data(withJSONObject: object)) ?? Data()) + Data("\n".utf8)
    }

    private static func json(_ line: String) -> [String: Any]? {
        line.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

// MARK: - Asking the tools

extension ArisModelDiscovery {
    static let deadline: TimeInterval = 20

    /// `brain`'s models from its tool; nil when it couldn't list (not installed, slow, an answer it couldn't read).
    static func list(_ brain: ArisBrain, environment: [String: String]) -> [ArisModelOption]? {
        switch brain {
        case .claude:
            let request = claudeRequest("aris-models", ["subtype": "initialize"])
            return ask(.claude, claudeArguments, input: request, environment: environment) { claudeModels($0) }
        case .codex:
            return ask(.codex, ["app-server", "-c", "notify=[]"], input: codexRequests(includeHidden: false), environment: environment) { codexModels($0) }
        case .antigravity:
            let output = ask(.antigravity, ["models"], input: nil, environment: environment, untilExit: true) { _ -> String? in nil }
            return output.map(agyModels).flatMap { $0.isEmpty ? nil : $0 }
        case .api:
            return nil
        }
    }

    /// Whether `brain`'s tool takes `id` (see the top of the file for how each is asked).
    static func check(_ id: String, brain: ArisBrain, environment: [String: String]) -> Check {
        guard ArisModelChoices.isModelID(id) else { return .unknown("") }
        switch brain {
        case .claude:
            let request = claudeRequest("aris-check", ["subtype": "set_model", "model": id])
            return ask(.claude, claudeArguments, input: request, environment: environment) { claudeCheck($0) } ?? .unchecked
        case .codex:
            let all = ask(.codex, ["app-server", "-c", "notify=[]"], input: codexRequests(includeHidden: true), environment: environment) {
                codexModels($0, includeHidden: true)
            }
            return listedCheck(id, brain: .codex, listed: all)
        case .antigravity:
            return listedCheck(id, brain: .antigravity, listed: list(.antigravity, environment: environment))
        case .api:
            return .unchecked
        }
    }

    /// Starts `brain`'s tool with `arguments` in an empty folder of its own, writes `input` (kept open: these tools stop
    /// at the end of their input), and reads its output until `read` makes something of a line, or (`untilExit`) the
    /// tool ends; then it is ended. Nil at the deadline or when the tool isn't there.
    private static func ask<T>(_ brain: ArisBrain, _ arguments: [String], input: Data?, environment: [String: String],
                               untilExit: Bool = false, read: @escaping (String) -> T?) -> T? {
        guard let executable = ArisReadJudge.executable(brain) else { return nil }
        let folder = ArisSealedScratch.make()
        defer { folder.map(ArisSealedScratch.remove) }
        let process = ArisExactProcess()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ArisReadJudge.environment(brain: brain, base: environment)
        if let folder { process.currentDirectoryURL = folder }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let lines = ArisModelProbeLines<T>(read: read)
        stdout.fileHandleForReading.readabilityHandler = { lines.append($0.availableData) }
        do { try ArisChildren.run(process) } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        if let input { ArisChildFeed.feed(input, to: stdin.fileHandleForWriting, closing: false) }
        let end = Date().addingTimeInterval(deadline)
        while Date() < end, lines.found == nil, process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        if untilExit, !process.isRunning { lines.append((try? stdout.fileHandleForReading.readToEnd()) ?? Data()) }
        stdout.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { ArisProcessEnd.end(process) }
        try? stdin.fileHandleForWriting.close()
        if untilExit { return process.terminationReason == .exit && process.terminationStatus == 0 ? lines.text as? T : nil }
        return lines.found
    }
}

/// A probe's output as it comes: each whole line is offered to `read` until it makes something of one.
private final class ArisModelProbeLines<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var all = Data()
    private var result: T?
    private let read: (String) -> T?

    init(read: @escaping (String) -> T?) { self.read = read }

    var found: T? { lock.withLock { result } }
    var text: String { lock.withLock { String(decoding: all.prefix(256 * 1_024), as: UTF8.self) } }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            if all.count < 256 * 1_024 { all.append(data) }
            guard result == nil else { return }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                if let made = read(line) {
                    result = made
                    return
                }
            }
            // A single answer line can be long (Claude Code's initialize is ~20 KB), but never this long.
            if pending.count > 1_024 * 1_024 { pending.removeAll() }
        }
    }
}
