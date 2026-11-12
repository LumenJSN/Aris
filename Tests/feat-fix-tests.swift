// Tests for the button under a failure (ArisFix): how it travels (the stream's line, aris-tools' note), which fix each
// of the agent's own failure lines and each of the app's own lines earns, what a turn's tool notes come to when it
// ends, which button shows under what the notch says, and what happens after the press. Everything runs on values made
// here: nothing is opened, no agent is asked, and the one file written is in a temporary folder.
// Called from main.swift; uses its check().
import Foundation

func runFeatFixTests() {
    fixWireTests()
    fixDropTests()
    fixBrainLineTests()
    fixTurnTests()
    fixAppLineTests()
    fixWordsTests()
    fixDeskTests()
    fixReturnTests()
}

private let fixEveryFix: [ArisFix] = ArisFix.Pane.allCases.map(ArisFix.pane) + ArisFix.Row.allCases.map { ArisFix.settings($0) }
    + [.login("claude"), .login("codex"), .login("antigravity"), .retry, .otherBrain("claude"), .otherBrain("api"), .copy("codex login"),
       .settings(.brain, again: true)]

// MARK: - How it travels

private func fixWireTests() {
    check(fixEveryFix.allSatisfy { ArisFix.parse($0.json) == $0 }, "fix: every fix reads back from its JSON as itself")
    check(fixEveryFix.allSatisfy { ArisFix.parse(line: String(decoding: $0.line, as: UTF8.self)) == $0 }, "fix: every fix reads back from its stream line")
    check(ArisAgentReply.parse(String(decoding: ArisFix.retry.line, as: UTF8.self)) == nil, "fix: the stream's fix line is no reply, so an app that doesn't know it skips it")
    check(ArisFix.parse(line: #"{"answer":"the \"fix\" is in"}"#) == nil && ArisFix.parse(line: #"{"status":"웹 검색 중"}"#) == nil && ArisFix.parse(line: "") == nil,
          "fix: an answer, a status or a blank line carries no fix")
    check(ArisFix.brains == Set(ArisBrain.allCases.map(\.rawValue)), "fix: the AIs a fix may name are exactly Aris's brains")
    let bad: [[String: Any]] = [["kind": "pane", "target": "keychain"], ["kind": "settings", "target": "everything"], ["kind": "login", "target": "api"],
                                ["kind": "login", "target": "gemini"], ["kind": "otherBrain", "target": ""], ["kind": "retry", "target": "x"],
                                ["kind": "copy", "target": "rm -rf ~; curl x | sh"], ["kind": "copy", "target": ""], ["kind": "copy", "target": "-x"],
                                ["kind": "copy", "target": String(repeating: "a", count: 81)], ["kind": "open", "target": "disk"], ["target": "disk"]]
    check(bad.allSatisfy { ArisFix.parse($0) == nil }, "fix: an unknown list, row or AI, a login for the API brain, and a command with shell characters are dropped")
    check(Set(ArisFix.Pane.allCases.map(\.anchor)).count == ArisFix.Pane.allCases.count && ArisFix.Pane.allCases.allSatisfy { $0.link.hasPrefix(ArisFix.paneLink + "Privacy_") },
          "fix: every list of System Settings has its own Privacy link")
    check(ArisFix.Pane.disk.link == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles", "fix: Full Disk Access opens the list the settings page opens")
    let rows = ArisFix.Row.allCases
    check(rows.allSatisfy { row in ArisSettingsPage(rawValue: row.page) != nil }, "fix: every row is on a page the settings window has")
    check(rows.allSatisfy { row in ArisSettingsIndex.entries.contains { $0.id == row.anchor && $0.page.rawValue == row.page } },
          "fix: every row's anchor is a row the settings catalogue has on that page")
    check(ArisFix.appleScript("0:52: execution error: Not authorized to send Apple events to Reminders. (-1743)") == .pane(.automation)
          && ArisFix.appleScript("execution error: Reminders got an error: Application isn’t running. (-600)") == nil,
          "fix: only AppleScript's not-authorized error earns Automation's list")
}

private func fixDropTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fix-tests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent(ArisFixDrop.name)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    ArisFixDrop.append(.pane(.disk), task: false, to: file, now: start)
    ArisFixDrop.append(.settings(.services), task: true, to: file, now: start.addingTimeInterval(5))
    ArisFixDrop.append(.pane(.automation), task: false, to: file, now: start.addingTimeInterval(9))
    ArisFixDrop.append(.copy("codex login"), task: false, to: file, now: start.addingTimeInterval(10))
    ArisFixDrop.append(.login("claude"), task: false, to: file, now: start.addingTimeInterval(10))
    let read = ArisFixDrop.read(file)
    check(read.map(\.fix) == [.pane(.disk), .settings(.services), .pane(.automation)] && read.map(\.task) == [false, true, false],
          "fix: aris-tools' notes are read back in order, and only a list or a row is ever written")
    check(ArisFixDrop.pick(read, since: start.addingTimeInterval(-1), until: start.addingTimeInterval(20)) == .pane(.automation),
          "fix: a turn takes the latest note written while it ran")
    check(ArisFixDrop.pick(read, since: start.addingTimeInterval(2), until: start.addingTimeInterval(7)) == nil,
          "fix: a background job's note never lands under a conversation's answer")
    check(ArisFixDrop.pick(read, since: start.addingTimeInterval(30), until: start.addingTimeInterval(60)) == nil, "fix: a note from before the turn began is not the turn's")
    ArisFixDrop.append(.pane(.screen), task: false, to: file, now: start.addingTimeInterval(ArisFixDrop.kept + 8))
    check(ArisFixDrop.read(file).map(\.fix) == [.pane(.automation), .pane(.screen)], "fix: notes older than ten minutes are dropped at the next write")
    check(ArisFixDrop.entry(#"{"at":1800000000,"fix":{"kind":"copy","target":"codex login"}}"#) == nil
          && ArisFixDrop.entry(#"{"at":1800000000,"fix":{"kind":"login","target":"claude"}}"#) == nil && ArisFixDrop.entry("not json") == nil,
          "fix: a note that names a command or a login is not taken from the file, whoever wrote it")
    check(ArisFixDrop.read(folder.appendingPathComponent("none.jsonl")).isEmpty, "fix: no file is no notes")
}

// MARK: - The agent's own failure lines

private func fixBrainLineTests() {
    let nobody = { (_: ArisBrain) -> ArisBrain? in nil }
    let toCodex = { (brain: ArisBrain) -> ArisBrain? in brain == .codex ? .claude : .codex }
    for brain in [ArisBrain.claude, .codex, .antigravity] {
        let name = brain.rawValue
        check(ArisBrainFix.fix(forLine: ArisBrainFailure.friendly("Error: not logged in. Please run /login", brain: brain), another: nobody) == .login(name),
              "fix: \(name)'s 로그인이 필요해요 earns its login")
        for korean in [true, false] {
            if case .say(let line) = ArisBrainFailure.death(stderr: "x\nPlease run /login", brain: brain, korean: korean, acted: false, isTask: false, events: 0, retried: false) {
                check(ArisBrainFix.fix(forLine: line, another: nobody) == .login(name), "fix: \(name) ending logged out earns its login (\(korean ? "ko" : "en"))")
            } else { check(false, "fix: \(name) ending logged out says a line") }
            if case .say(let line) = ArisBrainFailure.death(stderr: "error: unknown option --frob", brain: brain, korean: korean, acted: true, isTask: false, events: 2, retried: false) {
                check(ArisBrainFix.fix(forLine: line, another: toCodex) == .retry, "fix: \(name) stopping with its own last words earns 다시 해보기 (\(korean ? "ko" : "en"))")
            } else { check(false, "fix: \(name) stopping says a line") }
            if case .say(let line) = ArisBrainFailure.death(stderr: "", brain: brain, korean: korean, acted: true, isTask: false, events: 2, retried: false) {
                check(ArisBrainFix.fix(forLine: line, another: toCodex) == .retry, "fix: \(name) stopping without a word earns 다시 해보기 (\(korean ? "ko" : "en"))")
            } else { check(false, "fix: \(name) stopping silently says a line") }
            let passing = [ArisBrainFailure.startLine(brain: brain, missing: nil, korean: korean), ArisBrainFailure.slowLine(brain: brain, korean: korean),
                           ArisBrainFailure.silentLine(brain: brain, korean: korean), ArisBrainFailure.unreachableLine(brain: brain, korean: korean)]
            check(passing.allSatisfy { ArisBrainFix.fix(forLine: $0, another: toCodex) == .retry }, "fix: \(name) not starting, slow, silent or unreachable earns 다시 해보기 (\(korean ? "ko" : "en"))")
            check(ArisBrainFix.fix(forLine: ArisBrainFailure.startLine(brain: brain, missing: .program, korean: korean), another: toCodex) == .settings(.brain),
                  "fix: \(name) not installed earns Settings on the AI row (\(korean ? "ko" : "en"))")
        }
        let limit = ArisBrainFailure.friendly("You've hit your usage limit", brain: brain)
        check(ArisBrainFix.fix(forLine: limit, another: toCodex) == .otherBrain(toCodex(brain)!.rawValue), "fix: \(name) at its limit earns the AI that can take it instead")
        check(ArisBrainFix.fix(forLine: limit, another: nobody) == .settings(.brain, again: true), "fix: \(name) at its limit with no other AI earns the AI row and a quiet 다시 해보기")
        let zone = TimeZone(identifier: "Asia/Seoul")!
        let timed = ArisBrainFailure.friendly("usage limit reached. resets at 3pm", brain: brain, now: Date(timeIntervalSince1970: 1_800_000_000), timeZone: zone)
        check(ArisBrainFix.fix(forLine: timed, another: toCodex)?.kind == .otherBrain, "fix: \(name)'s limit line with a reset time is still its limit line")
    }
    check(ArisBrainFix.fix(forLine: ArisBrainFailure.friendly("401 unauthorized", brain: .api), another: nobody) == .settings(.key), "fix: the API brain's wrong key earns the key's row, never a login")
    for korean in [true, false] {
        check(ArisBrainFix.fix(forLine: ArisBrainTrouble(brain: .api, missing: .key).line(korean: korean), another: nobody) == .settings(.key)
              && ArisBrainFix.fix(forLine: ArisBrainTrouble(brain: .api, missing: .setup).line(korean: korean), another: nobody) == .settings(.key),
              "fix: an API brain with no key or no model earns the key's row (\(korean ? "ko" : "en"))")
        check(ArisBrainFix.fix(forLine: ArisBrainTrouble(brain: nil, missing: .any).line(korean: korean), another: nobody) == .settings(.brain), "fix: no AI at all earns the AI row (\(korean ? "ko" : "en"))")
        check(ArisBrainFix.fix(forLine: ArisAgentPrompt.busyLine(korean: korean), another: toCodex) == nil, "fix: still answering the last question has nothing to press (\(korean ? "ko" : "en"))")
    }
    check(ArisBrainFix.fix(forLine: "Stopped.", another: toCodex) == nil && ArisBrainFix.fix(forLine: "cancelled", another: toCodex) == nil
          && ArisBrainFix.fix(forLine: "", another: toCodex) == nil, "fix: a stop is not a failure and earns no button")
    check(ArisBrainFix.fix(forLine: "Claude: something the tool said about a login page", another: toCodex) == nil
          && ArisBrainFix.fix(forLine: "설정 › AI 서비스에서 로그인이 필요해요", another: toCodex) == nil,
          "fix: a sentence that only sounds like a failure line earns nothing: nothing is read out of wording")
    check(!ArisFixPrompt.rule.isEmpty && ArisAgentPrompt.system(tools: "/t/aris-tools").contains(ArisFixPrompt.rule)
          && !ArisAgentPrompt.system(tools: "/t/aris-tools", task: true).contains(ArisFixPrompt.rule),
          "fix: a conversation's brain is told to say what is missing and leave the path to the button; a job is not")
}

// MARK: - A turn's end

private final class FixStream {}

private func fixTurnTests() {
    let none = { (_: ArisBrain) -> ArisBrain? in nil }
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let end = start.addingTimeInterval(30)
    let dropped = { (fix: ArisFix, after: TimeInterval, task: Bool) in ArisFixDrop.Entry(at: start.addingTimeInterval(after), fix: fix, task: task) }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.began(stream, task: false, now: start)
        check(turns.closing(.status("웹 검색 중"), on: stream, dropped: [dropped(.pane(.disk), 3, false)], now: end, another: none) == nil, "fix: nothing is sent before the turn's last line")
        check(turns.closing(.answer("메시지를 읽을 권한이 없대요."), on: stream, dropped: [dropped(.pane(.disk), 3, false)], now: end, another: none) == .pane(.disk),
              "fix: a tool's note reaches the end of the turn whatever the brain's answer says")
        check(turns.closing(.answer("again"), on: stream, dropped: [dropped(.pane(.disk), 3, false)], now: end, another: none) == nil, "fix: a stream gets its fix once")
    }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.began(stream, task: true, now: start)
        check(turns.closing(.failure(ArisBrainFailure.slowLine(brain: .claude, korean: true)), on: stream, dropped: [], now: end, another: none) == nil,
              "fix: a background job's stream gets no button")
        check(turns.closing(.answer("ok"), on: FixStream(), dropped: [dropped(.pane(.disk), 3, false)], now: end, another: none) == nil, "fix: a stream that never began a turn gets none")
    }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.began(stream, task: false, now: start)
        turns.note(.pane(.accessibility), now: start.addingTimeInterval(4))
        check(turns.closing(.failure(ArisBrainFailure.friendly("not logged in", brain: .codex)), on: stream, dropped: [dropped(.pane(.disk), 9, false)], now: end, another: none) == .login("codex"),
              "fix: the failure line that ended the turn decides before any tool's note")
    }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.began(stream, task: false, now: start)
        turns.note(.pane(.accessibility), now: start.addingTimeInterval(4))
        check(turns.closing(.answer("앱 안을 보려면 권한이 필요해요."), on: stream, dropped: [dropped(.pane(.disk), 2, false), dropped(.pane(.screen), 8, true)], now: end, another: none) == .pane(.accessibility),
              "fix: of the agent's own note and aris-tools' notes the newest of the turn counts, a job's never")
    }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.note(.settings(.services), now: start.addingTimeInterval(-20))
        turns.began(stream, task: false, now: start)
        turns.note(.retry, now: start.addingTimeInterval(5))
        check(turns.closing(.answer("다른 방법으로 찾았어요."), on: stream, dropped: [], now: end, another: none) == nil,
              "fix: 다시 해보기 never stands under an answer that came, and a note from before the turn is not its own")
    }
    do {
        let turns = ArisFixTurns(), stream = FixStream()
        turns.began(stream, task: false, now: start)
        turns.note(.retry, now: start.addingTimeInterval(5))
        check(turns.closing(.failure("API 브레인에 닿지 못했어요."), on: stream, dropped: [], now: end, another: none) == .retry,
              "fix: a failure that isn't one of the agent's lines takes the turn's note")
        turns.note(.copy("rm -rf x; y"), now: end)
        let late = FixStream()
        turns.began(late, task: false, now: end.addingTimeInterval(-1))
        check(turns.closing(.failure("x"), on: late, dropped: [], now: end.addingTimeInterval(1), another: none) == nil, "fix: a note that names nothing real is never kept")
    }
}

