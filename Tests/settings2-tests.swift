// The settings window as the owner picked it from settings-mock.html (qa/design-1111/PICKS.md): one card a section, the
// preview only where it shows something, one sentence a row, 14 pages, the folded notch groups, one menu, and the
// fixes 10–20. Pure parts only; the pictures are checked with tests/settings-render.
import CoreGraphics
import Foundation

private func s2Rows(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot = ArisSettingsSnapshot()) -> [ArisSettingItem] {
    ArisSettingsBuilder.sections(page, s).flatMap(\.rows)
}

private func s2LayoutTests() {
    // Rows added the old way by the branches that merge after this one: a switch, a menu, buttons, a field.
    let added = [
        ArisSettingItem(id: "x.switch", icon: .symbol("moon"), title: "밤에는 조용히", control: .toggle(.muted, true)),
        ArisSettingItem(id: "x.menu", icon: .symbol("clock"), title: "시작", control: .menu(.quietHours, [.init(id: "22", title: "22시")], selected: "22")),
        ArisSettingItem(id: "x.clear", icon: .symbol("trash"), title: "배운 제안 지우기", control: .buttons([ArisSettingButton(title: "지우기", action: .clearName, kind: .danger)])),
    ]
    let section = ArisSettingSection(id: "x", heading: "알림", rows: added)
    check(ArisSettingsLayout.blocks(section) == [.group(added)], "2-B: rows added through the old components land in the section's one card, with no case of their own")
    for page in ArisSettingsPage.allCases {
        let sections = ArisSettingsBuilder.sections(page, ArisSettingsSnapshot())
        check(sections.allSatisfy { ArisSettingsLayout.blocks($0).count <= 1 }, "2-B: every section of \(page.rawValue) is at most one card")
    }
}

private func s2StageTests() {
    func plan(_ page: ArisSettingsPage, _ change: (inout ArisNotchPreviewInput) -> Void = { _ in }) -> ArisNotchPreviewPlan {
        var input = ArisNotchPreviewInput()
        input.page = page
        change(&input)
        return ArisNotchPreviewPlan.make(input)
    }
    check([ArisSettingsPage.aris, .voice, .notch, .control].allSatisfy { plan($0).shown }, "1-A: 대화, 목소리 · 언어, 노치 and 컴퓨터 제어 keep the preview")
    check(plan(.ai) { $0.aiWho = ["Claude", "Whisper", "Mac"] }.shown && !plan(.ai).shown, "1-A: AI 서비스 shows who does each job, once it knows")
    check(plan(.skills) { $0.skillsOn = true; $0.skillTitles = ["회의록"] }.shown && !plan(.skills).shown && !plan(.skills) { $0.skillsOn = true }.shown,
          "1-A: 스킬 has a preview only when there is a skill to show in it")
    check([ArisSettingsPage.memory, .dictation, .todo, .features, .general, .keys, .about].allSatisfy { !plan($0).shown },
          "1-A: the pages that only list settings start at their title")
}

