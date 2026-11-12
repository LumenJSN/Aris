// Tests for the ad's scripted demos (ArisPreview `team-demo`, `dictation-demo:<text>`, `circle-demo`, each with `:off`;
// ArisAdDemoScript, 2026-11-08): the states parse, the scripts say what the ad needs within the real views' limits,
// the circle's scripted pen goes through the real gesture controller to a sealed loop with nothing captured, and
// `:off`, side-close and quit stop every demo. That no demo reaches Reminders, Calendar, the history, the activity
// log, the teammates file, memory, aris-agent, the microphone or the screen is ad-demo checks in side-demo-lint.py.
import AppKit
import Foundation

func runAdDemoTests() {
    adDemoParseTests()
    adDemoBoardTests()
    adDemoTeamTests()
    adDemoSeatTests()
    adDemoDictationTests()
    MainActor.assumeIsolated { adDemoCircleTests() }
    adDemoMaskTests()
    adDemoStoresNothingTests()
    adDemoDisplayTests()
    MainActor.assumeIsolated { adDemoCaptureTests() }
}

private func adDemoDisplayTests() {
    typealias D = ArisAdDemoDisplay
    let dell = D.Screen(notch: false, builtIn: false, selected: true, main: true)
    let mac = D.Screen(notch: true, builtIn: true, selected: false, main: false)
    check(D.pick([dell, mac]) == 1 && D.pick([mac, dell]) == 0, "ad demo display: the built-in notch display, even with the DELL picked and in front")
    check(D.pick([dell, D.Screen(notch: false, builtIn: true, selected: false, main: false)]) == 1, "ad demo display: a closed-lid-less built-in before the pick")
    check(D.pick([D.Screen(notch: false, builtIn: false, selected: false, main: true), dell]) == 1 && D.pick([]) == nil,
          "ad demo display: without a built-in, the user's pick; none without displays")
}

/// The demo's windows show in screen recordings (`.readOnly`) and the real ones never do (`.none`); all of them sit
/// above the ad session's borderless `.floating` backdrop. Panels are made but never ordered in.
@MainActor private func adDemoCaptureTests() {
    _ = NSApplication.shared
    check(ArisCaptureSharing.type(demo: true) == .readOnly && ArisCaptureSharing.type(demo: false) == .none,
          "capture: a demo's windows are recorded, the real ones never")
    let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
    let realInk = ArisInkOverlay(display: 1, screenFrame: frame, screen: nil, headless: false, now: { 0 })
    let demoInk = ArisInkOverlay(display: 1, screenFrame: frame, screen: nil, headless: false, now: { 0 }, shownInCaptures: true)
    check(realInk.sharingType == NSWindow.SharingType.none && demoInk.sharingType == .readOnly && !realInk.isShown && !demoInk.isShown,
          "capture: the real ink stays out of recordings, the demo's ink is in them")
    check(demoInk.level.map { ArisCaptureSharing.drawsAbove($0) } == true, "capture: the ink draws above a .floating window")
    let realHint = ArisGestureHint(icon: .image(nil), headless: false, now: { 0 })
    let demoHint = ArisGestureHint(icon: .image(nil), headless: false, now: { 0 }, shownInCaptures: true)
    check(realHint.sharingType == NSWindow.SharingType.none && demoHint.sharingType == .readOnly
          && demoHint.level.map { ArisCaptureSharing.drawsAbove($0) } == true, "capture: the hint chip likewise")
    let env = ArisGestureController.Environment(now: { 0 }, pointer: { .zero }, buttonDown: { false }, screens: { [] }, nsScreen: { _ in nil },
                                                hintIcon: { .image(nil) }, headless: true)
    check(!env.shownInCaptures, "capture: a gesture session is out of recordings unless a demo says otherwise")
    let panels = ArisOverlayPanels()
    panels.rebuild()
    let real = panels.sharingTypes
    panels.shownInCaptures = true
    let shown = panels.sharingTypes
    panels.rebuild()
    let rebuilt = panels.sharingTypes
    panels.shownInCaptures = false
    let restored = panels.sharingTypes
    panels.tearDown()
    check(real.allSatisfy { $0 == .none } && shown.allSatisfy { $0 == .readOnly } && rebuilt.allSatisfy { $0 == .readOnly }
          && restored.allSatisfy { $0 == .none } && ArisCaptureSharing.drawsAbove(ArisOverlayPanels.level),
          "capture: the teammates' panels show while the demo's are out (rebuilt too), back to never after; above .floating")
    check(!ArisCaptureSharing.drawsAbove(.normal) && !ArisCaptureSharing.drawsAbove(.floating), "capture: the level check means above")
}

