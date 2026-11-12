//
//  ArisBrainDriver.swift
//  aris-agent
//
//  How aris-agent talks to one AI's command-line tool: what to run, what to write
//  to it, and what each line it prints means. ArisAgentRunner owns the process;
//  a driver only speaks the tool's line protocol, so it can be tested without one.
//

import Foundation

enum ArisBrainEvent: Equatable {
    /// A line to write back (an approval answer, or a question that was waiting).
    case send(Data)
    /// Tools the AI is about to use (to learn shortcuts from).
    case tools([ArisAgentStream.ToolCall])
    /// What it is doing, for the notch ("웹 검색 중").
    case status(String)
    /// A step ended with an error (ArisStepOutcome): its status when known, else nil (the step running now).
    case stepFailed(String?)
    /// The next piece of the answer, to start speaking early.
    case delta(String)
    /// The AI waits for the user's yes or no; answer with `decide`.
    case confirm(ArisConfirmation)
    /// One JSON line for actions.log: an action the AI asked for and how the risk gate judged it.
    case audit(String)
    case result(String)
    case failure(String)
    /// The AI can't answer right now (out of quota, rate-limited, overloaded): another one may.
    case unavailable(String)
    /// The process isn't what it must be (the sealed Claude with a tool or server it mustn't have, or a command off
    /// its list): it's stopped at once and the turn fails with this.
    case abort(String)
}

/// How far outside content has come into a conversation (the owner's ruling R1 = B, provenance). `screenSeen`: only pixels
/// of the screen (an image came with a turn of this conversation). `outsideText`: words others wrote (a web page, mail, a
/// tool's result, a file, the screen's text, a dispatched job's prompt, an app seen through computer use). The higher
/// level always wins; only a new conversation clears it.
enum ArisTaint: Int, Comparable, CustomStringConvertible {
    case none, screenSeen, outsideText

    static func < (a: ArisTaint, b: ArisTaint) -> Bool { a.rawValue < b.rawValue }

    var description: String { ["none", "screenSeen", "outsideText"][rawValue] }

    /// Whether the user must decide an action that a grant, the judge, a remembered yes or a countdown could otherwise let
    /// through. Under screenSeen only when the action isn't `covered` (its target and every word from the user's own words
    /// this turn, ArisRiskPolicy.coveredByRequest): the screen can't have chosen what the user said themselves.
    func blocks(covered: Bool) -> Bool {
        switch self {
        case .none: return false
        case .screenSeen: return !covered
        case .outsideText: return true
        }
    }

    /// Computer use remembers and auto-approves nothing once the screen came in: its steps act on what the screen
    /// shows, which the user's words can't cover.
    var cleanForComputerUse: Bool { self == .none }
}

/// The action behind a `.confirm`, for the escalation gate (ArisEscalation): what the risk gate judged, never the
/// card's words. `arguments`: an MCP tool's parameters; `connector`: the ChatGPT app it came through (Gmail).
struct ArisPendingAction {
    let action: ArisAction
    let arguments: [String: Any]
    let connector: String
    /// A computer-use step main Aris may judge in the user's place, and whether outside text came in for it.
    var judged: ArisJudgedStep? = nil
    var judgeTainted = true
    /// Its target and every word come from the user's own words this turn (ArisRiskPolicy.coveredByRequest).
    var covered = false
    /// A read on a careful turn: the read judge decides it (the owner, 2026-11-06), never a card.
    var read: ArisReadCall? = nil
}

