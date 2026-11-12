//
//  ArisCardListenLog.swift
//  Aris
//
//  What the log says when a confirm card can't listen for a spoken yes or no (the card then waits for a click, Y or N).
//  Pure (tested).
//

import Foundation

/// How it is logged that a card couldn't listen for a spoken yes or no. On a Mac whose speech model is still being
/// prepared (a new install, or no model for the language yet) that happens at every card and is expected: it is said
/// once, as a notice, and not again until listening has worked. Anything else is an error each time (VM run
/// 2026-11-10, bug 7: an error line per card on a Mac that was working as it should). Pure.
struct ArisCardListenLog: Equatable {
    enum Level: Equatable { case error, notice, silent }

    /// The "model is still getting ready" notice was written and listening hasn't worked since.
    private(set) var saidPreparing = false

    /// Whether `message` is the listener's "the speech model is still getting ready" line, in either language.
    static func isModelPreparing(_ message: String) -> Bool {
        message == ArisListenerWords.modelPreparing(english: true) || message == ArisListenerWords.modelPreparing(english: false)
    }

    /// How a failed start with `message` is logged, and the log's state after it.
    func failed(_ message: String) -> (level: Level, next: ArisCardListenLog) {
        guard Self.isModelPreparing(message) else { return (.error, self) }
        return (saidPreparing ? .silent : .notice, ArisCardListenLog(saidPreparing: true))
    }

    /// Listening started: the model is there, so a later "still getting ready" is news again.
    func started() -> ArisCardListenLog { ArisCardListenLog() }
}
