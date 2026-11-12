// Tests for the fresh-install fixes (QA's FRESH-INSTALL.md, F2 and F4–F9): which AI answers on a Mac that has just
// installed Aris, the wake word that starts off and never loops on a missing speech model, one UI language, a setup
// window that fits the display and comes forward, no Screen Recording request left behind, and a drag panel that keeps
// clear of macOS's own sheets. Called from main.swift; uses its check().
import Foundation

func runFirstRunTests() {
    firstRunPinTests()
    firstRunBrainTests()
    firstRunBrainWordsTests()
    firstRunFlowTests()
    firstRunWakeTests()
    firstRunLanguageTests()
    firstRunWindowTests()
    firstRunForwardTests()
    firstRunPermissionTests()
    firstRunCopyTests()
}

private func source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The lines of a source file that are code (a comment may name what the code no longer does).
private func code(_ path: String) -> String {
    source(path).split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

// MARK: - F2, F4: what an install from before keeps

private func firstRunPinTests() {
    typealias F = ArisFirstRun
    check(!F.isEarlierInstall(keys: []) && !F.isEarlierInstall(keys: ["NSWindow Frame ArisSettingsWindow", "SUHasLaunchedBefore", "KeyboardShortcuts_talkToAris"]),
          "F4: a Mac with nothing of Aris's stored is a fresh install")
    check(F.isEarlierInstall(keys: ["arisOnboardingSeen"]) && F.isEarlierInstall(keys: ["arisOnboardingLater"]) && F.isEarlierInstall(keys: ["arisVoiceID"]),
          "F4: anything Aris stored before means an install from before")
    check(!F.isEarlierInstall(keys: ["arisOnboardingReplay"]), "F4: the replay switch alone is not an earlier run")
    check(F.pins(keys: ["arisOnboardingSeen"]) == F.Pins(wakeWord: true, brain: "codex"),
          "F2/F4: an earlier install that never chose keeps what it ran on: the wake word on, Codex answering")
    check(F.pins(keys: ["arisOnboardingSeen", "arisWakeWord", "arisBrain"]) == F.Pins(wakeWord: nil, brain: nil),
          "F2/F4: what an earlier install chose itself is left alone")
    check(F.pins(keys: ["arisOnboardingSeen", "arisWakeWord"]) == F.Pins(wakeWord: nil, brain: "codex")
          && F.pins(keys: ["arisOnboardingLater", "arisBrain"]) == F.Pins(wakeWord: true, brain: nil), "F2/F4: each is pinned on its own")
    check(F.pins(keys: []) == F.Pins(wakeWord: nil, brain: nil), "F2/F4: a fresh install is pinned to nothing")

    let name = testSuiteName("aris-first-run-tests")
    guard let earlier = UserDefaults(suiteName: name) else { return check(false, "F4: a defaults suite for the test") }
    earlier.removePersistentDomain(forName: name)
    F.pinEarlierDefaults(in: earlier, stored: ["arisOnboardingSeen"])
    check(earlier.object(forKey: "arisWakeWord") as? Bool == true && earlier.string(forKey: "arisBrain") == "codex" && earlier.bool(forKey: F.pinnedKey),
          "F4: at the first launch of this build an earlier install's wake word is written as on, its brain as Codex")
    earlier.set(false, forKey: "arisWakeWord")
    earlier.set("claude", forKey: "arisBrain")
    F.pinEarlierDefaults(in: earlier, stored: ["arisOnboardingSeen"])
    check(earlier.object(forKey: "arisWakeWord") as? Bool == false && earlier.string(forKey: "arisBrain") == "claude", "F4: it is done once, never again over a later choice")
    earlier.removePersistentDomain(forName: name)
    F.pinEarlierDefaults(in: earlier, stored: [])
    check(earlier.object(forKey: "arisWakeWord") == nil && earlier.object(forKey: "arisBrain") == nil && earlier.bool(forKey: F.pinnedKey),
          "F4: a fresh install gets nothing written, and is never taken for an earlier one later")
    F.pinEarlierDefaults(in: earlier, stored: ["arisOnboardingSeen", F.pinnedKey])
    check(earlier.object(forKey: "arisWakeWord") == nil, "F4: once its guide is finished a fresh install still has the wake word off")
    earlier.removePersistentDomain(forName: name)

    let keys = code("Aris/private/Aris/ArisPreferenceKeys.swift")
    check(keys.contains(#"Key<Bool>("arisWakeWord", default: false)"#), "F4: on a fresh install the wake word is off")
    check(keys.contains(#"Key<String>("arisBrain", default: ArisBrain.codex.rawValue)"#), "F2: the stored brain's own default is unchanged for everyone")
    let entry = code("Aris/private/App/ArisEntry.swift")
    let pin = entry.range(of: "ArisFirstRun.pinEarlierDefaults"), launch = entry.range(of: "func applicationDidFinishLaunching")
    check(pin != nil && launch != nil && pin!.lowerBound < launch!.lowerBound, "F4: the pinning runs before anything else at launch")
}

// MARK: - F2: the brain that answers

private func firstRunBrainTests() {
    typealias C = ArisBrainChoice
    check(C.order == [.claude, .codex, .antigravity, .api], "F2: Claude first (the user's ruling), then Codex, Antigravity, the API brain")
    check(C.ready(["claude": true, "codex": false, "nonsense": true]) == [.claude: true, .codex: false], "F2: the agent's answer, by brain")
    check(C.firstReady([.claude: true, .codex: true, .antigravity: true, .api: true]) == .claude, "F2: with everything set up, Claude")
    check(C.firstReady([.claude: false, .codex: true, .api: true]) == .codex && C.firstReady([.claude: false, .codex: false, .antigravity: true, .api: true]) == .antigravity
          && C.firstReady([.claude: false, .codex: false, .antigravity: false, .api: true]) == .api, "F2: else the next one that is set up")
    check(C.firstReady([.claude: false, .codex: false, .antigravity: false, .api: false]) == nil && C.firstReady([:]) == nil, "F2: none set up: none")

    // The QA Mac: no Codex, Claude or Antigravity; a DeepSeek key saved.
    let vm: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: true]
    check(C.resolve(stored: nil, ready: vm) == .api, "F2: a fresh install with only an API key answers with it, not Codex")
    check(C.resolve(stored: nil, ready: [.claude: true, .codex: true, .antigravity: false, .api: false]) == .claude, "F2: a fresh install prefers Claude")
    check(C.resolve(stored: nil, ready: [.claude: false, .codex: false, .antigravity: false, .api: false]) == nil, "F2: nothing set up: nothing is stored")
    // The user's Mac: Codex pinned (it was the default they ran on), and everything installed.
    let users: [ArisBrain: Bool] = [.claude: true, .codex: true, .antigravity: true, .api: false]
    check(C.resolve(stored: "codex", ready: users) == nil, "F2: an existing user's brain stays, though Claude is there too")
    check(C.resolve(stored: "antigravity", ready: users) == nil && C.resolve(stored: "claude", ready: users) == nil, "F2: whatever he chose stays while it can answer")
    check(C.resolve(stored: "codex", ready: vm) == nil && C.answering(.codex, ready: vm) == .api, "F2: a stored brain that can't answer here is kept (security review M5); a request made meanwhile can go to one that can")
    check(C.resolve(stored: "codex", ready: [.claude: false, .codex: false, .antigravity: false, .api: false]) == nil, "F2: with nothing else to go to it stays")
    check(C.resolve(stored: "codex", ready: [.claude: true]) == nil, "F2: a brain the agent said nothing about is never moved off")
    check(C.resolve(stored: "nonsense", ready: users) == .claude, "F2: a stored name that is no brain is chosen afresh")
    check(C.noneReady([.claude: false, .codex: false, .antigravity: false, .api: false]) && !C.noneReady(vm) && !C.noneReady(nil) && !C.noneReady([:]),
          "F2: no AI is said only once the agent has answered for every one of them")

    typealias G = ArisSettingsCaption
    check(G.greeting(agentDown: false, missingPermissions: 0, noAI: true) == G.noAI && G.noAI != "모두 잘 되고 있어요", "F2: settings says when no AI can answer")
    check(G.greeting(agentDown: true, missingPermissions: 2, noAI: true) == "에이전트와 연결이 끊겼어요", "F2: a lost agent is said first (nothing is known then)")
    // The final check on a new Mac set the order: the helper, then permissions, then the AI (it was AI before permissions).
    check(G.greeting(agentDown: false, missingPermissions: 2, noAI: true) == "권한 2개가 더 필요해요", "F2 (final-new 7): missing permissions come before no AI")
    check(G.greeting(agentDown: false, missingPermissions: 0, noAI: false) == "모두 잘 되고 있어요" && G.greeting(agentDown: false, missingPermissions: 0) == "모두 잘 되고 있어요",
          "F2: all is well only when it is")
    check(G.asksForAI(G.noAI) && !G.asksForAI("모두 잘 되고 있어요") && !G.asksForPermissions(G.noAI), "F2: that line opens AI 서비스, not the permissions")
}

private func firstRunBrainWordsTests() {
    typealias T = ArisBrainTrouble
    for brain in ArisBrain.allCases {
        for korean in [true, false] {
            let line = T.cannotStart(brain, korean: korean)
            check(!line.contains("is it installed") && !line.contains("Couldn't start") && T.isCannotStart(line),
                  "F2: \(brain.rawValue) not starting is a sentence for a person, and the notch knows it (\(korean ? "ko" : "en"))")
        }
    }
    check(T.cannotStart(.codex, korean: true).contains("설정 › AI 서비스") && T.cannotStart(.codex, korean: false).contains("Settings › AI services"),
          "F2: it says where to fix it")
    check(T.cannotStart(.claude, korean: false).contains("Claude") && !T.cannotStart(.api, korean: false).contains("브레인"), "F2: it names the AI, in the sentence's language")
    check(!T.isCannotStart("Claude 한도에 닿았어요. 잠시 뒤에 다시 해 주세요.") && !T.isCannotStart("") && !T.isCannotStart("파리예요."), "F2: no other answer gets the settings button")
    check(T.settingsButton(english: false) == "설정 › AI 서비스 열기" && T.settingsButton(english: true) == "Open Settings › AI services", "F2: the button's words")
    let runner = code("ArisAgent/ArisAgentRunner.swift")
    check(!runner.contains("is it installed") && runner.contains("ArisBrainFailure.startLine(brain: brain, missing: driver.missing"), "F2: the agent says it that way")
    check(code("Aris/private/Aris/Home/ArisTurnView.swift").contains("ArisBrainTrouble.isCannotStart(session.reply)"), "F2: the notch offers Settings under it")
}

// MARK: - F2, F4: the setup's pages

private func firstRunFlowTests() {
    // The owner's picks of 2026-11-11 (onboarding 4-A): the shortcut's practice and the first question are one page, before
    // the AI page (onboard2-tests.swift has each kind of user's pages).
    check(ArisSetupPage.allCases == [.permissions, .ask, .brain, .wake, .dictation],
          "F2/F4: 권한 → 눌러서 말하기 → AI 고르기 → 아리스라고 부르기 → 받아쓰기")
    var flow = ArisSetupFlow(page: .ask)
    check(flow.next() && flow.page == .brain, "F2: the AI is picked right after the first request, which needs none")
    check(flow.next() && flow.page == .wake && flow.next() && flow.page == .dictation && !flow.next() && flow.finished, "F4: the wake word is asked before the last page")

    var none = ArisSetupFlow(page: .ask)
    check(none.next(skipping: [.brain]) && none.page == .wake, "F2: a page that is left out: 계속 goes past it")
    none.back(skipping: [.brain])
    check(none.page == .ask, "F2: and 뒤로 comes back over it")
    var last = ArisSetupFlow(page: .wake)
    check(last.next(skipping: [.dictation]) == false && last.finished, "F2: skipping the last page finishes")
    var first = ArisSetupFlow(page: .ask)
    first.back(skipping: [.permissions])
    check(first.page == .permissions, "F2: 뒤로 never leaves the first page")

    let fifth = 1.0 / 5
    check(abs(ArisSetupFlow(page: .brain).progress(granted: [:]) - 2 * fifth) < 1e-9 && abs(ArisSetupFlow(page: .dictation).progress(granted: [:]) - 4 * fifth) < 1e-9,
          "F2/F4: the rail moves an equal share a page")
    check(ArisOnboardingTalk.mode(phase: .setup, page: .brain) == .turn && ArisOnboardingTalk.mode(phase: .setup, page: .wake) == .turn
          && ArisOnboardingTalk.mode(phase: .setup, page: .ask) == .practice, "F2/F4: only the try page is practice")
    check(ArisSetupPage.resume(saved: 2) == .brain && ArisSetupPage.resume(saved: 5) == .dictation && ArisSetupPage.resume(saved: 6) == .permissions,
          "F2/F4: a saved page resumes; one that doesn't exist starts at 권한")

    typealias B = ArisOnboardingBrainRows
    let vm = B.rows(ready: [.claude: false, .codex: false, .antigravity: false, .api: true], chosen: "api")
    check(vm.map(\.brain) == ArisBrainChoice.order && vm.map(\.state) == [.missing, .missing, .missing, .chosen], "F2: every AI has a row; the one that answers is marked")
    let fresh = B.rows(ready: [.claude: true, .codex: true, .antigravity: false, .api: false], chosen: "claude")
    check(fresh.map(\.state) == [.chosen, .ready, .missing, .missing] && fresh[0].recommended && !fresh[1].recommended, "F2: Claude is the recommended one")
    let stale = B.rows(ready: [.claude: true, .codex: false, .antigravity: false, .api: false], chosen: "codex")
    check(stale.map(\.state) == [.ready, .missing, .missing, .missing], "F2: a brain that isn't set up is never shown as the one answering")
    check(B.rows(ready: nil, chosen: "codex").allSatisfy { $0.state == .unknown }, "F2: before the agent answers nothing is claimed either way")
    check(B.heading(ready: nil) == .unknown && B.heading(ready: [.claude: false, .codex: false, .antigravity: false, .api: false]) == .none
          && B.heading(ready: [.claude: true, .codex: false]) == .some, "F2: the page says plainly when nothing is available")
    check(B.selectable(.ready) && B.selectable(.chosen) && !B.selectable(.missing) && !B.selectable(.unknown), "F2: only an AI that is set up can be picked")
    check(B.keyProblem("  ") != nil && B.keyProblem("sk-abc") == nil, "F2: an empty key is said, not sent")
}

// MARK: - F4: the wake word never loops

private func firstRunWakeTests() {
    typealias A = ArisWakeArm
    check(A.blocker(A.State(speechReady: false)) == .speechModel && A.blocker(A.State()) == nil, "F4: no speech model: the microphone stays closed")
    check(A.blocker(A.State(settingOn: false, speechReady: false)) == .settingOff && A.blocker(A.State(permissionOK: false, speechReady: false)) == .permission
          && A.blocker(A.State(onboardingSeen: false, speechReady: false)) == .onboarding, "F4: the earlier guards still come first")
    var log = A.Log()
    check(log.line(for: .speechModel)?.contains("speech") == true && log.line(for: .speechModel) == nil, "F4: said once in the log, not every five seconds")

    check(A.speechRecheck(after: 0) == .seconds(30) && A.speechRecheck(after: 1) == .seconds(120) && A.speechRecheck(after: 2) == .seconds(600),
          "F4: a model still not ready is looked for again later, each time further off")
    check(A.speechRecheck(after: 3) == nil && A.speechRecheck(after: 50) == nil, "F4: then it stops looking until something changes")
    check(A.pause(afterListenFailures: 1) == .seconds(30) && A.pause(afterListenFailures: 2) == .seconds(120) && A.pause(afterListenFailures: 3) == .seconds(600),
          "F4: a check that couldn't listen keeps the microphone closed longer each time")
    check(A.pause(afterListenFailures: 4) == nil && A.pause(afterListenFailures: 0) == .seconds(30), "F4: after three in a row it stays closed")

    let wake = code("Aris/private/Aris/ArisController+Wake.swift")
    check(wake.contains("speechReady: Self.wakeSpeechReady") && wake.contains("case .speechModel?:"), "F4: the arming asks whether the model is there")
    check(wake.contains("wakeListenFailed(listener)"), "F4: a check whose recognizer couldn't start ends there")
    let failed = wake.range(of: "func wakeListenFailed").map { String(wake[$0.lowerBound...].prefix(900)) } ?? ""
    check(failed.contains("stopWaitingForWakeWord()") && !failed.contains("pause(false)"), "F4: the microphone closes then; it is not handed back to the detector")
    check(ArisWakeArm.mayTouchPermissions(onboardingSeen: false) == false, "F4: (unchanged) nothing listens before the guide's permission page")
    let guide = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide.swift")
    let close = guide.range(of: "func close(").map { String(guide[$0.lowerBound...].prefix(2200)) } ?? ""
    check(close.contains("ArisController.shared.waitForWakeWordSoon()"),
          "F4: when the guide closes, a wake word turned on in it starts listening (until then the guide held it back)")
}

// MARK: - F5: one UI language

private func firstRunLanguageTests() {
    typealias L = ArisUILanguage
    check(L.choose(preferred: ["en-US"]) == "en" && L.choose(preferred: ["ko-KR", "en-US"]) == "ko" && L.choose(preferred: ["en-GB", "ko-KR"]) == "en",
          "F5: the first of the Mac's languages Aris has")
    check(L.choose(preferred: ["fr-FR", "ko-KR"]) == "ko" && L.choose(preferred: ["ja-JP", "en-US"]) == "en", "F5: one it doesn't have is passed over")
    check(L.choose(preferred: ["fr-FR", "de-DE"]) == "en" && L.choose(preferred: []) == "en", "F5: none of them: English, in every part of the app alike")
    check(L.choose(preferred: ["KO"]) == "ko" && L.choose(preferred: ["ko"]) == "ko", "F5: however the code is written")
    check(ArisOnboardingLanguage.choose(preferred: ["fr-FR"], available: ["ko", "en"]) == "en"
          && ArisOnboardingLanguage.choose(preferred: ["ko-KR"], available: ["ko", "en"]) == "ko", "F5: the guide follows the same rule")
    check(ArisUIWords.english(preferred: "en") && !ArisUIWords.english(preferred: "ko") && ArisUIWords.english(preferred: "fr"), "F5: anything but Korean reads in English")
    check(ArisUIWords.text("선반", "Shelf", english: true) == "Shelf" && ArisUIWords.text("선반", "Shelf", english: false) == "선반", "F5: a word in the UI's language")
    // The tests have no app bundle: Korean, as the source is.
    check(!ArisUILanguage.english && ArisUIWords.text("선반", "Shelf") == "선반", "F5: (the tests read Korean)")

    for path in ["Aris/private/Aris/Onboarding/ArisOnboardingCopy.swift", "Aris/private/Aris/Team/ArisTeamCopy.swift", "Aris/private/Aris/ArisUIWords.swift"] {
        check(code(path).contains("ArisUILanguage."), "F5: \(path.split(separator: "/").last ?? "") asks the one place for the language")
    }
    check(!code("Aris/private/Aris/Team/ArisTeamCopy.swift").contains("Locale.preferredLanguages") && !code("Aris/private/Aris/ArisUIWords.swift").contains("preferredLocalizations"),
          "F5: nothing works the language out its own way")

    // What QA saw in Korean on an English Mac.
    check(ArisSpeechModel.small.name(english: true) == "Small model" && ArisSpeechModel.large.name(english: false) == "큰 모델", "F5: the dictation model card's models")
    check(ArisModelOffer.title(english: true) == "Make dictation more accurate?" && ArisModelOffer.title(english: false) == "받아쓰기를 더 정확하게 할까요?", "F5: its question")
    check(ArisModelDownload.waiting(0.2).earText(english: true) == "Wait" && ArisModelDownload.waiting(0.2).earText == "대기", "F5: the ear's word")
    check(ArisModelDownload.running(0.5).status(remaining: 90, english: true) == "About 2 min left" && ArisModelDownload.running(0.5).status(remaining: 90) == "약 2분 남음",
          "F5: the time left")
    check(ArisShelfWords.label(count: 2, shown: 3, english: true) == "Shelf" && ArisShelfWords.label(count: 2, shown: 3, english: false) == "선반"
          && ArisShelfWords.label(count: 5, shown: 3, english: true) == "All 5" && ArisShelfWords.label(count: 5, shown: 3, english: false) == "모두 5", "F5: the shelf's label")
    check(ArisAgentCopy.notRunning(english: true).hasPrefix("Aris's helper") && ArisAgentCopy.notRunning == "Aris 에이전트가 꺼져 있어요. 에이전트를 다시 시작해 주세요.",
          "F5: a failure sentence in the UI's language")
    check(ArisStartFailure.line(ArisFailure(message: "x"), timedOut: true, abandoned: false, english: true) == "The microphone took too long to open. Please try again.",
          "F5: the microphone's failure too")
    check(ArisListenerWords.modelPreparing(english: true).hasPrefix("The speech recognition model") && ArisListenerWords.modelPreparing(english: false).hasPrefix("음성 인식 모델"),
          "F5: the speech model line QA saw in Korean")
}

// MARK: - F6: the setup window fits the display

private func firstRunWindowTests() {
    typealias S = ArisOnboardingStage
    func inside(_ fit: S.Fit, _ visible: CGRect) -> Bool {
        visible.insetBy(dx: -0.5, dy: -0.5).contains(CGRect(origin: fit.origin, size: fit.size))
    }
    func centred(_ fit: S.Fit, _ visible: CGRect) -> Bool {
        abs(fit.origin.x + fit.size.width / 2 - visible.midX) <= 1 && abs(fit.origin.y + fit.size.height / 2 - visible.midY) <= 1
    }
    // The QA display: 1024 × 768, a menu bar and the Dock at the bottom.
    let vm = CGRect(x: 0, y: 70, width: 1024, height: 673)
    let small = S.fit(in: vm)
    check(inside(small, vm) && centred(small, vm), "F6: on 1024 × 768 the whole window is on screen, centred between the menu bar and the Dock")
    check(small.size.width <= 1024 - 2 * S.margin && small.size.height <= 673 - 2 * S.margin && small.scale == 1 && small.layout == small.size,
          "F6: there it is laid out narrower and shorter, not drawn smaller")
    check(small.origin.y >= vm.minY + S.margin - 0.5, "F6: 뒤로 sits clear of the Dock")
    let vmNoDock = CGRect(x: 0, y: 0, width: 1024, height: 743)
    check(inside(S.fit(in: vmNoDock), vmNoDock) && centred(S.fit(in: vmNoDock), vmNoDock) && S.fit(in: vmNoDock).size.height == 710, "F6: with the Dock hidden it keeps its full height")

    let air = CGRect(x: 0, y: 0, width: 1280, height: 775)
    check(S.fit(in: air).size == S.design && S.fit(in: air).scale == 1 && centred(S.fit(in: air), air), "F6: 1280 × 800 holds the designed window, centred")
    let airDock = CGRect(x: 0, y: 80, width: 1280, height: 695)
    check(inside(S.fit(in: airDock), airDock) && S.fit(in: airDock).size.width == 1080 && S.fit(in: airDock).size.height == 695 - 2 * S.margin && S.fit(in: airDock).scale == 1,
          "F6: with a tall Dock there only its height gives")
    let pro = CGRect(x: 0, y: 65, width: 1512, height: 884)
    check(S.fit(in: pro).size == S.design && centred(S.fit(in: pro), pro), "F6: 1512 × 982 shows it as designed")
    let big = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
    check(S.fit(in: big).size == S.design && S.fit(in: big).scale == 1 && centred(S.fit(in: big), big) && inside(S.fit(in: big), big),
          "F6: a large display beside the Mac's own never makes it bigger, and it stays on that display")

    let tiny = CGRect(x: 0, y: 0, width: 800, height: 575)
    let shrunk = S.fit(in: tiny)
    check(inside(shrunk, tiny) && shrunk.scale < 1 && shrunk.layout.width >= S.minimum.width - 0.5 && shrunk.layout.height >= S.minimum.height - 0.5,
          "F6: a display too small to lay it out draws it smaller, whole")
    check(abs(shrunk.layout.width * shrunk.scale - shrunk.size.width) <= 1 && abs(shrunk.layout.height * shrunk.scale - shrunk.size.height) <= 1,
          "F6: what is drawn is the layout at that scale")
    check(S.columnWidth(layout: S.design.width) == S.stageSize.width && S.stageScale(column: S.columnWidth(layout: S.design.width)) == 1,
          "F6: in the designed window the picture on the right is drawn as it always was")
    check(S.stageScale(column: 640) == 1 && abs(S.stageScale(column: S.stageSize.width * 0.8) - 0.8) < 1e-9 && S.stageScale(column: S.columnWidth(layout: small.layout.width)) < 1,
          "F6: it shrinks with its column on a narrow window, and never grows")

    let window = code("Aris/private/Aris/Onboarding/ArisOnboardingWindow.swift"), setup = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Setup.swift")
    check(setup.contains("fit = ArisOnboardingStage.fit(in: visible)") && window.contains("size: fit.size") && !window.contains("CGSize(width: 1080, height: 710)"),
          "F6: the window takes its size from the display's visible frame")
}

// MARK: - F7: the setup window comes forward

private func firstRunForwardTests() {
    typealias S = ArisOnboardingStage
    check(S.activates(quiet: false, reopened: false), "F7: the first time it opens in front, with the keyboard")
    check(S.activates(quiet: true, reopened: true), "F7: after Quit & Reopen it is back in front")
    check(!S.activates(quiet: true, reopened: false), "F7: a quiet resume at a later launch shows without taking the keyboard")
    check(S.comesForward(after: .promptAnswered, phase: .setup) && S.comesForward(after: .granted, phase: .setup) && S.comesForward(after: .promptAnswered, phase: .handoff),
          "F7: after macOS's prompt is answered, or a permission turns on, the setup is in front again")
    check(!S.comesForward(after: .promptAnswered, phase: .closed) && !S.comesForward(after: .granted, phase: .finish) && !S.comesForward(after: .promptAnswered, phase: .intro),
          "F7: never once the setup window is gone (nothing steals the keyboard in normal use)")
    check(!S.comesForward(after: .settingsOpened, phase: .setup), "F7: while System Settings is up for a permission it stays behind it")
    let setup = code("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Setup.swift")
    check(setup.contains("comeForward(after: .promptAnswered)") && setup.contains("comeForward(after: .granted)"), "F7: both moments bring it forward")
    check(code("Aris/private/Aris/Onboarding/ArisOnboardingWindow.swift").contains("orderFrontRegardless()"), "F7: in front of other apps' windows even if macOS refuses the activation")
}

// MARK: - F8, F9: permissions

private func firstRunPermissionTests() {
    typealias R = ArisPermissionPanelRules
    for path in ["Aris/private/Aris/ArisPermissionGuide.swift", "Aris/private/Aris/Onboarding/ArisOnboardingSystem.swift"] {
        check(!code(path).contains("CGRequestScreenCaptureAccess("), "F8: \(path.split(separator: "/").last ?? "") leaves no Screen Recording request of macOS's behind")
    }
    check(R.showsPanel(granted: false) && !R.showsPanel(granted: true), "F8: nothing is asked or shown for a permission already on")
    // The picture's score (which kind a card brings) is its own pure file now (ArisOnboardingPreviewScore).
    let preview = code("Aris/private/Aris/Onboarding/ArisOnboardingPreview.swift") + code("Aris/private/Aris/Onboarding/ArisOnboardingPreviewScore.swift")
    check(preview.contains("case .accessibility, .screen: .settingsOnly") && !preview.contains("case .screen: .alertThenSettings"),
          "F8: the page's picture shows what really comes next: System Settings, no alert, for Screen Recording")

    let panel = CGRect(x: 232, y: 600, width: 560, height: 132)
    let settings = R.Window(owner: "System Settings", settings: true, layer: 0, frame: CGRect(x: 150, y: 40, width: 720, height: 640))
    check(!R.yields(panel: panel, windows: [settings]), "F9: beside System Settings alone the drag panel shows")
    let sheet = R.Window(owner: "System Settings", settings: true, layer: 0, frame: CGRect(x: 300, y: 380, width: 420, height: 260))
    check(R.yields(panel: panel, windows: [settings, sheet]), "F9: System Settings' password sheet under it: the panel steps aside (its Cancel stays reachable)")
    let high = R.Window(owner: "System Settings", settings: true, layer: 0, frame: CGRect(x: 300, y: 100, width: 420, height: 260))
    check(!R.yields(panel: panel, windows: [settings, high]), "F9: a sheet it doesn't touch leaves it be")
    let agent = R.Window(owner: "SecurityAgent", settings: false, layer: 1000, frame: CGRect(x: 300, y: 380, width: 420, height: 300))
    check(R.yields(panel: panel, windows: [settings, agent]) && R.yields(panel: panel, windows: [agent]), "F9: macOS's own password window too")
    let finder = R.Window(owner: "Finder", settings: false, layer: 0, frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
    check(!R.yields(panel: panel, windows: [settings, finder]), "F9: any other app's window is none of its business")
    check(!R.yields(panel: panel, windows: []), "F9: nothing on screen: it shows")
    let guide = code("Aris/private/Aris/ArisPermissionGuide.swift")
    check(guide.contains("ArisPermissionPanelRules.yields(") && guide.contains("ArisPermissionPanelRules.showsPanel("), "F9: the panel follows those rules")
}

// MARK: - F4, F9: the words tell the truth

private func firstRunCopyTests() {
    let catalog = source("Aris/Localizable.xcstrings")
    let object = (try? JSONSerialization.jsonObject(with: Data(catalog.utf8))) as? [String: Any]
    let strings = object?["strings"] as? [String: Any] ?? [:]
    func value(_ key: String, _ language: String) -> String {
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        let unit = (localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return unit?["value"] as? String ?? ""
    }
    let project = source("Aris.xcodeproj/project.pbxproj")
    let prompt = "Aris listens while you hold its shortcut, and for its name if you turn that on."
    check(project.components(separatedBy: "INFOPLIST_KEY_NSMicrophoneUsageDescription = \"\(prompt)\";").count == 3, "F9: macOS's microphone prompt says both ways Aris listens")
    check(value("onboarding.mac.mic.body", "en") == prompt, "F9: the guide's picture of that prompt says the same words")
    check(value("onboarding.mac.mic.body", "ko").contains("단축키") && value("onboarding.mac.mic.body", "ko").contains("이름"), "F9: in Korean too")
    check(!value("onboarding.perms.mic.why", "en").contains("I only listen then") && !value("onboarding.perms.mic.why", "ko").contains("부를 때만"),
          "F9: the microphone card no longer promises what the wake word would break")
    for language in ["en", "ko"] {
        let title = value("onboarding.perms.title", language), narration = value("onboarding.perms.narration", language)
        check(!title.lowercased().contains("three") && !title.contains("세 가지") && !narration.lowercased().contains("three") && !narration.contains("세 가지"),
              "F9: the page no longer says three when macOS asks four times (\(language))")
        check(!value("onboarding.perms.mic.speech", language).isEmpty, "F9: the microphone card says macOS asks twice (\(language))")
        check(!value("onboarding.wake.title", language).isEmpty && !value("onboarding.wake.honest", language).isEmpty, "F4: the guide asks about the wake word (\(language))")
        check(!value("onboarding.brain.none", language).isEmpty && !value("onboarding.brain.how.claude", language).isEmpty, "F2: the guide says how to get an AI (\(language))")
    }
    check(value("onboarding.wake.title", "ko") == "아리스라고 불러서 쓸까요?", "F4: the user's question, word for word")
    check(value("onboarding.wake.honest", "ko").contains("마이크") && value("onboarding.wake.honest", "en").lowercased().contains("microphone stays on"),
          "F4: it says honestly that the microphone then stays on")
    check(ArisPermissionCard.mic.steps == [.mic, .speech], "F9: (the microphone card still asks for speech recognition, as Aris needs both)")
}