protocol ArisBrainDriver: AnyObject {
    /// The program and its arguments; nil when the tool isn't installed.
    func launch() -> (URL, [String])?
    /// Why `launch` gives nothing: the brain's program isn't installed, or (an API brain) its key or set-up is missing;
    /// nil when it can start (ArisBrainTrouble).
    var missing: ArisBrainTrouble.Missing? { get }
    /// The process has its conversation open and can take a question now. False only while a brain that opens one
    /// first (Codex's thread) hasn't heard back: an error then means it never will (audit warm-error-hang-10).
    var isReady: Bool { get }
    /// Called before each real start of the process, ahead of `launch` (never by a "is it installed?" look): what the
    /// brain's own tool needs on disk first (Antigravity's rules for aris-tools). It may change how the brain starts:
    /// an agy whose rules couldn't be written starts sealed.
    func prepare()
    /// Lines written as soon as the process starts.
    func opening() -> [Data]
    /// Lines that ask `prompt` (none yet if the tool isn't ready; it goes out from `read` later).
    func ask(_ prompt: String, tier: ArisTier) -> [Data]
    /// Whether screen images reach this brain (its own image input, in memory, never a file).
    var takesImages: Bool { get }
    /// Variables added to the process's environment.
    var environment: [String: String] { get }
    /// The process runs in its own fresh empty folder (ArisSealedScratch), not Aris's.
    var isolatedFolder: Bool { get }
    /// `ask` with the turn's checked images (ArisTurnImage.parse); a brain that can't take them gets the prompt alone.
    func ask(_ prompt: String, images: [ArisTurnImage], tier: ArisTier) -> [Data]
    func read(_ line: String) -> [ArisBrainEvent]
    /// The process ended; the next one starts from scratch.
    func reset()
    /// Lines that start a new conversation in the running process, forgetting the old one; nil when the tool
    /// can't, and the process is restarted instead.
    func newConversation() -> [Data]?
    /// The user's answer to a `.confirm`: the lines that tell the AI (none for an unknown or answered id).
    func decide(_ id: String, allow: Bool) -> [Data]
    /// A yes from the escalation gate, not the user: it covers this one call only, never a session, and isn't
    /// remembered as a yes for the next one.
    func approveOnce(_ id: String) -> [Data]
    /// The owner's ②A: the call is declined because the agent ran the user's changed card itself (`arguments`), and the AI is
    /// told so with `note`; not a no for the rest of the turn.
    func declineEdited(_ id: String, arguments: [String], note: String) -> [Data]
    /// The read judge blocked this read: declined, the AI told why (`note`); not a no for the rest of the turn.
    func refuseRead(_ id: String, note: String) -> [Data]
    /// The user's own words for the coming question (from the microphone), for the risk gate.
    func setRequest(_ text: String)
    /// The coming question was heard hands-free (ArisHandsFree): no remembered yes, no request coverage.
    func setHandsFree(_ handsFree: Bool)
    /// The question carries outside text (the screen, for "이거"): what follows is treated as after a web read.
    func markUntrusted()
    /// The conversation has seen the screen (an image came with this turn or an earlier one): screenSeen at least.
    func markScreenSeen()
    /// `aris-tools desktop` read this app's own window (its accessibility tree, a screenshot, an action's result): outside
    /// text for everything but computer use in that same app (ArisComputerUseLedger). `app`: its bundle id.
    func markAppRead(_ app: String)
    /// The taint as computer use in `app` sees it: its own window doesn't count. A brain that can't tell says `taint`.
    func taint(forApp app: String) -> ArisTaint
    /// The action behind a confirm still waiting for an answer; nil when unknown (then the user is asked).
    func escalation(for id: String) -> ArisPendingAction?
    /// How far outside content has come into this conversation.
    var taint: ArisTaint { get }
    /// Line kinds the driver knows and may say nothing about (ArisEventDrift: not drift).
    var quietKinds: Set<String> { get }
    /// Aside started for this turn (ArisAsideTool): lines that let the process wait for it (the API brain's helper).
    func asideStarted() -> [Data]
}

extension ArisBrainDriver {
    func asideStarted() -> [Data] { [] }
    var takesImages: Bool { false }
    var environment: [String: String] { [:] }
    var isolatedFolder: Bool { false }
    func ask(_ prompt: String, images: [ArisTurnImage], tier: ArisTier) -> [Data] { ask(prompt, tier: tier) }
    func opening() -> [Data] { [] }
    func reset() {}
    func newConversation() -> [Data]? { nil }
    func decide(_ id: String, allow: Bool) -> [Data] { [] }
    /// A driver that can't approve just one call declines it.
    func approveOnce(_ id: String) -> [Data] { decide(id, allow: false) }
    /// A driver that can't be told declines it as a plain no.
    func declineEdited(_ id: String, arguments: [String], note: String) -> [Data] { decide(id, allow: false) }
    func refuseRead(_ id: String, note: String) -> [Data] { decide(id, allow: false) }
    var missing: ArisBrainTrouble.Missing? { launch() == nil ? .program : nil }
    var isReady: Bool { true }
    func prepare() {}
    func setRequest(_ text: String) {}
    func setHandsFree(_ handsFree: Bool) {}
    func markUntrusted() {}
    func markScreenSeen() {}
    /// A brain that keeps no per-app reads treats one as any outside text (every later action then asks).
    func markAppRead(_ app: String) { markUntrusted() }
    func taint(forApp app: String) -> ArisTaint { taint }
    func escalation(for id: String) -> ArisPendingAction? { nil }
    /// A brain that can't tell is treated as steered by outside text.
    var taint: ArisTaint { .outsideText }
    var quietKinds: Set<String> { [] }
    /// Any outside content at all (every caller from before the two levels).
    var isTainted: Bool { taint != .none }

    func ask(_ prompt: String) -> [Data] {
        ask(prompt, tier: .quick)
    }

