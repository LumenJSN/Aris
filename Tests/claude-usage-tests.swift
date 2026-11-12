// Claude Code usage display (mockup claude-usage.html, the owner's pick A with 틈 넓히기): what the ear's ring shows
// (5시간 / 주간 / 자동), the API-key spend against a daily budget (per-session deltas into a local day that survives
// restarts), the budget field's rules, plan detection that never flips on a fresh session, and the session dots'
// adaptive gap (idle sessions merge into the ring; none active closes it).
import Foundation

func runClaudeUsageTests() {
    ringModeTests()
    MainActor.assumeIsolated { spendLedgerTests() }
    planDetectionTests()
    budgetTests()
    budgetEntryTests()
    earDotsTests()
    idleMergeTests()
    ringArcTests()
    usageSettingsTests()
}

private let usageCalendar = { () -> Calendar in
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
}()

/// 2026-11-10 at `hour`:`minute` in Seoul.
private func usageAt(_ hour: Int, _ minute: Int = 0, day: Int = 10) -> Date {
    usageCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func status(_ id: String, cost: Double?, limits: Bool = false, five: Double = 40, week: Double = 20) -> ClaudeStatusReport {
    var json: [String: Any] = ["session_id": id]
    if let cost { json["cost"] = ["total_cost_usd": cost] }
    if limits {
        json["rate_limits"] = ["five_hour": ["used_percentage": five, "resets_at": 1_800_000_000],
                               "seven_day": ["used_percentage": week, "resets_at": 1_800_000_000]]
    }
    return ClaudeStatusReport(json: json)!
}

private func ringModeTests() {
    check(ClaudeRingMode(stored: nil) == .fiveHour && ClaudeRingMode(stored: "junk") == .fiveHour
          && ClaudeRingMode(stored: "sevenDay") == .sevenDay && ClaudeRingMode(stored: "auto") == .auto,
          "ring mode: stored value read back, anything else is 5시간 (today's ring)")
    check(ClaudeRingMode.fiveHour.window(fiveHour: 10, sevenDay: 90) == .fiveHour
          && ClaudeRingMode.sevenDay.window(fiveHour: 90, sevenDay: 10) == .sevenDay, "ring mode: a fixed mode shows its own window")
    check(ClaudeRingMode.auto.window(fiveHour: 63, sevenDay: 21) == .fiveHour
          && ClaudeRingMode.auto.window(fiveHour: 21, sevenDay: 63) == .sevenDay, "ring mode: 자동 shows the window with the higher percent")
    check(ClaudeRingMode.auto.window(fiveHour: 50, sevenDay: 50) == .fiveHour, "ring mode: 자동 keeps 5시간 on a tie (mockup: week > five)")
    check(ClaudeRingMode.auto.window(fiveHour: nil, sevenDay: 30) == .sevenDay
          && ClaudeRingMode.auto.window(fiveHour: 30, sevenDay: nil) == .fiveHour, "ring mode: 자동 with one window reported shows that one")

    let usage = ClaudeUsage(fiveHour: UsageWindow(percent: 63, resetsAt: usageAt(23)), sevenDay: UsageWindow(percent: 21, resetsAt: usageAt(23, day: 14)), updatedAt: usageAt(9))
    let week = ClaudeRingReading.make(plan: .subscription, mode: .sevenDay, usage: usage, spent: 0, budget: 5, now: usageAt(10))
    check(week == .limit(.sevenDay, 21) && week.percent == 21, "ring reading: 주간 fills by the weekly percent")
    check(ClaudeRingReading.make(plan: .unknown, mode: .auto, usage: usage, spent: 3, budget: 5, now: usageAt(10)) == .limit(.fiveHour, 63),
          "ring reading: an undecided plan shows the limits, as before")
    check(ClaudeRingReading.make(plan: .subscription, mode: .fiveHour, usage: nil, spent: 0, budget: 5, now: usageAt(10)).percent == nil,
          "ring reading: no report yet leaves the ring empty")
    let api = ClaudeRingReading.make(plan: .apiKey, mode: .fiveHour, usage: usage, spent: 1.24, budget: 5, now: usageAt(10))
    check(api == .budget(spent: 1.24, budget: 5) && abs((api.percent ?? 0) - 24.8) < 1e-9, "ring reading: an API key fills by today's spend over the budget")
    check(ClaudeRingReading.make(plan: .apiKey, mode: .fiveHour, usage: nil, spent: 1.24, budget: nil, now: usageAt(10)).percent == nil,
          "ring reading: budget off leaves the ring empty")
    check(ClaudeRingReading.budget(spent: 12, budget: 5).percent == 100, "ring reading: spend past the budget fills the ring, no more")
    check(ClaudeRingReading.budget(spent: 4, budget: 5).tintLevel == 1 && ClaudeRingReading.budget(spent: 3.9, budget: 5).tintLevel == 0
          && ClaudeRingReading.budget(spent: 4.75, budget: 5).tintLevel == 2, "ring reading: the budget tints from 80 % (warnAt), red from 95 %")
    check(ClaudeRingReading.limit(.fiveHour, 85).tintLevel == 1 && ClaudeRingReading.limit(.fiveHour, nil).tintLevel == 0,
          "ring reading: a limit tints by the same warnAt rules")
}

@MainActor private func spendLedgerTests() {
    var ledger = ClaudeSpendLedger()
    ledger = ledger.recording(status("a", cost: 0), now: usageAt(9), calendar: usageCalendar)
    ledger = ledger.recording(status("a", cost: 0.40), now: usageAt(9, 5), calendar: usageCalendar)
    ledger = ledger.recording(status("b", cost: 0.25), now: usageAt(9, 6), calendar: usageCalendar)
    ledger = ledger.recording(status("a", cost: 0.90), now: usageAt(9, 30), calendar: usageCalendar)
    check(abs(ledger.spent(at: usageAt(10), calendar: usageCalendar) - 1.15) < 1e-9, "spend: today adds each session's growth (0.90 + 0.25)")
    check(ledger.session("a") == 0.90 && ledger.session("b") == 0.25 && ledger.session("c") == nil, "spend: 이 세션 is the session's own total")
    let same = ledger.recording(status("a", cost: 0.90), now: usageAt(9, 31), calendar: usageCalendar)
    check(abs(same.spent(at: usageAt(10), calendar: usageCalendar) - 1.15) < 1e-9, "spend: a repeated report adds nothing")
    let none = ledger.recording(status("a", cost: nil, limits: true), now: usageAt(9, 32), calendar: usageCalendar)
    check(abs(none.spent(at: usageAt(10), calendar: usageCalendar) - 1.15) < 1e-9, "spend: a report without cost changes nothing")
    let restarted = ledger.recording(status("a", cost: 0.10), now: usageAt(9, 40), calendar: usageCalendar)
    check(abs(restarted.spent(at: usageAt(10), calendar: usageCalendar) - 1.25) < 1e-9, "spend: a session whose total starts over counts from zero again")
    let junk = ledger.recording(ClaudeStatusReport(json: ["session_id": "a", "cost": ["total_cost_usd": -3], "context_window": ["used_percentage": 5]])!, now: usageAt(9, 41), calendar: usageCalendar)
    check(abs(junk.spent(at: usageAt(10), calendar: usageCalendar) - 1.15) < 1e-9, "spend: a negative cost is ignored")

    // Local midnight: the day starts at 0, and a session open across it counts only what it spends after.
    check(ledger.spent(at: usageAt(0, 5, day: 11), calendar: usageCalendar) == 0, "spend: past local midnight today reads $0 before any report")
    let next = ledger.recording(status("a", cost: 1.30), now: usageAt(0, 10, day: 11), calendar: usageCalendar)
    check(abs(next.spent(at: usageAt(0, 11, day: 11), calendar: usageCalendar) - 0.40) < 1e-9 && next.day == "2026-11-11",
          "spend: a session spanning midnight adds only the new day's growth")

    // Survives restarts: encoded and decoded, the same ledger.
    let back = ClaudeSpendLedger.decoded(ledger.encoded())
    check(back == ledger && abs(back.spent(at: usageAt(11), calendar: usageCalendar) - 1.15) < 1e-9, "spend: the ledger survives an app restart")
    check(ClaudeSpendLedger.decoded(nil) == ClaudeSpendLedger() && ClaudeSpendLedger.decoded(Data("nope".utf8)) == ClaudeSpendLedger(),
          "spend: nothing or junk saved starts a fresh ledger")
    // A total that went down is a session that started over: from there on only its new growth counts.
    let grownAgain = restarted.recording(status("a", cost: 0.30), now: usageAt(9, 50), calendar: usageCalendar)
    check(abs(grownAgain.spent(at: usageAt(10), calendar: usageCalendar) - 1.45) < 1e-9 && grownAgain.session("a") == 0.30,
          "spend: after starting over, a session adds only what it spends from its new total")
    // A terminal left open over the weekend: its total was counted on Friday, so Monday adds only Monday's.
    let monday = ledger.recording(status("a", cost: 1.00), now: usageAt(9, day: 13), calendar: usageCalendar)
    check(abs(monday.spent(at: usageAt(10, day: 13), calendar: usageCalendar) - 0.10) < 1e-9,
          "spend: a session quiet for a weekend adds only what it spent since, never its whole total again")
    let old = ledger.recording(status("z", cost: 0.01), now: usageAt(12, day: 10).addingTimeInterval(31 * 86_400), calendar: usageCalendar)
    check(old.seen["a"] == nil && old.seen["z"] != nil, "spend: sessions not heard from in thirty days are forgotten")
    check(!same.changedMoney(from: ledger) && restarted.changedMoney(from: ledger) && next.changedMoney(from: ledger)
          && ClaudeSpendLedger().recording(status("p", cost: 0, limits: true), now: usageAt(9), calendar: usageCalendar).changedMoney(from: ClaudeSpendLedger()),
          "spend: only a new amount, day, session or plan is worth saving, not the time of a repeated report")

    let store = ClaudeStore()
    store.applyStatus(status("s1", cost: 0), now: Date())
    store.applyStatus(status("s1", cost: 0.5), now: Date())
    check(abs(store.spentToday() - 0.5) < 1e-9 && store.sessionSpend("s1") == 0.5, "spend: the store keeps today's ledger")

    // Across an app restart: a second store on the same defaults starts from what the first one saved.
    let suite = testSuiteName("aris-claude-usage-tests")
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let now = Date()
    let first = ClaudeStore(spendStore: defaults)
    first.applyStatus(status("s1", cost: 0), now: now)
    first.applyStatus(status("s1", cost: 0.75), now: now.addingTimeInterval(1))
    let saved = defaults.data(forKey: ClaudeSpendLedger.defaultsKey)
    first.applyStatus(status("s1", cost: 0.75), now: now.addingTimeInterval(2))
    check(saved != nil && defaults.data(forKey: ClaudeSpendLedger.defaultsKey) == saved, "spend: a repeated report doesn't write the saved ledger again")
    let second = ClaudeStore(spendStore: defaults)
    check(abs(second.spentToday(at: now.addingTimeInterval(3)) - 0.75) < 1e-9 && second.spend.plan == .apiKey && second.sessionSpend("s1") == 0.75,
          "spend: after an app restart the store reads today's spend and the plan back")
    second.applyStatus(status("s1", cost: 1.00), now: now.addingTimeInterval(4))
    check(abs(second.spentToday(at: now.addingTimeInterval(5)) - 1.00) < 1e-9, "spend: after an app restart a session adds only its growth since the last report")
    defaults.removePersistentDomain(forName: suite)
}

private func planDetectionTests() {
    let fresh = ClaudeSpendLedger().recording(status("p", cost: 0), now: usageAt(9), calendar: usageCalendar)
    check(fresh.plan == .unknown, "plan: a fresh session with no rate_limits yet is not taken for an API key")
    let firstReply = fresh.recording(status("p", cost: 0.02, limits: true), now: usageAt(9, 1), calendar: usageCalendar)
    check(firstReply.plan == .subscription, "plan: rate_limits after the first response is a plan")
    let resumed = firstReply.recording(status("q", cost: 3.10), now: usageAt(9, 2), calendar: usageCalendar)
    check(resumed.plan == .subscription, "plan: a session first heard with a cost but no limits yet doesn't flip a plan")
    let newPlanSession = resumed.recording(status("r", cost: 0), now: usageAt(9, 3), calendar: usageCalendar)
    check(newPlanSession.plan == .subscription, "plan: a new plan session's first report keeps the plan")

    var api = ClaudeSpendLedger().recording(status("k", cost: 0), now: usageAt(9), calendar: usageCalendar)
    api = api.recording(status("k", cost: 0.07), now: usageAt(9, 1), calendar: usageCalendar)
    check(api.plan == .apiKey, "plan: a session that spent without ever reporting rate_limits is an API key")
    let apiFresh = api.recording(status("k2", cost: 0), now: usageAt(9, 2), calendar: usageCalendar)
    check(apiFresh.plan == .apiKey, "plan: an API key's next fresh session keeps it an API key")
    let switched = apiFresh.recording(status("k3", cost: 0.01, limits: true), now: usageAt(9, 3), calendar: usageCalendar)
    check(switched.plan == .subscription, "plan: logging in to a plan (rate_limits seen) switches back")
    let limitedThenBare = switched.recording(status("k3", cost: 0.04), now: usageAt(9, 4), calendar: usageCalendar)
    check(limitedThenBare.plan == .subscription, "plan: a plan session that once reported limits never makes it an API key")
    check(ClaudeSpendLedger.decoded(api.encoded()).plan == .apiKey, "plan: the decision survives a restart")

    // A plan session and a key session open together: the ring stays on the plan instead of flipping per report.
    var both = ClaudeSpendLedger().recording(status("plan", cost: 0.02, limits: true), now: usageAt(9), calendar: usageCalendar)
    both = both.recording(status("key", cost: 0), now: usageAt(9, 1), calendar: usageCalendar)
    var plans: [ClaudePlan] = []
    for minute in 2...7 {
        let report = minute % 2 == 0 ? status("key", cost: Double(minute) / 100) : status("plan", cost: Double(minute) / 100, limits: true)
        both = both.recording(report, now: usageAt(9, minute), calendar: usageCalendar)
        plans.append(both.plan)
    }
    check(plans.allSatisfy { $0 == .subscription }, "plan: a plan session and a key session open together never flip the ring back and forth")
    let heldKey = both.recording(status("key", cost: 0.50), now: usageAt(9, 16), calendar: usageCalendar)
    check(heldKey.plan == .subscription, "plan: a key session doesn't take the ring while a plan session reported in the last ten minutes")
    let keyAlone = both.recording(status("key", cost: 0.50), now: usageAt(9, 18), calendar: usageCalendar)
    check(keyAlone.plan == .apiKey, "plan: once the plan session has been quiet for ten minutes, the key session's spend takes the ring")
    check(ClaudeSpendLedger.planHold == 600, "plan: the hold is ten minutes")
}

private func budgetTests() {
    check(ClaudeBudget.parse("5") == .success(5) && ClaudeBudget.parse(" 4.5 ") == .success(4.5)
          && ClaudeBudget.parse("$10") == .success(10) && ClaudeBudget.parse("2,75") == .success(2.75),
          "budget: whole, decimal, a typed $ and a decimal comma read")
    check(ClaudeBudget.parse("0.5") == .success(0.5) && ClaudeBudget.parse("1000") == .success(1000), "budget: 0.5 and 1000 are allowed")
    check(ClaudeBudget.parse("0.49") == .failure(.tooSmall) && ClaudeBudget.parse("1000.01") == .failure(.tooLarge),
          "budget: under 0.5 or over 1000 is refused")
    check(ClaudeBudget.parse("") == .failure(.empty) && ClaudeBudget.parse("  ") == .failure(.empty), "budget: an empty field asks for an amount")
    check(ClaudeBudget.parse("abc") == .failure(.notNumber) && ClaudeBudget.parse("1.234") == .failure(.notNumber)
          && ClaudeBudget.parse("-5") == .failure(.notNumber) && ClaudeBudget.parse("1e3") == .failure(.notNumber),
          "budget: anything but a plain amount is refused")
    check(ClaudeBudget.hint(nil) == "0.5에서 1000달러까지 · 소수점도 돼요"
          && ClaudeBudget.hint(.tooSmall) == "0.5달러보다 적게는 정할 수 없어요"
          && ClaudeBudget.hint(.notNumber) == "숫자만 적어 주세요 (예: 4.5)", "budget: the mockup's Korean hints")
    check(ClaudeBudget.hint(.empty) == "금액을 적어 주세요. 쓰지 않으려면 오른쪽 스위치를 꺼요" && ClaudeBudget.hint(.tooLarge) == "1000달러까지 정할 수 있어요"
          && Set(ClaudeBudget.Problem.allCases.map { ClaudeBudget.hint($0) }).count == ClaudeBudget.Problem.allCases.count,
          "budget: every problem has its own hint")
    check(ClaudeBudget.line(5) == "고리가 오늘 쓴 돈을 $5에 대어 채워요" && ClaudeBudget.line(4.5) == "고리가 오늘 쓴 돈을 $4.50에 대어 채워요"
          && ClaudeBudget.line(nil) == "꺼져 있으면 고리가 비어 있어요", "budget: the row's line names the amount, or says the ring stays empty")
    check(ClaudeBudget.stored(7.5) == 7.5 && ClaudeBudget.stored(0.1) == 5 && ClaudeBudget.stored(.nan) == 5 && ClaudeBudget.stored(5000) == 5,
          "budget: a stored value out of range falls back to $5")
    check(ClaudeBudget.money(5) == "$5" && ClaudeBudget.money(1.24) == "$1.24" && ClaudeBudget.money(0.5) == "$0.50" && ClaudeBudget.money(0.004) == "$0",
          "budget: money reads like the mockup ($5, $1.24, $0.50)")
    check(ClaudeBudget.quick == [3, 5, 10], "budget: quick picks $3 / $5 / $10")
    check(ClaudeUsageWords.today(spent: 1.24, budget: 5, session: 0.75, english: false) == "오늘 $1.24 / $5 · 이 세션 $0.75"
          && ClaudeUsageWords.today(spent: 1.24, budget: nil, session: nil, english: true) == "Today $1.24", "budget: the tab's line in Korean and English")
}

/// The "$" field as it is typed in: a good amount is saved at once, a bad one shows its hint and saves nothing.
private func budgetEntryTests() {
    let empty = ClaudeBudgetEntry()
    check(empty.text(saved: 5) == "5" && empty.text(saved: 4.5) == "4.5" && empty.text(saved: 2.75) == "2.75" && empty.text(saved: 2.7) == "2.7"
          && empty.text(saved: 0.5) == "0.5" && empty.text(saved: 1000) == "1000", "budget field: it shows the saved amount without a trailing zero")
    let good = empty.typing("7.5")
    check(good.save == 7.5 && good.entry.problem == nil && good.entry.text(saved: 7.5) == "7.5", "budget field: a good amount is saved as it is typed")
    let bad = good.entry.typing("7.5x")
    check(bad.save == nil && bad.entry.problem == .notNumber && bad.entry.text(saved: 7.5) == "7.5x",
          "budget field: a bad entry shows its hint, stays in the field and saves nothing (the last good amount is kept)")
    check(empty.typing("").save == nil && empty.typing("").entry.problem == .empty && empty.typing("0.2").entry.problem == .tooSmall
          && empty.typing("2000").entry.problem == .tooLarge && empty.typing("2000").save == nil, "budget field: empty, too small and too large save nothing")
    check(bad.entry.settled() == ClaudeBudgetEntry() && bad.entry.settled().text(saved: 7.5) == "7.5",
          "budget field: leaving the field with a bad entry puts the last good amount back")
    check(good.entry.settled() == good.entry, "budget field: leaving it with a good entry changes nothing")
    let trailing = empty.typing("7.")
    check(trailing.save == nil && trailing.entry.problem == .notNumber && trailing.entry.typing("7.2").save == 7.2,
          "budget field: a half-typed decimal waits, then saves once it is whole")
}

private let earSize = 22.5

private func active(_ n: Int) -> [ClaudeEarDots.Session] { (0..<n).map { .init(id: "s\($0)", active: true) } }

private func earDotsTests() {
    let lw = earSize * 0.08, r = (earSize - lw) / 2, cap = (lw / 2) / r
    check(abs(r - 10.35) < 1e-9 && abs(earSize * 0.13 - 2.925) < 1e-9 && abs(cap - 0.087) < 0.001,
          "ear dots: the mockup's numbers (r 10.35, dot 2.9, the cap reaches 0.087 rad)")
    // CLR3: the room between the outer dot's edge and the cap at three dots in today's ±0.9 rad.
    let clr3 = 0.9 - cap - (0.5 + (earSize * 0.13 / 2) / r)
    check(abs(clr3 - 0.172) < 0.001 && abs(ClaudeEarDots.clearance(earSize) - clr3) < 1e-12, "ear dots: CLR3 = 0.9 − 0.087 − (0.5 + 0.141) ≈ 0.172 rad")
    check(ClaudeEarDots.layout([], size: earSize).gap == 0, "ear dots: no active session closes the gap (a full ring)")
    var gaps: [Double] = []
    for n in 1...8 {
        let layout = ClaudeEarDots.layout(active(n), size: earSize)
        gaps.append(layout.gap)
        let dots = layout.dots
        check(dots.count == n && dots.allSatisfy { !$0.merged }, "ear dots: \(n) sessions, \(n) dots (none dropped past 4)")
        check(layout.gap <= 0.4 * .pi + 1e-9, "ear dots: \(n) sessions keep the arc at 60 % or more")
        let clearance = layout.gap - cap - dots.map { abs($0.angle - .pi / 2) + ($0.diameter / 2) / r }.max()!
        check(n >= 3 ? abs(clearance - clr3) < 1e-9 : clearance > clr3, "ear dots: \(n) sessions keep CLR3 off the caps (never less)")
        let between = zip(dots, dots.dropFirst()).map { ($0.angle - $1.angle) * r - ($0.diameter + $1.diameter) / 2 }
        check(n == 8 ? between.allSatisfy { abs($0 - 0.44) < 0.01 } : between.allSatisfy { $0 >= 0.6 - 1e-9 },
              "ear dots: \(n) sessions keep 0.6 px between dots\(n == 8 ? " (8: 0.44 px, the clearance holds)" : "")")
        check(dots.allSatisfy { $0.diameter >= 2.2 - 1e-9 }, "ear dots: \(n) sessions never shrink a dot under 2.2 px")
        check(zip(dots, dots.dropFirst()).allSatisfy { $0.angle > $1.angle } && dots.map(\.id) == (0..<n).map { "s\($0)" },
              "ear dots: \(n) sessions in id order, the first on the left")
        let sum = dots.map { $0.angle - .pi / 2 }.reduce(0, +)
        check(abs(sum) < 1e-9, "ear dots: \(n) sessions sit symmetric about the bottom")
    }
    // The mockup's table: 0.900 for 1–3, 1.150 at 4, the 0.4π cap (1.257) from 5.
    check(zip(gaps, [0.9, 0.9, 0.9, 1.150, 1.257, 1.257, 1.257, 1.257]).allSatisfy { abs($0 - $1) < 0.0005 }, "ear dots: gap(1…8) is the mockup's table")
    check(gaps[0] == 0.9 && gaps[1] == 0.9 && gaps[2] == 0.9, "ear dots: gap(1) = gap(2) = gap(3) = today's ±0.9 rad")
    check(zip(gaps, gaps.dropFirst()).allSatisfy { $0 <= $1 }, "ear dots: the gap never narrows as sessions are added")
    // At the cap: the spacing (centre to centre) tightens first, then the dot shrinks to the floor.
    let atCap: [(n: Int, spacing: Double, dot: Double)] = [(5, 4.43, 2.93), (6, 3.55, 2.93), (7, 3.04, 2.44), (8, 2.64, 2.20)]
    for row in atCap {
        let dots = ClaudeEarDots.layout(active(row.n), size: earSize).dots
        let spacing = (dots[0].angle - dots[1].angle) * r
        check(abs(spacing - row.spacing) < 0.006 && abs(dots[0].diameter - row.dot) < 0.006,
              "ear dots: \(row.n) sessions space \(row.spacing) px apart, \(row.dot) px dots (the mockup's table)")
    }
    check(abs(ClaudeEarDots.maxGap - cap - clr3 - 0.998) < 0.001, "ear dots: at the cap the dots' half-room is 0.998 rad")
}

private func idleMergeTests() {
    let lw = earSize * 0.08
    func sessions(_ flags: [Bool]) -> [ClaudeEarDots.Session] { flags.enumerated().map { .init(id: "s\($0.offset)", active: $0.element) } }
    let mixed = ClaudeEarDots.layout(sessions([true, false, true, true, false]), size: earSize)
    check(mixed.gap == ClaudeEarDots.layout(active(3), size: earSize).gap, "idle merge: the gap counts only the active sessions")
    check(mixed.dots.filter { !$0.merged }.map(\.id) == ["s0", "s2", "s3"], "idle merge: only active sessions take a slot")
    check(ClaudeEarDots.layout(sessions([false, false]), size: earSize).gap == 0, "idle merge: only idle sessions close the gap")
    check(ClaudeEarDots.isActive(.idle) == false && ClaudeEarDots.isActive(.sleeping) == false && ClaudeEarDots.isActive(.happy)
          && ClaudeEarDots.isActive(.notification) && ClaudeEarDots.isActive(.error) && ClaudeEarDots.isActive(.building),
          "idle merge: idle merges; done keeps its dot until it turns idle; waiting and errors are dots")

    // The last of three goes idle: it was on the right, so it goes to the right end (π/2 − gap, the track's end).
    let rightGone = ClaudeEarDots.layout(sessions([true, true, false]), size: earSize)
    let right = rightGone.dots.first { $0.id == "s2" }!
    check(right.merged && right.side == -1 && abs(right.angle - (.pi / 2 - rightGone.gap)) < 1e-9 && abs(right.diameter - lw) < 1e-9,
          "idle merge: a right-hand dot slides to the nearer (right) end and shrinks to the line's width")
    let leftGone = ClaudeEarDots.layout(sessions([false, true, true]), size: earSize)
    let left = leftGone.dots.first { $0.id == "s0" }!
    check(left.merged && left.side == 1 && abs(left.angle - (.pi / 2 + leftGone.gap)) < 1e-9,
          "idle merge: a left-hand dot slides to the nearer (left) end, where the fill starts")
    let middle = ClaudeEarDots.layout(sessions([true, false, true]), size: earSize).dots.first { $0.id == "s1" }!
    check(middle.side == -1, "idle merge: the middle dot goes right, as the mockup's (cx < centre is left)")
    // Emerging is the same place in reverse: an idle session sits in the cap its slot is nearer to.
    let emerging = ClaudeEarDots.layout(sessions([true, true, true]), size: earSize).dots.first { $0.id == "s2" }!
    check(emerging.angle < .pi / 2 && right.side == -1, "idle merge: re-emerging, the dot springs out of the end it went into")
    let lone = ClaudeEarDots.layout(sessions([false]), size: earSize).dots[0]
    check(lone.merged && abs(lone.angle - .pi / 2) < 1e-9, "idle merge: with the ring closed, a merged dot waits where the ends meet")
    check(ClaudeEarDots.capOpacity(side: 1, filled: true) == 1 && ClaudeEarDots.capOpacity(side: 1, filled: false) == 0.22
          && ClaudeEarDots.capOpacity(side: -1, filled: true) == 0.22, "idle merge: the cap's colour strength (full at the filled end, 0.22 on the track)")
}

/// The ring's arc itself: where it starts, how far it turns, and how it closes when no session is at work.
private func ringArcTests() {
    let open = ClaudeEarDots.arc(gap: 0.9, fraction: 1)
    check(abs(open.start - (.pi / 2 + 0.9)) < 1e-12 && abs(open.start + open.sweep - (.pi / 2 - 0.9 + 2 * .pi)) < 1e-12,
          "ring arc: it runs from the fill's start (π/2 + gap) round to the track's end (π/2 − gap)")
    let half = ClaudeEarDots.arc(gap: 0.9, fraction: 0.5)
    check(half.start == open.start && abs(half.sweep - open.sweep / 2) < 1e-12, "ring arc: the fill starts where the track does and covers its share of it")
    let closed = ClaudeEarDots.arc(gap: 0, fraction: 0.63)
    check(abs(closed.start - .pi / 2) < 1e-12 && abs(closed.sweep - 0.63 * 2 * .pi) < 1e-12 && abs(ClaudeEarDots.arc(gap: 0, fraction: 1).sweep - 2 * .pi) < 1e-12,
          "ring arc: with no session at work it is a full turn, and the fill is the percent of a full turn")
    // Halfway through closing, both ends have moved the same way: one value drives the turn and both lengths.
    let mid = ClaudeEarDots.arc(gap: 0.45, fraction: 1)
    check(abs(mid.start - (.pi / 2 + 0.45)) < 1e-12 && abs(mid.start + mid.sweep - (.pi / 2 - 0.45 + 2 * .pi)) < 1e-12,
          "ring arc: while the opening moves its two ends stay mirrored about the bottom")
    check(ClaudeEarDots.arc(gap: 0.9, fraction: 1.4).sweep == open.sweep && ClaudeEarDots.arc(gap: 0.9, fraction: -1).sweep == 0, "ring arc: the fill never leaves the track")
    check(ClaudeEarDots.fill(percent: 63) == 0.63 && ClaudeEarDots.fill(percent: 0) == 0.003 && ClaudeEarDots.fill(percent: 140) == 1,
          "ring arc: the fill is the percent, a sliver at 0 % and full from 100 %")
}

/// 설정 › 대화 › Claude Code: the ring's mode and the daily budget, and that a search finds them.
private func usageSettingsTests() {
    var s = ArisSettingsSnapshot()
    let fresh = ArisSettingsBuilder.sections(.aris, s).first { $0.id == "aris.claude" }
    check(fresh?.heading == "Claude Code" && fresh?.grouped == true && fresh?.rows.map(\.id) == ["aris.claudeRing", "aris.claudeBudget"],
          "settings: 대화 has a Claude Code card with the ring's mode and the daily budget")
    let modes = [ArisSettingOption(id: "fiveHour", title: "5시간"), ArisSettingOption(id: "sevenDay", title: "주간"), ArisSettingOption(id: "auto", title: "자동")]
    check(fresh?.rows.first?.control == .choice(.claudeRing, modes, selected: "fiveHour") && fresh?.rows.first?.title == "귀에 보일 사용량"
          && fresh?.rows.first?.desc == "닫힌 노치 귀의 고리가 5시간 한도를 보여 줘요", "settings: a fresh install shows the 5-hour limit, as the ring always did")
    func ring(_ mode: String) -> ArisSettingItem? {
        s.claudeRing = mode
        return ArisSettingsBuilder.sections(.aris, s).flatMap(\.rows).first { $0.id == "aris.claudeRing" }
    }
    check(ring("sevenDay")?.control == .choice(.claudeRing, modes, selected: "sevenDay") && ring("sevenDay")?.desc == "닫힌 노치 귀의 고리가 주간 한도를 보여 줘요"
          && ring("auto")?.control == .choice(.claudeRing, modes, selected: "auto") && ring("auto")?.desc == "5시간과 주간 중 더 많이 쓴 쪽을 보여 줘요",
          "settings: the row's line says what the picked mode shows")
    check(ring("junk")?.control == .choice(.claudeRing, modes, selected: "fiveHour"), "settings: an unknown saved mode reads as 5시간")
    check(modes.map(\.id) == ClaudeRingMode.allCases.map(\.rawValue), "settings: the segments are the ring's three modes, in order")
    let budget = fresh?.rows.last
    check(budget?.control == .custom("claudeBudget") && budget?.title == "API 키로 쓸 때 하루 예산", "settings: the budget row draws its own field, switch and quick amounts")
    check(ArisSettingsIndex.entry("aris.claudeRing")?.page == .aris && ArisSettingsIndex.entry("aris.claudeBudget")?.page == .aris
          && ArisSettingsIndex.search("예산").first?.id == "aris.claudeBudget" && ArisSettingsIndex.search("귀에 보일").first?.id == "aris.claudeRing"
          && ArisSettingsIndex.search("클로드 코드").map(\.id).contains("aris.claudeRing"), "settings: a search finds both rows")
    check(ArisSettingsLayout.blocks(fresh ?? ArisSettingSection(id: "", rows: [])).count == 1, "settings: both rows share one card")
}
