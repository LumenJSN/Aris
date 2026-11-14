// Tests for the settings window's defects from the VM run of 2026-11-11 (qa/vm-run-1111/REPORT-new.md): AI 서비스
// tells the truth about which AI is chosen and which one answers on a Mac with none (bug 4), a page change starts at
// the top (bug 11), the built-in teammates' lines and the listening languages on an English Mac (bug 10), and the
// smaller things (다시 확인's sign, Scribe with no key, the voice caption, the word count, "api key" in the search,
// lines that were cut off). And two from the upgrade run (REPORT-upgrade.md): a dropdown's one highlight, kept in view
// (bug 8), and a click on a control of the settings window while it isn't the key window. Pure values and the source's
// own text: no window, no agent.
import Foundation

func runVM2SettingsTests() {
    vm2BrainTruthTests()
    vm2PageTopTests()
    vm2TeammateLineTests()
    vm2StartingLanguageTests()
    vm2CheckedAgainTests()
    vm2VoicePageTests()
    vm2WordCountTests()
    vm2SearchTests()
    vm2RoomForTextTests()
    vm2uMenuHighlightTests()
    vm2uFirstClickTests()
}

private let vm2Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func vm2Source(_ path: String) -> String { (try? String(contentsOf: vm2Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
private func vm2Catalog() -> [String: String] {
    ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: vm2Root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
}
private func vm2Hangul(_ text: String) -> Bool { text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) } }

private let vm2Presets = [
    ArisAIPreset(id: "openai", title: "OpenAI", needsKey: true, local: false, baseURL: "https://api.openai.com/v1", quick: "gpt-6-luna", strong: "gpt-6.1-sol"),
    ArisAIPreset(id: "anthropic", title: "Anthropic", needsKey: true, local: false, baseURL: "https://api.anthropic.com/v1", quick: "claude-haiku-4-5", strong: "claude-sonnet-4-5"),
]
private let vm2NoAI = ["claude": false, "codex": false, "antigravity": false, "api": false]

private func vm2State(_ change: (inout ArisAIServicesState) -> Void = { _ in }) -> ArisAIServicesState {
    var state = ArisAIServicesState()
    state.presets = vm2Presets
    state.brainReady = vm2NoAI
    change(&state)
    return state
}

// MARK: - Bug 4: AI 서비스 on a Mac with no AI

private func vm2BrainTruthTests() {
    let page = ArisAIServicesBuilder.page, menu = ArisAIServicesBuilder.menu
    func ticked(_ state: ArisAIServicesState) -> [String] { menu(.provider(.think), state, "").items.filter(\.checked).map(\.id) }

    // The rule the page takes its brain from: the preference's default is no choice.
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    check(ArisBrainChoice.shown("codex", stored: nil, ready: none).isEmpty && ArisBrainChoice.shown("codex", stored: "codex", ready: none) == "codex"
          && ArisBrainChoice.shown("codex", stored: nil, ready: nil) == "codex" && ArisBrainChoice.shown("api:openai", stored: "api", ready: none) == "api:openai",
          "vm2 bug 4: with nothing stored and no AI ready the page's brain is none; a brain the user stored is shown whatever is ready, and nothing is called missing before the agent answers")
    let live = vm2Source("Aris/components/Settings/ArisAIServicesLive.swift")
    check(live.contains("choices.think = ArisBrainChoice.shown(choices.think, stored: ArisBrainSetup.stored, ready: ArisBrainSetup.shared.ready)"),
          "vm2 bug 4: the AI 서비스 page reads its brain through the rule 대화's 기본으로 답하는 AI follows")

    // A new Mac with no AI: nothing is shown as chosen.
    let nobody = vm2State { $0.choices.think = "" }
    let empty = page(nobody)
    check(empty.think.rows.count == 1 && empty.think.rows[0].title == "생각" && empty.think.rows[0].desc == "고른 AI가 없어요" && empty.think.rows[0].warn == nil
          && empty.think.rows[0].control == .select(.provider(.think), ArisAISelectFace(label: "AI 고르기")),
          "vm2 bug 4: on a Mac with no AI the 생각 card names no AI as chosen, and its dropdown says to choose one")
    check(empty.think.need == .message(ArisAIServicesBuilder.noBrainHow) && ArisAIServicesBuilder.noBrainHow.hasPrefix("아직 답할 수 있는 AI가 없어요")
          && empty.thinkLine == nil && empty.login == nil,
          "vm2 bug 4: the card says no AI can answer yet and how to get one; no model, sign-in or fallback of an AI nobody chose is shown")
    check(ticked(nobody).isEmpty && menu(.provider(.think), nobody, "").items.first { $0.id == "codex" }?.tail == "설치 필요",
          "vm2 bug 4: nothing is ticked in the 생각 dropdown, and ChatGPT is listed as not installed like the others")

    // Claude or Anthropic picked on that Mac: shown with what it needs, and nobody is said to answer meanwhile.
    for (pick, needs) in [("claude", "설치 필요"), ("codex", "설치 필요"), ("api:anthropic", "키 필요")] {
        let picked = vm2State { $0.choices.think = pick; $0.thinkStored = "" }
        let shown = page(picked)
        check(shown.think.rows[0].warn == needs && shown.thinkLine == "아직 답할 수 있는 AI가 없어요" && ticked(picked) == [pick],
              "vm2 bug 4: \(pick) picked on a Mac with no AI says what it needs and that no AI can answer yet; ChatGPT is not said to think")
    }

    // "Until it can be used, X thinks" only when X really can.
    let working = vm2State { $0.choices.think = "api:anthropic"; $0.thinkStored = "codex"; $0.brainReady["codex"] = true }
    check(page(working).thinkLine == "쓸 수 있게 될 때까지 ChatGPT로 생각해요",
          "vm2 bug 4: a pick that can't answer yet names the stored AI as the one that thinks meanwhile when that one is set up")
    let keyed = vm2State { $0.choices.think = "claude"; $0.thinkStored = "api:openai"; $0.profiles = [ArisAIProfile(id: "openai", quick: "a", strong: "b", hasKey: true)] }
    check(page(keyed).thinkLine == "쓸 수 있게 될 때까지 OpenAI로 생각해요", "vm2 bug 4: an API brain with its key is named as the one that thinks meanwhile")
    let broken = vm2State { $0.choices.think = "claude"; $0.thinkStored = "codex" }
    let keyless = vm2State { $0.choices.think = "claude"; $0.thinkStored = "api:openai" }
    check(page(broken).thinkLine == "아직 답할 수 있는 AI가 없어요" && page(keyless).thinkLine == "아직 답할 수 있는 AI가 없어요",
          "vm2 bug 4: when the stored AI can't answer either (its tool or its key is missing), the line says no AI can answer yet")
    let unknown = vm2State { $0.choices.think = "api:anthropic"; $0.thinkStored = "codex"; $0.brainReady = [:] }
    check(page(unknown).thinkLine == "쓸 수 있게 될 때까지 ChatGPT로 생각해요", "vm2 bug 4: before the agent has answered, the stored AI is not called missing")

    // The security ruling: a brain the user stored stays the one shown, even when it can't answer here.
    let stored = vm2State { $0.choices.think = "codex" }
    check(page(stored).think.rows[0].desc == "ChatGPT" && page(stored).think.rows[0].warn == "설치 필요" && ticked(stored) == ["codex"]
          && ArisBrainChoice.resolve(stored: "codex", ready: none) == nil,
          "vm2 bug 4: a brain the user stored is still shown as theirs, with what it lacks, and is never replaced behind their back")

    // In English.
    ArisSettingsCopy.install(vm2Catalog())
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .ai, english: true)
    let lines = [ArisAIServicesBuilder.noBrainChosen, ArisAIServicesBuilder.chooseBrain, ArisAIServicesBuilder.noBrainHow, ArisAIServicesBuilder.noBrainAnswers]
    check(lines.allSatisfy { !vm2Hangul(english.dotted($0)) } && english.dotted(ArisAIServicesBuilder.noBrainAnswers) == "No AI can answer yet",
          "vm2 bug 4: the no-AI lines have their English")
}

