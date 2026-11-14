//
//  ArisAgentRunner.swift
//  aris-agent
//
//  Keeps one AI process alive per brain and model for Aris (Claude Code, Codex or
//  Antigravity), so follow-up questions skip the start-up time and remember the
//  conversation. The brain's driver speaks its line protocol; this owns the process,
//  the time limits and learning shortcuts. Only a known binary at a known path is
//  ever run, and questions go in on stdin as JSON, never through a shell.
//

import Foundation

final class ArisAgentRunner {
    private static let registry = NSLock()
    nonisolated(unsafe) private static var runners: [String: ArisAgentRunner] = [:]
    /// Which runner is waiting on each question put to the user.
    nonisolated(unsafe) private static var questions: [String: ArisAgentRunner] = [:]

    /// The running `brain` for `model` (ArisBrain.model(work:)). `sealed`: the Claude with no tools or web that answers
    /// turns carrying screen images (R2 = a), a process of its own (ArisImageRouting).
    static func shared(brain: ArisBrain, model: String, sealed: Bool = false, handsFree: Bool = false) -> ArisAgentRunner {
        registry.withLock {
            // This launch's nonce in every key: a question id from an earlier run never names a runner now.
            let key = ArisLaunch.sharedKey(brain: ArisImageRouting.runnerName(brain, sealed: sealed, handsFree: handsFree), model: model)
            if let runner = runners[key] { return runner }
            let runner = ArisAgentRunner(key: key, brain: brain, driver: driver(for: brain, model: model, sealed: sealed, handsFree: handsFree))
            runners[key] = runner
            return runner
        }
    }

    /// The details of each card put to the user (by id as the app got it), to check what the app says it showed.
    nonisolated(unsafe) private static var cards: [String: (detail: String, full: String?, fields: [ArisCardField])] = [:]

    /// Whether the details the app showed for `id` are the agent's own (ArisShownCard), and for a yes with changes
    /// (`edits`), whether `shown` is the card's own fields with exactly those changes. An unknown id passes here only
    /// without changes: decide() then finds nobody waiting.
    static func shownMatches(_ id: String, allow: Bool, detail: String?, full: String?, edits: [String: String] = [:],
                             shown: String? = nil) -> Bool {
        registry.withLock {
            if let proposal = proposals[id] {
                return ArisShownCard.matches(allow: allow, detail: detail, full: full, expectedDetail: ArisEscalation.describe(proposal.scope),
                                             expectedFull: nil, edits: edits, shown: shown)
            }
            guard let card = cards[id] else { return edits.isEmpty }
            return ArisShownCard.matches(allow: allow, detail: detail, full: full, expectedDetail: card.detail, expectedFull: card.full,
                                         fields: card.fields, edits: edits, shown: shown)
        }
    }

    /// The user's yes or no to a question (its id as the app got it), with what the user changed on the card. False when
    /// nobody is waiting for it.
    static func decide(_ id: String, allow: Bool, edits: [String: String] = [:], unanswered: Bool = false) -> Bool {
        expireParked()
        if let scope = registry.withLock({ takeProposal(id) }) {
            if allow { permissions.grant(scope) }
            writeAudit(auditJSON(["answer": allow ? "yes" : "no", "question": id, "proposal": ArisEscalation.describe(scope)]), key: "gate")
            return true
        }
        guard let runner = registry.withLock({ () -> ArisAgentRunner? in
            approvals.remove(id)
            cards[id] = nil
            return questions.removeValue(forKey: id)
        }) else { return false }
        runner.answered(String(id.dropFirst(runner.key.count + 1)), allow: allow, edits: edits, unanswered: unanswered)
        return true
    }

    // MARK: - Escalation (ArisEscalation)

    /// Kinds of action the user said Aris may do without asking.
    static let permissions = ArisStandingPermissions(file: ArisStandingPermissions.defaultFile)
    /// Background tasks' questions waiting for the user, which expire after a day (guarded by `registry`).
    nonisolated(unsafe) private static var approvals = ArisApprovalQueue()
    /// "앞으로 이건 그냥 할까?" questions waiting for an answer (guarded by `registry`).
    nonisolated(unsafe) private static var proposals: [String: (scope: ArisActionScope, at: Date)] = [:]
    nonisolated(unsafe) private static var proposalCount = 0

    /// Whether `id` (as the app got it) still waits for the user: a parked card that expired never shows.
    static func isWaiting(_ id: String) -> Bool {
        expireParked()
        return registry.withLock {
            if let proposal = proposals[id] { return Date().timeIntervalSince(proposal.at) <= ArisApprovalQueue.lifetime }
            return questions[id] != nil
        }
    }

    /// Called with `registry` held. An expired proposal is gone.
    private static func takeProposal(_ id: String) -> ArisActionScope? {
        guard let proposal = proposals.removeValue(forKey: id) else { return nil }
        return Date().timeIntervalSince(proposal.at) <= ArisApprovalQueue.lifetime ? proposal.scope : nil
    }

    /// Every parked question older than a day is a no (the job carries on without it). Checked by wall clock, also
    /// whenever the app asks: a timer's day doesn't count the hours the Mac slept.
    private static func expireParked() {
        let expired = registry.withLock { () -> [(String, ArisAgentRunner)] in
            proposals = proposals.filter { Date().timeIntervalSince($0.value.at) <= ArisApprovalQueue.lifetime }
            return approvals.expired(now: Date()).compactMap { id in
                cards[id] = nil
                return questions.removeValue(forKey: id).map { (id, $0) }
            }
        }
        for (id, runner) in expired { runner.decide(String(id.dropFirst(runner.key.count + 1)), allow: false, as: "expired", note: ArisRefusalWords.unanswered) }
    }

    static func auditJSON(_ object: [String: String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self)
    }

    nonisolated(unsafe) private static var taskCount = 0

    /// A fresh process for one background task (long work handed to Aris), so the conversation's own process
    /// stays free; it ends with the task.
    /// `job`: the app's id for the job (a UUID), which POST /cancel names. Nil when that job was already cancelled
    /// (its cancel came first): it never starts.
    /// `requested`: the AI the job asked for. It runs there when that AI can run on this Mac, else on the first that
    /// can (ArisJobBrain: no job is locked to one brain).
    /// `untrusted`: the job was written from outside content (a screen turn, outside text, a schedule, a model): it runs
    /// behind its brain's own gate for outside words, in a process of its own (never a warm spare, which has the web).
    /// Codex has its web search off and every command that isn't known safe comes to the gate, which asks the user (the
    /// thread is tainted); an API brain is gated the same way; the open Claude has its turn gate marked from the start;
    /// Antigravity is sealed.
    /// `teammate`: the teammate whose job it is (its id): the log names it, and its rows show its face.
    /// `handsFree`: a hands-free job for Claude: the sealed, hands-free Claude in a process of its own (no spare).
    static func task(brain requested: ArisBrain, model requestedModel: String, title: String, job: String? = nil, untrusted: Bool = false,
                     teammate: ArisTeammate? = nil, handsFree: Bool = false, helper: String? = nil) -> ArisAgentRunner? {
        // The AI asked for when it can run here, else the first that can. When none can, the asked one stays: its
        // first question then answers with what is missing (ArisBrainTrouble).
        let brain = ArisJobBrain.pick(requested, untrusted: untrusted, usable: ArisSealedOneShot.available) ?? requested
        let model = brain == requested ? requestedModel : brain.model(tier: .work)
        return registry.withLock {
            if let job, jobs.isCancelled(job) { return nil }
            let runner: ArisAgentRunner
            if let teammate {
                // A teammate's job: its own process (never a spare: its scopes go into the process), on its brain behind
                // that brain's gates (ArisTeammateJobs).
                let scopes = teammate.scopeSet
                if handsFree, brain == .claude || brain == .antigravity || brain == .api {
                    runner = newTask(brain: brain, model: model, handsFree: true, scopes: scopes)
                } else {
                    let plan = ArisTeammateJobs.plan(brain: brain, untrusted: untrusted, scopes: scopes)
                    runner = newTask(brain: plan.brain, model: model, webSearch: plan.webSearch, sealed: plan.sealed, scopes: scopes)
                }
            } else if handsFree, brain == .claude || brain == .antigravity || brain == .api {
                runner = newTask(brain: brain, model: model, handsFree: true)
            } else if untrusted {
                let plan = ArisJobBrain.untrustedPlan(brain)
                runner = newTask(brain: plan.brain, model: model, webSearch: plan.webSearch, sealed: plan.sealed)
                runner.marksFromStart = ArisJobBrain.marksFromStart(plan.brain, untrusted: true)
            } else {
                // A process started ahead of time (POST /warm) skips the seconds a new one takes to start.
                runner = spares.removeValue(forKey: brain.rawValue + "/" + model) ?? newTask(brain: brain, model: model)
            }
            runner.taskTitle = title
            runner.taskTeammate = teammate
            runner.taskHelper = helper
            runner.taskUntrusted = untrusted
            runners[runner.key] = runner
            if let job { _ = jobs.register(job, owner: runner) }
            return runner
        }
    }

    /// Background tasks by the app's job id, and the jobs cancelled this launch (guarded by `registry`).
    nonisolated(unsafe) private static var jobs = ArisJobBook<ArisAgentRunner>()

    /// The app cancelled job `job` (POST /cancel). Always recorded, so a job whose cancel arrives first is refused when
    /// it asks; a running one is cancelled now.
    static func cancel(job: String) {
        let runner = registry.withLock { jobs.cancel(job) }
        Self.writeAudit(auditJSON(["answer": "cancelled", "question": "job " + job]), key: "app")
        runner?.cancelTask()
    }

    /// One task process per brain and model kept started, ready for the next background task.
    nonisolated(unsafe) private static var spares: [String: ArisAgentRunner] = [:]

    /// Starts a spare task process (the user has started talking, and may hand something over).
    static func warmTask(brain: ArisBrain, model: String) {
        let spare = registry.withLock { () -> ArisAgentRunner in
            let key = brain.rawValue + "/" + model
            if let spare = spares[key] { return spare }
            let spare = newTask(brain: brain, model: model)
            spares[key] = spare
            return spare
        }
        spare.warm()
    }

    /// Called with `registry` held.
    private static func newTask(brain: ArisBrain, model: String, webSearch: Bool = true, handsFree: Bool = false, sealed: Bool = false,
                                scopes: Set<ArisTeammateScope>? = nil) -> ArisAgentRunner {
        taskCount += 1
        let key = ArisLaunch.taskKey(taskCount, brain: ArisImageRouting.runnerName(brain, sealed: handsFree || sealed, handsFree: handsFree), model: model)
        let runner = ArisAgentRunner(key: key, brain: brain, driver: driver(for: brain, model: model, task: true, sealed: sealed, webSearch: webSearch,
                                                                            handsFree: handsFree, scopes: scopes), isTask: true)
        runner.taskScopes = scopes
        return runner
    }

    /// A new conversation (닫기, a long quiet, a past one picked up): every conversation runner drops what its AI
    /// remembers before its next question, so an old topic or an old web page can't leak into the new one.
    static func startNewConversation() {
        registry.withLock { Array(runners.values) }.forEach { $0.forgetConversation() }
    }

    static func stopAll() {
        registry.withLock { Array(runners.values) }.forEach { $0.stop() }
    }

    /// Every conversation process and spare of `brain` ends and is forgotten (its settings changed: an API profile, its
    /// key or models); the next question starts a new one. A background job keeps its own until it ends.
    static func retire(brain: ArisBrain) {
        let gone = registry.withLock { () -> [ArisAgentRunner] in
            let mine = runners.filter { $0.value.brain == brain && !$0.value.isTask }
            for key in mine.keys { runners[key] = nil }
            let spare = spares.filter { $0.value.brain == brain }
            for key in spare.keys { spares[key] = nil }
            return Array(mine.values) + Array(spare.values)
        }
        gone.forEach { $0.stop() }
    }

    /// The connection `owner` closed (POST /ask's stream was dropped): the runner answering it, if any, ends that turn.
    static func abandon(owner: AnyObject) {
        registry.withLock { Array(runners.values) }.forEach { $0.abandon(owner: owner) }
    }

