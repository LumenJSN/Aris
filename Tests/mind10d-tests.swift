// Tests for the tenth real-screen VM check, items 7 and 12 (jv-mind10d): the quick understanding's pick, time limit and
// rest; the setup's key that didn't answer and where it points; the Mind's speech rule and a date said as a date; a
// card all in one language; the settings line for missing permissions; "35일" kept on one line. No live call.
import AppKit
import Foundation

func runMind10dTests() {
    mind10dRouterPickTests()
    mind10dRouterLimitTests()
    mind10dRouterMenuTests()
    mind10dSetupKeyTests()
    mind10dSettingsPointerTests()
    mind10dSpeechTests()
    mind10dCardTests()
    mind10dPermissionLineTests()
    mind10dLineBreakTests()
}

private func mind10dSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func mind10dProfile(_ id: String, router: String? = nil) -> ArisAPIProfile {
    let preset = ArisAPIPreset.named(id)!
    return ArisAPIProfile(id: id, quick: preset.quick, strong: preset.strong, baseURL: nil, vision: nil, tools: nil, router: router)
}

// MARK: - 7. Who is asked

private func mind10dRouterPickTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mind10d-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    let secrets = ArisMCPMemorySecrets(), signing = ArisMCPMemorySecrets()
    let store = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    let cheapest = { ArisAPIRouterCall.cheapest(store.load(), hasKey: { secrets.secret(for: $0) != nil })?.id }
    _ = store.update { $0.saving(mind10dProfile("deepseek")) }
    check(cheapest() == nil, "router 자동: a profile without its key is never asked")
    _ = secrets.save("sk-deepseek-key-0123456789", for: "deepseek")
    check(ArisAPIRouterCall.cost(ArisAPIRouterCall.model(for: mind10dProfile("deepseek"))) == nil && cheapest() == "deepseek",
          "router 자동 (VM 10, item 7): with only DeepSeek connected, whose price Aris doesn't know, DeepSeek is asked, not the keyword rules")
    _ = store.update { $0.saving(mind10dProfile("groq")) }
    _ = secrets.save("gsk-groq-key-0123456789", for: "groq")
    check(cheapest() == "deepseek", "router 자동: among profiles with no known price the id decides, the same on every turn")
    _ = store.update { $0.saving(mind10dProfile("openai")) }
    _ = secrets.save("sk-openai-key-0123456789", for: "openai")
    check(cheapest() == "openai", "router 자동: a profile with a known price comes before every one without")
}

// MARK: - 7. How long it may take, and the rest

