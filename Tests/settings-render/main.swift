// Offscreen renders of the redesigned settings window (the owner's pick: mockup settings-redesign.html C, with B's
// sidebar): every page, light and dark, as the 1000 × 680 window and as the whole page; plus a search, a landed
// search result, an open dropdown and the language sheet. The pages are the app's own views fed the mockup's
// stand-in values; the star and the faces are their baked sprites (BotAvatarsKit, as the app bakes them). Nothing is
// read from ~/.config/aris, nothing is saved, nothing touches the screen.
import AppKit
import BotAvatarsKit
import SwiftUI

let args = CommandLine.arguments
let outDir = args.count > 1 ? args[1] : NSTemporaryDirectory()
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
_ = NSApplication.shared

// `render OUT en <Settings.xcstrings>` draws the window as an English Mac does: the frame in English, and each page
// that has all its English (ArisSettingsCopy) in English.
let english = args.count > 3 && args[2] == "en"
if english, let catalog = FileManager.default.contents(atPath: args[3]) { ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: catalog)) }
func wording(_ page: ArisSettingsPage) -> ArisSettingsWording { .make(page: page, english: english) }

// MARK: - Baked art

@MainActor final class Bakery {
    static let shared = Bakery()
    var cells: [String: CGImage] = [:]

    private func name(_ look: ArisCharacterLook, _ size: CGFloat) -> String { "\(look.type)|\(look.colorHex ?? "-")|\(look.shading)|\(ArisSpriteLook.bakeSize(size))" }

    func bake(_ look: ArisCharacterLook, _ size: CGFloat) async {
        let key = name(look, size)
        guard cells[key] == nil else { return }
        let sprite = ArisSpriteLook(type: look.type, colorHex: look.colorHex, shading: look.shading, size: ArisSpriteLook.bakeSize(size), scale: 2, dark: true)
        guard let sheet = await ArisSpriteBaker.bake(ArisSpriteStore.key(sprite, .still)), let cell = sheet.image.cropping(to: sheet.grid.pixelRect(0)) else {
            print("bake failed: \(key)"); return
        }
        cells[key] = cell
    }

    func view(_ look: ArisCharacterLook, _ size: CGFloat) -> AnyView {
        guard let cell = cells[name(look, size)] else { return AnyView(Color.clear.frame(width: size, height: size)) }
        return AnyView(Color.clear.frame(width: size, height: size).overlay {
            Image(decorative: cell, scale: 2).resizable().interpolation(.high)
                .frame(width: size * BOT_AVATAR_OVERSCAN, height: size * BOT_AVATAR_OVERSCAN)
                .offset(y: -BOT_AVATAR_RISE * size)
        })
    }
}

let art = ArisSettingsArt(star: { size in MainActor.assumeIsolated { Bakery.shared.view(.main, size) } },
                          aris: { _, size in MainActor.assumeIsolated { Bakery.shared.view(.main, size) } },
                          face: { look, size, _ in MainActor.assumeIsolated { Bakery.shared.view(look, size) } })

// Aris's face (ArisFace) is kept in a defaults suite of the render's own, emptied before and after: never Aris's.
// By its path in the temporary folder: a bare name is written into the user's real ~/Library/Preferences.
let faceSuite = NSTemporaryDirectory() + "aris-settings-render-face"
ArisFace.store = UserDefaults(suiteName: faceSuite)!
ArisFace.store.removePersistentDomain(forName: faceSuite)

// MARK: - Stand-ins (mockup `S`)

@MainActor final class FakeTeam: ArisTeamSource {
    @Published var teammates: [ArisTeammate] = [
        ArisTeammate(id: "claude-code", name: "코디", role: "Claude Code 담당", look: ArisCharacterLook(type: "cat", colorHex: nil, shading: "fabric"), brain: "claude", memoryFile: ""),
        ArisTeammate(id: "mong", name: "몽실", role: "메일 담당 · 초안만", look: ArisCharacterLook(type: "cloud", colorHex: nil, shading: "fabric"), brain: "codex", memoryFile: ""),
        ArisTeammate(id: "ssuk", name: "쑥", role: "메모 정리", look: ArisCharacterLook(type: "clover", colorHex: nil, shading: "fabric"), brain: "codex", memoryFile: ""),
    ]
    var load = ArisTeamLoad.ready
    var notice: String?
    var brains: [String: Bool] = [:]
    var notes: [String: [ArisNoteRow]] = [:]
    var knowhow: [ArisNoteRow] = []
    func apply(_ list: [ArisTeammate]) { teammates = list }
    func refresh() {}
    func refreshExtras() {}
    func loadNotes(_ id: String) {}
    func forgetNote(_ id: String, note: String?) {}
    func forgetKnowhow(_ note: String?) {}
    func login(_ brain: String) {}
    func keep(_ note: String, teammate: String?) {}
    func takeOpenOn() -> String? { nil }
}

