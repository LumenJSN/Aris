// Tests for jv-vmfix6, the fourth VM run (aris-vmcheck notes4/*, cap4/*), the app's parts:
// 8   Aris's own replies follow the UI language whatever the request's: the timer (cap4/L1-en-timer-3s.jpg: "3분 타이머
//     맞췄어요." in the English UI; cap4/K4-ko-timer-4s.jpg: "Timer set for 2 minutes." in the Korean one), the undo card
//     and its result, the no-AI line (cap4/L1-en-reminder-8s.jpg: a Korean line over "Open Settings › AI services");
// 9a  the reopen pill under the closed notch is read whole (cap4/s14-notch-closed.jpg: "Input Monitoring is on. R…");
// 9b  the System Settings the setup put away stays away when the setup closes (notes4/setup-walk.txt, s12-after-start);
// 9c  taught procedures are listed under Settings › 기억 › 저장된 단계, with 이름 바꾸기 and 지우기 (ArisTaughtRoute);
// 9d  copy: the menu is on the right, a tool that isn't installed is said so, 허용하기 everywhere in 앱 › 권한.
// Called from main.swift; uses its check().
import Foundation

private let vmfix6Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func vmfix6Source(_ path: String) -> String { (try? String(contentsOf: vmfix6Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

/// Names that are no one's words to translate.
private let vmfix6Names = ["Aris", "macOS", "Mac", "TextEdit", "Claude Code", "Claude", "ChatGPT", "Gemini", "API", "AI", "Codex", "Pomodoro"]

private func vmfix6HasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

/// One line in the UI's language: no Hangul of Aris's in English, no English word of Aris's in Korean (vmfix5's rule).
private func vmfix6Checks(_ text: String, english: Bool, own: [String], _ name: String) {
    let aris = (own + vmfix6Names).sorted { $0.count > $1.count }.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }
    if english {
        check(!vmfix6HasHangul(aris), "vmfix6 8: \(name), English UI: no Korean of Aris's (\(text))")
    } else {
        let words = aris.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 2 && $0.unicodeScalars.allSatisfy(\.isASCII) }
        check(words.isEmpty, "vmfix6 8: \(name), Korean UI: no English word of Aris's (\(text))")
    }
}

func runVmfix6AppTests() {
    let catalog = vmfix6Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: catalog)) ?? Data()))
    defer { ArisSettingsCopy.install([:]) }
    vmfix6TurnLanguageTests()
    vmfix6UndoLanguageTests()
    vmfix6NoAITests()
    vmfix6ReopenPillTests()
    vmfix6SetupLeaveTests()
    vmfix6TaughtRouteTests()
    vmfix6TaughtRowsTests()
    vmfix6CopyTests()
}

// MARK: - 8: the turn's own replies