    /// The first of `candidates` that is there, else the program of that name on the user's own PATH (ArisPrograms:
    /// an nvm, volta, bun or npm-prefix install is found as a terminal finds it).
    static func installed(_ candidates: [String]) -> URL? {
        ArisPrograms.find(candidates.first.map { ($0 as NSString).lastPathComponent } ?? "", known: candidates)
    }

    static func line(_ object: [String: Any]) -> Data {
        ((try? JSONSerialization.data(withJSONObject: object)) ?? Data()) + Data("\n".utf8)
    }
}

/// A brain's command line as agent.log keeps it when its process ends on its own: the flags' names, and a value only
/// when it is one short word (a model, a mode). Never the long ones: Claude's is its whole system prompt, the allow and
/// deny rules and the hook settings, which went into the log in full on every unexpected end (HANDOVERS C).
enum ArisLoggedArguments {
    /// The longest value kept as it is.
    static let longest = 48
    /// Flags whose values are never kept, however short.
    static let hidden: Set<String> = ["--system-prompt", "--append-system-prompt", "--settings", "--mcp-config", "--allowedTools", "--disallowedTools",
                                      "--profile", "-c", "--config"]

    static func isFlag(_ word: String) -> Bool {
        word.hasPrefix("-") && word.count <= 40 && !word.contains(where: \.isWhitespace)
    }

    static func line(_ arguments: [String]) -> String {
        var parts: [String] = []
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            index += 1
            guard isFlag(word) else {
                // A word before any flag (a subcommand): kept when short.
                parts.append(word.count <= longest && !word.contains(where: \.isNewline) ? word : "‹\(word.count) characters›")
                continue
            }
            var values: [String] = []
            while index < arguments.count, !isFlag(arguments[index]) {
                values.append(arguments[index])
                index += 1
            }
            if values.isEmpty {
                parts.append(word)
            } else if values.count == 1, !hidden.contains(word), values[0].count <= longest, !values[0].contains(where: \.isNewline) {
                parts.append("\(word) \(values[0])")
            } else {
                parts.append("\(word) ‹\(values.count == 1 ? "\(values[0].count) characters" : "\(values.count) values")›")
            }
        }
        return parts.joined(separator: " ")
    }
}

/// Claude Code, kept lean the way Atticus does it: Aris's own short system prompt, no user settings,
/// hooks, CLAUDE.md or MCP servers, low effort, a few tools, and "don't ask" mode: the commands on the
/// allow list run without a prompt and everything else is refused. (Auto mode was tried: its safety
/// check took over ten seconds per command.)
///
/// `sealed` (the owner's ruling R2 = a): the Claude that answers a conversation that saw the screen (and a hands-free one).
/// It is a process of its own with Bash for the sealed aris-tools list only (ArisSealedTools: no files, Read or MCP
/// server) and the web; since the owner's ruling of 2026-11-06 the list includes their apps' reads and the connected services,
/// and its hook puts every read and every web search or fetch to the read judge first, so instructions on screen can't
/// get anything sent out unnoticed. aris-tools refuses the rest itself (ARIS_SEALED=1), and the process is stopped if
/// its init line shows any other tool or server, or it starts a command off the list. Only it takes images.
/// What writes, sends or opens something never runs in that process either: on a screen turn aris-tools hands the call
/// to the agent's gate (ArisHandOff: judged as Codex's on a turn that saw the screen, the user's card when that says to
/// ask), so the sealed Claude can act for him without gaining a way to act on its own (audit gate-1).
final class ArisClaudeDriver: ArisBrainDriver {
    /// stream-json kinds Claude Code writes that often carry nothing for Aris (a system line, a rate-limit notice, a
    /// non-text delta, a user tool result).
    static let quietKinds: Set<String> = ["system", "assistant", "user", "stream_event", "rate_limit_event", "result"]
    var quietKinds: Set<String> { Self.quietKinds }
    private let model: String
    private let tools: String
    let sealed: Bool
    /// A background task's process: its system prompt asks for a line to say and the full result (ArisTaskResult),
    /// never the jobs block (only main Aris splits work).
    let task: Bool
    /// The restricted Claude for a hands-free turn or job (always sealed; ArisHandsFree.profile).
    let handsFree: Bool

    /// The sealed process's init line showed exactly its tools and no MCP server (checked before any answer).
    private var initSeen = false

    /// The open Claude's private folder for its turn gate's mark (ArisTurnGate); nil for the sealed one.
    private let turnFolder: URL?

    /// A teammate's job: what it may use (ArisTeammateScope). Denied by Claude Code's rules, its hook and aris-tools.
    let scopes: Set<ArisTeammateScope>?

