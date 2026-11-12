// Tests for the last QA pass on qa-followup-final: BUG-60 (Aris's own data is never handed out or given to Aside),
// source labels at the end of answers, and the permission card.
import AppKit
import Foundation

func runQAFinal4Tests() {
    qaFinal4OwnDataWordsTests()
    qaFinal4OwnDataTurnTests()
    qaFinal4AsideTests()
    qaFinal4HandOutTests()
    qaFinal4JobClaimTests()
    qaFinal4CardLedgerTests()
    qaFinal4LabelTests()
    qaFinal4LabelSpeechTests()
    qaFinal4PermissionTests()
}

private func final4Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

private let repro = "큐에이 예약 테스트 예약 지워 줘"
private let scheduleNames = ["큐에이 예약 테스트", "아침 브리핑", "날씨"]

// MARK: - BUG-60

/// QA BUG-60: "큐에이 예약 테스트 예약 지워 줘" was taken for website work, handed out as a job, and the job asked Aside to
/// find and delete Aris's own schedule ("브라우저 작업 중 오류가 나서 … 삭제하지 못했어요"). Which words are about Aris's own
/// schedules, to-dos, memory, teammates, timers and settings, and which only look like it.
private func qaFinal4OwnDataWordsTests() {
    check(ArisOwnData.kind(of: repro) == .schedule && ArisOwnData.kind(of: repro, scheduleNames: scheduleNames) == .schedule,
          "BUG-60: the exact words (\(repro)) are about Aris's own schedule, with or without its title known")
    let own: [(String, ArisOwnData.Kind)] = [
        ("delete the reminder for QA", .schedule), ("cancel my scheduled task", .schedule), ("예약 목록 보여 줘", .schedule), ("매일 8시 알림 지워 줘", .schedule),
        ("remove the daily weather schedule", .schedule), ("QA 예약 테스트 예약을 찾아 삭제해 줘", .schedule), ("큐에이 예약 테스트 예약 지워 놔", .schedule),
        ("할 일에서 우유 빼 줘", .todo), ("add milk to my to-do list", .todo), ("좋아하는 과일에 대한 기억 전부 잊어 줘", .memory), ("forget that I like mango", .memory),
        ("큐에이봇 팀원 지워 줘", .teammate), ("타이머 꺼 줘", .timer), ("cancel the timer", .timer), ("아리스 설정 바꿔 줘", .settings),
    ]
    for (words, kind) in own {
        check(ArisOwnData.kind(of: words) == kind, "BUG-60: “\(words)” is Aris's own \(kind.rawValue)")
    }
    // A booking somewhere else, another app's alerts or settings, a computer's memory, other work: never Aris's data.
    let other = ["내일 저녁 7시 식당 예약해 줘", "호텔 예약 취소해 줘", "cancel my hotel booking", "네이버 예약 취소해 줘", "저녁 7시에 예약 잡아 줘", "book a table for two",
                 "유튜브 알림 설정 꺼 줘", "크롬 설정에서 다크모드 켜 줘", "VS Code 설정 파일 정리해 놔", "서버 메모리 누수 조사해 놔", "기억에 남는 영화 추천해 줘",
                 "팀원 평가서 초안 써 놔", "팀원한테 시켜서 조사해 놔", "노션 할 일 목록 정리해 줘", "show me the train schedule", "list the conference schedule and summarise it",
                 "이 논문 요약해 줘", "큐에이 논문 세 편 비교해서 정리해 줘", "올랜도 날씨 찾아 줘", "오늘 날씨 알려 줘", "세 편을 비교해 정리했어요."]
    for words in other {
        check(ArisOwnData.kind(of: words, scheduleNames: scheduleNames) == nil, "BUG-60: “\(words)” isn't Aris's own data")
    }
    // A schedule named by its own title needs no 예약 beside it; a title alone, with nothing that changes it, isn't a request about it.
    check(ArisOwnData.kind(of: "아침 브리핑 지워 줘", scheduleNames: scheduleNames) == .schedule && ArisOwnData.kind(of: "아침 브리핑 지워 줘") == nil
          && ArisOwnData.kind(of: "아침 브리핑 내용 요약해 줘", scheduleNames: scheduleNames) == nil,
          "BUG-60: one of Aris's schedules is told by its own title, with a word that changes or removes it")
}

