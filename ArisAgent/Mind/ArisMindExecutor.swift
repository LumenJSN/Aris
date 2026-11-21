//
//  ArisMindExecutor.swift
//  aris-agent
//
//  Runs one capability call that the trust decision let through, the Core 2 way (ARCHITECTURE Part 2, Hands and Record):
//  · shell.run under the shell sandbox (ArisShellSandbox.command): the never-list's places hold even when a command's
//    words fooled the text check;
//  · file.write and file.edit with their undo: the file's bytes kept first (ArisUndoStore), the recipe made after
//    (ArisUndoRecipes), so the record can put it back;
//  · the volume with its value before, so the record's undo sets it back (ArisMindUndoHooks);
//  · the record's undo capabilities with the call's real caller (its session, task and provenance);
//  · an aris-tools entry as aris-tools with those words (in-process where the registry says it can), a call that
//    hands back an id collected until it is done, its output marked as content where others' words may be in it;
//  · any other helper capability as itself.
//  Its parts are handed in, so the tests run it in a temp home with fakes.
//

import Foundation

struct ArisMindExecutor: @unchecked Sendable {
    let tools: String
    let environment: [String: String]
    let home: String
    let folder: URL
    var timeout: TimeInterval = ArisHandsFace.callLimit
    /// aris-tools with these words and that stdin.
    var runTools: (_ argv: [String], _ stdin: String?) -> ArisCapabilityLocal.Output
    /// aris-tools with a mark in its environment (callMarkKey) that the activity log's entries it writes
    /// keep, so the record knows which of them are this call (nil: runTools, and no entry is known as this call's).
    var markedTools: ((_ argv: [String], _ stdin: String?, _ mark: String) -> ArisCapabilityLocal.Output)?
    /// A read of Aris's own stores in this process; nil for a call a child runs.
    var local: (_ argv: [String]) -> ArisCapabilityLocal.Output? = { _ in nil }
    /// A shell line in a folder: the sandboxed shell by default.
    var shell: (_ line: String, _ folder: String, _ timeout: TimeInterval) -> ArisCapabilityLocal.Output
    var store: ArisUndoStore
    var hooks: ArisMindUndoHooks = .live
    /// The activity log's entries, where aris-tools keeps the id of an event or a to-do it made (ArisMindItemUndo).
    var activity: () -> [[String: Any]] = { ArisActivityBridge.objects(ArisActivityBridge.defaultLog) }
    /// The disk as a shell command's undo is read and confirmed on (ArisMindShellUndo).
    var disk = ArisMindShellUndo.Disk()

    init(tools: String, environment: [String: String], home: String = NSHomeDirectory(), folder: URL = ArisCapabilityLocal.ownFolder,
         runTools: ((_ argv: [String], _ stdin: String?) -> ArisCapabilityLocal.Output)? = nil,
         shell: ((_ line: String, _ folder: String, _ timeout: TimeInterval) -> ArisCapabilityLocal.Output)? = nil, store: ArisUndoStore? = nil) {
        self.tools = tools
        self.environment = environment
        self.home = home
        self.folder = folder
        let limit = ArisHandsFace.callLimit
        let child = Self.childEnvironment(environment)
        self.runTools = runTools ?? { argv, stdin in ArisHandsServer.runTools(tools, argv, stdin, child, limit) { _ in } }
        if runTools == nil {
            markedTools = { argv, stdin, mark in
                ArisHandsServer.runTools(tools, argv, stdin, ArisMindExecutor.marked(child, mark), limit) { _ in }
            }
        }
        self.shell = shell ?? { line, folder, timeout in ArisMindExecutor.sandboxed(line, folder: folder, environment: environment, home: home, timeout: timeout) }
        self.store = store ?? ArisUndoStore(home: home)
    }

