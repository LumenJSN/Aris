//
//  ArisAudioEngine.swift
//  Aris
//
//  The one owner of the microphone and the speaker during conversation, behind `arisDuplexAudio` (off by default):
//  one engine with voice processing on its input node, so Aris's own voice, played through the same IO unit, is
//  cancelled out of what the microphone hears, and Aris can hear the user while it talks on the Mac's speakers.
//  - Frames: the processed microphone at 16 kHz mono goes into the always-on ring and out to every consumer through
//    one subscription (ArisAudioFanout): the wake detector, a turn's or a card's listener (each passes on the level and
//    the recording that Smart Turn, Scribe and Whisper read). A consumer that starts late names the sample it wants
//    audio from.
//  - Lifetime and route are pure (ArisDuplexLifetime, ArisDuplexRoute); this class runs their effects on its own queue.
//    A consumer opens a ticket (the engine starts if the route allows; false: the old path serves it), attaches its sink
//    and closes the ticket when done. When the engine has to stop under consumers (lock, sleep, another Aris microphone
//    opening, a route change that no longer suits it, voice processing failing), each is told once on the main queue
//    and reopens the way it would after a device change.
//  - The AVFoundation calls sit behind ArisDuplexHardware (ArisVoiceProcessingHardware is the real one), so the
//    decisions here are tested with a fake.
//

import AVFoundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "duplex")

/// The AVFoundation surface of the duplex engine: narrow, so a fake stands in for it in tests.
protocol ArisDuplexHardware: AnyObject, Sendable {
    /// Builds a fresh engine with voice processing on and starts it; every processed 16 kHz mono chunk goes to `frames`
    /// (on the tap's thread). Returns a line for the log (the processed format). Throws when voice processing or the
    /// start fails.
    func start(frames: @escaping @Sendable ([Float]) -> Void) throws -> String
    /// Stops and lets go of the engine (and the device).
    func stop()
    var isRunning: Bool { get }
    /// The IO unit's configuration changed (any thread).
    var onConfigurationChange: (@Sendable () -> Void)? { get set }
    /// Schedules one buffer of Aris's voice on the engine's player; false when the engine isn't running.
    func play(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) -> Bool
    /// Stops the voice now (every scheduled buffer's `done` fires).
    func stopVoice()
    func setVoiceVolume(_ volume: Float)
    /// The voice's level (0...1 for the orb) and raw RMS (for the barge-in watch), on the player tap's thread.
    var onVoiceLevel: (@Sendable (_ level: Float, _ rms: Float) -> Void)? { get set }
}

/// A consumer's hold on the engine: its need, and the sink it attached.
struct ArisDuplexTicket: Hashable, Sendable {
    let id: Int
    let need: ArisDuplexLifetime.Need
}

final class ArisAudioEngine: @unchecked Sendable {
    let fanout: ArisAudioFanout
    private let hardware: ArisDuplexHardware
    /// The route as it is now, for a use (read on the engine's queue).
    private let facts: @Sendable (ArisMicUse) -> ArisDuplexRoute.Facts
    /// Runs a block after some seconds (the linger); a test runs it when it likes.
    private let after: @Sendable (Double, @escaping @Sendable () -> Void) -> Void
    private let clock: @Sendable () -> Double
    private let queue = DispatchQueue(label: "com.lumenjsn.aris.duplex", qos: .userInitiated)

    // On `queue`:
    private var lifetime = ArisDuplexLifetime()
    private var failed: Set<String> = []
    /// The device pair the engine runs on (or is starting on).
    private var key: String?
    private var nextTicket = 0
    private var consumers: [Int: Consumer] = [:]
    /// Why the last consumer went to the old path, so the log says it once per change.
    private var lastLegacyWhy: ArisDuplexRoute.Why?
    /// The lifetime's running and listening, readable from the main thread without waiting on `queue` (which may be
    /// busy starting the hardware).
    private let stateLock = NSLock()
    private var shown = (running: false, listening: false)
    private var hardwareUp = false

