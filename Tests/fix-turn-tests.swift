// Tests for the audited turn fixes (qa/audit-1110/turn.json): a local reply says what really happened (turn-1), a
// stopped turn does nothing more (turn-2), a request that goes on after its first act is the AI's (intent-1), a word
// inside a longer request is not a command (intent-2), files given to Aris are never read as commands (files-1), a
// conversation picked up from the 기록 list keeps its context (resume-1), a rewrite uses the chosen brain (brain-1),
// and a timer that ends while Aris is busy is still told (imp-5). Pure parts and fakes only: nothing here speaks,
// listens, sets a timer, adds a to-do or touches the user's data.
// Called from main.swift; uses its check().
import Foundation

func runFixTurnTests() {
    requestThatGoesOnTests()
    wordInsideARequestTests()
    brainNamedInPassingTests()
    trueLocalReplyTests()
    stoppedTurnTests()
    filesAreNotCommandsTests()
    resumedConversationTests()
    chosenBrainTests()
    leftBehindTests()
    pointingWordTests()
    turnWordingTests()
}

/// Runs an async test on the main actor and waits for it, keeping the main run loop turning.
private func fixTurnBlocking(_ body: @escaping @MainActor () async -> Void) {
    let done = FixTurnBox(false)
    Task { @MainActor in
        await body()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private final class FixTurnBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// A source file of the app, for the few facts that only its wiring shows.
private func fixTurnSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The text of one function, from its declaration to the next one at the same depth.
private func fixTurnFunction(_ name: String, in source: String) -> String {
    guard let start = source.range(of: "func " + name) else { return "" }
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\n    func ")?.lowerBound ?? rest.range(of: "\n    private func ")?.lowerBound ?? rest.endIndex
    return String(rest[..<end])
}

// MARK: - intent-1: a request that goes on after its first act

private func requestThatGoesOnTests() {
    // The audit's four sentences: each used to be cut down to its first act.
    for said in ["메일 열어서 안 읽은 거 요약해 줘", "카톡 켜서 엄마한테 곧 간다고 보내 줘", "크롬 열어서 네이버 들어가 줘",
                 "볼륨 30으로 하고 메일 열어 줘", "메모 앱 열고 어제 회의 내용 정리해 줘", "사파리 켜고 유튜브 들어가 줘",
                 "open mail and summarize my unread messages", "밝기 50으로 맞추고 다크 모드 켜 줘",
                 "소리 줄이고 음악 틀어 줘", "타이머 5분 맞추고 음악 틀어 줘", "skip the intro and summarize this",
                 "타이머 끝나면 음악 꺼 줘", "음악 멈추고 메일 확인해 줘"] {
        check(ArisIntent.parse(said) == .ask(said), "intent-1: \"\(said)\" goes on after its first act, so the AI does all of it")
    }
    // Whoever picked the act (the router's second guess too), the one guard sends a longer request to the AI.
    check(ArisIntent.guarded(.openApp("Notes"), said: "메모 앱 열고 어제 회의 내용 정리해 줘") == .ask("메모 앱 열고 어제 회의 내용 정리해 줘"),
          "intent-1: the router's open-app pick for a request that goes on is not acted on")
    check(ArisIntent.guarded(.volume(.set(30)), said: "볼륨 30으로 하고 메일 열어 줘") == .ask("볼륨 30으로 하고 메일 열어 줘"),
          "intent-1: the router's volume pick for a request that goes on is not acted on")
    check(ArisIntent.guarded(.timer(seconds: 300, focus: false), said: "set a timer for 5 minutes and then email Sam")
            == .ask("set a timer for 5 minutes and then email Sam"), "intent-1: an English request that goes on is the AI's too")
    check(ArisIntent.guarded(.openApp("Safari"), said: "사파리 좀 띄워 줄래") == .openApp("Safari"),
          "intent-1: a plain open request picked by the router is still done")
    // A single act stays local, however politely it ends.
    check(ArisIntent.parse("사파리 열어줘") == .openApp("Safari") && ArisIntent.parse("카톡 켜 줄래?") == .openApp("KakaoTalk")
            && ArisIntent.parse("피그마 실행해 주세요") == .openApp("Figma") && ArisIntent.parse("메모 띄워 줘") == .openApp("Notes")
            && ArisIntent.parse("사파리 켜 놔") == .openApp("Safari") && ArisIntent.parse("Open Notion") == .openApp("Notion"),
          "intent-1: a request that only opens an app still opens it")
    check(ArisIntent.parse("볼륨 30으로 해 줘") == .volume(.set(30)) && ArisIntent.parse("밝기 올려줘") == .brightness(.up)
            && ArisIntent.parse("소리 좀 줄여줘") == .volume(.down) && ArisIntent.parse("음악 멈춰") == .media(.pause),
          "intent-1: a single volume, brightness or music request is still done on the Mac")
    check(ArisIntent.parse("엑셀 4개 켜서 4등분") == .arrange(app: "Microsoft Excel", count: 4),
          "intent-1: opening windows and laying them out is one request, as before")
    check(ArisIntent.parse("할 일에 장 보고 빨래하기 추가해 줘") == .addTodo("장 보고 빨래하기"),
          "intent-1: a to-do whose own words have an 'and' is still one to-do")
    check(!ArisIntentScope.goesOn("볼륨 올리고 싶어") && ArisIntentScope.goesOn("볼륨 올리고 음악 틀어 줘"),
          "intent-1: \"…고 싶어\" is a wish for that one act, not a second one")
    check(ArisIntent.parse("set a timer for 1 hour and 30 minutes") == .timer(seconds: 5_400, focus: false),
          "intent-1: \"1 hour and 30 minutes\" is one length, not two requests")
}

// MARK: - intent-2: a word inside a longer request

private func wordInsideARequestTests() {
    // Each of these used to be answered by a read-only matcher (the brief, the date, the time, the to-do list, the
    // song) or to change the timer, the music or a to-do, and the request itself was never done.
    for said in ["내일 회의 브리핑 자료 만들어 줘", "이 문서 브리핑해 줘", "오늘 날짜로 폴더 하나 만들어 줘", "메모에 오늘 날짜 넣어 줘",
                 "지금 몇 시인지 슬랙에 올려 줘", "내일 할 일 있어서 3시 회의 취소해 줘", "오늘 할 일 목록 메일로 보내 줘",
                 "지금 듣는 노래 플레이리스트에 추가해 줘", "집중 모드 꺼 줘", "what's left to focus on this week",
                 "write a briefing for tomorrow's meeting", "put today's date in the note"] {
        check(ArisIntent.parse(said) == .ask(said), "intent-2: \"\(said)\" is a longer request, so the AI does it")
    }
    check(ArisIntent.parse("타이머 다시 10분 맞춰 줘") == .timer(seconds: 600, focus: false),
          "intent-2: \"타이머 다시 10분\" sets a 10-minute timer; it does not resume one")
    check(ArisIntent.parse("타이머 다시 시작") == .resumeTimer && ArisIntent.parse("타이머 계속") == .resumeTimer,
          "intent-2: with no length, 다시 and 계속 still resume the timer")
    // The plain questions still answer on the Mac.
    check(ArisIntent.parse("브리핑 해줘") == .brief && ArisIntent.parse("오늘 브리핑") == .brief && ArisIntent.parse("아침 브리핑 보여 줘") == .brief
            && ArisIntent.parse("briefing") == .brief, "intent-2: asking for the brief alone still shows it")
    check(ArisIntent.parse("오늘 며칠이야") == .tellDate && ArisIntent.parse("아리스 오늘 무슨 요일이야?") == .tellDate
            && ArisIntent.parse("오늘 날짜 알려 줘") == .tellDate && ArisIntent.parse("what's the date today") == .tellDate,
          "intent-2: asking for the date alone still says it")
    check(ArisIntent.parse("아리스, 지금 몇 시야?") == .tellTime && ArisIntent.parse("몇시야") == .tellTime
            && ArisIntent.parse("지금 몇 시인지 알려 줘") == .tellTime && ArisIntent.parse("what time is it") == .tellTime,
          "intent-2: asking for the time alone still says it")
    check(ArisIntent.parse("할 일 뭐 있어") == .listTodos && ArisIntent.parse("오늘 할 일 알려줘") == .listTodos
            && ArisIntent.parse("할 일 목록 보여 줘") == .listTodos && ArisIntent.parse("할 일 뭐 남았어?") == .listTodos
            && ArisIntent.parse("what's on my to-do list") == .listTodos, "intent-2: asking for the to-do list alone still reads it")
    check(ArisIntent.parse("지금 무슨 노래야?") == .whatsPlaying && ArisIntent.parse("지금 나오는 곡 제목 알려줘") == .whatsPlaying
            && ArisIntent.parse("이 노래 뭐야") == .whatsPlaying && ArisIntent.parse("what's playing") == .whatsPlaying,
          "intent-2: asking what is playing still answers from the player")
    check(ArisIntent.parse("타이머 얼마나 남았어") == .timerLeft && ArisIntent.parse("집중 몇 분 남았어") == .timerLeft,
          "intent-2: asking how long the timer has left still answers from the timer")
    check(ArisIntent.parse("타이머 꺼") == .cancelTimer && ArisIntent.parse("뽀모도로 그만") == .cancelTimer
            && ArisIntent.parse("타이머 잠깐 멈춰") == .pauseTimer, "intent-2: stopping or pausing the timer by its name still works")

    // "… 끝났어" ticks a to-do only when the words are an open item's title; anything looser is the AI's to settle.
    func item(_ id: String, _ title: String) -> ArisTodoItem {
        ArisTodoItem(id: id, title: title, notes: nil, due: nil, hasTime: false, listID: "", listName: "", colorHex: "")
    }
    let open = [item("t0", "회의 자료 준비"), item("t1", "과제"), item("t2", "PS3")]
    check(ArisTodoMatch.named("회의", in: open) == nil, "intent-2: \"회의 끝났어\" does not tick \"회의 자료 준비\"")
    check(ArisTodoMatch.named("드디어 과제", in: open) == nil, "intent-2: \"드디어 과제 끝났어\" ticks nothing by itself")
    check(ArisTodoMatch.named("PS3", in: open)?.id == "t2" && ArisTodoMatch.named("ps3는", in: open)?.id == "t2"
            && ArisTodoMatch.named("회의자료 준비", in: open)?.id == "t0",
          "intent-2: the item's own title (any spacing or case, a particle after it) is ticked")
    check(ArisTodoMatch.named("과제", in: open + [item("t9", "과제")]) == nil,
          "intent-2: two items with that title: neither is ticked without asking")
}

// MARK: - intent-2: an AI named in passing

private func brainNamedInPassingTests() {
    func picked(_ text: String) -> String? { ArisBrain.pick(from: text).map { "\($0.brain.rawValue)|\($0.request)" } }
    check(picked("API로 받아온 데이터 정리해 줘") == nil, "intent-2: \"API로 받아온 데이터\" is about an API; it does not switch brains")
    check(picked("API로 물어봐, 오늘 날씨") == "api|오늘 날씨" && picked("API한테 물어봐, 날씨") == "api|날씨",
          "intent-2: asking the API brain by name still picks it")
    check(picked("코덱스로 오늘 뉴스 요약해줘") == "codex|오늘 뉴스 요약해줘" && picked("GPT한테 물어봐, 내일 비 와?") == "codex|내일 비 와?",
          "intent-2: naming the AI to ask still takes its name off the request")
}

// MARK: - turn-1: a local reply says what really happened

private func trueLocalReplyTests() {
    // Adding a to-do: "넣었어요" only for an item that was saved.
    check(ArisLocalReply.todoAdded(.saved(title: "우유 사기"), korean: true) == "할 일에 넣었어요: 우유 사기",
          "turn-1: a saved to-do is told as saved")
    for outcome in [ArisTodoAdded.noAccess, .demo, .noTitle, .failed(why: "저장하지 못했어요. 디스크가 가득 찼어요."), .failed(why: nil)] {
        for korean in [true, false] {
            let said = ArisLocalReply.todoAdded(outcome, korean: korean)
            check(!said.isEmpty && !said.contains("넣었어요") && !said.hasPrefix("Added"),
                  "turn-1: a to-do that was not saved (\(outcome)) is never told as added: \(said)")
        }
    }
    check(ArisLocalReply.todoAdded(.noAccess, korean: true).contains("설정 › 할 일 · 캘린더 › 미리 알림 접근")
            && ArisLocalReply.todoAdded(.noAccess, korean: false).contains("Settings"),
          "turn-1: with Reminders off the reply says where to turn it on")
    check(ArisLocalReply.todoAdded(.failed(why: "저장하지 못했어요. 디스크가 가득 찼어요."), korean: true).contains("디스크가 가득 찼어요"),
          "turn-1: Reminders' own reason is passed on")
    check(ArisLocalReply.todosUnread(korean: true) != ArisTodoSpeech.line([], korean: true) && ArisLocalReply.todosUnread(korean: true).contains("미리 알림 접근"),
          "turn-1: a list Aris could not read is never told as empty")
    check(ArisLocalReply.undoUnknown(korean: true) != "되돌릴 일이 없어요." && ArisLocalReply.undoUnknown(korean: false) != "There's nothing to undo.",
          "turn-1: when the agent did not answer, Aris does not claim there is nothing to undo")
    check(ArisLocalReply.todoNotTicked("우유 사기", why: nil, korean: true).contains("못") && !ArisLocalReply.todoNotTicked("우유 사기", why: nil, korean: true).contains("체크했어요"),
          "turn-1: an item Reminders would not tick is not told as ticked")
    check(ArisLocalReply.appNotOpened("메일", korean: true) == "메일 앱을 열지 못했어요." && !ArisLocalReply.appNotOpened("Mail", korean: false).contains("Opening"),
          "turn-1: an app macOS did not open is not told as opening")

    // The timer: every change is told from the timer as it is.
    func plan(_ intent: ArisIntent, running: Bool, paused: Bool = false) -> ArisTimerChange? {
        ArisTimerChange.plan(intent, running: running, paused: paused, korean: true)
    }
    let none = ArisLocalReply.noTimer(korean: true)
    for intent in [ArisIntent.cancelTimer, .pauseTimer, .resumeTimer, .addTime(300)] {
        let change = plan(intent, running: false)
        check(change?.applies == false && change?.reply == none && change?.logged == nil,
              "turn-1: \(intent) with no timer running changes nothing, logs nothing and says so")
    }
    check(plan(.addTime(300), running: true)?.reply == "5분 늘렸어요." && plan(.addTime(300), running: true)?.applies == true,
          "turn-1: time is added to a running timer, and said")
    check(plan(.pauseTimer, running: true)?.applies == true && plan(.pauseTimer, running: true)?.reply == "타이머 잠깐 멈췄어요.",
          "turn-1: a running timer is paused, and said")
    check(plan(.pauseTimer, running: true, paused: true)?.applies == false && plan(.pauseTimer, running: true, paused: true)?.reply != "타이머 잠깐 멈췄어요.",
          "turn-1: a timer already paused is not paused again")
    check(plan(.resumeTimer, running: true, paused: true)?.applies == true && plan(.resumeTimer, running: true, paused: true)?.reply == "타이머 다시 갈게요.",
          "turn-1: a paused timer is resumed, and said")
    check(plan(.resumeTimer, running: true)?.applies == false && plan(.resumeTimer, running: true)?.reply != "타이머 다시 갈게요.",
          "turn-1: a timer that is not paused is not told as resumed")
    check(plan(.cancelTimer, running: true)?.logged == ArisTimerChange.Logged(kind: "timer-cancel", summary: "타이머 끔")
            && plan(.cancelTimer, running: true)?.reply == "타이머 껐어요.", "turn-1: a cancelled timer is logged for undo")
    check(plan(.timer(seconds: 1_500, focus: false), running: false)?.logged == ArisTimerChange.Logged(kind: "timer-set", summary: "타이머: 25분")
            && plan(.pomodoro, running: true)?.logged?.kind == "timer-set" && plan(.timer(seconds: 300, focus: true), running: false)?.applies == true,
          "turn-1: a timer that is set is logged for undo")
    check(plan(.tellTime, running: true) == nil && plan(.openApp("Safari"), running: false) == nil, "turn-1: anything else is not a timer request")
    check(ArisTimerChange.plan(.pauseTimer, running: false, paused: false, korean: false)?.reply == "No timer is running.",
          "turn-1: the same in English")

    // The wiring: each local branch says what its act returned.
    let controller = fixTurnSource("Aris/private/Aris/ArisController.swift")
    let local = fixTurnSource("Aris/private/Aris/ArisController+Local.swift")
    check(controller.contains("reply = ArisLocalReply.todoAdded(await addTodo(item), korean: korean)")
            && !controller.contains("reply = intent.acknowledgement(korean: korean) ?? \"\""),
          "turn-1: the to-do branch says the outcome, never the acknowledgement alone")
    check(controller.contains("read == nil ? ArisLocalReply.todosUnread(korean: korean)"), "turn-1: the list branch tells an unreadable list apart")
    check(local.contains("ArisTimerChange.plan(intent, running: timer.isRunning") && local.contains("guard change.applies else { return change.reply }"),
          "turn-1: a timer request is checked against the timer before anything is done")
    check(local.contains("if case .saved(let title, let id) = outcome") && local.contains("if let logged = change.logged"),
          "turn-1: only a change that happened is logged for undo")
    check(fixTurnSource("Aris/private/Aris/ArisController+Undo.swift").contains("guard let items = read else { return await undoSay(ArisLocalReply.undoUnknown(korean: korean)) }"),
          "turn-1: undo tells an agent that did not answer apart from an empty list")
    check(!controller.contains("func perform(_ intent: ArisIntent)") && !controller.contains("volumeBefore") && !controller.contains("musicHandled"),
          "the old local switch (with its dead volume and brightness cases) is gone")
}

// MARK: - turn-2: a stopped turn does nothing more

private func stoppedTurnTests() {
    fixTurnBlocking {
        // Stopping the caller stops the work inside, and the caller hears so at once.
        let inner = FixTurnBox("not started")
        let waiting = Task { @MainActor () -> String in
            do {
                return try await ArisDeadline.within(.seconds(30)) {
                    inner.value = "running"
                    do { try await Task.sleep(for: .seconds(30)) } catch { inner.value = "cancelled"; throw error }
                    inner.value = "finished"
                    return "answered"
                }
            } catch is CancellationError { return "stopped" } catch { return "timed out" }
        }
        try? await Task.sleep(for: .milliseconds(80))
        let began = ContinuousClock.now
        waiting.cancel()
        let ended = await waiting.value
        try? await Task.sleep(for: .milliseconds(50))
        check(ended == "stopped" && ContinuousClock.now - began < .seconds(5), "turn-2: a turn that is stopped stops waiting at once (\(ended))")
        check(inner.value == "cancelled", "turn-2: stopping the turn stops the work inside it (\(inner.value))")

        // A caller already stopped never starts the work.
        let started = FixTurnBox(false)
        let late = Task { @MainActor () -> Bool in
            try? await Task.sleep(for: .seconds(30))
            return (try? await ArisDeadline.within(.seconds(5)) { started.value = true; return true }) ?? false
        }
        late.cancel()
        let ran = await late.value
        check(!ran && !started.value, "turn-2: a stopped turn does not start anything new (speaking included)")

        // The deadline still works, and still cancels the work.
        let slow = FixTurnBox("running")
        var timedOut = false
        do {
            _ = try await ArisDeadline.within(.milliseconds(80)) {
                do { try await Task.sleep(for: .seconds(30)) } catch { slow.value = "cancelled"; throw error }
                return 1
            }
        } catch is ArisDeadline.TimedOut { timedOut = true } catch {}
        try? await Task.sleep(for: .milliseconds(50))
        check(timedOut && slow.value == "cancelled", "turn-2: work past its limit still times out and is cancelled")
        let quick = try? await ArisDeadline.within(.seconds(5)) { 7 }
        check(quick == 7, "turn-2: work inside its limit returns its result")

        // Work that must finish (giving the microphone back) runs to its end even when the caller is stopped.
        let stopping = FixTurnBox("running")
        let stopper = Task { @MainActor () -> String in
            (try? await ArisDeadline.within(.seconds(5), cancelsWork: false) {
                try? await Task.sleep(for: .milliseconds(150))
                stopping.value = Task.isCancelled ? "cancelled" : "finished"
                return "final words"
            }) ?? "none"
        }
        try? await Task.sleep(for: .milliseconds(30))
        stopper.cancel()
        let words = await stopper.value
        check(words == "final words" && stopping.value == "finished", "turn-2: a stop that must finish still does, and its result is kept")
    }

    // The wiring: nothing in a turn acts or writes the notch after a wait without checking it was not stopped.
    let controller = fixTurnSource("Aris/private/Aris/ArisController.swift")
    let answer = fixTurnFunction("answer(_ said: String", in: controller)
    let routed = answer.range(of: "let called = ").map { String(answer[$0.lowerBound...].prefix(800)) } ?? ""
    check(routed.contains("guard !Task.isCancelled else { return }") && (answer.range(of: "guard !Task.isCancelled else { return }")?.lowerBound ?? answer.endIndex)
            < (answer.range(of: "if let yes = madeAnswer {")?.lowerBound ?? answer.startIndex),
          "turn-2: after the router and the teammate lookup, a stopped turn ends before any branch acts")
    check((answer.range(of: "finishing = await ArisTodoModel.shared.finishable(item)")?.lowerBound ?? answer.endIndex)
            < (answer.range(of: "guard !Task.isCancelled else { return }")?.lowerBound ?? answer.startIndex) && answer.contains("} else if let found = finishing {"),
          "turn-2: the to-do lookup is done before that check, so a turn stopped during it cannot fall through to a hand-off")
    for wait in ["let read = await ArisTodoModel.shared.summary(korean: korean)", "let done = await performMedia(media)",
                 "let now = await ArisNowPlaying.shared.currentPlayback()", "reply = await performControl(control, korean: korean)",
                 "reply = ArisLocalReply.todoAdded(await addTodo(item), korean: korean)"] {
        let after = answer.range(of: wait).map { String(answer[$0.upperBound...].prefix(120)) } ?? ""
        check(after.contains("guard !Task.isCancelled else { return }"), "turn-2: after \"\(wait.prefix(40))…\" the turn checks it was not stopped before it speaks")
    }
    check(fixTurnSource("Aris/private/Aris/ArisController+Arrange.swift").contains("guard !Task.isCancelled else { return \"\" }")
            && fixTurnSource("Aris/private/Aris/ArisController+Undo.swift").contains("guard !Task.isCancelled else { return \"\" }"),
          "turn-2: arranging windows and undo stop too")
    let ask = fixTurnFunction("askAndSpeak(", in: controller)
    check((ask.range(of: "guard !Task.isCancelled else { return nil }")?.lowerBound ?? ask.endIndex) < (ask.range(of: "freshConversation = false")?.lowerBound ?? ask.startIndex),
          "turn-2: a turn stopped before it asked does not use up the new conversation's fresh start")
    check(controller.contains("try await ArisDeadline.within(limit, cancelsWork: cancelsWork, work)") && controller.contains("} catch is CancellationError {"),
          "turn-2: every timed wait of the controller goes through the deadline that forwards a stop")
}

// MARK: - files-1: files given to Aris are never read as commands

private func filesAreNotCommandsTests() {
    func turn(_ words: String, files: [String], text: String? = nil) -> String {
        ArisPendingFiles().adding(files.map { URL(fileURLWithPath: $0) }).request(with: words, contents: { _ in text })
    }
    // The audit's cases, built exactly as a turn builds them: only the user's own words are read as a command.
    let named = ["timer 5 min.png", "volume 2.png", "brightness 10.jpg", "pomodoro.png", "briefing.key"].map { turn("이거 설명해 줘", files: ["/tmp/" + $0]) }
    for whole in named {
        let own = ArisPendingFiles.words(of: whole)
        check(own == "이거 설명해 줘" && ArisIntent.parse(own) == .ask("이거 설명해 줘"),
              "files-1: a file's name is not a command (\(ArisPendingFiles.shown(whole)))")
    }
    check(ArisIntent.parse(named[0]) == .timer(seconds: 300, focus: false),
          "files-1: (why it matters) read whole, a file named \"timer 5 min.png\" would set a timer")
    let texts = ["주간 회의 브리핑 자료입니다.", "We should focus on retention. Two weeks left.", "오늘 할 일 목록을 정리했다. 뭐가 남았는지 보자.",
                 "Run the build in the background and wait.", "신중하게 검토해 주세요. carefully.", "아까 복사한 링크: https://github.com/a/b 스킬 추가"]
    for text in texts {
        let whole = turn("이 파일 요약해 줘", files: ["/tmp/notes.txt"], text: text)
        let own = ArisPendingFiles.words(of: whole)
        check(own == "이 파일 요약해 줘" && ArisIntent.parse(own) == .ask(own) && !ArisRouter.asksForCare(own) && !ArisDeixis.refersToClipboard(own)
                && !ArisIntent.isRecurring(own), "files-1: a file's text is not a command (\(text.prefix(24)))")
    }
    check(ArisPendingFiles.words(of: "타이머 5분") == "타이머 5분" && ArisIntent.parse(ArisPendingFiles.words(of: turn("타이머 5분", files: ["/tmp/a.png"]))) == .timer(seconds: 300, focus: false),
          "files-1: what the user says is still a command, with or without files")
    check(!ArisDeixis.refersToScreen(turn("이거 설명해 줘", files: ["/tmp/a.png"])), "files-1: (unchanged) with files, \"이거\" is the files, not the screen")

    // The wiring: the turn reads commands from the user's words and sends the whole request only to the AI or a job.
    let answer = fixTurnFunction("answer(_ said: String", in: fixTurnSource("Aris/private/Aris/ArisController.swift"))
    check(answer.contains("let whole = named?.request ?? heard") && answer.contains("let unmarked = ArisPendingFiles.words(of: whole)"),
          "files-1: the turn's own words are the user's alone")
    check(answer.contains("let text = shots ? (gesture?.markedRequest(heard) ?? whole) : whole") && answer.contains("called?.asking(whole)"),
          "files-1: the AI and a teammate's job still get the files")
    for reads in ["ArisGestureTurn.intent(unmarked: unmarked", "await route(unmarked)", "ArisIntent.guarded(intent, said: unmarked)", "ArisRouter.asksForCare(unmarked)",
                  "ArisHandoff.isHandoff(unmarked)", "ArisDeixis.refersToClipboard(unmarked)", "ArisSkillIntent.link(in: unmarked)", "teammateRemoval(unmarked)",
                  "ArisTeamMaking.parse(unmarked)", "teammateCalled(unmarked)", "ArisSpeech.language(of: unmarked)"] {
        check(answer.contains(reads), "files-1: \(reads) reads the user's own words")
    }
    check(!answer.contains("isHandoff(text)") && !answer.contains("refersToClipboard(text)"), "files-1: no command matcher reads the files' text")

    // Circled shots still go along with files: the words keep their markers, so the images must stay.
    let withFiles = turn("이거 [img 1] 뭐야", files: ["/tmp/a.pdf"])
    check(ArisPendingFiles.dropsTurnImages(withFiles, circledShots: false) && !ArisPendingFiles.dropsTurnImages(withFiles, circledShots: true)
            && !ArisPendingFiles.dropsTurnImages("이거 뭐야", circledShots: false),
          "files with circled shots: the files replace the screenshot, never the shots the user circled")
    check(answer.contains("if ArisPendingFiles.dropsTurnImages(heard, circledShots: shots) { seeEnded() }"), "files with circled shots: the turn asks that rule")
}

// MARK: - resume-1: a conversation picked up from the 기록 list

private func resumedConversationTests() {
    let resume = fixTurnFunction("resume(_ entry: ArisHistoryEntry)", in: fixTurnSource("Aris/private/Aris/ArisController.swift"))
    let set = resume.range(of: "history = [ArisContext.Turn(heard: entry.heard, reply: entry.reply)]")?.lowerBound ?? resume.endIndex
    let cleared = resume.range(of: "lastTurnAt = nil")?.lowerBound ?? resume.endIndex
    // The row no longer starts listening (vside-tests.swift, side 2): the turn is put back in the notch, and the clock
    // is cleared before that, so the next thing said or typed does not wipe the history and the marks as stale.
    let shows = resume.range(of: "session = .parked(heard: shown.heard, reply: shown.reply)")?.lowerBound ?? resume.startIndex
    check(set < cleared && cleared < shows,
          "resume-1: the old conversation's clock is cleared before the turn is shown again, so its history and marks are not wiped as stale")
}

// MARK: - brain-1: a rewrite uses the chosen brain

private func chosenBrainTests() {
    let all: [ArisBrain: Bool] = [.claude: true, .codex: true, .antigravity: true, .api: true]
    for brain in ArisBrain.allCases {
        check(ArisBrainChoice.answering(brain, ready: all) == brain, "brain-1: \(brain.rawValue) answers when it is the one chosen and set up")
        check(ArisBrainChoice.answering(brain, ready: nil) == brain && ArisBrainChoice.answering(brain, ready: [:]) == brain,
              "brain-1: before the agent has said what is set up, the chosen brain (\(brain.rawValue)) is kept")
    }
    check(ArisBrainChoice.answering(.codex, ready: [.claude: true, .codex: false, .antigravity: false, .api: false]) == .claude,
          "brain-1: on a Mac without Codex, a request for it goes to a brain that is set up")
    check(ArisBrainChoice.answering(.claude, ready: [.claude: false, .codex: false, .antigravity: true, .api: true]) == .antigravity,
          "brain-1: the fallback follows the user's order")
    check(ArisBrainChoice.answering(.codex, ready: [.claude: false, .codex: false, .antigravity: false, .api: false]) == .codex,
          "brain-1: with nothing set up the chosen brain is asked, and its failure says where to fix it")
    let look = fixTurnSource("Aris/private/Aris/ArisController+Look.swift")
    check(!look.contains("brain: .codex") && look.contains("rewriteSelection(text, look: look, tier: tier, brain: brain)")
            && look.contains("ArisBrainChoice.answering(brain, ready: ArisBrainSetup.shared.ready)"),
          "brain-1: rewriting a selection asks the turn's own brain, never Codex by name")
}

// MARK: - imp-5: a timer that ends while Aris is busy, and a notch left behind

private func leftBehindTests() {
    func left(busy: Bool = true, asking: Bool = false, stopped: Bool = false, replaced: Bool = false, untouched: Bool = true) -> Bool {
        ArisTurnWatch.isLeftBehind(busy: busy, asking: asking, stopped: stopped, replaced: replaced, untouched: untouched)
    }
    check(left(), "imp-5: a turn that ended by itself and left the notch thinking or speaking, untouched, is put back to idle")
    check(!left(busy: false), "imp-5: an idle or listening notch is left alone")
    check(!left(asking: true), "imp-5: a card that is up ends by its own wait")
    check(!left(stopped: true), "imp-5: a turn that was stopped is not second-guessed (whoever stopped it set the notch)")
    check(!left(replaced: true), "imp-5: another turn is running now")
    check(!left(untouched: false), "imp-5: something changed the notch meanwhile (an announcement, a streamed answer)")
    check(ArisTurnWatch.mayBeLeftBehind(busy: true, asking: false, stopped: false, replaced: false)
            && !ArisTurnWatch.mayBeLeftBehind(busy: false, asking: false, stopped: false, replaced: false)
            && ArisTurnWatch.patience >= .seconds(3), "imp-5: the notch is looked at again only after a few seconds")
    check(ArisTimerNews.shows(waited: .seconds(40)) && ArisTimerNews.shows(waited: .seconds(600)) && !ArisTimerNews.shows(waited: .seconds(601)),
          "imp-5: a timer's end is shown at the next pause, but not once it is long past")
    let brief = fixTurnSource("Aris/private/Aris/ArisController+Brief.swift")
    let announce = fixTurnFunction("announce(title: String", in: brief)
    let remembered = announce.range(of: "remember(ArisHistoryEntry(date: Date(), heard: title, reply: text))")?.lowerBound ?? announce.endIndex
    let firstGuard = announce.range(of: "await notify(")?.lowerBound ?? announce.endIndex
    check(remembered < firstGuard && announce.contains("Task { await notify(card, parking: text) }")
          && fixTurnSource("Aris/private/Aris/Notice/ArisController+Notice.swift").contains("await announce(recheck:"),
          "imp-5: the timer's end is in the 기록 list whatever Aris is doing, and its card waits for a pause (notify-card)")
    let controller = fixTurnSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("didSet { watchTurnEnd(turn) }") && fixTurnSource("Aris/private/Aris/ArisController+Watch.swift").contains("ArisTurnWatch.isLeftBehind("),
          "imp-5: every turn is watched to its end")

    // ⌥Space while a dictation's "넣었어요" lingers: the turn that starts is not a dictation.
    let start = fixTurnFunction("startListening()", in: controller)
    check((start.range(of: "if dictation != nil { dictation = nil }")?.lowerBound ?? start.endIndex) < (start.range(of: "openMicrophone()")?.lowerBound ?? start.startIndex),
          "a turn started over a lingering dictation is Aris's own: the dictation is put away first")
}

// MARK: - The pointing words

private func pointingWordTests() {
    for said in ["한화 이글스 경기 결과", "이글스 오늘 이겼어?", "필라델피아 이글스 일정 알려줘", "이창호 9단 기보 찾아줘", "이글이글 타는 태양",
                 "who sings this", "who's singing this?", "skip this", "pause this", "remember this: the door code is 4812",
                 "note this down, the meeting moved to 3", "remember this, my locker is 214", "how about this: we leave at six"] {
        check(!ArisDeixis.refersToScreen(said) && !ArisScreenNeed.pointsAtScreen(said), "deixis: \"\(said)\" points at nothing on the screen")
    }
    for said in ["이글 요약해줘", "이글은 누가 썼어", "이 글 요약해줘", "이문서 번역해줘", "이 메일 답장 써줘", "이 표현 무슨 뜻이야", "이 사진들 정리해 줘",
                 "what is this", "summarize this", "summarize this, please", "remember this page", "who wrote this", "translate this: into Korean please".replacingOccurrences(of: ":", with: ""),
                 "is this right", "what does the selected text mean"] {
        check(ArisDeixis.refersToScreen(said), "deixis: \"\(said)\" still points at the screen")
    }
}

// MARK: - Wording of a turn's own failures

private func turnWordingTests() {
    check(ArisPermissionWords.turnOn(english: false).contains("마이크") && ArisPermissionWords.turnOn(english: true).contains("Microphone")
            && ArisPermissionWords.ready(english: false).contains("⌥Space") && ArisPermissionWords.needsNewerMac(english: true).contains("macOS 26")
            && ArisPermissionWords.pressKeyFirst(english: false).contains("⌥Space"),
          "a turn that can't start says why in the UI's language, Korean or English")
    let controller = fixTurnSource("Aris/private/Aris/ArisController.swift")
    check(!controller.contains("fail(\"Turn on") && !controller.contains("fail(\"Ready.") && !controller.contains("Locale.preferredLanguages")
            && controller.contains("ArisTranscript.notHeard(korean: !ArisUILanguage.english)"),
          "the controller words its failures through the shared UI language, not its own rule")
    let wake = fixTurnSource("Aris/private/Aris/ArisController+Wake.swift")
    check(!wake.contains("fail(\"Press") && !wake.contains("fail(\"Couldn't"), "training the wake word fails in the UI's language too")
    // Every failure of a brain turn reaches the notch as the agent worded it (the notch knows the "can't start" sentence).
    let line = ArisBrainTrouble.cannotStart(.codex, korean: true)
    check(ArisBrainTrouble.isCannotStart(line) && controller.contains("case .failure(let message):")
            && fixTurnSource("Aris/private/Aris/ArisController+Look.swift").contains("case .failure(let message):\n                fail(message)"),
          "a brain that can't start is told on every path with the agent's own sentence, unchanged")
}
