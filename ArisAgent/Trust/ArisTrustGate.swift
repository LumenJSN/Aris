//
//  ArisTrustGate.swift
//  aris-agent
//
//  Where the Core 2 session loop (jv-mind) and the capability registry (jv-hands) meet the trust policy, when
//  `arisCore2` is on. Per session (a conversation or a task) it keeps the provenance tracker and the asks; the loop
//  feeds it the owner's words, each tool result and each tool call, and gets back the policy's decision, the cards to
//  show (one per intent, in the confirm line's format, so the app's card UI works unchanged), and what an answer lets
//  run. The owner's own words can make or take back a standing grant ("앞으로 엄마한테 보내는 건 묻지 마"). Every call
//  ends as one line of the record (ArisRecord). Nothing here runs with the switch off: the old gates stay as they are.
//

import Foundation

enum ArisTrustSwitch {
    /// The app's Core 2 switch as the helper heard it (ArisHelperSwitches; the same key as ArisCore2.switchKey); off by
    /// default. Settings › 할 수 있는 일 › 컴퓨터 제어 › 실험 기능 turns it on: no `defaults write` reaches the helper.
    static let key = ArisExperimentSwitch.core2.rawValue
    nonisolated(unsafe) static var isOn: () -> Bool = { ArisCore2.isOn() }
}

final class ArisTrustGate: @unchecked Sendable {
    struct Outcome: Equatable {
        let decision: ArisDecision
        let verdict: ArisProvenanceVerdict
        let facts: ArisCallFacts
        let effect: ArisEffectClass
        /// A model's typing whose decision read its field's selection as empty: its run is bound to that (ArisApps.TypeOver
        /// `empty`), so whatever is selected by the time it types stops it. Nil for every other call.
        var typingMark: String? = nil
    }

    static let keptSessions = 64

    private let lock = NSLock()
    private let home: String
    private let now: () -> Date
    private var trackers: [String: ArisProvenanceTracker] = [:]
    private var order: [String] = []
    private var asks = ArisAskPlan()
    private var waiting: [String: (session: String, task: String?, outcomes: [String: Outcome])] = [:]
    private var shownCards: [String: ArisAskCard] = [:]
    private var waiters: [String: ([String], [String]) -> Void] = [:]
    /// The calls a replay words itself on their cards (ArisAskDescription), by session and call id.
    private var described: [String: [String: ArisAskDescription]] = [:]
    var world: (String) -> ArisWorldFacts
    /// The address of a browser's front page, by the app's name (decision 2; the live reader is installed at start).
    var pageAddress: (String) -> String? = { _ in nil }
    /// The element a call acts on in an app (its label as the app shows it, and whether it is a password field); the
    /// target nil: the focused one.
    var element: (_ app: String, _ target: String?) -> (label: String?, secure: Bool) = { _, _ in (nil, false) }
    /// What this turn's reads of an app printed, by conversation (ArisMindClickReads): the app layer runs in the brain's
    /// own process, so an id a call names ("e188") means something only through them (eleventh VM run, items 1 and 6).
    var readElements: (_ session: String, _ app: String) -> [ArisApps.Grounding.Seen]? = { _, _ in nil }
    /// A conversation's Select All per app, until the typing that follows it (ArisSelectAllWatch).
    private var selectAll = ArisSelectAllWatch()
    /// An app as the app layer resolves what a call called it (its bundle id), so two names of one app are one; nil when
    /// it can't be resolved (then its folded name). ArisMindLive installs the app layer's resolver.
    var appKey: (_ app: String) -> String? = { _ in nil }
    /// The calls noted as a Select All when they were decided (their results then add nothing).
    private var selectAllCalls: Set<String> = []

    init(home: String, now: @escaping () -> Date = Date.init, world: @escaping (String) -> ArisWorldFacts = { _ in ArisWorldFacts() }) {
        self.home = home
        self.now = now
        self.world = world
    }

    nonisolated(unsafe) static var shared = ArisTrustGate(home: FileManager.default.homeDirectoryForCurrentUser.path)

    var settings: ArisTrustSettings { ArisTrustSettings.load(home: home, now: now()) }

    // MARK: - Feeding

    /// The owner's words of a turn. A sentence that makes or takes back a standing grant changes the settings (and the
    /// change is returned, for Aris to say so). `speaker`: who said them (F1); words whose voice was not the owner's
    /// never make or take back a grant.
    @discardableResult
    func ownerTurn(session: String, text: String, speaker: ArisTurnSpeaker = .notChecked) -> ArisGrantChange? {
        lock.withLock {
            tracker(session) { $0.ownerTurn(text, speaker: speaker) }
            selectAll.newTurn(session: session)
        }
        guard speaker.countsAsOwner else { return nil }
        let facts = world(session)
        guard let change = ArisGrantLearning.learn(text, world: facts, home: home, now: now()) else { return nil }
        let next = settings.applying(change, home: home)
        guard (try? next.save(home: home)) != nil else { return nil }
        ArisRecord.audit(Self.line(["trust": "learned", "change": Self.describe(change)]))
        return change
    }

