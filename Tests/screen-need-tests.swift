// Screen on demand (the owner, 2026-11-10): a turn captures the screen only when its words point at it. A plain question
// starts no capture (no ScreenCaptureKit call, no macOS notice, no recording dot) and goes out without an image, so
// the brain that answers it is not sealed for that. Fakes only: the real screen is never captured here.
import Foundation

func runScreenNeedTests() {
    screenNeedTableTests()
    screenNeedDecisionTests()
    MainActor.assumeIsolated { screenNeedCaptureTests() }
    screenNeedBrainTests()
    screenNeedWiringTests()
    screenNeedSettingsTests()
}

// MARK: - The table: which sentences need the screen

/// The user points at the screen with their words: the turn carries the screenshot.
private let screenNeedYes: [String] = [
    // The user's own examples
    "이거 뭐야", "이 메일 답장 써줘", "화면 봐 줘", "여기 뭐야", "지금 보이는 거 설명해줘",
    "what is this", "what's this error", "what's on my screen", "look at this", "what am I looking at",
    // Korean: the pointing words
    "이거 요약해줘", "이걸 영어로 바꿔줘", "이건 왜 안 돼", "이게 무슨 뜻이야", "이것 좀 봐줘", "요거 번역해줘",
    "저거 뭐야", "저게 뭐야", "이분 누구야", "이 사람 링크드인 찾아줘", "이 페이지 뭐에 관한 거야",
    "이 문장 정중하게 고쳐줘", "이 코드 왜 에러 나", "이 에러 왜 나는 거야", "이 오류 어떻게 고쳐", "이 문제 풀어줘",
    "이 단어 무슨 뜻이야", "이 그래프 설명해줘", "이 영상 요약해줘", "이거 말고 저거 요약해줘",
    // Korean: asking Aris to look
    "화면 좀 봐봐", "내 화면 보여?", "지금 화면에 뭐 있어", "화면에 뜬 에러 뭐야", "화면에 있는 거 요약해줘",
    "화면 보고 알려줘", "화면 읽어줘", "지금 화면 뭐야", "여기 뭐라고 써 있어", "여기 뭐가 틀렸어",
    "여기서 뭐 눌러야 돼", "여기 왜 빨간 줄이 떠", "지금 보고 있는 페이지 요약해줘", "내가 보고 있는 거 뭐야",
    "방금 뜬 알림 뭐야", "마우스 가리키는 거 뭐야", "선택한 부분 번역해줘", "화면에서 뭘 눌러야 해", "커서 있는 곳 뭐야",
    // English
    "summarize this", "translate this page", "reply to this email", "what does the selected text mean", "is this right",
    "What Is This Error", "what is on the screen right now", "look at my screen", "can you see my screen",
    "read the screen", "describe the screen", "explain what I'm looking at", "what do you see",
    "what does it say here", "what's wrong here", "what do I click here", "summarize these emails",
    "summarize the current page", "summarize my current tab", "what's under my cursor",
    // Written without the space, and "this" with a comma that is only a pause
    "이글 요약해줘", "이문서 번역해줘", "summarize this, please", "who wrote this",
]

/// Everything else: no capture, no image.
private let screenNeedNo: [String] = [
    // The user's own examples
    "이 노래 누구 거야", "이번 주 일정 알려줘", "this week's schedule", "play this song again", "이거 말고 타이머 맞춰줘",
    // Korean
    "프랑스 수도가 어디야", "오늘 날씨 어때", "이 노래 제목 뭐야", "이 곡 좋다", "이거 말고 다른 노래 틀어줘",
    "이건 아니고 내일 일정 알려줘", "타이머 5분", "다음 곡", "화면 밝기 올려줘", "화면 꺼줘", "화면 잠가줘",
    "화면 녹화 시작해줘", "화면 보호기 켜줘", "오른쪽 화면에 표로 보여줘", "여기 띄워줘", "여기로 창 옮겨줘",
    "여기 날씨 어때", "여기 근처 맛집 알려줘", "내일 회의 몇 시야", "그거 다시 말해줘", "이따가 알려줘",
    "이 시간에 뭐 해", "엄마한테 문자 보내줘", "음악 틀어줘", "메모해 줘, 우유 사기", "지금 몇 시야",
    "이번 달 지출 정리해줘", "볼륨 올려줘", "스크린샷 찍어줘", "이거 PNG로 바꿔줘", "아까 복사한 링크 열어줘",
    "화면 캡처 단축키 뭐야", "큰 화면으로 봐도 돼?", "우리 아이 문제 좀 봐줘", "우리 아이 사진 찾아줘", "그건 내일이거든",
    "타이머 삼십이분", "여기까지 할게", "고마워", "됐어",
    // English
    "what is the capital of france", "what's the weather today", "what's on this weekend", "skip this track",
    "what time is it", "set a timer for 5 minutes", "not this, set a timer for ten minutes",
    "remind me this friday to call mom", "this morning's news", "turn the screen brightness up", "lock the screen",
    "turn off the screen", "take a screenshot", "share my screen with the team", "what's the weather here",
    "tell me a joke", "send a message to mom", "how was this year for the stock market", "put it on the left screen",
    "convert this to png", "check my screen time", "turn on screen sharing", "open document budget", "open a new tab",
    "can you see my calendar for tomorrow", "see you later", "thanks",
    // A word that only looks like a pointing one, the song in the ears, and what the user is about to say
    "한화 이글스 경기 결과", "이글스 오늘 이겼어?", "이창호 9단 기보 찾아줘", "who sings this", "skip this",
    "remember this: the door code is 4812", "note this down, the meeting moved to 3",
]

