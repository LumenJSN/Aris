//
//  ArisMicDevices.swift
//  Aris
//
//  The live side of ArisMicPlan: the audio devices as Core Audio lists them now, an engine's microphone pinned to
//  the one device the plan names under the microphone choice (ArisMicSetting; so it never follows the default input
//  to a headset that connects later), and the log line written whenever an Aris microphone opens, pauses or closes
//  (who, and the device's kind; never any audio). The device watch is ArisAudioWatch's. Only reads device
//  properties: nothing here opens a device.
//

import AudioToolbox
import AVFoundation
import CoreAudio
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "microphone")

enum ArisMicDevices {
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func defaultInput() -> UInt32? { device(kAudioHardwarePropertyDefaultInputDevice) }

    private static func device(_ selector: AudioObjectPropertySelector) -> UInt32? {
        var where_ = address(selector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }

    static func all() -> [ArisAudioDevice] {
        var where_ = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &where_, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &where_, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            ArisAudioDevice(id: id, transport: ArisAudioDevice.transport(code: transportCode(id)),
                            hasInput: hasStreams(id, kAudioObjectPropertyScopeInput), hasOutput: hasStreams(id, kAudioObjectPropertyScopeOutput),
                            uid: text(id, kAudioDevicePropertyDeviceUID), name: text(id, kAudioObjectPropertyName))
        }
    }

    private static func text(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var where_ = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func transportCode(_ id: AudioDeviceID) -> UInt32 {
        var where_ = address(kAudioDevicePropertyTransportType)
        var type = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &type) == noErr ? type : 0
    }

    private static func hasStreams(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Bool {
        var where_ = address(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &where_, 0, nil, &size) == noErr && size > 0
    }

    /// The plan for `use` under the microphone choice (ArisMicSetting), from the devices as they are this moment.
    static func plan(for use: ArisMicUse) -> ArisMicPlan {
        let devices = all(), setting = ArisMicSetting.current
        noteFallback(setting.pick(devices))
        return ArisMicPlan.make(for: use, setting: setting, defaultInput: defaultInput(), devices: devices)
    }

    private static let fallbackSaid = OSAllocatedUnfairLock<ArisMicSetting.Fallback?>(initialState: nil)

    /// The choice not being there is said once, when it starts (and again only after it was there in between).
    private static func noteFallback(_ pick: ArisMicSetting.Pick) {
        let changed = fallbackSaid.withLock { said -> Bool in
            defer { said = pick.fallback }
            return said != pick.fallback
        }
        guard changed, let fallback = pick.fallback else { return }
        let instead = pick.device == nil ? "the system's input" : "the built-in microphone"
        log.notice("microphone choice: \(fallback.rawValue, privacy: .public); using \(instead, privacy: .public)")
    }

    /// How the voice should go out now (ArisVoiceRoute), with the default input's kind for the log.
    static func voiceRoute() -> (route: ArisVoiceRoute, input: ArisAudioDevice.Transport?) {
        let devices = all(), input = defaultInput()
        let route = ArisVoiceRoute.pick(setting: UserDefaults.standard.string(forKey: ArisVoiceRoute.key), defaultInput: input, devices: devices)
        return (route, input.flatMap { id in devices.first { $0.id == id }?.transport })
    }

    // MARK: - Pinning an engine's microphone

    /// Points `engine`'s microphone at the one device the plan names for `use`, before its format is read or a tap
    /// installed, and writes the log's line. The device it is on (nil: no microphone at all, the caller's own error
    /// says so). Throws ArisMicPaused when the plan is to open nothing (the wake word with only a headset's).
    @discardableResult
    static func pin(_ engine: AVAudioEngine, for use: ArisMicUse) throws -> (id: UInt32, transport: ArisAudioDevice.Transport)? {
        // An engine of its own is about to open: the duplex engine (arisDuplexAudio) lets go first, so the two never
        // hold the microphone together. Nothing with the switch off.
        if ArisDuplexSwitch.isOn { ArisDuplexAudio.legacyMicOpening() }
        switch plan(for: use) {
        case .none:
            return nil
        case .pause(let why):
            log.notice("\(ArisMicWords.paused(use, why: why), privacy: .public)")
            throw ArisMicPaused(why: why)
        case .open(let id, let transport):
            var device = id
            let status = engine.inputNode.audioUnit.map {
                AudioUnitSetProperty($0, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            }
            if status != noErr {
                // Said plainly: the engine is then on whatever the default input is.
                log.error("microphone: \(use.rawValue, privacy: .public) could not be pinned to device \(id, privacy: .public) (\(status ?? -1, privacy: .public)); it follows the default input")
            }
            log.notice("\(ArisMicWords.opened(use, transport: transport, id: id), privacy: .public)")
            return (id, transport)
        }
    }

    /// 호출어 녹음's AirPods group (the user asked for that microphone on purpose, for the seconds of a take): the engine on
    /// the first headset's microphone; nil when no headset with a microphone is connected.
    static func pinHeadset(_ engine: AVAudioEngine) -> (id: UInt32, transport: ArisAudioDevice.Transport)? {
        if ArisDuplexSwitch.isOn { ArisDuplexAudio.legacyMicOpening() }
        guard let headset = all().first(where: { $0.hasInput && $0.transport == .bluetooth }), let unit = engine.inputNode.audioUnit else { return nil }
        var device = headset.id
        guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else { return nil }
        log.notice("\(ArisMicWords.opened(.setup, transport: .bluetooth, id: headset.id), privacy: .public)")
        return (headset.id, .bluetooth)
    }

    static func noteClosed(_ use: ArisMicUse, transport: ArisAudioDevice.Transport?) {
        log.notice("\(ArisMicWords.closed(use, transport: transport), privacy: .public)")
    }

    static func noteVoice(_ route: ArisVoiceRoute, input: ArisAudioDevice.Transport?) {
        log.notice("\(ArisMicWords.voice(route, inputTransport: input), privacy: .public)")
    }
}

extension ArisAudioHALLive {
    /// The app's one: the inputs as ArisMicDevices lists them.
    static let shared = ArisAudioHALLive { ArisMicDevices.all().filter(\.hasInput).map(\.id) }
}
