// Tests for jv-jobfix (the owner, 2026-11-19): a correct list of the Canvas assignments he hadn't submitted was
// reported as FAILED ("background task not done: couldNot"), and the request went to Aside, the browser agent, though
// Aris has its own Canvas tool and he had just connected Composio.
// A: the job verdict reads what the job says about itself apart from what it reports (ArisJobSaid, ArisJobVerdict),
//    Aside's own outcome reaches the verdict (ArisJobWork.delegated), and a not-done job's answer stays readable.
// B: website work that names a service Aris reaches without a browser goes to that service first (ArisServiceReach),
//    brains are told the order, and Canvas says why it gave no answer (ArisCanvas).
// Called from main.swift; uses its check().
import Foundation

private typealias V = ArisJobVerdict

/// The owner's request as Aris briefed Aside (2026-11-19 08:43:29Z).
private let canvasTask = "Canvas 확인해서 일주일 안에(2026-11-19부터 11-26까지) 끝내야 되는 과제들 다 정리해 줘. 아직 제출 안 한 과제만, 과목명, 과제 이름, 마감 날짜와 시간(올랜도 시간)을 마감 빠른 순으로 알려 줘. 이미 마감이 지났는데 안 낸 과제가 있으면 따로 알려 줘."

/// A complete answer to it, with the negatives of its subject in it.
private let canvasList = """
Canvas에서 확인한 결과, 11월 19일부터 26일까지 아직 제출하지 않은 과제는 4개예요.

1. MAT237 — Problem Set 8 · 11월 20일(목) 23:59
2. CSC263 — Assignment 3 · 11월 21일(금) 22:00
3. PHY254 — Lab Report 5 · 11월 24일(월) 17:00
4. STA247 — Quiz 6 · 11월 26일(수) 11:59

마감이 지났는데 안 낸 과제: CSC263 Weekly Exercise 7 (11월 17일 23:59 마감, 아직 제출되지 않았어요). 이 과제는 아직 제출하지 않았어요.
"""

private let asideWork = ArisJobWork(tools: 1, failed: 0, acted: true, delegated: true)

/// One row of the verdict's table.
private struct VerdictRow {
    let name: String
    let task: String
    let answer: String
    let work: ArisJobWork?
    let expected: ArisJobVerdict
}

private let typed = "TextEdit의 jobA.txt 창에 '하나' 입력해 놔, 끝나면 알려줘"

