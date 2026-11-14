//
//  ArisMemoryCurator.swift
//  aris-agent
//
//  Memory at work, around each turn:
//  - before: the turn's few relevant memories for its context (ArisMemoryRecall), the relevant ones marked used;
//  - after a clean turn (ArisMemoryLearning.mayLearn): the user's words become a day note and, when they might hold
//    something lasting, the on-device model's picks (or the rules') are checked and merged in, on a background queue;
//  - "기억해 / 잊어 / 내가 뭐라고 했지 / 나에 대해 뭐 알아 / 어제 뭐 했지" are answered here (ArisMemoryIntent);
//  - days that ended get their one-paragraph summary.
//  The model calls are passed in, so the tests run without one.
//

import Foundation

/// A turn's memory: the lines, and for a restricted turn the value its fence is marked with (ArisMemoryRecall.fencedBlock).
struct ArisMemoryContext: Equatable {
    var text: String?
    var nonce: String?

    static let none = ArisMemoryContext(text: nil, nonce: nil)
}

final class ArisMemoryCurator: @unchecked Sendable {
    let store: ArisMemoryStore
    private let extract: (String) -> [ArisMemoryCandidate]?
    private let summarize: ([String]) -> String?
    /// The weekly tidy-up's one question (brain, instruction, input) to the user's own brain, sealed; nil when it can't.
    private let consolidate: (String, String, String) -> String?
    /// The last turn that asked for memory (the tidy-up waits until the user has been idle a while).
    private var lastTurnAt: Date?
    private var timer: DispatchSourceTimer?
    private let calendar: Calendar
    /// What time it is (the tests pass a fixed one).
    private let clock: @Sendable () -> Date
    /// Every store write, the day roll-up and the model calls run here, one at a time.
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.memory", qos: .utility)
    /// The memories as last read, so a turn's context needs no SQLite on the server queue (guarded by `cacheLock`).
    private let cacheLock = NSLock()
    private var cache: [ArisMemoryRecord] = []
    private var entityCache: [ArisEntity] = []
    /// The memories the user's last "잊어" matched when there were several, until they says yes or no (2 minutes).
    private var pendingForget: (ids: [String], at: Date)?
    static let pendingLife: TimeInterval = 120