private func screenNeedTableTests() {
    for said in screenNeedYes {
        check(ArisScreenNeed.pointsAtScreen(said), "screen need: \"\(said)\" points at the screen, so the turn carries it")
    }
    for said in screenNeedNo {
        check(!ArisScreenNeed.pointsAtScreen(said), "screen need: \"\(said)\" is not about the screen, so nothing is captured")
    }
    check(screenNeedYes.count >= 60 && screenNeedNo.count >= 60, "screen need: the table holds at least 60 sentences each way")
    // The look at the selection and the front window's text keeps its own, narrower words: nothing new is read there.
    for said in ["화면 봐 줘", "여기 뭐야", "지금 보이는 거 설명해줘", "what am I looking at", "what do you see"] {
        check(!ArisDeixis.refersToScreen(said) && ArisDeixis.asksToLook(said),
              "screen need: \"\(said)\" asks Aris to look (the screenshot), without the pointing words that read the selection")
    }
    check(!ArisDeixis.refersToScreen("이거 말고 타이머 맞춰줘") && !ArisDeixis.refersToScreen("not this, set a timer")
          && ArisDeixis.refersToScreen("이거 말고 저거 요약해줘"),
          "deixis: \"이거 말고 …\" sets this aside, so it points at nothing (unless something else in it does)")
    check(!ArisDeixis.refersToScreen("remind me this friday") && !ArisDeixis.refersToScreen("add it to this playlist")
          && ArisDeixis.refersToScreen("what's this timeline about"),
          "deixis: \"this friday\" is a day and \"this playlist\" music; \"this timeline\" still points (whole words only)")
}

// MARK: - The decision: the setting, a drawing, files

private func screenNeedDecisionTests() {
    check(ArisScreenNeed.captures(words: "이거 뭐야", setting: true, drew: false)
          && ArisScreenNeed.captures(words: "what's on my screen", setting: true, drew: false),
          "screen need: words that point at the screen capture it")
    check(!ArisScreenNeed.captures(words: "프랑스 수도가 어디야", setting: true, drew: false)
          && !ArisScreenNeed.captures(words: "what is the capital of france", setting: true, drew: false)
          && !ArisScreenNeed.captures(words: "", setting: true, drew: false),
          "screen need: a plain question captures nothing")
    check(!ArisScreenNeed.captures(words: "이거 뭐야", setting: false, drew: false)
          && !ArisScreenNeed.captures(words: "화면 봐 줘", setting: false, drew: false),
          "screen need: with \"질문할 때 화면 같이 보기\" off nothing is ever captured for a turn")
    check(!ArisScreenNeed.captures(words: "이거 [img 1] 뭐야", setting: true, drew: true),
          "screen need: a turn the user drew on sends its shots, never a screenshot as well")
    let shells = URL(fileURLWithPath: "/tmp/shells.pdf")
    let withFiles = ArisPendingFiles().adding([shells]).taking(into: "이거 요약해줘").text
    let lookWithFiles = ArisPendingFiles().adding([shells]).taking(into: "여기 뭐라고 써 있어").text
    check(ArisPendingFiles.carriesFiles(withFiles) && !ArisScreenNeed.captures(words: withFiles, setting: true, drew: false)
          && !ArisScreenNeed.captures(words: lookWithFiles, setting: true, drew: false),
          "screen need: with files given to Aris, \"이거\" and \"여기\" are the files, never the screen")
}

