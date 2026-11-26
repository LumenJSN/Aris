// The 1.3.1 hang (2026-11-25): after a day and a half the main thread sat at 100% inside ArisWorldAudio.listen(),
// adding Core Audio listeners and failing to remove them. These cover the fix: listeners kept by key and changed only
// by difference, removal by the exact token that was added (also against the live HAL), coalesced re-reads, the main
// thread watchdog's timing, and the microphone choice (the owner: This Mac by default, like Wispr Flow).
import CoreAudio
import Foundation

func runHangTests() {
    hangListenerGrowthTests()
    hangIdentityTests()
    hangCoalescerTests()
    hangDeviceDiffTests()
    hangSystemInputTests()
    hangFailedAddTests()
    hangLiveHALTests()
    hangStallClockTests()
    hangMicChoiceTests()
    hangMicSettingsRowTests()
    hangWiringTests()
}

// MARK: - The fake Core Audio and clock

private final class FakeHAL: ArisAudioHAL {
    var live: [(key: ArisAudioKey, token: ArisAudioToken)] = []
    var added: Set<ObjectIdentifier> = []
    var removed: [ObjectIdentifier] = []
    var adds = 0
    var unmatchedRemoves = 0
    var failing: Set<ArisAudioKey> = []
    var now = ArisAudioScene(output: 10, inputs: [20, 21])

