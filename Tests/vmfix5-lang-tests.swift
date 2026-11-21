// Tests for jv-vmfix5, the third VM run (aris-vmcheck notes3/*, cap3/*), the parts outside teaching:
// D4  Aris's own words follow the UI language whatever the request's: the day review (cap3/I9-today-list*.jpg: Korean
//     list under an English UI), the to-do replies and the Reminders off-line (cap3/I2b-rem-firstuse-8s.jpg: an English
//     settings path inside a Korean sentence), every ArisToolErrorWords entry (the app layer's "no app on this Mac is
//     called ‘Spotlight’"), the Talking to Aris › AI · Model footer (cap3/S-settings1.jpg), the receipt's 되돌리기 pill
//     (cap3/K-grid.jpg: "되돌…");
// D5  the to-do reply says when it is due (notes3/I2-rem-db.txt: stored for 2026-11-20 09:00), the day's sentence says
//     what was done besides the plan (notes3/I9-today.log, cap3/I9-today-list2.jpg: nine open plans, 그 밖 · 4, one
//     sentence about the plans only), and the System Settings window the setup opened for Accessibility goes as the
//     setup moves on (notes3/setup-walk.txt, page 7);
// D6  the uninstall list shows the sandbox folder as Aris's to leave from the start (cap3/U-confirm.jpg). The kept
//     permission record after a reset is in Tests/ArisCoreTests/ArisVMFix5PermissionTests.
// Called from main.swift; uses its check().
import Foundation

private let vmfix5Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func vmfix5Source(_ path: String) -> String { (try? String(contentsOf: vmfix5Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func vmfix5InstallCatalog() {
    let file = vmfix5Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data()))
}

/// Names that are no one's words to translate: apps, the Mac, and the folder path.
private let vmfix5Names = ["Aris", "macOS", "Mac", "Spotlight", "Finder", "Claude Code", "Claude", "~/Library/Containers/com.lumenjsn.aris"]

/// `text` with the user's own values (`own`) and the names taken out.
private func vmfix5Aris(_ text: String, own: [String]) -> String {
    (own + vmfix5Names).sorted { $0.count > $1.count }.reduce(text) { $0.replacingOccurrences(of: $1, with: " ") }
}

private func vmfix5HasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

/// ASCII words (two letters or more; "AM"/"PM" are never in a Korean line either).
private func vmfix5EnglishWords(_ text: String) -> [String] {
    text.components(separatedBy: CharacterSet.letters.inverted).filter { word in
        word.count >= 2 && word.unicodeScalars.allSatisfy { $0.isASCII }
    }
}

/// One render in the UI's language: no Hangul of Aris's in English, no English word of Aris's in Korean.
private func vmfix5Checks(_ text: String, english: Bool, own: [String], _ name: String) {
    let aris = vmfix5Aris(text, own: own)
    if english {
        check(!vmfix5HasHangul(aris), "vmfix5 D4: \(name), English UI: no Korean of Aris's (\(text))")
    } else {
        check(vmfix5EnglishWords(aris).isEmpty, "vmfix5 D4: \(name), Korean UI: no English word of Aris's (\(text))")
    }
}

private let vmfix5Seoul: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar
}()

