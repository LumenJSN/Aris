//
//  ArisWorldAudio.swift
//  Aris
//
//  The world's audio sources: one watch on the device list and the default input (ArisMicWatch, a burst settles into
//  one change, published as .audioDevices), one on the default output and its data source (the headphone jack), read
//  into the route (output kind, names), and one on every input device running somewhere, which says whether another
//  app has a microphone open (a call, most likely; ArisWakeRestProbe.recorder, read off the main thread and steadied
//  as ArisWakeRest.MicUse steadies it). Only device properties are read: nothing here opens a device.
//

import AppKit
import CoreAudio
import Foundation

@MainActor
final class ArisWorldAudio {
    private weak var world: ArisWorld?
    private var deviceWatch: ArisMicWatch?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var micUse = ArisWakeRest.MicUse()
    private var probing = false
    private var probeAgain = false
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.world-audio", qos: .utility)

    init(world: ArisWorld) {
        self.world = world
        deviceWatch = ArisMicWatch { [weak self] in
            MainActor.assumeIsolated {
                self?.listen()
                self?.world?.note(.audioDevices)
                self?.readRoute()
            }
        }
        listen()
        var now = world.snapshot
        now.audio = Self.route()
        world.seed(now)
        probeRecorder()
    }

    // MARK: - Listening

    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// (Again) on the default output, its data source, and every input device's running state.
    private func listen() {
        for (object, address, block) in listeners {
            var where_ = address
            AudioObjectRemovePropertyListenerBlock(object, &where_, .main, block)
        }
        listeners = []
        let route: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.readRoute()
                // Not from inside the listener being replaced: the next turn of the main queue.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.listen() } }
            }
        }
        add(AudioObjectID(kAudioObjectSystemObject), Self.address(kAudioHardwarePropertyDefaultOutputDevice), route)
        add(AudioObjectID(kAudioObjectSystemObject), Self.address(kAudioHardwarePropertyDefaultInputDevice), route)
        if let output = Self.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) {
            add(output, Self.address(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.readRoute() }
            }
        }
        for device in ArisMicDevices.all() where device.hasInput {
            add(device.id, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.probeRecorder() }
            }
        }
    }

    private func add(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ block: @escaping AudioObjectPropertyListenerBlock) {
        var where_ = address
        if AudioObjectAddPropertyListenerBlock(object, &where_, .main, block) == noErr { listeners.append((object, address, block)) }
    }

    // MARK: - The route

    private func readRoute() { world?.note(.audioRoute(Self.route())) }

    static func route() -> ArisWorldSnapshot.AudioRoute? {
        guard let output = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        let transport: ArisAudioOutputKind.Transport = switch ArisAudioDevice.transport(code: number(output, address(kAudioDevicePropertyTransportType)) ?? 0) {
        case .builtIn: .builtIn
        case .bluetooth: .bluetooth
        default: .other
        }
        let source = number(output, address(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput)).map(fourCharacters)
        let kind = ArisAudioOutputKind.of(transport: transport, dataSource: source, hasInput: hasInputStreams(output))
        return .init(output: kind, outputName: name(output), inputName: defaultDevice(kAudioHardwarePropertyDefaultInputDevice).flatMap(name))
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        number(AudioObjectID(kAudioObjectSystemObject), address(selector)).flatMap { $0 == kAudioObjectUnknown ? nil : $0 }
    }

    private static func number(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var where_ = address
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &where_, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func name(_ device: AudioDeviceID) -> String? {
        var where_ = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &where_, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func hasInputStreams(_ device: AudioDeviceID) -> Bool {
        var where_ = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &where_, 0, nil, &size) == noErr && size > 0
    }

    private static func fourCharacters(_ code: UInt32) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }, as: UTF8.self)
    }

    // MARK: - Another app on the microphone

    /// Who records now, read off the main thread; one read at a time, and one more if asked meanwhile.
    private func probeRecorder() {
        guard !probing else { probeAgain = true; return }
        probing = true
        queue.async {
            let recorder = ArisWakeRestProbe.recorder()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.took(recorder) } }
        }
    }

    private func took(_ recorder: ArisOtherAudio.Process?) {
        probing = false
        let now = ProcessInfo.processInfo.systemUptime
        let inUse = micUse.note(recording: recorder != nil, at: now)
        if let recorder {
            world?.note(.recorder(Self.appName(recorder)))
        } else if !inUse {
            world?.note(.recorder(nil))
        } else {
            // A microphone closed: it counts as in use a little longer (calls open and close it in bursts), then is
            // looked at again.
            DispatchQueue.main.asyncAfter(deadline: .now() + ArisWakeRest.MicUse.resumeAfter + 0.1) { [weak self] in
                MainActor.assumeIsolated { self?.probeRecorder() }
            }
        }
        if probeAgain {
            probeAgain = false
            probeRecorder()
        }
    }

    private static func appName(_ recorder: ArisOtherAudio.Process) -> String {
        let app = NSRunningApplication(processIdentifier: recorder.pid)
        return app?.localizedName ?? recorder.bundle ?? "pid \(recorder.pid)"
    }
}
