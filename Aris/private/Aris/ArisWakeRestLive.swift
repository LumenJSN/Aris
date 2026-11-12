//
//  ArisWakeRestLive.swift
//  Aris
//
//  The live side of ArisWakeRest: reads the facts (the lid, the displays, the power, who uses a microphone) without
//  any permission and without opening anything, keeps what the notch and the ✦ menu show while the wake word rests,
//  writes the log's one line per rest and per return, and looks again when macOS says something changed (a
//  microphone started or stopped somewhere, the power mode, the displays) and on a slow clock in between.
//  What a look costs: asking "is any microphone running" is a tenth of a millisecond; only when one is, every audio
//  process is asked whether it records (about a millisecond, off the main thread). Armed, that is once in ten
//  seconds; resting for another app, the cheap question every two.
//

import AppKit
import CoreAudio
import IOKit
import IOKit.ps
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "microphone")

/// The facts, read now. Nothing here opens a device or asks for a permission; safe off the main thread.
enum ArisWakeRestProbe {
    static func facts() -> ArisWakeRest.Facts {
        let recorder = recorder()
        return ArisWakeRest.Facts(lidClosed: lidClosed(), externalDisplays: externalDisplays(),
                                  lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, onBattery: onBattery(),
                                  recorder: recorder.map { $0.bundle ?? "" }, recorderPid: recorder?.pid)
    }

    /// The lid's switch, from the power manager's registry entry; nil on a Mac without a lid.
    static func lidClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool
    }

    /// Displays that are on and not the Mac's own.
    static func externalDisplays() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 0 }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return 0 }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 }.count
    }

    static func onBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        return (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPMBatteryPowerKey
    }

    /// Another app that records now (ArisWakeRest.recorder). First the cheap question, whether any input device runs
    /// at all (kAudioDevicePropertyDeviceIsRunningSomewhere); only then who: Aris's own microphone runs one too.
    static func recorder() -> ArisOtherAudio.Process? {
        guard ArisMicDevices.all().contains(where: { $0.hasInput && isRunningSomewhere($0.id) }) else { return nil }
        let recording = processObjects().filter { flag($0, kAudioProcessPropertyIsRunningInput) }.compactMap { object -> ArisOtherAudio.Process? in
            guard let pid: Int32 = number(object, kAudioProcessPropertyPID) else { return nil }
            return ArisOtherAudio.Process(object: object, pid: pid, bundle: bundle(of: object), output: false, input: true)
        }
        return ArisWakeRest.recorder(recording, ownPid: ProcessInfo.processInfo.processIdentifier)
    }

    static func isRunningSomewhere(_ device: AudioDeviceID) -> Bool { flag(device, kAudioDevicePropertyDeviceIsRunningSomewhere) }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        var where_ = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func number<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var where_ = address(selector)
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        (number(object, selector) as UInt32?).map { $0 != 0 } ?? false
    }

    private static func bundle(of object: AudioObjectID) -> String? {
        var where_ = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }
}

@MainActor
final class ArisWakeRestLive: ObservableObject {
    static let shared = ArisWakeRestLive()

    /// Why the wake word rests now, and the app on the microphone when that is why and it has a name: what the open
    /// notch and the ✦ menu say. nil while it listens (or is off).
    @Published private(set) var reason: ArisWakeRest.Reason?
    @Published private(set) var app: String?

    /// The line for the notch's row and the menu; nil while there is nothing to say.
    var words: String? { reason.map { ArisWakeRest.words($0, app: app, english: ArisUIWords.english) } }

    /// The wake word's microphone must stay closed now, also while Aris talks (ArisController.armBargeIn): it rests,
    /// or the facts just asked for a rest that a turn has kept it from taking yet.
    var keepsMicrophoneClosed: Bool { reason != nil || wanted }

    private var facts = ArisWakeRest.Facts()
    private var factsAt: TimeInterval = -.infinity
    private var micUse = ArisWakeRest.MicUse()
    private var restLog = ArisWakeRest.Log()
    /// Asks the controller to look at the wake word again; false when a turn or a check is in the way just now.
    private var changed: (() -> Bool)?
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var looking = false
    /// The facts as last read ask for a rest (the lid, the battery, another app's microphone).
    private var wanted = false
    private var watching = false
    private var deviceWatch: ArisMicWatch?
    private var deviceListeners: [(AudioDeviceID, AudioObjectPropertyListenerBlock)] = []
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.wake-rest", qos: .utility)

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    /// Facts this fresh are not read again.
    private static let freshFor: TimeInterval = 1
    /// How soon to look again when a turn or a check kept the wake word from following the facts.
    private static let retryAfter: TimeInterval = 1

    /// Before the wake word is armed: the facts as they are now, written into its state.
    func fill(_ state: inout ArisWakeArm.State) {
        if Self.now - factsAt > Self.freshFor {
            facts = ArisWakeRestProbe.facts()
            factsAt = Self.now
        }
        ArisWakeRest.apply(facts, micInUse: micUse.note(recording: recording(facts), at: Self.now), to: &state)
    }

