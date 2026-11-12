// Tests for the day-end summary as the owner picked it (2-C, "한 문장 + 목록"): the plan built from the day's facts (each
// source, the same thing listed once, the states, overdue, all-day, nothing planned, nothing at all, only unplanned
// work), the one sentence in both languages for every mix of clauses, the counts, 내일로 넘기기 (the date it moves to,
// its line in the record and the undo that puts the date back, the counts after), what the list remembers for the
// day, and the agent's account of today's schedules. Run by run.sh.
import Foundation

func runDayend2Tests() {
    dayend2SourceTests()
    dayend2OnceTests()
    dayend2WaitingTests()
    dayend2TomorrowTests()
    dayend2ExtrasTests()
    dayend2EmptyTests()
    dayend2SentenceTests()
    dayend2NumberTests()
    dayend2CountsTests()
    dayend2EnglishTests()
    dayend2PushTests()
    dayend2UndoTests()
    dayend2KeptTests()
    dayend2ScheduleTests()
    dayend2SourceTextTests()
}

private let seoul2: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

/// A moment on Wednesday 2026-11-11 (or `day` days from it), Seoul time.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    seoul2.date(from: DateComponents(year: 2026, month: 11, day: 11 + day, hour: hour, minute: minute))!
}

private let us = Locale(identifier: "en_US")

