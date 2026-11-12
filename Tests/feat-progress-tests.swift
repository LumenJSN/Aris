// Tests for the working tag's progress and cancel (feature "progress", 2026-11-11): the step count a status line
// carries when the work really knows it ("… · 2/4"), the clock a tag shows once it has run a while, when each tag
// began running, and what the notch says after the user stops the work from its tag. Pure: no agent, no view, no clock
// of its own. Called from main.swift; uses its check().
import Foundation

func runFeatProgressTests() {
    stepCountTests()
    agentStepLineTests()
    tagClockTests()
    tagTimesTests()
    stoppedSessionTests()
    stopRecordTests()
    stopLineTests()
    stoppedJobTests()
}

// MARK: - "2/4": only what the work itself counted

private func stepCountTests() {
    let counted = ArisTagProgress.split("카카오톡에서 입력 중… · 2/4")
    check(counted.words == "카카오톡에서 입력 중…" && counted.count == ArisTagCount(step: 2, of: 4),
          "progress: a status that ends in “ · 2/4” is its words and step 2 of 4")
    check(counted.count?.text == "2/4", "progress: the count reads “2/4”")
    let plain = ArisTagProgress.split("메일 보는 중")
    check(plain.words == "메일 보는 중" && plain.count == nil, "progress: a status with no count shows no numbers")
    check(ArisTagProgress.split("자료 정리 · 웹 검색 중 · 3/5").words == "자료 정리 · 웹 검색 중",
          "progress: a job's tag keeps its title and status when the count is taken off its end")
    check(ArisTagProgress.split("3/4분기 정리 · 하는 중").count == nil, "progress: numbers inside the words are never a count")
    check(ArisTagProgress.split("정리 · 5/4").count == nil, "progress: a step past the last one is not a count")
    check(ArisTagProgress.split("정리 · 0/4").count == nil, "progress: step zero is not a count")
    check(ArisTagProgress.split("정리 · 1/1").count == nil, "progress: one step of one is not worth a count")
    check(ArisTagProgress.split("정리 · 12/120").count == nil, "progress: more than 99 steps is not a count")
    check(ArisTagProgress.split("정리 2/4").count == nil, "progress: only the agreed “ · N/M” ending is a count")
    check(ArisTagProgress.split("· 2/4").count == nil, "progress: a count with no words before it is not shown as one")
    check(ArisTagProgress.counted("메일 보는 중", step: 2, of: 4) == "메일 보는 중 · 2/4", "progress: a counted status is written “… · 2/4”")
    check(ArisTagProgress.counted("메일 보는 중", step: 1, of: 1) == "메일 보는 중", "progress: a single step is written without a count")
    check(ArisTagProgress.counted("메일 보는 중", step: 5, of: 4) == "메일 보는 중", "progress: an impossible count is left off")
    let round = ArisTagProgress.split(ArisTagProgress.counted("Typing in Notes…", step: 3, of: 12))
    check(round.words == "Typing in Notes…" && round.count == ArisTagCount(step: 3, of: 12), "progress: what is written is read back the same")
    check(ArisTagProgress.withoutMinutes("영상·소리 변환하는 중 (3분째)") == "영상·소리 변환하는 중"
          && ArisTagProgress.withoutMinutes("Converting video or sound (3 min)") == "Converting video or sound",
          "progress: a long job's own minutes note goes when the tag shows its clock")
    check(ArisTagProgress.withoutMinutes("메일 보는 중") == "메일 보는 중", "progress: other words are left as they are")
}

/// The agent writes the same ending the app reads (the two programs share no file for it).
private func agentStepLineTests() {
    let line = ArisStepLine.counted("카카오톡에서 누르는 중…", step: 2, of: 4)
    check(line == ArisTagProgress.counted("카카오톡에서 누르는 중…", step: 2, of: 4), "progress: the agent's counted line is the one the app reads")
    check(ArisTagProgress.split(line).count == ArisTagCount(step: 2, of: 4), "progress: a batch's step reaches the tag as 2/4")
    check(ArisStepLine.counted("Notes 보는 중…", step: 1, of: 1) == "Notes 보는 중…", "progress: a one-step batch says no count")
    check(ArisStepLine.counted("Notes 보는 중…", step: nil) == "Notes 보는 중…", "progress: a single desktop call says no count")
    check(ArisStepLine.counted("Notes 보는 중…", step: ArisStepLine.Step(index: 2, of: 5)) == "Notes 보는 중… · 3/5",
          "progress: a batch's third step of five says 3/5")
    let long = ArisStepLine.counted(String(repeating: "가", count: 100), step: 2, of: 4)
    check(long.count <= ArisStepLine.limit && ArisTagProgress.split(long).count == ArisTagCount(step: 2, of: 4),
          "progress: a long line is cut before its count, never through it")
}

