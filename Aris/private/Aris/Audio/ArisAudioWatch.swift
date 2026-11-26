//
//  ArisAudioWatch.swift
//  Aris
//
//  The listeners ArisWorldAudio needs, as one set made to match the devices: on the system object the default output
//  and the device list for the app's life (and the default input only while the microphone choice follows the system,
//  ArisMicSetting), the default output's data source (the headphone jack), and every input device's running-somewhere
//  (another app on a microphone). A notice only pokes its coalescer; the coalesced re-read on the main queue reads the
//  devices again, applies the difference to the set and then says what changed (route, devices, recorder).
//

import CoreAudio
import Foundation

/// Main thread only (the coalescers' actions run there); @unchecked so the HAL-thread callbacks can hold it.
final class ArisAudioWatch: @unchecked Sendable {
    enum Event: Equatable { case route, devices, recorder }

    /// The device list and the default input change in bursts (a headset connecting changes the list, then the
    /// default): one re-read after this (it was ArisMicWatch.settleTime).
    static let deviceSettle: TimeInterval = 0.6

    private let hal: ArisAudioHAL
    private let listeners: ArisAudioListenerSet
    private let followsSystemInput: () -> Bool
    private let onEvent: (Event) -> Void
    private var coalescers: [Event: ArisAudioCoalescer] = [:]

    init(hal: ArisAudioHAL, followsSystemInput: @escaping () -> Bool, schedule: @escaping ArisAudioCoalescer.Schedule = ArisAudioCoalescer.onMain,
         onEvent: @escaping (Event) -> Void) {
        self.hal = hal
        listeners = ArisAudioListenerSet(hal: hal, owner: "world audio")
        self.followsSystemInput = followsSystemInput
        self.onEvent = onEvent
        for event in [Event.route, .devices, .recorder] {
            coalescers[event] = ArisAudioCoalescer(window: event == .devices ? Self.deviceSettle : ArisAudioCoalescer.window, schedule: schedule) { [weak self] in
                self?.fired(event)
            }
        }
    }

    /// What is registered now (the tests count it).
    var registered: Set<ArisAudioKey> { Set(listeners.registered.keys) }

    /// Reads the devices and makes the listeners match them: at launch, after a coalesced notice, and when the
    /// microphone choice changes.
    func resync() {
        listeners.sync(Self.wanted(hal.scene(), followsSystemInput: followsSystemInput())) { [coalescers] key in
            let coalescer = coalescers[Self.event(for: key.selector)]
            return { coalescer?.poke() }
        }
    }

    func stop() { listeners.removeAll() }

    private func fired(_ event: Event) {
        if event != .recorder { resync() }
        onEvent(event)
    }

    static func wanted(_ scene: ArisAudioScene, followsSystemInput: Bool) -> Set<ArisAudioKey> {
        var keys: Set<ArisAudioKey> = [.system(kAudioHardwarePropertyDefaultOutputDevice), .system(kAudioHardwarePropertyDevices)]
        if followsSystemInput { keys.insert(.system(kAudioHardwarePropertyDefaultInputDevice)) }
        if let output = scene.output {
            keys.insert(ArisAudioKey(object: output, selector: kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput))
        }
        for input in scene.inputs { keys.insert(ArisAudioKey(object: input, selector: kAudioDevicePropertyDeviceIsRunningSomewhere)) }
        return keys
    }

    static func event(for selector: AudioObjectPropertySelector) -> Event {
        switch selector {
        case kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice: .devices
        case kAudioDevicePropertyDeviceIsRunningSomewhere: .recorder
        default: .route
        }
    }
}
