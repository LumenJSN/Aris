//
//  ArisOtherAudio.swift
//  Aris
//
//  Between turns a conversation listens to the room. While another app plays sound (a video, a call) or uses the
//  microphone, what the room holds isn't the user talking to Aris, so listening pauses until it stops (security review C1,
//  N4). Core Audio's process objects say which processes run output or input; Aris's own are left out. An open output
//  stream isn't sound: a process tap on every process but Aris's (ArisOutputMeter) says whether anything is audible.
//  Without a reading (no tap yet, or only exact zeros since it started, which is also what a denied System Audio
//  permission gives) an open stream counts, except Aside's helpers, whose output stream is always open.
//

import AudioToolbox
import CoreAudio
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "conversation")

enum ArisOtherAudio {
    struct Process: Equatable {
        let object: AudioObjectID
        let pid: Int32
        let bundle: String?
        let output: Bool
        let input: Bool

        init(object: AudioObjectID = 0, pid: Int32, bundle: String? = nil, output: Bool, input: Bool) {
            self.object = object
            self.pid = pid
            self.bundle = bundle
            self.output = output
            self.input = input
        }
    }

    /// Aris: the app (and its helpers), aris-agent and aris-tools.
    static let ownBundles = ["com.lumenjsn.aris", "com.lumenjsn.aris.aris-agent", "com.lumenjsn.aris.aris-tools"]
    /// Left out only when there's no reading: Aside's browser and helpers keep an output stream open all the time.
    static let alwaysOpen = ["at.studio.AsideBrowser", "at.studio.AsideUpdater"]
    /// Output louder than this (RMS) is sound someone can hear.
    static let audible: Float = 0.003

    /// The exact bundle id, or one inside it ("com.lumenjsn.aris.XPCHelper"), never one that only starts the same.
    static func matches(_ bundle: String?, _ ids: [String]) -> Bool {
        guard let bundle else { return false }
        return ids.contains { bundle == $0 || bundle.hasPrefix($0 + ".") }
    }

    static func isOwn(_ process: Process, ownPid: Int32) -> Bool {
        process.pid == ownPid || matches(process.bundle, ownBundles)
    }

    /// Another app plays or records. `outputLevel`: the tap's reading of every app but Aris (nil: none yet, or nothing
    /// but zeros): with it, open output counts only when something is audible; without, any open stream but Aside's.
    /// `pausedPlayers`: music apps Aris knows are paused (Now Playing says nothing plays): with no reading, their open
    /// stream isn't sound (QA BUG-38: a paused Spotify keeps its output open, so listening between turns never began).
    static func isPresent(_ processes: [Process], ownPid: Int32, outputLevel: Float? = nil, pausedPlayers: [String] = []) -> Bool {
        let others = processes.filter { !isOwn($0, ownPid: ownPid) }
        if others.contains(where: \.input) { return true }
        if let outputLevel { return others.contains(where: \.output) && outputLevel > audible }
        return others.contains { $0.output && !matches($0.bundle, alwaysOpen) && !matches($0.bundle, pausedPlayers) }
    }

    /// The music apps whose open output stream says nothing while Now Playing reports nothing playing.
    static let musicPlayers = ["com.spotify.client", "com.apple.Music"]

    static func pausedPlayers(nowPlaying: Bool) -> [String] { nowPlaying ? [] : musicPlayers }

    /// Another app has output open: the meter is worth running.
    static func needsMeter(_ processes: [Process], ownPid: Int32) -> Bool {
        processes.contains { !isOwn($0, ownPid: ownPid) && $0.output }
    }

    enum MeterStep: Equatable { case ensure, stop, leave }

    /// What a check does with the output meter (a process tap and a private aggregate device): only a conversation,
    /// whose close stops it, runs it; any other check reads the open streams alone and leaves the meter be (bug hunt
    /// 11-06 #4: a wake turn with 계속 듣기 off started it and nothing ever stopped it).
    static func meterStep(_ processes: [Process], ownPid: Int32, forConversation: Bool) -> MeterStep {
        guard forConversation else { return .leave }
        return needsMeter(processes, ownPid: ownPid) ? .ensure : .stop
    }

    /// Aris's processes, the only ones the meter leaves out.
    static func ownObjects(_ processes: [Process], ownPid: Int32) -> [AudioObjectID] {
        processes.filter { isOwn($0, ownPid: ownPid) }.map(\.object)
    }

    /// Likely no System Audio permission: the tap gave only exact zeros for a while although an app that really
    /// plays when its stream is open (not Aside's always-open one) has output open. Settings says so.
    static func permissionMissing(onlyZeros: Bool, _ processes: [Process], ownPid: Int32) -> Bool {
        onlyZeros && processes.contains { !isOwn($0, ownPid: ownPid) && $0.output && !matches($0.bundle, alwaysOpen) }
    }

    /// The audio processes now; empty when Core Audio can't say (listening goes on as before).
    static func processes() -> [Process] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.compactMap { object in
            guard let pid: Int32 = read(object, kAudioProcessPropertyPID) else { return nil }
            let output: UInt32 = read(object, kAudioProcessPropertyIsRunningOutput) ?? 0
            let input: UInt32 = read(object, kAudioProcessPropertyIsRunningInput) ?? 0
            return Process(object: object, pid: pid, bundle: bundle(of: object), output: output != 0, input: input != 0)
        }
    }

    private static func read<T: FixedWidthInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value = T.zero
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func bundle(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }
}

