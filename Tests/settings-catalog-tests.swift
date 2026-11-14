// Tests for the settings window's pure parts: the search index, the Korean particles and captions, shortcut caps,
// the pages' rows, the tile layout and the notch preview's plan. Run by run.sh (and settings-catalog/run.sh alone).
import Foundation

func runSettingsCatalogTests() {
    indexTests()
    searchTests()
    wordTests()
    builderTests()
    layoutTests()
    faceStageWaveTests()
}

/// Everything turned on, every list filled: each conditional row on screen.
private func fullSnapshot() -> ArisSettingsSnapshot {
    var s = ArisSettingsSnapshot()
    s.hasVoiceKey = true
    s.voiceName = "Rachel"
    s.reminders = .granted
    s.reminderLists = [.init(id: "r1", name: "미리 알림", source: "iCloud", colorHex: "#FF9500", included: true)]
    s.defaultList = "r1"
    s.calendarAccess = .granted
    s.calendars = [.init(id: "c1", name: "집", source: "iCloud", colorHex: "#34C759", included: true)]
    s.googleCalendars = 1
    s.services = [.init(id: "claude", title: "Claude", detail: "Max", status: "연결됨", tone: .ok)]
    s.permissions = [.init(id: "ax", title: "손쉬운 사용", desc: "d", granted: true), .init(id: "screen", title: "화면 기록", desc: "d", granted: false),
                     .init(id: "mic", title: "마이크", desc: "d", granted: true)]
    s.standing = [.init(id: "p1", title: "메시지 보내기", desc: "대상: 엄마", symbol: "message")]
    s.standingLoaded = true
    s.memories = [ArisMemoryItem(id: "m1", kind: "preference", subject: "커피", text: "커피는 아이스 아메리카노", source: "said", said: 1_762_300_000, used: nil)]
    s.memoriesLoaded = true
    s.heightMode = "custom"
    s.displayMode = "preferred"
    s.screens = [.init(id: "u1", title: "내장 Retina 디스플레이")]
    s.customAccent = true
    s.more.flatHeightMode = "custom"
    s.more.peek = true
    return s
}

private func allRows(_ s: ArisSettingsSnapshot) -> [(page: ArisSettingsPage, row: ArisSettingItem)] {
    ArisSettingsPage.allCases.flatMap { page in ArisSettingsBuilder.sections(page, s).flatMap(\.rows).map { (page, $0) } }
}

private func indexTests() {
    let ids = ArisSettingsIndex.entries.map(\.id)
    check(Set(ids).count == ids.count, "settings index: every id once")
    check(ArisSettingsPage.allCases.allSatisfy { page in ArisSettingsIndex.entries.contains { $0.page == page } }, "settings index: every page has settings in it")
    check(ArisSettingsIndex.entries.allSatisfy { !$0.title.isEmpty && !$0.keywords.isEmpty }, "settings index: every entry has a title and Korean keywords")
    let rows = allRows(fullSnapshot())
    let missing = rows.filter { $0.row.indexed && ArisSettingsIndex.entry($0.row.id) == nil }.map(\.row.id)
    check(missing.isEmpty, "settings index: every setting a page draws is in the index (missing: \(missing))")
    let wrongPage = rows.filter { $0.row.indexed && ArisSettingsIndex.entry($0.row.id)?.page != $0.page }.map(\.row.id)
    check(wrongPage.isEmpty, "settings index: an entry names the page its row is on (\(wrongPage))")
    // The rest are anchors a page draws: a section (lists, calendars, services, standing permissions) or the 팀원 page's.
    let anchors = Set(rows.map(\.row.id)).union(ArisSettingsPage.allCases.flatMap { ArisSettingsBuilder.sections($0, fullSnapshot()).map(\.id) })
        .union(ArisSettingsIndex.teamAnchors).union(ArisSettingsIndex.skillsAnchors)
    let tags = ArisSettingsPage.allCases.reduce(into: Set(ArisSettingsIndex.teamAnchors + ArisSettingsIndex.skillsAnchors)) { $0.formUnion(ArisSettingsLayout.tags(ArisSettingsBuilder.sections($1, fullSnapshot()))) }
    let untagged = ids.filter { !tags.contains($0) }
    check(untagged.isEmpty, "settings index: every entry's id is a tag a page's view carries, so a search can scroll to it (\(untagged))")
    let orphans = ids.filter { !anchors.contains($0) }
    check(orphans.isEmpty, "settings index: every entry is something a page draws (orphans: \(orphans))")
    check(ArisSettingsGroup.allCases.flatMap(\.pages) == ArisSettingsPage.allCases, "pages: the groups hold every page once, in order")
    check(ArisSettingsPage.allCases.count == 14 && ArisSettingsGroup.aris.pages == [.aris, .ai, .voice, .memory, .team, .skills]
          && ArisSettingsGroup.tools.pages == [.dictation, .todo, .control] && ArisSettingsGroup.app.pages == [.notch, .features, .general, .keys, .about],
          "pages: 14 in three groups, 아리스 six, 도구 three, 화면 · 앱 five (pick 6-B)")
}

