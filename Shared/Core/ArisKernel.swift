//
//  ArisKernel.swift
//  Aris
//
//  The kernel's runner (ARCHITECTURE.md 3.1): it feeds events through ArisKernelState.reduce, keeps the event ring,
//  and runs the effects it owns: a confirm card's wait is a continuation here, resumed exactly once, by the user's answer,
//  by another card covering it, or with `.cancelled` when its turn ends. Cancelling a turn's work is the app's
//  (`cancelWork`), since the app holds the task.
//

import Foundation

@MainActor
final class ArisKernel {
    private(set) var state = ArisKernelState()
    private(set) var ring: ArisEventRing
    /// Runs `.cancelWork`: the app cancels the turn's task.
    var cancelWork: (ArisTurnID) -> Void = { _ in }
    /// Seconds of system uptime, for the ring.
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    /// Outcomes that came before their waiter asked for them, by showing.
    private var outcomes: [ArisCardKey: ArisCardOutcome] = [:]
    /// The waiter suspended on each showing (nil resumes it without an outcome: its own check ended the wait).
    private var waiters: [ArisCardKey: CheckedContinuation<ArisCardOutcome?, Never>] = [:]

    init(ringCapacity: Int = 512) {
        ring = ArisEventRing(capacity: ringCapacity)
    }

    var current: ArisTurnID? { state.current }

    @discardableResult
    func send(_ event: ArisEvent) -> [ArisEffect] {
        let (next, effects) = ArisKernelState.reduce(state, event)
        state = next
        // Every write would flood the ring: only the dropped ones are worth keeping.
        if case .sessionWrite = event, effects == [.write] {} else {
            ring.append(.init(at: clock(), turn: state.current, event: event, effects: effects))
        }
        for effect in effects { run(effect) }
        return effects
    }

    private func run(_ effect: ArisEffect) {
        switch effect {
        case .cancelWork(let turn): cancelWork(turn)
        case .resumeCard(let key, let outcome): deliver(outcome, to: key)
        case .write, .dropWrite: break
        }
    }

    // MARK: - Turns

    /// Opens the next turn; the one before is over.
    func openTurn(_ origin: ArisTurnOrigin) -> ArisTurnID {
        send(.turnOpened(origin))
        return state.latest
    }

    /// Ends `turn` (nil: the current one) without a successor; a turn already over is left as it is.
    func endTurn(_ turn: ArisTurnID? = nil, _ why: ArisTurnEnd) {
        guard let turn = turn ?? state.current else { return }
        send(.turnEnded(turn, why))
    }

    /// Whether a write from code working for `turn` goes through (it is dropped when that turn is over).
    func admitsWrite(from turn: ArisTurnID?) -> Bool {
        send(.sessionWrite(from: turn)) == [.write]
    }

    // MARK: - Card waits

    /// The card `card` is on screen for `turn` (nil: the current one) and waits for its answer.
    func showCard(_ card: String, turn: ArisTurnID?) -> ArisCardKey {
        let key = ArisCardKey(card: card, turn: turn ?? state.current, serial: state.nextCard)
        send(.cardShown(card: card, turn: turn))
        return key
    }

    /// The user's answer to the card on screen. False when no wait was open for it.
    @discardableResult
    func answerCard(_ card: String, allow: Bool) -> Bool {
        !send(.cardAnswered(card: card, allow: allow)).isEmpty
    }

    /// The outcome the showing already has, if any, without waiting (taking it: a showing has one outcome, read once).
    func takeOutcome(_ key: ArisCardKey) -> ArisCardOutcome? {
        outcomes.removeValue(forKey: key)
    }

    /// Whether the showing still waits for an answer (none came, it was not covered, its turn did not end).
    func isWaiting(_ key: ArisCardKey) -> Bool { state.card == key }

    /// The waiter is done with the showing: an answer that comes later answers nothing.
    func closeCard(_ key: ArisCardKey) {
        send(.cardClosed(key))
        outcomes[key] = nil
    }

    /// Waits for the showing's outcome. `check` is looked at every `tick` for what only time can tell (a deadline,
    /// spoken words holding still, the agent no longer waiting); when it says the wait is over this returns nil and the
    /// showing stays open for a later wait. Cancelling the waiting task ends the showing with `.cancelled`.
    func waitForCard(_ key: ArisCardKey, tick: Duration, until check: @escaping @MainActor () async -> Bool) async -> ArisCardOutcome? {
        if let early = takeOutcome(key) { return early }
        guard isWaiting(key) else { return .cancelled }
        let ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tick)
                guard !Task.isCancelled else { return }
                if await check() { self?.release(key); return }
            }
        }
        defer { ticker.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Settled between the check above and now: resumed at once.
                if let early = outcomes.removeValue(forKey: key) { return continuation.resume(returning: early) }
                guard isWaiting(key) else { return continuation.resume(returning: .cancelled) }
                waiters[key] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.send(.cardAbandoned(key)) }
        }
    }

    /// Waits at most `tick` for the showing's outcome; nil when none came in that time (the waiter then looks at its
    /// own clocks and waits again). An answer still resumes it at once.
    func waitForCard(_ key: ArisCardKey, atMost tick: Duration) async -> ArisCardOutcome? {
        await waitForCard(key, tick: tick) { true }
    }

    private func deliver(_ outcome: ArisCardOutcome, to key: ArisCardKey) {
        if let waiter = waiters.removeValue(forKey: key) { return waiter.resume(returning: outcome) }
        outcomes[key] = outcome
    }

    /// The waiter's own check ended this wait: it goes on without an outcome.
    private func release(_ key: ArisCardKey) {
        waiters.removeValue(forKey: key)?.resume(returning: nil)
    }
}