    init(store: ArisMemoryStore, calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() },
         extract: @escaping (String) -> [ArisMemoryCandidate]?, summarize: @escaping ([String]) -> String?,
         consolidate: @escaping (String, String, String) -> String? = { _, _, _ in nil }) {
        self.store = store
        self.calendar = calendar
        self.clock = clock
        self.extract = extract
        self.summarize = summarize
        self.consolidate = consolidate
    }

    /// How often the tidy-up looks whether it is due.
    static let consolidationCheck: TimeInterval = 15 * 60

    /// At launch: memory.md comes in once, the cache fills, and ended days get their summaries; then every quarter
    /// hour the weekly tidy-up looks whether it is due.
    func start() {
        queue.async { [self] in
            let imported = store.importBackupIfNeeded()
            if imported > 0 { FileHandle.standardError.write(Data("aris-agent: imported \(imported) memories from memory.md (kept as the backup)\n".utf8)) }
            refreshNow()
            rollUp(now: clock())
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.consolidationCheck, repeating: Self.consolidationCheck)
        timer.setEventHandler { [weak self] in self?.consolidateIfDue() }
        timer.resume()
        self.timer = timer
    }

    // MARK: - The weekly tidy-up

    /// On the memory queue: starts the tidy-up when it is due (ArisMemoryConsolidation.due) with the user's own brain.
    private func consolidateIfDue() {
        let now = clock()
        guard ArisMemoryConsolidation.due(on: store.consolidates, last: store.consolidatedAt, lastTurn: cacheLock.withLock({ lastTurnAt }), now: now) else { return }
        consolidateInBackground(at: now)
    }

    /// The tidy-up's own queue: its brain calls (up to a minute and a half each) never hold the memory queue, so a
    /// "잊어" or any other of the user's own memory actions runs while it works (security review 10, L7). The store's lock
    /// is taken only for each read and write, and a summary is written only while the memories it was made from are
    /// still there as read (ArisMemoryStore.applyConsolidation).
    private let tidyQueue = DispatchQueue(label: "com.lumenjsn.aris.agent.memory.tidy", qos: .utility)
    /// A tidy-up is under way (guarded by `cacheLock`): the timer starts no second one.
    private var tidying = false

    /// Starts one tidy-up on its own queue, unless one is under way. False when one was.
    @discardableResult
    func consolidateInBackground(at now: Date) -> Bool {
        let start = cacheLock.withLock { () -> Bool in
            guard !tidying else { return false }
            tidying = true
            return true
        }
        guard start else { return false }
        tidyQueue.async { [self] in
            let changes = consolidateNow(at: now)
            if !changes.isEmpty { FileHandle.standardError.write(Data("aris-agent: the weekly memory tidy-up changed \(changes.count) summaries\n".utf8)) }
            cacheLock.withLock { tidying = false }
        }
        return true
    }

    /// Waits until a tidy-up started in the background has ended, and the cache read after it (tests).
    func drainTidy() {
        tidyQueue.sync {}
        drain()
    }

    /// One tidy-up now, with the brain the owner chose for their own turns and no other (none recorded: nothing is asked, and
    /// it waits for the next week). Off the memory queue (consolidateInBackground; tests: directly); the cache is read
    /// again on the memory queue after it, in line with every other write.
    @discardableResult
    func consolidateNow(at now: Date) -> [ArisMemoryConsolidation.Change] {
        guard store.consolidates else { return [] }
        guard let brain = store.ownersBrain else {
            store.consolidatedAt = now
            return []
        }
        let changes = ArisMemoryConsolidation.run(store: store, now: now) { instruction, input in consolidate(brain, instruction, input) }
        queue.async { [self] in refreshNow() }
        return changes
    }

    /// Waits until everything queued so far has run (tests).
    func drain() { queue.sync {} }

    /// Reads the store into the cache (aris-tools may have written it); on the memory queue.
    func refresh() { queue.async { [self] in refreshNow() } }

    private func refreshNow() {
        // An import's journal keeps its 30 days whether or not another import comes (review 8, LOW).
        store.pruneImportJournal()
        // An unsettled conflict's older side isn't recalled until the user settles it (ArisMemoryStore+Review).
        let heldBack = store.conflictHeldBack()
        let all = Self.usable(store.all()).filter { !heldBack.contains($0.id) }
        let entities = store.entities()
        cacheLock.withLock {
            cache = all
            entityCache = entities
        }
    }

    /// Memories that may be said or given to a brain: never a question the learner once stored (QA BUG-59: one was read
    /// back as the user's favourite fruit). Such a row is as good as unknown; what the user told Aris to remember stays.
    static func usable(_ records: [ArisMemoryRecord]) -> [ArisMemoryRecord] {
        records.filter { !($0.source == .learned && ArisMemoryLearning.asks($0.text)) }
    }

    // MARK: - Before the turn

    /// The memory lines for a turn about `words`, or nil: none at all unless the turn may have them
    /// (ArisMemoryLearning.mayRecall), and none when nothing fits. From the cache; the relevant ones are marked used
    /// afterwards, on the memory queue, and the cache is read again for the next turn.
    func context(for words: String, eligible: Bool, now: Date? = nil) -> String? {
        context(for: words, mode: eligible ? .full : .none, now: now).text
    }

    /// Entity cards a turn gets at most (full, restricted).
    static let cardsFull = 2
    static let cardsRestricted = 1

    /// A turn's memory by its mode (ArisMemoryLearning.recallMode): the cards of the people and projects the user's words
    /// name, then the memories. `full`: the relevant ones and the core, as plain lines. `restricted`: only the few his
    /// own words are about, each with its source, fenced with this turn's own value. `none`: nothing. `brain`: the
    /// brain the owner chose for a full turn (the only one the weekly tidy-up may ask).
    func context(for words: String, mode: ArisMemoryLearning.RecallMode, brain: String? = nil, now: Date? = nil) -> ArisMemoryContext {
        guard mode != .none else { return .none }
        let now = now ?? clock()
        let (records, entities) = cacheLock.withLock { () -> ([ArisMemoryRecord], [ArisEntity]) in
            lastTurnAt = now
            return (cache, entityCache)
        }
        let own = ArisMemoryText.ownWords(words)
        let cards = ArisEntities.mentioned(entities, in: own).prefix(mode == .full ? Self.cardsFull : Self.cardsRestricted)
            .map { "- [\($0.kind.label(korean: true)) 카드] " + ArisEntities.card($0, memories: records, now: now) }
        let cardCost = cards.reduce(0) { $0 + ArisMemoryText.tokenEstimate($1) + 1 }
        let lines: [String], used: [String]
        if mode == .full {
            let picked = ArisMemoryRecall.pick(records, for: words, now: now, budget: max(0, ArisMemoryRecall.budget - cardCost))
            lines = cards + picked.all.map(ArisMemoryRecall.line)
            used = picked.relevant.map(\.id)
        } else {
            let picked = ArisMemoryRecall.pickRestricted(records, for: own, now: now)
            lines = cards + picked.map(ArisMemoryRecall.line)
            used = picked.map(\.id)
        }
        let chosen = brain
        queue.async { [self] in
            if let chosen, mode == .full, store.ownersBrain != chosen { store.ownersBrain = chosen }
            store.markUsed(used, at: now)
            refreshNow()
        }
        guard !lines.isEmpty else { return .none }
        return mode == .full ? ArisMemoryContext(text: lines.joined(separator: "\n"), nonce: nil)
            : ArisMemoryContext(text: lines.joined(separator: "\n"), nonce: ArisWorkRecall.nonce())
    }

    // MARK: - After a clean turn

    /// Learns from the user's words of a clean turn, later, on the memory queue; then the ended days roll up.
    func learn(from words: String, at date: Date? = nil) {
        let date = date ?? clock()
        let words = ArisMemoryText.ownWords(words)
        queue.async { [self] in
            _ = learnNow(from: words, at: date)
            rollUp(now: date)
        }
    }

    /// What learning from `words` wrote (nothing when learning on its own is off). Call it on the memory queue (tests:
    /// directly).
    func learnNow(from words: String, at date: Date) -> [ArisMemoryStore.Outcome] {
        guard store.learnsOnItsOwn else { return [] }
        store.addNote(words, at: date, calendar: calendar)
        // The user's words to their memory are a command (its own path, or a card they answered), never a fact (QA BUG-6).
        // A question learns nothing (QA BUG-59).
        guard ArisMemoryLearning.worthTrying(words), !ArisMemoryLearning.isMemoryCommand(words), !ArisMemoryLearning.asks(words) else { return [] }
        let picked = extract(words) ?? ArisMemoryLearning.ruleCandidates(words)
        let outcomes = ArisMemoryLearning.accepted(picked, words: words).map { store.remember($0, source: .learned, turnAt: date, now: date) }
        refreshNow()
        return outcomes
    }

    /// Every ended day with notes and no summary gets one (the model's, or the plain one); old notes go. On the memory
    /// queue only (start, learn, and a day question that found none yet).
    func rollUp(now: Date) {
        let today = ArisMemoryText.day(now, calendar: calendar)
        for day in store.daysToSummarize(before: today) {
            let notes = store.notes(day: day)
            guard let text = summarize(notes) ?? ArisMemoryAnswer.plainSummary(notes, offset: -1, korean: notes.contains(where: ArisMemoryText.isKorean))
            else { continue }
            store.setSummary(text, day: day, now: now)
        }
        store.prune(today: today, now: now, calendar: calendar)
    }

    // MARK: - Spoken to

    /// "응" or "아니" while several memories wait to be forgotten: that answer; nil otherwise.
    func pendingIntent(for said: String, now: Date? = nil) -> ArisMemoryIntent? {
        let now = now ?? clock()
        guard let pending = cacheLock.withLock({ pendingForget }), now.timeIntervalSince(pending.at) <= Self.pendingLife,
              let yes = ArisMemoryIntent.yesOrNo(said) else { return nil }
        return .confirmForget(yes)
    }

    /// The answer to a memory intent; nil hands the turn to the brain (a recall that finds nothing). Runs on the memory
    /// queue, so it is in line with every other write.
    func answer(_ intent: ArisMemoryIntent, said: String, now: Date? = nil) -> String? {
        let now = now ?? clock()
        return queue.sync { answerNow(intent, said: said, now: now) }
    }

    /// What "…잊어 줘" about `words` would remove, and whether the user is asked first: several memories, or any found only
    /// loosely (every word of the topic, a verb by its stem), never by the words as said (QA BUG-59).
    private func forgetPlan(_ words: String) -> (found: [ArisMemoryRecord], asks: Bool) {
        let exact = store.matching(words)
        if !exact.isEmpty { return (exact, exact.count > 1) }
        let loose = store.overlapping(words)
        return (loose, !loose.isEmpty)
    }

    /// The memories a forget would ask about first (nil: none, or just the one named as said, which goes at once), for
    /// the confirm card.
    func forgetAsks(_ words: String) -> [ArisMemoryRecord]? {
        queue.sync {
            let plan = forgetPlan(words)
            return plan.asks ? plan.found : nil
        }
    }

    /// The user's yes on the card: exactly those memories go.
    func forget(_ records: [ArisMemoryRecord], korean: Bool) -> String {
        queue.sync {
            defer { refreshNow() }
            store.delete(ids: records.map(\.id))
            return ArisMemoryAnswer.forgot(records, words: "", korean: korean)
        }
    }

    private func answerNow(_ intent: ArisMemoryIntent, said: String, now: Date) -> String? {
        let korean = ArisMemoryText.isKorean(said) || !said.contains(where: \.isLetter)
        defer { refreshNow() }
        if case .confirmForget = intent {} else { cacheLock.withLock { pendingForget = nil } }
        switch intent {
        case .remember(let fact):
            let candidate = ArisMemoryCandidate(kind: ArisMemoryKind.guess(fact), subject: ArisMemoryLearning.subject(of: fact), text: fact,
                                                confidence: ArisMemoryStore.saidConfidence)
            return ArisMemoryAnswer.remembered(store.remember(candidate, source: .said, turnAt: now, now: now), korean: korean)
        case .forget(let words):
            let plan = forgetPlan(words)
            guard plan.asks else {
                store.delete(ids: plan.found.map(\.id))
                return ArisMemoryAnswer.forgot(plan.found, words: words, korean: korean)
            }
            cacheLock.withLock { pendingForget = (plan.found.map(\.id), now) }
            return ArisMemoryAnswer.askForget(plan.found, words: words, korean: korean)
        case .confirmForget(let yes):
            let pending = cacheLock.withLock { () -> [String] in
                defer { pendingForget = nil }
                return pendingForget.map(\.ids) ?? []
            }
            guard yes else { return korean ? "그대로 둘게요." : "Okay, I'll keep them." }
            let records = store.all().filter { pending.contains($0.id) }
            store.delete(ids: pending)
            return ArisMemoryAnswer.forgot(records, words: "", korean: korean)
        case .forgetAll:
            return ArisMemoryAnswer.forgetAll(korean: korean)
        case .recall(let topic):
            let all = Self.usable(store.all())
            let found = topic.map { ArisMemoryRecall.matching(all, words: $0) } ?? Array(all.sorted { $0.turnAt > $1.turnAt }.prefix(3))
            store.markUsed(found.prefix(4).map(\.id), at: now)
            return ArisMemoryAnswer.recall(found, topic: topic, korean: korean)
        case .profile:
            return ArisMemoryAnswer.profile(Self.usable(store.all()), korean: korean)
        case .day(let offset):
            let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
            let day = ArisMemoryText.day(date, calendar: calendar)
            if let summary = store.summary(day: day) { return ArisMemoryAnswer.day(summary, offset: offset, korean: korean) }
            // No summary yet: the plain one now (no model here), and the roll-up after this, in line.
            if offset < 0 { queue.async { [self] in rollUp(now: now) } }
            return ArisMemoryAnswer.day(ArisMemoryAnswer.plainSummary(store.notes(day: day), offset: offset, korean: korean), offset: offset, korean: korean)
        }
    }
}

