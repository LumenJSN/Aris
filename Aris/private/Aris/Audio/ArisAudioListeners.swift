//
//  ArisAudioListeners.swift
//  Aris
//
//  Core Audio property listeners that can be taken out again (the 1.3.1 hang, 2026-11-25: a day and a half in, the
//  main thread spent all its time adding and failing to remove listeners). A listener block handed to
//  AudioObjectAddPropertyListenerBlock from Swift is re-wrapped into a new block object on every call, a stored
//  `@convention(block)` value too, so AudioObjectRemovePropertyListenerBlock never matched what was added, said noErr
//  anyway, and every default-output change ran `listen()` once for each route listener left behind, which added more.
//  So listeners here are a C function and a token (AudioObjectAddPropertyListener's proc and client data), which the
//  HAL compares by value, kept in one dictionary by object and property:
//  - `sync` makes what is registered exactly what is wanted: only new keys are added and only gone ones removed;
//    a key wanted all along (the system object's) is registered once and never touched again.
//  - Every add and remove is checked; a failure is one log line, and a failed add is not kept (the next sync tries).
//  - A token's callback runs on the HAL's thread and may only poke an ArisAudioCoalescer: at most one re-read waits
//    on the main queue, a burst inside its window is one re-read, and no callback adds or removes a listener.
//

import CoreAudio
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "audio-listeners")

/// One property of one Core Audio object.
struct ArisAudioKey: Hashable, CustomStringConvertible {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    var scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    var element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain

    var address: AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element) }

    var description: String { "\(ArisAudioDevice.fourCC(selector)) on \(object)" }

    static func system(_ selector: AudioObjectPropertySelector) -> ArisAudioKey {
        ArisAudioKey(object: AudioObjectID(kAudioObjectSystemObject), selector: selector)
    }
}

/// What one registration calls; its identity is the client data the HAL is given, so remove matches add exactly.
final class ArisAudioToken: @unchecked Sendable {
    let key: ArisAudioKey
    private let callback: @Sendable () -> Void

    init(_ key: ArisAudioKey, _ callback: @escaping @Sendable () -> Void) {
        self.key = key
        self.callback = callback
    }

    /// On the HAL's thread.
    func fire() { callback() }
}

/// The seam around Core Audio: add, remove, and the device facts a watch reads (a fake in the tests).
protocol ArisAudioHAL: AnyObject {
    func add(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus
    func remove(_ key: ArisAudioKey, _ token: ArisAudioToken) -> OSStatus
    /// The default output and the devices that can record, as they are now.
    func scene() -> ArisAudioScene
}

struct ArisAudioScene: Equatable {
    var output: AudioObjectID?
    var inputs: [AudioObjectID] = []
}

/// The listeners one owner holds, by key. Main thread only.
final class ArisAudioListenerSet {
    private let hal: ArisAudioHAL
    private let owner: String
    private(set) var registered: [ArisAudioKey: ArisAudioToken] = [:]
    /// Removed tokens stay alive this long: a call the HAL had already started may still reach one.
    static let retireAfter: TimeInterval = 5

    init(hal: ArisAudioHAL, owner: String) {
        self.hal = hal
        self.owner = owner
    }

    /// Registers exactly `wanted`: adds the new keys (with `callback(key)`), removes the gone ones, leaves the rest.
    func sync(_ wanted: Set<ArisAudioKey>, callback: (ArisAudioKey) -> @Sendable () -> Void) {
        for (key, token) in registered where !wanted.contains(key) { remove(key, token) }
        for key in wanted where registered[key] == nil {
            let token = ArisAudioToken(key, callback(key))
            let status = hal.add(key, token)
            guard status == noErr else {
                log.error("\(self.owner, privacy: .public): listener on \(key.description, privacy: .public) not added (\(status, privacy: .public))")
                continue
            }
            registered[key] = token
        }
    }

    /// Takes every listener out (the owner going away).
    func removeAll() { sync([]) { _ in {} } }

    private func remove(_ key: ArisAudioKey, _ token: ArisAudioToken) {
        registered[key] = nil
        let status = hal.remove(key, token)
        // A device that has gone takes its listeners with it and says so (kAudioHardwareBadObjectError): still one line.
        if status != noErr {
            log.notice("\(self.owner, privacy: .public): listener on \(key.description, privacy: .public) not removed (\(status, privacy: .public)); dropped")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retireAfter) { _ = token }
    }
}

/// At most one pending call of `action` on the main queue: the first poke schedules it `window` later, pokes until
/// it runs add nothing. Thread-safe; `action` runs on the main queue (or wherever the injected schedule runs it).
final class ArisAudioCoalescer: @unchecked Sendable {
    typealias Schedule = @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Void

    /// A burst of route or device-state notices inside this is one re-read.
    static let window: TimeInterval = 0.25

    static let onMain: Schedule = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }

    private let lock = NSLock()
    private var pending = false
    private let delay: TimeInterval
    private let schedule: Schedule
    private let action: @Sendable () -> Void

    init(window: TimeInterval = ArisAudioCoalescer.window, schedule: @escaping Schedule = ArisAudioCoalescer.onMain,
         action: @escaping @Sendable () -> Void) {
        delay = window
        self.schedule = schedule
        self.action = action
    }

    func poke() {
        let first = lock.withLock { () -> Bool in
            guard !pending else { return false }
            pending = true
            return true
        }
        guard first else { return }
        schedule(delay) { [self] in
            lock.withLock { pending = false }
            action()
        }
    }
}