/// The main turn: the brain is told to do it here with Aris's own tool; a jobs block it answers with anyway is asked
/// about once (do it yourself), then taken out; no teammates are offered; the user's clean turn is otherwise as it was.
private func qaFinal4OwnDataTurnTests() {
    let note = ArisOwnDataTurn.note(.schedule, tools: "/t", task: false)
    check(note.contains("`/t schedule list`") && note.contains("`/t schedule remove <id>`") && note.contains("Never reply with a jobs block")
          && note.contains("Never give it to Aside or the desktop") && note.contains("never a booking on a website") && note.contains("큐에이 stays 큐에이"),
          "BUG-60: the turn's note names Aris's own schedule commands, no jobs, no Aside or desktop, and names as said")
    check(ArisOwnDataTurn.note(.schedule, tools: "/t", task: true).contains("in this job") && !ArisOwnDataTurn.note(.schedule, tools: "/t", task: true).contains("jobs block"),
          "BUG-60: a job that got such a request anyway is told to do it with Aris's own tool too")
    check(ArisOwnDataTurn.note(.teammate, tools: "/t", task: false).contains("No tool of yours changes teammates") && ArisOwnDataTurn.note(.settings, tools: "/t", task: false).contains("change nothing")
          && ArisOwnDataTurn.note(.memory, tools: "/t", task: false).contains("`/t forget \"<words>\"`") && ArisOwnDataTurn.note(.todo, tools: "/t", task: false).contains("`/t todo add|done|edit …`")
          && ArisOwnDataTurn.note(.timer, tools: "/t", task: false).contains("`/t timer …`"),
          "BUG-60: each kind's note names its own command, or says that no tool changes it (teammates, settings)")
    let jobs = "```json\n{\"jobs\":[{\"title\":\"QA 예약 테스트\",\"prompt\":\"QA 예약 테스트 예약을 찾아 삭제해 줘\",\"assignee\":\"clone\"}]}\n```"
    check(ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: false, answer: jobs, acted: false, showedCard: false, commands: 0),
          "BUG-60: a jobs block for Aris's own data is answered by asking the brain once to do it itself")
    check(!ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: true, answer: jobs, acted: false, showedCard: false, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: false, task: false, asked: false, answer: jobs, acted: false, showedCard: false, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: true, task: true, asked: false, answer: jobs, acted: false, showedCard: false, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: false, answer: "예약을 지웠어요.", acted: false, showedCard: false, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: false, answer: jobs, acted: true, showedCard: false, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: false, answer: jobs, acted: false, showedCard: true, commands: 0)
          && !ArisOwnDataTurn.asksAgain(ownData: true, task: false, asked: false, answer: jobs, acted: false, showedCard: false, commands: 1),
          "BUG-60: asked once only, never for other work or a job, and never after the turn ran a command or showed a card")
    let kept = ArisOwnDataTurn.kept(jobs, ownData: true, task: false, korean: true)
    check(kept == ArisOwnDataTurn.keptLine(korean: true) && ArisDispatch.jobsBlockRange(in: kept) == nil
          && ArisOwnDataTurn.kept("확인해 볼게요.\n" + jobs, ownData: true, task: false, korean: true) == "확인해 볼게요.\n" + ArisOwnDataTurn.keptLine(korean: true),
          "BUG-60: a jobs block still there is taken out of the answer, so the app has nothing to hand out")
    check(ArisOwnDataTurn.kept(jobs, ownData: false, task: false, korean: true) == jobs && ArisOwnDataTurn.kept("예약을 지웠어요.", ownData: true, task: false, korean: true) == "예약을 지웠어요.",
          "BUG-60: other work's jobs block, and an answer without one, are as they were")
    let runner = final4Source("ArisAgent/ArisAgentRunner.swift")
    let doubtful = ArisOwnDataTurn.note(.schedule, tools: "/t", task: false), certain = ArisOwnDataTurn.note(.schedule, tools: "/t", task: false, named: true)
    check(doubtful.contains("reads as one about Aris's own schedule") && doubtful.contains("only with that site or place named in the brief")
          && certain.contains("names one of Aris's own schedules") && !certain.contains("If Aris has no such thing"),
          "BUG-60: words that only read like Aris's own leave room for a booking elsewhere; a schedule named by its title doesn't")
    check(ArisOwnData.namesSchedule(repro, scheduleNames: scheduleNames) && ArisOwnData.namesSchedule("아침 브리핑 지워 줘", scheduleNames: scheduleNames)
          && !ArisOwnData.namesSchedule("필라테스 예약 취소해 줘", scheduleNames: scheduleNames) && !ArisOwnData.namesSchedule("아침 브리핑 읽어 줘", scheduleNames: scheduleNames)
          && !ArisOwnData.namesSchedule("날씨 꺼 줘", scheduleNames: scheduleNames) && !ArisOwnData.namesSchedule(repro, scheduleNames: []),
          "BUG-60: a schedule is named by its own title (three characters or more) with a word that changes or removes it")
    check(runner.contains("write(driver.ask(ArisOwnDataTurn.doItHere(tools: Self.toolsPath), tier: tierNow))") && runner.contains("!(ownDataTurn && !isTask)")
          && runner.contains("ArisOwnDataTurn.kept(answer, ownData: true, task: false, korean: koreanRequest)"),
          "BUG-60: the runner holds such a turn's answer until it is whole, asks again in the same turn, and takes a jobs block out")
    // No teammates are offered; what a clean turn of the user's may do besides (memory answered here, learning) is unchanged.
    let own = ArisImageRouting.dispatchPolicy(outsideText: false, screenSeen: false, task: false, arisData: true)
    check(!own.teammates && own.vouch && ArisImageRouting.dispatchPolicy(outsideText: false, screenSeen: false, task: false).teammates
          && !ArisImageRouting.dispatchPolicy(outsideText: true, screenSeen: false, task: false, arisData: true).vouch,
          "BUG-60: a turn about Aris's own data has no teammates to hand out to, and is still the user's own clean turn")
    let agent = final4Source("ArisAgent/main.swift")
    check(agent.contains("let scheduleNames = ArisOwnDataTurn.scheduleNames(home: home)")
          && agent.contains("let ownData = ArisOwnData.kind(of: ArisMemoryText.ownWords(request), scheduleNames: scheduleNames)")
          && agent.contains("arisData: ownData != nil") && agent.contains("browser && ownData == nil"),
          "BUG-60: the agent decides it from the user's own words and Aris's schedule titles, for a turn and for a job")
    let prompt = final4Source("ArisAgent/ArisAgentPrompt.swift")
    check(ArisAgentPrompt.ownDataRule.contains("are never a job: do them in this turn") && ArisAgentPrompt.ownDataRule.contains("never ask Aside or the desktop")
          && prompt.contains("\\(ownDataRule) A job's prompt keeps the user's") && prompt.contains("큐에이 stays 큐에이, never QA")
          && prompt.contains("Names in the brief stay exactly as the user said them"),
          "BUG-60: the standing prompt says Aris's own data is never a job or Aside's, and that names stay as said")
}