@MainActor func snapshot() -> ArisSettingsSnapshot {
    var s = ArisSettingsSnapshot()
    s.hasVoiceModel = true
    s.talkCaps = ["⌥", "Space"]
    s.languages = [.init(id: "ko", title: "한국어"), .init(id: "en", title: "English")]
    s.hasVoiceKey = true
    s.voiceName = "Rachel"
    s.words = 12
    s.reminders = .granted
    s.reminderLists = [.init(id: "personal", name: "미리 알림", source: "iCloud", colorHex: "#FF9500", included: true),
                       .init(id: "home", name: "집", source: "iCloud", colorHex: "#34C759", included: true),
                       .init(id: "work", name: "회사", source: "iCloud", colorHex: "#007AFF", included: false)]
    s.defaultList = "personal"
    s.calendarAccess = .granted
    s.calendars = [.init(id: "home", name: "집", source: "iCloud", colorHex: "#34C759", included: true),
                   .init(id: "work", name: "회사", source: "iCloud", colorHex: "#007AFF", included: true),
                   .init(id: "gme", name: "개인", source: "Google", colorHex: "#FF9500", included: true),
                   .init(id: "gteam", name: "팀 일정", source: "Google", colorHex: "#AF52DE", included: false)]
    s.googleCalendars = 2
    s.services = [.init(id: "claude", title: "Claude", detail: "the user · Max", status: "연결됨", tone: .ok),
                  .init(id: "codex", title: "Codex", detail: "ChatGPT Pro", status: "연결됨", tone: .ok),
                  .init(id: "antigravity", title: "Antigravity", detail: "Gemini", status: "다시 로그인해 주세요", tone: .warn)]
    s.permissions = [.init(id: "ax", title: "손쉬운 사용", desc: "버튼·입력칸을 찾아 누르고 글자를 입력해요.", granted: true),
                     .init(id: "screen", title: "화면 기록", desc: "지금 보는 화면을 같이 봐요.", granted: true),
                     .init(id: "mic", title: "마이크", desc: "말을 들어요.", granted: false)]
    s.standing = [.init(id: "1", title: "메시지 보내기", desc: "대상: 엄마 · 메시지", symbol: "message"),
                  .init(id: "2", title: "미리 알림", desc: "대상: 장보기", symbol: "checkmark.shield"),
                  .init(id: "3", title: "Notion 일정 만들기", desc: "대상: 팀 캘린더 · Notion", symbol: "calendar")]
    s.standingLoaded = true
    s.hiddenSides = true
    s.clipCaps = ["⌥", "⌘", "C"]
    s.theme = "light"
    s.settingsIcon = false
    s.screens = [.init(id: "builtin", title: "내장 Retina 디스플레이"), .init(id: "studio", title: "Studio Display")]
    s.screen = "builtin"
    s.answerCaps = ["⌥", "R"]
    s.notchCaps = ["⌥", "⌘", "N"]
    s.peekCaps = ["⌥", "⌘", "M"]
    s.versionLine = "버전 2.1.0 (412)"
    s.teammateNames = ["코디", "몽실", "쑥"]
    // ARIS_RENDER_NO_AI=1: a new Mac with no AI set up, where 기본으로 답하는 AI marks all four as missing (its widest).
    if ProcessInfo.processInfo.environment["ARIS_RENDER_NO_AI"] == "1" {
        s.brains = ArisBrain.allCases.map { .init(id: $0.rawValue, title: $0.shortTitle) }
    }
    return s
}

@MainActor enum Fakes {
    static let keys = ArisKeysModel(actions: .init(read: { $0 == "elevenlabs-key" ? "sk_7f2c00000000a91c" : nil }, save: { _, _ in nil }, delete: { _ in nil }))
    static let team = FakeTeam()
}