private let verdictTable: [VerdictRow] = [
    // The owner's case, with Aside's report, with an agent that doesn't count, and with an offer at the end.
    VerdictRow(name: "the owner's Canvas list (Aside finished)", task: canvasTask, answer: canvasList, work: asideWork, expected: .done),
    VerdictRow(name: "the owner's Canvas list, no work counted", task: canvasTask, answer: canvasList, work: nil, expected: .done),
    VerdictRow(name: "the list ending in an offer, no work counted", task: canvasTask, answer: canvasList + "\n필요하면 캘린더에 추가해 드릴게요.", work: nil, expected: .done),
    VerdictRow(name: "an English list of what wasn't submitted", task: "Check Canvas and list the assignments I haven't submitted that are due this week",
               answer: "Here's what's due by Nov 26 that you haven't submitted yet:\n- MAT237 Problem Set 8 — Thu Nov 20, 11:59 PM\n- CSC263 Assignment 3 — Fri Nov 21, 10:00 PM\nOverdue and not submitted: CSC263 Weekly Exercise 7 (was due Nov 17). You didn't hand it in.",
               work: nil, expected: .done),
    VerdictRow(name: "the build didn't fail", task: "check whether last night's CI build passed",
               answer: "The build didn't fail: all 412 tests passed in 6 min 12 s. The only warning is a deprecated API in Networking.swift.",
               work: ArisJobWork(tools: 2, failed: 0, acted: true), expected: .done),
    VerdictRow(name: "he did not reply", task: "Slack에서 민수가 답장했는지 확인해 줘",
               answer: "민수는 아직 답장하지 않았어요. 마지막 메시지는 어제 오후 4시에 사용자가 보낸 거예요.", work: ArisJobWork(tools: 1, failed: 0, acted: true), expected: .done),
    VerdictRow(name: "he did not reply (English)", task: "did Sam answer my email about the offsite?",
               answer: "No, Sam did not reply. Your last email to them was on Monday at 9:14 and there's nothing from him since.", work: nil, expected: .done),
    VerdictRow(name: "the task's own negation is the subject", task: "안 읽은 메일 정리해 줘",
               answer: "아직 읽지 않은 메일이 3개예요. 그중 하나는 아직 읽지 못한 학교 공지예요.", work: ArisJobWork(tools: 1, failed: 0, acted: true), expected: .done),
    // Partial results: shown as done, the caveat in the answer.
    VerdictRow(name: "a partial result (Korean)", task: canvasTask,
               answer: "세 과목은 확인했고 한 과목(PHY254)은 로그인이 필요해서 못 봤어요.\n- MAT237 Problem Set 8 · 11월 20일 23:59\n- CSC263 Assignment 3 · 11월 21일 22:00\n- STA247 Quiz 6 · 11월 26일 11:59",
               work: asideWork, expected: .done),
    VerdictRow(name: "a partial result (English)", task: "Check Canvas and list what's due this week",
               answer: "I checked three of your four courses but couldn't open PHY254 (it needs a separate login).\n- MAT237 Problem Set 8, Nov 20 11:59 PM\n- CSC263 Assignment 3, Nov 21 10:00 PM",
               work: nil, expected: .done),
    VerdictRow(name: "a long report with a caveat at its end", task: "summarise the project update thread",
               answer: "The team agreed to ship version 2.4 on December 3rd after the payment fixes land. Dana owns the release notes and will circulate a draft by Friday. QA found two blockers in checkout, both assigned to Lee, with fixes expected Tuesday. Marketing moves the announcement to the following Monday so support has time to prepare the FAQ. I couldn't open the attached PDF.",
               work: ArisJobWork(tools: 2, failed: 0, acted: true), expected: .done),
    // Honest failures: red.
    VerdictRow(name: "it couldn't sign in (Korean)", task: canvasTask,
               answer: "Canvas에 로그인할 수 없었어요. 학교 로그인 페이지에서 2단계 인증을 요구해서 Aside가 더 진행하지 못했어요. Aside에서 한 번 로그인해 두시면 다시 확인해 볼게요.",
               work: asideWork, expected: .notDone(.couldNot)),
    VerdictRow(name: "it couldn't access Canvas (English)", task: "Check Canvas and list what's due this week",
               answer: "I couldn't access Canvas. The sign-in page asked for Duo two-factor authentication, which I can't approve for you. If you sign in once in the browser, I can try again and list what's due this week.",
               work: nil, expected: .notDone(.couldNot)),
    VerdictRow(name: "it found nothing it could", task: "Canvas에서 이번 주 과제 찾아 줘", answer: "과제를 찾지 못했어요.", work: ArisJobWork(tools: 1, failed: 0, acted: true), expected: .notDone(.couldNot)),
    VerdictRow(name: "it can't help", task: "check my bank balance", answer: "Sorry, I can't access your bank account from here.", work: nil, expected: .notDone(.couldNot)),
    VerdictRow(name: "Aside came back without an answer", task: canvasTask, answer: "Canvas를 확인해 봤어요.",
               work: ArisJobWork(tools: 2, failed: 1, acted: true, delegated: false), expected: .notDone(.stepFailed)),
    VerdictRow(name: "Aside failed and the job says so", task: canvasTask, answer: "Aside가 끝내지 못했어요: Canvas 페이지가 열리지 않았어요.",
               work: ArisJobWork(tools: 1, failed: 1, acted: false, delegated: false), expected: .notDone(.couldNot)),
    // Plans and promises.
    VerdictRow(name: "a plan, no work counted", task: canvasTask, answer: "Canvas를 확인해서 과제를 정리해 드릴게요. 잠시만 기다려 주세요.", work: nil, expected: .notDone(.planOnly)),
    VerdictRow(name: "a promise with no tool call", task: canvasTask, answer: "확인되면 알려드릴게요.", work: ArisJobWork(tools: 0, failed: 0, acted: false), expected: .notDone(.planOnly)),
    // Work on the Mac stays strict.
    VerdictRow(name: "half the typing done", task: typed, answer: "jobA.txt에는 '하나'를 입력했고, jobB.txt에는 입력하지 못했어요.",
               work: ArisJobWork(tools: 3, failed: 1, acted: true), expected: .notDone(.couldNot)),
    VerdictRow(name: "a build run with failing tests is a result", task: "터미널에서 빌드 실행해 줘",
               answer: "빌드를 실행했어요. 테스트 2개가 실패했어요: testLogin, testUpload. 나머지 410개는 통과했어요.",
               work: ArisJobWork(tools: 2, failed: 1, acted: true), expected: .done),
    // The seventh VM pass (fix-11), still red.
    VerdictRow(name: "VM: already in progress", task: typed, answer: "TextEdit 작업은 이미 진행 중이라, 끝나면 알려드릴게요.",
               work: ArisJobWork(tools: 0, failed: 0, acted: false), expected: .notDone(.alreadyRunning)),
    VerdictRow(name: "VM: a two-part plan", task: "계산기 앱에서 7 버튼 누르기, 그리고 캘린더 앱에서 Week 버튼 누르기",
               answer: "두 가지를 따로 진행할게요, 끝나면 알려 드릴게요.\n진행할 일\n[ ] 계산기 7\n[ ] 캘린더 Week", work: ArisJobWork(tools: 0, failed: 0, acted: false), expected: .notDone(.planOnly)),
    VerdictRow(name: "VM: the typing failed", task: typed, answer: "하나를 입력하지 못했어요. 다른 컨트롤에 포커스가 있어요.",
               work: ArisJobWork(tools: 2, failed: 1, acted: false), expected: .notDone(.couldNot)),
    VerdictRow(name: "VM: a failed step claimed done", task: typed, answer: "입력해 뒀어요.", work: ArisJobWork(tools: 2, failed: 1, acted: false), expected: .notDone(.stepFailed)),
    VerdictRow(name: "VM: no tool call", task: typed, answer: "jobA.txt에 '하나'를 입력했어요.", work: ArisJobWork(tools: 0, failed: 0, acted: false), expected: .notDone(.noAction)),
    VerdictRow(name: "an English promise from an agent that doesn't count", task: "press 7 in Calculator",
               answer: "I'll press 7 in Calculator and let you know when it's done.", work: nil, expected: .notDone(.planOnly)),
]

