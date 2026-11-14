// Tests for settings-look (2026-11-13): the settings window's menus, its rows' select and the 쓰는 언어 picker
// to the measured numbers (ArisMenuLook): the panel, its items, separator and label, a settings row's radio list (no
// check, the chosen row lit, at least 220 wide, 8 under its button, at most 320 tall), the settings select button, and
// the language dialog. Reads the tokens, the builder, the catalog file and the sources; nothing of the user's is touched.
// Called from main.swift; uses its check().
import Foundation

private let lookRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func lookSource(_ path: String) -> String { (try? String(contentsOf: lookRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }
private typealias L = ArisMenuLook
private func shade(_ hex: UInt32, _ alpha: Double = 1) -> ArisMenuLook.Shade { .init(hex, alpha) }

func runSettingsLookTests() {
    lookPanelTests()
    lookSelectTests()
    lookSheetTests()
    lookLanguageRowTests()
    lookSourceTests()
}

private func lookPanelTests() {
    check(L.radius == 16 && L.inset == 8, "menu: rounded-2xl and p-2 (16, 8)")
    check(L.shadow == .init(y: 25, blur: 50, spread: -12, shade: shade(0x000000, 0.1)), "menu: one shadow-2xl at black 10%, the same in dark")
    check(L.pageGap == 4 && L.settingsGap == 8, "menu: 4 under the AI 서비스 select (sideOffset 4), 8 under a settings row's (the primitive's default)")
    check(L.settingsMinWidth == 220 && L.settingsMaxHeight == 320 && L.pageMaxHeight == 300 && L.edge == 12,
          "menu: a settings row's at least 220 wide and at most 320 tall, the page's at most 300, 12 from the window")
    check(!L.animates, "menu: no entrance and no exit (the measured animate classes have no rule)")
    check(L.rowRadius == 8 && L.rowPaddingH == 12 && L.rowPaddingV == 10 && L.rowFont == 14 && L.disabledOpacity == 0.4,
          "menu items: rounded-lg px-3 py-2.5 text-sm, disabled at .4")
    check(L.rowHover == .init(light: shade(0xf3f4f6), dark: shade(0xffffff, 0.1)), "menu items: hover gray-100 / white 10%")
    check(L.checkBox == 16, "menu items: the AI 서비스 check is h-4 w-4")
    check(L.radioEdge == .init(light: shade(0xe6f5ff, 0.08), dark: shade(0x8c96aa, 0.05)) && L.radioMiddle == .init(light: shade(0xffffff, 0.2), dark: shade(0xffffff, 0.08)),
          "menu: a settings row's chosen item is the left-to-right glass sheen")
    check(L.radioShadowsLight.count == 4 && L.radioShadowsLight[2] == .init(y: 4, blur: 2, spread: -2, shade: shade(0x1e1e1e, 0.15))
          && L.radioShadowsLight[3] == .init(y: 0, blur: 1.6, spread: 4, shade: shade(0xd2ebff, 0.2), inset: true)
          && L.radioShadowsDark[0] == .init(y: 1, blur: 3, spread: 0, shade: shade(0x000000, 0.8), inset: true)
          && L.radioShadowsDark[3] == .init(y: 1.5, blur: 2, spread: 1.5, shade: shade(0xffffff, 0.24), inset: true),
          "menu: the chosen item's four shades, light and dark")
    check(L.separatorMargin == 6 && L.separator == .init(light: shade(0xe5e7eb), dark: shade(0xffffff, 0.1)), "menu: separator my-1.5, gray-200 / white 10%")
    check(L.labelFont == 12 && L.labelTracking == 0.05 && L.labelPaddingH == 12 && L.labelPaddingV == 8 && L.label == .init(light: shade(0x6a7282), dark: shade(0x99a1af)),
          "menu: group label text-xs/600 tracking-wider, px-3 py-2, gray-500 / gray-400")

    let options = [ArisSettingOption(id: "system", title: "시스템 언어"), ArisSettingOption(id: "ko", title: "한국어")]
    let menu = ArisAIMenu.choices(options, selected: "ko")
    check(menu.radio && menu.items.map(\.checked) == [false, true], "menu: a settings row's choices are a radio list with the chosen one marked")
    check(!ArisAIMenu(entries: [.item(ArisAIMenuItem(id: "a", title: "A", checked: true))]).radio && menu.filtered(by: "한").radio,
          "menu: the AI 서비스 page's menus keep the check; a filtered radio list stays one")
}

private func lookSelectTests() {
    check(L.selectPaddingH == 16 && L.selectHeight == 30 && L.selectRadius == 8 && L.selectFont == 12 && L.selectGap == 8 && L.selectIcon == 14,
          "select: px-4 py-1.5 rounded-lg gap-2 text-xs, 30 tall, a 14-pt chevrons icon")
    check(L.selectText == .init(light: shade(0x364153), dark: shade(0xe5e7eb)) && L.selectTextHover == .init(light: shade(0x101828), dark: shade(0xffffff)),
          "select: text gray-700 / gray-200, under the pointer gray-900 / white")
    check(L.selectChevron == .init(light: shade(0x4a5565), dark: shade(0x99a1af)), "select: chevrons gray-600 / gray-400")
    check(L.selectBorder == .init(light: shade(0x000000, 0.04), dark: shade(0xffffff, 0.04)) && L.selectBorderHover == .init(light: shade(0x000000, 0.08), dark: shade(0xffffff, 0.08)),
          "select: a 4% line, 8% under the pointer")
    check(L.selectFillTop == .init(light: shade(0xffffff), dark: shade(0xffffff, 0.08)) && L.selectFillBottom == .init(light: shade(0x000000, 0.02), dark: shade(0xffffff, 0.01)),
          "select: white → black 2%, white 8% → 1%")
}

private func lookSheetTests() {
    check(L.sheetWidth == 340 && L.sheetRadius == 16 && L.sheetMaxHeightShare == 0.7, "language sheet: 340 wide, r16, at most 70% of the window")
    check(L.sheetFill == .init(light: shade(0xffffff), dark: shade(0x1a1b1e)) && L.sheetBorder == .init(light: shade(0xe5e7eb), dark: shade(0xdfe2e8, 0x12 / 255.0)),
          "language sheet: white on gray-200, the dark modal on its line")
    check(L.sheetBackdrop == .init(light: shade(0x000000, 0.5), dark: shade(0x000000, 0.75)), "language sheet: the dialog's backdrop, black .5 / .75")
    check(L.sheetShadowsLight == [.init(y: 10, blur: 15, spread: -3, shade: shade(0x000000, 0.1)), .init(y: 4, blur: 6, spread: -4, shade: shade(0x000000, 0.1))]
          && L.sheetShadowsDark == [.init(y: 24, blur: 64, spread: -20, shade: shade(0x000000, 0xd1 / 255.0))],
          "language sheet: shadow-lg light, the dark modal shadow dark")
    check(L.sheetPadding == 20 && L.sheetHeadBottom == 16 && L.sheetTitleFont == 14 && L.sheetLineFont == 12 && L.sheetLineGap == 2 && L.sheetSearchGap == 12,
          "language sheet: px-5 pt-5 pb-4, title 14, its line 12 mt-0.5, mb-3")
    check(L.searchHeight == 34 && L.searchRadius == 8 && L.searchFont == 12 && L.searchLeading == 36 && L.searchIcon == 14 && L.searchIconInset == 12
          && L.searchFill == .init(light: shade(0xf9fafb), dark: shade(0x1f2024)), "language sheet: the search field pl-9 py-2 text-xs rounded-lg, gray-50 / the dark field")
    check(L.countFont == 10 && L.countPaddingV == 4 && L.listPaddingH == 12 && L.listPaddingV == 8 && L.listSpacing == 2 && L.optionGap == 12
          && L.optionNameFont == 12 && L.optionNativeFont == 10, "language sheet: the count 10/500, the list px-3 py-2 space-y-0.5, a row gap-3 with 12 over 10")
    check(L.optionOn == .init(light: shade(0xf3f4f6), dark: shade(0xffffff, 0.1)) && L.optionHover == .init(light: shade(0xf9fafb), dark: shade(0xffffff, 0.05)),
          "language sheet: a language on gray-100 / white 10%, under the pointer gray-50 / white 5%")
    check(L.box == 16 && L.boxRadius == 4 && L.boxCheck == 10 && L.boxOnFill == .init(light: shade(0x000000, 0.1), dark: shade(0xffffff, 0.2))
          && L.boxOffBorder == .init(light: shade(0xd1d5dc), dark: shade(0xffffff, 0.2)), "language sheet: the 16-pt box, r4, a 10-pt check")
}

private func lookLanguageRowTests() {
    check(ArisSettingsBuilder.languagesSummary(["한국어"]) == "한국어" && ArisSettingsBuilder.languagesSummary(["한국어", "English", "日本語"]) == "한국어 외 2개",
          "쓰는 언어: the closed select names the first language and how many more")
    var s = ArisSettingsSnapshot()
    s.languages = [.init(id: "ko", title: "한국어"), .init(id: "en", title: "English")]
    let row = ArisSettingsBuilder.sections(.voice, s).flatMap(\.rows).first { $0.id == "voice.languages" }
    check(row?.control == .buttons([ArisSettingButton(title: "한국어 외 1개", action: .addLanguage, kind: .select)]) && row?.extra == ArisSettingExtra.none,
          "쓰는 언어: one select that opens the picker, no chips under the row")
    let file = lookRoot.appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    var table = ArisSettingsCopyTable(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data()))
    check(table.english("한국어 외 1개") == "한국어 + 1 more" && table.english("2개 선택됨") == "2 selected", "쓰는 언어: the summary and the count in English")
}

private func lookSourceTests() {
    let menu = lookSource("Aris/components/Settings/ArisAIServicesMenu.swift")
    check(!menu.contains(".scaleEffect(") && !menu.contains("removal: .opacity") && !menu.contains(".easeOut(duration: 0.15), value: model.menu"),
          "menu: nothing plays as it opens or closes")
    check(menu.contains("if !item.action, !radio {") && menu.contains("ArisRadioGlass(radius: ArisMenuLook.rowRadius)"), "menu: a radio list has no check and lights its chosen row")
    let dropdown = lookSource("Aris/components/Settings/ArisSettingsDropdown.swift")
    check(dropdown.contains("ArisSettingSelect(choice:") && !dropdown.contains("ArisAISelect("), "select: a settings row opens its menu from the settings select")
    check(lookSource("Aris/components/Settings/ArisVoicePicker.swift").contains("ArisSettingSelect(choice:"), "select: 목소리's button is the same settings select")
    let sheets = lookSource("Aris/components/Settings/ArisSettingsSheets.swift")
    check(!sheets.contains("ArisSheetFrame(title: \"언어 추가\"") && !sheets.contains("ArisSwitch(") && sheets.contains("ArisLanguageOption"),
          "language sheet: the measured dialog with boxes, not the sheet frame with switches")
    // The measured product is named nowhere in what this branch added (its name is put together here, so this file
    // doesn't carry it either).
    let name = "voice" + "os"
    let tokens = lookSource("Aris/components/Settings/ArisAIMenuHighlight.swift").components(separatedBy: "enum ArisMenuLook").last ?? ""
    let select = dropdown.components(separatedBy: "struct ArisSettingSelect").last ?? ""
    let sheet = sheets.components(separatedBy: "struct ArisRestartSheet").first ?? ""
    check([tokens, select, sheet].allSatisfy { !$0.lowercased().contains(name) }, "settings look: the new tokens and views say \"measured\", never the product's name")
}
