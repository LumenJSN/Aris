//
//  ArisTaskFollow.swift
//  aris-agent
//
//  Where a background task's replies go: down its /ask stream while the app holds it, and once that stream is gone
//  (the app quit or restarted, or the helper restarted and took the task back) into the inbox under the job's id: its
//  result, its failure, a card it parks, each with a nudge (com.lumenjsn.aris.inbox). So the app hears how a job ended
//  by its id, not by an open connection, and a job no longer ends because the app went away. A card shown live that
//  still waits when the stream goes is put in the inbox then, so the app asks it again after a relaunch, and POST /tasks
//  says the job waits on it. A job's result or failure goes to the inbox once: a second one for the same job is dropped.
//

import Foundation

final class ArisTaskFollow {
    let job: String
    let title: String
    private let lock = NSLock()
    private var live: ((ArisAgentReply) -> Void)?
    private var file: String?
    private let inbox: URL
    /// For the tests: what nudges the app (nil: nothing).
    private let nudge: (() -> Void)?
    /// Whether a card (by its id) still waits for the user (ArisAgentRunner.isWaiting); and the cards shown live, newest last.
    private let cardWaits: (String) -> Bool
    private var shownLive: [ArisConfirmation] = []

    init(job: String, title: String, inbox: URL, live: ((ArisAgentReply) -> Void)?, nudge: (() -> Void)? = ArisTaskFollow.nudgeApp,
         cardWaits: @escaping (String) -> Bool = { _ in false }) {
        self.job = job
        self.title = title
        self.inbox = inbox
        self.live = live
        self.nudge = nudge
        self.cardWaits = cardWaits
        if !job.isEmpty, live != nil { Self.registry.withLock { Self.following[job] = Weak(self) } }
    }

    /// The stream to the app is gone: from now on, the inbox. A card it showed that still waits goes there now.
    func detach() {
        let open = lock.withLock { () -> [ArisConfirmation] in
            live = nil
            defer { shownLive = [] }
            return shownLive
        }.filter { cardWaits($0.id) }
        for card in open { put(.confirm(card)) }
    }

    /// The card this job waits on now, if it showed one live that is still unanswered.
    var waitingCard: ArisConfirmation? {
        lock.withLock { shownLive }.last { cardWaits($0.id) }
    }

    var attached: Bool { lock.withLock { live != nil } }

    /// One reply of the task's runner.
    func deliver(_ reply: ArisAgentReply) {
        let send = lock.withLock { () -> ((ArisAgentReply) -> Void)? in
            if case .file(let path) = reply { file = path }
            if live != nil, case .confirm(let card) = reply { shownLive.append(card) }
            if reply.isLast { shownLive = [] }
            return live
        }
        if let send { return send(reply) }
        put(reply)
    }

    /// One reply into the inbox, nudging the app. A job's second result or failure is dropped (it was reported).
    private func put(_ reply: ArisAgentReply) {
        if reply.isLast, !job.isEmpty, ArisInbox.hasEnd(job: job, file: inbox) {
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: job \(job.prefix(8)) already reported; its second report is dropped\n".utf8))
            return
        }
        let entry: ArisInboxEntry
        switch reply {
        case .answer(let text):
            entry = ArisInboxEntry(id: UUID(), date: Date(), kind: .result, schedule: nil, title: title, text: text, file: lock.withLock { file }, confirm: nil, job: job.isEmpty ? nil : job)
        case .failure(let line):
            entry = ArisInboxEntry(id: UUID(), date: Date(), kind: .failure, schedule: nil, title: title, text: line, file: nil, confirm: nil, job: job.isEmpty ? nil : job)
        case .confirm(let ask):
            entry = ArisInboxEntry(id: UUID(), date: Date(), kind: .confirm, schedule: nil, title: title, text: "", file: nil,
                                   confirm: ArisInboxEntry.Question(id: ask.id, title: ask.title, detail: ask.detail, full: ask.full), job: job.isEmpty ? nil : job)
        default:
            return
        }
        ArisInbox.append(entry, file: inbox)
        nudge?()
    }

    /// The jobs followed on a live stream, by id (POST /tasks: the card one waits on).
    private static let registry = NSLock()
    nonisolated(unsafe) private static var following: [String: Weak] = [:]
    private final class Weak {
        weak var follow: ArisTaskFollow?
        init(_ follow: ArisTaskFollow) { self.follow = follow }
    }

    /// The card job `job` waits on, shown live and still unanswered.
    static func waitingCard(job: String) -> ArisConfirmation? {
        let follow = registry.withLock { () -> ArisTaskFollow? in
            following = following.filter { $0.value.follow != nil }
            return following[job]?.follow
        }
        return follow?.waitingCard
    }

