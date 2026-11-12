//
//  ArisTaskRace.swift
//  Aris
//
//  "Wait for this task, but not longer than that": the per-turn screenshot (3 s at send), gesture frames (1.5 s) and
//  the parked gesture result (2.5 s). A task group can't do it: after the timer wins, the group still waits for the
//  child that awaits the task, and awaiting a task's value ignores cancellation. Here whichever finishes first
//  answers; the timer is cancelled when the value wins; the task itself keeps running for anyone else who waits on
//  it. Pure, so the tests run it.
//

import Foundation

enum ArisTaskRace {
    /// The task's value, or nil once `limit` has passed.
    static func value<T: Sendable>(of task: Task<T?, Never>, within limit: Duration) async -> T? {
        let once = Once()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let timer = Task {
                try? await Task.sleep(for: limit)
                if once.claim() { continuation.resume(returning: nil) }
            }
            Task {
                let value = await task.value
                if once.claim() {
                    timer.cancel()
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func claim() -> Bool {
            lock.withLock {
                guard !done else { return false }
                done = true
                return true
            }
        }
    }
}