private func jobfixVerdictTests() {
    for row in verdictTable {
        let got = V.judge(task: row.task, answer: row.answer, work: row.work)
        check(got == row.expected, "jobfix verdict: \(row.name) -> \(row.expected) (got \(got))")
    }
    check(!V.asksForAction(canvasTask), "jobfix verdict: the owner's request only asks to find and tell")
    // What the claim reader sees in the owner's list: no failure of its own, result lines.
    let read = ArisJobSaid.read(task: canvasTask, answer: canvasList)
    check(read.failures.isEmpty && read.results >= 4, "jobfix claim: the list's negatives are its subject (\(read.failures))")
    check(ArisJobSaid.saysItCouldNot("Canvas에 접속하지 못했어요.") && ArisJobSaid.saysItCouldNot("로그인이 안 됐어요.")
          && ArisJobSaid.saysItCouldNot("Couldn't load the planner page.") && !ArisJobSaid.saysItCouldNot("아직 제출하지 않았어요.")
          && !ArisJobSaid.saysItCouldNot("The compiler couldn't find module Foo.") && !ArisJobSaid.saysItCouldNot("테스트 2개가 실패했어요."),
          "jobfix claim: the job's own couldn't, not a negative about what it found")
    check(ArisJobSaid.negatedStems(in: "안 읽은 메일 정리해 줘") == ["읽"] && ArisJobSaid.negatedStems(in: canvasTask).isEmpty,
          "jobfix claim: a stem the task negates is the subject")
    // Retries are as before: a "couldn't" after real work is reported as it is.
    check(!V.retries(.couldNot, work: asideWork) && V.retries(.couldNot, work: nil), "jobfix verdict: retries unchanged")
}