    private struct Consumer {
        let ticket: ArisDuplexTicket
        let lost: @Sendable () -> Void
        var token: ArisAudioFanout.Token?
    }

    init(hardware: ArisDuplexHardware, fanout: ArisAudioFanout = ArisAudioFanout(),
         facts: @escaping @Sendable (ArisMicUse) -> ArisDuplexRoute.Facts,
         after: @escaping @Sendable (Double, @escaping @Sendable () -> Void) -> Void,
         clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.hardware = hardware
        self.fanout = fanout
        self.facts = facts
        self.after = after
        self.clock = clock
        hardware.onConfigurationChange = { [weak self] in self?.queue.async { self?.configurationChanged() } }
    }

    // MARK: - Consumers

    /// Takes the engine for `need` (starting it when the route allows); nil: the old path serves this consumer.
    /// `lost`: called once on the main queue if the engine stops under it. Blocks while the engine starts: call it off
    /// the main thread (the microphone's queue).
    func open(_ need: ArisDuplexLifetime.Need, use: ArisMicUse, lost: @escaping @Sendable () -> Void) -> ArisDuplexTicket? {
        precondition(need != .voice, "the voice opens with openVoice()")
        return queue.sync {
            guard allowed(use) else { return nil }
            apply(.need(need))
            guard lifetime.running else {
                // Not started (it failed just now): whatever was taken is let go again.
                apply(.release(need))
                return nil
            }
            nextTicket += 1
            let ticket = ArisDuplexTicket(id: nextTicket, need: need)
            consumers[ticket.id] = Consumer(ticket: ticket, lost: lost)
            return ticket
        }
    }

    /// The stream for `ticket` from sample `from` (nil: from now). A ticket that was dropped meanwhile gets nothing.
    func attach(_ ticket: ArisDuplexTicket, from: Int?, sink: @escaping ArisAudioFanout.Sink) {
        queue.sync {
            guard consumers[ticket.id] != nil else { return }
            consumers[ticket.id]?.token = fanout.subscribe(from: from, sink)
        }
    }

    /// The consumer is done: its stream stops and its need is let go (the engine lingers, then stops, when it was the
    /// last). Safe after the ticket was dropped.
    func close(_ ticket: ArisDuplexTicket) {
        queue.async { [self] in
            if let token = consumers.removeValue(forKey: ticket.id)?.token { fanout.unsubscribe(token) }
            // Another ticket with the same need (two turns can't share an id; the wake word has one detector) keeps it.
            guard !consumers.values.contains(where: { $0.ticket.need == ticket.need }) else { return }
            apply(.release(ticket.need))
        }
    }

    /// A conversation opened or closed (it holds the engine between a key turn, its answer and the next voice).
    func conversation(open: Bool, use: ArisMicUse = .wake) {
        queue.async { [self] in
            if open {
                guard allowed(use) else { return }
                apply(.need(.conversation))
            } else {
                apply(.release(.conversation))
            }
        }
    }

    /// The engine runs with something listening: Aris's next line would play through the canceller.
    var servesVoice: Bool { stateLock.withLock { shown.running && shown.listening } }

    /// The engine runs now.
    var running: Bool { stateLock.withLock { shown.running } }

    // MARK: - Aris's voice

    /// A line of Aris's voice starts: true when it plays through the engine (it runs with something listening), and
    /// the engine then keeps running to the line's end. From the main thread; never waits.
    func openVoice() -> Bool {
        guard servesVoice else { return false }
        queue.async { self.apply(.need(.voice)) }
        return true
    }

    /// The line ended or stopped.
    func closeVoice() { queue.async { self.apply(.release(.voice)) } }

    func play(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) -> Bool { hardware.play(buffer, done: done) }
    func stopVoice() { hardware.stopVoice() }
    func setVoiceVolume(_ volume: Float) { hardware.setVoiceVolume(volume) }
    func onVoiceLevel(_ report: (@Sendable (Float, Float) -> Void)?) { hardware.onVoiceLevel = report }

