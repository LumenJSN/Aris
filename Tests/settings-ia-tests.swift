// Settings reorganised as option A (settings-ia, the owner's pick): four pages of parts, the sidebar that lists the open
// page's parts and fits the window, the old page names and rows landing where their rows went, search by old and new
// names in Korean and English, the cleanups (dead rows, duplicates, status rows), and a snapshot of old defaults whose
// effective values stay the same. Plain values only: nothing is drawn, nothing of Aris's is read.
import Foundation

private func iaSnapshot() -> ArisSettingsSnapshot {
    var s = ArisSettingsSnapshot()
    s.hasVoiceKey = true
    s.savedSteps = []
    s.reminders = .granted
    s.reminderLists = [.init(id: "r1", name: "미리 알림", source: "iCloud", colorHex: "#FF9500", included: true)]
    s.calendarAccess = .granted
    s.calendars = [.init(id: "c1", name: "집", source: "iCloud", colorHex: "#34C759", included: true)]
    s.googleCalendars = 1
    s.services = [.init(id: "claude", title: "Claude", detail: "Max", status: "연결됨", tone: .ok)]
    s.permissions = [.init(id: "ax", title: "손쉬운 사용", desc: "d", granted: true), .init(id: "screen", title: "화면 기록", desc: "d", granted: false),
                     .init(id: "mic", title: "마이크", desc: "d", granted: true), .init(id: "speech", title: "음성 인식", desc: "d", granted: true),
                     .init(id: "input", title: "입력 모니터링", desc: "d", granted: false)]
    s.memories = [ArisMemoryItem(id: "m1", kind: "preference", subject: "커피", text: "커피는 아이스 아메리카노", source: "said", said: 1_762_300_000, used: nil)]
    s.standing = [.init(id: "p1", title: "메시지 보내기", desc: "대상: 엄마", symbol: "message")]
    s.standingLoaded = true
    s.memoriesLoaded = true
    s.heightMode = "custom"
    s.displayMode = "preferred"
    s.more.flatHeightMode = "custom"
    s.more.peek = true
    s.updates = true
    s.duplexAudio = true
    s.listenEngine = "SpeechAnalyzer"
    s.savedKeys = 1
    return s
}