/// Aside never gets Aris's own data: refused at its one gate (every brain's call, a job's, agy's relay), before any card.
private func qaFinal4AsideTests() {
    var ran = 0
    let deps = ArisAsideDeps(locate: { .ready("/x/aside") },
                             run: { _, _, _, _ in ran += 1; return ArisSkillProcessResult(status: 0, stdout: "done", stderr: "", timedOut: false) },
                             open: { _ in true }, environment: [:], verify: { _ in true },
                             ownData: { ArisOwnData.mentions($0, scheduleNames: scheduleNames) })
    let job = FakeAsideTurn(brain: "Codex", answers: [.yes([:])])
    job.isTask = true
    let refused = ArisAsideTool.answer("QA 예약 테스트 예약을 찾아 삭제해 줘", turn: job, critical: false, deps: deps)
    check(refused.status != 0 && refused.output == ArisAside.ownDataLine && ran == 0 && job.cards.isEmpty
          && job.audits.last?["answer"] == "refused (Aris's own data)" && job.audits.last?["risk"] == "never",
          "BUG-60: a job's Aside brief about Aris's own schedule is refused before any card, never run, and audited")
    check(ArisAside.ownDataLine.contains("`aris-tools schedule remove <id>`") && ArisAside.ownDataLine.contains("name the site or the place"),
          "BUG-60: the refusal says how it is done, and how a real booking on a website is told apart")
    // The turn's own request names one of Aris's schedules: nothing of that turn goes to Aside, however the brief is worded.
    let turn = FakeAsideTurn(brain: "Codex", answers: [.yes([:])])
    turn.asideOwnData = true
    check(ArisAsideTool.answer("Find the item called QA test and delete it", turn: turn, critical: false, deps: deps).output == ArisAside.ownDataLine && ran == 0,
          "BUG-60: in a turn that names one of Aris's schedules, Aside gets nothing, whatever the brief says")
    // Words that only read like Aris's own (a booking with no place named): refused with how to tell it apart, and the
    // same booking with its place named goes through.
    let unsure = FakeAsideTurn(brain: "Codex", answers: [.yes([:])])
    check(ArisAsideTool.answer("필라테스 예약 취소해 줘", turn: unsure, critical: true, deps: deps).output == ArisAside.ownDataLine && ran == 0
          && ArisAsideTool.answer("필라테스 스튜디오 사이트에서 내일 예약 취소해 줘", turn: unsure, critical: true, deps: deps).status == 0 && ran == 1,
          "BUG-60: a booking with no place named is asked to name it; with its site named it goes to Aside on its card")
    // A schedule named by its title, with no 예약 in the brief.
    let named = FakeAsideTurn(brain: "Claude", answers: [.yes([:])])
    check(ArisAsideTool.answer("아침 브리핑 지워 줘", turn: named, critical: false, deps: deps).output == ArisAside.ownDataLine && ran == 1,
          "BUG-60: a brief that names one of Aris's schedules by its title is refused")
    // Website work still reaches Aside's own gate and card.
    let web = FakeAsideTurn(brain: "Codex", answers: [.yes([:])])
    let done = ArisAsideTool.answer("캐치테이블에서 내일 저녁 7시 예약 취소해 줘", turn: web, critical: true, deps: deps)
    check(done.status == 0 && ran == 2 && web.cards.count == 1, "BUG-60: a booking on a website still goes to Aside, on its card")
    // One gate for every brain: the shell gate adds no refusal of its own, so the brain always reads the line that says how it is done.
    check(final4Source("ArisAgent/ArisAsideTool.swift").contains("if turn.asideOwnData || deps.ownData(brief) {")
          && final4Source("ArisAgent/ArisAsideRoutes.swift").contains("var asideOwnData: Bool { runner.ownScheduleNamedNow }")
          && !final4Source("ArisAgent/ArisRiskPolicy.swift").contains("ArisOwnData"),
          "BUG-60: the refusal sits at Aside's one gate, which every brain's call, every job's and the relay pass")
    // Computer use never works in Aris itself, nor in Calendar's or Reminders' windows.
    check(ArisRiskPolicy.computerUseIsNever(["Aris"]) && ArisRiskPolicy.computerUseIsNever(["com.lumenjsn.aris"]) && ArisRiskPolicy.computerUseIsNever(["아리스"])
          && ArisDesktopGate.neverRefusal.contains("Aris itself") && ArisDesktopGate.calendarRefusal.contains("aris-tools remind"),
          "BUG-60: computer use never works in Aris itself, and Calendar and Reminders change only through their tools")
}