// MARK: - The clock

private func tagClockTests() {
    let began = Date(timeIntervalSince1970: 1_000_000)
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(2)) == nil, "progress: a two-second step shows no clock")
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(9.9)) == nil, "progress: nothing shows before ten seconds")
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(10)) == "0:10", "progress: at ten seconds the tag shows 0:10")
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(75.4)) == "1:15", "progress: a minute and a quarter reads 1:15")
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(3_725)) == "1:02:05", "progress: past an hour it reads 1:02:05")
    check(ArisTagProgress.clock(since: nil, now: began) == nil, "progress: a tag with no start shows no clock")
    check(ArisTagProgress.clock(since: began, now: began.addingTimeInterval(-5)) == nil, "progress: a clock set back shows nothing rather than a wrong time")
    check([0, 9.9, 42, 605, 3_599, 3_723, 86_400].allSatisfy { ArisTagProgress.elapsed($0) == ArisPillLayout.elapsed($0) },
          "progress: the tag's clock reads as the jobs' pill's does")
    check(ArisTagProgress.untilClock(since: began, now: began.addingTimeInterval(4)) == 6, "progress: four seconds in, the clock is six seconds away")
    check(ArisTagProgress.untilClock(since: began, now: began.addingTimeInterval(40)) == 0, "progress: a tag seen again after forty seconds shows its clock at once")
}

// MARK: - When each tag began running

private func tagTimesTests() {
    let start = Date(timeIntervalSince1970: 2_000_000)
    let at = { (seconds: TimeInterval) in start.addingTimeInterval(seconds) }
    var session = ArisSession().listening().hearing("메일 정리해 줘").thinking()
    var times = ArisTagTimes().seeing(session, at: at(0))
    check(times.began == [0: at(0)] && times.turnBegan == at(0), "progress: 생각 중 starts its clock when the turn starts working")
    session = session.working("메일 보는 중")
    times = times.seeing(session, at: at(4))
    check(times.began == [0: at(0)], "progress: the first status relabels 생각 중 and keeps its clock")
    session = session.working("메일 쓰는 중")
    times = times.seeing(session, at: at(6))
    check(times.began == [0: at(0)], "progress: the same task's next status keeps its clock")
    session = session.working("웹 검색 중")
    times = times.seeing(session, at: at(9))
    check(times.began == [1: at(9)], "progress: a new task's tag starts its own clock, and the finished one has none")
    session = session.working("메일 보는 중")
    times = times.seeing(session, at: at(12))
    check(times.began == [0: at(12)], "progress: a finished task that runs again starts from zero")
    check(times.turnBegan == at(0), "progress: the turn's own start doesn't move with its steps")
    let asking = session.asking(ArisConfirmation(id: "q", title: "메일 보내기", detail: "to: a@b.c"))
    times = times.seeing(asking, at: at(20))
    check(times.began.isEmpty && times.turnBegan == at(0), "progress: while a card waits no tag runs, and the turn is still the same one")
    times = times.seeing(asking.answered(), at: at(50))
    check(times.began == [0: at(50)] && times.turnBegan == at(0), "progress: after the card, the step that waited on it counts from the user's answer, not through his wait (vm3 bug C)")
    times = times.seeing(asking.answered().answering("보냈어요"), at: at(55))
    check(times.began.isEmpty, "progress: an answered turn has no clocks")
    let next = ArisSession().listening().hearing("날씨 알려 줘").thinking()
    times = times.seeing(next, at: at(90))
    check(times.began == [0: at(90)] && times.turnBegan == at(90), "progress: the next turn starts its own clocks")
    // A typed turn over one still working never passes through idle.
    let typedOver = ArisSession().listening().hearing("그거 말고 일정 알려 줘").thinking()
    times = times.seeing(typedOver, at: at(95))
    check(times.began == [0: at(95)] && times.turnBegan == at(95), "progress: a new request over one still working starts from zero")
    check(ArisTagTimes().seeing(ArisSession(), at: at(0)) == ArisTagTimes(), "progress: at rest there is nothing to time")
}

// MARK: - The notch after a stop

