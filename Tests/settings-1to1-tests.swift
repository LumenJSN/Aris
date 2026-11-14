// Tests for settings-look, the 1:1 rebuild (2026-11-13): the Settings window, sidebar, pages, switch, icons and
// the feature detail sheets to the measured numbers (qa/design-1111/settings-rea-0141). Reads the tokens, the builder,
// the catalogs and the sources; nothing of the user's is touched. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

private let oneRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func oneSource(_ path: String) -> String { (try? String(contentsOf: oneRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }
private let settingsDir = "Aris/components/Settings/"

func runSettings1to1Tests() {
    oneWindowTests()
    oneSidebarTests()
    onePageTests()
    oneIconTests()
    oneFeatureTests()
    oneSourceTests()
    oneTileTests()
}

private func oneTileTests() {
    // The measured AppIcon tile: radius round(size × .2237), the glyph at .46, the glass.
    let icon = oneSource(settingsDir + "ArisIconTile.swift")
    check(icon.contains("(size * 0.2237).rounded()") && icon.contains("size * 0.46, stroke: size >= 96 ? 1.8 : 2"), "tiles: squircle round(size × .2237), glyph × .46 at stroke 2 (1.8 from 96)")
    check(icon.contains(".white.opacity(0.34), location: 0") && icon.contains(".white.opacity(0.13), location: 0.2") && icon.contains(".white.opacity(0.02), location: 0.36")
          && icon.contains("152.0") && icon.contains("endRadiusFraction: 0.62") && icon.contains("y: size * 1.12"), "tiles: the glass's 152° sheen and its radial light at 112%")
    check(icon.contains(".init(0xffffff, 0.45)") && icon.contains(".init(0x000000, 0.1)") && icon.contains("spread: 1, shade: .init(0xffffff, 0.18)"), "tiles: the glass's three inset lines")
    check(icon.contains("Color.white.opacity(0.08) : Color.black.opacity(0.05)") && icon.contains("Color(arisHex: 0x1d1d1f) : .white")
          && icon.contains(".black.opacity(dark ? 0.5 : 0.16) : .clear, radius: elevated ? 18 : 0, y: elevated ? 18 : 0"), "tiles: plain and image fills, the elevated lift")
    check(oneSource(settingsDir + "ArisFeatureSheet.swift").contains("ArisIconTile(content.icon, size: ArisFeatureLook.icon, elevated: true)"), "tiles: the sheet's 88-pt icon is the elevated tile")
    check(oneSource(settingsDir + "ArisSkillsCards.swift").contains("ArisIconTile(look.symbol, size: size, fill: .tinted(look.tint))"), "tiles: a skill's icon is the gradient tile")
    check(oneSource(settingsDir + "ArisServicesSection.swift").components(separatedBy: "ArisIconTile(").count == 3, "tiles: connected services' rows carry tiles")
    let page = oneSource(settingsDir + "ArisSettingsPageView.swift")
    check(page.contains("ArisIconTile(size: 36, fill: .image)") && page.contains("case .symbol(let name):\n            ArisLineIcon(name, size: 20"),
          "tiles: an app's logo row has the image tile; settings rows keep their bare 20-pt glyph")
}

private func oneWindowTests() {
    typealias M = ArisSidebarMetrics
    check(M.windowSize == (width: 1080, height: 710) && M.windowRadius == 20 && M.trafficLights == (x: 18, y: 18),
          "window: 1080 × 710, rounded 20, traffic lights at 18, 18")
    check(M.cardInset == 7 && M.cardRadius == 13 && M.cardInset + M.cardRadius == M.windowRadius,
          "window: the content card inset 7, radius 13, concentric with the window's 20")
    let window = oneSource(settingsDir + "ArisSettingsWindow.swift")
    check(window.contains("view.material = .sidebar") && window.contains("view.blendingMode = .behindWindow") && window.contains("window.isOpaque = false")
          && window.contains("window.backgroundColor = .clear") && window.contains("view.layer?.cornerCurve = .continuous"),
          "window: transparent, the whole window one behind-window sidebar material rounded continuously")
    check(window.contains("material?.state = .active") && window.contains("material?.state = .inactive") && window.contains("\"_setCornerRadius:\"")
          && window.contains("guard window.responds(to: selector)"), "window: active while key, resting when not; its own corners at 20 where macOS offers it")
    check(window.contains("ArisSidebarMetrics.trafficLights.x + CGFloat(index) * stride"), "window: the traffic lights placed from 18, 18 in their own spacing")
}

private func oneSidebarTests() {
    typealias M = ArisSidebarMetrics
    check(M.width == 220 && M.padding == 16 && M.top == 40 && M.greetingGap == 16, "sidebar: 220 wide, px-4, the header pt-10 pb-4")
    check(M.row == 44 && M.rowGap == 4 && M.rowRadius == 12 && M.rowLeading == 15.5 && M.rowTrailing == 16 && M.iconGap == 12 && M.iconSize == 20 && M.labelSize == 14,
          "sidebar: items 44 tall, 4 apart, r12, 15.5 / 16 in, a 20-pt icon 12 from a 14-pt label")
    check(M.height() > M.windowSize.height, "sidebar: 14 pages at 44 are taller than the window, so the list scrolls (and fades at its end)")
    let theme = oneSource(settingsDir + "ArisSettingsTheme.swift")
    check(theme.contains("var sidebarTint: Color { pick(Color(arisHex: 0xf5f7fa, 0x26 / 255.0), Color(arisHex: 0x1a1d24, 0x29 / 255.0)) }"),
          "sidebar: the tint is #f5f7fa .149 / #1a1d24 .161 over the material")
    check(theme.contains("var navIdle: Color { pick(black(0.5), white(0.5)) }") && theme.contains("var navOn: Color { pick(black(0.9), white(0.98)) }"),
          "sidebar: idle .5 in both appearances, chosen .9 / .98")
    let sidebar = oneSource(settingsDir + "ArisSettingsSidebar.swift")
    let item = sidebar.components(separatedBy: "private struct ArisNavItem").last?.components(separatedBy: "struct ArisGlassHighlight").first ?? ""
    check(item.contains("weight: .medium") && !item.contains("current ? .medium : .regular") && !item.contains("navFill") && !item.contains("navHover"),
          "sidebar: the label is 500 in both states and nothing fills or brightens under the pointer")
    let glass = sidebar.components(separatedBy: "struct ArisGlassHighlight").last ?? ""
    check(glass.contains("ArisMenuLook.radioShadowsDark : ArisMenuLook.radioShadowsLight") && glass.contains(".opacity(hovering ? 1 : 0)")
          && glass.contains("-75.0"), "sidebar glass: the measured −75° fill and four shades in both appearances, the rim only under the pointer")
    check(!sidebar.contains("matchedGeometryEffect") && !sidebar.contains("value: nav.page)"), "sidebar glass: no slide between pages; the selection appears on the new item")
    let shell = oneSource(settingsDir + "ArisSettingsShell.swift")
    check(!shell.contains("Rectangle().fill(palette.hairline).frame(width: 1)") && shell.contains("palette.wash") && shell.contains("ArisSidebarMetrics.cardRadius"),
          "shell: no line between the sidebar and the content; the gutter's wash and the floating card")
}

private func onePageTests() {
    typealias M = ArisSettingsMetrics
    check(M.sectionGap == 32 && M.headingGap == 16 && M.cardGap == 16 && M.titleGap == 20 && M.cardRadius == 18 && M.rowInset == 20 && M.iconBox == 20 && M.iconGap == 12,
          "pages: sections 32 apart, a title 16 over its cards, cards 16 apart, rows p-5 with a 20-pt icon 12 from the words")
    check(M.sectionTitleSize == 20 && M.sectionTitleTracking == -0.2 && M.pageTitleSize == 22 && M.pageTitleTracking == -0.44,
          "pages: section titles 20 / 700 −0.01em, the page title 22 / 600 −0.02em")
    check(M.columnTop == 40 && M.columnLeading == 48 && M.columnMaxWidth == 800 && M.bottomFade == 80, "pages: the column 6 + 18 + 16 down, 48 in, at most 800 wide; an 80-pt fade")
    let rows = (0..<3).map { ArisSettingItem(id: "r\($0)", icon: .symbol("moon"), title: "r\($0)", control: .toggle(.muted, true)) }
    check(ArisSettingsLayout.blocks(ArisSettingSection(id: "a", rows: rows)).count == 3, "pages: each settings row is its own card")
    check(ArisSettingsLayout.blocks(ArisSettingSection(id: "b", grouped: true, rows: rows)).count == 1, "pages: a list stays one card")
    let keys = ArisSettingsBuilder.sections(.keys, ArisSettingsSnapshot())
    check(keys.allSatisfy { !$0.grouped } && ArisSettingsLayout.blocks(keys[0]).count == keys[0].rows.count, "단축키: one card per shortcut")
    let shell = oneSource(settingsDir + "ArisSettingsShell.swift")
    check(!shell.contains("Text(w.frame(nav.page.subtitle)).font"), "pages: the title carries no line under it")
    let controls = oneSource(settingsDir + "ArisSettingsControls.swift")
    check(controls.contains("minWidth: 35, minHeight: 35"), "key caps: 35 × 35")
    let theme = oneSource(settingsDir + "ArisSettingsTheme.swift")
    check(theme.contains("var settingsSwitchOn: Color { pick(Color(arisHex: 0x2d2d2d), .white) }")
          && theme.contains("var settingsSwitchOff: Color { pick(Color(arisHex: 0xd1d1d1), Color(arisHex: 0x4b4b4b)) }")
          && theme.contains("dark && on ? Color(arisHex: 0x2d2d2d) : .white") && theme.contains("timingCurve(0.4, 0, 0.2, 1, duration: 0.15)"),
          "switch: the settings rows' monochrome switch and its 150 ms")
    check(controls.contains("static let settingsTrack = CGSize(width: 32, height: 18.4)") && controls.contains("static let settingsThumb: CGFloat = 16")
          && controls.contains("var style = ArisSwitchStyle.settings"), "switch: 32 × 18.4 with a 16-pt thumb, the settings one by default")
    let skills = oneSource(settingsDir + "ArisSkillsPage.swift"), services = oneSource(settingsDir + "ArisServicesSection.swift")
    check(skills.contains("ArisSwitch(isOn: row.enabled, style: .store") && services.components(separatedBy: "style: .store").count == 3
          && skills.contains("ArisSwitch(isOn: on, label: \"스킬 기능\")"), "switch: list rows keep the green one; the 스킬 기능 setting takes the settings one")
}

private func oneIconTests() {
    for name in ArisLineIconData.glyphs.keys.sorted() {
        guard let glyph = ArisLineIconPath.glyph(name) else { check(false, "icons: \(name) parses"); continue }
        let box = glyph.stroke.boundingBoxOfPath.union(glyph.fill.isEmpty ? glyph.stroke.boundingBoxOfPath : glyph.fill.boundingBoxOfPath)
        if glyph.stroke.isEmpty && glyph.fill.isEmpty || box.minX < -0.5 || box.minY < -0.5 || box.maxX > 24.5 || box.maxY > 24.5 {
            check(false, "icons: \(name) draws inside its 24 grid (\(box))")
        }
    }
    check(ArisLineIconData.glyphs.count > 150, "icons: every glyph the settings use is bundled (\(ArisLineIconData.glyphs.count))")
    let mic = ArisLineIconPath.glyph("mic")?.stroke.boundingBoxOfPath ?? .zero
    check(abs(mic.minX - 5) < 0.01 && abs(mic.maxX - 19) < 0.01 && abs(mic.minY - 2) < 0.01 && abs(mic.maxY - 22) < 0.01, "icons: the mic's path, arc and rect land where its SVG puts them")
    check(ArisSettingsPage.allCases.allSatisfy { ArisLineIconPath.glyph($0.lineIcon) != nil }, "icons: every page has its line icon")
    check(ArisSettingsPage.allCases.allSatisfy { ArisLineIconPath.glyph($0.symbol) != nil }, "icons: every page's SF name stands for a glyph (search results)")
    var full = ArisSettingsSnapshot()
    full.permissions = [.init(id: "ax", title: "a", desc: "a", granted: false), .init(id: "screen", title: "s", desc: "s", granted: true)]
    full.reminders = .granted
    full.calendarAccess = .granted
    let symbols = ArisSettingsPage.allCases.flatMap { ArisSettingsBuilder.sections($0, full) }.flatMap(\.rows).compactMap { row -> String? in
        if case .symbol(let name) = row.icon { return name } else { return nil }
    }
    let missing = Set(symbols.filter { ArisLineIconPath.glyph($0) == nil })
    check(missing.isEmpty, "icons: every settings row's icon is a line glyph" + (missing.isEmpty ? "" : " (\(missing.sorted()))"))
    let looks = ArisSkillLook.table.map(\.1.symbol) + ArisTeammateScope.allCases.map(ArisTeamSymbols.scope)
    let lost = looks.filter { ArisLineIconPath.glyph($0) == nil }
    check(lost.isEmpty, "icons: the skill tiles' and the teammate scopes' glyphs are bundled" + (lost.isEmpty ? "" : " (\(lost))"))
    for custom in ["aris-notch", "aris-side-notch", "aris-pill", "aris-star"] { check(ArisLineIconData.glyphs[custom] != nil, "icons: Aris's own \(custom)") }
    let licences = oneSource("THIRD_PARTY_LICENSES")
    check(licences.contains("Lucide") && licences.contains("ISC License"), "icons: the icon set's ISC notice is in THIRD_PARTY_LICENSES")
}

private func oneFeatureTests() {
    check(ArisFeature.allCases.count == 4, "feature sheets: 컴퓨터 제어, 스킬, 알림 카드, 저장된 단계")
    var full = ArisSettingsSnapshot()
    full.savedSteps = []
    for feature in ArisFeature.allCases {
        let c = feature.content
        check((3...4).contains(c.cells.count) && !c.tries.isEmpty && !c.facts.isEmpty && !c.about.isEmpty && ArisLineIconPath.glyph(c.icon) != nil,
              "feature sheets: \(feature.rawValue) has its hero, info strip, previews, about, tries and information")
        check(c.cells.allSatisfy { ($0.icon == nil) != ($0.value == nil) && ($0.icon.map { ArisLineIconPath.glyph($0) != nil } ?? true) },
              "feature sheets: \(feature.rawValue)'s cells each show an icon or a value")
        if feature != .skills {
            let sections = ArisSettingsBuilder.sections(feature.page, full)
            check(sections.first { $0.id == feature.sectionID }?.feature == feature && sections.filter { $0.feature != nil }.count == 1,
                  "feature sheets: \(feature.rawValue)'s 알아보기 link sits at the end of its section's title, and nowhere else on the page")
            check(!sections.flatMap(\.rows).contains { $0.id.hasPrefix("feature.") }, "feature sheets: \(feature.rawValue)'s page has no extra row for it")
        }
    }
    let skills = oneSource(settingsDir + "ArisSkillsPage.swift")
    check(skills.components(separatedBy: "ArisFeatureLink(feature: .skills)").count == 3 && !skills.contains("ArisFeatureRow("),
          "feature sheets: the 스킬 page keeps its layout and opens its sheet from the intro card and the off card")
    let file = oneRoot.appendingPathComponent(settingsDir + "Settings.xcstrings")
    var table = ArisSettingsCopyTable(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data()))
    let words = ArisFeature.allCases.flatMap { $0.content.strings + [$0.rowLine] } + ["미리 보기", "소개", "이렇게 말해 보세요", "정보", "닫기", "자세히 보기"]
    var untranslated: [String] = []
    for korean in words where korean.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) && table.english(korean) == nil {
        untranslated.append(korean)
    }
    check(untranslated.isEmpty, "feature sheets: everything they say is in English too" + (untranslated.isEmpty ? "" : " (\(untranslated.prefix(3)))"))
    typealias L = ArisFeatureLook
    check(L.width == 620 && L.radius == 20 && L.maxHeightShare == 0.86 && L.bodyTop == 32 && L.bodyLeading == 36 && L.bodyTrailing == 40 && L.closeInset == 24,
          "feature sheets: 620 wide, r20, at most 86% tall, the body 32 / 36 / 40 in, the close button 24 from the corner")
    check(L.icon == 88 && L.iconRadius == 20 && L.glyph == 40 && L.titleSize == 28 && L.lineSize == 15 && L.sectionGap == 28 && L.cellMinWidth == 104,
          "feature sheets: an 88-pt icon (r20, a 40-pt glyph), a 28-pt title, a 15-pt line, sections 28 apart, cells at least 104")
    check(L.tile == CGSize(width: 420, height: 244) && L.tileRadius == 26 && L.loop == 9, "feature sheets: 420 × 244 tiles, r26, a 9 s loop")
    check(L.notchClosed == CGSize(width: 128, height: 22) && L.notchListening == CGSize(width: 292, height: 34) && L.notchAnswerWidth == 300,
          "feature sheets: the notch closed 128 × 22, listening 292 × 34, answering 300 wide")
    let at = { (t: Double) in L.notch(at: t) }
    check(at(0).to == 0 && at(0.09).to == 1 && at(0.15) == (1, 1, 0) && at(0.22).to == 2 && at(0.5) == (2, 2, 0) && at(0.9).to == 1 && at(0.96).to == 0 && at(0.99) == (0, 0, 0),
          "feature sheets: closed, listening by 11.5%, the answer by 24.5%, held to 88.5%, closed by 97.5%")
    let scenes = oneSource(settingsDir + "ArisFeatureScenes.swift")
    check(scenes.contains("if still || ArisSettingsMotion.reduced") && scenes.contains("ArisWallpaper()") && !scenes.contains("NSImage(") && !scenes.contains("Image(\""),
          "feature sheets: the demo is drawn in code on Aris's own wallpaper, and still under Reduce Motion")
}