private func mind10dRouterLimitTests() {
    typealias P = ArisRouterPatience
    let body: [String: Any] = ["timeout": P.limit(.smallModel), "chatTimeout": P.limit(.chatModel)]
    check(ArisAPIRouterCall.limit(body, model: "gpt-6-luna") == 0.6 && ArisAPIRouterCall.limit(body, model: "deepseek-chat") == 2.5,
          "router limit (VM 10, item 7): a small routing model keeps 600 ms, a chat model gets the chat limit")
    check(ArisAPIRouterCall.limit(["timeout": 0.6], model: "deepseek-chat") == 0.6 && ArisAPIRouterCall.limit(["chatTimeout": 60], model: "deepseek-chat") == 5
          && ArisAPIRouterCall.limit([:], model: "gpt-6-luna") == 0.6,
          "router limit: an older app's request keeps its one limit, and no limit is longer than 5 s")
    check(P.appWait(api: true) > P.limit(.chatModel) && P.appWait(api: false) == P.limit(.jev) && abs(ArisRouterModels.timeoutSeconds - 0.6) < 0.0001,
          "router limit: the app waits a little longer than the agent's longest limit for an API profile, and Jev's own 600 ms for Jev")
    let ask = mind10dSource("Aris/private/Aris/ArisRouterModels+Ask.swift"), controller = mind10dSource("Aris/private/Aris/ArisController.swift")
    check(ask.contains("\"chatTimeout\": ArisRouterPatience.limit(.chatModel)") && ask.contains("timeout: max(2, ArisRouterPatience.appWait(api: true))"),
          "router limit: the app sends both limits and waits for the agent's answer that long")
    // Merged with the decision models (jv-decision): only a chat profile used as the router waits longer and rests.
    check(controller.contains("if case .api = route { isChat = true }")
          && controller.contains("Self.within(isChat ? .milliseconds(Int(ArisRouterPatience.appWait(api: true) * 1_000)) : ArisRouter.timeout)"),
          "router limit: only a chat profile gets the longer wait; Jev and the decision models keep theirs")
    check(controller.contains("if isChat, routerRest.isResting(route: routeName, now: Date()) { return (nil, unrouted.tier, false) }")
          && controller.contains("if isChat { routerRest.answered(route: routeName) }") && controller.contains("if isChat, routerRest.missed(route: routeName, now: Date()) {")
          && controller.components(separatedBy: "router resting").count == 2,
          "router rest: a resting model isn't asked, an answer clears the count, and the rest is logged in one place")
    var rest = ArisRouterRest()
    let start = Date(timeIntervalSince1970: 5_000)
    let began = (0..<ArisRouterRest.missesBeforeRest).map { _ in rest.missed(route: "api(Optional(\"deepseek\"))", now: start) }
    check(began == [false, false, true] && rest.isResting(route: "api(Optional(\"deepseek\"))", now: start.addingTimeInterval(599))
          && !rest.isResting(route: "api(Optional(\"deepseek\"))", now: start.addingTimeInterval(600)) && ArisRouterRest.restSeconds == 600,
          "router rest (VM 10, item 7): three misses in a row, then ten minutes on the keyword rules; the third miss is the one that says so")
}

// MARK: - 7. What the menu says

private func mind10dRouterMenuTests() {
    typealias B = ArisAIServicesBuilder
    var state = ArisAIServicesState()
    state.presets = [
        ArisAIPreset(id: "openai", title: "OpenAI", needsKey: true, local: false, baseURL: "", quick: "gpt-6-luna", strong: "gpt-6.1-sol"),
        ArisAIPreset(id: "deepseek", title: "DeepSeek", needsKey: true, local: false, baseURL: "", quick: "deepseek-chat", strong: "deepseek-chat"),
        ArisAIPreset(id: "mine", title: "My server", needsKey: true, local: false, baseURL: "https://x.example/v1", quick: "m", strong: "m", custom: true),
    ]
    let deepseek = ArisAIProfile(id: "deepseek", quick: "deepseek-chat", strong: "deepseek-chat", hasKey: true, router: nil, routerPrice: nil)
    let mine = ArisAIProfile(id: "mine", quick: "m", strong: "m", hasKey: true, router: nil, routerPrice: nil)
    state.profiles = [mine, deepseek]
    guard case .api(let preset, _) = B.routerPick(state) else { return check(false, "router row 자동 (VM 10, item 7): only DeepSeek connected is DeepSeek") }
    check(preset.id == "deepseek" && B.page(state).router.line == "DeepSeek deepseek-chat · 그 서비스 요금으로 · 요청한 말만 보내요",
          "router row 자동 (VM 10, item 7): with only DeepSeek connected the row names DeepSeek (never his own connection), at that service's price")
    state.profiles.append(ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true, router: "gpt-6-luna", routerPrice: ArisAIPrice(input: 0.10, output: 0.50)))
    if case .api(let priced, _) = B.routerPick(state) { check(priced.id == "openai", "router row 자동: a priced profile comes first") } else { check(false, "router row 자동: priced first") }
    let auto = B.menu(.router, state).items.first { $0.id == "auto" }
    check(auto?.subtitle == B.routerAutoLine && B.routerAutoLine.contains("연결된 API") && B.routerAutoLine.contains("키워드 규칙") && !B.routerAutoLine.contains("없으면 가장 싼 연결된 API"),
          "router menu: 자동's line says what happens (Jev, else a connected API with priced ones first, else the keyword rules)")
    let strings = mind10dSource("Aris/components/Settings/Settings.xcstrings")
    check(strings.contains("\"\(B.routerAutoLine)\"") && strings.contains("Jev when its key is saved, else a decision model with a saved key, then a connected API (the cheapest with a known price first), else the keyword rules")
          && !strings.contains("else the cheapest connected API\""),
          "router menu: the line has its English, and the old promise is gone")
}