    /// Runs the call. `caller`: who asks, for an undo (the Mind's session and the call's provenance). `judged`: the effect
    /// the call was decided as (nil: read again now); an overwrite decided change-reversible runs only with its copy.
    /// `resolved`: a file capability's path as it was decided, links followed (ArisCore2.decidedPath); the path is
    /// resolved again now and must land there (nil: the decision didn't say, and no link may be on the way at all).
    func run(_ entry: ArisCapabilityEntry, arguments: [String: Any], argv: [String]?, stdin: String?, caller: ArisUndoCaller,
             judged: ArisEffectClass? = nil, resolved: String? = nil) -> ArisMindResult {
        if let argv { return arisTools(entry, argv: argv, stdin: stdin) }
        guard case .helper(let body) = entry.run else { return ArisMindResult(text: ArisTurnGate.unreadable, isError: true) }
        var context = ArisCapabilityContext(environment: environment, folder: folder, home: home, tools: tools, timeout: timeout)
        var arguments = arguments
        if let key = ArisCore2.pathArgument[entry.id] {
            switch ArisCore2.fileTarget(entry.id, arguments, decided: resolved, home: home) {
            case .failure(let refusal): return ArisMindResult(text: refusal.text, isError: true)
            case .success(let target):
                arguments[key] = target.path
                context.checkedReal = target.real
            }
        }
        switch entry.id {
        case "shell.run": return shellRun(arguments, judged: judged ?? entry.effect(arguments))
        case "file.write", "file.edit":
            let needsCopy = entry.id == "file.write" && (judged ?? entry.effect(arguments)) == .changeReversible
            return fileChange(arguments, needsCopy: needsCopy) { body(arguments, context) }
        default:
            if let undo = ArisRecord.capabilities.first(where: { $0.id == entry.id }) {
                let done = undo.run(arguments, caller, home)
                return ArisMindResult(text: done.text, isError: done.isError)
            }
            var own = environment
            own[ArisMindBook.sessionKey] = caller.session
            // What a capability starts gets the one child environment (aris-tools for a page or a document); the web
            // search's own searcher (agy, not aris-tools) keeps the caller's.
            if entry.id != "web.search" { own = Self.childEnvironment(own) }
            var called = ArisCapabilityContext(environment: own, folder: folder, home: home, tools: tools, timeout: timeout)
            called.checkedReal = context.checkedReal
            return Self.result(body(arguments, called))
        }
    }

    static func result(_ tool: ArisToolResult) -> ArisMindResult {
        ArisMindResult(text: tool.text, isError: tool.isError, content: tool.content.map { ArisContentSource(kind: $0.kind, source: $0.source) }, undo: tool.undo)
    }

    // MARK: - The shell

    /// `judged`: what the line was decided as. A copy or a move decided reversible rested on its undo; with none now
    /// (its target appeared since), nothing runs (as an overwrite with no copy: `noCopy`).
    private func shellRun(_ arguments: [String: Any], judged: ArisEffectClass) -> ArisMindResult {
        guard let command = ArisAPICatalog.text(arguments["command"]), !command.isEmpty, command.count <= 20_000 else {
            return ArisMindResult(text: "Not run: give the command.", isError: true)
        }
        let seconds = TimeInterval(min(max(ArisAPICatalog.whole(arguments["timeout"]) ?? 120, 1), 600))
        let cwd = ArisAPICatalog.text(arguments["cwd"]).map { ($0 as NSString).expandingTildeInPath } ?? home
        // A command that only makes or moves one thing to a new name: its undo, read before it runs, kept once confirmed.
        let plan = ArisMindShellUndo.plan(command, cwd: cwd, home: home, disk: disk)
        if judged == .changeReversible, plan == nil, ArisCore2.copiesOrMoves(command) { return ArisMindResult(text: Self.noPlan, isError: true) }
        let shown = ArisHandsServer.shown(shell(command, cwd, seconds))
        let undo = shown.isError ? nil : plan.flatMap { ArisMindShellUndo.confirmed($0, disk: disk) }
        return ArisMindResult(text: shown.text, isError: shown.isError, content: ArisContentSource(kind: "shell", source: String(command.prefix(200))), undo: undo)
    }

    /// `line` run by zsh under the sandbox profile, in `folder`, within `timeout`, in `childEnvironment(environment)`.
    static func sandboxed(_ line: String, folder: String, environment: [String: String], home: String, timeout: TimeInterval) -> ArisCapabilityLocal.Output {
        let command = ArisShellSandbox.command(line, home: home)
        return ArisHandsServer.runTools(command.executable, command.arguments, nil, childEnvironment(environment), timeout, folder: folder) { _ in }
    }