// MARK: - The capture: nothing at the press, and only for words that point

@MainActor private func screenNeedCaptureTests() {
    func spin(_ seconds: Double = 3, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    }
    var shots = 0, enabled = true, granted = true, grantReads = 0, claims = 0
    var notices: [ArisScreenPermissionNotice.Line] = []
    var shotDelay: Duration = .zero
    let png = Data([0x89, 0x50, 0x4E, 0x47]) + Data(repeating: 7, count: 5000)
    func make(keep: Duration = .seconds(30)) -> ArisTurnCapture {
        ArisTurnCapture(dependencies: .init(
            shoot: { shots += 1; try? await Task.sleep(for: shotDelay); return ArisTurnCapture.Shot(png: png, ms: 42, retried: false) },
            enabled: { enabled }, permission: { grantReads += 1; return granted },
            nextNotice: { claims += 1; return claims == 1 ? .permission : nil }, notify: { notices.append($0) },
            waitAtSend: .milliseconds(300), keepFor: keep))
    }
    func take(_ capture: ArisTurnCapture) -> ArisTurnCapture.Taken? {
        var got: ArisTurnCapture.Taken??
        Task { @MainActor in got = .some(await capture.image()) }
        spin { got != nil }
        return got ?? nil
    }

    // A plain question, in Korean and in English, spoken or typed: nothing at all happens.
    for question in ["프랑스 수도가 어디야", "what is the capital of france"] {
        let plain = make()
        plain.began(notchShowsAnswer: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15)) // the key is held: nothing is due at any moment of it
        let started = plain.heard(question)
        let asked = Date()
        let taken = take(plain)
        check(!started && taken == nil && shots == 0 && grantReads == 0 && claims == 0 && notices.isEmpty && !plain.attempted
              && Date().timeIntervalSince(asked) < 0.2,
              "turn capture: \"\(question)\" starts no capture, reads no grant, shows no permission line, and its ask waits for nothing")
    }

    // Words that point at the screen: the shot is taken once they are known, never when the key goes down.
    let pointed = make()
    pointed.began(notchShowsAnswer: false)
    RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    let atPress = shots
    let started = pointed.heard("what's on my screen")
    let attempted = pointed.attempted
    spin { shots == 1 }
    _ = pointed.heard("what's on my screen")
    let taken = take(pointed)
    check(atPress == 0 && started && attempted && shots == 1 && taken?.image.kind == .cursor && taken?.image.name == "cursor-screen.png"
          && taken?.image.data == png && taken?.focus == .screen && taken?.ms == 42 && taken?.bytes == png.count && take(pointed) == nil,
          "turn capture: \"what's on my screen\" shoots once the words are known (nothing at the press), once, and hands the image out once")

    let overAnswer = make()
    overAnswer.began(notchShowsAnswer: true)
    _ = overAnswer.heard("이거 더 짧게 해줘")
    let closed = make()
    closed.began(notchShowsAnswer: false)
    _ = closed.heard("이거 뭐야")
    check(take(overAnswer)?.focus == .panel && take(closed)?.focus == .screen && shots == 3,
          "turn capture: \"이거\" over the open notch's answer most likely means that answer (the image is the fallback); else the screen")

    shotDelay = .seconds(2)
    let slow = make()
    slow.began(notchShowsAnswer: false)
    _ = slow.heard("화면 봐 줘")
    let sent = Date()
    let slowTaken = take(slow)
    let waited = Date().timeIntervalSince(sent)
    shotDelay = .zero
    check(slowTaken == nil && waited < 1.0, "turn capture: a capture still running at send is waited for only its limit, then the turn goes without it")

    // Barge-in: a new turn begins while the old one still waits for its screenshot.
    shotDelay = .milliseconds(150)
    let barge = make()
    barge.began(notchShowsAnswer: false)
    _ = barge.heard("이거 뭐야")
    var oldTaken: ArisTurnCapture.Taken??
    Task { @MainActor in oldTaken = .some(await barge.image()) }
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    barge.began(notchShowsAnswer: false)
    _ = barge.heard("이 에러 뭐야")
    spin { oldTaken != nil }
    let newTaken = take(barge)
    shotDelay = .zero
    check(oldTaken == .some(nil) && newTaken != nil, "turn capture: barge-in: the old turn's wait gets nothing and leaves the new turn's shot alone")

    let expiring = make(keep: .milliseconds(100))
    expiring.began(notchShowsAnswer: false)
    let expiringStarted = expiring.heard("이거 뭐야")
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let expiredTaken = take(expiring)
    let cancelled = make()
    cancelled.began(notchShowsAnswer: false)
    let cancelledStarted = cancelled.heard("이거 뭐야")
    cancelled.cancel()
    let cancelledTaken = take(cancelled)
    check(expiringStarted && expiredTaken == nil && cancelledStarted && cancelledTaken == nil && !cancelled.attempted,
          "turn capture: a shot nobody collects is dropped after its time, and a turn that ends drops its shot")

    // A drawing: its shots go as before, and stand in for the screenshot (none is taken).
    let circled = ArisTurnImage(kind: .gesture, name: "gesture-screenshot-1.jpg", format: .jpeg, data: Data([2]), badge: 1, app: nil, title: nil)
    let drew = make()
    let beforeDrawing = shots
    drew.began(notchShowsAnswer: false)
    drew.attachGesture([circled])
    let shotForDrawing = drew.heard("이거 [img 1] 뭐야")
    let firstTake = drew.takeGesture(), secondTake = drew.takeGesture()
    drew.attachGesture([circled])
    drew.began(notchShowsAnswer: false) // the next turn begins before the old one asked
    let staleTake = drew.takeGesture()
    check(!shotForDrawing && shots == beforeDrawing && !drew.attempted && firstTake == [circled] && secondTake.isEmpty && staleTake.isEmpty,
          "turn capture: a turn the user drew on hands out its circled shots once, never to the next turn, and takes no screenshot")

    // The off switch.
    enabled = false
    let readsBefore = grantReads
    let off = make()
    off.began(notchShowsAnswer: false)
    let offStarted = off.heard("이거 뭐야")
    check(!offStarted && take(off) == nil && shots == beforeDrawing && grantReads == readsBefore && claims == 0 && !off.attempted,
          "turn capture: with the setting off even \"이거 뭐야\" captures nothing and asks for no permission")
    enabled = true

    // No Screen Recording grant: the line shows only for a turn that wanted the screen, once per launch.
    granted = false
    let plainUngranted = make()
    plainUngranted.began(notchShowsAnswer: false)
    _ = plainUngranted.heard("오늘 날씨 어때")
    let claimsAfterPlain = claims
    let ungranted = make()
    ungranted.began(notchShowsAnswer: false)
    let ungrantedStarted = ungranted.heard("화면 봐 줘")
    let ungrantedTaken = take(ungranted)
    let again = make()
    again.began(notchShowsAnswer: false)
    _ = again.heard("이거 뭐야")
    granted = true
    check(claimsAfterPlain == 0 && !ungrantedStarted && ungrantedTaken == nil && notices == [.permission] && claims == 2
          && shots == beforeDrawing && !ungranted.attempted && take(again) == nil,
          "turn capture: without the grant a plain question shows no permission line; \"화면 봐 줘\" shows it once per launch, captures nothing, and the turn goes on")

    // The turn log: a turn that needed no screen has no capture entry at all (never a failed one).
    var stats = ArisTurnStats(startedAt: .now)
    stats.heard("프랑스 수도가 어디야", path: "brain:codex", tier: "quick", at: .now)
    let quiet = stats.line(outcome: "ok", at: .now)
    stats.captured(source: "cursorDisplay", ok: false, bytes: 0, ms: 0, retried: false)
    let failed = stats.line(outcome: "ok", at: .now)["capture"] as? [String: Any]
    check(quiet["capture"] == nil && failed?["ok"] as? Bool == false,
          "stats: a turn that needed no screen logs no capture; only a capture that was tried and gave nothing logs a failed one")
}