@MainActor func handlers() -> ArisSettingsHandlers {
    var h = ArisSettingsHandlers()
    h.custom = { item in
        guard case .custom(let kind) = item.control else {
            if case .trailing("voicePicker") = item.control {
                return AnyView(ArisSettingsButton(title: "Rachel", minWidth: 150, trailingSymbol: "chevron.down") {})
            }
            return nil
        }
        if kind == "about" { return AnyView(ArisAboutCard(version: item.desc ?? "")) }
        if let key = ArisKeysModel.keys.first(where: { "apiKey:" + $0.name == kind }) { return AnyView(ArisKeyRow(key: key, model: Fakes.keys)) }
        return nil
    }
    h.logo = { id in AnyView(Text(["claude": "C", "codex": "G", "antigravity": "A"][id] ?? "?").font(.system(size: 12, weight: .bold))) }
    return h
}

@MainActor func plan(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> ArisNotchPreviewPlan {
    var input = ArisNotchPreviewInput()
    input.page = page
    input.wakeWord = s.wakeWord
    input.talkCaps = s.talkCaps
    input.speedTitle = "보통"
    input.voiceName = s.voiceName
    input.heightMode = s.heightMode
    input.customHeight = s.notchHeight
    input.hoverOpens = s.hover
    input.circleGesture = s.circle
    input.seesScreen = s.seesScreen
    input.teammateNames = s.teammateNames
    return ArisNotchPreviewPlan.make(input)
}

/// The 팀원 page opens on 몽실, or (`face`) on Aris's own row, with the notice when a teammate was moved.
nonisolated(unsafe) var teamSelected = "mong"
nonisolated(unsafe) var teamMoved: ArisFaceDetail.Moved?

@MainActor func pageBody(_ page: ArisSettingsPage, _ s: ArisSettingsSnapshot) -> AnyView {
    page == .team ? AnyView(ArisTeamPage(team: Fakes.team, selected: teamSelected, moved: teamMoved)) : AnyView(ArisSettingsPageView(sections: wording(page).sections(ArisSettingsBuilder.sections(page, s))))
}

@MainActor func window(_ page: ArisSettingsPage, dark: Bool, s: ArisSettingsSnapshot, menus: ArisSettingMenus? = nil) -> some View {
    ArisSettingsShell(nav: .shared, menus: menus, status: ArisSettingsCaption.greeting(agentDown: false, missingPermissions: 0),
                      plan: plan(page, s), vibrancy: false) {
        pageBody(page, s)
    }
    .environment(\.arisWords, wording(page))
    .frame(width: 1000, height: 680)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
}

@MainActor func styled<V: View>(_ view: V, dark: Bool) -> some View {
    view
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.arisSettingsStill, true)
        .environment(\.arisSettingsArt, art)
        .environment(\.arisSettingsHandlers, handlers())
}