/// The app: Aris's own data never becomes website work or a hand-out; a job's prompt carries the user's words as said.
private func qaFinal4HandOutTests() {
    let turn = ArisHandOutPlan.Turn(words: repro, brain: .claude, turnId: nil, untrustedTurn: true)
    let spec = ArisJobSpec(title: "QA 예약 테스트", prompt: "QA 예약 테스트 예약을 찾아 삭제해 줘", assignee: .clone, cwd: nil, appHint: nil)
    check(ArisHandOutPlan.keepsInTurn([spec], turn: turn) && ArisHandOutPlan.keepsInTurn([], turn: turn)
          && ArisHandOutPlan.keepsInTurn([], turn: ArisHandOutPlan.Turn(words: "delete the reminder for QA", brain: .codex, turnId: nil)),
          "BUG-60: the app never dispatches a job about Aris's own data (a jobs block, website work, or the user's words as one job)")
    let other = ArisHandOutPlan.Turn(words: "큐에이 논문 세 편 비교해서 정리해 줘", brain: .codex, turnId: nil)
    let planned = ArisHandOutPlan.plan([ArisJobSpec(title: "a", prompt: "Compare the QA papers", assignee: .helper(1), cwd: nil, appHint: nil),
                                        ArisJobSpec(title: "b", prompt: "Summarise them", assignee: .helper(2), cwd: nil, appHint: nil)], turn: other)
    check(planned.count == 2 && planned.allSatisfy { $0.spec.prompt.contains("“큐에이 논문 세 편 비교해서 정리해 줘”") } && !ArisHandOutPlan.keepsInTurn(planned.map(\.spec), turn: other),
          "BUG-60: every job's prompt carries the user's words exactly as said (큐에이 stays 큐에이), and other work is still handed out")
    check(!ArisHandoff.isHandoff("큐에이 예약 테스트 예약 지워 놔") && ArisHandoff.isHandoff("논문 세 편 비교해서 정리해 놔") && ArisHandoff.isHandoff("서버 메모리 누수 조사해 놔")
          && ArisHandoff.isHandoff("VS Code 설정 파일 정리해 놔"),
          "BUG-60: “…해 놔” never hands Aris's own data out, and still hands other work out")
    let controller = final4Source("Aris/private/Aris/ArisController.swift")
    check(controller.contains("browserWork = routed.browserWork && brain != .antigravity && !ArisOwnData.mentions(unmarked)"),
          "BUG-60: the router's “website work” never takes Aris's own data to Aside (the path the live bug took)")
    let team = final4Source("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("if ArisHandOutPlan.keepsInTurn(specs, turn: turn)") && !team.contains("unverifiedClaim"),
          "BUG-60: the hand-out itself checks it, whoever asked for it")
}

/// A job's "삭제했어요" is passed on only when Aris's own store shows the change.
private func qaFinal4JobClaimTests() {
    let before = ArisOwnDataStores(schedules: ["1|큐에이 예약 테스트", "2|아침 브리핑"], memories: ["m1|망고"], teammates: ["t1|큐에이봇"])
    var removed = before
    removed.schedules = ["2|아침 브리핑"]
    let claim = "QA 예약 테스트 예약을 삭제했어요."
    let checked = { (answer: String, request: String, after: ArisOwnDataStores) in
        ArisOwnDataHonesty.checked(answer, request: request, scheduleNames: scheduleNames, before: before, after: after, korean: true)
    }
    check(checked(claim, repro, before) == ArisOwnDataHonesty.unchangedLine(.schedule, korean: true)
          && ArisOwnDataHonesty.unchangedLine(.schedule, korean: true).contains("확인해 보니 Aris에는 바뀐 게 없어요"),
          "BUG-60: a job's “삭제했어요” for a schedule that is still there is never passed on: \(checked(claim, repro, before))")
    check(checked(claim, repro, removed) == claim, "BUG-60: the same words stand once Aris's own store shows the schedule gone")
    check(checked("브라우저 작업 중 오류가 나서 삭제하지 못했어요.", repro, before) == "브라우저 작업 중 오류가 나서 삭제하지 못했어요.",
          "BUG-60: an answer that claims nothing is as it was")
    check(checked("우유를 할 일에서 뺐고 목록도 지웠어요.", "할 일에서 우유 빼 줘", before) == ArisOwnDataHonesty.uncheckedLine(.todo, korean: true),
          "BUG-60: a claim about to-dos, which the agent can't read, is told as one it couldn't check")
    check(checked("세 편을 비교해 정리했어요. 표도 추가했어요.", "논문 세 편 비교해서 정리해 놔", before) == "세 편을 비교해 정리했어요. 표도 추가했어요.",
          "BUG-60: other work's result is passed on as written")
    let aside = checked("예약 목록에서 그 항목을 삭제했어요.", "어제 말한 그거 정리해 놔", before)
    check(aside.hasPrefix("예약 목록에서 그 항목을 삭제했어요.") && aside.contains("Aris의 예약은 바뀌지 않았어요"),
          "BUG-60: a result that reads like a change to Aris's schedules, from other work, keeps its words with the checked fact after them")
    check(ArisOwnDataHonesty.checked("I deleted the reminder.", request: "delete the reminder for QA", scheduleNames: [], before: before, after: before, korean: false)
          .contains("nothing of Aris's changed"), "BUG-60: the same check in English")
    check(final4Source("ArisAgent/ArisAgentRunner.swift").contains("ArisOwnDataHonesty.checked(answer, request: request, scheduleNames: scheduleNamesBefore, before: before,"),
          "BUG-60: the runner checks every job's answer against the stores as they were when the job began")
}

