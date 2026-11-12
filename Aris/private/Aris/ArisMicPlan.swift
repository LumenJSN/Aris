//
//  ArisMicPlan.swift
//  Aris
//
//  Which microphone Aris opens, for whom, and whether it opens one at all. A Bluetooth headset has one radio link:
//  the moment anything opens its microphone it drops from music to call quality, and stays there until that
//  microphone is closed (the owner, 2026-11-11: "헤드폰 연결하면 마이크가 바뀌면서 계속 음질이 ㅈ돼"). So:
//  - Aris never follows "the default input". It opens one device by its id, chosen here from the devices as they are
//    now, and chosen again whenever the list or the default changes.
//  - A headset's microphone is never the choice while the Mac has another real one: the Mac's own first, else a
//    wired one (USB, a display's). A phone's Continuity microphone, a virtual device and an aggregate are never
//    picked in a headset's place (they would wake a phone or record nothing).
//  - When a headset's is the only microphone (the lid closed, a Mac with none of its own), the wake word pauses
//    with one line saying why. Hold-to-talk, dictation and the name's training are the user's own press: they may use it
//    for the seconds they last, and close it the moment they end.
//  - Aris's voice has the same trap from the other side: an AVAudioEngine that only plays still opens the default
//    input along with the output (it joins the two default devices into one), so with the headset as both, every
//    sentence Aris said put the headset in call mode. While the default input is a headset, the voice goes out
//    through an output of its own that has no input at all (ArisOwnOutput).
//  Foundation only, so every rule is tested over recorded device lists.
//

import Foundation

/// Who opens the microphone.
enum ArisMicUse: String, Equatable, CaseIterable {
    /// The wake word, and a conversation's listening between turns: nobody pressed anything.
    case wake
    /// Hold-to-talk, a card's spoken answer.
    case talk
    case dictation
    /// Teaching Aris the name, the setup's practice.
    case setup

    /// The user pressed or asked for this just now: it may use a headset's microphone when that is the only one.
    var isDeliberate: Bool { self != .wake }
}

struct ArisAudioDevice: Equatable {
    enum Transport: String, Equatable {
        case builtIn = "built-in", bluetooth, wired, continuity, virtual, aggregate, other
    }

    let id: UInt32
    let transport: Transport
    let hasInput: Bool
    var hasOutput = false

    /// Core Audio's four-letter transport type, as this file sorts it.
    static func transport(code: UInt32) -> Transport {
        switch fourCC(code) {
        case "bltn": return .builtIn
        case "blue", "blea": return .bluetooth
        case "usb ", "dprt", "hdmi", "thun", "1394", "pci ", "eavb": return .wired
        case "ccwd", "ccwl": return .continuity
        case "virt": return .virtual
        case "grup", "fgrp": return .aggregate
        default: return .other
        }
    }

    static func fourCC(_ code: UInt32) -> String {
        String(bytes: [UInt8(code >> 24 & 0xFF), UInt8(code >> 16 & 0xFF), UInt8(code >> 8 & 0xFF), UInt8(code & 0xFF)], encoding: .ascii) ?? ""
    }
}

enum ArisMicPlan: Equatable {
    enum Pause: Equatable {
        /// The only microphone is a Bluetooth headset's: opening it would put the headset in call mode.
        case headsetOnly
    }

    /// Open exactly this device (never "the default").
    case open(id: UInt32, transport: ArisAudioDevice.Transport)
    /// Open nothing.
    case pause(Pause)
    /// There is no microphone at all.
    case none

