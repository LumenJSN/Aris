//
//  ArisAudioHALLive.swift
//  Aris
//
//  ArisAudioHAL on the real Core Audio: one C listener function for every registration, the token as its client
//  data (the HAL matches a removal by that pair, so it takes out exactly what was added: tested against the live HAL
//  in hang-tests), and the device facts: the default output here, the inputs from `inputs` (the app's `shared` reads
//  them as ArisMicDevices does). Reads properties only; opens nothing.
//

import CoreAudio
import Foundation

/// Runs on the HAL's notification thread; the token only pokes a coalescer.
private let arisAudioListenerProc: AudioObjectPropertyListenerProc = { _, _, _, clientData in
    guard let clientData else { return noErr }
    Unmanaged<ArisAudioToken>.fromOpaque(clientData).takeUnretainedValue().fire()
    return noErr
}

final class ArisAudioHALLive: ArisAudioHAL {
    private let inputs: () -> [AudioObjectID]

    init(inputs: @escaping () -> [AudioObjectID]) { self.inputs = inputs }

    /// The token stays retained by its ArisAudioListenerSet while registered, and a while after (retireAfter).
    func add(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus {
        var address = key.address
        return AudioObjectAddPropertyListener(key.object, &address, arisAudioListenerProc, Unmanaged.passUnretained(token).toOpaque())
    }

    func remove(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus {
        var address = key.address
        return AudioObjectRemovePropertyListener(key.object, &address, arisAudioListenerProc, Unmanaged.passUnretained(token).toOpaque())
    }

    func scene() -> ArisAudioScene {
        ArisAudioScene(output: Self.defaultOutput(), inputs: inputs())
    }

    private static func defaultOutput() -> AudioObjectID? {
        var address = ArisAudioKey.system(kAudioHardwarePropertyDefaultOutputDevice).address
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }
}
