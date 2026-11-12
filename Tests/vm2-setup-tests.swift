// Tests for the first-run setup defects the VM run of 2026-11-11 found on a brand-new install with no AI
// (qa/vm-run-1111/REPORT-new.md, sections 1, 2 and 5, bugs 3, 5 and 13):
// - the try page shows whenever its example is answered without an AI, and is left out only when Aris can't hear;
// - what is in front when the setup's window closes (a System Settings the setup opened steps out of the way);
// - macOS's second question about the screen comes in the setup, and the Screen Recording card says what came of it;
// - the helper panel says what the "aris-agent" row is; it and the list picture show the app's own icon;
// - the AI page's cards copy their command and "Check again" says what it found; Return never picks the wake word.
// Everything here is pure: no window is shown, nothing is captured, no app is activated or hidden.
// Called from main.swift; uses its check().
import Foundation

func runVM2SetupTests() {
    vm2PagesTests()
    vm2ExampleTests()
    vm2LeaveTests()
    vm2LeaveQuitTests()
    vm2CaptureRuleTests()
    vm2CaptureWordsTests()
    MainActor.assumeIsolated { vm2CaptureModelTests() }
    vm2BrainHelpTests()
    vm2HelperRowTests()
    vm2WiringTests()
}

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")

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

private let onboarding = "Aris/private/Aris/Onboarding/"

// MARK: - Bug 5: which pages show

private func vm2PagesTests() {
    typealias P = ArisSetupPage
    // The owner's picks of 2026-11-11 (onboarding 1-A, 4-A): the try page is the shortcut's practice too, its request is
    // done by the app itself and can be typed, so it shows for everyone: with no AI and with the microphone off
    // (onboard2-tests.swift has each kind of user's pages).
    let counts: [Int?] = [0, 1, 2, nil]
    for ready in counts {
        for settled in [true, false] {
            check(ArisSetupPlan.make(permissionsSettled: settled, readyAIs: ready).pages.contains(.ask),
                  "vm2 bug 5: the try page shows whatever is set up (AIs \(ready.map { "\($0)" } ?? "unknown"), permissions \(settled ? "on" : "to do"))")
        }
    }
    // The pages in order.
    func walk(_ plan: ArisSetupPlan) -> [P] {
        var flow = ArisSetupFlow(page: plan.opening(at: .permissions)), pages = [flow.page]
        while flow.next(skipping: plan.skipped) { pages.append(flow.page) }
        return pages
    }
    let all: [P] = [.permissions, .ask, .brain, .wake, .dictation]
    check(walk(.make(permissionsSettled: false, readyAIs: 0)) == all, "vm2 bug 5: no AI: every page, the try page before the AI page")
    check(walk(.make(permissionsSettled: false, readyAIs: 2)) == all, "vm2 bug 5: several AIs: every page")

    var back = ArisSetupFlow(page: .wake)
    back.back(skipping: ArisSetupPlan.make(permissionsSettled: false, readyAIs: 0).skipped)
    check(back.page == .brain, "vm2 bug 5: Back from the wake word page goes to the AI page when it shows")
    back = ArisSetupFlow(page: .wake)
    back.back(skipping: ArisSetupPlan.make(permissionsSettled: false, readyAIs: 1).skipped)
    check(back.page == .ask, "vm2 bug 5: and to the try page when the AI page is left out")
    check(ArisOnboardingTalk.mode(phase: .setup, page: .ask) == .practice, "vm2 bug 5: on the try page the talk key is still a practice turn: nothing routed, no AI")
}