// MARK: - The app's own lines

private func fixAppLineTests() {
    for english in [false, true] {
        let tag = english ? "en" : "ko"
        check(ArisAppFix.fix(forLine: ArisPermissionWords.turnOn(english: english)) == .pane(.microphone), "fix: the microphone line earns the microphone's list (\(tag))")
        check(ArisAppFix.fix(forLine: ArisAgentCopy.notRunning(english: english)) == .settings(.helper, again: true), "fix: a helper that isn't running earns its restart and a quiet 다시 해보기 (\(tag))")
        check(ArisAppFix.fix(forLine: ArisStartFailure.tookTooLong(english: english)) == .retry, "fix: a microphone that took too long earns 다시 해보기 (\(tag))")
        check(ArisAppFix.fix(forLine: ArisLocalReply.todoAdded(.noAccess, korean: !english)) == .pane(.reminders)
              && ArisAppFix.fix(forLine: ArisLocalReply.todosUnread(korean: !english)) == .pane(.reminders), "fix: a to-do that Reminders access stopped earns that access (\(tag))")
        check(ArisAppFix.fix(forLine: ArisTurnWatchdog.line(korean: !english)) == .retry && ArisAppFix.fix(forLine: ArisLocalReply.undoUnknown(korean: !english)) == .retry,
              "fix: no answer at all, and an undo that couldn't read the log, earn 다시 해보기 (\(tag))")
        check(ArisAppFix.fix(forLine: ArisUndoWords.failure("Operation not permitted", korean: !english)) == .settings(.control), "fix: an undo macOS didn't allow earns the computer-control page (\(tag))")
        check(ArisAppFix.fix(forLine: ArisIntent.arrangeFailure("Accessibility permission needed", app: "Safari", korean: !english)) == .pane(.accessibility),
              "fix: arranging windows without Accessibility earns that list (\(tag))")
        check(ArisAppFix.fix(forLine: ArisBrainTrouble.cannotStart(.codex, korean: !english)) == .settings(.brain)
              && ArisAppFix.fix(forLine: ArisBrainTrouble.cannotStart(.api, korean: !english)) == .settings(.key), "fix: an AI that can't start keeps its way to Settings (\(tag))")
        check(ArisAppFix.fix(forLine: ArisLocalReply.todoAdded(.demo, korean: !english)) == nil && ArisAppFix.fix(forLine: ArisLocalReply.noTimer(korean: !english)) == nil
              && ArisAppFix.fix(forLine: ArisPermissionWords.needsNewerMac(english: english)) == nil && ArisAppFix.fix(forLine: ArisPrerequisites.full(.helper, english: english)) == nil
              && ArisAppFix.fix(forLine: ArisTranscript.notHeard(korean: !english)) == nil, "fix: a line with nothing he can press earns no button (\(tag))")
        check(ArisAppFix.fix(forLine: ArisStopLine.line(record: [], cut: ArisStopLine.cut(ArisSession().listening().hearing("x").thinking()), english: english)) == nil,
              "fix: the line of a turn he stopped earns no button (\(tag))")
        let spoken = ArisFixSpeech.spoken(ArisLocalReply.todoAdded(.noAccess, korean: !english))
        check(!spoken.contains("›") && !spoken.contains("Settings") && !spoken.contains("설정") && spoken.hasPrefix(english ? "I couldn't add it." : "할 일에 넣지 못했어요."),
              "fix: the voice says Reminders access is off without reading the path (\(tag))")
        check(ArisFixSpeech.spoken(ArisLocalReply.noTimer(korean: !english)) == ArisLocalReply.noTimer(korean: !english), "fix: any other line is said as it is (\(tag))")
    }
    check(ArisAppFix.fix(forLine: "") == nil && ArisAppFix.fix(forLine: "시스템 설정에서 마이크를 켜 주세요") == nil, "fix: a sentence that only resembles one of the app's lines earns nothing")
}