    init(model: String, tools: String, sealed: Bool = false, task: Bool = false, handsFree: Bool = false, scopes: Set<ArisTeammateScope>? = nil) {
        self.model = model
        self.tools = tools
        self.sealed = sealed || handsFree
        self.task = task
        self.handsFree = handsFree
        self.scopes = scopes
        turnFolder = sealed || handsFree ? nil : ArisTurnGate.makeFolder()
    }

    deinit {
        if let turnFolder { try? FileManager.default.removeItem(at: turnFolder) }
    }

    var takesImages: Bool { sealed }

    /// Outside content this process's thread has taken in, from the tools it was seen to use (review of Task 12): a web
    /// fetch or search, an MCP tool, a file read, any shell command but aris-tools, or an aris-tools command that reads
    /// outside content (the screen, the clipboard, Canvas, the weather service, model-written schedules…) makes it
    /// outside text; a turn with none of these stays clean. Cleared with the process.
    private var seen = ArisTaint.none
    /// The apps whose own windows `aris-tools desktop` read for this thread (bundle ids): outside text for everything
    /// but computer use in that app.
    private var appsRead: Set<String> = []

    var taint: ArisTaint { appsRead.isEmpty ? seen : .outsideText }

    func taint(forApp app: String) -> ArisTaint { appsRead.subtracting([app]).isEmpty ? seen : .outsideText }

    /// An app's window was read: outside text for the turn gate too (nothing outbound after it), but not `seen`.
    func markAppRead(_ app: String) {
        appsRead.insert(app)
        if !sealed, !ArisTurnGate.mark(turnFolder) {
            markFailed = true
            if let turnFolder { try? FileManager.default.removeItem(at: turnFolder) }
        }
    }

    func markUntrusted() {
        seen = .outsideText
        // Outside text came with the prompt itself: the turn gate counts it as a read (no web, nothing outbound). A mark
        // that can't be written still counts (I3): the folder goes, so the hook fails closed, and the driver's own flag
        // keeps its backstop on.
        if !sealed, !ArisTurnGate.mark(turnFolder) {
            markFailed = true
            if let turnFolder { try? FileManager.default.removeItem(at: turnFolder) }
        }
    }

    /// A mark the driver couldn't write (I3): counts as one until the conversation starts over.
    private var markFailed = false

    /// The open Claude's conversation has read outside text (the turn gate's mark, or the fallback flag).
    var turnMarked: Bool { !sealed && (markFailed || ArisTurnGate.isMarked(turnFolder)) }

    /// Said when the open Claude, after a read, reached for something that is neither a read nor a call the agent's gate
    /// takes (or for a local address) and was stopped (I2). Its writes and sends no longer end here: they ask on a card.
    static let afterReadStop = "읽은 내용이 있어서 밖으로 보내는 일은 막고 멈췄어요. 새 대화에서 다시 물어봐 주세요."
    /// Said when a web result came back that this turn's read judge never allowed (security review I3).
    static let uncheckedWebStop = "확인하지 않은 웹 결과가 와서 멈췄어요. 다시 물어봐 주세요."

    /// Whether this turn's read judge allowed exactly this call (the runner's memo); none set: never (fail closed).
    var webAllowed: (ArisReadCall) -> Bool = { _ in false }
    /// The web calls (by tool-use id) whose results need the judge's yes: every one of the sealed Claude, a job's, and
    /// the open Claude's after a read.
    private var judgedWeb: [String: ArisReadCall] = [:]

    func markScreenSeen() {
        seen = max(seen, .screenSeen)
    }

    /// Whether a tool call this brain announced brings outside content into its thread. An allowlist (security review
    /// of ee191bc): only one aris-tools command of a shape that returns nothing others wrote (a timer, the volume,
    /// music, a window, an app or folder opened, the calendar app) is clean; anything else, every read included (to-dos,
    /// memory, calendars, shortcuts, windows, the clipboard…), is outside text.
    /// `handsOff`: a Claude, whose writes the agent runs and answers itself (ArisHandOff): one whose answer is the
    /// agent's fixed words brings nothing in. Never for a brain that runs the command in its own process (agy).
    static func bringsInOutside(_ call: ArisAgentStream.ToolCall, tools: String, handsOff: Bool = false) -> Bool {
        // One desktop call (its text on stdin included): the agent's desktop engine marks the app it read (markAppRead).
        if call.name == "Bash", let command = call.command, ArisDesktopShell.words(command, tools: tools) != nil { return false }
        guard call.name == "Bash", let command = call.command,
              let words = ArisCommandPolicy.words(command), (ArisCommandPolicy.segments(command) ?? []).count == 1,
              words.first == tools, words.count > 1 else { return true }
        let rest = Array(words.dropFirst())
        // One plain service call: the agent's gate marks this thread itself, before the service is reached (M8).
        if rest.first == "mcp" { return false }
        // A skill: the agent marks this thread itself when a script's output comes back; reading the skill the user installed isn't.
        if rest.first == "skill" { return false }
        // A routine's AI-worded steps mark the thread themselves when they come back (ArisRoutineRoutes).
        if rest.first == "routine" { return false }
        // Aside: the agent marks this thread itself, before Aside runs.
        if rest.first == "aside" { return false }
        // A message: the agent decides and sends it, and says back only fixed words (ArisMessageGate.reported).
        if ArisTurnGate.isAgentMessage(rest) { return false }
        // A write handed to the agent (ArisHandOff), which answers it in fixed words; when it fails, the agent marks
        // this thread itself, before the error comes back.
        if handsOff, ArisHandOff.bringsNothingIn(rest) { return false }
        return !ArisTurnGate.bringsNothingIn(rest)
    }


