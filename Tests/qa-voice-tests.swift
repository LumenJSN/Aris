// QA 2026-11-09, the voice pipeline and the onboarding: BUG-31 (the 단축키 step only lights the keycaps; the 물어보기 step
// is answered read-only, never acted on), and 사용량 › Codex counting Aris's own Codex turns.
import Foundation

@MainActor
func runQAVoiceTests() {
    onboardingTalkKeyTests()
    onboardingPracticeTests()
    codexUsageLedgerTests()
}

// MARK: - BUG-31: what ⌥Space does while the onboarding shows

@MainActor private func onboardingTalkKeyTests() {
    // The owner's pick 4-A (2026-11-11): the shortcut's practice and the first request are one page, and its turn is practice.
    check(ArisOnboardingTalk.mode(phase: .setup, page: .ask) == .practice, "BUG-31: 눌러서 말하기 is a practice turn")
    check(ArisOnboardingTalk.mode(phase: .setup, page: .permissions) == .turn, "BUG-31: the permissions page leaves the key alone")
    check(ArisOnboardingTalk.mode(phase: .setup, page: .dictation) == .turn, "BUG-31: the dictation page leaves the key alone")
    check(ArisOnboardingTalk.mode(phase: .closed, page: .ask) == .turn, "BUG-31: a closed onboarding never holds the key back")
    check(ArisOnboardingTalk.mode(phase: .finish, page: .ask) == .turn, "BUG-31: the finish line is a real turn again")
    check(ArisOnboardingTalk.mode(phase: .intro, page: .ask) == .turn, "BUG-31: a page left from before only counts in setup")
}

// MARK: - BUG-31: the practice turn answers, read-only

@MainActor private func onboardingPracticeTests() {
    typealias P = ArisOnboardingPractice
    check(P.question("What's on my calendar tomorrow afternoon?") == .calendar(day: 1, part: .afternoon), "practice: the example line is a calendar read")
    check(P.question("내일 오후 일정 뭐 있어?") == .calendar(day: 1, part: .afternoon), "practice: Korean example line")
    check(P.question("오늘 일정 알려줘") == .calendar(day: 0, part: .wholeDay), "practice: today's calendar")
    check(P.question("오늘 아침 회의 있어?") == .calendar(day: 0, part: .morning), "practice: this morning")
    check(P.question("지금 몇 시야?") == .time, "practice: the time")
    check(P.question("오늘 며칠이야?") == .date || P.question("오늘 며칠이야?") == .calendar(day: 0, part: .wholeDay) || P.question("오늘 며칠이야?") == .other,
          "practice: a date question never acts")
    // The QA case and every action Aris could take but its own timer (the owner's pick 1-A, 2026-11-11: the first request sets
    // one): none is anything but `.other` (one line, nothing done).
    check(P.question("타이머 5분") == .timer(.timer(seconds: 300, focus: false)), "pick 1-A: a plain timer is the one thing the practice does on the Mac")
    for action in ["*sad music*", "노래 틀어줘", "play some music", "Spotify 틀어", "엄마한테 문자 보내줘", "send a message to Mom",
                   "다운로드 폴더 정리해줘", "delete my files", "볼륨 올려", "할 일에 우유 추가", "사파리 열어"] {
        check(P.question(action) == .other, "BUG-31: practice never acts on “\(action)”")
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 4, minute: 15))!
    let afternoon = P.window(day: 1, part: .afternoon, now: now, calendar: calendar)
    check(afternoon.start == calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12)), "practice: tomorrow afternoon starts at noon")
    check(afternoon.end == calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18)), "practice: and ends at six")
    let today = P.window(day: 0, part: .wholeDay, now: now, calendar: calendar)
    check(today.start == calendar.startOfDay(for: now) && today.end.timeIntervalSince(today.start) == 86_400, "practice: today is midnight to midnight")
    let three = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15))!
    let fourThirty = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 16, minute: 30))!
    let events = [P.Event(title: "1:1", start: fourThirty, isAllDay: false), P.Event(title: "디자인 리뷰", start: three, isAllDay: false),
                  P.Event(title: "휴가", start: calendar.startOfDay(for: three), isAllDay: true)]
    check(P.agenda(events, day: 1, part: .afternoon, korean: true, calendar: calendar) == "내일 오후 일정은 2개예요: 오후 3시 디자인 리뷰, 오후 4시 30분 1:1.",
          "practice: Korean agenda, timed events in order")
    check(P.agenda(events, day: 1, part: .afternoon, korean: false, calendar: calendar) == "2 on your calendar tomorrow afternoon: 3 pm 디자인 리뷰, 4:30 pm 1:1.",
          "practice: English agenda")
    check(P.agenda([], day: 1, part: .afternoon, korean: true, calendar: calendar) == "내일 오후엔 일정이 없어요.", "practice: nothing tomorrow afternoon")
    check(P.agenda([], day: 0, part: .afternoon, korean: false, calendar: calendar) == "Nothing on your calendar this afternoon.", "practice: nothing this afternoon")
    check(P.agenda(events, day: 1, part: .wholeDay, korean: true, calendar: calendar).contains("휴가"), "practice: the whole day names all-day events")
    check(!P.answersOnly(korean: true).isEmpty && !P.answersOnly(korean: false).isEmpty, "practice: the answers-only line exists in both languages")
}

// MARK: - 사용량 › Codex counts Aris's own Codex turns (ephemeral threads leave no session log)

