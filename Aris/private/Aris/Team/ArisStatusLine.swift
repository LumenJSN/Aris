//
//  ArisStatusLine.swift
//  Aris
//
//  The one line that says what Aris is doing: "생각 중…", "검색 중…", "2개 작업 중", "허락 기다리는 중".
//  Pure: it reads state (the main turn's phase and the jobs), never a timer.
//

import Foundation

enum ArisMainPhase: Equatable { case idle, listening, thinking, searching, speaking }

enum ArisStatusLine {
    /// Approval beats the main turn, which beats the background jobs. Nil when there is nothing to say.
    static func text(phase: ArisMainPhase, jobs: [ArisJob], korean: Bool) -> String? {
        let waiting = jobs.filter { if case .awaitingApproval = $0.state { return true } else { return false } }.count
        if waiting > 0 {
            return (korean ? "허락 기다리는 중" : "Waiting for your OK") + " · \(waiting)"
        }
        switch phase {
        case .thinking: return korean ? "생각 중…" : "Thinking…"
        case .searching: return korean ? "검색 중…" : "Searching…"
        case .idle, .listening, .speaking: break
        }
        let running = jobs.filter { job in
            switch job.state {
            case .queued, .running: return true
            default: return false
            }
        }.count
        guard running > 0 else { return nil }
        if korean { return "\(running)개 작업 중" }
        return running == 1 ? "1 job running" : "\(running) jobs running"
    }

    /// The closed-notch pill is for background jobs and approvals only; the main turn lives in the open notch's tag.
    static func pillText(jobs: [ArisJob], korean: Bool) -> String? {
        text(phase: .idle, jobs: jobs, korean: korean)
    }

    /// When the pill's clock started: the oldest job not yet finished. Nil when none is.
    static func since(jobs: [ArisJob]) -> Date? {
        jobs.filter { job in
            switch job.state {
            case .queued, .running, .awaitingApproval: return true
            case .done, .failed, .cancelled: return false
            }
        }.map(\.created).min()
    }

    /// The drivers' status strings (ArisAgentStatus): the web search one is searching, anything else is thinking.
    static func phase(fromStatus status: String) -> ArisMainPhase {
        status.contains("웹 검색") ? .searching : .thinking
    }
}

/// The pill's last word when the jobs are over (A6): "끝났어요" and a check for 1.6 s while the star cheers, then the
/// pill tucks up and the star hops home. Only when the last of them finished done: a failure is said aloud instead.
/// With the name the user gave (ArisUserName, N10): "Alex님, 끝났어요".
enum ArisPillFinish {
    static let hold: TimeInterval = 1.6

    static func text(name: String?) -> String {
        guard let name else {
            return String(localized: "team.pill.done", defaultValue: "Done", bundle: ArisTeamCopy.bundle, locale: ArisTeamCopy.locale,
                          comment: "The pill's last word when the background jobs are over")
        }
        return String(localized: "team.pill.done.named", defaultValue: "Done, \(name)", bundle: ArisTeamCopy.bundle, locale: ArisTeamCopy.locale,
                      comment: "The pill's last word when the background jobs are over; the argument is the user's name")
    }

    /// `justFinished`: the controller's few-second flash after a job ends. The newest finished job decides.
    static func showsDone(jobs: [ArisJob], justFinished: Bool) -> Bool {
        guard justFinished, !jobs.contains(where: { !isFinished($0) }), let last = jobs.last(where: isFinished) else { return false }
        if case .done = last.state { return true }
        return false
    }

    private static func isFinished(_ job: ArisJob) -> Bool {
        switch job.state {
        case .done, .failed, .cancelled: true
        case .queued, .running, .awaitingApproval: false
        }
    }
}
