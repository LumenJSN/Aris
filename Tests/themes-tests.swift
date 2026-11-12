// The notch's look in Settings › 노치 (themes): 글자 뒤 받침 (a soft dark patch behind the open notch's small text),
// the star asleep in the closed notch at rest, and a theme picked from the looks that were hidden preferences.
import Foundation

/// WCAG contrast of two sRGB colours (channels 0…1).
private func themesContrast(_ a: [Double], _ b: [Double]) -> Double {
    func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    func lum(_ c: [Double]) -> Double { 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]) }
    let (x, y) = (lum(a), lum(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

/// `top` at `alpha` over `under`, channel by channel.
private func themesOver(_ top: [Double], _ alpha: Double, _ under: [Double]) -> [Double] {
    zip(top, under).map { $0 * alpha + $1 * (1 - alpha) }
}

private func themesBackingTests() {
    check(!ArisTextBacking.standard && !ArisSettingsSnapshot().textBacking, "text backing: off on a fresh install, so the notch keeps today's look")
    check(ArisTextBacking.shows(on: true, reduceTransparency: false) && !ArisTextBacking.shows(on: false, reduceTransparency: false),
          "text backing: small text gets its patch while the setting is on, and none while it is off")
    check(!ArisTextBacking.shows(on: true, reduceTransparency: true), "text backing: with Reduce Transparency the notch is solid already, so no patch is drawn")
    check(ArisTextBacking.opacity == 0.62 && ArisTextBacking.blur == 5 && ArisTextBacking.wider == 6 && ArisTextBacking.taller == 3,
          "text backing: the patch is the proposal's soft one: black 62 %, blurred 5, 6 wider and 3 taller than the text each side")

    // What the glass shows of a white text window behind the composer in the VM capture g2-14a: sRGB .475 (L .19).
    let behind = [0.475, 0.475, 0.475]
    let backed = behind.map(ArisTextBacking.backed)
    let hintInk = [236.0 / 255, 239.0 / 255, 247.0 / 255]
    let hintBare = themesContrast(themesOver(hintInk, 0.62, behind), behind)
    let hintBacked = themesContrast(themesOver(hintInk, 0.62, backed), backed)
    check(hintBare < 4.5 && hintBacked >= 4.5, "text backing: the composer's hint over a bright window goes from \(String(format: "%.1f", hintBare)):1 to \(String(format: "%.1f", hintBacked)):1, past 4.5:1")
    let capsule = themesOver([1, 1, 1], 0.08, behind), capsuleBacked = capsule.map(ArisTextBacking.backed)
    let tagBare = themesContrast(themesOver([1, 1, 1], 0.74, capsule), capsule)
    let tagBacked = themesContrast(themesOver([1, 1, 1], 0.74, capsuleBacked), capsuleBacked)
    check(tagBare < 4.5 && tagBacked >= 4.5, "text backing: a working tag's words over a bright window go from \(String(format: "%.1f", tagBare)):1 to \(String(format: "%.1f", tagBacked)):1")

    var on = ArisSettingsSnapshot()
    on.textBacking = true
    let top = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.notch, s).first { $0.id == "notch.top" }?.rows ?? [] }
    let row = top(ArisSettingsSnapshot()).first { $0.id == ArisNotchLookSetting.backingID }
    check(row?.control == .toggle(.textBacking, false) && top(on).first { $0.id == ArisNotchLookSetting.backingID }?.control == .toggle(.textBacking, true),
          "text backing: its switch is a row of the 위 노치 card in Settings › 노치, showing what is stored")
    check(row?.title == "글자 뒤 받침" && row?.desc == "밝은 창 위에서도 작은 글씨가 잘 보이게 받쳐 줘요.", "text backing: the row says what it does in one sentence")
    check(ArisSettingsIndex.entry(ArisNotchLookSetting.backingID)?.page == .notch && ArisSettingsIndex.search("글자 뒤 받침", among: ArisSettingsBuilder.searchable(ArisSettingsSnapshot())).first?.id == ArisNotchLookSetting.backingID,
          "text backing: a search for its name finds the row")
    check(ArisSettingsCopyMore.english["글자 뒤 받침"] == "Text backing" && ArisSettingsCopyMore.english[ArisNotchLookSetting.backingDesc] != nil,
          "text backing: the row has its English")
}

