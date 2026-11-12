// Tests for the day-end summary (ArisDayEnd): the words that ask for it, the day it is about, the evening chip's
// moment, the jobs it reads, the agent's list of tomorrow's schedules and the setting. What the summary says and lists
// (the plan, the sentence, 내일로 넘기기) is in dayend2-tests.swift. Run by run.sh.
import Foundation

func runFeatDayEndTests() {
    dayEndAskTests()
    dayEndSpanTests()
    dayEndJobsTests()
    dayEndOfferTests()
    dayEndScheduleTests()
    dayEndSettingTests()
}

private let seoulDays: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

/// A moment on Wednesday 2026-11-11 (or `day` days from it), Seoul time.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    seoulDays.date(from: DateComponents(year: 2026, month: 11, day: 11 + day, hour: hour, minute: minute))!
}

private func dayEndAskTests() {
    let asks = { (said: String) in ArisDayEndAsk.asks(ArisIntent.phrase(of: said)) }
    for said in ["오늘 정리해 줘", "오늘 정리", "하루 마감", "하루 마감해 줘", "오늘 하루 정리해줘", "오늘 뭐 했어?", "아리스 오늘 뭐 했어", "오늘 뭐 했는지 알려줘",
                 "오늘 한 일 알려줘", "오늘 한 일 정리해 줘", "오늘 하루 마무리하자", "오늘 요약해 줘", "오늘 뭘 했어요?", "오늘 뭐 했는지 정리해 줘",
                 "하루 마감하자", "오늘 한 작업 정리해줘",
                 "wrap up my day", "Wrap up the day, please", "what did you do today", "What did we get done today?", "summarize my day",
                 "today's summary", "end of day summary", "hey aris, wrap up today"] {
        check(asks(said), "day end: “\(said)” asks for the summary")
    }
    for said in ["오늘 받은 메일 정리해 줘", "오늘 회의 내용 정리해 줘", "오늘 한 일 메일로 보내 줘", "오늘 한 일 노션에 정리해 줘", "책상 정리해 줘",
                 "오늘 날씨 어때", "내일 뭐 해", "오늘 일정 정리해 줘", "오늘 마감 뭐 있어", "오늘 한 일 정리해서 메일로 보내 줘", "오늘 정리할 거 뭐 있어", "하루에 물 얼마나 마셔야 해", "오늘 뭐 먹지", "오늘 뭐 했는지 엄마한테 문자 보내",
                 "wrap up this email", "what did the market do today", "summarize today's news", "what should I do today", ""] {
        check(!asks(said), "day end: “\(said)” is not a request for the summary")
    }
    check(ArisIntent.parse("오늘 정리해 줘") == .dayEnd && ArisIntent.parse("wrap up my day") == .dayEnd && ArisIntent.parse("오늘 뭐 했어?") == .dayEnd,
          "day end: the words become the day-end intent, a question included")
    check(ArisIntent.dayEnd.isReadOnly && ArisIntent.guarded(.dayEnd, said: "오늘 뭐 했어?") == .dayEnd, "day end: it only reads, so a question may ask for it")
    check(ArisIntent.parse("브리핑 해줘") == .brief && ArisIntent.parse("오늘 받은 메일 정리해 줘") == .ask("오늘 받은 메일 정리해 줘"),
          "day end: the morning brief and other requests keep their own paths")
    check(ArisIntent.parse("매일 저녁 9시에 오늘 정리해 줘") == .ask("매일 저녁 9시에 오늘 정리해 줘"), "day end: a repeating request is a schedule for the AI, not the summary now")
}

private func dayEndSpanTests() {
    let evening = ArisDaySpan(now: at(21), calendar: seoulDays)
    check(evening.today == at(0) && evening.tomorrow == at(0, day: 1) && evening.afterTomorrow == at(0, day: 2), "day span: in the evening today is today and tomorrow the next day")
    let late = ArisDaySpan(now: at(0, 30, day: 1), calendar: seoulDays)
    check(late.today == at(0) && late.tomorrow == at(0, day: 1), "day span: half past midnight still wraps up the day before")
    check(late.isToday(at(23, 50), now: at(0, 30, day: 1)) && late.isToday(at(0, 10, day: 1), now: at(0, 30, day: 1)) && !late.isToday(at(23, day: -1), now: at(0, 30, day: 1)),
          "day span: past midnight the day runs on until now, and never reaches back a day more")
    check(ArisDaySpan(now: at(5, 0, day: 1), calendar: seoulDays).today == at(0, day: 1), "day span: from five in the morning the new day is today")
    check(evening.isTomorrow(at(9, day: 1)) && !evening.isTomorrow(at(23)) && !evening.isTomorrow(at(0, day: 2)), "day span: tomorrow is the whole next day and nothing else")
}

