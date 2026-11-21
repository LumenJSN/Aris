//
//  ArisController+Report.swift
//  Aris
//
//  What Aris says when a job it handed out is done: one or two sentences a colleague would say, the result that
//  matters first, worded by the conversation's brain from the job's result and the conversation's last turns (the
//  helper's POST /report-line, a sealed one-shot that never holds the conversation's own process). The job's own line
//  is said when no such line comes in time. The full result stays on its card and in the reader, as before.
//

import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisAgentClient {
    private static let reportLineURL = URL(string: "http://127.0.0.1:23351/report-line")!

    /// The worded line, or nil (the helper didn't answer, or had no brain to word it).
    static func reportLine(title: String, result: String, recent: String, brain: String, korean: Bool) async -> String? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var request = URLRequest(url: reportLineURL, timeoutInterval: ArisReportWording.wait)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(["title": title, "result": result, "recent": recent,
                                                                                    "brain": brain, "korean": korean]))
        guard let (data, response) = try? await ArisNoStore.session.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["line"] as? String
    }
}

extension ArisController {
    /// The line said for a finished job (see the file's note).
    func colleagueLine(for job: ArisJob, result: String, own: String) async -> String {
        let korean = ArisSpeech.language(of: job.title) == "ko-KR"
        let worded = await ArisAgentClient.reportLine(title: job.title, result: result, recent: ArisReportWording.recent(history),
                                                      brain: Defaults[.arisBrain], korean: korean)
        log.notice("a finished job's line: \(worded == nil ? "its own" : "worded", privacy: .public)")
        return ArisReportWording.said(worded: worded, own: own)
    }
}