private func themesRestStarTests() {
    check(ArisRestStar.standard && ArisSettingsSnapshot().restStar, "rest star: on by default, so the closed notch shows the star at rest")
    check(ArisVNotchRest(stored: nil, starShown: true) == .star && ArisVNotchRest(stored: nil, starShown: false) == .outOfSight,
          "rest star: on, the star rests in the band; off, the closed notch rests as today, only the camera housing showing")
    check(ArisVNotchRest(stored: "star", starShown: false) == .star, "rest star: the hidden arisClosedRest = star still keeps it resting with the switch off")
    check(!ArisVNotchRest(stored: nil, starShown: false).starRests(muted: false, agentDown: false, modelNote: false)
          && ArisVNotchRest(stored: nil, starShown: false).starRests(muted: true, agentDown: false, modelNote: false),
          "rest star: with the switch off the star still comes out for what only the closed notch tells (muted)")

    // At rest on the user's MacBook (1800 wide, camera housing 220 × 38): the band the resting star always had.
    let metrics = ArisVNotch.metrics(ArisVNotch.Display(hasHousing: true, topBand: 39, width: 1800))
    let band = ArisVNotch.closedSize(.band, hovered: false, glass: true, metrics: metrics)
    check(band == CGSize(width: 321, height: 39) && ArisVNotch.ear(body: band.width, housing: 220) == 50.5,
          "rest star: at rest the band is 321 × 39 on the user's MacBook, the 220-wide housing and a 50.5-point ear each side")
    let rests = ArisStarBand.showsHome(closed: true, hidden: false, fullscreen: false, hasNotch: true, flat: false, busy: false)
    let mode = ArisStarBand.mode(turn: false, dueAlert: false, timer: false, tasks: false, claude: false, music: false, parked: false, home: rests)
    check(mode == .home, "rest star: a closed notch with nothing on is the star's home")

    check(ArisRestStar.sleeps(mode: .home, filesWaiting: false, modelNote: false), "rest star: at rest with nothing to tell, the star sleeps (not only after ten idle minutes)")
    check(ArisRestStar.mood("default", asleep: true) == "sleeping" && ArisRestStar.mood("working", asleep: true) == "working",
          "rest star: asleep at rest whatever the clock says, unless a job is running")
    check([ArisStarBand.Mode.turn, .tasks, .parked].allSatisfy { !ArisRestStar.sleeps(mode: $0, filesWaiting: false, modelNote: false) }
          && !ArisRestStar.sleeps(mode: nil, filesWaiting: false, modelNote: false),
          "rest star: the moment Aris listens, works or holds an answer, the star is awake")
    check(ArisRestStar.mood("default", asleep: false) == "default" && ArisRestStar.mood("sleeping", asleep: false) == "sleeping",
          "rest star: awake it keeps its own mood (the long-idle and night doze stay as they were)")
    check(!ArisRestStar.sleeps(mode: .home, filesWaiting: true, modelNote: false) && !ArisRestStar.sleeps(mode: .home, filesWaiting: false, modelNote: true),
          "rest star: at rest beside files waiting or a speech model's note, the star stays awake to show it")
    // Back at rest after a turn: the same rule gives sleep again.
    let after = ArisStarBand.mode(turn: false, dueAlert: false, timer: false, tasks: false, claude: false, music: false, parked: false, home: true)
    check(ArisRestStar.sleeps(mode: after, filesWaiting: false, modelNote: false), "rest star: once everything is over it goes back to sleep at rest")

    var off = ArisSettingsSnapshot()
    off.restStar = false
    let top = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.notch, s).first { $0.id == "notch.top" }?.rows ?? [] }
    check(top(ArisSettingsSnapshot()).first { $0.id == ArisNotchLookSetting.restStarID }?.control == .toggle(.restStar, true)
          && top(off).first { $0.id == ArisNotchLookSetting.restStarID }?.control == .toggle(.restStar, false),
          "rest star: its switch is a row of the 위 노치 card, on unless turned off")
    check(ArisSettingsIndex.search("쉬는 동안 별", among: ArisSettingsBuilder.searchable(ArisSettingsSnapshot())).first?.id == ArisNotchLookSetting.restStarID
          && ArisSettingsCopyMore.english[ArisNotchLookSetting.restStarTitle] == "Show the star while resting",
          "rest star: a search finds its row, and it has its English")
}

private func themesSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