/// One card's answer is one line in the ledger, keyed by the card's id (it was written at 00:32:36 and 00:32:37).
private func qaFinal4CardLedgerTests() {
    check(ArisCardAnswer.appRecords(waiter: false, agentCard: false) && !ArisCardAnswer.appRecords(waiter: true, agentCard: false)
          && !ArisCardAnswer.appRecords(waiter: false, agentCard: true),
          "BUG-60: the app tells the ledger only about a card it handles itself, never one the agent made")
    // Both are asked by the held-question runner now (audit card-1, card-2: ArisController+CardPark).
    let park = final4Source("Aris/private/Aris/ArisController+CardPark.swift")
    check(park.contains("self.askCard(ask, handsFree: handsFree, agentCard: true, quiet: quietNow)"),
          "BUG-60: a job's parked card and an inbox card are the agent's: one line, where the agent takes the answer")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var ledger = ArisCardLedger()
    // The live order: the app's word first, while the agent still waits for that card; then POST /confirm.
    check(!ledger.writesAppLine("mcp-7-abc", agentWaits: true, at: now), "BUG-60: no “app card” line for a card the agent still waits for")
    ledger = ledger.agentAnswered("mcp-7-abc")
    check(!ledger.writesAppLine("mcp-7-abc", agentWaits: false, at: now.addingTimeInterval(1)) && !ledger.writesAppLine("mcp-7-abc", agentWaits: false, at: now.addingTimeInterval(600)),
          "BUG-60: nor after the agent took its answer, in either order")
    // An app-handled card: one line; the same id told again at once is the same answer; shown again later, a new one.
    check(ledger.writesAppLine("undo-42", agentWaits: false, at: now), "BUG-60: an app-handled card's answer is written")
    ledger = ledger.appWrote("undo-42", at: now)
    check(!ledger.writesAppLine("undo-42", agentWaits: false, at: now.addingTimeInterval(1)) && ledger.writesAppLine("undo-42", agentWaits: false, at: now.addingTimeInterval(60))
          && ledger.writesAppLine("save-answer-1", agentWaits: false, at: now) && !ledger.writesAppLine("", agentWaits: false, at: now),
          "BUG-60: the same card id told twice within seconds is one line; the card shown again later is its own")
    var many = ArisCardLedger()
    for index in 0..<(ArisCardLedger.kept + 50) { many = many.agentAnswered("card-\(index)").appWrote("app-\(index)", at: now) }
    check(many.agentCards.count == ArisCardLedger.kept && many.appCards.count <= ArisCardLedger.kept, "BUG-60: the ledger keeps only the newest ids")
    // The agent applies an answer once: the card is gone after the first.
    let cards = ArisMCPCards()
    var answers = 0
    let shown = cards.put(ArisMCPCard(title: "Aside", detail: "d", full: nil, fields: []), timeout: 60) { _ in answers += 1 }
    check(cards.decide(shown.id, allow: true, detail: "d", full: nil, edits: [:], shown: nil) == .decided
          && cards.decide(shown.id, allow: true, detail: "d", full: nil, edits: [:], shown: nil) == .unknown && answers == 1,
          "BUG-60: a card's answer is applied once; the same id answered again finds no card")
    let agent = final4Source("ArisAgent/main.swift")
    check(agent.contains("cardLedger = cardLedger.agentAnswered(id)") && agent.contains("if cardLedger.writesAppLine(id, agentWaits: agentWaits || ArisMCPCards.owns(id), at: now)"),
          "BUG-60: the agent keys the ledger by the card's id on both routes")
}

// MARK: - Source labels

