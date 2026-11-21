//
//  ArisDuplexRoute.swift
//  Aris
//
//  Whether the duplex engine (voice processing: echo cancelling on one IO unit for microphone and speaker) may run on
//  the devices as they are now, or the old path (separate engines) takes the turn. Voice processing on macOS joins the
//  default input and the default output into an aggregate of its own, so:
//  - Only when the microphone Aris would pin (ArisMicPlan) is the default input itself: then that join is the device
//    Aris means, and pinning can't silently land on a headset's microphone (which would drop it to call quality).
//  - Not on an aggregate, virtual or Continuity device, in or out: voice processing builds its own aggregate and
//    refuses (err -10876, "AggregateDevice channel count mismatch") or records nothing on those.
//  - Not with headphones out: there is no echo to cancel, and the old path's headphone barge-in and ducking already
//    work; this keeps voice processing away from Bluetooth headsets entirely.
//  - Not on a pair that failed before in this run (ArisDuplexLifetime.markFailed).
//  Also: which outputs count as headphones once the switch is on (a Bluetooth loudspeaker is no headphone), and the
//  echo tail the between-turn watch waits for when the canceller has the reference. Foundation only.
//

import Foundation

enum ArisDuplexRoute {
    enum Kind: String, Equatable {
        case builtIn = "built-in", bluetooth, wired, continuity, virtual, aggregate, other
    }

    struct Output: Equatable {
        let id: UInt32
        let kind: Kind
        /// The built-in output's data source ("ispk" speakers, "hdpn" the headphone jack); nil when it has none.
        let dataSource: String?
        /// The same device also has an input side (a Bluetooth headset's microphone: a headset, worn).
        let hasInput: Bool
    }

    struct Facts: Equatable {
        var switchOn: Bool
        /// The device ArisMicPlan would open for this use; nil: it opens none.
        var plannedInput: UInt32?
        var defaultInput: UInt32?
        var inputKind: Kind?
        var output: Output?
        /// Device pairs voice processing failed on in this run (key(input:output:)).
        var failed: Set<String> = []
    }

    enum Why: String, Equatable {
        case switchOff = "switch off"
        case noMicrophone = "no microphone"
        case notDefaultInput = "the microphone isn't the default input"
        case inputKind = "the microphone is an aggregate, virtual or Continuity device"
        case noOutput = "no output"
        case outputKind = "the output is an aggregate, virtual or Continuity device"
        case headphones = "headphones (no echo to cancel)"
        case failedBefore = "voice processing failed on these devices before"
    }

    enum Plan: Equatable {
        case duplex(key: String)
        case legacy(Why)

        var isDuplex: Bool {
            if case .duplex = self { return true }
            return false
        }
    }

    static func key(input: UInt32, output: UInt32) -> String { "\(input)>\(output)" }

    private static let unsupported: Set<Kind> = [.aggregate, .virtual, .continuity]

    static func plan(_ facts: Facts) -> Plan {
        guard facts.switchOn else { return .legacy(.switchOff) }
        guard let input = facts.plannedInput else { return .legacy(.noMicrophone) }
        guard input == facts.defaultInput else { return .legacy(.notDefaultInput) }
        if let kind = facts.inputKind, unsupported.contains(kind) { return .legacy(.inputKind) }
        guard let output = facts.output else { return .legacy(.noOutput) }
        if unsupported.contains(output.kind) { return .legacy(.outputKind) }
        if isHeadphones(output) { return .legacy(.headphones) }
        let key = key(input: input, output: output.id)
        return facts.failed.contains(key) ? .legacy(.failedBefore) : .duplex(key: key)
    }

    /// Headphones, as the duplex path sees them: the Mac's jack, or a Bluetooth device that also has a microphone (a
    /// headset). A Bluetooth loudspeaker (output only) is a speaker: the Mac's microphone hears it. A pair of Bluetooth
    /// headphones with no microphone at all is taken for a speaker too, the cautious side (stricter barge-in).
    static func isHeadphones(_ output: Output) -> Bool {
        switch output.kind {
        case .builtIn: return output.dataSource == "hdpn"
        case .bluetooth: return output.hasInput
        default: return false
        }
    }

    // MARK: - The echo's tail

    /// With the canceller holding Aris's own voice as its reference, its tail in the room is cancelled too: the
    /// between-turn watch waits only this long after the voice ended (the canceller's own settling and one tap
    /// buffer), not the old path's output latency plus room tail.
    static let cancelledTail: Double = 0.15

    /// The tail to wait: the old one (`legacy`), or the short one when Aris's last line went through the canceller.
    static func tail(legacy: Double, cancelled: Bool) -> Double {
        cancelled ? min(legacy, cancelledTail) : legacy
    }
}

/// The one switch for the duplex engine, the app's own (Settings › 대화 › 에코 제거 오디오; `defaults write com.lumenjsn.aris
/// arisDuplexAudio -bool true` lands in the sandboxed app's container, where the app reads it), off by default; off,
/// nothing of it is made or asked and every path is the old one.
enum ArisDuplexSwitch {
    static let key = "arisDuplexAudio"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }
}
