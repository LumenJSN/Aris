//
//  ArisWhyDesk.swift
//  aris-agent
//
//  Where the agent's turn code meets the why-record: four calls, one line each where they are made.
//  - turn(…): at POST /ask, once everything about the turn is decided. A why-question from the Aris app itself is
//    answered here (no AI), from the record; any other conversation turn opens its own record.
//  - asking(…): each AI that is asked for the turn.
//  - heard(…): every line sent to the app on the turn's stream.
//  - audited(…): every line the gate writes to actions.log.
//  The book (ArisWhyBook) is held under a lock, since the audit comes from every queue. What the answer reads besides
//  the record (the activity log, where each memory came from) is passed in, so the tests run without the user's files.
//  Foundation only (tested); the agent's own one is ArisWhyDesk.shared (ArisWhyLive).
//

import Foundation

/// Reading the activity log ("한 일") for the lines one turn left.
enum ArisWhyActivity {
    /// What the AI's own commands logged in a conversation (ARIS_JOB), and what Aris ran for agy or the app logged.
    static let conversationJob = "대화"
    static let arisJob = "Aris"
    static let appWorker = "user"

    /// The summaries of the entries from `from` to `to` that a conversation turn made (`app`: instead, the ones the
    /// app logged for what it did itself), oldest first, each safe to say back; nil when the log can't be read.
    /// An entry that was undone since is left out.
    static func summaries(in file: URL, from: Date, to: Date, app: Bool = false) -> [String]? {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        guard let data = ArisPrivateFile.read(file) else { return nil }
        let formatter = ISO8601DateFormatter()
        return data.split(separator: 0x0A).compactMap { line -> String? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let date = (object["date"] as? String).flatMap(formatter.date(from:)), date >= from, date <= to,
                  object["undone"] as? Bool != true, let summary = object["summary"] as? String else { return nil }
            let job = object["job"] as? String, worker = object["worker"] as? String
            let fromApp = job == arisJob && worker == appWorker
            let fromTurn = job == conversationJob || (job == arisJob && worker != appWorker)
            guard app ? fromApp : fromTurn else { return nil }
            return ArisWhySafe.kept(summary, limit: 80)
        }
    }
}

final class ArisWhyDesk: @unchecked Sendable {
    /// What /ask knows about the caller and the turn, beside ArisWhyStart.
    struct Caller: Equatable {
        /// The Aris app itself asked (ArisPeer), and it is a conversation turn, not a background job.
        var fromApp = true
        var task = false
        /// The turn carries screen images or the screen's text: its words are about what is on screen.
        var showsScreen = false
        /// The turn's conversation holds the screen or outside text.
        var tainted = false
    }

    private let lock = NSLock()
    private var book = ArisWhyBook()
    private let tools: String
    private let log: URL
    private let memories: @Sendable () -> [ArisMemoryRecord]
    private let clock: @Sendable () -> Date
    /// When this agent started keeping records.
    private let since: Date

    /// `tools`: where aris-tools is. `log`: the activity log. `memories`: the memory store's rows as they are now.
    init(tools: String, log: URL, memories: @escaping @Sendable () -> [ArisMemoryRecord], clock: @escaping @Sendable () -> Date = { Date() }) {
        self.tools = tools
        self.log = log
        self.memories = memories
        self.clock = clock
        since = clock()
    }

    /// The records as they are now (tests).
    var records: [ArisWhyRecord] { lock.withLock { book.records } }

