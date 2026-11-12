//
//  ArisVolume.swift
//  Aris
//
//  The output volume for voice commands ("볼륨 올려 / 내려 / 음소거 / 50"). Every CoreAudio call runs on one serial
//  queue; level writes are coalesced to about 15 a second, always writing the newest target. The default output
//  device is looked up on every command, so a device switch is picked up by the next one. A command answers whether
//  it had anything to change: an HDMI or DisplayPort output has no level or mute the Mac can set, and Aris must not
//  say "올렸어요" for it.
//

import CoreAudio
import Foundation

/// The CoreAudio calls the volume needs (a stand-in in tests).
protocol ArisAudioOutput: AnyObject {
    func defaultDevice() -> AudioDeviceID?
    func hasMute(_ device: AudioDeviceID) -> Bool
    func isMuted(_ device: AudioDeviceID) -> Bool
    func setMuted(_ device: AudioDeviceID, _ on: Bool)
    func volume(_ device: AudioDeviceID) -> Float32?
    func setVolume(_ device: AudioDeviceID, _ value: Float32)
    /// Whether the device has a level the Mac can set (an HDMI or DisplayPort output has none).
    func canSetVolume(_ device: AudioDeviceID) -> Bool
}

extension ArisAudioOutput {
    /// Unless the output says otherwise, a level that can be read is taken as one that can be set.
    func canSetVolume(_ device: AudioDeviceID) -> Bool { volume(device) != nil }
}

/// What a command did to the output.
enum ArisVolumeOutcome: Equatable {
    case changed
    /// 올려 at 100 % or 내려 with the sound already off: nothing to change.
    case atLimit(ArisVolumeLimit)
    /// No device, or neither a level nor a mute the Mac can set.
    case unavailable

    var limit: ArisVolumeLimit? {
        if case .atLimit(let limit) = self { return limit }
        return nil
    }
}

final class ArisVolume: @unchecked Sendable {
    static let writeInterval: TimeInterval = 1.0 / 15
    static let shared = ArisVolume(output: ArisCoreAudioOutput())

    private let output: ArisAudioOutput
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.volume")
    // Touched only on `queue`.
    private var device: AudioDeviceID?
    private var rules = ArisVolumeRules()
    private var target = ArisLatestValue<Float32>()

    init(output: ArisAudioOutput, interval: TimeInterval = ArisVolume.writeInterval) {
        self.output = output
        self.interval = interval
    }

    /// Does the command; false when the output had nothing it could change (no device, or neither a level nor a mute
    /// the Mac can set), so nothing was written.
    @discardableResult
    func perform(_ command: ArisVolumeCommand) -> Bool {
        act(command) == .changed
    }

    /// Does the command and says what came of it: a change, the end of the scale it was already at, or an output with
    /// nothing to change.
    func act(_ command: ArisVolumeCommand) -> ArisVolumeOutcome {
        queue.sync { run(command) }
    }

    /// The default output's level now (0–100), with any write still pending; nil without a device. For the activity
    /// log's undo of a spoken volume change (QA BUG-18).
    func currentLevel() -> Int? {
        queue.sync {
            guard let current = output.defaultDevice() else { return nil }
            let level = (current == device ? target.pending : nil) ?? output.volume(current)
            return level.map { Int(($0 * 100).rounded()) }
        }
    }

    /// For tests: returns once queued commands and their delayed writes are done.
    func waitUntilIdle() {
        queue.sync {}
        Thread.sleep(forTimeInterval: interval * 3)
        queue.sync {}
    }