private func rows(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> [ArisSettingItem] {
    ArisSettingsBuilder.sections(page, s).flatMap(\.rows)
}

func runSettingsIATests() {
    iaPagesTests()
    iaFormerTests()
    iaSidebarTests()
    iaSearchTests()
    iaCleanupTests()
    iaMigrationTests()
}

// MARK: - The four pages

private func iaPagesTests() {
    check(ArisSettingsPage.allCases.map(\.title) == ["Aris와 말하기", "할 수 있는 일", "모양", "앱"], "ia: four pages by what the user is doing, in option A's order")
    check(ArisSettingsPage.allCases.map { $0.parts.map(\.title) } == [
        ["AI · 모델", "부르기", "듣기", "목소리", "대화", "조용히 · 알림"],
        ["컴퓨터 제어", "받아쓰기", "할 일", "캘린더", "기억", "팀원", "스킬", "연결"],
        ["노치", "사이드 노치", "음악", "선반", "창 · 테마"],
        ["권한", "단축키", "시작 · 언어 · 화면", "업데이트", "데이터 · 개인정보"],
    ], "ia: each page's parts in the mockup's order, the sidebar's links")
    check(ArisSettingsParts.all.first?.id == "talk.ai" && ArisSettingsParts.all.first?.subtitle != nil, "ia: AI · 모델 is the first part of the first page, with the mockup's small line")
    let ids = ArisSettingsParts.all.flatMap(\.rows)
    check(Set(ids).count == ids.count, "ia: no row is listed in two parts")
    let entries = Set(ArisSettingsIndex.entries.map(\.id))
    let unlisted = ids.filter { !entries.contains($0) && !ArisSettingsParts.slots.contains($0) }
    check(unlisted.isEmpty, "ia: every row a part lists is a search entry, or a slot kept for another branch (\(unlisted))")
    let homeless = ArisSettingsIndex.entries.filter { ArisSettingsParts.holding($0.id) == nil }.map(\.id)
    check(homeless.isEmpty, "ia: option A's mapping gives every search entry its part (\(homeless))")
    // Every entry is drawn somewhere for a full snapshot (or by the team sheet / the AI view), so a search lands.
    let drawn = ArisSettingsBuilder.searchable(iaSnapshot())
    let lost = ArisSettingsIndex.entries.map(\.id).filter { !drawn.contains($0) }
    check(lost.isEmpty, "ia: every search entry is drawn by its page for a full snapshot (\(lost))")
    for page in ArisSettingsPage.allCases {
        let parts = ArisSettingsBuilder.parts(page, iaSnapshot())
        check(parts.map(\.id) == page.parts.map(\.id), "ia: \(page.rawValue) draws its parts in order")
        check(parts.allSatisfy { $0.sections.first?.heading == nil }, "ia: \(page.rawValue): a part's title stands for its first section's")
        let built = ArisSettingsLayout.tags(parts.flatMap(\.sections))
        check(Set(page.parts.map(\.id)).isDisjoint(with: built), "ia: \(page.rawValue): a part's tag is its own (no section shares it)")
    }
    // The folds option A keeps: 호출어 녹음, 연결된 서비스, 열기와 움직임, 제스처 세부, 창.
    let folded = ArisSettingsPage.allCases.flatMap { ArisSettingsBuilder.sections($0, iaSnapshot()) }.filter { $0.fold != nil }.map(\.id)
    check(Set(folded) == ["aris.record", "ai.services", "notch.advanced", "notch.gestureDetail", "notch.window"] || Set(folded) == ["aris.record", "ai.services", "notch.advanced", "notch.window"],
          "ia: the sections the mockup folds start as one line (\(folded))")
    check(ArisSettingsLayout.openFolds(stored: nil).isEmpty, "ia: folds start folded")
    check(ArisSettingsLayout.openFolds(stored: ArisSettingsLayout.stored(openFolds: ["ai.services", "aris.record"])) == ["ai.services", "aris.record"],
          "ia: an opened fold is remembered as it is stored and read back")
}

// MARK: - Old names land where their rows went

private func iaFormerTests() {
    let expected: [String: ArisSettingsPage] = ["aris": .talk, "ai": .talk, "voice": .talk, "memory": .able, "team": .able, "skills": .able, "dictation": .able,
                                                "todo": .able, "control": .able, "notch": .look, "features": .look, "general": .app, "keys": .app, "about": .app,
                                                "calendar": .able, "look": .look, "talk": .talk, "able": .able, "app": .app]
    for (raw, page) in expected { check(ArisSettingsPage.named(raw) == page, "ia: the stored or spoken page name \(raw) opens \(page.rawValue)") }
    check(ArisSettingsPage.named("nonsense") == nil, "ia: an unknown name opens nothing")
    for former in ArisSettingsFormerPage.allCases {
        check(ArisSettingsParts.part(former.part)?.page == former.page, "ia: \(former.title) lands on a part of its new page")
    }
    // The fix cards' rows (ArisFix.Row) still land on their row's page.
    for row in ArisFix.Row.allCases {
        let page = ArisSettingsPage.named(row.page)
        let landing = ArisSettingsParts.landing(row.anchor)
        let holder = ArisSettingsParts.part(landing)?.page ?? ArisSettingsIndex.entry(landing)?.page ?? ArisSettingsParts.holding(landing)?.page
        check(page != nil && holder != nil, "ia: the fix row \(row.rawValue) still names a page and a row (\(row.anchor))")
    }
    // A moved or merged row's old id lands on the row doing its job now, which is drawn.
    let drawn = ArisSettingsBuilder.searchable(iaSnapshot())
    for (old, new) in ArisSettingsParts.moved {
        check(drawn.contains(new), "ia: \(old) lands on \(new), which is drawn")
        check(!drawn.contains(old) || old == new, "ia: \(old) is no longer drawn twice")
    }
    check(ArisSettingsCaption.talkKey.page == .app && ArisSettingsParts.holding(ArisSettingsCaption.talkKey.anchor)?.id == "app.keys", "ia: the guide's talk key link opens 앱 › 단축키")
    check(ArisSettingsParts.holding(ArisSettingsCaption.brainAnchor)?.id == "talk.ai", "ia: the status line's AI link opens AI · 모델")
    check(ArisSettingsBuilder.sections(.app, iaSnapshot()).contains { $0.id == ArisSettingsCaption.permissionsAnchor }, "ia: the status line's permissions link lands in 앱 › 권한")
    // Replies that name an old page read as the page that has its rows.
    check(ArisSettingsPath.shown("설정 › AI 서비스에서 바꿔요", english: false) == "설정 › Aris와 말하기 › AI · 모델에서 바꿔요", "ia: a reply's 설정 › AI 서비스 reads as the page and part that took its rows")
    check(ArisSettingsPath.shown("설정 › 컴퓨터 제어", english: false) == "설정 › 할 수 있는 일 › 컴퓨터 제어", "ia: 컴퓨터 제어 reads as 할 수 있는 일 › 컴퓨터 제어")
    check(ArisSettingsPath.shown("설정 › 모양", english: false) == "설정 › 모양", "ia: a page's own name stays as it is")
    // Where the window opens.
    let now = Date()
    check(!ArisSettingsOpening.keepsLink(linkedAt: nil, now: now), "ia: opened without a link, the window is on AI · 모델")
    check(ArisSettingsOpening.keepsLink(linkedAt: now.addingTimeInterval(-0.5), now: now), "ia: a link just before keeps its page")
    check(!ArisSettingsOpening.keepsLink(linkedAt: now.addingTimeInterval(-30), now: now), "ia: an old click does not decide where the window opens")
}

// MARK: - The sidebar

private func iaSidebarTests() {
    let tallest = ArisSidebarMetrics.tallest
    check(tallest <= ArisSidebarMetrics.windowMinimum.height, "ia sidebar: with the page of the most parts open it is \(tallest) pt, inside the smallest window (\(ArisSidebarMetrics.windowMinimum.height)); it was 883 in 710")
    let pagesPart: Double = 4 * 44 + 3 * 4
    let partsPart: Double = 4 + 2 + 8 * 30 + 7 * 2 + 6
    check(ArisSidebarMetrics.pagesHeight(open: .able) == pagesPart + partsPart, "ia sidebar: four 44-pt pages 4 apart, and the open page's eight 30-pt parts 2 apart")
    check(ArisSidebarMetrics.partLeading == ArisSidebarMetrics.rowLeading + ArisSidebarMetrics.iconSize + ArisSidebarMetrics.iconGap,
          "ia sidebar: a part's name starts where the pages' names do")
    let talk = ArisSidebarMetrics.rowSpan(.talk, open: .talk), able = ArisSidebarMetrics.rowSpan(.able, open: .talk)
    check(talk?.top == 0 && able?.top == 44 + ArisSidebarMetrics.partsHeight(.talk) + 4, "ia sidebar: the next page's row sits under the open page's parts")
    check(!ArisSidebarMetrics.fades(listHeight: ArisSidebarMetrics.pagesHeight(open: .able), boxHeight: ArisSidebarMetrics.windowMinimum.height - (tallest - ArisSidebarMetrics.pagesHeight(open: .able)),
                                    listTop: 0, chosen: nil), "ia sidebar: nothing fades: the list ends inside the box")
    let order = ["a", "b", "c"]
    check(ArisSettingsSpy.current(order: order, tops: [:]) == "a", "ia spy: before any part is measured, the first is marked")
    check(ArisSettingsSpy.current(order: order, tops: ["a": -400, "b": 60, "c": 500]) == "b", "ia spy: the last part whose top passed the line is marked")
    check(ArisSettingsSpy.current(order: order, tops: ["a": 10, "b": 300, "c": 600]) == "a", "ia spy: at the top the first part is marked")
    check(ArisSettingsSpy.current(order: order, tops: ["a": -900, "b": -300, "c": 400], atEnd: true) == "c", "ia spy: scrolled to the end, the last part is marked even if its top can't reach the line")
}

// MARK: - Search

private func iaSearchTests() {
    func finds(_ query: String, _ id: String, alias: ((ArisSettingsEntry) -> ArisSettingsIndex.Alias)? = nil) -> Bool {
        ArisSettingsIndex.matches(query, limit: 40, alias: alias).contains { $0.entry.id == id }
    }
    let korean: [(String, String)] = [("말하기 단축키", "keys.talk"), ("누르고 있는 동안 받아쓰기", "keys.dictation"), ("클립보드 기록", "keys.clipboard"),
                                      ("왼쪽 사이드 노치 열기", "keys.clipboard"), ("오른쪽 사이드 노치 열기", "keys.right"), ("기록 폴더 열기", "about.folder"),
                                      ("데이터가 있는 곳", "about.folder"), ("ElevenLabs Scribe로 듣기", "ai.hear"), ("듣기 엔진", "ai.hear"), ("생각", "ai.brain"),
                                      ("기본으로 답하는 AI", "ai.brain"), ("답하는 AI", "ai.brain"), ("팀원의 두뇌", "team.detail"), ("다른 앱 소리 확인", "aris.systemAudio"),
                                      ("에코 제거", "aris.duplex"), ("끼어들기", "aris.bargeIn"), ("AI 서비스", "ai.brain"), ("목소리 · 언어", "voice.speed"),
                                      ("정보", "about.wipe"), ("일반", "general.login"), ("저장된 키", "ai.savedKeys")]
    for (query, id) in korean { check(finds(query, id), "ia search: \(query) finds \(id)") }
    // English: the catalog's English for each row's name, former names and old page.
    if let data = FileManager.default.contents(atPath: settingsCatalogPath()) {
        ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: data))
        let w = ArisSettingsWording(pageEnglish: true, frameEnglish: true)
        let alias: (ArisSettingsEntry) -> ArisSettingsIndex.Alias = { ArisSettingsIndex.english($0, w) }
        var missing: [String] = []
        for entry in ArisSettingsIndex.entries {
            for name in [entry.title] + entry.formerly {
                guard let english = ArisSettingsCopy.english(name), english != name else { continue }
                if !finds(english, entry.id, alias: alias) { missing.append("\(entry.id) by \(english)") }
            }
        }
        check(missing.isEmpty, "ia search: every row is found by its English name and its English former names (\(missing.prefix(6)))")
        check(finds("AI services", "ai.brain", alias: alias) || ArisSettingsCopy.english("AI 서비스") == nil, "ia search: the old page's English name still finds its rows")
        ArisSettingsCopy.install([:])
    } else {
        check(false, "ia search: the settings catalog is readable for the English check")
    }
}

