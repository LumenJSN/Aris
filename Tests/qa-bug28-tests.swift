// Tests for QA BUG-28: the schedule-add card is a real schedule card in plain words (never "Mac 작업" with the CLI
// line), and a stored job keeps the user's own request, never an aris-tools path or a literal \n.
import Foundation

func runQABug28Tests() {
    qaScheduleCardTests()
    qaSchedulePromptTests()
}

private let s28Tools = "/Users/me/.config/aris/aris-tools"

private func qaScheduleCardTests() {
    let line = "\(s28Tools) schedule add --title \"아침 날씨 안내\" --prompt \"오늘 날씨 알려 줘\" --daily 09:00"
    let (title, detail) = ArisCodexDriver.describe(command: line, tools: s28Tools, team: [.claudeCode], request: "매일 아침 9시에 날씨 알려 줘")
    check(title == "예약 추가", "BUG-28: the card's title is 예약 추가, never Mac 작업: \(title)")
    check(detail.contains("매일 09:00") && detail.contains("아침 날씨 안내") && detail.contains("오늘 날씨 알려 줘"),
          "BUG-28: the card says when, the job's title and what it will do: \(detail)")
    check(!detail.contains("--") && !detail.contains("aris-tools") && !detail.contains("/Users/") && !detail.contains("add ")
          && !detail.contains("\\n") && !detail.contains("팀원"), "BUG-28: no flags, paths or CLI words, and no teammate line without one: \(detail)")

    // Said in English, an English card.
    let english = ArisCodexDriver.describe(command: "\(s28Tools) schedule add --title Weather --prompt \"tell me the weather\" --weekly fri 18:00",
                                           tools: s28Tools, team: [.claudeCode], request: "every Friday at 6 tell me the weather")
    check(english.0 == "Add a schedule" && english.1.contains("every Friday at 18:00") && english.1.contains("Weather")
          && english.1.contains("tell me the weather") && !english.1.contains("--"), "BUG-28: an English request gets an English card: \(english)")
    let once = ArisCodexDriver.describe(command: "\(s28Tools) schedule add --title 회의 --prompt \"회의 5분 전이라고 알려 줘\" --every 30m",
                                        tools: s28Tools, team: [.claudeCode], request: "30분마다 알려 줘")
    check(once.1.contains("30분마다"), "BUG-28: a repeat says how often: \(once.1)")

    // A "Say:" prompt is said in words, never raw.
    let say = ArisCodexDriver.describe(command: "\(s28Tools) schedule add --title 테스트 --prompt \"Say: 테스트 예약 완료\" --daily 08:00",
                                       tools: s28Tools, team: [.claudeCode], request: "매일 8시에 테스트 예약 완료라고 말해 줘")
    check(say.1.contains("“테스트 예약 완료”라고 말해요") && !say.1.contains("Say:"), "BUG-28: a Say: prompt reads as words: \(say.1)")

    // The teammate line stays (the existing scheduledAs line).
    let mate = ArisTeammate(id: "mong", name: "몽실", routing: "", look: .standard, brain: "codex", scopes: ["files", "calendar"], memoryFile: "")
    let named = ArisCodexDriver.describe(command: line + " --teammate mong", tools: s28Tools, team: [.claudeCode, mate], request: "매일 날씨 알려 줘").1
    check(named.contains("몽실") && named.contains("파일"), "BUG-28: the teammate who runs it, and what it may use: \(named)")

    // A model-written shell line as the prompt: the card says it won't be made, never shows it.
    let shell = "\(s28Tools) schedule add --title \"아침 날씨 안내\" --prompt \"Say: 날씨\\n\(s28Tools) weather\" --daily 09:00"
    let bad = ArisCodexDriver.describe(command: shell, tools: s28Tools, team: [.claudeCode], request: "매일 아침 9시에 날씨 알려 줘")
    check(bad.0 == "예약 추가" && !bad.1.contains("aris-tools") && !bad.1.contains("/Users/") && bad.1.contains("만들어지지 않아요"),
          "BUG-28: a prompt that is a command line is never shown, and the card says nothing will be scheduled: \(bad.1)")

    // The API gate's card is the same; and schedule add still always asks.
    let gate = ArisAPIGate(tools: s28Tools, home: "/Users/me")
    gate.request = "매일 아침 9시에 날씨 알려 줘"
    if case .ask(let ask, _, _, _) = gate.judge(line) {
        check(ask.title == "예약 추가" && ask.detail.contains("매일 09:00") && !ask.detail.contains("--"), "BUG-28: the API brain's card is the schedule card")
    } else {
        check(false, "BUG-28: the API brain's schedule add asks the user")
    }
    check(ArisRiskPolicy.risk(of: .shell(line), tools: s28Tools, home: "/Users/me") == .confirm
          && !ArisRiskPolicy.isRepeatable(.shell(line), tools: s28Tools), "BUG-28: schedule add always asks, never repeated")
}

private func qaSchedulePromptTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000), calendar = Calendar(identifier: .gregorian)
    func parse(_ prompt: String) -> Result<ArisScheduleArguments.Parsed, Error> {
        Result { try ArisScheduleArguments.parse(["--title", "날씨", "--prompt", prompt, "--daily", "09:00"], now: now, calendar: calendar) }
    }
    if case .success(let parsed) = parse("오늘 날씨 알려 줘") { check(parsed.prompt == "오늘 날씨 알려 줘", "BUG-28: the user's own words are kept as said") }
    else { check(false, "BUG-28: the user's own words parse") }
    if case .success(let parsed) = parse("Say: 좋은 아침\\n오늘도 화이팅") {
        check(parsed.prompt == "Say: 좋은 아침 오늘도 화이팅", "BUG-28: a literal \\n becomes a space: \(parsed.prompt)")
    } else { check(false, "BUG-28: a literal \\n is normalized, not refused") }
    if case .success(let parsed) = parse("좋은 아침\n오늘도") { check(parsed.prompt == "좋은 아침 오늘도", "BUG-28: a real line break becomes a space") }
    else { check(false, "BUG-28: a line break is normalized") }
    for command in ["Say: 날씨\\n\(s28Tools) weather --daily 09:00", "\(s28Tools) weather", "aris-tools weather 서울", "날씨 ~/.config/aris/aris-tools weather"] {
        if case .failure(let error) = parse(command) {
            let said = (error as? ArisScheduleError)?.message ?? ""
            check(said.contains("--prompt") && said.contains("own words") && said.contains("오늘 날씨 알려 줘"),
                  "BUG-28: a prompt with aris-tools in it is refused with what to do instead: \(said)")
        } else {
            check(false, "BUG-28: a prompt with an aris-tools command is refused: \(command)")
        }
    }
    // What the brains are told.
    let gated = ArisAgentPrompt.system(tools: "/t", gated: true)
    check(gated.contains("schedule add") && gated.contains("오늘 날씨 알려 줘") && gated.contains("no commands, paths or \\n")
          && !gated.contains("Say: 테스트 예약 완료"), "BUG-28: brains put the user's own request words in --prompt")
}
