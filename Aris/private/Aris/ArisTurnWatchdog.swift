//
//  ArisTurnWatchdog.swift
//  Aris
//
//  A routed turn that hears nothing back ends with a short failure line instead of hanging (BUG-25c reopened: "응"
//  went to the brain and nothing came back). Only silence from the very start counts: once the brain has said anything
//  (a status, a card, a word) its own stream rules apply. Pure but for the clock.
//

import Foundation

enum ArisTurnWatchdog {
    /// How long a turn waits for the first word from the agent.
    /// Long enough for a brain that thinks before its first status (a hard question on a slow model), short of the
    /// request's own 130 s idle limit.
    static let firstWord: Duration = .seconds(90)

    static func line(korean: Bool) -> String {
        korean ? "답이 오지 않아서 멈췄어요. 다시 말해 주세요." : "No answer came, so I stopped. Please ask again."
    }

    /// `stream`, or `failure` and the end when it says nothing at all within `within`.
    static func guarded<Element: Sendable>(_ stream: AsyncStream<Element>, within: Duration, failure: Element) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let heard = ArisTurnHeard()
            let forward = Task {
                for await element in stream {
                    guard heard.hear() else { return }
                    continuation.yield(element)
                }
                continuation.finish()
            }
            let timer = Task {
                try? await Task.sleep(for: within)
                guard !Task.isCancelled, heard.expire() else { return }
                continuation.yield(failure)
                continuation.finish()
                forward.cancel()
            }
            continuation.onTermination = { _ in
                forward.cancel()
                timer.cancel()
            }
        }
    }
}

/// Whether a guarded stream said anything before its watchdog ended it.
final class ArisTurnHeard: @unchecked Sendable {
    private let lock = NSLock()
    private var any = false, over = false

    /// Marks it heard; false once the watchdog ended it.
    func hear() -> Bool { lock.withLock { guard !over else { return false }; any = true; return true } }

    /// Ends it when nothing was heard; true then.
    func expire() -> Bool { lock.withLock { guard !any, !over else { return false }; over = true; return true } }
}