private func settingsCatalogPath() -> String {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/components/Settings/Settings.xcstrings").standardized.path
}

// MARK: - Cleanups

private func iaCleanupTests() {
    let s = iaSnapshot()
    let all = ArisSettingsPage.allCases.flatMap { rows($0, s) }
    // Dead rows: 노치에 설정 아이콘 is out until the notch draws it; 기록 폴더 열기 says where the data is.
    check(!all.contains { $0.id == "look.settingsIcon" } || ArisSettingsSlots.settingsIconWired, "ia: 노치에 설정 아이콘, which saved a key nothing read, is not shown")
    check(all.first { $0.id == "about.folder" }?.title == "데이터가 있는 곳" && (all.first { $0.id == "about.folder" }?.desc ?? "").contains("~/.config/aris"),
          "ia: the data folder row says where the data really is")
    // Duplicates: one row per shortcut, one name each; one voice picker; one Scribe control.
    let caps = all.compactMap { row -> String? in if case .shortcut(let name, _, _) = row.control { name } else { nil } }
    check(Set(caps).count == caps.count, "ia: each shortcut has one row (\(caps))")
    check(Set(caps) == ["talkToAris", ArisDictationKey.Choice.recorderName, "pasteLastDictation", "answerClaude", "openClipboard", "openRightPanel", "toggleNotchOpen", "toggleSneakPeek"],
          "ia: 단축키 has all eight, 오른쪽 사이드 노치 열기 too")
    check(rows(.app, s).first { $0.id == "keys.clipboard" }?.title == "클립보드 열기 (왼쪽 사이드 노치)", "ia: openClipboard is one row with one name")
    check(!all.contains { $0.id == "voice.voice" || $0.id == "voice.scribe" }, "ia: no second voice picker and no second Scribe switch")
    check(!all.contains { if case .toggle(let key, _, _) = $0.control { "\(key)" == "cloud" } else { false } }, "ia: nothing writes arisCloudListening from the window")
    // Rows that showed something but offered nothing: plain status now.
    check(!all.contains { $0.id == "voice.engine" } && ArisSettingsBuilder.engineLine(s) == "듣기 엔진 · SpeechAnalyzer", "ia: 듣기 엔진 is a status line under 듣기, not a row")
    var proven = s
    proven.systemAudioProven = true
    let audio = rows(.app, proven).first { $0.id == "aris.systemAudio" }
    check(audio?.control == .said("허용됨"), "ia: system audio, once allowed, says so in words like the other permissions")
    var missing = s
    missing.systemAudioMissing = true
    check(rows(.app, missing).first { $0.id == "aris.systemAudio" }.map { if case .buttons = $0.control { true } else { false } } == true, "ia: system audio missing has its button")
    // Permissions in one list.
    let permissions = ArisSettingsBuilder.sections(.app, s).first { $0.id == "control.permissions" }?.rows.map(\.id) ?? []
    check(["control.ax", "control.screen", "aris.systemAudio", "todo.access", "calendar.access"].allSatisfy(permissions.contains), "ia: every permission is in 앱 › 권한 (\(permissions))")
    var noReminders = s
    noReminders.reminders = .undecided
    check(rows(.able, noReminders).contains { $0.id == "todo.accessHere" && !$0.indexed } && !rows(.able, s).contains { $0.id == "todo.accessHere" },
          "ia: 할 일 echoes the missing Reminders permission, and only while it is missing")
    // Hidden settings with a home: the echo-cancelled engine (experimental, off by default) and barge-in under it.
    var off = s
    off.duplexAudio = false
    check(ArisSettingsSnapshot().duplexAudio == false, "ia: the echo-cancelled engine is off by default")
    let duplex = rows(.talk, s).first { $0.id == "aris.duplex" }
    check(duplex?.title == "에코 제거 오디오 (새 엔진)" && (duplex?.desc ?? "").contains("실험"), "ia: the duplex row says it is experimental")
    check(rows(.talk, s).contains { $0.id == "aris.bargeIn" } && !rows(.talk, off).contains { $0.id == "aris.bargeIn" },
          "ia: 스피커로 들을 때도 끼어들기 comes back only with the echo-cancelled engine")
    // Team and skills open as sheets from their part.
    let able = rows(.able, s)
    check(able.first { $0.id == "team.add" }?.control == .buttons([ArisSettingButton(title: "추가", action: .openSheet("team", anchor: "team.add"))]), "ia: 팀원 추가 opens the team sheet")
    check(able.first { $0.id == "skills.list" }.map { if case .link(.openSheet("skills", _), _) = $0.control { true } else { false } } == true, "ia: 내 스킬 opens the skills sheet")
    check(ArisSettingsParts.sheetAnchors["team.look"] == "team", "ia: a search for the team's own parts opens the team sheet")
    // Moved rows on their new pages.
    check(rows(.look, s).contains { $0.id == "aris.claudeRing" } && rows(.look, s).contains { $0.id == "features.fullScreen" }, "ia: the notch ring and the full-screen rule are in 모양 › 노치")
    check(rows(.app, s).contains { $0.id == "notch.hideFromRecording" } && !rows(.look, s).contains { $0.id == "notch.hideFromRecording" }, "ia: 화면 기록에서 숨기기 is in 데이터 · 개인정보")
    check(rows(.talk, s).contains { $0.id == "aris.claudeBudget" }, "ia: Claude Code's budget is in AI · 모델's 연결된 서비스")
    check(rows(.able, s).contains { $0.id == "ai.computerEngine" } && rows(.able, s).contains { $0.id == "ai.mcp.composio" }, "ia: app control and the outside services are in 할 수 있는 일")
    // Slots for the branches still being merged sit in the right parts and draw nothing until filled.
    check(ArisSettingsParts.holding("ai.models")?.id == "talk.ai" && ArisSettingsParts.holding("ai.fallback")?.id == "talk.ai"
          && ArisSettingsParts.holding("aris.wakeName")?.id == "talk.call" && ArisSettingsParts.holding("control.trust")?.id == "able.control",
          "ia: the slots for models, 다른 AI로 넘기기, the wake name and trust are in their parts")
    check(ArisSettingsSlots.trust(s).isEmpty, "ia: an empty slot draws nothing")
    check(ArisSettingsSlots.wakeRows(s).map(\.id) == ["aris.wakeName"] && ArisSettingsParts.holding("aris.wakeName")?.id == "talk.call",
          "ia: jv-wake's name row is in its slot under “아리스”라고 부르기")
    // A row a branch adds with its old page still lands (merge-friendly).
    let added = ArisSettingsEntry(id: "ai.someNewRow", page: .ai, title: "새 줄", keywords: [])
    check(added.page == .talk && added.part.id == "talk.ai", "ia: a row added with its old page lands in the part that took that page's rows")
}