@MainActor func save<V: View>(_ view: V, _ name: String, dark: Bool) {
    let renderer = ImageRenderer(content: styled(view, dark: dark))
    renderer.scale = 2
    guard let cg = renderer.cgImage else { print("\(name): no image"); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    let path = (outDir as NSString).appendingPathComponent(name + ".png")
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("\(name).png \(cg.width / 2)×\(cg.height / 2)")
}

/// The page's whole column (stage, title, every section) on the pane, for comparing with the mockup's.
@MainActor func column(_ page: ArisSettingsPage, dark: Bool, s: ArisSettingsSnapshot) -> some View {
    let palette = ArisPalette(dark: dark)
    return VStack(alignment: .leading, spacing: 0) {
        Group { if page == .team { ArisFaceStageView(shownMode: .rest) } else { ArisNotchPreview(plan: plan(page, s)) } }.padding(.bottom, 22)
        HStack(alignment: .firstTextBaseline) {
            Text(wording(page).frame(page.title)).font(.system(size: 22, weight: .semibold)).tracking(-0.44).foregroundStyle(palette.title)
            Spacer()
            Text(wording(page).frame(page.subtitle)).font(.system(size: 12)).foregroundStyle(palette.desc)
        }
        .padding(.bottom, 12)
        pageBody(page, s)
    }
    .environment(\.arisWords, wording(page))
    .frame(width: 700, alignment: .leading)
    .padding(.horizontal, 40).padding(.top, 44).padding(.bottom, 60)
    .background(palette.pane)
}

@MainActor func run() async {
    // Aris (the star, and the cat the user picks in the face renders) at every size the window shows it, and each face the
    // pages show.
    // feat-2: with ARIS_RENDER_FEAT2 set, only the rows built there are drawn (the night hours in each state,
    // the teammate's terminal, the learned suggestions), light and dark, and nothing else.
    if ProcessInfo.processInfo.environment["ARIS_RENDER_FEAT2"] != nil {
        renderFeat2()
        exit(0)
    }
    let catFace = ArisCharacterLook(type: "cat", colorHex: nil, shading: "fabric")
    var looks: [(ArisCharacterLook, CGFloat)] = []
    for face in [ArisCharacterLook.star, catFace] { looks += [20, 22, 34, 48, 30, 44].map { (face, $0) } }
    for mate in Fakes.team.teammates { looks += [(mate.look, 20), (mate.look, 30), (mate.look, 44)] }
    looks += [(.star, 30)]
    let picked = Fakes.team.teammates[1].look
    for type in ArisFace.pickableTypes(aris: "star") { looks.append((ArisCharacterLook(type: type, colorHex: type == picked.type ? picked.colorHex : nil, shading: picked.shading), 34)) }
    for hex in ArisCharacterLook.colorChoices(for: picked.type) { looks.append((ArisCharacterLook(type: picked.type, colorHex: hex, shading: picked.shading), 24)) }
    for face in [ArisCharacterLook.star, catFace] {
        for type in ArisFace.choices { looks.append((ArisCharacterLook(type: type, colorHex: nil, shading: "fabric"), 32)) }
        for hex in ArisFace.colorChoices(for: face.type) { looks.append((ArisCharacterLook(type: face.type, colorHex: hex, shading: "fabric"), 24)) }
        for type in ArisFace.pool(aris: face.type) { looks.append((ArisCharacterLook(type: type, colorHex: nil, shading: "fabric"), 24)) }
    }
    for (look, size) in looks { await Bakery.shared.bake(look, size) }

    let s = snapshot()
    for page in ArisSettingsPage.allCases {
        for dark in [false, true] {
            ArisSettingsNav.shared.page = page
            ArisSettingsNav.shared.query = ""
            let theme = dark ? "dark" : "light"
            save(window(page, dark: dark, s: s), "window-\(page.rawValue)-\(theme)", dark: dark)
            save(column(page, dark: dark, s: s), "page-\(page.rawValue)-\(theme)", dark: dark)
        }
    }
    // Aris's face (Settings A): its row open, wearing the star; then the cat, 코디 moved to the star, the notice up.
    // The 미리보기 strip in each of its three modes.
    teamSelected = ArisTeamEditing.mainId
    let team = Fakes.team.teammates
    for (name, look) in [("star", ArisCharacterLook.star), ("cat", catFace)] {
        ArisFace.set(look)
        let change = ArisFace.moving(team, to: look)
        Fakes.team.teammates = change.team
        teamMoved = change.moved.first.map { ArisFaceDetail.Moved(id: $0.id, text: ArisFace.notice(moved: $0, aris: look.type), action: ArisFace.noticeAction(moved: $0)) }
        for dark in [false, true] {
            ArisSettingsNav.shared.page = .team
            let theme = dark ? "dark" : "light"
            save(window(.team, dark: dark, s: s), "face-window-\(name)-\(theme)", dark: dark)
            save(column(.team, dark: dark, s: s), "face-page-\(name)-\(theme)", dark: dark)
        }
        for mode in ArisFaceStage.Mode.allCases {
            save(ArisFaceStageView(shownMode: mode).frame(width: 620).padding(20).background(ArisPalette(dark: false).pane), "face-stage-\(name)-\(mode)", dark: false)
        }
    }
    Fakes.team.teammates = team
    teamMoved = nil
    teamSelected = "mong"
    ArisFace.store.removePersistentDomain(forName: faceSuite)

    // As a new English Mac has them (VM run 2026-11-11): the teammates page with only the seeded Claude Code and Aris's
    // own row open, 목소리 · 언어 with no ElevenLabs key and English alone, and a search whose results have long names.
    if english {
        Fakes.team.teammates = [.claudeCode]
        await Bakery.shared.bake(ArisTeammate.claudeCode.look, 30)
        teamSelected = ArisTeamEditing.mainId
        ArisSettingsNav.shared.page = .team
        save(window(.team, dark: false, s: s), "vm2-team-seeded", dark: false)
        Fakes.team.teammates = team
        teamSelected = "mong"
        var fresh = s
        fresh.hasVoiceKey = false
        fresh.voiceName = ArisNotchPreviewInput.macVoice
        fresh.languages = ArisLanguages.starting(system: ["en-US"]).map { .init(id: $0, title: ArisLanguages.named($0)?.native ?? $0) }
        ArisSettingsNav.shared.page = .voice
        save(window(.voice, dark: false, s: fresh), "vm2-voice-new-mac", dark: false)
        ArisSettingsNav.shared.page = .aris
        ArisSettingsNav.shared.query = "screen"
        save(window(.aris, dark: false, s: s), "vm2-search-screen", dark: false)
        ArisSettingsNav.shared.query = "api key"
        save(window(.aris, dark: false, s: s), "vm2-search-api-key", dark: false)
        ArisSettingsNav.shared.query = ""
    }

    // A search, typed.
    for dark in [false, true] {
        ArisSettingsNav.shared.page = .aris
        ArisSettingsNav.shared.query = "단축키"
        save(window(.aris, dark: dark, s: s), "state-search-\(dark ? "dark" : "light")", dark: dark)
    }
    ArisSettingsNav.shared.query = ""
    // A result landed: 말하기 속도 on 목소리 · 언어, highlighted.
    for dark in [false, true] {
        ArisSettingsNav.shared.go(.voice, anchor: "voice.speed")
        save(window(.voice, dark: dark, s: s), "state-landed-\(dark ? "dark" : "light")", dark: dark)
    }
    // The 표시 방식 dropdown.
    for dark in [false, true] {
        ArisSettingsNav.shared.page = .general
        let menus = ArisSettingMenus()
        menus.toggle(ArisSettingMenu(key: .displayMode, title: "표시 방식", options: s.displayModes, selected: s.displayMode,
                                     anchor: CGRect(x: 740, y: 479, width: 200, height: 40)))
        save(window(.general, dark: dark, s: s, menus: menus), "state-dropdown-\(dark ? "dark" : "light")", dark: dark)
    }
    // 언어 추가.
    for dark in [false, true] {
        var languages = ["ko", "en"]
        let binding = Binding(get: { languages }, set: { languages = $0 })
        let sheet = ArisLanguageSheet(languages: binding, close: {}).frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(ArisPalette(dark: dark).modal))
            .padding(40).background(ArisPalette(dark: dark).backdrop)
        save(sheet, "sheet-languages-\(dark ? "dark" : "light")", dark: dark)
    }
}