    /// The only folders a shell line's bare program names are found in (ArisCore2.trustedProgram rates a bare name as
    /// that system program).
    static let pinnedPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// What a child keeps of the parent's own: who and where it runs (and LC_*, below).
    static let keptVariables: Set<String> = ["HOME", "USER", "LOGNAME", "LANG", "TERM", "TMPDIR", "SHELL"]

    /// Aris's own machinery, passed on as it is, each with who reads it. Nothing else of the caller's environment (a
    /// Claude's, with its PATH, a loader's or a tool's options) reaches the child.
    static let arisVariables: Set<String> = [
        "ARIS_MCP_TURN_FILE",    // ArisMCPTurnCredential: the turn's credential file aris-tools sends to the agent's routes
        "ARIS_MIND_PASS",        // ArisMindPasses: the owner's yes on the gate's card, taken by the call's own route
        "ARIS_CALL_MARK",        // ArisActivity (aris-tools): the activity log marks the entries this call wrote
        "ARIS_MIND_SESSION",     // ArisMindBook.sessionKey: the Mind's session, for a capability that asks for it
        "ARIS_SWITCHES",         // ArisSwitchSet: the helper's switches as aris-tools reads them
        "ARIS_TURN_STATE",       // ArisTurnGate.stateKey: the open Claude's turn folder (its outside-text mark)
        "ARIS_JUDGE_READS",      // ArisReadGate.carefulKey: a job's reads go to the read judge
        "ARIS_CONVERT_DEADLINE", // ArisConvertWords.deadlineKey: when a conversion must end
        "ARIS_TASK",             // ArisConvertWords.taskKey: a background job's mark
        "ARIS_SEALED", "ARIS_SEALED_HANDS_FREE", "ARIS_SEALED_MESSAGES", // ArisSealedTools: the sealed lists aris-tools enforces
        "ARIS_SEALED_HANDOFF",   // ArisHandOff.sealedKey: a screen turn's writes go to the agent's gate
        "ARIS_UNGATED",          // ArisSealedTools.ungatedKey: aris-tools refuses the user's private reads itself
        "ARIS_TEAMMATE_SCOPES",  // ArisTeammateScope: a teammate's scopes, enforced by aris-tools
        "ARIS_FOREGROUND",       // ArisAutomationAsk: a turn the user is in front of
        "ARIS_BRAIN",            // ArisSchedule.brainKey: the brain a schedule is made with
        "ARIS_JOB", "ARIS_WORKER", "ARIS_TEAMMATE", // aris-tools' activity and schedule entries: whose work it is
        "CFFIXED_USER_HOME", "ARIS_TEST_PREFS",     // the tests' throwaway preferences (tests/run.sh); unset in use
    ]

    /// The one environment every child Core 2 starts gets (a shell line, an aris-tools call, an undo's aris-tools):
    /// empty, then the parent's `keptVariables`, LC_* and `arisVariables`, and PATH pinned to the system's folders. So
    /// nothing that makes a program run other code (DYLD_*, LD_*, ENV, BASH_ENV, ZDOTDIR, IFS, PAGER, EDITOR, LESSOPEN,
    /// MANPAGER, PERL5OPT, PYTHON*, NODE_OPTIONS, RUBYOPT, GIT_*, GREP_OPTIONS, TAR_OPTIONS, RIPGREP_CONFIG_PATH, …)
    /// gets there. A Homebrew tool by its bare name is then not found (by its full path it is an unknown program, which
    /// asks): accepted, for the rating to hold.
    static func childEnvironment(_ environment: [String: String]) -> [String: String] {
        var own = environment.filter { keptVariables.contains($0.key) || arisVariables.contains($0.key) || $0.key.hasPrefix("LC_") }
        own["PATH"] = pinnedPath
        return own
    }

    // MARK: - Files