private func vmfix5At(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    vmfix5Seoul.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

func runVmfix5LangTests() {
    vmfix5InstallCatalog()
    defer { ArisSettingsCopy.install([:]) }
    vmfix5DayReviewTests()
    vmfix5TodoTests()
    vmfix5ToolErrorTests()
    vmfix5SettingsFooterTests()
    vmfix5ReceiptPillTests()
    vmfix5SetupLeaveTests()
    vmfix5UninstallTests()
}

// MARK: - D4, D5: the day review

private func vmfix5TurnSource() -> String { vmfix5Source("Aris/private/Aris/DayEnd/ArisController+DayEnd.swift") }

/// The VM's day (notes3/I9-today.log: 9 planned, 0 done, 5 for tomorrow; cap3/I9-today-list2.jpg: 그 밖 · 4), with
/// The user's titles in the request's language: English titles under a Korean UI, Korean ones under an English UI.
private func vmfix5Day(titles english: Bool) -> (ArisDayEndFacts, [String]) {
    let planned = english ? ["water the ferns", "water the plants", "Call the plumber", "stretch", "fold the laundry", "sweep the porch", "buy stamps",
                             "Call the dentist", "Register for the lantern walk"]
        : ["고사리 물 주기", "화분 물 주기", "배관공 부르기", "스트레칭", "빨래 개기", "현관 쓸기", "우표 사기", "치과 전화", "등불 걷기 신청"]
    let tomorrow = english ? "buy milk" : "우유 사기"
    var facts = ArisDayEndFacts()
    facts.todos = planned.enumerated().map { ArisDayEndFacts.Todo(id: "t\($0.offset)", title: $0.element, due: vmfix5At(day: 19, 0)) }
        + (0..<4).map { ArisDayEndFacts.Todo(id: "m\($0)", title: tomorrow, due: vmfix5At(day: 20, 9), hasTime: true) }
    facts.activity = [("할 일 추가: \(tomorrow)", 7, 39), ("할 일 추가: \(tomorrow)", 7, 40), ("타이머: 3분", 7, 41), ("할 일 추가: \(tomorrow)", 7, 42)].map { line in
        ArisActivityItem(id: UUID().uuidString, date: vmfix5At(day: 19, line.1, line.2), job: "대화", worker: "Aris", summary: line.0, undoable: true,
                         undone: false, asks: false, teammate: nil)
    }
    return (facts, planned + [tomorrow])
}

private func vmfix5DayReviewTests() {
    for uiEnglish in [true, false] {
        let (facts, own) = vmfix5Day(titles: !uiEnglish)
        let card = ArisDayEnd.make(facts, now: vmfix5At(day: 19, 7, 43), calendar: vmfix5Seoul, english: uiEnglish)
        check(card.counts.planned == 9 && card.counts.extra == 4 && card.counts.tomorrow == 4, "vmfix5: the VM's day as the card counts it (\(card.counts))")
        var shown = [card.sentence, ArisDayEndCopy.list(english: uiEnglish), ArisDayEndCopy.plannedTitle(card.counts.planned, english: uiEnglish),
                     ArisDayEndCopy.tomorrowTitle(card.counts.tomorrow, english: uiEnglish), ArisDayEndCopy.extrasTitle(card.counts.extra, english: uiEnglish),
                     ArisDayEndCopy.push(english: uiEnglish), ArisDayEndCopy.listHelp(open: false, english: uiEnglish), card.chip]
        shown += card.planned.map { ArisDayEndCopy.kind($0.kind, english: uiEnglish) }
        shown += card.tomorrow.map { $0.time + " " + ArisDayEndCopy.kind($0.kind, english: uiEnglish) }
        shown += card.extras.map(\.title)
        for line in shown { vmfix5Checks(line, english: uiEnglish, own: own + ["3"], "day review") }
        // D5: asked what was done, the answer says what was done besides the plan, as the day in review says it; the
        // card's own sentence (the chip, "오늘 정리해 줘") stays the short one. The request is in the other language.
        let done = uiEnglish ? "Four other things got done too." : "그 밖에 네 가지를 더 했어요."
        let asked = uiEnglish ? "오늘 뭐 했어" : "what did i do today"
        let answer = ArisDayEndCopy.answer(card.counts, unread: false, english: uiEnglish, phrase: asked)
        check(answer == card.sentence + " " + done, "vmfix5 D5: \"\(asked)\" says what was done besides the open plans (\(answer))")
        vmfix5Checks(answer, english: uiEnglish, own: own, "day review answer")
        let wrap = ArisDayEndCopy.answer(card.counts, unread: false, english: uiEnglish, phrase: uiEnglish ? "오늘 정리해 줘" : "wrap up my day")
        check(wrap == card.sentence, "vmfix5 D5: a wrap-up keeps the card's one sentence (\(wrap))")
    }
    var none = ArisDayEnd.Counts()
    none.planned = 2
    none.left = 2
    check(ArisDayEndCopy.answer(none, unread: false, english: false, phrase: "오늘 뭐 했어") == ArisDayEndCopy.sentence(none, unread: false, english: false),
          "vmfix5 D5: nothing done besides the plan adds nothing")
    check(ArisDayEndCopy.asksWhatWasDone("오늘 뭐 했어") && ArisDayEndCopy.asksWhatWasDone("내가 오늘 한 일 알려 줘") && ArisDayEndCopy.asksWhatWasDone("what have i done today")
            && !ArisDayEndCopy.asksWhatWasDone("오늘 정리해 줘") && !ArisDayEndCopy.asksWhatWasDone("할 일 뭐 남았어"),
          "vmfix5 D5: which requests ask what was done")
    check(vmfix5TurnSource().contains("ArisDayEndCopy.answer(card.counts, unread: card.activityUnread, english: card.english, phrase: ArisIntent.phrase(of: heard))"),
          "vmfix5 D5: the turn answers with it when the day in review is off")
    let turn = vmfix5TurnSource()
    let asked = turn.components(separatedBy: "func showDayEnd(heard: String)").last?.components(separatedBy: "func openDayEnd()").first ?? ""
    check(asked.contains("let english = ArisUIWords.english") && asked.contains("model.compose(english: english)") && !asked.contains("korean"),
          "vmfix5 D4: the day review asked for in a turn is in the UI's language, never the request's")
    check(vmfix5Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift").contains("return await showDayEnd(heard: unmarked)"),
          "vmfix5 D4: the turn hands no request language to the day review")
}

// MARK: - D4, D5: the to-do replies

private func vmfix5TodoTests() {
    let now = vmfix5At(day: 19, 7, 40)
    for uiEnglish in [true, false] {
        let korean = !uiEnglish
        let title = uiEnglish ? "우유 사기" : "buy milk"
        let replies = [ArisLocalReply.todoAdded(.saved(title: title, due: vmfix5At(day: 20, 9), hasTime: true), korean: korean, now: now, calendar: vmfix5Seoul),
                       ArisLocalReply.todoAdded(.saved(title: title), korean: korean), ArisLocalReply.todoAdded(.noAccess, korean: korean),
                       ArisLocalReply.todoAdded(.demo, korean: korean), ArisLocalReply.todoAdded(.noTitle, korean: korean),
                       ArisLocalReply.todoAdded(.failed(why: nil), korean: korean), ArisLocalReply.todosUnread(korean: korean),
                       ArisLocalReply.noRemindersAccess(korean: korean), ArisIntent.finishTodo(title).acknowledgement(korean: korean) ?? "",
                       ArisLocalReply.todoNotTicked(title, why: nil, korean: korean)]
        for reply in replies { vmfix5Checks(reply, english: uiEnglish, own: [title], "to-do reply") }
    }
    // D5: the VM's "내일 아침 9시에 우유 사기 미리 알림 추가해 줘", stored for tomorrow 9:00.
    check(ArisLocalReply.todoAdded(.saved(title: "우유 사기", due: vmfix5At(day: 20, 9), hasTime: true), korean: true, now: now, calendar: vmfix5Seoul)
            == "할 일에 넣었어요: 우유 사기 (내일 오전 9시)", "vmfix5 D5: the to-do reply says the due time it stored")
    check(ArisLocalReply.todoAdded(.saved(title: "buy milk", due: vmfix5At(day: 20, 9), hasTime: true), korean: false, now: now, calendar: vmfix5Seoul)
            == "Added to your to-dos: buy milk (tomorrow at 9 AM)"
          && ArisLocalReply.todoAdded(.saved(title: "buy milk", due: vmfix5At(day: 20, 0)), korean: false, now: now, calendar: vmfix5Seoul)
            == "Added to your to-dos: buy milk (tomorrow)",
          "vmfix5 D5: in English too, a day alone without a time")
    check(ArisLocalReply.noRemindersAccess(korean: true) == "미리 알림 접근이 꺼져 있어요. 설정 › 앱 › 권한 › 미리 알림 접근에서 켜 주세요."
            && ArisLocalReply.noRemindersAccess(korean: false).hasPrefix("Aris can't use Reminders yet. Turn it on in Settings › "),
          "vmfix5 D4: the Reminders path is in the sentence's language (\(ArisLocalReply.noRemindersAccess(korean: false)))")
    let runs = vmfix5Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    check(runs.contains("static var todoKorean: Bool { replyKorean }") && runs.components(separatedBy: "let korean = Self.todoKorean").count == 3
            && runs.contains("finishTodo(found, heard: unmarked, korean: Self.todoKorean)"),
          "vmfix5 D4: listing, adding and ticking off to-dos answer whole in one language (the request's since the tenth VM run, mind10a 4)")
    let local = vmfix5Source("Aris/private/Aris/ArisController+Local.swift")
    check(local.contains("let asked = ArisTodoModel.draft(from: item)") && local.contains("return .saved(title: title, due: asked.due, hasTime: asked.hasTime)"),
          "vmfix5 D5: the reply's due time is read from the words as the stored one was")
}

// MARK: - D4: tool errors

private func vmfix5ToolErrorTests() {
    check(ArisToolErrorWords.known.count >= 6, "vmfix5 D4: every tool reason is listed")
    for entry in ArisToolErrorWords.known {
        for uiEnglish in [true, false] {
            guard let shown = ArisToolErrorWords.shown(entry.sample, english: uiEnglish) else {
                check(false, "vmfix5 D4: \(entry.sample) is said in \(uiEnglish ? "English" : "Korean")")
                continue
            }
            vmfix5Checks(shown, english: uiEnglish, own: [], "tool reason \(entry.pattern)")
            vmfix5Checks(ArisToolErrorWords.line("할 일을 하지 못했어요", "Couldn't do it", problem: entry.sample, inEnglish: uiEnglish), english: uiEnglish, own: [],
                         "tool line \(entry.pattern)")
        }
    }
    // The VM's line (cap3/K-grid.jpg): "3단계 ‘Spotlight 열기’가 안 됐어요: no app on this Mac is called ‘Spotlight’".
    check(ArisToolErrorWords.shown("no app on this Mac is called ‘Spotlight’", english: false) == "이 Mac에 없는 앱이에요: ‘Spotlight’"
            && ArisToolErrorWords.shown("no app on this Mac is called 'TextEdit'", english: true) == "no app on this Mac is called ‘TextEdit’",
          "vmfix5 D4: the app layer's unknown-app reason is said in the UI's language")
}

// MARK: - D4: the settings footer

private func vmfix5SettingsFooterTests() {
    var lists = ArisModelLists()
    lists.lists[ArisBrain.claude.rawValue] = ArisModelList(at: Date(timeIntervalSince1970: 0), options: [], fromTool: false)
    let english = ArisModelChoiceRows.footer(.claude, lists: lists, wording: ArisSettingsWording(pageEnglish: true, frameEnglish: true))
    check(!vmfix5HasHangul(english) && english.contains("Automatic lets Aris pick") && english.contains("didn't give its list"),
          "vmfix5 D4: the AI · Model footer is all English on an English Mac (\(english))")
    let korean = ArisModelChoiceRows.footer(.claude, lists: lists, wording: .korean)
    vmfix5Checks(korean, english: false, own: [], "AI · Model footer")
    check(vmfix5Source("Aris/components/Settings/ArisModelChoiceSection.swift").contains("Text(ArisModelChoiceRows.footer(brain, lists: model.lists, installed: brainSetup.ready?[brain], wording: w))"),
          "vmfix5 D4: the section draws the footer looked up part by part")
}

// MARK: - D4: the receipt's 되돌리기 pill

private func vmfix5ReceiptPillTests() {
    let chip = vmfix5Source("Aris/private/Aris/Home/ArisReceiptChip.swift")
    let pill = chip.components(separatedBy: "Button(action: undo) {").last?.components(separatedBy: ".help(ArisReceiptWords.undo").first ?? ""
    check(pill.contains("Text(verbatim: ArisReceiptWords.undo(english: english)).lineLimit(1)") && pill.contains(".fixedSize()")
            && pill.contains(".layoutPriority(1)"),
          "vmfix5 D4: the receipt's 되돌리기 keeps its width; the act's words give way first (K-grid: \"되돌…\")")
}

// MARK: - D5: System Settings after the Accessibility card

private func vmfix5SetupLeaveTests() {
    // notes3/setup-walk.txt: Allow opened System Settings (not running before), the password sheet, Aris came back by
    // itself, then later macOS handed the screen to System Settings again (a prompt closing), long after the setup came
    // forward: by the finish it counted as the user's and was left open.
    var leave = ArisSetupLeave(frontApp: "com.apple.finder")
    leave.sending(runningPid: nil)
    leave.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 501, sinceForward: nil)
    leave.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 501, sinceForward: 0)
    let atGrant = leave.planOnGranted(runningPid: 501)
    check(atGrant.hidesSettings && atGrant.activates == nil, "vmfix5 D5: as Accessibility comes on, the System Settings the setup opened is put away")
    var old = leave
    old.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 501, sinceForward: 120)
    check(!old.plan(runningPid: 501, quitting: false).hidesSettings, "vmfix5 D5: (why) waiting until the finish lost it to a later activation")
    leave.putAway()
    // Fourth VM run: put away and left alone at the finish, it came back in front as the window closed; it is kept
    // out of the way then too (vmfix6-app-tests), and never put away twice on a grant.
    check(!leave.planOnGranted(runningPid: 501).hidesSettings,
          "vmfix5 D5: put away once, nothing more to do for it on a grant")
    // The next card (Screen Recording) sends the user to that same process: still the setup's, put away at the finish.
    var next = leave
    next.sending(runningPid: 501)
    next.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 501, sinceForward: nil)
    next.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 501, sinceForward: 0)
    check(next.plan(runningPid: 501, quitting: false).hidesSettings, "vmfix5 D5: sent back to the one it put away, it is still the setup's")
    // One that was open before the setup and that a card sent the user to is put away too (sixth VM run, item 8).
    var theirs = ArisSetupLeave()
    theirs.sending(runningPid: 77)
    check(theirs.planOnGranted(runningPid: 77).hidesSettings, "vmfix5 D5 / vmfix9 item 8: a System Settings the card sent the user to is put away")
    theirs.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 77, sinceForward: nil)
    theirs.cameForward(.aris, bundleID: "com.lumenjsn.aris", settingsPid: 77, sinceForward: 0)
    theirs.cameForward(.systemSettings, bundleID: "com.apple.systempreferences", settingsPid: 77, sinceForward: 60)
    check(!theirs.planOnGranted(runningPid: 77).hidesSettings, "vmfix5 D5: one the user went back to by themselves is left alone")
    let setup = vmfix5Source("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Setup.swift")
    check(setup.contains("if card.steps.contains(.accessibility), !card.steps.contains(.screen) { guide.putAwaySettings() }"),
          "vmfix5 D5: only the Accessibility card puts it away (Screen Recording's Quit & Reopen is asked in System Settings)")
}