private func stoppedSessionTests() {
    let working = ArisSession().listening().hearing("메일 읽고 일정 잡아 줘").thinking().working("메일 보는 중").working("일정 추가 중")
    let cut = ArisStopLine.cut(working)
    check(cut == ArisStopLine.Cut(finished: ["메일 보는 중"], cutOff: "일정 추가 중"), "stop: the finished steps and the one cut off are told apart")
    let stopped = working.stopped("멈췄어요.")
    check(stopped.phase == .idle && stopped.reply == "멈췄어요." && stopped.heard == "메일 읽고 일정 잡아 줘", "stop: the notch rests on the stop line under the user's words")
    check(stopped.steps == [ArisStep(label: "메일 보는 중", done: true, id: 0)], "stop: only what finished keeps its check; the step cut off is not ticked")
    check(stopped.tags == stopped.steps, "stop: the finished tags stay under the line")
    let thinkingOnly = ArisSession().listening().hearing("안녕").thinking()
    check(ArisStopLine.cut(thinkingOnly) == ArisStopLine.Cut(finished: [], cutOff: nil), "stop: stopped while only thinking, nothing was begun")
    check(thinkingOnly.stopped("멈췄어요.").steps.isEmpty, "stop: and no tag stays")
    let between = working.asking(ArisConfirmation(id: "q", title: "일정 추가", detail: "회의")).answered()
    check(ArisStopLine.cut(between) == ArisStopLine.Cut(finished: ["메일 보는 중"], cutOff: "일정 추가 중"),
          "stop: stopped after a card's yes, the step that waited on the card is the one cut off (vm3 bug C)")
    let counted = ArisSession().listening().hearing("메모에 적어 줘").thinking().working("메모에서 입력 중… · 2/4")
    check(ArisStopLine.cut(counted).cutOff == "메모에서 입력 중… · 2/4", "stop: a counted step keeps its count for the line")
}

private func item(_ summary: String, at date: Date, job: String = "대화", worker: String = "Claude", undone: Bool = false) -> ArisActivityItem {
    ArisActivityItem(id: UUID().uuidString, date: date, job: job, worker: worker, summary: summary, undoable: true, undone: undone, asks: false)
}

private func stopRecordTests() {
    let began = Date(timeIntervalSince1970: 3_000_000)
    let items = [
        item("옮김: old.pdf → ~/Documents", at: began.addingTimeInterval(-60)),
        item("일정 추가: 회의", at: began.addingTimeInterval(3)),
        item("할 일 추가: 우유", at: began.addingTimeInterval(5), job: "장보기 목록", worker: "코디"),
        item("휴지통으로: a.txt", at: began.addingTimeInterval(8), undone: true),
        item("옮김: b.pdf → ~/Desktop", at: began.addingTimeInterval(9)),
    ]
    check(ArisStopLine.mine(items, since: began) == ["일정 추가: 회의", "옮김: b.pdf → ~/Desktop"],
          "stop: the turn's record is what the conversation did since it began, oldest first, without another job's work or anything undone")
    check(ArisStopLine.mine(items, since: began.addingTimeInterval(100)).isEmpty, "stop: nothing recorded since the turn began is an empty record")
    check(ArisStopLine.job(items, title: "장보기 목록", since: began) == ["할 일 추가: 우유"], "stop: a job's record is what was done under its name")
    check(ArisStopLine.job(items, title: "다른 일", since: began).isEmpty, "stop: another job's work is never told as this one's")
    let long = String(repeating: "가", count: 90)
    check(ArisStopLine.job([item("새 폴더: 자료", at: began.addingTimeInterval(1), job: String(long.prefix(80)), worker: "코디")], title: long, since: began)
          == ["새 폴더: 자료"], "stop: a long job title is matched as the record keeps it (80 letters)")
    check(ArisStopLine.mine([item("일정 추가: 회의", at: began.addingTimeInterval(-0.5))], since: began) == ["일정 추가: 회의"],
          "stop: an entry stamped a moment before the app saw the turn start still counts")
}