/// QA live: "환율 확인", "AP통신 보도", "애플 발표" at the end of answers, shown and read out. They were a source link's label,
/// left when the link was taken out; or a source's bare name written after the last sentence.
private func qaFinal4LabelTests() {
    let linked = "1달러는 약 천삼백사십오 원이에요. [환율 확인](https://example.com/fx)"
    check(ArisAgentStream.spoken(linked) == "1달러는 약 천삼백사십오 원이에요."
          && ArisAgentStream.spoken("맥북 에어 M5는 출시됐어요 ([애플 발표](https://apple.com/newsroom), [The Verge](https://theverge.com/x)).") == "맥북 에어 M5는 출시됐어요."
          && ArisAgentStream.spoken("AP가 그렇게 보도했어요. [AP통신 보도](https://apnews.com/a) [로이터](https://reuters.com/b)") == "AP가 그렇게 보도했어요."
          && ArisAgentStream.spoken("환율은 천삼백 원이에요 [환율 확인](https://example.com/fx)") == "환율은 천삼백 원이에요",
          "labels: a source link after a sentence, or in brackets, leaves the answer with its label: \(ArisAgentStream.spoken(linked))")
    check(ArisAgentStream.spoken("자세한 건 [애플 지원 페이지](https://support.apple.com)에서 볼 수 있어요.") == "자세한 건 애플 지원 페이지에서 볼 수 있어요."
          && ArisAgentStream.spoken("관련 기사예요:\n[기사 하나](https://a.com/1)\n[기사 둘](https://b.com/2)") == "관련 기사예요:\n기사 하나\n기사 둘"
          && ArisAgentStream.spoken("[애플 지원](https://support.apple.com)") == "애플 지원",
          "labels: a link inside a sentence, a list of links and an answer that is only a link keep their words")
    let fenced = "여기예요. [출처](https://a.com)\n```json\n{\"jobs\":[]}\n```"
    check(ArisAgentStream.spoken(fenced).hasPrefix("여기예요.") && ArisAgentStream.spoken(fenced).contains("```json\n{\"jobs\":[]}\n```"),
          "labels: a machine block beside it is kept exactly as written")
    // A "Sources" list that closes the answer, and links after 출처:.
    let listed = "금리가 동결됐어요.\n\nSources:\n- [한국은행 기준금리 동결](https://bok.or.kr/a)\n- [연합뉴스 보도](https://yna.co.kr/b)"
    check(ArisAgentStream.spoken(listed) == "금리가 동결됐어요." && ArisAgentStream.spoken("금리가 동결됐어요.\n\n**출처**\n1. [한국은행](https://bok.or.kr/a)") == "금리가 동결됐어요."
          && ArisAgentStream.spoken("금리가 동결됐어요. 출처: [한국은행](https://bok.or.kr/a), [연합뉴스](https://yna.co.kr/b)") == "금리가 동결됐어요.",
          "labels: a Sources or 출처 list of links that closes the answer goes whole: \(ArisAgentStream.spoken(listed))")
    check(ArisAgentStream.spoken("순서예요.\n1. [첫째](https://a.com)\n2. [둘째](https://b.com)") == "순서예요.\n1. 첫째\n2. 둘째"
          && ArisAgentStream.spoken("읽을거리예요.\n\n참고:\n- 첫 번째 책\n- [둘째](https://b.com)") == "읽을거리예요.\n\n참고:\n- 첫 번째 책\n- 둘째",
          "labels: a numbered list of links, and a list that isn't only links, keep their words")
    check(ArisAgentStream.citationLinks.map(\.pattern) == ArisSpeakable.citationLinks.map(\.pattern)
          && ArisAgentStream.citationLinks.map(\.template) == ArisSpeakable.citationLinks.map(\.template),
          "labels: the agent and the app take the same source links out")
    // The app, on what it shows: the same links, and a source named after the last sentence with no link.
    check(ArisSpeakable.shown(linked, korean: true) == "1달러는 약 천삼백사십오 원이에요." && ArisSpeakable.shown(listed, korean: true) == "금리가 동결됐어요."
          && ArisSpeakable.shown("AP가 그렇게 보도했어요.\nAP통신 보도", korean: true) == "AP가 그렇게 보도했어요."
          && ArisSpeakable.shown("가격은 3.5달러예요. 출처: 한국은행", korean: true) == "가격은 3.5달러예요." && ArisSpeakable.shown("가격은 3.5달러예요. (출처: 한국은행)", korean: true) == "가격은 3.5달러예요."
          && ArisSpeakable.shown("It rose 2%. Source: Reuters", korean: false) == "It rose 2%." && ArisSpeakable.shown("It rose 2%. via AP", korean: false) == "It rose 2%.",
          "labels: a source link, or a source named after the last sentence (… 보도, 출처: …, Source: …, via …), is never shown")
    // Never words that could be the answer itself.
    let stays = ["원문 기사를 확인했어요.", "환율 확인", "정리했어요. 내일 다시 볼게요.", "남은 건 하나예요. 메일 확인", "내일 일정은 하나예요. 팀 발표",
                 "할 일은 세 가지예요. 장보기, 운동, 메일 확인", "오늘 일정은 두 개예요. 10시 팀 회의, 3시 분기 실적 발표", "- 첫 번째 기사예요.\n- 두 번째 보도",
                 "1. 첫 기사예요.\n2. 두 번째 보도", "버전은 2. 새 보도", "두 가지예요.\n| 항목 | 값 |\n| 뉴스 | 보도 |"]
    for text in stays {
        check(ArisSpeakable.shown(text, korean: true) == text, "labels: “\(text.replacingOccurrences(of: "\n", with: "⏎"))” stays as written")
    }
    check(final4Source("ArisAgent/ArisAgentPrompt.swift").contains("a trailing source label"), "labels: the prompt asks for no trailing source label at the source")
}

