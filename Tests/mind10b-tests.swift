//
//  mind10b-tests.swift
//  Tenth VM run, items 2, 5 and 9: a folder, file, app or link opens by one direct call (known places by name in both
//  languages, ~ resolved by the helper, an invented /Users/… home refused with the way to say it); every way of saying
//  "the selected file" carries the Finder selection; the weather is a look in the units of the answer's language.
//

import Foundation

private final class M10bSystem: ArisAppsSystem {
    var opened: [ArisAppsOpenRequest] = []
    var kinds: [String: ArisApps.PathKind] = [:]
    func installedApps() -> [ArisApps.AppRecord] {
        [.init(bundle: "com.apple.Preview", names: ["Preview", "미리보기"], path: "/System/Applications/Preview.app"),
         .init(bundle: "com.apple.finder", names: ["Finder"], path: "/System/Library/CoreServices/Finder.app")]
    }
    func runningApps() -> [ArisAppsRunning] { [] }
    func frontmost() -> ArisAppsRunning? { nil }
    func defaultBrowser() -> String? { "com.apple.Safari" }
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) { opened.append(request); return (true, "opened") }
    func quit(pid: Int32) -> Bool { true }
    func hide(pid: Int32) -> Bool { true }
    func activate(pid: Int32) -> Bool { true }
    func bundleInfo(path: String) -> ArisApps.BundleInfo? { nil }
    func scriptingDictionary(path: String) -> Data? { nil }
    func includedDictionary(path: String) -> Data? { nil }
    func intentsMetadata(path: String) -> Data? { nil }
    func shortcuts() -> [String] { [] }
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) { (true, "") }
    func automation(bundle: String) -> ArisApps.Grant { .notAsked }
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) { (false, "", nil) }
    func pathKind(_ path: String) -> ArisApps.PathKind { kinds[path] ?? .folder }
    func displays() -> [ArisApps.Rect] { [] }
}

private final class M10bAX: ArisAppsAccessibility {
    func menuBar(pid: Int32) -> ArisApps.MenuBar? { nil }
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String) { (false, "no menu") }
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool { true }
    func focusedRole(pid: Int32) -> String? { nil }
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .moved }
}

private final class M10bEngine: ArisAppsEngine {
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON { .object(["success": .bool(true), "data": .object([:])]) }
}

private func mind10bPlaceTests() {
    let home = "/Users/admin"
    let exists = { (path: String) in ["/Users/admin", "/Users/Shared"].contains(path) }
    let resolve = { (said: String) in ArisKnownPlaces.resolve(said, home: home, exists: exists) }
    // The known-place table, both languages.
    let table: [(String, String)] = [
        ("다운로드", "/Users/admin/Downloads"), ("다운로드 폴더", "/Users/admin/Downloads"), ("Downloads", "/Users/admin/Downloads"),
        ("downloads folder", "/Users/admin/Downloads"), ("the Downloads folder", "/Users/admin/Downloads"),
        ("문서", "/Users/admin/Documents"), ("문서 폴더", "/Users/admin/Documents"), ("Documents", "/Users/admin/Documents"),
        ("바탕화면", "/Users/admin/Desktop"), ("바탕 화면", "/Users/admin/Desktop"), ("데스크탑", "/Users/admin/Desktop"), ("desktop", "/Users/admin/Desktop"),
        ("홈", "/Users/admin"), ("홈 폴더", "/Users/admin"), ("home", "/Users/admin"), ("home folder", "/Users/admin"), ("~", "/Users/admin"),
        ("응용 프로그램", "/Applications"), ("응용프로그램 폴더", "/Applications"), ("Applications", "/Applications"),
        ("사진", "/Users/admin/Pictures"), ("pictures", "/Users/admin/Pictures"), ("음악", "/Users/admin/Music"), ("music", "/Users/admin/Music"),
        ("동영상", "/Users/admin/Movies"), ("movies", "/Users/admin/Movies"), ("휴지통", "/Users/admin/.Trash"), ("trash", "/Users/admin/.Trash"),
        ("~/Downloads", "/Users/admin/Downloads"), ("~/Desktop/vmcheck10/초안.txt", "/Users/admin/Desktop/vmcheck10/초안.txt"),
        ("/Users/admin/Downloads", "/Users/admin/Downloads"), ("/Users/Shared/a.txt", "/Users/Shared/a.txt"), ("/tmp/a.txt", "/tmp/a.txt"),
    ]
    for (said, path) in table { check(resolve(said) == .path(path), "mind10b places: “\(said)” is \(path) (got \(resolve(said)))") }
    // The recorded invention, and others like it.
    check(resolve("/Users/me/Downloads") == .noSuchUser("me"), "mind10b places: /Users/me/Downloads (the recorded call) names a user that isn't here")
    check(resolve("/Users/username/Documents/a.pdf") == .noSuchUser("username") && resolve("/Users/user") == .noSuchUser("user"),
          "mind10b places: any made-up home is refused")
    for said in ["", "다운로드함에 있는 보고서", "보고서", "Downloads/setup.command", "Desktop/../../etc", "notes.txt", "downloadsx", "문서들 정리"] {
        check(resolve(said) == .unknown, "mind10b places: “\(said)” is no place and no path (got \(resolve(said)))")
    }
    let line = ArisKnownPlaces.noSuchUserLine("me", home: home)
    check(line.contains("/Users/admin") && line.contains("~/Downloads") && line.contains("downloads") && line.contains("Never make up a home path"),
          "mind10b places: the refusal gives the real home and the way to say it")
    check(Set(ArisKnownPlaces.ids) == ["home", "desktop", "documents", "downloads", "pictures", "music", "movies", "applications", "trash"],
          "mind10b places: the ids a call may name")
}

