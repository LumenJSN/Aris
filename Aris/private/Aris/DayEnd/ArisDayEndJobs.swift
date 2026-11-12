//
//  ArisDayEndJobs.swift
//  Aris
//
//  The jobs of the day for the day-end summary (ArisDayEnd): the ones the notch still lists (each with
//  how it ended) and, for those it no longer lists (only the newest few are kept, and none across a restart), their
//  results in the 기록 list. A job in both is counted once. One the user stopped themselves is listed as not done. Also how
//  the agent's answer about Aris's schedules (ArisDayEndRoute) is read. Foundation only, so it is tested.
//

import Foundation

enum ArisDayEndJobs {
    /// `jobs`: the controller's list, oldest first. `parked`: the questions waiting as 확인 대기 (those jobs are their
    /// cards' rows). `history`: the 기록 list. Newest first.
    static func facts(jobs: [ArisJob], parked: Set<String>, history: [ArisHistoryEntry], span: ArisDaySpan, now: Date) -> [ArisDayEndFacts.Job] {
        let listed = jobs.filter { span.isToday($0.created, now: now) }.sorted { $0.created > $1.created }.compactMap { job -> ArisDayEndFacts.Job? in
            guard let outcome = outcome(job.state, parked: parked) else { return nil }
            return ArisDayEndFacts.Job(id: job.id.uuidString, title: job.title, outcome: outcome)
        }
        let known = Set(jobs.map(\.id))
        let kept = history.filter { entry in
            entry.isTask && span.isToday(entry.date, now: now) && !(entry.job.map(known.contains) ?? false)
        }.sorted { $0.date > $1.date }.map { entry in
            ArisDayEndFacts.Job(id: entry.id.uuidString, title: entry.heard, outcome: failure(entry.reply).map { .failed($0) } ?? .done)
        }
        return listed + kept
    }

    /// How a job in the notch's list stands; nil when it isn't a row of its own (its question is parked as 확인 대기).
    static func outcome(_ state: ArisJobState, parked: Set<String>) -> ArisDayEndFacts.Job.Outcome? {
        switch state {
        case .queued, .running: return .running
        case .awaitingApproval(let id): return parked.contains(id) ? nil : .asking
        case .done: return .done
        case .failed(let message): return .failed(ArisJobFailure.reason(message))
        case .cancelled: return .stopped
        }
    }

    /// The reason in a 기록 entry that says its job wasn't finished (ArisJobFailure.shown wrote it); nil for a result.
    static func failure(_ reply: String) -> String? {
        for korean in [true, false] {
            let lead = String(ArisJobFailure.shown(reason: "", korean: korean).dropLast())
            guard reply.hasPrefix(lead) else { continue }
            return String(reply.dropFirst(lead.count).drop { ":. \n".contains($0) })
        }
        return nil
    }
}

extension ArisDayEndFacts {
    /// Tomorrow's schedule runs as aris-agent answers POST /dayend ({"schedules": [{"title", "at", "every"?, "once"?}]});
    /// nil when the answer isn't one (an older agent doesn't know the question), and the part is left out.
    static func schedules(from data: Data) -> [Schedule]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let listed = object["schedules"] as? [[String: Any]] else { return nil }
        return listed.compactMap { item in
            guard let title = item["title"] as? String, let at = item["at"] as? Double else { return nil }
            return Schedule(title: title, at: Date(timeIntervalSince1970: at), every: item["every"] as? Int, repeats: item["once"] as? Bool != true)
        }
    }

    /// The schedules that were due today, in the same answer ({"today": [{"title", "at", "state", "once"?}]}); nil when
    /// the agent didn't say (an older one), and they are left out of the plan.
    static func routines(from data: Data) -> [Routine]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let listed = object["today"] as? [[String: Any]] else { return nil }
        return listed.compactMap { item in
            guard let title = item["title"] as? String, let at = item["at"] as? Double, let state = (item["state"] as? String).flatMap({ Routine.State(rawValue: $0) }) else { return nil }
            return Routine(title: title, at: Date(timeIntervalSince1970: at), state: state, repeats: item["once"] as? Bool != true)
        }
    }
}