// MARK: - D6: the uninstall list

private func vmfix5UninstallTests() {
    typealias R = ArisUninstallReply
    check(R.mark("sandbox", index: 7, done: nil, kept: false, failed: []) == .byHand && R.mark("app", index: 0, done: nil, kept: false, failed: []) == .willRemove
            && R.mark("data", index: 4, done: nil, kept: false, failed: []) == .choice,
          "vmfix5 D6: before it runs, the sandbox folder is shown as one Aris can't remove, never ticked")
    check(R.mark("sandbox", index: 7, done: 8, kept: false, failed: ["sandbox"]) == .byHand && R.mark("app", index: 0, done: 8, kept: false, failed: []) == .removed
            && R.mark("hooks", index: 1, done: 8, kept: false, failed: ["hooks"]) == .failed && R.mark("tools", index: 3, done: 2, kept: false, failed: []) == .pending,
          "vmfix5 D6: after it runs, the sandbox folder is still marked as his to remove, not as a failure")
    check(R.english[R.sandboxBefore] != nil && R.english[R.sandboxTag] != nil && R.sandboxBefore.contains("Finder")
            && R.sandboxBefore.contains("~/Library/Containers/com.lumenjsn.aris"),
          "vmfix5 D6: the row says from the start what to do, in both languages")
    vmfix5Checks(R.english[R.sandboxBefore] ?? "", english: true, own: [], "uninstall sandbox line")
    vmfix5Checks(R.sandboxBefore, english: false, own: [], "uninstall sandbox line")
    let section = vmfix5Source("Aris/components/Settings/ArisDataSection.swift")
    check(vmfix5Source("Aris/private/Aris/ArisDataModel.swift").contains("(\"sandbox\", \"샌드박스 폴더\", ArisUninstallReply.sandboxBefore)")
            && section.contains("tag: byHand ? ArisUninstallReply.sandboxTag") && section.contains("switch ArisUninstallReply.mark(id, index: index, done: model.uninstallDone"),
          "vmfix5 D6: the sheet draws the row's mark and line from that")
}