    /// Assistant content blocks that carry no tool and no outside text.
    private static let plainBlocks: Set<String> = ["text", "thinking", "redacted_thinking"]

    var isolatedFolder: Bool { sealed }

    /// The sealed process: aris-tools enforces its list too (with `message`, handed to the agent: messageKey), and no
    /// claude.ai connectors ride along. The open one: where
    /// its turn gate keeps the mark (no folder: the gate treats every call as after a read).
    /// The open Claude's background job: every read judged from its first (ArisReadGate.carefulKey).
    /// Every Claude's commands may take up to 30 minutes, by default too (an Aside task: its card, then Aside's own 15;
    /// Claude Code's limit is 2 by default and 10 at most otherwise; aris-tools keeps its own limits).
    var environment: [String: String] {
        (sealed ? [ArisSealedTools.environmentKey: "1", ArisSealedTools.messageKey: "1", "ENABLE_CLAUDEAI_MCP_SERVERS": "false"]
                    // A screen turn's writes are handed to the agent's gate (ArisHandOff); a hands-free turn's never are.
                    .merging(handsFree ? [ArisSealedTools.handsFreeKey: "1"] : [ArisHandOff.sealedKey: "1"]) { $1 }
            : [ArisTurnGate.stateKey: turnFolder?.path ?? "none"].merging(task ? [ArisReadGate.carefulKey: "1"] : [:]) { $1 })
            .merging(["BASH_MAX_TIMEOUT_MS": "1800000", "BASH_DEFAULT_TIMEOUT_MS": "1800000"]) { $1 }
    }

    func reset() {
        // A new conversation: what the old one read is gone with it, so the web and sending open again (the folder is
        // made again if it went: I3).
        ArisTurnGate.clear(turnFolder)
        markFailed = false
        initSeen = false
        seen = .none
        appsRead = []
        inTurn = false
        classified = []
        judgedWeb = [:]
    }

    /// A turn is under way (between ask and its result): anything it can't read then is outside text (fail closed).
    private var inTurn = false
    /// The tool calls seen this process (by id): a result for any other is outside text.
    private var classified: Set<String> = []

    /// aris-tools that send, delete, type or open things, as a brain with no risk gate and no hand-off must be refused
    /// them (Antigravity's own shell: ArisAgyRules). A Claude isn't refused them any more (audit gate-2): aris-tools
    /// hands each to the agent, which judges it as Codex's and asks the user on a card (ArisHandOff, ArisActionGate), so
    /// `openRefused` below drops every handed-off form.
    /// `schedule add` makes work that runs later on its own, and `schedule remove` cancels the user's. `undo` could bring a
    /// removed schedule back or delete an event. Memory, events and to-dos are read back in later turns, so outside text
    /// written there would steer them: a brain that can't tell outside text came in never writes them itself.
    /// `memory`: this brain can't tell outside text came in, so it never reads the user's memories either (its clean turns get
    /// the relevant ones in the context).
    /// The user's messages, mail, notes and Obsidian (ArisLocalReadPolicy.privateReads) are refused to agy (no hooks); the
    /// open Claude reads them behind its turn gate (ArisTurnGate) and the sealed one behind its hook, both with the read
    /// judge, so `openRefused` (which both use) drops them.
    static let ungatedRefused = ["message", "mail", "messages", "notes", "obsidian", "trash", "keys", "type", "link", "shortcut", "clipboard set", "schedule add", "schedule remove",
                                 "undo", "remember", "forget", "memory", "event", "todo add", "todo edit", "todo remove", "todo done", "remind", "note"]