/// The voice: a source link or name is never read, as the answer streams or at its end.
private func qaFinal4LabelSpeechTests() {
    let linked = "1달러는 약 천삼백사십오 원이에요. [환율 확인](https://example.com/fx)"
    check(!ArisSpeakable.speakable("AP가 그렇게 보도했어요. AP통신 보도").contains("AP통신") && !ArisSpeakable.speakable("맥북 에어 M5는 출시됐어요 ([애플 발표](https://apple.com/n)).").contains("애플 발표")
          && !ArisSpeakable.speakable(linked).contains("환율 확인") && ArisSpeakable.speakable(linked).contains("천삼백사십오"),
          "labels: neither a source link's label nor a source named after the last sentence is spoken")
    check(ArisSpeakable.speakable("자세한 건 [애플 지원 페이지](https://support.apple.com)에서 볼 수 있어요.") == "자세한 건 애플 지원 페이지에서 볼 수 있어요.",
          "labels: a link inside a sentence is read as its words")
    // As it streamed live: the raw link arrives piece by piece, then the answer comes without it.
    let said = { (raw: String, final: String) -> [String] in
        var stream = ArisSpeechStream()
        var out: [String] = []
        var at = raw.startIndex
        while at < raw.endIndex {
            let next = raw.index(at, offsetBy: 7, limitedBy: raw.endIndex) ?? raw.endIndex
            out += stream.add(String(raw[at..<next]))
            at = next
        }
        return out + stream.finish(shown: ArisSpeakable.shown(final, korean: true), korean: true)
    }
    let streamed = said(linked, ArisAgentStream.spoken(linked))
    check(streamed == ["1달러는 약 천삼백사십오 원이에요."], "labels: a streamed answer's source link is never read out at the end: \(streamed)")
    let long = "AP가 그렇게 보도했어요. [블룸버그 통신의 오늘 아침 보도](https://bloomberg.com/news/articles/x)"
    check(said(long, ArisAgentStream.spoken(long)) == ["AP가 그렇게 보도했어요."], "labels: nor a long label, part of which had already reached the voice")
    let named = "금리가 동결됐어요. 연합뉴스 경제부 보도"
    check(said(named, named) == ["금리가 동결됐어요."], "labels: nor a source named after the last sentence as it streamed: \(said(named, named))")
    let inline = "네, 맞아요 [출처](https://example.com/abcdefgh)"
    check(said(inline, ArisAgentStream.spoken(inline)) == ["네, 맞아요"], "labels: words that were waiting before the link are still said: \(said(inline, ArisAgentStream.spoken(inline)))")
    let plain = "오늘은 맑아요. 내일은 비가 와요."
    check(said(plain, plain) == ["오늘은 맑아요.", "내일은 비가 와요."], "labels: an answer without one is read as before")
    var splitter = ArisSentenceSplitter()
    _ = splitter.add("첫 문장이에요. 둘째 문장의 앞부분")
    splitter.keepWaiting(first: 4)
    check(splitter.waiting == " 둘째 " && splitter.finish() == ["둘째"], "labels: the splitter keeps only the waiting words the answer kept")
    check(ArisSpeakable.streaming("1달러는 약 천삼백사십오 원이에요. [환율 확") == "1달러는 약 천삼백사십오 원이에요."
          && ArisSpeakable.streaming("1달러는 약 천삼백사십오 원이에요. ([환율 확인](https://exam") == "1달러는 약 천삼백사십오 원이에요."
          && ArisSpeakable.streaming("1달러는 약 천삼백사십오 원이에요. [환율 확인](https://example.com/fx)") == "1달러는 약 천삼백사십오 원이에요."
          && ArisSpeakable.streaming("[img 1]은 그래프예요") == "[img 1]은 그래프예요" && ArisSpeakable.streaming("오늘은 맑아요. 내일은") == "오늘은 맑아요. 내일은",
          "labels: while it streams, the notch shows neither a source link nor the start of one")
    check(final4Source("Aris/private/Aris/ArisController.swift").contains("showAnswer(ArisSpeakable.streaming(speech.display))"),
          "labels: the notch never shows one while the answer streams either")
}

// MARK: - Permissions