// MARK: - Bug 11: a page change starts at the top

private func vm2PageTopTests() {
    // The behaviour itself is checked on a real scroll view by the offscreen probe (ARIS_RENDER_SCROLL=1
    // settings-render/render.sh); this pins what makes it so.
    let shell = vm2Source("Aris/components/Settings/ArisSettingsShell.swift")
    // Since settings pick 4-A the preview and the title stay while pages change, so there is one scroll view, and a
    // page's opening scrolls it to the mark at its very top before any jump to a row.
    let scroll = shell.range(of: "ScrollView { column.background(alignment: .top) { Color.clear.frame(height: 1).id(Self.top) } }")
    let page = shell.range(of: "proxy.scrollTo(Self.top, anchor: .top)"), jump = shell.range(of: "proxy.scrollTo(target.id")
    check(scroll != nil && page != nil && jump != nil && scroll!.upperBound < page!.lowerBound && page!.upperBound < jump!.lowerBound,
          "vm2 bug 11: a page change scrolls the pane to its top, and a jump to a row is still scrolled to after the page is there")
    let sidebar = vm2Source("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(sidebar.contains("nav.go(entry.page, anchor: entry.id, byKey: byKey)") && sidebar.contains("if let anchor { flash = ArisSettingsFlashTarget(id: anchor"),
          "vm2 bug 11: a search result still asks for its row, and only a jump with a row scrolls anywhere but the top")
}

// MARK: - Bug 10: the built-in teammates' lines, and the languages a new install listens in

private func vm2TeammateLineTests() {
    let ghost = ArisCharacterLook(type: "ghost", colorHex: nil, shading: "fabric")
    let mine = ArisTeammate(id: "docs", name: "Dora", routing: ArisTeammate.claudeCode.routing, look: ghost, brain: "claude", memoryFile: "")
    let renamed = ArisTeammate(id: ArisTeammate.claudeCodeId, name: "Claude Code", routing: "내 프로젝트를 고칠 때", look: ghost, brain: "claude", memoryFile: "")
    let rows = ArisTeamEditing.rows([.claudeCode, mine])
    check(rows.map(ArisTeamEditing.isAppLine) == [true, true, false] && !ArisTeamEditing.isAppLine(ArisTeamEditing.rows([renamed])[1]),
          "vm2 bug 10: main Aris's line and Claude Code's line as Aris seeded it are the app's own words; a line the user wrote is theirs, even with the same words")

    ArisSettingsCopy.install(vm2Catalog())
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .team, english: true), korean = ArisSettingsWording.make(page: .team, english: false)
    check(rows.prefix(2).allSatisfy { !vm2Hangul(english($0.role)) && korean($0.role) == $0.role } && english(ArisTeammate.claudeCode.routing) == "When coding a project in the terminal",
          "vm2 bug 10: both built-in teammates' lines have their English, and are drawn as written in Korean")
    let page = vm2Source("Aris/components/Settings/ArisTeamPage.swift"), detail = vm2Source("Aris/components/Settings/ArisFaceDetail.swift")
    check(page.contains("ArisTeamEditing.isAppLine(row) ? w(row.role) : row.role") && detail.contains("Text(w(row.role))"),
          "vm2 bug 10: the roster and Aris's own detail say the app's lines in the page's wording, and a user's line as it was written")
    check(page.contains(".lineLimit(3).truncationMode(.tail)") && !page.contains(".lineLimit(1).truncationMode(.tail)"),
          "vm2 bug 10: a roster line that doesn't fit one line wraps (Aris's own English line needs three) instead of ending in …")
}

private func vm2StartingLanguageTests() {
    let start = ArisLanguages.starting
    check(start(["en-US"]) == ["en"] && start(["en-GB", "en-US"]) == ["en"], "vm2 bug 10: an English Mac starts listening in English only, not Korean")
    check(start(["ko-KR"]) == ["ko", "en"] && start(["ko-KR", "en-US"]) == ["ko", "en"] && start(["en-US", "ko-KR"]) == ["ko", "en"] && start(["en-KR"]) == ["ko", "en"]
          && start([]) == ArisLanguages.defaults,
          "vm2 bug 10: a Mac that speaks Korean (the language or the region), or says nothing, starts with Korean and English as every install did")
    check(start(["fr-FR"]) == ["fr", "en"] && start(["ja-JP", "en-US"]) == ["ja", "en"] && start(["de-DE", "fr-FR", "en-GB"]) == ["de", "fr", "en"],
          "vm2 bug 10: any other Mac starts with its own languages in its order, then English")
    check(start(["zh-Hans-CN"]) == ["zh-Hans", "en"] && start(["zh-Hant-TW"]) == ["zh-Hant", "en"] && start(["zh-HK"]) == ["zh-Hant", "en"] && start(["yue-Hant-HK"]) == ["yue", "en"]
          && start(["nb-NO"]) == ["no", "en"] && start(["tlh"]) == ["en"],
          "vm2 bug 10: a system language is matched to the one Aris has (Chinese by its script or region, Bokmål as Norwegian); one it doesn't have is left out")
    for system in [["en-US"], ["ko-KR"], ["en-KR"], ["fr-FR", "ko"], ["ja-JP"], []] {
        check((start(system) == ArisLanguages.defaults) == (system.isEmpty || ArisHearingLocale.speaksKorean(system)),
              "vm2 bug 10: the starting languages and the recogniser's language agree on which Mac speaks Korean (\(system))")
    }
    check(start(["en-US"]).allSatisfy { code in ArisLanguages.all.contains { $0.code == code } } && start(["sw-KE", "xx"]) == ["sw", "en"],
          "vm2 bug 10: every starting language is one of the list's own codes")

    // Only the default: what a user stored is read exactly as stored.
    let stored = ArisAIStore.read({ $0 == "arisLanguages" ? ["ko", "ja"] : nil }, facts: .init(languages: ["en"]))
    check(stored.languages == ["ko", "ja"] && ArisAIStore.read({ _ in nil }, facts: .init(languages: ["en"])).languages == ["en"]
          && ArisAIStore.read({ _ in nil }, facts: .init()).languages == ArisLanguages.defaults,
          "vm2 bug 10: a stored choice of languages is never changed; with none stored the page reads the Mac's own")
    let keys = vm2Source("Aris/private/Aris/ArisPreferenceKeys.swift"), live = vm2Source("Aris/components/Settings/ArisAIServicesLive.swift")
    check(keys.contains(#"Key<[String]>("arisLanguages", default: ArisLanguages.starting(system: ArisLanguages.macLanguages))"#)
          && live.contains("languages: ArisLanguages.starting(system: ArisLanguages.macLanguages)"),
          "vm2 bug 10: the languages preference's default, and the AI 서비스 page's reading of it, start from the Mac's own preferred languages")
}

// MARK: - Smaller things

private func vm2CheckedAgainTests() {
    let page = ArisAIServicesBuilder.page
    let missing = vm2State { $0.choices.think = "claude"; $0.thinkStored = "" }
    let how = ArisSettingsBuilder.brainHow(.claude)
    check(page(missing).think.need == .button(message: how, title: "다시 확인", .recheckBrains), "vm2 check again: an AI that isn't installed says how to get it, with 다시 확인")
    var checked = missing
    checked.ui.checked = ArisAIServicesBuilder.brainsChecked
    check(page(checked).think.need == .checked(message: how, note: "방금 확인했어요"),
          "vm2 check again: just after 다시 확인 found it still missing, the row says it was checked just now where the button was")
    var other = missing
    other.ui.checked = "api:ollama"
    check(page(other).think.need == page(missing).think.need, "vm2 check again: a check of something else leaves this row's button")

    let server = ArisAIPreset(id: "ollama", title: "Ollama (이 Mac)", needsKey: false, local: true, baseURL: "http://127.0.0.1:11434/v1", quick: "q", strong: "q")
    var stopped = vm2State { $0.presets.append(server); $0.choices.think = "api:ollama"; $0.models["ollama"] = .unreachable }
    check(page(stopped).think.need == .button(message: "Ollama가 실행 중이 아니에요", title: "다시 확인", .recheck("api:ollama")), "vm2 check again: a local server that isn't running has 다시 확인")
    stopped.ui.checked = "api:ollama"
    check(page(stopped).think.need == .checked(message: "Ollama가 실행 중이 아니에요", note: "방금 확인했어요"), "vm2 check again: and says it was checked just now after it was asked again")
    check(ArisAIServicesBuilder.checkedShows >= 2 && ArisAIServicesBuilder.checkedShows <= 6, "vm2 check again: the sign stays a few seconds, then the button is back")

    let live = vm2Source("Aris/components/Settings/ArisAIServicesLive.swift"), view = vm2Source("Aris/components/Settings/ArisAIServicesPage.swift")
    check(live.contains("showChecked(ArisAIServicesBuilder.brainsChecked)") && live.contains("showChecked(provider)") && live.contains(".seconds(ArisAIServicesBuilder.checkedShows)"),
          "vm2 check again: both 다시 확인 buttons show the sign once their check has ended, and it goes away by itself")
    let drawn = view.range(of: "case .checked(let message, let note):").map { String(view[$0.lowerBound...].prefix(400)) } ?? ""
    check(drawn.contains("Text(w(note))") && !drawn.contains("Circle()") && !drawn.contains("repeatForever"), "vm2 check again: the sign is still text, with no dot and nothing that blinks")
    ArisSettingsCopy.install(vm2Catalog())
    defer { ArisSettingsCopy.install([:]) }
    check(ArisSettingsCopy.t("방금 확인했어요") == "Checked just now", "vm2 check again: the sign has its English")
}

private func vm2VoicePageTests() {
    func scribe(_ change: (inout ArisSettingsSnapshot) -> Void) -> ArisSettingItem? {
        var s = ArisSettingsSnapshot()
        change(&s)
        return ArisSettingsBuilder.sections(.voice, s).flatMap(\.rows).first { $0.id == "voice.scribe" }
    }
    let noKey = scribe { $0.cloud = true; $0.hasVoiceKey = false }
    check(noKey?.control == .toggle(.cloud, false, enabled: false) && noKey?.desc?.contains("ElevenLabs 키를 넣으면") == true,
          "vm2 voice: with no ElevenLabs key, ElevenLabs Scribe로 듣기 reads as off and can't be switched, and its line says a key is needed")
    check(scribe { $0.cloud = true; $0.hasVoiceKey = true }?.control == .toggle(.cloud, true) && scribe { $0.cloud = false; $0.hasVoiceKey = true }?.control == .toggle(.cloud, false)
          && ArisSettingsBuilder.sections(.voice, { var s = ArisSettingsSnapshot(); s.hasVoiceKey = true; return s }()).first { $0.id == "voice.language" }?.note?.contains("요금") == true,
          "vm2 voice: with a key the switch shows and changes the stored choice as before")

    ArisSettingsCopy.install(vm2Catalog())
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .voice, english: true)
    check(english(noKey?.desc ?? "가").unicodeScalars.allSatisfy { !(0xAC00...0xD7A3).contains($0.value) }, "vm2 voice: the no-key line has its English")
}

private func vm2WordCountTests() {
    check(ArisVocabulary.own(file: nil, learned: []).isEmpty && ArisVocabulary.own(file: "# 내 단어\n", learned: []).isEmpty,
          "vm2 word list: a new install has no words of the user's own")
    check(ArisVocabulary.expected(own: []) == ArisVocabulary.builtIn && ArisVocabulary.expected(own: ["노션", "youtube"]) == ["노션", "youtube", "유튜브"],
          "vm2 word list: the recognisers are still told to expect the built-in names, each once")
    check(ArisVocabulary.own(file: "노션\nClawd\n", learned: ["Aris", "노션"]) == ["노션", "Clawd", "Aris"], "vm2 word list: the user's words are the file's, then the ones dictation learned")
    let live = vm2Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("words = ArisVocabulary.loadOwn().count") && !live.contains("words = ArisVocabulary.load().count"),
          "vm2 word list: 단어장's count is of the user's own words, not the two built-in ones (it said 2 on a new install)")
}