private func themesThemeTests() {
    check(ArisNotchTheme.allCases.map(\.title) == ["기본", "또렷한 유리", "검정", "밝은 아래"],
          "theme: four looks to pick from, named by how they look")
    let stored = ArisNotchTheme.allCases.map { "\($0.glassValue ?? "-")/\($0.voiceValue ?? "-")" }
    check(stored == ["-/-", "clear-glass/-", "floor/-", "-/surface-light"],
          "theme: each is a pair of stored values (기본 leaves both unset; 밝은 아래 is the light-bottom surface alone)")
    check(ArisNotchTheme.stored(glass: nil, voice: nil) == .standard && ArisNotchTheme.stored(glass: "private-glass", voice: "aris") == .standard,
          "theme: a fresh install, or the shipped glass written out, is 기본")
    check(ArisNotchTheme.allCases.allSatisfy { ArisNotchTheme.stored(glass: $0.glassValue, voice: $0.voiceValue) == $0 },
          "theme: what each theme writes reads back as that theme")
    check(ArisNotchTheme.stored(glass: " Clear-Glass ", voice: nil) == .clear && ArisNotchTheme.stored(glass: "floor", voice: "SURFACE-LIGHT") == .lightBottom,
          "theme: a value written by hand reads the way the notch reads it (any case, spaces ignored; the voice look wins)")
    check(ArisNotchTheme.stored(glass: "mid", voice: nil) == nil && ArisNotchTheme.stored(glass: nil, voice: "siri-frost") == nil
          && ArisNotchTheme.stored(glass: nil, voice: "siri") == nil,
          "theme: a look set by hand that is none of the four (the whole light-bottom look among them) shows none picked")

    let suite = testSuiteName("aris-themes-tests")
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    ArisNotchTheme.lightBottom.write(to: defaults)
    let lightGlass = ArisGlassLook.current(defaults), lightVoice = ArisVoiceLook.resolve(defaults.string(forKey: ArisVoiceLook.key))
    ArisNotchTheme.solid.write(to: defaults)
    let solidGlass = ArisGlassLook.current(defaults), solidVoice = ArisVoiceLook.resolve(defaults.string(forKey: ArisVoiceLook.key))
    ArisNotchTheme.standard.write(to: defaults)
    let cleared = defaults.object(forKey: ArisGlassLook.preferenceKey) == nil && defaults.object(forKey: ArisVoiceLook.key) == nil
    defaults.removePersistentDomain(forName: suite)
    check(lightGlass == .privateGlass && lightVoice == .surfaceLight, "theme: 밝은 아래 makes the notch draw the light-bottom surface over the shipped glass")
    check(solidGlass == .floor && solidVoice == .aris, "theme: 검정 after 밝은 아래 draws the solid floor and turns the light-bottom surface off")
    check(cleared, "theme: 기본 removes both preferences, as a fresh install has them")

    let top = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.notch, s).first { $0.id == "notch.top" }?.rows ?? [] }
    check(top(ArisSettingsSnapshot()).suffix(3).map(\.id) == [ArisNotchLookSetting.themeID, ArisNotchLookSetting.backingID, ArisNotchLookSetting.restStarID],
          "theme: the three look rows close the 위 노치 card, in one card with its other rows")
    check(ArisSettingsSnapshot().notchTheme == "standard", "theme: 기본 on a fresh install")
    let row = top(ArisSettingsSnapshot()).first { $0.id == ArisNotchLookSetting.themeID }
    check(row?.desc == "고른 모양은 다음에 노치가 열릴 때 바뀌어요.", "theme: the row says when a new theme shows, in one sentence")
    check(ArisSettingsIndex.search("테마", among: ArisSettingsBuilder.searchable(ArisSettingsSnapshot())).first?.id == ArisNotchLookSetting.themeID,
          "theme: a search for 테마 finds the row")
    let english = ArisSettingsWording(pageEnglish: true, frameEnglish: true)
    let drawn = english.sections(ArisSettingsBuilder.sections(.notch, ArisSettingsSnapshot())).flatMap(\.rows).first { $0.id == ArisNotchLookSetting.themeID }
    var names: [String] = []
    if case .menu(_, let options, _)? = drawn?.control { names = options.map(\.title) }
    check(names == ["Default", "Clear glass", "Solid black", "Light bottom"] && drawn?.title == "Theme" && drawn?.desc != ArisNotchLookSetting.themeDesc,
          "theme: in English the row and its menu read Theme · Default, Clear glass, Solid black, Light bottom")
    check(english("기본") == ArisSettingsCopy.t("기본") && ArisSettingsWording.korean.sections(ArisSettingsBuilder.sections(.notch, ArisSettingsSnapshot())) == ArisSettingsBuilder.sections(.notch, ArisSettingsSnapshot()),
          "theme: 기본 is Default only in the theme menu; everywhere else it reads as the catalog has it, and the Korean page is unchanged")
    let words = ArisNotchTheme.allCases.flatMap { [$0.title, $0.englishTitle, $0.rawValue] } + [ArisNotchLookSetting.themeTitle, ArisNotchLookSetting.themeDesc]
        + ArisNotchLookSetting.english.values
    check(!words.contains { $0.lowercased().contains("siri") || $0.lowercased().contains("regular-glass") || $0.lowercased().contains("apple") },
          "theme: nothing the picker shows names another product")
}

/// The frosted glass looked the same as the default: it is not offered, and a hand-set one keeps drawing.
private func themesNoFrostedTests() {
    check(!ArisNotchTheme.allCases.contains { $0.glassValue == ArisGlassLook.regularGlass.rawValue } && ArisNotchTheme(rawValue: "frosted") == nil,
          "theme: the frosted glass is not offered (it looked the same as 기본)")
    check(ArisNotchTheme.stored(glass: "regular-glass", voice: nil) == nil && ArisGlassLook(preference: "regular-glass") == .regularGlass,
          "theme: a hand-set arisGlassLook = regular-glass still draws the frosted glass, and the picker shows none picked")
}

