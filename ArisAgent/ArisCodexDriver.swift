//
//  ArisCodexDriver.swift
//  aris-agent
//
//  Codex (the user's ChatGPT plan) through `codex app-server`, JSON-RPC over stdio:
//  one thread per conversation (newConversation()), so follow-ups remember it. Codex runs with
//  full access but asks before every command, edit and tool ("untrusted"), and Aris answers
//  with ArisRiskPolicy: at once, never, or after asking the user in the notch (`.confirm`,
//  then `decide`).
//  The user's own Codex MCP servers, plugins, ChatGPT apps and notifier stay off: they
//  slow every start and would hand Aris tools it shouldn't have. Computer use is the one
//  plugin kept, and only real work turns it on (every app it touches is asked about first).
//

import AppKit
import CryptoKit
import Foundation

final class ArisCodexDriver: ArisBrainDriver {
    /// app-server notifications and replies that often carry nothing for Aris (item/started, thread/*, a reply to a request).
    static let quietKinds: Set<String> = ["item/", "turn/", "thread/", "codex/", "account/", "response"]
    var quietKinds: Set<String> { Self.quietKinds }
    private let model: String
    private let tools: String
    private let home: String
    private let instructions: String
    private var nextId = 0
    private var threadRequest: Int?
    private var threadId: String?
    private var waiting: (prompt: String, images: [ArisTurnImage], tier: ArisTier)?
    /// The current turn's tier: critical turns think harder and ask before more.
    private var tier = ArisTier.quick
    /// Each edit's changes (path, diff, kind): its approval request only names the edit.
    private var editedFiles: [String: [[String: Any]]] = [:]
    /// Requests waiting for the user, by confirmation id: Codex's request id, and how to answer it.
    private var asking: [String: (request: Any, isToolQuestion: Bool, computerUseBundle: String?, remember: String?)] = [:]
    /// The action behind each waiting confirmation, for the escalation gate.
    private var pendingActions: [String: ArisPendingAction] = [:]
    /// Actions the user said yes to, and when: the same one again soon goes ahead without a second question.
    private var approved: [String: Date] = [:]
    /// The user said no in this turn: anything else that would ask is declined without asking (the AI trying
    /// another way, as printf then touch for the same file, isn't asking again).
    private var declinedThisTurn = false
    /// The owner's ②A: calls declined this turn because the agent ran the user's changed card itself (their aris-tools arguments,
    /// as the AI asked and as the user changed them): the same again this turn is a duplicate and is never run. Not a no, so
    /// the rest of the turn goes on as usual.
    private var sentForUser: Set<[String]> = []
    /// The turn under way (turn/started), which turn/steer names; and requests whose error is no failure of the turn.
    private var turnId: String?
    private var quietRequests: Set<Int> = []
    /// Codex errors that mean "not now" rather than "can't": the request can go to another AI.
    static let unavailableErrors: Set = ["usageLimitExceeded", "rateLimitExceeded", "serverOverloaded"]
    /// The user's own words for the current question (ArisRiskPolicy+Dictation).
    private var request = ""
    private var attached = ""
    /// This turn was heard hands-free (ArisHandsFree).
    private var handsFree = false
    /// When outside text first came into this thread (a web search, a tool's result, a file, the screen, Canvas).
    /// It stays in the thread's history, so sending things out asks first until a new thread (newConversation(), reset()).
    private var untrustedAt: Date? {
        // Outside text wipes every "computer use OK": the next call asks again, saying why.
        didSet {
            guard untrustedAt != nil else { return }
            computerUse.wipe()
        }
    }
    /// When the screen (an image of it) first came into this thread: screenSeen (R1 = B). Like outside text it wipes
    /// computer use's memory; an action the user's own words cover still goes as judged.
    private var screenSeenAt: Date? {
        didSet {
            guard screenSeenAt != nil else { return }
            computerUse.wipe()
        }
    }
    /// The apps (bundle ids) the user let computer use into in this conversation, while no outside text had come in, and the
    /// ones outside text wiped: the conversation's ledger, shared with `aris-tools desktop` (the runner hands its own in).
    var computerUse = ArisComputerUseLedger()
    /// A cua_repl call the user or main Aris let run, while it runs: the apps its code names (its steps there go ahead), the
    /// apps its steps asked for, and whether its finish is only its one app's own screen (clean code, one app,
    /// approved before other outside text came in).
    private struct RunningCode {
        let targets: Set<String>
        let clean: Bool
        var apps: Set<String> = []
        var unattributed = false
    }
    private var runningCode: [String: RunningCode] = [:]
    /// A cua_repl call waiting for its yes, by question id: its call id and what it would be once approved.
    private var codeAsks: [String: (call: String, code: RunningCode)] = [:]
    /// The apps (bundle ids) whose own screen computer use read in this conversation: outside text for everything but that app.
    private var screensRead: Set<String> = []
    /// How long a yes stands for the same action.
    static let approvalMemory: TimeInterval = 600
    private var asked = 0
    /// MCP tool calls still running, by item id: an MCP server's approval request doesn't name its tool, so it is
    /// matched to the one running call with the same server and arguments.
    private var runningCalls: [String: (server: String, tool: String, arguments: [String: Any])] = [:]
    private var lastMessage: String?
    /// The messages that are the answer (not Codex's notes to itself), whose pieces are spoken as they come.
    private var answerItems: Set<String> = []
    /// Each thread's running token total, so each update adds only what it used (ArisCodexUsageLedger).
    private var usageTotals: [String: ArisCodexTotals] = [:]

    /// Codex's computer use (it sees and works the Mac's apps): on for work and critical turns only, and only when the
    /// user picked it as the engine (ArisComputerEngine); otherwise Codex works apps through `aris-tools desktop`.
    static let computerUse = "unified-computer-use@openai-bundled"
    var computerEngine = ArisComputerEngine.peekaboo

    /// Aris's own Notion login (`codex mcp login aris_notion`), separate from the user's Codex setup.
    static let notionURL = "https://mcp.notion.com/mcp"
    /// What Aris may do in Notion: read and search, write pages and comments (the risk gate asks the user before any
    /// write). Nothing that deletes or moves, and no calendar: the schedule is the Mac calendar on every brain (QA BUG-16).
    static let notionTools = [
        "notion-search", "notion-fetch", "notion-query-data-sources", "notion-query-multiple-data-sources",
        "notion-list-recent-pages", "notion-query-meeting-notes", "notion-get-self",
        "notion-create-pages", "notion-update-page", "notion-create-comment",
    ]

    /// The user's ChatGPT apps Aris may use: Gmail (read, draft, send) and Contacts (who "엄마" is).
    static let gmail = "connector_2128aebfecb84f64a069897515042a44"
    static let contacts = "connector_c0f748249d6a42aea4b00fd375570ded"

    /// Every other app off; these ask the risk gate before each call, and can't delete anything.
    static var appSwitches: [String] {
        ["-c", "apps._default.enabled=false"] + [gmail, contacts].flatMap { app in
            ["-c", "apps.\(app).enabled=true", "-c", "apps.\(app).default_tools_approval_mode=\"prompt\"",
             "-c", "apps.\(app).destructive_enabled=false"]
        }
    }

    /// Aris's Notion server, its tools, and every call coming to the risk gate first ("prompt").
    static var notionSwitches: [String] {
        ["-c", "mcp_servers.aris_notion.url=\"\(notionURL)\"",
         "-c", "mcp_servers.aris_notion.enabled_tools=[" + notionTools.map { "\"\($0)\"" }.joined(separator: ",") + "]",
         "-c", "mcp_servers.aris_notion.default_tools_approval_mode=\"prompt\""]
    }

    /// Whether Codex's built-in web search is on. Off for every untrusted job (security review C1): an unattended job
    /// written from a screenshot or outside text must not be able to read something and send it out in a search.
    let webSearch: Bool

    /// A background job's process: careful from its first read (every read judged, ArisReadGate).
    let task: Bool

    /// A teammate's job: what it may use (ArisTeammateScope). Anything else is refused by the gate (never a card), a
    /// command Codex runs on its own outside them stops the turn, and the web search is off without `web`.
    var scopes: Set<ArisTeammateScope>?

    /// Said when Codex ran a command a teammate may not on its own (its read-only commands skip the approval): which
    /// switch is off (when one would allow it) and where the user turns it on (audit team-8).
    static func scopeStop(missing: Set<ArisTeammateScope>) -> String {
        guard !missing.isEmpty else { return "이 팀원이 쓸 수 없는 걸 쓰려고 해서 멈췄어요. 설정 › 팀원의 쓸 수 있는 것을 확인해 주세요." }
        let names = ArisTeammateScope.allCases.filter(missing.contains).map { "‘\($0.koreanTitle)’" }.joined(separator: ", ")
        return "이 팀원은 \(names) 권한이 꺼져 있어서 멈췄어요. 설정 › 팀원 › 쓸 수 있는 것에서 켜면 다시 맡길 수 있어요."
    }