/// POST /memory: the settings 기억 page (only the Aris app itself: ArisPeer, checked in main.swift).
///   {"op": "list"}                    -> {"memories": [{"id","kind","subject","text","source","label","said","used"?,"via"?,"mark"?,"changed"?}], "auto": bool,
///                                         "held": [{"id","kind","text","source","why","whyEn"}], "conflicts": [{"id","first","second"}],
///                                         "entities": [{"id","kind","name","summary","entries","open"}], "changes": [{"id","name","before","after","at","evidence"}],
///                                         "consolidate": bool}
///   {"op": "heldKeep", "id": "…"}     -> {"kept": bool}        (확인할 것 › 넣기: written as the user saw it)
///   {"op": "heldDrop", "id": "…"}     -> {"dropped": bool}     (버리기)
///   {"op": "conflictKeep", "id": "…", "keep": "<memory id>" | "both"} -> {"settled": bool}
///   {"op": "entityDelete", "id": "…"} -> {"removed": bool}     (a page goes; its memories stay)
///   {"op": "changeUndo", "id": n}     -> {"undone": bool}      (the weekly tidy-up's change taken back)
///   {"op": "consolidate", "on": bool} -> {"consolidate": bool} (매주 정리하기)
///   {"op": "delete", "id": "…"}       -> {"removed": bool}
///   {"op": "confirm", "id": "…"}      -> {"confirmed": bool}  (확인: a memory as sure as can be)
///   {"op": "clear", "confirm": "모두"} -> {"cleared": true}   (every memory, day note and summary, and memory.md)
///   {"op": "auto", "on": bool}        -> {"auto": bool}       (자동으로 기억하기)
/// Anything else is 400 with nothing touched. `audit`: the line for actions.log (never a memory's words).
enum ArisMemoryRoute {
    static let clearWord = "모두"