private func searchTests() {
    check(ArisSettingsIndex.search("").isEmpty && ArisSettingsIndex.search("  ").isEmpty, "search: nothing typed, nothing found")
    check(ArisSettingsIndex.search("말하기 속도").first?.id == "voice.speed", "search: a title finds its setting first")
    check(ArisSettingsIndex.search("말하기속도").first?.id == "voice.speed", "search: spaces don't matter")
    check(ArisSettingsIndex.search("아리스라고").first?.id == "aris.wake", "search: quotes don't matter")
    check(ArisSettingsIndex.search("다크 모드").first?.id == "look.theme", "search: a keyword finds the setting (다크 모드 → 설정 창 모양)")
    check(ArisSettingsIndex.search("답하는 ai").first?.id == "ai.brain", "search: 기본으로 답하는 AI is found in AI 서비스, where it moved")
    check(!ArisSettingsIndex.search("답하는").contains { $0.page == .aris }, "search: the 대화 page's link row isn't a second result")
    check(ArisSettingsIndex.search("GEMINI").first?.id == "ai.brain", "search: Latin letters ignore case")
    check(ArisSettingsIndex.search("ㅁㅎㄱㅅㄷ").first?.id == "voice.speed", "search: initial consonants (초성) find a title")
    let keys = ArisSettingsIndex.search("단축키")
    check(keys.first?.id == "aris.talkKey" && keys.contains { $0.id == "keys.talk" }, "search: a title match ranks above keyword matches")
    check(ArisSettingsIndex.search("권한").contains { $0.id == "control.mic" }, "search: 권한 finds the permissions")
    check(ArisSettingsIndex.search("캘린더").count > 3, "search: a page's name finds its settings")
    check(ArisSettingsIndex.search("없는설정").isEmpty, "search: nothing matching, nothing found")
    check(ArisSettingsIndex.search("키", limit: 3).count == 3, "search: results stop at the limit")
    check(ArisSettingsIndex.initials("말하기 속도") == "ㅁㅎㄱㅅㄷ" && ArisSettingsIndex.normalized("“A” b·c") == "abc", "search: initials and normalizing")
}

