// Tests for the audited notch fixes (qa/audit-1110/notch.json): volume and brightness answer from whether anything
// really moved (platform-1), the side notches at an edge two displays share (side-1), a tab turned off stops its
// background work (side-2), "다시 시작" starts the copy that is running (platform-2), and the right side notch opens
// by a key (imp-3). Everything here runs on fakes: no real volume, brightness, key or panel is touched.
// Called from main.swift; uses its check().
import AppKit
import CoreAudio
import Foundation

func runFixNotchTests() {
    controlReplyTests()
    volumeReportTests()
    toolsVolumeTests()
    fixNotchBlocking { await brightnessReportTests() }
    sharedEdgeTests()
    tabWorkTests()
    relaunchTargetTests()
    rightPanelKeyTests()
}

/// Runs an async test on the main actor and waits for it, keeping the main run loop turning.
private func fixNotchBlocking(_ body: @escaping @MainActor () async -> Void) {
    let done = FixNotchBox(false)
    Task { @MainActor in
        await body()
        done.value = true
    }
    while !done.value { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

private final class FixNotchBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

// MARK: - platform-1: what Aris says and logs

private func controlReplyTests() {
    check(ArisControl(.volume(.up)) == .volume(.up) && ArisControl(.brightness(.set(30))) == .brightness(.set(30)),
          "control: a spoken volume or brightness change is one")
    check(ArisControl(.brightness(.mute)) == nil && ArisControl(.tellTime) == nil && ArisControl(.media(.play)) == nil,
          "control: 밝기 음소거 and everything else are not (they go where they went before)")

    let levels: [ArisIntent.Level] = [.up, .down, .set(40), .mute]
    check(levels.allSatisfy { ArisControl.volume($0).reply(changed: true, korean: true) == ArisIntent.volume($0).acknowledgement(korean: true) }
          && levels.dropLast().allSatisfy { ArisControl.brightness($0).reply(changed: true, korean: false) == ArisIntent.brightness($0).acknowledgement(korean: false) },
          "control: a change that happened is said as before (볼륨 올렸어요)")
    let done = ["올렸어요", "낮췄어요", "맞췄어요", "바꿨어요"]
    check(levels.allSatisfy { level in
        let volume = ArisControl.volume(level).reply(changed: false, korean: true), brightness = ArisControl.brightness(level).reply(changed: false, korean: true)
        return !done.contains(where: volume.contains) && !done.contains(where: brightness.contains)
    }, "control: when nothing changed Aris never says it did")
    check(ArisControl.volume(.up).reply(changed: false, korean: true).contains("볼륨을 바꿀 수 없어요")
          && ArisControl.brightness(.up).reply(changed: false, korean: true).contains("밝기를 바꾸지 못했어요"),
          "control: it says the volume or the brightness could not be changed")
    check(ArisControl.volume(.set(40)).reply(changed: false, korean: false).lowercased().contains("can't")
          && ArisControl.brightness(.down).reply(changed: false, korean: false).lowercased().contains("couldn't"),
          "control: and the same in English")

    check(ArisControl.volume(.up).logSummary(changed: true) == "볼륨 올림" && ArisControl.volume(.down).logSummary(changed: true) == "볼륨 낮춤"
          && ArisControl.volume(.set(40)).logSummary(changed: true) == "볼륨 40" && ArisControl.volume(.mute).logSummary(changed: true) == "음소거 바꿈",
          "control: a volume change that happened gets its 한 일 line")
    check(levels.allSatisfy { ArisControl.volume($0).logSummary(changed: false) == nil },
          "control: a volume change that did not happen leaves no 한 일 line (nothing to undo)")
    check(levels.allSatisfy { ArisControl.brightness($0).logSummary(changed: true) == nil }, "control: brightness is not logged, as before")

    check(ArisControl.volumeCommand(.up) == .up && ArisControl.volumeCommand(.down) == .down && ArisControl.volumeCommand(.mute) == .toggleMute
          && ArisControl.volumeCommand(.set(40)) == .set(0.4), "control: 볼륨 40 is 40 % on the output")
}

// MARK: - platform-1: the volume reports whether anything changed

/// An output device as CoreAudio shows it: `settable` false is an HDMI or DisplayPort output (no level the Mac can set).
private final class FixNotchOutput: ArisAudioOutput, @unchecked Sendable {
    var device: AudioDeviceID? = 7
    var level: Float32? = 0.5
    var settable = true
    var muted = false
    var mutable = true
    var levelWrites: [Float32] = []
    var muteWrites: [Bool] = []

    func defaultDevice() -> AudioDeviceID? { device }
    func hasMute(_ device: AudioDeviceID) -> Bool { mutable }
    func isMuted(_ device: AudioDeviceID) -> Bool { muted }
    func setMuted(_ device: AudioDeviceID, _ on: Bool) { muted = on; muteWrites.append(on) }
    func volume(_ device: AudioDeviceID) -> Float32? { level }
    func canSetVolume(_ device: AudioDeviceID) -> Bool { settable }
    func setVolume(_ device: AudioDeviceID, _ value: Float32) { level = value; levelWrites.append(value) }
}

private func volumeReportTests() {
    let normal = FixNotchOutput()
    let volume = ArisVolume(output: normal, interval: 0.01)
    let up = volume.perform(.up)
    volume.waitUntilIdle()
    check(up && normal.level == 0.5625, "volume: on an ordinary output a step up is reported as a change, and written")
    check(volume.perform(.toggleMute) && normal.muted, "volume: muting an output that has a mute is a change")

    // HDMI or DisplayPort: no level, no mute. macOS greys its slider out.
    let hdmi = FixNotchOutput()
    hdmi.level = nil; hdmi.settable = false; hdmi.mutable = false
    let display = ArisVolume(output: hdmi, interval: 0.01)
    let commands: [ArisVolumeCommand] = [.up, .down, .set(0.4), .set(0), .toggleMute]
    let answers = commands.map { display.perform($0) }
    display.waitUntilIdle()
    check(answers.allSatisfy { !$0 }, "volume: on an output with no level or mute to set (HDMI, DisplayPort) nothing is reported as changed")
    check(hdmi.levelWrites.isEmpty && hdmi.muteWrites.isEmpty, "volume: and nothing is written to it")
    hdmi.level = 0.5; hdmi.settable = true
    let later = display.perform(.toggleMute)
    display.waitUntilIdle()
    check(later && hdmi.levelWrites == [0], "volume: the refused commands left no software mute behind (the next mute still mutes)")

    // A level that reads but can't be set.
    let fixed = FixNotchOutput()
    fixed.settable = false; fixed.mutable = false
    let line = ArisVolume(output: fixed, interval: 0.01)
    let fixedUp = line.perform(.up)
    line.waitUntilIdle()
    check(!fixedUp && fixed.levelWrites.isEmpty, "volume: a level that can be read but not set is not a change either")

    // A mute but no level: only the mute can change.
    let muteOnly = FixNotchOutput()
    muteOnly.settable = false
    let switched = ArisVolume(output: muteOnly, interval: 0.01)
    let muteOnlyUp = switched.perform(.up)
    let muteOnlyMute = switched.perform(.toggleMute)
    switched.waitUntilIdle()
    check(!muteOnlyUp && muteOnlyMute && muteOnly.muted && muteOnly.levelWrites.isEmpty, "volume: an output with only a mute reports the mute, never a level")

    let none = FixNotchOutput()
    none.device = nil
    check(!ArisVolume(output: none, interval: 0.01).perform(.up), "volume: no output device, nothing changed")
}

// MARK: - platform-1: aris-tools volume

private func toolsVolumeTests() {
    let speakers = ArisActions.volumeSettings("output volume:50, input volume:73, alert volume:100, output muted:false")
    check(speakers.level == 50 && speakers.muted == false, "tools volume: the output's level and mute are read from macOS's volume settings")
    let muted = ArisActions.volumeSettings("output volume:0, input volume:73, alert volume:100, output muted:true")
    check(muted.level == 0 && muted.muted == true, "tools volume: a muted output reads as muted")
    let hdmi = ArisActions.volumeSettings("output volume:missing value, input volume:missing value, alert volume:100, output muted:missing value")
    check(hdmi.level == nil && hdmi.muted == nil, "tools volume: an HDMI or DisplayPort output has neither")
    check(ArisActions.volumeSettings("").level == nil && ArisActions.volumeSettings("nonsense").muted == nil, "tools volume: an answer it can't read has neither")

    check(["up", "down", "40", "0", "mute", "unmute"].allSatisfy { ArisActions.volumeRefusal($0, speakers) == nil },
          "tools volume: an ordinary output takes every command")
    check(["up", "down", "40", "0"].allSatisfy { ArisActions.volumeRefusal($0, hdmi)?.contains("nothing was changed") == true },
          "tools volume: a level for an output that has none is refused, saying nothing was changed")
    check(["mute", "unmute"].allSatisfy { ArisActions.volumeRefusal($0, hdmi)?.contains("nothing was changed") == true },
          "tools volume: so is a mute for an output that has none")
    check(ArisActions.volumeRefusal("mute", (level: 50, muted: nil)) != nil && ArisActions.volumeRefusal("30", (level: 50, muted: nil)) == nil,
          "tools volume: an output with a level but no mute still takes a level")
}

// MARK: - platform-1: the brightness reports whether anything changed

@MainActor
private func brightnessReportTests() async {
    let took = ArisBrightness(adjust: { _ in true }, set: { _ in true })
    let tookStep = await took.change(by: 0.15), tookLevel = await took.change(to: 0.3)
    check(tookStep && tookLevel, "brightness: a display that took the change reports it")

    // A third-party display with the lid closed, or a helper that fails: the helper answers "no".
    let refused = ArisBrightness(adjust: { _ in false }, set: { _ in false })
    let refusedStep = await refused.change(by: 0.15), refusedLevel = await refused.change(to: 0.3)
    check(!refusedStep && !refusedLevel, "brightness: a display that can't be changed reports that nothing changed")

    // The helper never answers at all.
    let silent = ArisBrightness(adjust: { _ in try? await Task.sleep(for: .seconds(60)); return true },
                                set: { _ in try? await Task.sleep(for: .seconds(60)); return true },
                                patience: .milliseconds(60))
    let started = ContinuousClock.now
    let silentStep = await silent.change(by: 0.15), silentLevel = await silent.change(to: 0.3)
    check(!silentStep && !silentLevel && ContinuousClock.now - started < .seconds(2), "brightness: a helper that never answers is nothing changed, after a short wait")

    // Steps asked while one is on its way are sent together next: each hears how its own send went.
    let sent = FixNotchBox<[Float]>([])
    let gate = FixNotchBox<CheckedContinuation<Void, Never>?>(nil)
    let queued = ArisBrightness(adjust: { delta in
        sent.value.append(delta)
        if sent.value.count == 1 { await withCheckedContinuation { gate.value = $0 } }
        return sent.value.count == 1
    }, set: { _ in true })
    async let first = queued.change(by: 0.15)
    while gate.value == nil { await Task.yield() }
    async let second = queued.change(by: 0.15)
    async let third = queued.change(by: 0.15)
    for _ in 0..<20 { await Task.yield() }
    gate.value?.resume()
    let results = await [first, second, third]
    check(sent.value.count == 2 && abs(sent.value[1] - 0.3) < 0.0001, "brightness: steps asked meanwhile still go out together (\(sent.value))")
    check(results == [true, false, false], "brightness: each step hears how its own send went, not the one before it (\(results))")

    // Up then down while one is on its way cancel out: nothing more is sent, and both still get an answer.
    let cancelSent = FixNotchBox<[Float]>([])
    let cancelGate = FixNotchBox<CheckedContinuation<Void, Never>?>(nil)
    let cancelling = ArisBrightness(adjust: { delta in
        cancelSent.value.append(delta)
        if cancelSent.value.count == 1 { await withCheckedContinuation { cancelGate.value = $0 } }
        return true
    }, set: { _ in true })
    async let lead = cancelling.change(by: 0.15)
    while cancelGate.value == nil { await Task.yield() }
    async let upMore = cancelling.change(by: 0.15)
    async let backDown = cancelling.change(by: -0.15)
    for _ in 0..<20 { await Task.yield() }
    cancelGate.value?.resume()
    let cancelled = await [lead, upMore, backDown]
    check(cancelSent.value.count == 1 && cancelled == [true, true, true], "brightness: steps that cancel out are answered without another send")
}

// MARK: - side-1: an edge two displays share

private func sharedEdgeTests() {
    // A laptop (left) and a taller monitor to its right, bottoms aligned; a third display above the laptop.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let monitor = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    let above = CGRect(x: 0, y: 982, width: 1512, height: 982)
    let two = [laptop, monitor]
    check(ArisSideEdgeRules.isShared(.right, of: laptop, at: 500, displays: two) && ArisSideEdgeRules.isShared(.left, of: monitor, at: 500, displays: two),
          "shared edge: where two displays touch, that edge is shared on both of them")
    check(!ArisSideEdgeRules.isShared(.left, of: laptop, at: 500, displays: two) && !ArisSideEdgeRules.isShared(.right, of: monitor, at: 500, displays: two),
          "shared edge: the outer edges are each display's own")
    check(!ArisSideEdgeRules.isShared(.left, of: monitor, at: 1030, displays: two),
          "shared edge: where the taller display rises past its neighbour, its edge is its own again")
    check(!ArisSideEdgeRules.isShared(.left, of: laptop, at: 500, displays: [laptop, above]) && !ArisSideEdgeRules.isShared(.right, of: laptop, at: 500, displays: [laptop, above]),
          "shared edge: a display above shares no side edge")
    check(!ArisSideEdgeRules.isShared(.right, of: laptop, at: 500, displays: [laptop]), "shared edge: one display shares nothing")

    check(ArisSideEdgeRules.comesOut(near: true, shared: false, restedFor: 0), "shared edge: at an edge of its own the sliver is out the moment the pointer arrives")
    check(!ArisSideEdgeRules.comesOut(near: true, shared: true, restedFor: 0) && !ArisSideEdgeRules.comesOut(near: true, shared: true, restedFor: 0.08),
          "shared edge: a pointer crossing to the other display brings no sliver out (and no tap)")
    check(ArisSideEdgeRules.comesOut(near: true, shared: true, restedFor: ArisSideEdgeRules.restAtSharedEdge) && ArisSideEdgeRules.comesOut(near: true, shared: true, restedFor: 2),
          "shared edge: resting there brings it out, and it stays while the pointer does")
    check(!ArisSideEdgeRules.comesOut(near: false, shared: false, restedFor: 5) && !ArisSideEdgeRules.comesOut(near: false, shared: true, restedFor: 5),
          "shared edge: away from the edge it is never out")
    check(ArisSideEdgeRules.restAtSharedEdge >= 0.1 && ArisSideEdgeRules.restAtSharedEdge <= 0.25, "shared edge: the rest is longer than a crossing and shorter than a wait")

    // The open panel belongs to the display it opened on, whichever display the pointer is on now.
    let size = CGSize(width: 232, height: 580)
    let panel = ArisSideEdgeRules.panelRect(.left, in: laptop, size: size)
    check(panel == CGRect(x: 0, y: 201, width: 232, height: 580) && ArisSideEdgeRules.panelRect(.right, in: monitor, size: size) == CGRect(x: 3200, y: 250, width: 232, height: 580),
          "open panel: against its display's edge, centred down the side")
    let sameSpotNextDoor = CGPoint(x: monitor.minX + 100, y: monitor.midY)
    check(panel.contains(CGPoint(x: 100, y: 491)) && !panel.contains(sameSpotNextDoor),
          "open panel: a click at the same spot on the other display is outside it (so it closes)")
}

// MARK: - side-2: a tab turned off stops what runs behind it

private func tabWorkTests() {
    check(ArisSideTabWork.pollsUsage(hidden: []) && ArisSideTabWork.pollsUsage(hidden: ["clipboard", "todo"]),
          "tab work: the plan limits are read every few minutes while the 사용량 tab shows")
    check(!ArisSideTabWork.pollsUsage(hidden: ["usage"]), "tab work: with the 사용량 tab off they are not")

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check(ArisSideTabWork.readsUsageOnce(hidden: ["usage"], lastRead: nil, now: now, every: 180),
          "tab work: the settings window still gets one read when it comes up with the tab off")
    check(!ArisSideTabWork.readsUsageOnce(hidden: ["usage"], lastRead: now.addingTimeInterval(-30), now: now, every: 180)
          && ArisSideTabWork.readsUsageOnce(hidden: ["usage"], lastRead: now.addingTimeInterval(-200), now: now, every: 180),
          "tab work: but not again while that read is fresher than the timer's would be")
    check(!ArisSideTabWork.readsUsageOnce(hidden: [], lastRead: nil, now: now, every: 180),
          "tab work: with the tab on the timer already reads, so the settings window asks for nothing more")

    check(ArisSideTabWork.takesClipboardKey(hidden: []) && ArisSideTabWork.takesClipboardKey(hidden: ["usage", "history"]),
          "tab work: ⌃⌥V is Aris's while the 클립보드 tab shows")
    check(!ArisSideTabWork.takesClipboardKey(hidden: ["clipboard"]), "tab work: with the 클립보드 tab off the key is left to the app in front")
}

// MARK: - platform-2: "다시 시작" starts the copy that is running

private func relaunchTargetTests() {
    let running = URL(fileURLWithPath: "/Users/p/aris-worktree/build-release/Build/Products/Release/Aris.app")
    let registered = URL(fileURLWithPath: "/Applications/Aris.app"), named = URL(fileURLWithPath: "/tmp/Other/Aris.app")
    var asked = 0
    let system = { () -> URL? in asked += 1; return registered }
    check(ArisRelauncher.target(asked: nil, running: running, exists: { _ in true }, registered: system) == running && asked == 0,
          "relaunch: with several copies on disk, the one that is running is started again (the system's pick is not even asked)")
    check(ArisRelauncher.target(asked: named, running: running, exists: { _ in true }, registered: system) == named && asked == 0,
          "relaunch: a copy named by the caller is the one started")
    check(ArisRelauncher.target(asked: nil, running: running, exists: { _ in false }, registered: system) == registered,
          "relaunch: a running copy that was moved or deleted falls back to the system's pick")
    check(ArisRelauncher.target(asked: nil, running: URL(fileURLWithPath: "/usr/local/bin"), exists: { _ in true }, registered: system) == registered,
          "relaunch: so does one that isn't an app bundle")
    check(ArisRelauncher.target(asked: nil, running: running, exists: { _ in false }, registered: { nil }) == nil,
          "relaunch: nothing to start is nothing (Aris keeps running)")
}

// MARK: - imp-3: the right side notch opens by a key

private func rightPanelKeyTests() {
    let fresh = ArisSettingsSnapshot()
    let side = ArisSettingsBuilder.sections(.notch, fresh).first { $0.id == "notch.side" }
    check(side?.rows.map(\.id) == ["notch.unhide", "notch.clipKey", "notch.rightKey"], "right panel key: its row sits right after the left side's")
    let row = side?.rows.last
    check(row?.title == "오른쪽 사이드 노치 열기" && row?.control == .shortcut(name: "openRightPanel", caps: []),
          "right panel key: no key until the user picks one (nothing is taken from other apps)")
    var picked = ArisSettingsSnapshot()
    picked.rightPanelCaps = ["⌃", "⌥", "T"]
    check(ArisSettingsBuilder.sections(.notch, picked).flatMap(\.rows).first { $0.id == "notch.rightKey" }?.control == .shortcut(name: "openRightPanel", caps: ["⌃", "⌥", "T"]),
          "right panel key: the key he picked shows on the row")

    let desc = { (hidden: Set<String>) -> String in
        var s = ArisSettingsSnapshot()
        s.hiddenSideTabs = hidden
        return ArisSettingsBuilder.sections(.notch, s).flatMap(\.rows).first { $0.id == "notch.rightKey" }?.desc ?? ""
    }
    check(desc([]) == desc(["todo"]) && desc([]) == desc(["clipboard", "usage"]) && desc([]) != desc(["todo", "calendar"]) && desc(["todo", "calendar"]).contains("꺼져"),
          "right panel key: the row says so while every right tab is off, and only then")
    check(ArisSettingsIndex.search("오른쪽 사이드 노치 열기").contains { $0.id == "notch.rightKey" } && ArisSettingsIndex.search("할 일").contains { $0.id == "notch.rightKey" },
          "right panel key: a search finds the row")

    check(ArisSideTabWork.takesRightKey(hidden: []) && ArisSideTabWork.takesRightKey(hidden: ["todo"]) && ArisSideTabWork.takesRightKey(hidden: ["calendar", "history", "clipboard"]),
          "right panel key: the key is Aris's while the right side has a tab left")
    check(!ArisSideTabWork.takesRightKey(hidden: ["todo", "calendar"]), "right panel key: with every right tab off the key is left to the app in front")
    check(ArisSideTabChoice.resolve(.todo, hidden: ["todo"]) == .calendar && ArisSideTabChoice.resolve(.todo, hidden: ["todo", "calendar"]) == nil,
          "right panel key: it opens the tab that is left, and nothing when none is")
}
