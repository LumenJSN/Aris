// Tests for what the VM run of 2026-11-10 found (qa/vm-run-1110/REPORT.md): the 사용량 tab that never finished loading
// on a Mac with no Claude Code or Codex (bug 3), and the plain defects in the list under bug 7.
// Called from main.swift; uses its check().
import AppKit
import Foundation

func runVMUsageTests() {
    usageDeskTests()
    usagePatienceTests()
    usageTabStateTests()
    terminationSignalTests()
    permissionPromptTests()
    cardListenLogTests()
    aboutCommitTests()
    unpickedBrainTests()
    modelCardFitTests()
    failedStepTests()
}

/// A file of the repository, as text.
private func repositoryFile(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

// MARK: - Bug 3: the 사용량 tab

/// A source that answers after `delay` with `answer` (nil: this AI isn't on this Mac).
private final class FakeUsageSource: ArisUsageSource, @unchecked Sendable {
    let id: String
    let every: TimeInterval = 600
    let background: Bool
    private let delay: TimeInterval
    private let answer: ArisUsageProvider?

    init(_ id: String, delay: TimeInterval = 0, listed: Bool = true, background: Bool = false) {
        self.id = id
        self.delay = delay
        self.background = background
        answer = listed ? ArisUsageProvider(id: id, title: id, lanes: [], updatedAt: Date(timeIntervalSince1970: 0)) : nil
    }

    func limits(now: Date) -> ArisUsageProvider? {
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        return answer
    }
}

private func usageDeskTests() {
    // One AI answers at once, one takes a second and a half, one isn't on this Mac.
    let desk = ArisUsageDesk(sources: [FakeUsageSource("quick"), FakeUsageSource("slow", delay: 1.5), FakeUsageSource("absent", listed: false)])
    let began = Date()
    let first = desk.report(now: began, wait: 0.3)
    check(Date().timeIntervalSince(began) < 1.2, "usage: a report waits no longer than its limit for an AI that is slow to answer")
    check(first.providers.map(\.id) == ["quick"], "usage: the AI that answered is listed while another is still being asked")
    check(first.pending == ["slow"], "usage: the report names the AI it is still asking, and only that one")
    Thread.sleep(forTimeInterval: 1.6)
    let second = desk.report(now: Date(), wait: 0.3)
    check(second.providers.map(\.id) == ["quick", "slow"], "usage: the slow AI is listed by the next ask, in the sources' order")
    check(second.pending == nil, "usage: nothing is pending once every AI has answered")
    check(!second.providers.contains { $0.id == "absent" }, "usage: an AI that isn't on this Mac is not listed")

    let none = ArisUsageDesk(sources: [FakeUsageSource("a", listed: false), FakeUsageSource("b", listed: false)])
    let empty = none.report(now: Date(), wait: 0.3)
    check(empty.providers.isEmpty && empty.pending == nil, "usage: with no AI on this Mac the report is empty and waits for nothing")

    // A source that takes seconds by design (agy) is never waited for; the report says it is still being asked.
    let late = ArisUsageDesk(sources: [FakeUsageSource("quick"), FakeUsageSource("agy", delay: 1, background: true)])
    let lateBegan = Date()
    let lateReport = late.report(now: lateBegan, wait: 5)
    check(Date().timeIntervalSince(lateBegan) < 0.8 && lateReport.providers.map(\.id) == ["quick"] && lateReport.pending == ["agy"],
          "usage: a background source is not waited for, and is named as pending")
    let all = ArisUsageDesk(sources: [FakeUsageSource("quick"), FakeUsageSource("agy", delay: 0.4, background: true)])
    check(all.report(now: Date(), wait: 5, waitForAll: true).providers.map(\.id) == ["quick", "agy"], "usage: the report for the command line waits for every source")

    let wire = ArisUsageReport(providers: [], pending: ["claude"])
    check(ArisUsageReport.decode(wire.encoded()) == wire, "usage: the pending ids survive the trip from the agent to the app")
    check(ArisUsageReport.decode(Data("{\"providers\":[]}".utf8)) == ArisUsageReport(providers: [], pending: nil),
          "usage: a report with no pending field (an earlier agent) reads as nothing pending")
    check(!String(decoding: ArisUsageReport.empty.encoded(), as: UTF8.self).contains("pending"), "usage: a report with nothing pending leaves the field out")
}

private func usagePatienceTests() {
    let began = Date(timeIntervalSince1970: 1_000)
    check(!ArisUsagePatience.asksAgain(pending: nil, began: began, now: began) && !ArisUsagePatience.asksAgain(pending: [], began: began, now: began),
          "usage: with nothing pending the app does not ask again")
    check(ArisUsagePatience.asksAgain(pending: ["claude"], began: began, now: began.addingTimeInterval(4)), "usage: while an AI is pending the app asks again")
    check(!ArisUsagePatience.asksAgain(pending: ["claude"], began: began, now: began.addingTimeInterval(ArisUsagePatience.followUp)),
          "usage: an AI that never answers stops being waited for at the stated limit")
    check(ArisUsagePatience.report < ArisUsagePatience.ask, "usage: the app waits longer for the agent than the agent waits for an AI, so the agent's answer arrives")
    check(ArisUsagePatience.ask + ArisUsagePatience.followUp <= 60, "usage: everything the tab can wait for adds up to under a minute")
}

private func usageTabStateTests() {
    check(ArisUsageTabState.of(hasProviders: false, read: .waiting) == .loading, "usage tab: before the first read ends it says it is loading")
    check(ArisUsageTabState.of(hasProviders: false, read: .answered) == .none, "usage tab: a read that found no AI ends the loading line (VM bug 3)")
    check(ArisUsageTabState.of(hasProviders: false, read: .unanswered) == .unread, "usage tab: a read the agent never answered says so, not loading")
    check([ArisUsageRead.waiting, .answered, .unanswered].allSatisfy { ArisUsageTabState.of(hasProviders: true, read: $0) == .listed },
          "usage tab: limits that are known show, whatever the latest read did")

    check(ArisUsageRead.waiting.after(answered: true, asksAgain: false) == .answered, "usage read: an answer with nothing pending settles it")
    check(ArisUsageRead.waiting.after(answered: true, asksAgain: true) == .waiting, "usage read: the first answer with an AI still pending keeps waiting")
    check(ArisUsageRead.answered.after(answered: true, asksAgain: true) == .answered,
          "usage read: a later read with an AI pending does not put the loading line back")
    check(ArisUsageRead.unanswered.after(answered: true, asksAgain: true) == .waiting, "usage read: after a failed read, an answer with an AI pending waits again")
    check([ArisUsageRead.waiting, .answered, .unanswered].allSatisfy { $0.after(answered: false, asksAgain: false) == .unanswered },
          "usage read: no answer from the agent is told apart from an empty one")

    check(ArisUsageRead.unanswered.beginning == .waiting, "usage read: trying again after no answer shows loading while it reads")
    check(ArisUsageRead.answered.beginning == .answered && ArisUsageRead.waiting.beginning == .waiting, "usage read: a new read leaves a settled one as it is")

    for english in [false, true] {
        let lines = [ArisUsageTabCopy.loading(english: english), ArisUsageTabCopy.none(english: english), ArisUsageTabCopy.unread(english: english),
                     ArisUsageTabCopy.retry(english: english)]
        check(lines.allSatisfy { !$0.isEmpty && !$0.contains("\n") } && Set(lines).count == lines.count, "usage tab: each state has its own one line (\(english ? "English" : "Korean"))")
    }
    check(ArisUsageTabCopy.none(english: true).contains("Claude") && ArisUsageTabCopy.none(english: false).contains("Claude"),
          "usage tab: the empty line names the AIs whose limits it can show")
    check(ArisUsageTabCopy.none(english: false).unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
          && !ArisUsageTabCopy.none(english: true).unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) },
          "usage tab: the empty line is Korean on a Korean Mac and has no Korean on an English one")
}