/// A time as the system writes it, with an ordinary space where it puts a narrow one ("10:00 AM").
private func plain(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

private func made(_ facts: ArisDayEndFacts, now: Date = at(20), english: Bool = false) -> ArisDayEnd {
    ArisDayEnd.make(facts, now: now, calendar: seoul2, english: english, locale: english ? us : nil)
}

private func did(_ summary: String, job: String = "대화", worker: String = "Aris", at date: Date = at(14), undone: Bool = false) -> ArisActivityItem {
    ArisActivityItem(id: UUID().uuidString, date: date, job: job, worker: worker, summary: summary, undoable: false, undone: undone, asks: false, teammate: nil)
}

/// The day of the mockup: five things planned, three done, two left, one waiting, two tomorrow.
private func mockDay() -> ArisDayEndFacts {
    var facts = ArisDayEndFacts()
    facts.todos = [.init(id: "t1", title: "발표 자료 보내기", due: at(0), completed: at(11)),
                   .init(id: "t2", title: "보고서 초안 쓰기", due: at(18), hasTime: true),
                   .init(id: "t3", title: "엄마한테 전화", due: at(17, day: 1), hasTime: true)]
    facts.events = [.init(start: at(14), end: at(15), title: "팀 회의"), .init(start: at(10, day: 1), end: at(11, day: 1), title: "치과")]
    facts.jobs = [.init(id: "j1", title: "영수증 PDF 합치기", outcome: .done)]
    facts.routines = [.init(title: "저녁 스트레칭", at: at(21), state: .pending)]
    facts.cards = [.init(id: "q1", title: "김민지", action: "메일 답장 초안")]
    return facts
}

private func dayend2SourceTests() {
    let day = made(mockDay())
    check(day.planned.map(\.title) == ["발표 자료 보내기", "오후 2:00 팀 회의", "영수증 PDF 합치기", "보고서 초안 쓰기", "저녁 스트레칭"],
          "plan: what was planned is listed done first, then what is left, each source in its place (\(day.planned.map(\.title)))")
    check(day.planned.map(\.kind) == [.todo, .event, .job, .todo, .routine], "plan: each row knows its kind")
    check(day.planned.map(\.state) == [.done, .done, .done, .none, .none], "plan: a ticked to-do, a meeting that is over and a finished job are done; an open to-do and a routine not run are not")
    check(day.planned.map(\.pushes) == [false, false, false, true, false], "plan: only an open to-do can be put off; an event, a job and a routine never")
    check(day.counts == ArisDayEnd.Counts(planned: 5, done: 3, left: 2, moved: 0, waiting: 1, extra: 0, tomorrow: 2), "plan: the mockup's day counts five, three, two and one")

    var facts = ArisDayEndFacts()
    facts.todos = [.init(id: "old", title: "지난주 숙제", due: at(9, day: -6)), .init(id: "later", title: "다음 주 일", due: at(9, day: 5)),
                   .init(id: "none", title: "언젠가"), .init(id: "y", title: "어제 끝낸 일", due: at(9, day: -1), completed: at(22, day: -1)),
                   .init(id: "early", title: "미리 끝낸 일", due: at(9, day: 3), completed: at(12))]
    let todos = made(facts)
    check(todos.planned.map(\.title) == ["지난주 숙제"] && todos.planned[0].state == .none && todos.planned[0].todo == "old",
          "plan: an overdue to-do is planned for today; one due later, one with no date and one ticked off yesterday are not")
    check(todos.extras.map(\.title) == ["할 일 완료: 미리 끝낸 일"], "plan: a to-do ticked off today that wasn't due is done but not planned")

    facts = ArisDayEndFacts()
    facts.events = [.init(start: at(9), end: at(10), title: "스탠드업"), .init(start: at(19, 30), end: at(21), title: "저녁 약속"),
                    .init(start: at(21), end: at(22), title: "운동"), .init(start: at(0), end: at(23, 59), title: "창립기념일", allDay: true),
                    .init(start: at(22, day: -1), end: at(1), title: "어제 밤 일정")]
    let events = made(facts)
    check(events.planned.map(\.title) == ["오전 9:00 스탠드업", "오후 7:30 저녁 약속", "오후 9:00 운동"] && events.planned.map(\.state) == [.done, .part, .none],
          "plan: an event is done once its end has passed, under way while it runs, and an all-day one is left out (\(events.planned.map(\.title)))")
    check(events.planned.map(\.mark) == [.done, .part, .none] && events.counts.left == 2, "plan: what is under way is marked half and still counts as left")

    facts = ArisDayEndFacts()
    facts.jobs = [.init(id: "d", title: "경쟁사 조사", outcome: .running), .init(id: "c", title: "주간 메일 초안", outcome: .failed("Gemini 로그인이 필요해요.")),
                  .init(id: "b", title: "취소한 조사", outcome: .stopped), .init(id: "a", title: "블랙홀 자료 정리", outcome: .done),
                  .init(id: "q", title: "견적 요청", outcome: .asking)]
    let jobs = made(facts)
    check(jobs.planned.map(\.title) == ["블랙홀 자료 정리", "경쟁사 조사", "취소한 조사", "주간 메일 초안"] && jobs.planned.map(\.state) == [.done, .part, .none, .none],
          "plan: a finished job is done, a running one under way, a stopped or failed one not done (\(jobs.planned.map(\.title)))")
    check(jobs.planned[3].note == "Gemini 로그인이 필요해요." && jobs.planned.allSatisfy { !$0.pushes }, "plan: a failed job keeps its reason for the tooltip, and has no button")
    check(jobs.waiting.map(\.title) == ["견적 요청"] && !jobs.planned.contains { $0.title == "견적 요청" }, "plan: a job waiting on a card is in the waiting part, never also planned")

    facts = ArisDayEndFacts()
    facts.routines = [.init(title: "아침 날씨", at: at(8), state: .done), .init(title: "점심 메일 확인", at: at(12), state: .failed),
                      .init(title: "주간 보고", at: at(17), state: .running), .init(title: "약 먹기 알림", at: at(22), state: .pending, repeats: false)]
    facts.deadlines = [.init(course: "경영학", title: "과제 제출", at: at(23, 59)), .init(course: "마케팅", title: "발표", at: at(14, day: 2))]
    let routines = made(facts)
    check(routines.planned.map(\.title) == ["아침 날씨", "주간 보고", "경영학 과제 제출", "점심 메일 확인", "약 먹기 알림"]
          && routines.planned.map(\.state) == [.done, .part, .none, .none, .none],
          "plan: a schedule that ran is done; one that failed, was missed or is still ahead is not; a deadline due today is planned (\(routines.planned.map(\.title)))")
    check(routines.planned.map(\.kind) == [.routine, .routine, .deadline, .routine, .job], "plan: a schedule that comes back is a routine, a one-time one something asked for")
}

private func dayend2OnceTests() {
    var facts = ArisDayEndFacts()
    facts.todos = [.init(id: "t1", title: "우유 사기", due: at(0), completed: at(13))]
    facts.activity = [did("할 일 완료: 우유 사기", at: at(13)), did("타이머: 25분", at: at(15))]
    let ticked = made(facts)
    check(ticked.planned.map(\.title) == ["우유 사기"] && ticked.planned[0].state == .done && ticked.extras.map(\.title) == ["타이머: 25분"],
          "once: a to-do Aris ticked off is one row, done; its line in the record is not listed again")

    facts = ArisDayEndFacts()
    facts.jobs = [.init(id: "2", title: "보고서 정리", outcome: .done), .init(id: "1", title: "보고서  정리.", outcome: .failed("끊겼어요"))]
    check(made(facts).planned.map(\.state) == [.done] && made(facts).planned.count == 1, "once: a job asked for twice is one row with its best outcome")

    facts = ArisDayEndFacts()
    facts.routines = [.init(title: "아침 날씨 알려주기", at: at(8), state: .done)]
    facts.jobs = [.init(id: "h", title: "아침 날씨 알려주기", outcome: .done), .init(id: "j", title: "빌드 폴더 정리", outcome: .done)]
    facts.activity = [did("휴지통으로: old.zip", job: "빌드 폴더 정리", worker: "코디", at: at(16)), did("변환: 영수증.heic → 영수증.pdf", at: at(17))]
    let both = made(facts)
    check(both.planned.map(\.title) == ["빌드 폴더 정리", "아침 날씨 알려주기"] && both.planned.map(\.kind) == [.job, .routine],
          "once: a schedule's result in the history is the schedule's row, not a second one (\(both.planned.map(\.title)))")
    check(both.extras.map(\.title) == ["변환: 영수증.heic → 영수증.pdf"], "once: the record's lines of a listed job are that job; a conversion asked for on the spot is 그 밖")
}

private func dayend2WaitingTests() {
    var facts = ArisDayEndFacts()
    facts.cards = [.init(id: "q1", title: "김민지", action: "메일 답장 초안"), .init(id: "q2", title: "파일 정리", action: "파일 정리"), .init(id: "q3", title: "주간 보고", action: " ")]
    facts.jobs = [.init(id: "a", title: "견적 요청", outcome: .asking)]
    let day = made(facts)
    check(day.waiting.map(\.title) == ["메일 답장 초안 · 김민지", "파일 정리", "주간 보고", "견적 요청"], "waiting: a parked card says what it asks and whose it is (\(day.waiting.map(\.title)))")
    check(day.waiting.map(\.card) == ["q1", "q2", "q3", nil], "waiting: 보기 brings a parked card back; a question on its way has no button")
    check(day.counts.waiting == 4 && day.counts.planned == 0 && day.marks.map(\.count) == [4] && day.marks.first?.mark == .wait, "waiting: counted on the row, and never as planned")
}

private func dayend2TomorrowTests() {
    var facts = ArisDayEndFacts()
    facts.events = [.init(start: at(15, day: 1), end: at(16, day: 1), title: "디자인 리뷰"), .init(start: at(0, day: 1), end: at(23, 59, day: 1), title: "워크숍", allDay: true),
                    .init(start: at(9, day: 2), end: at(10, day: 2), title: "모레 일정")]
    facts.todos = [.init(id: "a", title: "엄마한테 전화", due: at(17, day: 1), hasTime: true), .init(id: "b", title: "보고서 내기", due: at(0, day: 1)),
                   .init(id: "c", title: "이미 끝낸 내일 일", due: at(9, day: 1), hasTime: true, completed: at(10))]
    facts.deadlines = [.init(course: "경영학", title: "과제 제출", at: at(23, 59, day: 1))]
    facts.schedules = [.init(title: "아침 날씨", at: at(8, day: 1)), .init(title: "메일 확인", at: at(0, 30, day: 1), every: 1_800), .init(title: "약 먹기", at: at(21, day: 1), repeats: false)]
    let day = made(facts)
    check(day.counts.tomorrow == 8 && day.tomorrow.count == ArisDayEndPlan.tomorrowShown, "tomorrow: everything is counted, the first four are listed")
    check(day.tomorrow.map(\.time) == ["오전 8:00", "오후 3:00", "오후 5:00", "오후 9:00"] && day.tomorrow.map(\.title) == ["아침 날씨", "디자인 리뷰", "엄마한테 전화", "약 먹기"],
          "tomorrow: the first things by their time (\(day.tomorrow.map(\.time)))")
    check(day.tomorrow.map(\.kind) == [.routine, .event, .todo, .job], "tomorrow: each row knows its kind")
    let all = ArisDayEndPlan.tomorrow(facts, span: ArisDaySpan(now: at(20), calendar: seoul2), english: false) { ArisUIDates.time($0, english: false, calendar: seoul2) }
    check(all.suffix(3).map(\.time) == ["종일", "", "30분마다"] && all.suffix(3).map(\.title) == ["워크숍", "보고서 내기", "메일 확인"],
          "tomorrow: what has no time of its own comes last: an all-day event, a to-do for the day, a schedule that repeats (\(all.suffix(3).map(\.time)))")
    let late = made(facts, now: at(0, 30, day: 1))
    check(late.tomorrow.first?.title == "아침 날씨", "tomorrow: asked past midnight, tomorrow is the day that has just begun")
    check(made(ArisDayEndFacts()).tomorrow.isEmpty, "tomorrow: nothing due is no row")
}

private func dayend2ExtrasTests() {
    var facts = ArisDayEndFacts()
    facts.activity = [did("볼륨 30", at: at(10)), did("타이머: 25분", at: at(11)), did("변환: 3개 → PNG", at: at(12)), did("할 일 추가: 우유", at: at(13), undone: true),
                      did("내일로 넘김: 보고서 초안", at: at(19)), did("어제 한 일", at: at(14, day: -1)), did("예약: standup (매일 09:00)", at: at(9))]
    let day = made(facts)
    check(day.extras.map(\.title) == ["변환: 3개 → PNG", "타이머: 25분", "볼륨 30", "예약: standup (매일 09:00)"],
          "extras: today's unplanned work newest first; nothing undone, nothing from yesterday, and putting a to-do off is not work done (\(day.extras.map(\.title)))")
    check(day.counts.planned == 0 && day.counts.extra == 4 && day.sentence == "오늘 따로 정한 일은 없었고, 네 가지를 했어요.", "extras: with nothing planned the sentence says what was done (\(day.sentence))")
    let english = made(facts, english: true)
    check(english.extras.map(\.title) == ["Converted: 3 → PNG", "Timer: 25 min", "Volume 30", "Scheduled: standup (every day at 09:00)"],
          "extras: in English the record's lines are said in English, a schedule's time included (\(english.extras.map(\.title)))")
    check(english.sentence == "Nothing was planned for today, and four things got done.", "extras: the same sentence in English (\(english.sentence))")
    facts.todos = [.init(id: "t", title: "보고서 초안", due: at(0))]
    let planned = made(facts)
    check(planned.counts.extra == 4 && planned.sentence == "오늘 하려던 한 가지가 아직 남았어요.", "extras: once something was planned, unplanned work stays out of the sentence (\(planned.sentence))")
    facts.activity = (1...15).map { did("이름 바꿈: f\($0)", at: at(10, $0)) }
    check(made(facts).extras.count == ArisDayEndPlan.extrasShown && made(facts).counts.extra == 15, "extras: a long day's are counted whole and listed up to twelve")
    check(ArisDayEndPlan.parts("변환: a: b") == ("변환", "a: b") && ArisDayEndPlan.parts("볼륨 30") == ("볼륨 30", ""), "extras: a line's kind is what stands before its first colon")
}

private func dayend2EmptyTests() {
    let nothing = made(ArisDayEndFacts())
    check(nothing.planned.isEmpty && nothing.waiting.isEmpty && nothing.tomorrow.isEmpty && nothing.extras.isEmpty && !nothing.hasNews && !nothing.hasList && nothing.marks.isEmpty,
          "empty: a day with nothing has no list and is not worth a chip")
    check(nothing.sentence == "오늘은 정한 일도 한 일도 없었어요." && made(ArisDayEndFacts(), english: true).sentence == "Nothing was planned or done today.",
          "empty: it says so in one short sentence (\(nothing.sentence))")
    let unread = made(ArisDayEndFacts(activity: nil))
    check(unread.activityUnread && unread.hasList && unread.sentence == "오늘 따로 정한 일은 없었어요. 오늘 한 일 기록은 지금 읽지 못했어요.",
          "empty: a record that couldn't be read is said to be missing, never told as nothing done (\(unread.sentence))")
    check(made(ArisDayEndFacts(activity: nil), english: true).sentence == "Nothing was planned for today. I couldn't read today's activity record just now.", "empty: the same in English")
    var only = ArisDayEndFacts()
    only.cards = [.init(id: "q", title: "주간 보고", action: "메일 보내기")]
    check(made(only).sentence == "오늘은 정한 일도 한 일도 없었어요. 확인을 기다리는 일이 하나 있어요." && made(only).hasNews,
          "empty: something waiting is still told (\(made(only).sentence))")
}

private func dayend2SentenceTests() {
    typealias C = ArisDayEnd.Counts
    let ko = { (c: C) in ArisDayEndCopy.sentence(c, unread: false, english: false) }
    let en = { (c: C) in ArisDayEndCopy.sentence(c, unread: false, english: true) }
    let cases: [(C, String, String)] = [
        (C(planned: 5, done: 3, left: 2, waiting: 1), "오늘 하려던 다섯 가지 중 세 가지를 끝냈어요. 두 가지가 남았고, 하나는 확인을 기다려요.",
         "You finished three of the five things you planned for today. Two are left, and one is waiting for your OK."),
        (C(planned: 5, done: 3, left: 2), "오늘 하려던 다섯 가지 중 세 가지를 끝냈어요. 두 가지가 남았어요.", "You finished three of the five things you planned for today. Two are left."),
        (C(planned: 3, done: 3), "오늘 하려던 세 가지를 모두 끝냈어요.", "You finished all three things you planned for today."),
        (C(planned: 1, done: 1), "오늘 하려던 한 가지를 끝냈어요.", "You finished the one thing you planned for today."),
        (C(planned: 2, done: 2, waiting: 2), "오늘 하려던 두 가지를 모두 끝냈어요. 확인을 기다리는 일이 둘 있어요.",
         "You finished both things you planned for today. Two things are waiting for your OK."),
        (C(planned: 4, left: 4), "오늘 하려던 네 가지가 아직 남았어요.", "All four things you planned for today are still open."),
        (C(planned: 1, left: 1, waiting: 1), "오늘 하려던 한 가지가 아직 남았어요. 확인을 기다리는 일이 하나 있어요.",
         "The one thing you planned for today is still open. One thing is waiting for your OK."),
        (C(planned: 2, moved: 2), "오늘 하려던 두 가지를 모두 내일로 넘겼어요.", "You moved both things you planned for today to tomorrow."),
        (C(planned: 5, done: 3, left: 1, moved: 1, waiting: 1), "오늘 하려던 다섯 가지 중 세 가지를 끝냈어요. 한 가지가 남았고, 한 가지는 내일로 넘겼고, 하나는 확인을 기다려요.",
         "You finished three of the five things you planned for today. One is left, one moved to tomorrow, and one is waiting for your OK."),
        (C(planned: 4, done: 3, moved: 1), "오늘 하려던 네 가지 중 세 가지를 끝냈어요. 한 가지는 내일로 넘겼어요.",
         "You finished three of the four things you planned for today. One moved to tomorrow."),
        (C(planned: 3, left: 2, moved: 1), "오늘 하려던 세 가지 중 끝낸 건 아직 없어요. 두 가지가 남았고, 한 가지는 내일로 넘겼어요.",
         "You haven't finished any of the three things you planned for today yet. Two are left, and one moved to tomorrow."),
        (C(planned: 4, done: 1, moved: 3, waiting: 3), "오늘 하려던 네 가지 중 한 가지를 끝냈어요. 세 가지는 내일로 넘겼고, 셋은 확인을 기다려요.",
         "You finished one of the four things you planned for today. Three moved to tomorrow, and three are waiting for your OK."),
        (C(extra: 3), "오늘 따로 정한 일은 없었고, 세 가지를 했어요.", "Nothing was planned for today, and three things got done."),
        (C(extra: 1, tomorrow: 2), "오늘 따로 정한 일은 없었고, 한 가지를 했어요.", "Nothing was planned for today, and one thing got done."),
        (C(waiting: 1, extra: 2), "오늘 따로 정한 일은 없었고, 두 가지를 했어요. 확인을 기다리는 일이 하나 있어요.",
         "Nothing was planned for today, and two things got done. One thing is waiting for your OK."),
        (C(), "오늘은 정한 일도 한 일도 없었어요.", "Nothing was planned or done today."),
    ]
    for (counts, korean, english) in cases {
        check(ko(counts) == korean, "sentence: \(korean) (got \(ko(counts)))")
        check(en(counts) == english, "sentence: \(english) (got \(en(counts)))")
    }
    // Every mix of zero and non-zero clauses reads as one or two short sentences, never with a zero in it.
    var mixes = 0
    for done in [0, 2] { for left in [0, 1] { for moved in [0, 3] { for waiting in [0, 1] { for extra in [0, 4] {
        let counts = C(planned: done + left + moved, done: done, left: left, moved: moved, waiting: waiting, extra: extra)
        mixes += 1
        for english in [false, true] {
            let said = ArisDayEndCopy.sentence(counts, unread: false, english: english)
            let sentences = said.components(separatedBy: ". ").count
            check(sentences <= 2 && said.hasSuffix(".") && !said.contains("0") && !said.contains("zero") && said.range(of: #"\d"#, options: .regularExpression) == nil
                  && (english ? said.unicodeScalars.allSatisfy { !(0xAC00...0xD7A3).contains($0.value) } : true),
                  "sentence: done \(done), left \(left), moved \(moved), waiting \(waiting), extra \(extra) in \(english ? "English" : "Korean") is short and whole (\(said))")
        }
    } } } } }
    check(mixes == 32, "sentence: all thirty-two mixes were said")
}

private func dayend2NumberTests() {
    let things = [1: "한 가지", 2: "두 가지", 3: "세 가지", 4: "네 가지", 5: "다섯 가지", 10: "열 가지", 11: "열한 가지", 14: "열네 가지", 20: "스무 가지", 21: "스물한 가지",
                  35: "서른다섯 가지", 99: "아흔아홉 가지", 120: "120가지"]
    check(things.allSatisfy { ArisDayEndCopy.things($0.key) == $0.value }, "numbers: a count of things is said in words, past ninety-nine in figures")
    let alone = [1: "하나", 2: "둘", 3: "셋", 4: "넷", 5: "다섯", 10: "열", 12: "열둘", 20: "스물", 23: "스물셋", 100: "100개"]
    check(alone.allSatisfy { ArisDayEndCopy.alone($0.key) == $0.value }, "numbers: a count standing by itself has its own words")
    check(ArisDayEndCopy.number(1) == "one" && ArisDayEndCopy.number(12) == "twelve" && ArisDayEndCopy.number(20) == "twenty" && ArisDayEndCopy.number(21) == "21",
          "numbers: English counts are words up to twenty")
    check(ArisDayEndCopy.sentence(.init(planned: 3, done: 1, left: 2, waiting: 2), unread: false, english: false).hasSuffix("둘은 확인을 기다려요.")
          && ArisDayEndCopy.sentence(.init(planned: 3, done: 1, left: 2, waiting: 5), unread: false, english: false).hasSuffix("다섯은 확인을 기다려요."),
          "numbers: the particle follows the number's last sound")
}

private func dayend2CountsTests() {
    let day = made(mockDay())
    check(day.marks.map(\.mark) == [.done, .none, .wait] && day.marks.map(\.count) == [3, 2, 1], "counts: the 목록 row carries done, not done and waiting")
    check(day.sentence == "오늘 하려던 다섯 가지 중 세 가지를 끝냈어요. 두 가지가 남았고, 하나는 확인을 기다려요.", "counts: the mockup's sentence, word for word (\(day.sentence))")
    check(day.chip == "오늘 정리 · 끝냄 3 · 남음 2 · 확인 1 · 내일 2" && day.chipDetail == "· 끝냄 3 · 남음 2 · 확인 1 · 내일 2" && day.hasNews && day.hasList,
          "counts: the evening chip counts the same things (\(day.chip))")
    var facts = ArisDayEndFacts()
    facts.todos = [.init(id: "t", title: "끝낸 일", due: at(0), completed: at(9))]
    check(made(facts).marks.map(\.count) == [1] && made(facts).chip == "오늘 정리 · 끝냄 1", "counts: a count of zero is never drawn")
    facts = ArisDayEndFacts(activity: [did("타이머: 5분")])
    check(made(facts).chip == "오늘 정리 · 끝냄 1" && made(facts).marks.map(\.count) == [1] && made(facts).marks.first?.mark == .done && made(facts).hasList,
          "counts: with nothing planned the row and the chip count what was done anyway")
    check(ArisDayEndCopy.plannedTitle(5, english: false) == "오늘 하려던 일 · 5" && ArisDayEndCopy.waitingTitle(1, english: false) == "내 확인 · 1"
          && ArisDayEndCopy.tomorrowTitle(2, english: false) == "내일 · 2" && ArisDayEndCopy.extrasTitle(3, english: false) == "그 밖 · 3" && ArisDayEndCopy.list(english: false) == "목록",
          "counts: the tiles are named as the mockup names them")
    check([ArisDayEnd.Kind.todo, .event, .deadline, .job, .routine].map { ArisDayEndCopy.kind($0, english: false) } == ["할 일", "일정", "마감", "시킨 일", "루틴"],
          "counts: the kinds are 할 일, 일정, 마감, 시킨 일 and 루틴")
}

private func dayend2EnglishTests() {
    var facts = mockDay()
    facts.activity = [did("타이머: 25분"), did("예약 취소: 저녁 알림 (매주 금 18:00)")]
    facts.schedules = [.init(title: "mail check", at: at(0, 30, day: 1), every: 7_200)]
    let day = made(facts, english: true)
    check(day.sentence == "You finished three of the five things you planned for today. Two are left, and one is waiting for your OK.", "english: the sentence (\(day.sentence))")
    check(plain(day.planned[1].title) == "2:00 PM 팀 회의" && day.tomorrow.map(\.time).map(plain) == ["10:00 AM", "5:00 PM", "every 2 h"], "english: times are written the English way (\(day.tomorrow.map(\.time)))")
    check(day.chip == "Today's wrap-up · 3 done · 2 left · 1 waiting · 3 tomorrow", "english: the chip (\(day.chip))")
    let hangul = { (text: String) in text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) } }
    let own: [String] = [ArisDayEndCopy.list(english: true), ArisDayEndCopy.listHelp(open: true, english: true), ArisDayEndCopy.listHelp(open: false, english: true),
                         ArisDayEndCopy.plannedTitle(5, english: true), ArisDayEndCopy.waitingTitle(1, english: true), ArisDayEndCopy.tomorrowTitle(2, english: true),
                         ArisDayEndCopy.extrasTitle(2, english: true), ArisDayEndCopy.extrasUnread(english: true), ArisDayEndCopy.push(english: true),
                         ArisDayEndCopy.pushed(english: true), ArisDayEndCopy.notPushed(english: true), ArisDayEndCopy.show(english: true), ArisDayEndCopy.allDay(english: true),
                         ArisDayEndCopy.andMore(3, english: true), ArisDayEndCopy.every(seconds: 1_800, english: true), ArisDayEndCopy.title(english: true),
                         ArisDayEndCopy.remembered(english: true), ArisDayEndCopy.chipHelp(english: true), day.sentence, day.chip]
        + [ArisDayEnd.Kind.todo, .event, .deadline, .job, .routine].map { ArisDayEndCopy.kind($0, english: true) }
        + [ArisDayEnd.Mark.done, .part, .none, .wait].map { ArisDayEndCopy.mark($0, english: true) } + day.tomorrow.map(\.time)
    check(own.allSatisfy { !hangul($0) }, "english: none of the list's own words is Korean on an English Mac (\(own.filter(hangul)))")
    check(day.extras.map(\.title) == ["Timer: 25 min", "Schedule cancelled: 저녁 알림 (every Friday at 18:00)"],
          "english: a line of the record keeps its names and loses its Korean words, a schedule's time too (\(day.extras.map(\.title)))")
    check(ArisReceiptWords.line(ArisDayEndPush.logLine("report draft"), english: true) == "Moved to tomorrow" && ArisReceiptWords.line(ArisDayEndPush.logLine("보고서"), english: false) == "내일로 넘김"
          && ArisActivityWords.english(ArisDayEndPush.logLine("report draft")) == "Moved to tomorrow: report draft",
          "english: the receipt and the Activity tab say the move in English")
}