private func oneSourceTests() {
    // The measured product is named nowhere in what this rebuild added (its name is put together here).
    let name = "voice" + "os"
    let files = ["ArisLineIcon.swift", "ArisLineIconPath.swift", "ArisLineIconData.swift", "ArisWallpaper.swift", "ArisFeatureCatalog.swift", "ArisFeatureSheet.swift",
                 "ArisFeatureScenes.swift", "ArisSettingsShell.swift", "ArisSettingsWindow.swift", "ArisSettingsTheme.swift", "ArisSettingsSidebar.swift", "ArisSettingsPageView.swift",
                 "ArisSettingsControls.swift"]
    let named = files.filter { oneSource(settingsDir + $0).lowercased().contains(name) }
    check(named.isEmpty, "settings 1:1: no other product is named in the rebuilt files" + (named.isEmpty ? "" : " (\(named))"))
    let icons = files.prefix(7).filter { oneSource(settingsDir + $0).lowercased().contains("lucide") }
    check(icons.isEmpty, "settings 1:1: the icon set is named only in THIRD_PARTY_LICENSES")
    let settings = (try? FileManager.default.contentsOfDirectory(atPath: oneRoot.appendingPathComponent(settingsDir).path)) ?? []
    let symbols = settings.filter { $0.hasSuffix(".swift") && $0 != "ArisLineIcon.swift" && $0 != "ArisSettingsArt.swift" }
        .filter { oneSource(settingsDir + $0).contains("Image(systemName:") }
    check(symbols.isEmpty, "icons: the Settings window draws line glyphs, not SF Symbols" + (symbols.isEmpty ? "" : " (\(symbols))"))
}