private func wordTests() {
    check(ArisParticle.attach("강조 색", .eulReul) == "강조 색을" && ArisParticle.attach("알림 효과음", .eulReul) == "알림 효과음을", "josa: 을 after a final consonant")
    check(ArisParticle.attach("진동", .eulReul) == "진동을" && ArisParticle.attach("제스처", .eulReul) == "제스처를", "josa: 를 after a vowel")
    check(ArisParticle.attach("“아리스”라고 부르기", .eulReul) == "“아리스”라고 부르기를", "josa: closing punctuation is skipped")
    check(ArisParticle.attach("Space", .eulReul) == "Space를" && ArisParticle.attach("⌘ M", .eulReul) == "⌘ M을", "josa: Latin letters (M 엠 closed)")
    check(ArisParticle.attach("3", .iGa) == "3이" && ArisParticle.attach("2", .iGa) == "2가", "josa: digits read in Korean")
    check(ArisParticle.attach("서울", .euroRo) == "서울로" && ArisParticle.attach("집", .euroRo) == "집으로" && ArisParticle.attach("지영", .euroRo) == "지영으로"
          && ArisParticle.attach("Rachel", .euroRo) == "Rachel로" && ArisParticle.attach("Aria", .euroRo) == "Aria로", "josa: 으로/로, ㄹ takes 로")
    check(ArisParticle.attach("Aris", .eunNeun) == "Aris는", "josa: 은/는")
    check(ArisSettingsCaption.changed("진동", on: false) == "진동을 껐어요" && ArisSettingsCaption.changed("제스처", on: true) == "제스처를 켰어요"
          && ArisSettingsCaption.changed("강조 색", on: nil) == "강조 색을 바꿨어요", "caption: what the preview says after a change")
    check(ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0) == "모두 잘 되고 있어요"
          && ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 2) == "권한 2개가 더 필요해요"
          && ArisSettingsCaption.greeting(agentDown: true, missingPermissions: 2) == "에이전트와 연결이 끊겼어요", "caption: the sidebar's greeting says what needs the user")
    check(ArisShortcutCaps.caps("⌃⌥Space") == ["⌃", "⌥", "Space"] && ArisShortcutCaps.caps("⇧⌘I") == ["⇧", "⌘", "I"], "caps: one per modifier, then the key")
    check(ArisShortcutCaps.problem(modifiers: ["⌥"], key: "Space", functionKey: false) == nil
          && ArisShortcutCaps.problem(modifiers: [], key: "F5", functionKey: true) == nil, "shortcut rule: ⌥ Space and F5 alone are fine")
    check(ArisShortcutCaps.problem(modifiers: [], key: "A", functionKey: false) != nil, "shortcut rule: a plain letter isn't a shortcut")
    check(ArisShortcutCaps.problem(modifiers: ["⇧"], key: "A", functionKey: false) != nil
          && ArisShortcutCaps.problem(modifiers: ["⇧", "⌥"], key: "A", functionKey: false) == nil, "shortcut rule: ⇧ alone isn't enough")
    for key in ["W", "Q", "C", "V", "X", "Z", "A", "H", "M", ","] {
        check(ArisShortcutCaps.problem(modifiers: ["⌘"], key: key, functionKey: false) != nil, "shortcut rule: ⌘\(key) is the system's")
    }
    check(ArisShortcutCaps.problem(modifiers: ["⇧", "⌘"], key: "Z", functionKey: false) != nil
          && ArisShortcutCaps.problem(modifiers: ["⌥", "⌘"], key: "C", functionKey: false) == nil, "shortcut rule: ⇧⌘Z is redo; ⌥⌘C is free")
    check(ArisKoreanText.keepAll("다른 AI가 답해요") == "다\u{2060}른 A\u{2060}I\u{2060}가 답\u{2060}해\u{2060}요"
          && ArisKoreanText.keepAll("") == "" && ArisKoreanText.keepAll("a\nb c") == "a\nb c", "keep-all: words never break inside, only at spaces")
    check(ArisShortcutCaps.caps("⌥ ") == ["⌥", "Space"] && ArisShortcutCaps.caps("F5") == ["F5"], "caps: a blank key is Space; no modifiers")
}

