//
//  ArisDuplexSource.swift
//  Aris
//
//  The thin adapters between the duplex engine and the consumers that used to open engines of their own:
//  - ArisAudioSource: what a listener hears from when it doesn't open the microphone itself (the wake detector, as
//    before; or the duplex engine's stream on a key turn or a card, ArisDuplexKeySource).
//  - ArisDuplexHold: the wake detector's hold on the engine (its chunks in place of its own tap).
//  - ArisDuplexVoice: one line of Aris's voice on the engine's player, so the canceller has it as its reference.
//

import AVFoundation

/// A 16 kHz stream a listener can hear from, from a given sample: `forward(to:from:)` hands `sink` the held audio
/// from `from`, then every chunk with its level, until it is called with nil.
protocol ArisAudioSource: AnyObject {
    func forward(to sink: (([Float], Float) -> Void)?, from: Int?)
}

extension ArisAudioSource {
    func forward(to sink: (([Float], Float) -> Void)?) { forward(to: sink, from: nil) }
}

extension ArisWakeDetector: ArisAudioSource {}

/// The wake detector's hold: its chunks from the engine, from now on.
final class ArisDuplexHold: @unchecked Sendable {
    private let engine: ArisAudioEngine
    private let ticket: ArisDuplexTicket

    private init(engine: ArisAudioEngine, ticket: ArisDuplexTicket) {
        self.engine = engine
        self.ticket = ticket
    }

    /// The engine's stream for the wake detector, when the switch is on and the route allows it; nil: the detector opens
    /// its own engine as before. `lost`: on the main queue, once, when the engine stops under it. Off the main thread.
    static func open(sink: @escaping @Sendable ([Float]) -> Void, lost: @escaping @Sendable () -> Void) -> ArisDuplexHold? {
        guard let engine = ArisDuplexAudio.engine, let ticket = engine.open(.wake, use: .wake, lost: lost) else { return nil }
        engine.attach(ticket, from: nil) { samples, _ in sink(samples) }
        return ArisDuplexHold(engine: engine, ticket: ticket)
    }

    func close() { engine.close(ticket) }
}

/// A key turn's or a card's microphone from the duplex engine: taken when the listener starts (before its recognizer
/// is ready), so everything from that moment waits in the ring and is handed over once the recognizer listens. The
/// first word is never lost to the recognizer's start-up.
final class ArisDuplexKeySource: ArisAudioSource, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var nextID = 0

    private let engine: ArisAudioEngine
    private let ticket: ArisDuplexTicket
    /// The sample the turn's audio starts at: where the ring was when the turn took the engine.
    let mark: Int
    private var closed = false

    private init(engine: ArisAudioEngine, ticket: ArisDuplexTicket, mark: Int) {
        self.engine = engine
        self.ticket = ticket
        self.mark = mark
    }

    /// The duplex stream for a turn's listener (`use` .talk: a key turn, a card, the countdown), when the switch is on
    /// and the route allows it; nil: the listener opens its own microphone as before. Dictation keeps its own engine.
    /// Waits for the engine off the main thread. `lost`: on the main queue when the engine stops under the turn.
    static func open(use: ArisMicUse, lost: @escaping @Sendable () -> Void) async -> ArisDuplexKeySource? {
        guard use == .talk, let engine = ArisDuplexAudio.engine else { return nil }
        let id = lock.withLock { () -> Int in
            nextID += 1
            return nextID
        }
        return await withCheckedContinuation { continuation in
            ArisAudio.microphoneQueue.async {
                guard let ticket = engine.open(.turn(id), use: use, lost: lost) else { return continuation.resume(returning: nil) }
                continuation.resume(returning: ArisDuplexKeySource(engine: engine, ticket: ticket, mark: engine.fanout.written))
            }
        }
    }

    /// From `from` (nil: the mark), then live, each chunk with its level for the orb; nil lets the engine go.
    func forward(to sink: (([Float], Float) -> Void)?, from: Int?) {
        guard let sink else { return close() }
        engine.attach(ticket, from: from ?? mark) { samples, _ in sink(samples, min(1, ArisVoicePrint.rms(samples[...]) * 8)) }
    }

    private func close() {
        let first = Self.lock.withLock { () -> Bool in
            defer { closed = true }
            return !closed
        }
        if first { engine.close(ticket) }
    }
}

/// One line of Aris's voice through the duplex engine: its buffers on the engine's player, its level to the orb and the
/// barge-in meter, and the engine held until the line ends.
@MainActor
final class ArisDuplexVoice {
    private let engine: ArisAudioEngine
    private var ended = false

    private init(engine: ArisAudioEngine) { self.engine = engine }

    /// The line plays through the canceller when the engine runs with something listening; nil: the old output.
    static func begin(meter: ArisPlaybackMeter, onLevel: ((Float) -> Void)?) -> ArisDuplexVoice? {
        guard let engine = ArisDuplexAudio.existing, ArisDuplexSwitch.isOn, engine.openVoice() else {
            ArisDuplexAudio.lastLineCancelled = false
            return nil
        }
        ArisDuplexAudio.lastLineCancelled = true
        let report = onLevel.map { handler in { @Sendable (level: Float) in DispatchQueue.main.async { MainActor.assumeIsolated { handler(level) } } } }
        engine.onVoiceLevel { level, rms in
            meter.set(rms)
            report?(level)
        }
        engine.setVoiceVolume(1)
        return ArisDuplexVoice(engine: engine)
    }

    var volume: Float = 1 {
        didSet { engine.setVoiceVolume(volume) }
    }

    /// False when the engine stopped under the line (the rest of it is dropped, as on the old output).
    func play(_ buffer: AVAudioPCMBuffer, done: @escaping @Sendable () -> Void) -> Bool { !ended && engine.play(buffer, done: done) }

    /// Cut off now (every scheduled buffer's completion fires).
    func stop() { engine.stopVoice() }

    /// The line is over: the engine may stop once nothing listens.
    func end() {
        guard !ended else { return }
        ended = true
        engine.onVoiceLevel(nil)
        engine.closeVoice()
    }
}
