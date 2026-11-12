//
//  ArisAPIDriver.swift
//  aris-agent
//
//  The API brain (cleanroom spec 14): any provider with a key (OpenAI-compatible, Anthropic, Gemini) or a local server,
//  driven like Codex's app-server through its helper process (`aris-agent api-brain`, ArisAPIHelper). All policy is
//  here, in Aris: every function call the model makes becomes an aris-tools argv, then the command the risk gate judges
//  (ArisAPIGate: the Codex approve path), and the helper runs it only after this driver writes `allow` with that argv.
//  A call to a function that wasn't offered, arguments that don't parse, a sealed turn's command off the sealed list,
//  or more than eight rounds in a turn stop the turn. Taint is exact: every call's kind is known before it runs, so a
//  read makes the conversation outside text, and so does anything the helper couldn't read (fail closed). A turn that
//  saw the screen keeps every function (the gate knows the screen came in: reads judged, what the user's words don't cover
//  asked on his card). Only a hands-free turn runs the sealed process: offered only the sealed subset, with
//  ARIS_SEALED=1, so aris-tools refuses the rest again.
//

import Foundation

final class ArisAPIDriver: ArisBrainDriver {
    static let quietKinds: Set<String> = ["tool_done", "notice"]
    var quietKinds: Set<String> { Self.quietKinds }

    let profile: ArisAPIProfile?
    let tools: String
    let sealed: Bool
    let task: Bool
    let handsFree: Bool
    /// The program the helper runs as (this binary), and whether a key is saved (a provider that needs one).
    private let executable: URL?
    private let hasKey: () -> Bool
    let gate: ArisAPIGate
    private let instructions: String
    /// A teammate's job: what it may use (ArisTeammateScope); a call outside it is refused before the gate.
    var scopes: Set<ArisTeammateScope>?

    /// The calls waiting for an answer, by confirmation id: the helper's call id, its argv and its command.
    private var asking: [String: (call: String, argv: [String], command: String)] = [:]
    private var pendingActions: [String: ArisPendingAction] = [:]
    /// The argv of each call this turn by the helper's id, to read its result's taint.
    private var calls: [String: [String]] = [:]
    /// The text each call's aris-tools reads on stdin (a desktop type or set-value), by the helper's id.
    private var stdins: [String: String] = [:]
    private var offered: Set<String> = []
    private var inTurn = false
    /// This turn's call ids (a repeat stops it) and how many calls each round made.
    private var seenIds: Set<String> = []
    private var roundCalls: [Int: Int] = [:]
    /// Made-up function names answered as a tool error this turn (ArisAPIUnknownTool).
    private var unknownCalls = 0

    static let maxRounds = 8

    init(profile: ArisAPIProfile?, tools: String, sealed: Bool = false, task: Bool = false, handsFree: Bool = false,
         home: String = FileManager.default.homeDirectoryForCurrentUser.path,
         executable: URL? = ArisAppBundle.ownProgram, hasKey: @escaping () -> Bool = { true }) {
        self.profile = profile
        self.tools = tools
        self.sealed = sealed || handsFree
        self.task = task
        self.handsFree = handsFree
        self.executable = executable
        self.hasKey = hasKey
        // A job, and the sealed process (hands-free), judge every read from the first (as the sealed Claude's hook).
        gate = ArisAPIGate(tools: tools, home: home, task: task || sealed || handsFree)
        // Only a profile whose every model searches the web itself is told it can; any other is told the truth: `web fetch`
        // for a page it can name, and what the user can do for a search (audit imp-api-web-13).
        let models = [profile?.quick, profile?.strong].compactMap { $0 }.filter { !$0.isEmpty }
        instructions = self.sealed ? ArisAgentPrompt.sealed(tools: ArisAPICatalog.generic, handsFree: handsFree, task: task, functions: true)
            : ArisAgentPrompt.system(tools: ArisAPICatalog.generic, gated: true, task: task, functions: true,
                                     ownSearch: !models.isEmpty && models.allSatisfy(Self.searchesOnItsOwn))
    }

