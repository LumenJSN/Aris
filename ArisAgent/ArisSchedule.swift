//
//  ArisSchedule.swift
//  aris-agent, aris-tools
//
//  Scheduled work ("매일 아침 8시에 날씨 알려 줘", "2분 뒤에 알려 줘"): when a rule runs next, whether a run was missed
//  (the Mac slept, the agent was down), which jobs are due, and how `aris-tools schedule add` reads its arguments.
//  Pure rules; the store is ArisScheduleStore and the timer ArisScheduler.
//

import Foundation

/// When a scheduled job runs. `weekday` is Calendar's (1 = Sunday); `every` is clamped to at least a minute.
/// The last four came with the store's version 2 (ArisSchedule.storeVersion): `weekdays` on several days of the week
/// ("평일 08:00"), `everyDays`/`everyWeeks` every N days or weeks counted from the day `start` ("yyyy-MM-dd", the day it
/// was made), `monthly` on a day of the month (a month without that day: its last day).
enum ArisRepeat: Codable, Equatable {
    case once(Date)
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case every(seconds: Int)
    case weekdays(days: [Int], hour: Int, minute: Int)
    case everyDays(count: Int, hour: Int, minute: Int, start: String)
    case everyWeeks(count: Int, weekday: Int, hour: Int, minute: Int, start: String)
    case monthly(day: Int, hour: Int, minute: Int)

    /// A rule an older Aris can't read: its job is written with ArisSchedule.storeVersion.
    var isVersion2: Bool {
        switch self {
        case .once, .daily, .weekly, .every: return false
        case .weekdays, .everyDays, .everyWeeks, .monthly: return true
        }
    }
}

struct ArisScheduledJob: Codable, Identifiable, Equatable {
    let id: UUID
    let title: String
    /// What the job asks the AI to do. Written by a model, so it always runs as untrusted, with no words of
    /// The user's to match targets against (no target counts as known, and nothing is a dictated message).
    let prompt: String
    let teammate: String?
    let rule: ArisRepeat
    let created: Date
    var nextRun: Date?
    var lastRun: Date?
    /// A run is going on (set when it starts, cleared when it ends): after an agent restart it is reported, never resumed.
    var runningSince: Date?
    /// Its questions waiting for the user (ids as the app gets them): after a restart they count as declined.
    var parked: [String]
    /// The AI the user was talking to when they set it up (ArisBrain's name): the one its runs ask for first. Nil for a
    /// schedule made before this was kept; then whoever can run on this Mac takes it (ArisJobBrain).
    var brain: String? = nil
    /// Its last run ended in a failure (the day-end list reads it: ArisDayEndRoute); nil before a run ended since this was kept.
    var lastFailed: Bool? = nil
    /// Failed runs in a row of the run that is due (each tried again after a pause: ArisSchedule.failed); nil after a
    /// run that went through.
    var tries: Int? = nil
    /// A one-time job whose run failed every try or was cut off by a restart: kept (never dropped), not run again,
    /// until the user removes it or asks again.
    var stopped: Bool? = nil
    /// The store's version this entry needs (ArisSchedule.storeVersion for a rule an older Aris can't read; nil: 1).
    var version: Int? = nil
}

struct ArisScheduleError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum ArisSchedule {
    /// The variable a brain's process carries its own name in (set by the agent, never inherited).
    static let brainKey = "ARIS_BRAIN"

    /// A brain's name as a schedule keeps it: short lowercase letters only, else nothing.
    static func brainName(_ raw: String?) -> String? {
        guard let raw, raw.range(of: "^[a-z]{2,20}$", options: .regularExpression) != nil else { return nil }
        return raw
    }

    static let minimumEvery = 60
    /// The store's newest entry format this build reads (an entry with a higher `version` is kept as it is, never
    /// read or dropped: ArisScheduleStore).
    static let storeVersion = 2
    /// Enabled schedules at most.
    static let maxSchedules = 50
    /// Scheduled runs at once (the app's worker queue cap).
    static let maxConcurrent = 3
    static let titleLimit = 80
    static let promptLimit = 2_000

    // MARK: - When