    /// A write or an edit with its undo: the earlier bytes kept first (verified: ArisUndoStore.keep), the recipe made
    /// after. `needsCopy`: the write was decided change-reversible (decision 4), so a file that is there when it runs is
    /// overwritten only once its copy was kept; with none, nothing is written. A file decided as permanent (asked, the
    /// owner said yes) is still changed when it can't be kept, with no undo.
    private func fileChange(_ arguments: [String: Any], needsCopy: Bool = false, change: () -> ArisToolResult) -> ArisMindResult {
        guard let raw = ArisAPICatalog.text(arguments["path"]) else { return Self.result(change()) }
        let path = ((raw as NSString).expandingTildeInPath as NSString).standardizingPath
        let prepared = ArisUndoRecipes.beforeWrite(path, store: store)
        var there = stat()
        if needsCopy, lstat(path, &there) == 0, prepared?.copy == nil {
            return ArisMindResult(text: Self.noCopy, isError: true)
        }
        var result = Self.result(change())
        if result.isError {
            if let copy = prepared?.copy { store.remove(copy) }
            return result
        }
        result.undo = prepared.flatMap(ArisUndoRecipes.afterWrite)
        return result
    }

    /// What a decided call was decided as, from its verdict: run with its undo is change-reversible (an overwrite then
    /// runs only with its kept copy); anything asked (the owner said yes) or run without one is not.
    static func judged(_ verdict: ArisMindVerdict) -> ArisEffectClass {
        if case .run(true, _) = verdict { return .changeReversible }
        return .changePermanent
    }

    /// Said when a copy or a move decided reversible has no undo when it is about to run.
    static let noPlan = "Not run: what this command copies or moves onto is there now (it wasn't when it was decided), so it could overwrite "
        + "something with no way back; nothing ran. Tell the user; running it now needs their yes."

    /// Said when an overwrite decided reversible couldn't keep its copy (decision 4).
    static let noCopy = "Not changed: a copy of the file Aris could undo to couldn't be kept (too big, no room, or it changed), so nothing was overwritten. "
        + "Tell the user; overwriting it without a copy needs their yes."

    // MARK: - aris-tools

    private func arisTools(_ entry: ArisCapabilityEntry, argv: [String], stdin: String?) -> ArisMindResult {
        let content = ArisHandsServer.content(argv).map { ArisContentSource(kind: $0.kind, source: $0.source) }
        let before = hooks.before(entry.id, argv)
        if stdin == nil, let output = local(argv) {
            let shown = ArisHandsServer.shown(output)
            return ArisMindResult(text: shown.text, isError: shown.isError, content: content)
        }
        let started = Date()
        let mark = UUID().uuidString.lowercased()
        var output = markedTools.map { $0(argv, stdin, mark) } ?? runTools(argv, stdin)
        // A call that handed back an id (a desktop, service or skill call waiting on a card): collected here.
        if let kind = argv.first, ["desktop", "mcp", "skill"].contains(kind) {
            let deadline = started.addingTimeInterval(timeout)
            while output.status == ArisSlowCalls.waitingStatus, Date() < deadline,
                  let match = (output.stdout + output.stderr).range(of: #"wait [0-9a-f]{16}"#, options: .regularExpression) {
                output = runTools([kind, "wait", String((output.stdout + output.stderr)[match].dropFirst(5))], nil)
            }
        }
        let shown = ArisHandsServer.shown(output)
        let framed = Self.framedRoutes.contains(argv.first ?? "")
        guard !shown.isError else {
            var failed = ArisMindResult(text: shown.text, isError: true, content: content)
            failed.framed = framed
            return failed
        }
        // An event or a to-do it made: the app's id, from the activity log's entry written during the call.
        let entries = activity()
        let made = before == nil && ArisMindItemUndo.expected(argv) != nil ? ArisMindItemUndo.recipe(argv: argv, since: started, entries: entries) : nil
        var result = ArisMindResult(text: shown.text, isError: false, content: content, undo: before ?? made)
        result.framed = framed
        if markedTools != nil { result.logged = Self.logged(by: mark, in: entries) }
        // A file or calendar change that ran with its undo kept says so to the model (ArisUndoSaid).
        result.text = ArisUndoSaid.text(result.text, capability: entry.id, canUndo: result.undo != nil || !result.logged.isEmpty)
        return result
    }