// MARK: - Where a page opens (ARIS_RENDER_SCROLL=1)

/// The window as the app draws it (a real scroll view, not the still column), following the page that is open.
struct ScrollProbeWindow: View {
    @ObservedObject var nav = ArisSettingsNav.shared
    let s: ArisSettingsSnapshot

    var body: some View {
        window(nav.page, dark: false, s: s)
            .environment(\.colorScheme, .light)
            .environment(\.arisSettingsArt, art)
            .environment(\.arisSettingsHandlers, handlers())
    }
}

/// Every scroll view under `view`, the tallest content first (the content pane's; the sidebar's list is short).
@MainActor func scrollViews(_ view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = []
    func walk(_ view: NSView) {
        if let scroll = view as? NSScrollView { found.append(scroll) }
        view.subviews.forEach(walk)
    }
    walk(view)
    return found.sorted { ($0.documentView?.frame.height ?? 0) > ($1.documentView?.frame.height ?? 0) }
}

/// VM run 2026-11-11, bug 11: a page opened where the page before it had been scrolled to. The window is hosted in a
/// window that is never shown, its content pane scrolled to the end, and another page opened: by the sidebar (it must
/// start at the top) and by a jump to a row (it must land on that row). Prints what the scroll view says.
@MainActor func scrollProbe() async {
    let hosting = NSHostingView(rootView: ScrollProbeWindow(s: snapshot()))
    let offscreen = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 1000, height: 680), styleMask: [.borderless], backing: .buffered, defer: true)
    offscreen.contentView = hosting
    func settle(_ seconds: Double) async {
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .seconds(seconds))
        hosting.layoutSubtreeIfNeeded()
    }
    func pane() -> NSScrollView? { scrollViews(hosting).first }
    func offset() -> CGFloat { pane()?.contentView.bounds.origin.y ?? -1 }
    func toEnd() {
        guard let pane = pane(), let document = pane.documentView else { return }
        pane.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.frame.height - pane.contentView.bounds.height)))
        pane.reflectScrolledClipView(pane.contentView)
    }
    var failed = 0
    func report(_ ok: Bool, _ line: String) {
        if !ok { failed += 1 }
        print((ok ? "ok " : "FAIL ") + line)
    }

    ArisSettingsNav.shared.page = .notch
    await settle(0.5)
    toEnd()
    await settle(0.3)
    let scrolled = offset()
    report(scrolled > 200, "the 노치 page can be scrolled to its end (offset \(Int(scrolled)))")

    ArisSettingsNav.shared.go(.control)
    await settle(0.8)
    report(offset() == 0, "컴퓨터 제어 opened from the sidebar starts at the top (offset \(Int(offset())))")

    toEnd()
    await settle(0.3)
    ArisSettingsNav.shared.go(.aris)
    await settle(0.8)
    report(offset() == 0, "대화 opened after 컴퓨터 제어 was scrolled to its end starts at the top (offset \(Int(offset())))")

    ArisSettingsNav.shared.go(.notch, anchor: "notch.tab.calendar")
    await settle(1.5)
    report(offset() > 200, "a jump to a row far down another page still lands on that row (offset \(Int(offset())))")

    ArisSettingsNav.shared.go(.notch, anchor: "notch.hover")
    await settle(1.5)
    report(offset() < 200, "a jump to a row on the page that is open scrolls to it (offset \(Int(offset())))")
    // Final check on a new Mac: 5 of 13 pages opened part-way down when the page before had been scrolled (AI
    // services at its end; Voice, Memory, Music · Shelf, General). Every page is opened from the sidebar after the
    // page before it was scrolled to its end, in both directions through the list, and must start at its top; the
    // offset is read again a moment later, since a page whose rows arrive late used to slide after it had opened.
    let pages = ArisSettingsPage.allCases
    let back = Array(pages.reversed())
    for (from, to) in Array(zip(pages, pages.dropFirst())) + Array(zip(back, back.dropFirst())) {
        ArisSettingsNav.shared.go(from)
        await settle(0.6)
        toEnd()
        await settle(0.3)
        let before = offset()
        ArisSettingsNav.shared.go(to)
        await settle(0.35)
        let early = offset()
        await settle(0.9)
        report(early == 0 && offset() == 0, "\(to) opened after \(from) was scrolled to its end (offset \(Int(before))) starts at the top and stays there (offset \(Int(early)), then \(Int(offset())))")
    }
    print(failed == 0 ? "SCROLL PROBE PASSED" : "SCROLL PROBE: \(failed) FAILED")
    exit(failed == 0 ? 0 : 1)
}

