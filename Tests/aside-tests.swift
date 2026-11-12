// Tests for Aside on every brain (ArisAside, ArisAsideTool, aris-tools aside): the brief's argv and line-break safety,
// the one gate's verdict for each brain's turn (the same rules as Codex's old aris_aside path: acting, critical, outside
// text, the screen and hands-free ask; a lookup on a clean turn runs), the outside text Aside's answer brings in, the
// audit lines, the missing-Aside card (설치 opens the official download page, nothing is installed), and how each
// brain's gate lets `aside` through to the agent. Aside itself never runs: the runner and the opener are fakes.
import Foundation

/// A turn for the Aside tool: the user's answers in order, what each card and audit line said, when the turn took in
/// outside text, and whether Aside was said to be running.
final class FakeAsideTurn: ArisAsideTurn {
    let brainName: String
    var taint: ArisTaint
    var handsFree: Bool
    var isTask = false
    var screen: Bool
    var relayed = false
    var answers: [ArisMCPAnswer]
    var cards: [ArisMCPCard] = []
    var audits: [[String: String]] = []
    var outsideTaken = 0
    var running = 0
    var ended = 0
    var statuses: [String] = []
    /// The taint when Aside started (it must already be outside text: its answer is the web's).
    var taintAtRun: ArisTaint?
    let asideTurnKey: String
    var asideLive = true
    /// The turn's own request is about Aris's own data (QA BUG-60).
    var asideOwnData = false

    init(brain: String, taint: ArisTaint = .none, handsFree: Bool = false, screen: Bool = false, answers: [ArisMCPAnswer] = []) {
        brainName = brain
        self.taint = taint
        self.handsFree = handsFree
        self.screen = screen
        self.answers = answers
        asideTurnKey = "fake-" + UUID().uuidString
    }

    func takeOutsideText() { outsideTaken += 1; taint = .outsideText }
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) {
        cards.append(card)
        answer(answers.isEmpty ? .no : answers.removeFirst())
    }
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.blocked(.undecided)) }
    func quiet(_ status: String) {}
    func audit(_ fields: [String: String]) { audits.append(fields) }
    func asideRunning(_ brief: String) { running += 1; taintAtRun = taint; statuses.append(ArisAside.runningStatus(brief)) }
    func asideWaiting(_ status: String) { statuses.append(status) }
    func asideEnded() { ended += 1 }
}

/// What the fake Aside was run with.
final class AsideRunLog {
    var runs: [(path: String, arguments: [String], environment: [String: String])] = []
    var opened: [URL] = []
    var forgotten = 0
    var logins: [String] = []
}

private func deps(_ log: AsideRunLog, installed: Bool = true, found: ArisAside.Found? = nil, status: Int32 = 0, stdout: String = "가장 싼 건 12,900원이에요.",
                  stderr: String = "session ses_1", privateTexts: [String] = [], verified: Bool = true, during: @escaping () -> Void = {},
                  loginOutput: [String] = [], loginStatus: Int32 = 0, loginTimedOut: Bool = false, confirmed: Bool = true) -> ArisAsideDeps {
    ArisAsideDeps(locate: { found ?? (installed ? .ready("/x/aside") : .missing) },
                  run: { path, arguments, environment, _ in
                      log.runs.append((path, arguments, environment))
                      during()
                      return ArisSkillProcessResult(status: status, stdout: stdout, stderr: stderr, timedOut: false)
                  },
                  open: { url in log.opened.append(url); return true },
                  environment: ["HOME": "/Users/p", "PATH": "/usr/bin", "ARIS_MCP_TURN_FILE": "/tmp/t", "ARIS_SEALED": "1", "SECRET_TOKEN": "x"],
                  privateTexts: { privateTexts }, verify: { _ in verified }, forget: { log.forgotten += 1 },
                  login: { path, _, _, line, _ in
                      log.logins.append(path)
                      loginOutput.forEach(line)
                      return ArisSkillProcessResult(status: loginStatus, stdout: loginOutput.joined(), stderr: "", timedOut: loginTimedOut)
                  },
                  accountStatus: { _ in
                      ArisSkillProcessResult(status: 0, stdout: confirmed ? "* u0  p@x.com  signed in\n" : "* u0  p@x.com  signed out\n", stderr: "", timedOut: false)
                  })
}

