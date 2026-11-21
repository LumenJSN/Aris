// Tests for jv-helperbugs (schedules): audited helper and aris-tools bugs. A failed scheduled run is tried again
// and a one-time job is never dropped for a failure or a restart; a late run says so; schedules repeat on weekdays,
// every N days or weeks and monthly, in a versioned store an older entry still reads; a routine's schedules go with
// it; unreadable schedule and skill entries are kept aside in a .bad file and reported once; a store that can't be
// used is said in the inbox; a GitHub skill's limits are its folder's; a slow gh is not "signed out".
// Called from main.swift; uses its check(). Temp folders only, no model, no network.
import Compression
import Foundation

private let hbRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func hbSource(_ path: String) -> String { (try? String(contentsOf: hbRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func hbFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-helperbugs-sched-\(UUID().uuidString.prefix(8))").resolvingSymlinksInPath()
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    return folder
}

private func hbCalendar(_ zone: String = "Asia/Seoul") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private func hbAt(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func hbJob(_ rule: ArisRepeat, next: Date?, created: Date = Date(), running: Date? = nil) -> ArisScheduledJob {
    ArisScheduledJob(id: UUID(), title: "t", prompt: "p", teammate: nil, rule: rule, created: created, nextRun: next, lastRun: nil,
                     runningSince: running, parked: [])
}

func runHelperbugsSchedulesTests() {
    hbRuleTests()
    hbArgumentTests()
    hbWordsTests()
    hbRetryTests()
    hbStoreTests()
    hbSkillStoreTests()
    hbRoutineTests()
    hbArchiveTests()
    hbGitHubTests()
}

// MARK: - Item 3: the new rules

private func hbRuleTests() {
    let seoul = hbCalendar()
    // Tuesday 2026-11-03.
    let tuesday = hbAt(seoul, 2026, 11, 3, 12)
    let monWedFri = ArisRepeat.weekdays(days: [2, 4, 6], hour: 8, minute: 0)
    check(ArisSchedule.next(monWedFri, after: tuesday, calendar: seoul) == hbAt(seoul, 2026, 11, 4, 8)
          && ArisSchedule.next(monWedFri, after: hbAt(seoul, 2026, 11, 6, 9), calendar: seoul) == hbAt(seoul, 2026, 11, 9, 8),
          "schedule rules: mon/wed/fri runs on the next of those days (Friday after its time: Monday)")
    check(ArisSchedule.next(.weekdays(days: [], hour: 8, minute: 0), after: tuesday, calendar: seoul) == nil
          && ArisSchedule.next(.weekdays(days: [9], hour: 8, minute: 0), after: tuesday, calendar: seoul) == nil,
          "schedule rules: no day or an impossible day never runs")

    let everyThree = ArisRepeat.everyDays(count: 3, hour: 9, minute: 0, start: "2026-11-03")
    check(ArisSchedule.next(everyThree, after: hbAt(seoul, 2026, 11, 3, 8), calendar: seoul) == hbAt(seoul, 2026, 11, 3, 9)
          && ArisSchedule.next(everyThree, after: hbAt(seoul, 2026, 11, 3, 9), calendar: seoul) == hbAt(seoul, 2026, 11, 6, 9)
          && ArisSchedule.next(everyThree, after: hbAt(seoul, 2026, 11, 5, 10), calendar: seoul) == hbAt(seoul, 2026, 11, 6, 9)
          && ArisSchedule.next(everyThree, after: hbAt(seoul, 2026, 12, 1, 10), calendar: seoul) == hbAt(seoul, 2026, 12, 3, 9),
          "schedule rules: every 3 days counts from the day it was made")
    let orlando = hbCalendar("America/New_York")
    // Summer time ends on 2026-11-01: the run stays at 09:00 on the wall clock.
    let acrossChange = ArisSchedule.next(.everyDays(count: 2, hour: 9, minute: 0, start: "2026-10-30"), after: hbAt(orlando, 2026, 10, 31, 12), calendar: orlando)
    check(acrossChange == hbAt(orlando, 2026, 11, 1, 9) && acrossChange.map { orlando.component(.hour, from: $0) } == 9,
          "schedule rules: every N days keeps its time on the clock across a change of summer time")

    let fortnightly = ArisRepeat.everyWeeks(count: 2, weekday: 6, hour: 9, minute: 0, start: "2026-11-03")
    check(ArisSchedule.next(fortnightly, after: tuesday, calendar: seoul) == hbAt(seoul, 2026, 11, 6, 9)
          && ArisSchedule.next(fortnightly, after: hbAt(seoul, 2026, 11, 6, 9), calendar: seoul) == hbAt(seoul, 2026, 11, 20, 9)
          && ArisSchedule.next(fortnightly, after: hbAt(seoul, 2026, 11, 13, 9), calendar: seoul) == hbAt(seoul, 2026, 11, 20, 9),
          "schedule rules: every 2 weeks on Friday, from the first Friday after it was made")

    let lastDay = ArisRepeat.monthly(day: 31, hour: 9, minute: 0)
    check(ArisSchedule.next(lastDay, after: tuesday, calendar: seoul) == hbAt(seoul, 2026, 11, 30, 9)
          && ArisSchedule.next(lastDay, after: hbAt(seoul, 2026, 11, 30, 9), calendar: seoul) == hbAt(seoul, 2026, 12, 31, 9)
          && ArisSchedule.next(lastDay, after: hbAt(seoul, 2027, 2, 1), calendar: seoul) == hbAt(seoul, 2027, 2, 28, 9),
          "schedule rules: monthly on the 31st falls on a shorter month's last day")
    check(ArisSchedule.next(.monthly(day: 15, hour: 9, minute: 0), after: hbAt(seoul, 2026, 11, 15, 9), calendar: seoul) == hbAt(seoul, 2026, 12, 15, 9)
          && ArisSchedule.next(.monthly(day: 15, hour: 9, minute: 0), after: hbAt(seoul, 2026, 12, 20), calendar: seoul) == hbAt(seoul, 2027, 1, 15, 9)
          && ArisSchedule.next(.monthly(day: 0, hour: 9, minute: 0), after: tuesday, calendar: seoul) == nil,
          "schedule rules: monthly on the 15th, into the next year; day 0 never runs")

    // A daily-like rule's stored run time follows a time zone change (ArisSchedule.retimed), as daily and weekly did.
    var stale = hbJob(monWedFri, next: hbAt(orlando, 2026, 11, 4, 8), created: tuesday)
    stale.nextRun = hbAt(orlando, 2026, 11, 4, 8)
    check(ArisSchedule.retimed(stale, now: tuesday, calendar: seoul).nextRun == hbAt(seoul, 2026, 11, 4, 8), "schedule rules: a new rule's run follows the Mac's time zone")

    // The store's format: an old entry reads as before; a new rule is written as version 2 and reads back.
    let old = Data(#"{"created":"2026-11-03T03:00:00Z","id":"AAAAAAAA-0000-0000-0000-000000000001","nextRun":"2026-11-04T23:00:00Z","parked":[],"prompt":"p","rule":{"daily":{"hour":8,"minute":0}},"title":"t"}"#.utf8)
    let decodedOld = try? ArisPrivateFile.decoder.decode(ArisScheduledJob.self, from: old)
    check(decodedOld?.rule == .daily(hour: 8, minute: 0) && decodedOld?.version == nil && decodedOld?.tries == nil && decodedOld?.stopped == nil,
          "schedule store: an entry written before still reads")
    let rules: [ArisRepeat] = [monWedFri, everyThree, fortnightly, lastDay]
    let roundTrip = rules.allSatisfy { rule in
        var job = hbJob(rule, next: tuesday, created: tuesday)
        job.version = ArisSchedule.storeVersion
        guard let data = try? ArisPrivateFile.encoder.encode(job) else { return false }
        return (try? ArisPrivateFile.decoder.decode(ArisScheduledJob.self, from: data)) == job
    }
    check(roundTrip && rules.allSatisfy(\.isVersion2) && !ArisRepeat.daily(hour: 1, minute: 0).isVersion2 && !ArisRepeat.every(seconds: 60).isVersion2,
          "schedule store: the new rules are version 2 and read back as written")
}

// MARK: - Item 3: the command line

private func hbArgumentTests() {
    let seoul = hbCalendar()
    let now = hbAt(seoul, 2026, 11, 3, 12)
    func rule(_ time: [String]) -> ArisRepeat? { try? ArisScheduleArguments.parse(["--title", "t", "--prompt", "p"] + time, now: now, calendar: seoul).rule }
    check(rule(["--weekdays", "mon,wed,fri", "08:00"]) == .weekdays(days: [2, 4, 6], hour: 8, minute: 0)
          && rule(["--weekdays", "Friday,MON", "8:00"]) == .weekdays(days: [2, 6], hour: 8, minute: 0)
          && rule(["--weekdays", "weekdays", "07:30"]) == .weekdays(days: [2, 3, 4, 5, 6], hour: 7, minute: 30)
          && rule(["--weekdays", "weekends", "10:00"]) == .weekdays(days: [1, 7], hour: 10, minute: 0),
          "schedule CLI: --weekdays takes days, weekdays or weekends")
    check(rule(["--weekdays", "fri", "18:00"]) == .weekly(weekday: 6, hour: 18, minute: 0)
          && rule(["--weekdays", "sun,mon,tue,wed,thu,fri,sat", "08:00"]) == .daily(hour: 8, minute: 0)
          && rule(["--every-days", "1", "09:00"]) == .daily(hour: 9, minute: 0)
          && rule(["--every-weeks", "1", "fri", "09:00"]) == .weekly(weekday: 6, hour: 9, minute: 0),
          "schedule CLI: a rule an older Aris reads is kept in its old form")
    check(rule(["--every-days", "3", "09:00"]) == .everyDays(count: 3, hour: 9, minute: 0, start: "2026-11-03")
          && rule(["--every-weeks", "2", "fri", "09:00"]) == .everyWeeks(count: 2, weekday: 6, hour: 9, minute: 0, start: "2026-11-03")
          && rule(["--monthly", "15", "09:00"]) == .monthly(day: 15, hour: 9, minute: 0),
          "schedule CLI: --every-days, --every-weeks and --monthly")
    let rejected: [[String]] = [["--monthly", "32", "09:00"], ["--monthly", "0", "09:00"], ["--every-days", "0", "09:00"], ["--every-days", "400", "09:00"],
                                ["--every-weeks", "2", "fry", "09:00"], ["--every-weeks", "60", "fri", "09:00"], ["--weekdays", "xyz", "08:00"],
                                ["--weekdays", "mon,", "08:00"], ["--monthly", "15"], ["--weekdays", "mon", "25:00"], ["--monthly", "15", "09:00", "--daily", "08:00"]]
    for args in rejected { check(rule(args) == nil, "schedule CLI: rejects \(args.joined(separator: " "))") }

    // aris-tools writes a new rule as the store's version 2.
    let home = hbFolder().path
    let added = try? ArisScheduleTool.add(["--title", "보고", "--prompt", "보고서 정리해 줘", "--monthly", "15", "09:00"], home: home, environment: [:], now: now, calendar: seoul)
    let stored = ArisScheduleStore.load(file: ArisScheduleStore.file(home: home))
    check(added?.next == hbAt(seoul, 2026, 11, 15, 9) && stored.first?.version == ArisSchedule.storeVersion && stored.first?.rule == .monthly(day: 15, hour: 9, minute: 0),
          "schedule CLI: a monthly schedule is stored as version 2 and runs next on the 15th")
    _ = try? ArisScheduleTool.add(["--title", "아침", "--prompt", "날씨 알려 줘", "--daily", "08:00"], home: home, environment: [:], now: now, calendar: seoul)
    check(ArisScheduleStore.load(file: ArisScheduleStore.file(home: home)).last?.version == nil, "schedule CLI: an old-form rule is stored as before (no version)")

    // The card the user allows reads the new rules.
    let card = ArisScheduleCard.card(["--title", "t", "--prompt", "p", "--weekdays", "weekdays", "08:00"], english: false, teammate: nil, now: now, calendar: seoul)
    let english = ArisScheduleCard.card(["--title", "t", "--prompt", "p", "--every-weeks", "2", "fri", "09:00"], english: true, teammate: nil, now: now, calendar: seoul)
    check(card.1.contains("언제: 평일 08:00") && english.1.contains("When: every 2 weeks on Friday at 09:00"), "schedule card: says when a new rule runs")

    // The prompts name the new flags (one list, in every brain's prompt).
    let flags = ArisScheduleArguments.promptFlags
    check(flags.contains("--weekdays") && flags.contains("--every-days") && flags.contains("--every-weeks") && flags.contains("--monthly")
          && flags.contains("--weekly fri 18:00") && flags.contains("--every 30m"), "schedule prompt: the flags list has the new rules and the old ones")
    let prompts = hbSource("ArisAgent/ArisAgentPrompt.swift") + hbSource("ArisAgent/ArisAgentPrompt+HandOff.swift")
    check(prompts.components(separatedBy: "ArisScheduleArguments.promptFlags").count - 1 == 4 && !prompts.contains("`--weekly fri 18:00`, `--every 30m`"),
          "schedule prompt: every brain's schedule line names the flags from that list")
    check(ArisScheduleArguments.usage.contains("--monthly") && ArisScheduleArguments.usage.contains("--weekdays"), "schedule CLI: the usage line names the new flags")
}

// MARK: - Item 3: the words, Korean and English

private func hbWordsTests() {
    let seoul = hbCalendar()
    let pairs: [(ArisRepeat, String, String)] = [
        (.weekdays(days: [2, 3, 4, 5, 6], hour: 8, minute: 0), "평일 08:00", "every weekday at 08:00"),
        (.weekdays(days: [1, 7], hour: 10, minute: 0), "주말 10:00", "on weekends at 10:00"),
        (.weekdays(days: [1, 2, 4], hour: 8, minute: 30), "매주 월·수·일 08:30", "every Monday, Wednesday and Sunday at 08:30"),
        (.everyDays(count: 3, hour: 9, minute: 0, start: "2026-11-03"), "3일마다 09:00", "every 3 days at 09:00"),
        (.everyWeeks(count: 2, weekday: 6, hour: 9, minute: 0, start: "2026-11-03"), "2주마다 금 09:00", "every 2 weeks on Friday at 09:00"),
        (.monthly(day: 15, hour: 9, minute: 0), "매월 15일 09:00", "monthly on the 15th at 09:00"),
    ]
    for (rule, korean, english) in pairs {
        check(ArisSchedule.describe(rule, calendar: seoul) == korean && ArisScheduleCard.when(rule, english: true, calendar: seoul) == english,
              "schedule words: \(korean) / \(english)")
        // The 한 일 tab and the undo card read the log's Korean line in English (ArisActivityWords).
        check(ArisActivityWords.english("예약: 운동 (\(korean))") == "Scheduled: 운동 (\(english))", "schedule words: the activity line in English: \(english)")
    }
    check(ArisScheduleCard.when(.monthly(day: 31, hour: 9, minute: 0), english: true, calendar: seoul) == "monthly on the 31st at 09:00 (or the month's last day)"
          && ArisScheduleCard.ordinal(22) == "22nd" && ArisScheduleCard.ordinal(13) == "13th" && ArisScheduleCard.ordinal(3) == "3rd",
          "schedule words: a day past the 28th says it may be the month's last day")
}

// MARK: - Item 2: tried again, caught up, never dropped

private func hbRetryTests() {
    let seoul = hbCalendar()
    let now = hbAt(seoul, 2026, 11, 3, 8, 1)
    // A daily job that started at 08:00 (its next run tomorrow) and failed.
    let daily = ArisSchedule.started(hbJob(.daily(hour: 8, minute: 0), next: hbAt(seoul, 2026, 11, 3, 8)), at: hbAt(seoul, 2026, 11, 3, 8), calendar: seoul)
    let first = ArisSchedule.failed(daily, now: now)
    check(first.retry == now.addingTimeInterval(120) && first.job.nextRun == first.retry && first.job.tries == 1 && first.job.runningSince == nil
          && first.job.lastFailed == true, "schedule retry: a failed run is tried again in 2 minutes")
    check(ArisSchedule.due([first.job], now: now.addingTimeInterval(121), running: 0).count == 1, "schedule retry: the try is due at its time")
    var job = first.job
    var pauses: [TimeInterval] = []
    for _ in 0..<3 {
        let start = job.nextRun ?? now
        job = ArisSchedule.started(job, at: start, calendar: seoul)
        let after = ArisSchedule.failed(job, now: start)
        if let retry = after.retry { pauses.append(retry.timeIntervalSince(start)) }
        job = after.job
    }
    check(pauses == [600, 1_800] && job.tries == nil && job.nextRun == hbAt(seoul, 2026, 11, 4, 8),
          "schedule retry: then 10 and 30 minutes; after the last try it waits for its next time")
    let recovered = ArisSchedule.finished(ArisSchedule.started(first.job, at: first.retry!, calendar: seoul), failed: false)
    check(recovered?.tries == nil && recovered?.lastFailed == false, "schedule retry: a try that goes through ends the tries")
    // Its own next time comes before the pause: no extra run.
    let often = ArisSchedule.started(hbJob(.every(seconds: 60), next: now), at: now, calendar: seoul)
    let oftenFailed = ArisSchedule.failed(often, now: now)
    check(oftenFailed.retry == nil && oftenFailed.job.nextRun == now.addingTimeInterval(60) && oftenFailed.job.tries == nil,
          "schedule retry: a job whose next time comes first just runs then")

    // A one-time job: tried again, and after the last try kept, stopped, never dropped.
    var once = ArisSchedule.started(hbJob(.once(now), next: now), at: now, calendar: seoul)
    check(once.nextRun == nil, "schedule retry: a one-time job has no next run while it runs")
    var onceTries: [Date?] = []
    for _ in 0..<4 {
        let after = ArisSchedule.failed(once, now: now)
        onceTries.append(after.retry)
        once = after.retry == nil ? after.job : ArisSchedule.started(after.job, at: after.retry!, calendar: seoul)
    }
    check(onceTries.prefix(3).allSatisfy { $0 != nil } && onceTries[3] == nil && ArisSchedule.isStopped(once) && once.stopped == true,
          "schedule retry: a one-time job is tried three more times, then stopped")
    check(ArisSchedule.pruned([once]).count == 1 && !ArisSchedule.isEnabled(once) && ArisSchedule.due([once], now: now.addingTimeInterval(86_400), running: 0).isEmpty
          && !ArisSchedule.isDone(once), "schedule retry: a stopped one-time job stays in the store, never runs on its own and doesn't count toward the cap")
    check(ArisSchedule.gaveUp(tries: 4, stopped: true, korean: true).contains("3번 다시") && ArisSchedule.gaveUp(tries: 4, stopped: true, korean: true).contains("남겨 뒀어요")
          && ArisSchedule.gaveUp(tries: 1, stopped: false, korean: false).isEmpty, "schedule retry: the last failure says how often it was tried and that it was kept")
    // A one-time job that went through still leaves the store.
    check(ArisSchedule.finished(ArisSchedule.started(hbJob(.once(now), next: now), at: now, calendar: seoul), failed: false) == nil,
          "schedule retry: a one-time job that went through leaves the store")
    // Cut off by a restart: kept, stopped (not run again: part of it may be done); one that finished is dropped.
    let cutOff = hbJob(.once(now), next: nil, running: now)
    let finishedOnce = hbJob(.once(now), next: nil)
    let afterRestart = ArisSchedule.recovered([cutOff, finishedOnce])
    check(afterRestart.jobs.map(\.id) == [cutOff.id] && afterRestart.jobs.first?.stopped == true && afterRestart.interrupted.map(\.id) == [cutOff.id]
          && ArisSchedule.recovered(afterRestart.jobs).jobs.map(\.id) == [cutOff.id], "schedule restart: a one-time job cut off is kept, stopped; a finished one leaves")
    // At most maxStopped stopped jobs are kept (the newest).
    let many = (0..<(ArisSchedule.maxStopped + 3)).map { index -> ArisScheduledJob in
        var job = hbJob(.once(now), next: nil, created: now.addingTimeInterval(Double(index)))
        job.stopped = true
        return job
    }
    check(ArisSchedule.pruned(many).count == ArisSchedule.maxStopped && !ArisSchedule.pruned(many).contains { $0.id == many[0].id },
          "schedule retry: the stopped jobs kept are the newest \(ArisSchedule.maxStopped)")

    // A run missed while the Mac slept runs once, and says it is late.
    let missed = ArisSchedule.lateNote(due: hbAt(seoul, 2026, 11, 1, 8), now: hbAt(seoul, 2026, 11, 3, 12), korean: true, calendar: seoul)
    check(missed?.contains("11월 1일 08:00") == true && missed?.contains("늦게") == true
          && ArisSchedule.lateNote(due: now, now: now.addingTimeInterval(60), korean: true, calendar: seoul) == nil
          && ArisSchedule.lateNote(due: nil, now: now, korean: false, calendar: seoul) == nil
          && ArisSchedule.lateNote(due: hbAt(seoul, 2026, 11, 1, 8), now: now, korean: false, calendar: seoul)?.contains("later than planned") == true,
          "schedule catch-up: a late run's result says when it was due; one on time says nothing")
    let scheduler = hbSource("ArisAgent/ArisScheduler.swift")
    check(scheduler.contains("ArisSchedule.failed(stored, now: now)") && scheduler.contains("lateSince[job.id] = at") && scheduler.contains("ArisSchedule.lateNote(")
          && scheduler.contains("It was due at") && scheduler.contains("reportRefusal()"),
          "scheduler: a failure goes through the retry rule, a late run tells the brain and the user, and a refused store is reported")
}

// MARK: - Item 4: the store keeps what it can't read

private func hbStoreTests() {
    let folder = hbFolder()
    let file = folder.appendingPathComponent("schedules.json")
    let inbox = folder.appendingPathComponent("inbox.jsonl")
    let now = Date()
    let good = hbJob(.daily(hour: 8, minute: 0), next: now.addingTimeInterval(3_600))
    let goodObject = (try? JSONSerialization.jsonObject(with: ArisPrivateFile.encoder.encode(good))) as? [String: Any] ?? [:]
    let damaged: [String: Any] = ["id": "not-a-uuid", "title": "망가진 예약"]
    let future: [String: Any] = ["id": UUID().uuidString, "title": "새 형식", "version": ArisSchedule.storeVersion + 1, "rule": ["yearly": ["day": 1]]]
    try? ArisPrivateFile.write(JSONSerialization.data(withJSONObject: [goodObject, damaged, future]), to: file)
    let loaded = ArisScheduleStore.load(file: file)
    let bad = (try? JSONSerialization.jsonObject(with: Data(contentsOf: ArisPrivateFile.badFile(file)))) as? [[String: Any]]
    check(loaded.map(\.id) == [good.id] && bad?.count == 1 && bad?.first?["title"] as? String == "망가진 예약",
          "schedule store: a damaged entry is kept aside in schedules.json.bad, the rest is read")
    let notes = ArisInbox.load(file: inbox).filter { $0.kind == .note }
    check(notes.count == 1 && notes[0].text.contains("schedules.json.bad"), "schedule store: the user is told once, in the inbox")
    _ = ArisScheduleStore.load(file: file)
    check(ArisInbox.load(file: inbox).filter { $0.kind == .note }.count == 1, "schedule store: reading it again tells nobody twice")
    // A change rewrites the store: the damaged entry is safe in .bad, the newer one is kept as it is.
    let another = hbJob(.daily(hour: 9, minute: 0), next: now.addingTimeInterval(7_200))
    try? ArisScheduleStore.add(another, file: file)
    let raw = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [[String: Any]] ?? []
    check(raw.count == 3 && raw.contains { $0["title"] as? String == "새 형식" } && !raw.contains { $0["title"] as? String == "망가진 예약" }
          && ArisScheduleStore.load(file: file).map(\.id) == [good.id, another.id],
          "schedule store: an entry of a newer version is never dropped by a rewrite; the damaged one stays in .bad")
    _ = try? ArisScheduleStore.remove(id: another.id, file: file)
    let afterRemove = (try? JSONSerialization.jsonObject(with: Data(contentsOf: file))) as? [[String: Any]] ?? []
    check(afterRemove.contains { $0["title"] as? String == "새 형식" } && afterRemove.count == 2, "schedule store: a remove keeps the newer entry too")

    // A store that isn't a list at all is kept whole.
    let folder2 = hbFolder()
    let garbled = folder2.appendingPathComponent("schedules.json")
    try? ArisPrivateFile.write(Data("{not json".utf8), to: garbled)
    check(ArisScheduleStore.load(file: garbled).isEmpty, "schedule store: a garbled store reads as empty")
    let kept = (try? String(contentsOf: ArisPrivateFile.badFile(garbled), encoding: .utf8)) ?? ""
    check(kept.contains("not json"), "schedule store: a garbled store is kept whole in .bad")
    // Kept aside where the .bad file can't take it: the store is never written over.
    let folder3 = hbFolder()
    let stuck = folder3.appendingPathComponent("schedules.json")
    try? ArisPrivateFile.write(Data("{not json".utf8), to: stuck)
    FileManager.default.createFile(atPath: ArisPrivateFile.badFile(stuck).path, contents: Data("x".utf8), attributes: [.posixPermissions: 0o644])
    check(ArisScheduleStore.update(file: stuck) { $0 + [good] } == nil && (try? String(contentsOf: stuck, encoding: .utf8)) == "{not json",
          "schedule store: what can't be kept aside is never written over")

    // A store that can't be used is named (the scheduler says so in the inbox).
    let folder4 = hbFolder()
    let open = folder4.appendingPathComponent("schedules.json")
    check(ArisScheduleStore.refusal(file: open) == nil, "schedule store: no store, nothing refused")
    try? ArisPrivateFile.write(Data("[]".utf8), to: open)
    check(ArisScheduleStore.refusal(file: open) == nil, "schedule store: a private store is fine")
    chmod(open.path, 0o644)
    check(ArisScheduleStore.refusal(file: open)?.contains("644") == true, "schedule store: a store others may read is refused, and why is said")
    let scheduler = hbSource("ArisAgent/ArisScheduler.swift")
    check(scheduler.contains("예약 파일(schedules.json)의 권한이 맞지 않아서") && scheduler.contains("guard let reason, !refusalTold"),
          "scheduler: a refused store is said in the inbox once")
}

// MARK: - Item 4: skills.json keeps what it can't read

private func hbSkillStoreTests() {
    let folder = hbFolder()
    let file = folder.appendingPathComponent("skills.json")
    let inbox = folder.appendingPathComponent("inbox.jsonl")
    let record = ArisSkillRecord(name: "pdf", folder: "pdf", title: "PDF", summary: "s", source: "folder", origin: nil, owner: nil, version: nil,
                                 enabled: true, verdict: .safe, accepted: false, acceptedFindings: nil, reviewed: ["SKILL.md"], findings: [], checked: [],
                                 fingerprint: "f", scannedAt: nil, tested: [], addedAt: Date(timeIntervalSince1970: 1_700_000_000))
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let goodRecord = (try? JSONSerialization.jsonObject(with: encoder.encode(record))) ?? [:]
    let state: [String: Any] = ["enabled": true, "deferred": false, "reviewBrain": "claude", "skills": [goodRecord, ["name": "broken"]]]
    FileManager.default.createFile(atPath: file.path, contents: try? JSONSerialization.data(withJSONObject: state), attributes: [.posixPermissions: 0o600])
    let loaded = ArisSkillStore.load(file)
    check(loaded.enabled && loaded.reviewBrain == "claude" && loaded.skills.map(\.name) == ["pdf"],
          "skills store: one record that can't be read no longer resets the whole store")
    let bad = (try? JSONSerialization.jsonObject(with: Data(contentsOf: ArisPrivateFile.badFile(file)))) as? [[String: Any]]
    check(bad?.count == 1 && bad?.first?["name"] as? String == "broken" && ArisInbox.load(file: inbox).filter { $0.kind == .note }.count == 1,
          "skills store: the record is kept in skills.json.bad and the user is told once")
    _ = ArisSkillStore.load(file)
    let written = ArisSkillStore.update(file) { $0 }
    check(written.skills.map(\.name) == ["pdf"] && ArisInbox.load(file: inbox).filter { $0.kind == .note }.count == 1
          && ArisSkillStore.load(file).enabled, "skills store: a write keeps what was read and tells nobody twice")
    // A file that isn't the state at all is kept whole.
    let folder2 = hbFolder()
    let garbled = folder2.appendingPathComponent("skills.json")
    FileManager.default.createFile(atPath: garbled.path, contents: Data("[[[ nope".utf8), attributes: [.posixPermissions: 0o600])
    _ = ArisSkillStore.update(garbled) { $0 }
    check(((try? String(contentsOf: ArisPrivateFile.badFile(garbled), encoding: .utf8)) ?? "").contains("nope"), "skills store: a garbled file is kept whole in .bad")
}

// MARK: - Item 4: a routine's schedules go with it

private func hbRoutineTests() {
    let now = Date()
    let commute = ArisRoutine(id: UUID(), name: "출근", steps: ["날씨 알려 줘"], own: true, created: now, changed: now)
    let commutePrep = ArisRoutine(id: UUID(), name: "출근 준비", steps: ["뉴스 알려 줘"], own: true, created: now, changed: now)
    func scheduled(_ prompt: String) -> ArisScheduledJob {
        ArisScheduledJob(id: UUID(), title: prompt, prompt: prompt, teammate: nil, rule: .daily(hour: 8, minute: 0), created: now,
                         nextRun: now.addingTimeInterval(60), lastRun: nil, runningSince: nil, parked: [])
    }
    let runsCommute = scheduled("출근 루틴 해 줘"), runsPrep = scheduled("출근 준비 루틴 해 줘"), weather = scheduled("날씨 알려 줘")
    let found = ArisRoutineChain.schedules(running: commute, routines: [commute, commutePrep], in: [runsCommute, runsPrep, weather])
    check(found.map(\.id) == [runsCommute.id], "routine delete: only the schedules that run this routine go with it")
    let turn = hbSource("ArisAgent/ArisRoutineTurn.swift")
    check(turn.contains("ArisRoutineChain.schedules(running: routine, routines: routines, in: jobs)") && turn.contains("return jobs.filter { job in !gone.contains"),
          "routine delete: deleting a routine removes its schedules from the store")
    let card = ArisRoutineCopy.deleteCard(commute, schedules: ["출근 (매일 08:00)"], korean: true)
    check(card.detail.contains("그 예약도 함께 지워요") && ArisRoutineCopy.deleteCard(commute, schedules: ["a"], korean: false).detail.contains("deletes that schedule too"),
          "routine delete: the card says the schedule goes too")
}

// MARK: - Item 7: a GitHub skill's limits are its folder's

private func hbTarEntry(_ name: String, body: Data = Data(), type: Character = "0") -> Data {
    var header = [UInt8](repeating: 0, count: 512)
    let nameBytes = Array(name.utf8.prefix(100))
    header.replaceSubrange(0..<nameBytes.count, with: nameBytes)
    let size = Array(String(format: "%011o", body.count).utf8)
    header.replaceSubrange(124..<(124 + size.count), with: size)
    header[156] = type.asciiValue!
    header.replaceSubrange(257..<262, with: Array("ustar".utf8))
    var data = Data(header) + body
    data.append(Data(count: (512 - body.count % 512) % 512))
    return data
}

private func hbGzip(_ tar: Data) -> Data {
    let deflated = (try? (tar as NSData).compressed(using: .zlib) as Data) ?? Data()
    return Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 3]) + deflated + Data(count: 8)
}

private func hbArchiveTests() {
    let skill = Data("---\nname: pdf\ndescription: PDFs\n---\n# PDF\n".utf8)
    let top = "owner-repo-abc123/"
    // A repository bigger than the limits, with a link and an odd path elsewhere, and one small skill folder.
    var repo = hbTarEntry(top, type: "5") + hbTarEntry(top + "skills/pdf/SKILL.md", body: skill) + hbTarEntry(top + "skills/pdf/notes.md", body: Data("n".utf8))
    repo += hbTarEntry(top + "assets/big.bin", body: Data(count: ArisSkillArchive.maxInflated + 1_048_576))
    repo += hbTarEntry(top + "docs/link", type: "2") + hbTarEntry(top + "../escape.txt", body: Data("x".utf8))
    repo += (0..<(ArisSkillArchive.maxEntries + 10)).reduce(into: Data()) { $0 += hbTarEntry(top + "data/\($1).txt") }
    repo += Data(count: 1_024)
    let tarball = hbGzip(repo)
    if case .success(let files) = ArisSkillLink.extract(tarball, path: "skills/pdf") {
        check(files.map(\.path).sorted() == ["SKILL.md", "notes.md"] && files.first { $0.path == "SKILL.md" }?.data == skill,
              "github skill: a big repository with links elsewhere still gives its small skill folder")
    } else {
        check(false, "github skill: a big repository with links elsewhere still gives its small skill folder")
    }
    // Found on its own when the link names no folder.
    check((try? ArisSkillLink.extract(tarball, path: "").get())?.map(\.path).sorted() == ["SKILL.md", "notes.md"], "github skill: the one skill folder is found without a path")
    // Before, the whole repository counted (it was refused as too big).
    check(ArisSkillArchive.gunzip(tarball).flatMap(ArisSkillArchive.untar).map { _ in true } == .failure(.tooBig), "github skill: the whole repository is over the limit")
    // The skill folder's own entries are still checked.
    let linked = hbGzip(hbTarEntry(top + "s/SKILL.md", body: skill) + hbTarEntry(top + "s/evil", type: "2") + hbTarEntry(top + "other.md", body: Data("o".utf8)) + Data(count: 1_024))
    check(ArisSkillLink.extract(linked, path: "s") == .failure(ArisSkillWhy(ArisArchiveProblem.link(top + "s/evil").message)), "github skill: a link in the skill folder is refused")
    let bigSkill = hbGzip(hbTarEntry(top + "s/SKILL.md", body: skill) + hbTarEntry(top + "s/big.bin", body: Data(count: ArisSkillArchive.maxInflated + 1)) + Data(count: 1_024))
    check(ArisSkillLink.extract(bigSkill, path: "s") == .failure(ArisSkillWhy(ArisArchiveProblem.tooBig.message)), "github skill: a skill folder over the limit is refused")
    // A skill at the repository's root is the whole repository: every entry counts.
    let root = hbGzip(hbTarEntry(top + "SKILL.md", body: skill) + hbTarEntry(top + "docs/link", type: "2") + Data(count: 1_024))
    check(ArisSkillLink.extract(root, path: "") == .failure(ArisSkillWhy(ArisArchiveProblem.link(top + "docs/link").message)), "github skill: a root skill is checked whole")
    check(ArisSkillLink.extract(hbGzip(hbTarEntry(top + "README.md", body: Data("r".utf8)) + Data(count: 1_024)), path: "") == .failure("이 저장소에는 SKILL.md가 없어요.")
          && ArisSkillLink.extract(tarball, path: "skills/none") == .failure("그 폴더에 SKILL.md가 없어요."), "github skill: no SKILL.md is said as before")
    check(ArisSkillLink.extract(Data("not gzip at all, really".utf8), path: "") == .failure(ArisSkillWhy(ArisArchiveProblem.notGzip.message)), "github skill: not gzip is refused")
    check(ArisSkillLink.maxDownload >= 100 * 1_048_576 && hbSource("ArisAgent/ArisSkills+Add.swift").contains("ArisSkillLink.extract(data, path: source.path)"),
          "github skill: the add reads the tarball for the skill's folder only")
}

// MARK: - Item 8: a slow gh is not "signed out"

private func hbGitHubTests() {
    typealias G = ArisGitHubStar
    func runner(_ user: G.Run?) -> G.Runner { { _, arguments, _ in arguments.contains("user") ? user : G.Run(status: 0, out: "HTTP/2.0 404 Not Found\n") } }
    check(G.check(gh: "/x/gh", run: runner(G.Run(status: -1, out: "", timedOut: true))) == .unknown, "gh: a login check that ran out of time isn't \"signed out\"")
    check(G.check(gh: "/x/gh", run: runner(G.Run(status: 1, out: "", err: "error connecting to api.github.com"))) == .unknown, "gh: no network isn't \"signed out\"")
    check(G.check(gh: "/x/gh", run: runner(nil)) == .unknown, "gh: a gh that couldn't start isn't \"signed out\"")
    check(G.check(gh: "/x/gh", run: runner(G.Run(status: 4, out: "", err: "You are not logged into any GitHub hosts. To log in, run: gh auth login"))) == .signedOut
          && G.check(gh: "/x/gh", run: runner(G.Run(status: 1, out: "", err: "HTTP 401: Bad credentials"))) == .signedOut,
          "gh: gh saying it has no login is \"signed out\"")
    check(G.timeout >= 10, "gh: each call has 10 s")
    let reply = (try? JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: G.reply(.unknown)))) as? [String: Any]
    check(reply?["gh"] as? String == "unknown" && ArisStarCard.checked(reply) == .web, "gh: the app takes \"unknown\" the browser's way, as any answer short of a login")
    check(hbSource("Aris/private/Aris/ArisAgentClient+Star.swift").contains("timeoutInterval: 20"), "gh: the app waits longer than gh's limit")
}