/// How many sentences a line has: its full stops, question marks and 요-endings before a space count once each.
private func s2Sentences(_ text: String) -> Int {
    // A decimal point isn't a full stop ("0.3초").
    let plain = text.replacingOccurrences(of: #"(?<=[0-9])\.(?=[0-9])"#, with: "", options: .regularExpression)
    let marks = plain.replacingOccurrences(of: "…", with: "").components(separatedBy: CharacterSet(charactersIn: ".?!")).dropLast()
    return max(1, marks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count)
}

private func s2CopyTests() {
    var full = ArisSettingsSnapshot()
    full.reminders = .granted
    full.calendarAccess = .granted
    full.hasVoiceKey = true
    full.standingLoaded = true
    full.standing = []
    full.memories = []
    full.memoriesLoaded = true
    // The rows another branch owns (quiet time, the day-end offer) and the AI 서비스 page keep their own lines.
    let others: Set<String> = ["aris.mute", "aris.quietHours", ArisDayEndSetting.id]
    var long: [String] = []
    for snapshot in [ArisSettingsSnapshot(), full] {
        for page in ArisSettingsPage.allCases where page != .ai {
            for row in s2Rows(page, snapshot) where !others.contains(row.id) {
                if let desc = row.desc, s2Sentences(desc) > 1 { long.append("\(row.id): \(desc)") }
            }
        }
    }
    check(long.isEmpty, "5-B: every row's line is one sentence" + (long.isEmpty ? "" : " (\(long.prefix(4)))"))
    let notes = ArisSettingsPage.allCases.filter { $0 != .ai }.flatMap { ArisSettingsBuilder.sections($0, full) }.compactMap(\.note)
    check(notes.allSatisfy { s2Sentences($0) <= 2 } && !notes.isEmpty, "5-B: what must be known is one small line under the card, two sentences at most")
    let talk = ArisSettingsBuilder.sections(.aris, full).first { $0.id == "aris.talk" }
    check(talk?.note?.contains("녹음하지 않아요") == true && talk?.note?.contains("보라색 표시") == true && talk?.note?.contains("Esc") == true,
          "5-B: 대화 모드's small line keeps how it ends, the purple mark and that nothing is recorded")
    let untrained = ArisSettingsBuilder.sections(.aris, ArisSettingsSnapshot()).first { $0.id == "aris.call" }?.note ?? ""
    check(untrained.contains("이 Mac 안에서만") && untrained.contains("모두 확인해요"), "5-B: 부르기 says the name is heard on this Mac only, and that every voice is checked until one is learned")
    let polish = ArisSettingsBuilder.sections(.dictation, full).first { $0.id == "dictation.polish" }?.note ?? ""
    check(polish.contains("Anthropic"), "5-B: 다듬기 still says where the words go when Claude tidies them")
    let standing = ArisSettingsBuilder.sections(.control, full).first { $0.id == "control.standing" }?.note ?? ""
    check(standing.contains("메일 보내기") && standing.contains("영구 삭제") && standing.contains("돈이 드는 일은 하지 않아요"), "5-B: 묻지 않고 하는 일 keeps what is always asked and that no money is spent")
}

private func s2SidebarTests() {
    check(ArisSettingsPage.allCases.count == 14 && ArisSettingsGroup.allCases.map(\.rawValue) == ["아리스", "도구", "화면 · 앱"],
          "6-B: 14 pages in three groups named in Korean")
    check(ArisSettingsGroup.allCases.flatMap(\.pages) == ArisSettingsPage.allCases, "6-B: the sidebar lists every page once, in the pages' order")
    check(ArisSidebarMetrics.height() <= ArisSidebarMetrics.windowSize.height,
          "6-B: every page is visible at the window's default height with no scrolling (needs \(ArisSidebarMetrics.height()) of \(ArisSidebarMetrics.windowSize.height))")
    check(ArisSettingsPage.named("calendar") == .todo && ArisSettingsPage.named("look") == .general && ArisSettingsPage.named("todo") == .todo
          && ArisSettingsPage.named("nope") == nil, "6-B: a link that names a page that was merged opens the page that took its rows")

    // Every way into a page lands on a row that page draws: the search, the fix buttons, the status line, the guide.
    var full = ArisSettingsSnapshot()
    full.reminders = .granted
    full.calendarAccess = .granted
    full.heightMode = "custom"
    full.more.flatHeightMode = "custom"
    full.more.peek = true
    full.permissions = [.init(id: "ax", title: "a", desc: "a", granted: false), .init(id: "screen", title: "s", desc: "s", granted: true), .init(id: "mic", title: "m", desc: "m", granted: true)]
    full.memoriesLoaded = true
    full.memories = [ArisMemoryItem(id: "m1", kind: "fact", subject: "", text: "커피는 아이스", source: "said", said: 0, used: nil)]
    func tags(_ page: ArisSettingsPage) -> Set<String> {
        switch page {
        case .team: Set(ArisSettingsIndex.teamAnchors)
        case .skills: Set(ArisSettingsIndex.skillsAnchors)
        default: ArisSettingsLayout.tags(ArisSettingsBuilder.sections(page, full))
        }
    }
    let lost = ArisSettingsIndex.entries.filter { !tags($0.page).contains($0.id) }.map(\.id)
    check(lost.isEmpty, "6-B: every search result opens the page that draws its row" + (lost.isEmpty ? "" : " (\(lost))"))
    let fixes = ArisFix.Row.allCases.filter { row in ArisSettingsPage.named(row.page).map { !tags($0).contains(row.anchor) } ?? true }
    check(fixes.isEmpty, "6-B: every fix button that opens Settings lands on a row of its page" + (fixes.isEmpty ? "" : " (\(fixes))"))
    check(tags(.control).contains(ArisSettingsCaption.permissionsAnchor) && tags(.ai).contains(ArisSettingsCaption.brainAnchor)
          && tags(ArisSettingsCaption.talkKey.page).contains(ArisSettingsCaption.talkKey.anchor),
          "6-B: the status line's and the guide's links (permissions, the answering AI, the talk key) land on their rows")
    let link = s2Rows(.features, full).first { $0.id == "features.calendar" }
    check(link?.control == .link(.go(.todo, anchor: "calendar.intro"), value: nil) && tags(.todo).contains("calendar.intro"),
          "6-B: 음악 · 선반's calendar link opens 할 일 · 캘린더 on the calendar's card")
    check(Set(["look.theme", "look.accent", "look.reduceMotion"]).isSubset(of: tags(.general)) && Set(["look.settingsIcon", "look.alwaysTabs"]).isSubset(of: tags(.notch)),
          "6-B: what the 모양 page held is in 일반 (the window's look) and 노치 (the notch's icon and tabs)")
    check(Set(["todo.access", "calendar.access", "calendar.allDay"]).isSubset(of: tags(.todo)), "6-B: 할 일 and 캘린더 are one page")
}

private func s2FoldTests() {
    let notch = ArisSettingsBuilder.sections(.notch, ArisSettingsSnapshot())
    let folded = notch.filter { $0.fold != nil }
    check(folded.map(\.id) == ["notch.advanced", "notch.gestureDetail", "notch.window"] && folded.allSatisfy { !$0.rows.isEmpty && !$0.fold!.desc.isEmpty },
          "7-A: the notch page's motion, gesture and window groups are one collapsed line each, saying what is inside")
    check(notch.filter { $0.fold == nil }.map(\.id) == ["notch.top", "notch.side", "notch.sideLeft", "notch.sideRight"], "7-A: what is used often stays open")
    check(ArisSettingsLayout.fold(holding: "notch.lockScreen", in: notch) == "notch.window" && ArisSettingsLayout.fold(holding: "notch.sensitivity", in: notch) == "notch.gestureDetail"
          && ArisSettingsLayout.fold(holding: "notch.advanced", in: notch) == "notch.advanced" && ArisSettingsLayout.fold(holding: "notch.hover", in: notch) == nil,
          "7-A: a search that lands on a folded row, or on the group itself, knows which fold to open; an open row needs none")
    let searchable = ArisSettingsBuilder.searchable(ArisSettingsSnapshot())
    check(["notch.hoverDelay", "notch.closeGesture", "notch.lockScreen"].allSatisfy(searchable.contains), "7-A: the folded rows are still found by the search")
    check(ArisSettingsLayout.openFolds(stored: ArisSettingsLayout.stored(openFolds: ["notch.window", "notch.advanced"])) == ["notch.window", "notch.advanced"]
          && ArisSettingsLayout.openFolds(stored: nil).isEmpty && ArisSettingsLayout.openFolds(stored: "x").isEmpty,
          "7-A: which folds are open is remembered, and a first launch (or anything unreadable) has them all closed")
    let english = ArisSettingsWording(pageEnglish: true, frameEnglish: true).sections(notch).compactMap(\.fold)
    check(english.count == 3, "7-A: the folds keep their line in the English window")
}

private func s2MenuTests() {
    let options = [ArisSettingOption(id: "system", title: "시스템 설정대로"), ArisSettingOption(id: "ko", title: "한국어"), ArisSettingOption(id: "en", title: "English", detail: "영어")]
    let menu = ArisAIMenu.choices(options, selected: "ko")
    check(menu.items.map(\.id) == ["system", "ko", "en"] && menu.items.map(\.checked) == [false, true, false] && menu.items[2].subtitle == "영어" && menu.search == nil,
          "item 8: a settings row's choices are the one menu's items, the chosen one checked")
    let opened = ArisAIMenuHighlight.opening(menu)
    check(opened.id == "ko", "item 8: the menu opens with the chosen item highlighted")
    let at = CGPoint(x: 1, y: 1)
    check(opened.moved(1, in: menu, pointer: at).id == "en" && opened.moved(1, in: menu, pointer: at).moved(1, in: menu, pointer: at).id == "system"
          && opened.moved(-1, in: menu, pointer: at).id == "system", "item 8: the arrow keys move the highlight and wrap")
    check(opened.typed("e", in: menu, pointer: at).id == "en" && opened.typed("E", in: menu, pointer: at).id == "en", "item 8: typing a letter goes to the item that starts with it")
    check(opened.typed("ㅅ", in: menu, pointer: at).id == "system" && opened.typed("시", in: menu, pointer: at).id == "system",
          "item 8: a Hangul consonant, or a syllable, finds the item that starts with it")
    check(opened.typed("z", in: menu, pointer: at) == opened, "item 8: a letter nothing starts with leaves the highlight where it is")
    let two = ArisAIMenu.choices([.init(id: "a", title: "Apple Music"), .init(id: "b", title: "AirDrop"), .init(id: "c", title: "Spotify")], selected: "a")
    let first = ArisAIMenuHighlight.opening(two).typed("a", in: two, pointer: at)
    check(first.id == "b" && first.typed("a", in: two, pointer: at).id == "a", "item 8: the same letter again goes on to the next item that starts with it")
    check(first.keyMoves == 1 && first.pointerAtKey == at, "item 8: a typed letter scrolls the list to its row like an arrow key, and a resting pointer doesn't take the highlight back")
    let said = opened.typed("s", in: menu, said: { $0 == "시스템 설정대로" ? "System default" : $0 }, pointer: at)
    check(said.id == "system", "item 8: in the English window the letter is matched against the name as it is drawn")
}

private func s2FixesTests() {
    // 10: the slider says its own value.
    check(ArisSliderStep.label(0.3, step: 0.1, unit: "초", zero: "바로") == "0.3초" && ArisSliderStep.label(0, step: 0.1, unit: "초", zero: "바로") == "바로"
          && ArisSliderStep.label(38, step: 1, unit: "pt") == "38pt" && ArisSliderStep.label(0, step: 1, unit: "pt") == "0pt",
          "item 10: a slider's value is written beside it, with its unit, and in a word at zero where one was given")
    var more = ArisSettingsSnapshot()
    more.heightMode = "custom"
    more.more.flatHeightMode = "custom"
    let sliders = (s2Rows(.notch, more) + s2Rows(.features, more)).filter { if case .slider = $0.control { true } else { false } }
    check(sliders.count == 5 && sliders.allSatisfy { !($0.desc ?? "").contains(where: \.isNumber) || $0.id == "notch.flatCustomHeight" },
          "item 10: the five sliders' lines no longer carry the value (it is beside the bar)")
    check(ArisSliderStep.nudge(0.3, up: true, in: 0...1, step: 0.1) == 0.4 && ArisSliderStep.nudge(0, up: false, in: 0...1, step: 0.1) == 0,
          "item 10: an arrow key moves the slider one step and stops at its ends")

    // 11: permissions.
    let permissions: [ArisSettingsSnapshot.Permission] = [.init(id: "ax", title: "손쉬운 사용", desc: "a.", granted: true), .init(id: "screen", title: "화면 기록", desc: "s.", granted: false),
                                                          .init(id: "mic", title: "마이크", desc: "m.", granted: true)]
        + ArisSettingsSnapshot.folderPermissions(granted: ["Desktop": true, "Documents": true])
    let rows = ArisSettingsBuilder.permissionRows(permissions)
    check(rows.map(\.id) == ["control.screen", "control.folders", "control.ax", "control.mic"], "item 11: what still needs allowing comes first, and the three folders are one row")
    check(rows[0].control == .buttons([ArisSettingButton(title: "허용하기", action: .permission("screen"), kind: .primary)]) && rows[0].icon == .status(false)
          && rows[1].control == .buttons([ArisSettingButton(title: "허용하기", action: .permission("folders"), kind: .primary)]),
          "item 11: a missing permission has the one button to press")
    check(rows[2].control == .said("허용됨") && rows[2].icon == .symbol("checkmark") && rows[3].control == .said("허용됨"),
          "item 11: an allowed permission is a check and 허용됨, with nothing to press")
    check(!rows.contains { $0.title.contains("aris-agent") || ($0.desc ?? "").contains("~/") || ($0.desc ?? "").contains("⌘") },
          "item 11: no process name, path or key combination in a permission row")
    let all = ArisSettingsBuilder.permissionRows(ArisSettingsSnapshot.folderPermissions(granted: ["Desktop": true, "Documents": true, "Downloads": true]))
    check(all.map(\.id) == ["control.folders"] && all[0].control == .said("허용됨"), "item 11: the folders' row is allowed once all three are")
    var granted = ArisSettingsSnapshot()
    granted.permissions = [.init(id: "ax", title: "a", desc: "a.", granted: true)]
    var missing = granted
    missing.permissions = [.init(id: "ax", title: "a", desc: "a.", granted: false)]
    let note = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.control, s).first { $0.id == "control.permissions" }?.note }
    check(note(granted) == nil && note(missing)?.contains("시스템 설정") == true, "item 11: how to allow is said only while something is missing")

    // 12: the toast.
    check(ArisToastTone.ok.symbol == "checkmark.circle" && ArisToastTone.bad.symbol == "xmark.circle" && ArisToastTone.info.symbol == "info.circle",
          "item 12: a toast for something that did not work wears a cross, not a check")
    check(ArisToastTone.seconds(for: "저장했어요") == 2 && ArisToastTone.seconds(for: String(repeating: "가", count: 100)) == 4.5 && ArisToastTone.seconds(for: String(repeating: "가", count: 400)) == 7,
          "item 12: a toast stays 45 ms a character, between 2 and 7 seconds")

    // 14: empty and loading.
    var s = ArisSettingsSnapshot()
    let loading = ArisMemorySettingsRows.sections(s).first { $0.id == "memory.list" }?.rows ?? []
    check(loading.map(\.id) == ["memory.none"] && loading[0].control == .loading, "item 14: while the memories load the card says so, and shimmers")
    s.memoriesLoaded = true
    s.memories = []
    let empty = ArisMemorySettingsRows.sections(s).first { $0.id == "memory.list" }?.rows ?? []
    check(empty.map(\.id) == ["memory.none"] && empty[0].control == .empty && empty[0].desc?.contains("기억해") == true,
          "item 14: with nothing remembered the card is an empty state, and the search over nothing is gone")
    s.memories = [ArisMemoryItem(id: "m1", kind: "fact", subject: "", text: "커피는 아이스", source: "said", said: 0, used: nil)]
    check((ArisMemorySettingsRows.sections(s).first { $0.id == "memory.list" }?.rows.first?.id) == "memory.search", "item 14: the search comes with the first memory")
    var control = ArisSettingsSnapshot()
    check((ArisSettingsBuilder.sections(.control, control).last?.rows.first?.control) == .loading, "item 14: the standing permissions say they are loading")
    control.standingLoaded = true
    control.standing = []
    check((ArisSettingsBuilder.sections(.control, control).last?.rows.first?.control) == .empty, "item 14: and then that there are none yet")
    var calendar = ArisSettingsSnapshot()
    calendar.calendarAccess = .granted
    check((ArisSettingsBuilder.sections(.todo, calendar).first { $0.id == "calendar.include" }?.rows.first?.control) == .empty, "item 14: no calendars is an empty state in the card")

    // 15: the search says why.
    let dark = ArisSettingsIndex.matches("다크")
    check(dark.first?.entry.id == "look.theme" && dark.first?.why == "다크", "item 15: a result found by a keyword says which (다크 → 설정 창 모양 · 다크)")
    check(ArisSettingsIndex.matches("설정 창").first?.why == nil, "item 15: a result found by its own name needs no reason")
    check(ArisSettingsIndex.matches("다크").map(\.entry) == ArisSettingsIndex.search("다크"), "item 15: the results are the ones the search always gave")

    // 17, 20.
    check(!ArisSettingsGroup.allCases.map(\.rawValue).contains { $0.unicodeScalars.contains { ("A"..."Z").contains($0) } }, "item 17: no English group name in the Korean sidebar")
    check(!ArisSettingsBuilder.sections(.control, ArisSettingsSnapshot()).flatMap(\.rows).contains { $0.id == "control.bot" }
          && ArisSettingsIndex.entry("control.bot") == nil, "item 20: no row for a feature that doesn't exist")
    check(ArisSettingsIndex.showsNew(.skills, seen: []) && !ArisSettingsIndex.showsNew(.skills, seen: ["skills"]) && !ArisSettingsIndex.showsNew(.aris, seen: []),
          "item 20: 새 stays on a new page until it has been opened once")
    // 19.
    check(ArisSkillsOff.shown(enabled: false, chatEmpty: true) && !ArisSkillsOff.shown(enabled: true, chatEmpty: true) && !ArisSkillsOff.shown(enabled: false, chatEmpty: false),
          "item 19: 스킬 is the one card with one button only while it is off and nothing was said")
}