private func fixWordsTests() {
    for english in [false, true] {
        let titles = fixEveryFix.map { ArisFixWords.title($0, english: english) }
        check(titles.allSatisfy { !$0.isEmpty && !$0.contains("›") || $0 == ArisBrainTrouble.settingsButton(english: english) }, "fix: every button has words (\(english ? "en" : "ko"))")
        check(titles.allSatisfy { $0.count <= 34 }, "fix: every button's words fit one short line (\(english ? "en" : "ko"))")
        check(Set(ArisFix.Pane.allCases.map { ArisFixWords.title(.pane($0), english: english) }).count == ArisFix.Pane.allCases.count, "fix: every list's button says which list (\(english ? "en" : "ko"))")
    }
    check(ArisFixWords.title(.settings(.brain), english: false) == ArisBrainTrouble.settingsButton(english: false), "fix: the AI row keeps the words its button had")
    check(ArisFixWords.title(.login("codex"), english: false) == "Codex 로그인하기" && ArisFixWords.title(.otherBrain("claude"), english: true) == "Ask Claude instead"
          && ArisFixWords.title(.otherBrain("api"), english: true) == "Ask the API model instead",
          "fix: a login and a hand-over name the AI by its short name")
    check(ArisFixWords.title(.pane(.disk), english: true).range(of: #"[가-힣]"#, options: .regularExpression) == nil
          && ArisFixWords.title(.retry, english: false).range(of: #"[A-Za-z]"#, options: .regularExpression) == nil, "fix: English buttons hold no Korean, and 다시 해보기 no English")
    check(ArisFixWords.loginCommand("codex") == "codex login" && ArisFixWords.loginCommand("claude") == "claude" && ArisFixWords.loginCommand("api") == nil
          && ["claude", "codex", "antigravity"].allSatisfy { ArisFix.copy(ArisFixWords.loginCommand($0) ?? ";").isValid }, "fix: every login has a command that may be copied when Terminal can't be opened")
}

// MARK: - Which button shows, and after the press

private func fixMoment(_ phase: ArisFixMoment.Phase, reply: String = "", heard: String = "메일 읽어 줘", asking: Bool = false) -> ArisFixMoment {
    ArisFixMoment(phase: phase, heard: heard, reply: reply, asking: asking)
}

private func fixDeskTests() {
    let failed = fixMoment(.failed, reply: "Codex: 뭔가 잘못됐어요")
    let answered = fixMoment(.speaking, reply: "메일을 읽을 권한이 꺼져 있어요.")
    check(ArisFixDesk().offer(failed) == nil && ArisFixDesk().offer(answered) == nil, "fix: a failure nobody named a fix for gets no button")
    let disk = ArisFixDesk().arriving(.pane(.disk))
    check(disk.offer(answered) == ArisFixOffer(fix: .pane(.disk), again: false) && disk.offer(fixMoment(.idle, reply: answered.reply)) == ArisFixOffer(fix: .pane(.disk), again: false),
          "fix: the fix the agent sent stands under the answer, and still when the notch is opened again")
    check(disk.offer(fixMoment(.thinking, reply: "쓰는 중")) == nil && disk.offer(fixMoment(.listening)) == nil && disk.offer(fixMoment(.speaking, reply: "보낼까요?", asking: true)) == nil
          && disk.offer(fixMoment(.speaking)) == nil, "fix: no button while Aris listens, works or asks on a card, or with nothing said")
    check(ArisFixDesk().arriving(.retry).offer(failed) == ArisFixOffer(fix: .retry, again: false) && ArisFixDesk().arriving(.retry).offer(fixMoment(.failed, reply: "x", heard: " ")) == nil
          && ArisFixDesk().arriving(.otherBrain("claude")).offer(fixMoment(.failed, reply: "x", heard: "")) == nil, "fix: 다시 해보기 needs their words to ask again")
    check(ArisFixDesk().arriving(.settings(.brain, again: true)).offer(failed) == ArisFixOffer(fix: .settings(.brain, again: true), again: true), "fix: a fix that pairs with asking again brings the quiet second button")
    let pressed = disk.pressing(.pane(.disk), under: answered.reply)
    check(pressed.offer(answered) == ArisFixOffer(fix: .pane(.disk), again: true), "fix: once the button was pressed, 다시 해보기 stands beside it")
    check(pressed.offer(fixMoment(.speaking, reply: answered.reply, heard: "")) == ArisFixOffer(fix: .pane(.disk), again: false), "fix: with no words to ask again there is only the one button")
    check(disk.foundOn(.pane(.disk)).offer(answered) == nil && disk.foundOn(.pane(.disk)).offer(failed) == ArisFixOffer(fix: .retry, again: false) && disk.foundOn(.pane(.screen)).offer(answered) != nil,
          "fix: a permission that is already on gets no button under an answer, and 다시 해보기 under a failure")
    let next = pressed.moving(from: fixMoment(.idle, reply: answered.reply), to: fixMoment(.thinking))
    check(next == ArisFixDesk(), "fix: a new typed turn takes the old button and its press away")
    check(pressed.moving(from: answered, to: fixMoment(.listening)) == ArisFixDesk(), "fix: a new spoken turn takes them away too")
    check(disk.moving(from: fixMoment(.speaking, reply: "보낼까요?", asking: true), to: fixMoment(.thinking)) == disk && disk.moving(from: fixMoment(.thinking), to: answered) == disk
          && disk.moving(from: answered, to: fixMoment(.idle, reply: answered.reply)) == disk, "fix: an answered card, the answer coming and the turn ending keep the turn's fix")
    check(disk.moving(from: fixMoment(.thinking), to: fixMoment(.idle, reply: "멈췄어요.")).offer(fixMoment(.idle, reply: "멈췄어요.")) == nil, "fix: a turn he stopped loses the fix sent for it: a stop is not a failure")
    check(pressed.moving(from: fixMoment(.idle, reply: answered.reply), to: fixMoment(.speaking, reply: "다 끝냈어요.", heard: "보고서 정리")) == ArisFixDesk(),
          "fix: Aris speaking up about something else (a background job that ended) never inherits the last turn's button")
    let own = fixMoment(.failed, reply: ArisAgentCopy.notRunning(english: false))
    check(ArisFixDesk().offer(own) == ArisFixOffer(fix: .settings(.helper, again: true), again: true), "fix: the app's own line earns its button with nothing sent")
    check(ArisFixDesk().arriving(.pane(.screen)).offer(own)?.fix == .pane(.screen), "fix: what the agent sent for the turn comes before the app's own reading")
    check(ArisFixDesk().offer(fixMoment(.failed, reply: ArisPermissionWords.turnOn(english: true), heard: "")) == ArisFixOffer(fix: .pane(.microphone), again: false),
          "fix: a turn that never heard anything still gets the list that lets it hear")
}

private func fixReturnTests() {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    let armed = ArisFixReturn.Armed(request: "메일 읽어 줘", fix: .pane(.disk), at: at)
    var seen = armed
    seen.seenOff = true
    let soon = at.addingTimeInterval(40)
    check(ArisFixReturn.next(armed, fixed: false, heard: armed.request, busy: false, now: soon) == .wait(seen), "fix: while the permission is still off Aris waits, and knows it saw it off")
    check(ArisFixReturn.next(seen, fixed: true, heard: armed.request, busy: false, now: soon) == .askAgain, "fix: when it turns on within five minutes the same request is asked again by itself")
    check(ArisFixReturn.next(seen, fixed: true, heard: "", busy: false, now: soon) == .askAgain, "fix: also when the answer was put away meanwhile")
    check(ArisFixReturn.next(armed, fixed: true, heard: armed.request, busy: false, now: soon) == .drop, "fix: a fix that was already on at the press changes nothing, so nothing is asked by itself")
    check(ArisFixReturn.next(seen, fixed: true, heard: "날씨 어때", busy: false, now: soon) == .drop, "fix: after another turn began the old request is let go")
    check(ArisFixReturn.next(seen, fixed: true, heard: armed.request, busy: true, now: soon) == .wait(seen), "fix: never over a turn or a card that is under way")
    check(ArisFixReturn.next(seen, fixed: nil, heard: armed.request, busy: false, now: soon) == .wait(seen), "fix: no answer about the permission is not a yes")
    check(ArisFixReturn.next(seen, fixed: true, heard: armed.request, busy: false, now: at.addingTimeInterval(ArisFixReturn.window + 1)) == .drop, "fix: past five minutes nothing is asked by itself")
    check(ArisFixReturn.check(for: .pane(.disk)) == .agentDisk && ArisFixReturn.check(for: .pane(.screen)) == .agentScreen && ArisFixReturn.check(for: .pane(.reminders)) == .reminders
          && ArisFixReturn.check(for: .settings(.todoAccess)) == .reminders && ArisFixReturn.check(for: .settings(.brain)) == .brain && ArisFixReturn.check(for: .settings(.helper)) == .helper,
          "fix: a permission, the chosen AI and the helper can be read back")
    check([ArisFix.login("claude"), .pane(.automation), .pane(.contacts), .copy("claude"), .retry, .settings(.services), .settings(.skills)]
        .allSatisfy { ArisFixReturn.check(for: $0) == nil }, "fix: a login, Automation and a connected service can't be read back, so asking again stays one press")
}