    func add(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus {
        adds += 1
        if failing.contains(key) { return OSStatus(kAudioHardwareUnspecifiedError) }
        live.append((key, token))
        added.insert(ObjectIdentifier(token))
        return noErr
    }

    /// As the HAL does: noErr whether or not anything matched.
    func remove(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus {
        removed.append(ObjectIdentifier(token))
        if let at = live.firstIndex(where: { $0.key == key && $0.token === token }) { live.remove(at: at) } else { unmatchedRemoves += 1 }
        return noErr
    }

    func scene() -> ArisAudioScene { now }

    /// The HAL telling every listener on `selector` (on its own thread in life; here inline).
    func fire(_ selector: AudioObjectPropertySelector) {
        for entry in live where entry.key.selector == selector { entry.token.fire() }
    }

    func count(_ selector: AudioObjectPropertySelector) -> Int { live.filter { $0.key.selector == selector }.count }
}

private final class FakeClock: @unchecked Sendable {
    private(set) var now: TimeInterval = 0
    private var due: [(at: TimeInterval, work: @Sendable () -> Void)] = []

    var schedule: ArisAudioCoalescer.Schedule { { [self] delay, work in due.append((now + delay, work)) } }

    func advance(_ seconds: TimeInterval) {
        let until = now + seconds
        while let next = due.enumerated().filter({ $0.element.at <= until }).min(by: { $0.element.at < $1.element.at }) {
            due.remove(at: next.offset)
            now = next.element.at
            next.element.work()
        }
        now = until
    }
}

private final class Events: @unchecked Sendable {
    var list: [ArisAudioWatch.Event] = []
    func count(_ event: ArisAudioWatch.Event) -> Int { list.filter { $0 == event }.count }
}

private func makeWatch(_ hal: FakeHAL, _ clock: FakeClock, follows: @escaping () -> Bool = { false }) -> (ArisAudioWatch, Events) {
    let events = Events()
    let watch = ArisAudioWatch(hal: hal, followsSystemInput: follows, schedule: clock.schedule) { events.list.append($0) }
    watch.resync()
    return (watch, events)
}

// MARK: - (a) No growth

private func hangListenerGrowthTests() {
    let hal = FakeHAL(), clock = FakeClock()
    let (watch, events) = makeWatch(hal, clock)
    // Default output, device list, the output's data source, two inputs' running-somewhere; no default input (This Mac).
    check(hal.live.count == 5 && watch.registered.count == 5, "hang: the watch starts with one listener per object and property (\(hal.live.count))")
    let system = hal.live.filter { $0.key.object == AudioObjectID(kAudioObjectSystemObject) }.map { ObjectIdentifier($0.token) }
    var counts: Set<Int> = []
    for change in 0..<200 {
        hal.now.output = change % 2 == 0 ? 11 : 10
        hal.fire(kAudioHardwarePropertyDefaultOutputDevice)
        clock.advance(0.3)
        counts.insert(hal.live.count)
    }
    check(counts == [5], "hang: 200 default-output changes leave exactly 5 listeners, never more (\(counts.sorted()))")
    check(hal.count(kAudioHardwarePropertyDefaultOutputDevice) == 1 && hal.count(kAudioDevicePropertyDataSource) == 1,
          "hang: one default-output listener and one data-source listener after them")
    check(hal.live.filter { $0.key.object == AudioObjectID(kAudioObjectSystemObject) }.map { ObjectIdentifier($0.token) } == system,
          "hang: the system object's listeners are the ones registered at launch, never removed and added again")
    check(events.count(.route) == 200 && hal.unmatchedRemoves == 0, "hang: each change is one route re-read, and every removal matched")
    // The 1.3.1 loop: every route listener left behind ran listen() again on the next change. Here a change heard
    // by however many notices is still one re-read, and the count stays put.
    hal.fire(kAudioHardwarePropertyDefaultOutputDevice)
    hal.fire(kAudioHardwarePropertyDefaultOutputDevice)
    hal.fire(kAudioDevicePropertyDataSource)
    clock.advance(0.3)
    check(events.count(.route) == 201 && hal.live.count == 5, "hang: three notices in a burst are one re-read and add nothing")
}

// MARK: - (b) Remove gets what add got

private func hangIdentityTests() {
    let hal = FakeHAL(), clock = FakeClock()
    let (watch, _) = makeWatch(hal, clock)
    for output in [11, 12, 13] as [AudioObjectID] {
        hal.now.output = output
        hal.fire(kAudioHardwarePropertyDefaultOutputDevice)
        clock.advance(0.3)
    }
    check(hal.removed.count == 3 && hal.removed.allSatisfy(hal.added.contains) && hal.unmatchedRemoves == 0,
          "hang: every remove is handed the identical token its add was (\(hal.removed.count) removed, \(hal.unmatchedRemoves) unmatched)")
    watch.stop()
    check(hal.live.isEmpty && hal.unmatchedRemoves == 0, "hang: stopping takes every listener out, each by its own token")
}

// MARK: - (c) Bursts

private func hangCoalescerTests() {
    final class Count: @unchecked Sendable { var value = 0 }
    let clock = FakeClock(), runs = Count()
    let coalescer = ArisAudioCoalescer(schedule: clock.schedule) { runs.value += 1 }
    for _ in 0..<50 {
        coalescer.poke()
        clock.advance(0.002)
    }
    check(runs.value == 0, "hang: nothing runs inside the window")
    clock.advance(ArisAudioCoalescer.window)
    check(runs.value == 1, "hang: 50 pokes in 100 ms are one re-read (\(runs.value))")
    coalescer.poke()
    clock.advance(ArisAudioCoalescer.window + 0.01)
    check(runs.value == 2, "hang: a poke after the re-read is the next one")
    check(ArisAudioCoalescer.window == 0.25 && ArisAudioWatch.deviceSettle == 0.6, "hang: the windows are 250 ms, and 600 ms for the device list")

    let hal = FakeHAL()
    let (watch, events) = makeWatch(hal, clock)
    let adds = hal.adds
    for _ in 0..<50 {
        hal.fire(kAudioHardwarePropertyDefaultOutputDevice)
        clock.advance(0.002)
    }
    clock.advance(0.3)
    check(events.count(.route) == 1 && hal.adds == adds, "hang: 50 route notices in 100 ms are one re-read, which adds nothing for an unchanged output")
    for _ in 0..<20 { hal.fire(kAudioDevicePropertyDeviceIsRunningSomewhere) }
    clock.advance(0.3)
    check(events.count(.recorder) == 1, "hang: a burst of microphones starting is one look at who records")
    withExtendedLifetime(watch) {}
}

// MARK: - (d) Devices coming and going

private func hangDeviceDiffTests() {
    let hal = FakeHAL(), clock = FakeClock()
    let (watch, events) = makeWatch(hal, clock)
    let running = { (id: AudioObjectID) in ArisAudioKey(object: id, selector: kAudioDevicePropertyDeviceIsRunningSomewhere) }
    var adds = hal.adds, removes = hal.removed.count
    hal.now.inputs = [20, 21, 22]
    hal.fire(kAudioHardwarePropertyDevices)
    clock.advance(0.7)
    check(hal.adds == adds + 1 && hal.removed.count == removes && watch.registered.contains(running(22)),
          "hang: a microphone appearing adds its one listener and touches nothing else")
    check(events.count(.devices) == 1, "hang: the device list's change is told once it settles")
    adds = hal.adds
    removes = hal.removed.count
    let kept = hal.live.filter { $0.key != running(21) }.map { ObjectIdentifier($0.token) }
    hal.now.inputs = [20, 22]
    hal.fire(kAudioHardwarePropertyDevices)
    clock.advance(0.7)
    check(hal.adds == adds && hal.removed.count == removes + 1 && !watch.registered.contains(running(21))
            && hal.live.map { ObjectIdentifier($0.token) } == kept,
          "hang: a microphone going removes only its listener")
}

// MARK: - The default input, only when the choice follows the system

private func hangSystemInputTests() {
    final class Follows: @unchecked Sendable { var value = false }
    let hal = FakeHAL(), clock = FakeClock(), follows = Follows()
    let (watch, _) = makeWatch(hal, clock) { follows.value }
    let input = ArisAudioKey.system(kAudioHardwarePropertyDefaultInputDevice)
    check(!watch.registered.contains(input) && hal.count(kAudioHardwarePropertyDefaultInputDevice) == 0,
          "mic choice: with This Mac no default-input listener is registered")
    follows.value = true
    watch.resync()
    check(watch.registered.contains(input) && hal.count(kAudioHardwarePropertyDefaultInputDevice) == 1, "mic choice: Same as system adds one")
    for _ in 0..<20 {
        hal.fire(kAudioHardwarePropertyDefaultInputDevice)
        clock.advance(0.7)
    }
    check(hal.count(kAudioHardwarePropertyDefaultInputDevice) == 1, "mic choice: and keeps one through 20 default-input changes")
    follows.value = false
    watch.resync()
    check(hal.count(kAudioHardwarePropertyDefaultInputDevice) == 0 && hal.unmatchedRemoves == 0, "mic choice: back to This Mac takes it out")
}

private func hangFailedAddTests() {
    let hal = FakeHAL(), clock = FakeClock()
    let source = ArisAudioKey(object: 10, selector: kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
    hal.failing = [source]
    let (watch, _) = makeWatch(hal, clock)
    check(!watch.registered.contains(source) && hal.live.count == 4, "hang: a listener the HAL refused is not kept as if it were there")
    hal.failing = []
    watch.resync()
    check(watch.registered.contains(source) && hal.live.count == 5, "hang: the next re-read tries it again")
}

// MARK: - The live HAL

/// Against the real Core Audio: the process's own "is audible" property (this test process plays nothing) is turned
/// off and on, which tells its listeners. A listener taken out must not be told; the 1.3.1 way is printed as found.
private func hangLiveHALTests() {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        func hit(_ name: String) { lock.withLock { counts[name, default: 0] += 1 } }
        func count(_ name: String) -> Int { lock.withLock { counts[name] ?? 0 } }
    }
    let counter = Counter()
    let key = ArisAudioKey.system(kAudioHardwarePropertyProcessIsAudible)
    let kept = ArisAudioListenerSet(hal: ArisAudioHALLive { [] }, owner: "test kept")
    let taken = ArisAudioListenerSet(hal: ArisAudioHALLive { [] }, owner: "test taken")
    kept.sync([key]) { _ in { counter.hit("kept") } }
    taken.sync([key]) { _ in { counter.hit("taken") } }
    taken.removeAll()
    // 1.3.1's way, for the record: a stored listener block handed back to remove.
    var address = key.address
    let old: AudioObjectPropertyListenerBlock = { [counter] _, _ in counter.hit("1.3.1") }
    let stored = [old]
    _ = AudioObjectAddPropertyListenerBlock(key.object, &address, nil, stored[0])
    _ = AudioObjectRemovePropertyListenerBlock(key.object, &address, nil, stored[0])
    for value: UInt32 in [0, 1] {
        var audible = value
        _ = AudioObjectSetPropertyData(key.object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &audible)
        Thread.sleep(forTimeInterval: 0.3)
    }
    Thread.sleep(forTimeInterval: 0.3)
    kept.removeAll()
    guard counter.count("kept") > 0 else {
        print("note: live HAL check skipped, Core Audio sent no notice for the process's audible property here")
        return
    }
    check(counter.count("taken") == 0, "hang: on the live HAL a listener taken out is never told again (\(counter.count("taken")))")
    print("note: on the live HAL, 1.3.1's stored listener block after its 'removal' was told \(counter.count("1.3.1")) time(s), the kept one \(counter.count("kept"))")
}

// MARK: - The watchdog's timing

private func hangStallClockTests() {
    var clock = ArisStallClock()
    check(clock.tick(now: 0) == .post && clock.tick(now: 1.9) == .none && clock.tick(now: 2.5) == .stalled(2.5),
          "watchdog: a beat unanswered past 2 s is a stall")
    check(clock.tick(now: 5) == .none && clock.tick(now: 9.9) == .none, "watchdog: said once, not again before 10 s")
    check(clock.tick(now: 10.5) == .stillStuck(10.5) && clock.tick(now: 30) == .none && clock.tick(now: 600) == .none,
          "watchdog: past 10 s once more, still stuck, and then quiet")
    check(clock.answered(now: 700) == .recovered(700) && clock.tick(now: 700.5) == .post, "watchdog: back, with how long it was")
    check(clock.tick(now: 703) == .stalled(2.5) && clock.tick(now: 711) == .stillStuck(10.5),
          "watchdog: the next stall is said again from the start")
    check(ArisStallClock.threshold == 2 && ArisStallClock.stuck == 10, "watchdog: 2 s and 10 s")
}

// MARK: - The microphone choice

private let fakeBuiltInMic = ArisAudioDevice(id: 1, transport: .builtIn, hasInput: true, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
private let fakeSpeakers = ArisAudioDevice(id: 4, transport: .builtIn, hasInput: false, hasOutput: true, uid: "BuiltInSpeakerDevice", name: "MacBook Pro Speakers")
private let fakeAirPods = ArisAudioDevice(id: 2, transport: .bluetooth, hasInput: true, hasOutput: true, uid: "AA-BB:input", name: "the user’s AirPods Pro")
private let fakeUsbMic = ArisAudioDevice(id: 3, transport: .wired, hasInput: true, uid: "usb-mic", name: "Yeti")

private func hangMicChoiceTests() {
    let all = [fakeSpeakers, fakeBuiltInMic, fakeAirPods, fakeUsbMic]
    func plan(_ setting: ArisMicSetting, _ use: ArisMicUse = .wake, input: UInt32?, _ devices: [ArisAudioDevice]) -> ArisMicPlan {
        ArisMicPlan.make(for: use, setting: setting, defaultInput: input, devices: devices)
    }
    check(ArisMicSetting(stored: nil) == .thisMac && ArisMicSetting(stored: "builtIn") == .thisMac && ArisMicSetting(stored: "system") == .system
            && ArisMicSetting(stored: "uid:usb-mic") == .device(uid: "usb-mic") && ArisMicSetting(stored: "uid:") == .thisMac
            && ArisMicSetting(stored: "anything") == .thisMac, "mic choice: nothing stored is This Mac; the stored forms read back")
    check([ArisMicSetting.thisMac, .system, .device(uid: "a:b")].allSatisfy { ArisMicSetting(stored: $0.stored) == $0 }, "mic choice: every choice stores and reads back")
    check(plan(.thisMac, input: fakeAirPods.id, all) == .open(id: 1, transport: .builtIn) && plan(.thisMac, input: fakeUsbMic.id, all) == .open(id: 1, transport: .builtIn),
          "mic choice: This Mac opens the built-in microphone whatever the system input is (AirPods untouched)")
    check(ArisMicSetting.thisMac.pick(all).fallback == nil && ArisMicSetting.thisMac.pick([fakeAirPods, fakeUsbMic]).fallback == .noBuiltIn,
          "mic choice: a Mac without a built-in microphone is a fallback")
    check(plan(.thisMac, input: fakeUsbMic.id, [fakeAirPods, fakeUsbMic]) == .open(id: 3, transport: .wired)
            && plan(.thisMac, input: fakeAirPods.id, [fakeAirPods]) == .pause(.headsetOnly)
            && plan(.thisMac, .talk, input: fakeAirPods.id, [fakeAirPods]) == .open(id: 2, transport: .bluetooth),
          "mic choice: without one, the system's input as 1.3.1 chose it (a headset only for a press)")
    check(plan(.device(uid: "usb-mic"), input: fakeAirPods.id, all) == .open(id: 3, transport: .wired)
            && plan(.device(uid: "AA-BB:input"), input: fakeBuiltInMic.id, all) == .open(id: 2, transport: .bluetooth),
          "mic choice: a chosen device opens by its UID, a headset too when it is the one chosen")
    let gone = ArisMicSetting.device(uid: "gone")
    check(gone.pick(all) == .init(device: fakeBuiltInMic, fallback: .chosenGone) && plan(gone, input: fakeUsbMic.id, all) == .open(id: 1, transport: .builtIn),
          "mic choice: a chosen device that is gone falls back to the built-in one")
    check(gone.pick([fakeAirPods, fakeUsbMic]) == .init(device: nil, fallback: .chosenGone) && plan(gone, input: fakeUsbMic.id, [fakeAirPods, fakeUsbMic]) == .open(id: 3, transport: .wired),
          "mic choice: and without a built-in one to the system's input")
    check(plan(.system, input: fakeUsbMic.id, all) == .open(id: 3, transport: .wired) && plan(.system, input: fakeAirPods.id, all) == .open(id: 1, transport: .builtIn)
            && plan(.system, input: fakeAirPods.id, all) == ArisMicPlan.make(for: .wake, defaultInput: fakeAirPods.id, devices: all),
          "mic choice: Same as system is 1.3.1's rule exactly")
    check(ArisMicSetting.system.followsSystemInput && !ArisMicSetting.thisMac.followsSystemInput && !ArisMicSetting.device(uid: "x").followsSystemInput,
          "mic choice: only Same as system watches the default input")
}

private func hangMicSettingsRowTests() {
    var s = ArisSettingsSnapshot()
    s.microphones = [fakeSpeakers, fakeBuiltInMic, fakeAirPods, fakeUsbMic]
    let row = ArisSettingsBuilder.microphone(s)
    guard case .menu(let key, let options, let selected) = row.control else { return check(false, "mic settings: a menu") }
    check(key == .microphone && selected == "builtIn" && options.map(\.id) == ["builtIn", "system", "uid:AA-BB:input", "uid:usb-mic"]
            && options.map(\.title) == ["이 Mac (내장)", "시스템 설정과 같게", "the user’s AirPods Pro", "Yeti"],
          "mic settings: This Mac (the default), Same as system, then each input by name (\(options.map(\.id)))")
    check(row.desc == "에어팟을 연결해도 이 Mac의 마이크로 들어서 음악 음질이 그대로예요.", "mic settings: the default says why")
    s.microphone = "uid:gone"
    s.microphoneName = "Old Mic"
    let gone = ArisSettingsBuilder.microphone(s)
    if case .menu(_, let options, let selected) = gone.control {
        check(selected == "uid:gone" && options.last == ArisSettingOption(id: "uid:gone", title: "Old Mic"), "mic settings: a chosen device that is gone stays by its name")
    }
    check(gone.desc == "고른 마이크가 연결되어 있지 않아 이 Mac의 마이크로 들어요.", "mic settings: and the line says Aris hears with this Mac's")
    s.microphones = [fakeAirPods]
    check(ArisSettingsBuilder.microphone(s).desc == "고른 마이크가 연결되어 있지 않아 시스템 설정의 입력 기기로 들어요.", "mic settings: or the system's input")
    s.microphone = "builtIn"
    check(ArisSettingsBuilder.microphone(s).desc == "이 Mac에 내장 마이크가 없어 시스템 설정의 입력 기기로 들어요.", "mic settings: no built-in one is said")
    let rows = ArisSettingsBuilder.sections(part: "talk.hear", ArisSettingsSnapshot()).flatMap(\.rows).map(\.id)
    check(rows.prefix(2) == ["ai.hear", "hear.mic"] && ArisSettingsParts.all.first { $0.id == "talk.hear" }?.rows.contains("hear.mic") == true,
          "mic settings: 마이크 sits under the hearing card in 듣기")
    let catalog = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/components/Settings/Settings.xcstrings")
    let pairs = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: catalog.standardized)) ?? Data())
    for korean in ["이 Mac (내장)", "시스템 설정과 같게", "에어팟을 연결해도 이 Mac의 마이크로 들어서 음악 음질이 그대로예요.", "고른 마이크로 들어요.",
                   "고른 마이크가 연결되어 있지 않아 이 Mac의 마이크로 들어요.", "고른 마이크가 연결되어 있지 않아 시스템 설정의 입력 기기로 들어요.",
                   "이 Mac에 내장 마이크가 없어 시스템 설정의 입력 기기로 들어요.", "시스템 설정의 입력 기기를 따라가요. 다른 마이크가 있으면 헤드폰 마이크는 쓰지 않아요.", "고른 마이크"] {
        check(pairs[korean] != nil, "mic settings: \(korean) has its English")
    }
}