private func dayend2PushTests() {
    let tomorrow = at(0, day: 1)
    check(ArisDayEndPush.due(after: at(18), hasTime: true, tomorrow: tomorrow, calendar: seoul2) == at(18, day: 1), "push: a timed to-do moves to tomorrow at the same time of day")
    check(ArisDayEndPush.due(after: at(9, 30, day: -6), hasTime: true, tomorrow: tomorrow, calendar: seoul2) == at(9, 30, day: 1), "push: an overdue one moves to tomorrow too, keeping its time")
    check(ArisDayEndPush.due(after: at(0), hasTime: false, tomorrow: tomorrow, calendar: seoul2) == tomorrow && ArisDayEndPush.due(after: nil, hasTime: false, tomorrow: tomorrow, calendar: seoul2) == tomorrow,
          "push: a to-do for the day moves to tomorrow with no time")
    let late = ArisDaySpan(now: at(0, 30, day: 1), calendar: seoul2)
    check(ArisDayEndPush.due(after: at(18), hasTime: true, tomorrow: late.tomorrow, calendar: seoul2) == at(18, day: 1), "push: past midnight tomorrow is the day that has just begun, never a day further")
    check(ArisDayEndPush.logLine("보고서 초안 쓰기") == "내일로 넘김: 보고서 초안 쓰기" && ArisDayEndPush.logLine("a\nb") == "내일로 넘김: a b" && ArisDayEndPush.logKind == "todo-due",
          "push: the record's line names the to-do on one line")

    // Before the press, after it (Reminders now has the to-do due tomorrow and the list remembers the move), after its undo.
    var facts = mockDay()
    let before = made(facts)
    facts.todos[1] = .init(id: "t2", title: "보고서 초안 쓰기", due: at(18, day: 1), hasTime: true)
    facts.moved = ["t2"]
    let after = made(facts)
    let row = after.planned.first { $0.todo == "t2" }
    check(row?.state == .moved && row?.pushes == false && after.planned.count == before.planned.count, "push: the row stays on the list as 넘겼어요, without its button")
    check(after.counts.left == before.counts.left - 1 && after.counts.moved == 1 && after.counts.planned == 5 && after.marks.map(\.count) == [3, 1, 1],
          "push: the counts update: one less left, the same five planned")
    check(after.counts.tomorrow == before.counts.tomorrow + 1 && after.tomorrow.map(\.title).contains("보고서 초안 쓰기"), "push: it is one of tomorrow's things now")
    check(after.sentence == "오늘 하려던 다섯 가지 중 세 가지를 끝냈어요. 한 가지가 남았고, 한 가지는 내일로 넘겼고, 하나는 확인을 기다려요.", "push: the sentence says it was put off (\(after.sentence))")
    check(after.planned.last?.todo == "t2", "push: what was put off goes to the end of the list")
    facts.moved = []
    check(!made(facts).planned.contains { $0.todo == "t2" }, "push: a to-do that was due tomorrow all along is not planned for today")
    facts.todos[1] = .init(id: "t2", title: "보고서 초안 쓰기", due: at(18), hasTime: true)
    facts.moved = ["t2"]
    check(made(facts) == before, "push: undone, the row is open again with its button, and the counts are as they were")
}