private func s2DangerTests() {
    var s = ArisSettingsSnapshot()
    s.memoriesLoaded = true
    s.memories = []
    let clear = ArisMemorySettingsRows.sections(s).flatMap(\.rows).first { $0.id == "memory.clear" }
    check(clear?.title == "기억 모두 지우기" && clear?.control == .buttons([ArisSettingButton(title: "지우기", action: .forgetAllMemories, kind: .danger, enabled: false)]),
          "item 13: the row names what is erased, the red is on its button alone, and with nothing to erase the button stays in place, off")
    s.memories = [ArisMemoryItem(id: "m1", kind: "fact", subject: "", text: "x", source: "said", said: 0, used: nil)]
    s.confirmingMemoryClear = true
    let confirm = ArisMemorySettingsRows.sections(s).flatMap(\.rows).first { $0.id == "memory.clear" }
    check(confirm?.control == .buttons([ArisSettingButton(title: "취소", action: .keepMemories), ArisSettingButton(title: "정말 지우기", action: .forgetAllMemories, kind: .danger)]),
          "item 13: asked twice, in the same destructive style")
    let about = s2Rows(.about)
    let wipe = about.first { $0.id == "about.wipe" }, uninstall = about.first { $0.id == "about.uninstall" }
    check(wipe?.control == .buttons([ArisSettingButton(title: "지우기…", action: .wipe, kind: .danger)])
          && uninstall?.control == .buttons([ArisSettingButton(title: "제거…", action: .uninstall, kind: .danger)]) && uninstall?.title == "Aris 제거",
          "item 13: 정보's two rows that destroy carry their red on a button, not on the row's name")
    // The buttons that can't be pressed yet are still there (nothing hides, nothing jumps).
    let name = s2Rows(.general).first { $0.id == "general.name" }
    var hidden = ArisSettingsSnapshot()
    hidden.hiddenSides = false
    let unhide = s2Rows(.notch, hidden).first { $0.id == "notch.unhide" }
    if case .field(_, _, _, let button)? = name?.control, case .buttons(let buttons)? = unhide?.control {
        check(!button.enabled && button.title == "지우기" && buttons.count == 1 && !buttons[0].enabled,
              "item 13: 지우기 with no name and 다시 보이기 with nothing hidden stay in their place, switched off")
    } else {
        check(false, "item 13: 지우기 with no name and 다시 보이기 with nothing hidden stay in their place, switched off")
    }
}