private func vmfix6TurnLanguageTests() {
    // The claims answered on the Mac take the UI's language, never the request's.
    let runs = vmfix6Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    check(runs.contains("static var replyKorean: Bool { ArisReplyLanguage.korean(uiEnglish: ArisUIWords.english) }") && runs.contains("tier = reading.tier, korean = Self.replyKorean")
            && !runs.contains("korean = heard.korean"),
          "vmfix6 8: every claim the turn answers itself (timer, time, undo, hand-off…) is said in the UI's language")
    check(!vmfix6Source("Aris/private/Aris/Routing/ArisTurnRequest.swift").contains("ArisSpeech.language(of: unmarked)"),
          "vmfix6 8: the request's language is no longer offered to the turn's replies")
    let controller = vmfix6Source("Aris/private/Aris/ArisController.swift")
    check(controller.contains("ArisTurnWatchdog.line(korean: Self.replyKorean)") && controller.contains("ArisThinking.lookingLine(korean: Self.replyKorean)")
            && controller.contains("Self.replyKorean ? \"확인해 볼게요.\" : \"One moment.\"")
            && controller.contains("handOut(specs ?? [], turn: handing, tier: tier, korean: Self.replyKorean)")
            && controller.contains("let korean = Self.replyKorean"),
          "vmfix6 8: the brain turn's own lines (no answer, looking, one moment, the hand-off, on the screen) follow the UI")
    check(vmfix6Source("Aris/private/Aris/ArisController+Practice.swift").contains("let korean = Self.replyKorean")
            && vmfix6Source("Aris/private/Aris/ArisController+RoutineStep.swift").contains("let korean = Self.replyKorean"),
          "vmfix6 8: the setup's practice and a routine's local steps too")
    // What those lines are, in each UI language, with the request in the other.
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    for uiEnglish in [true, false] {
        let korean = !uiEnglish
        let intents: [ArisIntent] = [.timer(seconds: 180, focus: false), .timer(seconds: 120, focus: true), .cancelTimer, .pomodoro, .pauseTimer,
                                     .resumeTimer, .addTime(60), .tellTime, .tellDate, .media(.play), .media(.next)]
        for intent in intents {
            vmfix6Checks(intent.acknowledgement(korean: korean, now: now) ?? "", english: uiEnglish, own: [], "\(intent)")
            for running in [true, false] {
                if let change = ArisTimerChange.plan(intent, running: running, paused: false, korean: korean) {
                    vmfix6Checks(change.reply, english: uiEnglish, own: [], "timer change \(intent)")
                }
            }
        }
        vmfix6Checks(ArisTurnWatchdog.line(korean: korean), english: uiEnglish, own: [], "no answer")
        vmfix6Checks(ArisThinking.lookingLine(korean: korean), english: uiEnglish, own: [], "looking")
        vmfix6Checks(ArisSpeakable.onScreen(korean: korean), english: uiEnglish, own: [], "on the screen")
    }
    // The VM's two lines, as they are now said.
    check(ArisIntent.timer(seconds: 180, focus: false).acknowledgement(korean: false) == "Timer set for 3 minutes."
            && ArisIntent.timer(seconds: 120, focus: false).acknowledgement(korean: true) == "2분 타이머 맞췄어요.",
          "vmfix6 8: '3분 타이머' in the English UI says 'Timer set for 3 minutes.', 'set a 2 minute timer' in the Korean UI '2분 타이머 맞췄어요.'")
}

// MARK: - 8: the undo card and its result

private func vmfix6UndoLanguageTests() {
    // The undo is reached only through the turn (undoLast(korean: korean)): its korean is the UI's now.
    check(vmfix6Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift").contains("return await undoLast(korean: korean, heard: unmarked)"),
          "vmfix6 8: the undo card and its reply are built with the turn's korean, the UI's")
    // A to-do added in Korean, undone from an English UI (and the other way): the card names the user's title as written.
    for uiEnglish in [true, false] {
        let korean = !uiEnglish
        let title = uiEnglish ? "우유 사기" : "buy milk"
        let todo = ArisUndoWords.Candidate(id: "1", summary: "할 일 추가: \(title)", action: "made")
        let timer = ArisUndoWords.Candidate(id: "2", summary: "타이머: 3분", action: "made")
        let card = ArisUndoWords.card(for: todo, newest: timer, doubt: true, korean: korean)
        for line in [card.title, card.detail, ArisUndoWords.cannotLine(timer.summary, korean: korean), ArisUndoWords.nothingRecent(korean: korean),
                     ArisUndoWords.noneOfKindLine([todo, timer], korean: korean), ArisUndoWords.doneLine(todo.summary, korean: korean),
                     ArisUndoWords.waitingLine(folder: nil, korean: korean), ArisLocalReply.undoUnknown(korean: korean)] {
            vmfix6Checks(line, english: uiEnglish, own: [title, "3"], "undo")
        }
    }
}

// MARK: - 8: no AI can answer

private func vmfix6NoAITests() {
    typealias C = ArisBrainChoice
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    let noAI = ArisBrainTrouble(brain: nil, missing: .any)
    // cap4/L1-en-reminder-8s.jpg: asked in Korean on an English Mac, the agent's Korean line.
    let shown = C.failureLine(noAI.line(korean: true), stored: nil, ready: none, english: true)
    check(shown == noAI.line(korean: false) && ArisBrainTrouble.isCannotStart(shown),
          "vmfix6 8: the no-AI line is in the English UI's language, with its button (\(shown))")
    check(C.failureLine(noAI.line(korean: false), stored: nil, ready: none, english: false) == noAI.line(korean: true),
          "vmfix6 8: and in the Korean UI's, asked in English")
    let missing = ArisBrainTrouble.cannotStart(.claude, korean: true)
    check(C.failureLine(missing, stored: "claude", ready: none, english: true) == ArisBrainTrouble.cannotStart(.claude, korean: false),
          "vmfix6 8: a chosen AI that isn't installed is said in the UI's language too")
    for english in [true, false] {
        vmfix6Checks(C.failureLine(noAI.line(korean: english), stored: nil, ready: none, english: english), english: english, own: [], "no AI line")
        vmfix6Checks(ArisBrainTrouble.settingsButton(english: english), english: english, own: [], "no AI button")
    }
    check(vmfix6Source("Aris/private/Aris/ArisAgentClient.swift").contains("ArisBrainChoice.failureLine(line, stored: stored, ready: ready, english: ArisUIWords.english)"),
          "vmfix6 8: every failed turn's line goes through it with the UI's language")
}

