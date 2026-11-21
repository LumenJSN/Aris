//
//  ArisAXBudget.swift
//  aris-agent
//
//  How long Aris's own engine waits on an app's Accessibility. An app that hangs (a beach ball) answers nothing, and
//  every question to it used to wait the system's default six seconds, element after element, so one look could hold
//  a turn for minutes. Now each element answers within `perCall`, a look stops at its limit (what it read so far kept,
//  marked cut short), and a few timeouts in a row end it as "the app is not responding": the brain gets that reason,
//  never a hang. Pure apart from the clock.
//

import ApplicationServices
import Foundation

final class ArisAXBudget {
    /// Seconds one element may take to answer.
    static let perCall: Float = 1.0
    /// The quick question before any call: does the app answer at all?
    static let probe: Float = 1.5
    /// A look's own limit (within the call's).
    static let lookLimit: TimeInterval = 8
    /// Timeouts in a row that mean the app has stopped answering.
    static let giveUpAfter = 3

    static let notRespondingCode = "APP_NOT_RESPONDING"
    static let notRespondingLine = "the app is not responding (it didn't answer Accessibility in time), so nothing was read or done there; " +
        "say so, and try again once it responds"

    private let deadline: Date
    private let now: () -> Date
    private(set) var timeoutsInARow = 0
    private(set) var unresponsive = false

    init(limit: TimeInterval, now: @escaping () -> Date = Date.init) {
        self.now = now
        deadline = now().addingTimeInterval(limit)
    }

    /// One call's error: a timeout counts, anything else (an answer, even "no such attribute") resets the count.
    func record(_ error: AXError) {
        if error == .cannotComplete {
            timeoutsInARow += 1
            if timeoutsInARow >= Self.giveUpAfter { unresponsive = true }
        } else {
            timeoutsInARow = 0
        }
    }

    /// No more questions: the app stopped answering, or the look's time is up.
    var exhausted: Bool { unresponsive || now() >= deadline }
}
