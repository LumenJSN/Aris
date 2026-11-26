//
//  ArisStallWatch.swift
//  Aris
//
//  Logs any stall of the main thread over 2 s (QA BUG-37: Aris froze whole and nothing said so). A background timer
//  posts a beat to the main queue every half second; a beat not answered within the threshold is logged once as a
//  stall with what Aris was doing (the turn's phase, as the main thread last wrote it), once more past 10 s that it
//  is still stuck, and again with its length when the main thread comes back. Always on, displays asleep too (a
//  stall that starts then would keep the wake-up from ever restarting it; the 1.3.1 listener hang ran for hours).
//  No stacks are sampled and nothing is captured. ArisStallClock is the pure half (tested).
//

import Foundation
import os

struct ArisStallClock: Equatable {
    static let threshold: TimeInterval = 2
    /// A stall this long is said once more: still stuck.
    static let stuck: TimeInterval = 10

    enum Event: Equatable {
        case none
        /// Post a beat to the main thread now.
        case post
        /// The beat has waited this long, past the threshold (said once per stall).
        case stalled(TimeInterval)
        /// The same stall has gone on past `stuck` (said once per stall).
        case stillStuck(TimeInterval)
        /// The main thread answered after a stall of this long.
        case recovered(TimeInterval)
    }

    /// When the beat waiting for the main thread was posted.
    private(set) var postedAt: TimeInterval?
    private(set) var reported = false
    private(set) var reportedStuck = false

    /// The timer fired at `now`.
    mutating func tick(now: TimeInterval) -> Event {
        guard let postedAt else {
            self.postedAt = now
            return .post
        }
        let waited = now - postedAt
        guard waited > Self.threshold else { return .none }
        if !reported {
            reported = true
            return .stalled(waited)
        }
        guard waited > Self.stuck, !reportedStuck else { return .none }
        reportedStuck = true
        return .stillStuck(waited)
    }

    /// The main thread ran the beat at `now`.
    mutating func answered(now: TimeInterval) -> Event {
        guard let postedAt else { return .none }
        let waited = now - postedAt
        let stalled = reported || waited > Self.threshold
        self.postedAt = nil
        reported = false
        reportedStuck = false
        return stalled ? .recovered(waited) : .none
    }
}

final class ArisStallWatch: @unchecked Sendable {
    static let shared = ArisStallWatch()

    private let queue = DispatchQueue(label: "com.lumenjsn.aris.stall-watch", qos: .utility)
    private var clock = ArisStallClock()
    private var timer: DispatchSourceTimer?
    private var doing = "idle"

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Starts watching (once).
    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    /// What Aris is doing, for the stall's line ("idle", "listening", "thinking", "speaking", "failed"): written by the
    /// main thread when the turn's phase changes, read here while the main thread may be stuck.
    func note(doing: String) {
        queue.async { [self] in self.doing = doing }
    }

    private func tick() {
        switch clock.tick(now: Self.now) {
        case .post:
            DispatchQueue.main.async { [weak self] in
                let at = Self.now
                self?.queue.async { self?.answered(at: at) }
            }
        case .stalled(let waited):
            Log.app.error("main thread stalled: no answer for \(waited, format: .fixed(precision: 1), privacy: .public) s (Aris was \(self.doing, privacy: .public))")
        case .stillStuck(let waited):
            Log.app.error("main thread still stuck: no answer for \(waited, format: .fixed(precision: 1), privacy: .public) s (Aris was \(self.doing, privacy: .public))")
        case .none, .recovered:
            break
        }
    }

    private func answered(at: TimeInterval) {
        if case .recovered(let waited) = clock.answered(now: at) {
            Log.app.error("main thread was stalled for \(waited, format: .fixed(precision: 1), privacy: .public) s")
        }
    }
}