private func dayend2UndoTests() {
    let due = at(18).timeIntervalSince1970
    check(ArisActivity.localUndo(kind: "todo-due", id: "r1", level: nil, due: due, timed: true) == .some(.restoreTodoDue(id: "r1", due: due, timed: true)),
          "undo: a to-do put off is logged with the date it had, which its undo puts back")
    check(ArisActivity.localUndo(kind: "todo-due", id: "r1", level: nil) == nil && ArisActivity.localUndo(kind: "todo-due", id: nil, level: nil, due: due) == nil
          && ArisActivity.localUndo(kind: "todo-due", id: "r1", level: nil, due: 12) == nil && ArisActivity.localUndo(kind: "todo-due", id: "r1", level: nil, due: .infinity) == nil,
          "undo: never without the to-do's id or a real date")
    check(ArisUndo.restoreTodoDue(id: "r", due: due, timed: false).action == "changed" && ArisUndo.restoreTodoDue(id: "r", due: due, timed: false).scope == .calendar
          && !ArisActivity.needsYes(.restoreTodoDue(id: "r", due: due, timed: false)), "undo: it is a change of the calendar's kind and asks nothing more (the press and the undo are both the user's)")
    check(ArisActivityBridge.localLogArguments(kind: "todo-due", summary: "내일로 넘김: 보고서", id: "x-apple://R/1", level: nil, due: due, timed: true)
          == ["activity", "log", "--kind", "todo-due", "--id", "x-apple://R/1", "--due", String(Int(due)), "--timed", "1", "내일로 넘김: 보고서"],
          "undo: the agent hands the log line to aris-tools with the date it had")
    check(ArisActivityBridge.localLogArguments(kind: "todo-due", summary: "내일로 넘김: 보고서", id: "r", level: nil) == nil
          && ArisActivityBridge.localLogArguments(kind: "todo-due", summary: "내일로 넘김: 보고서", id: nil, level: nil, due: due) == nil
          && ArisActivityBridge.localLogArguments(kind: "todo-due", summary: "내일로 넘김: 보고서", id: "r", level: nil, due: -1) == nil,
          "undo: the agent refuses the line without an id or a date")
    var performed: ArisUndo?
    try? ArisActivity.perform(.restoreTodoDue(id: "r1", due: due, timed: true), local: { performed = $0 })
    check(performed == .restoreTodoDue(id: "r1", due: due, timed: true), "undo: it is one of the app's own changes, undone through the app's to-do route")
    let request = ArisTodoRoute.Request(json: ["op": "set-due", "id": "r1", "at": due, "timed": true])
    check(request?.op == .setDue && request?.id == "r1" && request?.at == due && request?.timed == true, "undo: the route reads the to-do's id, the date and whether it had a time")
    let key = ArisActionGrant.key(todo: ["op": "set-due", "id": "r1", "at": due, "timed": true])
    check(key == "todo|set-due|id=r1" && key.map(ArisActionGrant.isUndoKey) == true, "undo: the route takes it only with the agent's grant for an undo, never on the token alone")
    check(!ArisActionGrant.isUndoKey("todo|edit|text=x|due=tomorrow") && ArisActionGrant.key(todo: ["op": "list"]) == nil, "undo: an ordinary edit is never let through as an undo")
    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-dayend2-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("activity.jsonl")
    let entry = ArisActivityEntry(id: UUID(), date: Date(), job: "Aris", worker: "user", summary: "내일로 넘김: 보고서", undo: .restoreTodoDue(id: "r1", due: due, timed: true), undone: false)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    if let line = try? encoder.encode(entry) { try? (line + Data("\n".utf8)).write(to: file) }
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    check(ArisActivityBridge.undoWritesTodo(ofEntry: entry.id.uuidString, file: file, now: Date()), "undo: the agent mints its to-do grant for this undo, as for a reopened to-do")
    check(ArisUndoWords.doneLine("내일로 넘김: 보고서", korean: true) == "‘보고서’ 할 일을 되돌렸어요.", "undo: “방금 거 취소해” answers by the to-do's name")
}