    /// The device to open for `use`, from the devices as they are now.
    static func make(for use: ArisMicUse, defaultInput: UInt32?, devices: [ArisAudioDevice]) -> ArisMicPlan {
        let inputs = devices.filter(\.hasInput)
        guard !inputs.isEmpty else { return .none }
        let chosen = defaultInput.flatMap { id in inputs.first { $0.id == id } }
        // The user's own choice of input, when it is no headset: used as it is, by its id.
        if let chosen, chosen.transport != .bluetooth { return .open(id: chosen.id, transport: chosen.transport) }
        // A headset is the default (or nothing readable is): the Mac's own microphone, else a wired one.
        if let own = inputs.first(where: { $0.transport == .builtIn }) ?? inputs.first(where: { $0.transport == .wired }) {
            return .open(id: own.id, transport: own.transport)
        }
        guard let headset = chosen ?? inputs.first(where: { $0.transport == .bluetooth }) else {
            // No default, no microphone of the Mac's, no headset: whatever is there (a phone's, a virtual one).
            return inputs.first.map { .open(id: $0.id, transport: $0.transport) } ?? .none
        }
        return use.isDeliberate ? .open(id: headset.id, transport: .bluetooth) : .pause(.headsetOnly)
    }

    /// The device the plan opens; nil when it opens none.
    var device: UInt32? {
        if case .open(let id, _) = self { return id }
        return nil
    }

    /// Whether a running microphone must be opened again: what it should be on now is not what it is on.
    static func mustReopen(openOn current: UInt32?, plan: ArisMicPlan) -> Bool {
        switch plan {
        case .open(let id, _): return current != id
        case .pause, .none: return current != nil
        }
    }
}

/// How Aris's voice reaches the loudspeakers (the preference `arisVoiceOutput`: "auto", "own" or "engine").
enum ArisVoiceRoute: Equatable {
    /// AVAudioEngine's own output, as always.
    case engine
    /// An output with no input side (ArisOwnOutput): nothing of a headset's microphone is touched.
    case own

    static let key = "arisVoiceOutput"

    /// Automatic: the own output exactly when the default input is a Bluetooth headset's, which the engine's output
    /// would open along with the loudspeakers.
    static func pick(setting: String?, defaultInput: UInt32?, devices: [ArisAudioDevice]) -> ArisVoiceRoute {
        switch setting {
        case "own": return .own
        case "engine": return .engine
        default:
            let input = defaultInput.flatMap { id in devices.first { $0.id == id } }
            return input?.transport == .bluetooth ? .own : .engine
        }
    }
}

/// The lines about the microphone: the log's (never any audio, only who, which kind of device and why) and the one
/// The user sees when the wake word pauses.
enum ArisMicWords {
    /// "microphone opened: wake on built-in (device 88)".
    static func opened(_ use: ArisMicUse, transport: ArisAudioDevice.Transport, id: UInt32) -> String {
        "microphone opened: \(use.rawValue) on \(transport.rawValue) (device \(id))"
    }

    static func closed(_ use: ArisMicUse, transport: ArisAudioDevice.Transport?) -> String {
        "microphone closed: \(use.rawValue)" + (transport.map { " (was on \($0.rawValue))" } ?? "")
    }

    static func paused(_ use: ArisMicUse, why: ArisMicPlan.Pause) -> String {
        switch why {
        case .headsetOnly: return "microphone not opened: \(use.rawValue) pauses, the only microphone is a Bluetooth headset's (it stays in music mode)"
        }
    }

    static func voice(_ route: ArisVoiceRoute, inputTransport: ArisAudioDevice.Transport?) -> String {
        "voice output: \(route == .own ? "own output, no input side" : "the engine's") (default input: \(inputTransport?.rawValue ?? "none"))"
    }

    /// What the notch says once when the wake word pauses for a headset.
    static func wakePaused(english: Bool) -> String {
        english ? "Only the headphones' microphone is here, so listening for the name is paused: that keeps your music's sound. Hold the talk key to speak."
            : "헤드폰 마이크만 있어서 이름 듣기를 쉬어요. 음악 음질을 지키려고요. 말하려면 말하기 키를 눌러 주세요."
    }
}

/// Thrown instead of opening a microphone the plan says to leave closed.
struct ArisMicPaused: Error, Equatable {
    let why: ArisMicPlan.Pause
}