private func adDemoParseTests() {
    typealias C = ArisAdDemoCommand
    check(C.parse("team-demo") == .team && C.parse(" TEAM-DEMO ") == .team && C.parse("team-demo:off") == .off(.team)
          && C.parse("team-demo:OFF") == .off(.team) && C.parse("team-demo:on") == nil && C.parse("team-demo2") == nil,
          "ad demo: team-demo and team-demo:off, nothing else")
    check(C.parse("dictation-demo:내일 회의 자료 보내 줘") == .dictation("내일 회의 자료 보내 줘")
          && C.parse("dictation-demo:  내일   회의 ") == .dictation("내일 회의") && C.parse("dictation-demo:off") == .off(.dictation)
          && C.parse("dictation-demo") == nil && C.parse("dictation-demo:") == nil && C.parse("dictation-demo:\u{202E}\u{200B}") == nil,
          "ad demo: dictation-demo:<text> keeps the words (spaces tidied, invisible letters dropped); empty is nothing")
    check(C.parse("dictation-demo:Hello: World") == .dictation("Hello: World"), "ad demo: a colon inside the dictated words stays")
    if case .dictation(let long) = C.parse("dictation-demo:" + String(repeating: "가", count: 900)) {
        check(long.count == C.maxText, "ad demo: dictated words are bounded")
    } else { check(false, "ad demo: long dictated words still parse") }
    check(C.parse("circle-demo") == .circle(nil) && C.parse("circle-demo:off") == .off(.circle)
          && C.parse("circle-demo:100, 200, 520, 300") == .circle(CGRect(x: 100, y: 200, width: 520, height: 300))
          && C.parse("circle-demo:1,2,3") == nil && C.parse("circle-demo:0,0,10,300") == nil && C.parse("circle-demo:-5,0,300,300") == nil
          && C.parse("circle-demo:0,0,nan,300") == nil && C.parse("circle-demo:0,0,99999,300") == nil,
          "ad demo: circle-demo[:x,y,w,h] with a sane rect only")
    check(C.parse("side-demo:on") == nil && C.parse("side-close") == nil && C.parse("answer") == nil,
          "ad demo: the other preview states aren't the ad demos'")
    check(C.parse("team-demo")?.kind == .team && C.parse("dictation-demo:x")?.kind == .dictation && C.parse("circle-demo:off")?.kind == .circle,
          "ad demo: each state names its demo")
}

private func adDemoBoardTests() {
    var board = ArisAdDemoBoard()
    check(board.running.isEmpty && board.stopAll().isEmpty, "ad demo board: a launch runs none")
    check(board.start(.team).isEmpty && board.running == [.team], "ad demo board: team starts")
    check(board.start(.dictation) == [.team] && board.running == [.dictation], "ad demo board: one at a time (dictation stops team)")
    check(board.start(.dictation) == [.dictation] && board.running == [.dictation], "ad demo board: starting again starts over")
    check(board.stop(.dictation) && !board.stop(.dictation) && board.running.isEmpty, "ad demo board: :off stops its own, once")
    _ = board.start(.circle)
    check(!board.stop(.team) && board.running == [.circle], "ad demo board: another demo's :off leaves it")
    check(board.stopAll() == [.circle] && board.running.isEmpty && board.stopAll().isEmpty,
          "ad demo board: side-close and quit stop everything")
}

