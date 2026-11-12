//
//  ArisVolumeRules.swift
//  Aris
//
//  What a volume voice command does to the output device: steps of 1/16, a hardware mute where the device has
//  one, otherwise a software mute that remembers the level. Pure rules; ArisVolume does the CoreAudio side.
//

import Foundation

enum ArisVolumeCommand: Equatable {
    case up, down
    case set(Float32)
    case toggleMute
}

/// The device as the command finds it.
struct ArisVolumeReading {
    var level: Float32
    var muted: Bool
    var hasMute: Bool
}

/// Where the volume already was when 올려 or 내려 asked for more.
enum ArisVolumeLimit: Equatable {
    /// 100 % and not muted.
    case top
    /// 0 with the sound already off.
    case bottom
}

/// What to write: a new level and/or a hardware mute state. `limit`: the command asked past the end, so the level
/// planned is the one it already has and nothing changes (Aris says "이미 최대예요", never "올렸어요").
struct ArisVolumePlan: Equatable {
    var level: Float32? = nil
    var mute: Bool? = nil
    var limit: ArisVolumeLimit? = nil
}

struct ArisVolumeRules {
    static let step: Float32 = 1.0 / 16
    /// Levels at or below this aren't worth remembering for a software unmute.
    static let silence: Float32 = 0.001
    /// What a software unmute restores when no level was remembered.
    static let unmuteLevel: Float32 = 0.2

    /// The device's level: the average of its channels, or the main element's when it has no channel controls.
    static func level(channels: [Float32], main: Float32?) -> Float32? {
        guard !channels.isEmpty else { return main }
        return channels.reduce(0, +) / Float32(channels.count)
    }

    private(set) var isSoftMuted = false
    private var remembered: Float32?

    mutating func plan(_ command: ArisVolumeCommand, _ device: ArisVolumeReading) -> ArisVolumePlan {
        let muted = device.hasMute ? device.muted : isSoftMuted
        switch command {
        case .up:
            if device.level >= 1 - Self.silence, !muted { return ArisVolumePlan(level: 1, limit: .top) }
            return louder(min(1, device.level + Self.step), device)
        case .down:
            if device.level <= Self.silence, muted { return ArisVolumePlan(level: 0, limit: .bottom) }
            return quieter(max(0, device.level - Self.step), device)
        case .set(let value):
            let level = min(1, max(0, value))
            return level == 0 ? quieter(0, device) : louder(level, device)
        case .toggleMute:
            if device.hasMute { return ArisVolumePlan(mute: !device.muted) }
            if isSoftMuted {
                isSoftMuted = false
                return ArisVolumePlan(level: remembered ?? Self.unmuteLevel)
            }
            return mute(device, levelToo: false)
        }
    }

    /// A lower level; reaching exactly 0 while not muted engages mute.
    private mutating func quieter(_ level: Float32, _ device: ArisVolumeReading) -> ArisVolumePlan {
        let muted = device.hasMute ? device.muted : isSoftMuted
        return level == 0 && !muted ? mute(device, levelToo: true) : ArisVolumePlan(level: level)
    }

    /// A new level above zero; a muted device is unmuted with it.
    private mutating func louder(_ level: Float32, _ device: ArisVolumeReading) -> ArisVolumePlan {
        isSoftMuted = false
        return ArisVolumePlan(level: level, mute: device.hasMute && device.muted ? false : nil)
    }

    /// Hardware mute (setting 0 also brings the level down), or a software mute that keeps the level for later.
    private mutating func mute(_ device: ArisVolumeReading, levelToo: Bool) -> ArisVolumePlan {
        if device.hasMute { return ArisVolumePlan(level: levelToo ? 0 : nil, mute: true) }
        remembered = device.level > Self.silence ? device.level : nil
        isSoftMuted = true
        return ArisVolumePlan(level: 0)
    }
}

/// Holds only the newest value until it's written; `offer` says when a write needs scheduling.
struct ArisLatestValue<Value> {
    private(set) var pending: Value?

    /// True when nothing was waiting, so the caller schedules one write.
    mutating func offer(_ value: Value) -> Bool {
        defer { pending = value }
        return pending == nil
    }

    mutating func take() -> Value? {
        defer { pending = nil }
        return pending
    }
}
