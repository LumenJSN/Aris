//
//  ArisAutoCheckLive.swift
//  aris-agent
//
//  The automatic check's live half (ArisAutoCheck): who is asked. The checker
//  is the quick model of the brain that is acting, through the drivers Aris already has and nothing new: Claude and
//  Codex as one sealed process each, exactly as the read judge runs them (ArisReadJudge: no tools, no MCP, no web, no
//  hooks or user settings, nothing kept, an empty folder of its own, ended at its deadline); an API brain as one HTTP
//  call with no functions, on its quick model, and only a keyed provider's (a local model's yes isn't worth the user's).
//  No such route (no quick model, no key, the program missing): nobody checks, and every card is today's. Once a
//  checker is asked, a failure of any kind (the network included) or no answer by the budget stops the action: nothing
//  ever runs because the check could not be made.
//
//  What keeps other instructions out of the checker, per brain (the code's part; a VM run with planted files decides):
//  - Claude: the instruction is the whole system prompt (--system-prompt replaces Claude Code's own); --setting-sources ""
//    loads no user, project or local settings (which is also what loads CLAUDE.md and user memory); hooks off; no MCP
//    server; --tools ""; nothing persisted; the folder is a new empty one, so there is no project file to find.
//  - API brain: the instruction is the request's system prompt; no file is read at all.
//  - Codex: `codex exec` has no system-prompt flag (codex-cli 0.166.0's `exec --help`), but its config takes
//    `developer_instructions`, a developer message ahead of the user's: the instruction goes there with `-c`
//    (security review 9, L5), and stays at the head of the user message too, so a Codex that ignored the key still
//    checks. --ignore-user-config (no ~/.codex/config.toml), --ignore-rules, project_doc_max_bytes=0 (no AGENTS.md
//    from the folder), every tool feature disabled, a new empty folder. The CLI has no flag or key that skips the
//    global AGENTS.md in CODEX_HOME (its docs: read first, within project_doc_max_bytes, which may or may not leave
//    it out at 0), and CODEX_HOME can't be moved without losing the login: whether one is still read is for a VM run
//    with a planted file to tell.
//

import Foundation

enum ArisAutoCheckLive {
    /// How long one check may take. An API brain answers over one HTTP call: about three seconds. A CLI brain's own
    /// program takes several seconds just to start (the read judge allows it 15 and retries at 6), so it gets longer;
    /// the notch shows "시킨 일이 맞는지 확인 중" meanwhile, and past the budget the action stops, it never runs.
    static let apiBudget: TimeInterval = 3
    static let cliBudget: TimeInterval = 10

    /// The checker for a turn `brain` is answering; nil when no AI can check.
    static func checker(_ brain: ArisBrain, environment: [String: String]) -> ArisAutoChecking? {
        switch brain {
        case .api:
            guard let profile = ArisAPIActive.profile(), ArisAPIActive.isReady, profile.preset?.needsKey == true, !profile.quick.isEmpty,
                  ArisAPIActive.key(for: profile) != nil else { return nil }
            return ArisAPIAutoChecker(profile: profile)
        case .claude, .codex:
            guard let executable = ArisReadJudge.executable(brain) else { return nil }
            return ArisCLIAutoChecker(brain: brain, executable: executable, environment: environment)
        // Antigravity's own process can't be left without its web search: it never checks (its writes always ask).
        case .antigravity: return nil
        }
    }
}

/// One no-functions call on the API brain's quick model.
final class ArisAPIAutoChecker: ArisAutoChecking {
    private let profile: ArisAPIProfile
    static let maxTokens = 1_024
    let budget = ArisAutoCheckLive.apiBudget
    var model: String { profile.quick }

    init(profile: ArisAPIProfile) { self.profile = profile }