private func dayEndJobsTests() {
    let span = ArisDaySpan(now: at(20), calendar: seoulDays)
    func job(_ title: String, _ state: ArisJobState, _ assignee: ArisJobAssignee = .clone, created: Date = at(13)) -> ArisJob {
        ArisJob(id: UUID(), title: title, prompt: "", assignee: assignee, cwd: nil, appHint: nil, target: .notch, state: state, created: created)
    }
    let done = job("블랙홀 자료 정리", .done("정리했어요"), .teammate("t1"), created: at(15))
    let jobs = [job("어제 일", .done("x"), created: at(13, day: -1)), job("취소한 일", .cancelled), job("메일 초안", .failed("Gemini 로그인이 필요해요.\n다시 해 주세요."), .helper(2)),
                job("물어볼 일", .awaitingApproval(id: "q9")), job("대기 중인 질문", .awaitingApproval(id: "q1")), job("조사", .running(step: "웹 검색 중")), done]
    let history = [ArisHistoryEntry(date: at(15), heard: "블랙홀 자료 조사해서 정리해 놔", reply: "정리했어요", isTask: true, job: done.id),
                   ArisHistoryEntry(date: at(11), heard: "경쟁사 조사해 놔", reply: "세 곳을 비교했어요", isTask: true, job: UUID()),
                   ArisHistoryEntry(date: at(10), heard: "견적 요청", reply: ArisJobFailure.shown(reason: "연결이 끊겼어요.", korean: true), isTask: true),
                   ArisHistoryEntry(date: at(9), heard: "report", reply: ArisJobFailure.shown(reason: "", korean: false), isTask: true),
                   ArisHistoryEntry(date: at(12), heard: "날씨 어때", reply: "맑아요"),
                   ArisHistoryEntry(date: at(12, day: -1), heard: "어제 맡긴 일", reply: "끝", isTask: true)]
    let facts = ArisDayEndJobs.facts(jobs: jobs, parked: ["q1"], history: history, span: span, now: at(20))
    check(facts.map(\.title) == ["블랙홀 자료 정리", "취소한 일", "메일 초안", "물어볼 일", "조사", "경쟁사 조사해 놔", "견적 요청", "report"],
          "jobs: today's only, a job in the list and in the history once, no parked question's job (\(facts.map(\.title)))")
    check(facts[0].outcome == .done && facts[0].id == done.id.uuidString, "jobs: a listed job is known by its own id")
    check(facts[1].outcome == .stopped, "jobs: one the user stopped himself is listed as stopped, which the list shows as not done")
    check(facts[2].outcome == .failed("Gemini 로그인이 필요해요. 다시 해 주세요."), "jobs: a failed job's reason is one short paragraph")
    check(facts[3].outcome == .asking && facts[4].outcome == .running, "jobs: a question on its way is asking; a queued or running job is running")
    check(facts[5].outcome == .done, "jobs: a result only the history holds is still a job that finished")
    check(facts[6].outcome == .failed("연결이 끊겼어요.") && facts[7].outcome == .failed(""), "jobs: a history entry that says not finished is a failure, with its reason")
    check(ArisDayEndJobs.failure("정리했어요") == nil && ArisDayEndJobs.failure(ArisJobFailure.shown(reason: "x", korean: false)) == "x",
          "jobs: a result is never read as a failure")
}

private func dayEndOfferTests() {
    let due = { (last: Date?, now: Date, idle: TimeInterval, on: Bool) in ArisDayEndOffer.isDue(enabled: on, lastShown: last, now: now, idle: idle, calendar: seoulDays) }
    check(!due(nil, at(17, 59), 0, true) && due(nil, at(18), 0, true) && due(nil, at(23, 30), 10, true), "offer: from six in the evening, never before")
    check(!due(nil, at(19), 600, true) && due(nil, at(19), 60, true), "offer: only while the user is at the Mac")
    check(!due(nil, at(19), 0, false), "offer: never with the setting off")
    check(!due(at(18, 5), at(21), 0, true) && !due(at(19), at(0, 30, day: 1), 0, true), "offer: not twice in one evening, past midnight included")
    check(due(at(14), at(19), 0, true), "offer: a summary asked for in the afternoon doesn't use up the evening's")
    check(due(at(22, day: -1), at(18, 30), 0, true) && due(at(0, 30), at(18, 30), 0, true), "offer: yesterday evening's, even one past midnight, is not today's")
    check(due(nil, at(1, day: 1), 0, true) && !due(nil, at(5, 30, day: 1), 0, true), "offer: the evening runs until the day ends at five")
    check(ArisDayEndOffer.nextCheck(after: at(15), lastShown: nil, calendar: seoulDays) == 3 * 3_600, "offer: in the afternoon the next look is at six")
    check(ArisDayEndOffer.nextCheck(after: at(19), lastShown: nil, calendar: seoulDays) == 60
          && ArisDayEndOffer.nextCheck(after: at(19), lastShown: nil, quiet: true, calendar: seoulDays) == ArisDayEndOffer.quietRecheck,
          "offer: in the evening it looks every minute for the user, and half an hour after finding nothing to tell")
    check(ArisDayEndOffer.nextCheck(after: at(19), lastShown: at(18, 10), calendar: seoulDays) == 23 * 3_600, "offer: once shown, the next look is tomorrow at six")
    check(ArisDayEndOffer.mayShow(turn: false, card: false, dragging: false, onboarding: false) && !ArisDayEndOffer.mayShow(turn: true, card: false, dragging: false, onboarding: false)
          && !ArisDayEndOffer.mayShow(turn: false, card: true, dragging: false, onboarding: false) && !ArisDayEndOffer.mayShow(turn: false, card: false, dragging: true, onboarding: false)
          && !ArisDayEndOffer.mayShow(turn: false, card: false, dragging: false, onboarding: true), "offer: the chip never hangs over a turn, a card, a drag or the guide")
    check(ArisDayEndOffer.hour == 18 && ArisDaySpan.startHour == 5, "offer: the evening is from six, the day from five")
}

