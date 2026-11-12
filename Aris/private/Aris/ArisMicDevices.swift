//
//  ArisMicDevices.swift
//  Aris
//
//  The live side of ArisMicPlan: the audio devices as Core Audio lists them now, an engine's microphone pinned to
//  the one device the plan names (so it never follows the default input to a headset that connects later), a watch
//  on the device list and the default input, and the log line written whenever an Aris microphone opens, pauses or
//  closes (who, and the device's kind; never any audio). Only reads device properties: nothing here opens a device.
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
                            hasInput: hasStreams(id, kAudioObjectPropertyScopeInput), hasOutput: hasStreams(id, kAudioObjectPropertyScopeOutput))
        }
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

    /// The plan for `use`, from the devices as they are this moment.
    static func plan(for use: ArisMicUse) -> ArisMicPlan {
        ArisMicPlan.make(for: use, defaultInput: defaultInput(), devices: all())
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

    static func noteClosed(_ use: ArisMicUse, transport: ArisAudioDevice.Transport?) {
        log.notice("\(ArisMicWords.closed(use, transport: transport), privacy: .public)")
    }

    static func noteVoice(_ route: ArisVoiceRoute, input: ArisAudioDevice.Transport?) {
        log.notice("\(ArisMicWords.voice(route, inputTransport: input), privacy: .public)")
    }
}

/// Tells its owner (on the main queue) when the list of audio devices or the default input changes: headphones
/// connected or gone, AirPods taken over by another device, the lid closed. Several changes in a row arrive as one.
final class ArisMicWatch {
    private var blocks: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var settle: DispatchWorkItem?
    /// Changes come in bursts (a headset connecting changes the list, then the default): one call after they settle.
    static let settleTime: TimeInterval = 0.6

    init(onChange: @escaping () -> Void) {
        for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
            var where_ = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                self.settle?.cancel()
                let work = DispatchWorkItem(block: onChange)
                self.settle = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime, execute: work)
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &where_, .main, block) == noErr {
                blocks.append((where_, block))
            }
        }
    }

    deinit {
        settle?.cancel()
        for (where_, block) in blocks {
            var address = where_
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
    }
}
