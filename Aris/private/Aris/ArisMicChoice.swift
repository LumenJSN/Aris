//
//  ArisMicChoice.swift
//  Aris
//
//  Which microphone Aris listens through. Opening a Bluetooth headset's mic switches it to call mode, which
//  makes music sound like a phone line (and its narrow, quiet audio is hard to transcribe). So with Bluetooth
//  headphones as the input, Aris uses the Mac's own mic instead, when there is one (not with the lid closed).
//

import AudioToolbox
import AVFoundation
import CoreAudio

enum ArisMicChoice {
    struct Device: Equatable {
        enum Transport: Equatable { case builtIn, bluetooth, other }
        let id: AudioDeviceID
        let transport: Transport
        let hasInput: Bool
    }

    /// The mic to use instead of the default input; nil to keep the default.
    static func pick(defaultInput: AudioDeviceID?, devices: [Device]) -> AudioDeviceID? {
        guard let id = defaultInput, devices.first(where: { $0.id == id })?.transport == .bluetooth else { return nil }
        return devices.first { $0.transport == .builtIn && $0.hasInput }?.id
    }

    /// Points `engine`'s microphone at the Mac's own mic when the input is a Bluetooth headset. Call before reading
    /// the input's format. True when it switched.
    @discardableResult
    static func apply(to engine: AVAudioEngine) -> Bool {
        guard let id = pick(defaultInput: defaultInput(), devices: devices()), let unit = engine.inputNode.audioUnit else { return false }
        var device = id
        return AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                    &device, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr
    }

    // MARK: - Core Audio

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// The system's default input device now.
    static func defaultInputDevice() -> AudioDeviceID? { defaultInput() }

    /// The input device `engine` actually uses (after apply(to:)), for telling a device change from a format change.
    static func device(of engine: AVAudioEngine) -> AudioDeviceID? {
        guard let unit = engine.inputNode.audioUnit else { return nil }
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size)
        return status == noErr && id != 0 ? id : nil
    }

    /// Whether any of `devices` can record.
    static func anyInput(_ devices: [Device]) -> Bool { devices.contains(where: \.hasInput) }

    /// Whether this Mac has an audio input device now (a microphone of its own, a headset's, a display's).
    static func hasMicrophone() -> Bool { anyInput(devices()) }

    /// The ids of the devices among `devices` that can record (an input stream of their own): never a speaker's or a
    /// display's that only plays.
    static func inputIds(_ devices: [Device]) -> Set<AudioDeviceID> { Set(devices.filter(\.hasInput).map(\.id)) }

    /// The ids of every device with input now (it used to be every audio device, output-only ones too).
    static func inputDeviceIds() -> Set<AudioDeviceID> { inputIds(devices()) }

    private static func defaultInput() -> AudioDeviceID? {
        var where_ = address(kAudioHardwarePropertyDefaultInputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func devices() -> [Device] {
        var where_ = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &where_, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { Device(id: $0, transport: transport(of: $0), hasInput: hasInput($0)) }
    }

    private static func transport(of id: AudioDeviceID) -> Device.Transport {
        var where_ = address(kAudioDevicePropertyTransportType)
        var type = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &where_, 0, nil, &size, &type) == noErr else { return .other }
        switch type {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default: return .other
        }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var where_ = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &where_, 0, nil, &size) == noErr && size > 0
    }
}
