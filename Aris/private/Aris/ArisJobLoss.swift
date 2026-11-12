//
//  ArisJobLoss.swift
//  Aris
//
//  What a background job's stream failure means, from the transport's own error code (never the words): the agent
//  wasn't running when the job was handed over, the agent isn't answering, or the stream dropped mid-way (the agent
//  crashed or launchd restarted it, and the job's process went with it). The notch says which, by the job's name.
//

import Foundation

enum ArisJobLoss {
    /// The line for a task stream that failed with `code`; `started`: the stream had delivered something before.
    /// Nil when the code says nothing about the agent (then the error's own description is shown).
    static func line(title: String, code: URLError.Code, started: Bool) -> String? {
        switch code {
        case .cannotConnectToHost, .cannotFindHost:
            return started ? dropped(title) : ArisAgentCopy.notRunning
        case .timedOut:
            return ArisAgentCopy.notAnswering
        case .networkConnectionLost:
            return dropped(title)
        default:
            return nil
        }
    }

    /// The stream dropped while the job ran: the job is gone with the agent's process.
    static func dropped(_ title: String, english: Bool = ArisUIWords.english) -> String {
        ArisUIWords.text("에이전트가 다시 시작되면서 '\(title)' 작업이 끊겼어요. 다시 맡겨 주세요.",
                         "Aris's helper restarted and the job “\(title)” was cut off. Please hand it over again.", english: english)
    }
}

/// What a job that didn't finish says and leaves in the 기록 tab (audit team-3: the user heard only "<제목>, 못 끝냈어요",
/// the agent's own reason, such as a login that expired, stayed in the done tray, and the hand-out's 기록 entry kept
/// "맡았어요" for good). The reason is the agent's line, cut to one short paragraph. Pure.
enum ArisJobFailure {
    /// The most of a reason that is said and kept.
    static let longestReason = 200

    /// The agent's reason as one short paragraph: its first lines up to the limit, cut at a word.
    static func reason(_ message: String) -> String {
        let flat = message.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        guard flat.count > longestReason else { return flat }
        let cut = flat.prefix(longestReason)
        let whole = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return whole.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// What Aris says: the job by name, that it wasn't finished, and why. A reason that already names the job (the
    /// agent's own "… '제목' 작업이 끊겼어요") is said as it is.
    static func said(title: String, reason: String, korean: Bool) -> String {
        guard !reason.isEmpty else { return korean ? "\(title), 못 끝냈어요." : "I couldn't finish: \(title)." }
        if reason.contains(title) { return reason }
        return korean ? "\(title), 못 끝냈어요. \(reason)" : "I couldn't finish: \(title). \(reason)"
    }

    /// The 기록 entry's words for that job.
    static func shown(reason: String, korean: Bool) -> String {
        guard !reason.isEmpty else { return korean ? "못 끝냈어요." : "Not finished." }
        return korean ? "못 끝냈어요: \(reason)" : "Not finished: \(reason)"
    }

    /// The job's stream ended with neither an answer nor an error.
    static func cutOff(korean: Bool) -> String {
        korean ? "끝나기 전에 연결이 끊겼어요. 다시 맡겨 주세요." : "It was cut off before it finished. Hand it over again."
    }
}