    func taskInstruction(session: String, text: String) {
        lock.withLock { tracker(session) { $0.taskInstruction(text) } }
    }

    /// A background job's request (twelfth VM run, B3): never the owner's words (it may have come from a model or from
    /// what was read), so it gives no call any provenance; it only makes the job's turn one about paying for the payment
    /// boundary (only stricter), and says in which language a hand-off's words go out.
    func jobRequest(session: String, text: String) {
        // The rule every job's words end with is Aris's own, not the request (it names paying in every job).
        let request = [true, false].reduce(text) { $0.replacingOccurrences(of: ArisPaymentBoundary.stopClause(english: $1), with: " ") }
        lock.withLock { jobWords[session] = String(request.prefix(4_000)) }
    }
    private var jobWords: [String: String] = [:]

    /// How many content results the session's tracker has taken in so far (ArisProvenanceTracker.read).
    func contentRead(session: String) -> Int {
        lock.withLock { trackers[session]?.read ?? 0 }
    }

    /// `framed`: the text is a route's output in Aris's own outside-text frame (ArisMindResult.framed).
    func toolResult(session: String, call: String?, text: String, source: ArisContentSource?, sender: String? = nil, framed: Bool = false) {
        lock.withLock { tracker(session) { $0.toolResult(text, source: source, sender: sender, call: call, framed: framed) } }
    }

    /// What `from` read (each content with its source) is `to`'s too: a replay a model started in a conversation that
    /// read outside text decides its steps with that text in view (ArisMindTaught). How many were carried.
    @discardableResult
    func carryContent(from: String, to: String) -> Int {
        lock.withLock {
            let read = trackers[from]?.contents ?? []
            guard !read.isEmpty else { return 0 }
            tracker(to) { tracker in for content in read { tracker.toolResult(content.text, source: content.source, sender: content.sender) } }
            return read.count
        }
    }

    /// What every conversation of the owner's has read, as `to`'s content too: a run by its name starts with no model
    /// and in no conversation, yet its steps are decided with everything Aris read in view (eleventh VM run, item 4).
    /// Never from another replay's session.
    @discardableResult
    func carryConversations(to: String) -> Int {
        lock.withLock {
            let read = order.filter { $0 != to && !$0.hasPrefix("teach-") }.flatMap { trackers[$0]?.contents ?? [] }
            guard !read.isEmpty else { return 0 }
            tracker(to) { tracker in for content in read { tracker.toolResult(content.text, source: content.source, sender: content.sender) } }
            return read.count
        }
    }

    /// A taught procedure's replay (F3): its own calls on the tracker's replay-scoped channel (each valid once, for that
    /// exact call), and `endApproval` when the run is over.
    func approve(session: String, steps: [ArisApprovedStep]) {
        lock.withLock { tracker(session) { $0.approve(steps) } }
    }

    func endApproval(session: String, run: String) {
        lock.withLock { tracker(session) { $0.endApproval(run: run) } }
    }

    /// What the policy would decide for a step of Aris's own toward the owner's request, read only: nothing is learned,
    /// remembered or recorded (a taught run's one card marks its steps by it: ArisTeachRunPass.Mark). The run's own
    /// decision, step by step, is `decide`, as ever.
    func preview(capability: String, effect: ArisEffectClass, arguments: [String: Any], payment: Bool) -> ArisDecision {
        let facts = ArisCallFacts(capability: capability, arguments: ArisKeyArguments.extract(arguments, capability: capability), registeredPayment: payment)
        return ArisTrustPolicy.decide(facts, effect: effect, provenance: .ownStep, context: settings.context(home: home, now: now()))
    }

    /// A step of a taught run ran on the owner's yes to the run's one card (ArisTeachRunPass): its answer in the record.
    func passed(call: String) {
        answers.withLock { $0[call] = Self.runCardAnswer }
    }
    static let runCardAnswer = "yes (the run's card)"

    /// A taught procedure's replay (F3) words its own calls on their cards, each from the step it was made from
    /// (fifth VM run, D2). Presentation only: what is decided, asked and read back about each call is unchanged.
    func describe(session: String, calls: [String: ArisAskDescription]) {
        lock.withLock { described[session] = calls.isEmpty ? nil : calls }
    }

    /// The model's own words: never evidence (dropped by the tracker).
    func modelText(session: String, text: String) {
        lock.withLock { tracker(session) { $0.modelText(text) } }
    }

    // MARK: - Deciding

