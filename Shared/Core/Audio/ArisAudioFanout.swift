//
//  ArisAudioFanout.swift
//  Aris
//
//  One microphone stream, many consumers (the wake detector, a turn's listener, a card's listener; each passes on the
//  level for the orb and the 16 kHz recording Smart Turn and Whisper read). Every chunk goes into the always-on ring
//  (ArisSampleRing, about 8 s) and then to each subscriber, in the order they subscribed. A subscriber that starts late
//  names the sample it wants audio from: what the ring still holds from there is handed over first, then every chunk
//  that follows, with no gap and nothing twice (both happen under one lock). Foundation only; thread-safe.
//

import Foundation

final class ArisAudioFanout: @unchecked Sendable {
    /// A chunk and the absolute index of its first sample.
    typealias Sink = (_ samples: [Float], _ start: Int) -> Void

    struct Token: Hashable, Sendable {
        let id: Int
    }

    static let sampleRate = 16_000.0
    /// What the ring keeps: enough for a late consumer's pre-roll and Smart Turn's 8 s window.
    static let heldSeconds = 8.0

    private let lock = NSLock()
    private var ring: ArisSampleRing
    private var sinks: [(id: Int, sink: Sink)] = []
    private var nextID = 0

    init(capacity: Int = Int(ArisAudioFanout.sampleRate * ArisAudioFanout.heldSeconds)) {
        ring = ArisSampleRing(capacity: capacity)
    }

    /// The index the next sample gets.
    var written: Int { lock.withLock { ring.written } }
    /// The oldest index still held.
    var oldest: Int { lock.withLock { ring.oldest } }
    var subscriberCount: Int { lock.withLock { sinks.count } }

    /// One chunk from the microphone: kept, then handed to every subscriber.
    func push(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        lock.withLock {
            let start = ring.written
            ring.append(samples)
            for entry in sinks { entry.sink(samples, start) }
        }
    }

    /// The stream starts again after a stop: a late consumer's pre-roll never reaches into the previous take.
    func restart() { lock.withLock { ring.restart() } }

    /// `from`: the first sample wanted (clamped into what is held); nil: only what comes next. The held part is handed
    /// over at once, on the caller's thread, before this returns.
    @discardableResult
    func subscribe(from: Int?, _ sink: @escaping Sink) -> Token {
        lock.withLock {
            if let from {
                let held = ring.read(from: from)
                if !held.samples.isEmpty { sink(held.samples, held.start) }
            }
            nextID += 1
            sinks.append((nextID, sink))
            return Token(id: nextID)
        }
    }

    /// Stops handing chunks to `token`'s sink. Safe to call twice.
    func unsubscribe(_ token: Token) {
        lock.withLock { sinks.removeAll { $0.id == token.id } }
    }

    /// Everyone stops getting chunks (the engine stopped for good, or fell back to the old path).
    func unsubscribeAll() {
        lock.withLock { sinks.removeAll() }
    }

    /// The held samples from `from`, for a consumer that only reads (Smart Turn's window).
    func read(from: Int, limit: Int = .max) -> (start: Int, samples: [Float]) {
        lock.withLock { ring.read(from: from, limit: limit) }
    }

    /// The last `count` samples held.
    func last(_ count: Int) -> [Float] { lock.withLock { ring.last(count) } }
}
