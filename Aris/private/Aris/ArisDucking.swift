//
//  ArisDucking.swift
//  Aris
//
//  When you start talking over Aris, it turns itself down at once instead of talking on at full volume (as
//  ChatGPT's voice does: -10 dB, held at least 0.75 s, back up over a second). Saying "아리스" still stops it.
//  Only with headphones: through speakers the microphone would hear Aris itself and keep turning it down.
//  Headphones are the duplex path's (ArisDuplexRoute.isHeadphones) on both paths: the Mac's jack, or a Bluetooth device
//  that also has a microphone (a headset). A Bluetooth loudspeaker is a speaker: the Mac's microphone hears it, so
//  Aris neither ducks under its own voice nor takes the name from it for the user's (2026-11-18 audit).
//

import CoreAudio
import Foundation

enum ArisDucking {
    /// -10 dB.
    static let duckedVolume: Float = 0.316
    static let shortestDuck: Duration = .milliseconds(750)
    static let restoreTime: Duration = .seconds(1)

    static func mayRestore(sinceDuck: Duration) -> Bool { sinceDuck >= shortestDuck }

    /// The volume `restoringFor` into the climb back to full.
    static func volume(restoringFor elapsed: Duration) -> Float {
        let done = Float(min(1, max(0, elapsed / restoreTime)))
        return duckedVolume + (1 - duckedVolume) * done
    }

    /// Output through headphones: the Mac's own jack (data source "hdpn"), or a Bluetooth device with a microphone of
    /// its own (`hasInput`: a headset); a Bluetooth loudspeaker is not (ArisDuplexRoute.isHeadphones decides).
    static func isHeadphones(transport: ArisMicChoice.Device.Transport, dataSource: String?, hasInput: Bool) -> Bool {
        let kind: ArisDuplexRoute.Kind = switch transport {
        case .builtIn: .builtIn
        case .bluetooth: .bluetooth
        case .other: .other
        }
        return ArisDuplexRoute.isHeadphones(.init(id: 0, kind: kind, dataSource: dataSource, hasInput: hasInput))
    }

    /// Whether the Mac's sound goes to headphones right now.
    static func outputIsHeadphones() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        address.mSelector = kAudioDevicePropertyTransportType
        var type = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr else { return false }
        let transport: ArisMicChoice.Device.Transport = switch type {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        default: .other
        }
        var source = UInt32(0)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput,
                                             mElement: kAudioObjectPropertyElementMain)
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasSource = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &source) == noErr
        // A Bluetooth loudspeaker, with no microphone of its own, is no headphone, on the duplex path and the old one alike.
        return isHeadphones(transport: transport, dataSource: hasSource ? fourCharacters(source) : nil,
                            hasInput: transport == .bluetooth && hasInputStreams(device))
    }

    /// Whether `device` also has an input side (a Bluetooth headset's microphone).
    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func fourCharacters(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
    }
}
