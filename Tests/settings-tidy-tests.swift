// Tests for settings-tidy (2026-11-12): the notch preview is gone from every Settings page (only 팀원 keeps Aris's
// face strip), and 노치 기능 › 선반 has 첫 화면에도 보이기, whether the open notch's home shows the shelf's files as
// chips (on by default, as before). Reads the builder, the catalog file and the sources; nothing of the user's is touched.
// Called from main.swift; uses its check().
import Foundation

private let tidyRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func tidySource(_ path: String) -> String { (try? String(contentsOf: tidyRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

/// Every Swift file the app and its helpers are built from.
private func tidyAllSources() -> [(path: String, text: String)] {
    let fm = FileManager.default
    var out: [(String, String)] = []
    for top in ["Aris", "ArisAgent", "ArisTools", "ArisXPCHelper", "Shared"] {
        guard let walk = fm.enumerator(at: tidyRoot.appendingPathComponent(top), includingPropertiesForKeys: nil) else { continue }
        for case let url as URL in walk where url.pathExtension == "swift" {
            out.append((url.path, (try? String(contentsOf: url, encoding: .utf8)) ?? ""))
        }
    }
    return out
}

func runSettingsTidyTests() {
    tidyNoNotchPreviewTests()
    tidyShelfOnHomeTests()
}

// MARK: - No notch preview on any page

private func tidyNoNotchPreviewTests() {
    let settings = "Aris/components/Settings/"
    let gone = ["ArisNotchPreview.swift", "ArisNotchPreviewPlan.swift"].filter { FileManager.default.fileExists(atPath: tidyRoot.appendingPathComponent(settings + $0).path) }
    check(gone.isEmpty, "settings tidy: the notch preview's view and plan files are gone" + (gone.isEmpty ? "" : " (\(gone))"))
    let sources = tidyAllSources()
    check(sources.count > 100, "settings tidy: the app's sources are read")
    let still = sources.filter { $0.text.contains("ArisNotchPreview") }.map { ($0.path as NSString).lastPathComponent }
    check(still.isEmpty, "settings tidy: nothing builds or names the notch preview any more" + (still.isEmpty ? "" : " (\(still.prefix(3)))"))

    let shell = tidySource(settings + "ArisSettingsShell.swift")
    check(!shell.isEmpty && !shell.contains("plan") && !shell.contains("replay"), "settings tidy: the shell takes no preview plan and no replay")
    check(shell.contains("if nav.page == .team { ArisFaceStageView()") && shell.components(separatedBy: "ArisFaceStageView(").count == 2,
          "settings tidy: the only stage left is 팀원's face, drawn on that page alone; every other page starts at its title")
    check(shell.contains(".padding(.top, ArisSettingsMetrics.columnTop)"), "settings tidy: the column starts at its measured top (40 inside the card) on every page")

    let live = tidySource(settings + "ArisLiveSettings.swift")
    check(!live.contains("previewInput") && !live.contains("arisSettingsSpeed") && !live.contains("replay += 1") && live.contains("wording(ArisVoiceSample.line)"),
          "settings tidy: the live window builds no preview input; 들어 보기 still reads the sample line in the page's wording")
    let ai = tidySource(settings + "ArisAIServicesLive.swift")
    check(ai.components(separatedBy: "ArisVoiceSample.line").count == 3, "settings tidy: AI 서비스's 미리 듣기 and a Korean Mac voice's sample read the same line")
    check(ArisVoiceSample.line == "안녕하세요, 아리스예요. 이 속도로 말할게요.", "settings tidy: the sample line is as it was")
    check(!tidySource(settings + "ArisSettingsArt.swift").contains("struct ArisNotchPreview") && tidySource(settings + "ArisSettingsArt.swift").contains("struct ArisSettingsArt"),
          "settings tidy: the window's art keeps its own file")
    check(tidySource(settings + "ArisFaceStageView.swift").contains("ArisFaceStageWave.heights(tick:"), "settings tidy: 팀원's listening bars take the wave from ArisFaceStageWave")
    check(!tidySource(settings + "ArisAIServicesPageModel.swift").contains("who:") && !tidySource(settings + "ArisSettingsSnapshot.swift").contains("teammateNames"),
          "settings tidy: the names only the preview showed are no longer gathered")
}

// MARK: - 첫 화면에도 보이기

private func tidyShelfOnHomeTests() {
    check(ArisMoreSettings().shelfOnHome, "shelf on home: on by default (today's behaviour)")
    func row(_ m: ArisMoreSettings) -> ArisSettingItem? {
        var s = ArisSettingsSnapshot()
        s.more = m
        return ArisSettingsBuilder.sections(.features, s).first { $0.id == "features.shelf" }?.rows.first { $0.id == "features.shelfOnHome" }
    }
    let on = row(ArisMoreSettings())
    check(on?.title == "첫 화면에도 보이기" && on?.desc == "끄면 선반 파일은 선반 탭에서만 보여요." && on?.control == .toggle(.more(.shelfOnHome), true),
          "shelf on home: 노치 기능 › 선반 has the switch, on, with its line")
    var offValues = ArisMoreSettings()
    offValues.shelfOnHome = false
    check(row(offValues)?.control == .toggle(.more(.shelfOnHome), false), "shelf on home: the switch shows off when it is off")
    let shelfRows = ArisSettingsBuilder.sections(.features, ArisSettingsSnapshot()).first { $0.id == "features.shelf" }?.rows.map(\.id) ?? []
    check(shelfRows.prefix(2) == ["features.shelfOn", "features.shelfOnHome"], "shelf on home: right under 선반 쓰기")

    check(ArisSettingsIndex.entry("features.shelfOnHome")?.page == .features && ArisSettingsIndex.search("첫 화면").first?.id == "features.shelfOnHome"
          && ArisSettingsIndex.search("선반").contains { $0.id == "features.shelfOnHome" },
          "shelf on home: the search finds it on 노치 기능")
    check(ArisSettingsBuilder.searchable(ArisSettingsSnapshot()).contains("features.shelfOnHome"), "shelf on home: offered by the search")

    // In English.
    ArisSettingsCopy.install(ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: tidyRoot.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data()))
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .features, english: true)
    let shown = english.sections(ArisSettingsBuilder.sections(.features, ArisSettingsSnapshot())).flatMap(\.rows).first { $0.id == "features.shelfOnHome" }
    check(shown?.title == "Also show on the home screen" && shown?.desc == "When off, shelf files show only in the Shelf tab.", "shelf on home: its English")

    // What the home shows.
    let rule = ArisShelfTileLayout.homeRowShown
    check(rule(2, false, true), "shelf on home: on, files on the shelf and no turn: the chips show (as before)")
    check(!rule(2, false, false), "shelf on home: off, the home never shows the shelf's chips")
    check(!rule(0, false, true) && !rule(3, true, true), "shelf on home: no files, or a turn on screen: no chips, as before")

    // Wired to the app, and nothing else changes.
    let home = tidySource("Aris/private/Aris/Home/ArisHomeView.swift")
    check(home.contains("@Default(.shelfOnHome) private var shelfOnHome")
          && home.contains("ArisShelfTileLayout.homeRowShown(files: ArisShelfChips.visible(shelf.items).count, turnShowing: showsTurn, onHome: shelfOnHome)"),
          "shelf on home: the home's shelf row follows the setting")
    check(home.contains("if vm.dropInteraction.anyDropZoneTargeting {\n                ArisDropZones().transition(.opacity)\n            } else {"),
          "shelf on home: the drop target (its shelf half) shows while dragging whatever the setting")
    check(tidySource("Aris/private/Notch/ArisPreferences.swift").contains("static let shelfOnHome = Key<Bool>(\"shelfOnHome\", default: true)"),
          "shelf on home: stored in its own preference, on by default")
    let model = tidySource("Aris/components/Settings/ArisMoreSettingsModel.swift")
    check(model.contains("m.shelfOnHome = Defaults[.shelfOnHome]") && model.contains("case .shelfOnHome: Defaults[.shelfOnHome] = on ?? true")
          && model.contains(".shelfOnHome,"), "shelf on home: the settings window reads it, writes it and hears it change")
    let others = tidyAllSources().filter { $0.text.contains("shelfOnHome") }.map { ($0.path as NSString).lastPathComponent }.sorted()
    check(others == ["ArisHomeView.swift", "ArisMoreSettings.swift", "ArisMoreSettingsModel.swift", "ArisPreferences.swift", "ArisSettingsCatalog.swift"],
          "shelf on home: only the home reads it: the Shelf tab and what Aris is told of the shelf (--shelf) don't" + " (\(others))")
    check(tidySource("Aris/private/Aris/ArisAgentClient.swift").contains("body[\"shelf\"] = await MainActor.run { ShelfStateViewModel.shared.items.compactMap { $0.fileURL?.path } }"),
          "shelf on home: Aris still knows the shelf's files")
}