// MARK: - Migration: a user's settings keep their values

private func iaMigrationTests() {
    // A snapshot of an install from before the reorganisation (ai-services-tests' old keys, and the rows' own keys).
    let name = testSuiteName("aris-ia-old-defaults")
    let store = UserDefaults(suiteName: name)!
    store.removePersistentDomain(forName: name)
    let old: [String: Any] = ["arisBrain": "claude", "arisCloudListening": false, "arisHearEngine": "scribe", "arisSpeechModel": "small",
                              "arisVoiceID": "voice123", "arisVoiceName": "Rachel", "arisVoiceSpeed": 1.15, "arisLanguages": ["ko", "en", "ja"],
                              "arisWakeWord": true, "arisConversationMinutes": 15, "arisConversationSilence": 60, "arisBargeInOnSpeakers": true,
                              "arisDuplexAudio": true, "arisMuted": false, "claudeRingMode": "sevenDay", "settingsIconInNotch": false,
                              "arisSettingsOpenFolds": ["notch.window"], "arisSettingsTheme": "dark", "arisComputerEngine": "peekaboo"]
    for (key, value) in old { store.set(value, forKey: key) }
    let facts = ArisAIStore.Facts(hasElevenKey: true, whisperLargeInstalled: true)
    let before = ArisAIStore.read({ store.object(forKey: $0) }, facts: facts)
    let scribeBefore = (store.object(forKey: "arisCloudListening") as? Bool ?? true) && facts.hasElevenKey
    ArisHearSource.migrate(store, facts: facts)
    let after = ArisAIStore.read({ store.object(forKey: $0) }, facts: facts)
    check(before == after, "ia migration: every AI choice reads the same after (brain, hearing, voice, speed, languages)")
    check(ArisHearSource.scribeListens({ store.object(forKey: $0) }) == scribeBefore && store.string(forKey: "arisHearEngine") == after.hear,
          "ia migration: what really listened (not Scribe: its old switch was off) is what the one key says now")
    let unchanged = old.keys.filter { $0 != "arisHearEngine" && $0 != "arisCloudListening" }
    let changed = unchanged.filter { key in !((store.object(forKey: key) as AnyObject?)?.isEqual(old[key]) ?? false) }
    check(changed.isEmpty, "ia migration: nothing else a user set changes value, and every key keeps its name (\(changed))")
    ArisHearSource.migrate(store, facts: facts)
    check(ArisAIStore.read({ store.object(forKey: $0) }, facts: facts) == after, "ia migration: running again changes nothing")
    store.removePersistentDomain(forName: name)

    // The cases: agreeing keys and a fresh install are left alone; each disagreement keeps what was in effect.
    func run(_ values: [String: Any], key: Bool) -> (writes: Int, before: String, after: String, scribe: (Bool, Bool)) {
        var prefs = values
        let facts = ArisAIStore.Facts(hasElevenKey: key)
        let was = ArisAIStore.read({ prefs[$0] }, facts: facts).hear
        // What started Scribe before: the old switch alone (on unless turned off), with a key.
        let listened = (prefs["arisCloudListening"] as? Bool ?? true) && key
        let writes = ArisHearSource.migration({ prefs[$0] }, facts: facts)
        for write in writes { prefs[write.key] = write.value }
        return (writes.count, was, ArisAIStore.read({ prefs[$0] }, facts: facts).hear, (listened, ArisHearSource.scribeListens { prefs[$0] } && key))
    }
    check(run([:], key: true).writes == 0, "ia migration: a fresh install has nothing to change")
    check(run(["arisCloudListening": true], key: false).writes == 0, "ia migration: the old switch on and nothing chosen: Scribe still starts once a key is added")
    check(run(["arisHearEngine": "whisper", "arisCloudListening": false], key: true).writes == 0, "ia migration: keys that agree are left alone")
    for values: [String: Any] in [["arisHearEngine": "scribe", "arisCloudListening": false], ["arisHearEngine": "whisper", "arisCloudListening": true],
                                  ["arisCloudListening": false], ["arisHearEngine": "apple", "arisCloudListening": true]] {
        for key in [true, false] {
            let r = run(values, key: key)
            check(r.before == r.after && r.scribe.0 == r.scribe.1, "ia migration: \(values) with\(key ? "" : "out") a key keeps \(r.before)")
        }
    }
}