private func stopLineTests() {
    let none = ArisStopLine.Cut(finished: [], cutOff: nil)
    check(ArisStopLine.line(record: [], cut: none, english: false) == "멈췄어요.", "stop: stopped before anything began, the line is just 멈췄어요")
    check(ArisStopLine.line(record: nil, cut: none, english: false) == "멈췄어요.", "stop: with nothing begun, an unread record changes nothing")
    let done = ArisStopLine.line(record: ["일정 추가: 회의", "옮김: b.pdf → ~/Desktop"], cut: ArisStopLine.Cut(finished: ["일정 추가 중"], cutOff: "옮기는 중"), english: false)
    check(done == "여기까지 했어요: ‘일정 추가: 회의’, ‘옮김: b.pdf → ~/Desktop’. 나머지는 멈췄어요.", "stop: what the record holds is told as done, and the rest as stopped")
    check(!done.contains("취소"), "stop: something already done is never called cancelled")
    let many = ArisStopLine.line(record: ["a", "b", "c", "d", "e"], cut: none, english: false)
    check(many == "여기까지 했어요: ‘a’, ‘b’, ‘c’ 외 2건. 나머지는 멈췄어요.", "stop: past three, the line counts the others")
    check(ArisStopLine.line(record: [], cut: ArisStopLine.Cut(finished: ["메일 보는 중"], cutOff: "웹 검색 중"), english: false)
          == "‘웹 검색 중’에서 멈췄어요. 나머지는 안 했어요.", "stop: with nothing on record, the line names the step it stopped at")
    check(ArisStopLine.line(record: [], cut: ArisStopLine.Cut(finished: [], cutOff: "메모에서 입력 중… · 2/4"), english: false)
          == "‘메모에서 입력 중’ 2/4 단계에서 멈췄어요. 나머지는 안 했어요.", "stop: a counted step says which step of how many it stopped at")
    check(ArisStopLine.line(record: [], cut: ArisStopLine.Cut(finished: ["메일 보는 중"], cutOff: nil), english: false)
          == "멈췄어요. 나머지는 안 했어요.", "stop: stopped between steps, the ticked tags say what was done")
    check(ArisStopLine.line(record: nil, cut: ArisStopLine.Cut(finished: ["메일 보는 중"], cutOff: "일정 추가 중"), english: false)
          == "‘일정 추가 중’에서 멈췄어요. 나머지는 안 했어요. 한 일 기록을 못 읽었어요. 바뀐 게 있는지는 ‘한 일’ 탭에서 확인해 주세요.",
          "stop: when the record can't be read, the line says so and where to look")
    check(ArisStopLine.line(record: ["Event added: Sync"], cut: none, english: true) == "Done so far: ‘Event added: Sync’. The rest was stopped.",
          "stop: the English line says the same")
    check(ArisStopLine.line(record: [], cut: ArisStopLine.Cut(finished: [], cutOff: "Typing in Notes… · 2/4"), english: true)
          == "Stopped at ‘Typing in Notes’, step 2 of 4. The rest wasn't done.", "stop: the English line names the step and its count")
    check(ArisStopLine.line(record: ["a", "b", "c", "d"], cut: none, english: true) == "Done so far: ‘a’, ‘b’, ‘c’ and 1 more. The rest was stopped.",
          "stop: the English line counts the others")
    check(ArisStopLine.line(record: nil, cut: ArisStopLine.Cut(finished: ["Reading mail"], cutOff: nil), english: true)
          == "Stopped. The rest wasn't done. The activity record couldn't be read: check the Activity tab for anything that changed.",
          "stop: the English line says when the record can't be read")
    check(ArisStopLine.help(english: false) == "눌러서 멈추기" && ArisStopLine.help(english: true) == "Click to stop", "stop: the tag's tip says a press stops it")
}

// MARK: - A job stopped from its tag

private func stoppedJobTests() {
    let id = UUID(), other = UUID()
    let cancelled = ArisBackgroundTask(id: id, title: "자료 정리", state: .failed(ArisStopLine.cancelledWord))
    let notes = [id: "여기까지 했어요: ‘새 폴더: 자료’. 나머지는 멈췄어요."]
    check(ArisStopLine.shown(cancelled, notes: notes).state == .failed("여기까지 했어요: ‘새 폴더: 자료’. 나머지는 멈췄어요."),
          "stop: a job stopped from its tag says what it had done, not 취소됨")
    let failed = ArisBackgroundTask(id: id, title: "자료 정리", state: .failed(ArisJobCancel.unconfirmed))
    check(ArisStopLine.shown(failed, notes: notes) == failed, "stop: a job whose stop the agent never confirmed keeps saying it may still run")
    let unrelated = ArisBackgroundTask(id: other, title: "다른 일", state: .failed(ArisStopLine.cancelledWord))
    check(ArisStopLine.shown(unrelated, notes: notes) == unrelated, "stop: a job without a note is left as it was")
    check(ArisStopLine.jobCut(.running(step: "웹 검색 중")) == ArisStopLine.Cut(finished: [], cutOff: "웹 검색 중")
          && ArisStopLine.jobCut(.queued) == ArisStopLine.Cut(finished: [], cutOff: nil)
          && ArisStopLine.jobCut(.running(step: "")) == ArisStopLine.Cut(finished: [], cutOff: nil),
          "stop: a job is cut off at the step it was running; one still waiting had begun nothing")
    check(ArisStopLine.line(record: [], cut: ArisStopLine.jobCut(.queued), english: false) == "멈췄어요.", "stop: a job stopped while it waited just says 멈췄어요")
}