/// What the tap has read since it started: the loudest RMS of the last half second, and whether anything but exact
/// zeros ever came (a denied System Audio permission delivers only zeros, so then the level is unknown: fail closed).
struct ArisMeterReading: Equatable {
    static let window: Double = 0.5
    /// Only zeros this long since the start: the permission is likely missing.
    static let zerosAreSuspect: Double = 3

    let startedAt: Double
    private(set) var peak: Float = 0
    private(set) var peakAt: Double = -.infinity
    private(set) var heardSound = false
    private(set) var measured = false

    init(startedAt: Double) { self.startedAt = startedAt }

    func reading(_ loudest: Float, at now: Double) -> ArisMeterReading {
        var next = self
        next.measured = true
        if loudest > 0 { next.heardSound = true }
        if loudest >= peak || now - peakAt >= Self.window {
            next.peak = loudest
            next.peakAt = now
        }
        return next
    }

    /// The level now; nil until something but zeros came (unknown, so the open-stream rule applies).
    func level(at now: Double) -> Float? {
        guard measured, heardSound else { return nil }
        return now - peakAt < Self.window ? peak : 0
    }

    func onlyZeros(at now: Double) -> Bool { measured && !heardSound && now - startedAt >= Self.zerosAreSuspect }
}

/// How loud every app but Aris is: a private Core Audio process tap read through a private aggregate device (nothing
/// is recorded or kept). Made and torn down off the main thread, only while a conversation listens and another app has
/// output open; a tap Core Audio refuses is tried again later, each wait twice the last (up to 5 minutes).
final class ArisOutputMeter: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.output-meter")
    // Under `lock`:
    private var reading: ArisMeterReading?
    private var wanted: Set<AudioObjectID>?
    private var failures = 0
    private var retryAt = Date.distantPast
    // On `queue`:
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var proc: AudioDeviceIOProcID?

    private static var now: Double { ProcessInfo.processInfo.systemUptime }

    /// The level now (ArisMeterReading.level); nil when not running or not known.
    var level: Float? { lock.withLock { reading?.level(at: Self.now) } }

    /// Only exact zeros since the tap started, for a while.
    var onlyZeros: Bool { lock.withLock { reading?.onlyZeros(at: Self.now) ?? false } }

    /// Wants the tap running, leaving out `objects` (Aris's). Returns at once; the tap is made on the meter's queue.
    func ensure(leavingOut objects: [AudioObjectID]) {
        let set = Set(objects)
        let go = lock.withLock { () -> Bool in
            guard wanted != set, Date() >= retryAt else { return false }
            wanted = set
            reading = nil
            return true
        }
        guard go else { return }
        queue.async { [weak self] in self?.build(set) }
    }

    func stop() {
        let wasWanted = lock.withLock { () -> Bool in
            defer { wanted = nil; reading = nil }
            return wanted != nil
        }
        guard wasWanted else { return }
        queue.async { [weak self] in self?.tearDown() }
    }

    private func build(_ objects: Set<AudioObjectID>) {
        guard #available(macOS 14.2, *), lock.withLock({ wanted == objects }) else { return }
        tearDown()
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: Array(objects))
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return failed() }
        let aggregate: [String: Any] = [kAudioAggregateDeviceNameKey: "Aris output meter", kAudioAggregateDeviceUIDKey: UUID().uuidString,
                                        kAudioAggregateDeviceIsPrivateKey: true, kAudioAggregateDeviceTapAutoStartKey: true,
                                        kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]]]
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else {
            AudioHardwareDestroyProcessTap(tapID)
            return failed()
        }
        var procID: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { [weak self] _, input, _, _, _ in
            self?.measure(input)
        }
        guard created == noErr, let procID, AudioDeviceStart(deviceID, procID) == noErr else {
            if let procID { AudioDeviceDestroyIOProcID(deviceID, procID) }
            AudioHardwareDestroyAggregateDevice(deviceID)
            AudioHardwareDestroyProcessTap(tapID)
            return failed()
        }
        (tap, device, proc) = (tapID, deviceID, procID)
        lock.withLock {
            failures = 0
            reading = ArisMeterReading(startedAt: Self.now)
        }
    }

    private func failed() {
        let wait = lock.withLock { () -> Double in
            failures += 1
            wanted = nil
            let wait = min(300, 5 * pow(2, Double(failures - 1)))
            retryAt = Date().addingTimeInterval(wait)
            return wait
        }
        log.notice("output meter: no process tap; trying again in \(Int(wait), privacy: .public) s")
    }

    private func tearDown() {
        guard let procID = proc, #available(macOS 14.2, *) else { return }
        AudioDeviceStop(device, procID)
        AudioDeviceDestroyIOProcID(device, procID)
        AudioHardwareDestroyAggregateDevice(device)
        AudioHardwareDestroyProcessTap(tap)
        (tap, device, proc) = (AudioObjectID(kAudioObjectUnknown), AudioObjectID(kAudioObjectUnknown), nil)
    }

    private func measure(_ input: UnsafePointer<AudioBufferList>) {
        var loudest: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            var sum: Float = 0
            for i in 0..<count { sum += samples[i] * samples[i] }
            loudest = max(loudest, (sum / Float(count)).squareRoot())
        }
        let now = Self.now
        lock.withLock { reading = reading?.reading(loudest, at: now) }
    }
}