// MARK: - The brains: told the truth, and still able to look for themselves

private func screenNeedBrainTests() {
    let tools = "/Users/p/.config/aris/aris-tools", home = "/Users/p"
    let cursor = ArisTurnImage(kind: .cursor, name: "cursor-screen.png", format: .png, data: Data([1]), badge: nil, app: nil, title: nil)

    // A plain question carries no image, so it is not outside content and the brain the owner chose answers it, unsealed.
    for brain in [ArisBrain.codex, .claude, .antigravity, .api] {
        let route = ArisImageRouting.route(requested: brain, images: [], screenText: false, claudeInstalled: true, api: .init(vision: true))
        check(route.brain == brain && !route.sealed && !route.sendsImages && route.note == nil && route.status == nil,
              "routing: a plain question (no image) is answered by \(brain.rawValue) itself, unsealed")
    }
    var conversation = ArisScreenConversation()
    let plainSaw = conversation.turn(fresh: true, images: [])
    check(!plainSaw && !ArisImageRouting.untrusted(screenText: false, flagged: false, images: [])
          && ArisImageRouting.taint(screenText: false, flagged: false, screenConversation: plainSaw) == .none
          && ArisImageRouting.dispatchPolicy(outsideText: false, screenSeen: plainSaw, task: false) == .init(teammates: true, vouch: true),
          "routing: a turn without an image is not outside content: no taint, and it may hand out and vouch as the user's own")

    // A turn that does carry the screen is outside content exactly as before, and its conversation stays that way.
    let sawNow = conversation.turn(fresh: false, images: [cursor])
    let sawLater = conversation.turn(fresh: false, images: [])
    let sealedClaude = ArisImageRouting.route(requested: .claude, images: [cursor], screenText: false, claudeInstalled: true)
    let laterClaude = ArisImageRouting.route(requested: .claude, images: [], screenText: false, claudeInstalled: true, screenConversation: sawLater)
    check(sawNow && sawLater && ArisImageRouting.untrusted(screenText: false, flagged: false, images: [cursor])
          && ArisImageRouting.untrusted(screenText: false, flagged: false, images: [], screenConversation: sawLater)
          && ArisImageRouting.taint(screenText: false, flagged: false, screenConversation: sawNow) == .screenSeen
          && sealedClaude.sealed && sealedClaude.sendsImages && laterClaude.sealed && !laterClaude.sendsImages
          && !ArisImageRouting.dispatchPolicy(outsideText: false, screenSeen: sawNow, task: false).vouch,
          "routing: a turn with the screenshot is outside content as before, and the conversation stays sealed after it, image or not")

    // What each brain is told: nothing about images when none came; the sealed one, that it sees only what came now.
    check(ArisAgentPrompt.images([], focus: .screen) == nil && ArisAgentPrompt.images([cursor], focus: .screen)?.contains("cursor-screen.png") == true,
          "prompt: the <images> section comes only with images")
    let plainPrompt = ArisAgentStream.prompt(request: "프랑스 수도가 어디야", context: nil, memory: nil)
    check(!plainPrompt.contains("<images>") && !plainPrompt.contains("<screen>"), "prompt: a plain question's prompt says nothing about the screen")
    let truth = ArisAgentPrompt.screenWhenShown
    check(truth.contains("only when an image of it came with the request") && truth.contains("desktop") && truth.contains("화면 봐 줘")
          && !truth.contains("what you see") && !truth.contains("looking at the screen"),
          "prompt: the truth line: the screen is seen only when an image came; else look with the desktop look or ask for \"화면 봐 줘\"")
    check(ArisAgentPrompt.sealed(tools: tools).contains(truth) && ArisAgentPrompt.sealed(tools: tools, functions: true).contains(truth)
          && ArisAgentPrompt.sealed(tools: tools, task: true).contains(truth),
          "prompt: the sealed brain of a conversation that saw the screen is told it sees it only when an image came")
    check(!ArisAgentPrompt.sealed(tools: tools, handsFree: true).contains(truth)
          && !ArisAgentPrompt.system(tools: tools, gated: true).contains(truth) && !ArisAgentPrompt.system(tools: tools, reads: true).contains(truth),
          "prompt: brains that are told nothing about seeing the screen (hands-free, unsealed) get no line about it")

    // A brain that decides it needs the screen can still ask for it itself.
    let gated = ArisAgentPrompt.system(tools: tools, gated: true), functions = ArisAgentPrompt.system(tools: tools, gated: true, functions: true)
    check(gated.contains("`\(tools) screen`") && gated.contains("`\(tools) selection`") && functions.contains("`\(tools) screen`"),
          "prompt: the gated brains (Codex, an API brain) are still told how to read the screen themselves (selection, tab, screen)")
    check(ArisRiskPolicy.risk(of: .shell("\(tools) screen"), tools: tools, home: home) == .auto
          && ArisRiskPolicy.bringsInUntrusted(.shell("\(tools) screen"), tools: tools, home: home),
          "tools: `screen` still runs at once for a gated brain, and what it reads is outside text as before")
    check(ArisTurnGate.staysLocal(["screen"]) && !ArisClaudeDriver.openRefused.contains("screen"),
          "tools: the open Claude may still run `screen` behind its turn gate")
    let everyPrompt = [gated, ArisAgentPrompt.system(tools: tools, reads: true), ArisAgentPrompt.system(tools: tools, gated: false),
                       ArisAgentPrompt.sealed(tools: tools), ArisAgentPrompt.sealed(tools: tools, handsFree: true)]
    check(everyPrompt.allSatisfy { $0.contains("desktop see --app") } && functions.contains("desktop_see(app")
          && ArisSealedTools.allows(["desktop", "see", "--app", "Safari", "--ocr"]),
          "tools: every brain, sealed or not, can still look at an app's window with the desktop look")
}