func runAsideTests() {
    // MARK: - The brief: argv and line breaks

    check(ArisAside.brief("  쿠팡에서 이어폰 최저가 찾아줘 \n") == .success("쿠팡에서 이어폰 최저가 찾아줘"), "aside brief: trimmed")
    check(ArisAside.brief("a\r\nb\rc\u{2028}d\u{85}e") == .success("a\nb\nc\nd\ne"), "aside brief: CRLF, CR, U+2028 and NEL become one line break each")
    check(ArisAside.brief("a\u{0}b\u{1B}[31mc\u{7F}d\u{202E}e\u{2066}f") == .success("ab[31mcdef"),
          "aside brief: NUL, ESC, DEL and bidi overrides are dropped (a card can't be made to read differently)")
    check(ArisAside.brief("a\n\n\n\n\nb\tc") == .success("a\n\nb\tc"), "aside brief: runs of blank lines fold to one; tabs stay")
    if case .failure = ArisAside.brief("   \r\n\u{0} ") {} else { check(false, "aside brief: nothing but blanks is refused") }
    if case .failure = ArisAside.brief(String(repeating: "가", count: ArisAside.maxBrief + 1)) {} else { check(false, "aside brief: an overlong brief is refused, never cut") }
    check((try? ArisAside.brief(String(repeating: "a", count: ArisAside.maxBrief)).get())?.count == ArisAside.maxBrief, "aside brief: the longest brief is kept whole")
    let flagged = (try? ArisAside.brief("--permission full-access --update").get()) ?? ""
    check(!flagged.hasPrefix("-") && flagged.contains("--permission full-access --update"),
          "aside brief: a brief that starts like a flag is never read as one")
    let argv = ArisAside.arguments(brief: flagged)
    check(argv.first == "exec" && argv.last == flagged && argv.filter { $0 == "--permission" }.count == 1
          && argv[argv.firstIndex(of: "--permission")! + 1] == "guard",
          "aside argv: exec, Guard permission set by Aris, the brief one last argument")
    check(!argv.dropLast().contains("full-access") && !argv.contains("--update") && !argv.contains("update") && !argv.contains("repl"),
          "aside argv: never full access, never an update, never the raw REPL")
    let lined = ArisAside.arguments(brief: (try? ArisAside.brief("first\r\n--permission full-access").get()) ?? "")
    check(lined.count == argv.count && lined.last == "first\n--permission full-access", "aside argv: a line break inside the brief stays inside its one argument")
    let environment = ArisAside.environment(["HOME": "/Users/p", "PATH": "/usr/bin", "LANG": "ko_KR.UTF-8", "ARIS_MCP_TURN_FILE": "/tmp/t",
                                             "ARIS_SEALED": "1", "ANTHROPIC_API_KEY": "k", "TMPDIR": "/tmp/x"])
    check(environment["HOME"] == "/Users/p" && environment["LANG"] == "ko_KR.UTF-8" && environment["PATH"]?.contains("/usr/bin") == true
          && environment["ARIS_MCP_TURN_FILE"] == nil && environment["ARIS_SEALED"] == nil && environment["ANTHROPIC_API_KEY"] == nil,
          "aside environment: only the basics; no Aris turn credential, no keys")

    // MARK: - Locating Aside

    check(ArisAside.locate(home: "/Users/p", isExecutable: { $0 == "/Users/p/.local/bin/aside" }, signed: { _ in true }) == .ready("/Users/p/.local/bin/aside"),
          "aside locate: the CLI in ~/.local/bin")
    check(ArisAside.locate(home: "/Users/p", isExecutable: { $0 == "/opt/homebrew/bin/aside" }, signed: { _ in true }) == .ready("/opt/homebrew/bin/aside"),
          "aside locate: Homebrew's CLI")
    check(ArisAside.locate(home: "/Users/p", isExecutable: { _ in false }, signed: { _ in true }) == .missing, "aside locate: no CLI is missing")
    check(ArisAside.hasLocalHost(home: "/Users/p", exists: { $0 == "/Applications/Aside.app" }, signed: { _ in true })
          && !ArisAside.hasLocalHost(home: "/Users/p", exists: { _ in true }, signed: { _ in false })
          && !ArisAside.hasLocalHost(home: "/Users/p", exists: { _ in false }, signed: { _ in true }),
          "aside host: local only when Aside.app is there and signed by Aside's team (else remote or cloud may serve)")
    check(ArisAside.locate(home: "/Users/p", isExecutable: { $0 == "/Users/p/.local/bin/aside" }, signed: { _ in false }) == .untrusted("/Users/p/.local/bin/aside"),
          "aside locate (L9): a CLI not signed by Aside's team is never ready")
    check(!ArisAside.isSignedByAside("/bin/ls") && !ArisAside.isSignedByAside("/nonexistent/aside"),
          "aside locate (L9): Apple's own or a missing binary isn't Aside's (team \(ArisAside.teamID))")
    let unsignedLog = AsideRunLog()
    let unsigned = ArisAsideTool.answer("가격 찾아줘", turn: FakeAsideTurn(brain: "Claude"), critical: false, deps: deps(unsignedLog, found: .untrusted("/Users/p/.local/bin/aside")))
    check(unsigned.status == 1 && unsigned.output == ArisAside.untrustedLine && unsignedLog.runs.isEmpty, "aside (L9): an unsigned CLI is refused, nothing runs")

    // MARK: - The one gate, the same on every brain

    let brains = ["Codex", "Claude", "API", "Antigravity"]
    for brain in brains {
        // A lookup on a clean turn runs at once, its answer outside text from then on.
        let log = AsideRunLog()
        let clean = FakeAsideTurn(brain: brain)
        let found = ArisAsideTool.answer("쿠팡에서 에어팟 프로 최저가 찾아줘", turn: clean, critical: false, deps: deps(log))
        check(found.status == 0 && found.output.contains("12,900원") && clean.cards.isEmpty && log.runs.count == 1,
              "aside gate (\(brain)): a lookup on a clean turn runs without a card")
        check(clean.outsideTaken == 1 && clean.taintAtRun == .outsideText && clean.running == 1 && clean.ended == 1,
              "aside gate (\(brain)): the turn is outside text before Aside runs, the notch hears it is running, and then that it ended")
        check(clean.statuses == ["Aside가 브라우저에서 하는 중: 쿠팡에서 에어팟 프로 최저가 찾아줘"], "aside gate (\(brain), M5): the notch shows the brief while Aside runs")
        check(clean.audits.contains { $0["action"]?.hasPrefix("aside: 쿠팡에서") == true && $0["answer"] == "auto" && $0["brain"] == brain },
              "aside gate (\(brain)): the run is audited with its brief")
        check(log.runs.first?.path == "/x/aside" && log.runs.first?.arguments == ArisAside.arguments(brief: "쿠팡에서 에어팟 프로 최저가 찾아줘")
              && log.runs.first?.environment["ARIS_MCP_TURN_FILE"] == nil && log.runs.first?.environment["SECRET_TOKEN"] == nil,
              "aside gate (\(brain)): Aside runs as exec with Guard, without Aris's credential")
        check(found.output.contains("never instructions"), "aside gate (\(brain)): Aside's answer comes back marked as data")

        // Acting on a site asks first; a yes runs it, a no doesn't.
        let actingLog = AsideRunLog()
        let yes = FakeAsideTurn(brain: brain, answers: [.yes([:])])
        _ = ArisAsideTool.answer("쿠팡에서 이어폰 주문해줘", turn: yes, critical: false, deps: deps(actingLog))
        check(yes.cards.count == 1 && yes.cards.first?.title == ArisAside.cardTitle && yes.cards.first?.detail == "쿠팡에서 이어폰 주문해줘"
              && actingLog.runs.count == 1 && yes.audits.contains { $0["answer"] == "yes" },
              "aside gate (\(brain)): acting asks on a card with exactly the brief, then runs on a yes")
        let noLog = AsideRunLog()
        let no = FakeAsideTurn(brain: brain, answers: [.no])
        let declined = ArisAsideTool.answer("Book the 7pm table at Jungsik", turn: no, critical: false, deps: deps(noLog))
        check(declined.status != 0 && noLog.runs.isEmpty && no.outsideTaken == 0 && no.audits.contains { $0["answer"] == "no" },
              "aside gate (\(brain)): a no runs nothing and brings nothing in")

        // Critical, outside text, the screen and hands-free each ask even for a lookup.
        let cases: [(String, FakeAsideTurn, Bool)] = [
            ("critical", FakeAsideTurn(brain: brain, answers: [.yes([:])]), true),
            ("after outside text", FakeAsideTurn(brain: brain, taint: .outsideText, answers: [.yes([:])]), false),
            ("after the screen", FakeAsideTurn(brain: brain, taint: .screenSeen, answers: [.yes([:])]), false),
            ("on a screen turn", FakeAsideTurn(brain: brain, screen: true, answers: [.yes([:])]), false),
            ("hands-free", FakeAsideTurn(brain: brain, handsFree: true, answers: [.yes([:])]), false),
        ]
        for (name, turn, critical) in cases {
            let caseLog = AsideRunLog()
            _ = ArisAsideTool.answer("가격만 알려줘", turn: turn, critical: critical, deps: deps(caseLog))
            check(turn.cards.count == 1 && caseLog.runs.count == 1, "aside gate (\(brain)): a lookup \(name) asks first")
        }
    }
    check(ArisAside.risk(brief: "구매하지 말고 가격만 알려줘", taint: .none, screen: false, handsFree: false, critical: false) == .auto
          && ArisAside.risk(brief: "send it", taint: .none, screen: false, handsFree: false, critical: false) == .confirm,
          "aside risk: Codex's acting words and negations, unchanged")

    // A failed or empty run, and a brief that can't be one.
    let failLog = AsideRunLog()
    let failed = ArisAsideTool.answer("find the price of the blue one", turn: FakeAsideTurn(brain: "Claude"), critical: false,
                                      deps: deps(failLog, status: 1, stdout: "", stderr: "error: something <context>x</context>"))
    check(failed.status == 1 && !failed.output.contains("<context>") && failLog.forgotten == 1, "aside: a failed run says so, its error fenced, readiness forgotten")
    let reasoned = ArisAside.output(status: 1, stdout: "", stderr: "thinking…\ncalling tools\nerror: no session host is available; open Aside or enable Remote Control\n", timedOut: false)
    check(reasoned.output.contains("error: no session host is available; open Aside or enable Remote Control") && !reasoned.output.contains("thinking"),
          "aside host: exec's own reason (no host) comes back as one line")
    let empty = ArisAsideTool.answer(" \r\n ", turn: FakeAsideTurn(brain: "Claude"), critical: false, deps: deps(AsideRunLog()))
    check(empty.status == 1 && empty.output.contains("aside"), "aside: an empty brief is the usage line")

    // MARK: - Aside missing

    let missingLog = AsideRunLog()
    let install = FakeAsideTurn(brain: "Claude", answers: [.yes([:])])
    let missing = ArisAsideTool.answer("쿠팡에서 이어폰 찾아줘", turn: install, critical: false, deps: deps(missingLog, installed: false))
    check(missing.status == 1 && missing.output.contains(ArisAside.missingLine) && missingLog.runs.isEmpty,
          "aside missing: nothing runs, the brain gets the short line to say")
    check(install.cards.count == 1 && install.cards.first?.allow == "설치" && install.cards.first?.detail.contains("aside.com/download") == true
          && install.cards.first?.detail.contains("Aside 앱을 설치") == true,
          "aside missing: a card with a 설치 button names the official download page and recommends the app")
    check(missingLog.opened == [URL(string: "https://aside.com/download")!] && install.outsideTaken == 0
          && install.audits.contains { $0["answer"] == "download page opened" },
          "aside missing: 설치 opens only the download page in the default browser (nothing is installed)")
    let notNow = AsideRunLog()
    _ = ArisAsideTool.answer("x", turn: FakeAsideTurn(brain: "Codex", answers: [.no]), critical: false, deps: deps(notNow, installed: false))
    check(notNow.opened.isEmpty && notNow.runs.isEmpty, "aside missing: 취소 opens nothing")
    check(ArisAside.missingLine.contains("Aside") && ArisAside.missingLine.contains("설치"), "aside missing: the line names Aside and its 설치 button")

    // The card's own button label reaches the app.
    let card = ArisMCPCards.shared.put(ArisMCPCard(title: "Aside 설치", detail: "d", full: nil, fields: [], allow: "설치"), timeout: 1) { _ in }
    check(card.allow == "설치", "aside missing: the card keeps its 설치 label")
    if case .confirm(let parsed)? = ArisAgentReply.parse(String(decoding: ArisAgentReply.confirm(card).line, as: UTF8.self)) {
        check(parsed.allow == "설치", "aside missing: the label survives the stream to the app")
    } else { check(false, "aside missing: the card parses back") }
    if case .confirm(let plain)? = ArisAgentReply.parse(String(decoding: ArisAgentReply.confirm(ArisConfirmation(id: "c", title: "t", detail: "d")).line, as: UTF8.self)) {
        check(plain.allow == nil, "aside missing: other cards keep 허용")
    }

    // MARK: - aris-tools aside, and every brain's gate letting it through to the agent

    let credential = FileManager.default.temporaryDirectory.appendingPathComponent("aris-aside-turn-\(UUID().uuidString.prefix(8))")
    try? "turn-123".write(to: credential, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: credential) }
    if case .success(let body) = asideRequest(["쿠팡에서", "이어폰 찾아줘"], environment: ["ARIS_MCP_TURN_FILE": credential.path]) {
        check(body["turn"] as? String == "turn-123" && body["brief"] as? String == "쿠팡에서 이어폰 찾아줘", "aris-tools aside: the words are the brief, with the turn's credential")
    } else { check(false, "aris-tools aside: a request is made") }
    if case .failure = asideRequest(["x"], environment: [:]) {} else { check(false, "aris-tools aside: only inside an Aris turn") }
    if case .failure = asideRequest([], environment: ["ARIS_MCP_TURN_FILE": credential.path]) {} else { check(false, "aris-tools aside: no brief is the usage line") }

    let tools = "/t"
    check(ArisRiskPolicy.risk(of: .shell(#"/t aside "쿠팡에서 이어폰 주문해줘""#), tools: tools, home: "/Users/p") == .auto
          && !ArisRiskPolicy.asksAfterOutsideText(.shell(#"/t aside "x""#), tools: tools)
          && !ArisHandsFree.asks(.shell(#"/t aside "x""#), tools: tools),
          "aside, Codex and the API brain: the shell gate hands it to the agent's one gate (asking twice otherwise)")
    check(ArisTurnGate.verdict(tool: "Bash", command: #"/t aside "주문해줘""#, tools: tools, tainted: true) == .allow
          && ArisTurnGate.verdict(tool: "Bash", command: #"/t aside "x""#, tools: tools, tainted: false) == .allow,
          "aside, the open Claude: the turn gate hands it to the agent, which knows what this conversation read")
    if case .deny = ArisTurnGate.verdict(tool: "Bash", command: #"/t aside "x" && /t link https://a.b"#, tools: tools, tainted: false) {} else {
        check(false, "aside, the open Claude: it runs alone")
    }
    check(!ArisClaudeDriver.bringsInOutside(ArisAgentStream.ToolCall(name: "Bash", command: #"/t aside "x""#), tools: tools),
          "aside, Claude: the agent marks the thread when Aside's answer comes, not the call")
    check(ArisSealedTools.allows(["aside", "쿠팡에서 이어폰 찾아줘"]) && !ArisSealedTools.allows(["aside"])
          && !ArisSealedTools.allows(["aside", "a\nb"]) && ArisSealedTools.permits(command: #"/t aside "쿠팡에서 찾아줘""#, tools: tools)
          && ArisSealedTools.allowRules(tools: tools).contains("Bash(/t aside:*)"),
          "aside, the sealed Claude: on its list, one line, its allow rule")
    check(ArisSealedTools.ungatedRefusal(environment: [ArisSealedTools.ungatedKey: "1"], arguments: ["aside", "쿠팡에서 찾아줘"]) == nil
          && ArisSealedTools.ungatedRefusal(environment: [ArisSealedTools.ungatedKey: "1"], arguments: ["aside", "a", "b"]) != nil
          && ArisSealedTools.ungatedRefusal(environment: [ArisSealedTools.ungatedKey: "1"], arguments: ["aside"]) != nil
          && ArisSealedTools.ungatedRefusal(environment: [ArisSealedTools.ungatedKey: "1"], arguments: ["mcp", "list"]) != nil,
          "aside, agy job: its ungated aris-tools lets exactly `aside \"<brief>\"` through to the agent's carded route, nothing else")
    let agyJobPrompt = ArisAgentPrompt.system(tools: tools, task: true, relay: true)
    check(agyJobPrompt.contains("`\(tools) aside \"<brief>\"`") && !agyJobPrompt.contains("aris-run block of one `aside"),
          "aside, agy job: its prompt hands websites to `aris-tools aside` (its conversation keeps the relay)")
    let agyLog = AsideRunLog()
    let agyJob = FakeAsideTurn(brain: "Antigravity", taint: .outsideText, answers: [.yes([:])])
    _ = ArisAsideTool.answer("이 노트북 최저가 찾아줘", turn: agyJob, critical: true, deps: deps(agyLog))
    check(agyJob.cards.count == 1 && agyLog.runs.count == 1, "aside, agy job: even a plain lookup shows a card (outside text, critical)")
    check(ArisAgyRelay.isAside(["aside", "x"]) && !ArisAgyRelay.isAside(["aside"]) && ArisAgyRelay.permitted(["aside", "x"], sealed: true)
          && ArisAgyRelay.permitted(["aside", "x"], sealed: false, handsFree: true) && ArisAgyRelay.mayRelay(round: 1, commands: [["aside", "x"]])
          && ArisAgyRelay.bringsInOutside([["aside", "x"]]),
          "aside, agy: the relay runs it (sealed or hands-free too), in a later round too, and its answer is outside text")
    let apiArgv = ArisAPICatalog.argv(name: "aside_task", arguments: #"{"brief":"쿠팡에서 이어폰 찾아줘"}"#)
    check(apiArgv == ["aside", "쿠팡에서 이어폰 찾아줘"] && ArisAPICatalog.names(sealed: true).contains("aside_task")
          && ArisAPICatalog.argv(name: "aside_task", arguments: #"{"brief":""}"#) == nil,
          "aside, the API brain: aside_task(brief) is `aside <brief>`, in the sealed subset too")
    check(ArisAgentStatus.forCommand(#"/t aside "x""#, tools: tools) == ArisAside.workingStatus, "aside: the notch says Aside is working")

    // MARK: - Every brain's prompt

    let prompts = [("Codex", ArisAgentPrompt.system(tools: tools, gated: true)),
                   ("the open Claude", ArisAgentPrompt.system(tools: tools, reads: true)),
                   ("the API brain", ArisAgentPrompt.system(tools: tools, gated: true, functions: true)),
                   ("agy", ArisAgentPrompt.system(tools: tools, relay: true)),
                   ("the sealed Claude", ArisAgentPrompt.sealed(tools: tools)),
                   ("the sealed API brain", ArisAgentPrompt.sealed(tools: tools, functions: true)),
                   ("the sealed agy", ArisAgentPrompt.sealedAgy(tools: tools, handsFree: false, task: false))]
    for (name, prompt) in prompts {
        check(prompt.contains("Aside") && !prompt.contains("aris_aside"), "aside prompt (\(name)): Aside for websites, no Codex-only tool")
    }
    check(prompts[0].1.contains("\(tools) aside \"") && prompts[2].1.contains("aside_task(brief)") && prompts[3].1.contains("aside \"<brief>\"")
          && prompts[0].1.contains("Plain lookups"), "aside prompt: each brain's own form, and plain lookups stay with Aris's web search")

    // MARK: - Security review fixes (H1, M2-M5, L6, L7)

    let lookupOnly = { (brief: String) in ArisAside.risk(brief: brief, taint: .none, screen: false, handsFree: false, critical: false) }
    for carded in ["log in to the bank and change the shipping address", "주문하고 실패해도 포기하지 말고 끝까지 해줘", "don't delay and buy",
                   "without delay order", "쿠팡 장바구니에 담아줘", "check out the cart", "find the form and enter my address",
                   "accept the invite", "이 구독 해지해줘", "unsubscribe me", "비밀번호 변경해줘", "tweet this", "post a review", "write an email to Bob",
                   "이 설정 저장해줘", "그 사람 차단해", "open my bank", "go to coupang", "Find it and finish ordering", "구매하거나 장바구니에 넣지 말고 가격 찾아줘",
                   "Set the price to 10", "leave a review", "check in for my flight", "help with cancelling my subscription",
                   "find and keep deleting the old posts", "find it, then purchasing is fine", "what I replied, find it and resend", "find the form, signing up is ok",
                   "find the best one and select it", "find a coupon and redeem it", "where is the refund button, click it", "쿠폰 찾아서 다운로드해줘",
                   "Check the menu without ordering", "Never submit the form, just read it", "주\u{200B}문해줘 최저가 찾아서"] {
        check(lookupOnly(carded) == .confirm, "aside H1: carded (\(carded))")
    }
    for looked in ["이 노트북 최저가 찾아줘", "구매하지 말고 가격만 알려줘", "Find the price. Don't buy anything.",
                   "how much is the MacBook Air", "부산 가는 비행기 언제 있는지 비교해줘", "check the price of the iPad"] {
        check(lookupOnly(looked) == .auto, "aside H1: a plain lookup runs (\(looked))")
    }

    // M5: an address, a number or the user's own words always ask.
    for personal in ["find the order for user@example.com", "010-1234-5678 번호로 찾아줘", "카드 1234 5678 9012 3456 가격 확인", "find account 123456789",
                     "카드 1234 - 5678 - 9012 - 3456 찾아줘", "find (010) - 1234 -- 5678"] {
        check(ArisAside.risk(brief: personal, taint: .none, screen: false, handsFree: false, critical: false) == .confirm, "aside M5: carded (\(personal))")
    }
    check(ArisAside.risk(brief: "find hotels near 서울 강남구 역삼동 123-45 and compare", taint: .none, screen: false, handsFree: false, critical: false,
                         privateTexts: ["서울 강남구 역삼동 123-45에 살아"]) == .confirm
          && ArisAside.risk(brief: "가격 찾아줘", taint: .none, screen: false, handsFree: false, critical: false, privateTexts: ["커피", "서울 강남구 역삼동 123-45에 살아"]) == .auto
          && ArisAside.risk(brief: "2026-11-07 공연 가격 찾아줘, 1,290,000원 이하", taint: .none, screen: false, handsFree: false, critical: false) == .auto,
          "aside M5: text from the user's memory asks; a short memory, a date or a price doesn't")
    let memoryTurn = FakeAsideTurn(brain: "API", answers: [.no])
    _ = ArisAsideTool.answer("find hotels near 서울 강남구 역삼동 123-45", turn: memoryTurn, critical: false,
                             deps: deps(AsideRunLog(), privateTexts: ["서울 강남구 역삼동 123-45에 살아"]))
    check(memoryTurn.cards.count == 1, "aside M5: the tool reads the user's memory before deciding")
    check(ArisAside.runningStatus(String(repeating: "가", count: 80) + "\nsecond").count <= ArisAside.workingStatus.count + 2 + 61,
          "aside M5: the status shows the brief's first line, cut short")
    check(ArisAside.runningStatus("짧은 줄\n둘째 줄").hasSuffix("짧은 줄…") && ArisAside.runningStatus(String(repeating: "a", count: 61)).hasSuffix("…")
          && ArisAside.runningStatus("가격 찾아줘").hasSuffix("가격 찾아줘"),
          "aside (8): the status ends with … whenever the brief was cut")

    // (6) Zero-width and format characters are gone before the gate and Aside see the brief.
    check(ArisAside.brief("주\u{200B}문\u{200C}해\u{200D}줘\u{2060}\u{FEFF}\u{00AD}") == .success("주문해줘"),
          "aside (6): zero-width and format characters are stripped from the brief")
    let hiddenLog = AsideRunLog()
    let hiddenTurn = FakeAsideTurn(brain: "Codex", answers: [.yes([:])])
    _ = ArisAsideTool.answer("최저가 찾아서 주\u{200B}문해줘", turn: hiddenTurn, critical: false, deps: deps(hiddenLog))
    check(hiddenTurn.cards.first?.detail == "최저가 찾아서 주문해줘" && hiddenLog.runs.first?.arguments.last == "최저가 찾아서 주문해줘",
          "aside (6): a hidden acting word is carded, and Aside gets the same brief the card showed")

    // (3) The signature again right before Aside runs, after the card.
    let swappedLog = AsideRunLog()
    let swapped = FakeAsideTurn(brain: "Claude", answers: [.yes([:])])
    let refused = ArisAsideTool.answer("쿠팡에서 주문해줘", turn: swapped, critical: false, deps: deps(swappedLog, verified: false))
    check(swapped.cards.count == 1 && swappedLog.runs.isEmpty && refused.output == ArisAside.untrustedLine && swapped.outsideTaken == 0,
          "aside (3): a CLI whose signature fails after the card never runs")
    check(ArisAside.isAsideIdentifier("at.studio.AsideBrowser.cli") && ArisAside.isAsideIdentifier("at.studio.AsideBrowser")
          && !ArisAside.isAsideIdentifier("at.studio.AsideBrowserEvil") && !ArisAside.isAsideIdentifier("com.evil.at.studio.AsideBrowser")
          && !ArisAside.isAsideIdentifier(nil) && ArisAside.teamID == "8CPD4K4TBB",
          "aside (L9): team 8CPD4K4TBB and an at.studio.AsideBrowser identifier, both pinned")

    // M4: one Aside call at a time in a turn.
    let busyTurn = FakeAsideTurn(brain: "Claude", answers: [.yes([:])])
    let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
    let busyLog = AsideRunLog()
    DispatchQueue.global().async {
        _ = ArisAsideTool.answer("가격 찾아줘", turn: busyTurn, critical: false, deps: deps(busyLog, during: { started.signal(); _ = release.wait(timeout: .now() + 5) }))
        finished.signal()
    }
    _ = started.wait(timeout: .now() + 5)
    let second = ArisAsideTool.answer("가격 찾아줘", turn: busyTurn, critical: false, deps: deps(AsideRunLog()))
    release.signal()
    _ = finished.wait(timeout: .now() + 5)
    check(second.status == 1 && second.output == ArisAside.busy, "aside M4: a second Aside call in the same turn is refused while one runs")
    check(ArisAsideTool.answer("가격 찾아줘", turn: busyTurn, critical: false, deps: deps(AsideRunLog())).status == 0, "aside M4: once it ended, the next one runs (on its card: the turn is outside text now)")
    check(ArisClaudeDriver(model: "m", tools: "/t").environment["BASH_DEFAULT_TIMEOUT_MS"] == "1800000"
          && ArisClaudeDriver(model: "m", tools: "/t", sealed: true).environment["BASH_DEFAULT_TIMEOUT_MS"] == "1800000",
          "aside M4: every Claude's commands may wait 30 minutes by default")

    // M2: the API brain's helper waits for Aside once a turn, never shorter than it already would.
    let now = Date()
    check(ArisAPIHelper.asideDeadline(existing: now.addingTimeInterval(60), now: now, extended: false) == now.addingTimeInterval(ArisAPIHelper.asideExtension)
          && ArisAPIHelper.asideDeadline(existing: now.addingTimeInterval(5_000), now: now, extended: false) == now.addingTimeInterval(5_000)
          && ArisAPIHelper.asideDeadline(existing: now, now: now, extended: true) == nil,
          "aside M2: max(existing, now + extension), once per turn")
    let apiDriver = ArisAPIDriver(profile: nil, tools: "/t")
    check(apiDriver.asideStarted().count == 1 && String(decoding: apiDriver.asideStarted()[0], as: UTF8.self).contains(#""type":"aside""#)
          && ArisClaudeDriver(model: "m", tools: "/t").asideStarted().isEmpty,
          "aside M2: the agent tells the API helper only when Aside starts (after its gate)")

    // L6: only 설치 may name a card's yes button.
    check(ArisConfirmation(id: "c", title: "t", detail: "d", allow: "결제").allow == nil && ArisConfirmation(id: "c", title: "t", detail: "d", allow: "설치").allow == "설치",
          "aside L6: the card label is allowlisted")
    if case .confirm(let spoofed)? = ArisAgentReply.parse(#"{"confirm":{"id":"c","title":"t","detail":"d","allow":"확인"}}"#) {
        check(spoofed.allow == nil, "aside L6: a label off the list from the stream is ignored")
    } else { check(false, "aside L6: the card parses") }

    // L7: one install card a turn, none after outside text, the screen or hands-free.
    let once = FakeAsideTurn(brain: "Codex", answers: [.no, .no])
    _ = ArisAsideTool.answer("x", turn: once, critical: false, deps: deps(AsideRunLog(), installed: false))
    let again = ArisAsideTool.answer("y", turn: once, critical: false, deps: deps(AsideRunLog(), installed: false))
    check(once.cards.count == 1 && again.output.contains(ArisAside.missingLine), "aside L7: at most one install card a turn, the line every time")
    for (name, turn) in [("outside text", FakeAsideTurn(brain: "Claude", taint: .outsideText, answers: [.yes([:])])),
                         ("the screen", FakeAsideTurn(brain: "Claude", screen: true, answers: [.yes([:])])),
                         ("hands-free", FakeAsideTurn(brain: "Claude", handsFree: true, answers: [.yes([:])]))] {
        let log = AsideRunLog()
        let said = ArisAsideTool.answer("x", turn: turn, critical: false, deps: deps(log, installed: false))
        check(turn.cards.isEmpty && log.opened.isEmpty && said.output.contains(ArisAside.missingLine), "aside L7: no install card after \(name)")
    }

    // MARK: - Readiness and guided sign-in (the owner, 2026-11-08)

    let probeText = "* u0  user@example.com  signed in  profiles: Profile 0, Profile 1\n    provider: google\n"
    check(ArisAside.signedIn(accountStatus: probeText) && !ArisAside.signedIn(accountStatus: "* u0  p@x.com  signed out\n")
          && !ArisAside.signedIn(accountStatus: "  u1  a@x.com  signed in\n* u0  p@x.com  not signed in\n") && !ArisAside.signedIn(accountStatus: ""),
          "aside ready: the active (*) account must read \"signed in\"; anything else isn't")
    check(ArisAside.accountStatusArguments == ["account", "status"] && !ArisAside.accountStatusArguments.contains { $0.hasPrefix("-") },
          "aside ready: the one readiness command, plain text, no flag (never --json, never a host command)")
    let ok = ArisSkillProcessResult(status: 0, stdout: probeText, stderr: "", timedOut: false)
    check(ArisAsideReadiness.probe(.ready("/x/aside"), account: { _ in ok }) == .ready("/x/aside")
          && ArisAsideReadiness.probe(.ready("/x/aside"), account: { _ in ArisSkillProcessResult(status: 0, stdout: "* u0 x signed out", stderr: "", timedOut: false) }) == .signedOut("/x/aside")
          && ArisAsideReadiness.probe(.ready("/x/aside"), account: { _ in ArisSkillProcessResult(status: 1, stdout: probeText, stderr: "", timedOut: false) }) == .signedOut("/x/aside")
          && ArisAsideReadiness.probe(.missing, account: { _ in ok }) == .missing,
          "aside ready: signed CLI, then signed in; a failed status check counts as signed out")
    check(ArisAside.readinessTTL == 600, "aside ready: cached for 10 minutes")

    for (output, code) in [("Open Aside › Settings › Account › Devices and confirm this code:\n\n    WDJB-MJHT\n\nWaiting for approval…", "WDJB-MJHT"),
                           ("Your device code is 482-913. It expires in 10 minutes.", "482-913"),
                           ("Code: ab12cd\nhttps://aside.com/device", "AB12CD"),
                           ("Confirm the code in Settings > Account > Devices.\nK7Q2-9XZD", "K7Q2-9XZD")] {
        check(ArisAside.deviceCode(in: output) == code, "aside sign-in: the code is read from \(output.prefix(24))…")
    }
    check(ArisAside.deviceCode(in: "Sign the CLI in by confirming a code in Settings > Account > Devices") == nil
          && ArisAside.deviceCode(in: "Waiting for approval…") == nil,
          "aside sign-in: no code is made up from other words")
    check(ArisAside.loginArguments == ["login", "--device-code"] && !ArisAside.loginArguments.contains("--password"),
          "aside sign-in: device approval only, never a password")
    let loginLog = AsideRunLog()
    let loginTurn = FakeAsideTurn(brain: "Claude", answers: [.yes([:])])
    let signedIn = ArisAsideTool.answer("가격 찾아줘", turn: loginTurn, critical: false,
                                        deps: deps(loginLog, found: .signedOut("/x/aside"), loginOutput: ["Confirm this code:\n", "  WDJB-MJHT\n", "Waiting…\n"]))
    check(loginTurn.cards.first?.title == "Aside 로그인" && loginTurn.cards.first?.allow == "로그인" && loginLog.logins == ["/x/aside"]
          && loginTurn.statuses.contains(ArisAside.loginStatus("WDJB-MJHT")) && loginTurn.ended == 1,
          "aside sign-in: a 로그인 card, then the code in the notch with where to approve it")
    check(signedIn.status == 0 && signedIn.output.contains("로그인했어요") && loginLog.runs.isEmpty && loginLog.forgotten == 1
          && ArisAside.loginStatus("X").contains("Aside 설정 > Account > Devices에서 이 코드를 승인해 주세요"),
          "aside sign-in: approved, Aris says so and readiness is checked again; no task ran")
    let expiredLog = AsideRunLog()
    let expired = ArisAsideTool.answer("가격 찾아줘", turn: FakeAsideTurn(brain: "Codex", answers: [.yes([:])]), critical: false,
                                       deps: deps(expiredLog, found: .signedOut("/x/aside"), loginOutput: ["code: 482-913\n"], loginStatus: -1, loginTimedOut: true))
    check(expired.status == 1 && expired.output.contains("만료"), "aside sign-in: an unapproved code expires and Aris says so")
    let declinedLog = AsideRunLog()
    let declinedLogin = ArisAsideTool.answer("가격 찾아줘", turn: FakeAsideTurn(brain: "Codex", answers: [.no]), critical: false,
                                             deps: deps(declinedLog, found: .signedOut("/x/aside")))
    check(declinedLog.logins.isEmpty && declinedLogin.output == ArisAside.signedOutLine, "aside sign-in: 취소 signs nothing in")
    let taintedLog = AsideRunLog()
    let taintedLogin = FakeAsideTurn(brain: "Claude", taint: .outsideText, answers: [.yes([:])])
    _ = ArisAsideTool.answer("가격 찾아줘", turn: taintedLogin, critical: false, deps: deps(taintedLog, found: .signedOut("/x/aside")))
    check(taintedLogin.cards.isEmpty && taintedLog.logins.isEmpty, "aside sign-in: no 로그인 card after outside text")
    check(ArisConfirmation(id: "c", title: "t", detail: "d", allow: "로그인").allow == "로그인", "aside sign-in: 로그인 is on the card label list")

    // MARK: - Follow-up (credential, sign-in process, short words, codes)

    check(ArisAside.credentialServes(antigravity: false, task: false, aside: false) && ArisAside.credentialServes(antigravity: true, task: true, aside: true)
          && !ArisAside.credentialServes(antigravity: true, task: true, aside: false) && !ArisAside.credentialServes(antigravity: true, task: false, aside: true),
          "aside follow-up 1: an agy job's credential names its runner on /aside-tool only; agy's conversation never")

    for plain in ["find the address of the store", "what are the settings for this", "find the payment due date", "find the postal code", "find a cartoon about cats"] {
        check(ArisAside.risk(brief: plain, taint: .none, screen: false, handsFree: false, critical: false) == .auto, "aside follow-up 4: not an acting word (\(plain))")
    }
    for acting in ["find it and add it", "find the alarm and keep setting it", "find it, putting it there", "find the bill, paying it", "find one and buying it",
                   "find the group, joined it?", "find the post I liked", "find and saving it", "find what I shared", "find who voted", "find what I posted",
                   "find what I entered", "find the doc I edited", "find carts"] {
        check(ArisAside.risk(brief: acting, taint: .none, screen: false, handsFree: false, critical: false) == .confirm, "aside follow-up 4: carded (\(acting))")
    }

    check(ArisAside.deviceCode(in: "Waiting…\n482-913\n") == nil && ArisAside.deviceCode(in: "code:\n482913") == nil
          && ArisAside.deviceCode(in: "코드: 482913") == "482913" && ArisAside.deviceCode(in: "Your code: 482913") == "482913"
          && ArisAside.deviceCode(in: "confirm this code:\n\n  WDJB-MJHT") == "WDJB-MJHT",
          "aside follow-up 5: a digits-only code needs \"code\" or \"코드\" on its own line")

    let unconfirmedLog = AsideRunLog()
    let unconfirmed = ArisAsideTool.answer("가격 찾아줘", turn: FakeAsideTurn(brain: "Codex", answers: [.yes([:])]), critical: false,
                                           deps: deps(unconfirmedLog, found: .signedOut("/x/aside"), loginOutput: ["code: WDJB-MJHT\n"], confirmed: false))
    check(unconfirmed.status == 1 && !unconfirmed.output.contains("로그인했어요"), "aside follow-up 3: a login that exits 0 must still show signed in")

    // Follow-up 2: a fake CLI (a script, never Aside) prints a code, starts a child and waits; the turn ending stops the group.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-aside-login-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let script = folder.appendingPathComponent("fake-aside"), childFile = folder.appendingPathComponent("child")
    try? "#!/bin/sh\nsleep 60 &\necho $! > '\(childFile.path)'\necho 'Confirm this code: WDJB-MJHT'\nwait\n".write(to: script, atomically: true, encoding: .utf8)
    chmod(script.path, 0o755)
    nonisolated(unsafe) var stopNow = false
    nonisolated(unsafe) var codeSeen = false
    let loginStarted = Date()
    let stopped = ArisAsideLogin.run(script.path, environment: ["PATH": "/usr/bin:/bin"], limit: 30, line: { text in
        if ArisAside.deviceCode(in: text) != nil { codeSeen = true; stopNow = true }
    }, stop: { stopNow }, arguments: [])
    let child = (try? String(contentsOf: childFile, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    Thread.sleep(forTimeInterval: 0.3)
    check(codeSeen && stopped.timedOut && Date().timeIntervalSince(loginStarted) < 10, "aside follow-up 2: the sign-in stops when the turn is over")
    check(child.map { kill($0, 0) != 0 } == true, "aside follow-up 2: the whole process group is ended, its child too")
    let done = folder.appendingPathComponent("done")
    try? "#!/bin/sh\necho 'code: K7Q2-9XZD'\nexit 0\n".write(to: done, atomically: true, encoding: .utf8)
    chmod(done.path, 0o755)
    let loginFinished = ArisAsideLogin.run(done.path, environment: ["PATH": "/usr/bin:/bin"], limit: 10, line: { _ in }, stop: { false }, arguments: [])
    check(loginFinished.ok && loginFinished.stdout.contains("K7Q2-9XZD"), "aside follow-up 2: a sign-in that ends on its own reports its exit")
}
