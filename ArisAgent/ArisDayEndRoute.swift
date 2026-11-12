//
//  ArisDayEndRoute.swift
//  aris-agent
//
//  POST /dayend {"from": <seconds>, "to": <seconds>, "day"?: <seconds>, "now"?: <seconds>}
//    ->  {"schedules": [{"title", "at", "every"?, "once"?}], "today"?: [{"title", "at", "state", "once"?}]}
//  The one part of the notch's day-end summary (ArisDayEnd, "오늘 정리해 줘") the sandboxed app can't read itself:
//  which of Aris's schedules will run tomorrow (`from` up to `to`), and when first; and, when the app also names the
//  day being wrapped up (`day`, its first second; it ends at `from`), which were due in it and how each went by `now`:
//  done, failed, running, or pending (missed, or its time still ahead). Only titles, times and that one word leave
//  here, never a job's prompt. Reading only: nothing is run, changed or logged. Only the Aris app itself may ask
//  (main.swift's isAppItself). The summary is written by the app from facts alone, so no AI is told anything about it
//  and none is needed for it.
//

import Foundation

enum ArisDayEndRoute {
    struct Run: Equatable {
        let title: String
        /// Its first run inside the window.
        let at: Date
        /// It runs again this many seconds later, still inside the window (an "every N" schedule).
        let every: Int?
        /// A one-time schedule: something asked for once, where the others come back (a routine).
        var once = false
    }

    /// A schedule that was due in the day being wrapped up, and how its run went.
    struct Due: Equatable {
        let title: String
        /// When it was due that day.
        let at: Date
        /// "done", "failed", "running", or "pending" (it hasn't run that day: missed, or its time is still ahead).
        let state: String
        var once = false
    }

    /// The longest window answered: the summary asks about one day.
    static let longestWindow: TimeInterval = 2 * 86_400

    /// The window a request names, in seconds since 1970; nil when it isn't one day or so, forwards.
    static func window(_ object: [String: Any]) -> (from: Date, to: Date)? {
        guard let from = object["from"] as? Double, let to = object["to"] as? Double, to > from, to - from <= longestWindow else { return nil }
        return (Date(timeIntervalSince1970: from), Date(timeIntervalSince1970: to))
    }

    /// Each schedule's first run from `from` up to `to`, earliest first. A schedule whose next run is earlier is
    /// followed along its rule until it reaches the window or ends (a one-time job).
    static func runs(_ jobs: [ArisScheduledJob], from: Date, to: Date, calendar: Calendar) -> [Run] {
        jobs.compactMap { job -> Run? in
            guard var next = job.nextRun else { return nil }
            if case .every(let seconds) = job.rule {
                let step = TimeInterval(max(ArisSchedule.minimumEvery, seconds))
                if next < from { next = next.addingTimeInterval(((from.timeIntervalSince(next)) / step).rounded(.up) * step) }
                guard next < to else { return nil }
                return Run(title: job.title, at: next, every: next.addingTimeInterval(step) < to ? Int(step) : nil)
            }
            // A daily or weekly rule reaches any day within eight steps.
            var steps = 0
            while next < from, steps < 8, let later = ArisSchedule.next(job.rule, after: next, calendar: calendar) {
                next = later
                steps += 1
            }
            var once = false
            if case .once = job.rule { once = true }
            return next >= from && next < to ? Run(title: job.title, at: next, every: nil, once: once) : nil
        }.sorted { $0.at < $1.at }
    }

    /// The schedules due from `day` up to `end` (the day being wrapped up), earliest first, each with how it went by
    /// `now`. One that repeats every few minutes all day is no thing to finish and is left out. A one-time schedule
    /// that already ran has left the store: its result is in the app's 기록 list, which the summary reads itself.
    static func due(_ jobs: [ArisScheduledJob], day: Date, end: Date, now: Date, calendar: Calendar) -> [Due] {
        jobs.compactMap { job -> Due? in
            let at: Date?
            var once = false
            switch job.rule {
            case .every: return nil
            case .once(let date): at = date; once = true
            case .daily, .weekly: at = ArisSchedule.next(job.rule, after: day.addingTimeInterval(-1), calendar: calendar)
            }
            guard let at, at >= day, at < end else { return nil }
            let ran = job.lastRun.map { $0 >= day && $0 <= max(now, end) } ?? false
            let state = job.runningSince != nil ? "running" : !ran ? "pending" : job.lastFailed == true ? "failed" : "done"
            return Due(title: job.title, at: at, state: state, once: once)
        }.sorted { $0.at < $1.at }
    }

    /// The day a request names besides its window: from `day` up to the window's start, a day or so; nil when it names none.
    static func day(_ object: [String: Any], from: Date) -> (day: Date, now: Date)? {
        guard let day = object["day"] as? Double, let now = object["now"] as? Double else { return nil }
        let length = from.timeIntervalSince1970 - day
        guard length > 0, length <= longestWindow else { return nil }
        return (Date(timeIntervalSince1970: day), Date(timeIntervalSince1970: now))
    }

    static func body(jobs: [ArisScheduledJob], from: Date, to: Date, calendar: Calendar, today: (day: Date, now: Date)? = nil) -> Data {
        let listed = runs(jobs, from: from, to: to, calendar: calendar).map { run -> [String: Any] in
            var item: [String: Any] = ["title": run.title, "at": run.at.timeIntervalSince1970]
            if let every = run.every { item["every"] = every }
            if run.once { item["once"] = true }
            return item
        }
        var answer: [String: Any] = ["schedules": listed]
        if let today {
            answer["today"] = due(jobs, day: today.day, end: from, now: today.now, calendar: calendar).map { due -> [String: Any] in
                var item: [String: Any] = ["title": due.title, "at": due.at.timeIntervalSince1970, "state": due.state]
                if due.once { item["once"] = true }
                return item
            }
        }
        return (try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// The answer for the schedules stored under `home`; nil for a request that names no proper window.
    static func answer(_ object: [String: Any], home: String, calendar: Calendar = .current) -> Data? {
        guard let window = window(object) else { return nil }
        return body(jobs: ArisScheduleStore.load(file: ArisScheduleStore.file(home: home)), from: window.from, to: window.to, calendar: calendar,
                    today: day(object, from: window.from))
    }
}
