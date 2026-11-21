//
//  ArisTaskFollowing.swift
//  Aris
//
//  A background job is followed by its id, not by the stream it was handed over on: the helper keeps each job's
//  journal, takes a job back when it starts again (resumed in the brain's own session, or restarted told what was
//  done), and leaves how it ended in the inbox under the job's id. So when a job's stream is gone (the app restarted,
//  the helper restarted) the app asks the helper (POST /tasks) what became of it: one still going is shown as picked
//  up again and waits for the inbox; only one the helper doesn't have is cut off. Pure, Foundation only.
//

import Foundation

/// One job as the helper knows it (POST /tasks).
struct ArisTaskSeen: Equatable {
    enum State: String {
        case running, waiting, done, failed, cancelled, lost, unknown
    }

    let job: UUID
    let state: State
    /// "resumed" or "restarted" when the helper took it back after a restart.
    let recovered: String?
    /// Its last line (why it failed; an answer's text isn't kept).
    let line: String?
    /// The card it waits on (the id POST /confirm takes), when it waits on one.
    var card: String? = nil

    /// It still goes on in the helper: its end comes through the inbox.
    var goesOn: Bool { state == .running || state == .waiting }

    /// POST /tasks's body; nil when it isn't one (an older helper answers 404, so nothing is followed).
    static func decode(_ data: Data) -> [ArisTaskSeen]? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = body["tasks"] as? [[String: Any]] else { return nil }
        return rows.compactMap { row in
            guard let job = (row["job"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return ArisTaskSeen(job: job, state: State(rawValue: row["state"] as? String ?? "") ?? .unknown,
                                recovered: row["recovered"] as? String, line: row["line"] as? String,
                                card: (row["card"] as? [String: Any])?["id"] as? String)
        }
    }
}

enum ArisTaskFollowing {
    /// How often, and how far apart, the helper is asked after a stream was lost (it may be starting again: launchd
    /// brings it back within seconds).
    static let attempts = 8
    static let spacing: Duration = .seconds(2)

    /// Of the jobs the last run left unfinished, the ones the helper still has (they go on), and the rest (cut off).
    static func split(_ records: [ArisJobRecord], seen: [ArisTaskSeen]?) -> (goOn: [ArisJobRecord], lost: [ArisJobRecord]) {
        guard let seen else { return ([], records) }
        let going = Set(seen.filter(\.goesOn).map(\.job))
        // A Claude Code teammate's job is a terminal window: the helper never had it.
        return (records.filter { !$0.claudeCode && going.contains($0.id) }, records.filter { $0.claudeCode || !going.contains($0.id) })
    }

    /// The job's row while the helper carries on with it after a restart.
    static func pickedUpLine(recovered: String?, korean: Bool) -> String {
        if recovered == "restarted" {
            return korean ? "Aris가 다시 시작되어 처음부터 이어서 하는 중" : "Picked up again after Aris restarted"
        }
        return korean ? "Aris가 다시 시작되어 이어서 하는 중" : "Carrying on after Aris restarted"
    }

    /// Said once after a relaunch for the jobs that go on.
    static func pickedUpSaid(_ records: [ArisJobRecord], korean: Bool) -> String {
        guard let first = records.first else { return "" }
        if records.count == 1 {
            return korean ? "Aris가 다시 시작됐지만 ‘\(first.title)’ 일은 이어서 하고 있어요. 끝나면 알려 드릴게요."
                : "Aris restarted, but ‘\(first.title)’ is still going. I'll tell you when it's done."
        }
        return korean ? "Aris가 다시 시작됐지만 맡긴 일 \(records.count)개는 이어서 하고 있어요. 끝나면 알려 드릴게요."
            : "Aris restarted, but \(records.count) jobs are still going. I'll tell you when they're done."
    }

    /// What an inbox item of a job means for that job.
    enum Outcome: Equatable {
        case done(String, file: String?)
        case failed(String)
        case asks
        case other
    }

    /// An inbox item for a job this app already shows as finished: a second result or failure (it was reported), which
    /// is acknowledged and never said again.
    static func isRepeat(kind: String, finished: Bool) -> Bool {
        finished && (kind == "result" || kind == "failure")
    }

    static func outcome(kind: String, text: String, file: String?) -> Outcome {
        switch kind {
        case "result": return .done(text, file: file)
        case "failure": return .failed(text)
        case "confirm": return .asks
        default: return .other
        }
    }
}
