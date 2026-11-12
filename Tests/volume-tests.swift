// Acceptance tests for the clean-room output volume (cleanroom-specs/11-system-controls.md, volume part).
import CoreAudio
import Foundation

func runVolumeTests() {
    volumeRuleTests()
    coalescingTests()
    volumeControllerTests()
}

private func reading(_ level: Float32, muted: Bool = false, hasMute: Bool = true) -> ArisVolumeReading {
    ArisVolumeReading(level: level, muted: muted, hasMute: hasMute)
}

private func volumeRuleTests() {
    var rules = ArisVolumeRules()
    check(ArisVolumeRules.step == 1.0 / 16, "volume: a step is 1/16")
    check(rules.plan(.up, reading(0.5)) == ArisVolumePlan(level: 0.5625), "volume: up adds a step")
    check(rules.plan(.down, reading(0.5)) == ArisVolumePlan(level: 0.4375), "volume: down takes a step")
    check(rules.plan(.up, reading(0.98)) == ArisVolumePlan(level: 1), "volume: up stops at full")
    check(rules.plan(.down, reading(0.02)) == ArisVolumePlan(level: 0, mute: true), "volume: down to zero mutes (hardware)")
    var softDown = ArisVolumeRules()
    check(softDown.plan(.down, reading(0.05, hasMute: false)) == ArisVolumePlan(level: 0) && softDown.isSoftMuted
          && softDown.plan(.toggleMute, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.05), "volume: down to zero mutes (software, level kept)")
    check(rules.plan(.set(1.7), reading(0.2)) == ArisVolumePlan(level: 1) && rules.plan(.set(0.4), reading(0.2)) == ArisVolumePlan(level: 0.4),
          "volume: set is clamped to 0…1")

    // A device with a mute control: toggling flips the hardware mute and keeps the level.
    check(rules.plan(.toggleMute, reading(0.5, muted: false)) == ArisVolumePlan(mute: true)
          && rules.plan(.toggleMute, reading(0.5, muted: true)) == ArisVolumePlan(mute: false), "volume: hardware mute toggles, level kept")
    check(rules.plan(.up, reading(0.5, muted: true)) == ArisVolumePlan(level: 0.5625, mute: false), "volume: raising while muted unmutes")
    check(rules.plan(.set(0.3), reading(0.5, muted: true)) == ArisVolumePlan(level: 0.3, mute: false), "volume: setting a level while muted unmutes")
    check(rules.plan(.set(0), reading(0.5)) == ArisVolumePlan(level: 0, mute: true), "volume: set 0 engages the hardware mute")
    check(rules.plan(.up, reading(0, muted: true)) == ArisVolumePlan(level: 0.0625, mute: false), "volume: 0 then up -> unmuted at 1/16")

    // A device without one: software mute remembers the level.
    var soft = ArisVolumeRules()
    check(soft.plan(.toggleMute, reading(0.6, hasMute: false)) == ArisVolumePlan(level: 0) && soft.isSoftMuted,
          "volume: software mute sets 0 and remembers the level")
    check(soft.plan(.toggleMute, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.6) && !soft.isSoftMuted,
          "volume: software unmute restores the remembered level")
    _ = soft.plan(.toggleMute, reading(0.6, hasMute: false))
    check(soft.plan(.set(0.4), reading(0, hasMute: false)) == ArisVolumePlan(level: 0.4) && !soft.isSoftMuted,
          "volume: software-muted, then set 40 % -> unmuted at 0.4")
    check(soft.plan(.set(0), reading(0.4, hasMute: false)) == ArisVolumePlan(level: 0) && soft.isSoftMuted, "volume: set 0 engages the software mute")
    var kept = ArisVolumeRules()
    _ = kept.plan(.toggleMute, reading(0.7, hasMute: false))
    _ = kept.plan(.set(0), reading(0, hasMute: false))
    _ = kept.plan(.down, reading(0, hasMute: false))
    check(kept.plan(.toggleMute, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.7),
          "volume: 0 while already software-muted keeps the remembered level")
    check(rules.plan(.down, reading(0.05, muted: true)) == ArisVolumePlan(level: 0), "volume: down to 0 while muted only lowers the level")
    check(soft.plan(.up, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.0625) && !soft.isSoftMuted,
          "volume: software-muted, then up -> unmuted at 1/16")
    var quiet = ArisVolumeRules()
    _ = quiet.plan(.toggleMute, reading(0.0005, hasMute: false))
    check(quiet.plan(.toggleMute, reading(0, hasMute: false)) == ArisVolumePlan(level: 0.2),
          "volume: a near-zero level isn't remembered; unmuting then restores 0.2")
    check(ArisVolumeRules.level(channels: [0.4, 0.6], main: 0.9) == 0.5 && ArisVolumeRules.level(channels: [], main: 0.3) == 0.3
          && ArisVolumeRules.level(channels: [], main: nil) == nil, "volume: the level is the channels' average, else the main element's")
}

private func coalescingTests() {
    // 30 writes within 100 ms, at most one device write per 1/15 s, always the latest value.
    var coalescer = ArisLatestValue<Float32>()
    var flushAt: [Double] = []
    var written: [Float32] = []
    let interval = ArisVolume.writeInterval
    for i in 0..<30 {
        let now = Double(i) * 0.1 / 29
        while let due = flushAt.first, due <= now {
            flushAt.removeFirst()
            if let value = coalescer.take() { written.append(value) }
        }
        if coalescer.offer(Float32(i)) { flushAt.append(now + interval) }
    }
    for _ in flushAt { if let value = coalescer.take() { written.append(value) } }
    check(written.count <= 2 && written.last == 29, "volume: 30 writes in 100 ms are at most 2 device writes, ending on the last value (\(written))")
    check(abs(interval - 1.0 / 15) < 0.0001, "volume: writes at most ~15 Hz")
}

private final class FakeOutput: ArisAudioOutput, @unchecked Sendable {
    var device: AudioDeviceID? = 7
    var level: Float32 = 0.5
    var muted = false
    var mutable = true
    var levelWrites: [Float32] = []
    var muteWrites: [Bool] = []

    func defaultDevice() -> AudioDeviceID? { device }
    func hasMute(_ device: AudioDeviceID) -> Bool { mutable }
    func isMuted(_ device: AudioDeviceID) -> Bool { muted }
    func setMuted(_ device: AudioDeviceID, _ on: Bool) { muted = on; muteWrites.append(on) }
    func volume(_ device: AudioDeviceID) -> Float32? { level }
    func setVolume(_ device: AudioDeviceID, _ value: Float32) { level = value; levelWrites.append(value) }
}

private func volumeControllerTests() {
    let output = FakeOutput()
    let volume = ArisVolume(output: output, interval: 0.01)
    volume.perform(.up)
    volume.perform(.up)
    volume.waitUntilIdle()
    check(output.level == 0.625 && output.levelWrites.last == 0.625, "volume: back-to-back ups build on the pending target")
    volume.perform(.toggleMute)
    volume.waitUntilIdle()
    check(output.muted && output.level == 0.625, "volume: mute on the device")
    output.device = 9; output.mutable = false; output.level = 0.3
    volume.perform(.toggleMute)
    volume.waitUntilIdle()
    check(output.level == 0, "volume: a new default device is used on the next command (software mute)")
    output.device = nil
    let writes = output.levelWrites.count
    volume.perform(.up)
    volume.waitUntilIdle()
    check(output.levelWrites.count == writes, "volume: no output device, nothing written")
}