    /// Another app records, and the rest for that is not switched off (ArisWakeRest.otherAppsKey).
    private func recording(_ facts: ArisWakeRest.Facts) -> Bool {
        facts.recorder != nil && ArisWakeRest.restsForOtherApps(setting: UserDefaults.standard.string(forKey: ArisWakeRest.otherAppsKey))
    }

    /// What the wake word's state came to: kept for the notch and the menu, logged once per change, and the facts
    /// watched for as long as the wake word is on and the screen is here (the screen coming back arms it anyway).
    func note(_ state: ArisWakeArm.State, onChange: @escaping () -> Bool) {
        let rests = ArisWakeRest.reason(state)
        if let line = restLog.line(for: rests, wakeWordOn: ArisWakeRest.mayRun(state)) { log.notice("\(line, privacy: .public)") }
        if reason != rests { reason = rests }
        let name = rests == .micInUse ? appName() : nil
        if app != name { app = name }
        changed = onChange
        watch(ArisWakeRest.mayRun(state) && !state.screenAway, every: ArisWakeRest.recheckEvery(rests))
    }

    private func appName() -> String? {
        guard let recorder = facts.recorder else { return nil }
        let apps = NSWorkspace.shared.runningApplications.map {
            ArisWakeRest.App(pid: $0.processIdentifier, bundle: $0.bundleIdentifier, name: $0.localizedName, regular: $0.activationPolicy == .regular)
        }
        return ArisWakeRest.appName(recorder: recorder, pid: facts.recorderPid, among: apps)
    }

    // MARK: - Looking again

    private func watch(_ on: Bool, every seconds: TimeInterval) {
        guard on else {
            timer?.invalidate()
            timer = nil
            interval = 0
            return
        }
        startNotices()
        guard timer == nil || interval != seconds else { return }
        timer?.invalidate()
        interval = seconds
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.look() } }
        timer.tolerance = seconds / 4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Once: macOS's own notices that a fact may have changed.
    private func startNotices() {
        guard !watching else { return }
        watching = true
        let look: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.look() } }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main, using: look)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: look)
        deviceWatch = ArisMicWatch { [weak self] in
            self?.listenToDevices()
            self?.look()
        }
        listenToDevices()
    }

    /// A microphone starting or stopping anywhere is told at once (kAudioDevicePropertyDeviceIsRunningSomewhere).
    private func listenToDevices() {
        for (device, block) in deviceListeners {
            var where_ = Self.runningSomewhere
            AudioObjectRemovePropertyListenerBlock(device, &where_, .main, block)
        }
        deviceListeners = ArisMicDevices.all().filter(\.hasInput).compactMap { device in
            var where_ = Self.runningSomewhere
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.look() } }
            return AudioObjectAddPropertyListenerBlock(device.id, &where_, .main, block) == noErr ? (device.id, block) : nil
        }
    }

    private static let runningSomewhere = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                                     mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    /// Reads the facts off the main thread; when they ask for something else than the wake word is doing, the
    /// controller looks at it again.
    private func look() {
        guard !looking else { return }
        looking = true
        queue.async {
            let fresh = ArisWakeRestProbe.facts()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.took(fresh) } }
        }
    }

    private func took(_ fresh: ArisWakeRest.Facts) {
        looking = false
        facts = fresh
        factsAt = Self.now
        let inUse = micUse.note(recording: recording(fresh), at: Self.now)
        wanted = ArisWakeRest.lidRests(fresh) || ArisWakeRest.lowPowerRests(fresh) || inUse
        let resting = reason.map { [ArisWakeRest.Reason.lidClosed, .lowPower, .micInUse].contains($0) } ?? false
        guard wanted != resting else { return }
        // A turn or a check in the way: looked at again in a moment, so the microphone does not stay open behind it.
        if changed?() == false {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryAfter) { [weak self] in MainActor.assumeIsolated { self?.look() } }
        }
    }

    /// The screen was locked or went to sleep (ArisController.watchScreen closes the microphone itself): the rest is
    /// written down and shown, and nothing is read again until the screen is back.
    func screenWentAway(wakeWordOn: Bool) {
        guard wakeWordOn else { return }
        if let line = restLog.line(for: .screenAway) { log.notice("\(line, privacy: .public)") }
        reason = .screenAway
        app = nil
        watch(false, every: 0)
    }
}

extension ArisController {
    /// The lid, the power or another app's microphone changed (ArisWakeRestLive). A wake word that waits idle is looked
    /// at again: closed while the reason holds, opened when it ended. False when a turn or a check has the microphone
    /// now (asked again in a moment); a conversation between turns follows its own rules and is left alone.
    func wakeRestChanged() -> Bool {
        guard session.phase == .idle, training == nil, listener == nil, wakeListener == nil else { return false }
        guard !conversation.isOpen else { return true }
        waitForWakeWord()
        return true
    }
}