    /// Refused even if a rule above would allow them.
    private static let neverAllowed = [
        "Bash(rm:*)", "Bash(sudo:*)", "Bash(su:*)", "Bash(diskutil:*)", "Bash(dd:*)", "Bash(mkfs:*)",
        "Bash(shutdown:*)", "Bash(reboot:*)", "Bash(halt:*)", "Bash(launchctl:*)", "Bash(csrutil:*)",
        "Bash(chmod -R:*)", "Bash(chown:*)", "Bash(defaults delete:*)", "Bash(tccutil:*)",
        "Bash(git push:*)", "Bash(security:*)",
        // Keys and tokens: a web page's hidden instructions must never get them read (and then fetched out).
        "Read(~/.ssh/**)", "Read(~/.gnupg/**)", "Read(~/.aws/**)", "Read(~/.codex/**)", "Read(~/.claude/**)",
        "Read(~/.config/aris/claude-hook-token)", "Read(~/.config/aris/*-key)", "Read(~/Library/Keychains/**)",
        // Nor through the shell, open or sealed (security review of batch 3: the token alone reached the app's routes).
        "Bash(*claude-hook-token*)", "Bash(*/.config/aris/*-key*)", "Bash(*/.config/boring-notch/*-key*)",
        // The old folder name is a link to the same files.
        "Read(~/.config/boring-notch/claude-hook-token)", "Read(~/.config/boring-notch/*-key)",
        // Computer use's runtime and Peekaboo's store: only the agent runs or reads them (I11, I12). Only Peekaboo as the
        // program: a note or a typed message may name it (re-review 1).
        "Bash(peekaboo:*)", "Bash(*/peekaboo:*)", "Bash(*/computer-runtime/*)",
        "Read(~/.peekaboo/**)", "Read(~/Library/Application Support/Aris/computer-runtime/**)",
    ] + ArisLocalReadPolicy.storeFolders.map { "Read(~/\($0)/**)" } + schedulerFiles

    /// The scheduled work and what it produced (model-written prompts and results), the activity log that can bring
    /// a schedule back, the teammate list, the Claude Code prompt files and the memory store (its day notes are the user's
    /// words; memories are read through `aris-tools memory`): this brain (no gate) neither reads nor writes them;
    /// aris-tools and the agent do that.
    private static let schedulerFiles = ["~/.config/aris/aris", "~/.config/boring-notch/aris"].flatMap { folder in
        ["schedules.json", "routines.json", "inbox.jsonl", "activity.jsonl", "teammates.json", "teammates/**", "teammate-jobs/**", "knowhow.md", "work/**", "memory.sqlite*", "memory.md"].flatMap { file in
            ["Read", "Edit", "Write"].map { "\($0)(\(folder)/\(file))" }
        }
    }

    /// What Aris's Claude may use without asking: aris-tools (every Mac action goes through it), reading Aris's own
    /// folder, and the web. Anything else is refused (this brain has no risk gate to ask the user): no raw osascript
    /// or open, which could run anything, and no reading the user's files, so nothing private can be read and then
    /// sent out through a web fetch.
    private var allowed: [String] {
        ["Bash(\(tools):*)", "Read(~/.config/aris/aris/**)", "WebSearch", "WebFetch"]
    }