    private static func driver(for brain: ArisBrain, model: String, task: Bool = false, sealed: Bool = false, webSearch: Bool = true,
                               handsFree: Bool = false, scopes: Set<ArisTeammateScope>? = nil) -> ArisBrainDriver {
        switch brain {
        case .claude: return ArisClaudeDriver(model: model, tools: toolsPath, sealed: sealed && !task, task: task, handsFree: handsFree, scopes: scopes)
        case .codex:
            let engine = ArisComputerEngineChoice.current
            let codex = ArisCodexDriver(model: model, tools: toolsPath, instructions: ArisAgentPrompt.system(tools: toolsPath, notion: true, gated: true, task: task, computerEngine: engine),
                                        webSearch: webSearch, task: task)
            codex.computerEngine = engine
            codex.scopes = scopes
            return codex
        case .api:
            // Any provider with a key, or a local model (the active profile, read now: a changed profile retires these
            // runners, retire(brain:)). Gated like Codex; sealed for the screen and hands-free.
            let profile = ArisAPIActive.profile()
            let api = ArisAPIDriver(profile: profile, tools: toolsPath, sealed: sealed && !task, task: task, handsFree: handsFree,
                                    hasKey: { profile.map { ArisAPIActive.key(for: $0) != nil || $0.preset?.needsKey == false } ?? false })
            api.scopes = scopes
            return api
        case .antigravity:
            // Sealed (hands-free, or a conversation that read the user's private data): no tools, Aris runs things for it.
            // A teammate whose scopes aren't all on: sealed too (H1), whatever the caller planned.
            let scoped = scopes.map { !ArisTeammateScope.isAll($0) } ?? false
            let restricted = sealed || handsFree || scoped
            return ArisAntigravityDriver(model: model, instructions: restricted ? ArisAgentPrompt.sealedAgy(tools: toolsPath, handsFree: handsFree, task: task,
                                                                                                         scoped: scoped)
                                                                   : ArisAgentPrompt.system(tools: toolsPath, task: task, relay: true),
                                         tools: toolsPath, sealed: restricted)
        }
    }

    let brain: ArisBrain
    private let key: String
    private let driver: ArisBrainDriver
    private let isTask: Bool
    /// A background task's name, for the file its long answer is saved in.
    private var taskTitle = "Aris"
    private var taskTeammate: ArisTeammate?
    /// A helper's job: the name the app gave it ("도우미 2"), which its log rows go under (N14).
    private var taskHelper: String?
    /// A teammate's job: what it may use (ARIS_TEAMMATE_SCOPES in its process).
    private var taskScopes: Set<ArisTeammateScope>?
    /// The job's prompt came from a model or outside content.
    private var taskUntrusted = false
    /// An untrusted job on the open Claude: its question counts as outside text from the start, whatever the caller
    /// said (ArisJobBrain.marksFromStart).
    private var marksFromStart = false
    /// The brain process whose job file this runner wrote (removed with the process).
    private var jobFilePid: Int32?

    private init(key: String, brain: ArisBrain, driver: ArisBrainDriver, isTask: Bool = false) {
        self.key = key
        self.brain = brain
        self.driver = driver
        self.isTask = isTask
        // A Claude's web results need this turn's judge's yes for exactly that call (read on `queue`, where lines are read).
        (driver as? ArisClaudeDriver)?.webAllowed = { [weak self] call in self?.judgeAllowed(call) == true }
        // Codex's cua_repl and every brain's `aris-tools desktop` share one per-app memory for the conversation.
        (driver as? ArisCodexDriver)?.computerUse = computerUse
    }

    /// Computer use's memory for this conversation (the user's per-app yes, the snapshots Aris took), shared by Codex's
    /// cua_repl and `aris-tools desktop` (ArisDesktopEngine).
    let computerUse = ArisComputerUseLedger(forget: { ArisPeekabooSnapshots.remove($0, record: ArisPeekabooSnapshots.recordFile) })
    /// This turn's desktop calls (ArisDesktopEngine.maxSteps).
    private let desktopSteps = ArisDesktopStepCount()
    /// This turn's desktop actions, each the step it could be saved as (ArisSavedSteps), from POST /desktop-tool.
    let savedSteps = ArisSavedStepsRecorder()

    /// The runner whose brain process carries `credential` (ARIS_MCP_TURN); nil for any other.
    /// `aside`: the caller is /aside-tool, the one route an agy job's credential reaches (ArisAside.credentialServes).
    static func runner(forMCPTurn credential: String, aside: Bool = false) -> ArisAgentRunner? {
        guard ArisMCPTurnCredential.isWellFormed(credential) else { return nil }
        let all = registry.withLock { Array(runners.values) }
        return all.first {
            ArisMCPTurnCredential.same($0.mcpTurn, credential)
                && ArisAside.credentialServes(antigravity: $0.brain == .antigravity, task: $0.isTask, aside: aside)
        }
    }

    /// Outside text has come into this conversation (a brain that can't tell counts as yes). Read on the runner's
    /// queue: inside a listener, where the answer is handed over.
    var isTainted: Bool { driver.isTainted }

    /// This turn ran any tool (a command or another tool), read on the runner's queue (inside a listener).
    var turnUsedTools: Bool { !commands.isEmpty || usedOtherTools }

    /// The taint as of now, read on the runner's queue (inside a listener).
    var currentTaint: ArisTaint { driver.taint }

    /// Whether any conversation runner (every brain, sealed or not) holds outside text in its thread, read from the
    /// agent's queue before a turn: the conversation then dispatches nothing, whichever brain answers now
    /// (ArisOutsideConversation).
    /// Each runner publishes its taint under its own lock as it changes, so this never waits on a runner's queue.
    static func anyOutsideText() -> Bool {
        let conversation = registry.withLock { runners.values.filter { !$0.isTask } }
        return conversation.contains { $0.publishedTaint == .outsideText }
    }

    /// The driver's taint as last published (none once the conversation starts over or the process ends).
    private let taintLock = NSLock()
    private var lastTaint = ArisTaint.none
    var publishedTaint: ArisTaint { taintLock.withLock { lastTaint } }

    /// On the runner's queue, whenever the driver's taint may have changed.
    private func publishTaint(_ taint: ArisTaint? = nil) {
        let now = taint ?? (startsOver ? .none : driver.taint)
        taintLock.withLock { lastTaint = now }
    }

    /// How long one answer may take: a background task gets much longer.
    private var answerLimit: TimeInterval { isTask ? Self.taskTimeout : Self.answerTimeout }

    /// Hears what the AI is doing, pieces of the answer, then the answer or what went wrong (the last call).
    typealias Listener = (ArisAgentReply) -> Void