    var title: String { profile?.preset?.title ?? "API" }

    /// The prompt names the commands `aris …`; the gate and the card read them with aris-tools' real path.
    func launch() -> (URL, [String])? {
        guard missing == nil, let profile, let executable else { return nil }
        return (executable, ["api-brain", "--profile", profile.id])
    }

    /// What keeps it from starting: no provider or model chosen yet, or a provider that needs a key with none saved.
    var missing: ArisBrainTrouble.Missing? {
        guard let profile, let preset = profile.preset, executable != nil, !profile.quick.isEmpty || !profile.strong.isEmpty else { return .setup }
        return !preset.needsKey || hasKey() ? nil : .key
    }

    /// Nothing: the helper reads its provider, address and key from its own argv and the signed profile (C1).
    func opening() -> [Data] { [] }

    /// A model that searches the web on its own (OpenRouter's :online, Perplexity's sonar, a *search* model): what it
    /// says is outside text from the first round (I1).
    static func searchesOnItsOwn(_ model: String) -> Bool {
        model.range(of: #"(?i)(:online|search|sonar)"#, options: .regularExpression) != nil
    }

    /// Characters that make a card read differently from what runs (bidi controls, zero-width marks).
    static func hidesText(_ argv: [String]) -> Bool {
        argv.contains { word in
            word.unicodeScalars.contains { (0x202A...0x202E).contains($0.value) || (0x2066...0x2069).contains($0.value)
                || [0x200B, 0x200C, 0x200D, 0x200E, 0x200F, 0x2060, 0xFEFF, 0x061C].contains($0.value) }
        }
    }

    var takesImages: Bool { profile?.takesImages == true }

    var isolatedFolder: Bool { sealed }

    var environment: [String: String] {
        sealed ? [ArisSealedTools.environmentKey: "1"].merging(handsFree ? [ArisSealedTools.handsFreeKey: "1"] : [:]) { $1 } : [:]
    }

    func ask(_ prompt: String, tier: ArisTier) -> [Data] { ask(prompt, images: [], tier: tier) }

    func ask(_ prompt: String, images: [ArisTurnImage], tier: ArisTier) -> [Data] {
        gate.startTurn()
        gate.tier = tier
        calls = [:]
        stdins = [:]
        // Decisions belong to their turn: nothing of the last one can be answered into this one.
        asking = [:]
        pendingActions = [:]
        seenIds = []
        roundCalls = [:]
        unknownCalls = 0
        inTurn = true
        let sent = takesImages ? images : []
        if !sent.isEmpty { markScreenSeen() }
        offered = ArisAPICatalog.names(sealed: sealed)
        let functions = ArisAPICatalog.functions(sealed: sealed).map(\.name)
        let relay = profile?.callsTools == false
        let model = profile?.model(tier: tier) ?? ""
        if Self.searchesOnItsOwn(model.isEmpty ? (profile?.quick ?? "") : model) { gate.markUntrusted() }
        return [Self.line(["type": "ask", "system": instructions, "text": prompt, "model": model.isEmpty ? (profile?.quick ?? "") : model,
                           "functions": relay ? [String]() : functions, "relay": relay, "maxRounds": Self.maxRounds,
                           "images": sent.map { ["mime": $0.format.rawValue, "data": $0.base64, "label": $0.label] }])]
    }

    /// Aside started: the helper's turn waits for it, once (ArisAPIHelper.asideDeadline).
    func asideStarted() -> [Data] { [Self.line(["type": "aside"])] }

    func read(_ line: String) -> [ArisBrainEvent] {
        guard let data = line.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            if inTurn, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { gate.markUntrusted() }
            return []
        }
        switch object["type"] as? String {
        case "delta":
            guard let text = object["text"] as? String, !text.isEmpty else { return [] }
            return [.delta(text)]
        case "tool_request":
            return request(object)
        case "tool_done":
            // Whatever came back is in the model's hands now: outside text unless the call is one that brings nothing
            // anyone else wrote (a service call is marked by the agent's one gate, before the service is reached).
            // Nor a small write that worked and is answered in fixed words (the helper hands the model only "done" for
            // it, as the agent does for a Claude: ArisActionGate.reported), so a to-do added on a clean turn leaves the
            // conversation clean on this brain too (VM run 2: its second to-do asked). One that failed, or whose answer
            // may name what others wrote (a to-do ticked off, an event found), still marks it.
            let fixed = object["exit"] as? Int == 0 && (object["id"] as? String).flatMap { calls[$0] }.map(ArisHandOff.answersInFixedWords) == true
            if let id = object["id"] as? String, let argv = calls[id], argv.first != "mcp", argv.first != "desktop", argv.first != "skill", !ArisTurnGate.bringsNothingIn(argv), !fixed { gate.markUntrusted() }
            // A call that exited with an error: its step's tag gets no tick.
            return ArisStepOutcome.api(toolDone: object, argv: (object["id"] as? String).flatMap { calls[$0] }, tools: tools)
        case "result":
            inTurn = false
            return [.result((object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))]
        case "error":
            inTurn = false
            return [failure(kind: object["kind"] as? String ?? "", message: object["message"] as? String ?? "")]
        case "notice":
            // Something the helper couldn't read (a malformed chunk, an unknown event, a stream cut short): fail closed.
            gate.markUntrusted()
            return []
        default:
            if inTurn { gate.markUntrusted() }
            return []
        }
    }

