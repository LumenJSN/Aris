// Tests for the first-run setup as the owner picked it on 2026-11-11 (qa/design-1111/PICKS.md, "Onboarding"; the mockup
// qa/design-1111/onboarding-mock.html):
//  1-A  the first thing to try is "3분 타이머 맞춰 줘": the practice turn sets a real timer, and the page is done when one runs;
//  2    the permissions stay on the first page (one switch each); the page is left out only when nothing on it is to do;
//  3-A  with no AI the key field comes first, the AIs someone may already use are lines with a command, the way on is
//       "AI 없이 계속"; a saved key is tried the way Settings tries one;
//  4-A  the shortcut's practice and the first request are one page; where Aris can't hear, the request can be typed;
//  5-A  after the last page the notch opens with three things to try and the left side notch shows once;
//  6    one rail, its steps the pages this person sees;
//  9-A  the dictation model is asked for in one line on the dictation page, never in a card after the first turn;
//  and the permissions page's picture is never empty grey (VM run 2026-11-11, new install);
//  and, decided the same evening: the setup's × means "later", never "done for good". Only the last page finishes it.
// Everything here is pure: no window is shown, nothing is asked of macOS, no key is saved, no timer is set.
// Called from main.swift; uses its check().
import Foundation

func runOnboard2Tests() {
    onboard2PlanTests()
    onboard2WalkTests()
    onboard2RailTests()
    onboard2PracticeTests()
    onboard2TryTests()
    onboard2BrainTests()
    onboard2ModelLineTests()
    onboard2FirstTriesTests()
    onboard2PictureTests()
    onboard2LaterTests()
    onboard2WordsTests()
    onboard2WiringTests()
}

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private let onboarding = "Aris/private/Aris/Onboarding/"

