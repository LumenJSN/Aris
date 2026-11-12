//
//  ArisController+Arrange.swift
//  Aris
//
//  "엑셀 4개 켜서 4등분": Aris says what it's doing while aris-agent opens the windows and lays them out
//  (the app is sandboxed, so moving other apps' windows is the agent's job). No AI, no confirmation.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "arrange")

extension ArisController {
    /// The reply said: the acknowledgement, then (in the past tense) that it's done, or why it failed.
    func arrange(_ app: String, count: Int, korean: Bool) async -> String {
        let intent = ArisIntent.arrange(app: app, count: count)
        let acknowledgement = intent.acknowledgement(korean: korean) ?? ""
        async let failure = ArisAgentClient.arrange(app: app, count: count)
        stats?.firstSound(at: .now)
        session = session.answering(acknowledgement)
        await speak { await self.speaker.speak(acknowledgement) }
        let message = await failure
        // Stopped while the windows were laid out: the notch is not this turn's any more (audit turn-2).
        guard !Task.isCancelled else { return "" }
        guard let message else {
            // Done: the notch says so in the past tense (QA BUG-14), without saying it a second time.
            let done = intent.doneLine(korean: korean) ?? acknowledgement
            session = session.answering(done)
            return done
        }
        log.error("arrange failed: \(message, privacy: .public)")
        // macOS's and aris-tools' own English never reaches the reply (QA BUG-13).
        let why = ArisIntent.arrangeFailure(message, app: app, korean: korean)
        let reply = korean ? "창을 나누지 못했어요. \(why)" : "I couldn't lay out the windows. \(why)"
        session = session.answering(reply)
        await speak { await self.speaker.speak(reply) }
        return reply
    }
}