private func vm2ExampleTests() {
    typealias Q = ArisOnboardingPractice
    check(Q.answersAlone("What time is it?") && Q.answersAlone("지금 몇 시야?"), "vm2 bug 5: the try page's example is answered by the app itself, in English and Korean")
    check(Q.answersAlone(ArisOnboardingCopy.askLine), "vm2 bug 5: the example the page shows (its Swift default) needs no AI")
    check(Q.answersAlone("what's the date today?"), "vm2 bug 5: the date needs no AI either")
    check(!Q.answersAlone("What's on my calendar tomorrow afternoon?"), "vm2 bug 5: the calendar needs a permission the setup never asks for: not answered alone")
    check(!Q.answersAlone("What is the capital of France?") && !Q.answersAlone(""), "vm2 bug 5: anything else is not answered alone")

    // The catalog's example in both languages, as the app shows it.
    let catalog = (try? JSONSerialization.jsonObject(with: Data(source("Aris/Localizable.xcstrings").utf8))) as? [String: Any]
    let entry = ((catalog?["strings"] as? [String: Any])?["onboarding.ask.line"] as? [String: Any])?["localizations"] as? [String: Any]
    for language in ["ko", "en"] {
        let value = ((entry?[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
        check(!value.isEmpty && Q.answersAlone(value), "vm2 bug 5: the catalog's example in \(language) (\"\(value)\") is answered without an AI")
    }

    // The page listens (the talk key, or its hold button pressing that key) and, since 2026-11-11, takes the same
    // request typed where Aris can't hear: the microphone no longer decides whether it shows.
    let page = code(onboarding + "ArisOnboardingTryPage.swift")
    check(page.contains("aris.keyDown()") && page.contains("aris.keyUp()") && page.contains("TextField(") && page.contains("aris.submitTyped(text)"),
          "vm2 bug 5: the try page is asked by voice, and typed where Aris can't hear")
    check(code("Aris/private/Aris/ArisController+Practice.swift").contains("case .time: reply = ArisIntent.tellTime.acknowledgement(korean: korean)"),
          "vm2 bug 5: the practice turn answers the time itself, with no AI")
}

// MARK: - Bug 5: what is in front when the window closes

private let terminal = "com.apple.Terminal", settingsID = "com.apple.systempreferences"

/// A card's Allow with System Settings not running, System Settings coming forward as `pid`, then the setup again.
private func sentAndBack(_ leave: inout ArisSetupLeave, pid: Int32 = 500) {
    leave.sending(runningPid: nil)
    leave.cameForward(.systemSettings, bundleID: settingsID, settingsPid: pid, sinceForward: nil)
    leave.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: pid, sinceForward: 0.1)
}

private func vm2LeaveTests() {
    typealias L = ArisSetupLeave
    let nothing = L.Plan()
    check(L(frontApp: terminal).plan(runningPid: nil, quitting: false) == nothing && L(frontApp: terminal).plan(runningPid: 500, quitting: false) == nothing,
          "vm2 bug 5: a setup that never opened System Settings touches nothing as it closes")

    var leave = L(frontApp: terminal)
    sentAndBack(&leave)
    check(leave.startedPid == 500, "vm2 bug 5: System Settings started by a card's Allow is remembered as the setup's")
    check(leave.plan(runningPid: 500, quitting: false) == L.Plan(hidesSettings: true, activates: terminal),
          "vm2 bug 5: Finish with System Settings only there because the setup opened it: it steps out of the way and the app the user had comes forward")
    check(leave.plan(runningPid: nil, quitting: false) == nothing, "vm2 bug 5: the user quit System Settings meanwhile: nothing to do")
    check(leave.plan(runningPid: 612, quitting: false) == nothing, "vm2 bug 5: another System Settings (one the user opened later) is never touched")
    check(leave.plan(runningPid: 500, quitting: true) == nothing, "vm2 bug 5: Aris quitting mid-setup (Quit & Reopen) leaves System Settings as it is")

    // The second card: the setup's own System Settings is still running.
    leave.sending(runningPid: 500)
    leave.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: nil)
    check(leave.startedPid == 500, "vm2 bug 5: sent there again for the next card, it is still the setup's")
    leave.cameForward(.app, bundleID: "com.apple.Safari", settingsPid: 500, sinceForward: nil)
    leave.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: nil)
    check(leave.startedPid == 500, "vm2 bug 5: going back to it while the card still waits is the setup's errand, not the user's own")
    leave.cameForward(.aris, bundleID: nil, settingsPid: 500, sinceForward: 0.1)
    check(leave.plan(runningPid: 500, quitting: false) == L.Plan(hidesSettings: true, activates: "com.apple.Safari"),
          "vm2 bug 5: the app that comes forward is the one the user last had")

    // The user goes back to System Settings by themselves.
    var used = L(frontApp: terminal)
    sentAndBack(&used)
    used.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: 30)
    check(used.startedPid == nil && used.plan(runningPid: 500, quitting: false) == nothing,
          "vm2 bug 5: the user went back to System Settings by themselves: it is theirs and stays where it is")
    var never = L(frontApp: terminal)
    sentAndBack(&never)
    never.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: nil)
    check(never.plan(runningPid: 500, quitting: false) == nothing, "vm2 bug 5: the same when the setup never came forward on purpose in between")
    var late = L(frontApp: terminal)
    sentAndBack(&late)
    late.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: 0.5)
    check(late.plan(runningPid: 500, quitting: false).hidesSettings,
          "vm2 bug 5: macOS handing the screen back to System Settings a moment after the setup came forward is not the user going there")
    late.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: ArisOnboardingFront.settle)
    check(!late.plan(runningPid: 500, quitting: false).hidesSettings, "vm2 bug 5: after that moment it is")

    // A System Settings the user already had open.
    var theirs = L(frontApp: terminal)
    theirs.sending(runningPid: 77)
    theirs.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 77, sinceForward: nil)
    theirs.cameForward(.aris, bundleID: nil, settingsPid: 77, sinceForward: 0.1)
    check(theirs.startedPid == nil && theirs.plan(runningPid: 77, quitting: false) == nothing,
          "vm2 bug 5: a System Settings that was already open when the card sent the user there is the user's: never hidden")
    var replaced = L(frontApp: terminal)
    sentAndBack(&replaced)
    replaced.sending(runningPid: 612)
    check(replaced.plan(runningPid: 612, quitting: false) == nothing && replaced.plan(runningPid: 500, quitting: false) == nothing,
          "vm2 bug 5: the user quit the setup's System Settings and opened their own before the next card: theirs")

    // Who the user was with.
    var apps = L()
    check(apps.userApp == nil, "vm2 bug 5: opened with no other app in front, there is none to bring back")
    apps.cameForward(.app, bundleID: terminal, settingsPid: nil, sinceForward: nil)
    apps.cameForward(.agent, bundleID: "com.apple.SecurityAgent", settingsPid: nil, sinceForward: nil)
    apps.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: nil, sinceForward: nil)
    apps.cameForward(.app, bundleID: nil, settingsPid: nil, sinceForward: nil)
    check(apps.userApp == terminal, "vm2 bug 5: macOS's own prompt windows, Aris and nameless processes are not the app the user had")
    sentAndBack(&apps)
    check(apps.plan(runningPid: 500, quitting: false).activates == terminal && apps.userApp == terminal, "vm2 bug 5: System Settings is never the app to bring back")
    var none = L()
    sentAndBack(&none)
    check(none.plan(runningPid: 500, quitting: false) == L.Plan(hidesSettings: true, activates: nil),
          "vm2 bug 5: with no app the user had, System Settings still steps aside and macOS's own order stands")

    var done = L(frontApp: terminal)
    sentAndBack(&done)
    done.done()
    check(done.plan(runningPid: 500, quitting: false) == nothing && done.userApp == terminal, "vm2 bug 5: once carried out, the plan is not carried out twice (Finish, then the close)")
}