    init(model: String, tools: String, instructions: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path,
         webSearch: Bool = true, task: Bool = false) {
        self.model = model
        self.tools = tools
        self.home = home
        self.instructions = instructions
        self.webSearch = webSearch
        self.task = task
    }

    /// Whether a read waits for the read judge (the owner, 2026-11-06): after outside text or the screen, hands-free, or in a job.
    private var careful: Bool { taint != .none || handsFree || task }

    /// The read the judge checks for this action on a careful turn: one aris-tools read of the user's apps or their memories,
    /// or a connector's read tool (Notion, Gmail); nil for anything else (it keeps its own gate and card).
    func readCall(for action: ArisAction, source: String, arguments: [String: Any]) -> ArisReadCall? {
        switch action {
        case .shell(let command):
            guard let pieces = ArisCommandPolicy.segments(command), pieces.count == 1, let words = ArisCommandPolicy.words(pieces[0]),
                  words.first == tools, words.count > 1 else { return nil }
            let rest = Array(words.dropFirst())
            if let web = ArisReadGate.web(rest), web.tool == "web fetch" { return web }
            return ArisReadGate.isJudgedRead(rest) ? ArisReadGate.call(arisTools: rest) : nil
        case .mcp(let server, let tool):
            // Only a tool named like a read (minor 11): a draft made or changed is a write, never put to the judge as a read.
            guard server != ArisRiskPolicy.computerUseRepl, ArisRiskPolicy.connectorReads(tool) else { return nil }
            return ArisReadGate.call(service: source.isEmpty ? server : source, tool: tool, arguments: arguments)
        case .fileChange, .computerUse, .browserTask:
            return nil
        }
    }

