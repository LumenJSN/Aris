//
//  ArisMicSetting.swift
//  Aris
//
//  Which microphone Aris listens through (Settings › Aris와 말하기 › 듣기 › 마이크; the owner, 2026-11-25: "like Wispr Flow").
//  The Mac's own built-in microphone by default, whatever the system's input is, so AirPods connecting never have
//  their microphone opened (which drops them to call quality for the music too); or the system's input, as 1.3.1 did
//  (ArisMicPlan's rule); or one device by its Core Audio UID, kept across reconnects. When the choice is not there:
//  - This Mac without a built-in microphone (a Mac mini, a closed lid): the system's input, said once in the log.
//  - A chosen device that is gone: the built-in microphone, else the system's input; Settings says so.
//  Output is untouched: it follows the system. No earlier setting chose a microphone (arisVoiceOutput is the
//  voice's output), so every install starts on This Mac. Foundation only (tested).
//

import Foundation

enum ArisMicSetting: Equatable {
    case thisMac
    case system
    case device(uid: String)

    /// The preference: "builtIn", "system" or "uid:<Core Audio device UID>"; nothing stored is This Mac.
    static let key = "arisMicrophone"
    /// The chosen device's name, for Settings while it is not connected.
    static let nameKey = "arisMicrophoneName"
    /// Posted (on the main thread) when the choice changes: the audio watch and the wake word choose again.
    static let changed = Notification.Name("com.lumenjsn.aris.microphoneChoice")

    private static let devicePrefix = "uid:"

    init(stored: String?) {
        switch stored {
        case "system": self = .system
        case let value? where value.hasPrefix(Self.devicePrefix) && value.count > Self.devicePrefix.count:
            self = .device(uid: String(value.dropFirst(Self.devicePrefix.count)))
        default: self = .thisMac
        }
    }

    var stored: String {
        switch self {
        case .thisMac: "builtIn"
        case .system: "system"
        case .device(let uid): Self.devicePrefix + uid
        }
    }

    static var current: ArisMicSetting { ArisMicSetting(stored: UserDefaults.standard.string(forKey: key)) }

    /// Only "Same as system" listens for the system's default input changing.
    var followsSystemInput: Bool { self == .system }

    enum Fallback: String, Equatable {
        case noBuiltIn = "this Mac has no built-in microphone now"
        case chosenGone = "the chosen microphone is not connected"
    }

    /// The device this choice opens among `devices`, or nil for ArisMicPlan's system rule; and why it is not the
    /// choice itself, when it is not.
    struct Pick: Equatable {
        let device: ArisAudioDevice?
        let fallback: Fallback?
    }

    func pick(_ devices: [ArisAudioDevice]) -> Pick {
        let inputs = devices.filter(\.hasInput)
        let builtIn = inputs.first { $0.transport == .builtIn }
        switch self {
        case .system:
            return Pick(device: nil, fallback: nil)
        case .thisMac:
            return Pick(device: builtIn, fallback: builtIn == nil ? .noBuiltIn : nil)
        case .device(let uid):
            if let chosen = inputs.first(where: { $0.uid == uid }) { return Pick(device: chosen, fallback: nil) }
            return Pick(device: builtIn, fallback: .chosenGone)
        }
    }
}
