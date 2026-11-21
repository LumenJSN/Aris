// Tests for dictation-off: Settings › 받아쓰기 › 받아쓰기 쓰기, a master switch for Aris's dictation (the user uses another
// dictation app). On by default; off, the key tap hands nothing on (the key and Esc reach the apps, nothing starts), ⌃⌘V
// is unregistered, the pill is hidden (idle too) and a click where it was does nothing, all live; talking to Aris is
// untouched. Off dims the page's other dictation rows. The app side can't compile here without its packages, so its
// wiring is read from the sources. Called from main.swift; uses its check().
import Foundation

private let offRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func offSource(_ path: String) -> String { (try? String(contentsOf: offRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

func runDictationOffTests() {
    dictationOffDefaultTests()
    dictationOffGateTests()
    dictationOffPillTests()
    dictationOffSettingsTests()
    dictationOffWiringTests()
}

// MARK: - On unless turned off

private func dictationOffDefaultTests() {
    typealias S = ArisDictationSwitch
    check(S.storeKey == "arisDictationOn", "dictation off: kept under arisDictationOn")
    check(S.isOn(nil) && S.isOn(true) && !S.isOn(false), "dictation off: nothing stored means on; a stored off is off")
    check(S.isOn("off") && S.isOn(0 as Int?), "dictation off: a value that isn't a switch's means on (never off by accident)")
    check(ArisSettingsSnapshot().dictationOn, "dictation off: the settings row starts on")
    let state = offSource("Aris/private/Aris/ArisDictationState.swift")
    check(state.contains("static let arisDictationOn = Key<Bool>(ArisDictationSwitch.storeKey, default: true)"),
          "dictation off: the Defaults key is the switch's, on by default")
}

// MARK: - The key

/// The key tap's handling, as it runs: an event goes to the key's state only when the switch lets it.
private func offPresses(_ events: [ArisDictationKey.Event], on: Bool, paused: Bool = false) -> (actions: [ArisDictationKey.Action], idle: Bool) {
    var state = ArisDictationKey.State()
    let start = ContinuousClock.now
    var actions: [ArisDictationKey.Action] = []
    for (i, event) in events.enumerated() where ArisDictationSwitch.reacts(on: on, paused: paused) {
        actions.append(state.handle(event, at: start + .milliseconds(700 * i)))
    }
    return (actions, state.isIdle)
}

private func dictationOffGateTests() {
    typealias S = ArisDictationSwitch
    check(S.reacts(on: true, paused: false), "dictation off: on, the key tap reacts")
    check(!S.reacts(on: false, paused: false), "dictation off: off, the key tap reacts to nothing")
    check(!S.reacts(on: true, paused: true) && !S.reacts(on: false, paused: true), "dictation off: Settings recording a key still pauses it")
    let hold: [ArisDictationKey.Event] = [.down(alone: true), .tick, .up]
    let onRun = offPresses(hold, on: true)
    check(onRun.actions == [.none, .start, .finish], "dictation off: on, holding the key starts (past the tap threshold) and lets go finishes")
    let offRun = offPresses(hold + [.down(alone: true), .escape, .tick, .otherKey], on: false)
    check(offRun.actions.isEmpty && offRun.idle, "dictation off: off, no press starts anything and the key's state stays idle")
    let tap = offSource("Aris/private/Aris/ArisDictationKeyTap.swift")
    check(tap.contains("options: .listenOnly") && tap.components(separatedBy: "options: .defaultTap").count == 2,
          "dictation off: the key tap only listens (the key reaches the apps); only the hands-free Esc tap can take a key")
    let handle = tap.components(separatedBy: "private func handle(").dropFirst().first ?? ""
    let guardAt = handle.range(of: "guard ArisDictationSwitch.reacts(on: ArisDictationSwitch.on, paused: Self.paused) else { return }")
    let deliverAt = handle.range(of: "deliver(state.handle(event")
    check(guardAt != nil && deliverAt != nil && guardAt!.lowerBound < deliverAt!.lowerBound,
          "dictation off: the tap checks the switch before anything is handed on")
    check(tap.contains("let wanted = state.isLocked && ArisController.shared.dictation == .listening"),
          "dictation off: Esc is taken only during a hands-free dictation, which can't start while off")
}

// MARK: - The pill

private func dictationOffPillTests() {
    typealias R = ArisDictationPillRules
    typealias S = ArisDictationSwitch
    check(S.pillOn(dictation: true, pill: true), "dictation off: on with the pill on, the pill takes dictation")
    check(!S.pillOn(dictation: false, pill: true) && !S.pillOn(dictation: false, pill: false) && !S.pillOn(dictation: true, pill: false),
          "dictation off: off, the pill is off whatever 받아쓰기 알약 보이기 says")
    for stage in [R.Stage.none, .listening, .writing, .cleaning, .typed] {
        for hovered in [false, true] {
            var i = R.Inputs()
            i.enabled = S.pillOn(dictation: false, pill: true)
            i.showIdle = true
            i.stage = stage
            i.hovered = hovered
            i.error = "줄"
            check(R.phase(i) == .hidden && !R.phase(i).shown, "dictation off: the pill is hidden (\(stage), hovered \(hovered))")
        }
    }
    var on = R.Inputs()
    on.enabled = S.pillOn(dictation: true, pill: true)
    check(R.phase(on) == .idle, "dictation off: on again, the idle sliver is back")
    let center = offSource("Aris/private/Aris/Dictation/ArisDictationPillCenter.swift")
    check(center.contains("static var on: Bool { ArisDictationSwitch.pillOn(dictation: Defaults[.arisDictationOn], pill: Defaults[.arisDictationPill]) }"),
          "dictation off: the pill's gate reads the switch")
    check(center.contains("Defaults.publisher(.arisDictationOn, options: [])"), "dictation off: the pill hides and comes back live")
    check(center.contains("panel?.ignoresMouseEvents = true"), "dictation off: a hidden pill's panel lets clicks through")
}

// MARK: - Settings › 받아쓰기

private func dictationOffSettingsTests() {
    // Option A: 받아쓰기 is a part of 할 수 있는 일, and its two keys are in 앱 › 단축키.
    let rows = { (s: ArisSettingsSnapshot) in (ArisSettingsBuilder.sections(part: "able.dictation", s) + ArisSettingsBuilder.sections(part: "app.keys", s)).flatMap(\.rows) }
    let row = { (s: ArisSettingsSnapshot, id: String) in rows(s).first { $0.id == id } }
    var s = ArisSettingsSnapshot()
    let first = rows(s).first
    check(first?.id == "dictation.on" && first?.title == "받아쓰기 쓰기" && first?.desc == "끄면 단축키와 알약이 꺼지고, 다른 받아쓰기 앱과 겹치지 않아요.",
          "dictation off: 받아쓰기 쓰기 is the page's first row, with its words")
    check(first?.control == .toggle(.dictationOn, true, enabled: true), "dictation off: the row is a switch, on")
    check(ArisSettingsBuilder.sections(part: "able.dictation", s).first?.rows.count == 1, "dictation off: one row of its own")
    check(row(s, "keys.dictation")?.control == .shortcut(name: ArisDictationKey.Choice.recorderName, caps: s.dictationCaps, enabled: true)
          && row(s, "keys.pasteLast")?.control == .shortcut(name: "pasteLastDictation", caps: s.pasteLastCaps, enabled: true)
          && row(s, "dictation.pill")?.control == .toggle(.dictationPill, true, enabled: true)
          && row(s, "dictation.pillIdle")?.control == .toggle(.dictationPillIdle, true, enabled: true)
          && row(s, "dictation.brainPolish")?.control == .toggle(.dictationBrainPolish, false, enabled: true),
          "dictation off: on, the other rows are as before")
    s.dictationOn = false
    check(row(s, "dictation.on")?.control == .toggle(.dictationOn, false, enabled: true), "dictation off: off shows off, and can be turned back on")
    check(row(s, "keys.dictation")?.control == .shortcut(name: ArisDictationKey.Choice.recorderName, caps: s.dictationCaps, enabled: false),
          "dictation off: the key row is dimmed")
    check(row(s, "keys.pasteLast")?.control == .shortcut(name: "pasteLastDictation", caps: s.pasteLastCaps, enabled: false),
          "dictation off: the paste-last row is dimmed")
    check(row(s, "dictation.pill")?.control == .toggle(.dictationPill, true, enabled: false)
          && row(s, "dictation.pillIdle")?.control == .toggle(.dictationPillIdle, true, enabled: false),
          "dictation off: the pill rows are dimmed (their values kept)")
    check(row(s, "dictation.brainPolish")?.control == .toggle(.dictationBrainPolish, false, enabled: false), "dictation off: polish is dimmed")
    check(ArisSettingsIndex.entry("dictation.on")?.page == .dictation, "dictation off: in the search catalog")
    check(["받아쓰기 끄기", "다른 받아쓰기", "받아쓰기 쓰기"].allSatisfy { q in ArisSettingsIndex.search(q).contains { $0.id == "dictation.on" } },
          "dictation off: '받아쓰기 끄기', '다른 받아쓰기' and its name find it")
    check(ArisSettingsBuilder.searchable(ArisSettingsSnapshot()).contains("dictation.on"), "dictation off: the row is searchable")
    let catalog = (try? Data(contentsOf: offRoot.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data()
    let pairs = ArisSettingsCopy.pairs(catalog: catalog)
    check(pairs["받아쓰기 쓰기"] == "Use dictation" && pairs["끄면 단축키와 알약이 꺼지고, 다른 받아쓰기 앱과 겹치지 않아요."] != nil,
          "dictation off: the row is in English too")
}

// MARK: - Wiring

private func dictationOffWiringTests() {
    let tap = offSource("Aris/private/Aris/ArisDictationKeyTap.swift")
    check(tap.contains("Defaults.publisher(.arisDictationOn, options: [])") && tap.contains("KeyboardShortcuts.disable(.pasteLastDictation)")
          && tap.contains("KeyboardShortcuts.enable(.pasteLastDictation)"),
          "dictation off: ⌃⌘V is unregistered when it goes off and registered again when it comes back, live")
    check(tap.contains("if !ArisDictationSwitch.on { KeyboardShortcuts.disable(.pasteLastDictation) }"),
          "dictation off: off at launch, ⌃⌘V is never Aris's")
    let controller = offSource("Aris/private/Aris/ArisController+Dictation.swift")
    check(controller.contains("guard ArisDictationSwitch.on, dictation != .listening else { return }"),
          "dictation off: a click where the pill was starts nothing")
    check(controller.contains("guard ArisDictationSwitch.on, let text = ArisDictationState.shared.lastText"), "dictation off: paste-last does nothing")
    check(controller.contains("func dictationTurnedOff()") && tap.contains("ArisController.shared.dictationTurnedOff()"),
          "dictation off: turning it off drops a dictation still listening")
    let live = offSource("Aris/components/Settings/ArisLiveSettings.swift")
    check(live.contains("@Default(.arisDictationOn) private var dictationOn") && live.contains("case .dictationOn: dictationOn = on ?? dictationOn")
          && live.contains("s.dictationOn = dictationOn"), "dictation off: the row reads and writes the switch")
    let controls = offSource("Aris/components/Settings/ArisSettingsControls.swift")
    let caps = controls.components(separatedBy: "struct ArisShortcutCapsButton").dropFirst().first ?? ""
    check(caps.contains(".disabled(!enabled)") && caps.contains(".opacity(enabled ? 1 : 0.5)"), "dictation off: a dimmed shortcut is drawn like a dimmed switch")
    // Talking to Aris never reads it.
    let talk = ["Aris/private/Aris/ArisTalkKey.swift", "Aris/private/Aris/ArisWakeWord.swift", "Aris/private/Aris/ArisController+Wake.swift"]
    check(talk.allSatisfy { !offSource($0).contains("ArisDictationSwitch") && !offSource($0).contains("arisDictationOn") },
          "dictation off: the talk key and the wake word don't read it")
    // Finishing the first-run guide never turns it back on.
    let onboarding = (try? FileManager.default.contentsOfDirectory(atPath: offRoot.appendingPathComponent("Aris/private/Aris/Onboarding").path)) ?? []
    let writes = onboarding.filter { $0.hasSuffix(".swift") }.filter {
        let text = offSource("Aris/private/Aris/Onboarding/" + $0)
        return text.contains("arisDictationOn") || text.contains("ArisDictationSwitch") || text.contains("arisDictationPill]")
    }
    check(!onboarding.isEmpty && writes.isEmpty, "dictation off: the first-run guide never touches the switch" + (writes.isEmpty ? "" : " (\(writes))"))
}