private func dayEndScheduleTests() {
    func scheduled(_ title: String, _ rule: ArisRepeat, next: Date?) -> ArisScheduledJob {
        ArisScheduledJob(id: UUID(), title: title, prompt: "p", teammate: nil, rule: rule, created: at(8, day: -3), nextRun: next, lastRun: nil, runningSince: nil, parked: [])
    }
    let jobs = [scheduled("날씨 알려주기", .daily(hour: 8, minute: 0), next: at(8, day: 1)),
                scheduled("주간 보고", .weekly(weekday: 5, hour: 17, minute: 30), next: at(17, 30, day: 1)),
                scheduled("금요일 정리", .weekly(weekday: 6, hour: 9, minute: 0), next: at(9, day: 2)),
                scheduled("메일 확인", .every(seconds: 1_800), next: at(20, 10)),
                scheduled("약 먹기", .once(at(21, day: 1)), next: at(21, day: 1)),
                scheduled("오늘 밤 알림", .once(at(23)), next: at(23)),
                scheduled("끝난 일", .once(at(9)), next: nil)]
    let runs = ArisDayEndRoute.runs(jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoulDays)
    check(runs.map(\.title) == ["메일 확인", "날씨 알려주기", "주간 보고", "약 먹기"], "schedules: tomorrow's runs in order, none from another day (\(runs.map(\.title)))")
    check(runs[0].every == 1_800 && runs[1].at == at(8, day: 1) && runs[1].every == nil && runs[3].at == at(21, day: 1), "schedules: each with its first time tomorrow; one that repeats says how often")
    let body = (try? JSONSerialization.jsonObject(with: ArisDayEndRoute.body(jobs: jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoulDays))) as? [String: Any]
    let listed = body?["schedules"] as? [[String: Any]]
    check(listed?.count == 4 && listed?.first?["title"] as? String == "메일 확인" && listed?.first?["every"] as? Int == 1_800 && listed?[1]["every"] == nil,
          "schedules: the agent answers with titles and times only, never a prompt")
    check(!String(decoding: ArisDayEndRoute.body(jobs: jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoulDays), as: UTF8.self).contains("\"p\""), "schedules: no job's prompt leaves the agent")
    let read = ArisDayEndFacts.schedules(from: ArisDayEndRoute.body(jobs: jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoulDays))
    check(read?.count == 4 && read?[1].title == "날씨 알려주기" && read?[1].at == at(8, day: 1) && read?[0].every == 1_800, "schedules: the app reads the same list back")
    check(ArisDayEndFacts.schedules(from: Data("{}".utf8)) == nil && ArisDayEndFacts.schedules(from: Data("nope".utf8)) == nil,
          "schedules: an agent that doesn't know the question leaves the part out")
    check(ArisDayEndRoute.window(["from": 1_800_000_000.0, "to": 1_800_086_400.0])?.from == Date(timeIntervalSince1970: 1_800_000_000)
          && ArisDayEndRoute.window(["from": 5.0, "to": 1.0]) == nil && ArisDayEndRoute.window(["from": 0.0, "to": 86_400.0 * 30]) == nil && ArisDayEndRoute.window([:]) == nil,
          "schedules: the agent takes one day's window, never a backwards or a month-long one")
}

private func dayEndSettingTests() {
    let rows = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).flatMap(\.rows)
    let row = rows.first { $0.id == ArisDayEndSetting.id }
    check(row?.title == ArisDayEndSetting.title && row?.control == .toggle(.dayEndOffer, true), "setting: the evening chip has one row on the 대화 page, on by default")
    var off = ArisSettingsSnapshot()
    off.dayEndOffer = false
    check(ArisSettingsBuilder.sections(.aris, off).flatMap(\.rows).first { $0.id == ArisDayEndSetting.id }?.control == .toggle(.dayEndOffer, false), "setting: the row shows it off")
    check(ArisSettingsIndex.entry(ArisDayEndSetting.id)?.page == .aris && ArisSettingsIndex.search("오늘 정리").first?.id == ArisDayEndSetting.id
          && ArisSettingsIndex.search("하루 마감").contains { $0.id == ArisDayEndSetting.id }, "setting: a search for 오늘 정리 or 하루 마감 finds it")
}