private func vm2LeaveQuitTests() {
    typealias L = ArisSetupLeave
    var leave = L(frontApp: terminal)
    check(leave.saved == nil, "vm2 bug 5: nothing is kept across a quit when the setup opened nothing")
    sentAndBack(&leave)
    let saved = leave.saved
    check(saved?["pid"] as? Int == 500 && saved?["app"] as? String == terminal, "vm2 bug 5: Quit & Reopen keeps which System Settings the setup started and the app the user had")
    // Back after the quit: System Settings (the same process) is what is in front, so no other app is seen.
    var back = L.restored(saved: saved, runningPid: 500, frontApp: nil)
    check(back.plan(runningPid: 500, quitting: false) == L.Plan(hidesSettings: true, activates: terminal),
          "vm2 bug 5: back from Quit & Reopen, Finish still clears the System Settings the setup opened and brings Terminal back")
    back.cameForward(.aris, bundleID: nil, settingsPid: 500, sinceForward: 0.1)
    back.cameForward(.systemSettings, bundleID: settingsID, settingsPid: 500, sinceForward: 0.6)
    check(back.plan(runningPid: 500, quitting: false).hidesSettings, "vm2 bug 5: macOS handing the screen back right after the relaunch does not make it the user's")
    check(L.restored(saved: saved, runningPid: 612, frontApp: terminal).plan(runningPid: 612, quitting: false) == L.Plan()
          && L.restored(saved: saved, runningPid: nil, frontApp: terminal).plan(runningPid: nil, quitting: false) == L.Plan(),
          "vm2 bug 5: what was kept counts only while that same System Settings still runs (a launch days later starts clean)")
    check(L.restored(saved: nil, runningPid: 500, frontApp: terminal) == L(frontApp: terminal), "vm2 bug 5: nothing kept: a plain start")
    check(L.restored(saved: ["pid": "x"], runningPid: 500, frontApp: nil) == L(), "vm2 bug 5: something unreadable kept: a plain start")
    var noApp = L()
    sentAndBack(&noApp)
    check(L.restored(saved: noApp.saved, runningPid: 500, frontApp: "com.apple.finder").plan(runningPid: 500, quitting: false).activates == "com.apple.finder",
          "vm2 bug 5: with no app kept, the one in front at the relaunch is the user's")
}