private func vm2SearchTests() {
    let plain = ArisSettingsIndex.search("api key").map(\.id)
    check(["ai.brain", "ai.jev", "ai.speak", "ai.mcp.composio"].allSatisfy(plain.contains), "vm2 search: \"api key\" finds the AI 서비스 rows that take a key")
    ArisSettingsCopy.install(vm2Catalog())
    defer { ArisSettingsCopy.install([:]) }
    let w = ArisSettingsWording.make(page: .ai, english: true)
    let english = ArisSettingsIndex.search("api key", alias: { .init(title: w.of($0.page, $0.title), page: w.frame($0.page.title)) }).map(\.id)
    check(english.contains("aris.claudeBudget") && english.contains("ai.brain") && english.contains("ai.speak"),
          "vm2 search: in the English window \"api key\" finds AI services as well as the daily budget row")
    check(ArisSettingsIndex.search("API 키").map(\.id).contains("ai.brain") && english.first == "aris.claudeBudget",
          "vm2 search: the Korean words find what they did, and the setting named for an API key still comes before the ones that only take one")
}

private func vm2RoomForTextTests() {
    let menu = vm2Source("Aris/components/Settings/ArisAIServicesMenu.swift"), sidebar = vm2Source("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(menu.contains("return text.font(.system(size: 11)).lineLimit(2).fixedSize(horizontal: false, vertical: true)"),
          "vm2 cut off: a dropdown item's small line takes a second line instead of ending in … (\"Answers through…\")")
    let row = sidebar.range(of: "private struct ArisSearchResultRow").map { String(sidebar[$0.lowerBound...]) } ?? ""
    check(row.contains("foregroundStyle(palette.navOn).lineLimit(2)") && row.contains(".frame(minHeight: 42)") && !row.contains(".frame(height: 42)"),
          "vm2 cut off: a search result's name takes a second line, and its row grows for it (\"Look at the screen w…\")")
}

