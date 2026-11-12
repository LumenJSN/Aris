//
//  ArisAgentClient+DayEnd.swift
//  Aris
//
//  The one part of the day-end summary (ArisDayEnd) the sandboxed app can't read itself: which of Aris's schedules run
//  tomorrow, and which were due today and how each went (aris-agent's POST /dayend, ArisDayEndRoute). An agent that
//  doesn't answer, or an older one that doesn't know the question, leaves the part out.
//

import Foundation

extension ArisAgentClient {
    private static let dayEndURL = URL(string: "http://127.0.0.1:23351/dayend")!

    /// Aris's schedules for the summary of `span`'s day: tomorrow's runs, each with its first time, and the ones due
    /// today with how they went by `now` (nil from an agent that doesn't say). Nil when the agent didn't answer.
    static func dayEndSchedules(_ span: ArisDaySpan, now: Date) async -> (tomorrow: [ArisDayEndFacts.Schedule], today: [ArisDayEndFacts.Routine]?)? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: dayEndURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified([
            "from": span.tomorrow.timeIntervalSince1970, "to": span.afterTomorrow.timeIntervalSince1970,
            "day": span.today.timeIntervalSince1970, "now": now.timeIntervalSince1970,
        ]))
        // URLSession.shared: its sockets live in this process, which is what the agent's check of the caller reads.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let tomorrow = ArisDayEndFacts.schedules(from: data) else { return nil }
        return (tomorrow, ArisDayEndFacts.routines(from: data))
    }
}
