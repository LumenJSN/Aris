//
//  ArisSilenceWatch.swift
//  aris-agent
//
//  The runner's turn clock (ArisSilenceClock) on its queue: one timer at the clock's deadline, looked at again when it
//  fires, so a turn whose brain keeps talking never ends and hearing a line costs no new timer. Every call is made on
//  `queue`.
//

import Foundation

final class ArisSilenceWatch {
    private let queue: DispatchQueue
    let limits: ArisTurnLimits
    private var clock: ArisSilenceClock?
    private var timer: DispatchWorkItem?
    private var expire: ((ArisSilenceClock.Why) -> Void)?
    /// For the tests: what "now" is.
    private let now: () -> Date

    init(queue: DispatchQueue, limits: ArisTurnLimits, now: @escaping () -> Date = Date.init) {
        self.queue = queue
        self.limits = limits
        self.now = now
    }

    /// A turn begins: `expired` is called once, on `queue`, when it is over (unless stopped first).
    func start(_ expired: @escaping (ArisSilenceClock.Why) -> Void) {
        clock = ArisSilenceClock(limits: limits, at: now())
        expire = expired
        arm()
    }

    var running: Bool { clock != nil }

    /// The brain wrote something.
    func heard() {
        clock?.heard(at: now())
    }

    /// Nothing ends for `seconds` from now (a card, a judge, a long conversion); 0 ends a hold.
    func hold(for seconds: TimeInterval) {
        guard clock != nil else { return }
        clock?.hold(for: seconds, at: now())
        arm()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        clock = nil
        expire = nil
    }

    /// When it would end now, and why (nil when no turn is timed).
    var deadline: (at: Date, why: ArisSilenceClock.Why)? { clock?.deadline }

    private func arm() {
        timer?.cancel()
        guard let clock else { return }
        let wait = max(0.01, clock.deadline.at.timeIntervalSince(now()))
        let item = DispatchWorkItem { [weak self] in self?.check() }
        timer = item
        queue.asyncAfter(deadline: .now() + wait, execute: item)
    }

    private func check() {
        guard let clock else { return }
        guard let why = clock.expired(at: now()) else { return arm() }
        let expired = expire
        stop()
        expired?(why)
    }
}