    /// `savedSteps`: the agent's saved desktop steps (ArisSavedStepsRoute), nil where there are none.
    static func handle(_ object: [String: Any], store: ArisMemoryStore, savedSteps: ArisSavedStepsStore? = nil) -> (status: Int, body: Data, audit: String?) {
        switch object["op"] as? String {
        case "list":
            // Where an imported memory came from, and whether it is an instruction (ArisMemoryImportStore).
            let extras = store.importExtras()
            let rows = store.all().map { r -> [String: Any] in
                var row: [String: Any] = ["id": r.id, "kind": r.kind.rawValue, "subject": r.subject, "text": r.text, "source": r.source.rawValue,
                                          "label": r.source.label(korean: true), "said": r.turnAt.timeIntervalSince1970, "confidence": r.confidence]
                if let used = r.lastUsedAt { row["used"] = used.timeIntervalSince1970 }
                // An event holds until the end of its day (ArisMemoryStore.ends): Settings shows the end.
                if let until = r.validUntil { row["until"] = until.timeIntervalSince1970 }
                if let via = extras[r.id]?.via { row["via"] = via }
                if let mark = extras[r.id]?.mark { row["mark"] = mark }
                // Said in other words before: how many older wordings it keeps (never shown by default).
                let older = store.history(of: r.id).count
                if older > 0 { row["changed"] = older }
                return row
            }
            return ok(["memories": rows, "auto": store.learnsOnItsOwn, "consolidate": store.consolidates].merging(ArisMemoryReviewRoute.lists(store)) { a, _ in a },
                      audit: nil)
        case "delete":
            guard let id = object["id"] as? String, !id.isEmpty, id.count <= 64 else { return bad() }
            let removed = store.delete(id: id)
            return ok(["removed": removed], audit: removed ? "memory: deleted one" : nil)
        case "confirm":
            guard let id = object["id"] as? String, !id.isEmpty, id.count <= 64 else { return bad() }
            let confirmed = store.confirm(id: id)
            return ok(["confirmed": confirmed], audit: confirmed ? "memory: confirmed one" : nil)
        case "clear":
            guard object["confirm"] as? String == clearWord else { return bad() }
            return store.deleteAll() ? ok(["cleared": true], audit: "memory: cleared all") : (500, Data("{}".utf8), "memory: clear failed")
        case "auto":
            guard let on = object["on"] as? Bool else { return bad() }
            store.learnsOnItsOwn = on
            return ok(["auto": store.learnsOnItsOwn], audit: "memory: learning on its own \(on ? "on" : "off")")
        default:
            // What waits for the user, people and projects, the weekly tidy-up: ArisMemoryReviewRoute.
            // The work memory's part of the page (일하면서 배운 것): ArisWorkRoute.
            // And the import from another AI (다른 AI에서 가져오기): ArisImportRoute.
            // And the saved desktop steps (저장된 단계): ArisSavedStepsRoute.
            return ArisMemoryReviewRoute.handle(object, store: store) ?? ArisWorkRoute.handle(object, store: ArisWorkStore(memory: store))
                ?? ArisImportRoute.handle(object, store: store) ?? ArisSavedStepsRoute.handle(object, store: savedSteps) ?? bad()
        }
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }

    private static func bad() -> (status: Int, body: Data, audit: String?) { (400, Data("{}".utf8), nil) }
}