private func mind10bOpenTests() {
    let system = M10bSystem()
    let hands = ArisAppsHands(system: system, ax: M10bAX(), engine: M10bEngine(), store: ArisAppsMemoryStore())
    let oldHome = ArisAppsHands.home
    ArisAppsHands.home = { "/Users/admin" }
    defer { ArisAppsHands.home = oldHome }
    system.kinds["/Users/me"] = .missing
    // The recorded calls (record-full.jsonl 5 and 7).
    let tilde = hands.call("app.open", .object(["app": .string("Finder"), "path": .string("~/Downloads")]))
    check(system.opened.last?.path == "/Users/admin/Downloads", "mind10b open: ~/Downloads (the recorded call) opens the real folder (\(tilde.did))")
    let before = system.opened.count
    let invented = hands.call("app.open", .object(["app": .string("Finder"), "path": .string("/Users/me/Downloads")]))
    check(!invented.ok && system.opened.count == before && invented.did.contains("/Users/admin") && invented.did.contains("Never make up"),
          "mind10b open: /Users/me/Downloads (the recorded call) opens nothing and says the real home (\(invented.did))")
    let place = hands.call("app.open", .object(["place": .string("downloads"), "front": .bool(true)]))
    check(place.ok && system.opened.last == ArisAppsOpenRequest(bundle: nil, path: "/Users/admin/Downloads", url: nil, front: true, reveal: false),
          "mind10b open: a place by its id, in front when asked")
    _ = hands.call("app.open", .object(["place": .string("다운로드 폴더")]))
    check(system.opened.last?.path == "/Users/admin/Downloads", "mind10b open: a place by its Korean name")
    _ = hands.call("app.open", .object(["place": .string("응용 프로그램")]))
    check(system.opened.last?.path == "/Applications", "mind10b open: 응용 프로그램")
    let count = system.opened.count
    let odd = hands.call("app.open", .object(["place": .string("/Users/admin/Downloads/setup.command")]))
    check(!odd.ok && system.opened.count == count, "mind10b open: place takes a place's name only, never a path (its effect was judged as a folder's)")
    let reveal = hands.call("app.open", .object(["path": .string("~/Desktop/a.pdf"), "reveal": .bool(true)]))
    check(reveal.ok && system.opened.last?.reveal == true && system.opened.last?.path == "/Users/admin/Desktop/a.pdf" && reveal.did.contains("in Finder"),
          "mind10b open: a file shown in Finder")
    check(!hands.call("app.open", .object(["reveal": .bool(true), "url": .string("https://example.com")])).ok, "mind10b open: reveal needs a path")
    _ = hands.call("app.open", .object(["path": .string("~/Desktop/a.pdf"), "app": .string("미리보기")]))
    check(system.opened.last?.path == "/Users/admin/Desktop/a.pdf" && system.opened.last?.bundle == "com.apple.Preview", "mind10b open: a file in the app named")
    _ = hands.call("app.open", .object(["url": .string("https://www.apple.com")]))
    check(system.opened.last?.url == "https://www.apple.com" && system.opened.last?.path == nil, "mind10b open: a link")
    // The effect: a place is a folder's; a path is judged as written, so a runnable still asks.
    system.kinds["~/Downloads/setup.command"] = .runnable
    check(hands.assess("app.open", .object(["place": .string("downloads")])).effect == .changeReversible
          && hands.assess("app.open", .object(["path": .string("~/Downloads/setup.command")])).effect == .changePermanent
          && hands.assess("app.open", .object(["place": .string("nowhere"), "path": .string("~/Downloads/setup.command")])).effect == .changePermanent,
          "mind10b open: a known place opens like a folder; a path that runs something is still judged as one")
    // The model's view of it.
    let spec = ArisApps.Spec.named("app.open")
    let schema = String(decoding: (try? JSONEncoder().encode(spec?.parameters)) ?? Data(), as: UTF8.self)
    check(spec?.summary.contains("never open a folder or file by pressing keys") == true && (spec?.summary.count ?? 999) <= 320 && schema.contains("downloads") && schema.contains("다운로드")
          && schema.contains("reveal") && schema.contains("Never a made-up"), "mind10b open: the capability says it is the direct way and lists the places")
}