// MARK: - Bug 7: Aris.app did not exit on SIGTERM

/// A flag two threads share.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }
}

private func terminationSignalTests() {
    // As in the app: a library took SIGTERM for itself at load with a handler that ends nothing.
    signal(SIGTERM) { _ in }
    let asked = DispatchSemaphore(value: 0)
    ArisTerminationSignal.watch { asked.signal() }
    kill(getpid(), SIGTERM)
    check(asked.wait(timeout: .now() + 3) == .success, "sigterm: a SIGTERM reaches Aris's own handler, off the main thread, whatever handler was there before")
    ArisTerminationSignal.watch { asked.signal() }
    kill(getpid(), SIGTERM)
    check(asked.wait(timeout: .now() + 3) == .success && asked.wait(timeout: .now() + 0.3) == .timedOut, "sigterm: watching again replaces the earlier watch, so one signal asks once")
    ArisTerminationSignal.unwatch()

    // The main thread is busy here (the tests never return to it), as in an app whose main thread is stuck: the normal
    // quit can't run, and the exit after the grace does.
    let quit = Flag(), forced = DispatchSemaphore(value: 0)
    let began = Date()
    ArisTerminationSignal.quit(grace: 0.3, quit: { quit.raise() }, force: { forced.signal() })
    check(forced.wait(timeout: .now() + 3) == .success && Date().timeIntervalSince(began) >= 0.25 && !quit.isRaised,
          "sigterm: with the main thread stuck, Aris still exits once the grace is over")
    check(ArisTerminationSignal.grace >= 2 && ArisTerminationSignal.grace <= 5, "sigterm: a normal quit gets a few seconds, less than an installer waits before it kills")
}

