//
//  ArisCapabilityGate.swift
//  aris-agent
//
//  The one gate entry for a capability call (ARCHITECTURE 3.4): `decide(argv, tools:, turn:)`, whoever calls. It adds
//  no rule of its own: it sends the call, as the very shell command the old path judged, to the policy code that
//  judged it there, with that caller's state.
//  · An API brain (ArisAPIDriver): a sealed process's list, a teammate's scopes, then ArisAPIGate (Codex's approve path:
//    ArisRiskPolicy, the read judge on a careful turn, the taint rules, remembered yeses).
//  · A write a Claude or agy hands over (POST /action-tool, ArisActionRelay): ArisActionGate.
//  · The open Claude's own turn gate (ArisTurnGate.run, its PreToolUse hook): for a call of the MCP face, which Claude
//    Code doesn't send to the hook (ArisHandsFace), the shim asks this with the hook's own environment and judge.
//  · `arisCore2` on (the MCP face, the provider's only tools): the trust policy (ArisTrustDeciding), whose stub until
//    jv-trust's lands gives every call today's open-Claude answer (ArisTodayTrust); the never-list holds regardless.
//  The services (ArisMCPPolicy), computer use (ArisDesktopGate), Aside, skills, sessions and routines keep their own
//  routes, which every brain's call reaches as before; their gates are unchanged.
//

import Foundation

enum ArisCapabilityGate {
    enum Turn {
        /// An API brain's call: its conversation's gate, a sealed (hands-free) process, a teammate's scopes.
        case api(ArisAPIGate, sealed: Bool, handsFree: Bool, scopes: Set<ArisTeammateScope>?)
        /// A write handed to the agent by a brain with no gate of its own.
        case handOff(ArisMessageTurn, home: String, declined: Bool, alwaysAsks: Bool)
        /// The open Claude's turn gate: the hook's environment (its mark's folder, a job's careful flag, a teammate's
        /// scopes) and its read judge.
        case claude(environment: [String: String], judge: (ArisReadCall) -> ArisReadVerdict)
        /// `arisCore2`: the trust policy decides (ArisTrustDeciding; ArisTodayTrust until jv-trust's lands).
        case trust(ArisTrustDeciding, ArisTrustCall)
    }

    enum Decision {
        /// An API brain's turn stops (a sealed process's call off its list).
        case stop
        /// An API brain's call refused before its gate (a teammate's scopes), with its audit line.
        case refused(reason: String, audit: String)
        /// ArisAPIGate's own answer.
        case api(ArisAPIGateDecision)
        /// ArisActionGate's answer and its audit line.
        case handOff(ArisActionGate.Decision, audit: String)
        /// The turn gate's answer, as its hook exits: 0 runs the call, 2 blocks it with the reason.
        case hook(code: Int32, reason: String?)
        /// The trust policy's answer.
        case trust(ArisTrustVerdict)
    }