/// The rows that replaced the old 고급 설정 / 음악 / 선반 screens.
private func moreTests() {
    let fresh = ArisSettingsSnapshot()
    let notch = ArisSettingsBuilder.sections(.notch, fresh)
    check(notch.map(\.id) == ["notch.top", "notch.side", "notch.sideLeft", "notch.sideRight", "notch.advanced", "notch.gestureDetail", "notch.window"]
          && notch.suffix(3).map { $0.fold?.title ?? "" } == ["열기와 움직임", "제스처 세부", "창"],
          "more: 노치 has 열기와 움직임, 제스처 세부 and 창 after the side notch and its tabs, each folded to one line (pick 7-A)")
    check(!notch.flatMap(\.rows).contains { if case .buttons(let b) = $0.control { b.contains { $0.title == "열기 ›" } } else { false } }
          && !ArisSettingsBuilder.sections(.todo, fresh).flatMap(\.rows).contains { $0.id == "calendar.widgetDetail" },
          "more: no row opens an old screen any more")
    let features = ArisSettingsBuilder.sections(.features, fresh)
    check(features.map(\.id) == ["features.music", "features.shelf", "features.more"], "more: 음악 · 선반 is 음악, 선반, then the link to the calendar's settings")
    let rows = (notch + features).flatMap(\.rows)
    let row = { (id: String) in rows.first { $0.id == id } }
    check(row("notch.hoverDelay")?.control == .slider(.more(.hoverDelay), value: 0.3, min: 0, max: 1, unit: "초", step: 0.1, zero: "바로")
          && row("notch.hoverDelay")?.desc == "노치 위에 이만큼 머물면 열려요.", "more: the hover delay starts at 0.3 s, written beside its slider (settings item 10)")
    check(row("features.musicSource")?.control == .choice(.more(.musicSource), [.init(id: "nowPlaying", title: "지금 재생 중"),
          .init(id: "appleMusic", title: "Apple Music"), .init(id: "spotify", title: "Spotify")], selected: "nowPlaying"),
          "more: the music source is a three-way choice, Now Playing first")
    check(row("features.shelfOn")?.control == .toggle(.more(.shelf), true) && row("features.wideDrop")?.control == .toggle(.more(.wideDrop), true)
          && row("features.copyOnDrag")?.control == .toggle(.more(.copyOnDrag), false), "more: the shelf toggles start as a fresh install's")
    check(row("notch.flatCustomHeight") == nil && row("features.peekStyle") == nil, "more: the custom height and the peek style only when they apply")
    check(row("notch.lockScreen")?.control == .toggle(.more(.lockScreen), false) && row("notch.hideFromMissionControl")?.control == .toggle(.more(.hideFromMissionControl), true),
          "more: the window switches start as a fresh install's")

    var broken = fresh
    broken.more.nowPlayingWorks = false
    if case .choice(_, _, _, let disabled, let lead) = ArisSettingsBuilder.sections(.features, broken).flatMap(\.rows).first(where: { $0.id == "features.musicSource" })?.control {
        check(disabled == ["nowPlaying"] && lead?.action == .recheckNowPlaying, "more: Now Playing can't be picked when it doesn't answer, and 다시 확인 asks again")
    } else { check(false, "more: the music source is a choice") }
    var noGestures = fresh
    noGestures.gestures = false
    check(!ArisSettingsBuilder.sections(.notch, noGestures).contains { $0.id == "notch.gestureDetail" }, "more: the gesture details only while gestures are on")
    var still = fresh
    still.more.animation = false
    check(!ArisSettingsBuilder.sections(.notch, still).flatMap(\.rows).contains { $0.id == "notch.animationSpeed" }, "more: no speed without the animation")

    check(ArisMoreRounding.flatHeight(0) == 0 && ArisMoreRounding.flatHeight(5) == 0 && ArisMoreRounding.flatHeight(9) == 15
          && ArisMoreRounding.flatHeight(20.4) == 20 && ArisMoreRounding.flatHeight(26) == 26 && ArisMoreRounding.flatHeight(40) == 40
          && ArisMoreRounding.flatHeight(52) == 40, "more: a flat display's height is 0 or 15–40")
    check(ArisMoreRounding.hoverDelay(0.34) == 0.3 && ArisMoreRounding.hoverDelay(1.7) == 1 && ArisMoreRounding.animationSpeed(0) == 0.1
          && ArisMoreRounding.animationSpeed(1.26) == 1.3 && ArisMoreRounding.idleWait(3.6) == 4 && ArisMoreRounding.idleWait(12) == 10,
          "more: the sliders round to their steps and stay in range")
    check(ArisSettingsIndex.search("고급 설정").first?.id == "notch.advanced" && ArisSettingsIndex.search("에어드롭").contains { $0.id == "features.quickShare" }
          && ArisSettingsIndex.search("스포티파이").first?.id == "features.musicSource", "more: search finds the moved settings")
    if case .slider(_, _, let lower, let upper, _, let step, _) = row("notch.animationSpeed")?.control {
        check(step == 0.1 && lower == 0.1 && upper == 2, "more: 애니메이션 속도 moves in tenths from 0.1 to 2")
    } else { check(false, "more: 애니메이션 속도 is a slider") }
    var custom = fresh
    custom.more.flatHeightMode = "custom"
    if case .slider(_, _, let lower, let upper, _, let step, _) = ArisSettingsBuilder.sections(.notch, custom).flatMap(\.rows).first(where: { $0.id == "notch.flatCustomHeight" })?.control {
        check(lower == 0 && upper == 40 && step == 1, "more: a flat display's custom height slides 0–40 in whole points")
    } else { check(false, "more: the flat display's custom height is a slider") }

    // The slider's own rounding (ArisRangeSlider calls these).
    check(ArisSliderStep.value(at: 0.34, in: 0...1, step: 0.1) == 0.3 && ArisSliderStep.value(at: 1.2, in: 0...1, step: 0.1) == 1
          && ArisSliderStep.value(at: -0.5, in: 0...1, step: 0.1) == 0, "slider: tenths across 0–1 s, clamped to the track")
    check(ArisSliderStep.value(at: 0.47, in: 0.1...2, step: 0.1) == 1 && ArisSliderStep.value(at: 0, in: 0.1...2, step: 0.1) == 0.1,
          "slider: tenths from 0.1 for the animation speed")
    check(ArisSliderStep.value(at: 0.5, in: 15...45, step: 1) == 30 && ArisSliderStep.value(at: 0.51, in: 15...45, step: 1) == 30,
          "slider: whole points when the step is 1")
    check(ArisSliderStep.nudge(0.3, up: true, in: 0...1, step: 0.1) == 0.4 && ArisSliderStep.nudge(0.1, up: false, in: 0.1...2, step: 0.1) == 0.1
          && ArisSliderStep.nudge(40, up: true, in: 0...40, step: 1) == 40, "slider: VoiceOver moves one step and stops at the ends")
    check(ArisSliderStep.spoken(0.3, step: 0.1) == "0.3" && ArisSliderStep.spoken(32, step: 1) == "32", "slider: VoiceOver reads tenths as tenths")

    // Search offers only what a page draws now.
    var hidden = fresh
    hidden.more.animation = false
    hidden.displayMode = "active"
    check(!ArisSettingsIndex.search("애니메이션 속도", among: ArisSettingsBuilder.searchable(hidden)).contains { $0.id == "notch.animationSpeed" }
          && ArisSettingsIndex.search("애니메이션 속도", among: ArisSettingsBuilder.searchable(fresh)).first?.id == "notch.animationSpeed",
          "search: 애니메이션 속도 only while the animation is on")
    check(!ArisSettingsIndex.search("선호하는 화면", among: ArisSettingsBuilder.searchable(hidden)).contains { $0.id == "general.screen" }
          && !ArisSettingsIndex.search("직접 정한 높이", among: ArisSettingsBuilder.searchable(fresh)).contains { $0.id == "notch.customHeight" }
          && !ArisSettingsIndex.search("보여 주는 곳", among: ArisSettingsBuilder.searchable(fresh)).contains { $0.id == "features.peekStyle" },
          "search: rows another setting hides aren't offered")
    check(ArisSettingsBuilder.searchable(fullSnapshot()).isSuperset(of: Set(ArisSettingsIndex.entries.map(\.id))),
          "search: with everything on, every entry can be offered")
    var all = fullSnapshot()
    all.more.animation = true
    let moved = ArisMoreRows.notch(all.more, gestures: true) + [ArisMoreRows.music(all.more), ArisMoreRows.shelf(all.more)]
    let movedIDs = ArisSettingsLayout.tags(moved)
    let pageTags = ArisSettingsLayout.tags(ArisSettingsBuilder.sections(.notch, all) + ArisSettingsBuilder.sections(.features, all))
    check(movedIDs.allSatisfy { ArisSettingsIndex.entry($0) != nil } && movedIDs.isSubset(of: pageTags) && movedIDs.count == 35,
          "more: every moved row and section is in the search index and is a tag its page carries (\(movedIDs.count))")
}