Task { @MainActor in
    if ProcessInfo.processInfo.environment["ARIS_RENDER_SCROLL"] == "1" { await scrollProbe() }
    await run()
    exit(0)
}
RunLoop.main.run()

/// The wake word's small line (ArisWakeRest.swift, which needs the wake word's own files to compile).
enum ArisWakeHonesty {
    static let note = "이름을 부르면 들어요"
    static let noteUntrained = "이름을 부르면 들어요 · 아직 목소리를 배우지 않았어요"
}

/// The 한 일 tab's name for main Aris (ArisActivityTimeline.swift, which needs the whole session to compile).
enum ArisActivityTab {
    static let mainName = "Aris"
    static func paletteIndex(_ name: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 } % count
    }
}


/// The rows built on feat-2, each on the settings window's own background.
@MainActor func renderFeat2() {
    var s = snapshot()
    func draw(_ sections: [ArisSettingSection], page: ArisSettingsPage, _ name: String) {
        for dark in [false, true] {
            let palette = ArisPalette(dark: dark)
            let view = ArisSettingsPageView(sections: wording(page).sections(sections)).environment(\.arisWords, wording(page))
                .frame(width: 700).padding(28).background(dark ? Color(white: 0.13) : Color(white: 0.96))
            _ = palette
            save(view, "feat2-\(name)-\(dark ? "dark" : "light")", dark: dark)
        }
    }
    for (name, stored) in [("quiet-preset", "23-7"), ("quiet-custom", "22:30-6:00"), ("quiet-same", "7:00-7:00"), ("quiet-off", "off")] {
        s.quietHours = stored
        draw(ArisSettingsBuilder.sections(.aris, s).filter { $0.id == "aris.alerts" }, page: .aris, name)
    }
    draw([ArisTerminalSetting.section(pinned: "auto", installed: [.terminal, .iTerm, .ghostty, .warp])], page: .team, "terminal")
    draw([ArisDropLearnedSetting.section(4)], page: .memory, "drop-learned")
}
