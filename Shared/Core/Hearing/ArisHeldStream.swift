//
//  ArisHeldStream.swift
//  Aris (Shared/Core, Foundation only)
//
//  A request's replies, started before the turn is sure to want them (the speculative turn). Every reply is held, in
//  order, until the turn takes the stream; nothing is shown or said before. Each reply is sorted (ArisReplyKind): the
//  first that may have acted locks the stream (it can no longer be cancelled without leaving something done) and says
//  so through `onLock`, so the turn commits at once. `cancel()` ends the source, which drops the request's connection:
//  aris-agent then abandons that turn (`abandon(owner:)`).
//

import Foundation

@MainActor
final class ArisHeldStream<Element: Sendable> {
    /// A reply that may have acted came: no cancel from here on.
    private(set) var locked = false
    private(set) var cancelled = false
    private(set) var taken = false
    /// Replies received so far (held or passed on).
    private(set) var received = 0
    /// When the first reply that would be seen or heard arrived (held or not).
    private(set) var firstOutputAt: ContinuousClock.Instant?
    var onLock: (() -> Void)?
    var onFirstOutput: ((ContinuousClock.Instant) -> Void)?

    private let output: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation
    private let pump = PumpBox()

    init(_ source: AsyncStream<Element>, kind: @escaping @MainActor (Element) -> ArisReplyKind) {
        (output, continuation) = AsyncStream.makeStream(of: Element.self, bufferingPolicy: .unbounded)
        let box = pump
        // The turn that took the stream stopped reading it (an answer, a stop): the request goes with it.
        continuation.onTermination = { _ in box.cancel() }
        let continuation = continuation
        pump.set(Task { @MainActor [weak self] in
            for await element in source {
                guard !Task.isCancelled else { break }
                self?.sort(kind(element))
                continuation.yield(element)
            }
            continuation.finish()
        })
    }

    /// The replies, those held first; once only, and never after a cancel.
    func take() -> AsyncStream<Element>? {
        guard !taken, !cancelled else { return nil }
        taken = true
        return output
    }

    /// Drops the request: its source ends (and with it the connection) and nothing held is ever read.
    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        pump.cancel()
        continuation.finish()
    }

    private func sort(_ kind: ArisReplyKind) {
        received += 1
        if kind == .output, firstOutputAt == nil {
            let now = ContinuousClock.now
            firstOutputAt = now
            onFirstOutput?(now)
        }
        if kind == .action, !locked {
            locked = true
            onLock?()
        }
    }
}

/// The pump's task, cancelled from the stream's termination handler (any thread).
private final class PumpBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var done = false

    func set(_ task: Task<Void, Never>) {
        let cancelNow = lock.withLock { () -> Bool in
            self.task = task
            return done
        }
        if cancelNow { task.cancel() }
    }

    func cancel() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            done = true
            return self.task
        }
        task?.cancel()
    }
}