    /// One call: its key arguments (from JSON arguments or aris-tools words), its provenance, the policy's decision. A
    /// refusal is recorded here (nothing will run). A read that goes out to a service (ArisOutboundReads), once
    /// something private was read, is decided as outward unless what it sends is the owner's own words verbatim
    /// (ArisWebCarry), and its outcome says so.
    func decide(session: String, task: String? = nil, call: String, capability: String, effect: ArisEffectClass,
                arguments: [String: Any], argv: [String]? = nil, stdin: String? = nil, payment: Bool = false) -> Outcome {
        var keys = argv.map { ArisKeyArguments.extract(argv: $0, stdin: stdin) } ?? ArisKeyArguments.extract(arguments, capability: capability)
        let cwd = (arguments["cwd"] as? String)
        let worldNow = world(session)
        let outbound = ArisOutboundReads.sends(capability: capability, arguments: arguments, argv: argv)
        let (verdict, said, decided): (ArisProvenanceVerdict, String, ArisEffectClass) = lock.withLock {
            var tracker = self.tracker(session)
            tracker.world = worldNow
            // A read that goes out to a service, once something private was read: a look only when what it sends is the
            // owner's own words verbatim (ArisWebCarry); else a send, decided by the table as one.
            var rated = effect
            var why: [String] = []
            if effect == .observe, let outbound, tracker.readPrivate, tracker.unaccounted(outbound) != nil {
                rated = .outward
                why = ["something private was read in this conversation, and what it sends isn't the owner's own words verbatim"]
                for query in outbound.queries where !query.isEmpty { keys.append(ArisKeyArgument(kind: .body, value: String(query.prefix(20_000)))) }
            }
            let verdict = tracker.toolCall(id: call, capability: capability, effect: rated, arguments: keys, publicWeb: outbound?.publicWeb == true,
                                           outboundRead: !why.isEmpty)
            trackers[session] = tracker
            return (why.isEmpty ? verdict : Self.adding(why, to: verdict), tracker.turnText, rated)
        }
        // `payment`: the registry marks the call as one (decision 1: it asks on its own card). An act on a browser's
        // page (decision 2): its host and element, read now.
        var facts = ArisCallFacts(capability: capability, arguments: keys, cwd: cwd, registeredPayment: payment,
                                  browser: browserPage(session: session, capability: capability, effect: decided, arguments: arguments, said: said))
        // Rated a send by the outbound rule: its card shows all it sends, whole.
        if decided != effect, let outbound { facts.sends = outbound.shown }
        // A replace of a field's whole text: what it would erase, read now for its card (presentation only).
        let typedApp = arguments["app"] as? String ?? "", typedTarget = arguments["target"] as? String
        // A field named by a read's id: what that read printed for it, so it is found again in a look taken now.
        let typedSeen = typedTarget.flatMap { target in
            ArisApps.Grounding.named(target).id.flatMap { _ in ArisApps.Grounding.matches(target, in: readElements(session, typedApp) ?? []).last }
        }
        if capability == "app.type", arguments["replace"] as? Bool == true {
            if typedTarget.map({ ArisApps.Grounding.named($0).id != nil }) == true {
                facts.erases = Self.peekRead(typedApp, typedTarget, typedSeen).map { ArisErasedText(text: $0.text, keepable: $0.keepable) }
                    ?? ArisErasedText(text: nil, keepable: false)
            } else {
                facts.erases = Self.peekReplaced(typedApp, typedTarget)
            }
        }
        // A model's typing (never a replace, which has its own card above; never a replay's, which has its own read
        // below) goes over whatever is selected where it lands, so its field's selection is read now, whatever came
        // before it (security review of exp11: recognising a Select All can't be the guard). Read and empty: it types
        // as any text put in, its run bound to that (`typingMark`). Anything selected, or a selection that can't be
        // read: it erases, and asks on a card that shows it (or says it couldn't be read).
        // A Select All decided earlier in this turn for that app (ArisSelectAllWatch, an extra signal: in one batch
        // it hasn't run yet when the typing is decided, so no read can see it) makes the typing a replace of the
        // field's whole text, bound to it.
        var typesOver = false
        var typingMark: String?
        if capability == "app.type", arguments["replace"] as? Bool != true, lock.withLock({ described[session]?[call] == nil }) {
            let key = typedApp.isEmpty ? nil : Self.appKey(typedApp, resolved: appKey(typedApp))
            let noted = lock.withLock { selectAll.typing(session: session, app: key) }
            let peek = Self.typingPeek(typedApp, typedTarget, typedSeen)
            let selected = peek?.selected, whole = peek?.text
            if noted, selected == "", let whole, !whole.isEmpty {
                facts.erases = ArisErasedText(text: whole, keepable: peek?.keepable == true)
                typesOver = true
            } else if selected == "", !noted || whole == "" {
                typingMark = ArisApps.TypeOver.empty
            } else {
                facts.erases = ArisErasedText(text: selected.flatMap { $0.isEmpty ? nil : $0 }, keepable: selected != nil && peek?.keepable == true)
                typesOver = true
            }
        } else if capability != "app.type" {
            let app = arguments["app"] as? String ?? ""
            let key = app.isEmpty ? nil : Self.appKey(app, resolved: appKey(app))
            lock.withLock {
                selectAll.acted(session: session, capability: capability, arguments: arguments, app: key)
                if ArisSelectAllWatch.selectsAll(capability: capability, arguments: arguments) { selectAllCalls.insert(session + "/" + call) }
            }
        }
        if capability == "app.type", arguments["replace"] as? Bool != true, lock.withLock({ described[session]?[call] != nil }) {
            let selected = Self.peekSelection(arguments["app"] as? String ?? "", arguments["target"] as? String)
            if selected != "" {
                facts.erases = ArisErasedText(text: selected, keepable: false)
                typesOver = true
            }
        }
        let rated = typesOver ? ArisEffectClass.changePermanent : decided
        // What content may drive (ArisContentReach): input into an app, and an address that first appeared in content
        // (not in a page Aris fetched from the public web itself).
        facts.inputAct = ArisContentReach.isInput(capability: capability, effect: decided, argv: argv)
        facts.contentAddress = verdict.contentKinds.contains(.url) && verdict.urlSource?.publicWeb != true
        // What each path the call changes is, read now, for its card and for the guard on whole folders (ArisBroadTarget).
        let guarded = ArisBroadTarget.guarded(capability: capability, effect: decided, argv: argv, paths: facts.values(.path))
        if decided == .changeReversible || decided == .changePermanent {
            var seen = Set<String>()
            facts.pathTargets = (guarded + facts.values(.path)).filter { seen.insert($0).inserted }.map { ArisPathTarget(path: $0, kind: pathKind($0)) }
        }
        let breadth = guarded.isEmpty ? ArisBroadTarget.Verdict.fine
            : ArisBroadTarget.judge(facts.pathTargets.filter { guarded.contains($0.path) }, said: said, home: home)
        if case .wholeFolder(let folder) = breadth { facts.wholeFolder = folder }
        // A job's request makes its turn one about paying (never its words: twelfth VM run, B3), and is the language its
        // hand-offs' words go out in.
        let job = lock.withLock { jobWords[session] } ?? ""
        let request = said.isEmpty ? job : said, paying = said + "\n" + job
        // A hand-off: where its words go and the words exactly as they go out, for its own card (twelfth VM run, B1).
        facts.handOff = ArisHandOffWords.read(argv: argv, request: request)
        // The card's title only (never the class or the decision): a line whose first program is osascript is a script run.
        if capability == "shell.run" { facts.scriptTitle = Self.firstProgramIsScript((arguments["command"] as? String) ?? keys.first { $0.kind == .command }?.value) }
        var decision = ArisTrustPolicy.decide(facts, effect: rated, provenance: verdict.provenance, specified: verdict.specified,
                                              ownerNamed: verdict.ownerNamed, speaker: verdict.speaker, context: settings.context(home: home, now: now()))
        if typesOver {
            switch decision {
            case .run, .runWithUndo, .sayThenRun: decision = .ask
            case .readBackThenAsk, .ask, .refuse: break
            }
        }
        // A whole folder, or a place too broad, after every other rule and only stricter.
        decision = ArisBroadTarget.decide(decision, breadth)
        // rel11's payment boundary, in Core 2 too (here the hand-offs are judged by this gate, not ArisRiskPolicy): a brief
        // handed to Aside, a background task, a schedule, a routine, a coding session or a teammate's launch that tells it
        // to pay is refused; any brief in a turn about paying asks on its card. Only stricter. Its words carry the owner's
        // rule where they arrive (ArisAsideTool, ArisTaskTool/the task's run, ArisScheduler, ArisSessionSend, ArisTeammateGate).
        decision = Self.paymentBoundary(decision, argv: argv, request: paying)
        // Aris's own hands in a browser, in a turn or job about paying (twelfth VM run, B3): up to the payment step only,
        // a pay or order button never pressed, a checkout page's keys only those that move through a form. Only stricter.
        if facts.browser != nil {
            let app = arguments["app"] as? String ?? ""
            let words = ["target", "option", "command", "action", "task"].compactMap { arguments[$0] as? String } + [facts.browser?.target].compactMap { $0 }
            decision = ArisCheckoutGuard.decide(decision, facts: facts, payingTurn: ArisPaymentBoundary.involves(paying), address: pageAddress(app),
                                                words: words, keys: arguments["keys"] as? String)
        }
        // A hand-off is never only said and then sent: its words are read back on its card first (only stricter).
        if facts.handOff != nil, case .sayThenRun = decision { decision = .ask }
        // A shell line is never how something is deleted (tenth VM run, item 3): the Trash capability is, with its undo.
        if capability == "shell.run", ArisMindJudge.mayRun(decision),
           Self.shellDeletes((arguments["command"] as? String) ?? keys.first { $0.kind == .command }?.value) {
            decision = .refuse(reason: Self.shellDeleteRefusal)
        }
        // An undo reaches what its provenance lets it (ArisUndoScope): the owner's words any entry, anything else its own.
        if ArisRecord.capabilities.contains(where: { $0.id == capability }) {
            let caller = ArisUndoCaller(session: session, task: task, provenance: verdict.provenance, speaker: verdict.speaker)
            // The speaker is read again after the undo's own plan, so no path through it drops the voice check (F1).
            decision = ArisTrustPolicy.voiceChecked(undoDecision(arguments, caller: caller, base: decision), effect: rated, speaker: verdict.speaker)
        }
        // Every path the call names, where it lands (links followed): a link into a protected place is that place.
        if let rule = Self.linkedPathRule(facts.values(.path), effect: rated, home: home) { decision = .refuse(reason: rule.korean) }
        let outcome = Outcome(decision: decision, verdict: verdict, facts: facts, effect: rated, typingMark: typingMark)
        if case .refuse = decision { record(session: session, task: task, call: call, outcome: outcome, answer: nil, result: nil, ok: false, undo: nil) }
        return outcome
    }