    func launch() -> (URL, [String])? {
        guard let claude = Self.installed(["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]) else { return nil }
        return (claude, arguments)
    }

    /// The command line after the program.
    var arguments: [String] {
        sealed ? sealedArguments : openArguments
    }

    /// What every Claude shares. `--no-session-persistence`: Claude Code keeps no session transcript (with the images
    /// in it) under ~/.claude/projects.
    private func common(settings: String = #"{"disableAllHooks":true}"#) -> [String] {
        ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
         "--include-partial-messages", "--no-session-persistence",
         "--model", model, "--effort", "low",
         "--permission-mode", "dontAsk", "--permission-prompts", "none",
         "--setting-sources", "", "--settings", settings,
         // No MCP servers or claude.ai connectors: their tool lists made every request seconds slower (and the
         // sealed Claude must have none).
         "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]
    }

    /// Bash, allowed exactly for the sealed aris-tools list, and the web (no Read or MCP server). Three layers, each
    /// before the next: "dontAsk" refuses anything not allowed without asking; the PreToolUse hook (aris-tools
    /// sealed-gate) blocks any call ArisSealedTools.hookVerdict rejects before it runs and puts every read and web call
    /// to the read judge; the deny shapes and the deny lists on top (the user's app reads aren't on them: the hook judges
    /// those). observe still stops the process if anything gets past them.
    private var sealedArguments: [String] {
        common(settings: ArisSealedTools.hookSettings(tools: tools)) + ["--tools", toolList.joined(separator: ","), "--allowedTools"]
            + ArisSealedTools.allowRules(tools: tools, memory: !handsFree, messages: true, handOff: !handsFree) + ["WebSearch", "WebFetch"]
            + ["--disallowedTools"] + ArisSealedTools.deniedShapes + Self.neverAllowed
            + (handsFree ? Self.handsFreeRefused + ["memory"] : Self.sealedRefused).map { "Bash(\(tools) \($0):*)" } + scopeDenied
            + ["--system-prompt", ArisAgentPrompt.sealed(tools: tools, handsFree: handsFree, task: task)]
    }

    /// Every Claude's own checks on a line, before it's read as usual. Its init must list exactly its tools and no MCP
    /// server, and nothing may answer before that (else the process is stopped). The sealed Claude's every tool call
    /// must be a command on the sealed list (else it is stopped). Taint is observed and fails closed: a tool that brings
    /// in outside content, a line that can't be read during a turn, an unknown content block, a tool result for a call
    /// that was never seen, or a failed turn makes the thread outside text.
    private func observe(_ line: String) -> [ArisBrainEvent]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if inTurn, !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { seen = .outsideText }
            return nil
        }
        let refused = [ArisBrainEvent.abort(handsFree ? ArisHandsFree.askAgainLine
                                            : sealed ? "화면을 본 Claude가 허용되지 않은 도구를 가져서 멈췄어요."
                                                   : "Claude가 허용되지 않은 도구를 가져서 멈췄어요.")]
        switch (object["type"] as? String, object["subtype"] as? String) {
        case ("system", "init"):
            let listed = object["tools"] as? [String] ?? []
            // A teammate's Claude is given fewer tools (ArisTeammateScope.claudeTools): it must list exactly those.
            let expected = Set(toolList)
            guard Set(listed) == expected, listed.count == expected.count, let servers = object["mcp_servers"] as? [Any], servers.isEmpty else { return refused }
            initSeen = true
            return []
        case ("assistant", _):
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            // Outside text an earlier block of this same message brings in (its mark may not be written yet).
            var broughtInHere = false
            for block in content {
                let type = block["type"] as? String ?? ""
                if type == "tool_use" {
                    let input = block["input"] as? [String: Any] ?? [:]
                    let command = input["command"] as? String
                    let call = ArisAgentStream.ToolCall(name: block["name"] as? String ?? "", command: command)
                    // The hook resolved the address already; here only its shape counts (no lookup on this queue).
                    let shapeOnly: (String) -> [String]? = { _ in ["93.184.216.34"] }
                    if sealed {
                        // The web goes to its hook's read judge (never to a local address); Bash only for the sealed list.
                        let web = call.name == "WebSearch" || call.name == "WebFetch"
                        let fetchOK = ArisReadGate.fetchAllowed(tool: call.name, input: input, resolve: shapeOnly) != false
                        guard (web && fetchOK) || (call.name == "Bash" && command.map { ArisSealedTools.permits(command: $0, tools: tools, memory: !handsFree,
                                                                                                                  messages: true, handOff: !handsFree) } == true)
                        else { return refused }
                    } else if turnMarked, case .deny = ArisTurnGate.verdict(tool: call.name, command: command, tools: tools, tainted: true,
                                                                            input: input, resolve: shapeOnly) {
                        // The backstop (I2): after a read, a command (or an address) the turn gate refuses stops the
                        // process, whatever the hook did.
                        return [.abort(Self.afterReadStop)]
                    }
                    if let id = block["id"] as? String {
                        classified.insert(id)
                        // I3: a web call the hook had to judge; its result must find the judge's yes.
                        if let web = ArisReadGate.call(webTool: call.name, input: input), sealed || task || turnMarked || broughtInHere {
                            judgedWeb[id] = web
                        }
                        // R5: so must a page the open Claude fetched with aris-tools after a read (or in a job).
                        if !sealed, call.name == "Bash", let command, task || turnMarked || broughtInHere,
                           case .judge(let read, _) = ArisTurnGate.verdict(tool: "Bash", command: command, tools: tools, tainted: turnMarked || broughtInHere,
                                                                           careful: task, resolve: shapeOnly),
                           read.tool == "web fetch" || read.arguments.contains("web fetch") {
                            judgedWeb[id] = read
                        }
                    }
                    // What marks the turn (R1: an ordinary web search on a clean turn doesn't).
                    let bringsIn = Self.bringsInOutside(call, tools: tools, handsOff: !handsFree)
                    if bringsIn, sealed || task || !(call.name == "WebSearch" || call.name == "WebFetch") { broughtInHere = true }
                    // Seen before the tool runs: its result is outside content from here on.
                    if bringsIn { seen = .outsideText }
                } else if !Self.plainBlocks.contains(type) {
                    seen = .outsideText
                }
            }
            return initSeen ? nil : refused
        case ("user", _):
            let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content where block["type"] as? String == "tool_result" {
                let id = block["tool_use_id"] as? String ?? ""
                if !classified.contains(id) { seen = .outsideText }
                // The backstop (I3): a web result the judge never allowed stops the process before the model reads it.
                // A refused call comes back as an error and ran nothing.
                if let web = judgedWeb.removeValue(forKey: id), block["is_error"] as? Bool != true, !webAllowed(web) {
                    return [.abort(Self.uncheckedWebStop)]
                }
            }
            return nil
        case ("result", _):
            inTurn = false
            if object["is_error"] as? Bool == true || object["subtype"] as? String != "success" { seen = .outsideText }
            return initSeen ? nil : refused
        case ("stream_event", _):
            return initSeen ? nil : refused
        default:
            return nil
        }
    }