private func mind10bRuleTests() {
    let rule = ArisMindSession.directFirstRule
    for sentence in ["Use a direct capability first.", "Drive an app by pressing keys, typing or clicking only when no direct capability does it.",
                     "Never invent a path under /Users", "write ~ and Aris fills in the real home folder", "다운로드 is downloads"] {
        check(rule.contains(sentence), "mind10b rule: “\(sentence)” is pinned")
    }
    check(ArisMindSession.rules.contains(rule) && ArisMindSession.rules.contains(ArisMindSession.appTextRule), "mind10b rule: it is in the Mind's rules, beside the others")
}

private func mind10bSelectionTests() {
    // Hit: the look (with the Finder selection) rides with the turn, and the helper's resolver wants files.
    let hits = ["선택한 파일 이름을 new-name.txt로 바꿔 줘", "선택된 파일 이름 바꿔 줘", "고른 파일 휴지통에 버려 줘", "지금 고른 파일 이름 알려 줘",
                "선택해 둔 파일들 새 폴더로 옮겨 줘", "선택해 놓은 파일 열어 줘", "골라 놓은 파일 보여 줘", "선택되어 있는 파일 뭐야",
                "이 파일 이름 new-name.txt로 바꿔 줘", "이 파일들 옮겨 줘",
                "rename the selected file to new-name.txt", "move the selected files to Documents", "rename this file to a.txt",
                "move these files to the desktop", "rename the file I selected", "open the files I picked", "what are these two files"]
    for words in hits {
        check(ArisDeixis.refersToScreen(words), "mind10b selection: “\(words)” carries what is selected")
        let pointing = ArisFocusWords.parse(words)
        check(pointing.points && pointing.wants == .file, "mind10b selection: “\(words)” wants the files (\(String(describing: pointing.wants)))")
    }
    check(ArisFocusWords.parse("선택한 파일들 옮겨 줘").plural && ArisFocusWords.parse("move these files").plural, "mind10b selection: several")
    for words in ["선택한 거 번역해 줘", "고른 거 지워 줘", "선택된 항목 복사해 줘", "선택한 사진 보여 줘"] {
        check(ArisDeixis.refersToScreen(words), "mind10b selection: “\(words)” points at the selection")
    }
    // Must not hit.
    for words in ["파일 선택하는 법 알려 줘", "Finder에서 파일 여러 개 선택하려면 어떻게 해", "선택지 중에 뭐가 좋을까", "잘 고른 것 같아?", "메뉴 고르는 중이야",
                  "how do I select a file in Finder", "what file formats can you read", "these days I am busy", "내일 날씨 알려 줘", "새 파일 만들어 줘",
                  "which file should I pick"] {
        check(!ArisDeixis.refersToScreen(words) && !ArisDeixis.refersToSelection(words), "mind10b selection: “\(words)” points at nothing")
    }
    check(ArisGrounding.pointsAtFocus("지금 고른 파일 이름 바꿔 줘") && ArisGrounding.pointsAtFocus("선택한 파일 이름 바꿔 줘") && !ArisGrounding.pointsAtFocus("메뉴 고르는 중"),
          "mind10b selection: 고른 points at the focus like 선택한, as a whole word")
}