private func source(_ path: String) -> String {
    (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
private func code(_ path: String) -> String {
    source(path).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

/// The part of a source file from `from` up to `to`.
private func part(_ text: String, from: String, to: String) -> String {
    guard let start = text.range(of: from) else { return "" }
    let rest = text[start.lowerBound...]
    guard let end = rest.range(of: to, range: rest.index(after: rest.startIndex)..<rest.endIndex) else { return String(rest) }
    return String(rest[..<end.lowerBound])
}

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

private typealias Page = ArisSetupPage

/// The pages one person walks through, pressing each page's own button from where the window opens.
private func walk(_ plan: ArisSetupPlan, from wanted: Page = .permissions) -> [Page] {
    var flow = ArisSetupFlow(page: plan.opening(at: wanted)), pages = [flow.page]
    while flow.next(skipping: plan.skipped) { pages.append(flow.page) }
    return pages
}

// MARK: - Picks 2, 3, 4: the pages each kind of user sees

private func onboard2PlanTests() {
    typealias Plan = ArisSetupPlan
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    var one = none, several = none
    one[.api] = true
    several[.claude] = true
    several[.codex] = true

    check(Plan.readyCount(none) == 0 && Plan.readyCount(one) == 1 && Plan.readyCount(several) == 2, "plan: the AIs set up are counted from the helper's answer")
    check(Plan.readyCount(nil) == nil && Plan.readyCount([:]) == nil && Plan.readyCount([.claude: false]) == nil,
          "plan: until the helper has answered for every AI, how many are set up is not known (never \"none\")")
    check(Plan.readyCount([.claude: true]) == 1, "plan: one that is named as set up counts at once")

    check(walk(.make(permissionsSettled: false, readyAIs: 0)) == [.permissions, .ask, .brain, .wake, .dictation],
          "a new Mac with no AI: 권한 → 눌러서 말하기 → AI 고르기 → 아리스라고 부르기 → 받아쓰기")
    check(walk(.make(permissionsSettled: false, readyAIs: 1)) == [.permissions, .ask, .wake, .dictation],
          "a new Mac with one AI: the AI page is left out (that AI answers; there is nothing to pick)")
    check(walk(.make(permissionsSettled: false, readyAIs: 3)) == [.permissions, .ask, .brain, .wake, .dictation],
          "a new Mac with several AIs: the AI page shows, to pick one")
    check(walk(.make(permissionsSettled: false, readyAIs: nil)) == [.permissions, .ask, .brain, .wake, .dictation],
          "the helper has not said which AIs are set up: the AI page shows (and says it could not check)")
    check(walk(.make(permissionsSettled: true, readyAIs: 1)) == [.ask, .wake, .dictation],
          "permissions already on, one AI: the setup opens on the try page (nothing on 권한 is left to do)")
    check(walk(.make(permissionsSettled: true, readyAIs: 0)) == [.ask, .brain, .wake, .dictation], "permissions already on, no AI: the try page, then the key")

    // A Mac with no microphone, or the microphone card put off, sees the same pages: the try page takes the request typed.
    for ready in [0, 1, 2] {
        let plan = Plan.make(permissionsSettled: false, readyAIs: ready)
        check(plan.pages.contains(.ask) && plan.pages.first == .permissions, "no microphone changes no page (\(ready) AIs): the try page shows and can be typed on")
    }

    // A replay (Settings › 처음 안내 다시 보기) starts at the intro and then walks the same plan, from what is true now.
    check(ArisOnboarding.launch(seen: true, later: false, replay: true, loginItem: false, lastResume: nil, resumes: 0, quitAt: nil, now: Date()) == .intro
          && !ArisOnboarding.resumes(later: true, replay: true), "a replay starts at the intro, never at a saved page")
    check(walk(.make(permissionsSettled: true, readyAIs: 2), from: .permissions) == [.ask, .brain, .wake, .dictation],
          "a replay on a Mac that is set up, several AIs: 눌러서 말하기 → AI 고르기 → 아리스라고 부르기 → 받아쓰기")
    check(walk(.make(permissionsSettled: true, readyAIs: 1), from: .permissions) == [.ask, .wake, .dictation], "a replay with one AI: three pages")

    // Put off for later, the setup comes back at the page it was on, if that page still shows.
    let plan = Plan.make(permissionsSettled: false, readyAIs: 1)
    check(plan.opening(at: .wake) == .wake && plan.opening(at: .brain) == .wake && plan.opening(at: .permissions) == .permissions,
          "a saved page that is left out now opens at the next one that shows")
    check(Plan.make(permissionsSettled: true, readyAIs: 0).opening(at: .permissions) == .ask, "a saved 권한 with nothing left on it opens at the try page")
    check(Page.resume(saved: 0) == .permissions && Page.resume(saved: 1) == .ask && Page.resume(saved: 2) == .brain && Page.resume(saved: 4) == .wake
          && Page.resume(saved: 5) == .dictation, "the numbers a setup put off for later saved still mean their pages")
    check(Page.resume(saved: 3) == .ask && Page.resume(saved: 9) == .permissions && Page.resume(saved: -1) == .permissions,
          "the old question page resumes at the one page it shares with the shortcut now; anything unknown starts at 권한")

    check(Plan.everyPage.pages == Page.allCases && Plan.everyPage.skipped.isEmpty, "every page: the whole list, nothing left out")
    check(plan.skipped == [.brain] && Plan.make(permissionsSettled: true, readyAIs: 1).skipped == [.permissions, .brain], "what a plan leaves out is what the flow steps over")
    check(plan.step(.permissions) == (1, 4) && plan.step(.ask) == (2, 4) && plan.step(.dictation) == (4, 4) && Plan.everyPage.step(.wake) == (4, 5),
          "VoiceOver's step count is of the pages this person sees")
}

// MARK: - What is learned after the window opened; back and forth

private func onboard2WalkTests() {
    typealias Plan = ArisSetupPlan
    // The helper answers a moment after the window opened (it was installed seconds ago): the AI page goes while it is ahead.
    let unknown = Plan.make(permissionsSettled: false, readyAIs: nil)
    check(unknown.learning(readyAIs: 1, at: .permissions).pages == [.permissions, .ask, .wake, .dictation]
          && unknown.learning(readyAIs: 1, at: .ask).pages == [.permissions, .ask, .wake, .dictation],
          "the helper says one AI is set up while the AI page is still ahead: the page is left out")
    check(unknown.learning(readyAIs: 0, at: .ask) == unknown && unknown.learning(readyAIs: nil, at: .ask) == unknown, "nothing new about the AIs: the plan stays")
    // A key saved on the AI page makes one AI ready: the page being looked at never disappears, and going back finds it.
    let empty = Plan.make(permissionsSettled: false, readyAIs: 0)
    check(empty.learning(readyAIs: 1, at: .brain) == empty && empty.learning(readyAIs: 1, at: .wake) == empty && empty.learning(readyAIs: 1, at: .dictation) == empty,
          "a key saved on the AI page (now one AI) changes nothing: a page reached or passed stays in the plan")
    let single = Plan.make(permissionsSettled: false, readyAIs: 1)
    check(single.learning(readyAIs: 0, at: .ask).pages.contains(.brain), "the one AI went away before the AI page was reached: the page comes back")
    check(single.learning(readyAIs: 0, at: .wake) == single, "after the AI page's place was passed it is not put back behind the user")
    check(Plan.make(permissionsSettled: true, readyAIs: nil).learning(readyAIs: 1, at: .ask).pages == [.ask, .wake, .dictation],
          "the permissions page that was left out stays out while the plan learns")

    // Back steps over what is left out, and never past the first page shown.
    var flow = ArisSetupFlow(page: .wake)
    flow.back(skipping: single.skipped)
    check(flow.page == .ask, "뒤로 from the wake word page goes to the try page when the AI page is left out")
    flow.back(skipping: single.skipped)
    check(flow.page == .permissions && !flow.backShown, "and then to 권한, where there is no 뒤로")
    var settled = ArisSetupFlow(page: .wake)
    let noPerms = Plan.make(permissionsSettled: true, readyAIs: 1)
    settled.back(skipping: noPerms.skipped)
    check(settled.page == .ask, "with 권한 left out, 뒤로 stops at the try page")
    var last = ArisSetupFlow(page: .dictation)
    check(!last.next(skipping: single.skipped) && last.finished, "마치기 on the last page finishes")
}

// MARK: - Pick 6: one rail, its steps the pages shown

private func onboard2RailTests() {
    typealias Plan = ArisSetupPlan
    typealias M = ArisRailMetrics
    // No jump: from one page to the next the rail always moves one equal share, whoever the user is.
    let plans: [(String, Plan)] = [("no AI", .make(permissionsSettled: false, readyAIs: 0)), ("one AI", .make(permissionsSettled: false, readyAIs: 1)),
                                   ("several AIs", .make(permissionsSettled: false, readyAIs: 2)), ("permissions on, one AI", .make(permissionsSettled: true, readyAIs: 1)),
                                   ("permissions on, no AI", .make(permissionsSettled: true, readyAIs: 0))]
    for (name, plan) in plans {
        var flow = ArisSetupFlow(page: plan.opening(at: .permissions)), marks = [flow.progress(granted: [:], shown: plan.pages)]
        while flow.next(skipping: plan.skipped) { marks.append(flow.progress(granted: [:], shown: plan.pages)) }
        let share = 1 / Double(plan.pages.count)
        check(marks.count == plan.pages.count && marks.enumerated().allSatisfy { near($0.element, Double($0.offset) * share) },
              "rail (\(name)): each page starts one equal share further (\(plan.pages.count) pages), so a page left out never makes it jump")
        check(near(flow.progress(granted: [:], shown: plan.pages), 1), "rail (\(name)): finished, it is full")
    }
    // The old way divided by every page: with the AI page left out it would have jumped two shares at once.
    let single = Plan.make(permissionsSettled: false, readyAIs: 1)
    var jump = ArisSetupFlow(page: .ask)
    let before = jump.progress(granted: [:], shown: single.pages)
    jump.next(skipping: single.skipped)
    check(near(jump.progress(granted: [:], shown: single.pages) - before, 0.25), "rail: over a page left out it still moves exactly one share")

    // Within a page: the permission cards by thirds, the try page's share once its request is done.
    var perms = ArisSetupFlow()
    perms.begin(granted: [:])
    check(near(perms.progress(granted: [:], shown: single.pages), 0), "rail: nothing decided, it is empty")
    check(near(perms.progress(granted: [.mic: true], shown: single.pages), 0.25 / 3) && near(perms.progress(granted: [.mic: true, .accessibility: true], shown: single.pages), 0.5 / 3),
          "rail: each permission decided moves it a third of the page's share")
    let asking = ArisSetupFlow(page: .ask)
    check(near(asking.progress(granted: [:], shown: single.pages, tryDone: false), 0.25) && near(asking.progress(granted: [:], shown: single.pages, tryDone: true), 0.5),
          "rail: the first request really done fills the try page's share")
    check(near(ArisSetupFlow(page: .wake).progress(granted: [:], shown: single.pages, tryDone: true), 0.5), "rail: a done try adds nothing on another page")

    // The rail's look: its size, gradients, shadows, motion and fade.
    check(M.height == 11 && M.inset == 24, "rail: 11 points high, inset 24")
    check(M.track.map(\.hex) == [0xfbfcfd, 0xeceef1, 0xf6f7f8] && M.track.map(\.at) == [0, 0.54, 1], "rail: the track's gradient, #fbfcfd → #eceef1 at 54% → #f6f7f8")
    check(M.lip.hex == 0x0f172a && M.lip.alpha == 0.07 && M.lip.y == 1 && M.lip.blur == 2 && M.shine.alpha == 0.94 && M.shine.y == 1,
          "rail: the track's two inset shadows, rgba(15,23,42,.07) 0 1px 2px and white .94 along the bottom")
    check(M.fill.map(\.hex) == [0x1684e5, 0x3d9ded, 0x72b7ee, 0xb6d7ef, 0xedf3f7, 0x9fc7eb, 0x2b8de5] && M.fill.map(\.at) == [0, 0.21, 0.41, 0.59, 0.73, 0.87, 1]
          && M.fillDegrees == 96, "rail: the fill, blue to silver and back at 96°, its seven stops")
    check(M.widthSeconds == 0.5 && M.widthCurve == (0.4, 0, 0.2, 1) && M.opacitySeconds == 0.18, "rail: its width moves over 500 ms on (.4, 0, .2, 1), its opacity over 180 ms")
    let mask = M.mask(width: 200, complete: false)
    check(mask.count == 4 && mask[0].alpha == 1 && near(mask[1].at, 1 - 48.0 / 200) && mask[1].alpha == 1 && near(mask[2].at, 1 - 27.0 / 200) && mask[2].alpha == 0.72
          && mask[3].alpha == 0 && mask[3].at == 1, "rail: the fill fades over its leading 48 points (.72 at 27 from the end)")
    check(M.mask(width: 30, complete: false).allSatisfy { $0.at >= 0 && $0.at <= 1 }, "rail: a fill shorter than its fade keeps its stops in range")
    check(M.mask(width: 1032, complete: true).map(\.alpha) == [1, 1], "rail: full, the fade drops (no mask)")
    let flat = M.gradientLine(width: 200, height: 11, degrees: 90), down = M.gradientLine(width: 200, height: 11, degrees: 180)
    check(near(flat.start.x, 0) && near(flat.start.y, 0.5) && near(flat.end.x, 1) && near(flat.end.y, 0.5), "rail: CSS's 90° is left to right across the middle")
    check(near(down.start.x, 0.5) && near(down.start.y, 0) && near(down.end.x, 0.5) && near(down.end.y, 1), "rail: CSS's 180° is top to bottom")
    let line = M.gradientLine(width: 200, height: 11)
    let dx = (line.end.x - line.start.x) * 200, dy = (line.end.y - line.start.y) * 11
    check(near(atan2(dx, -dy) * 180 / .pi, 96, 1e-6) && near((dx * dx + dy * dy).squareRoot(), 200 * sin(96 * .pi / 180) + 11 * abs(cos(96 * .pi / 180)), 1e-6),
          "rail: the fill's line is CSS's 96° line, as long as the box's corners reach along it")

    let rail = code(onboarding + "ArisOnboardingRail.swift")
    check(rail.contains("model.flow.progress(granted: model.grants, shown: guide.plan.pages, tryDone: guide.askAnswered)"), "rail: it is drawn from the pages this person sees")
    check(!rail.contains("Text(") && !rail.contains("Image(") && rail.contains("M.fill.map") && rail.contains("M.gradientLine("),
          "rail: no number, no step name, no picture: the fill is drawn from its stops")
    check(rail.contains("guide.reduced ? nil :"), "rail: Reduce Motion changes it at once")
    check(rail.contains("ArisOnboardingCopy.progress(step.number, step.count)") && code(onboarding + "ArisOnboardingWindow.swift").contains("ArisSetupRail(guide: guide, model: model, palette: palette)"),
          "rail: VoiceOver hears the step among the pages shown")
}

// MARK: - Pick 1-A: the first thing to try is a timer the app sets itself

private func onboard2PracticeTests() {
    typealias P = ArisOnboardingPractice
    let three = P.Question.timer(.timer(seconds: 180, focus: false))
    check(ArisSetupTry.line(english: false) == "3분 타이머 맞춰 줘" && ArisSetupTry.line(english: true) == "Set a 3 minute timer", "pick 1-A: the page's request, in both languages")
    check(P.question(ArisSetupTry.line(english: false)) == three && P.question(ArisSetupTry.line(english: true)) == three,
          "pick 1-A: the request the page shows is a three-minute timer to the practice turn, in both languages")
    check(P.question("3분 타이머 맞춰줘") == three && P.question("set a three minute timer") == three && P.question("타이머 3분") == three,
          "pick 1-A: said a little differently it is the same timer")
    check(P.answersAlone(ArisSetupTry.line(english: false)) && P.answersAlone(ArisSetupTry.line(english: true)), "pick 1-A: it needs no AI")
    check(P.question("타이머 꺼 줘") == .timer(.cancelTimer) && P.question("cancel the timer") == .timer(.cancelTimer) && P.question("타이머 잠깐 멈춰") == .timer(.pauseTimer),
          "pick 1-A: the timer just set can be stopped or paused by voice too")
    // Only a plain timer of Aris's own: a focus session, a question about timers, and every other act stay out.
    check(P.question("25분 집중") == .other && P.question("뽀모도로 시작해") == .other, "pick 1-A: a focus session is more than the practice does")
    check(P.question("5분 타이머 맞춰야 할까?") == .other, "pick 1-A: a question about a timer sets none")
    for action in ["*sad music*", "노래 틀어줘", "play some music", "볼륨 올려", "사파리 열어", "할 일에 우유 추가", "엄마한테 문자 보내줘", "delete my files", ""] {
        check(P.question(action) == .other, "BUG-31 still holds: the practice does nothing with “\(action)”")
    }
    check(P.question("지금 몇 시야?") == .time && P.question("What time is it?") == .time && P.question("내일 오후 일정 뭐 있어?") == .calendar(day: 1, part: .afternoon),
          "pick 1-A: the time and the calendar are still answered")
    check(P.answersOnly(korean: true).contains("타이머") && P.answersOnly(korean: false).contains("timers") && !P.answersOnly(korean: true).contains("일정"),
          "the line for anything else says what the practice does now: timers and the time (no promise about the calendar)")

    typealias T = ArisSetupTry
    check(T.outcome(of: three, timerRunning: true) == .done, "pick 1-A: the page is done when a timer really runs after the request")
    check(T.outcome(of: three, timerRunning: false) == nil, "pick 1-A: a timer request that left no timer running does not finish the page")
    check(T.outcome(of: .timer(.cancelTimer), timerRunning: false) == nil, "a timer stopped is neither done nor a miss")
    check(T.outcome(of: .time, timerRunning: false) == .done && T.outcome(of: .date, timerRunning: false) == .done
          && T.outcome(of: .calendar(day: 0, part: .wholeDay), timerRunning: false) == .done, "pick 4-A: a real answer finishes the page too")
    check(T.outcome(of: .other, timerRunning: false) == .notUnderstood && T.outcome(of: .other, timerRunning: true) == .notUnderstood,
          "the line that says the practice does nothing else is not an answer, even with a timer left from before")
}

// MARK: - Pick 4-A: one page for the shortcut and the first request; typed where Aris can't hear

private func onboard2TryTests() {
    typealias T = ArisSetupTry
    check(ArisOnboardingTalk.mode(phase: .setup, page: .ask) == .practice && Page.allCases.filter { ArisOnboardingTalk.mode(phase: .setup, page: $0) == .practice } == [.ask],
          "pick 4-A: on the one try page the talk key really listens, as a practice turn; on every other page it is a real turn")
    check(ArisOnboardingTalk.mode(phase: .finish, page: .ask) == .turn && ArisOnboardingTalk.mode(phase: .closed, page: .ask) == .turn, "after the setup the key is a real turn again")

    check(T.hearing(micGranted: true, hasMicrophone: true, lastFailure: nil) == .can, "the microphone is there and allowed: Aris can hear")
    check(T.hearing(micGranted: true, hasMicrophone: false, lastFailure: nil) == .noMicrophone && T.hearing(micGranted: false, hasMicrophone: false, lastFailure: "x") == .noMicrophone,
          "a Mac with no microphone: that comes first, whatever else is true")
    check(T.hearing(micGranted: false, hasMicrophone: true, lastFailure: nil) == .notAllowed, "the microphone card put off: not allowed")
    check(T.hearing(micGranted: true, hasMicrophone: true, lastFailure: "The speech recognition model is still getting ready.") == .failed("The speech recognition model is still getting ready."),
          "a press that could not start listening: its sentence is kept")
    for hearing in [T.Hearing.noMicrophone, .notAllowed, .failed("x")] {
        check(T.typedOffered(hearing) && T.button(done: false, hearing: hearing) == .send, "where Aris can't hear (\(hearing)) the request can be typed and sent")
    }
    check(!T.typedOffered(.can) && T.button(done: false, hearing: .can) == .hold, "where it can, the page's button is hold-to-talk")
    check(T.button(done: true, hearing: .can) == .next && T.button(done: true, hearing: .noMicrophone) == .next, "once the request is done the button is 계속")

    for english in [true, false] {
        let noMic = T.sentence(.noMicrophone, english: english) ?? ""
        check(noMic.hasPrefix(ArisListenStart.line(.noMicrophone, english: english)) && noMic.hasSuffix(ArisSetupWords.tryTypeInstead(english: english)),
              "no microphone: the page says the line every other place says, then that typing works (\(english ? "en" : "ko"))")
        check(T.sentence(.notAllowed, english: english) == ArisSetupWords.tryNotAllowed(english: english) && T.sentence(.can, english: english) == nil,
              "the microphone not allowed has its own sentence; nothing is said when Aris can hear (\(english ? "en" : "ko"))")
        check(T.sentence(.failed("왜 안 됐는지."), english: english)?.hasPrefix("왜 안 됐는지.") == true, "a failed start is said in the notch's own sentence (\(english ? "en" : "ko"))")
    }
    check(ArisSetupWords.tryTypeInstead(english: true).contains("type") && ArisSetupWords.tryTypeInstead(english: false).contains("글로"), "typing is offered in words")

    check(T.failure(failed: true, reply: "마이크를 찾을 수 없어요.") == "마이크를 찾을 수 없어요." && T.failure(failed: false, reply: "3분 타이머 맞췄어요.") == nil
          && T.failure(failed: true, reply: "") == nil, "only a turn that failed, with something said, leaves a sentence on the page")
    check(T.failure(failed: true, reply: ArisPermissionWords.ready(english: true)) == nil && T.failure(failed: true, reply: ArisPermissionWords.ready(english: false)) == nil,
          "\"Ready. Press ⌥Space and talk.\" (the microphone was just allowed) is not a failure")

    check(T.lit(words: 4, heard: "3분 타이머", listening: true, done: false) == 2 && T.lit(words: 4, heard: "3분 타이머 맞춰 줘 지금", listening: true, done: false) == 4,
          "the request lights word by word as it is heard, never past its end")
    check(T.lit(words: 4, heard: "3분 타이머", listening: false, done: false) == 0 && T.lit(words: 4, heard: "", listening: false, done: true) == 4,
          "nothing is lit when Aris is not listening; all of it once the request is done (typed too)")

    check(T.note(done: false, lastOutcome: nil, changedKey: false, hearing: .can) == .hold && T.note(done: false, lastOutcome: nil, changedKey: true, hearing: .can) == .changed,
          "the page's one quiet line: what letting go does; where the key is changed after 아니요, 키를 바꿀게요")
    check(T.note(done: false, lastOutcome: .notUnderstood, changedKey: true, hearing: .can) == .again && T.note(done: true, lastOutcome: .notUnderstood, changedKey: true, hearing: .can) == .done,
          "something else was said: try the line as it is; done wins over everything")
    check(T.note(done: false, lastOutcome: nil, changedKey: false, hearing: .noMicrophone) == nil, "where the request is typed there is no talk of letting go")
    check(T.advanceAfter > 1 && T.advanceAfter <= 3, "the page moves on by itself a moment after it worked (long enough to read, short enough not to wait)")
}

// MARK: - Pick 3-A: no AI on this Mac

private func onboard2BrainTests() {
    typealias R = ArisOnboardingBrainRows
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    var keyed = none, claude = none
    keyed[.api] = true
    claude[.claude] = true
    check(R.layout(ready: none, startedEmpty: false) == .keyFirst, "pick 3-A: no AI on this Mac: the key field comes first")
    check(R.layout(ready: claude, startedEmpty: false) == .pick && R.layout(ready: nil, startedEmpty: false) == .pick, "some AI set up, or not known yet: the list to pick from")
    check(R.layout(ready: keyed, startedEmpty: true) == .keyFirst && R.layout(ready: claude, startedEmpty: true) == .keyFirst,
          "pick 3-A: a key saved (or an AI found) on the key-first page changes its row in place; the page does not turn into another")
    check(R.terminalBrains == [.claude, .codex, .antigravity] && R.terminalBrains.compactMap(R.command) == ["claude", "codex login", "agy"],
          "pick 3-A: under the key, the AIs someone may already use, Claude first, each with its Terminal command")
    check(R.command(.api) == nil, "the key itself has no command")
    check(R.onward(ready: none) == .withoutAI && R.onward(ready: keyed) == .next && R.onward(ready: claude) == .next && R.onward(ready: nil) == .next,
          "pick 3-A: the way on says what it does: “AI 없이 계속” only when the helper said none is set up")
    check(ArisSetupWords.brainWithoutAI(english: false) == "AI 없이 계속" && ArisSetupWords.brainWithoutAI(english: true) == "Continue without an AI", "that button's words")
    check(ArisSetupWords.brainKeyTitle(anyReady: false, english: false) == "아직 답할 AI가 없어요" && ArisSetupWords.brainKeyTitle(anyReady: true, english: false) != ArisSetupWords.brainKeyTitle(anyReady: false, english: false)
          && ArisSetupWords.brainKeyTitle(anyReady: true, english: true) != ArisSetupWords.brainKeyTitle(anyReady: false, english: true),
          "the heading says no AI can answer only while that is true")

    // The key is checked as Settings › AI services checks one: empty is refused before it is sent; the helper's own
    // check after the save is trouble only when it failed with something to say.
    check(R.keyProblem("   \n") == .empty && R.keyProblem(" sk-abc ") == nil, "a key that is only spaces is not sent")
    check(R.keyTestTrouble(ok: true, message: "") == nil && R.keyTestTrouble(ok: true, message: "테스트 통과") == nil && R.keyTestTrouble(ok: false, message: "") == nil,
          "the helper's check passed, or could not say anything: nothing is said")
    check(R.keyTestTrouble(ok: false, message: "401: 키가 맞지 않아요") == "401: 키가 맞지 않아요", "a key that did not answer is said now, with the helper's reason")
    check(R.canAnswer(ready: keyed, keyTrouble: false) && !R.canAnswer(ready: keyed, keyTrouble: true) && R.canAnswer(ready: claude, keyTrouble: true)
          && !R.canAnswer(ready: none, keyTrouble: false) && !R.canAnswer(ready: nil, keyTrouble: false),
          "the page says an AI can answer only when one can: never for a key whose check just failed")
    check(R.onward(ready: keyed, keyTrouble: true) == .withoutAI && R.onward(ready: claude, keyTrouble: true) == .next && R.onward(ready: nil, keyTrouble: false) == .next
          && R.onward(ready: keyed, keyTrouble: false) == .next, "with only a key that did not answer, the way on is still “AI 없이 계속”")
    let troubled = R.shown(R.rows(ready: keyed, chosen: "api"), keyTrouble: true)
    check(troubled.first { $0.brain == .api }?.state == .ready && R.shown(R.rows(ready: keyed, chosen: "api"), keyTrouble: false).first { $0.brain == .api }?.state == .chosen,
          "a key that is saved but did not answer is shown as saved, without the check of the one that answers")
    check(ArisSetupWords.keyNotWorking("401", english: false).contains("401") && ArisSetupWords.keyNotWorking("401", english: false).contains("저장")
          && ArisSetupWords.keyNotWorking("401", english: true).contains("saved") && !ArisSetupWords.keyNotWorking("키가 맞지 않아요", english: true).contains("키"),
          "the line says the key was saved and did not answer; the helper's Korean reason is not shown to an English reader")
    check(ArisSetupWords.keyRefused("키 모양이 아니에요", english: false) == "키 모양이 아니에요" && ArisSetupWords.keyRefused("키 모양이 아니에요", english: true) == ArisOnboardingCopy.brainKeyFailed,
          "a refused key: the helper's own words in Korean, the guide's line otherwise")

    let save = code(onboarding + "ArisOnboardingGuide+Brain.swift")
    let saved = save.range(of: "ArisAgentClient.saveAPIBrain(id: id, key: key, quick: nil, strong: nil, baseURL: nil)")?.lowerBound
    let tried = save.range(of: "ArisAgentClient.testAPIBrain(id, model: nil)")?.lowerBound
    check(saved != nil && tried != nil && saved! < tried!, "pick 3-A: the key goes to the helper (the Keychain) as Settings sends it, then is tried as Settings tries it")
    check(save.contains("ArisOnboardingBrainRows.keyTestTrouble(ok: result.ok, message: result.message)") && save.contains("self.brainKeyOpen = true")
          && save.contains("ArisBrainSetup.shared.choose(.api)"), "a key that did not answer reopens the field; one that was saved answers from then on")
    let page = code(onboarding + "ArisOnboardingBrainPage.swift")
    check(page.contains("Rows.layout(ready: setup.ready, startedEmpty: guide.brainStartedEmpty) == .keyFirst") && page.contains("ArisBrainKeyForm(guide: guide, palette: palette, takesKeyboard:"),
          "pick 3-A: the page opens on the key's form when no AI is set up")
    check(page.contains("Rows.onward(ready: setup.ready, keyTrouble: guide.brainKeyTrouble != nil) == .withoutAI") && page.contains("ArisSetupWords.brainWithoutAI()") && page.contains("ArisOnboardingCopy.brainAgain"),
          "pick 3-A: “AI 없이 계속” and 다시 확인 are on the page")
    check(page.contains("ArisSetupWords.brainCopy()") && page.contains("NSPasteboard.general.setString(command, forType: .string)"), "pick 3-A: a line's command is copied by a click")
    let form = code(onboarding + "ArisOnboardingBrainKeyForm.swift")
    check(form.contains("SecureField(") && form.contains("guide.saveBrainKey(provider: id, key: typed)") && form.contains("Rows.keyProblem(key) == nil"),
          "the key's field is a secure one, checked before it is sent, saved through the guide")
}

// MARK: - Pick 9-A: the dictation model, one line on the dictation page

private func onboard2ModelLineTests() {
    typealias L = ArisModelLine
    for english in [true, false] {
        let lang = english ? "en" : "ko"
        let offer = L.shown(state: .idle, model: .small, installed: false, english: english)
        check(offer?.action == .get && offer?.fraction == nil && offer?.detail.contains("220 MB") == true && offer?.detail.contains("Wi-Fi") == true,
              "pick 9-A: the line offers the small model with its size and that it comes over Wi-Fi only (\(lang))")
        check(L.shown(state: .idle, model: .small, installed: true, english: english) == nil, "a Mac that already has a model shows no line (\(lang))")
        let coming = L.shown(state: .running(0.37), model: .small, installed: false, english: english)
        check(coming?.action == nil && coming?.fraction == 0.37 && coming?.detail.contains("37%") == true, "pick 9-A: while it comes in, the line itself says how far it is (\(lang))")
        check(coming?.detail.contains(english ? "meanwhile" : "그동안") == true, "and that dictation works meanwhile: nothing waits for it (\(lang))")
        let waiting = L.shown(state: .waiting(0.2), model: .small, installed: false, english: english)
        check(waiting?.action == nil && waiting?.fraction == 0.2 && waiting?.detail.contains("Wi-Fi") == true, "off Wi-Fi it waits, and says for what (\(lang))")
        check(L.shown(state: .paused(0.5), model: .small, installed: false, english: english)?.action == .resume
              && L.shown(state: .failed(0.5), model: .small, installed: false, english: english)?.action == .retry, "paused: 이어 받기; failed: 다시 받기 (\(lang))")
        let done = L.shown(state: .done, model: .small, installed: true, english: english)
        check(done?.action == nil && done?.fraction == nil && done?.detail.contains(ArisSpeechModel.small.name(english: english)) == true, "in: the line says the model is ready (\(lang))")
        check(L.shown(state: .running(0.1), model: .large, installed: false, english: english)?.detail.contains(ArisSpeechModel.large.name(english: english)) == true,
              "a download begun in Settings is named as what it is (\(lang))")
        for action in [L.Action.get, .resume, .retry] { check(!ArisSetupWords.modelAction(action, english: english).isEmpty, "each button of the line has its word (\(action), \(lang))") }
    }
    check(L.offered == .small, "the line offers the small model (the large one stays in Settings)")

    let downloader = code("Aris/private/Aris/ArisModelDownloader.swift")
    check(!downloader.contains("turnEnded") && !downloader.contains("ArisController.shared.$session") && !code("Aris/private/Aris/ArisSpeechModel.swift").contains("static func offers("),
          "pick 9-A: no turn's end schedules the model card any more")
    check(downloader.components(separatedBy: "offering = true").count == 2 && part(downloader, from: "func loadFailed(", to: "// MARK: running").contains("offering = true"),
          "the card is offered only for a model on disk that would not load")
    let page = part(code(onboarding + "ArisOnboardingTryPages.swift"), from: "struct ArisDictationPage", to: "\n}\n")
    check(code(onboarding + "ArisOnboardingTryPages.swift").contains("ArisModelLineView(palette: palette, reduced: guide.reduced)") && !page.isEmpty,
          "pick 9-A: the line is on the dictation page, under the practice note's button")
    let line = code(onboarding + "ArisOnboardingModelLine.swift")
    check(line.contains("downloads.choose(ArisModelLine.offered)") && line.contains("downloads.accept()") && !line.contains("await"), "받기 starts the download and waits for nothing")

    // The dictation key is named from the key Aris watches, in one place.
    check(ArisDictationKeyName.name(keyCode: ArisDictationKey.keyCode, english: false) == "오른쪽 ⌥" && ArisDictationKeyName.name(keyCode: ArisDictationKey.keyCode, english: true) == "the right ⌥",
          "the dictation key as it is set today is named as people know it")
    check(ArisDictationKeyName.name(keyCode: 96, english: false) == "받아쓰기 키" && ArisDictationKeyName.name(keyCode: 96, english: true) == "the dictation key",
          "another key is called what it is for, never by the right ⌥'s name")
    check(ArisSetupWords.dictateLead(key: "F5", english: false).contains("F5") && ArisSetupWords.dictateLead(key: "F5", english: true).contains("F5"), "the page's sentence carries whatever the key is called")
    check(code(onboarding + "ArisOnboardingTryPages.swift").contains("Text(ArisSetupWords.dictateLead())") && !code(onboarding + "ArisOnboardingTryPages.swift").contains("ArisOnboardingCopy.dictateLead"),
          "the dictation page reads the key's name through that one lookup")
}

// MARK: - Pick 5-A: after the last page

private func onboard2FirstTriesTests() {
    typealias F = ArisFirstTriesPlan
    check(F.tries(noAI: false) == [.timer, .folder, .screen], "pick 5-A: three things to try: the timer, a folder on the desktop, what is on the screen")
    check(F.tries(noAI: true) == [.timer, .notes, .time] && F.tries(noAI: true).allSatisfy(\.needsNoAI), "on a Mac with no AI the three are ones the app does itself")
    check(!ArisFirstTry.folder.needsNoAI && !ArisFirstTry.screen.needsNoAI, "the folder and the screen need an AI, which is why they are not offered without one")
    for english in [true, false] {
        let lang = english ? "en" : "ko"
        func intent(_ item: ArisFirstTry) -> ArisIntent { let said = item.text(english: english); return ArisIntent.guarded(ArisIntent.parse(said), said: said) }
        check(intent(.timer) == .timer(seconds: 180, focus: false), "pressed, the timer is read as a three-minute timer the app sets itself (\(lang))")
        if case .openApp = intent(.notes) { check(true, "pressed, Notes is read as an app the app opens itself (\(lang))") } else { check(false, "pressed, Notes is read as an app the app opens itself (\(lang))") }
        check(intent(.time) == .tellTime, "pressed, the time is read as the time (\(lang))")
        if case .ask = intent(.folder) { check(true, "the folder goes to the AI, which asks on a card (\(lang))") } else { check(false, "the folder goes to the AI, which asks on a card (\(lang))") }
        // As the turn decides it (ArisScreenNeed): words that point at the screen, or that ask Aris to look.
        let screen = ArisFirstTry.screen.text(english: english)
        check(ArisDeixis.refersToScreen(screen) || ArisDeixis.asksToLook(screen), "the screen question is read as being about the screen (\(lang))")
        check(Set(ArisFirstTry.allCases.map { $0.text(english: english) }).count == ArisFirstTry.allCases.count, "each has its own sentence (\(lang))")
        check(F.line(name: "Alex", english: english).contains("Alex") && !F.line(name: nil, english: english).isEmpty && F.line(name: "", english: english) == F.line(name: nil, english: english),
              "the one line over them, with the name when there is one (\(lang))")
        check(F.hint(keys: "⌥ Space", english: english).contains("⌥ Space") && !F.sliverWord(english: english).isEmpty, "the hint names the talk key as it is set; the side notch has its two words (\(lang))")
    }
    check(ArisFirstTry.timer.text(english: false) == ArisSetupTry.line(english: false), "the timer offered is the one just practised")
    check(F.sliverWord(english: false) == "기록은 여기", "the left side notch's words")
    check(F.ends(turnStarted: true) && !F.ends(turnStarted: false), "the offer is over at the first request of any kind")
    check(F.closesItself(offered: true, open: true, inTurn: false, pointerOnNotch: false), "the notch Aris opened closes by itself when nobody came")
    check(!F.closesItself(offered: true, open: true, inTurn: false, pointerOnNotch: true) && !F.closesItself(offered: true, open: true, inTurn: true, pointerOnNotch: false)
          && !F.closesItself(offered: false, open: true, inTurn: false, pointerOnNotch: false) && !F.closesItself(offered: true, open: false, inTurn: false, pointerOnNotch: false),
          "never under the pointer, during a turn, once the offer is over, or when it is closed already")
    check(F.staysOpen >= 30 && F.sliverSeconds >= 3 && F.sliverSeconds <= 8, "long enough to read, not left open for good")

    typealias S = ArisOnboardingStage
    check(!S.ownsNotch(phase: .finish, realActive: false) && S.ownsNotch(phase: .setup, realActive: false) && !S.ownsNotch(phase: .closed, realActive: false),
          "pick 5-A: at the finish the notch is Aris's own again (what opens is the real one)")
    check(S.windowOut == 0.24 && S.windowOutReduced < S.windowOut, "the window leaves in 240 ms, quicker than it came")

    let tries = code(onboarding + "ArisFirstTries.swift")
    let press = part(tries, from: "func press(_ item: ArisFirstTry)", to: "func end()")
    check(press.contains("ArisController.shared.submitTyped(text)") && press.contains("end()"), "pick 5-A: a press sends the request the way typed words are sent (the normal path), and the offer is over")
    check(tries.contains("ArisSidePanels.shared.showOnce(.left, for: ArisFirstTriesPlan.sliverSeconds)") && tries.contains("host.model.open()"),
          "pick 5-A: the notch opens and the left side notch shows itself once")
    check(!tries.contains("repeatForever") && !tries.contains("UserDefaults"), "nothing in it blinks or loops, and nothing is stored")
    let setup = code(onboarding + "ArisOnboardingGuide+Setup.swift")
    let finish = part(setup, from: "func finish()", to: "\n}\n")
    check(finish.contains("ArisFirstTries.shared.begin(on: guide.notch(), noAI: ArisBrainSetup.shared.noneReady") && finish.contains("$0.close(.finished)"),
          "pick 5-A: the last page's button ends in the three things to try, then the guide is over")
    check(part(setup, from: "func reopenSetup()", to: "func finish()").contains("ArisFirstTries.shared.cancel()"), "coming back to the setup during the finish takes the offer away")
    check(code("Aris/private/Aris/Home/ArisHomeView.swift").contains("ArisFirstTriesRow(hidden: showsTurn)"), "the three are part of the open notch's home page; a turn has the notch to itself")
    let panels = code("Aris/private/Aris/Side/ArisSidePanels.swift")
    let once = part(panels, from: "func showOnce(_ edge: Edge, for seconds: TimeInterval) -> Bool", to: "var isHiddenAny")
    check(once.contains("guard !isOff(edge), !isHidden(edge), !open.contains(edge) else { return false }") && once.contains("setRevealed(edge, true)"),
          "the sliver shows itself only where there is one to show (no tab off, not hidden, panel closed)")
    check(code("Aris/private/Aris/Side/ArisSidePanelView.swift").contains("if edge == .left, firstTries.sliverShown, !isOpen {"), "its words are beside the left sliver only, and only then")
}

// MARK: - The permissions page's picture is never empty grey

private func onboard2PictureTests() {
    typealias P = ArisStagePicture
    check(P.of(active: .mic, waiting: []) == .preview(.mic, still: false) && P.of(active: .screen, waiting: []) == .preview(.screen, still: false),
          "picture: the open card's system UI, looping")
    check(P.of(active: .mic, waiting: [.mic]) == .preview(.mic, still: true), "picture: while macOS's own microphone prompt is up the alert stays, still (it was empty grey)")
    check(P.of(active: .accessibility, waiting: [.accessibility]) == .preview(.accessibility, still: false) && P.of(active: .screen, waiting: [.screen]) == .preview(.screen, still: false),
          "picture: while System Settings is up the list keeps showing what to do there")
    check(P.of(active: nil, waiting: [.screen]) == .preview(.screen, still: false), "picture: nothing open but one being asked: that one's")
    check(P.of(active: nil, waiting: []) == .star, "picture: every card decided: the star")
    for card in ArisPermissionCard.allCases {
        for waiting in [Set<ArisPermissionCard>(), [card], Set(ArisPermissionCard.allCases)] {
            if case .preview(let shown, _) = P.of(active: card, waiting: waiting) { check(shown == card, "picture: the open card's own (\(card))") } else { check(false, "picture: the open card always has one (\(card))") }
        }
    }
    for kind in [ArisPreviewKind.alertOnly, .settingsOnly] {
        let score = ArisPreviewScore(kind: kind)
        let times = stride(from: 0.0, to: score.period, by: 10)
        check(times.allSatisfy { score.pictureOpacity($0, entered: true) == 1 }, "picture (\(kind)): after its first round it is on the stage at every moment of the loop")
        check(times.filter { $0 >= 200 }.allSatisfy { score.pictureOpacity($0, entered: false) == 1 } && score.pictureOpacity(100, entered: false) > 0 && score.pictureOpacity(0, entered: false) == 0,
              "picture (\(kind)): the first time it comes in over 200 ms and then stays to the round's end")
        check(times.allSatisfy { kind == .alertOnly ? score.alertScale($0, entered: true) == 1 : score.settingsScale($0, entered: true) == 1 }, "picture (\(kind)): nothing shrinks it away between rounds")
    }
    let alert = ArisPreviewScore(kind: .alertOnly)
    check(alert.yesDown(ArisPreviewScore.alertStill) && ArisPreviewScore.alertStill < alert.period, "picture: the still frame of the alert has its button held down")
    let list = ArisPreviewScore(kind: .settingsOnly)
    check(!list.added(0) && list.added(ArisPreviewScore.drop + 10) && list.toggleOn(ArisPreviewScore.switchOn + 10) && !list.added(list.period - 10),
          "picture: in the list, Aris's row comes with the drop, its switch goes on, and the row leaves before the next round (the list itself stays)")
    let preview = code(onboarding + "ArisOnboardingPreview.swift")
    check(preview.contains("case .star:") && preview.contains("score.alertOpacity(t, entered: entered)") && preview.contains("score.settingsOpacity(t, entered: entered)")
          && code(onboarding + "ArisOnboardingPermissions.swift").contains("ArisStagePicture.of(active: flow.active, waiting: flow.waiting)"),
          "picture: the stage is drawn from that rule and that score")
}

// MARK: - The × means "later"

private func onboard2LaterTests() {
    typealias O = ArisOnboarding
    let later = O.AfterClose(seen: false, later: true), done = O.AfterClose(seen: true, later: false)
    // Closed by the user (the ×, Esc, the veil's ✕) at any moment before the last page is finished: put off, not done.
    for phase in [ArisOnboardingPhase.intro, .flight, .talk, .handoff, .setup] {
        check(O.closing(.dismissed, phase: phase, doneBefore: false) == .later && O.afterClose(O.closing(.dismissed, phase: phase, doneBefore: false)) == later,
              "×: closed during \(phase), the setup is put off: it stays unseen and waits")
    }
    // At each page: the page is kept, and the next launch opens there with no intro.
    let everything = ArisSetupPlan.make(permissionsSettled: false, readyAIs: 0)
    for page in Page.allCases {
        let kept = O.afterClose(O.closing(.dismissed, phase: .setup, doneBefore: false))
        check(kept == later && Page.resume(saved: page.rawValue) == page && everything.opening(at: Page.resume(saved: page.rawValue)) == page,
              "×: closed on \(page), the next launch continues on \(page)")
        check(O.launch(seen: kept.seen, later: kept.later, replay: false, loginItem: false, lastResume: nil, resumes: 0, quitAt: nil, now: Date()) == .resume
              && O.resumes(later: kept.later, replay: false), "×: after a close on \(page) the next launch resumes the pages, without the intro")
    }
    // What is already done is not asked again: the permissions that are on and the AI that is set up leave their pages out.
    check(ArisSetupPlan.make(permissionsSettled: true, readyAIs: 1).opening(at: .permissions) == .ask
          && ArisSetupPlan.make(permissionsSettled: true, readyAIs: 1).opening(at: .brain) == .wake, "×: coming back, no page repeats what is done")
    // Only finishing the last page marks it done; then it never shows again by itself.
    check(O.closing(.finished, phase: .finish, doneBefore: false) == .finished && O.afterClose(.finished) == done
          && O.launch(seen: true, later: false, replay: false, loginItem: false, lastResume: nil, resumes: 0, quitAt: nil, now: Date()) == .none,
          "×: finishing the last page marks the setup done, and it is never shown again")
    check(O.closing(.dismissed, phase: .finish, doneBefore: false) == .finished, "×: Esc while the last page's finish plays is still finished")
    check(O.closing(.later, phase: .setup, doneBefore: false) == .later && O.closing(.later, phase: .setup, doneBefore: true) == .later, "나중에 할게요 is later, as it was")
    // A setup that was already done and is only being looked at again (Settings, the launch flag) stays done when closed.
    check(O.doneBefore(seen: true, later: false) && !O.doneBefore(seen: false, later: false) && !O.doneBefore(seen: true, later: true) && !O.doneBefore(seen: false, later: true),
          "×: done before means seen and not put off")
    check(O.closing(.dismissed, phase: .setup, doneBefore: true) == .finished && O.closing(.dismissed, phase: .intro, doneBefore: true) == .finished,
          "×: closing a replay of a setup that was finished leaves it finished (it does not come back at the next launch)")
    // The replay flag still works, whatever the state.
    for (seen, put) in [(false, false), (true, false), (false, true), (true, true)] {
        check(O.launch(seen: seen, later: put, replay: true, loginItem: false, lastResume: Date(), resumes: 9, quitAt: nil, now: Date()) == .intro && !O.resumes(later: put, replay: true),
              "×: the replay flag starts from the intro (seen \(seen), put off \(put))")
    }
    // Put off, nothing nags: at most once a day, three times, never at login; and the ✦ menu has the quiet way back.
    let now = Date()
    check(O.launch(seen: false, later: true, replay: false, loginItem: true, lastResume: nil, resumes: 0, quitAt: nil, now: now) == .none
          && O.launch(seen: false, later: true, replay: false, loginItem: false, lastResume: now.addingTimeInterval(-3_600), resumes: 1, quitAt: nil, now: now) == .none
          && O.launch(seen: false, later: true, replay: false, loginItem: false, lastResume: now.addingTimeInterval(-90_000), resumes: 1, quitAt: nil, now: now) == .resume
          && O.launch(seen: false, later: true, replay: false, loginItem: false, lastResume: nil, resumes: O.maxResumes, quitAt: nil, now: now) == .none,
          "×: put off, it comes back by itself at most once a day and three times, never at login")
    check(O.postponed(later: true, showing: false) && !O.postponed(later: true, showing: true) && !O.postponed(later: false, showing: false),
          "×: while it is put off (and not on screen) the ✦ menu offers the way back")
    check(ArisSetupWords.continueSetup(english: false) == "설정 안내 이어서 하기" && ArisSetupWords.continueSetup(english: true) == "Continue setup", "that entry's words")

    let guide = code(onboarding + "ArisOnboardingGuide.swift")
    let close = part(guide, from: "func close(_ how: ArisOnboarding.Close = .dismissed)", to: "func closeForQuit()")
    check(close.contains("let reason = ArisOnboarding.closing(how, phase: phase, doneBefore: doneBefore)") && close.contains("if reason != .later {"),
          "×: every close goes through that rule, and a put-off setup keeps its page")
    let show = part(guide, from: "func show(replay: Bool = false, asked: Bool = false)", to: "func surface()")
    let read = show.range(of: "doneBefore = ArisOnboarding.doneBefore(")?.lowerBound, written = show.range(of: "defaults.set(true, forKey: ArisOnboarding.seenKey)")?.lowerBound
    check(read != nil && written != nil && read! < written!, "×: whether it was done before is read before this showing writes anything")
    check(show.contains("quiet = resuming && !asked") && guide.contains("func continueSetup() { show(asked: true) }"), "the way back from the menu opens in front, at the page left")
    let window = code(onboarding + "ArisOnboardingWindow.swift")
    let x = part(window, from: "Button { guide.close(.dismissed) } label: {", to: ".animation(ArisOBCurve.card, value: backShown)")
    check(x.contains(".focusable(false)") && x.contains(".accessibilityHint(ArisOnboardingCopy.laterHint)"),
          "×: the window's × stays out of the keyboard's focus loop, and VoiceOver hears that the rest comes back")
    let menu = code("Aris/private/Aris/ArisStatusItem.swift")
    check(menu.contains("ArisOnboarding.postponed(later: UserDefaults.standard.bool(forKey: ArisOnboarding.laterKey), showing: ArisOnboardingGuide.shared.showing)")
          && menu.contains("ArisSetupWords.continueSetup(") && menu.contains("ArisOnboardingGuide.shared.continueSetup()"), "the ✦ menu has “설정 안내 이어서 하기” while the setup is put off")
}

// MARK: - Words

private func onboard2WordsTests() {
    typealias W = ArisSetupWords
    let pairs: [(String, (Bool) -> String)] = [
        ("try title", { W.tryTitle("⌥ Space", english: $0) }), ("try narration", { W.tryNarration("⌥ Space", english: $0) }), ("try how", { W.tryHow(english: $0) }),
        ("try hold note", { W.tryHoldNote(english: $0) }), ("try done", { W.tryDone(english: $0) }), ("try again", { W.tryAgain(english: $0) }),
        ("try not allowed", { W.tryNotAllowed(english: $0) }), ("try type instead", { W.tryTypeInstead(english: $0) }), ("try send", { W.trySend(english: $0) }),
        ("try field", { W.tryFieldLabel(english: $0) }), ("brain lead", { W.brainKeyLead(anyReady: false, english: $0) }), ("brain lead ready", { W.brainKeyLead(anyReady: true, english: $0) }),
        ("brain existing", { W.brainExisting(english: $0) }), ("brain copy", { W.brainCopy(english: $0) }), ("dictate lead", { W.dictateLead(key: "K", english: $0) }),
        ("model title", { W.modelTitle(english: $0) }), ("model wifi", { W.modelWifi(english: $0) }), ("model waiting", { W.modelWaiting(english: $0) }),
        ("model failed", { W.modelFailed(english: $0) }), ("first tries line", { ArisFirstTriesPlan.line(name: nil, english: $0) }),
        ("first tries hint", { ArisFirstTriesPlan.hint(keys: "⌥ Space", english: $0) }), ("sliver", { ArisFirstTriesPlan.sliverWord(english: $0) }),
        ("capture note", { W.captureNote(.asksOnceMore, english: $0) }), ("continue setup", { W.continueSetup(english: $0) }),
    ]
    for (name, say) in pairs {
        let ko = say(false), en = say(true)
        check(!ko.isEmpty && !en.isEmpty && ko != en, "words: “\(name)” is said in Korean and in English")
        check(ko.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } && !en.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) },
              "words: “\(name)”: Korean in the Korean line, none in the English one")
        check(![ko, en].joined().unicodeScalars.contains { $0.properties.isEmojiPresentation }, "words: “\(name)” has no emoji")
        check(!["aris-agent", "helper", "도우미"].contains { ko.contains($0) || en.lowercased().contains($0) }, "words: “\(name)” says nothing of a helper")
    }
    check(W.tryTitle("⌃ K", english: true).contains("⌃ K") && W.tryNarration("⌃ K", english: false).contains("⌃ K"), "words: the try page names the talk key as it is set")
    check(W.tryNote(.hold, english: true) == W.tryHoldNote(english: true) && W.tryNote(.done, english: false) == W.tryDone(english: false)
          && W.tryNote(.again, english: true) == W.tryAgain(english: true) && W.tryNote(.changed, english: true) == ArisOnboardingCopy.shortcutChanged, "words: each note of the try page")
    // 2: the permissions page, shorter. One sentence less on the Screen Recording card; it still says why macOS asks again.
    let once = W.captureNote(.asksOnceMore, english: true), onceKo = W.captureNote(.asksOnceMore, english: false)
    check(once.count < 100 && onceKo.count < 60 && once.contains("asks once more") && onceKo.contains("한 번 더"), "pick 2: the Screen Recording card's line is one short sentence")
}