// MARK: - Wiring

private func hangSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

private func hangWiringTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardized
    let swift = (FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
        .filter { $0.pathExtension == "swift" && !$0.path.contains("/Tests/") && !$0.path.contains("/.build/") && !$0.path.contains("/build-branch/") }
    let blockUsers = swift.filter { ((try? String(contentsOf: $0, encoding: .utf8)) ?? "").contains("PropertyListenerBlock(") }.map(\.lastPathComponent)
    check(blockUsers.isEmpty, "hang: no Core Audio listener is registered as a block anywhere (they can't be removed): \(blockUsers)")
    let world = hangSource("Aris/private/Aris/World/ArisWorldAudio.swift")
    check(world.contains("ArisAudioWatch(") && !world.contains("func listen()") && !world.contains("ArisMicWatch"),
          "hang: the world's audio listens through one ArisAudioWatch")
    let rest = hangSource("Aris/private/Aris/ArisWakeRestLive.swift")
    check(rest.contains("deviceListeners.sync(") && rest.contains("ArisAudioCoalescer"), "hang: the wake rest's device listeners change by difference")
    check(!hangSource("Aris/private/Aris/ArisMicDevices.swift").contains("final class ArisMicWatch"), "hang: ArisMicWatch is gone")
    let controller = hangSource("Aris/private/Aris/ArisController.swift")
    check(controller.contains("ArisStallWatch.shared.note(doing:"), "watchdog: the turn's phase is told to the stall watch")
    let stall = hangSource("Aris/private/Platform/ArisStallWatch.swift")
    check(!stall.contains("sample(") && !stall.contains("backtrace") && !stall.contains("CGWindowListCreateImage"), "watchdog: no stacks, no captures")
    let plan = hangSource("Aris/private/Aris/ArisMicDevices.swift")
    check(plan.contains("ArisMicPlan.make(for: use, setting: setting,"), "mic choice: every pinned microphone goes through the choice")
}