private func builderTests() {
    let s = fullSnapshot()
    let ai = ArisSettingsBuilder.sections(.ai, s)
    check(ai.first?.heading == "생각" && ai.first?.rows.first?.id == "ai.brain" && ai.first?.rows.first?.control == .custom("ai.think"),
          "builder: AI 서비스 opens with 생각 › who answers, drawn by the page itself (ArisAIServicesPage)")
    check(ai.flatMap(\.rows).filter(\.indexed).map(\.id) == ["ai.brain", "ai.jev", "ai.hear", "ai.speak", "ai.mcp.composio", "ai.mcp.add", "ai.computerEngine", "ai.teamBrain"],
          "builder: AI 서비스 lists 생각, Jev, 듣기 and 말하기 for the search, then the connected services and the two rows it had")
    if case .menu(.computerEngine, let engines, let chosen) = ai.flatMap(\.rows).first(where: { $0.id == "ai.computerEngine" })?.control {
        check(engines.map(\.id) == ["peekaboo", "codex"] && chosen == "peekaboo", "builder: the computer-use engine is a plain menu, Peekaboo by default")
    } else { check(false, "builder: the computer-use engine has its row") }
    let link = ArisSettingsBuilder.sections(.aris, s).flatMap(\.rows).first { $0.id == "aris.brainLink" }
    check(link?.control == .link(.go(.ai, anchor: "ai.brain"), value: "Codex") && link?.indexed == false, "builder: 대화 keeps a row that goes to the brain, showing it")
    check(!ArisSettingsBuilder.sections(.aris, s).flatMap(\.rows).contains { if case .choice(.brain, _, _, _, _) = $0.control { true } else { false } },
          "builder: the brain is chosen in one place only")
    var fresh = ArisSettingsSnapshot()
    fresh.reminders = .undecided
    check(!ArisSettingsBuilder.sections(.todo, fresh).contains { $0.id == "todo.lists" }, "builder: no lists until Reminders is allowed")
    check(ArisSettingsBuilder.sections(.notch, fresh).flatMap(\.rows).allSatisfy { $0.id != "notch.customHeight" }
          && ArisSettingsBuilder.sections(.notch, s).flatMap(\.rows).contains { $0.id == "notch.customHeight" }, "builder: the height slider only for 직접")
    fresh.hover = false
    let gestures = ArisSettingsBuilder.sections(.notch, fresh).flatMap(\.rows).first { $0.id == "notch.gestures" }
    check(gestures?.control == .toggle(.gestures, true, enabled: false), "builder: gestures stay on (and can't be turned off) without hover")
    var pointer = ArisSettingsSnapshot()
    pointer.displayMode = "active"
    check(ArisSettingsBuilder.sections(.general, pointer).flatMap(\.rows).allSatisfy { $0.id != "general.screen" }
          && ArisSettingsBuilder.sections(.general, ArisSettingsSnapshot()).flatMap(\.rows).contains { $0.id == "general.screen" }, "builder: 선호하는 화면 only when it applies")
    var one = ArisSettingsSnapshot()
    one.languages = [.init(id: "ko", title: "한국어")]
    check(ArisSettingsBuilder.sections(.voice, one).flatMap(\.rows).first?.control == .buttons([ArisSettingButton(title: "한국어", action: .addLanguage, kind: .select)]),
          "builder: one language: the select names it alone (the sheet keeps the last one on)")
    check(ArisSettingsBuilder.sections(.team, s).isEmpty, "builder: 팀원 draws itself")
    let total = allRows(s).count
    check(total >= 70, "builder: every page's rows are there (\(total))")
    check(ArisSettingsBuilder.sections(.control, ArisSettingsSnapshot()).last?.rows.first?.title == "불러오는 중", "builder: standing permissions loading")
    moreTests()
    let sees = ArisSettingsBuilder.sections(.control, s).flatMap(\.rows).first { $0.id == "control.sees" }
    let circle = ArisSettingsBuilder.sections(.control, s).flatMap(\.rows).first { $0.id == "control.circle" }
    check(sees?.desc == "화면을 가리켜 물을 때만 화면을 찍어 보내요." && circle?.desc == "\(s.circleHint).", "builder: 화면 같이 보기 is one sentence, and the circle row carries the hint (pick 5-B)")
    check(ArisSettingsBuilder.accents.contains("#FF453A") && ArisSettingsBuilder.accents.contains("#66D22D") && ArisSettingsBuilder.accents.count == 8,
          "builder: the old preset accents, so a saved one still shows its ring")
    let fresh0 = ArisSettingsSnapshot()
    check(fresh0.brain == "codex" && fresh0.displayMode == "fallback" && fresh0.alwaysTabs && fresh0.settingsIcon
          && fresh0.wakeWord && fresh0.hover && fresh0.joinMeeting && fresh0.allDay && fresh0.notchHeight == 32, "snapshot: a fresh one matches the app's Defaults")
}