/// The theme row is a plain menu of the theme names, like the page's other choices: no previews.
private func themesPlainPickerTests() {
    var picked = ArisSettingsSnapshot()
    picked.notchTheme = ArisNotchTheme.solid.rawValue
    let row = ArisSettingsBuilder.sections(.notch, picked).first { $0.id == "notch.top" }?.rows.first { $0.id == ArisNotchLookSetting.themeID }
    let options = ArisNotchTheme.allCases.map { ArisSettingOption(id: $0.rawValue, title: $0.title) }
    check(row?.control == .menu(.notchTheme, options, selected: "solid"),
          "theme: the row is the settings' own menu of the four names, showing the one picked; nothing drawn by hand")
    var none = ArisSettingsSnapshot()
    none.notchTheme = ""
    let unpicked = ArisSettingsBuilder.sections(.notch, none).first { $0.id == "notch.top" }?.rows.first { $0.id == ArisNotchLookSetting.themeID }
    check(unpicked?.control == .menu(.notchTheme, options, selected: ""), "theme: with a hand-set look the menu shows none picked")
    check(themesSource("Aris/components/Settings/ArisNotchThemeRow.swift").isEmpty, "theme: the previews' view is gone")
}

/// A theme changes only the notch's surface: 밝은 아래 picked in Settings is the light-bottom look's fill, rim, shadow
/// and text scrim over the glass, with Aris's own controls, layout and motion.
private func themesSurfaceOnlyTests() {
    let surface = ArisVoiceLook.resolve("surface-light")
    check(surface == .surfaceLight && surface.drawsSurface && !surface.isSiri,
          "surface only: surface-light draws the light-bottom surface and is not the whole look")
    check(ArisVoiceLook.siri.isSiri && ArisVoiceLook.siri.drawsSurface && ArisVoiceLook.siriFrost.isSiri && !ArisVoiceLook.aris.drawsSurface,
          "surface only: the whole hidden look (set by hand) still brings its controls with its surface; Aris's own draws neither")
    let before = ArisSiriLookNow.look
    ArisSiriLookNow.look = .surfaceLight
    let (on, surfaceOn) = (ArisSiriLookNow.on, ArisSiriLookNow.surfaceOn)
    ArisSiriLookNow.look = .siri
    let (siriOn, siriSurface) = (ArisSiriLookNow.on, ArisSiriLookNow.surfaceOn)
    ArisSiriLookNow.look = before
    check(!on && surfaceOn && siriOn && siriSurface, "surface only: with the theme the surface is on and every control keeps Aris's own")

    let root = themesSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains("let siri = ArisSiriLookNow.surfaceOn") && root.contains("siri ? ArisSiriLookSurface(shape: shape, open: open, band: siriBand"),
          "surface only: the notch draws the light-bottom surface (fill, rim, shadow) for the theme")
    check(root.contains("if ArisSiriLookNow.on { $0.animation = ArisSiriLookMotion.surface(open: open) }") && root.contains("if ArisSiriLookNow.on {\n                withAnimation(ArisSiriLookMotion.resize"),
          "surface only: the look's springs come only with the whole look; the theme keeps Aris's curves")
    check(themesSource("Aris/private/Aris/SiriLook/ArisSiriLookSurface.swift").contains("if ArisSiriLookNow.surfaceOn, !reduceTransparency"),
          "surface only: the scrim the light bottom needs behind the text comes with the surface")
    let controls = ["Aris/private/Aris/Home/ArisComposer.swift", "Aris/private/Aris/Home/ArisNotchHeader.swift", "Aris/private/Aris/Home/ArisTurnView.swift",
                    "Aris/private/Aris/Home/ArisActivityTag.swift", "Aris/private/Aris/SiriLook/ArisSiriLookHooks.swift", "Aris/private/Aris/ArisDocumentBlocks.swift",
                    "Aris/private/Aris/Home/ArisWidgetCards.swift", "Aris/private/Aris/Home/ArisAnswerDocumentView.swift"].map(themesSource)
    check(controls.allSatisfy { $0.contains("ArisSiriLookNow.on") && !$0.contains("surfaceOn") },
          "surface only: the composer (no + or microphone), the request card, Stop and Close, the working mark, the tags, cards and answer type follow the whole look only")
}

func runThemesTests() {
    themesBackingTests()
    themesRestStarTests()
    themesThemeTests()
    themesNoFrostedTests()
    themesPlainPickerTests()
    themesSurfaceOnlyTests()
}