    static let offListStop = "API 브레인이 허용되지 않은 도구를 써서 멈췄어요."
    static let roundsStop = "API 브레인이 도구를 너무 여러 번 써서 멈췄어요. 다시 물어봐 주세요."
    static let sealedStop = "화면을 본 API 브레인이 허용되지 않은 도구를 써서 멈췄어요."
    /// The same lines for a request in English (ArisGateWords.lines says them; fourth VM run, bug 4: the Korean line
    /// under an English request).
    /// How long an idle `aris-agent api-brain` process is kept for the next question. It is aris-agent itself, so a
    /// new one starts at once; the runner's half hour for a CLI brain left three of them alive long after Aris quit
    /// (second upgrade run, C17).
    static let idleLife: TimeInterval = 300

    static let stopsInEnglish: [String: String] = [
        offListStop: "The API model used a tool it isn't allowed, so I stopped.",
        roundsStop: "The API model used tools too many times, so I stopped. Please ask again.",
        sealedStop: "After seeing the screen, the API model used a tool it isn't allowed, so I stopped.",
    ]

    private func request(_ object: [String: Any]) -> [ArisBrainEvent] {
        guard inTurn, let id = object["id"] as? String, let name = object["name"] as? String else { return [.abort(Self.offListStop)] }
        let round = object["round"] as? Int ?? Int.max
        guard round <= Self.maxRounds else { return [.abort(Self.roundsStop)] }
        // One id once a turn, and at most eight calls a round.
        guard seenIds.insert(id).inserted else { return [.abort(Self.offListStop)] }
        roundCalls[round, default: 0] += 1
        guard roundCalls[round] ?? 0 <= ArisAPIHelper.maxCallsPerRound else { return [.abort(Self.roundsStop)] }
        guard offered.contains(name), let argv = ArisAPICatalog.argv(name: name, arguments: object["arguments"] as? String ?? "") else {
            // A name that is no tool of Aris's at all (the model made one up): told as a tool error it can go on from,
            // at most twice a turn. A real tool this turn was not offered, any off-list call of a sealed or hands-free
            // turn, and a third made-up name still stop the turn (ArisAPIUnknownTool).
            if ArisAPIUnknownTool.answered(name: name, known: ArisAPICatalog.names(sealed: false).union(ArisAPICatalog.names(sealed: true)),
                                           offered: offered, sealed: sealed, soFar: unknownCalls) {
                unknownCalls += 1
                return [.send(Self.line(["type": "deny", "id": id, "reason": ArisAPIUnknownTool.reason(name: name, offered: offered)])),
                        .audit(String(decoding: (try? JSONSerialization.data(withJSONObject: ["action": "function " + ArisAPIUnknownTool.shown(name),
                                                                                                "risk": "error result (no such tool; nothing ran)"],
                                                                             options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self))]
            }
            return [.abort(handsFree ? ArisHandsFree.askAgainLine : Self.offListStop)]
        }
        let command = ArisAPICatalog.command(tools: tools, argv: argv)
        // The sealed process: only a command the sealed Claude may run (its list, the user's app reads, the services).
        if sealed, !ArisSealedTools.allows(argv, memory: !handsFree) {
            return [.abort(handsFree ? ArisHandsFree.askAgainLine : Self.sealedStop)]
        }
        // A teammate's call outside what it may use: refused, never asked.
        if let scopes, !ArisTeammateScope.allows(toolsArguments: argv, scopes: scopes) {
            return [.send(Self.line(["type": "deny", "id": id, "reason": ArisTeammateScope.refusalLine(ArisTeammateScope.needed(forTools: argv).map { $0.subtracting(scopes) })])),
                    .audit(String(decoding: (try? JSONSerialization.data(withJSONObject: ["action": command, "risk": "never (outside the teammate's scopes)"],
                                                                         options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self))]
        }
        calls[id] = argv
        // A desktop type or set-value's text goes on aris-tools' stdin (only its own functions carry one; the generic
        // form's call then has none, and the desktop engine says how to send it).
        if argv.first == "desktop", argv.last == "--stdin", let text = ArisAPICatalog.stdin(name: name, arguments: object["arguments"] as? String ?? "") {
            stdins[id] = text
        }
        let seen: [ArisBrainEvent] = [.tools([ArisAgentStream.ToolCall(name: "Bash", command: command)]),
                                      .status(ArisAgentStatus.forCommand(command, tools: tools))]
        switch gate.judge(command) {
        case .allow(let audit):
            return seen + [.send(allowLine(id, argv)), .audit(audit)]
        case .deny(let audit, let reason):
            calls[id] = nil
            return [.send(Self.line(["type": "deny", "id": id, "reason": reason])), .audit(audit)]
        case .read(let ask, let pending, let audit):
            asking[ask.id] = (id, argv, command)
            pendingActions[ask.id] = pending
            return seen + [.confirm(ask), .audit(audit)]
        case .ask(let ask, let pending, _, let audit):
            // A card must read as what runs.
            if Self.hidesText(argv) {
                calls[id] = nil
                return [.send(Self.line(["type": "deny", "id": id, "reason": "Refused: the words carry hidden or direction-changing characters."])),
                        .audit(audit)]
            }
            asking[ask.id] = (id, argv, command)
            pendingActions[ask.id] = pending
            return seen + [.confirm(ask), .audit(audit)]
        }
    }

    private func failure(kind: String, message: String) -> ArisBrainEvent {
        // A failed turn may have left anything half read: fail closed.
        gate.markUntrusted()
        let said = ArisAPISecrets.redacted(message)
        switch ArisAPIError.Kind(rawValue: kind) {
        case .quota, .rate, .overloaded:
            return .unavailable(said.isEmpty ? "rate limit" : said)
        case .auth:
            ArisFixTurns.shared.note(.settings(.key))
            return .failure(ArisAPIFailureWords.line(.key, title: title, english: false))
        case .malformed where said == "rounds" || said == "calls":
            return .abort(Self.roundsStop)
        case .context:
            return .failure(ArisAPIFailureWords.line(.tooLong, title: title, english: false))
        case .network, .timeout:
            ArisFixTurns.shared.note(.retry)
            return .failure(ArisAPIFailureWords.line(.unreachable, title: title, english: false))
        default:
            return .failure("\(title): \(String(said.prefix(ArisBrainFailure.longest)))")
        }
    }

    static func allowLine(_ id: String, _ argv: [String], stdin: String? = nil) -> Data {
        // The helper runs exactly this argv: aris-tools may send its message, once (ArisMessagePass).
        ArisMessagePass.mint(argv: argv)
        ArisActionGrants.shared.mint(argv: argv)
        return line(["type": "allow", "id": id, "argv": argv].merging(stdin.map { ["stdin": $0] } ?? [:]) { $1 })
    }

    /// The allow line with the call's stdin text, if it has one.
    private func allowLine(_ id: String, _ argv: [String]) -> Data { Self.allowLine(id, argv, stdin: stdins[id]) }

    // MARK: - Answers

    func decide(_ id: String, allow: Bool) -> [Data] {
        pendingActions[id] = nil
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        gate.answered(id, allow: allow)
        if !allow { calls[waiting.call] = nil }
        return [allow ? allowLine(waiting.call, waiting.argv)
                : Self.line(["type": "deny", "id": waiting.call, "reason": "The user said no (their choice, not a refusal by the system). Don't try another way now; say plainly, in their terms, that you won't (\"알겠어요, 안 할게요.\" / \"OK, I won't.\"), never that it was denied. A later request in a new turn gets a new card."])]
    }

    func approveOnce(_ id: String) -> [Data] {
        pendingActions[id] = nil
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        gate.approvedOnce(id)
        return [allowLine(waiting.call, waiting.argv)]
    }

    func declineEdited(_ id: String, arguments: [String], note: String) -> [Data] {
        gate.sentEdited(pendingActions[id]?.action, arguments: arguments)
        pendingActions[id] = nil
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        calls[waiting.call] = nil
        return [Self.line(["type": "result", "id": waiting.call, "text": note])]
    }

    func refuseRead(_ id: String, note: String) -> [Data] {
        pendingActions[id] = nil
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        calls[waiting.call] = nil
        return [Self.line(["type": "result", "id": waiting.call, "text": note])]
    }

    func escalation(for id: String) -> ArisPendingAction? { pendingActions[id] }

    func setRequest(_ text: String) { gate.request = text }
    func setHandsFree(_ handsFree: Bool) { gate.handsFree = handsFree || self.handsFree }
    func markUntrusted() { gate.markUntrusted() }
    func markScreenSeen() { gate.markScreenSeen() }
    func markAppRead(_ app: String) { gate.markAppRead(app) }
    func taint(forApp app: String) -> ArisTaint { gate.taint(forApp: app) }
    var taint: ArisTaint { gate.taint }

    func reset() {
        gate.reset()
        asking = [:]
        pendingActions = [:]
        calls = [:]
        inTurn = false
    }

    func newConversation() -> [Data]? {
        reset()
        return [Self.line(["type": "new_conversation"])]
    }
}

/// A call to a function that is no tool of Aris's at all (fourth VM run, bug 4: one made-up name ended the whole turn
/// 1.2 s in). Such a name runs nothing and reaches nothing, so on an ordinary turn it is answered to the model as a
/// tool error ("no such tool; the tools are: …") and the model goes on, at most `most` times a turn. It is not the
/// sealed rule's case: a real tool that this turn was not offered, and any off-list call of a sealed or hands-free
/// turn (the model has seen the screen or is unattended), stop the turn as before. Foundation only (tested).
enum ArisAPIUnknownTool {
    static let most = 2

    /// `known`: every function Aris has, offered this turn or not; `offered`: this turn's; `sealed`: a sealed or
    /// hands-free turn; `soFar`: made-up names already answered this turn.
    static func answered(name: String, known: Set<String>, offered: Set<String>, sealed: Bool, soFar: Int) -> Bool {
        !sealed && !offered.isEmpty && !offered.contains(name) && !known.contains(name) && soFar < most
    }

    /// The name as the ledger and the model see it again: its plain characters, cut short.
    static func shown(_ name: String) -> String {
        let plain = name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || "_.-".unicodeScalars.contains($0) }
        let text = String(String.UnicodeScalarView(plain.prefix(60)))
        return text.isEmpty ? "(unnamed)" : text
    }

    static func reason(name: String, offered: Set<String>) -> String {
        "no such tool: \(shown(name)). Nothing ran. Use one of the tools you were given, or answer in words. The tools are: \(offered.sorted().joined(separator: ", "))."
    }
}