// MARK: - Bug 3: macOS's second question about the screen

private func vm2CaptureRuleTests() {
    typealias C = ArisFirstCapture
    check(C.outcome(gotImage: true, declined: false) == .allowed && C.outcome(gotImage: true, declined: true) == .allowed,
          "vm2 bug 3: a frame came back: macOS has its yes")
    check(C.outcome(gotImage: false, declined: true) == .declined, "vm2 bug 3: no frame and macOS says the user turned it down: declined")
    check(C.outcome(gotImage: false, declined: false) == .unknown, "vm2 bug 3: no frame and no reason: not claimed either way")

    check(C.due(page: .permissions, screenGranted: true, waiting: false, step: .idle, allowedBefore: false),
          "vm2 bug 3: once the Screen Recording card is on, the setup takes the first capture there")
    check(!C.due(page: .permissions, screenGranted: false, waiting: false, step: .idle, allowedBefore: false),
          "vm2 bug 3: never without the Screen Recording grant (macOS's own request is never raised)")
    check(!C.due(page: .permissions, screenGranted: true, waiting: true, step: .idle, allowedBefore: false),
          "vm2 bug 3: not while another card's prompt or list is up")
    check(!C.due(page: .permissions, screenGranted: true, waiting: false, step: .asking, allowedBefore: false)
          && [C.Outcome.allowed, .declined, .unknown].allSatisfy { !C.due(page: .permissions, screenGranted: true, waiting: false, step: .done($0), allowedBefore: false) },
          "vm2 bug 3: once per setup, whatever came of it (a no is not asked again and again)")
    check(!C.due(page: .permissions, screenGranted: true, waiting: false, step: .idle, allowedBefore: true),
          "vm2 bug 3: never again once macOS has said yes (a replay of the guide captures nothing)")
    check(ArisSetupPage.allCases.filter { $0 != .permissions }.allSatisfy { !C.due(page: $0, screenGranted: true, waiting: false, step: .idle, allowedBefore: false) },
          "vm2 bug 3: only on the permissions page, where the card that explains the prompt is on screen")

    // What the card says, for every state of the card and every outcome.
    for state in [ArisCardState.idle, .later] {
        for step in [C.Step.idle, .asking, .done(.allowed), .done(.declined), .done(.unknown)] {
            check(C.note(card: state, step: step, allowedBefore: false) == nil, "vm2 bug 3: a closed or put-off card says nothing about the second question (\(state), \(step))")
        }
    }
    for state in [ArisCardState.active, .waiting] {
        check(C.note(card: state, step: .idle, allowedBefore: false) == .asksOnceMore, "vm2 bug 3: the open card says beforehand that macOS asks once more (\(state))")
    }
    check(C.note(card: .granted, step: .idle, allowedBefore: false) == .asksOnceMore && C.note(card: .granted, step: .asking, allowedBefore: false) == .asksOnceMore,
          "vm2 bug 3: on, with the prompt about to come or up: the card says macOS asks once more and why")
    check(C.note(card: .granted, step: .done(.allowed), allowedBefore: false) == nil, "vm2 bug 3: allowed: the card just says Screen Recording is on")
    check(C.note(card: .granted, step: .done(.declined), allowedBefore: false) == .declined, "vm2 bug 3: not now: the card says what happens at the first screen question")
    check(C.note(card: .granted, step: .done(.unknown), allowedBefore: false) == .unfinished, "vm2 bug 3: not finished: the card says the question may come at the first screen question")
    for state in [ArisCardState.idle, .active, .waiting, .granted, .later] {
        check(C.note(card: state, step: .idle, allowedBefore: true) == nil, "vm2 bug 3: macOS said yes before: no line promises a prompt that will not come (\(state))")
    }
    check(C.comesForward(after: .allowed) && !C.comesForward(after: .declined) && !C.comesForward(after: .unknown),
          "vm2 bug 3: after a yes the setup is in front again; after anything else nothing covers what macOS may have opened")
}