// MARK: - Wiring

private func onboard2WiringTests() {
    let practice = code("Aris/private/Aris/ArisController+Practice.swift")
    check(practice.contains("case .timer(let intent): reply = await doOnMac(intent, korean: korean)"), "pick 1-A: the practice turn sets the timer with the code every turn uses")
    check(practice.contains("ArisOnboardingGuide.shared.tryEnded(ArisSetupTry.outcome(of: question, timerRunning: ArisTimerModel.shared.isRunning))"),
          "pick 1-A: the page hears how the turn ended from the timer as it really is, by voice or typed")
    check(code("Aris/private/Aris/ArisController+Typed.swift").contains("practiceTurn = onboardingTalk == .practice"), "a request typed on the try page is a practice turn too")
    check(!code("Aris/private/Aris/ArisController.swift").contains("keycapOnly"), "pick 4-A: no page only lights the keys any more: the key listens")

    let setup = code(onboarding + "ArisOnboardingGuide+Setup.swift")
    let ended = part(setup, from: "func tryEnded(_ outcome: ArisSetupTry.Outcome?)", to: "func narration(for page")
    check(ended.contains("guard phase == .setup, page == .ask, let outcome else { return }") && ended.contains("askAnswered = true")
          && ended.contains("after(ArisSetupTry.advanceAfter, name: \"try\")") && ended.contains("guide.next()"),
          "pick 4-A: a request really done shows 계속 and moves the page on by itself, only on the try page")
    check(setup.contains("clocks.cancel(name: \"try\")"), "pressing 계속 first leaves no second move waiting")
    check(setup.contains("plan = ArisSetupPlan.make(permissionsSettled: cardsOn && actions.captureAllowed() && ArisPrerequisites.current().isEmpty")
          && setup.contains("let page = plan.opening(at: wanted)") && setup.contains("model.next(skipping: plan.skipped)") && setup.contains("model.back(skipping: plan.skipped)"),
          "the guide walks the plan made as the window opens")
    check(setup.contains("plan.learning(readyAIs: ArisSetupPlan.readyCount(ready), at: page)"), "and lets it learn which AIs are set up")

    let page = code(onboarding + "ArisOnboardingTryPage.swift")
    check(page.contains("ArisOnboardingKeycap(symbol: key, lit: aris.keyHeld || holding, palette: palette)") && page.contains("aris.keyDown()") && page.contains("aris.keyUp()"),
          "pick 4-A: the keycaps light while the key (or the page's button) is held, and it listens")
    check(page.contains("Button(ArisOnboardingCopy.shortcutChange)") && page.contains("ArisSettingsNav.shared.go(ArisSettingsCaption.talkKey.page, anchor: ArisSettingsCaption.talkKey.anchor)"),
          "pick 4-A: 아니요, 키를 바꿀게요 is kept, and opens Settings at the talk key")
    check(page.contains("Try.sentence(hearing, english: ArisSetupWords.english)") && page.contains("TextField(line, text: $typed)") && page.contains("aris.submitTyped(text)")
          && page.contains("ArisMicChoice.hasMicrophone()"), "pick 1-A: with no microphone the page says so and takes the request typed")
    check(!page.contains("ArisOnboardingCopy.shortcutQuestion") && !page.contains("ArisOnboardingCopy.shortcutYes"), "pick 4-A: no quiz: nobody is asked whether the keys lit")
    let window = code(onboarding + "ArisOnboardingWindow.swift")
    check(window.contains("case .ask: ArisTryPage(guide: guide, model: model, palette: palette)") && !window.contains("ArisShortcutPage") && !window.contains("ArisAskPage"),
          "pick 4-A: one page where there were two")

    // 7 and 8 stay: the wake word page and the intro are as they were.
    let wake = code(onboarding + "ArisOnboardingWakePage.swift")
    check(wake.contains("ArisGlassRect(title: ArisOnboardingCopy.wakeYes) { guide.chooseWakeWord(true) }") && wake.contains("Button(ArisOnboardingCopy.wakeNo) { guide.chooseWakeWord(false) }")
          && wake.contains("ArisOnboardingCopy.wakeHonest"), "pick 7: the wake word page keeps 네 as the glass button and its sentence about the microphone")
    check(ArisOnboardingScore.skip == 12_000, "pick 8: the intro keeps its length (건너뛰기 at 12 s)")
    check(window.contains("Button { guide.close(.dismissed) } label: {") && window.contains("Button(ArisOnboardingCopy.later) { guide.close(.later) }"),
          "the setup's × and 나중에 할게요 are both there (what the × comes to is ArisOnboarding.closing)")

    // Nothing new pulses or blinks, and no new file names the dictation key itself.
    let mine = ["ArisOnboardingTryPage.swift", "ArisOnboardingRail.swift", "ArisOnboardingBrainPage.swift", "ArisOnboardingBrainKeyForm.swift", "ArisOnboardingModelLine.swift",
                "ArisFirstTries.swift", "ArisFirstTriesPlan.swift", "ArisSetupTry.swift", "ArisSetupPlan.swift", "ArisSetupBrainKey.swift", "ArisOnboardingGuide+Brain.swift"]
    for file in mine {
        let text = code(onboarding + file)
        check(!text.isEmpty && !text.contains("repeatForever") && !text.contains("오른쪽 ⌥") && !text.lowercased().contains("right ⌥"),
              "\(file): nothing loops or blinks, and the dictation key is never named by hand")
    }
}