// MARK: - 12a. A key that is saved and didn't answer

private func mind10dSetupKeyTests() {
    typealias R = ArisOnboardingBrainRows
    let none: [ArisBrain: Bool] = [.claude: false, .codex: false, .antigravity: false, .api: false]
    check(R.checked(answered: true, before: none, after: none).withKeyTrouble(true) == .keyNotAnswering
          && R.checked(answered: true, before: none, after: none).withKeyTrouble(false) == .nothing,
          "setup 다시 확인 (VM 10, item 12): after a key was saved and didn't answer, it is never \"no AI is set up\"")
    var keyOnly = none
    keyOnly[.api] = true
    check(R.checked(answered: true, before: none, after: keyOnly).withKeyTrouble(true) == .keyNotAnswering
          && R.checked(answered: true, before: keyOnly, after: keyOnly).withKeyTrouble(true) == .keyNotAnswering
          && R.checked(answered: true, before: none, after: keyOnly).withKeyTrouble(false) == .found([.api]),
          "setup 다시 확인: a key whose check failed is not called newly ready; one that answers is")
    var claude = none
    claude[.claude] = true
    var both = claude
    both[.api] = true
    check(R.checked(answered: true, before: none, after: claude).withKeyTrouble(true) == .found([.claude])
          && R.checked(answered: true, before: none, after: both).withKeyTrouble(true) == .found([.claude])
          && R.checked(answered: false, before: none, after: none).withKeyTrouble(true) == .unreachable,
          "setup 다시 확인: another AI found is still said, and a helper that didn't answer is still that")
    let korean = ArisSetupWords.checked(.keyNotAnswering, names: { $0.rawValue }, english: false)
    let english = ArisSetupWords.checked(.keyNotAnswering, names: { $0.rawValue }, english: true)
    check(korean.contains("키는 저장돼 있는데") && korean.contains("답을 받지 못했어요") && english.contains("the key is saved") && english.contains("didn't answer")
          && !english.contains("no AI") && !korean.contains("준비된 AI가 없어요"),
          "setup 다시 확인: both languages say the key is saved and still didn't answer, as the line above it does")
    let guide = mind10dSource("Aris/private/Aris/Onboarding/ArisOnboardingGuide+Brain.swift"), page = mind10dSource("Aris/private/Aris/Onboarding/ArisOnboardingBrainPage.swift")
    check(guide.contains("func retryBrainKey() async") && page.contains("if pressed { await guide.retryBrainKey() }")
          && page.contains(".withKeyTrouble(guide.brainKeyTrouble != nil)"),
          "setup 다시 확인: the press tries the saved key again, and says what that came to")
}

// MARK: - 12b. Where the setup points

private func mind10dSettingsPointerTests() {
    let part = ArisSettingsParts.part("talk.ai")
    let korean = ArisSettingsPath.aiPage(english: false)
    check(part != nil && korean == "설정 › \(ArisSettingsPage.talk.title) › \(part?.title ?? "?")" && korean == "설정 › Aris와 말하기 › AI · 모델",
          "setup pointer (VM 10, item 12): the AI page is named from the part's own title")
    // The window's English, read from its catalogue as the app reads it.
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/components/Settings/Settings.xcstrings")
    ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data()))
    let english = ArisSettingsPath.aiPage(english: true)
    let own = ArisSettingsCopy.t(ArisSettingsPage.talk.title) + " › " + ArisSettingsCopy.t(part?.title ?? "?")
    check(english == "Settings › " + own && english == "Settings › Talking to Aris › AI · Model" && !english.contains("AI services"),
          "setup pointer: in English it is the window's own English, never \"AI services\"")
    check(ArisSettingsPath.shown("You can pick one later in Settings › AI services.", english: true) == "You can pick one later in \(english)."
          && ArisSettingsPath.shown("나중에 설정 › AI 서비스에서 고를 수 있어요.", english: false) == "나중에 \(korean)에서 고를 수 있어요.",
          "setup pointer: the guide's translated lines that still name the old page read as the page that has its rows")
    ArisSettingsCopy.install([:])
    check(ArisSettingsPath.aiPageEnglish == own && ArisSettingsPath.aiPage(english: true) == english,
          "setup pointer: where the catalogue can't be read the English is the catalogue's own, held equal here")
    check(ArisSetupWords.brainKeyLead(anyReady: true, english: false).contains(korean) && ArisSetupWords.brainKeyLead(anyReady: true, english: true).contains(english),
          "setup pointer: the key page's line points there in both languages")
    check(mind10dSource("Aris/private/Aris/Onboarding/ArisOnboardingCopy.swift").contains("ArisSettingsPath.shown(brainHeadingText(heading), english: language != \"ko\")"),
          "setup pointer: the AI page's heading goes through the same naming")
}