private func mind10bWeatherTests() {
    // Units: the answer's language, unless he chose himself.
    let us = Locale(identifier: "en_US")
    // rel11 (eleventh VM run, P02): the unit is the Mac's, never the answer's language (it was the language in mind10b).
    check(ArisWeather.usesFahrenheit(appleUnit: nil, locale: us) && !ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "en_CA"))
          && !ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "ko_KR")), "mind10b weather: the unit follows the region")
    check(ArisWeather.usesFahrenheit(appleUnit: "Fahrenheit", locale: Locale(identifier: "ko_KR"))
          && !ArisWeather.usesFahrenheit(appleUnit: "Celsius", locale: us), "mind10b weather: his own setting wins either way")
    let json = #"{"current":{"temperature_2m":11.2,"apparent_temperature":6.9,"weather_code":3,"wind_speed_10m":17.6},"daily":{"time":[],"weather_code":[],"temperature_2m_max":[],"temperature_2m_min":[],"precipitation_probability_max":[]}}"#
    guard let forecast = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(json.utf8)) else { return check(false, "mind10b weather: the fixture decodes") }
    let said = ArisWeather.summary(forecast, place: "올랜도", korean: true, fahrenheit: ArisWeather.usesFahrenheit(appleUnit: nil, locale: Locale(identifier: "ko_KR")))
    check(said.contains("11°C") && said.contains("km/h") && !said.contains("°F") && !said.contains("mph"), "mind10b weather: said in °C and km/h (\(said))")
    // What the look sends: the place, without the tool's own closed settings.
    check(ArisOutboundReads.weatherPlace(["Orlando", "--ko"]) == ["Orlando"] && ArisOutboundReads.weatherPlace(["올랜도", "--days", "7", "--ko"]) == ["올랜도"]
          && ArisOutboundReads.weatherPlace(["--en"]) == [], "mind10b weather: one language and one whole --days are settings, not words sent")
    for odd in [["Seoul", "--ko", "--ko"], ["Seoul", "--ko", "--en"], ["Seoul", "--days", "hunter22"], ["Seoul", "--days", "3", "--days", "4"], ["Seoul", "--days", "99"],
                ["Seoul", "--days", "03"], ["Seoul", "--x=hunter22"], ["Seoul", "--days"]] {
        check(ArisOutboundReads.weatherPlace(odd) == odd, "mind10b weather: \(odd) is left as written (so it is asked about)")
    }
    for words in [["Orlando", "--ko"], ["올랜도", "--days", "7", "--ko"], ["Seoul"], ["New", "York", "--en"]] {
        if case .forecast(let place, _, _, _) = ArisWeather.request(words) {
            check(place == ArisOutboundReads.weatherPlace(words).joined(separator: " "), "mind10b weather: what is accounted is the place the tool looks up (\(words))")
        } else { check(false, "mind10b weather: \(words) is a forecast") }
    }
    // The gate, with something private read before (the recorded conversation): the place he said runs; anything else asks as before.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-mind10b-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let gate = ArisTrustGate(home: folder.path)
    gate.ownerTurn(session: "w", text: "오늘 올랜도 날씨 어때?")
    gate.toolResult(session: "w", call: "w0", text: "hunter22", source: ArisContentSource(kind: "app", source: "TextEdit"))
    let rated = { (argv: [String]) in gate.decide(session: "w", call: UUID().uuidString, capability: "aris.weather", effect: .observe, arguments: [:], argv: argv) }
    let looked = rated(["weather", "올랜도", "--ko"])
    check(looked.effect == .observe && looked.decision == .run, "mind10b weather: the place he said, with the answer's language, is a look: no card")
    check(rated(["weather", "--ko"]).effect == .observe && rated(["weather", "올랜도", "--days", "7", "--ko"]).effect == .observe, "mind10b weather: home, and the week")
    check(rated(["weather", "Orlando", "--ko"]).effect == .outward, "mind10b weather: a place he didn't say (the recorded translation) still asks after a private read")
    check(rated(["weather", "hunter22", "--ko"]).effect == .outward && rated(["weather", "올랜도", "--ko", "--days", "hunter22"]).effect == .outward
          && rated(["weather", "올랜도", "--x=hunter22"]).effect == .outward, "mind10b weather: what was read never rides out on the weather")
    try? FileManager.default.removeItem(at: folder)
    // The model is told to pass the place as said.
    let entry = ArisCapabilityBook.entry(named: "weather")
    let schema = String(decoding: (try? JSONSerialization.data(withJSONObject: entry?.parameters ?? [:])) ?? Data(), as: UTF8.self)
    check(schema.contains("exactly as the owner said it") && schema.contains("never translated") && entry?.description.contains("look-up") == true,
          "mind10b weather: the place goes in as he said it")
    if let entry, case .arisTools(let argv, _) = entry.run {
        check(argv(["place": "올랜도", "language": "ko"]) == ["weather", "올랜도", "--ko"], "mind10b weather: the call's words")
    } else { check(false, "mind10b weather: the entry runs aris-tools") }
}

func runMind10bTests() {
    mind10bPlaceTests()
    mind10bOpenTests()
    mind10bRuleTests()
    mind10bSelectionTests()
    mind10bWeatherTests()
}