    func check(input: String, done: @escaping (ArisAutoRun) -> Void) {
        // Room for a model that thinks before it answers (its thinking counts against the allowance on some
        // providers); the answer itself is read only up to ArisAutoCheck.maxReply.
        ArisAPIOneShot.ask(profile: profile, model: profile.quick, system: ArisAutoCheck.instruction, user: input, timeout: budget,
                           key: ArisAPIActive.key(for: profile), maxTokens: Self.maxTokens) { result in
            switch result {
            case .success(let answer): done(.answered(String(answer.text.prefix(ArisAutoCheck.maxReply + 1))))
            case .failure(let error): done(error.kind == .timeout ? .late : .failed)
            }
        }
    }
}

/// One sealed process of Claude or Codex on its quick model, in an empty folder of its own, ended at the budget.
final class ArisCLIAutoChecker: ArisAutoChecking {
    private let brain: ArisBrain
    private let executable: URL
    private let environment: [String: String]
    let budget = ArisAutoCheckLive.cliBudget
    var model: String { brain.model(tier: .quick) }

    init(brain: ArisBrain, executable: URL, environment: [String: String]) {
        self.brain = brain
        self.executable = executable
        self.environment = environment
    }

    /// The sealed one-shot's command line (ArisSealedOneShot: Claude takes the instruction as its system prompt), and
    /// for Codex also no project instruction file (the flag goes before the "-" that reads the prompt from stdin).
    static func arguments(brain: ArisBrain, model: String) -> [String] {
        let sealed = ArisSealedOneShot.arguments(brain: brain, model: model, instruction: ArisAutoCheck.instruction)
        guard brain == .codex, sealed.last == "-" else { return sealed }
        return sealed.dropLast() + ["-c", "project_doc_max_bytes=0", "-c", "developer_instructions=" + tomlString(ArisAutoCheck.instruction), "-"]
    }

    /// `text` as a TOML basic string (what `-c key=value` parses its value as): quotes, backslashes and control
    /// characters escaped, so the instruction arrives exactly as written.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    func check(input: String, done: @escaping (ArisAutoRun) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let folder = ArisSealedScratch.make()
            defer { folder.map(ArisSealedScratch.remove) }
            done(run(input: input, folder: folder))
        }
    }

    private func run(input: String, folder: URL?) -> ArisAutoRun {
        let process = ArisExactProcess()
        process.executableURL = executable
        process.arguments = Self.arguments(brain: brain, model: model)
        process.environment = ArisReadJudge.environment(brain: brain, base: environment)
        if let folder { process.currentDirectoryURL = folder }
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let reply = ArisAutoReply()
        stdout.fileHandleForReading.readabilityHandler = { reply.append($0.availableData) }
        defer { stdout.fileHandleForReading.readabilityHandler = nil }
        // Through the one place the helper starts anything (ArisChildren: written down, the AI's program as approved;
        // a program that waits for the owner's yes is not started, and the check then stops the action).
        do { try ArisChildren.run(process) } catch {
            ArisProcessEnd.end(process)
            return .failed
        }
        // Written on its own queue, with the reader and the deadline already going (ArisChildFeed).
        ArisChildFeed.feed(ArisSealedOneShot.stdin(brain: brain, instruction: ArisAutoCheck.instruction, input: input),
                           to: stdin.fileHandleForWriting, closing: true)
        let deadline = Date().addingTimeInterval(budget)
        while Date() < deadline, process.isRunning { Thread.sleep(forTimeInterval: 0.02) }
        guard !process.isRunning else {
            ArisProcessEnd.end(process)
            return .late
        }
        guard process.terminationStatus == 0 else { return .failed }
        reply.append((try? stdout.fileHandleForReading.readToEnd()) ?? Data())
        return .answered(reply.text)
    }
}

/// The checker's stdout, gathered off its pipe's queue (only its start is ever read).
private final class ArisAutoReply: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.withLock { if data.count < 4_096 { data.append(chunk) } } }
    var text: String { lock.withLock { String(decoding: data.prefix(4_096), as: UTF8.self) } }
}