private func dayend2KeptTests() {
    let day = ArisDaySpan(now: at(20), calendar: seoul2).today
    let fresh = ArisDayEndKept.current(nil, day: day)
    check(fresh == ArisDayEndKept(day: day) && !fresh.open && fresh.moved.isEmpty, "kept: the list starts folded")
    let opened = fresh.opened(true).moving("t2").moving("t2")
    check(opened.open && opened.moved == ["t2"] && fresh == ArisDayEndKept(day: day), "kept: opening and a move are remembered, and the value before is left as it was")
    check(ArisDayEndKept.current(opened.stored, day: day) == opened, "kept: asked again the same day, 목록 is as he left it")
    check(ArisDayEndKept.current(opened.stored, day: ArisDaySpan(now: at(0, 30, day: 1), calendar: seoul2).today) == opened, "kept: half past midnight is still the same day")
    let next = ArisDaySpan(now: at(9, day: 1), calendar: seoul2).today
    check(ArisDayEndKept.current(opened.stored, day: next) == ArisDayEndKept(day: next), "kept: the next day it is folded again and yesterday's moves are forgotten")
    check(ArisDayEndKept.current(Data("nope".utf8), day: day) == ArisDayEndKept(day: day), "kept: something unreadable is a new day's")
    let tomorrow = at(0, day: 1)
    let todos: [ArisDayEndFacts.Todo] = [.init(id: "t2", title: "a", due: at(18, day: 1)), .init(id: "t3", title: "b", due: at(18)), .init(id: "t4", title: "c", due: at(9, day: 1), completed: at(19))]
    let settled = ArisDayEndKept(day: day, open: true, moved: ["t2", "t3", "t4", "gone"]).settled(open: todos, tomorrow: tomorrow)
    check(settled.moved == ["t2"] && settled.open, "kept: a move that was undone, a to-do ticked off and one that is gone are no longer remembered as put off")
}

