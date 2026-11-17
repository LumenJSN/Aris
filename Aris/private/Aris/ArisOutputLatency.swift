//
//  ArisOutputLatency.swift
//  Aris
//
//  How long the Mac's default output takes to put a sample out (its device and stream latency, safety offset and
//  buffer), and whether it is Bluetooth: ArisEchoGuard.tail waits this long after the speaker says Aris's voice ended
//  before the microphone may take a turn. Read from Core Audio each time (the output can change between answers); nil
//  when it can't be read (the tail's floor then covers it).
//

import CoreAudio
import Foundation

enum ArisOutputLatency {
    /// The tail to wait now for the default output (ArisEchoGuard.tail).
    static func tail() -> Double {
        let device = defaultOutput()
        return ArisEchoGuard.tail(outputLatency: device.flatMap(seconds), bluetooth: device.map(isBluetooth) ?? false)
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private static func value(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    /// The first output stream's own latency, in frames.
    private static func streamLatency(_ device: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) else { return 0 }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &streams) == noErr, let first = streams.first else { return 0 }
        var latency = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyLatency, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var frames = UInt32(0)
        var frameSize = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(first, &latency, 0, nil, &frameSize, &frames) == noErr ? frames : 0
    }

    private static func seconds(_ device: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        guard let latency = value(device, kAudioDevicePropertyLatency) else { return nil }
        let frames = Double(latency) + Double(value(device, kAudioDevicePropertySafetyOffset) ?? 0)
            + Double(value(device, kAudioDevicePropertyBufferFrameSize) ?? 0) + Double(streamLatency(device))
        return frames / rate
    }

    private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var type = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr else { return false }
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }
}
