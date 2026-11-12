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

final class ArisMemoryCurator: @unchecked Sendable {
    let store: ArisMemoryStore
    private let extract: (String) -> [ArisMemoryCandidate]?
    private let summarize: ([String]) -> String?
    private let calendar: Calendar
    /// What time it is (the tests pass a fixed one).
    private let clock: @Sendable () -> Date
    /// Every store write, the day roll-up and the model calls run here, one at a time.
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.agent.memory", qos: .utility)
    /// The memories as last read, so a turn's context needs no SQLite on the server queue (guarded by `cacheLock`).
    private let cacheLock = NSLock()
    private var cache: [ArisMemoryRecord] = []
    /// The memories the user's last "잊어" matched when there were several, until they says yes or no (2 minutes).
    private var pendingForget: (ids: [String], at: Date)?
    static let pendingLife: TimeInterval = 120

    init(store: ArisMemoryStore, calendar: Calendar = .current, clock: @escaping @Sendable () -> Date = { Date() },
         extract: @escaping (String) -> [ArisMemoryCandidate]?, summarize: @escaping ([String]) -> String?) {
        self.store = store
        self.calendar = calendar
        self.clock = clock
        self.extract = extract
        self.summarize = summarize
    }

    /// At launch: memory.md comes in once, the cache fills, and ended days get their summaries.
    func start() {
        queue.async { [self] in
            let imported = store.importBackupIfNeeded()
            if imported > 0 { FileHandle.standardError.write(Data("aris-agent: imported \(imported) memories from memory.md (kept as the backup)\n".utf8)) }
            refreshNow()
            rollUp(now: clock())
        }
    }

    /// Waits until everything queued so far has run (tests).
    func drain() { queue.sync {} }

    /// Reads the store into the cache (aris-tools may have written it); on the memory queue.
    func refresh() { queue.async { [self] in refreshNow() } }

    private func refreshNow() {
        // An import's journal keeps its 30 days whether or not another import comes (review 8, LOW).
        store.pruneImportJournal()
        let all = Self.usable(store.all())
        cacheLock.withLock { cache = all }
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
        guard eligible else { return nil }
        let now = now ?? clock()
        let picked = ArisMemoryRecall.pick(cacheLock.withLock { cache }, for: words, now: now)
        let used = picked.relevant.map(\.id)
        queue.async { [self] in
            store.markUsed(used, at: now)
            refreshNow()
        }
        return ArisMemoryRecall.block(picked)
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
///   {"op": "list"}                    -> {"memories": [{"id","kind","subject","text","source","said","used"?,"via"?,"mark"?}], "auto": bool}
///   {"op": "delete", "id": "…"}       -> {"removed": bool}
///   {"op": "confirm", "id": "…"}      -> {"confirmed": bool}  (확인: a memory as sure as can be)
///   {"op": "clear", "confirm": "모두"} -> {"cleared": true}   (every memory, day note and summary, and memory.md)
///   {"op": "auto", "on": bool}        -> {"auto": bool}       (자동으로 기억하기)
/// Anything else is 400 with nothing touched. `audit`: the line for actions.log (never a memory's words).
enum ArisMemoryRoute {
    static let clearWord = "모두"

    static func handle(_ object: [String: Any], store: ArisMemoryStore) -> (status: Int, body: Data, audit: String?) {
        switch object["op"] as? String {
        case "list":
            // Where an imported memory came from, and whether it is an instruction (ArisMemoryImportStore).
            let extras = store.importExtras()
            let rows = store.all().map { r -> [String: Any] in
                var row: [String: Any] = ["id": r.id, "kind": r.kind.rawValue, "subject": r.subject, "text": r.text, "source": r.source.rawValue,
                                          "said": r.turnAt.timeIntervalSince1970, "confidence": r.confidence]
                if let used = r.lastUsedAt { row["used"] = used.timeIntervalSince1970 }
                if let via = extras[r.id]?.via { row["via"] = via }
                if let mark = extras[r.id]?.mark { row["mark"] = mark }
                return row
            }
            return ok(["memories": rows, "auto": store.learnsOnItsOwn], audit: nil)
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
            // The work memory's part of the page (일하면서 배운 것): ArisWorkRoute.
            // And the import from another AI (다른 AI에서 가져오기): ArisImportRoute.
            return ArisWorkRoute.handle(object, store: ArisWorkStore(memory: store)) ?? ArisImportRoute.handle(object, store: store) ?? bad()
        }
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }

    private static func bad() -> (status: Int, body: Data, audit: String?) { (400, Data("{}".utf8), nil) }
}