private func adDemoTeamTests() {
    typealias S = ArisTeamDemoScript
    let cues = S.cues()
    check(zip(cues, cues.dropFirst()).allSatisfy { $0.at <= $1.at }, "team demo: cues in time order")
    let heard = cues.compactMap { if case .hear(let w) = $0.step { $0.at > 0 ? w : nil } else { nil } }
    check(heard.last == "Claude Code는 실크로드 소개글을 쓰고, 코디는 슬라이드 개요를 정리해 줘" && heard.count > 3
          && zip(heard, heard.dropFirst()).allSatisfy { $1.hasPrefix($0) }, "team demo: the prompt card's words, word by word")
    check(S.answer == "Claude Code하고 코디가 맡았어요, 끝나면 알려줄게요.", "team demo: Aris hands out with the real line")
    check(S.jobs.count == 2 && S.jobs.allSatisfy { (3...4).contains($0.steps.count) }, "team demo: two jobs, 3-4 steps each")
    for job in S.jobs {
        for step in job.steps {
            check(ArisBubbleText.text(for: .running(step: step), korean: true) == step && ArisSpeech.language(of: step) == "ko-KR",
                  "team demo: \"\(step)\" fits the real bubble uncut")
        }
        check(ArisSpeech.language(of: job.title) == "ko-KR", "team demo: \(job.title) speaks Korean in its bubble")
    }
    check(S.jobs[0].teammate == ArisTeammate.claudeCodeId && S.jobs[1].teammate == S.kodi.id, "team demo: Claude Code's job, then 코디's")
    check(S.kodi.id.hasPrefix(ArisSideDemoSamples.idPrefix) && ArisTeammate.isValidId(S.kodi.id) && S.kodi.name == "코디"
          && S.kodi.look.type == "clover", "team demo: 코디 is the demo's own (its id marked), with the clover face")
    func at(_ match: (ArisTeamDemoStep) -> Bool) -> [TimeInterval] { cues.filter { match($0.step) }.map(\.at) }
    let think = at { $0 == .think }, dispatch = at { $0 == .dispatch }, close = at { $0 == .closeTurn }, clear = at { $0 == .clear }
    let finishes = at { if case .finish = $0 { true } else { false } }
    check(think.count == 1 && dispatch.count == 1 && close.count == 1 && clear.count == 1 && finishes.count == 2
          && think[0] > 0 && dispatch[0] > think[0] && close[0] > dispatch[0] && finishes.allSatisfy { $0 > close[0] }
          && clear[0] >= finishes.max()! + 8 && cues.last?.step == .clear,
          "team demo: think, hand out, the notch closes, both jobs end, the jobs leave last")
    for index in S.jobs.indices {
        let steps = cues.filter { if case .progress(index, _) = $0.step { true } else { false } }
        let done = cues.first { $0.step == .finish(job: index) }!
        check(steps.count == S.jobs[index].steps.count && steps.allSatisfy { $0.at > dispatch[0] && $0.at < done.at },
              "team demo: job \(index)'s steps run between its start and its end")
    }
    // The pill reads the real lines off jobs in the demo's states.
    func job(_ state: ArisJobState, _ n: Int) -> ArisJob {
        ArisJob(id: UUID(), title: S.jobs[n].title, prompt: "", assignee: .teammate(S.jobs[n].teammate), cwd: nil, appHint: nil,
                target: .window(pid: ArisTeamDemoSeats.fixedPid, windowNumber: ArisTeamDemoSeats.fixedNumberBase + n), state: state, created: Date())
    }
    check(ArisStatusLine.pillText(jobs: [job(.running(step: S.jobs[0].steps[0]), 0), job(.running(step: S.jobs[1].steps[0]), 1)], korean: true) == "2개 작업 중",
          "team demo: the pill says 2개 작업 중")
    let both = [job(.done(S.jobs[0].result), 0), job(.done(S.jobs[1].result), 1)]
    check(ArisStatusLine.pillText(jobs: both, korean: true) == nil && ArisPillFinish.showsDone(jobs: both, justFinished: true),
          "team demo: then the pill's own 끝났어요")
}

