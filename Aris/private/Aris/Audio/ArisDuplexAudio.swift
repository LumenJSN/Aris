//
//  ArisDuplexAudio.swift
//  Aris
//
//  Where the rest of Aris meets the duplex engine (ArisAudioEngine), behind `arisDuplexAudio`. With the switch off
//  nothing here makes an engine, reads a device or watches a notification: every call returns at once and the caller
//  goes its old way. With it on:
//  - the engine is made on first use, and watches the screen itself (lock, display sleep, the Mac sleeping stop it at
//    once, whatever the controller does next);
//  - an open conversation holds it (`conversation(open:)`);
//  - any other Aris microphone that opens an engine of its own (ArisMicDevices.pin: dictation, 호출어 녹음, the
//    name's training, a wake word on the old path) stops it first, so the two never hold the microphone together;
//  - whether Aris's line went through the canceller (`lastLineCancelled`) shortens the echo tail the between-turn
//    watch waits for (ArisDuplexRoute.tail).
//

import AppKit
import CoreAudio
import Defaults

extension Defaults.Keys {
    /// The duplex engine (one owner for microphone and speaker, echo cancelled). No settings row yet.
    static let arisDuplexAudio = Key<Bool>(ArisDuplexSwitch.key, default: false)
}

enum ArisDuplexAudio {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var made: ArisAudioEngine?
    nonisolated(unsafe) private static var cancelledLine = false
    nonisolated(unsafe) private static var watchers: [NSObjectProtocol] = []

    /// The engine, made on first use while the switch is on; nil while it is off.
    static var engine: ArisAudioEngine? {
        guard ArisDuplexSwitch.isOn else { return nil }
        let (engine, fresh) = lock.withLock { () -> (ArisAudioEngine, Bool) in
            if let made { return (made, false) }
            let engine = ArisAudioEngine(hardware: ArisVoiceProcessingHardware(), facts: { ArisDuplexDevices.facts(for: $0) },
                                         after: { seconds, work in DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: work) })
            made = engine
            return (engine, true)
        }
        if fresh { DispatchQueue.main.async { watchScreen(engine) } }
        return engine
    }

    /// The engine if it was ever made (a release after the switch went off still reaches it).
    static var existing: ArisAudioEngine? { lock.withLock { made } }

    /// Another Aris microphone is about to open an engine of its own.
    static func legacyMicOpening() { existing?.legacyMicOpening() }

    static func conversation(open: Bool) {
        if open { engine?.conversation(open: true) } else { existing?.conversation(open: false) }
    }

    /// Aris's next line would play through the canceller.
    static var voiceWouldBeCancelled: Bool { existing?.servesVoice ?? false }

    /// Aris's latest line played through the canceller (set by the speaker as each line starts).
    static var lastLineCancelled: Bool {
        get { lock.withLock { cancelledLine } }
        set { lock.withLock { cancelledLine = newValue } }
    }

    /// The lock, the displays' sleep and the Mac's: the microphone closes at once, not after the linger.
    @MainActor private static func watchScreen(_ engine: ArisAudioEngine) {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let away: @Sendable (Notification) -> Void = { _ in engine.away(true) }
        let back: @Sendable (Notification) -> Void = { _ in engine.away(false) }
        watchers = [
            workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: away),
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil, using: away),
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil, using: back),
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil, using: back),
            distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: nil, using: away),
            distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: nil, using: back),
        ]
    }
}

/// The devices as the duplex route needs them, read from Core Audio now (reads properties only; opens nothing).
enum ArisDuplexDevices {
    static func facts(for use: ArisMicUse) -> ArisDuplexRoute.Facts {
        let devices = ArisMicDevices.all()
        let defaultInput = ArisMicDevices.defaultInput()
        let kind = { (id: UInt32?) in id.flatMap { id in devices.first { $0.id == id } }.flatMap { ArisDuplexRoute.Kind(rawValue: $0.transport.rawValue) } }
        let output = defaultOutput().map { id in
            ArisDuplexRoute.Output(id: id, kind: kind(id) ?? .other, dataSource: dataSource(id),
                                   hasInput: devices.first { $0.id == id }?.hasInput ?? false)
        }
        return ArisDuplexRoute.Facts(switchOn: ArisDuplexSwitch.isOn, plannedInput: ArisMicDevices.plan(for: use).device,
                                     defaultInput: defaultInput, inputKind: kind(defaultInput), output: output)
    }

    private static func defaultOutput() -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func dataSource(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var source = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr else { return nil }
        return ArisAudioDevice.fourCC(source)
    }
}
