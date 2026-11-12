//
//  ArisScheduleTool.swift
//  aris-tools
//
//  What `aris-tools schedule add|list|remove` does, with the home folder given (so it can be checked in a temp
//  folder). `add` and `remove` each record an activity entry that undoes them. The risk gate always asks the user before
//  an AI runs `add`, and before `remove` once outside text came into the turn.
//

import Foundation

enum ArisScheduleTool {
    struct Added: Equatable {
        let id: UUID
        let next: Date
    }

    /// `scoped`: the caller is a teammate's job (its scopes came from the variables or its job file); `teammate`: the
    /// one its job file names (ArisTeammateJobFile, through the parent chain; never ARIS_TEAMMATE, which a brain can set).
    /// Its schedule is filed under that teammate, never another, so the run keeps the teammate's scopes (N5); one whose
    /// job file names nobody schedules nothing. Main Aris's `--teammate` is honoured.
    static func add(_ arguments: [String], home: String, environment: [String: String], scoped: Bool = false, teammate own: String? = nil,
                    now: Date = Date(), calendar: Calendar = .current) throws -> Added {
        let parsed = try ArisScheduleArguments.parse(arguments, now: now, calendar: calendar)
        let teammate = try owner(parsed.teammate, teammate: own, scoped: scoped)
        guard let next = ArisSchedule.next(parsed.rule, after: now, calendar: calendar) else {
            throw ArisScheduleError(message: "that schedule never runs")
        }
        let job = ArisScheduledJob(id: UUID(), title: parsed.title, prompt: parsed.prompt, teammate: teammate, rule: parsed.rule,
                                   created: now, nextRun: next, lastRun: nil, runningSince: nil, parked: [],
                                   brain: ArisSchedule.brainName(environment[ArisSchedule.brainKey]))
        try ArisScheduleStore.add(job, file: ArisScheduleStore.file(home: home))
        log("예약: \(job.title) (\(ArisSchedule.describe(job.rule, calendar: calendar)))", undo: .removeSchedule(id: job.id.uuidString),
            home: home, environment: environment, now: now)
        return Added(id: job.id, next: next)
    }

    /// Whose schedule it is: a teammate's job's own, from its job file (any other `--teammate` refused), else what
    /// `--teammate` named.
    static func owner(_ named: String?, teammate: String?, scoped: Bool) throws -> String? {
        guard scoped else { return named }
        guard let own = teammate.flatMap(ArisActivity.teammateId) else { throw ArisScheduleError(message: "this teammate's job couldn't say which teammate it is, so nothing was scheduled") }
        if let named, named != own { throw ArisScheduleError(message: "a teammate schedules work only for itself (--teammate \(own))") }
        return own
    }

    private static func log(_ summary: String, undo: ArisUndo, home: String, environment: [String: String], now: Date) {
        ArisActivity.append(ArisActivityEntry(id: UUID(), date: now, job: environment["ARIS_JOB"] ?? "Aris",
                                              worker: environment["ARIS_WORKER"] ?? "aris-tools", summary: summary, undo: undo, undone: false,
                                              teammate: environment["ARIS_TEAMMATE"]),
                            file: ArisPrivateFile.folder(home: home).appendingPathComponent("activity.jsonl"))
    }

    /// `{"id": "…", "next": "2026-11-03T14:05:00+09:00"}` (local time).
    static func addedLine(_ added: Added, calendar: Calendar = .current) -> String {
        let object = ["id": added.id.uuidString, "next": timestamp(added.next, calendar: calendar)]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// One line per schedule: its id, title, rule and next run.
    static func list(home: String, calendar: Calendar = .current) -> String {
        let jobs = ArisScheduleStore.load(file: ArisScheduleStore.file(home: home))
        guard !jobs.isEmpty else { return "(no schedules)" }
        return jobs.map { job in
            let next = job.nextRun.map { "next \(timestamp($0, calendar: calendar))" } ?? "done"
            return "\(job.id.uuidString)  \(job.title) · \(ArisSchedule.describe(job.rule, calendar: calendar)) · \(next)"
        }.joined(separator: "\n")
    }

    /// `remove <id>`: takes the schedule out (a run of it going on is cancelled by the agent), logged so it can be put back.
    static func remove(_ arguments: [String], home: String, environment: [String: String] = [:], now: Date = Date(),
                       calendar: Calendar = .current) throws -> ArisScheduledJob {
        guard arguments.count == 1, let id = UUID(uuidString: arguments[0]) else { throw ArisScheduleError(message: "usage: schedule remove <id>") }
        let removed = try ArisScheduleStore.remove(id: id, file: ArisScheduleStore.file(home: home))
        log("예약 취소: \(removed.title) (\(ArisSchedule.describe(removed.rule, calendar: calendar)))", undo: .restoreSchedule(job: removed),
            home: home, environment: environment, now: now)
        return removed
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return formatter.string(from: date)
    }
}