    /// The cards for one step's calls that wait for the owner (one per intent: `intent` is the turn or task), in the
    /// confirm line's format; and the calls an earlier yes of the same intent already covers (they run).
    /// `onAnswer`: called once per card with the calls that now run and those refused (the loop waits on it).
    func cards(session: String, task: String? = nil, intent: String, outcomes: [(call: String, outcome: Outcome)],
               onAnswer: (([String], [String]) -> Void)? = nil) -> (cards: [ArisConfirmation], covered: [String]) {
        let items = outcomes.map { ArisAskItem(call: $0.call, facts: $0.outcome.facts, effect: $0.outcome.effect, decision: $0.outcome.decision,
                                               provenance: $0.outcome.verdict.provenance, ownerNamed: $0.outcome.verdict.ownerNamed,
                                               readFrom: $0.outcome.verdict.readFrom, inspired: $0.outcome.verdict.inspired) }
        return lock.withLock {
            let planned = asks.plan(items, intent: intent, home: home, described: described[session] ?? [:])
            for card in planned.cards {
                let mine = Dictionary(uniqueKeysWithValues: outcomes.filter { card.calls.contains($0.call) }.map { ($0.call, $0.outcome) })
                waiting[card.id] = (session, task, mine)
                shownCards[card.id] = card
                if let onAnswer { waiters[card.id] = onAnswer }
            }
            return (planned.cards.map(Self.confirmation), planned.covered)
        }
    }