private func vm2CaptureWordsTests() {
    typealias W = ArisSetupWords
    for english in [true, false] {
        let lines = [ArisFirstCapture.Note.asksOnceMore, .declined, .unfinished].map { W.captureNote($0, english: english) }
        check(lines.allSatisfy { !$0.isEmpty && $0.contains("macOS") } && Set(lines).count == 3, "vm2 bug 3: each line of the card is its own and names macOS (\(english ? "en" : "ko"))")
    }
    let once = W.captureNote(.asksOnceMore, english: true), onceKo = W.captureNote(.asksOnceMore, english: false)
    check(once.contains("asks once more") && once.contains("window picker"), "vm2 bug 3: the card says macOS asks once more and why (the screen is read without its window picker)")
    check(onceKo.contains("한 번 더") && onceKo.contains("창 선택"), "vm2 bug 3: and in Korean")
    for note in [ArisFirstCapture.Note.declined, .unfinished] {
        let en = W.captureNote(note, english: true), ko = W.captureNote(note, english: false)
        check(en.contains("first time you ask") && en.contains("may") && !en.contains("will ask"),
              "vm2 bug 3: after a \"not now\" the card says what happens at the first screen question, without promising what macOS does (\(note))")
        check(ko.contains("처음 물어볼 때") && ko.contains("수 있어요"), "vm2 bug 3: and in Korean (\(note))")
    }
    check(W.captureNote(.declined, english: true).contains("wasn't allowed") && W.captureNote(.declined, english: true).contains("try again"),
          "vm2 bug 3: a no is called a no, and Aris says it will try again then")
}