private func adDemoSeatTests() {
    typealias T = ArisTeamDemoSeats
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    func w(_ pid: Int32, _ n: Int, _ bundle: String?, _ frame: CGRect) -> T.Window { .init(pid: pid, number: n, bundleId: bundle, frame: frame) }
    let editA = w(10, 101, "com.apple.TextEdit", CGRect(x: 120, y: 200, width: 600, height: 420))
    let editB = w(10, 102, "com.apple.TextEdit", CGRect(x: 800, y: 220, width: 600, height: 420))
    let safari = w(20, 201, "com.apple.Safari", CGRect(x: 0, y: 30, width: 1512, height: 900))
    let own = w(99, 301, "com.lumenjsn.aris", CGRect(x: 0, y: 0, width: 1512, height: 982))
    let tiny = w(30, 401, "com.apple.finder", CGRect(x: 10, y: 10, width: 120, height: 80))
    let elsewhere = w(40, 501, "com.apple.Notes", CGRect(x: 1600, y: 0, width: 800, height: 600))
    check(T.pick([safari, editA, own, editB], screen: screen, own: 99) == [.window(pid: 10, number: 101), .window(pid: 10, number: 102)],
          "team seats: two TextEdit windows first, whatever is in front of them")
    check(T.pick([safari, editA], screen: screen, own: 99) == [.window(pid: 10, number: 101), .window(pid: 20, number: 201)],
          "team seats: then another app's window")
    let fixed = T.fixedFrames(screen: screen)
    check(T.pick([own, tiny, elsewhere], screen: screen, own: 99)
          == [.fixed(number: T.fixedNumberBase, frame: fixed[0]), .fixed(number: T.fixedNumberBase + 1, frame: fixed[1])],
          "team seats: no window to sit on (Aris's own, a tiny one, one on another display): two fixed points")
    check(T.pick([editA], screen: screen, own: 99) == [.window(pid: 10, number: 101), .fixed(number: T.fixedNumberBase, frame: fixed[0])],
          "team seats: one window and one fixed point")
    check(fixed.allSatisfy { screen.contains($0) } && fixed[0].maxX < fixed[1].minX, "team seats: the fixed points sit apart on the display")
    check(T.isFixed(pid: T.fixedPid, number: T.fixedNumberBase + 1) && !T.isFixed(pid: 10, number: T.fixedNumberBase)
          && !T.isFixed(pid: T.fixedPid, number: 101), "team seats: a stand-in window is told from a real one")
    // The real perch lands on the stand-in window's top edge, inside the display.
    let cg = fixed[0]
    let point = ArisPerchGeometry.perchPoint(windowCG: cg, screens: [screen], visibleFrames: [CGRect(x: 0, y: 0, width: 1512, height: 950)],
                                             primaryHeight: screen.height, size: ArisCharacterDirector.perchSize,
                                             titleBarHeight: ArisPerchGeometry.titleBarHeight)
    check(point.map { screen.contains($0) } == true, "team seats: a fixed point gets a real perch")
}

private func adDemoDictationTests() {
    let text = "내일 오후 세 시 회의 자료, 어 팀장님께 먼저 보내 줘."
    let cues = ArisDictationDemoScript.cues(text)
    let heard = cues.compactMap { if case .hear(let w) = $0.step { w } else { nil } }
    let words = text.split(separator: " ").map(String.init)
    check(heard.count == words.count && heard.last == text && zip(heard, heard.dropFirst()).allSatisfy { $1.hasPrefix($0) },
          "dictation demo: the words come one by one, all of them")
    let times = cues.filter { if case .hear = $0.step { true } else { false } }.map(\.at)
    check(zip(times, times.dropFirst()).allSatisfy { (0.24...0.86).contains($1 - $0) }, "dictation demo: at a natural pace")
    let tail = cues.suffix(3).map(\.step)
    check(cues.first?.step == .listen && tail == [.clean(text), .typed(ArisDictationCleaner.clean(text, endStop: false)), .close]
          && zip(cues, cues.dropFirst()).allSatisfy { $0.at < $1.at }, "dictation demo: listen, words, tidy, typed, the card goes")
    if case .typed(let typed) = tail[1] { check(!typed.contains("어 "), "dictation demo: the filler is tidied away as the real card does") }
}