private func layoutTests() {
    let tile = { (id: String) in ArisSettingItem(id: id, icon: .symbol("x"), title: id, control: .toggle(.sounds, true)) }
    let card = ArisSettingItem(id: "c", icon: .symbol("x"), title: "c", control: .buttons([]))
    let dotted = ArisSettingItem(id: "d", icon: .dot("#fff"), title: "d", control: .toggle(.sounds, true))
    let blocks = ArisSettingsLayout.blocks(ArisSettingSection(id: "s", rows: [tile("a"), tile("b"), card, tile("e"), dotted]))
    // Settings 1:1 (2026-11-13): each row is its own card, as measured; a list (grouped) stays one card.
    check(blocks == [.group([tile("a")]), .group([tile("b")]), .group([card]), .group([tile("e")]), .group([dotted])], "layout: each row of a section is its own card, whatever its control")
    check(ArisSettingsLayout.blocks(ArisSettingSection(id: "g", grouped: true, rows: [tile("a"), card])) == [.group([tile("a"), card])], "layout: a section written as grouped is the same one card")
    check(ArisSettingsLayout.blocks(ArisSettingSection(id: "e", grouped: true, rows: [])).isEmpty, "layout: an empty section draws nothing")
    let tagged = ArisSettingsLayout.tags([ArisSettingSection(id: "s", heading: "h", rows: [tile("a"), card]), ArisSettingSection(id: "g", grouped: true, rows: [dotted])])
    check(tagged == ["s", "a", "c", "g", "d"], "layout: the tags are every section and every row")
}

private func faceStageWaveTests() {
    // The notch preview is gone from the settings window (the owner, 2026-11-12); the 팀원 strip's listening bars remain.
    let a = ArisFaceStageWave.heights(tick: 3), b = ArisFaceStageWave.heights(tick: 3)
    check(a == b && a.count == 4, "wave: four bars, the same for the same tick")
    let all = (0..<200).flatMap { ArisFaceStageWave.heights(tick: $0) }
    check(all.allSatisfy { (2...17).contains($0) }, "wave: bars 2–17 tall")
    check(Set(all).count > 20 && ArisFaceStageWave.tick == 0.058, "wave: the bars move, a step every 58 ms")
}