// MARK: - 9a: the reopen pill

private func vmfix6ReopenPillTests() {
    typealias Fit = ArisNoticePillFit
    let now = Date()
    for english in [true, false] {
        for permission in [ArisPermission.inputMonitoring, .accessibility] {
            guard let card = ArisPermissionNotice.notice(for: .offerRelaunch(ArisPermissionKey(permission)), english: english) else {
                check(false, "vmfix6 9a: a reopen card for \(permission)")
                continue
            }
            let posted = ArisNotice(key: card.key, kind: card.kind, title: card.title, body: card.body, actions: card.actions, posted: now)
            check(Fit.readWhole(posted), "vmfix6 9a: the reopen card's line is read whole")
            let width = Fit.width(posted, now: now, english: english), whole = Fit.whole(posted, now: now, english: english)
            // Input Monitoring (the keys' card, the VM's) fits whole; a longer name (Accessibility's list is "Device
            // Control and Data Access" on this macOS) shortens, its body and time never.
            check((permission != .inputMonitoring || whole <= width) && Fit.kept(posted, now: now, english: english) <= width
                    && width <= ArisNoticePillLayout.widths.last!,
                  "vmfix6 9a: \(permission) (\(english ? "en" : "ko")): \"\(card.title)  \(card.body)\": what to do is never cut in the closed notch's pill (\(Int(whole)) in \(Int(width)))")
            check(!card.body.contains(card.title), "vmfix6 9a: the body doesn't say the permission's name again (\(card.body))")
            vmfix6Checks(card.body, english: english, own: [], "reopen card")
        }
    }
    // Any other notice keeps its rule: the preview may be cut.
    let mail = ArisNotice(kind: .incoming, title: "김지원", body: String(repeating: "긴 내용 ", count: 40))
    check(!Fit.readWhole(mail) && Fit.width(mail, now: now, english: false) == 440, "vmfix6 9a: an incoming notice's preview is still cut")
    let view = vmfix6Source("Aris/private/Aris/Notice/ArisNoticePillView.swift")
    check(view.contains("} else if whole {") && view.contains("Text(verbatim: line.rest).foregroundStyle(Look.body).lineLimit(1).fixedSize().layoutPriority(2)"),
          "vmfix6 9a: drawn so: the rest keeps its width, the bold part gives way first")
}

// MARK: - 9b: System Settings after Start

private func vmfix6SetupLeaveTests() {
    // notes4/setup-walk.txt: Allow opened System Settings, Accessibility came on, it was put away (12:12:37); after the
    // last page's Start it was in front again, visible.
    var leave = ArisSetupLeave(frontApp: "com.apple.Terminal")
    leave.sending(runningPid: nil)
    leave.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 1257, sinceForward: nil)
    leave.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 1257, sinceForward: 0)
    check(leave.planOnGranted(runningPid: 1257).hidesSettings, "vmfix6 9b: (as before) put away as Accessibility comes on")
    leave.putAway()
    // macOS hands the screen back to System Settings for a moment after the setup comes forward: still the setup's.
    leave.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 1257, sinceForward: 0.1)
    let close = leave.plan(runningPid: 1257, quitting: false)
    check(close.hidesSettings && close.activates == "com.apple.Terminal",
          "vmfix6 9b: as the setup closes, the one it put away is kept hidden and the user's app comes forward (\(close))")
    check(!leave.plan(runningPid: 1257, quitting: true).hidesSettings, "vmfix6 9b: never while quitting (Quit & Reopen)")
    check(!leave.plan(runningPid: 999, quitting: false).hidesSettings, "vmfix6 9b: another System Settings process is the user's")
    var done = leave
    done.done()
    check(!done.plan(runningPid: 1257, quitting: false).hidesSettings, "vmfix6 9b: once carried out, nothing is left")
    // He went back to it himself later: his, left alone.
    var theirs = leave
    theirs.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 1257, sinceForward: 40)
    check(!theirs.plan(runningPid: 1257, quitting: false).hidesSettings, "vmfix6 9b: one he opened again himself is left alone")
    let guide = vmfix6Source("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Leave.swift")
    check(guide.contains("if let settings, !settings.isTerminated, !settings.isHidden { _ = settings.hide() }"),
          "vmfix6 9b: one macOS showed again as the window went is hidden again")
}