    private static let answerTimeout: TimeInterval = 120
    private static let taskTimeout: TimeInterval = 900
    /// A question put to the user that isn't answered by then is a no (a background task's waits a day:
    /// ArisApprovalQueue.lifetime).
    /// A conversation's card waits as long as the app shows it, and a little longer (the app owns the deadline and closes
    /// the card first: ArisCardTiming.longestWait), never less (QA BUG-33 reopened).
    private static let questionTimeout: TimeInterval = ArisCardEdit.questionTimeout
    /// An idle AI process stays up this long: starting one (its tools, apps and plugins) takes seconds. An API brain's
    /// process is aris-agent itself and starts at once: it ends sooner (ArisAPIDriver.idleLife).
    private static let idleTimeout: TimeInterval = 1800
    private var idleLimit: TimeInterval { brain == .api ? ArisAPIDriver.idleLife : Self.idleTimeout }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris")
    }

    static var toolsPath: String { ArisAppBundle.toldTools }

    private let queue = DispatchQueue(label: "com.lumenjsn.aris.agent")
    private var process: Process?
    /// The sealed process's own empty folder (ArisSealedScratch), while it runs.
    private var scratch: URL?
    private var input: FileHandle?
    private var output = Data()
    private var pending: Listener?
    /// Called instead of `pending` when the AI is out of quota before it did anything: another AI can take it.
    private var handOff: ((String) -> Void)?
    /// The AI did something this question (ran a command, used a tool): it's not safe to hand to another AI.
    private var acted = false
    private var timeout: DispatchWorkItem?
    private var idle: DispatchWorkItem?
    /// While a video or sound conversion runs: the next "still going" line for the notch.
    private var longJobBeat: DispatchWorkItem?
    /// While one may run: the turn waits at least until then, whatever restarts its timeout (a card's answer included).
    private var longJobDeadline: Date?
    /// What the AI ran for the current question, to learn a shortcut from.
    private var learnKey: String?
    private var commands: [String] = []
    private var usedOtherTools = false
    /// The turn's tool calls and its steps that ended with an error, for a job's report (ArisJobWork).
    private var toolCalls = 0
    private var failedSteps = 0
    /// A tool that is not a shell command was used (a service, Aside, a skill, the desktop, a changed card run): not a
    /// card for a shell command, which `commands` and `cardAnswers` already hold (ArisSendClaim).
    private var nonShellTools = false
    /// A tool other than `aris-tools desktop` ran this turn (a message, a file, a service, any shell command): a reply
    /// claiming success is never rewritten then, whatever the desktop ledger says (security review of BUG-33).
    private var nonDesktopTool = false
    /// This turn already held its answer once for calls under way (ArisSlowCalls.followUp): never twice.
    private var followedUp = false
    /// The turn's request is about Aris's own schedules, to-dos, memory, teammates, timers or settings (ArisOwnData): done
    /// here with Aris's own tool, never handed out; and whether the brain was already asked once more to do it itself.
    private var ownDataTurn = false
    private var askedToDoItHere = false
    /// The request names one of Aris's schedules by its title: nothing of this turn goes to Aside (ArisAsideTool).
    private var ownScheduleNamed = false
    /// A job's start: Aris's own stores and schedule titles then, to check its "삭제했어요" against (ArisOwnDataHonesty).
    private var ownStoresBefore: ArisOwnDataStores?
    private var scheduleNamesBefore: [String] = []
    /// This turn showed a memory card (remember or forget), whatever the user answered: it never teaches memory (QA BUG-6).
    /// Read on the runner's queue (inside a listener).
    private(set) var showedMemoryCard = false
    /// This turn showed the user a card (any action asked about; never a read the judge took): it never teaches memory.
    private(set) var showedCard = false
    /// What was answered on this turn's cards, for what a job may say it did (ArisJobClaim). On `queue`.
    private var cardAnswers = ArisJobClaim.Cards()
    /// The user's own words for the current question, which the escalation gate compares a target against.
    private var request = ""
    /// The question as it came, files note included (ArisMemoryText.filesNote): what `opensAttachment` reads.
    private var attachedRequest = ""
    /// The scope of each question forwarded to the user (by the driver's id), to learn from their answer.
    private var askedScopes: [String: ArisActionScope] = [:]
    /// The turn now was heard hands-free (on `queue`; ArisHandsFree).
    private var handsFreeTurn = false
    /// Set by startNewConversation(): the next question starts the AI on a new thread.
    private var startsOver = false
    /// The running process has been asked something: a new conversation has something to forget. A process just
    /// started (warm()) has nothing, so it's kept.
    private var askedSinceStart = false
    /// The connection the current question came on (abandon(owner:)).
    private var pendingOwner: AnyObject?
    /// The last bytes the process wrote to stderr, logged if it ends unexpectedly (ArisStderrTail), and the lines the
    /// driver read this turn but made nothing of (ArisEventDrift); both only on `queue`.
    private var stderrTail = ArisStderrTail()
    private var drift = ArisEventDrift()
    private var eventsThisTurn = 0
    private var argv: [String] = []
    /// The credential that names this runner's turn to POST /mcp-tool: a new one every turn, and none between turns (M1).
    /// The brain's process carries only where to read it (ARIS_MCP_TURN_FILE: a 0600 file in a 0700 folder of its own).
    private let credentialLock = NSLock()
    private var currentTurnCredential = ""
    var mcpTurn: String { credentialLock.withLock { currentTurnCredential } }
    private lazy var credentialFile: URL? = ArisMCPTurnCredential.makeFile()
    /// The turn carries or follows the screen (its images, or its conversation saw it): careful, its reads judged.
    private var screenTurn = false
    /// This turn's read judgements (on `queue`; a new memo every turn): the same call is judged once.
    private var readMemo: ArisReadMemo?

    /// On `queue`: a fresh credential for a turn starting (or "" when one ends), written where aris-tools reads it.
    private func rotateCredential(active: Bool) {
        let fresh = active ? ArisMCPTurnCredential.make() : ""
        credentialLock.withLock { currentTurnCredential = fresh }
        if let credentialFile { ArisMCPTurnCredential.write(fresh, to: credentialFile) }
    }
    /// The external-service cards this turn has up (ArisMCPCards ids, on `queue`): a no when the turn ends.
    private var mcpCards: Set<String> = []
    /// This turn took in an external service's text (on `queue`).
    private var mcpOutsideThisTurn = false
    /// A hands-free turn that read the user's private data or an external service: its answer is shown, never spoken.
    private var showsOnly: Bool {
        ArisLocalReadPolicy.showsOnly(handsFree: handsFreeTurn, task: isTask, commands: commands, tools: Self.toolsPath)
            || (handsFreeTurn && !isTask && mcpOutsideThisTurn)
    }
    /// The owner's ②A, on `queue`: the editable action behind each card shown (by the card's id) and the note above its
    /// fields, the fresh cards that ask again about a change (their id → the AI's own call they stand for), and what
    /// Aris said once it ran each changed card (spoken at once, then at the head of the answer; the AI's own words
    /// stream no more this turn).
    private var editables: [String: ArisEditableAction] = [:]
    private var editNotes: [String: String] = [:]
    private var reasked: [String: String] = [:]
    private var editedOutcomes: [String] = []
    private var tierNow: ArisTier = .quick
    nonisolated(unsafe) private static var reaskCount = 0

    func forgetConversation() {
        queue.async { [self] in
            startsOver = true
            publishTaint(ArisTaint.none)
        }
    }

    /// `learnAs`: the shortcut key to save the AI's actions under, if they turn out replayable.
    /// `whenUnavailable`: the AI is out of quota (or overloaded) before doing anything; the listener isn't called.
    /// `request`: the user's own words (no context), which the risk gate compares a message against.
    /// `untrusted`: the prompt carries the screen (ArisLook), so sending things out afterwards asks first.
    /// `images`: the turn's checked screen images (ArisTurnImage.parse), for a brain that takes them; in memory only.
    /// `screenSeen`: the conversation has seen the screen (R1 = B): the thread is screenSeen at least.
    /// `owner`: the connection the question came on; when it closes before the answer, abandon(owner:) ends the turn.
    /// `handsFree`: heard in a conversation without a key or the name (ArisHandsFree): no standing permission, remembered
    /// yes or request coverage. `ownData`: the request is about Aris's own data (ArisOwnDataTurn).
    func ask(_ prompt: String, tier: ArisTier = .quick, learnAs: String? = nil, request: String = "", untrusted: Bool = false,
             screenSeen: Bool = false, handsFree: Bool = false, images: [ArisTurnImage] = [], owner: AnyObject? = nil, ownData: Bool = false,
             whenUnavailable: ((String) -> Void)? = nil, listener: @escaping Listener) {
        queue.async { [self] in
            // In the user's language, and the likely reason first: a card waiting for their answer (QA retest).
            let korean = request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } || prompt.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
            guard pending == nil else { return listener(.failure(ArisAgentPrompt.busyLine(korean: korean))) }
            if startsOver {
                startsOver = false
                computerUse.reset()
                // In the same process when the tool can open a new thread; otherwise a new process.
                if process != nil, askedSinceStart {
                    if let lines = driver.newConversation() { write(lines) } else { stopProcess() }
                }
            }
            koreanTurn = ArisBrainFailure.korean(request: request, prompt: prompt)
            // What is missing, in the user's language and typed for the app (ArisBrainTrouble): never "(is it installed?)".
            guard runningInput() != nil else {
                return listener(.failure(notStartedLine()))
            }
            pending = listener
            pendingOwner = owner
            askedSinceStart = true
            handOff = whenUnavailable
            drift.reset()
            eventsThisTurn = 0
            desktopSteps.reset()
            savedSteps.start()
            acted = false
            learnKey = learnAs
            commands = []
            toolCalls = 0
            failedSteps = 0
            usedOtherTools = false
            nonShellTools = false
            nonDesktopTool = false
            followedUp = false
            ownDataTurn = ownData
            askedToDoItHere = false
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let scheduleNames = ownData || isTask ? ArisOwnDataTurn.scheduleNames(home: home) : []
            ownScheduleNamed = ownData && ArisOwnData.namesSchedule(ArisMemoryText.ownWords(request), scheduleNames: scheduleNames)
            if isTask {
                ownStoresBefore = ArisOwnDataStores.live(home: home)
                scheduleNamesBefore = scheduleNames
            }
            showedMemoryCard = false
            showedCard = false
            cardAnswers = ArisJobClaim.Cards()
            idle?.cancel()
            longJobDeadline = nil
            restartTimeout(after: answerLimit)
            // The user's own words for every gate and judge; an attached file's text is outside text (ArisMemoryText.ownWords).
            self.request = ArisMemoryText.ownWords(request)
            // The whole request, with the note of the files the user gave: only for telling that one of them is being opened.
            attachedRequest = request
            computerUse.startTurn()
            askedScopes = [:]
            autoLock.withLock { autoBookNow = ArisAutoBook() }
            autoStops = [:]
            // The turn before's passes take their rows now or never: none is left to mark a row of this turn.
            if !isTask { ArisAutoMarks.shared.turnBegan() }
            mcpOutsideThisTurn = false
            editables = [:]
            editNotes = [:]
            reasked = [:]
            editedOutcomes = []
            tierNow = tier
            driver.setRequest(request)
            driver.setHandsFree(handsFree)
            handsFreeTurn = handsFree
            screenTurn = screenSeen || !images.isEmpty
            readMemo = nil
            rotateCredential(active: true)
            ArisWorkDesk.live.started(self, key: key, brain: brain.rawValue, owner: owner)
            // After ask(), which starts the turn: the screen in the prompt counts as outside text from the start.
            // The user asked for a file: Aris saves the answer as it, so the brain returns the content only (QA BUG-20: it
            // wrote a refusal, which was saved as the .md).
            let prompt = isTask && ArisTaskResult.asksForFile(request) ? prompt + "\n\n" + ArisTaskResult.fileJobRule : prompt
            let question = Question(prompt: prompt, images: images, tier: tier, request: request, untrusted: untrusted, screenSeen: screenSeen)
            asked = question
            askedAgain = false
            put(question)
        }
    }

    /// One turn's question as it went to the brain: kept so a process that died before doing anything can be asked again.
    private struct Question {
        let prompt: String
        let images: [ArisTurnImage]
        let tier: ArisTier
        let request: String
        let untrusted: Bool
        let screenSeen: Bool
    }

    private var asked: Question?
    private var askedAgain = false
    /// This turn's lines for the user are Korean (their words were), else English.
    private var koreanTurn = true

    /// Hands the question to the running process, with the turn's marks.
    private func put(_ question: Question) {
        let opened = question.images.isEmpty ? driver.ask(question.prompt, tier: question.tier)
                                             : driver.ask(question.prompt, images: question.images, tier: question.tier)
        if question.screenSeen { driver.markScreenSeen() }
        if question.untrusted || marksFromStart { driver.markUntrusted() }
        publishTaint()
        write(opened)
    }

    /// The brain's process ended on its own while a question waited (a crash, a flag a new version dropped, a login the
    /// tool refused). Before anything was done it is started again and asked once more; a limit goes to another AI as
    /// any limit does; otherwise the turn ends with the tool's own last words, never a log file's name
    /// (audit imp-brain-died-16).
    private func endedOnItsOwn(stderr: String) {
        guard pending != nil else { return }
        switch ArisBrainFailure.death(stderr: stderr, brain: brain, korean: koreanTurn, acted: acted, isTask: isTask,
                                      events: eventsThisTurn, retried: askedAgain) {
        case .askAgain:
            askedAgain = true
            guard let question = asked, runningInput() != nil else {
                return finish(nil, notStartedLine())
            }
            FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue) ended before doing anything; asking once more\n".utf8))
            driver.setRequest(question.request)
            driver.setHandsFree(handsFreeTurn)
            put(question)
        case .unavailable(let message):
            let handsOff = !acted && !isTask && handOff != nil
            finish(nil, handsOff ? message : ArisBrainFailure.friendly(message, brain: brain, korean: koreanTurn), handingOff: handsOff)
        case .say(let line):
            finish(nil, line)
        }
    }

    /// Starts the AI now (the user has started talking), so the question doesn't wait for it to start up.
    func warm() {
        queue.async { [self] in
            guard runningInput() != nil, pending == nil else { return }
            schedule(&idle, after: idleLimit) { [weak self] in self?.stopProcess() }
        }
    }

    /// The job was cancelled (POST /cancel), or its connection closed and the app is gone: every question it has
    /// waiting is declined as cancelled, and the task and its AI process end. Harmless once it's over.
    func cancelTask() {
        guard isTask else { return }
        let waiting = Self.registry.withLock { () -> [String] in
            let ids = ArisApprovalQueue.owned(by: key, among: Array(Self.questions.keys))
            for id in ids {
                Self.questions[id] = nil
                Self.cards[id] = nil
            }
            _ = Self.approvals.cancel(owner: key)
            return ids
        }
        for id in waiting { decide(String(id.dropFirst(key.count + 1)), allow: false, as: "cancelled") }
        queue.async { [self] in
            finish(nil, "cancelled")
            stopProcess()
            Self.registry.withLock {
                _ = Self.runners.removeValue(forKey: key)
                Self.jobs.forget(owner: self)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            finish(nil, "Stopped.")
            stopProcess()
        }
    }

    /// The connection a question came on closed before its answer: that turn ends and its process stops (it may be
    /// mid-tool), so the next question starts clean. A turn on another connection, or none, is left alone.
    func abandon(owner: AnyObject) {
        queue.async { [self] in
            guard pending != nil, pendingOwner === owner else { return }
            FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue) turn abandoned (the app dropped the stream)\n".utf8))
            finish(nil, "연결이 끊겨서 답을 멈췄어요.")
            stopProcess()
        }
    }

    // MARK: - External services (ArisMCPHub, from POST /mcp-tool; called off `queue`)

    /// This runner's turn as the hub sees it now: whether one is under way, its taint, hands-free, and the brain's pid.
    func mcpSnapshot() -> (active: Bool, taint: ArisTaint, handsFree: Bool, screen: Bool, pid: Int32?) {
        queue.sync { (pending != nil, driver.taint, handsFreeTurn, screenTurn || driver.taint == .screenSeen, process?.processIdentifier) }
    }

    var isBackgroundTask: Bool { isTask }

    /// Whether this runner's turn names one of Aris's own schedules (ArisOwnData.namesSchedule), read off `queue` (the
    /// Aside gate: nothing of such a turn is Aside's).
    var ownScheduleNamedNow: Bool { queue.sync { ownScheduleNamed } }

    /// This runner's turn as the message gate sees it (POST /message-tool, off `queue`): the user's words, the taint (the open
    /// Claude's turn-gate mark counts as outside text too: its hook writes it before a read runs), hands-free, the tier,
    /// a teammate's scopes and the brain's pid.
    func messageSnapshot() -> ArisMessageSnapshot {
        queue.sync {
            let claude = driver as? ArisClaudeDriver
            let marked = claude?.turnMarked == true
            return ArisMessageSnapshot(active: pending != nil, request: request, attached: attachedRequest, taint: marked ? .outsideText : driver.taint,
                                       handsFree: handsFreeTurn, critical: tierNow == .critical, scopes: taskScopes,
                                       pid: process?.processIdentifier, openClaude: claude.map { !$0.sealed && !$0.isolatedFolder } ?? false,
                                       sealedClaude: claude?.sealed == true)
        }
    }

    /// A listing or a result is about to come in: the thread is outside text from now on (before the server is reached).
    func mcpTakeOutsideText() {
        queue.sync {
            driver.markUntrusted()
            publishTaint()
            mcpOutsideThisTurn = true
        }
    }

    /// The user's card for an external-service call (ArisMCPCards); `answer` is called once (a no on a timeout or when the
    /// turn ends). Never a standing permission, a remembered yes or a judge: only the user answers it.
    func mcpAsk(_ card: ArisMCPCard, credential: String, answer: @escaping (ArisMCPAnswer) -> Void) {
        queue.async { [self] in
            // Only the call's own turn: a card from a call whose turn already ended never shows in a later one.
            guard pending != nil, ArisMCPTurnCredential.same(mcpTurn, credential) else {
                Self.writeAudit(Self.auditJSON(["answer": "dropped (the call's turn ended before its card)", "question": "mcp"]), key: "mcp")
                return answer(.no)
            }
            // A background job's card waits ten minutes (aris-tools waits for it), a conversation's a minute.
            let limit = isTask ? Self.mcpTaskWait : Self.questionTimeout
            let shown = ArisMCPCards.shared.put(card, timeout: limit) { [weak self] reply in
                self?.queue.async {
                    guard let self, self.pending != nil else { return }
                    // The user's own no on this card (any service, a file or folder, the desktop): their "알겠어요" line stays.
                    if reply == .no { self.computerUse.noteUsersNo() }
                    self.restartTimeout(after: self.answerLimit + ArisMCPHub.callTimeout)
                }
                answer(reply)
            }
            mcpCards.insert(shown.id)
            usedOtherTools = true
            nonShellTools = true
            // The user was shown a card (a service's, a message's, a handed-off write's): the turn teaches memory nothing.
            showedCard = true
            restartTimeout(after: limit + answerLimit)
            // An API brain's helper waits for it as long (its whole turn had five minutes; a job's card waits ten).
            write(driver.cardWaits(limit + answerLimit))
            pending?(.confirm(shown))
        }
    }

    /// How long a background job's external-service card waits.
    static let mcpTaskWait: TimeInterval = 600

    /// The turn is critical (Jev: sending, deleting, money): every Aside task asks (off `queue`).
    func mcpCritical() -> Bool { queue.sync { tierNow == .critical } }

    /// Aside is about to work or a sign-in code waits (POST /aside-tool, off `queue`): the turn waits as long as that may
    /// take, the notch shows `status` (the brief, or the code), and an API brain's helper waits too.
    func asideRunning(_ status: String) {
        queue.async { [self] in
            guard pending != nil else { return }
            usedOtherTools = true
            nonShellTools = true
            longJobDeadline = Date().addingTimeInterval(ArisAside.runLimit + answerLimit)
            restartTimeout(after: ArisAside.runLimit + answerLimit)
            write(driver.asideStarted())
            pending?(.status(status))
        }
    }

    /// Aside's call ended (M3): the turn's usual time limit again, from now.
    func asideEnded() {
        queue.async { [self] in
            guard pending != nil else { return }
            longJobDeadline = nil
            restartTimeout(after: answerLimit)
        }
    }

    /// The brain read one of the user's skills (POST /skill-tool, off `queue`): the app shows "<title> 스킬 사용 중" on this answer.
    func skillNote(_ title: String) {
        queue.async { [self] in
            guard pending != nil else { return }
            usedOtherTools = true
            nonShellTools = true
            pending?(.skill(title))
        }
    }

    // MARK: - The read judge (ArisReadJudge: reads never show a card)

    /// A read on a careful or screen turn, from the hub or a Claude's hook (off `queue`): the judge on this runner's
    /// brain, with the user's own words for the turn. `showsBlock`: a block shows its quiet line here (the hub shows its own).
    func judgeRead(_ call: ArisReadCall, showsBlock: Bool, done: @escaping (ArisReadVerdict) -> Void) {
        queue.async { [self] in judgeOnQueue(call, showsBlock: showsBlock, done: done) }
    }

    /// On `queue`. `done` is called once, off it. No turn under way is a block.
    private func judgeOnQueue(_ call: ArisReadCall, showsBlock: Bool, done: @escaping (ArisReadVerdict) -> Void) {
        guard pending != nil else { return done(.blocked(.undecided)) }
        let memo = turnMemo()
        restartTimeout(after: ArisReadGate.timeout + 5 + answerLimit)
        let question = key
        memo.judge(call, request: request) { [weak self] verdict in
            // The judge's words go to the audit log only (I5).
            Self.writeAudit(Self.auditJSON(["answer": verdict.allowed ? "read allowed by the judge" : "read refused by the judge (\(verdict.why?.rawValue ?? ""))",
                                            "note": verdict.note, "action": "\(call.tool): \(call.arguments.prefix(300))",
                                            "question": question]), key: question)
            if let why = verdict.why, showsBlock { self?.quietStatus(ArisReadGate.status(why)) }
            done(verdict)
        }
    }

    /// On `queue`: this turn's memo (made on first use), its source from the turn: hands-free, a job, a schedule (a job
    /// with no words from the user) or the user.
    private func turnMemo() -> ArisReadMemo {
        if let readMemo { return readMemo }
        let source = ArisReadSource.of(handsFree: handsFreeTurn, task: isTask, request: request)
        // One second try for a judge that gives no answer, and a job (one long turn) may make more reads (audit gate-11).
        let made = ArisReadMemo(judge: ArisReadJudge.retrying(brain, environment: Self.environment()), source: source,
                                limit: isTask ? ArisReadGate.maxPerJob : ArisReadGate.maxPerTurn)
        readMemo = made
        return made
    }

    /// On `queue` (the drivers' backstop, I3): whether this turn's judge allowed exactly this call.
    private func judgeAllowed(_ call: ArisReadCall) -> Bool { readMemo?.allows(call) == true }

    /// One quiet line in the notch (never a card), while a turn is under way.
    func quietStatus(_ line: String) {
        queue.async { [self] in pending?(.status(said(line))) }
    }

    // MARK: - Computer use (ArisDesktopEngine, from POST /desktop-tool; called off `queue`)

    /// The taint as computer use in `app` sees it (its own window isn't outside text for it).
    func desktopTaint(forApp app: String) -> ArisTaint { queue.sync { driver.taint(forApp: app) } }

    /// The app's window is about to come in: outside text for everything but computer use in that app.
    func desktopMarkRead(_ app: String) {
        queue.sync {
            driver.markAppRead(app)
            publishTaint()
            mcpOutsideThisTurn = true
            usedOtherTools = true
            nonShellTools = true
        }
    }

    /// One more desktop call in this turn; how many so far.
    func desktopStep() -> Int { desktopSteps.next() }

    /// The overlay on the window computer use works in, and its line in the notch.
    func operating(_ target: ArisOperatingTarget) {
        queue.async { [self] in pending?(.operating(target)) }
    }

    // MARK: - Process (on `queue`)

    /// Why the AI was not started, in the turn's language: its program changed and waits for a yes, the tools link
    /// could not be put right, or the usual line (security review 4, H1).
    private func notStartedLine() -> String {
        if ArisProgramApproval.isWaiting(brain) { return ArisProgramApproval.changedLine(brain, korean: koreanTurn) }
        if !ArisToolsLink.ensure() { return koreanTurn ? ArisToolsLink.refusedLine : ArisToolsLink.refusedLineEnglish }
        return ArisBrainFailure.startLine(brain: brain, missing: driver.missing, korean: koreanTurn)
    }

    private func runningInput() -> FileHandle? {
        if let process, process.isRunning, let input { return input }
        // What the brain's own tool needs on disk first: an agy whose rules couldn't be written starts sealed (security
        // review L3), so its command line is asked for after.
        driver.prepare()
        // The path the AI is told for aris-tools must be the link to this app's own program before the AI starts
        // (security review 4, H1): put right when it is not, and no AI is started when that fails.
        guard ArisToolsLink.ensure() else { return nil }
        guard let (executable, arguments) = driver.launch() else { return nil }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        let process = ArisExactProcess()
        process.executableURL = executable
        process.arguments = arguments
        // The sealed Claude works in an empty folder of its own, removed with the process.
        if driver.isolatedFolder {
            if let old = scratch { ArisSealedScratch.remove(old) }
            scratch = nil
            guard let folder = ArisSealedScratch.make() else { return nil }
            scratch = folder
            process.currentDirectoryURL = folder
        } else {
            process.currentDirectoryURL = Self.directory
        }
        process.environment = Self.environment(job: isTask ? ArisWorkDesk.taskLabel(taskTitle) : "대화",
                                               worker: ArisActivityBridge.worker(teammate: taskTeammate?.name, helper: taskHelper, brain: brain.title),
                                               teammate: taskTeammate?.id, foreground: !isTask, task: isTask, brain: brain).merging(driver.environment) { $1 }
            // A teammate's scopes, which aris-tools and the hooks enforce (set last of the limits: nothing else may widen them).
            .merging(taskScopes.map(ArisTeammateScope.environment) ?? [:]) { $1 }
            // agy's conversation never reaches the bus itself (I6): only through Aris's relay.
            // An agy job gets it for exactly one thing, `aris-tools aside` (its aris-tools refuses the rest: ArisSealedTools).
            .merging(brain == .antigravity && !isTask ? [:] : credentialFile.map { [ArisMCPTurnCredential.environmentKey: $0.path] } ?? [:]) { $1 }
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            self?.queue.async { self?.receive(chunk) }
        }
        // Only the tail is kept, and it's written out only when the process ends on its own.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            self?.queue.async { self?.stderrTail.append(chunk) }
        }
        stderrTail = ArisStderrTail()
        argv = [executable.path] + arguments
        process.terminationHandler = { [weak self] ended in
            self?.queue.async {
                guard let self, self.process === ended else { return }
                // Not stopped by the agent: a crash, a flag the new version dropped, a login the tool refused. The log
                // gets the command and the tool's last words, so the cause is readable; the notch gets one line.
                self.logUnexpectedEnd(status: ended.terminationStatus)
                let lastWords = self.stderrTail.text
                self.clearProcess()
                self.endedOnItsOwn(stderr: lastWords)
            }
        }
        driver.reset()
        computerUse.reset()
        publishTaint(ArisTaint.none)
        do {
            try ArisChildren.run(process)
        } catch {
            FileHandle.standardError.write(Data("aris-agent: couldn't start \(brain.rawValue): \(error.localizedDescription)\n".utf8))
            if let scratch { ArisSealedScratch.remove(scratch) }
            scratch = nil
            return nil
        }
        self.process = process
        // A teammate's job: its scopes also go into a job file for this very process, before it gets anything to do;
        // aris-tools finds it through its parent chain, whatever the brain does to its environment (re-review 2).
        if let scopes = taskScopes {
            let pid = process.processIdentifier
            guard let started = ArisTeammateJobFile.startTime(of: pid),
                  ArisTeammateJobFile.write(pid: pid, started: started, scopes: scopes, teammate: taskTeammate?.id, home: Self.home) else {
                FileHandle.standardError.write(Data("aris-agent: couldn't write a teammate's job file; not running it\n".utf8))
                stopProcess()
                return nil
            }
            jobFilePid = pid
        }
        askedSinceStart = false
        self.input = stdin.fileHandleForWriting
        output = Data()
        write(driver.opening())
        return input
    }

    private func write(_ lines: [Data]) {
        guard let input else { return }
        do {
            for line in lines { try input.write(contentsOf: line) }
        } catch {
            FileHandle.standardError.write(Data("aris-agent: couldn't write to \(brain.rawValue): \(error.localizedDescription)\n".utf8))
            // A process that has just ended (a flag it doesn't know, an expired login) closes its pipe a moment before
            // its end is heard: then its end says why and what happens next (endedOnItsOwn), not this write.
            let patience = Date().addingTimeInterval(0.3)
            while process?.isRunning == true, Date() < patience { usleep(10_000) }
            guard process?.isRunning == true else { return }
            finish(nil, ArisBrainFailure.unreachableLine(brain: brain, korean: koreanTurn))
            stopProcess()
        }
    }

    private func receive(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        output.append(chunk)
        while let newline = output.firstIndex(of: UInt8(ascii: "\n")) {
            let line = String(decoding: output[output.startIndex..<newline], as: UTF8.self)
            output.removeSubrange(output.startIndex...newline)
            ArisWorkDesk.live.sawLine(line, from: self)
            let events = driver.read(line)
            publishTaint()
            if events.isEmpty, pending != nil, let note = drift.note(line, quiet: driver.quietKinds) {
                FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue): \(note)\n".utf8))
            }
            eventsThisTurn += events.count
            // Anything new from the brain: a long job's "still going" lines stop (a new one starts below if it is one).
            if !events.isEmpty { longJobBeat?.cancel() }
            for event in events {
                ArisWorkDesk.live.saw(event, taint: driver.taint, from: self)
                switch event {
                case .send(let data): write([data])
                case .audit(let line):
                    acted = true
                    Self.writeAudit(line, key: key)
                case .status(let text): pending?(.status(said(text)))
                case .stepFailed(let label):
                    failedSteps += 1
                    // A step failed: no mark waits for a row that may never come (ArisAutoMarks; a conversation's only).
                    if !isTask { ArisAutoMarks.shared.dropWaiting() }
                    pending?(.stepFailed(label))
                case .delta(let text):
                    // Hands-free, after a read of the user's messages, mail or notes: nothing more is streamed to be spoken.
                    // After the user's changed card ran (②A): its outcome was spoken; the AI's own words aren't.
                    // While a call of its own still waits on the user's card, nothing the brain says is passed on: a claim of
                    // success can't be shown or spoken before the outcome (security review).
                    // A main turn about Aris's own data: its answer goes whole, once it is known not to hand the work out.
                    if editedOutcomes.isEmpty, !(ownDataTurn && !isTask),
                       !showsOnly, ArisSlowCalls.shared.pending(owner: mcpTurn).isEmpty {
                        pending?(.delta(text))
                    }
                case .confirm(let ask):
                    // An action that was asked about is never learned as a shortcut.
                    usedOtherTools = true
                    if driver.escalation(for: ask.id).map({ ArisMemoryLearning.isMemoryWrite($0.action, tools: Self.toolsPath) }) == true
                        || ask.memoryWrite { showedMemoryCard = true }
                    if driver.escalation(for: ask.id)?.read == nil { showedCard = true }
                    escalate(ask)
                case .tools(let calls):
                    toolCalls += calls.count
                    for call in calls {
                        if call.name == "Bash", let command = call.command { commands.append(command) } else { usedOtherTools = true; nonShellTools = true }
                        if !(call.name == "Bash" && call.command.map { ArisDesktopHonesty.isDesktopCommand($0, tools: Self.toolsPath) } == true) { nonDesktopTool = true }
                    }
                    if calls.contains(where: { $0.command.map { ArisConvertWords.isLong(command: $0, tools: Self.toolsPath) } ?? false }) { waitForLongJob() }
                case .result(let written):
                    // The brain answered while a call of its own still waits on the user's card (or a slow step): the turn
                    // doesn't end on it. The card stays up to its limit, and the brain gets the call's result in the same
                    // turn, once (QA retest: the turn ended 2 s into `desktop wait`, tearing the card down as a "no").
                    if !followedUp, !ArisSlowCalls.shared.pending(owner: mcpTurn).isEmpty {
                        followedUp = true
                        let owner = mcpTurn
                        // A job's card waits ten minutes (mcpTaskWait), a conversation's two.
                        let cardLimit = isTask ? Self.mcpTaskWait : ArisCardEdit.questionTimeout
                        restartTimeout(after: cardLimit + answerLimit)
                        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                            // The card's own limit, then time for the work the user's yes lets run (a type, a batch).
                            let results = ArisSlowCalls.shared.finishAll(owner: owner, deadline: Date().addingTimeInterval(cardLimit + ArisSlowCalls.workAfterAnswer))
                            self?.queue.async { [weak self] in
                                guard let self, self.pending != nil, ArisMCPTurnCredential.same(self.mcpTurn, owner) else { return }
                                Self.writeAudit(Self.auditJSON(["answer": "held the turn for \(results.count) call(s) under way", "question": "slow calls"]), key: "desktop")
                                self.restartTimeout(after: self.answerLimit)
                                // The results carry what the apps showed: outside text from here on (security review).
                                self.driver.markUntrusted()
                                self.publishTaint()
                                self.write(self.driver.ask(ArisSlowCalls.followUp(results), tier: self.tierNow))
                            }
                        }
                        break
                    }
                    // Aris's own data answered with a jobs block: the brain is asked once more to do it itself, here, with
                    // Aris's own tool (QA BUG-60); the turn goes on.
                    if ArisOwnDataTurn.asksAgain(ownData: ownDataTurn, task: isTask, asked: askedToDoItHere, answer: written, acted: self.acted,
                                                 showedCard: showedCard, commands: commands.count) {
                        askedToDoItHere = true
                        Self.writeAudit(Self.auditJSON(["answer": "asked again (Aris's own data is never handed out)", "question": "jobs block"]), key: key)
                        restartTimeout(after: answerLimit)
                        write(driver.ask(ArisOwnDataTurn.doItHere(tools: Self.toolsPath), tier: tierNow))
                        break
                    }
                    // Notes it left (ArisNoteFence) are kept with where they came from, and never shown or said.
                    let noted = ArisNoteFence.reading(written, teammate: taskTeammate != nil)
                    // A note the teammate said it would keep but that broke the rules: the answer says it wasn't kept.
                    let raw = noted.dropped > 0 && !handsFreeTurn ? noted.text + "\n\n" + ArisNoteFence.droppedLine(noted.dropped, korean: koreanTurn) : noted.text
                    if noted.dropped > 0 {
                        Self.writeAudit(Self.auditJSON(["action": "notes not kept (broke the note rules): \(noted.dropped)", "question": taskTeammate?.name ?? "Aris"]),
                                        key: "notes")
                    }
                    // A job that says it did what the request asked while what the helper knows first-hand says it did
                    // not (ArisJobClaim) ends as failed with a line that is true, and what it wanted remembered is not kept.
                    if isTask, let line = ArisJobClaim.unbacked(ArisAgentStream.spoken(raw), request: request,
                                                                 record: ArisJobClaim.Record(acted: acted, commands: commands, otherTools: usedOtherTools, showedCard: showedCard, cards: cardAnswers),
                                                                 schedulesUnchanged: ownStoresBefore.map { $0.schedules == ArisOwnDataStores.live(home: FileManager.default.homeDirectoryForCurrentUser.path).schedules },
                                                                 tools: Self.toolsPath, korean: request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }) {
                        Self.writeAudit(Self.auditJSON(["answer": "a job's claim was not passed on: what the helper knows first-hand says it was not done", "question": key]), key: key)
                        finish(nil, line)
                        break
                    }
                    // A look whose window could not be confirmed as the app's teaches nothing (ArisLookTrust): the garden
                    // memo was learned as "the front window" while Safari was (second upgrade run, bug 1).
                    let lookUnconfirmed = !ArisLookTrust.keepsNotes(prompt: asked?.prompt)
                    if lookUnconfirmed, !noted.notes.isEmpty {
                        Self.writeAudit(Self.auditJSON(["action": "notes not kept (the look could not be confirmed): \(noted.notes.count)", "question": taskTeammate?.name ?? "Aris"]),
                                        key: "notes")
                    }
                    if !noted.notes.isEmpty, !handsFreeTurn, !lookUnconfirmed {
                        ArisNotesStore.keepFound(noted.notes, by: taskTeammate?.name ?? "Aris", teammate: taskTeammate?.id,
                                                 tainted: driver.taint != .none || taskUntrusted, isApp: ArisTeamExtrasRoute.isAppHere)
                        Self.writeAudit(Self.auditJSON(["action": "notes kept: \(noted.notes.count)", "question": taskTeammate?.name ?? "Aris",
                                                        "risk": driver.taint != .none || taskUntrusted ? "learned (outside text: waits for the user)" : "learned"]),
                                        key: "notes")
                    }
                    var answer = ArisAgentStream.spoken(raw)
                    // A key that had never answered has now: the API brain counts as ready from here (ArisAPIActive).
                    if brain == .api { ArisAPIActive.noteAnswered() }
                    if isTask {
                        let delivered = deliver(raw)
                        if let file = delivered.file { pending?(.file(file.path)) }
                        answer = delivered.answer
                        // "I sent it" after its send card got a no: the answer stays, and what happened is added.
                        if let truth = ArisJobClaim.refusedNote(answer, record: ArisJobClaim.Record(commands: commands, cards: cardAnswers), tools: Self.toolsPath,
                                                               korean: request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }) {
                            answer += "\n" + truth
                        }
                    }
                    if let key = learnKey, !ArisShortcuts.isQuestion(key), ArisShortcuts.learnable(commands: commands, usedOtherTools: usedOtherTools,
                                                                   reply: answer, tools: Self.toolsPath, tainted: driver.isTainted) {
                        ArisShortcutStore.shared.learn(commands, reply: answer, as: key)
                    }
                    // A conversation's weather, timer, to-do or music command earns its card (the app reads the values).
                    // A read that found Full Disk Access or Screen Recording off earns the permission card (its button
                    // opens that list in System Settings).
                    // "I sent it" in a conversation's answer when nothing could have been sent: the answer stays, and
                    // Aris's own line says it was not sent (ArisSendClaim).
                    if !isTask, let line = ArisSendClaim.note(answer, request: request, record: ArisSendClaim.Record(commands: commands, otherTools: nonShellTools, cards: cardAnswers),
                                                             tools: Self.toolsPath, korean: request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }) {
                        Self.writeAudit(Self.auditJSON(["answer": "an answer said it sent something no send went out for: Aris's line added", "question": key]), key: key)
                        answer += "\n\n" + line
                    }
                    if !isTask { answer = ArisWidgetPick.attach(to: answer, commands: commands, tools: Self.toolsPath, access: commands.isEmpty ? ArisWidgetPick.Access() : .now) }
                    if showsOnly {
                        pending?(.shownOnly)
                    }
                    // Where it really typed, never where the brain says it did (QA BUG-47 reopened).
                    let acted = computerUse.windowsThisTurn
                    let koreanRequest = request.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
                    answer = ArisWindowHonesty.checked(answer, done: acted.done, titles: acted.titles, korean: koreanRequest)
                    // A claim of success with none of the turn's desktop actions done: the true line (QA BUG-33 reopened).
                    let actions = computerUse.actionsThisTurn
                    // A conversation turn done with desktop actions only, all of them saveable and done: its steps are
                    // saved under the user's words, replayed next time with no AI (ArisSavedSteps). Never a job's, never a
                    // hands-free or screen turn's (learnKey is nil for those), never with an answer that says it failed.
                    if let recipe = ArisSavedSteps.turnRecipe(key: isTask ? nil : learnKey, request: request, notes: savedSteps.all, notDone: actions.notDone,
                                                              otherTools: nonDesktopTool, reply: answer, outside: mcpOutsideThisTurn || driver.isTainted), let key = learnKey {
                        ArisSavedStepsLive.store.save(recipe)
                        Self.writeAudit(Self.auditJSON(["answer": "saved \(recipe.steps.count) desktop step(s) for this request", "question": key]), key: key)
                    }
                    if !nonDesktopTool {
                        answer = ArisDesktopHonesty.checked(answer, done: actions.done, notDone: actions.notDone, korean: koreanRequest)
                        answer = ArisDesktopHonesty.declineWorded(answer, done: actions.done, notDone: actions.notDone,
                                                                  declined: computerUse.latestNoIsUsers ? 1 : 0, korean: koreanRequest)
                    }
                    // Aris's own data is never handed out: a jobs block still there is taken out and Aris says so; and a job's
                    // claim to have changed it stands only when Aris's own store shows the change (QA BUG-60).
                    if ownDataTurn, !isTask, answer != ArisOwnDataTurn.kept(answer, ownData: true, task: false, korean: koreanRequest) {
                        Self.writeAudit(Self.auditJSON(["answer": "jobs block taken out (Aris's own data)", "question": "jobs block"]), key: key)
                        answer = ArisOwnDataTurn.kept(answer, ownData: true, task: false, korean: koreanRequest)
                    }
                    if isTask, let before = ownStoresBefore {
                        let checked = ArisOwnDataHonesty.checked(answer, request: request, scheduleNames: scheduleNamesBefore, before: before,
                                                                 after: ArisOwnDataStores.live(home: FileManager.default.homeDirectoryForCurrentUser.path),
                                                                 korean: koreanRequest)
                        if checked != answer { Self.writeAudit(Self.auditJSON(["answer": "a job's claim about Aris's own data was checked against the store", "question": key]), key: key) }
                        answer = checked
                    }
                    // A job says what it did before its answer: the app never ticks green a job that did nothing, or whose
                    // step failed (seventh VM pass: ArisJobVerdict).
                    if isTask {
                        let desk = computerUse.actionsThisTurn
                        pending?(.work(ArisJobWork(tools: toolCalls, failed: failedSteps + desk.notDone,
                                                   acted: desk.done || (toolCalls > 0 && failedSteps < toolCalls && desk.notDone == 0))))
                    }
                    // What the agent did for the user's changed card comes first; the AI's answer (a task's result, a card) stays.
                    finish(ArisEditableAction.answer(answer, outcomes: editedOutcomes), nil)
                case .failure(let message):
                    // Nobody is waiting (a warmed process) and its conversation never opened: this process can't take
                    // a question any more. It is stopped, so the next question starts a new one and hears the same
                    // error at once, instead of waiting two minutes on a thread that never comes (audit warm-error-hang-10).
                    if stopsUnopened(message) { return }
                    finish(nil, ArisEditableAction.answer(koreanTurn ? message : ArisBrainFailure.english(message, brain: brain), outcomes: editedOutcomes))
                case .unavailable(let message):
                    if stopsUnopened(message) { return }
                    // Another AI takes the question only before anything was done, and never for a task: otherwise the
                    // notch gets the Korean line, not the tool's English.
                    let handsOff = !acted && !isTask && handOff != nil
                    finish(nil, handsOff ? message : ArisBrainFailure.friendly(message, brain: brain, korean: koreanTurn), handingOff: handsOff)
                case .abort(let message):
                    Self.writeAudit(Self.auditJSON(["answer": "stopped (the sealed process broke its rules)", "question": key]), key: key)
                    // In the request's language (the API brain's stop lines were Korean only: vm4 bug 4).
                    finish(nil, said(message))
                    stopProcess()
                    return
                }
            }
        }
    }

    /// An error from a process nobody is asking, whose conversation never opened: logged and the process stopped.
    private func stopsUnopened(_ message: String) -> Bool {
        guard ArisBrainFailure.stopsIdleProcess(waiting: pending != nil, ready: driver.isReady) else { return false }
        FileHandle.standardError.write(Data("aris-agent: \(brain.rawValue) failed before any question (\(message.prefix(200))); it starts afresh next time\n".utf8))
        stopProcess()
        return true
    }

    // MARK: - Escalation (on `queue`)

    /// ArisRiskPolicy said to ask. The hard lines decide first; after outside text the user always decides; otherwise a
    /// standing permission, then for a background task main Aris's judgement, may let it through; anything else goes
    /// to the user as before. Only the action the
    /// driver judged counts, never the card's words; an action the driver can't name goes to the user.
    private func escalate(_ ask: ArisConfirmation) {
        guard let pendingAction = driver.escalation(for: ask.id) else { return forward(ask, scope: nil) }
        // A read on a careful turn (the owner, 2026-11-06): the read judge, never a card.
        if let read = pendingAction.read {
            return judgeOnQueue(read, showsBlock: true) { [weak self] verdict in
                self?.queue.async { [weak self] in
                    guard let self, self.pending != nil, self.driver.escalation(for: ask.id) != nil else { return }
                    self.restartTimeout(after: self.answerLimit)
                    self.write(verdict.allowed ? self.driver.approveOnce(ask.id) : self.driver.refuseRead(ask.id, note: ArisReadGate.refusal(verdict.why ?? .other)))
                }
            }
        }
        let scope = ArisRiskPolicy.scope(of: pendingAction.action, tools: Self.toolsPath, arguments: pendingAction.arguments)
        let hardLine = ArisRiskPolicy.hardLine(of: pendingAction.action, tools: Self.toolsPath, connector: pendingAction.connector,
                                               arguments: pendingAction.arguments)
        // Only a typed, parsed action (one aris-tools subcommand, a fully scoped MCP call) may go ahead without the user.
        let approvable = ArisEscalation.autoApprovable(pendingAction.action, tools: Self.toolsPath, arguments: pendingAction.arguments)
        // A computer-use step that changes something, or cua_repl's code: main Aris judges it in the user's place.
        if let step = pendingAction.judged, hardLine == nil {
            return judge(step, ask: ask, scope: scope, tainted: pendingAction.judgeTainted || handsFreeTurn)
        }
        let standing = Set(Self.permissions.all)
        // R1 = B: after the screen, a grant, the judge, learning and a plain card only for an action the user's words cover.
        // Hands-free: no standing permission, no learning, no proposal (ArisHandsFree).
        let tainted = driver.taint.blocks(covered: pendingAction.covered) || handsFreeTurn
        let verdict = { (judgement: ArisJudgement?) in
            ArisEscalation.decide(scope: scope, approvable: approvable, hardLine: hardLine, tainted: tainted, standing: standing,
                                  judgement: judgement, showsMail: ArisMailCard.shows(pendingAction.action, arguments: pendingAction.arguments))
        }
        let early = verdict(nil)
        // Never learned after outside text: a yes then counts toward no streak and no proposal.
        let learnable = ArisEscalation.learnable(scope, approvable: approvable, hardLine: hardLine, tainted: tainted)
        // After outside text the card says why it asks again, and is a question, never a countdown.
        let escalated = ArisEscalation.card(for: ask, approvable: approvable, hardLine: hardLine, tainted: tainted)
        // A card that is there only because outside content was read says so too (the conversion after the brain's own
        // `files find`, as the trash card after it): one rule, where every brain's card passes (ArisGateReason).
        let raised = ArisGateReason.raised(outside: driver.taint.blocks(covered: pendingAction.covered), hardLine: hardLine != nil,
                                           cleanRisk: ArisRiskPolicy.risk(of: pendingAction.action, tools: Self.toolsPath,
                                                                          home: FileManager.default.homeDirectoryForCurrentUser.path, request: request),
                                           asksAfter: ArisRiskPolicy.asksAfterOutsideText(pendingAction.action, tools: Self.toolsPath))
        let ask = ArisGateReason.card(for: escalated, raised: raised)
        // Auto mode: a card that is there only because outside content was read goes to the automatic check first.
        if autoSettles(ask, action: pendingAction, hardLine: hardLine) { return }
        // In a conversation the user is right there: nobody judges for them, and their own dictated message keeps its countdown.
        if !isTask, ask.countdown, hardLine == nil { return forward(ask, scope: learnable) }
        // Main Aris is asked only when its yes could change the answer.
        guard isTask, case .askUser = early, case .proceed = verdict(.proceed) else {
            return apply(early, to: ask, scope: scope, learnable: learnable, reason: "")
        }
        restartTimeout(after: ArisJudge.timeout + answerLimit)
        // After outside text, the judge reads only the code-made kind, app and target, never the call's free text.
        let judged = ArisEscalation.judgeAction(title: ask.title, detail: ask.full ?? ask.detail, scope: scope, tainted: tainted)
        ArisJudge.judge(action: judged, request: request, environment: Self.environment()) { [weak self] judgement, reason in
            self?.queue.async { [weak self] in
                // The turn ended (or the question was answered) while main Aris was thinking.
                guard let self, self.pending != nil, self.driver.escalation(for: ask.id) != nil else { return }
                self.apply(verdict(judgement), to: ask, scope: scope, learnable: learnable, reason: reason)
            }
        }
    }

    /// The owner's ruling ("auto mode"): main Aris's yes lets one computer-use step through, never learned or remembered; after
    /// outside text, for a step it may not judge, or on a no, an odd answer or a timeout, the card goes to the user.
    private func judge(_ step: ArisJudgedStep, ask: ArisConfirmation, scope: ArisActionScope, tainted: Bool) {
        let verdict = { (judgement: ArisJudgement?) in ArisEscalation.computerUseVerdict(step, tainted: tainted, judgement: judgement) }
        // Anything main Aris may not judge (a message is always the user's) is their card, as it came.
        guard case .proceed = verdict(.proceed) else { return forward(ask, scope: nil) }
        // Long code is judged in parts; every part must say yes in time.
        let parts = ArisEscalation.judgeChunks(step, request: request)
        let budget = ArisEscalation.judgeBudget(parts: parts.count)
        restartTimeout(after: budget + answerLimit)
        ArisChunkJudge.run(parts: parts, request: request, environment: Self.environment(), budget: budget) { [weak self] judgement, reason in
            self?.queue.async { [weak self] in
                guard let self, self.pending != nil, self.driver.escalation(for: ask.id) != nil else { return }
                self.apply(verdict(judgement), to: ask, scope: scope, learnable: nil, reason: reason)
            }
        }
    }

    // MARK: - Auto mode (ArisAutoMode)

    /// This turn's checks: a new book every turn (a Claude's handed-off calls read it off `queue`).
    private let autoLock = NSLock()
    private var autoBookNow = ArisAutoBook()
    var autoBook: ArisAutoBook { autoLock.withLock { autoBookNow } }
    /// The stopped cards up, on `queue`: each one's id and today's card for the call it stands for.
    private var autoStops: [String: ArisConfirmation] = [:]
    /// Who checks for this runner's brain (its quick model); nil when no AI can.
    var autoChecker: ArisAutoChecking? { ArisAutoCheckLive.checker(brain, environment: Self.environment()) }

    /// The notch's running tag while a check takes longer than a moment (from any queue), for the turn it began in.
    func autoChecking(turn: String) {
        queue.async { [self] in
            guard ArisMCPTurnCredential.same(mcpTurn, turn) else { return }
            pending?(.status(ArisAutoCard.checking(english: englishRequest)))
        }
    }

    /// The automatic check for Codex's and the API brain's card (the Claudes' is ArisAutoHandOff, the same rule): only
    /// for a card that is there because outside content was read and for nothing else (ArisAutoScope.eligible). A match
    /// approves this one call, once, as the escalation gate's own yes does (never remembered, the taint as it was);
    /// anything else stops it or leaves today's card. False: the card isn't the check's, and goes on as before.
    private func autoSettles(_ ask: ArisConfirmation, action pendingAction: ArisPendingAction, hardLine: ArisHardLine?) -> Bool {
        guard let argv = ArisAutoScope.eligible(pendingAction.action, tools: Self.toolsPath, home: FileManager.default.homeDirectoryForCurrentUser.path,
                                                request: request, critical: tierNow == .critical, blocked: driver.taint.blocks(covered: pendingAction.covered),
                                                hardLine: hardLine != nil, task: isTask, handsFree: handsFreeTurn, countdown: ask.countdown) else { return false }
        // The call as the checker can be shown it whole; nil (a kind it never checks, or anything that would be cut,
        // dropped or altered) keeps today's card.
        let subject = ArisAutoAction.read(argv, title: ask.title, detail: ArisAutoCard.plain(ask.detail))
        let owner = ArisOwnerWords.shared.said(endingWith: request)
        let checker = autoChecker, book = autoBook, key = key
        let note = { (verdict: String, seconds: TimeInterval?) in
            guard let subject else { return }
            Self.writeAudit(Self.auditJSON(ArisAutoMode.ledger(subject, verdict: verdict, model: checker?.model ?? "", seconds: seconds)), key: key)
        }
        // On `queue`.
        let finish = { [self] (outcome: ArisAutoOutcome) in
            switch outcome {
            case .stop(let why):
                // Nothing decided (late, failed, odd, too few words): today's card at once, with the line why (review 9, L1).
                if let line = ArisAutoCard.todaysLine(why, english: englishRequest) { return forward(ArisAutoCard.reasoned(ask, line), scope: nil) }
                let id = Self.registry.withLock { () -> String in
                    Self.reaskCount += 1
                    return "s\(Self.reaskCount)-\(ArisLaunch.nonce)"
                }
                autoStops[id] = ask
                forward(ArisAutoCard.stopped(for: ask, id: id, why: why, english: englishRequest), scope: nil)
            case .run:
                // Its row earns the mark unless the step then fails (receive: a failed step drops the waiting marks).
                ArisAutoMarks.shared.passed(argv)
                // The write's grant (minted by the driver's approval) tells the app it is outside text (review 9, M2).
                ArisActionGrants.shared.passedByCheck(argv: argv)
                restartTimeout(after: answerLimit)
                write(driver.approveOnce(ask.id))
            }
        }
        switch ArisAutoMode.before(argv: argv, action: subject, ownerTurns: owner, available: checker != nil, book: book, english: englishRequest) {
        case .asIs: return false
        case .ask(let reason): forward(ArisAutoCard.reasoned(ask, reason), scope: nil)
        case .stop(let why, let ledger):
            note(ledger, nil)
            finish(.stop(why))
        case .check(let ticket):
            guard let checker, let subject, let owner else { return false }
            let began = Date(), turn = mcpTurn
            restartTimeout(after: checker.budget + answerLimit)
            let input = ArisAutoCheck.input(ownerTurns: owner, action: subject, code: ArisAutoCheck.code())
            ArisAutoAsk.ask(checker, input: input, showTag: { [weak self] in self?.autoChecking(turn: turn) }) { [weak self] run in
                self?.queue.async { [weak self] in
                    // The turn ended (another may have begun), or the call is gone, while it was checked: nothing runs.
                    guard let self, self.pending != nil, ArisMCPTurnCredential.same(self.mcpTurn, turn),
                          let now = self.driver.escalation(for: ask.id) else { return }
                    // The verdict counts only for the call as it stands now, word for word, and once (ArisAutoBook).
                    let settled = ArisAutoMode.after(run, ticket: ticket, argvNow: ArisAutoScope.argv(of: now.action, tools: Self.toolsPath), book: book)
                    note(settled.ledger, Date().timeIntervalSince(began))
                    finish(settled.outcome)
                }
            }
        }
        return true
    }

    private func apply(_ verdict: ArisEscalationVerdict, to ask: ArisConfirmation, scope: ArisActionScope, learnable: ArisActionScope?,
                       reason: String) {
        let question = key + "/" + ask.id
        switch verdict {
        case .askUser:
            forward(ask, scope: learnable)
        case .proceed(let why):
            let because = reason.isEmpty ? why : "\(why): \(reason)"
            Self.writeAudit(Self.auditJSON(["answer": "auto-approved (\(because))", "question": question,
                                            "scope": ArisEscalation.describe(scope)]), key: key)
            restartTimeout(after: answerLimit)
            // This one call only: never a session, never remembered as the user's yes.
            write(driver.approveOnce(ask.id))
            // What main Aris allowed on its own judgement shows on the notch, as the audit line keeps it.
            if why.hasPrefix(ArisEscalation.judgedNote) { pending?(.status(said(ArisEscalation.judgedNote))) }
        case .refuse(let why):
            Self.writeAudit(Self.auditJSON(["answer": "refused (\(why))", "question": question, "scope": ArisEscalation.describe(scope)]), key: key)
            restartTimeout(after: answerLimit)
            // Aris's own refusal, never the user's no: the brain is told which rule, and the turn's other cards still come up
            // (audit gate-5, gate-6).
            write(driver.refuseRead(ask.id, note: ArisRefusalWords.hardLine(why == ArisEscalation.moneyReason ? .money : why == ArisEscalation.mailReason ? .mailSend : nil)))
            pending?(.status(said(why)))
        }
    }

    /// The confirm card goes to the app. A background task's question parks until the user is at the Mac, for a day at
    /// most; a conversation's is a no after a minute, as before. `scope`: what the user's answer counts toward.
    /// The request is in English (ArisGateWords' one switch): cards, refusal reasons and the read-block line are too.
    private var englishRequest: Bool { ArisGateWords.isEnglish(ArisMemoryText.ownWords(request)) }

    /// One of the gate's own fixed lines as this turn says it; any other line as it is.
    private func said(_ line: String) -> String { englishRequest ? ArisGateWords.line(line) : line }

    private func forward(_ ask: ArisConfirmation, scope: ArisActionScope?) {
        let id = key + "/" + ask.id
        if let scope { askedScopes[ask.id] = scope }
        // The owner's ②A: the fields of an action the agent's code knows how to change (never a countdown or a proposal).
        let editable = editables[ask.id] ?? (ask.countdown || ask.proposal ? nil
            : driver.escalation(for: ask.id).flatMap { ArisEditableAction.parse($0.action, tools: Self.toolsPath) })
        editables[ask.id] = editable
        let fields = editable?.fields ?? []
        // The user may be typing in it: an editable card waits longer (the app stops a little before, ArisCardEdit).
        let limit = isTask ? ArisApprovalQueue.lifetime : fields.isEmpty ? Self.questionTimeout : ArisCardEdit.questionTimeout
        // The AI's own call: its card's details become the fields' text (a fresh card's already are).
        var detail = ask.detail
        if let editable, reasked[ask.id] == nil, case .shell(let command)? = driver.escalation(for: ask.id)?.action {
            detail = ArisEditableAction.detail(ask.detail, described: ArisCodexDriver.describe(command: command, tools: Self.toolsPath,
                                                                                               request: ArisMemoryText.ownWords(request)).1,
                                               fields: editable.fields)
            editNotes[ask.id] = ArisCardEdit.note(ArisConfirmation(id: ask.id, title: ask.title, detail: detail, fields: fields))
        }
        // A request in English: the title, the lines the card opens with and the countdown's spoken line in English
        // (audit gate-24). An editable card's fields keep their own text (the app shows and sends back exactly that); a
        // countdown's title and details are the recipient and the message, never changed.
        var title = ask.title, full = ask.full, spoken = ask.spoken
        if englishRequest {
            if ask.countdown {
                spoken = ArisRiskPolicy.announcement(to: ask.title, text: ask.detail, english: true)
            } else {
                title = ArisGateWords.title(title)
                let own = fields.isEmpty ? "" : ArisCardEdit.shown(fields, ArisCardEdit.values(fields))
                if fields.isEmpty {
                    detail = ArisGateWords.detail(detail)
                    full = full.map(ArisGateWords.detail)
                } else if detail.hasSuffix(own) {
                    detail = ArisGateWords.detail(String(detail.dropLast(own.count))) + own
                }
            }
        }
        Self.registry.withLock {
            Self.questions[id] = self
            if Self.cards.count >= 1_000 { Self.cards = Self.cards.filter { Self.questions[$0.key] != nil } }
            Self.cards[id] = (detail, full, fields)
            if isTask { Self.approvals.park(id: id, at: Date()) }
        }
        restartTimeout(after: limit + answerLimit)
        if isTask {
            queue.asyncAfter(wallDeadline: .now() + limit + 1) { Self.expireParked() }
        } else {
            queue.asyncAfter(deadline: .now() + limit) { [weak self] in
                guard Self.registry.withLock({ () -> ArisAgentRunner? in
                    Self.cards[id] = nil
                    return Self.questions.removeValue(forKey: id)
                }) != nil else { return }
                // Nobody answered: not the user's no, so the turn's later cards are still asked (audit gate-6).
                self?.decide(ask.id, allow: false, as: "unanswered", note: ArisRefusalWords.unanswered)
            }
        }
        var shown = ArisConfirmation(id: id, title: title, detail: detail, countdown: ask.countdown, spoken: spoken, full: full, fields: fields)
        shown.stopped = ask.stopped
        pending?(.confirm(shown))
    }

    /// The user answered (POST /confirm): the AI is told, and three yeses in a row for one scope bring the question
    /// "앞으로 이건 그냥 할까?" (asked once; a yes makes it a standing permission).
    private func answered(_ id: String, allow: Bool, edits: [String: String] = [:], unanswered: Bool = false) {
        queue.async { [self] in
            // The user's own no on a card of this turn: the reply keeps their "알겠어요" line, unless something else fails after it
            // (ArisDesktopHonesty.declineWorded).
            if !allow, !unanswered { computerUse.noteUsersNo() }
            // A card the app closed unanswered is no answer of the user's: the brain is told so, and later cards still ask.
            let note = !allow && unanswered ? ArisRefusalWords.unanswered : nil
            guard !settlesEdit(id, allow: allow, edits: edits, note: note) else { return }
            decide(id, allow: allow, as: note == nil ? nil : "unanswered", note: note)
            guard let scope = askedScopes.removeValue(forKey: id), Self.permissions.recordApproval(scope, allowed: allow), pending != nil else { return }
            let proposal = Self.registry.withLock { () -> String in
                Self.proposalCount += 1
                let proposal = ArisLaunch.proposalId(Self.proposalCount)
                Self.proposals[proposal] = (scope, Date())
                return proposal
            }
            pending?(.confirm(ArisConfirmation(id: proposal, title: englishRequest ? ArisGateWords.title(ArisEscalation.proposalTitle) : ArisEscalation.proposalTitle,
                                               detail: ArisEscalation.describe(scope),
                                               proposal: true)))
        }
    }

    /// A background task's answer: the line to say; the rest, when long or when the user asked for a file (their own words,
    /// `request`), is saved as a Markdown file, which the app shows in its reader (POST /result) when the answer arrives.
    private func deliver(_ raw: String) -> (answer: String, file: URL?) {
        ArisTaskResult.deliver(raw, request: request, title: taskTitle, tainted: driver.taint != .none, folders: Self.resultFolders)
    }

    /// Where task results are saved; only files right in these are ever read for the app (POST /result).
    static var resultFolders: [URL] {
        [documentsResults, directory.appendingPathComponent("results")]
    }

    /// ~/Documents/Aris: the only folder 파일로 열기 opens from (POST /open).
    static var documentsResults: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Aris")
    }

    /// The reader's 파일로 열기: a saved result in the .md's default app. False for anything but a .md right in
    /// ~/Documents/Aris (ArisResultPath: no "..", no link out).
    static func openResult(_ path: String) -> Bool {
        guard let file = ArisResultPath.resolve(path, in: [documentsResults]) else { return false }
        open(file)
        return true
    }

    /// A saved result's words and when it was saved, for the app's reader; nil for anything but a result.
    static func readResult(_ path: String) -> (text: String, modified: Date)? {
        guard let file = ArisResultPath.resolve(path, in: resultFolders),
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: ArisResultPath.readLimit) else { return nil }
        let modified = (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date ?? Date()
        return (String(decoding: data, as: UTF8.self), modified)
    }

    /// The reader's 메모에 저장: the result as an Apple Notes note, through aris-tools note --markdown (its HTML and
    /// AppleScript escaping, its `- [ ]` items as real checklists). Nil when it worked, else what to show.
    static func noteResult(_ path: String) -> String? {
        guard let result = readResult(path) else { return "그 결과를 찾지 못했어요." }
        guard !ArisResultPath.noteText(result.text).isEmpty else { return "메모에 넣을 내용이 없어요." }
        let added = ArisLook.tool(toolsPath, ["note", "--markdown", ArisResultPath.noteMarkdown(result.text)], environment(foreground: true), timeout: 30)
        return added == nil ? "메모에 넣지 못했어요." : nil
    }

    /// "방금 답 메모에 저장해 줘", after the user's yes: the answer as a new note, as the reader's 메모에 저장 does.
    static func noteText(_ text: String) -> String? {
        guard !ArisResultPath.noteText(text).isEmpty else { return "메모에 넣을 내용이 없어요." }
        let added = ArisLook.tool(toolsPath, ["note", "--markdown", ArisResultPath.noteMarkdown(text)], environment(foreground: true), timeout: 30)
        return added == nil ? "메모에 넣지 못했어요." : nil
    }

    private static func open(_ file: URL) {
        let process = ArisExactProcess()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [file.path]
        try? ArisChildren.run(process)
    }

    /// Every action an AI asked for, how the risk gate judged it, and the user's answers: a private
    /// record in ~/.config/aris/aris/actions.log, to check what Aris did.
    /// Writers come from every runner's queue and the server's: one lock keeps lines whole, the rotation single, and
    /// the refusal throttle consistent (ArisAuditWriter: fields capped, refusals counted, copies pruned by age only).
    private static let auditLock = NSLock()
    nonisolated(unsafe) private static var auditWriter = ArisAuditWriter(directory: directory)

    static func writeAudit(_ line: String, key: String) {
        ArisWhyDesk.shared.audited(line, key: key)
        ArisWorkDesk.live.audited(line, key: key)
        auditLock.withLock { auditWriter.write(line, caller: key, at: Date()) }
    }

    /// At exit: every count still held is written, so nothing the throttle counted is lost with the process.
    static func flushAudit() {
        auditLock.withLock { auditWriter.flush(at: Date()) }
    }

    /// `answer`: what actions.log calls it (yes or no from the user, or "expired"). `note`: the decline isn't the user's own no
    /// (nobody answered, or Aris refused it): the brain is told this instead of a plain no, and the turn's other cards
    /// still come up (only his own no closes them: audit gate-6).
    private func decide(_ id: String, allow: Bool, as answer: String? = nil, note: String? = nil) {
        // The stopped card's answer (ArisAutoMode; a conversation's only, on `queue`): 하지 않기, or no answer, declines the
        // call it stands for as any no does; 그래도 하기 runs nothing: today's card for that call goes up next.
        if !isTask, let held = autoStops.removeValue(forKey: id) {
            Self.writeAudit(Self.auditJSON(["answer": allow ? "stopped card: asked for the confirm card" : "stopped card: \(answer ?? "no")",
                                            "question": key + "/" + held.id]), key: key)
            return allow ? forward(held, scope: nil) : decide(held.id, allow: false, as: answer, note: note)
        }
        Self.writeAudit(Self.auditJSON(["answer": answer ?? (allow ? "yes" : "no"), "question": id]), key: key)
        queue.async { [self] in
            // A fresh card that asked again about a change stands for the AI's own call (a no or a timeout declines it).
            let call = reasked.removeValue(forKey: id) ?? id
            if let asked = driver.escalation(for: call)?.action { cardAnswers.note(asked, allowed: allow && call == id) }
            editables[id] = nil
            editNotes[id] = nil
            guard pending != nil else { return }
            restartTimeout(after: answerLimit)
            if let note, !allow {
                write(driver.refuseRead(call, note: note))
            } else {
                write(driver.decide(call, allow: allow && call == id))
            }
        }
    }

    // MARK: - the owner's ②A: a changed card (on `queue`)

    /// An answer to a card the user changed, or to the fresh card that asks again about such a change: the change is checked
    /// again and judged by the risk gate, then refused, asked again, or run by the agent itself; the AI's own call is
    /// declined in every case but a fresh ask. False: an ordinary answer.
    private func settlesEdit(_ id: String, allow: Bool, edits: [String: String], note: String? = nil) -> Bool {
        guard let base = editables[id], reasked[id] != nil || (allow && !edits.isEmpty) else { return false }
        editables[id] = nil
        let note = editNotes.removeValue(forKey: id)
        let call = reasked.removeValue(forKey: id) ?? id
        // A changed yes never counts toward a standing permission.
        askedScopes[call] = nil
        let question = key + "/" + id
        guard allow else { decide(call, allow: false, as: note == nil ? nil : "unanswered", note: note); return true }
        guard let edited = base.applying(edits) else {
            return refuseEdit(call, question: question, why: "고친 내용을 그대로 쓸 수 없어서 하지 않았어요.")
        }
        // Money and mail are never what a changed message, reminder or event becomes; any other hard line the change
        // newly crosses is asked about on a fresh card instead of refused.
        let line = ArisRiskPolicy.hardLine(of: .shell(edited.command), tools: Self.toolsPath)
        let crossed = line != nil && line != ArisRiskPolicy.hardLine(of: .shell(base.command), tools: Self.toolsPath)
        switch ArisEditableAction.verdict(base: base, edited: edited, risk: assess(edited), baseRisk: assess(base),
                                          hardLine: line == .money || line == .mailSend, asksUser: crossed) {
        case .refuse(let why):
            return refuseEdit(call, question: question, why: why)
        case .reask(let why):
            let fresh = Self.registry.withLock { () -> String in
                Self.reaskCount += 1
                return "e\(Self.reaskCount)-\(ArisLaunch.nonce)"
            }
            reasked[fresh] = call
            editables[fresh] = edited
            // Why the first card asked (outside text came in) still holds: it stays under the new reason.
            if let note { editNotes[fresh] = note }
            Self.writeAudit(Self.auditJSON(["answer": "asked again (\(why))", "question": question]), key: key)
            let above = [why, note].compactMap { $0 }.joined(separator: "\n")
            forward(ArisConfirmation(id: fresh, title: edited.kind.title, detail: above + "\n" + ArisCardEdit.shown(edited.fields, ArisCardEdit.values(edited.fields))),
                    scope: nil)
        case .run:
            run(edited, for: call, question: question)
        }
        return true
    }

    /// Runs the user's changed card off the runner's queue (aris-tools may take seconds); then, if the turn is still on,
    /// declines the AI's call as done for the user, tells it so, speaks the outcome and keeps it for the answer.
    private func run(_ edited: ArisEditableAction, for call: String, question: String) {
        acted = true
        usedOtherTools = true
        nonShellTools = true
        cardAnswers.approvedOther = true
        restartTimeout(after: Self.editRunLimit + answerLimit)
        let environment = Self.environment(job: isTask ? ArisWorkDesk.taskLabel(taskTitle) : "대화", worker: taskTeammate?.name ?? brain.title, teammate: taskTeammate?.id,
                                           foreground: !isTask, task: isTask).merging(taskScopes.map(ArisTeammateScope.environment) ?? [:]) { $1 }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The user's changed card is a yes to exactly these words: aris-tools may send its message, once.
            ArisMessagePass.mint(argv: edited.arguments)
            ArisActionGrants.shared.mint(argv: edited.arguments)
            let result = ArisActivityBridge.run(tools: Self.toolsPath, arguments: edited.arguments, environment: environment, timeout: Self.editRunLimit)
            self?.queue.async { [weak self] in
                guard let self else { return }
                Self.writeAudit(Self.auditJSON(["answer": "yes, changed on the card: the agent ran it", "question": question,
                                                "action": ArisCodexDriver.what(.shell(edited.command)),
                                                "status": result.map { String($0.status) } ?? "stopped at the time limit"]), key: self.key)
                let outcome = edited.outcome(status: result?.status, error: result?.err ?? "", english: self.englishRequest)
                guard self.pending != nil else { return }
                self.restartTimeout(after: self.answerLimit)
                self.write(self.driver.declineEdited(call, arguments: edited.arguments, note: ArisEditableAction.steer(outcome: outcome)))
                self.editedOutcomes.append(outcome)
                self.pending?(.delta(outcome + "\n\n"))
            }
        }
    }

    /// How long a changed card's aris-tools may take.
    private static let editRunLimit: TimeInterval = 30

    private func refuseEdit(_ call: String, question: String, why: String) -> Bool {
        Self.writeAudit(Self.auditJSON(["answer": "refused (\(why))", "question": question]), key: key)
        decide(call, allow: false, as: "refused", note: ArisRefusalWords.changedCard)
        pending?(.status(said(why)))
        return true
    }

    /// The gate's rating of a changed card's command, as this turn would rate the AI's (critical, the user's words, hands-free).
    private func assess(_ edit: ArisEditableAction) -> ArisRisk {
        let action = ArisAction.shell(edit.command)
        let risk = ArisRiskPolicy.risk(of: action, tools: Self.toolsPath, home: FileManager.default.homeDirectoryForCurrentUser.path,
                                       critical: tierNow == .critical, request: request)
        return handsFreeTurn ? ArisHandsFree.risk(risk, of: action, tools: Self.toolsPath) : risk
    }

    /// A video or sound conversion may take minutes (aris-tools stops it at ArisConvertWords.mediaLimit): the turn waits
    /// that long, and every half minute the notch hears it is still going, so its stream never goes quiet. On `queue`.
    private func waitForLongJob() {
        // Its card may come first (the API brain's): that wait, the job's own limit, then the answer.
        longJobDeadline = Date().addingTimeInterval(Self.questionTimeout + ArisConvertWords.mediaLimit + answerLimit)
        restartTimeout(after: ArisConvertWords.mediaLimit + answerLimit)
        beatLongJob(started: Date())
    }

    private func beatLongJob(started: Date) {
        schedule(&longJobBeat, after: 30) { [weak self] in
            guard let self, self.pending != nil, Date().timeIntervalSince(started) < ArisConvertWords.mediaLimit + 30 else { return }
            // A card of this turn still waits: nothing runs yet, so nothing is said to be going (ArisAgentStatus.beatsLongJob).
            let cardWaiting = Self.registry.withLock { Self.questions.values.contains { $0 === self } }
            if ArisAgentStatus.beatsLongJob(cardWaiting: cardWaiting) {
                self.pending?(.status(ArisAgentStatus.longJob(minutes: Int(Date().timeIntervalSince(started) / 60))))
            }
            self.beatLongJob(started: started)
        }
    }

    private func restartTimeout(after seconds: TimeInterval) {
        schedule(&timeout, after: max(seconds, longJobDeadline?.timeIntervalSinceNow ?? 0)) { [weak self] in
            guard let self else { return }
            self.finish(nil, ArisBrainFailure.slowLine(brain: self.brain, korean: self.koreanTurn))
            self.stopProcess()
        }
    }

    /// `handingOff`: the question goes to another AI (whenUnavailable) instead of ending here.
    private func finish(_ answer: String?, _ error: String?, handingOff: Bool = false) {
        timeout?.cancel()
        longJobBeat?.cancel()
        longJobDeadline = nil
        // An external-service card still up when the turn ends is a no, and the turn's credential stops working.
        ArisMCPCards.shared.cancel(mcpCards)
        mcpCards = []
        // The turn's slow calls end with it: their results are no longer collected (ArisSlowCalls).
        let ended = mcpTurn
        if !ended.isEmpty { ArisSlowCalls.shared.endTurn(owner: ended) }
        // The turn's hold on the keys and pointer ends with it (ArisDesktopLock): the next turn or job in line goes.
        if !ended.isEmpty { ArisDesktopLock.shared.release(ArisDesktopRoutes.owner(credential: ended)) }
        rotateCredential(active: false)
        Self.registry.withLock {
            let mine = Self.questions.filter { $0.value === self }.keys
            for id in mine { Self.cards[id] = nil }
            Self.questions = Self.questions.filter { $0.value !== self }
        }
        let handOff = self.handOff
        self.handOff = nil
        pendingOwner = nil
        ArisWorkDesk.live.finished(self, answered: answer != nil, error: error, handingOff: handingOff && handOff != nil && error != nil, taint: driver.taint)
        if let summary = ArisEventDrift.summary(count: drift.count, events: eventsThisTurn, brain: brain.rawValue) {
            FileHandle.standardError.write(Data("aris-agent: \(summary)\n".utf8))
        }
        guard let listener = pending else { return }
        pending = nil
        if handingOff, let handOff, let error {
            handOff(error)
        } else {
            listener(answer.map(ArisAgentReply.answer) ?? .failure(error ?? ArisBrainFailure.silentLine(brain: brain, korean: koreanTurn)))
        }
        guard !isTask else {
            // A task's process ends with it.
            stopProcess()
            Self.registry.withLock {
                _ = Self.runners.removeValue(forKey: key)
                Self.jobs.forget(owner: self)
            }
            return
        }
        schedule(&idle, after: idleLimit) { [weak self] in self?.stopProcess() }
    }

    /// agent.log: the exit status, the command as run, and the tail of what the tool wrote to stderr. Written only for
    /// an end the agent didn't ask for.
    private func logUnexpectedEnd(status: Int32) {
        let tail = stderrTail.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var line = "aris-agent: \(brain.rawValue) ended on its own (status \(status))\n  argv: \(ArisLoggedArguments.line(argv))\n"
        if !tail.isEmpty { line += "  stderr: \(tail.replacingOccurrences(of: "\n", with: "\n          "))\n" }
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func stopProcess() {
        let running = process
        clearProcess()
        if let running { ArisProcessEnd.end(running) }
    }

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private func clearProcess() {
        if let pid = jobFilePid { ArisTeammateJobFile.remove(pid: pid, home: Self.home) }
        jobFilePid = nil
        // The thread ends with its process: nothing it read carries over, and computer use's looks, the user's yeses for
        // apps and Peekaboo's snapshot folders go with it (stop, retire, an idle end, a crash: I12).
        computerUse.reset()
        publishTaint(ArisTaint.none)
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        (process?.standardError as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        try? input?.close()
        process = nil
        input = nil
        output = Data()
        if let scratch { ArisSealedScratch.remove(scratch) }
        scratch = nil
    }

    private func schedule(_ slot: inout DispatchWorkItem?, after seconds: TimeInterval, _ work: @escaping () -> Void) {
        slot?.cancel()
        let item = DispatchWorkItem(block: work)
        slot = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// launchd starts the agent with a bare environment; the AI tools and what they run need the usual one.
    /// `job`, `worker` and `teammate` are what aris-tools writes into the activity log (ARIS_JOB, ARIS_WORKER,
    /// ARIS_TEAMMATE); an inherited value is never passed on. `foreground` (ARIS_FOREGROUND): a turn the user is in front of
    /// (the conversation, his own 메모에 저장), the only kind that may bring Notes forward for its checklists.
    /// `task`: a background job's process (ARIS_TASK): aris-tools then picks no files by itself (no --finder or --shelf).
    /// `brain`: the AI this process is (ARIS_BRAIN): a schedule made in it asks for that AI first.
    static func environment(job: String = "Aris", worker: String = "Aris", teammate: String? = nil, foreground: Bool = false,
                            task: Bool = false, brain: ArisBrain? = nil) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment[ArisSchedule.brainKey] = brain?.rawValue
        environment["ARIS_FOREGROUND"] = foreground ? "1" : nil
        environment[ArisConvertWords.taskKey] = task ? "1" : nil
        environment["ARIS_JOB"] = ArisActivityBridge.label(job, fallback: "Aris")
        environment["ARIS_WORKER"] = ArisActivityBridge.label(worker, fallback: "Aris")
        environment["ARIS_TEAMMATE"] = nil
        environment.merge(ArisActivityBridge.teammateEnvironment(teammate)) { $1 }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // The same folders first, as always; then the agent's own PATH; then what only the user's shell has (node under
        // nvm, a bun or volta folder), so a CLI that is a node script finds its node (ArisPrograms).
        environment["PATH"] = ArisPrograms.childPath(first: ArisPrograms.knownFolders(home: home) + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"],
                                                     inherited: environment["PATH"])
        environment["HOME"] = home
        // claude (and the others) find their login in the keychain under the account name.
        environment["USER"] = NSUserName()
        environment["LOGNAME"] = NSUserName()
        return environment
    }
}