    /// The switch that turns the built-in web search off (codex-cli 0.166.0: `web_search` is disabled|cached|indexed|live;
    /// checked with config/read, which reports "disabled" under this switch).
    static func webSwitches(enabled: Bool) -> [String] {
        enabled ? [] : ["-c", #"web_search="disabled""#]
    }

    func launch() -> (URL, [String])? {
        guard let codex = Self.installed(["~/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                                          "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"]) else { return nil }
        let config = (try? String(contentsOf: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml"), encoding: .utf8)) ?? ""
        let quiet = Self.mcpServers(inConfig: config).flatMap { ["-c", "mcp_servers.\($0).enabled=false"] } + Self.pluginSwitches(inConfig: config)
        // Of the ChatGPT apps that ride along with the login (Gmail, Drive, GitHub…) only Gmail and Contacts.
        let notion = Self.notionSwitches
        // Aside isn't Codex's own tool: it is `aris-tools aside`, behind the one Aside gate every brain shares (ArisAsideTool).
        return (codex, ["app-server"] + Self.quietSwitches + quiet + notion + Self.appSwitches
                + Self.skillSwitches(Self.installedSkills()) + Self.webSwitches(enabled: webSearch && scopes?.contains(.web) != false))
    }

    /// Its thread is open (thread/start was answered); until then a question only waits.
    var isReady: Bool { threadId != nil }

    func opening() -> [Data] {
        let thread = request("thread/start", ["model": model, "approvalPolicy": "untrusted", "sandbox": "danger-full-access",
                                              "ephemeral": true, "baseInstructions": instructions])
        threadRequest = nextId
        return [request("initialize", ["clientInfo": ["name": "aris", "version": "1"]]),
                Self.line(["method": "initialized"]), thread]
    }

    func ask(_ prompt: String, tier: ArisTier) -> [Data] {
        ask(prompt, images: [], tier: tier)
    }

    var takesImages: Bool { true }

    func ask(_ prompt: String, images: [ArisTurnImage], tier: ArisTier) -> [Data] {
        declinedThisTurn = false
        sentForUser = []
        // A screen image: the thread has seen the screen from this turn's start, before its first approval (R1 = B).
        if !images.isEmpty { markScreenSeen() }
        guard let threadId else {
            waiting = (prompt, images, tier)
            return []
        }
        self.tier = tier
        return [request("turn/start", ["threadId": threadId, "effort": tier == .critical ? "high" : "low",
                                       "disabledPluginIds": tier == .quick || computerEngine != .codex ? [Self.computerUse] : [String](),
                                       "input": Self.input(prompt: prompt, images: images)])]
    }

    /// turn/start's input (app-server v2 UserInput): each image's label (other people's words, fenced) and the image
    /// as a data URL, so nothing touches disk (the thread is ephemeral), then the prompt. A circled window is read in
    /// detail; the whole screen and drawing references at Codex's own choice.
    static func input(prompt: String, images: [ArisTurnImage]) -> [[String: Any]] {
        images.flatMap { image -> [[String: Any]] in
            [["type": "text", "text": ArisAgentStream.fenced(image.label)],
             ["type": "image", "url": image.dataURL, "detail": image.kind == .gesture ? "high" : "auto"]]
        } + [["type": "text", "text": prompt]]
    }

    func read(_ line: String) -> [ArisBrainEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let params = object["params"] as? [String: Any] ?? [:]
        if let id = object["id"], let method = object["method"] as? String {
            return approve(id, method, params)
        }
        if let id = object["id"] as? Int {
            return response(id, object)
        }
        let item = params["item"] as? [String: Any] ?? [:]
        let type = item["type"] as? String ?? ""
        switch object["method"] as? String {
        case "item/started":
            if type == "commandExecution", let command = item["command"] as? String {
                let inner = ArisCommandPolicy.unwrap(command)
                // A teammate's command outside what it may use (Codex runs its read-only ones without asking): stopped.
                if let scopes, !ArisTeammateScope.permits(.shell(inner), scopes: scopes, tools: tools) {
                    // The switch is in Settings › Team: the turn's failure gets that button (ArisFixTurns).
                    ArisFixTurns.shared.note(.settings(.team))
                    return [.abort(Self.scopeStop(missing: ArisTeammateScope.missing(for: .shell(inner), scopes: scopes, tools: tools)))]
                }
                // Also when Codex ran it without asking: its output is outside text now.
                if ArisRiskPolicy.bringsInUntrusted(.shell(inner), tools: tools, home: home) { untrustedAt = Date() }
                return [.tools([ArisAgentStream.ToolCall(name: "Bash", command: inner)]), .status(ArisAgentStatus.forCommand(inner, tools: tools))]
            }
            if type == "agentMessage", let id = item["id"] as? String, (item["phase"] as? String ?? "final_answer") == "final_answer" {
                answerItems.insert(id)
            }
            if type == "fileChange", let id = item["id"] as? String {
                editedFiles[id] = item["changes"] as? [[String: Any]] ?? []
            }
            if type == "webSearch" { untrustedAt = Date() }
            if type == "mcpToolCall", let id = item["id"] as? String, let server = item["server"] as? String, let tool = item["tool"] as? String {
                runningCalls[id] = (server, tool, item["arguments"] as? [String: Any] ?? [:])
            }
            guard !["userMessage", "agentMessage", "reasoning", ""].contains(type) else { return [] }
            let status = ArisAgentStatus.forTool(type: type, server: item["server"] as? String)
            return [.tools([ArisAgentStream.ToolCall(name: type, command: nil)])] + (status.map { [.status($0)] } ?? [])
        case "item/agentMessage/delta":
            guard let id = params["itemId"] as? String, answerItems.contains(id), let delta = params["delta"] as? String else { return [] }
            return [.delta(delta)]
        case "item/completed":
            if type == "agentMessage" { lastMessage = item["text"] as? String }
            let callId = item["id"] as? String
            if type == "mcpToolCall", let callId { runningCalls[callId] = nil }
            let code = callId.flatMap { runningCode.removeValue(forKey: $0) }
            // A tool's or search's result is outside text now in the AI's hands, approved or not (Notion reads never ask);
            // only clean code whose every step was in its one app brought back nothing but that app's own screen.
            if type == "mcpToolCall", item["server"] as? String == ArisRiskPolicy.computerUseRepl, let code, code.clean, !code.unattributed,
               code.apps.isSubset(of: code.targets), let app = code.targets.first {
                screensRead.insert(app)
            } else if type == "mcpToolCall" || type == "webSearch" {
                untrustedAt = Date()
            }
            // A command that exited with an error: its step's tag gets no tick.
            return ArisStepOutcome.codex(completed: item, tools: tools)
        case "turn/started":
            turnId = (params["turn"] as? [String: Any])?["id"] as? String
            return []
        case "thread/tokenUsage/updated":
            // Aris's threads are ephemeral (no session log): the counts go to Aris's own ledger for 사용량 › Codex.
            if let update = ArisCodexUsageLedger.update(params) {
                let added = ArisCodexUsageLedger.delta(update.total, last: update.last, previous: usageTotals[update.thread])
                usageTotals[update.thread] = update.total
                ArisCodexUsageLedger.record(added, model: model.isEmpty ? "unknown" : model)
            }
            return []
        case "turn/completed":
            let turn = params["turn"] as? [String: Any] ?? [:]
            defer {
                turnId = nil
                lastMessage = nil
                answerItems = []
                editedFiles = [:]
            }
            guard turn["status"] as? String == "completed" else {
                let error = turn["error"] as? [String: Any] ?? [:]
                let message = error["message"] as? String ?? "Codex couldn't answer."
                let outOfQuota = (error["codexErrorInfo"] as? String).map(Self.unavailableErrors.contains) ?? false
                return [outOfQuota ? .unavailable(message) : ArisBrainFailure.event(message, brain: .codex)]
            }
            return [.result(lastMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")]
        default:
            return []
        }
    }

    func reset() {
        untrustedAt = nil
        screenSeenAt = nil
        computerUse.reset()
        screensRead = []
        runningCode = [:]
        codeAsks = [:]
        approved = [:]
        declinedThisTurn = false
        sentForUser = []
        turnId = nil
        quietRequests = []
        nextId = 0
        threadRequest = nil
        threadId = nil
        waiting = nil
        lastMessage = nil
        answerItems = []
        editedFiles = [:]
        asking = [:]
        pendingActions = [:]
        runningCalls = [:]
        tier = .quick
    }

    /// A new thread in the same app-server: nothing of the old one (its turns, or the outside text that made it
    /// untrusted) comes along. A question asked before the thread is ready waits for it, as at launch.
    func newConversation() -> [Data]? {
        untrustedAt = nil
        screenSeenAt = nil
        computerUse.reset()
        screensRead = []
        runningCode = [:]
        codeAsks = [:]
        approved = [:]
        declinedThisTurn = false
        sentForUser = []
        turnId = nil
        asking = [:]
        pendingActions = [:]
        runningCalls = [:]
        threadId = nil
        waiting = nil
        lastMessage = nil
        answerItems = []
        editedFiles = [:]
        let thread = request("thread/start", ["model": model, "approvalPolicy": "untrusted", "sandbox": "danger-full-access",
                                              "ephemeral": true, "baseInstructions": instructions])
        threadRequest = nextId
        return [thread]
    }

    /// The user's own words for the gates; the whole request (files note and their text) only for `opensAttachment`.
    func setRequest(_ text: String) {
        request = ArisMemoryText.ownWords(text)
        attached = text
    }
    func setHandsFree(_ handsFree: Bool) { self.handsFree = handsFree }

    /// The screen went into this thread's history, so it stays there for every later turn: no time window.
    func markUntrusted() { untrustedAt = Date() }

    func markScreenSeen() { if screenSeenAt == nil { screenSeenAt = Date() } }

    /// Outside text (and any app's screen read through computer use) outranks the screen image.
    var taint: ArisTaint {
        if untrustedAt != nil || !screensRead.isEmpty { return .outsideText }
        return screenSeenAt != nil ? .screenSeen : .none
    }

    /// For computer use in `app`: outside content other than that app's own screen has come in (a screen image counts:
    /// ArisTaint.cleanForComputerUse).
    private func isTainted(for app: String) -> Bool { untrustedAt != nil || screenSeenAt != nil || !screensRead.subtracting([app]).isEmpty }

    /// `aris-tools desktop` read this app's own screen (its accessibility tree): outside text for everything but it.
    func markAppRead(_ app: String) { screensRead.insert(app) }

    func taint(forApp app: String) -> ArisTaint { isTainted(for: app) ? .outsideText : .none }

    func escalation(for id: String) -> ArisPendingAction? { pendingActions[id] }

    /// A yes to a cua_repl call (the user's or main Aris's): it runs, and its steps in the apps its code names go ahead
    /// while it does; nothing else.
    private func startCode(_ id: String, allowed: Bool) {
        guard let asked = codeAsks.removeValue(forKey: id), allowed else { return }
        runningCode[asked.call] = asked.code
    }

    func approveOnce(_ id: String) -> [Data] {
        let action = pendingActions.removeValue(forKey: id)?.action
        startCode(id, allowed: true)
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        mintPasses(action)
        return [Self.answer(waiting.request, allow: true, toolQuestion: waiting.isToolQuestion)]
    }

    func decide(_ id: String, allow: Bool) -> [Data] {
        let action = pendingActions.removeValue(forKey: id)?.action
        startCode(id, allowed: allow)
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        if allow { mintPasses(action) }
        // The key was only issued when the user's yes could be kept (no taint, or screenSeen with the action covered).
        if allow, taint != .outsideText, let key = waiting.remember { approved[key] = Date() }
        if allow, let bundle = waiting.computerUseBundle { computerUse.remember(bundle, tainted: isTainted(for: bundle)) }
        if !allow { declinedThisTurn = true }
        return [Self.answer(waiting.request, allow: allow, toolQuestion: waiting.isToolQuestion)]
    }

    /// Whether an action is one aris-tools `memory` read, or a `recall` of Aris's own work memory (never hands-free either).
    static func readsMemory(_ action: ArisAction, tools: String) -> Bool {
        guard case .shell(let command) = action else { return false }
        return (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return false }
            return ["memory", "recall"].contains(Array(words.dropFirst()).first ?? "")
        }
    }

    /// The read judge blocked this read: declined and Codex told why (turn/steer), never a no for the rest of the turn.
    /// Also how the runner declines a card nobody answered and an action a hard line refuses (audit gate-6): the call
    /// is declined with `note`, and the turn's other cards still come up, since the user said no to nothing.
    func refuseRead(_ id: String, note: String) -> [Data] {
        pendingActions[id] = nil
        startCode(id, allowed: false)
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        return [Self.answer(waiting.request, allow: false, toolQuestion: waiting.isToolQuestion)] + (steer(note).map { [$0] } ?? [])
    }

    /// A note to the turn under way (turn/steer); nil when no turn is open. Its reply, or an error for coming too late,
    /// is nothing to fail the answer over.
    private func steer(_ note: String) -> Data? {
        guard let threadId, let turnId else { return nil }
        let line = request("turn/steer", ["threadId": threadId, "expectedTurnId": turnId, "input": [["type": "text", "text": note]]])
        quietRequests.insert(nextId)
        return line
    }

    /// The owner's ②A: the AI's call is declined because the agent ran the user's changed card itself (`arguments`: that
    /// version's aris-tools words). It isn't a no: the rest of the turn goes on, the AI is told what happened
    /// (turn/steer with `note`), and only this same action again is refused this turn.
    func declineEdited(_ id: String, arguments: [String], note: String) -> [Data] {
        if let action = pendingActions[id]?.action, let asked = ArisEditableAction.parse(action, tools: tools) {
            sentForUser.insert(asked.arguments)
        }
        sentForUser.insert(arguments)
        pendingActions[id] = nil
        startCode(id, allowed: false)
        guard let waiting = asking.removeValue(forKey: id) else { return [] }
        return [Self.answer(waiting.request, allow: false, toolQuestion: waiting.isToolQuestion)] + (steer(note).map { [$0] } ?? [])
    }

    /// No notifier, live web search, and tools called directly rather than from code mode's scripts (which poll a
    /// long tool like Aside with a model round trip every ~13 s: minutes for a 15-second browser task).
    static let quietSwitches = ["-c", "notify=[]", "-c", #"web_search="live""#, "--disable", "code_mode"]

    /// Where the user's own skills live. Their instructions would steer Aris's Codex (e.g. to drive Aside through its
    /// command line instead of the gated tool) and slow every start, so they're switched off for Aris.
    static var skillFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".agents/skills"), home.appendingPathComponent(".codex/skills")]
    }

    /// The `name:` in a SKILL.md's front matter.
    static func skillName(fromSkillFile text: String) -> String? {
        guard text.hasPrefix("---") else { return nil }
        for line in text.split(separator: "\n").dropFirst() {
            if line.hasPrefix("---") { break }
            if line.hasPrefix("name:") {
                let name = line.dropFirst(5).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'")))
                return name.isEmpty ? nil : name
            }
        }
        return nil
    }

    static func skillSwitches(_ names: [String]) -> [String] {
        let safe = names.filter { $0.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil }
        guard !safe.isEmpty else { return [] }
        return ["-c", "skills.config=[" + safe.map { "{name=\"\($0)\",enabled=false}" }.joined(separator: ",") + "]"]
    }

    /// Every skill the user has installed, by name.
    static func installedSkills() -> [String] {
        let files = skillFolders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).map {
                folder.appendingPathComponent($0).appendingPathComponent("SKILL.md")
            }
        }
        return Array(Set(files.compactMap { (try? String(contentsOf: $0, encoding: .utf8)).flatMap(skillName) })).sorted()
    }

    /// The plugins in the user's Codex config.
    static func plugins(inConfig config: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"^\[plugins\."([^"]+)"\]\s*$"#, options: .anchorsMatchLines)
        let range = NSRange(config.startIndex..., in: config)
        return pattern.matches(in: config, range: range).compactMap { Range($0.range(at: 1), in: config).map { String(config[$0]) } }
    }

    /// Every plugin off, except computer use.
    static func pluginSwitches(inConfig config: String) -> [String] {
        plugins(inConfig: config).filter { $0 != computerUse }.flatMap { ["-c", "plugins.\"\($0)\".enabled=false"] }
            + ["-c", "plugins.\"\(computerUse)\".enabled=true"]
            // Its runtime runs model-written code with full access: Codex asks before every call (Aris shows the code).
            + ["-c", "plugins.\"\(computerUse)\".mcp_servers.\(ArisRiskPolicy.computerUseRepl).default_tools_approval_mode=\"prompt\"",
               "-c", "plugins.\"\(computerUse)\".mcp_servers.\(ArisRiskPolicy.computerUseRepl).tools.js.approval_mode=\"prompt\""]
    }

    /// The MCP servers in the user's Codex config, to switch off for Aris.
    static func mcpServers(inConfig config: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: #"^\[mcp_servers\.([A-Za-z0-9_-]+)\]\s*$"#, options: .anchorsMatchLines)
        let range = NSRange(config.startIndex..., in: config)
        return pattern.matches(in: config, range: range).compactMap { Range($0.range(at: 1), in: config).map { String(config[$0]) } }
    }

    /// Korean names for the parameters tools usually take, for the confirm card.
    private static let paramNames: [String: String] = [
        "title": "제목", "name": "이름", "subject": "제목", "summary": "제목",
        "start": "시작", "start_date": "시작", "starttime": "시작", "start_time": "시작", "end": "끝", "end_date": "끝", "endtime": "끝", "end_time": "끝",
        "to": "받는 사람", "recipients": "받는 사람", "cc": "참조", "body": "내용", "content": "내용", "text": "내용", "message": "내용",
        "query": "검색어", "location": "장소", "description": "설명", "attendees": "참석자", "date": "날짜", "due": "마감",
    ]

    /// One line of a tool's parameters on the confirm card, as a person reads it: a Korean name, dates written out,
    /// lists joined, every field of a wrapper object. Nothing that picks the target is hidden: an id is shown as
    /// "대상", shortened to its head and tail. Text longer than `limit` is cut and says how much is hidden; the card's
    /// 전체 보기 has the lines with no limit. Empty values are left out.
    /// `english`: for a request in English (ArisGateWords): the tool's own names, yes/no, dates the English way.
    static func paramLine(name: String, display: String?, value: Any?, timeZone: TimeZone = .current, limit: Int? = 120, english: Bool = false) -> String? {
        guard let value else { return nil }
        let key = name.lowercased()
        let isID = key == "id" || key.hasSuffix("_id") || name.hasSuffix("Id") || name.hasSuffix("ID")
        let text = readable(value, timeZone: timeZone, english: english)
        guard !text.isEmpty else { return nil }
        if isID { return "\(english ? "Target" : "대상"): \(limit == nil ? text : shortened(text))" }
        let label = (english ? paramNames[key].flatMap { ArisGateWords.labels[$0] } : paramNames[key]) ?? display ?? name
        guard let limit, text.count > limit else { return "\(label): \(text)" }
        let kept = limit - 1
        return "\(label): \(text.prefix(kept))… (+\(text.count - kept)\(english ? " characters" : "자"))"
    }

    /// An id as its first and last four characters ("abc1…9xyz"); a short one whole.
    static func shortened(_ id: String) -> String {
        id.count > 10 ? "\(id.prefix(4))…\(id.suffix(4))" : id
    }

    private static func readable(_ value: Any, timeZone: TimeZone, english: Bool = false) -> String {
        switch value {
        case let text as String:
            return date(text, timeZone: timeZone, english: english) ?? text.trimmingCharacters(in: .whitespacesAndNewlines)
        case let list as [Any]:
            return list.map { readable($0, timeZone: timeZone, english: english) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case let object as [String: Any]:
            // {"dateTime": …} and {"email": …} style wrappers: the value that matters, then every other field after it.
            if let key = ["dateTime", "date", "email", "name", "title", "value"].first(where: { object[$0] != nil }), let inner = object[key] {
                let main = readable(inner, timeZone: timeZone, english: english)
                let others = object.keys.filter { $0 != key }.sorted().compactMap { object[$0].map { readable($0, timeZone: timeZone, english: english) } }
                    .filter { !$0.isEmpty }
                return others.isEmpty ? main : "\(main) (\(others.joined(separator: ", ")))"
            }
            return object.keys.sorted().compactMap { key in object[key].map { "\(key) \(readable($0, timeZone: timeZone, english: english))" } }.joined(separator: ", ")
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? (english ? "yes" : "예") : (english ? "no" : "아니요")) : number.stringValue
        default:
            return "\(value)"
        }
    }

    /// An ISO 8601 date or date-time written the Korean way: "11월 3일 (화) 오후 3:00", or "11월 3일 (화)" for a day.
    private static func date(_ text: String, timeZone: TimeZone, english: Bool = false) -> String? {
        let output = DateFormatter()
        output.locale = Locale(identifier: english ? "en_US" : "ko_KR")
        output.timeZone = timeZone
        if text.count == 10, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            let input = DateFormatter()
            input.locale = Locale(identifier: "en_US_POSIX")
            input.timeZone = timeZone
            input.dateFormat = "yyyy-MM-dd"
            guard let day = input.date(from: text) else { return nil }
            output.dateFormat = english ? "EEE, MMM d" : "M월 d일 (E)"
            return output.string(from: day)
        }
        guard text.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}"#, options: .regularExpression) != nil else { return nil }
        let options: [ISO8601DateFormatter.Options] = [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
                                                       [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]]
        let parsers = options.map {
            let parser = ISO8601DateFormatter()
            parser.formatOptions = $0
            parser.timeZone = timeZone
            return parser
        }
        guard let moment = parsers.lazy.compactMap({ $0.date(from: text) }).first else { return nil }
        output.dateFormat = english ? "EEE, MMM d, h:mm a" : "M월 d일 (E) a h:mm"
        return output.string(from: moment)
    }

    // MARK: - JSON-RPC

    private func request(_ method: String, _ params: [String: Any]) -> Data {
        nextId += 1
        return Self.line(["id": nextId, "method": method, "params": params])
    }

    /// The approval requests Codex sends (app-server v2); each names the thread it belongs to.
    private static let approvalMethods: Set<String> = ["item/commandExecution/requestApproval", "item/fileChange/requestApproval",
                                                       "mcpServer/elicitation/request"]

    /// Codex asking permission: ArisRiskPolicy answers at once, refuses, or the user is asked.
    private func approve(_ id: Any, _ method: String, _ params: [String: Any]) -> [ArisBrainEvent] {
        let toolQuestion = method == "mcpServer/elicitation/request"
        // Only the thread Aris is in may ask: a request for another thread, or naming none while one is open, is declined.
        if Self.approvalMethods.contains(method), params["threadId"] as? String != threadId {
            return [.send(Self.answer(id, allow: false, toolQuestion: toolQuestion))]
        }
        let action: ArisAction
        var title: String
        var detail: String
        /// The details with nothing cut, for the card's 전체 보기 (when they differ from `detail`).
        var full: String?
        /// An MCP tool's parameters and the ChatGPT app it came through, for the escalation gate's scope.
        var arguments: [String: Any] = [:]
        var connector = ""
        /// A file edit's changes and a command's folder, for what a yes to it is remembered by.
        var changes: [[String: Any]]?
        var cwd = ""
        /// A computer-use step: its tool and its app (nil unless both of the runtime's names agree).
        var step = ""
        var app: ComputerUseApp?
        /// What main Aris may judge instead of the user (a cua_repl call's code), whether outside text came in for it, and the
        /// call it would start; a computer-use step's own call.
        var judged: ArisJudgedStep?
        var codeTainted = true
        var codeCall: (String, RunningCode)?
        /// Code that sends a message the user said word for word: their dictated-message countdown instead of a question.

        var housekeepingOK = false
        var stepCall: String?
        /// An edit of a shell or tool settings file, and whether its whole change is on the card.
        var settingsEdit = false, settingsEditShown = true
        /// A file edit that moves the file somewhere Aris can't read, or carries a field Aris doesn't know.
        var unreadMove = false, unknownChange = false
        /// The request is in English: the card's fixed words are too (ArisGateWords).
        let english = ArisGateWords.isEnglish(request)
        /// Who a connector's tool belongs to ("Notion", "Gmail"), for the read judge.
        var source = ""
        /// False when an MCP approval can't be tied to one call: it's asked about whatever the tool's name says.
        var identified = true
        switch method {
        case "item/commandExecution/requestApproval":
            let command = (params["command"] as? String).map(ArisCommandPolicy.unwrap) ?? ""
            cwd = params["cwd"] as? String ?? ""
            action = .shell(command)
            (title, detail) = Self.describe(command: command, tools: tools, request: request)
        case "item/fileChange/requestApproval":
            changes = (params["itemId"] as? String).flatMap { editedFiles[$0] }
            // Each change's path, and where it moves the file to when it does: both are rated and both are on the
            // card (ArisCodexChange: security review 2 H2).
            let files = ArisCodexChange.files(changes ?? [])
            action = .fileChange(files)
            (title, detail) = ("파일 수정", files.isEmpty ? "(어떤 파일인지 알 수 없어요)" : ArisCodexChange.lines(changes ?? []).joined(separator: "\n"))
            unreadMove = !ArisCodexChange.unread(changes ?? []).isEmpty
            unknownChange = ArisCodexChange.hasExtra(changes ?? [])
            // A shell or tool settings file (~/.zshrc, ~/.gitconfig, ~/bin…): the whole change on the card (audit gate-17).
            if ArisRiskPolicy.isSettingsEdit(files, home: home) {
                settingsEdit = true
                if let card = ArisCardWords.settingsEdit(changes ?? [], home: home, english: english) {
                    let extra = (changes ?? []).flatMap { ArisCodexChange.read($0).extra }.map(ArisDesktopCard.shown)
                    (title, detail) = (card.title, ([card.detail] + extra).joined(separator: "\n"))
                } else { settingsEditShown = false }
            }
        case "mcpServer/elicitation/request":
            let meta = params["_meta"] as? [String: Any] ?? [:]
            // Only a tool asking to run is answered; any other question a tool asks (a form to fill in) is declined.
            guard meta["codex_approval_kind"] as? String == "mcp_tool_call" else { return [.send(Self.answer(id, allow: false, toolQuestion: true))] }
            let displayed = meta["tool_params_display"] as? [[String: Any]] ?? []
            let shown = displayed.compactMap {
                Self.paramLine(name: $0["name"] as? String ?? "", display: $0["display_name"] as? String, value: $0["value"], english: english)
            }
            let uncut = displayed.compactMap {
                Self.paramLine(name: $0["name"] as? String ?? "", display: $0["display_name"] as? String, value: $0["value"], limit: nil, english: english)
            }
            // Computer use names the tool, ChatGPT apps (Gmail) give its title, and MCP servers neither: then it's the
            // running call it belongs to. When that can't be told for sure, the tool stays unknown and the user is asked.
            let server = params["serverName"] as? String ?? ""
            let toolParams = meta["tool_params"] as? [String: Any] ?? [:]
            let call = runningCall(id: meta["callId"] as? String, server: server, arguments: toolParams)
            let tool = meta["tool_name"] as? String ?? meta["tool_title"] as? String ?? call?.tool ?? ""
            if tool.isEmpty { identified = false }
            arguments = toolParams.isEmpty ? call?.arguments ?? [:] : toolParams
            connector = meta["connector_id"] as? String ?? ""
            if connector == "computer-use" {
                // Computer use only from its own runtime.
                guard server == ArisRiskPolicy.computerUseRepl else { return [.send(Self.answer(id, allow: false, toolQuestion: true))] }
                let found = Self.computerUseApp(meta: meta, tool: tool, request: request)
                app = found
                step = tool
                stepCall = meta["tool_call_id"] as? String ?? meta["callId"] as? String
                action = .computerUse(app: found.name)
                (title, detail) = (found.title, found.detail)
            } else if server == ArisRiskPolicy.computerUseRepl, let fields = Self.housekeeping[tool] {
                // The runtime's own housekeeping (a reset, the end-of-turn hook) runs no code: no card, when its arguments
                // are exactly what it takes.
                action = .mcp(server: server, tool: tool)
                (title, detail) = ("컴퓨터 사용 · \(tool)", tool)
                housekeepingOK = Set(arguments.keys) == fields && arguments.values.allSatisfy { $0 is String }
            } else if server == ArisRiskPolicy.computerUseRepl && tool == "js" {
                // Model-written code that drives the Mac: the user (or main Aris, for code the strict reader understands) reads it.
                let code = toolParams["code"] as? String ?? call?.arguments["code"] as? String ?? ""
                action = .mcp(server: server, tool: tool)
                (title, detail) = ("컴퓨터 사용 코드 실행", code.count > Self.codePreview ? String(code.prefix(Self.codePreview)) + "…" : code)
                full = code
                let program = ArisJSProgram.read(code)
                let targets = (program?.apps ?? []).map(Self.target)
                let bundles = Set(targets.compactMap(\.bundle))
                // Only one named app's own screen is no taint for it: code naming two after either's screen was read is.
                let tainted = untrustedAt != nil || screenSeenAt != nil || !screensRead.subtracting(bundles.count == 1 ? bundles : []).isEmpty
                codeTainted = tainted
                let step = ArisJudgedStep(code: code, program: program, targets: targets)
                if ArisEscalation.isMessage(step) {
                    (title, detail) = Self.messageCard(step)
                } else if ArisEscalation.hasLiteralEscape(step) {
                    detail = ArisEscalation.literalEscapeNote + "\n" + detail
                }
                judged = step
                // Its id: the one Codex gives, or the one running cua_repl call with this code.
                codeCall = (meta["callId"] as? String ?? runningCallId(server: server, arguments: toolParams)).map { id in
                    (id, RunningCode(targets: bundles, clean: !tainted && program?.staysInItsApps == true && bundles.count == 1 && targets.count == 1))
                }
            } else {
                action = .mcp(server: server, tool: tool)
                source = meta["connector_name"] as? String ?? (params["serverName"] as? String == "aris_notion" ? "Notion" : params["serverName"] as? String ?? "")
                (title, detail) = ("\(source) · \(tool)", shown.isEmpty ? (params["message"] as? String ?? tool) : shown.joined(separator: "\n"))
                full = uncut.joined(separator: "\n")
                // A mail about to be sent: who it goes to, its subject and its whole text, from the call's own parameters
                // and with nothing cut (audit gate-9). One that doesn't carry them is refused by the escalation gate.
                if ArisRiskPolicy.hardLine(of: action, tools: tools, connector: connector, arguments: arguments) == .mailSend,
                   let mail = ArisMailCard.lines(arguments, english: english) {
                    (title, detail, full) = (source.isEmpty ? ArisMailCard.title : "\(ArisMailCard.title) · \(source)", mail.joined(separator: "\n"), nil)
                }
            }
        default:
            return [.send(Self.line(["id": id, "error": ["code": -32601, "message": "Aris doesn't support \(method)"]]))]
        }
        let assessed = ArisRiskPolicy.risk(of: action, tools: tools, home: home, critical: tier == .critical, request: request)
        var risk: ArisRisk = identified || assessed == .never ? assessed : .confirm
        // Every never says why: in the audit and the ledger (QA live on b9c766bc).
        var neverWhy = assessed == .never ? ArisRiskPolicy.neverReason(action, tools: tools, home: home, critical: tier == .critical, request: request) : nil
        func refuse(_ why: String) { if risk != .never || neverWhy == nil { neverWhy = why }; risk = .never }
        // A read on a careful turn goes to the read judge, never a card: outside text, the screen or hands-free don't
        // turn it into a question (only what it would send or change does).
        // Follow-up M1: after outside text or the screen, a maps lookup with words that aren't the user's asks, never judged.
        let carries = identified && taint != .none && ArisRiskPolicy.mapsLookupCarries(action, tools: tools, request: request)
        let judgedRead = identified && careful && assessed == .auto && !housekeepingOK && !carries
            ? readCall(for: action, source: source, arguments: arguments) : nil
        // R3: on a careful turn a connector's tool that names a write (a draft included) is no read: the user's card.
        if careful, identified, judgedRead == nil, risk == .auto, !housekeepingOK, case .mcp(let server, let tool) = action,
           server != ArisRiskPolicy.computerUseRepl, !ArisRiskPolicy.connectorReads(tool) { risk = .confirm }
        // R1 = B: after the screen came in, an action whose target and every word are the user's own goes as judged.
        let covered = identified && taint == .screenSeen && !handsFree
            && ArisRiskPolicy.coveredByRequest(action, tools: tools, arguments: arguments, request: request)
        let blocked = taint.blocks(covered: covered)
        // Outside text read moments ago (or the screen, for words the user didn't say) could have planted this (send what you
        // know to this address, remove that schedule): ask first.
        if risk == .auto || risk == .countdown, blocked, judgedRead == nil,
           ArisRiskPolicy.asksAfterOutsideText(action, tools: tools) { risk = .confirm }
        if carries, risk == .auto { risk = .confirm }
        if identified, risk == .auto, ArisRiskPolicy.opensAttachment(action, tools: tools, request: attached) { risk = .confirm }
        // A settings file's edit whose change can't be shown in full is never put to the user as a bare file name.
        if settingsEdit, !settingsEditShown { refuse("an edit of a shell or tool settings file whose change can't be shown on the card") }
        // Nor an edit that moves the file to a place that can't be read; one with a field Aris doesn't know asks.
        if unreadMove { refuse(ArisCodexChange.unreadReason) }
        if unknownChange, risk == .auto { risk = .confirm }
        // A conversion hidden in another command (sh -c, a pipe) after outside text or the screen: refused. One written
        // plainly asked above, on the user's card (audit gate-4).
        if taint != .none, ArisRiskPolicy.refusedAfterOutsideText(action, tools: tools) { refuse("a conversion hidden inside another command, after outside text came in") }
        // Websites are Aside's, and terminals, password and code-running apps are never computer use's.
        if let app, app.browser || app.never { refuse(app.browser ? "computer use in a browser (websites are Aside's)" : "computer use is never in \(app.name)") }
        // System Settings like any app, judged by the pane last seen there (the desktop engine's three tiers): never in a
        // protected one; a pane not told for sure, or a step whose words name a protected one, asks every time, never kept.
        var settingsAsks = false
        if let app, ArisRiskPolicy.isSystemSettings([app.name, app.bundle]) {
            let words = (try? JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            switch computerUse.lastSettingsPane() {
            case .protected: refuse("a protected System Settings pane")
            case .unknown: settingsAsks = true
            case .safe: settingsAsks = ArisSettingsPane.mentionsProtected(words)
            }
            if settingsAsks, risk == .auto { risk = .confirm }
            // The step may change the pane: the next one is judged as not told until a look shows it again.
            computerUse.forgetSettingsPane()
        }
        let bundle = app?.bundle
        let lookStep = app.map { ArisRiskPolicy.computerUseStepIsPlain(bundle: $0.bundle, name: $0.name, tool: step, arguments: arguments) } ?? false
        if app != nil { recordStep(bundle: bundle, call: stepCall) }
        if risk != .never, app != nil {
            // Its app's own screen comes in; an app that couldn't be told for sure is outside text for everything.
            if let bundle { screensRead.insert(bundle) } else { untrustedAt = Date() }
        } else if risk != .never, !Self.isComputerUseCode(action), ArisRiskPolicy.bringsInUntrusted(action, tools: tools, home: home) {
            // A cua_repl call taints when it finishes (its result), not when it asks: the app memory holds for its steps.
            untrustedAt = Date()
        }
        // After outside text a remembered yes is never used and none is kept (the owner's ruling: never act on outside content
        // without asking).
        let anyKey = identified && ArisRiskPolicy.isRepeatable(action, tools: tools) ? Self.rememberKey(action, cwd: cwd, changes: changes) : nil
        // Hands-free: no remembered yes is used or kept (ArisHandsFree).
        // Nor for a settings file's edit: each one is the user's own yes to exactly what the card showed.
        let key = blocked || handsFree || settingsAsks || settingsEdit ? nil : anyKey
        let remembered = anyKey.flatMap { approved[$0] }.map { Date().timeIntervalSince($0) < Self.approvalMemory } ?? false
        if risk == .confirm, key != nil, remembered, !settingsAsks { risk = .auto }
        // The user's yes for this app covers a step that only looks while only its own screen has come in.
        let appKnown = bundle.map { computerUse.allows($0, tainted: false) || computerUse.wasWiped($0) } ?? false
        let appTainted = handsFree || (bundle.map(isTainted(for:)) ?? true)
        if risk == .confirm, appKnown, !appTainted, lookStep, !settingsAsks { risk = .auto }
        // A step inside code the user or main Aris let run, in an app that code names, while it runs.
        // Never a paste or a drag into a chat app: they bring in content other than typed text.
        if risk == .confirm, !settingsAsks, let bundle, let stepCall, let code = runningCode[stepCall], code.targets.contains(bundle),
           !(ArisRiskPolicy.isSendingApp(bundle: bundle, name: app?.name ?? "") && ["paste", "drag"].contains(step)) { risk = .auto }
        // A yes that outside text keeps from applying: the card says why.
        let blockedByTaint = risk == .confirm && ((blocked && remembered) || (appKnown && appTainted && lookStep))
        if handsFree, judgedRead == nil { risk = ArisHandsFree.risk(risk, of: action, tools: tools) }
        // The user's memories are never read on a hands-free turn, on any brain (minor 2).
        if handsFree, Self.readsMemory(action, tools: tools) { refuse("the user's memories are never read on a hands-free turn") }
        if declinedThisTurn && (risk == .confirm || risk == .countdown) { refuse("the user already said no to a card this turn; nothing else that asks runs after it") }
        // The user's changed card already did this (ArisEditableAction): the same action again is never run twice.
        if !sentForUser.isEmpty, let again = ArisEditableAction.parse(action, tools: tools), sentForUser.contains(again.arguments) { refuse("the user's changed card already did this") }
        if housekeepingOK {
            if declinedThisTurn { refuse("the user already said no to a card this turn") } else { risk = .auto }
        }
        // A teammate's job: outside what it may use is refused, never asked (a housekeeping call runs no code).
        if let scopes, !housekeepingOK, !ArisTeammateScope.permits(action, scopes: scopes, tools: tools) { refuse("outside what this teammate's job may use") }
        if risk != .never { neverWhy = nil }
        if let neverWhy { computerUse.noteRefusal("refused (never): \(neverWhy)", action: false) }
        let audit = ArisBrainEvent.audit(Self.auditLine(action, risk: risk, raw: params["command"] as? String ?? method, why: neverWhy))
        // The read judge answers it (the runner): approveOnce on its yes, refuseRead on its no. Never shown as a card.
        if risk == .auto, let judgedRead, !(handsFree && Self.readsMemory(action, tools: tools)) {
            asked += 1
            let ask = ArisConfirmation(id: ArisLaunch.confirmId(asked), title: "읽기 확인", detail: judgedRead.tool)
            asking[ask.id] = (id, toolQuestion, nil, nil)
            pendingActions[ask.id] = ArisPendingAction(action: action, arguments: arguments, connector: connector, read: judgedRead)
            return [.confirm(ask), audit]
        }
        switch risk {
        case .auto:
            mintPasses(action)
            return [.send(Self.answer(id, allow: true, toolQuestion: toolQuestion)), audit]
        case .never:
            let browser = app?.browser == true && app?.never == false
            // Codex is told it was Aris's rule and which one (a fixed line, never its own words back), so it neither words
            // the refusal as the user's no nor gives up on what another allowed command could do (audit gate-5).
            // (A hands-free turn's refusal says to ask again by the key, as the API brain's does; a refusal that follows
            // The user's own no, or their changed card, says nothing more.)
            let note = handsFree && neverWhy == nil ? ArisRefusalWords.handsFree : ArisRefusalWords.neverNote(action, why: neverWhy ?? "", tools: tools)
            let told = note.flatMap(steer).map { [ArisBrainEvent.send($0)] } ?? []
            return [.send(Self.answer(id, allow: false, toolQuestion: toolQuestion))] + told + [audit] + (browser ? [.status(ArisRiskPolicy.browserRefusal)] : [])
        case .confirm, .countdown:
            asked += 1
            let reason = blockedByTaint || (judged != nil && codeTainted) ? ArisEscalation.taintedReason + "\n" : ""
            let dictated = risk == .countdown ? Self.dictatedMessage(in: action, tools: tools, request: request) : nil
            let korean = dictated.map { ArisConfirmation(id: ArisLaunch.confirmId(asked), title: $0.to, detail: $0.text, countdown: true,
                                                         spoken: ArisRiskPolicy.announcement(to: $0.to, text: $0.text)) }
                ?? ArisConfirmation(id: ArisLaunch.confirmId(asked), title: title, detail: reason + detail,
                                    full: full.flatMap { $0.isEmpty || $0 == detail ? nil : reason + $0 },
                                    memoryWrite: ArisMemoryLearning.isMemoryWrite(action, tools: tools))
            let ask = english ? ArisGateWords.card(korean) : korean
            // A yes to computer use in an app is kept by Aris (computerUse), never as Codex's session approval.
            asking[ask.id] = (id, toolQuestion, bundle, key)
            if let (call, code) = codeCall { codeAsks[ask.id] = (call, code) }
            // An action that couldn't be tied to one tool has no scope the gate could trust: it stays with the user.
            if identified {
                pendingActions[ask.id] = ArisPendingAction(action: action, arguments: arguments, connector: connector, judged: judged,
                                                           judgeTainted: codeTainted, covered: covered)
            }
            return [.confirm(ask), audit]
        }
    }

    /// A computer-use step asked inside a running approved call: which app it was for (a step that can't be tied to
    /// a call, or an app that can't be told, makes every running call's finish outside text).
    private func recordStep(bundle: String?, call: String?) {
        guard let call, runningCode[call] != nil else {
            if call == nil { runningCode = runningCode.mapValues { var code = $0; code.unattributed = true; return code } }
            return
        }
        if let bundle { runningCode[call]?.apps.insert(bundle) } else { runningCode[call]?.unattributed = true }
    }

    /// cua_repl's tools that run no code, and the arguments each takes (@oai/cua-repl's plugin.json hooks).
    static let housekeeping: [String: Set<String>] = ["js_reset": [], "turn_ended": ["hook_event_name", "session_id", "turn_id"]]

    /// How much of a cua_repl call's code the card shows before 전체 보기.
    static let codePreview = 600

    private static func isComputerUseCode(_ action: ArisAction) -> Bool {
        if case .mcp(let server, _) = action { return server == ArisRiskPolicy.computerUseRepl }
        return false
    }

    /// The running MCP call an approval belongs to: by its call id when it has one, otherwise the only running call on
    /// that server with exactly these arguments. Nil when none or several match.
    private func runningCallId(server: String, arguments: [String: Any]) -> String? {
        let matches = runningCalls.filter { $0.value.server == server && NSDictionary(dictionary: $0.value.arguments).isEqual(to: arguments) }
        return matches.count == 1 ? matches.first?.key : nil
    }

    private func runningCall(id: String?, server: String, arguments: [String: Any]) -> (server: String, tool: String, arguments: [String: Any])? {
        if let id, let call = runningCalls[id] { return call }
        let matches = runningCalls.values.filter { $0.server == server && NSDictionary(dictionary: $0.arguments).isEqual(to: arguments) }
        return Set(matches.map(\.tool)).count == 1 ? matches.first : nil
    }

    /// actions.log's line for one request: what it is, the gate's answer, and Codex's raw words.
    /// A desktop heredoc's body (the text typed, maybe a private message) is kept only as its length and SHA-256 (I13).
    /// `why`: a never's reason (every never has one).
    static func auditLine(_ action: ArisAction, risk: ArisRisk, raw: String, why: String? = nil) -> String {
        let shown: ArisAction
        if case .shell(let command) = action { shown = .shell(ArisDesktopShell.audited(command)) } else { shown = action }
        var object: [String: String] = ["action": what(shown), "risk": risk.rawValue, "raw": ArisDesktopShell.audited(raw)]
        if let why { object["why"] = why }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data(), as: UTF8.self)
    }

    /// The gate let a command run: aris-tools may send each message in it, once (ArisMessagePass).
    private func mintPasses(_ action: ArisAction?) {
        if case .shell(let command)? = action {
            ArisMessagePass.mint(command: command, tools: tools)
            // And each calendar or to-do write in it, for the app's route (ArisActionGrant).
            ArisActionGrants.shared.mint(command: command, tools: tools)
        }
    }

    /// The dictated message in a command (ArisRiskPolicy+Dictation), for the countdown card.
    static func dictatedMessage(in action: ArisAction, tools: String, request: String) -> (to: String, text: String)? {
        guard case .shell(let command) = action else { return nil }
        for piece in ArisCommandPolicy.segments(command) ?? [command] {
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { continue }
            if let message = ArisRiskPolicy.dictatedMessage(Array(words.dropFirst()), request: request) { return message }
        }
        return nil
    }

    /// What a yes is remembered by: the action with exactly what it does, so different content is a new question. A file
    /// edit is its paths and a SHA-256 of its changes (each path's diff and kind), a command its whole text and the
    /// folder it runs in. Nil (never remembered) for anything else, or when the content can't be told.
    static func rememberKey(_ action: ArisAction, cwd: String = "", changes: [[String: Any]]? = nil) -> String? {
        switch action {
        case .fileChange:
            guard let changes, !changes.isEmpty, changes.allSatisfy({ $0["diff"] is String }), let data = canonical(changes) else { return nil }
            return what(action) + " #" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        case .shell(let command):
            return "shell (\(cwd)): " + command
        case .mcp, .browserTask, .computerUse:
            // Never repeatable (ArisRiskPolicy.isRepeatable); computer use is held per app in `computerUse`.
            return nil
        }
    }

    /// JSON with its keys sorted, so the same content always reads the same; nil when it isn't JSON.
    private static func canonical(_ object: Any) -> Data? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// One action in words, for actions.log's line.
    static func what(_ action: ArisAction) -> String {
        switch action {
        case .shell(let command): return "shell: " + command
        case .fileChange(let paths): return "files: " + (paths.isEmpty ? "(unknown)" : paths.joined(separator: ", "))
        case .mcp(let server, let tool): return "tool: \(server)/\(tool)"
        case .computerUse(let app): return "computer use: " + app
        case .browserTask(let task): return "aside: " + task
        }
    }

    /// What Aris's own tools are called on the confirm card (and out loud).
    private static let toolTitles = [
        "message": "메시지 보내기", "mail": "메일 보내기", "trash": "휴지통으로 옮기기", "keys": "키 누르기", "type": "입력하기",
        "new": "새 창 열기", "tile": "창 배치", "window": "창 옮기기", "app": "앱 열기", "link": "링크 열기", "folder": "폴더 열기",
        "music": "음악", "volume": "볼륨", "remind": "미리 알림", "event": "일정 추가", "note": "메모", "clipboard": "클립보드",
        "shortcut": "단축어 실행", "remember": "기억하기", "forget": "잊기", "timer": "타이머",
        "maps": "지도 열기", "convert": "파일 변환하기", "merge": "파일 합치기", "split": "PDF 나누기", "compress": "용량 줄이기",
    ]

    /// Card titles that name a thing, not an action: the subcommand's verb follows them.
    static let nounTitles: Set<String> = ["Mac 작업", "미리 알림", "메모", "클립보드", "타이머", "음악", "볼륨", "단축어 실행"]

    /// aris-tools subcommands as a card says them.
    static let subcommandWords = ["add": "추가", "remove": "빼기", "delete": "지우기", "done": "끝내기", "edit": "고치기", "list": "보기", "show": "보기",
                                  "set": "설정", "new": "새로 만들기", "find": "찾기", "search": "찾기", "recent": "최근 보기", "cancel": "취소", "stop": "멈추기"]

    /// The tools whose first word really is a subcommand, and which ones each has (security review M3). For every other
    /// tool that word is part of what is typed, pressed, remembered, sent or run (`type delete everything…`, `keys
    /// delete`, `remember stop asking…`, `shortcut stop`, a message to someone called "stop"), so it stays on the card.
    static let subcommands: [String: Set<String>] = [
        "clipboard": ["set"], "timer": ["stop"], "schedule": ["add", "remove", "list"], "todo": ["add", "remove", "delete", "done", "edit", "list"],
        "folder": ["new"], "mcp": ["list"], "skill": ["list"], "mail": ["recent", "search"], "notes": ["recent", "search"], "messages": ["recent"],
        "files": ["find"], "obsidian": ["search"], "maps": ["search"], "web": ["search"],
    ]

    /// What a maps lookup (`maps … --json`) is called, should it ever be named: it only looks the way up.
    static let mapsLookupTitle = "길 찾기"

    /// The title and exact words the user sees before a command runs. Made from the command itself, never from
    /// what the AI says it is doing.
    /// `team`: the stored teammates, for a `schedule add --teammate` card (nil: read from the store when needed).
    /// `request`: the user's words for the turn (a schedule card is in English when they have no Hangul).
    static func describe(command: String, tools: String, log: URL = ArisActivityBridge.defaultLog, team: [ArisTeammate]? = nil, request: String = "",
                         schedules: URL = ArisScheduleStore.file(home: FileManager.default.homeDirectoryForCurrentUser.path)) -> (String, String) {
        let (title, detail) = describeKorean(command: command, tools: tools, log: log, team: team, request: request, schedules: schedules)
        // A request in English: the same card, its fixed words in English (ArisGateWords: audit gate-24).
        return ArisGateWords.isEnglish(request) ? (ArisGateWords.title(title), ArisGateWords.detail(detail)) : (title, detail)
    }

    private static func describeKorean(command: String, tools: String, log: URL, team: [ArisTeammate]?, request: String, schedules: URL) -> (String, String) {
        if let pieces = ArisCommandPolicy.segments(command), pieces.count > 1 {
            let cards = pieces.map { describe(command: $0, tools: tools, log: log, team: team, request: request) }
            // A reply to a mail chained with other commands still shows who it really goes to: its own card's lines
            // under the command (the command alone names only the mail's number).
            let replies = zip(pieces, cards).filter { piece, _ in
                guard let words = ArisCommandPolicy.words(piece), words.first == tools, words.count > 2, words[1] == "mail" else { return false }
                return ArisMailReplyWords.isReply(Array(words.dropFirst(2)))
            }.map(\.1.1)
            return (cards.map(\.0).joined(separator: " · "), ([command] + replies).joined(separator: "\n\n"))
        }
        guard let words = ArisCommandPolicy.words(command), let first = words.first else { return ("명령 실행", command) }
        // Restarting, shutting down, logging out or sleeping the Mac, in plain words, however it reached the gate: the
        // shell's own osascript or aris-tools' (audit gate-18; VM run 2). Only the plain words: the script is one of four
        // fixed ones and says nothing more (ArisCardWords.power).
        if let power = ArisRiskPolicy.powerCommand(command, tools: tools) {
            return ArisCardWords.power(power)
        }
        if first == tools, words.count > 1, words[1] == "undo" {
            // Read as aris-tools reads it; the user sees what would be put back, from the log, not just an id.
            guard let parsed = ArisUndoArguments.parse(Array(words.dropFirst(2))) else { return ("되돌리기", "(알 수 없는 명령이라 실행하지 않아요)") }
            guard let id = parsed.id else { return ("되돌리기", "가장 최근에 한 일을 되돌려요 (만든 일정이면 캘린더에서 지워지고, 취소한 예약이면 다시 살아나요)") }
            guard let entry = ArisActivityBridge.entry(id: id.uuidString, file: log) else { return ("되돌리기", "기록에서 찾지 못한 일 (\(id.uuidString))") }
            let warning = entry.deletesEvent ? "캘린더 일정이 지워져요: " : entry.revivesSchedule ? "예약을 다시 살려요 (혼자 실행돼요): " : ""
            return ("되돌리기", warning + entry.summary)
        }
        if first == tools, words.count > 1 {
            let detail = words.dropFirst(2).joined(separator: " ")
            // A schedule: its own card in plain words (QA BUG-28), with who it will run as and what that one may use (the
            // scheduler's ArisTeammateJobs.scheduled).
            if words.count > 2, words[1] == "schedule", words[2] == "add" {
                let rest = Array(words.dropFirst(3)), english = ArisScheduleCard.isEnglish(request)
                return ArisScheduleCard.card(rest, english: english, teammate: scheduledAs(rest, team: team, english: english))
            }
            // A schedule removed: its name and when it runs, read from the helper's own list (vm4 bug 3).
            if words.count > 2, words[1] == "schedule", words[2] == "remove" {
                return ArisScheduleCard.removal(Array(words.dropFirst(3)), jobs: ArisScheduleStore.load(file: schedules), english: ArisScheduleCard.isEnglish(request))
            }
            // An event removed or moved: the exact event in plain words (QA BUG-53).
            if words.count > 2, words[1] == "event", let card = ArisEventCard.card(Array(words.dropFirst(2))) { return card }
            // A reply to a mail: who it really goes to, from Mail's own record, and its whole text (ArisMailReplyCard).
            if words[1] == "mail", let card = ArisMailReplyCard.card(Array(words.dropFirst(2)), request: request) { return card }
            // A maps lookup opens nothing: never "지도 열기" (QA BUG-1).
            if ArisReadGate.isMapsLookup(Array(words.dropFirst())) { return (Self.mapsLookupTitle, detail) }
            // File and desktop actions in plain words, never the command (QA BUG-41, BUG-48).
            // A desktop heredoc's text (to type, or a batch's steps) is part of what the card says.
            let carried = ArisDesktopShell.parse(command, tools: tools)?.text
            if let card = ArisCardWords.card(Array(words.dropFirst()), home: NSHomeDirectory(), text: carried, english: ArisGateWords.isEnglish(request)) { return card }
            // Never a raw English subcommand on a card (BUG-48): "add", "remove", … said in Korean in the title.
            // Only a real subcommand of that tool is read as one (M3): any other first word is shown with the rest.
            let verb = words.count > 2 && Self.subcommands[words[1]]?.contains(words[2]) == true ? Self.subcommandWords[words[2]] : nil
            // A title that already says what happens ("지도 열기") stays; a noun ("미리 알림") gets the verb. The subcommand
            // leaves the detail only when the title says it: every word that runs is on the card, here or there.
            let title = toolTitles[words[1]] ?? "Mac 작업"
            // Typing where the cursor is: the text and the app in words, as the desktop's own typing card says them.
            if words[1] == "type", let typed = ArisCardWords.typing(Array(words.dropFirst(2)), english: ArisGateWords.isEnglish(request)) { return (title, typed) }
            guard let verb, Self.nounTitles.contains(title) else { return (title, detail) }
            return ("\(title) · \(verb)", words.dropFirst(3).joined(separator: " "))
        }
        let program = (first as NSString).lastPathComponent
        if program == "osascript", let found = command.range(of: #"tell application "[^"]+""#, options: .regularExpression) {
            let app = command[found].dropFirst("tell application \"".count).dropLast()
            return ("\(app) 제어", command)
        }
        return ("명령 실행 (\(program))", command)
    }

    /// The card's line for `schedule add … --teammate <id>`: the teammate's name and scopes, or that it won't run (no
    /// such teammate); nil without --teammate. Claude Code's is run as Aris (it opens in a terminal).
    static func scheduledAs(_ arguments: [String], team: [ArisTeammate]?, english: Bool = false) -> String? {
        guard let flag = arguments.firstIndex(of: "--teammate"), flag + 1 < arguments.count else { return nil }
        let id = arguments[flag + 1]
        let stored = team ?? ArisTeammateStore.load(file: ArisTeammateStore.file(home: NSHomeDirectory()))
        if english {
            switch ArisTeammateJobs.scheduled(id, in: stored) {
            case .teammate(let mate):
                let uses = ArisTeammateScope.allCases.filter(mate.scopeSet.contains).map(\.englishTitle)
                return "Teammate: \(mate.name) · can use: \(uses.isEmpty ? "nothing" : uses.joined(separator: ", "))"
            case .missing: return "Teammate: couldn't find that teammate (\(id)), so it won't run"
            case .aris: return "Runs as Aris, with no teammate"
            }
        }
        switch ArisTeammateJobs.scheduled(id, in: stored) {
        case .teammate(let mate): return "팀원: \(mate.name) · 쓸 수 있는 것: \(ArisTeammateScope.summary(mate.scopeSet))"
        case .missing: return "팀원: 그 팀원(\(id))을 찾지 못해 실행되지 않아요"
        case .aris: return "팀원 없이 Aris로 실행돼요"
        }
    }

    /// One call only: never Codex's session-wide approval.
    private static func answer(_ id: Any, allow: Bool, toolQuestion: Bool) -> Data {
        // A yes is passed on only while the path the AI calls aris-tools by is the link to this app's own program
        // (security review 4, H1); a link that can't be put right declines the call.
        let allow = allow && ArisToolsLink.ensure()
        let result: [String: Any] = toolQuestion ? (allow ? ["action": "accept", "content": [String: Any]()] : ["action": "decline"])
                                                 : ["decision": allow ? "accept" : "decline"]
        return line(["id": id, "result": result])
    }

    private func response(_ id: Int, _ object: [String: Any]) -> [ArisBrainEvent] {
        // A note to the turn (turn/steer) that came too late is nothing to fail the answer over.
        if quietRequests.remove(id) != nil { return [] }
        if let error = object["error"] as? [String: Any] {
            return [ArisBrainFailure.event(error["message"] as? String ?? "Codex refused the request.", brain: .codex)]
        }
        guard id == threadRequest else { return [] }
        threadId = ((object["result"] as? [String: Any])?["thread"] as? [String: Any])?["id"] as? String
        guard threadId != nil, let question = waiting else { return [] }
        waiting = nil
        return ask(question.prompt, images: question.images, tier: question.tier).map { .send($0) }
    }
}