    private func run(_ command: ArisVolumeCommand) -> ArisVolumeOutcome {
        guard let current = output.defaultDevice() else { return .unavailable }
        if current != device {
            device = current
            rules = ArisVolumeRules()
            _ = target.take()
        }
        let hasLevel = output.canSetVolume(current), hasMute = output.hasMute(current)
        // Nothing to set: the rules aren't asked, so no software mute is remembered for a level that never moved.
        guard hasLevel || hasMute else { return .unavailable }
        let reading = ArisVolumeReading(level: target.pending ?? output.volume(current) ?? 0,
                                        muted: output.isMuted(current), hasMute: hasMute)
        var planned = rules
        let plan = planned.plan(command, reading)
        // A plan that is only a level, for an output with only a mute: nothing changes, and the rules stay as they were.
        guard plan.mute != nil || (plan.level != nil && hasLevel) else { return .unavailable }
        // Already at the end it was asked to move towards: nothing is written.
        if let limit = plan.limit { return .atLimit(limit) }
        rules = planned
        if let mute = plan.mute { output.setMuted(current, mute) }
        guard hasLevel, let level = plan.level else { return .changed }
        if target.offer(level) {
            queue.asyncAfter(deadline: .now() + interval) { self.write(to: current) }
        }
        return .changed
    }

    private func write(to written: AudioDeviceID) {
        guard let level = target.take(), written == device else { return }
        output.setVolume(written, level)
    }
}

/// The default output device through CoreAudio. Devices without a main volume (AirPods, some HDMI outputs) expose
/// per-channel controls, so every element from main through channel 4 is tried.
final class ArisCoreAudioOutput: ArisAudioOutput {
    private static let elements: [AudioObjectPropertyElement] = [kAudioObjectPropertyElementMain, 1, 2, 3, 4]

    func defaultDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    func hasMute(_ device: AudioDeviceID) -> Bool { !settable(kAudioDevicePropertyMute, on: device).isEmpty }

    func isMuted(_ device: AudioDeviceID) -> Bool {
        guard let element = settable(kAudioDevicePropertyMute, on: device).first else { return false }
        var muted: UInt32 = 0
        return read(kAudioDevicePropertyMute, element, of: device, into: &muted) && muted != 0
    }

    func setMuted(_ device: AudioDeviceID, _ on: Bool) {
        for element in settable(kAudioDevicePropertyMute, on: device) {
            var value: UInt32 = on ? 1 : 0
            write(kAudioDevicePropertyMute, element, of: device, from: &value)
        }
    }

    /// The average of the channels' levels (the main element's when the device has no per-channel controls).
    func volume(_ device: AudioDeviceID) -> Float32? {
        var main: Float32?
        var channels: [Float32] = []
        for element in readable(kAudioDevicePropertyVolumeScalar, on: device) {
            var level: Float32 = 0
            guard read(kAudioDevicePropertyVolumeScalar, element, of: device, into: &level) else { continue }
            if element == kAudioObjectPropertyElementMain { main = level } else { channels.append(level) }
        }
        return ArisVolumeRules.level(channels: channels, main: main)
    }

    func canSetVolume(_ device: AudioDeviceID) -> Bool { !settable(kAudioDevicePropertyVolumeScalar, on: device).isEmpty }

    func setVolume(_ device: AudioDeviceID, _ value: Float32) {
        for element in settable(kAudioDevicePropertyVolumeScalar, on: device) {
            var level = value
            write(kAudioDevicePropertyVolumeScalar, element, of: device, from: &level)
        }
    }

    // MARK: Property plumbing

    private func address(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private func readable(_ selector: AudioObjectPropertySelector, on device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        Self.elements.filter { element in
            var property = address(selector, element)
            return AudioObjectHasProperty(device, &property)
        }
    }

    private func settable(_ selector: AudioObjectPropertySelector, on device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        readable(selector, on: device).filter { element in
            var property = address(selector, element)
            var canSet: DarwinBoolean = false
            return AudioObjectIsPropertySettable(device, &property, &canSet) == noErr && canSet.boolValue
        }
    }

    private func read<T>(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement,
                         of device: AudioDeviceID, into value: inout T) -> Bool {
        var property = address(selector, element)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value) == noErr
    }

    private func write<T>(_ selector: AudioObjectPropertySelector, _ element: AudioObjectPropertyElement,
                          of device: AudioDeviceID, from value: inout T) {
        var property = address(selector, element)
        _ = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<T>.size), &value)
    }
}