private func s2DictationKeyTests() {
    typealias Key = ArisDictationKey.Choice
    check(Key.stored(nil) == .rightOption && Key.rightOption.keyCode == ArisDictationKey.keyCode && Key.rightOption.name(english: false) == "오른쪽 ⌥",
          "item 18: with nothing picked the dictation key is the right ⌥, as it always was")
    check(Key.stored(54).name(english: false) == "오른쪽 ⌘" && Key.stored(62).name(english: true) == "right ⌃" && Key.stored(63).name(english: false) == "fn",
          "item 18: another key can be kept: the right ⌘, the right ⌃ or fn")
    check(Key.stored(58) == .rightOption && Key.stored(56) == .rightOption && Key.stored(0) == .rightOption && Key.stored("x") == .rightOption,
          "item 18: a stored key that can't dictate (a left-hand one, ⇧, a letter, nonsense) falls back to the right ⌥")
    let talk: Set<Key.Kind> = [.option]
    check(Key.problem(keyCode: 61, talkModifiers: talk, talkCaps: ["⌥", "Space"]) == nil && Key.problem(keyCode: 54, talkModifiers: talk, talkCaps: ["⌥", "Space"]) == nil
          && Key.problem(keyCode: 63, talkModifiers: talk, talkCaps: ["⌥", "Space"]) == nil, "item 18: the right-hand keys and fn can be picked")
    check(Key.problem(keyCode: 58, talkModifiers: talk, talkCaps: ["⌥", "Space"])?.contains("말하기 단축키(⌥ Space)") == true,
          "item 18: a key the talk shortcut is pressed with is refused, and the reason names the talk key")
    check(Key.problem(keyCode: 55, talkModifiers: [.command], talkCaps: ["⌘", "J"])?.contains("말하기 단축키(⌘ J)") == true
          && Key.problem(keyCode: 55, talkModifiers: talk, talkCaps: ["⌥", "Space"])?.contains("왼쪽 ⌘") == true,
          "item 18: the left ⌘ is refused for the talk key when that uses it, else for every other shortcut")
    check(Key.problem(keyCode: 58, talkModifiers: [], talkCaps: [])?.contains("⌥⇧") == true, "item 18: the left ⌥ is refused for ⌥⇧, the key that points at the screen")
    check(Key.problem(keyCode: 56, talkModifiers: [], talkCaps: [])?.contains("⇧") == true && Key.problem(keyCode: 60, talkModifiers: [], talkCaps: []) != nil
          && Key.problem(keyCode: nil, talkModifiers: [], talkCaps: [])?.contains("fn") == true, "item 18: ⇧ and a key that isn't held by itself are refused, saying what can be picked")
    check(Set(Key.keys.map(\.keyCode)).count == Key.keys.count && Set(Key.keys.map(\.flag)).count == Key.keys.count, "item 18: every modifier key is told apart by its own code and bit")

    // Every line that named the right ⌥ names the key in use.
    let command = Key.stored(54), control = Key.stored(62), fn = Key.stored(63)
    check(Key.rightOption.naming("오른쪽 ⌥에서 손을 떼면 넣어요") == "오른쪽 ⌥에서 손을 떼면 넣어요", "item 18: with the right ⌥ every line is as it was")
    check(command.naming("오른쪽 ⌥에서 손을 떼면 넣어요 · 두 번 누르면 손 떼고 말해요") == "오른쪽 ⌘에서 손을 떼면 넣어요 · 두 번 누르면 손 떼고 말해요"
          && command.naming("Let go of right ⌥ to put it in") == "Let go of right ⌘ to put it in" && fn.naming("press right ⌥ once more") == "press fn once more",
          "item 18: the notch's dictation lines name the key that dictates now, in both languages")
    check(command.naming("오른쪽 ⌥를 누른 채 말하면 여기에 받아 적어요.") == "오른쪽 ⌘를 누른 채 말하면 여기에 받아 적어요."
          && control.naming("오른쪽 ⌥를 누른 채 말하기") == "오른쪽 ⌃을 누른 채 말하기" && fn.naming("오른쪽 ⌥를 누른 채 말하기") == "fn을 누른 채 말하기",
          "item 18: and the particle after it follows the key's name")
    check(command.naming("In any app, hold the right ⌥ and talk.") == "In any app, hold the right ⌘ and talk.", "item 18: the setup's dictation page names the real key")

    // The rows: the same recorder as every other key, on both pages.
    var s = ArisSettingsSnapshot()
    s.dictationCaps = ["오른쪽 ⌘"]
    let rows = [s2Rows(.dictation, s).first { $0.id == "dictation.key" }, s2Rows(.keys, s).first { $0.id == "keys.dictation" }]
    check(rows.allSatisfy { $0?.control == .shortcut(name: Key.recorderName, caps: ["오른쪽 ⌘"]) }, "item 18: the dictation key's rows record a new key like the others and show the one in use")
    check(!ArisSettingsPage.allCases.flatMap { s2Rows($0, s) }.contains { if case .caps = $0.control { true } else { false } }, "item 18: no key in Settings is fixed any more")
    check(s2Rows(.keys, s).first { $0.id == "keys.dictation" }?.desc == "누르고 있는 동안 받아 적어요.", "item 18: and no row says a key can't be changed")
}

private func s2StatusTests() {
    let down = ArisSettingsCaption.greeting(agentDown: true, missingPermissions: 2, noAI: true, english: false)
    check(ArisSettingsCaption.asksForHelper(down) && !ArisSettingsCaption.asksForPermissions(down) && !ArisSettingsCaption.asksForAI(down),
          "item 3: when the helper doesn't answer the status line says so, and pressing it restarts the helper (it did nothing)")
    check(!ArisSettingsCaption.asksForHelper(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0, english: false))
          && ArisSettingsCaption.asksForPermissions(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 2, english: false))
          && ArisSettingsCaption.asksForAI(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0, noAI: true, english: false)),
          "item 3: the other status lines open what they always opened, and the healthy one opens nothing")
}

func runSettings2Tests() {
    s2StatusTests()
    s2DictationKeyTests()
    s2DangerTests()
    s2FixesTests()
    s2MenuTests()
    s2FoldTests()
    s2SidebarTests()
    s2LayoutTests()
    s2StageTests()
    s2CopyTests()
}