    /// The aris-tools commands whose routes wrap their output in Aris's outside-text frame (ArisMCPPolicy.wrapped).
    static let framedRoutes: Set<String> = ["desktop", "mcp"]

    /// aris-tools' ArisActivity.callMarkKey (the tests hold the two the same).
    static let callMarkKey = "ARIS_CALL_MARK"

    /// `environment` with a call's mark for aris-tools' activity log.
    static func marked(_ environment: [String: String], _ mark: String) -> [String: String] {
        var own = environment
        own[callMarkKey] = mark
        return own
    }

    /// The activity log's entries a run with `mark` wrote, by id (lowercased).
    static func logged(by mark: String, in entries: [[String: Any]]) -> [String] {
        entries.compactMap { entry in
            guard (entry["call"] as? String) == mark, let id = (entry["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return id.uuidString.lowercased()
        }.suffix(20)
    }
}

/// The undo hooks for what isn't a file (ArisUndoHands): a recipe made before a change, and the performer that takes it
/// back. The Mac's volume (its value before; set back with aris-tools), and a calendar event or a to-do made through
/// aris-tools (taken back through the activity log's entry that holds its id: ArisMindItemUndo).
struct ArisMindUndoHooks: @unchecked Sendable {
    /// The volume now (0-100), nil when it can't be read.
    var volume: () -> Int?
    /// Sets the volume (aris-tools volume N).
    var setVolume: (Int) throws -> Void

    /// The recipe to keep for this call, read before it runs; nil when it has none.
    func before(_ id: String, _ argv: [String]) -> ArisUndoRecipe? {
        guard id == "aris.volume" || argv.first == "volume", let now = volume() else { return nil }
        return .setting(name: "volume", before: String(now))
    }

    /// Puts this process's performers into ArisUndoHands.live (once is enough; again changes nothing).
    func register() {
        let set = setVolume
        ArisUndoHands.live.setSetting = { name, value in
            guard name == "volume", let level = Int(value), (0...100).contains(level) else {
                throw ArisUndoError(message: "undoing \(name) isn't available in this helper yet")
            }
            try set(level)
        }
        let undoTools = undoTools
        ArisUndoHands.live.removeItem = { kind, id in
            try ArisMindItemUndo.remove(kind: kind, id: id, entries: ArisActivityBridge.objects(ArisActivityBridge.defaultLog)) {
                undoTools($0, kind == "reminder" ? ArisMindItemUndo.todoUndoKey(id) : nil)
            }
        }
    }

    /// aris-tools as Aris itself for an undo (never a brain's turn-gate folder, which would hand it back to a route): a
    /// to-do's undo gets a grant for exactly its own write (`todoKey`), single-use, while it runs (only the helper's own
    /// grants count; elsewhere the app says no and the undo says so).
    var undoTools: (_ argv: [String], _ todoKey: String?) -> (status: Int32, output: String) = { argv, todoKey in
        var environment = ArisMindExecutor.childEnvironment(ArisAPIHelper.scrubbed(ProcessInfo.processInfo.environment))
        environment[ArisTurnGate.stateKey] = nil
        environment[ArisHandOff.sealedKey] = nil
        let grant = todoKey.flatMap { ArisActionGrants.shared.mintUndo(exactly: $0) }
        defer { ArisActionGrants.shared.dropUndo(grant) }
        let output = ArisHandsServer.runTools(ArisAppBundle.toldTools, argv, nil, environment, ArisActivityBridge.undoTimeout) { _ in }
        return (output.status, output.stderr + output.stdout)
    }

    nonisolated(unsafe) static var live = ArisMindUndoHooks(
        volume: {
            let output = ArisHandsServer.runTools("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"], nil, [:], 5) { _ in }
            return output.status == 0 ? Int(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) : nil
        },
        setVolume: { level in
            let output = ArisHandsServer.runTools(ArisAppBundle.toldTools, ["volume", String(level)], nil,
                                                  ArisMindExecutor.childEnvironment(ArisAPIHelper.scrubbed(ProcessInfo.processInfo.environment)), 10) { _ in }
            guard output.status == 0 else { throw ArisUndoError(message: "the volume couldn't be set back") }
        })
}
