// Tests for fix-14 (the tenth VM pass on 551a585f), the parts off the desktop rig: a turn that typed through
// `aris-tools type` (the desktop engine's call now) counts as a desktop-only turn, so its step can be saved; the shell
// gate reads `desktop wait <id>` (read-only, no card); the brains are told to keep a standing preference word for word
// ("앞으로" included) when they remember it. Called from main.swift; uses its check().
import Foundation

func runFix14Tests() {
    fix14DesktopTurnTests()
    fix14WaitGateTests()
    fix14RememberPromptTests()
}

// MARK: - 1. `aris-tools type` is a desktop call of the turn

private func fix14DesktopTurnTests() {
    let tools = "/tools/aris-tools"
    let desktop = { (command: String) in ArisDesktopHonesty.isDesktopCommand(command, tools: tools) }
    check(desktop("\(tools) type '둘' --app TextEdit") && desktop("aris-tools type '둘' --app TextEdit") && desktop("\(tools) type 둘"),
          "fix-14 turn: `aris-tools type` (the engine's `desktop type --focused`) is a desktop call of the turn")
    check(desktop("\(tools) desktop see --app TextEdit") && desktop("\(tools) desktop see --app TextEdit && \(tools) type '둘' --app TextEdit"),
          "fix-14 turn: `aris-tools desktop …` still is, and a line of desktop calls only")
    check(!desktop("\(tools) keys cmd+t --app Safari") && !desktop("\(tools) type '둘' --app TextEdit && \(tools) remember x")
          && !desktop("\(tools) remember '앞으로 나를 솔이라고 불러'") && !desktop("echo type") && !desktop("\(tools) type"),
          "fix-14 turn: keys, anything chained after it, other tools and a bare `type` are not")
    // The turn's recipe: desktop actions only, the typed text word for word in the request.
    let request = "TextEdit 창 끝에 '둘' 입력해 줘"
    let step = ArisSavedStep(action: .type, bundle: "com.apple.TextEdit", app: "TextEdit", window: "noteC.txt", role: "textArea", path: [], text: "둘",
                             lookJudged: false, contentLabel: true)
    let otherTools = !desktop("\(tools) type '둘' --app TextEdit")
    let recipe = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: request), request: request, notes: [.success(step)], notDone: 0, otherTools: otherTools,
                                           reply: "noteC.txt 창 끝에 '둘'을 입력했어요.", outside: true)
    check(recipe?.steps == [step], "fix-14 turn: \"\(request)\" typed through `aris-tools type` makes a recipe of its one step")
    let notInWords = ArisSavedSteps.turnRecipe(key: ArisShortcuts.key(for: "TextEdit 창 끝에 입력해 줘"), request: "TextEdit 창 끝에 입력해 줘",
                                               notes: [.success(step)], notDone: 0, otherTools: otherTools, reply: "입력했어요.", outside: true)
    check(notInWords == nil, "fix-14 turn: text that isn't word for word in the request is never saved")
    let runner = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisAgent/ArisAgentRunner.swift"), encoding: .utf8)) ?? ""
    check(runner.contains("ArisDesktopHonesty.isDesktopCommand($0, tools: Self.toolsPath) } == true) { nonDesktopTool = true }"),
          "fix-14 turn: the runner marks a turn as using other tools by that one rule")
}

// MARK: - 3. `desktop wait <id>` through the shell gate

private func fix14WaitGateTests() {
    let tools = "/tools/aris-tools"
    func risk(_ command: String) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(command), tools: tools, home: "/Users/testuser", request: "TextEdit의 noteD.txt 창 끝에 '넷' 입력해 줘")
    }
    let id = "030ab0af834b52bd"
    check(risk("\(tools) desktop wait \(id)") == .auto && ArisRiskPolicy.isDesktop("\(tools) desktop wait \(id)", tools: tools)
          && ArisRiskPolicy.desktopProblem("\(tools) desktop wait \(id)", tools: tools) == nil,
          "fix-14 wait: `desktop wait <id>` is read by the shell gate: read-only, no card (\(risk("\(tools) desktop wait \(id)")))")
    check(ArisDesktopWords.isWait(["wait", id]) && !ArisDesktopWords.isWait(["wait"]) && !ArisDesktopWords.isWait(["wait", "XYZ"])
          && !ArisDesktopWords.isWait(["wait", id, "--app", "TextEdit"]),
          "fix-14 wait: the words are `wait` and one call id, nothing else")
    let bad = ArisRiskPolicy.desktopProblem("\(tools) desktop wait", tools: tools) ?? ""
    check(risk("\(tools) desktop wait") == .never && bad.contains(ArisDesktopWords.waitUsage),
          "fix-14 wait: with no id it is refused with its own usage (\(bad.prefix(120)))")
    check(risk("\(tools) desktop wait \(id); rm -rf ~") != .auto && risk("\(tools) desktop wait \(id) && \(tools) remember x") != .auto,
          "fix-14 wait: chained with anything else it is judged as a command")
    // The engine's words never take it (it is the route's, never an action): agy's relay can't send it to the engine.
    check((try? ArisDesktopWords.parse(["wait", id], text: nil).get()) == nil, "fix-14 wait: not one of the engine's verbs")
}

// MARK: - 4. remember: a standing preference word for word

private func fix14RememberPromptTests() {
    let tools = "/tools/aris-tools"
    let rule = ArisAgentPrompt.rememberRule
    check(rule.contains("word for word") && rule.contains("앞으로") && rule.contains("from now on") && rule.contains("never reworded"),
          "fix-14 prompt: the rule says a standing preference is kept word for word, 앞으로 / from now on included")
    let api = ArisAgentPrompt.system(tools: tools, gated: true, functions: true)
    let claude = ArisAgentPrompt.system(tools: tools)
    let handOff = ArisAgentPrompt.sealedWrites(tools)
    check(api.contains(rule) && claude.contains(rule) && handOff.contains(rule),
          "fix-14 prompt: every brain's memory line carries it (the API brain's, Claude's and the hand-off list)")
    let function = ArisAPICatalog.entry("remember")?.function
    let fact = ((function?.parameters["properties"] as? [String: Any])?["fact"] as? [String: Any])?["description"] as? String ?? ""
    check(function?.description.contains("word for word") == true && function?.description.contains("앞으로") == true && fact.contains("word for word"),
          "fix-14 prompt: the API brain's remember function says so, and its fact is the user's sentence word for word (\(fact))")
    let toolsMain = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisTools/main.swift"), encoding: .utf8)) ?? ""
    check(toolsMain.contains("aris-tools remember <fact>              keep a fact about the user in their own words (a standing preference word for word, 앞으로 kept)")
          && toolsMain.contains(#"fail("usage: remember <fact, in the user's own words>")"#),
          "fix-14 prompt: aris-tools' own usage says it too")
}