    /// The first time `rule` runs strictly after `after`; nil for a one-time job whose time has passed, or a rule
    /// naming an impossible time.
    static func next(_ rule: ArisRepeat, after: Date, calendar: Calendar) -> Date? {
        switch rule {
        case .once(let date):
            return date > after ? date : nil
        case .daily(let hour, let minute):
            guard valid(hour: hour, minute: minute) else { return nil }
            return calendar.nextDate(after: after, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
        case .weekly(let weekday, let hour, let minute):
            guard valid(hour: hour, minute: minute), (1...7).contains(weekday) else { return nil }
            return calendar.nextDate(after: after, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                                     matchingPolicy: .nextTime)
        case .every(let seconds):
            return after.addingTimeInterval(TimeInterval(max(minimumEvery, seconds)))
        case .weekdays(let days, let hour, let minute):
            guard valid(hour: hour, minute: minute), !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else { return nil }
            return Set(days).compactMap { day in
                calendar.nextDate(after: after, matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: day), matchingPolicy: .nextTime)
            }.min()
        case .everyDays(let count, let hour, let minute, let start):
            guard valid(hour: hour, minute: minute), (1...maxEveryDays).contains(count), let first = day(start, calendar: calendar) else { return nil }
            return stepping(from: first, by: count, hour: hour, minute: minute, after: after, calendar: calendar)
        case .everyWeeks(let count, let weekday, let hour, let minute, let start):
            guard valid(hour: hour, minute: minute), (1...maxEveryWeeks).contains(count), (1...7).contains(weekday),
                  let made = day(start, calendar: calendar) else { return nil }
            // The first such weekday on or after the day it was made, then every `count` weeks.
            let shift = (weekday - calendar.component(.weekday, from: made) + 7) % 7
            guard let first = calendar.date(byAdding: .day, value: shift, to: made) else { return nil }
            return stepping(from: first, by: count * 7, hour: hour, minute: minute, after: after, calendar: calendar)
        case .monthly(let day, let hour, let minute):
            guard valid(hour: hour, minute: minute), (1...31).contains(day) else { return nil }
            let month = calendar.dateComponents([.year, .month], from: after)
            for offset in 0...13 {
                guard let firstOfMonth = calendar.date(from: DateComponents(year: month.year, month: (month.month ?? 1) + offset, day: 1)),
                      let length = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count,
                      let dayOfMonth = calendar.date(byAdding: .day, value: min(day, length) - 1, to: firstOfMonth),
                      let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayOfMonth) else { continue }
                if at > after { return at }
            }
            return nil
        }
    }

    /// "Every N days/weeks": the longest gaps.
    static let maxEveryDays = 365
    static let maxEveryWeeks = 52

    /// The day a rule counts from ("yyyy-MM-dd"), at its start in `calendar`.
    static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// `date`'s day as a rule keeps it ("yyyy-MM-dd").
    static func dayText(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The first `hour:minute` strictly after `after` on a day `first` + k·`days` (k ≥ 0), counted in whole days, so a
    /// change to or from summer time never moves it.
    private static func stepping(from first: Date, by days: Int, hour: Int, minute: Int, after: Date, calendar: Calendar) -> Date? {
        let since = calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: after)).day ?? 0
        var step = since <= 0 ? 0 : (since + days - 1) / days * days
        for _ in 0..<3 {
            guard let day = calendar.date(byAdding: .day, value: step, to: first),
                  let at = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else { return nil }
            if at > after { return at }
            step += days
        }
        return nil
    }

    /// A run of `rule` came due between the last run and now (it was missed): it runs once now, however many were missed.
    static func catchUp(_ rule: ArisRepeat, lastRun: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let lastRun, let due = next(rule, after: lastRun, calendar: calendar) else { return false }
        return due <= now
    }

    private static func valid(hour: Int, minute: Int) -> Bool {
        (0...23).contains(hour) && (0...59).contains(minute)
    }

    // MARK: - Runs

    /// The jobs to start now: due and not running (in the store, or `excluding`: running here), the most overdue first, so
    /// that no more than `maxConcurrent` run.
    static func due(_ jobs: [ArisScheduledJob], now: Date, running: Int, excluding: Set<UUID> = []) -> [ArisScheduledJob] {
        let free = max(0, maxConcurrent - running)
        let ready = jobs.filter { job in
            job.runningSince == nil && !excluding.contains(job.id) && job.nextRun.map { $0 <= now } == true
        }
        return Array(ready.sorted { ($0.nextRun ?? now) < ($1.nextRun ?? now) }.prefix(free))
    }

    /// The job as it starts a run at `now`: its next run is counted from now, so missed runs never pile up.
    static func started(_ job: ArisScheduledJob, at now: Date, calendar: Calendar) -> ArisScheduledJob {
        var copy = job
        copy.lastRun = now
        copy.nextRun = next(job.rule, after: now, calendar: calendar)
        copy.runningSince = now
        copy.parked = []
        return copy
    }

    /// The job with its next run at its rule's time in `calendar`'s zone. A daily or weekly job's next run is kept as
    /// a moment, worked out where the Mac was when it last ran: after the Mac's time zone changes, "매일 아침 8시" would
    /// fire once more at eight in the old place (the middle of the local night) before following the new one. Its
    /// next run becomes the rule's next time here (audit imp-sched-tz). A one-time job is a moment and an "every N" job
    /// an interval: both stay as they are, and so does a run that is already due or going.
    static func retimed(_ job: ArisScheduledJob, now: Date, calendar: Calendar) -> ArisScheduledJob {
        guard job.runningSince == nil, let stored = job.nextRun, stored > now else { return job }
        switch job.rule {
        case .once, .every: return job
        case .daily, .weekly, .weekdays, .everyDays, .everyWeeks, .monthly: break
        }
        guard let local = next(job.rule, after: now, calendar: calendar), local != stored else { return job }
        var copy = job
        copy.nextRun = local
        return copy
    }

    /// The job once its run ended; nil when it never runs again (a one-time job that went through), so it leaves the
    /// store. A run that went through ends the tries of a failed one.
    static func finished(_ job: ArisScheduledJob, failed: Bool? = nil) -> ArisScheduledJob? {
        guard job.nextRun != nil else { return nil }
        var copy = job
        copy.runningSince = nil
        copy.parked = []
        if let failed { copy.lastFailed = failed }
        if failed == false { copy.tries = nil }
        return copy
    }

    /// A failed run is tried again after these pauses (2, 10 and 30 minutes), then waits for its next time.
    static let retryPauses: [TimeInterval] = [120, 600, 1_800]

    /// The job after a failed run (`job` as stored while it ran). It is tried again after a pause (retryPauses) unless
    /// its own next time comes first; after the last try it waits for its next time, and a one-time job is kept,
    /// stopped, never dropped. `retry`: when it runs again for this failure (nil: it doesn't), `tries`: the tries so far.
    static func failed(_ job: ArisScheduledJob, now: Date) -> (job: ArisScheduledJob, retry: Date?, tries: Int) {
        var copy = job
        copy.runningSince = nil
        copy.parked = []
        copy.lastFailed = true
        let tries = (job.tries ?? 0) + 1
        if tries <= retryPauses.count {
            let retry = now.addingTimeInterval(retryPauses[tries - 1])
            if let next = job.nextRun, next <= retry {
                copy.tries = nil
                return (copy, nil, tries)
            }
            copy.tries = tries
            copy.nextRun = retry
            return (copy, retry, tries)
        }
        copy.tries = nil
        if job.nextRun == nil { copy.stopped = true }
        return (copy, nil, tries)
    }

    /// At the agent's start: a run that was going (or a question that was parked) when it stopped is over. Those jobs
    /// are reported (`interrupted`, as they were) and cleared; their questions count as declined. One-time jobs that
    /// already ran leave the store; one whose run was cut off stays, stopped (it is never run again on its own: part
    /// of it may have been done).
    static func recovered(_ jobs: [ArisScheduledJob]) -> (jobs: [ArisScheduledJob], interrupted: [ArisScheduledJob]) {
        let interrupted = jobs.filter { $0.runningSince != nil || !$0.parked.isEmpty }
        let cleared = jobs.compactMap { job -> ArisScheduledJob? in
            let cutOff = job.nextRun == nil && job.runningSince != nil
            guard job.nextRun != nil || job.stopped == true || cutOff else { return nil }
            var copy = job
            copy.runningSince = nil
            copy.parked = []
            if cutOff { copy.stopped = true }
            return copy
        }
        return (cleared, interrupted)
    }

    /// Stopped one-time jobs kept at most (the newest).
    static let maxStopped = 20

    /// Without one-time jobs that ran and finished (they never run again); a running one stays until its run ends, and
    /// a stopped one (the newest maxStopped) until the user removes it.
    static func pruned(_ jobs: [ArisScheduledJob]) -> [ArisScheduledJob] {
        let stopped = jobs.filter(isStopped).sorted { ($0.lastRun ?? $0.created) > ($1.lastRun ?? $1.created) }.prefix(maxStopped).map(\.id)
        return jobs.filter { $0.nextRun != nil || $0.runningSince != nil || stopped.contains($0.id) }
    }

    /// A one-time job kept after its run failed or was cut off, which never runs again on its own.
    static func isStopped(_ job: ArisScheduledJob) -> Bool {
        job.stopped == true && job.nextRun == nil && job.runningSince == nil
    }

    /// A one-time job that ran and finished: it leaves the store at the next tick.
    static func isDone(_ job: ArisScheduledJob) -> Bool {
        job.nextRun == nil && job.runningSince == nil && job.stopped != true
    }

    /// What a failure's entry adds once no try is left: how often it was tried, and that a one-time job was kept.
    static func gaveUp(tries: Int, stopped: Bool, korean: Bool) -> String {
        let again = tries > 1 ? (korean ? " \(tries - 1)번 다시 해 봤지만 안 됐어요." : " It was tried \(tries - 1) more times.") : ""
        let kept = stopped ? (korean ? " 이 예약은 지우지 않고 멈춘 채로 남겨 뒀어요. 다시 하려면 말해 주세요." : " The schedule is kept, stopped: ask again to run it.") : ""
        return again + kept
    }

    /// Runs this much past their time are late (the Mac slept, or the agent was down): the run says so.
    static let lateAfter: TimeInterval = 5 * 60

    /// The note a late run carries ("예정 시각(11월 3일 08:00)보다 늦게 실행했어요"), nil when it runs on time.
    static func lateNote(due: Date?, now: Date, korean: Bool, calendar: Calendar) -> String? {
        guard let due, now.timeIntervalSince(due) > lateAfter else { return nil }
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: due)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if korean { return "예정 시각(\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(clock))보다 늦게 실행했어요. Mac이 잠자고 있었거나 Aris가 꺼져 있었어요." }
        return "This ran later than planned (\(parts.month ?? 0)/\(parts.day ?? 0) at \(clock)): the Mac was asleep or Aris wasn't running."
    }

    /// Whether a job counts toward ArisSchedule.maxSchedules: it will still run.
    static func isEnabled(_ job: ArisScheduledJob) -> Bool {
        job.nextRun != nil
    }

    /// The running jobs that are no longer in the store (removed, or their creation undone): their runs are cancelled.
    static func orphaned(running: Set<UUID>, jobs: [ArisScheduledJob]) -> Set<UUID> {
        running.subtracting(jobs.map(\.id))
    }

    // MARK: - Words

    private static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]
    /// Monday to Friday, and the weekend, as Calendar numbers them.
    static let workdays = [2, 3, 4, 5, 6]
    static let weekend = [1, 7]

    /// Several weekdays in the week's order from Monday ("월·수·금"), "평일" or "주말".
    static func weekdayList(_ days: [Int]) -> String {
        let sorted = Set(days).filter { (1...7).contains($0) }.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }
        if sorted == workdays { return "평일" }
        if Set(sorted) == Set(weekend) { return "주말" }
        return sorted.map { weekdayNames[$0 - 1] }.joined(separator: "·")
    }

    /// "매일 08:00", "매주 금 18:00", "30분마다", "11월 3일 14:05에 한 번", "평일 08:00", "매주 월·수·금 08:00",
    /// "3일마다 09:00", "2주마다 금 09:00", "매월 15일 09:00".
    static func describe(_ rule: ArisRepeat, calendar: Calendar) -> String {
        func clock(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
        switch rule {
        case .weekdays(let days, let hour, let minute):
            let list = weekdayList(days)
            return (list == "평일" || list == "주말" ? list : "매주 " + list) + " " + clock(hour, minute)
        case .everyDays(let count, let hour, let minute, _): return "\(count)일마다 \(clock(hour, minute))"
        case .everyWeeks(let count, let weekday, let hour, let minute, _):
            return "\(count)주마다 \((1...7).contains(weekday) ? weekdayNames[weekday - 1] : "?") \(clock(hour, minute))"
        case .monthly(let day, let hour, let minute): return "매월 \(day)일 \(clock(hour, minute))"
        case .once(let date):
            let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(clock(parts.hour ?? 0, parts.minute ?? 0))에 한 번"
        case .daily(let hour, let minute): return "매일 \(clock(hour, minute))"
        case .weekly(let weekday, let hour, let minute):
            return "매주 \((1...7).contains(weekday) ? weekdayNames[weekday - 1] : "?") \(clock(hour, minute))"
        case .every(let seconds):
            let minutes = max(minimumEvery, seconds) / 60
            return minutes % 60 == 0 ? "\(minutes / 60)시간마다" : "\(minutes)분마다"
        }
    }

    /// One line: no line breaks or control characters, cut to `limit`.
    static func oneLine(_ text: String, limit: Int) -> String {
        let cleaned = text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        return String(cleaned.trimmingCharacters(in: .whitespaces).prefix(limit))
    }
}

