//
//  ArisDeadline.swift
//  Aris
//
//  Work with a time limit, so a stuck system call can't freeze Aris: the caller gets the result, or `TimedOut` once
//  the limit has passed. The work runs in a task of its own and is not waited for after the deadline (a task group
//  would wait for it). Stopping the caller stops the work too (audit turn-2: a turn that the user stopped went on
//  waiting for the router and then spoke, because the cancel never reached the work inside).
//  Foundation only, so it is tested.
//

import Foundation

enum ArisDeadline {
    struct TimedOut: Error {}

    /// Runs `work`, giving up after `limit`.
    /// `cancelsWork`: on the deadline, or when the caller is cancelled, the work is cancelled too (a start that may
    /// still open the microphone); false for work that must run to its end anyway (a stop, which gives the device back).
    @MainActor
    static func within<T>(_ limit: Duration, cancelsWork: Bool = true, _ work: @escaping @MainActor () async throws -> T) async throws -> T {
        // A caller already stopped never starts work that may be stopped (a stopped turn does not speak or ask on).
        if cancelsWork { try Task.checkCancellation() }
        let race = Race<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.begin(continuation, limit: limit, cancelsWork: cancelsWork, work: work)
            }
        } onCancel: {
            Task { @MainActor in race.callerCancelled(cancelsWork: cancelsWork) }
        }
    }

    /// One run: the work against the clock; the continuation is resumed once, by whichever ends first.
    @MainActor
    private final class Race<T> {
        private var continuation: CheckedContinuation<T, Error>?
        private var running: Task<Void, Never>?
        private var cancelled = false

        func begin(_ continuation: CheckedContinuation<T, Error>, limit: Duration, cancelsWork: Bool,
                   work: @escaping @MainActor () async throws -> T) {
            self.continuation = continuation
            // The caller was stopped before the work began: it never starts.
            if cancelled, cancelsWork {
                resume(.failure(CancellationError()))
                return
            }
            running = Task { @MainActor in
                do { self.resume(.success(try await work())) } catch { self.resume(.failure(error)) }
            }
            Task { @MainActor in
                try? await Task.sleep(for: limit)
                if self.resume(.failure(TimedOut())), cancelsWork { self.running?.cancel() }
            }
        }

        /// The caller no longer wants the result: it hears so at once, and the work is told to stop unless it must finish.
        func callerCancelled(cancelsWork: Bool) {
            cancelled = true
            guard cancelsWork else { return }
            running?.cancel()
            resume(.failure(CancellationError()))
        }

        /// True when this call resumed the continuation (the first call does; later ones do nothing).
        @discardableResult
        private func resume(_ result: Result<T, Error>) -> Bool {
            guard let continuation else { return false }
            self.continuation = nil
            continuation.resume(with: result)
            return true
        }
    }
}
