// Look first (the owner, 2026-11-14: "생각을 하고 답하든지… 알아볼께 이지랄하던가"). Aris answered "이 대화에는 어사이드의 답이
// 없어요" with Aside open on the screen, "다른 화면은 읽을 수 없어요" with Claude Code on his other display, and asked
// "어느 채널이요?" twice for a report it could have handed to Claude Code. Now: words that name a visible app's words
// ("어사이드가 뭐라고 했어"), a bare "뭐야?" and "다른 화면" carry the screen; the display holding the named app is the
// one shot, others too when he says another screen (at most 3, in memory only); and the prompt has Aris look, recall
// and hand over before it asks. Fakes only: the real screen is never captured here.
import CoreGraphics
import Foundation

func runLookFirstTests() {
    lookFirstTriggerTests()
    lookFirstWantTests()
    lookFirstDisplayTests()
    lookFirstImageTests()
    MainActor.assumeIsolated { lookFirstCaptureTests() }
    lookFirstPromptTests()
    lookFirstThinkingTests()
    lookFirstReachTests()
}

/// What is on the user's screens in these tests: the apps with a window showing.
private let lookApps = ["Aside", "Google Chrome", "Terminal", "Finder", "Slack"]

// MARK: - A: the words that point at the screen

private let lookYes: [String] = [
    // The user's own words tonight
    "어사이드가 지금 뭐라고 했는지 나한테 읽어줘 봐", "어사이드가 뭐라고 했어", "뭐야? 뭐야?", "다른 화면에 있다",
    // A named app's words
    "어사이드 답 읽어줘", "어사이드 뭐래", "크롬에 뭐 떠 있어", "크롬에 나와 있는 거 요약해줘", "슬랙에 뭐라고 왔어", "터미널에 뭐라고 나와",
    "터미널 지금 뭐 하고 있어", "aside가 뭐라고 했어",
    "what did Aside say", "read me what Aside wrote", "what's Aside saying", "what does Chrome show", "read the terminal",
    // A bare what
    "뭐야?", "뭐야", "뭐지?", "이게 뭐지", "뭔데", "아리스 뭐야", "what's that", "what is that?", "what?", "huh, what",
    // Another screen
    "옆 화면 봐 줘", "다른 모니터에 있는 거 읽어줘", "다른 화면 봐", "두 번째 화면에 뭐 있어", "모든 화면 봐 줘",
    "it's on the other screen", "look at my other monitor", "what's on my second display", "check both screens",
]

private let lookNo: [String] = [
    // Doing something with the app, not reading it
    "어사이드한테 물어봐", "어사이드한테 맛집 예약 시켜", "어사이드 열어줘", "크롬 꺼줘", "크롬 닫아줘", "슬랙 실행해줘",
    "ask Aside to book a table", "open Chrome", "quit Slack", "have Aside do it",
    // Not a bare what
    "그게 뭐야", "오늘 뭐야", "다음 일정 뭐야", "회의 언제야", "what's the weather", "what's next", "what time is it",
    // Another screen as a place to put things
    "다른 화면에 띄워줘", "다른 화면으로 옮겨줘", "옆 화면에 표로 보여줘", "put it on the other screen", "move Safari to the other monitor",
    "show it on my second display", "다른 모니터 밝기 올려줘",
    // An everyday word that is also an app, and a plain question
    "메일 읽어줘", "메모 뭐라고 돼 있어", "프랑스 수도가 어디야", "고마워",
]

