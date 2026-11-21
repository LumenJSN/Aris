//
//  ArisAgentClient+DayEnd.swift
//  Aris
//
//  The one part of the day-end summary (ArisDayEnd) the sandboxed app can't read itself: which of Aris's schedules run
//  tomorrow, and which were due today and how each went (aris-agent's POST /dayend, ArisDayEndRoute), and with the day
//  in review on, the record's digest of the day (counts only). An agent that
//  doesn't answer, or an older one that doesn't know the question, leaves the part out.
//

import Foundation

extension ArisAgentClient {
    private static let dayEndURL = URL(string: "http://127.0.0.1:23351/dayend")!

    /// Aris's schedules for the summary of `span`'s day: tomorrow's runs, each with its first time, and the ones due
    /// today with how they went by `now` (nil from an agent that doesn't say). Nil when the agent didn't answer.
    /// `record`: also ask for the record's digest of the day (the day in review, ArisRecapSwitch); nil in the answer
    /// when the agent keeps no record (Core 2 off) or is older.
    static func dayEndSchedules(_ span: ArisDaySpan, now: Date, record: Bool = false)
        async -> (tomorrow: [ArisDayEndFacts.Schedule], today: [ArisDayEndFacts.Routine]?, record: ArisRecordDigest?)? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: dayEndURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        var question: [String: Any] = [
            "from": span.tomorrow.timeIntervalSince1970, "to": span.afterTomorrow.timeIntervalSince1970,
            "day": span.today.timeIntervalSince1970, "now": now.timeIntervalSince1970,
        ]
        if record { question["record"] = true }
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(question))
        // ArisNoStore.session: its sockets live in this process, which is what the agent's check of the caller reads.
        guard let (data, response) = try? await ArisNoStore.session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let tomorrow = ArisDayEndFacts.schedules(from: data) else { return nil }
        let digest = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ArisRecordDigest.from($0["record"]) }
        return (tomorrow, ArisDayEndFacts.routines(from: data), digest)
    }
}