@MainActor private func vm2CaptureModelTests() {
    var grants: [ArisOnboardingStep: ArisGrant] = [.mic: .granted, .speech: .granted, .accessibility: .granted, .screen: .granted]
    var answers: [CheckedContinuation<ArisFirstCapture.Outcome, Never>] = []
    var taken = 0, allowed = false
    func actions() -> ArisOnboardingModel.Actions {
        ArisOnboardingModel.Actions(grant: { grants[$0] ?? .undecided }, request: { _ in }, stop: { _ in }, talkKeys: { ["⌥", "Space"] },
                                    firstCapture: {
                                        taken += 1
                                        return await withCheckedContinuation { answers.append($0) }
                                    },
                                    captureAllowed: { allowed })
    }
    func turn() { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

    // Back from Quit & Reopen: three ticks, and the capture is taken on the permissions page.
    for outcome in [ArisFirstCapture.Outcome.allowed, .declined, .unknown] {
        taken = 0
        let model = ArisOnboardingModel(actions: actions())
        var came: [ArisFirstCapture.Outcome] = []
        model.onFirstCapture = { came.append($0) }
        model.begin()
        check(model.captureNote == .asksOnceMore && !model.prompting, "vm2 bug 3: Screen Recording on, nothing asked yet: the card says macOS asks once more (\(outcome))")
        check(model.takeFirstCaptureIfDue(), "vm2 bug 3: the first capture is taken in the setup (\(outcome))")
        turn()
        check(taken == 1 && model.firstCapture == .asking && model.prompting && model.captureNote == .asksOnceMore,
              "vm2 bug 3: while macOS's prompt is up the setup holds the front as for the microphone's (\(outcome))")
        check(!model.takeFirstCaptureIfDue() && taken == 1, "vm2 bug 3: it is not taken twice while the prompt is up (\(outcome))")
        answers.removeFirst().resume(returning: outcome)
        turn()
        check(model.firstCapture == .done(outcome) && came == [outcome] && !model.prompting, "vm2 bug 3: what came of it reaches the card and the guide (\(outcome))")
        let expected: ArisFirstCapture.Note? = outcome == .allowed ? nil : outcome == .declined ? .declined : .unfinished
        check(model.captureNote == expected && model.state(.screen) == .granted, "vm2 bug 3: the card's line after \(outcome)")
        check(!model.takeFirstCaptureIfDue() && taken == 1, "vm2 bug 3: and it is not asked again in this setup (\(outcome))")
    }

    taken = 0
    grants[.screen] = .undecided
    let off = ArisOnboardingModel(actions: actions())
    off.begin()
    check(!off.takeFirstCaptureIfDue() && taken == 0 && off.captureNote == .asksOnceMore && off.flow.active == .screen,
          "vm2 bug 3: with Screen Recording not on nothing is captured; the open card says beforehand that macOS asks once more")
    off.allow(.screen)
    turn()
    check(!off.takeFirstCaptureIfDue() && taken == 0, "vm2 bug 3: nor while its System Settings list is up")
    grants[.screen] = .granted
    off.refresh()
    check(off.takeFirstCaptureIfDue() && off.prompting, "vm2 bug 3: the switch turned on: the capture is taken now")
    turn()
    answers.removeFirst().resume(returning: .allowed)
    turn()
    check(taken == 1 && off.captureNote == nil, "vm2 bug 3: allowed: Screen Recording is on, with nothing more to say")

    taken = 0
    allowed = true
    let before = ArisOnboardingModel(actions: actions())
    before.begin()
    check(!before.takeFirstCaptureIfDue() && taken == 0 && before.captureNote == nil, "vm2 bug 3: macOS said yes on an earlier run: the setup captures nothing and promises no prompt")
    allowed = false
    let later = ArisOnboardingModel(actions: actions(), page: .wake)
    later.begin()
    check(!later.takeFirstCaptureIfDue() && taken == 0, "vm2 bug 3: resumed on a later page, nothing is captured where no card explains it")

    // A model made the old way (no capture given) never claims a yes.
    let plain = ArisOnboardingModel(actions: ArisOnboardingModel.Actions(grant: { _ in .granted }, request: { _ in }, stop: { _ in }, talkKeys: { [] }))
    plain.begin()
    plain.takeFirstCaptureIfDue()
    turn()
    check(plain.firstCapture == .done(.unknown) && plain.captureNote == .unfinished, "vm2 bug 3: with no capture to take, the card does not say it was allowed")
}

// MARK: - Section 2.4: the AI page with no AI

private func vm2BrainHelpTests() {
    typealias R = ArisOnboardingBrainRows
    typealias W = ArisSetupWords
    check(R.command(.claude) == "claude" && R.command(.codex) == "codex login" && R.command(.antigravity) == "agy" && R.command(.api) == nil,
          "vm2 setup: each AI's Terminal command can be copied; the API key has its own form")
    for brain in [ArisBrain.claude, .codex, .antigravity] {
        let command = R.command(brain) ?? "?"
        check(ArisOnboardingCopy.brainHow(brain).contains("“\(command)”"), "vm2 setup: the command copied for \(brain.rawValue) is the one its line names")
        check(W.copyCommand(command, english: true).contains("“\(command)”") && W.copyCommand(command, english: false).contains("“\(command)”"),
              "vm2 setup: the card says which command a click copies (\(brain.rawValue))")
    }
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    let rows = R.rows(ready: none, chosen: "codex")
    check(rows.filter(R.copiesCommand).map(\.brain) == [.claude, .codex, .antigravity], "vm2 setup: with no AI, a click on the Claude, GPT or Gemini card copies its command")
    let some = R.rows(ready: [.claude: true, .codex: false, .antigravity: false, .api: true], chosen: "claude")
    check(some.filter(R.copiesCommand).map(\.brain) == [.codex, .antigravity], "vm2 setup: a card that is set up is picked, not copied")
    check(R.rows(ready: nil, chosen: nil).filter(R.copiesCommand).isEmpty, "vm2 setup: while the agent hasn't answered no card claims it needs setting up")
    check(W.thenCheckAgain(english: true).contains(ArisOnboardingCopy.brainAgain) && W.thenCheckAgain(english: false).contains("다시 확인"),
          "vm2 setup: each of those lines says what to do afterwards: press Check again")
    check(!W.copied(english: true).isEmpty && !W.copied(english: false).isEmpty && !W.copyHint(english: true).isEmpty && !W.copyHint(english: false).isEmpty,
          "vm2 setup: the card says it copied")

    // Check again: that it checked, and what it found.
    check(R.checked(answered: true, before: none, after: none) == .nothing, "vm2 setup: Check again with still no AI says so")
    check(R.checked(answered: false, before: none, after: none) == .unreachable && R.checked(answered: true, before: none, after: nil) == .unreachable
          && R.checked(answered: true, before: none, after: [:]) == .unreachable, "vm2 setup: the agent didn't answer: the page says it couldn't check, not that nothing is set up")
    var claude = none
    claude[.claude] = true
    check(R.checked(answered: true, before: none, after: claude) == .found([.claude]), "vm2 setup: Claude was installed since the last look: found")
    check(R.checked(answered: true, before: claude, after: claude) == .same([.claude]), "vm2 setup: nothing changed: said, with what is ready")
    var two = claude
    two[.api] = true
    check(R.checked(answered: true, before: claude, after: two) == .found([.api]) && R.checked(answered: true, before: nil, after: two) == .same([.claude, .api]),
          "vm2 setup: only what is new is called new, in the user's order; with no look before, nothing is new")
    check(R.checkingShown >= .milliseconds(400), "vm2 setup: \"Checking…\" stays long enough to be seen (the agent answers in a few ms)")
    let name: (ArisBrain) -> String = { $0 == .claude ? "Claude" : $0.rawValue }
    for english in [true, false] {
        let lines = [R.Checked.unreachable, .nothing, .found([.claude]), .same([.claude])].map { W.checked($0, names: name, english: english) }
        check(lines.allSatisfy { !$0.isEmpty } && Set(lines).count == 4, "vm2 setup: every result of Check again has its own line (\(english ? "en" : "ko"))")
        check(lines[2].contains("Claude") && lines[3].contains("Claude") && !lines[1].contains("Claude"), "vm2 setup: the line names what is ready (\(english ? "en" : "ko"))")
    }
    check(W.checked(.nothing, names: name, english: true).contains("no AI") && W.checked(.unreachable, names: name, english: true).contains("couldn't check"),
          "vm2 setup: the English lines say what was found, or that the check itself failed")
    let page = code(onboarding + "ArisOnboardingBrainPage.swift")
    check(page.contains("check(pressed: true)") && page.contains("guide.brainChecked = Rows.checked(answered: answered, before: before, after: setup.ready)")
          && page.contains("ArisSetupWords.checked(checked"), "vm2 setup: a press of Check again leaves its result on the page")
    check(page.contains("NSPasteboard.general.setString(command, forType: .string)") && page.contains("!Rows.copiesCommand(row)"),
          "vm2 setup: a click on a card that isn't set up copies its command instead of doing nothing")
    check(!page.contains("repeatForever") && !page.contains("Circle()"), "vm2 setup: the page shows the check in words: no dot, nothing that blinks")
}

// MARK: - Bug 3: the aris-agent row, and the icon that is really in the list

private func vm2HelperRowTests() {
    // One row: the helper lives inside the app, so no second row appears and the panel says nothing about one.
    let panel = code("Aris/private/Aris/ArisPermissionGuide.swift")
    check(!panel.contains("helperRow") && !code("Aris/private/Aris/Onboarding/ArisOnboardingWords.swift").contains("aris-agent"),
          "one row: the helper panel has one row to drag and no sentence about a second one")
    check(panel.contains("ArisOwnAppIcon(size: 32)") && !panel.contains("ArisOnboardingStar"),
          "vm2 setup: the helper panel's row shows the app's own icon, the one the list will show, not the star")
    check(panel.contains("NSApplication.shared.applicationIconImage"), "vm2 setup: that icon is the running app's own")
    let preview = code(onboarding + "ArisOnboardingPreview.swift")
    let list = part(preview, from: "struct ArisMacSettings", to: "struct ArisMacCursor")
    check(list.contains("ArisOwnAppIcon") && !list.contains("ArisOnboardingStar"), "vm2 setup: the list picture and its panel show the app's own icon")
    check(list.contains("if added {") && list.contains("Text(\"+\")"), "vm2 setup: the list picture has no Aris until it is added, and shows the list's own + and −")
    check(preview.contains("score.added(t)") && preview.contains("score.carrying(t)") && preview.contains("ArisMacDragPanel(dark: palette.dark"),
          "vm2 setup: the picture shows what the user does: the row dragged from the helper panel into the list, then its switch")
    // The cause of the row, as read: aris-agent asks macOS whether it is trusted when it looks at the screen.
    check(code("ArisAgent/ArisLook.swift").contains("let trusted = AXIsProcessTrusted()"), "vm2 bug 3: aris-agent's look asks macOS about Accessibility, which is what adds its row")
}

// MARK: - Wiring

private func vm2WiringTests() {
    let guide = code(onboarding + "ArisOnboardingGuide.swift"), setup = code(onboarding + "ArisOnboardingGuide+Setup.swift")
    let leave = code(onboarding + "ArisOnboardingGuide+Leave.swift")
    check(guide.contains("self?.noteFront(bundleID: bundleID, regular: regular)") && guide.contains("self?.appCameForward(bundleID: bundleID, regular: regular)"),
          "vm2 bug 5: the guide notes who comes forward, and yesterday's front rule still hears it")
    check(guide.contains("if window != nil { stepBackFromSettings() }") && guide.contains("handBack()") && guide.contains("beginLeave()"),
          "vm2 bug 5: closing the setup window (✕, Esc, Finish later) steps back from the System Settings it opened")
    let quit = part(guide, from: "func closeForQuit()", to: "private func persist()")
    check(quit.contains("quitting = true") && guide.contains("if !quitting { forgetLeave() }") && leave.contains("if leave != before { keepLeave() }"),
          "vm2 bug 5: quitting mid-setup hides nothing, and what the setup opened stays kept for when Aris is back")
    let finish = part(setup, from: "func finish()", to: "guide.audio?.ambient(false")
    check(finish.contains("stepBackFromSettings()") && finish.contains("guide.handBack()"), "vm2 bug 5: Finish steps back from System Settings as the window fades, then hands the front back")
    check(setup.contains("sendingToSettings(for: card)"), "vm2 bug 5: a card's Allow tells the guide it is sending the user to System Settings")
    check(leave.contains("leave.plan(runningPid: settings?.processIdentifier, quitting: quitting)") && leave.contains("settings?.hide()")
          && !leave.contains("terminate()"), "vm2 bug 5: System Settings is hidden, never quit, and only as the pure plan says")
    check(setup.contains("takeFirstCaptureSoon(after:") && setup.contains("model.onFirstCapture = { [weak self] outcome in self?.firstCaptureEnded(outcome) }"),
          "vm2 bug 3: the guide takes the first capture on the permissions page and hears what came of it")
    check(code(onboarding + "ArisOnboardingGuide+FirstCapture.swift").contains("if ArisFirstCapture.comesForward(after: outcome) { comeForward(after: .promptAnswered) }"),
          "vm2 bug 3: the setup comes forward again only after a yes")

    let capture = code("Aris/private/Aris/See/ArisScreenCapture.swift")
    let first = part(source("Aris/private/Aris/See/ArisScreenCapture.swift"), from: "func firstCapture() async -> ArisFirstCapture.Outcome", to: "// MARK: - Capture chain")
    check(first.contains("guard CGPreflightScreenCaptureAccess(), !IsSecureEventInputEnabled() else { return .unknown }") && first.contains("budget: .consent"),
          "vm2 bug 3: the setup's capture needs the grant, never runs while a password field has the keyboard, and is the smallest frame")
    check(!first.contains("windowList(") && !first.contains("ArisCaptured") && !capture.contains("CGRequestScreenCaptureAccess"),
          "vm2 bug 3: it goes through ScreenCaptureKit only, keeps no image, and macOS's own Screen Recording request is still never raised")
    check(ArisImageBudget.consent.fit(CGSize(width: 3024, height: 1964)).width <= 64, "vm2 bug 3: that frame is at most 64 pixels wide")
    let system = code(onboarding + "ArisOnboardingSystem.swift")
    check(system.contains("if outcome == .allowed { ArisAppCaptureFirst.allowed() }") && code("Aris/private/Aris/See/ArisAppCaptureFirst.swift").contains("defaults.set(true, forKey: ArisFirstCapture.allowedKey)"), "vm2 bug 3: a yes is remembered, so the setup never captures for it again")
    let card = code(onboarding + "ArisOnboardingPermissions.swift")
    check(card.contains("note: card == .screen ? model.captureNote.map { ArisSetupWords.captureNote($0) } : nil"), "vm2 bug 3: the Screen Recording card shows the line")

    // The wake word page: the default is off, and Return must not pick "Yes, turn it on".
    let wake = code(onboarding + "ArisOnboardingWakePage.swift")
    check(!wake.contains("keyboardShortcut") && !wake.contains("defaultAction"), "vm2 setup: on the wake word page Return and Enter pick nothing (never \"Yes, turn it on\")")
    let tokens = code(onboarding + "ArisOnboardingTokens.swift")
    check(!part(tokens, from: "struct ArisGlassRect", to: "struct ArisBackButtonStyle").contains("keyboardShortcut"),
          "vm2 setup: the glass button, the page's highlighted one, is no default button anywhere")
    check(ArisWakeWordDefault.isOff, "vm2 setup: and the wake word's default is still off")
}

/// The wake word's default, read from where the preference is declared.
private enum ArisWakeWordDefault {
    static var isOff: Bool {
        let text = (try? FileManager.default.subpathsOfDirectory(atPath: root.appendingPathComponent("Aris").path))?
            .filter { $0.hasSuffix(".swift") }
            .compactMap { try? String(contentsOf: root.appendingPathComponent("Aris/" + $0), encoding: .utf8) }
            .first { $0.contains("static let arisWakeWord = Key<Bool>(") } ?? ""
        return text.contains("static let arisWakeWord = Key<Bool>(\"arisWakeWord\", default: false")
    }
}