/// What the scheduler last read of schedules.json, so an idle tick doesn't read it again: unchanged (same modification
/// time and size), nothing running, and nothing due before the earliest next run.
struct ArisScheduleWatch {
    struct Stamp: Equatable {
        let modified: Date
        let size: Int
    }

    private var last: Stamp?
    private var earliest: Date?
    private var seen = false

    func needsLook(stamp: Stamp?, now: Date, running: Int) -> Bool {
        guard seen, running == 0, let stamp, stamp == last else { return true }
        return earliest.map { $0 <= now } ?? false
    }

    mutating func saw(stamp: Stamp?, jobs: [ArisScheduledJob]) {
        last = stamp
        earliest = jobs.compactMap(\.nextRun).min()
        // A finished one-time job waits to be pruned: look again next time (a stopped one stays as it is).
        if jobs.contains(where: ArisSchedule.isDone) { earliest = .distantPast }
        seen = true
    }

    /// The file's modification time and size, without following a link; nil when it can't be read.
    static func stamp(of file: URL) -> Stamp? {
        var info = stat()
        guard lstat(file.path, &info) == 0 else { return nil }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000)
        return Stamp(modified: modified, size: Int(info.st_size))
    }
}

/// How `aris-tools schedule add` reads its arguments:
/// `--title T --prompt P (--at "YYYY-MM-DD HH:mm" | --daily HH:mm | --weekly <sun..sat> HH:mm | --weekdays <days> HH:mm |
/// --every-days <N> HH:mm | --every-weeks <N> <sun..sat> HH:mm | --monthly <1-31> HH:mm | --every <N>m|<N>h) [--teammate ID]`.
/// Exactly one time flag, each flag once, nothing left over.
enum ArisScheduleArguments {
    struct Parsed: Equatable {
        let title: String
        let prompt: String
        let rule: ArisRepeat
        let teammate: String?
    }

