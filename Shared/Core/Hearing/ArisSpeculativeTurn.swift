//
//  ArisSpeculativeTurn.swift
//  Aris (Shared/Core, Foundation only)
//
//  Runs ArisEndpointDriver's effects for one hands-free turn. At a plausible end it finalises the words (the second
//  listen, within its budget) and, when the gate lets the request go early, sends it while the microphone keeps
//  listening; its replies are held (ArisHeldStream). Voice that comes back before anything irreversible cancels it
//  (the connection is dropped: aris-agent abandons that turn) and the utterance goes on. At the firm end the turn
//  commits: the words and the held request are taken by the turn as if they had just been made.
//
//  The app wires in what it does (the hooks); the tests drive the same code with fakes.
//

import Foundation

@MainActor
final class ArisSpeculativeTurn<Reply: Sendable, Key: Equatable & Sendable> {
    struct Hooks {
        /// The words of the turn so far, final: the second listen within its budget. Nil: nothing to send.
        var finalWords: @MainActor (_ id: Int) async -> String?
        /// What the request would be sent as, when it may go early (ArisSpeculationGate, the router's verdict); nil: it waits.
        var requestKey: @MainActor (_ words: String) async -> Key?
        /// Sends the request.
        var ask: @MainActor (_ words: String, _ key: Key) -> AsyncStream<Reply>
        var kind: @MainActor (Reply) -> ArisReplyKind
        /// The turn is over (the app stops listening and takes the words with `committedWords`).
        var commit: @MainActor (_ speculation: Int?) -> Void
        /// A speculation was dropped because the user talked again.
        var cancelled: @MainActor (_ speculation: Int) -> Void = { _ in }
        var speculated: @MainActor (_ speculation: Int) -> Void = { _ in }
        /// The first reply that would be seen or heard arrived (held).
        var firstOutput: @MainActor (ContinuousClock.Instant) -> Void = { _ in }
    }

    private struct Speculation {
        let id: Int
        var words: String?
        var key: Key?
        var request: ArisHeldStream<Reply>?
        var work: Task<Void, Never>?
    }

    private(set) var driver: ArisEndpointDriver
    private let hooks: Hooks
    private var current: Speculation?
    /// Requests sent early, and those cancelled (for turns.jsonl and the tests).
    private(set) var requestsSent = 0
    private(set) var requestsCancelled = 0
    /// When a request that had been sent was last cancelled: aris-agent ends that turn when it sees the connection close,
    /// so the next request waits a moment (`settle`) rather than meet "still answering".
    private(set) var lastCancelAt: ContinuousClock.Instant?
    static var settle: Duration { .milliseconds(250) }

    init(driver: ArisEndpointDriver = ArisEndpointDriver(), hooks: Hooks) {
        self.driver = driver
        self.hooks = hooks
    }

    var committed: Bool { driver.phase == .committed }
    /// The turn committed on a speculation (its words, and perhaps its request, are ready to take).
    var committedSpeculation: Bool { committed && current != nil }
    /// The pending speculation's request said something that may have acted.
    var locked: Bool { current?.request?.locked ?? false }

    func observe(_ snapshot: ArisEndpointDriver.Snapshot) {
        run(driver.observe(snapshot))
    }

    /// The key was pressed again (or the turn ends for another reason).
    func finish() {
        run(driver.finish())
    }

    /// At commit: the words the speculation finalised (its work awaited, so a request it started is in place); nil when
    /// no speculation was committed.
    func committedWords() async -> String? {
        guard let speculation = current else { return nil }
        await speculation.work?.value
        return current?.id == speculation.id ? current?.words : nil
    }

    /// The held request, when it was sent for `key` (or it already acted, and must be the one used). Any other is
    /// cancelled. Once only.
    func takeRequest(for key: Key) -> AsyncStream<Reply>? {
        guard let request = current?.request else { return nil }
        current?.request = nil
        if current?.key == key || request.locked, let replies = request.take() { return replies }
        cancel(request)
        return nil
    }

    /// The turn ended without taking it (a local answer, a stop, a new turn): the request goes.
    func drop() {
        current?.work?.cancel()
        if let request = current?.request { cancel(request) }
        current = nil
    }

    private func run(_ effects: [ArisEndpointDriver.Effect]) {
        for effect in effects {
            switch effect {
            case .speculate(let id): speculate(id)
            case .cancel(let id):
                guard current?.id == id else { continue }
                drop()
                hooks.cancelled(id)
            case .commit(let id):
                if id == nil { drop() }
                hooks.commit(id)
            }
        }
    }

    private func speculate(_ id: Int) {
        drop()
        current = Speculation(id: id)
        hooks.speculated(id)
        current?.work = Task { @MainActor [weak self] in
            guard let self else { return }
            let words = await self.hooks.finalWords(id)
            guard self.current?.id == id, !Task.isCancelled else { return }
            self.current?.words = words
            guard let words, let key = await self.hooks.requestKey(words) else { return }
            // Cancelled while the router was asked, or the turn ended on another speculation: nothing goes.
            guard self.current?.id == id, !Task.isCancelled else { return }
            let request = ArisHeldStream(self.hooks.ask(words, key), kind: self.hooks.kind)
            request.onLock = { [weak self] in self?.locked(id) }
            request.onFirstOutput = { [weak self] at in self?.hooks.firstOutput(at) }
            self.requestsSent += 1
            self.current?.key = key
            self.current?.request = request
        }
    }

    private func locked(_ id: Int) {
        run(driver.reply(.action, id: id))
    }

    private func cancel(_ request: ArisHeldStream<Reply>) {
        guard !request.cancelled, !request.taken else { return }
        request.cancel()
        requestsCancelled += 1
        lastCancelAt = .now
    }
}