// MARK: - 9c: taught procedures in Settings

private func vmfix6Procedure(_ name: String, changed: TimeInterval) -> ArisTeachProcedure {
    let steps = [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit"),
                 ArisTeachStep(action: .type, app: "TextEdit", bundle: "com.apple.TextEdit", target: "본문", label: "본문", parameter: "p1")]
    let parameter = ArisTeachParameter(key: "p1", label: "본문", example: "Lesson line one", app: "TextEdit")
    return ArisTeachProcedure(name: name, steps: steps, parameters: [parameter], created: Date(timeIntervalSince1970: changed))
}

private func vmfix6TaughtRouteTests() {
    var stored = [vmfix6Procedure("메모 쓰기", changed: 100), vmfix6Procedure("Write note", changed: 200)]
    var removed: [UUID] = []
    let access = ArisTaughtAccess(all: { stored }, remove: { id in
        removed.append(id)
        let had = stored.contains { $0.id == id }
        stored.removeAll { $0.id == id }
        return had
    }, routineNames: { ["출근 준비"] }, save: { procedure in
        stored = stored.map { $0.id == procedure.id ? procedure : $0 }
        return true
    })
    let earlier: () -> (status: Int, body: Data, audit: String?) = {
        (200, (try? JSONSerialization.data(withJSONObject: ["recipes": [["key": "plain", "request": "plain", "steps": [], "stepsEn": [], "apps": "", "saved": "x"]], "tampered": false])) ?? Data(), nil)
    }
    let listed = ArisTaughtRoute.handle(["op": "savedSteps"], access: access, earlier: earlier)
    let recipes = ((try? JSONSerialization.jsonObject(with: listed.body)) as? [String: Any])?["recipes"] as? [[String: Any]] ?? []
    check(listed.status == 200 && recipes.count == 3 && recipes[0]["key"] as? String == "plain",
          "vmfix6 9c: the saved steps' own rows first, then the taught procedures (\(recipes.count))")
    let items = (try? JSONDecoder().decode([ArisSavedStepsItem].self, from: JSONSerialization.data(withJSONObject: recipes))) ?? []
    check(items.count == 3 && items[1].request == "Write note" && items[2].request == "메모 쓰기" && items[1].taught == true && items[0].taught == nil,
          "vmfix6 9c: the app reads them as rows, the last changed first, marked as taught")
    if items.count == 3 {
        let shown = stored.first { $0.name == "메모 쓰기" }!
        check(items[2].steps == shown.steps.map { ArisTeachCopy.step($0, in: shown, english: false) }
                && items[2].stepsEn == shown.steps.map { ArisTeachCopy.step($0, in: shown, english: true) } && items[2].stepsEn.first == "Open TextEdit"
                && items[2].apps == "TextEdit",
              "vmfix6 9c: their steps in both languages, as the read-back says them (\(items[2].steps))")
    }
    let first = stored[0]
    // Renaming: onto another's name, or a routine's, is refused; else it is kept under the new name.
    let onto = ArisTaughtRoute.handle(["op": "savedStepsRename", "key": ArisTaughtRoute.keyPrefix + first.id.uuidString, "name": "write-note"],
                                      access: access, earlier: earlier)
    let ontoRoutine = ArisTaughtRoute.handle(["op": "savedStepsRename", "key": ArisTaughtRoute.keyPrefix + first.id.uuidString, "name": "출근준비"],
                                             access: access, earlier: earlier)
    check(String(data: onto.body, encoding: .utf8)?.contains("\"taken\":true") == true && String(data: ontoRoutine.body, encoding: .utf8)?.contains("\"taken\":true") == true
            && stored[0].name == "메모 쓰기",
          "vmfix6 9c: a name another procedure or a routine has is refused, nothing taken over")
    let renamed = ArisTaughtRoute.handle(["op": "savedStepsRename", "key": ArisTaughtRoute.keyPrefix + first.id.uuidString, "name": "  “메모 남기기” "],
                                         access: access, earlier: earlier)
    check(renamed.status == 200 && String(data: renamed.body, encoding: .utf8)?.contains("\"renamed\":true") == true && stored[0].name == "메모 남기기"
            && stored[0].id == first.id && renamed.audit != nil,
          "vmfix6 9c: renamed, cleaned as a spoken name is (\(stored[0].name))")
    check(ArisTaughtRoute.handle(["op": "savedStepsRename", "key": "plain", "name": "x"], access: access, earlier: earlier).status == 400
            && ArisTaughtRoute.handle(["op": "savedStepsRename", "key": ArisTaughtRoute.keyPrefix + first.id.uuidString, "name": " ‘’ "], access: access, earlier: earlier).status == 400,
          "vmfix6 9c: only a taught row is renamed, and never to nothing")
    // Deleting: a taught key removes that procedure; any other key is the saved steps' own.
    let deleted = ArisTaughtRoute.handle(["op": "savedStepsDelete", "key": ArisTaughtRoute.keyPrefix + first.id.uuidString], access: access, earlier: earlier)
    check(String(data: deleted.body, encoding: .utf8)?.contains("\"removed\":true") == true && removed == [first.id] && stored.count == 1,
          "vmfix6 9c: 지우기 deletes the taught procedure")
    var passed = false
    _ = ArisTaughtRoute.handle(["op": "savedStepsDelete", "key": "plain"], access: access) { passed = true; return (200, Data("{}".utf8), nil) }
    check(passed && removed.count == 1, "vmfix6 9c: another row's key goes to the saved steps' own route")
    // The live wiring: POST /memory reaches it with the store on this Mac.
    check(vmfix6Source("ArisAgent/main.swift").contains("taught: ArisTaughtRoute.live(home: FileManager.default.homeDirectoryForCurrentUser.path)")
            && vmfix6Source("ArisAgent/ArisMemoryCurator.swift").contains("ArisTaughtRoute.handle(object, access: taught)"),
          "vmfix6 9c: the helper's /memory lists, renames and deletes taught procedures")
    // Through the memory route, as the app calls it.
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("vmfix6-taught-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: home) }
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let store = ArisMemoryStore.at(home.resolvingSymlinksInPath())
    let viaMemory = ArisMemoryRoute.handle(["op": "savedSteps"], store: store, taught: access)
    let viaRows = ((try? JSONSerialization.jsonObject(with: viaMemory.body)) as? [String: Any])?["recipes"] as? [[String: Any]] ?? []
    check(viaMemory.status == 200 && viaRows.count == 1 && viaRows[0]["request"] as? String == "Write note",
          "vmfix6 9c: listed through POST /memory's savedSteps")
}

private func vmfix6TaughtRowsTests() {
    typealias R = ArisSavedStepsSettingsRows
    let taught = ArisSavedStepsItem(key: ArisTaughtRoute.keyPrefix + "A", request: "메모 쓰기", steps: ["TextEdit 열기"], stepsEn: ["Open TextEdit"],
                                    apps: "TextEdit", saved: "x", taught: true)
    let plain = ArisSavedStepsItem(key: "plain", request: "plain", steps: ["a"], stepsEn: ["a"], apps: "", saved: "x")
    var s = ArisSettingsSnapshot()
    s.savedSteps = [taught, plain]
    let rows = R.sections(s, english: false).first?.rows ?? []
    check(rows.count == 2 && rows[0].title == "“메모 쓰기”"
            && rows[0].control == .buttons([ArisSettingButton(title: R.rename, action: .renameSavedSteps(taught.key)),
                                            ArisSettingButton(title: R.forget, action: .forgetSavedSteps(taught.key))])
            && rows[1].control == .buttons([ArisSettingButton(title: R.forget, action: .forgetSavedSteps("plain"))]),
          "vmfix6 9c: a taught procedure's row has 이름 바꾸기 and 지우기; a saved steps' row only 지우기")
    check(R.describe(taught, english: false).hasPrefix("보여 주고 가르친 것 · 1단계") && R.describe(taught, english: true).hasPrefix("Taught by showing · 1 step"),
          "vmfix6 9c: the row says it was taught, in either language")
    s.savedStepsRenaming = taught.key
    s.savedStepsName = "메모 남기기"
    let editing = R.sections(s, english: false).first?.rows.first
    check(editing?.control == .field(.savedStepsName, text: "메모 남기기", placeholder: R.renamePlaceholder,
                                     ArisSettingButton(title: R.renameSave, action: .saveSavedStepsName(taught.key), kind: .primary, enabled: true)),
          "vmfix6 9c: 이름 바꾸기 turns the row into the name field with 저장")
    s.savedStepsName = "  "
    s.savedStepsRenameProblem = .taken
    let blank = R.sections(s, english: false).first?.rows.first
    check(blank?.desc == R.RenameProblem.taken.line && { if case .field(_, _, _, let button) = blank?.control { return !button.enabled }; return false }(),
          "vmfix6 9c: a taken name is said under it; 저장 waits for a name")
    // Every word of the rows is in the catalog: Korean first, with English.
    for korean in [R.rename, R.renameSave, R.renamePlaceholder, R.renamedToast, R.taughtMark, R.RenameProblem.taken.line, R.RenameProblem.failed.line] {
        let english = ArisSettingsCopy.english(korean)
        check(english != nil && !vmfix6HasHangul(english ?? ""), "vmfix6 9c: ‘\(korean)’ has its English in Settings.xcstrings (\(english ?? "none"))")
    }
    let model = vmfix6Source("Aris/private/Aris/ArisMemorySettingsModel.swift"), live = vmfix6Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(model.contains("await ArisAgentClient.renameSavedSteps(key: key, name: name)") && live.contains("case .renameSavedSteps(let key): memory.startRename(key: key)")
            && live.contains("case .savedStepsName:") && live.contains("s.savedStepsRenaming = memory.renaming"),
          "vmfix6 9c: the page renames through the helper")
}

// MARK: - 9d: copy

private func vmfix6CopyTests() {
    check(ArisAIServicesBuilder.noBrainHow.contains("오른쪽 메뉴에서") && !ArisAIServicesBuilder.noBrainHow.contains("위에서")
            && ArisSettingsCopy.english(ArisAIServicesBuilder.noBrainHow)?.contains("from the menu on the right") == true
            && ArisSettingsCopy.english(ArisAIServicesBuilder.noBrainHow)?.contains("above") == false,
          "vmfix6 9d: the no-AI line points at the menu on its right, in both languages")
    var lists = ArisModelLists()
    lists.lists[ArisBrain.claude.rawValue] = ArisModelList(at: Date(timeIntervalSince1970: 0), options: [], fromTool: false)
    let missing = ArisModelChoiceRows.source(.claude, lists: lists, installed: false)
    check(missing == "Claude Code가 이 Mac에 설치되어 있지 않아 기본 이름만 보여요" && ArisModelChoiceRows.source(.claude, lists: ArisModelLists(), installed: false) == missing,
          "vmfix6 9d: Claude Code not installed is said so, never 'didn't give its list' (\(missing))")
    check(ArisModelChoiceRows.source(.claude, lists: lists, installed: true) == "Claude Code에서 목록을 받지 못해 기본 이름만 보여요"
            && ArisModelChoiceRows.source(.claude, lists: lists) == "Claude Code에서 목록을 받지 못해 기본 이름만 보여요",
          "vmfix6 9d: installed (or not known yet), a list it couldn't give is said as before")
    let english = ArisModelChoiceRows.footer(.claude, lists: lists, installed: false, wording: ArisSettingsWording(pageEnglish: true, frameEnglish: true))
    check(english.contains("Claude Code isn't installed on this Mac, so only the usual names are shown") && !vmfix6HasHangul(english),
          "vmfix6 9d: and in English (\(english))")
    // 앱 › 권한: one word for every button that asks.
    var s = ArisSettingsSnapshot()
    s.calendarAccess = .undecided
    s.reminders = .undecided
    let titles = [ArisSettingsBuilder.calendarAccessRow(s), ArisSettingsBuilder.remindersAccessRow(s)].compactMap { row -> String? in
        if case .buttons(let buttons) = row.control { return buttons.first?.title }
        return nil
    }
    check(titles == ["허용하기", "허용하기"], "vmfix6 9d: Calendar's and Reminders' buttons say 허용하기 like the others (\(titles))")
    check(!vmfix6Source("Aris/components/Settings/ArisSettingsBuilder.swift").contains("button(\"허용\","), "vmfix6 9d: no permission button says 허용 alone")
}
