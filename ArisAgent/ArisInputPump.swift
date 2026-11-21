//
//  ArisInputPump.swift
//  aris-agent
//
//  What the runner writes to its brain's stdin, written off the runner's queue: a brain that stops reading (stuck in a
//  tool, its pipe full) used to block the queue, and with it every line, card answer and timer of that runner. The
//  pump writes in order on a queue of its own; the runner only hands lines over. What is waiting is bounded: a brain
//  that has not taken that much is treated as gone (`failed` is called once, on the runner's queue), as a failed write
//  was before.
//

import Foundation

final class ArisInputPump {
    /// The most bytes waiting to be written (a turn's images are the largest lines: well under this).
    static let defaultLimit = 64 * 1_024 * 1_024

    private let handle: FileHandle
    private let writer = DispatchQueue(label: "com.lumenjsn.aris.agent.stdin")
    private let lock = NSLock()
    private var waiting = 0
    private var broken = false
    private let limit: Int
    private let owner: DispatchQueue
    private let failed: (String) -> Void

    /// `failed`: on `owner`, once, with why (the write's error, or the limit).
    init(handle: FileHandle, owner: DispatchQueue, limit: Int = ArisInputPump.defaultLimit, failed: @escaping (String) -> Void) {
        self.handle = handle
        self.owner = owner
        self.limit = limit
        self.failed = failed
    }

    /// Bytes handed over and not yet written.
    var backlog: Int { lock.withLock { waiting } }

    /// Hands `lines` over; never blocks.
    func write(_ lines: [Data]) {
        let size = lines.reduce(0) { $0 + $1.count }
        guard size > 0 else { return }
        let over = lock.withLock { () -> Bool? in
            guard !broken else { return nil }
            if waiting + size > limit {
                broken = true
                return true
            }
            waiting += size
            return false
        }
        guard let over else { return }
        if over { return fail("the brain stopped reading its input (\(limit / 1_024 / 1_024) MiB waiting)") }
        writer.async { [self] in
            guard !lock.withLock({ broken }) else { return }
            do {
                for line in lines { try handle.write(contentsOf: line) }
                lock.withLock { waiting -= size }
            } catch {
                guard lock.withLock({ () -> Bool in
                    defer { broken = true }
                    return !broken
                }) else { return }
                fail(error.localizedDescription)
            }
        }
    }

    /// The process ended or was stopped: nothing more is written, and nothing is reported.
    func close() {
        lock.withLock { broken = true }
    }

    private func fail(_ why: String) {
        owner.async { [failed] in failed(why) }
    }
}
