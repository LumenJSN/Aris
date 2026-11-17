// Tests for brain-handoff (the owner, 2026-11-14: "아니 그냥 클로드 시켜" → "지금 클로드라는 팀원은 없어요"). The AIs on
// this Mac are Aris's brains, not teammates: naming one as the one to do it hands the request to it as a background job
// (ArisBrainHandOff), the last request carried over when no task is said; a teammate of that name still wins; an AI that
// isn't set up is said as exactly that; apps the words name go to the context (ArisProgramMention); the model is told
// the brains and apps by name. Called from main.swift; uses its check().
import Foundation

private let handRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func handSource(_ path: String) -> String { (try? String(contentsOf: handRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runBrainHandoffTests() {
    brainHandoffResolverTests()
    brainHandoffCarryOverTests()
    brainHandoffMissingTests()
    brainHandoffTeammateTests()
    brainHandoffProgramTests()
    brainHandoffDispatchTests()
    brainHandoffWiringTests()
}

private typealias H = ArisBrainHandOff

private func target(_ text: String, teammates: [ArisTeammate] = []) -> ArisHandOffTarget? { H.parse(text, teammates: teammates)?.target }

// MARK: - Names

private func brainHandoffResolverTests() {
    let claude: [String] = ["아니 그냥 클로드 시켜", "그냥 클로드 시켜", "클로드 시켜", "클로드한테 맡겨", "클로드한테 맡겨 줘", "Claude로 해", "claude로 해 줘",
                            "클로드 코드 시켜", "클로드코드한테 넘겨", "클코한테 시켜", "클코 시켜", "claude code한테 맡겨", "Claude Code로 해",
                            "클로드가 해", "클로드한테 줘", "그거 클로드한테 넘겨", "이거 클로드한테 맡겨 주세요", "그냥클로드시켜", "클로드 시키면 돼",
                            "just have Claude do it", "let claude handle it", "give it to Claude Code", "hand this over to Claude",
                            "No, just use Claude", "do it with Claude", "ask Claude to do it", "클러드 시켜", "크로드한테 맡겨"]
    for words in claude { check(target(words) == .brain(.claude), "brain hand-off: \"\(words)\" → Claude") }
    let codex = ["코덱스한테 시켜", "그냥 코덱스 시켜", "codex로 해", "GPT한테 맡겨", "지피티 시켜", "챗GPT한테 넘겨", "let Codex do it", "give it to GPT"]
    for words in codex { check(target(words) == .brain(.codex), "brain hand-off: \"\(words)\" → Codex") }
    let agy = ["안티그래비티한테 시켜", "안티 그래비티로 해", "제미나이 시켜", "재미나이한테 맡겨", "gemini로 해", "have Gemini do it", "antigravity한테 넘겨"]
    for words in agy { check(target(words) == .brain(.antigravity), "brain hand-off: \"\(words)\" → Antigravity") }
    check(target("딥시크한테 시켜") == .api(service: "deepseek") && target("DeepSeek로 해") == .api(service: "deepseek")
          && target("오픈라우터한테 맡겨") == .api(service: "openrouter") && target("Gemini API로 해") == .api(service: "gemini")
          && target("let Mistral handle it") == .api(service: "mistral") && target("올라마로 해") == .api(service: "ollama"),
          "brain hand-off: an API model by its service name (Gemini API is the API model, Gemini alone Antigravity)")
    check(target("API로 해") == .api(service: nil) && target("API한테 시켜") == .api(service: nil), "brain hand-off: the API brain as such")

    // Not a hand-off: asking an AI in the turn (ArisBrain.pick), a name in passing, the app, everyday "API".
    let none = ["클로드한테 물어봐 이거 뭐야", "GPT한테 물어봐, 내일 비 와?", "코덱스로 오늘 뉴스 요약해줘", "클로드 코드 세션 몇 개야", "오늘 날씨 어때",
                "API로 받아온 데이터 정리해 줘", "클로드 앱으로 해", "ChatGPT 열어서 물어봐", "클로드 시키지 마", "Claude Code 세션 보여줘",
                "ask Claude what the capital of Peru is", "openclaude 시켜", "커서로 열어", "클로드 앱 열어서 시켜",
                "클로드한테 맡겨 놓은 거 어떻게 됐어", "클로드가 해 준 거 보여줘", "클로드 시키면 어떻게 돼?", "클로드 시켜?", "did you have Claude do it?",
                "클로드 시켜서 만든 파일 어디 있어"]
    for words in none { check(H.parse(words) == nil, "brain hand-off: \"\(words)\" is no hand-off") }
    check(ArisBrain.pick(from: "클로드한테 물어봐 이거 뭐야")?.brain == .claude, "brain hand-off: 물어봐 still picks the brain that answers the turn")

    // The task: none for a bare hand-off, the user's words when there is one.
    check(H.parse("아니 그냥 클로드 시켜")?.task == nil && H.parse("그거 클로드한테 넘겨")?.task == nil && H.parse("just have Claude do it")?.task == nil
          && H.parse("No, just use Claude")?.task == nil && H.parse("이거 클로드한테 맡겨 주세요")?.task == nil,
          "brain hand-off: only the hand-off said → no task of its own (the last request carries over)")
    check(H.parse("클로드한테 이 보고서 세 줄로 정리하라고 시켜")?.task == "클로드한테 이 보고서 세 줄로 정리하라고 시켜"
          && H.parse("다운로드 폴더 정리하는 거 클로드한테 맡겨")?.task != nil && H.parse("have Claude write the release notes")?.task != nil
          && H.parse("클로드 시켜, 회의록 요약해서 메모로")?.task != nil,
          "brain hand-off: a task said with it → the user's words as said")
    check(H.parse("아니 그냥 클로드 시켜")?.said == "클로드" && H.parse("Claude Code로 해")?.said == "Claude Code",
          "brain hand-off: the name as said")
}

// MARK: - The task carries over

private func brainHandoffCarryOverTests() {
    let asked = ArisContext.Turn(heard: "이번 주 회의록 정리해서 노션에 올려 줘", reply: "어떤 회의록을 말씀하시는 거예요? 폴더를 알려 주세요?")
    let said = "아니 그냥 클로드 시켜"
    let handOff = H.parse(said)!
    let brief = H.brief(handOff, words: said, history: [asked], to: "Claude Code")
    check(brief != nil, "carry-over: the previous request makes the job")
    check(brief?.prompt.hasPrefix(asked.heard) == true && brief?.prompt.contains(asked.reply) == true && brief?.prompt.contains(said) == true,
          "carry-over: the job's brief is the request, Aris's question back and the hand-off")
    check(brief?.title == ArisHandoff.title(of: asked.heard) && brief?.request == asked.heard + "\n" + said && brief?.request.contains("어떤 회의록") == false,
          "carry-over: its title is the request's; the policy hears only the user's words")

    // An answer to the question goes with it; an earlier unrelated turn doesn't.
    let before = ArisContext.Turn(heard: "오늘 날씨 어때", reply: "맑고 18도예요.")
    let answered = ArisContext.Turn(heard: "공유 폴더에 있는 거", reply: "노션 어느 페이지에 올릴까요?")
    let chain = H.exchange(in: [before, asked, answered])
    check(chain == [asked, answered], "carry-over: the request and the answers to Aris's questions, oldest first; the turn before stays out")
    let both = H.brief(handOff, words: said, history: [before, asked, answered], to: "Claude Code")
    check(both?.prompt.hasPrefix(asked.heard) == true && both?.prompt.contains("공유 폴더에 있는 거") == true && both?.prompt.contains("오늘 날씨") == false
          && both?.request == [asked.heard, answered.heard, said].joined(separator: "\n"),
          "carry-over: the answer rides along; the policy hears every one of the user's words in it")
    check(H.exchange(in: [asked, ArisContext.Turn(heard: "클로드 시켜", reply: "Claude Code가 맡았어요, 끝나면 알려줄게요.")]) == [asked],
          "carry-over: an earlier bare hand-off is no request")
    check(H.brief(handOff, words: said, history: [], to: "Claude Code") == nil, "carry-over: no request in the conversation → nil (Aris asks)")
    check(H.askLine("Claude Code", korean: true) == "Claude Code한테 무엇을 맡길까요?" && ArisFollowUp.asksSomething(H.askLine("Codex", korean: false)),
          "carry-over: the question back when there is nothing to hand over")
    let own = H.parse("클로드한테 이 보고서 정리하라고 시켜")!
    check(H.brief(own, words: "클로드한테 이 보고서 정리하라고 시켜", whole: "클로드한테 이 보고서 정리하라고 시켜\n[file: a.pdf]", history: [asked], to: "Claude Code")
            == H.Brief(title: "클로드한테 이 보고서 정리하라고 시켜", prompt: "클로드한테 이 보고서 정리하라고 시켜\n[file: a.pdf]", request: "클로드한테 이 보고서 정리하라고 시켜"),
          "carry-over: a task of its own is the user's words with the files given; nothing carried over")

    // The job: on the named brain, Aris's own (clone), the way Aris's own single job runs.
    let clean = ArisHandOutPlan.Turn(words: brief!.request, brain: .codex, turnId: "t1")
    let plan = H.plan(brief!, target: .brain(.claude), turn: clean)
    check(plan.brain == .claude && plan.spec.assignee == .clone && plan.spec.prompt == brief!.prompt && plan.request == brief!.request
          && !plan.provenance.untrusted && !plan.cleanContext && plan.turn == nil,
          "carry-over: \"그냥 클로드 시켜\" after a request → a background job on Claude carrying that request (clean turn: trusted, with the conversation)")
    let unclean = ArisHandOutPlan.Turn(words: brief!.request, brain: .codex, turnId: nil, screenConversation: true, handsFree: true)
    let gated = H.plan(brief!, target: .brain(.claude), turn: unclean)
    check(gated.brain == .claude && gated.provenance.untrusted && gated.provenance.screenConversation && gated.provenance.handsFree && gated.cleanContext,
          "carry-over: after the screen or outside text → untrusted, none of the conversation, on the brain named behind its own gate")
    check(H.plan(brief!, target: .api(service: "deepseek"), turn: clean).brain == .api && H.plan(brief!, target: .brain(.antigravity), turn: clean).brain == .antigravity,
          "carry-over: an API service runs on the API brain, Gemini on Antigravity")
}

// MARK: - Not set up here

private func brainHandoffMissingTests() {
    let off = ["claude": false, "codex": true, "antigravity": false, "api": false]
    let line = H.missingLine(.brain(.claude), ready: off, api: nil, korean: true, english: false)
    check(line == "Claude Code가 이 Mac에 없거나 로그인돼 있지 않아요. 설정 › AI 서비스에서 연결해 주세요.",
          "missing: Claude Code not installed or logged in → said as exactly that, with where to connect it")
    check(line?.contains("팀원") == false, "missing: never \"no such teammate\"")
    check(H.missingLine(.brain(.claude), ready: off, api: nil, korean: false, english: false)
            == "Claude Code isn't on this Mac or isn't logged in. Connect it in 설정 › AI 서비스.",
          "missing: English for an English request (the path as the window names it)")
    check(H.missingLine(.brain(.codex), ready: off, api: nil, korean: true, english: false) == nil
          && H.missingLine(.brain(.claude), ready: nil, api: nil, korean: true, english: false) == nil,
          "missing: a ready brain, or no answer from the agent → handed over (the job says what is missing)")
    check(H.missingLine(.brain(.antigravity), ready: off, api: nil, korean: true, english: false)?.hasPrefix("Antigravity가 이 Mac에") == true,
          "missing: Antigravity likewise")
    check(H.missingLine(.api(service: "deepseek"), ready: off, api: H.APIState(active: "openai", connected: ["openai"]), korean: true, english: false)
            == "DeepSeek API 키가 아직 없어요. 설정 › AI 서비스에서 키를 넣어 주세요.",
          "missing: an API service without a key")
    check(H.missingLine(.api(service: "deepseek"), ready: ["api": true], api: H.APIState(active: "openai", connected: ["openai", "deepseek"]), korean: true, english: false)
            == "지금 답하는 API 모델이 DeepSeek가 아니에요. 설정 › AI 서비스에서 바꾸면 맡길 수 있어요.",
          "missing: an API service connected but not the one that answers")
    check(H.missingLine(.api(service: "deepseek"), ready: ["api": true], api: H.APIState(active: "deepseek", connected: ["deepseek"]), korean: true, english: false) == nil,
          "missing: the API service that answers, ready → handed over")
    check(H.missingLine(.api(service: nil), ready: off, api: nil, korean: true, english: false)?.contains("API 키") == true,
          "missing: the API brain with no key")
}

// MARK: - A teammate of that name wins

private func brainHandoffTeammateTests() {
    let mate = ArisTeammate(id: "mate-claude", name: "클로드", role: "문서 담당", look: .standard, brain: "codex", memoryFile: "teammates/mate-claude.md")
    let codi = ArisTeammate(id: "mate-codi", name: "코디", role: "문서 정리 담당", look: .standard, brain: "antigravity", memoryFile: "teammates/mate-codi.md")
    check(target("아니 그냥 클로드 시켜", teammates: [.claudeCode, mate, codi]) == .teammate("mate-claude"),
          "teammate wins: a teammate named 클로드 takes \"그냥 클로드 시켜\" over the brain")
    check(target("클로드 코드 시켜", teammates: [.claudeCode, mate]) == .brain(.claude),
          "teammate wins: only the name itself (클로드 코드 is still the brain)")
    check(target("아니 그냥 코디 시켜", teammates: [.claudeCode, codi]) == .teammate("mate-codi") && H.parse("코디한테 맡겨", teammates: [codi])?.task == nil,
          "teammate: a teammate's bare hand-off carries over too")
    check(target("Claude Code한테 맡겨", teammates: [.claudeCode]) == .brain(.claude),
          "teammate: the seeded Claude Code (a terminal in a project folder) is the brain here")
    let brief = H.Brief(title: "t", prompt: "p", request: "r")
    let plan = H.plan(brief, target: .teammate("mate-codi"), turn: ArisHandOutPlan.Turn(words: "r", brain: .codex, turnId: nil), teammateBrains: ["mate-codi": .antigravity])
    check(plan.spec.assignee == .teammate("mate-codi") && plan.brain == .antigravity,
          "teammate: its job on its own brain, as its own (its scopes apply in the agent)")
    check(H.missingLine(.teammate("mate-codi"), ready: ["antigravity": false], api: nil, korean: true, english: false) == nil,
          "teammate: no brain line for a teammate (its unready brain falls back to Aris as every teammate job does)")
}

// MARK: - Apps

private func brainHandoffProgramTests() {
    let installed = ["Claude", "ChatGPT", "Cursor", "Notion", "Safari"]
    check(ArisProgramMention.named(in: "클로드 앱으로 해", installed: installed).apps == ["Claude"], "apps: 클로드 앱 → the Claude app")
    check(ArisProgramMention.named(in: "ChatGPT 열어서 물어봐", installed: installed).apps == ["ChatGPT"], "apps: ChatGPT 열어서 → the ChatGPT app")
    check(ArisProgramMention.named(in: "커서로 열어", installed: installed).apps == ["Cursor"], "apps: 커서로 열어 → Cursor")
    check(ArisProgramMention.named(in: "open the Claude app and ask it", installed: installed).apps == ["Claude"]
          && ArisProgramMention.named(in: "write it in Notion", installed: installed).apps == ["Notion"],
          "apps: English names (open …, in …)")
    check(ArisProgramMention.named(in: "클로드 시켜", installed: installed).apps.isEmpty && ArisProgramMention.named(in: "오늘 날씨 어때", installed: installed).apps.isEmpty
          && ArisProgramMention.named(in: "설정에서 다크 모드 켜", installed: installed + ["System Settings"]).apps.isEmpty,
          "apps: a hand-off, an ordinary question and Aris's own 설정 name no app")
    let missing = ArisProgramMention.named(in: "커서로 열어", installed: ["Safari"])
    check(missing.apps.isEmpty && missing.missing == ["Cursor"], "apps: a known app that isn't installed is said as not installed")
    let line = ArisProgramMention.contextLine(apps: ["Claude"], missing: [])
    check(line?.contains("never a teammate or a person") == true && line?.contains("Claude") == true && ArisProgramMention.contextLine(apps: [], missing: []) == nil,
          "apps: the context's line says the app is the app, never a teammate")
    let context = ArisContext.make(now: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: [],
                                   programs: line)
    check(context.contains("apps the request names"), "apps: the line goes into the turn's context")
}

// MARK: - The model knows them by name

private func brainHandoffDispatchTests() {
    let block = ArisAgentPrompt.teammates([.claudeCode], home: "/Users/p", addressed: nil)
    check(block.contains("No one else is a teammate") && block.contains("클로드") && block.contains("코덱스") && block.contains("제미나이")
          && block.contains("never \"no such teammate\"") && block.contains("\"brain\"") && block.contains("`desktop`"),
          "prompt: the teammates block names the brains and apps by name, and never says \"no such teammate\" for them")
    let reply = "```json\n{\"jobs\":[{\"title\":\"회의록\",\"prompt\":\"회의록 정리\",\"assignee\":\"clone\",\"brain\":\"claude\"}]}\n```"
    let specs = ArisDispatch.parse(reply, teammateIds: ArisDispatch.teammateIds([]))
    check(specs?.first?.brain == .claude && specs?.first?.assignee == .clone, "dispatch: a jobs block may name the brain")
    check(ArisDispatch.parse(reply.replacingOccurrences(of: "\"claude\"", with: "\"skynet\""), teammateIds: [])?.first?.brain == nil,
          "dispatch: an unknown brain is none")
    let turn = ArisHandOutPlan.Turn(words: "그냥 클로드 시켜", brain: .codex, turnId: nil)
    check(ArisHandOutPlan.plan(specs ?? [], turn: turn).first?.brain == .claude, "dispatch: a clean turn's one job runs on the brain its block named")
    let untrusted = ArisHandOutPlan.Turn(words: "그냥 클로드 시켜", brain: .codex, turnId: nil, untrustedTurn: true)
    check(ArisHandOutPlan.plan(specs ?? [], turn: untrusted).first?.brain == .codex,
          "dispatch: an untrusted turn's model-named brain is ignored (the gated brain, as before)")
    check(ArisJobSpec(title: "t", prompt: "p", assignee: .clone, cwd: nil, appHint: nil, brain: .claude).brain == .claude
          && handSource("Aris/private/Aris/ArisController+Local.swift").contains("brain: brain)"),
          "dispatch: the files given keep the brain")
}

// MARK: - Wiring

private func brainHandoffWiringTests() {
    let controller = handSource("Aris/private/Aris/ArisController.swift")
    let handOver = handSource("Aris/private/Aris/ArisController+BrainHandOff.swift")
    check(controller.contains("let handOff = shots ? nil : await brainHandOff(") && controller.contains("let named = handOff == nil ? ArisBrain.pick(from: heard) : nil"),
          "wiring: the hand-off is read before an AI is picked for the turn")
    check(controller.contains("} else if let handing {") && controller.contains("reply = await handOver(handing,")
          && (controller.range(of: "} else if let handing {")?.lowerBound ?? controller.endIndex) < (controller.range(of: "} else if let job = called?.asking(whole) {")?.lowerBound ?? controller.startIndex),
          "wiring: handed over before a teammate's direct call (whose task-less hand-off now carries over too)")
    check(controller.contains("programs: turnPrograms") && controller.contains("turnPrograms = handOff == nil && !shots ? await programsLine(unmarked) : nil"),
          "wiring: the apps named go into the turn's context")
    check(handOver.contains("missingForHandOff") && handOver.contains("ArisAgentClient.teamBrainsSaid()") && handOver.contains("ArisHandOutPlan.keepsInTurn")
          && handOver.contains("ArisJobRouting.withoutUnreadyTeammates") && handOver.contains("dispatch([plan]"),
          "wiring: readiness asked now, Aris's own data kept in the turn, an unready teammate falls back, the job dispatched")
}