private func dayend2ScheduleTests() {
    func scheduled(_ title: String, _ rule: ArisRepeat, next: Date?, last: Date? = nil, running: Date? = nil, failed: Bool? = nil) -> ArisScheduledJob {
        ArisScheduledJob(id: UUID(), title: title, prompt: "secret prompt", teammate: nil, rule: rule, created: at(8, day: -9), nextRun: next, lastRun: last, runningSince: running,
                         parked: [], lastFailed: failed)
    }
    let jobs = [scheduled("아침 날씨", .daily(hour: 8, minute: 0), next: at(8, day: 1), last: at(8, 0)),
                scheduled("점심 메일", .daily(hour: 12, minute: 0), next: at(12, day: 1), last: at(12, 1), failed: true),
                scheduled("주간 보고", .weekly(weekday: 4, hour: 17, minute: 0), next: at(17, day: 7), last: at(17), running: at(17)),
                scheduled("저녁 스트레칭", .daily(hour: 21, minute: 0), next: at(21), last: at(21, day: -1)),
                scheduled("놓친 일", .daily(hour: 10, minute: 0), next: at(10), last: at(10, day: -2)),
                scheduled("금요일 정리", .weekly(weekday: 6, hour: 9, minute: 0), next: at(9, day: 2)),
                scheduled("메일 확인", .every(seconds: 1_800), next: at(20, 10), last: at(19, 40)),
                scheduled("약 먹기", .once(at(22)), next: at(22)),
                scheduled("내일 한 번", .once(at(9, day: 1)), next: at(9, day: 1))]
    let due = ArisDayEndRoute.due(jobs, day: at(0), end: at(0, day: 1), now: at(20), calendar: seoul2)
    check(due.map(\.title) == ["아침 날씨", "놓친 일", "점심 메일", "주간 보고", "저녁 스트레칭", "약 먹기"],
          "today's schedules: the ones due today by their time; none from another day, and none that repeats all day (\(due.map(\.title)))")
    check(due.map(\.state) == ["done", "pending", "failed", "running", "pending", "pending"], "today's schedules: ran is done, a failed run failed, one going on running, missed or still ahead pending (\(due.map(\.state)))")
    check(due.map(\.once) == [false, false, false, false, false, true] && due[0].at == at(8), "today's schedules: a one-time one says so, and each has the time it was due")
    let body = ArisDayEndRoute.body(jobs: jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoul2, today: (at(0), at(20)))
    check(!String(decoding: body, as: UTF8.self).contains("secret"), "today's schedules: no job's prompt leaves the agent")
    let read = ArisDayEndFacts.routines(from: body)
    check(read?.map(\.title) == due.map(\.title) && read?.map(\.state) == [.done, .pending, .failed, .running, .pending, .pending] && read?.last?.repeats == false,
          "today's schedules: the app reads the same list back")
    let tomorrow = ArisDayEndFacts.schedules(from: body)
    check(tomorrow?.first { $0.title == "내일 한 번" }?.repeats == false && tomorrow?.first { $0.title == "아침 날씨" }?.repeats == true, "today's schedules: tomorrow's one-time run says so too")
    let old = ArisDayEndRoute.body(jobs: jobs, from: at(0, day: 1), to: at(0, day: 2), calendar: seoul2)
    check(ArisDayEndFacts.routines(from: old) == nil && ArisDayEndFacts.schedules(from: old) != nil && ArisDayEndFacts.routines(from: Data("{}".utf8)) == nil,
          "today's schedules: an answer without them (an older agent) leaves them out of the plan")
    check(ArisDayEndRoute.day(["day": at(0).timeIntervalSince1970, "now": at(20).timeIntervalSince1970], from: at(0, day: 1))?.day == at(0)
          && ArisDayEndRoute.day(["day": at(0, day: -9).timeIntervalSince1970, "now": 1.0], from: at(0, day: 1)) == nil
          && ArisDayEndRoute.day(["day": at(0, day: 2).timeIntervalSince1970, "now": 1.0], from: at(0, day: 1)) == nil && ArisDayEndRoute.day([:], from: at(0, day: 1)) == nil,
          "today's schedules: the agent takes one day before the window, never a backwards or a long one")
    let run = scheduled("아침 날씨", .daily(hour: 8, minute: 0), next: at(8, day: 1), last: at(8), running: at(8))
    check(ArisSchedule.finished(run, failed: true)?.lastFailed == true && ArisSchedule.finished(run, failed: false)?.lastFailed == false && ArisSchedule.finished(run)?.lastFailed == nil
          && ArisSchedule.finished(run, failed: true)?.runningSince == nil, "today's schedules: a run's end keeps whether it failed, with the schedule")
    let stored = try? JSONDecoder().decode(ArisScheduledJob.self, from: Data(#"{"id":"\#(UUID().uuidString)","title":"t","prompt":"p","rule":{"daily":{"hour":8,"minute":0}},"created":0,"parked":[]}"#.utf8))
    check(stored?.lastFailed == nil && stored?.title == "t", "today's schedules: a schedule stored before this was kept still reads")
}

/// The source's own promises: the old tally is gone, and the list never asks an AI or shows a card of its own.
private func dayend2SourceTextTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")
    let read = { (path: String) in (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    let folder = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("DayEnd").path)) ?? []
    check(!folder.contains("ArisDayEndDone.swift") && !folder.contains("ArisDayEndCard.swift") && !folder.contains("ArisDayEndTomorrow.swift"), "source: the tally card and its parts are gone")
    let all = folder.map { read("DayEnd/" + $0) }.joined()
    check(!all.contains("Person") && !all.contains("맡은 일") && !all.contains("teammate(of"), "source: nothing counts who did how much")
    let model = read("DayEnd/ArisDayEndModel.swift")
    check(model.contains("ArisReceiptModel.shared.turnBegan()") && model.contains("ArisAgentClient.logLocalChange(kind: ArisDayEndPush.logKind"),
          "source: a press leaves its line in the record, so the receipt carries 되돌리기")
    check(model.contains("todos.update(todo, draft)") && !model.contains("ArisConfirmation"), "source: the press edits the reminder the way every to-do edit does, with no card of its own")
    let list = read("DayEnd/ArisDayEndList.swift")
    check(list.contains("accessibilityReduceMotion") && list.contains("ArisGlass.opening") && !list.contains("repeatForever"), "source: the fold opens on the notch's clock, respects Reduce Motion, and nothing pulses")
    check(read("ArisIntent.swift").contains("if ArisDayEndAsk.asks(phrase) { return .dayEnd }"), "source: it is still a local intent, asked with the same words")
    let turn = read("Home/ArisTurnView.swift")
    check(turn.contains("ArisDayEndFold(summary: summary, open: dayEnd.open") && turn.contains("dayEnd.isLine(session.reply)") && turn.contains("if plainLine {"), "source: the list sits under its sentence, as an answer's card does")
}