// MARK: - 12c. How the Mind speaks

private func mind10dSpeechTests() {
    let rule = ArisMindSession.speechStyleRule
    check(ArisMindSession.rules.hasSuffix(rule) && ArisMindSession.rules.components(separatedBy: rule).count == 2, "mind speech: the rule is in the Mind's rules, once, at the end")
    check(rule.contains("Small talk, thanks and simple questions get one short sentence")
          && rule.contains("State what you know as a plain fact in your own voice") && rule.contains("ends on 예요 or 이에요") && rule.contains("never as hearsay")
          && rule.contains("Say dates and times the way people say them aloud") && rule.contains("never as digits joined by hyphens or colons")
          && rule.contains("Never say the name of one of your tools"),
          "mind speech (VM 10, item 12): one short sentence for small talk, facts stated plainly, dates as people say them, no tool names")
    // No wrong form is spelled out (a shown form is a form the model copies), and no capability's id is in it.
    check(!["래요", "대요", "라고 해요", "2026-"].contains(where: rule.contains)
          && !ArisCapabilityBook.all.contains { rule.contains($0.name) || rule.contains($0.id) },
          "mind speech: the rule shows no hearsay ending and no digit date, and names no capability")

    typealias D = ArisSpeakableDates
    check(D.natural("2026-11-20에서 100일 뒤는 2027-02-28이에요.", thisYear: 2026) == "11월 20일에서 100일 뒤는 2027년 2월 28일이에요.",
          "spoken date (VM 10, item 12): \"2026-11-20에서\" is said \"11월 20일에서\"; another year keeps its year")
    check(D.natural("The event is on 2026-11-21 at 3 pm.", thisYear: 2026) == "The event is on November 21 at 3 pm."
          && D.natural("Due 2027-01-05.", thisYear: 2026) == "Due January 5, 2027.",
          "spoken date: an English sentence gets the month's name")
    check(D.natural("버전 1.2026-11-20", thisYear: 2026) == "버전 1.2026-11-20" && D.natural("2026-13-40은 날짜가 아니에요", thisYear: 2026) == "2026-13-40은 날짜가 아니에요"
          && D.natural("전화 010-2026-11-20-1", thisYear: 2026) == "전화 010-2026-11-20-1" && D.natural("2026-02-30", thisYear: 2026) == "2026-02-30"
          && D.natural("날짜 없음", thisYear: 2026) == "날짜 없음",
          "spoken date: only a whole, real date is read as one")
    let year = Calendar(identifier: .gregorian).component(.year, from: Date())
    check(ArisSpeakable.speakable("\(year)-11-20에서 100일 뒤예요.") == "11월 20일에서 100일 뒤예요.", "spoken date: the voice's text passes through it, whatever the model wrote")
}

// MARK: - 12d. A card in one language