// MARK: - The wiring: who starts the capture

private func screenNeedSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

private func screenNeedWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris").standardized
    var sources: [String: String] = [:]
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
    for file in files where file.pathExtension == "swift" {
        if let text = try? String(contentsOf: file, encoding: .utf8) { sources[file.lastPathComponent] = text }
    }
    check(sources.count > 300, "wiring: the app's sources were read (\(sources.count))")
    // The per-turn screenshot has one caller, and one place that starts it: when the words are known.
    let shooters = sources.filter { $0.value.contains("cursorDisplayShot()") }.keys.sorted()
    check(shooters == ["ArisController+See.swift", "ArisScreenCapture.swift"], "wiring: only the turn's capture takes the cursor screenshot (\(shooters))")
    let starters = sources.filter { $0.value.contains("ArisTurnCapture.shared.heard(") }.keys.sorted()
    check(starters == ["ArisController+See.swift"], "wiring: the capture starts in one place (\(starters))")
    let stats = screenNeedSource("Aris/private/Aris/ArisController+Stats.swift")
    check(stats.contains("if path.hasPrefix(\"brain:\") || path == \"screen\" { seeWords(text) } else { seeEnded() }"),
          "wiring: the capture is decided when the words are final, and only on a turn that goes to the AI")
    // Nothing captures when the key goes down, comes up, a wake word is heard or a typed request is sent.
    let old = ["seePressed()", "seeReleased()", "seeWoke()", ".pressed(notchShowsAnswer", ".released()", ".woke(notchShowsAnswer", ".typed(notchShowsAnswer"]
    let stale = sources.filter { name, text in old.contains { text.contains($0) } }.keys.sorted()
    check(stale.isEmpty, "wiring: no press, release, wake or submit starts a capture any more (\(stale))")
    let see = screenNeedSource("Aris/private/Aris/ArisController+See.swift")
    check(see.contains("if attempted || taken != nil {"), "wiring: the turn log gets a capture entry only when a capture was tried")
    let controller = screenNeedSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("if !images.isEmpty {\n            // Defence in depth: the agent says so too, but an image turn is outside content from here on.\n            untrustedTurn = true\n            screenConversation = true"),
          "wiring: only a turn that really carries an image is outside content in the app")
}