    // MARK: - The world

    /// Locked, display asleep, the Mac going to sleep (true); back (false).
    func away(_ isAway: Bool) { queue.async { self.apply(.away(isAway)) } }

    /// Another Aris microphone is about to open an engine of its own: the duplex engine stops first, now.
    func legacyMicOpening() { queue.sync { apply(.legacyMicOpening) } }

    // MARK: - On `queue`

    private func allowed(_ use: ArisMicUse) -> Bool {
        var current = facts(use)
        current.failed = failed
        switch ArisDuplexRoute.plan(current) {
        case .duplex(let pair):
            lastLegacyWhy = nil
            if let key, key != pair { log.notice("duplex: the devices are now \(pair, privacy: .public) (were \(key, privacy: .public))") }
            key = pair
            return true
        case .legacy(let why):
            if why != lastLegacyWhy, why != .switchOff {
                log.notice("duplex: the old path serves this (\(why.rawValue, privacy: .public))")
            }
            lastLegacyWhy = why
            return false
        }
    }

    private func apply(_ event: ArisDuplexLifetime.Event) {
        let (next, effects) = lifetime.reduce(event)
        lifetime = next
        showState()
        for effect in effects { perform(effect) }
    }

    /// Running for the main thread means the hardware really runs (a line scheduled while it starts would be lost).
    private func showState() {
        let state = (running: lifetime.running && hardwareUp, listening: lifetime.listening)
        stateLock.withLock { shown = state }
    }

    private func perform(_ effect: ArisDuplexLifetime.Effect) {
        switch effect {
        case .start: startHardware()
        case .rebuild:
            stopHardware()
            log.notice("duplex: the configuration changed; rebuilding")
            startHardware(restart: false)
        case .stop:
            stopHardware()
            log.notice("duplex: stopped (microphone closed)")
        case .stopAfterLinger(let token):
            after(ArisDuplexLifetime.linger) { [weak self] in self?.queue.async { self?.apply(.lingerElapsed(token: token)) } }
        case .dropConsumers: dropConsumers()
        case .markFailed:
            guard let key, failed.insert(key).inserted else { return }
            // Once per device pair for the rest of this run; the user is told nothing (the old path just works).
            log.error("duplex: voice processing failed on \(key, privacy: .public); the old path for the rest of this run")
        }
    }

    /// `restart`: a new take (the ring's pre-roll never reaches into the last one); a rebuild keeps the stream going.
    private func startHardware(restart: Bool = true) {
        if restart { fanout.restart() }
        let fanout = fanout
        do {
            let line = try hardware.start { samples in fanout.push(samples) }
            hardwareUp = true
            log.notice("duplex: started on \(self.key ?? "?", privacy: .public): \(line, privacy: .public)")
            apply(.started(ok: true))
        } catch {
            log.error("duplex: couldn't start: \(String(describing: error), privacy: .public)")
            stopHardware()
            apply(.started(ok: false))
        }
    }

    private func stopHardware() {
        hardware.stop()
        hardwareUp = false
        showState()
    }

    private func dropConsumers() {
        let dropped = consumers.values
        consumers = [:]
        fanout.unsubscribeAll()
        // Their needs were holds on an engine that is gone: let go, so a later open starts it afresh. An open
        // conversation's own hold stays (it is let go when the conversation closes).
        for need in Set(dropped.map(\.ticket.need)) { apply(.release(need)) }
        let calls = dropped.map(\.lost)
        guard !calls.isEmpty else { return }
        DispatchQueue.main.async { calls.forEach { $0() } }
    }

    private func configurationChanged() {
        // A change the engine rode through (it still runs) needs nothing.
        guard lifetime.running, !hardware.isRunning else { return }
        let allows = allowed(.wake)
        apply(.configurationChanged(routeAllows: allows, at: clock()))
    }
}
