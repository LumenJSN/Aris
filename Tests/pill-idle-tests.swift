// Tests for pill-idle: Settings › 받아쓰기 › 화면 › 쉴 때도 보이기 (on by default). Off, the dictation pill's idle
// sliver and its hover are hidden (nothing to click); the pill shows while a dictation runs (its ring, copied words and
// error included) and goes away once it ended. The row sits under 받아쓰기 알약 보이기 and is greyed while the pill is
// off. Called from main.swift; uses its check().
import CoreGraphics
import Foundation

private let idleRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func idleSource(_ path: String) -> String { (try? String(contentsOf: idleRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runPillIdleTests() {
    pillIdleRuleTests()
    pillIdleSettingsTests()
    pillIdleWiringTests()
}

// MARK: - The rule

private func pillIdleRuleTests() {
    typealias R = ArisDictationPillRules
    var i = R.Inputs()
    check(i.showIdle, "pill idle: shown while idle by default")
    check(R.phase(i) == .idle, "pill idle: on → the idle sliver between dictations")
    i.showIdle = false
    check(R.phase(i) == .hidden, "pill idle: off → no sliver between dictations")
    i.hovered = true
    check(R.phase(i) == .hidden, "pill idle: off → no hover either (nothing to click)")
    i.hovered = false
    i.stage = .listening
    check(R.phase(i) == .recording(handsFree: false), "pill idle: off → the pill appears when dictation starts")
    i.handsFree = true
    check(R.phase(i) == .recording(handsFree: true), "pill idle: off → hands-free still shows")
    i.hovered = true
    check(R.phase(i) == .recording(handsFree: true), "pill idle: off → the pointer on a recording keeps the recording")
    i.hovered = false
    i.stage = .writing
    check(R.phase(i) == .transcribing(.charging), "pill idle: off → the ring while it writes")
    i.stage = .cleaning
    check(R.phase(i) == .transcribing(.releasing), "pill idle: off → the ring while it goes in")
    i.stage = .typed
    i.typedHold = true
    check(R.phase(i) == .transcribing(.done), "pill idle: off → the ring's full hold")
    i.typedHold = false
    check(R.phase(i) == .hidden, "pill idle: off → gone once the dictation ended")
    i.recovered = "복사된 말"
    check(R.phase(i) == .recovered("복사된 말"), "pill idle: off → the copied words still show")
    i.recovered = nil
    i.error = "입력하지 못했어요"
    check(R.phase(i) == .error("입력하지 못했어요"), "pill idle: off → a failure still says its line")
    i.error = nil
    i.stage = .none
    check(R.phase(i) == .hidden, "pill idle: off → hidden with nothing running")
    i.showIdle = true
    i.enabled = false
    check(R.phase(i) == .hidden, "pill idle: the pill's own switch still wins")
    check(R.size(.hidden) == R.idleSize, "pill idle: hidden keeps the sliver's size to fade from")
}

// MARK: - The Settings row

private func pillIdleSettingsTests() {
    let rows = { (s: ArisSettingsSnapshot) in ArisSettingsBuilder.sections(.dictation, s).flatMap(\.rows) }
    let row = { (s: ArisSettingsSnapshot, id: String) in rows(s).first { $0.id == id } }
    var s = ArisSettingsSnapshot()
    check(s.dictationPillIdle, "settings: 쉴 때도 보이기 is on by default")
    check(row(s, "dictation.pillIdle")?.control == .toggle(.dictationPillIdle, true, enabled: true),
          "settings: 쉴 때도 보이기 is a switch, on and enabled with the pill on")
    check(row(s, "dictation.pillIdle")?.title == "쉴 때도 보이기" && row(s, "dictation.pillIdle")?.desc == "끄면 받아 쓸 때만 나타나요.",
          "settings: 쉴 때도 보이기's words")
    let screen = ArisSettingsBuilder.sections(.dictation, s).first { $0.id == "dictation.screen" }
    check(screen?.rows.map(\.id) == ["dictation.pill", "dictation.pillIdle"], "settings: 화면 has the pill switch, then 쉴 때도 보이기 under it")
    s.dictationPill = false
    check(row(s, "dictation.pillIdle")?.control == .toggle(.dictationPillIdle, true, enabled: false),
          "settings: 쉴 때도 보이기 is greyed while the pill is off")
    s.dictationPill = true
    s.dictationPillIdle = false
    check(row(s, "dictation.pillIdle")?.control == .toggle(.dictationPillIdle, false, enabled: true), "settings: 쉴 때도 보이기 off shows off")
    check(ArisSettingsIndex.entry("dictation.pillIdle")?.page == .dictation, "settings search: 쉴 때도 보이기 is in the catalog")
    check(ArisSettingsIndex.search("쉴 때").contains { $0.id == "dictation.pillIdle" }, "settings search: '쉴 때' finds it")
    check(ArisSettingsBuilder.searchable(ArisSettingsSnapshot()).contains("dictation.pillIdle"), "settings search: the row is searchable")
}

// MARK: - Wiring

private func pillIdleWiringTests() {
    let center = idleSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(center.contains("Key<Bool>(\"arisDictationPillIdle\", default: true)"), "pill idle: arisDictationPillIdle defaults on")
    check(center.contains("Defaults.publisher(.arisDictationPillIdle"), "pill idle: the switch is watched live")
    check(center.contains("showIdle: Defaults[.arisDictationPillIdle]"), "pill idle: the center feeds the switch to the rule")
    let live = idleSource("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("@Default(.arisDictationPillIdle) private var dictationPillIdle") && live.contains("s.dictationPillIdle = dictationPillIdle")
          && live.contains("case .dictationPillIdle: dictationPillIdle = on ?? dictationPillIdle"), "pill idle: Settings reads and writes the key")
    let strings = idleSource("Aris/components/Settings/Settings.xcstrings")
    check(strings.contains("\"쉴 때도 보이기\"") && strings.contains("Show while idle")
          && strings.contains("\"끄면 받아 쓸 때만 나타나요.\"") && strings.contains("When off, it appears only while you dictate."),
          "pill idle: the row in English")
}
