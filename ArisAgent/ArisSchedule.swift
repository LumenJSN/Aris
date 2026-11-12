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
enum ArisRepeat: Codable, Equatable {
    case once(Date)
    case daily(hour: Int, minute: Int)
    case weekly(weekday: Int, hour: Int, minute: Int)
    case every(seconds: Int)
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
        }
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
        case .daily, .weekly: break
        }
        guard let local = next(job.rule, after: now, calendar: calendar), local != stored else { return job }
        var copy = job
        copy.nextRun = local
        return copy
    }

    /// The job once its run ended; nil when it never runs again (a one-time job), so it leaves the store.
    static func finished(_ job: ArisScheduledJob, failed: Bool? = nil) -> ArisScheduledJob? {
        guard job.nextRun != nil else { return nil }
        var copy = job
        copy.runningSince = nil
        copy.parked = []
        if let failed { copy.lastFailed = failed }
        return copy
    }

    /// At the agent's start: a run that was going (or a question that was parked) when it stopped is over. Those jobs
    /// are reported (`interrupted`, as they were) and cleared; their questions count as declined. One-time jobs that
    /// already ran leave the store.
    static func recovered(_ jobs: [ArisScheduledJob]) -> (jobs: [ArisScheduledJob], interrupted: [ArisScheduledJob]) {
        let interrupted = jobs.filter { $0.runningSince != nil || !$0.parked.isEmpty }
        let cleared = jobs.compactMap { job -> ArisScheduledJob? in
            guard job.nextRun != nil else { return nil }
            var copy = job
            copy.runningSince = nil
            copy.parked = []
            return copy
        }
        return (cleared, interrupted)
    }

    /// Without one-time jobs that ran and finished (they never run again); a running one stays until its run ends.
    static func pruned(_ jobs: [ArisScheduledJob]) -> [ArisScheduledJob] {
        jobs.filter { $0.nextRun != nil || $0.runningSince != nil }
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

    /// "매일 08:00", "매주 금 18:00", "30분마다", "11월 3일 14:05에 한 번".
    static func describe(_ rule: ArisRepeat, calendar: Calendar) -> String {
        func clock(_ hour: Int, _ minute: Int) -> String { String(format: "%02d:%02d", hour, minute) }
        switch rule {
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
        // A finished one-time job waits to be pruned: look again next time.
        if jobs.contains(where: { $0.nextRun == nil && $0.runningSince == nil }) { earliest = .distantPast }
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
/// `--title T --prompt P (--at "YYYY-MM-DD HH:mm" | --daily HH:mm | --weekly <sun..sat> HH:mm | --every <N>m|<N>h) [--teammate ID]`.
/// Exactly one time flag, each flag once, nothing left over.
enum ArisScheduleArguments {
    struct Parsed: Equatable {
        let title: String
        let prompt: String
        let rule: ArisRepeat
        let teammate: String?
    }

    static let usage = #"usage: schedule add --title T --prompt P (--at "YYYY-MM-DD HH:mm" | --daily HH:mm | --weekly <sun..sat> HH:mm | --every <N>m) [--teammate ID]"#

    private static let weekdays: [String: Int] = [
        "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7,
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
    ]
    private static let timeFlags: Set<String> = ["--at", "--daily", "--weekly", "--every"]
    /// How many values each flag takes.
    private static let flags: [String: Int] = ["--title": 1, "--prompt": 1, "--teammate": 1, "--at": 1, "--daily": 1, "--weekly": 2, "--every": 1]

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
            throw ArisScheduleError(message: "give exactly one of --at, --daily, --weekly, --every. \(usage)")
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
        default:
            let text = values[0].lowercased()
            guard let unit = text.last, unit == "m" || unit == "h", let amount = Int(text.dropLast()), amount > 0,
                  amount <= (unit == "m" ? 10_080 : 168) else {
                throw ArisScheduleError(message: "--every takes minutes or hours, like 30m or 2h")
            }
            return .every(seconds: max(ArisSchedule.minimumEvery, amount * (unit == "m" ? 60 : 3_600)))
        }
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