private func codexUsageLedgerTests() {
    typealias L = ArisCodexUsageLedger
    let note: [String: Any] = ["threadId": "t1", "turnId": "u1", "tokenUsage": [
        "total": ["inputTokens": 12_000, "cachedInputTokens": 8_000, "outputTokens": 300, "reasoningOutputTokens": 120, "totalTokens": 12_300],
        "last": ["inputTokens": 12_000, "cachedInputTokens": 8_000, "outputTokens": 300, "totalTokens": 12_300]]]
    let first = L.update(note)
    check(first?.thread == "t1" && first?.total.input == 12_000 && first?.total.cached == 8_000 && first?.total.output == 300, "usage: a tokenUsage update reads its totals")
    check(L.update(["threadId": "t1"]) == nil && L.update(["tokenUsage": ["total": [:]]]) == nil, "usage: anything else is no update")
    var second = first!.total
    second.input = 20_000; second.cached = 15_000; second.output = 500; second.total = 20_500
    let added = L.delta(second, last: nil, previous: first!.total)
    check(added.input == 8_000 && added.cached == 7_000 && added.output == 200, "usage: a thread's running total turns into what it added")
    var shrunk = ArisCodexTotals(); shrunk.input = 3_000; shrunk.output = 50
    var lastTurn = ArisCodexTotals(); lastTurn.input = 2_000; lastTurn.output = 40
    check(L.delta(shrunk, last: lastTurn, previous: second) == lastTurn, "usage: a total that went down counts the latest turn only")
    check(L.delta(first!.total, last: nil, previous: nil) == first!.total, "usage: a thread's first update counts whole")
    let at = Date(timeIntervalSince1970: 1_794_200_000)
    let line = L.line(added, model: "gpt-5.5", at: at).map { String(decoding: $0, as: UTF8.self) } ?? ""
    let keys = (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]).map { Set($0.keys) } ?? []
    check(keys == ["at", "model", "input", "cached", "cacheWrite", "output", "total"], "usage: a ledger line holds counts, the model and the time, nothing else")
    check(!line.contains("t1") && !line.contains("u1"), "usage: no thread or turn id is kept")
    let back = L.raw(Substring(line.trimmingCharacters(in: .newlines)))
    check(back?.usage == added && back?.model == "gpt-5.5" && back.map { abs($0.at.timeIntervalSince(at)) < 1 } == true, "usage: a ledger line reads back as the same event")
    check(L.raw("not json") == nil && L.raw(#"{"at":"x","model":"m"}"#) == nil, "usage: a broken line is skipped")

    // On fixtures only (never ~/.config/aris or ~/.codex): a ledger with today's two Codex turns, counted beside the logs.
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("aris-usage-ledger-\(UUID().uuidString)")
    let saved = L.directory
    L.directory = root.appendingPathComponent("aris")
    let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(12 * 3_600)
    L.record(added, model: "gpt-5.5", at: now.addingTimeInterval(-60))
    L.record(lastTurn, model: "gpt-5.5", at: now.addingTimeInterval(-30))
    L.record(ArisCodexTotals(), model: "gpt-5.5", at: now)
    let mode = ((try? FileManager.default.attributesOfItem(atPath: L.file.path))?[.posixPermissions] as? NSNumber)?.intValue
    check(mode == 0o600, "usage: the ledger is 0600")
    let ledger = L.events(since: now.addingTimeInterval(-3_600))
    check(ledger.count == 2, "usage: a zero update writes no line")
    check(L.events(since: now.addingTimeInterval(-45)).count == 1, "usage: lines before the cutoff are left out")
    var cli = ArisCodexTotals(); cli.input = 1_000; cli.output = 10
    let logs = [ArisCodexRaw(at: now.addingTimeInterval(-10), model: "gpt-5.5", usage: cli)]
    let merged = ArisUsageScanner.codexRaws(logs: logs, ledger: ledger)
    check(merged.count == 3, "usage: Codex counts the CLI's logs and Aris's own turns")
    let events = merged.map { ArisCostEvent(at: $0.at, model: $0.model, tokens: $0.usage.input + $0.usage.output, usd: 0) }
    let today = ArisUsageAggregate.cost(events, now: now, weekEnd: nil).today
    check(today.tokens == added.input + added.output + lastTurn.input + lastTurn.output + cli.input + cli.output,
          "usage: 사용량 › Codex 오늘 토큰 includes Aris's own Codex turns")
    check(ArisUsageAggregate.cost(ArisUsageScanner.codexRaws(logs: [], ledger: []).map { ArisCostEvent(at: $0.at, model: $0.model, tokens: 0, usd: 0) },
                                  now: now, weekEnd: nil).today.tokens == 0, "usage: nothing logged, nothing counted")
    // The Codex driver: each thread/tokenUsage/updated adds only what that thread used since its last update.
    L.directory = root.appendingPathComponent("driver")
    let driver = ArisCodexDriver(model: "gpt-5.5", tools: "/x/aris-tools", instructions: "i", home: "/Users/me")
    func usageLine(_ thread: String, input: Int, output: Int) -> String {
        let total: [String: Any] = ["inputTokens": input, "cachedInputTokens": 0, "outputTokens": output, "totalTokens": input + output]
        let object: [String: Any] = ["method": "thread/tokenUsage/updated", "params": ["threadId": thread, "turnId": "u", "tokenUsage": ["total": total, "last": total]]]
        return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
    check(driver.read(usageLine("a", input: 1_000, output: 50)).isEmpty, "usage: a token update is nothing the turn shows")
    _ = driver.read(usageLine("a", input: 1_600, output: 80))
    _ = driver.read(usageLine("a", input: 1_600, output: 80))
    _ = driver.read(usageLine("b", input: 400, output: 20))
    let counted = L.events(since: .distantPast)
    check(counted.map(\.usage.input) == [1_000, 600, 400] && counted.map(\.usage.output) == [50, 30, 20] && counted.allSatisfy { $0.model == "gpt-5.5" },
          "usage: the driver counts each thread's new tokens once, per thread")
    L.directory = saved
    try? FileManager.default.removeItem(at: root)
}
