//
//  ArisDucking.swift
//  Aris
//
//  When you start talking over Aris, it turns itself down at once instead of talking on at full volume (as
//  ChatGPT's voice does: -10 dB, held at least 0.75 s, back up over a second). Saying "아리스" still stops it.
//  Only with headphones: through speakers the microphone would hear Aris itself and keep turning it down.
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

    /// Output through headphones: Bluetooth, or the Mac's own jack (data source "hdpn").
    static func isHeadphones(transport: ArisMicChoice.Device.Transport, dataSource: String?) -> Bool {
        switch transport {
        case .bluetooth: return true
        case .builtIn: return dataSource == "hdpn"
        case .other: return false
        }
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
        return isHeadphones(transport: transport, dataSource: hasSource ? fourCharacters(source) : nil)
    }

    private static func fourCharacters(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
    }
}