private func mind10dCardTests() {
    typealias E = ArisCardEnglish
    let finder = ArisDesktopTarget(name: "Finder", bundle: "com.apple.finder", pid: 4242, known: true, never: false, browser: false, sending: false)
    let element = ArisDesktopElement(id: "elem_5", role: "AXStaticText", label: "Downloads")
    let click = ArisDesktopRequest(verb: .click)
    let korean = ArisDesktopCard.card(click, target: finder, element: element, window: "vmcheck3", remember: false, wiped: false, mayRaise: true, english: false)
    let english = ArisDesktopCard.card(click, target: finder, element: element, window: "vmcheck3", remember: false, wiped: false, mayRaise: true, english: true)
    check(korean.title == "Finder에서 누르기" && korean.detail.contains("대상: 글자 “Downloads”") && korean.detail.contains("백그라운드로 안 되면 ‘vmcheck3’ 창을"),
          "card fixture: the click card of the VM run (\"Finder에서 누르기\", 창, 대상: 글자 “Downloads”, the line about bringing the window forward)")
    check(E.title(korean.title) == english.title && E.detail(korean.detail, title: korean.title) == english.detail,
          "card English (VM 10, item 12): the helper's Korean click card under an English UI reads exactly as the helper's own English card, no Korean label left")
    check(!E.hasHangul(E.detail(korean.detail, title: korean.title)) && !E.hasHangul(E.title(korean.title)), "card English: nothing Korean is left on that card but his own names")
    // Every verb's title, and the rows that carry no words of his.
    let verbs: [ArisDesktopVerb] = [.click, .type, .setValue, .press, .scroll, .drag, .menuClick, .dialogClick, .dialogInput, .dialogFile, .window, .app, .clickAt, .see, .batch]
    check(verbs.allSatisfy { E.title("Finder에서 " + ArisDesktopCard.verbLabel($0)) == ArisDesktopCopy.verb($0) + " in Finder" },
          "card English: every desktop verb's title is the helper's own English")
    let roles = ["textfield", "searchfield", "securetextfield", "button", "popupbutton", "menubutton", "checkbox", "radiobutton", "link", "menuitem", "menu", "tab",
                 "slider", "statictext", "image", "row", "cell", "table", "list", "scrollarea", "window", "group", "toolbar", "webarea", "heading", "disclosuretriangle", "nonsense"]
    check(roles.allSatisfy { E.desktopRow("대상: " + ArisDesktopCard.roleWord($0) + " “x”") == "Target: " + ArisDesktopCard.roleWord($0, english: true) + " “x”" },
          "card English: every role's word on the 대상 row is the helper's own English")
    let remembered = ArisDesktopCard.closing(target: finder, remember: true, wiped: false, english: false), rememberedEnglish = ArisDesktopCard.closing(target: finder, remember: true, wiped: false, english: true)
    let wiped = ArisDesktopCard.closing(target: finder, remember: false, wiped: true, english: false), wipedEnglish = ArisDesktopCard.closing(target: finder, remember: false, wiped: true, english: true)
    check(remembered.map { E.desktopRow($0) ?? $0 } == rememberedEnglish && wiped.map { E.desktopRow($0) ?? $0 } == wipedEnglish,
          "card English: the card's closing line too")
    check(E.desktopRow("메모: 우유 사기") == nil && E.desktopRow("엄마에서 만나") == nil && E.desktopTitle("집에서 쉬기") == nil
          && E.desktopRow("창문: 열기") == nil && E.desktopRow("대상: 엄마 “x”") == nil
          && E.detail("백그라운드로 안 되면 창을 앞으로 가져와서 누르기 (끝나면 원래 앱으로 돌아가요)", title: "할 일에 넣기").hasPrefix("백그라운드로"),
          "card English: his own words are never taken for one of the card's rows")
    // The undo's card for an event Aris added: "Delete the event" over "일정 추가: 치과".
    // (ArisActivityTimeline.confirmation: the title "일정 지우기" or "예약 다시 살리기", the detail the activity log's own line.)
    let timeline = mind10dSource("Aris/private/Aris/Side/ArisActivityTimeline.swift")
    check(timeline.contains("ArisUIWords.text(\"예약 다시 살리기\", \"Bring the schedule back\", english: english) : ArisUIWords.text(\"일정 지우기\", \"Delete the event\", english: english)")
          && Set(E.undoLeads.keys) == ["일정 지우기", "예약 다시 살리기", "Delete the event", "Bring the schedule back"]
          && E.undoLeads.values.joined().allSatisfy { ArisActivityWords.english($0.korean + "x") == $0.english + "x" },
          "card fixture: the undo card's two titles are the ones whose row is the activity log's line")
    check(E.title("일정 지우기") == "Delete the event" && E.detail("일정 추가: 치과", title: "일정 지우기") == "Event added: 치과"
          && E.detail("일정 추가: 치과", title: "메모 만들기") == "일정 추가: 치과",
          "card English (VM 10, item 12): the undo card's row is said in English too (\"Delete the event\" over \"Event added: 치과\"), and only on that card")
}