// MARK: - Bug 7: what macOS's permission prompts say Aris does

private func permissionPromptTests() {
    let project = repositoryFile("Aris.xcodeproj/project.pbxproj")
    let plist = repositoryFile("Aris/Info.plist")
    let catalog = (try? JSONSerialization.jsonObject(with: Data(repositoryFile("Aris/InfoPlist.xcstrings").utf8))) as? [String: Any]
    let strings = catalog?["strings"] as? [String: Any] ?? [:]
    func localized(_ key: String, _ language: String) -> String {
        let localizations = (strings[key] as? [String: Any])?["localizations"] as? [String: Any]
        return ((localizations?[language] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? ""
    }
    /// The reason the build settings give for `key` (both configurations must say the same).
    func built(_ key: String) -> String? {
        let marker = "INFOPLIST_KEY_\(key) = \""
        let values = Set(project.components(separatedBy: marker).dropFirst().map { String($0.prefix { $0 != "\"" }) })
        return values.count == 1 ? values.first : nil
    }
    let keys = ["NSRemindersUsageDescription", "NSCalendarsUsageDescription", "NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription",
                "NSAppleEventsUsageDescription"]
    for key in keys {
        let reason = built(key) ?? ""
        check(reason.hasPrefix("Aris ") && reason.hasSuffix(".") && !reason.dropLast().contains(". "), "prompts: \(key) says in one sentence what Aris does")
        check(!reason.contains("This app") && !reason.contains("AppleEvents"), "prompts: \(key) names Aris and uses no developer's word")
        check(localized(key, "en") == reason, "prompts: \(key)'s English in the string catalog is the build's own sentence")
        let korean = localized(key, "ko")
        check(korean.hasPrefix("Aris") && korean.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "prompts: \(key) has its Korean")
    }
    check(built("NSRemindersUsageDescription")?.contains("calendar") == false && built("NSRemindersUsageDescription")?.contains("to-do") == true,
          "prompts: the Reminders prompt is about Aris's to-dos, not a calendar (VM bug 7)")
    check(!project.contains("NSContactsUsageDescription"), "prompts: no reason is given for Contacts, which the app never asks for")
    // The one reason kept in Info.plist itself (it has two sentences on purpose: what is measured and what isn't kept).
    check(plist.contains("<string>\(localized("NSAudioCaptureUsageDescription", "en"))</string>") && !localized("NSAudioCaptureUsageDescription", "en").isEmpty,
          "prompts: the system-audio reason in the catalog is Info.plist's own")
    check(localized("NSAudioCaptureUsageDescription", "ko").unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "prompts: the system-audio reason has its Korean")
    let everyKey = keys + ["NSAudioCaptureUsageDescription"]
    check(Set(strings.keys) == Set(everyKey), "prompts: the catalog has every reason the app gives and no other")
}

// MARK: - Bug 7: a card with no speech model yet logged an error each time

private func cardListenLogTests() {
    let preparing = ArisListenerWords.modelPreparing(english: true), preparingKorean = ArisListenerWords.modelPreparing(english: false)
    check(preparing.contains("still getting ready") && ArisCardListenLog.isModelPreparing(preparing) && ArisCardListenLog.isModelPreparing(preparingKorean),
          "listen log: the listener's 'model still getting ready' line is known in both languages")
    let first = ArisCardListenLog().failed(preparing)
    check(first.level == .notice, "listen log: no speech model yet is a notice, not an error (VM bug 7)")
    let second = first.next.failed(preparingKorean)
    check(second.level == .silent && second.next.failed(preparing).level == .silent, "listen log: it is said once, not at every card")
    check(second.next.started().failed(preparing).level == .notice, "listen log: after listening has worked, a model that is missing again is said again, once")
    check(ArisCardListenLog().failed("Couldn't read the microphone.").level == .error && first.next.failed("Couldn't read the microphone.").level == .error,
          "listen log: any other failure is an error every time")
    check(first.next.failed("Couldn't read the microphone.").next == first.next, "listen log: another failure does not make the model notice come back")
    check(ArisCardListenLog().failed("").level == .error, "listen log: a failure with no words of Aris's own is an error")
}

// MARK: - Bug 7: Settings › 정보 showed no commit

private func aboutCommitTests() {
    check(ArisBuildInfo.buildDetail(number: "1", commit: "13758537") == "1 · 13758537", "about: the build is shown with its commit")
    check(ArisBuildInfo.buildDetail(number: "1", commit: ArisBuildInfo.unstamped) == "1 · dev" && ArisBuildInfo.buildDetail(number: nil, commit: "abc") == "? · abc",
          "about: a build with no stamp says dev, and a missing number a question mark")
    check(repositoryFile("Aris/components/Settings/ArisLiveSettings.swift").contains("(\\(ArisBuildInfo.buildDetail(number: Bundle.main.buildVersionNumber)))"),
          "about: Settings › 정보's version line is made with the commit")
    // The line still has its English: the catalog's two version sentences take the build and commit as one value.
    let table = ArisSettingsCopy.pairs(catalog: Data(repositoryFile("Aris/components/Settings/Settings.xcstrings").utf8))
    var copy = ArisSettingsCopyTable(table)
    check(copy.english("버전 0.1.0 (1 · 13758537)") == "Version 0.1.0 (1 · 13758537)", "about: the version line with a commit is still English on an English Mac")
    check(copy.english("Sol · 버전 1.4 (212 · 3f2a1b9c)") == "Sol · Version 1.4 (212 · 3f2a1b9c)", "about: and with a release name before it")
}

// MARK: - Bug 7: a new Mac with no AI showed and blamed Codex, which the user never chose

private func unpickedBrainTests() {
    typealias C = ArisBrainChoice
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    let claudeOnly: [ArisBrain: Bool] = [.claude: true, .codex: false, .antigravity: false, .api: false]
    let codexGone = ArisBrainTrouble.cannotStart(.codex, korean: false), codexGoneKorean = ArisBrainTrouble.cannotStart(.codex, korean: true)
    let noAI = ArisBrainTrouble(brain: nil, missing: .any)

    // What the settings show as chosen.
    check(C.shown("codex", stored: nil, ready: none) == "", "brain: with nothing picked and no AI set up, the settings show none as chosen, not the key's default (VM bug 7)")
    check(C.shown("codex", stored: "codex", ready: none) == "codex", "brain: a brain the user stored stays shown as chosen though it isn't set up (security review M5)")
    check(C.shown("codex", stored: nil, ready: nil) == "codex" && C.shown("codex", stored: nil, ready: [.claude: false]) == "codex",
          "brain: before the agent has answered for every AI, nothing is claimed: the value shows as it is")
    check(C.shown("codex", stored: nil, ready: claudeOnly) == "codex", "brain: with an AI set up the value shows (ArisBrainSetup is about to store that AI)")
    check(C.shown("claude", stored: "nonsense", ready: none) == "", "brain: a stored name that is no brain is no choice")

    var settings = ArisSettingsSnapshot(); settings.brains = ArisBrain.allCases.map { .init(id: $0.rawValue, title: $0.shortTitle) }; settings.brain = C.shown("codex", stored: nil, ready: none)
    check(settings.brainTitle == "없음", "brain: with none chosen, 대화's 기본으로 답하는 AI row reads 없음, not Codex")
    settings.brain = "codex"; check(settings.brainTitle == "Codex", "brain: a chosen brain reads by its name")

    // What a failed turn says.
    check(C.failureLine(codexGone, stored: nil, ready: none) == noAI.line(korean: false),
          "brain: an AI the user never picked is not named as missing: the line says no AI is ready (VM bug 7)")
    check(C.failureLine(codexGoneKorean, stored: nil, ready: none) == noAI.line(korean: true), "brain: in Korean when the line was Korean")
    check(ArisBrainTrouble.isCannotStart(C.failureLine(codexGone, stored: nil, ready: none)), "brain: the new line still gets the button to Settings › AI 서비스")
    check(C.failureLine(codexGone, stored: "codex", ready: none) == codexGone, "brain: a brain the user stored is named when it can't start")
    check(C.failureLine(codexGone, stored: nil, ready: claudeOnly) == codexGone && C.failureLine(codexGone, stored: nil, ready: nil) == codexGone,
          "brain: with another AI set up, or nothing known yet, the line stays as the agent wrote it")
    let noKey = ArisBrainTrouble(brain: .api, missing: .key).line(korean: false)
    check(C.failureLine(noKey, stored: nil, ready: none) == noAI.line(korean: false), "brain: an API brain nobody picked, with no key, reads the same way")
    check(C.failureLine("The network is down.", stored: nil, ready: none) == "The network is down." && C.failureLine(noAI.line(korean: true), stored: nil, ready: none) == noAI.line(korean: true),
          "brain: any other failure is passed on untouched")

    // The ruling stands: nothing here stores or replaces a brain.
    check(C.resolve(stored: "codex", ready: none) == nil && C.resolve(stored: "codex", ready: claudeOnly) == nil && C.resolve(stored: nil, ready: none) == nil,
          "brain: a stored brain is never replaced, and with no AI set up nothing is stored")
}

// MARK: - Bug 7: the dictation-model card cut "About 220 MB · a few hundred…" off

private func modelCardFitTests() {
    check(ArisModelOffer.choiceTextRoom == 177, "model card: a model's button leaves its lines 177 points (440 wide, 16 in, 6 between, 12 inside)")
    let font = NSFont.systemFont(ofSize: ArisModelOffer.costFontSize)
    for english in [false, true] {
        for model in ArisSpeechModel.allCases {
            let line = ArisModelOffer.cost(model, english: english)
            let width = Double((line as NSString).size(withAttributes: [.font: font]).width)
            check(width <= ArisModelOffer.choiceTextRoom - 4, "model card: “\(line)” fits its button with room to spare (\(Int(width.rounded())) of 177 points)")
        }
    }
    let was = Double(("About 220 MB · a few hundred MB of memory" as NSString).size(withAttributes: [.font: font]).width)
    check(was > ArisModelOffer.choiceTextRoom, "model card: the line the VM run saw cut off did not fit (so this check would have caught it)")
    check(ArisModelOffer.cost(.small, english: true) == "220 MB · under 1 GB of memory" && ArisModelOffer.cost(.large, english: true) == "630 MB · 1–2 GB of memory",
          "model card: both models say their size and their memory the same way in English")
    check(ArisModelOffer.cost(.small, english: false) == "약 220 MB · 메모리 수백 MB", "model card: the Korean line is as it was")
}

// MARK: - Bug 7: a failed to-do add still showed "Adding a to-do ✓"

private func failedStepTests() {
    // The turn: the AI adds a to-do, the tool says it couldn't, the AI answers "I couldn't add it".
    let working = ArisSession().listening().hearing("add a to-do: buy milk").thinking().working("할 일 추가 중")
    check(working.tags.map(\.label) == ["할 일 추가 중"] && working.tags.allSatisfy { !$0.done && !$0.failed }, "chip: a step that is running has no tick and no mark")
    let failed = working.stepFailed("할 일 추가 중")
    check(failed.steps.map(\.failed) == [true] && failed.steps.map(\.done) == [true], "chip: a step the agent says failed is settled as failed")
    let answered = failed.answering("I couldn't add it.")
    check(answered.tags.map(\.failed) == [true] && answered.done().tags.map(\.failed) == [true],
          "chip: the answer does not turn a failed step into a done one: no tick under \"I couldn't add it\" (VM bug 7)")
    check(working.answering("Added it.").tags.map(\.failed) == [false] && working.answering("Added it.").tags.map(\.done) == [true], "chip: a step that worked still gets its tick")

    // Which step: the one the label names (by its tool), else the one running, else the last.
    let two = working.working("날씨 보는 중")
    check(two.stepFailed("할 일 추가 중").steps.map(\.failed) == [true, false], "chip: the failure marks the step it names, though another runs now")
    check(two.stepFailed(nil).steps.map(\.failed) == [false, true], "chip: with no name it marks the step that is running")
    check(two.stepFailed("메일 보는 중").steps.map(\.failed) == [false, true], "chip: a name no step has marks the running one too")
    check(two.answering("…").stepFailed(nil).steps.map(\.failed) == [false, false] && ArisSession().stepFailed(nil).steps.isEmpty,
          "chip: nothing is marked once the turn has answered, or with no step at all")
    // The same tool tried again runs afresh, and its tick is the retry's.
    let retried = failed.working("할 일 추가 중")
    check(retried.steps.map(\.failed) == [false] && retried.steps.map(\.done) == [false] && retried.answering("Added.").tags.map(\.done) == [true],
          "chip: trying the same step again clears the mark")
    check(two.stepFailed("할 일 추가 중").working("메일 보는 중").steps.map(\.failed) == [true, false, false], "chip: a later step leaves the failed one marked")

    // The wire, agent → app.
    let line = String(decoding: ArisAgentReply.stepFailed("할 일 추가 중").line, as: UTF8.self)
    check(ArisAgentReply.parse(line) == .stepFailed("할 일 추가 중") && !ArisAgentReply.stepFailed("x").isLast, "chip: the failed step crosses from the agent to the app, and is not the turn's last line")
    check(ArisAgentReply.parse(String(decoding: ArisAgentReply.stepFailed(nil).line, as: UTF8.self)) == .stepFailed(nil), "chip: and with no name")
    check(!line.contains("\"status\""), "chip: the line is no status line (an app that doesn't know it shows nothing new)")

    // What each brain's process says when a call failed.
    let tools = "/opt/aris/aris-tools"
    check(ArisStepOutcome.api(toolDone: ["type": "tool_done", "id": "c1", "exit": 1], argv: ["todo", "add", "buy milk"], tools: tools) == [.stepFailed("할 일 추가 중")],
          "chip: the API brain's call that exits with an error fails its step, by the step's own words")
    check(ArisStepOutcome.api(toolDone: ["type": "tool_done", "id": "c1", "exit": 0], argv: ["todo", "add", "buy milk"], tools: tools).isEmpty
          && ArisStepOutcome.api(toolDone: ["type": "tool_done", "id": "c1"], argv: ["todo", "add", "x"], tools: tools).isEmpty,
          "chip: a call that worked, or one that doesn't say, fails nothing")
    check(ArisStepOutcome.api(toolDone: ["exit": 2], argv: nil, tools: tools) == [.stepFailed(nil)], "chip: a failed call whose command is no longer known fails the running step")
    let codexFailed: [String: Any] = ["type": "commandExecution", "id": "i1", "command": "/bin/zsh -lc '\(tools) todo add \"buy milk\"'", "exitCode": 1, "status": "failed"]
    check(ArisStepOutcome.codex(completed: codexFailed, tools: tools) == [.stepFailed("할 일 추가 중")], "chip: Codex's command that exits with an error fails its step")
    var codexOK = codexFailed; codexOK["exitCode"] = 0; codexOK["status"] = "completed"
    check(ArisStepOutcome.codex(completed: codexOK, tools: tools).isEmpty && ArisStepOutcome.codex(completed: ["type": "agentMessage", "text": "hi"], tools: tools).isEmpty
          && ArisStepOutcome.codex(completed: ["type": "commandExecution", "command": "ls", "status": "declined"], tools: tools).isEmpty,
          "chip: Codex's command that worked, a message, or a command that was never run fails nothing")
    let claudeFailed = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"Exit code 1"}]}}"#
    let claudeOK = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"added"}]}}"#
    check(ArisStepOutcome.claude(line: claudeFailed) == [.stepFailed(nil)] && ArisStepOutcome.claude(line: claudeOK).isEmpty
          && ArisStepOutcome.claude(line: #"{"type":"assistant","message":{"content":[]}}"#).isEmpty && ArisStepOutcome.claude(line: "not json").isEmpty,
          "chip: Claude's tool result that is an error fails the running step; anything else fails nothing")
}
