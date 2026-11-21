//
//  ArisSampleRing.swift
//  Aris
//
//  The last few seconds of the microphone (16 kHz mono in the duplex engine), addressed by absolute sample index: the
//  first sample ever written is 0 and every later one counts on from there, across wraps. A consumer that starts late
//  asks for audio "from sample N" and gets what is still held from there; older than that is gone. Foundation only.
//

import Foundation

struct ArisSampleRing {
    let capacity: Int
    private var storage: [Float]
    /// Samples written since the ring was made: the index the next sample gets.
    private(set) var written = 0
    /// Reads never reach back before this index (set when the stream restarts: what came before is another take).
    private(set) var floor = 0

    init(capacity: Int) {
        precondition(capacity > 0, "a ring holds at least one sample")
        self.capacity = capacity
        storage = [Float](repeating: 0, count: capacity)
    }

    /// The oldest index a read can still return.
    var oldest: Int { max(floor, written - capacity) }

    /// How many samples a read from `oldest` returns now.
    var held: Int { written - oldest }

    mutating func append<C: Collection>(_ samples: C) where C.Element == Float {
        let count = samples.count
        guard count > 0 else { return }
        // More than the ring holds: only the last `capacity` are kept, at the positions their indices map to.
        let skipped = max(0, count - capacity)
        var position = (written + skipped) % capacity
        storage.withUnsafeMutableBufferPointer { buffer in
            for sample in samples.dropFirst(skipped) {
                buffer[position] = sample
                position += 1
                if position == capacity { position = 0 }
            }
        }
        written += count
    }

    /// Marks a new take: nothing before the current end is read any more.
    mutating func restart() { floor = written }

    /// The held samples from index `from` (clamped into what is held: older is gone, later is not there yet), at most
    /// `limit` of them, with the index the first one has.
    func read(from: Int, limit: Int = .max) -> (start: Int, samples: [Float]) {
        let start = min(max(from, oldest), written)
        let available = written - start
        let count = max(0, min(available, limit))
        guard count > 0 else { return (start, []) }
        var out = [Float](repeating: 0, count: count)
        var position = start % capacity
        storage.withUnsafeBufferPointer { buffer in
            for i in 0..<count {
                out[i] = buffer[position]
                position += 1
                if position == capacity { position = 0 }
            }
        }
        return (start, out)
    }

    /// The last `count` samples held (fewer when less is held).
    func last(_ count: Int) -> [Float] {
        read(from: written - max(0, count)).samples
    }
}
