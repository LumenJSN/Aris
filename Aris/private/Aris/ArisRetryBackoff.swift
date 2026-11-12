//
//  ArisRetryBackoff.swift
//  Aris
//
//  When to try again after something failed (a model download with no network): the wait doubles from `first` up to
//  `longest`, and a success clears it. Pure, so the timing is tested without a clock.
//

import Foundation

struct ArisRetryBackoff {
    let first: Duration
    let longest: Duration
    private var failures = 0
    private var notBefore: ContinuousClock.Instant?

    init(first: Duration, longest: Duration) {
        self.first = first
        self.longest = longest
    }

    /// Whether a try is allowed now (the first always is; after a failure, once the wait has passed).
    func mayTry(at now: ContinuousClock.Instant) -> Bool {
        notBefore.map { now >= $0 } ?? true
    }

    /// The wait after this many failures: first, 2 × first, 4 × first … up to longest.
    func wait(afterFailures count: Int) -> Duration {
        var wait = first
        for _ in 1..<max(count, 1) {
            wait *= 2
            if wait >= longest { return longest }
        }
        return min(wait, longest)
    }

    mutating func failed(at now: ContinuousClock.Instant) {
        failures += 1
        notBefore = now + wait(afterFailures: failures)
    }

    mutating func succeeded() {
        failures = 0
        notBefore = nil
    }
}