private func lookFirstTriggerTests() {
    for said in lookYes {
        check(ArisScreenNeed.pointsAtScreen(said, apps: lookApps), "look first: \"\(said)\" points at the screen, so the turn carries it")
    }
    for said in lookNo {
        check(!ArisScreenNeed.pointsAtScreen(said, apps: lookApps), "look first: \"\(said)\" is not about the screen, so nothing is captured")
    }
    // Only an app that is showing: with no Aside window there is nothing of it on the screen to read.
    check(!ArisScreenNeed.pointsAtScreen("어사이드가 뭐라고 했어", apps: []) && !ArisScreenNeed.pointsAtScreen("what did Aside say", apps: ["Finder"]),
          "look first: an app that has no window showing is not on the screen")
    check(ArisScreenNeed.captures(words: "어사이드가 뭐라고 했어", setting: true, drew: false, apps: lookApps)
          && !ArisScreenNeed.captures(words: "어사이드가 뭐라고 했어", setting: false, drew: false, apps: lookApps)
          && !ArisScreenNeed.captures(words: "뭐야?", setting: true, drew: true, apps: lookApps),
          "look first: the setting and a drawing still decide, as for every screen turn")
    // Files given to Aris are still what "이거" and "뭐야" mean.
    let withFiles = ArisPendingFiles().adding([URL(fileURLWithPath: "/tmp/a.pdf")]).taking(into: "뭐야?").text
    check(!ArisScreenNeed.pointsAtScreen(withFiles, apps: lookApps), "look first: with files given to Aris a bare \"뭐야\" is about them")
}

// MARK: - What the turn wants to see

private func lookFirstWantTests() {
    let aside = ArisScreenNeed.want("어사이드가 지금 뭐라고 했는지 나한테 읽어줘 봐", apps: lookApps)
    check(aside == ArisScreenNeed.Want(apps: ["Aside"], others: false), "want: \"어사이드가 뭐라고\" wants Aside's display (\(String(describing: aside)))")
    let terminal = ArisScreenNeed.want("터미널에 뭐라고 나와", apps: lookApps)
    check(terminal?.apps == ["Terminal"] && terminal?.others == false, "want: \"터미널\" is the terminal that is showing")
    // Claude Code's sessions come from Aris's hooks (the context), never off the screen, and "claude" in it is no app.
    check(ArisScreenNeed.readsApps("Claude Code 세션 읽어줘", apps: lookApps + ["Claude"]).isEmpty
          && ArisScreenNeed.readsApps("클로드 코드가 뭐라고 했어", apps: lookApps + ["Claude"]).isEmpty
          && ArisScreenNeed.readsApps("클로드 앱이 뭐라고 했어", apps: lookApps + ["Claude"]) == ["Claude"],
          "want: a coding agent's session is never taken for an app's window; the Claude app still is")
    check(ArisScreenNeed.want("다른 화면에 있다", apps: lookApps) == ArisScreenNeed.Want(apps: [], others: true)
          && ArisScreenNeed.want("옆 화면에 있는 어사이드 읽어줘", apps: lookApps) == ArisScreenNeed.Want(apps: ["Aside"], others: true),
          "want: \"다른 화면\" wants the other displays too")
    check(ArisScreenNeed.want("이거 뭐야", apps: lookApps) == ArisScreenNeed.Want(apps: [], others: false)
          && ArisScreenNeed.want("프랑스 수도가 어디야", apps: lookApps) == nil,
          "want: a plain pointing turn wants the display under the pointer; a plain question wants nothing")
    check(ArisScreenNeed.wantsOtherScreens("다른 화면에 있다") && ArisScreenNeed.wantsOtherScreens("look at my other monitor")
          && !ArisScreenNeed.wantsOtherScreens("다른 화면에 띄워줘") && !ArisScreenNeed.wantsOtherScreens("화면 봐 줘"),
          "want: another screen is said in words, never a place to put things")
}

// MARK: - B: which displays