    /// The turn on `stream`. True when it was a why-question answered from the record: `answer` is then called once
    /// with the text, off the caller's queue, and nothing else of the turn should run. False for every other turn,
    /// whose record (a conversation turn from the app only) is now open.
    func turn(_ start: ArisWhyStart, context: String?, caller: Caller, on stream: AnyHashable, answer: @escaping @Sendable (String) -> Void) -> Bool {
        guard caller.fromApp, !caller.task else { return false }
        let now = clock()
        let own = ArisMemoryText.ownWords(start.request)
        if !caller.showsScreen, let focus = ArisWhyIntent.parse(own) {
            let plan = lock.withLock { () -> ArisWhyPlan in
                let plan = book.plan(focus, lastHeard: ArisWhyMatch.lastHeard(in: context))
                if case .explain(let record) = plan { book = book.explaining(own, from: record) }
                return plan
            }
            if plan != .brain {
                let asking = ArisWhyAsking(focus: focus, korean: ArisMemoryText.isKorean(own), tainted: caller.tainted, handsFree: start.handsFree, now: now)
                DispatchQueue.global(qos: .userInitiated).async { [self] in answer(text(plan, asking: asking)) }
                return true
            }
        }
        // The same rule the turn's memories were picked under (ArisMemoryLearning.mayRecall).
        var start = start
        start.memoryAllowed = ArisMemoryLearning.mayRecall(fromApp: caller.fromApp, task: caller.task, untrusted: caller.tainted, outsideConversation: start.outside,
                                                           screenSeen: start.screen, handsFree: start.handsFree, images: caller.showsScreen, screenText: caller.showsScreen)
        lock.withLock { book = book.beginning(start, on: stream, at: now) }
        return false
    }

    func asking(_ brain: ArisBrain, instead requested: ArisBrain, on stream: AnyHashable) {
        lock.withLock { book = book.asking(brain, instead: requested, on: stream) }
    }

    func heard(_ reply: ArisAgentReply, on stream: AnyHashable) {
        // Pieces of the answer are never kept: nothing to do for them, on every stream there is.
        if case .delta = reply { return }
        let now = clock()
        lock.withLock { if book.open[stream] != nil { book = book.hearing(reply, on: stream, at: now) } }
    }

    /// A line for actions.log from `key`. Only a conversation's own AI process counts (its key opens with this launch's
    /// nonce): a background job's lines and the shared routes' are not this turn's for sure, so they are left out.
    func audited(_ line: String, key: String) {
        guard key.hasPrefix(ArisLaunch.nonce + "/"), lock.withLock({ !book.open.isEmpty }),
              let fact = ArisWhyAuditFact.read(line, tools: tools, log: log) else { return }
        lock.withLock { book = book.audited(fact) }
    }

    /// A line for actions.log that its writer knows is a conversation turn's own, not a background job's (a route that
    /// can tell: it holds the turn it is answering).
    func gated(_ line: String) {
        guard lock.withLock({ !book.open.isEmpty }), let fact = ArisWhyAuditFact.read(line, tools: tools, log: log) else { return }
        lock.withLock { book = book.audited(fact) }
    }

    /// The answer for `plan` (never `.brain`), with what the activity log and the memory store add. Blocks on files.
    func text(_ plan: ArisWhyPlan, asking: ArisWhyAsking) -> String {
        switch plan {
        case .explain(let record):
            // The log keeps whole seconds (cut, never rounded up): from the second the turn began in, to its end.
            let done = ArisWhyActivity.summaries(in: log, from: Self.second(of: record.at), to: record.ended ?? asking.now)
            return ArisWhyAnswer.text(record, evidence: ArisWhyEvidence(done: done, sources: sources(of: record)), asking: asking)
        case .unrecorded(let heard):
            let latest = lock.withLock { book.records.last }
            let from = max(latest?.ended ?? since, asking.now.addingTimeInterval(-Self.appWindow))
            let appDid = ArisWhyActivity.summaries(in: log, from: Self.second(of: from), to: asking.now, app: true) ?? []
            return ArisWhyAnswer.unrecorded(heard: heard, appDid: appDid, latest: latest, asking: asking)
        case .nothing, .brain:
            return ArisWhyAnswer.nothing(since: since, asking: asking)
        }
    }

    private static func second(of date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }

    /// How far back the app's own logged changes are looked for when the turn before isn't in the record.
    static let appWindow: TimeInterval = 300

    /// Where each of the record's memories came from, for the ones still in the store with the same words.
    private func sources(of record: ArisWhyRecord) -> [String: ArisMemorySource] {
        guard !record.memories.isEmpty else { return [:] }
        let wanted = Set(record.memories)
        var found: [String: ArisMemorySource] = [:]
        for memory in memories() {
            let line = String(ArisMemoryRecall.line(memory).dropFirst(2))
            if wanted.contains(line) { found[line] = memory.source }
        }
        return found
    }
}
