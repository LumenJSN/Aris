//
//  ArisSealedOneShot.swift
//  aris-agent
//
//  One question to one brain in the read judge's sealed mode (ArisReadJudge: no tools, no MCP, no web, no hooks or
//  user settings, nothing kept, an empty folder of its own, ended at its deadline), with an instruction of the
//  caller's: the skills check's AI review, the "모든 AI로 시험" dry runs and 말로 만들기's drafts. What comes back is
//  only text; nothing it says is ever run.
//

import Foundation

protocol ArisOneShotAsking: AnyObject {
    /// The brain's whole answer, or nil (not installed, failed, late, or agy reached for a tool).
    func ask(_ brain: ArisBrain, instruction: String, input: String, timeout: TimeInterval) -> String?
}

final class ArisSealedOneShot: ArisOneShotAsking {
    private let environment: [String: String]

    init(environment: [String: String]) { self.environment = environment }

    /// The command line on each brain: the judge's sealed flags, the instruction as the system prompt where there is one.
    static func arguments(brain: ArisBrain, model: String, instruction: String) -> [String] {
        switch brain {
        case .claude:
            return ["-p", "--model", model, "--effort", "low", "--tools", "", "--permission-mode", "dontAsk",
                    "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
                    "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
                    "--no-session-persistence", "--output-format", "text", "--system-prompt", instruction]
        case .codex, .antigravity:
            return ArisReadJudge.arguments(brain: brain, model: model)
        case .api:
            // No process: an API brain is one HTTP call with no functions (askAPI).
            return []
        }
    }

    /// Whether `brain` can be asked on this Mac: its program is installed, or (API) a provider is set up.
    static func available(_ brain: ArisBrain) -> Bool {
        guard brain == .api else { return ArisReadJudge.executable(brain) != nil }
        guard let profile = ArisAPIActive.profile() else { return false }
        return profile.preset?.needsKey == false || ArisAPIActive.key(for: profile) != nil
    }

    static func stdin(brain: ArisBrain, instruction: String, input: String) -> Data {
        switch brain {
        case .claude, .api: return Data(input.utf8)
        case .codex: return Data((instruction + "\n\n" + input).utf8)
        case .antigravity:
            let line = (try? JSONSerialization.data(withJSONObject: ["event": "user", "message": ["content": instruction + "\n\n" + input]])) ?? Data()
            return line + Data("\n".utf8)
        }
    }

    func ask(_ brain: ArisBrain, instruction: String, input: String, timeout: TimeInterval) -> String? {
        if brain == .api { return Self.askAPI(instruction: instruction, input: input, timeout: timeout) }
        guard let executable = ArisReadJudge.executable(brain) else { return nil }
        let folder = ArisSealedScratch.make()
        defer { folder.map(ArisSealedScratch.remove) }
        let process = ArisExactProcess()
        process.executableURL = executable
        process.arguments = Self.arguments(brain: brain, model: brain.model(tier: .work), instruction: instruction)
        process.environment = ArisReadJudge.environment(brain: brain, base: environment)
        if let folder { process.currentDirectoryURL = folder }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let lines = ArisOneShotLines(agy: brain == .antigravity)
        stdout.fileHandleForReading.readabilityHandler = { lines.append($0.availableData) }
        do { try ArisChildren.run(process) } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        // Written on its own queue, with the reader and the deadline below already going: a child that stalls without
        // reading its input is ended at the deadline instead of holding this call for good (ArisChildFeed).
        ArisChildFeed.feed(Self.stdin(brain: brain, instruction: instruction, input: input), to: stdin.fileHandleForWriting, closing: brain != .antigravity)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !lines.finished, process.isRunning { Thread.sleep(forTimeInterval: 0.05) }
        stdout.fileHandleForReading.readabilityHandler = nil
        let exited = !process.isRunning
        if process.isRunning { ArisProcessEnd.end(process) }
        try? stdin.fileHandleForWriting.close()
        if brain == .antigravity { return lines.answer }
        guard exited, process.terminationStatus == 0 else { return nil }
        lines.append((try? stdout.fileHandleForReading.readToEnd()) ?? Data())
        let text = lines.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

extension ArisSealedOneShot {
    /// The API brain's one call: the active provider's strong model, the instruction as its system prompt, no functions.
    static func askAPI(instruction: String, input: String, timeout: TimeInterval) -> String? {
        guard let profile = ArisAPIActive.profile() else { return nil }
        let done = DispatchSemaphore(value: 0)
        let box = ArisSkillTextBox()
        ArisAPIOneShot.ask(profile: profile, model: profile.model(tier: .work), system: instruction, user: input, timeout: timeout,
                           key: ArisAPIActive.key(for: profile), maxTokens: 4_096) { result in
            if case .success(let answer) = result { box.set(answer.text) }
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout + 5)
        let text = box.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}

final class ArisSkillTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    func set(_ text: String) { lock.withLock { stored = text } }
    var value: String? { lock.withLock { stored } }
}

/// The answer as it comes; for agy, read through the sealed driver (a tool step ends it with no answer).
private final class ArisOneShotLines: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private var pending = Data()
    private var result: String?
    private var stopped = false
    private let agy: ArisAntigravityDriver?

    init(agy: Bool) { self.agy = agy ? ArisAntigravityDriver(model: "", instructions: "", sealed: true) : nil }

    var text: String { lock.withLock { String(decoding: data.prefix(256 * 1_024), as: UTF8.self) } }
    var finished: Bool { lock.withLock { stopped } }
    var answer: String? { lock.withLock { result } }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.withLock {
            guard data.count < 512 * 1_024 else { return }
            data.append(chunk)
            guard let agy, !stopped else { return }
            pending.append(chunk)
            while let end = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<end], as: UTF8.self)
                pending = Data(pending[(end + 1)...])
                for event in agy.read(line) {
                    switch event {
                    case .result(let text): result = text; stopped = true
                    case .abort, .failure, .unavailable: stopped = true
                    default: break
                    }
                    if stopped { return }
                }
            }
        }
    }
}