    static let usage = #"usage: schedule add --title T --prompt P (--at "YYYY-MM-DD HH:mm" | --daily HH:mm | --weekly <sun..sat> HH:mm | --weekdays <mon,wed,fri|weekdays|weekends> HH:mm | --every-days <N> HH:mm | --every-weeks <N> <sun..sat> HH:mm | --monthly <1-31> HH:mm | --every <N>m|<N>h) [--teammate ID]"#

    /// The repeating time flags as the brains' prompts show them (ArisAgentPrompt).
    static let promptFlags = "`--daily 08:00`, `--weekly fri 18:00`, `--weekdays mon,wed,fri 08:00` (or `weekdays`, `weekends`), " +
        "`--every-days 3 09:00`, `--every-weeks 2 fri 09:00`, `--monthly 15 09:00` (a month without that day: its last day), `--every 30m`"

    private static let weekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let timeFlags: Set<String> = ["--at", "--daily", "--weekly", "--every", "--weekdays", "--every-days", "--every-weeks", "--monthly"]
    /// How many values each flag takes.
    private static let flags: [String: Int] = ["--title": 1, "--prompt": 1, "--teammate": 1, "--at": 1, "--daily": 1, "--weekly": 2, "--every": 1,
                                               "--weekdays": 2, "--every-days": 2, "--every-weeks": 3, "--monthly": 2]