// MARK: - 12e. The settings line for a missing permission

private func mind10dPermissionLineTests() {
    typealias C = ArisSettingsCaption
    let line = C.greeting(agentDown: false, missingPermissions: 1, missingNames: [ArisFix.Pane.screen.title(english: false)])
    check(C.asksForPermissions(line) && ArisSettingsParts.part(C.permissionsAnchor) == nil && ArisSettingsParts.holding(C.permissionsAnchor) == nil,
          "permission line fixture: the line asks for the permission rows, and the section's id is no part or row (so its page couldn't be looked up)")
    check(C.permissionsPage != nil && C.permissionsPage == ArisSettingsParts.holding("control.ax")?.page,
          "permission line (VM 10, item 12): the press knows the page the permission rows are on")
    let sidebar = mind10dSource("Aris/components/Settings/ArisSettingsSidebar.swift")
    check(sidebar.contains("if anchor == ArisSettingsCaption.permissionsAnchor { return ArisSettingsCaption.permissionsPage }")
          && sidebar.contains("nav.go(anchor: ArisSettingsCaption.permissionsAnchor)"),
          "permission line: the press finds that page for the section, from whatever page is open")
    let look = mind10dSource("ArisAgent/ArisLook.swift")
    check(look.contains("if !ArisFocusContext.missesScreen(resolution) {") && look.contains("if ArisScreenRead.saysPermissionOff(look.unread) {")
          && look.contains("look.needs.removeAll { $0 == \"screen\" }"),
          "screen button (VM 10, item 12): a look whose focus was read whole says nothing about Screen Recording and leaves no button for it")
}

// MARK: - 12f. "35일" on one line

private func mind10dLineBreakTests() {
    let answer = ArisAnswerAttributed.string(from: "오늘(11월 20일)부터 크리스마스(12월 25일)까지는 35일 남았어요.")
    check(ArisAnswerAttributed.keptTogether("35일 남았어요, 3시 2개 v2 100 일") == "35\u{2060}일 남았어요, 3\u{2060}시 2\u{2060}개 v2 100 일"
          && ArisAnswerAttributed.plainText(answer) == "오늘(11월 20일)부터 크리스마스(12월 25일)까지는 35일 남았어요.",
          "answer lines (VM 10, item 12): a number and its Korean counter are joined; a copy gets the text without the joiner")
    // Laid out at every width from narrow to wide: no line begins with the counter of a number that ended the line before.
    let storage = NSTextStorage(attributedString: answer), manager = NSLayoutManager()
    storage.addLayoutManager(manager)
    let container = NSTextContainer(size: NSSize(width: 100, height: 10_000))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    let text = answer.string as NSString
    var split: [Int] = []
    for width in stride(from: 120, through: 520, by: 4) {
        container.size = NSSize(width: CGFloat(width), height: 10_000)
        manager.ensureLayout(for: container)
        var index = 0
        while index < manager.numberOfGlyphs {
            var range = NSRange()
            manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            let characters = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            if characters.location > 0, text.substring(with: characters).hasPrefix("일"), text.substring(to: characters.location).hasSuffix("5") || text.substring(to: characters.location).hasSuffix("\u{2060}") { split.append(width) }
            index = NSMaxRange(range)
        }
    }
    check(split.isEmpty, "answer lines (VM 10, item 12): \"35일\" is never split over two lines (split at widths \(split))")
}
