//
//  ArisWorkerQueue.swift
//  Aris
//
//  Which jobs may run now: up to `cap` at once, the rest wait in the order they came. A job parked on a question
//  for the user steps out of the count (it may wait a day), and comes back when they answers.
//

import Foundation

struct ArisWorkerQueue {
    var cap: Int
    private(set) var running: [UUID] = []
    private var waiting: [UUID] = []
    /// Parked on a question for the user: not counted against the cap.
    private(set) var paused: [UUID] = []

    init(cap: Int = 3) {
        self.cap = cap
    }

    /// Adds jobs; returns the ones that start now (the rest wait).
    mutating func admit(_ ids: [UUID]) -> [UUID] {
        var started: [UUID] = []
        for id in ids {
            if running.count < cap {
                running.append(id)
                started.append(id)
            } else {
                waiting.append(id)
            }
        }
        return started
    }

    /// A running job ended (done, failed or cancelled): frees its slot and returns the next waiting job, now running.
    /// Does nothing for a job that isn't running.
    mutating func finished(_ id: UUID) -> UUID? {
        // A parked job held no slot: it just leaves.
        if let index = paused.firstIndex(of: id) {
            paused.remove(at: index)
            return nil
        }
        guard let index = running.firstIndex(of: id) else { return nil }
        running.remove(at: index)
        guard running.count < cap, !waiting.isEmpty else { return nil }
        let next = waiting.removeFirst()
        running.append(next)
        return next
    }

    /// A running job parks on a question: its slot goes to the next waiting job, which is returned (now running).
    mutating func pause(_ id: UUID) -> UUID? {
        guard let index = running.firstIndex(of: id) else { return nil }
        running.remove(at: index)
        paused.append(id)
        guard running.count < cap, !waiting.isEmpty else { return nil }
        let next = waiting.removeFirst()
        running.append(next)
        return next
    }

    /// The user answered: the job runs again at once (its AI is already running), even over the cap for a while;
    /// nothing new starts until the count is back under it.
    mutating func resume(_ id: UUID) {
        guard let index = paused.firstIndex(of: id) else { return }
        paused.remove(at: index)
        running.append(id)
    }

    /// Drops a waiting job so it never starts. A running job ends through `finished`.
    mutating func cancel(_ id: UUID) {
        waiting.removeAll { $0 == id }
    }
}