/// QA after a macOS update: Notes, Mail and screen reads failed and nothing said that Full Disk Access or Screen
/// Recording was off. The tools say so, and the answer gets a card whose button opens that list in System Settings.
private func qaFinal4PermissionTests() {
    let disk = ArisLocalStore.diskAccessLine("메모")
    check(disk.contains("전체 디스크 접근 권한") && disk.contains("지금 꺼져 있어요") && disk.contains("macOS 업데이트 뒤에 꺼졌을 수 있어요") && !disk.contains("]("),
          "permissions: a missing Full Disk Access says it is off (maybe after a macOS update), in words the brain can say")
    let noGrant = ArisLocalStore.screenLine(.noPermission), noWindow = ArisLocalStore.screenLine(.noWindow("메모")),
        failed = ArisLocalStore.screenLine(.captureError("no image")), english = ArisLocalStore.screenLine(.noPermission, korean: false)
    check(noGrant.contains("화면 기록 권한") && noGrant.contains("지금 꺼져 있어요") && noWindow.contains("메모의 창이 화면에 없어서")
          && failed.contains("화면 기록 권한은 켜져 있는데") && !failed.contains("꺼져 있어요") && english.contains("Screen Recording") && english.contains("it's off"),
          "permissions: a failed screen read names its reason (no grant, no window, a capture error), Korean and English")
    let screen = final4Source("ArisTools/ArisScreen.swift")
    check(!screen.contains("couldn't capture the screen") && screen.contains("CGPreflightScreenCaptureAccess() ? .captureError")
          && screen.components(separatedBy: "if lines.isEmpty, !CGPreflightScreenCaptureAccess() { fail(ArisLocalStore.screenLine(.noPermission)) }").count == 3,
          "permissions: `aris-tools screen` tells a missing grant from a capture error, and never calls an ungranted capture “no text”")
    // The card: picked by what the turn ran and what aris-agent may read now.
    let tools = "/t", off = ArisWidgetPick.Access(disk: false, screen: false)
    check(ArisWidgetPick.card(commands: ["/t notes recent"], tools: tools, access: off) == ["type": "permission", "pane": "disk"]
          && ArisWidgetPick.card(commands: ["/t mail recent"], tools: tools, access: off)?["pane"] == "disk"
          && ArisWidgetPick.card(commands: ["/t messages recent --with 엄마"], tools: tools, access: off)?["pane"] == "disk"
          && ArisWidgetPick.card(commands: ["/t screen"], tools: tools, access: off) == ["type": "permission", "pane": "screen"]
          && ArisWidgetPick.card(commands: ["/t weather", "/t screen"], tools: tools, access: off)?["type"] == "permission",
          "permissions: a read that found Full Disk Access or Screen Recording off earns the permission card, before any other")
    check(ArisWidgetPick.card(commands: ["/t notes recent", "/t screen"], tools: tools) == nil
          && ArisWidgetPick.card(commands: ["/t notes recent"], tools: tools, access: ArisWidgetPick.Access(disk: true, screen: false)) == nil
          && ArisWidgetPick.card(commands: ["/t weather"], tools: tools, access: off) == ["type": "weather"]
          && ArisWidgetPick.card(commands: ["echo notes screen"], tools: tools, access: off) == nil,
          "permissions: no card while the permission is on, or for a turn that ran no such read")
    let answer = ArisWidgetPick.attach(to: "메모를 읽지 못했어요.", commands: ["/t notes recent"], tools: tools, access: off)
    check(ArisWidget.request(in: answer) == ArisWidgetRequest(kind: .permission, pane: .disk) && ArisSpeakable.shown(answer, korean: true) == "메모를 읽지 못했어요.",
          "permissions: the answer carries the card's block, which is never shown or said")
    check(ArisWidget.request(json: #"{"type":"permission","pane":"screen"}"#)?.pane == .screen && ArisWidget.request(json: #"{"type":"permission"}"#) == nil
          && ArisWidget.request(json: #"{"type":"permission","pane":"x-apple.systempreferences:evil"}"#) == nil,
          "permissions: the card names one of the two lists, never an address of its own")
    check(ArisPermissionPane.disk.settingsURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
          && ArisPermissionPane.screen.settingsURL == "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
          && ArisPermissionPane.allCases.allSatisfy { $0.title(korean: true).contains("꺼져 있어요") && $0.detail(korean: true).contains("Aris에") && !$0.detail(korean: true).contains("aris-agent") && $0.title(korean: false).contains("is off") }
          && ArisPermissionPane.button(korean: true) == "시스템 설정 열기",
          "permissions: each card says what is off, for what, and its button opens that exact System Settings list")
    let model = final4Source("Aris/private/Aris/ArisWidgetModel.swift")
    check(model.contains("guard let pane = request.pane, await ArisAgentClient.agentHas(pane) == false else { return nil }")
          && model.contains("NSWorkspace.shared.open(url)") && final4Source("ArisAgent/main.swift").contains("case \"screenAccess\":"),
          "permissions: the card shows only while aris-agent itself says the permission is off, and opens Settings only on a click")
    check(final4Source("ArisAgent/ArisAgentRunner.swift").contains("access: commands.isEmpty ? ArisWidgetPick.Access() : .now"),
          "permissions: the runner reads what aris-agent may read when a turn ran commands")
}