    static func parse(_ arguments: [String], now: Date, calendar: Calendar) throws -> Parsed {
        var values: [String: [String]] = [:]
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            guard let count = flags[flag] else { throw ArisScheduleError(message: "unexpected \"\(flag)\". \(usage)") }
            guard values[flag] == nil else { throw ArisScheduleError(message: "\(flag) is given twice") }
            guard index + count < arguments.count else { throw ArisScheduleError(message: "\(flag) needs a value. \(usage)") }
            values[flag] = Array(arguments[(index + 1)...(index + count)])
            index += count + 1
        }
        let title = ArisSchedule.oneLine(values["--title"]?.first ?? "", limit: ArisSchedule.titleLimit)
        let prompt = try promptText(values["--prompt"]?.first ?? "")
        guard !title.isEmpty, !prompt.isEmpty else { throw ArisScheduleError(message: "a schedule needs --title and --prompt. \(usage)") }
        guard prompt.count <= ArisSchedule.promptLimit else { throw ArisScheduleError(message: "the prompt is too long") }
        let given = timeFlags.filter { values[$0] != nil }
        guard given.count == 1, let timeFlag = given.first, let timeValues = values[timeFlag] else {
            throw ArisScheduleError(message: "give exactly one of --at, --daily, --weekly, --weekdays, --every-days, --every-weeks, --monthly, --every. \(usage)")
        }
        let teammate = values["--teammate"]?.first
        if let teammate, teammate.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) == nil {
            throw ArisScheduleError(message: "--teammate is an id like claude-code")
        }
        let rule = try self.rule(timeFlag, timeValues, now: now, calendar: calendar)
        return Parsed(title: title, prompt: prompt, rule: rule, teammate: teammate)
    }

    /// What the brain is told when its --prompt isn't the user's request (QA BUG-28).
    static let promptRule = #"--prompt is the user's own request in their own words, e.g. "오늘 날씨 알려 줘" (no commands, paths or \n); the run does it then with its own tools"#

    /// What a stored prompt never holds (QA follow-up to BUG-28): aris-tools by name or path, an absolute or home path
    /// (/Users/…, ~/…, /bin/zsh), substitution ($(…), backticks), a chain (&&, ||), a pipe, a redirect into a file, a
    /// long flag (--daily), or a command word followed by a flag (ls -la, curl -s). Ordinary requests pass: "A/B 테스트",
    /// "1/2", "30도 > 이면", "a; then b", a web address.
    static let commandShapes = [
        #"(^|[\s/"'`=])aris-tools($|[\s"'`;])"#,
        #"(^|[\s"'`(=])(~|/)[A-Za-z0-9._-]*/"#,
        #"\$\("#, #"`"#,
        #"&&|\|\|"#, #"(^|\s)\|(\s|$)"#,
        #"(^|\s)\d?>>?\s*[~/.A-Za-z0-9_-]*[/.]"#, #"\d>&\d"#,
        #"(^|\s)--[A-Za-z][A-Za-z-]+"#,
        #"^[a-z][a-z0-9._-]*\s+-[A-Za-z]"#,
    ]

    /// The prompt a job keeps: the user's intent, never a model-written shell line (QA BUG-28: "Say: …\n/Users/…/aris-tools
    /// weather"). A literal \n (or \r) or a line break becomes a space and runs of spaces one; a path or a command line
    /// in it (commandShapes) is refused, with what to write instead.
    static func promptText(_ raw: String) throws -> String {
        let spaced = raw.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\r", with: " ")
            .components(separatedBy: .newlines).joined(separator: " ")
        let prompt = spaced.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        if commandShapes.contains(where: { prompt.range(of: $0, options: .regularExpression) != nil }) {
            throw ArisScheduleError(message: "refused: " + promptRule)
        }
        return prompt
    }

    private static func rule(_ flag: String, _ values: [String], now: Date, calendar: Calendar) throws -> ArisRepeat {
        switch flag {
        case "--at":
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            guard let date = formatter.date(from: values[0]) else { throw ArisScheduleError(message: #"--at takes "YYYY-MM-DD HH:mm""#) }
            guard date > now else { throw ArisScheduleError(message: "that time has already passed") }
            return .once(date)
        case "--daily":
            let (hour, minute) = try clock(values[0])
            return .daily(hour: hour, minute: minute)
        case "--weekly":
            guard let weekday = weekdays[values[0].lowercased()] else { throw ArisScheduleError(message: "--weekly takes a day: sun, mon, tue, wed, thu, fri or sat") }
            let (hour, minute) = try clock(values[1])
            return .weekly(weekday: weekday, hour: hour, minute: minute)
        case "--weekdays":
            let days = try weekdaySet(values[0])
            let (hour, minute) = try clock(values[1])
            return days.count == 7 ? .daily(hour: hour, minute: minute)
                : days.count == 1 ? .weekly(weekday: days[0], hour: hour, minute: minute) : .weekdays(days: days, hour: hour, minute: minute)
        case "--every-days":
            guard let count = Int(values[0]), (1...ArisSchedule.maxEveryDays).contains(count) else {
                throw ArisScheduleError(message: "--every-days takes a number of days from 1 to \(ArisSchedule.maxEveryDays) and a time, like 3 09:00")
            }
            let (hour, minute) = try clock(values[1])
            if count == 1 { return .daily(hour: hour, minute: minute) }
            return .everyDays(count: count, hour: hour, minute: minute, start: ArisSchedule.dayText(now, calendar: calendar))
        case "--every-weeks":
            guard let count = Int(values[0]), (1...ArisSchedule.maxEveryWeeks).contains(count) else {
                throw ArisScheduleError(message: "--every-weeks takes a number of weeks from 1 to \(ArisSchedule.maxEveryWeeks), a day and a time, like 2 fri 09:00")
            }
            guard let weekday = weekdays[values[1].lowercased()] else { throw ArisScheduleError(message: "--every-weeks takes a day: sun, mon, tue, wed, thu, fri or sat") }
            let (hour, minute) = try clock(values[2])
            if count == 1 { return .weekly(weekday: weekday, hour: hour, minute: minute) }
            return .everyWeeks(count: count, weekday: weekday, hour: hour, minute: minute, start: ArisSchedule.dayText(now, calendar: calendar))
        case "--monthly":
            guard let day = Int(values[0]), (1...31).contains(day) else { throw ArisScheduleError(message: "--monthly takes a day of the month from 1 to 31 and a time, like 15 09:00") }
            let (hour, minute) = try clock(values[1])
            return .monthly(day: day, hour: hour, minute: minute)
        default:
            let text = values[0].lowercased()
            guard let unit = text.last, unit == "m" || unit == "h", let amount = Int(text.dropLast()), amount > 0,
                  amount <= (unit == "m" ? 10_080 : 168) else {
                throw ArisScheduleError(message: "--every takes minutes or hours, like 30m or 2h")
            }
            return .every(seconds: max(ArisSchedule.minimumEvery, amount * (unit == "m" ? 60 : 3_600)))
        }
    }

    /// "mon,wed,fri" (any case, short or long names), "weekdays" (Monday to Friday) or "weekends": Calendar's numbers,
    /// each once, in order.
    private static func weekdaySet(_ text: String) throws -> [Int] {
        let word = text.lowercased()
        if word == "weekdays" || word == "workdays" { return ArisSchedule.workdays }
        if word == "weekends" || word == "weekend" { return ArisSchedule.weekend }
        let names = word.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        let days = names.compactMap { weekdays[$0] }
        guard !names.isEmpty, days.count == names.count else {
            throw ArisScheduleError(message: "--weekdays takes days like mon,wed,fri (sun, mon, tue, wed, thu, fri, sat), weekdays or weekends")
        }
        return Set(days).sorted()
    }

    /// "08:00" or "8:05".
    private static func clock(_ text: String) throws -> (Int, Int) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, parts[0].count <= 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw ArisScheduleError(message: "a time is HH:mm, like 08:00")
        }
        return (hour, minute)
    }
}