private func lookFirstDisplayTests() {
    typealias P = ArisDisplayPick
    let main = P.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
    let right = P.Display(id: 2, frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    let left = P.Display(id: 3, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let fourth = P.Display(id: 4, frame: CGRect(x: 0, y: 982, width: 1512, height: 982))
    let screens = [main, right, left, fourth]
    let onMain = CGPoint(x: 700, y: 400)
    let asideOnRight = P.Window(app: "Aside", frame: CGRect(x: 1700, y: 200, width: 1200, height: 900))

    let plain = P.pick(displays: screens, pointer: onMain, windows: [asideOnRight], want: .init(apps: [], others: false))
    check(plain == [P.Pick(id: 1, role: .pointer)], "displays: a plain screen turn takes the display under the pointer (\(plain))")
    let aside = P.pick(displays: screens, pointer: onMain, windows: [asideOnRight], want: .init(apps: ["Aside"], others: false))
    check(aside == [P.Pick(id: 2, role: .app("Aside"))], "displays: the display holding the named app's window, not the pointer's (\(aside))")
    let others = P.pick(displays: screens, pointer: onMain, windows: [], want: .init(apps: [], others: true))
    check(others == [P.Pick(id: 1, role: .pointer), P.Pick(id: 2, role: .other), P.Pick(id: 3, role: .other)],
          "displays: \"다른 화면\" adds the others, at most 3 in all (\(others))")
    let gone = P.pick(displays: screens, pointer: onMain, windows: [], want: .init(apps: ["Aside"], others: false))
    check(gone.count == 3 && gone.first == P.Pick(id: 1, role: .pointer),
          "displays: a named app whose window can't be placed: the pointer's display first, then the others (\(gone))")
    let both = P.pick(displays: screens, pointer: onMain,
                      windows: [asideOnRight, P.Window(app: "Aside", frame: CGRect(x: -1500, y: 100, width: 800, height: 600))],
                      want: .init(apps: ["Aside"], others: false))
    check(both == [P.Pick(id: 2, role: .app("Aside")), P.Pick(id: 3, role: .app("Aside"))],
          "displays: an app with windows on two displays: both, front window's first (\(both))")
    let alone = P.pick(displays: [main], pointer: onMain, windows: [], want: .init(apps: [], others: true))
    check(alone == [P.Pick(id: 1, role: .pointer)], "displays: one display: \"다른 화면\" still takes just it")
    let tiny = P.pick(displays: screens, pointer: onMain, windows: [P.Window(app: "Aside", frame: CGRect(x: 1600, y: 10, width: 20, height: 20))],
                      want: .init(apps: ["Aside"], others: false))
    check(tiny.first?.role == .pointer, "displays: a sliver of a window (a menu-bar item) doesn't count as the app's window")
    check(P.pick(displays: [], pointer: onMain, windows: [], want: .init(apps: [], others: true)).isEmpty, "displays: no display, no shot")
    check(P.maxDisplays == 3, "displays: at most three")

    // CGWindowList's top-left coordinates turned into the screens' bottom-left ones.
    let cocoa = P.cocoa(fromWindowBounds: CGRect(x: 100, y: 50, width: 400, height: 300), primaryHeight: 982)
    check(cocoa == CGRect(x: 100, y: 632, width: 400, height: 300), "displays: window bounds are turned into the screens' coordinates (\(cocoa))")

    // What the brain is told about each image.
    let one = P.description(role: .pointer, index: 1, count: 1, frame: main.frame, main: main.frame)
    let first = P.description(role: .app("Aside"), index: 1, count: 2, frame: right.frame, main: main.frame)
    let second = P.description(role: .other, index: 2, count: 2, frame: left.frame, main: main.frame)
    check(one == "화면 1/1 · 마우스가 있는 화면" && first == "화면 1/2 (오른쪽) · Aside 창이 있는 화면" && second == "화면 2/2 (왼쪽) · 다른 화면",
          "displays: each image says which display it is (\(one) | \(first) | \(second))")
    check(P.imageName(1) == "cursor-screen.png" && P.imageName(2) == "screen-2.png" && P.imageName(3) == "screen-3.png",
          "displays: the first image keeps its name, the others are screen-N")
}

// MARK: - The images as the agent checks them

private func lookFirstImageTests() {
    func pngEntry() -> [String: Any] {
        let image = CGContext(data: nil, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return ["kind": "cursor", "mime": "image/png", "data": ArisImageCodec.png(image)!.base64EncodedString(), "title": "화면 1/2 · 마우스가 있는 화면"]
    }
    guard case .success(let three) = ArisTurnImage.parse([pngEntry(), pngEntry(), pngEntry()]) else {
        return check(false, "images: three displays are taken")
    }
    check(three.map(\.name) == ["cursor-screen.png", "screen-2.png", "screen-3.png"] && three.allSatisfy { $0.kind == .cursor }
          && three[0].label == "cursor-screen.png — 지금 화면: 화면 1/2 · 마우스가 있는 화면",
          "images: up to three displays, named by Aris, each with its label (\(three.map(\.label)))")
    if case .failure(let error) = ArisTurnImage.parse([pngEntry(), pngEntry(), pngEntry(), pngEntry()]) {
        check(error == .counts, "images: a fourth display is refused")
    } else {
        check(false, "images: a fourth display is refused")
    }
    check(ArisTurnImage.maxCursor == ArisDisplayPick.maxDisplays, "images: the agent takes as many displays as the app sends")
}

// MARK: - The capture: the plan goes to the shooter

@MainActor private func lookFirstCaptureTests() {
    func spin(_ seconds: Double = 3, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    let png = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 7, count: 5000)
    var plain = 0
    var wanted: [ArisScreenNeed.Want] = []
    func make() -> ArisTurnCapture {
        var deps = ArisTurnCapture.Dependencies(
            shoot: { plain += 1; return ArisTurnCapture.Shot(png: png, ms: 10, retried: false) },
            enabled: { true }, permission: { true }, nextNotice: { nil }, notify: { _ in },
            waitAtSend: .milliseconds(300), keepFor: .seconds(30))
        deps.visibleApps = { lookApps }
        deps.screens = { want in
            wanted.append(want)
            return [ArisTurnCapture.Shot(png: png, ms: 20, retried: false, title: "화면 1/2 (오른쪽) · Aside 창이 있는 화면"),
                    ArisTurnCapture.Shot(png: png, ms: 21, retried: false, title: "화면 2/2 · 다른 화면")]
        }
        return ArisTurnCapture(dependencies: deps)
    }
    func take(_ capture: ArisTurnCapture) -> ArisTurnCapture.Taken? {
        var got: ArisTurnCapture.Taken??
        Task { @MainActor in got = .some(await capture.image()) }
        spin { got != nil }
        return got ?? nil
    }

    let aside = make()
    aside.began(notchShowsAnswer: false)
    let started = aside.heard("어사이드가 뭐라고 했어")
    let taken = take(aside)
    check(started && plain == 0 && wanted == [ArisScreenNeed.Want(apps: ["Aside"], others: false)]
          && taken?.images.map(\.name) == ["cursor-screen.png", "screen-2.png"]
          && taken?.images.first?.title == "화면 1/2 (오른쪽) · Aside 창이 있는 화면" && taken?.bytes == png.count * 2,
          "capture: a named app's words shoot its display with the plan, every image labelled (\(String(describing: taken?.images.map(\.label))))")

    let pointing = make()
    pointing.began(notchShowsAnswer: false)
    _ = pointing.heard("이거 뭐야")
    let one = take(pointing)
    check(plain == 1 && wanted.count == 1 && one?.images.count == 1 && one?.image.name == "cursor-screen.png",
          "capture: a plain \"이거 뭐야\" is the one shot of the pointer's display, as before")

    let other = make()
    other.began(notchShowsAnswer: false)
    _ = other.heard("다른 화면에 있다")
    _ = take(other)
    check(wanted.last == ArisScreenNeed.Want(apps: [], others: true), "capture: \"다른 화면\" asks for the other displays too")

    let none = make()
    none.began(notchShowsAnswer: false)
    check(!none.heard("프랑스 수도가 어디야") && take(none) == nil && wanted.count == 2 && plain == 1, "capture: a plain question shoots nothing")
}

// MARK: - C: the prompt tells Aris to look before it asks

private func lookFirstPromptTests() {
    let tools = "/Users/p/.config/aris/aris-tools"
    let rule = ArisAgentPrompt.tryFirstRule
    check(rule.contains("Before you ask the user anything") && rule.contains("look at an app's window") && rule.contains("memory")
          && rule.contains("recall") && rule.contains("activity") && rule.contains("<reach>") && rule.contains("알아볼게요")
          && rule.contains("one specific question") && rule.contains("더 알려 주세요"),
          "prompt: look, recall and hand over first; ask one specific question only when nothing reachable could answer")
    check(rule.contains("display") && rule.contains("never say you can see only one screen"),
          "prompt: every display can be looked at, and \"I can only see this screen\" is never said")
    let open = ArisAgentPrompt.system(tools: tools, reads: true), gated = ArisAgentPrompt.system(tools: tools, gated: true)
    let api = ArisAgentPrompt.system(tools: tools, gated: true, functions: true)
    check([open, gated, api].allSatisfy { $0.contains(rule) && !$0.contains("Only ask a question back if the request is truly ambiguous") },
          "prompt: every conversation brain gets the rule in place of \"only ask if truly ambiguous\"")
    check(!ArisAgentPrompt.system(tools: tools, gated: true, task: true).contains(rule),
          "prompt: a background job hands nothing out, so it isn't told to")
    check(open.contains("A follow-up that points back") && open.contains("never change or send anything on a guess"),
          "prompt: a follow-up that points back at several things still asks which one, and nothing is changed on a guess")
    let past = ArisAgentPrompt.pastJobsRule
    check(past.contains("look first") && past.contains("record of past work") && past.contains("activity --today") && past.contains("on the screen")
          && !past.contains("recall")
          && past.contains("Activity tab") && past.contains("한 일") && past.contains("only when you answer in Korean"),
          "prompt: how earlier work went is looked up first, what an app said is read off the screen, and only then the Activity tab")
    let truth = ArisAgentPrompt.screenWhenShown
    check(truth.contains("only when an image of it came with the request") && truth.contains("display") && truth.contains("desktop see --app"),
          "prompt: the sealed brain may look at an app's window on any display")
    let cursor = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: Data([1]), badge: nil, app: nil, title: "화면 1/2")
    let second = ArisTurnImage(kind: .cursor, name: "screen-2.png", format: .png, data: Data([1]), badge: nil, app: nil, title: "화면 2/2")
    let two = ArisAgentPrompt.images([cursor, second], focus: .screen) ?? ""
    let single = ArisAgentPrompt.images([cursor], focus: .screen) ?? ""
    check(two.contains("screen-N.png") && two.contains("another display") && !single.contains("screen-N.png") && single.contains("cursor-screen.png"),
          "prompt: several displays are named as such; one display is as before")
    let everything = [open, gated, api, ArisAgentPrompt.sealed(tools: tools), truth, two, rule]
    check(everything.allSatisfy { !$0.contains("only this screen") && !$0.contains("이 화면뿐") && !$0.contains("can only see") },
          "prompt: no line says Aris sees only one screen")
}

// MARK: - Thinking: a normal turn Sonnet at medium, a look-up turn Opus at high

private func lookFirstThinkingTests() {
    typealias T = ArisThinking
    for words in ["인터넷에 올려서 마케팅하는 거 어떻게 됐는지 보고서 간단하게 써줘", "마케팅 어떻게 됐어", "Aris 진행 상황 알려줘", "클로드 코드 세션 읽어줘",
                  "how's the marketing going", "give me a status report", "look into why the build failed", "이거 좀 알아봐 줘"] {
        check(T.looksUp(words, task: false, images: false, screenText: false, handsFree: false), "thinking: \"\(words)\" has to be looked up")
    }
    for words in ["프랑스 수도가 어디야", "고마워", "엄마한테 문자 보내줘 늦는다고", "what's 12 times 7", "타이머 5분 맞춰줘", "내일 일정 알려줘"] {
        check(!T.looksUp(words, task: false, images: false, screenText: false, handsFree: false), "thinking: \"\(words)\" is a normal turn")
    }
    check(T.looksUp("이거 뭐야", task: false, images: true, screenText: false, handsFree: false)
          && T.looksUp("요약해줘", task: false, images: false, screenText: true, handsFree: false)
          && T.looksUp("정리해 놔", task: true, images: false, screenText: false, handsFree: false)
          && !T.looksUp("마케팅 어떻게 됐어", task: false, images: false, screenText: false, handsFree: true),
          "thinking: the screen to judge and a background job look things up; a hands-free turn never does")
    check(T.tier(.quick, looksUp: false) == .quick && T.tier(.work, looksUp: true) == .deep && T.tier(.quick, looksUp: true) == .deep
          && T.tier(.critical, looksUp: true) == .critical,
          "thinking: a look-up turn runs deep; a careful one stays critical for the gate")
    check(T.model(.claude, tier: .quick) == "sonnet" && T.model(.claude, tier: .work) == "sonnet" && T.model(.claude, tier: .deep) == "opus"
          && T.model(.claude, tier: .critical) == "opus",
          "thinking: Claude is Sonnet for a normal turn (never Haiku), Opus for a look-up or careful one")
    check(T.claudeEffort(model: "sonnet") == "medium" && T.claudeEffort(model: "opus") == "high" && T.claudeEffort(model: "haiku") == "low",
          "thinking: Sonnet thinks at medium, Opus at high")
    check(T.codexEffort(tier: .quick) == "medium" && T.codexEffort(tier: .work) == "medium" && T.codexEffort(tier: .deep) == "high"
          && T.codexEffort(tier: .critical) == "high",
          "thinking: Codex at medium normally, high for a look-up or careful turn")
    check(T.model(.codex, tier: .deep) == ArisBrain.codex.model(tier: .work) && T.model(.antigravity, tier: .quick) == ArisBrain.antigravity.model(tier: .quick),
          "thinking: the other brains keep their models (a deep turn uses the strong one)")
    // The one-shot helpers keep their own low effort and quick model.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisAgent")
    let helpers = ["ArisJudge.swift", "ArisDictationRoutes.swift", "ArisSealedOneShot.swift", "ArisReadJudge.swift", "ArisDesktopVision.swift"]
    let low = helpers.allSatisfy { ((try? String(contentsOf: root.appendingPathComponent($0).standardized, encoding: .utf8)) ?? "").contains("\"--effort\", \"low\"") }
    let driver = (try? String(contentsOf: root.appendingPathComponent("ArisBrainDriver.swift").standardized, encoding: .utf8)) ?? ""
    let codex = (try? String(contentsOf: root.appendingPathComponent("ArisCodexDriver.swift").standardized, encoding: .utf8)) ?? ""
    check(low && driver.contains("\"--effort\", ArisThinking.claudeEffort(model: model)") && !driver.contains("\"--model\", model, \"--effort\", \"low\"")
          && codex.contains("\"effort\": ArisThinking.codexEffort(tier: tier)"),
          "thinking: conversation runners take the policy; judges, dictation routes and one-shots stay on low")
    check(T.saysAtOnce(T.lookingStatus) && !T.saysAtOnce("화면 보는 중") && T.lookingLine(korean: true) == "알아볼게요."
          && ArisUIWords.status(T.lookingStatus, english: true) == "Looking into it",
          "thinking: a look-up turn's first status says \"알아볼게요\" at once")
}

// MARK: - Who looks into the user's own work

private func lookFirstReachTests() {
    typealias T = ArisThinking
    check(T.handOffBrain { _ in true } == .claude, "reach: Claude Code first when it is ready")
    check(T.handOffBrain { $0 != .claude } == .codex && T.handOffBrain { $0 == .antigravity || $0 == .api } == .antigravity
          && T.handOffBrain { $0 == .api } == .api && T.handOffBrain { _ in false } == nil,
          "reach: without Claude Code, Codex, then Antigravity, then the API model; none: Aris digs itself")
    let claude = T.reachLine(handTo: .claude), codex = T.reachLine(handTo: .codex), none = T.reachLine(handTo: nil)
    check(claude.contains("\"brain\": \"claude\"") && claude.contains("\"assignee\": \"clone\"") && codex.contains("\"brain\": \"codex\"")
          && codex.contains("Claude Code isn't"),
          "reach: the line names the AI to hand it to")
    check(none.contains("dig yourself") && none.contains("find") && none.contains("memory") && none.contains("one specific question")
          && none.contains("인스타그램") && none.contains("더 알려 주세요") && !none.contains("\"brain\""),
          "reach: with none ready Aris digs itself, then asks one specific question naming its guess")
}