    static let nudgeApp: () -> Void = {
        DistributedNotificationCenter.default().postNotificationName(.init("com.lumenjsn.aris.inbox"), object: nil, userInfo: nil, deliverImmediately: true)
    }
}

/// Cards a task waited on when the helper stopped, asked again after it started (ArisTaskRecovery's waitCard): the
/// same title and details under a new id (an id from the last launch never names anything now). The user's answer lets
/// the task go on (`carryOn`); nobody's answer within a day is a no, as a parked card's is: it expires on a wall-clock
/// timer and whenever the app asks (expire). Either way the answer goes to actions.log and the card leaves the inbox.
final class ArisRecoveredCards {
    static let shared = ArisRecoveredCards()

    struct Waiting {
        let state: ArisTaskState
        let card: ArisTaskCard
        let at: Date
    }

    private let lock = NSLock()
    private var waiting: [String: Waiting] = [:]
    private var count = 0
    /// What runs once a card is settled: the task, the card, the answer and how it came ("yes", "no", "expired"; set by
    /// ArisTaskTakeBack; the tests set their own).
    var carryOn: (ArisTaskState, ArisTaskCard, Bool, String) -> Void = { _, _, _, _ in }
    /// actions.log's line for each answer, and the inbox its card was put in (set by ArisTaskTakeBack).
    var audit: (String) -> Void = { _ in }
    var inbox: URL?

    /// Parks `card` for `state` again under a new id, which it returns. It expires a day later (wall clock: a Mac
    /// asleep meanwhile is past it on waking).
    func park(_ state: ArisTaskState, card: ArisTaskCard, now: Date = Date()) -> ArisTaskCard {
        let parked = lock.withLock { () -> ArisTaskCard in
            count += 1
            let fresh = ArisTaskCard(id: "r\(count)-\(ArisLaunch.nonce)/\(state.job.prefix(8))", title: card.title, detail: card.detail, full: card.full)
            waiting[fresh.id] = Waiting(state: state, card: fresh, at: now)
            return fresh
        }
        let left = max(0, ArisApprovalQueue.lifetime - Date().timeIntervalSince(now))
        DispatchQueue.global(qos: .utility).asyncAfter(wallDeadline: .now() + left + 1) { [weak self] in self?.expire() }
        return parked
    }

    func isWaiting(_ id: String, now: Date = Date()) -> Bool {
        lock.withLock { waiting[id].map { now.timeIntervalSince($0.at) <= ArisApprovalQueue.lifetime } ?? false }
    }

    func card(_ id: String) -> ArisTaskCard? { lock.withLock { waiting[id]?.card } }

    func waitingJob(_ job: String) -> Bool { waitingCard(job: job) != nil }

    /// The card job `job` waits on (unexpired), if any.
    func waitingCard(job: String, now: Date = Date()) -> ArisTaskCard? {
        lock.withLock { waiting.values.first { $0.state.job == job && now.timeIntervalSince($0.at) <= ArisApprovalQueue.lifetime }?.card }
    }

    /// The user answered `id` (POST /confirm): false when it isn't one of these. An expired one is a no.
    @discardableResult
    func answer(_ id: String, allow: Bool, now: Date = Date()) -> Bool {
        guard let found = lock.withLock({ waiting.removeValue(forKey: id) }) else { return false }
        let inTime = now.timeIntervalSince(found.at) <= ArisApprovalQueue.lifetime
        settle(found, allow: allow && inTime, how: inTime ? (allow ? "yes" : "no") : "expired")
        return true
    }

    /// Every card older than a day is a no nobody gave. How many were.
    @discardableResult
    func expire(now: Date = Date()) -> Int {
        let gone = lock.withLock { () -> [Waiting] in
            let old = waiting.values.filter { now.timeIntervalSince($0.at) > ArisApprovalQueue.lifetime }
            old.forEach { waiting[$0.card.id] = nil }
            return old
        }
        gone.sorted { $0.at < $1.at }.forEach { settle($0, allow: false, how: "expired") }
        return gone.count
    }

    private func settle(_ found: Waiting, allow: Bool, how: String) {
        if let inbox { ArisInbox.removeQuestions([found.card.id], file: inbox) }
        let object = ["answer": how, "question": found.card.id, "job": found.state.job]
        audit(String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data("{}".utf8), as: UTF8.self))
        carryOn(found.state, found.card, allow, how)
    }

    /// The job was cancelled: its waiting card goes (true when it had one), and leaves the inbox.
    @discardableResult
    func cancel(job: String) -> Bool {
        let ids = lock.withLock { () -> [String] in
            let ids = waiting.filter { $0.value.state.job == job }.map(\.key)
            ids.forEach { waiting[$0] = nil }
            return ids
        }
        if let inbox, !ids.isEmpty { ArisInbox.removeQuestions(Set(ids), file: inbox) }
        return !ids.isEmpty
    }
}