    /// The open Claude's refusals: the ungated list but the reads its turn gate guards (that gate also refuses any
    /// `mail` that isn't a read), the user's memories (judged on a careful turn, like every brain's: minor 2), `message`,
    /// which aris-tools hands to the agent to decide (ArisMessageGate: the countdown or the user's card, as Codex's gate),
    /// and every write aris-tools hands to the agent the same way (ArisHandOff: judged as Codex's, the user's card when that
    /// says to ask). Inside this brain's process aris-tools never runs one of those itself (handOffRouting).
    static var openRefused: [String] {
        ungatedRefused.filter { command in
            !ArisLocalReadPolicy.privateReads.contains(command) && command != "memory" && command != "message"
                && !ArisHandOff.names(command.split(separator: " ").map(String.init))
        }
    }
    /// The sealed Claude's refusals: the open list (the owner, 2026-11-08: its `message` goes to the agent too, which shows
    /// his plain card, never a countdown, and refuses it after outside text; its other writes go to the agent's gate
    /// too, as the open Claude's: audit gate-1).
    static var sealedRefused: [String] { openRefused }
    /// The hands-free Claude's refusals: every write, as before (the owner, 2026-11-08: nothing is sent, deleted or changed
    /// on words anyone near the Mac could have said; only its `message` is his plain card). Nothing of it is handed off.
    static var handsFreeRefused: [String] {
        ungatedRefused.filter { !ArisLocalReadPolicy.privateReads.contains($0) && $0 != "memory" && $0 != "message" }
    }

    /// Every call first asks the turn gate (ArisTurnGate): after a read, no web and nothing outbound.
    private var openArguments: [String] {
        common(settings: ArisTurnGate.hookSettings(tools: tools)) + ["--tools", toolList.joined(separator: ","),
                  "--allowedTools"] + allowed + ["--disallowedTools"] + Self.neverAllowed
            + Self.openRefused.map { "Bash(\(tools) \($0):*)" } + scopeDenied
            + ["--system-prompt", ArisAgentPrompt.system(tools: tools, task: task, reads: true)]
    }

    /// The tools this Claude is given and its init must list (checked live: claude 2.1.317 lists exactly the open Bash,
    /// Read, WebFetch, WebSearch and no MCP server; the sealed one Bash and the web), less what a teammate's scopes leave out.
    private var toolList: [String] { ArisTeammateScope.claudeTools(scopes, sealed: sealed) }

    /// A teammate's deny rules (none for any other job).
    private var scopeDenied: [String] {
        scopes.map { ArisTeammateScope.claudeDenied($0, tools: tools) } ?? []
    }

    func ask(_ prompt: String, tier: ArisTier) -> [Data] {
        inTurn = true
        return [ArisAgentStream.userMessage(prompt)]
    }

    func ask(_ prompt: String, images: [ArisTurnImage], tier: ArisTier) -> [Data] {
        inTurn = true
        return [ArisAgentStream.userMessage(prompt, images: sealed ? images : [])]
    }

    func read(_ line: String) -> [ArisBrainEvent] {
        // nil: read it as usual; [] the init line passed; else the abort.
        if let checked = observe(line) { return checked }
        switch ArisAgentStream.parse(line) {
        case .tools(let calls):
            let status = calls.last.flatMap { call in
                call.name == "Bash" ? call.command.map { ArisAgentStatus.forCommand($0, tools: tools) } : ArisAgentStatus.forClaudeTool(call.name)
            }
            return [.tools(calls)] + (status.map { [.status($0)] } ?? [])
        case .delta(let text): return [.delta(text)]
        case .result(let answer): return [.result(answer)]
        case .failure(let message): return [ArisBrainFailure.event(message, brain: .claude)]
        // A tool result that is an error: the step it ended gets no tick.
        case .other: return ArisStepOutcome.claude(line: line)
        }
    }
}