// MARK: - The setting says what happens

private func screenNeedSettingsTests() {
    var snapshot = ArisSettingsSnapshot()
    snapshot.standingLoaded = true
    let sees = ArisSettingsBuilder.sections(.control, snapshot).flatMap(\.rows).first { $0.id == "control.sees" }
    let desc = sees?.desc ?? ""
    check(sees?.title == "질문할 때 화면 같이 보기" && sees?.control == .toggle(.seesScreen, snapshot.seesScreen),
          "setting: \"질문할 때 화면 같이 보기\" is still the switch")
    let seeingNote = ArisSettingsBuilder.sections(.control, snapshot).first { $0.id == "control.seeing" }?.note ?? ""
    let circleRow = ArisSettingsBuilder.sections(.control, snapshot).flatMap(\.rows).first { $0.id == "control.circle" }
    check(desc.contains("화면을 가리켜") && desc.contains("때만") && seeingNote.contains("찍지 않고") && !desc.contains("말하거나 입력할 때 마우스가 있는 화면을")
          && circleRow?.desc == "\(snapshot.circleHint).",
          "setting: its line says the screen is looked at only when the user points at it, the small line under the card that no other question captures it, and the circle's row keeps the hint (settings pick 5-B)")
    let entry = ArisSettingsIndex.entry("control.sees")
    check(entry?.title == "질문할 때 화면 같이 보기" && entry?.keywords.contains("화면 봐 줘") == true && entry?.keywords.contains("가리킬 때만") == true
          && ArisSettingsIndex.search("가리킬 때만").first?.id == "control.sees",
          "setting: the search index finds it by what it does now")
}