// MARK: - Upgrade run, bug 8: a dropdown's highlight

private func vm2uMenuHighlightTests() {
    let more = ["groq", "xai", "mistral", "deepseek"].map { ArisAIPreset(id: $0, title: $0.capitalized, needsKey: true, local: false, baseURL: "https://x.example/v1", quick: "q", strong: "s") }
    let state = vm2State {
        $0.presets += more
        $0.profiles = more.map { ArisAIProfile(id: $0.id, quick: "q", strong: "s", hasKey: true) }
        $0.choices.think = "api:deepseek"
    }
    let menu = ArisAIServicesBuilder.menu(.provider(.think), state)
    let stops = ArisAIMenuHighlight.stops(menu)
    check(stops.first == "claude" && stops.last == "connect" && stops.contains("api:deepseek") && stops.count == menu.items.count + menu.foot.count,
          "vm2u bug 8: the keys stop at every item that can be picked, the foot's too")
    let opened = ArisAIMenuHighlight.opening(menu)
    check(opened.id == "api:deepseek" && opened.keyMoves == 0 && ArisAIMenuHighlight.opening(ArisAIMenu()).id == nil,
          "vm2u bug 8: a dropdown opens with its chosen item highlighted (the list opens scrolled to it)")

    // The keyboard moves it, and says so, so the list follows.
    let rest = CGPoint(x: 400, y: 300)
    let down = opened.moved(1, in: menu, pointer: rest)
    let at = stops.firstIndex(of: "api:deepseek")!
    let up = opened.moved(-1, in: menu, pointer: rest)
    check(down.id == stops[at + 1] && down.keyMoves == 1 && up.id == stops[at - 1],
          "vm2u bug 8: ↓ and ↑ move the highlight to the next item, and each move is counted so the list scrolls to it")
    var walk = opened
    var seen: [String] = []
    for _ in stops { walk = walk.moved(1, in: menu, pointer: rest); seen.append(walk.id ?? "") }
    let wrapsDown = ArisAIMenuHighlight(id: "connect").moved(1, in: menu, pointer: rest).id, wrapsUp = ArisAIMenuHighlight(id: "claude").moved(-1, in: menu, pointer: rest).id
    check(Set(seen) == Set(stops) && walk.id == "api:deepseek" && walk.keyMoves == stops.count && wrapsDown == "claude" && wrapsUp == "connect",
          "vm2u bug 8: ↓ goes through every item and wraps from the last to the first")
    let fromNone = [ArisAIMenuHighlight().moved(1, in: menu, pointer: rest).id, ArisAIMenuHighlight().moved(-1, in: menu, pointer: rest).id]
    let fromGone = ArisAIMenuHighlight(id: "gone").moved(1, in: menu, pointer: rest).id, inEmpty = ArisAIMenuHighlight().moved(1, in: ArisAIMenu(), pointer: rest).id
    check(fromNone == ["claude", "connect"] && fromGone == "claude" && inEmpty == nil,
          "vm2u bug 8: with nothing highlighted (or an item the search took away) ↓ starts at the first and ↑ at the last; an empty list has none")
    let hear = ArisAIServicesBuilder.menu(.provider(.hear), state)
    let afterLast = ArisAIMenuHighlight(id: "scribe").moved(1, in: hear, pointer: rest).id
    check(!ArisAIMenuHighlight.stops(hear).contains("deepgram") && afterLast == "apple",
          "vm2u bug 8: an item that can't be picked (준비 중) is never highlighted")

    // One highlight: the pointer's moving takes it; a row sliding under a pointer at rest doesn't.
    let slidUnder = down.hovered("claude", pointer: rest, in: menu), slidOut = down.unhovered(down.id ?? "", pointer: rest)
    check(slidUnder == down && slidOut == down,
          "vm2u bug 8: after a key moved the highlight, the row that scrolls under a pointer at rest doesn't take it back")
    let pointed = down.hovered("claude", pointer: CGPoint(x: 401, y: 300), in: menu)
    check(pointed.id == "claude" && pointed.keyMoves == down.keyMoves && pointed.pointerAtKey == nil,
          "vm2u bug 8: once the pointer moves, the row under it is the one highlight, and the list doesn't scroll for it")
    check(pointed.moved(1, in: menu, pointer: rest).id == "codex", "vm2u bug 8: the keyboard goes on from the row the pointer highlighted")
    let away = CGPoint(x: 9, y: 9)
    let overDisabled = pointed.hovered("deepgram", pointer: away, in: hear), leftIt = pointed.unhovered("claude", pointer: away), leftOther = pointed.unhovered("codex", pointer: away)
    check(overDisabled == pointed && leftIt.id == nil && leftOther == pointed,
          "vm2u bug 8: the pointer never highlights an item that can't be picked; leaving the highlighted row clears it, leaving another doesn't")

    let view = vm2Source("Aris/components/Settings/ArisAIServicesMenu.swift")
    let row = view.range(of: "private struct ArisAIMenuRow").map { String(view[$0.lowerBound...]) }?.components(separatedBy: "struct ArisAISampleButton").first ?? ""
    check(!row.contains("@State private var hovering") && !view.contains("hovering || highlighted") && row.contains("highlighted && !item.disabled"),
          "vm2u bug 8: a row has no highlight of its own, so the pointer's and the keyboard's can't both show")
    check(view.contains(".onChange(of: open.highlight.keyMoves)") && view.contains("proxy.scrollTo(id, anchor: .center)") && view.contains(".id(item.id)")
          && view.contains("ArisAIMenuHighlight.opening(menu)"),
          "vm2u bug 8: the list scrolls to the row a key highlighted, and to the chosen row when it opens")
}

// MARK: - Upgrade run: the first click on a settings control

private func vm2uFirstClickTests() {
    let window = vm2Source("Aris/components/Settings/ArisSettingsWindow.swift")
    check(window.contains("let host = ArisSettingsHostingView(rootView: ArisSettingsRoot())") && window.contains("material.addSubview(host)")
          && window.contains("override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }"),
          "vm2u restart: a click on a settings control counts even when it is the click that brings the window forward (다시 시작 did nothing on the first click)")
    let live = vm2Source("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("case .restart: ApplicationRelauncher.restart()"), "vm2u restart: 다시 시작 restarts at once, with no confirm, wait or page load before it")
}
