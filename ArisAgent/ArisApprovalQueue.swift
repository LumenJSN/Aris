//
//  ArisApprovalQueue.swift
//  aris-agent
//
//  A background job's question waits ("parks") until the user is at the Mac. One left unanswered for a day expires,
//  and an expired question is a no.
//

import Foundation

struct ArisApprovalQueue {
    /// How long a parked question waits for the user (Claude's call, spec §5).
    static let lifetime: TimeInterval = 86_400

    private var parked: [String: Date] = [:]

    mutating func park(id: String, at: Date) {
        parked[id] = at
    }

    /// Answered (or otherwise gone): it will never expire.
    mutating func remove(_ id: String) {
        parked[id] = nil
    }

    func contains(_ id: String) -> Bool {
        parked[id] != nil
    }

    /// The questions older than `lifetime`, taken off the queue (each is reported once).
    mutating func expired(now: Date) -> [String] {
        let gone = parked.filter { now.timeIntervalSince($0.value) > Self.lifetime }.map(\.key).sorted()
        for id in gone { parked[id] = nil }
        return gone
    }

    /// The runner `key` was cancelled: its parked questions, taken off the queue.
    mutating func cancel(owner key: String) -> [String] {
        let gone = Self.owned(by: key, among: Array(parked.keys))
        for id in gone { parked[id] = nil }
        return gone
    }

    /// The question ids that belong to the runner `key` ("<key>/<id>"), sorted; never a longer key's.
    static func owned(by key: String, among ids: [String]) -> [String] {
        ids.filter { $0.hasPrefix(key + "/") }.sorted()
    }
}

/// A yes counts only for the card the agent made: the app sends back the details it showed, and they must be exactly
/// the agent's own (a card edited on its way, say in the inbox file, is refused). A no needs no match: it can only
/// stop something. A yes with changes (the owner's ②A) also echoes the card's text as finally shown, which must be the
/// card's own fields with exactly those changes, on fields the card has.
enum ArisShownCard {
    static func matches(allow: Bool, detail: String?, full: String?, expectedDetail: String, expectedFull: String?,
                        fields: [ArisCardField] = [], edits: [String: String] = [:], shown: String? = nil) -> Bool {
        guard allow else { return true }
        guard detail == expectedDetail && full == expectedFull else { return false }
        guard !edits.isEmpty else { return shown == nil }
        guard Set(edits.keys).isSubset(of: Set(fields.filter { !$0.fixed }.map(\.key))) else { return false }
        return shown == ArisCardEdit.shown(fields, ArisCardEdit.values(fields).merging(edits) { $1 })
    }
}

/// This run of aris-agent. Every runner key, confirm id and proposal id carries it, so a yes the app kept from an
/// earlier run (the agent restarted while a card was parked) can never answer a different question now.
enum ArisLaunch {
    static let nonce = String(UUID().uuidString.prefix(8))

    static func sharedKey(brain: String, model: String) -> String { "\(nonce)/\(brain)/\(model)" }

    static func taskKey(_ number: Int, brain: String, model: String) -> String { "task\(number)-\(nonce)/\(brain)/\(model)" }

    static func proposalId(_ number: Int) -> String { "proposal-\(nonce)/\(number)" }

    static func confirmId(_ number: Int) -> String { "c\(number)-\(nonce)" }
}

/// How a background task ends when its connection to the app closes. The app cancels a job on purpose with
/// POST /cancel; a connection that merely dropped (a long sleep, a network hiccup) while the app is still running
/// must not take a parked question with it. Only when the app's process is gone (quit, crashed) does a close cancel.
enum ArisTaskEnd {
    /// `appAlive`: the app's process (its pid and start time from /ask) still exists.
    static func cancelsOnClose(appAlive: Bool) -> Bool {
        !appAlive
    }

    /// Whether the app is still there: process `pid` exists and started at `started` (to the millisecond), so a pid
    /// reused by another process doesn't count. Anything unknown or unreadable counts as gone.
    static func isAlive(pid: Int32?, started: Double?) -> Bool {
        guard let pid, pid > 0, let started, let now = ArisProcessStart.of(pid: pid) else { return false }
        return abs(now - started) < 0.001
    }

    /// The app's id for a job: a UUID string, or nil.
    static func jobId(_ raw: Any?) -> String? {
        guard let text = raw as? String, UUID(uuidString: text) != nil else { return nil }
        return text
    }
}

/// Background tasks by the app's job id, and the jobs cancelled this launch (the last `remembered` of them). A cancel
/// is never lost: one that comes before its job registers is kept, and that job is refused when it does.
struct ArisJobBook<Owner: AnyObject> {
    /// How many cancelled ids are kept: far more than jobs that could still be on their way.
    static var remembered: Int { 1_000 }

    private var owners: [String: Owner] = [:]
    private var cancelled: Set<String> = []
    /// Cancelled ids, oldest first, to drop the oldest past `remembered`.
    private var cancelOrder: [String] = []

    var cancelledCount: Int { cancelled.count }

    /// False when the job was already cancelled: it must not start.
    mutating func register(_ job: String, owner: Owner) -> Bool {
        guard !cancelled.contains(job) else { return false }
        owners[job] = owner
        return true
    }

    /// Records the cancel; returns the job's task when it is running.
    mutating func cancel(_ job: String) -> Owner? {
        if cancelled.insert(job).inserted {
            cancelOrder.append(job)
            while cancelOrder.count > Self.remembered { cancelled.remove(cancelOrder.removeFirst()) }
        }
        return owners.removeValue(forKey: job)
    }

    func isCancelled(_ job: String) -> Bool {
        cancelled.contains(job)
    }

    /// A task ended: its job is no longer running (a cancel for it is still recorded).
    mutating func forget(owner: Owner) {
        owners = owners.filter { $0.value !== owner }
    }
}