    static func decide(_ argv: [String], stdin: String? = nil, tools: String, turn: Turn) -> Decision {
        switch turn {
        case .api(let gate, let sealed, let handsFree, let scopes):
            // The sealed process: only a command the sealed Claude may run (its list, the user's app reads, the services).
            if sealed, !ArisSealedTools.allows(argv, memory: !handsFree) { return .stop }
            // A teammate's call outside what it may use: refused, never asked.
            if let scopes, !ArisTeammateScope.allows(toolsArguments: argv, scopes: scopes) {
                let command = ArisAPICatalog.command(tools: tools, argv: argv)
                return .refused(reason: ArisTeammateScope.refusalLine(ArisTeammateScope.needed(forTools: argv).map { $0.subtracting(scopes) }),
                                audit: String(decoding: (try? JSONSerialization.data(withJSONObject: ["action": command, "risk": "never (outside the teammate's scopes)"],
                                                                                     options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self))
            }
            return .api(gate.judge(ArisAPICatalog.command(tools: tools, argv: argv)))
        case .handOff(let turn, let home, let declined, let alwaysAsks):
            let decided = ArisActionGate.decide(argv, turn: turn, tools: tools, home: home, declined: declined, alwaysAsks: alwaysAsks)
            return .handOff(decided.decision, audit: decided.audit)
        case .claude(let environment, let judge):
            let input = hookInput(argv, stdin: stdin, tools: tools)
            // The aris-tools hook's own order (ArisTools/main.swift, turn-gate): a teammate's scopes, then the gate.
            let scopes = ArisCapabilityLocal.scopes(environment: environment)
            let words = { (command: String) in ArisCommandPolicy.segments(command)?.map { ArisCommandPolicy.words($0) ?? [] } }
            let desktop = { (command: String) in ArisDesktopShell.parse(command, tools: tools)?.words }
            if let refusal = ArisTeammateScope.hookRefusal(input: input, tools: tools, scopes: scopes, words: words, desktop: desktop) {
                return .hook(code: 2, reason: refusal)
            }
            let answer = ArisTurnGate.run(input: input, tools: tools, environment: environment, judge: judge)
            return .hook(code: answer.code, reason: answer.reason)
        case .trust(let policy, let call):
            // The never-list holds whatever the policy says.
            if call.effect == .never { return .trust(.refuse(ArisCapabilityGate.neverLine)) }
            return .trust(policy.decide(call))
        }
    }

    /// ArisActionGate's answer for a handed-off write, through the one entry.
    static func handOff(_ words: [String], turn: ArisMessageTurn, tools: String, home: String, declined: Bool,
                        alwaysAsks: Bool) -> (decision: ArisActionGate.Decision, audit: String) {
        guard case .handOff(let decision, let audit) = decide(words, tools: tools, turn: .handOff(turn, home: home, declined: declined, alwaysAsks: alwaysAsks)) else {
            return (.refused(ArisActionGate.refusal), "{}")
        }
        return (decision, audit)
    }

    static let neverLine = "Refused by Aris's safety rules (the never-list); don't try another way."

    // MARK: - The shell command a call stands for

    /// The line the open Claude's Bash would run for this call: every word quoted so it reads back as exactly these
    /// words, and a desktop call's text in a heredoc (as the prompt teaches it), so the gates read the same command.
    static func shellLine(_ argv: [String], stdin: String?, tools: String) -> String {
        let line = ArisAPICatalog.command(tools: tools, argv: argv)
        guard let stdin else { return line }
        var delimiter = "ARIS_TEXT"
        let lines = Set(stdin.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        var count = 0
        while lines.contains(delimiter) { count += 1; delimiter = "ARIS_TEXT_" + String(repeating: "X", count: min(count, 6)) }
        return line + " <<'" + delimiter + "'\n" + stdin + "\n" + delimiter
    }

    /// The PreToolUse input Claude Code would have given the hook for that Bash call.
    static func hookInput(_ argv: [String], stdin: String?, tools: String) -> Data {
        let object: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": shellLine(argv, stdin: stdin, tools: tools)]]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

// MARK: - In-process runs (the agent's side)

extension ArisCapabilityLocal {
    /// The words that run here: exactly the registry's rows that say so.
    static func handles(_ argv: [String]) -> Bool {
        guard let first = argv.first, ["memory", "recall", "shelf"].contains(first) else { return false }
        return ArisCapabilities.runsInProcess(argv)
    }

    /// One call run here; nil for one an aris-tools child runs. `folder`: Aris's own folder (~/.config/aris/aris; the
    /// tests' scratch one); `home`: the home the shelf file is under; `scopes`: a teammate's, as aris-tools finds them.
    static func run(_ argv: [String], environment: [String: String], folder: URL, home: String,
                    scopes: ([String: String]) -> Set<ArisTeammateScope>? = { ArisCapabilityLocal.scopes(environment: $0) }) -> Output? {
        guard handles(argv) else { return nil }
        if let refusal = refusal(argv, environment: environment, scopes: scopes(environment)) { return .failed(refusal) }
        switch argv[0] {
        case "memory": return memory(argv.dropFirst().joined(separator: " "), folder: folder)
        case "recall": return recall(argv, folder: folder)
        case "shelf": return shelf(home: home)
        default: return nil
        }
    }

    static var ownFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris") }

    /// The API brain's helper process: its own environment as an aris-tools child of it gets it (ArisAPIHelper.runTools).
    static func live(_ argv: [String]) -> Output? {
        run(argv, environment: ArisAPIHelper.scrubbed(ProcessInfo.processInfo.environment), folder: ownFolder,
            home: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