@MainActor private func adDemoCircleTests() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let rect = ArisCircleDemoScript.defaultRect(display: screen.size)
    check(abs(rect.midX - 756) < 1 && abs(rect.midY - 491) < 1 && rect.width == 520, "circle demo: the default rect is centred")
    let path = ArisCirclePath(rect: rect, screen: screen)
    var clock = 0.0
    let capture = ArisAdDemoCapture()
    let controller = ArisGestureController(capturer: capture, environment: .init(
        now: { clock }, pointer: { path.point(at: clock / 1000) }, buttonDown: { false },
        screens: { [ArisGestureScreen(id: 1, frame: screen)] }, nsScreen: { _ in nil }, hintIcon: { .image(nil) }, headless: true))
    controller.keyDown()
    controller.tap()
    var drawn = 0
    var inkFrom: Double?, sealedAt: Double?
    while clock < ArisCircleDemoScript.endAt * 1000 {
        clock += 8
        controller.pumpTick()
        drawn = max(drawn, controller.surfaceCount)
        if inkFrom == nil, controller.surfaceCount > 0 { inkFrom = clock / 1000 }
        if sealedAt == nil, !capture.kept.isEmpty { sealedAt = clock / 1000 }
    }
    print(String(format: "     circle demo timing: ink from %.2f s, loop sealed at %.2f s (fades by %.2f s), ink gone at %.2f s",
                 inkFrom ?? -1, sealedAt ?? -1, (sealedAt ?? 0) + 0.6, ArisCircleDemoScript.endAt))
    check((inkFrom ?? 9) < 1 && (1.5...2.4).contains(sealedAt ?? 0), "circle demo: ink starts within 1 s, the loop seals around 2 s")
    check(drawn == 1 && controller.interactiveSurfaceCount == 0, "circle demo: one click-through ink surface (it never takes a click)")
    check(capture.kept == [1], "circle demo: the scripted loop is a circle to the real detector, sealed, shot 1 (no picture taken)")
    controller.handsFreeEnd()
    check(capture.finalized && controller.isIdle, "circle demo: the session ends and leaves nothing up")
    // The loop goes round the rect.
    let loop = (0...100).map { path.loop(Double($0) / 100) }
    let inner = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
    check(loop.allSatisfy { !inner.contains($0) } && loop.map(\.x).min()! < rect.minX && loop.map(\.x).max()! > rect.maxX
          && loop.map(\.y).min()! < rect.minY && loop.map(\.y).max()! > rect.maxY, "circle demo: the loop surrounds the rect")
    let g = path.global(CGPoint(x: 10, y: 20))
    check(g == CGPoint(x: 10, y: 962), "circle demo: display points from the top left become Cocoa points")

    let cues = ArisCircleDemoScript.cues()
    let writes = cues.compactMap { if case .write(let w) = $0.step { w } else { nil } }
    check(writes.last == ArisCircleDemoScript.answer && zip(writes, writes.dropFirst()).allSatisfy { $1.hasPrefix($0) }
          && cues.contains { $0.step == .final(ArisCircleDemoScript.answer) } && cues.last?.step == .close,
          "circle demo: the answer streams in, then the whole of it, then the turn ends")
    check(cues.contains { $0.step == .hear("이거 뭐야?") } && cues.first { $0.step == .end }!.at == ArisCircleDemoScript.endAt
          && zip(cues, cues.dropFirst()).allSatisfy { $0.at <= $1.at }, "circle demo: 이거 뭐야? while drawing, then it thinks")
    check(ArisCircleDemoScript.answer.contains("주간 매출 차트") && ArisCircleDemoScript.answer.contains("8%"), "circle demo: the agreed answer")
}

private func adDemoMaskTests() {
    check(ArisUsageMask.account("user@example.com", masked: true) == "•••@•••" && ArisUsageMask.account("user@example.com", masked: false) == "user@example.com",
          "usage mask: the account only while side-demo is on")
    check(ArisUsageMask.usd(12.345, masked: true) == "$•••" && ArisUsageMask.usd(12.345, masked: false) == ArisUsageFormat.usd(12.345)
          && ArisUsageMask.peak(11.6, masked: true) == "$•••" && ArisUsageMask.peak(11.6, masked: false) == "$12",
          "usage mask: every amount, the chart's peak too")
}

/// Every demo's whole script, built and walked, touches no preference: the steps are views' state only (the files and
/// stores are side-demo-lint.py's, run.sh runs the tests under no ~/.config when ARIS_TEST_SANDBOX is set).
private func adDemoStoresNothingTests() {
    let defaults = UserDefaults.standard.dictionaryRepresentation().keys.sorted()
    var steps = 0
    steps += ArisTeamDemoScript.cues().count
    steps += ArisDictationDemoScript.cues("내일 회의 자료 보내 줘").count
    steps += ArisCircleDemoScript.cues().count
    MainActor.assumeIsolated {
        var board = ArisAdDemoBoard()
        for kind in ArisAdDemoKind.allCases { _ = board.start(kind) }
        _ = board.stopAll()
    }
    check(steps > 50 && UserDefaults.standard.dictionaryRepresentation().keys.sorted() == defaults,
          "ad demo: the scripts store nothing (no preference)")
}
