//
//  ArisSteerDesk.swift
//  aris-agent
//
//  The instructions waiting for each running task's next turn (ArisSteerQueue), shared by the task tool (which adds
//  them) and the task's runner (which takes them when its turn answers). Locked: the tool runs off the runners' queues.
//  In memory only: a helper that starts again has none, and a task taken back after a restart runs as handed over.
//

import Foundation

final class ArisSteerDesk: @unchecked Sendable {
    static let shared = ArisSteerDesk()

    private let lock = NSLock()
    private var queue = ArisSteerQueue()

    /// Held for `job`'s next turn: `.queued`, or `.refused` with why.
    func hold(_ note: String, job: String) -> ArisTaskSteer.Outcome {
        lock.withLock {
            switch queue.adding(note, job: job) {
            case .success(let next):
                queue = next
                return .queued
            case .failure(let refusal):
                return .refused(refusal.why)
            }
        }
    }

    /// The notes waiting for `job`, taken (none: empty).
    func take(job: String) -> [String] {
        lock.withLock {
            let (next, notes) = queue.taking(job: job)
            queue = next
            return notes
        }
    }

    /// A task that ended: whatever still waited for it goes.
    func drop(job: String) { _ = take(job: job) }
}