private func jobfixWorkTests() {
    // Aside's outcome goes from the agent to the app with the job's count; an older line without it reads as nil.
    let work = ArisJobWork(tools: 1, failed: 0, acted: true, delegated: true)
    let line = String(decoding: ArisAgentReply.work(work).line, as: UTF8.self)
    check(ArisAgentReply.parse(line) == .work(work) && line.contains("\"delegated\":true"), "jobfix work: Aside's outcome reaches the app")
    check(ArisAgentReply.parse(#"{"work":{"tools":2,"failed":0,"acted":true}}"#) == .work(ArisJobWork(tools: 2, failed: 0, acted: true)),
          "jobfix work: a line without it is read as before")
}

private func jobfixShownTests() {
    // A job really not done keeps its answer readable: the tray row and its reader say why, then the answer; the card
    // has 보기 beside 다시 시도.
    let reason = V.reason(.couldNot, korean: true)
    check(V.shownNotDone(reason: reason, answer: "Canvas에 로그인할 수 없었어요.") == reason + "\n\nCanvas에 로그인할 수 없었어요."
          && V.shownNotDone(reason: reason, answer: "") == reason, "jobfix shown: the row keeps the answer after why")
    let id = UUID()
    let card = ArisNoticeRoute.jobNotDone(title: "Canvas 과제", shown: reason + " 답", job: id, english: false, answered: true)
    check(card.kind == .problem && card.actions.map(\.role) == [.retryJob(id), .openJob(id)] && card.actions.first?.primary == true,
          "jobfix shown: a not-done card with an answer has 다시 시도 and 보기")
    check(ArisNoticeRoute.jobNotDone(title: "x", shown: "y", job: id, english: false).actions.map(\.role) == [.retryJob(id)],
          "jobfix shown: one with nothing said has only 다시 시도")
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    let team = (try? String(contentsOf: root.appendingPathComponent("Aris/private/Aris/ArisController+Team.swift"), encoding: .utf8)) ?? ""
    check(team.contains(".failed(ArisJobVerdict.shownNotDone(reason: reason, answer: report.shown))")
          && team.contains("answered: !report.shown.isEmpty") && team.contains("ArisJobVerdict.reason(why, korean: !english)"),
          "jobfix shown: reportNotDone keeps the answer, and its own words follow the UI language")
}

// MARK: - B: the route

private let composioRow = ArisServiceReach.ConnectedRow(name: "composio", enabled: true, composio: true,
                                                        tools: ["COMPOSIO_SEARCH_TOOLS", "COMPOSIO_MULTI_EXECUTE_TOOL"])

private func jobfixReachTests() {
    let request = "Canvas 확인해서 과제 정리해 줘"
    let own = ArisServiceReach.make(canvasSetUp: true, connected: [])
    check(own.reaching(request).map(\.name) == ["canvas"] && own.reaching(request).first?.route == .own, "jobfix reach: Aris's own Canvas tool")
    let composio = ArisServiceReach.make(canvasSetUp: false, connected: [composioRow])
    check(composio.reaching(request).map(\.name) == ["composio"] && composio.reaching(request).first?.route == .connected,
          "jobfix reach: Composio, which has a Canvas toolkit")
    let both = ArisServiceReach.make(canvasSetUp: true, connected: [composioRow])
    check(both.reaching(request).map(\.name) == ["canvas", "composio"], "jobfix reach: own tool first, then the connected service")
    check(ArisServiceReach.make(canvasSetUp: false, connected: []).reaching(request).isEmpty, "jobfix reach: neither: the browser agent")
    let off = ArisServiceReach.ConnectedRow(name: "composio", enabled: false, composio: true, tools: nil)
    check(ArisServiceReach.make(canvasSetUp: false, connected: [off]).reaching(request).isEmpty, "jobfix reach: a service turned off doesn't count")
    check(composio.reaching("쿠팡에서 이어폰 찾아서 장바구니에 넣어줘").isEmpty, "jobfix reach: a site no service covers stays the browser agent's")
    let mine = ArisServiceReach.make(canvasSetUp: false, connected: [ArisServiceReach.ConnectedRow(name: "school-lms", enabled: true, composio: false,
                                                                                                  tools: ["canvas_list_assignments", "get_course"])])
    check(mine.reaching("check Canvas for my assignments").map(\.name) == ["school-lms"], "jobfix reach: the user's own server by its tools' names")
    check(!ArisServiceReach.names("canvas", in: "draw on html canvases") && ArisServiceReach.names("캔버스", in: "캔버스에서 공지 확인"),
          "jobfix reach: a Latin name as a word of its own, a Korean one with its particle")
    let line = ArisServiceReach.contextLine(both.reaching(request)) ?? ""
    check(line.contains("`canvas`") && line.contains("composio") && line.contains("Aside (the browser agent) only if")
          && ArisServiceReach.contextLine([]) == nil, "jobfix reach: the brain is told the order, Aside last")

    // The routing decision itself: the router said website work.
    let heard = ArisTurnRequest.Heard.make(heard: request, gesture: nil, handOff: nil, moment: .init())
    let routed = { (reach: ArisServiceReach) in ArisTurnRequest.Routed(intent: nil, tier: .work, browserWork: true, reach: reach) }
    let viaOwn = ArisTurnRequest.Reading.make(heard, routed: routed(own))
    check(!viaOwn.browserWork && viaOwn.reached.map(\.name) == ["canvas"], "jobfix route: own Canvas tool set up: not the browser agent")
    let viaComposio = ArisTurnRequest.Reading.make(heard, routed: routed(composio))
    check(!viaComposio.browserWork && viaComposio.reached.map(\.name) == ["composio"], "jobfix route: Composio connected: not the browser agent")
    let viaBrowser = ArisTurnRequest.Reading.make(heard, routed: routed(.none))
    check(viaBrowser.browserWork && viaBrowser.reached.isEmpty, "jobfix route: neither: the browser agent, as before")
    let notWebsite = ArisTurnRequest.Reading.make(heard, routed: ArisTurnRequest.Routed(intent: nil, tier: .work, browserWork: false, reach: own))
    check(!notWebsite.browserWork && notWebsite.reached.isEmpty, "jobfix route: a request the router didn't call website work is untouched")
}

/// The funnel with a router that says website work, and what Aris reaches.
@MainActor
private final class JobfixHost: ArisTurnHost {
    let reach: ArisServiceReach
    init(_ reach: ArisServiceReach) { self.reach = reach }
    func hear(_ request: ArisTurnRequest) async -> ArisTurnRequest.Heard {
        .make(heard: request.said, gesture: nil, handOff: nil, moment: .init())
    }
    func routed(_ words: String) async -> ArisTurnRequest.Routed { ArisTurnRequest.Routed(intent: nil, tier: .work, browserWork: true, reach: reach) }
    func teammateRemoval(_ words: String) async -> ArisTeamRemoval? { nil }
    func teammateCalled(_ words: String) async -> ArisJobSpec? { nil }
    func finishable(_ item: String) async -> ArisTodoFinishable? { nil }
    func application(_ name: String) -> URL? { nil }
    func run(_ claim: ArisTurnClaim, _ request: ArisTurnRequest) async -> String? { claim.branch }
}

private final class JobfixFlag: @unchecked Sendable { var done = false }

private func jobfixFunnelTests() {
    let flag = JobfixFlag()
    Task { @MainActor in
        let said = "Canvas 확인해서 과제 정리해 줘"
        let branch = { (reach: ArisServiceReach) async -> String in
            await ArisTurnFunnel.claim(ArisTurnRequest(said: said, origin: .key, context: .init()), host: JobfixHost(reach))?.claim.branch ?? "none"
        }
        check(await branch(ArisServiceReach.make(canvasSetUp: true, connected: [])) == "brain", "jobfix funnel: own Canvas tool: the brain takes it")
        check(await branch(ArisServiceReach.make(canvasSetUp: false, connected: [composioRow])) == "brain", "jobfix funnel: Composio: the brain takes it")
        check(await branch(.none) == "background", "jobfix funnel: neither: a background job for Aside")
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private func jobfixHelperTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    // Brains are told the order wherever Aside is described, and the browser job's own note says it.
    let before = ArisAgentPrompt.canvasSetUp
    ArisAgentPrompt.canvasSetUp = { true }
    let withCanvas = ArisAgentPrompt.asideRule("/x/aris-tools", form: .shell)
    ArisAgentPrompt.canvasSetUp = { false }
    let without = ArisAgentPrompt.serviceOrder
    ArisAgentPrompt.canvasSetUp = before
    check(withCanvas.contains("`canvas` for Canvas") && withCanvas.contains("`mcp list`") && withCanvas.contains("Aside only when neither")
          && !without.contains("canvas"), "jobfix prompt: own tool, then a connected service, Aside last (Canvas named only when set up)")
    check(source("ArisAgent/main.swift").contains("unless Aris reaches the site another way: \" + ArisAgentPrompt.serviceOrder"),
          "jobfix prompt: a browser job's note gives the same order")
    check(source("ArisAgent/ArisMCPRoutes.swift").contains("\"ownTools\": ArisAgentPrompt.canvasSetUp() ? [\"canvas\"] : []"),
          "jobfix reach: the agent's list says which of Aris's own tools are set up")
    // A service saved seconds before a request counts for it: every change in 연결된 서비스 forgets the router's list.
    let client = source("Aris/private/Aris/ArisAgentClient+MCP.swift")
    check(client.components(separatedBy: "ArisReachableServices.shared.forget()").count - 1 == 5, "jobfix reach: every change forgets the list")
    let funnel = source("Aris/private/Aris/Routing/ArisController+Funnel.swift")
    check(funnel.contains("async let reach = ArisReachableServices.shared.current()") && funnel.contains("reach: await reach"),
          "jobfix reach: the router's answer comes with what is reachable now")
    // Whoever answers the router (Jev, an API profile: jv-router), its website-work answer goes through the same step:
    // the reach is added after routeNow, never as a question of the router's own.
    let controller = source("Aris/private/Aris/ArisController.swift")
    check(controller.contains("ArisRouterModels.ask(text, apps: apps, profile: profile)") && controller.contains("return (decided, answers.tier, answers.browserWork)")
          && funnel.contains("let routed = await route(words)") && !source("Aris/private/Aris/ArisRouter.swift").contains("ArisServiceReach"),
          "jobfix reach: the step after the router holds for Jev and for an API router alike")

    // Aside's run tells the turn how it ended.
    final class Log { var runs = 0 }
    let log = Log()
    let deps = { (status: Int32, stdout: String) in
        ArisAsideDeps(locate: { .ready("/x/aside") },
                      run: { _, _, _, _ in log.runs += 1; return ArisSkillProcessResult(status: status, stdout: stdout, stderr: "no host", timedOut: false) },
                      open: { _ in true }, environment: ["HOME": "/Users/p"], verify: { _ in true })
    }
    let answered = FakeAsideTurn(brain: "claude")
    _ = ArisAsideTool.answer("쿠팡에서 에어팟 프로 최저가 찾아줘", turn: answered, critical: false, deps: deps(0, "MAT237 Problem Set 8, Nov 20"))
    let failed = FakeAsideTurn(brain: "claude")
    _ = ArisAsideTool.answer("쿠팡에서 에어팟 프로 최저가 찾아줘", turn: failed, critical: false, deps: deps(1, ""))
    check(log.runs == 2 && answered.finished == [true] && failed.finished == [false], "jobfix work: Aside's run says whether it answered")
}

private func jobfixCanvasTests() {
    let host = "q.exampleu.edu"
    check(ArisCanvas.problem(noAnswer: .timedOut, host: host).contains("within 15 seconds")
          && ArisCanvas.problem(noAnswer: .notConnectedToInternet, host: host).contains("no network")
          && ArisCanvas.problem(noAnswer: .cannotFindHost, host: host).contains("wasn't found")
          && ArisCanvas.problem(noAnswer: .secureConnectionFailed, host: host).contains("secure connection")
          && ArisCanvas.problem(noAnswer: nil, host: host) == "Canvas didn't answer",
          "jobfix canvas: no answer says why")
    check(ArisCanvas.retries(.networkConnectionLost, elapsed: 0.3) && !ArisCanvas.retries(.timedOut, elapsed: 0.3)
          && !ArisCanvas.retries(.networkConnectionLost, elapsed: 10) && !ArisCanvas.retries(nil, elapsed: 0.1),
          "jobfix canvas: only a quick network failure is tried again")
    let next = "<https://q.exampleu.edu/api/v1/planner/items?page=2&per_page=100>; rel=\"next\", <https://q.exampleu.edu/api/v1/planner/items?page=1>; rel=\"first\""
    check(ArisCanvas.nextPage(link: next, host: host)?.absoluteString == "https://q.exampleu.edu/api/v1/planner/items?page=2&per_page=100",
          "jobfix canvas: the planner's next page is read")
    check(ArisCanvas.nextPage(link: "<https://evil.example/api/v1/planner/items?page=2>; rel=\"next\"", host: host) == nil
          && ArisCanvas.nextPage(link: "<http://q.exampleu.edu/x>; rel=\"next\"", host: host) == nil
          && ArisCanvas.nextPage(link: "<https://q.exampleu.edu/x>; rel=\"prev\"", host: host) == nil
          && ArisCanvas.nextPage(link: nil, host: host) == nil,
          "jobfix canvas: the token never follows a link off the school's host or off https")
    check(ArisCanvas.allPagesWithin < 20 && ArisCanvas.requestTimeout <= ArisCanvas.allPagesWithin, "jobfix canvas: every page fits the callers' 20 s")
}

func runJobfixTests() {
    jobfixVerdictTests()
    jobfixWorkTests()
    jobfixShownTests()
    jobfixReachTests()
    jobfixFunnelTests()
    jobfixHelperTests()
    jobfixCanvasTests()
}