    /// What a path is right now (the link itself, never what it points at): a file, a folder and how many items are
    /// directly in it, nothing, or unreadable. The tests hand in their own.
    var pathKind: (String) -> ArisPathKind = ArisTrustGate.livePathKind

    static func livePathKind(_ raw: String) -> ArisPathKind {
        let path = ((raw as NSString).expandingTildeInPath as NSString).standardizingPath
        guard path.hasPrefix("/") else { return .unknown }
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .missing : .unknown }
        switch info.st_mode & S_IFMT {
        case S_IFREG, S_IFLNK: return .file
        case S_IFDIR: return .folder(items: (try? FileManager.default.contentsOfDirectory(atPath: path))?.count)
        default: return .unknown
        }
    }

    static let deletingPrograms: Set<String> = ["rm", "rmdir", "srm", "shred", "unlink", "trash"]
    static let shellDeleteRefusal = "파일이나 폴더는 셸 명령으로 지우지 않아요. 휴지통으로 옮기기(file_trash)를 쓰면 되돌릴 수 있어요. "
        + "(Aris never deletes with a shell command: use file_trash, which can be undone.)"

    /// A shell line that deletes: one of its parts runs a deleting program, moves something into the Trash folder, or
    /// is a script that tells an app to delete. Read with the shell rule's own splitter; a line it can't read is left
    /// to the shell rule (which asks or refuses).
    static func shellDeletes(_ command: String?) -> Bool {
        guard let command, let pieces = ArisCommandPolicy.segments(command) else { return false }
        for piece in pieces {
            guard let words = ArisCommandPolicy.words(piece), let first = words.first else { continue }
            let program = (first as NSString).lastPathComponent
            if deletingPrograms.contains(program) { return true }
            if program == "mv", words.dropFirst().contains(where: { $0.contains("/.Trash") }) { return true }
            if program == "osascript", words.dropFirst().contains(where: { $0.range(of: #"\bdelete\b|\btrash\b"#, options: [.regularExpression, .caseInsensitive]) != nil }) { return true }
        }
        return false
    }

    /// What a replace in that app's field would erase now (ArisMindLive installs the app layer's read): the field's text
    /// and whether a copy of it can be kept; by default it can't be read.
    nonisolated(unsafe) static var peekReplaced: (_ app: String, _ target: String?) -> ArisErasedText = { _, _ in ArisErasedText(text: nil, keepable: false) }

    /// The text selected in that app's field now, which typing there would go over (ArisMindLive installs the app
    /// layer's read): "" when nothing is selected; nil when it can't be read, which is the default and is taken as
    /// something selected (a miss is never less strict than a hit).
    nonisolated(unsafe) static var peekSelection: (_ app: String, _ target: String?) -> String? = { _, _ in nil }

    /// The payment boundary on a hand-off call (ArisPaymentHandOff names its brief; a coding session's or a teammate's
    /// launch is a coding context). Never looser than `decision`.
    static func paymentBoundary(_ decision: ArisDecision, argv: [String]?, request: String) -> ArisDecision {
        guard let argv, let brief = ArisPaymentHandOff.brief(argv) else { return decision }
        switch ArisPaymentBoundary.judge(brief: brief, request: request, coding: argv.first == "session") {
        case .plain: return decision
        case .refused: return .refuse(reason: ArisPaymentBoundary.refusedLine)
        case .stopsAtPayment:
            switch decision {
            case .run, .runWithUndo, .sayThenRun: return .ask
            case .readBackThenAsk, .ask, .refuse: return decision
            }
        }
    }

    /// An app's key for the Select All watch: as resolved (its bundle id), else its name folded.
    static func appKey(_ name: String, resolved: String?) -> String {
        if let resolved, !resolved.isEmpty { return resolved.lowercased() }
        return name.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What a model's typing into `app` would go over, read now: the field app.type will take (an id found again by what
    /// this turn's read printed for it, `seen`; no field named: the window's one document or field, as app.type takes
    /// it), its whole text and its selected text; a field named in words, only its selection, as app.type finds it.
    /// Nil (or a nil selection) when it can't be read, which is taken as something selected.
    static func typingPeek(_ app: String, _ target: String?, _ seen: ArisApps.Grounding.Seen?) -> (text: String?, selected: String?, keepable: Bool)? {
        let named = target?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !named.isEmpty, ArisApps.Grounding.named(named).id == nil {
            return (text: nil, selected: peekSelection(app, named), keepable: false)
        }
        return peekRead(app, target, seen).map { (text: $0.text, selected: $0.selected, keepable: $0.keepable) }
    }

    /// The text field a replace of `target` in `app` means, read now (ArisApps.Read.replaceField; `seen`: what this
    /// turn's read printed for an id): its whole text, what is selected in it (nil: can't be told), and whether a copy
    /// of the text can be kept. Nil when there is no such field to read, which is the default and the strict case.
    nonisolated(unsafe) static var peekRead: (_ app: String, _ target: String?, _ seen: ArisApps.Grounding.Seen?)
        -> (text: String, selected: String?, keepable: Bool)? = { _, _, _ in nil }

    static func confirmation(_ card: ArisAskCard) -> ArisConfirmation {
        var shown = ArisConfirmation(id: card.id, title: card.title, detail: card.detail, countdown: card.countdown, spoken: card.spoken, full: card.full)
        // A countdown that is no message (a permanent change said first): the app draws it as an action, not 받는 사람/메시지.
        shown.action = card.countdown && !card.message
        return shown
    }

    /// Whether the card the app showed is the card made: its details exactly (a no needs no match).
    func shown(_ id: String, detail: String?, full: String?) -> Bool {
        lock.withLock { shownCards[id].map { $0.detail == detail && $0.full == full } ?? false }
    }

    /// Whether a card id is one of this gate's (POST /confirm sends those here).
    func owns(_ id: String) -> Bool { lock.withLock { waiting[id] != nil } }

    /// The owner's answer to a card (the card's allow, `always` when the app sends it, or their words). Returns the
    /// calls that now run and those refused; "yes, always" keeps its grants. A refused call is recorded here.
    /// `unanswered`: the card timed out with no answer from him: for its calls exactly a no, recorded as unanswered.
    func answer(_ id: String, allow: Bool, always: Bool = false, words: String? = nil, unanswered: Bool = false) -> (run: [String], refused: [String]) {
        let none = unanswered && !allow && words == nil
        let answer = none ? .no : words.flatMap(ArisAskAnswer.parse) ?? ArisAskAnswer.from(allow: allow, always: always)
        let (result, held, waiter) = lock.withLock {
            shownCards[id] = nil
            return (asks.answer(id, answer, home: home, now: now()), waiting.removeValue(forKey: id), waiters.removeValue(forKey: id))
        }
        if !result.grants.isEmpty {
            var next = settings
            next.grants += result.grants
            try? next.save(home: home)
        }
        if let held {
            for call in result.refused {
                guard let outcome = held.outcomes[call] else { continue }
                record(session: held.session, task: held.task, call: call, outcome: outcome, answer: none ? "unanswered" : "no",
                       result: none ? ArisJournalWords.unanswered(english: ArisSkillLanguage.english) : ArisJournalWords.declined(english: ArisSkillLanguage.english), ok: false, undo: nil)
            }
            answers.withLock { for call in result.run { $0[call] = answer == .always ? "always" : "yes" } }
        }
        waiter?(result.run, result.refused)
        return (result.run, result.refused)
    }

    private let answers = ArisLocked<[String: String]>([:])

    /// The turn or task is over: its asks and yeses end with it.
    func end(intent: String) {
        let closed: [([String], [String]) -> Void] = lock.withLock {
            asks.end(intent: intent)
            let gone = Set(waiting.keys).subtracting(asks.open.keys)
            return gone.compactMap { id in
                waiting[id] = nil
                shownCards[id] = nil
                return waiters.removeValue(forKey: id)
            }
        }
        // Told outside the lock: nothing runs.
        for waiter in closed { waiter([], []) }
    }

    /// A session is over: its tracker goes.
    func forget(session: String) {
        lock.withLock {
            trackers[session] = nil
            described[session] = nil
            jobWords[session] = nil
            selectAll.newTurn(session: session)
            selectAllCalls = selectAllCalls.filter { !$0.hasPrefix(session + "/") }
            order.removeAll { $0 == session }
        }
    }

    /// The never-list's rule for the first of `paths` that a link on the way takes somewhere protected (ArisCore2.resolved);
    /// nil when none (a path with no link on the way is the policy's own check).
    static func linkedPathRule(_ paths: [String], effect: ArisEffectClass, home: String) -> ArisNeverRule? {
        for path in paths where path.hasPrefix("/") || path.hasPrefix("~") {
            let given = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
            let landed = ArisCore2.resolved(given, home: home)
            guard !ArisCore2.samePlace(given, landed) else { continue }
            if let rule = ArisNeverList.pathRule(landed, effect: effect, home: home) { return rule }
        }
        return nil
    }

    /// The verdict with more reasons.
    static func adding(_ reasons: [String], to verdict: ArisProvenanceVerdict) -> ArisProvenanceVerdict {
        var more = ArisProvenanceVerdict(provenance: verdict.provenance, specified: verdict.specified, ownerNamed: verdict.ownerNamed,
                                         reasons: verdict.reasons + reasons)
        more.speaker = verdict.speaker
        more.readFrom = verdict.readFrom
        more.contentKinds = verdict.contentKinds
        more.urlSource = verdict.urlSource
        more.inspired = verdict.inspired
        return more
    }

    /// An act on a browser window's page: the app named is a browser and the call acts (a look is no act). Nil
    /// otherwise.
    /// The line's first program, as the shell rule's own splitter reads it (ArisCommandPolicy), is osascript.
    static func firstProgramIsScript(_ command: String?) -> Bool {
        guard let command, let piece = ArisCommandPolicy.segments(command)?.first, let first = ArisCommandPolicy.words(piece)?.first else { return false }
        return first == "osascript" || first == "/usr/bin/osascript"
    }

    private func browserPage(session: String, capability: String, effect: ArisEffectClass, arguments: [String: Any], said: String) -> ArisBrowserPage? {
        guard ArisBrowserActs.acts.contains(capability), effect != .observe, let app = arguments["app"] as? String, ArisBrowserActs.isBrowser(app) else { return nil }
        let target = arguments["target"] as? String
        let found = element(app, target)
        // A target that is a read's id is shown by the element's kind and name, never the id (eleventh VM run, C5:
        // "대상: e188"); an element with no name, or one nothing was read for, is said as that.
        let read = target.map { ArisApps.Grounding.matches($0, in: readElements(session, app) ?? []) }?.last
        let shown = target.flatMap { ArisApps.Grounding.shown(target: $0, seen: readElements(session, app)) }
        let label = found.label ?? read.flatMap { $0.label.isEmpty ? nil : $0.label } ?? (shown == nil ? target : nil)
        return ArisBrowserPage(host: ArisBrowserActs.host(pageAddress(app)), target: found.label ?? shown?.words ?? target,
                               secret: found.secure || read?.role == "secureTextField" || ArisBrowserActs.namesSecret(label),
                               signIn: ArisBrowserActs.namesSignIn(label), signInAsked: ArisBrowserActs.asksForSignIn(said))
    }

    private func undoDecision(_ arguments: [String: Any], caller: ArisUndoCaller, base: ArisDecision) -> ArisDecision {
        if case .refuse = base { return base }
        let plan = ArisRecord.plan(id: arguments["id"] as? String, count: (arguments["count"] as? NSNumber)?.intValue, caller: caller, home: home, now: now())
        return plan.decision
    }

    // MARK: - Recording

    /// The call's line in the record, once it ran (or was refused, or its card said no).
    @discardableResult
    func record(session: String, task: String?, call: String, outcome: Outcome, answer: String?, result: String?, ok: Bool, undo: ArisUndoRecipe?,
                logged: [String] = []) -> Bool {
        let answered = answer ?? answers.withLock { $0.removeValue(forKey: call) }
        // A Select All the app layer found by itself (its result says what it pressed), not seen as one when decided.
        let app = ok ? result.flatMap { ArisSelectAllWatch.selectedAll(capability: outcome.facts.capability, result: $0) } : nil
        let key = app.map { Self.appKey($0, resolved: appKey($0)) }
        lock.withLock {
            if selectAllCalls.remove(session + "/" + call) == nil, let key { selectAll.note(session: session, app: key) }
        }
        var entry = ArisRecordEntry.call(at: now(), session: session, task: task, capability: outcome.facts.capability, effect: outcome.effect,
                                         provenance: outcome.verdict.provenance, why: outcome.verdict.reasons, decision: outcome.decision,
                                         answer: answered, arguments: outcome.facts.arguments, result: result, ok: ok, undo: undo)
        entry.logged = logged.isEmpty ? nil : Array(logged.prefix(20))
        return ArisRecord.write(entry, home: home)
    }

    // MARK: - jv-hands' port

    /// The policy's answer in the registry's terms (ArisTrustVerdict: run, run with undo, ask with its question, refuse).
    /// jv-hands' ArisTrustDeciding conformance is this call; `session` is the caller's conversation or task.
    func verdict(session: String, call: String, capability: String, effect: ArisEffectClass, arguments: [String: Any],
                 argv: [String]? = nil, stdin: String? = nil, payment: Bool = false) -> (kind: String, text: String?) {
        let outcome = decide(session: session, call: call, capability: capability, effect: effect, arguments: arguments, argv: argv, stdin: stdin,
                             payment: payment)
        switch outcome.decision {
        case .run: return ("run", nil)
        case .runWithUndo: return ("runWithUndo", nil)
        case .sayThenRun, .readBackThenAsk, .ask:
            let item = ArisAskItem(call: call, facts: outcome.facts, effect: outcome.effect, decision: outcome.decision, provenance: outcome.verdict.provenance,
                                   ownerNamed: outcome.verdict.ownerNamed, readFrom: outcome.verdict.readFrom, inspired: outcome.verdict.inspired)
            // A payment's or a browser act's question reads it back as its own card does (decisions 1 and 2).
            if outcome.facts.registeredPayment || outcome.facts.browser != nil {
                let card = outcome.facts.registeredPayment ? ArisAskPlan.paymentCard(item, id: call, intent: session) : ArisAskPlan.browserCard(item, id: call, intent: session)
                return ("ask", card.title + "\n" + card.detail)
            }
            return ("ask", ([ArisAskPlan.line(item)] + ArisAskPlan.sendsLines(item)).joined(separator: "\n"))
        case .refuse(let reason): return ("refuse", reason)
        }
    }

    // MARK: - Inside

    private func tracker(_ session: String) -> ArisProvenanceTracker {
        if let tracker = trackers[session] { return tracker }
        order.append(session)
        if order.count > Self.keptSessions {
            let gone = order.removeFirst()
            trackers[gone] = nil
            described[gone] = nil
        }
        let tracker = ArisProvenanceTracker(world: world(session))
        trackers[session] = tracker
        return tracker
    }

    /// `mutating` access to a session's tracker under the lock.
    private func tracker(_ session: String, _ change: (inout ArisProvenanceTracker) -> Void) {
        var tracker = self.tracker(session)
        change(&tracker)
        trackers[session] = tracker
    }

    static func describe(_ change: ArisGrantChange) -> String {
        switch change {
        case .add(let grant): "add \(grant.effect?.rawValue ?? "") \(grant.target?.kind.rawValue ?? "") \(grant.target?.pattern.prefix(60) ?? "")"
        case .revoke(let effect, let target): "revoke \(effect?.rawValue ?? "any") \(target?.pattern.prefix(60) ?? "")"
        }
    }

    static func line(_ fields: [String: String]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// A value behind its own lock.
final class ArisLocked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func withLock<T>(_ work: (inout Value) -> T) -> T { lock.withLock { work(&value) } }
}
