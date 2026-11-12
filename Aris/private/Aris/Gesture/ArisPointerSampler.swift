//
//  ArisPointerSampler.swift
//  Aris
//
//  The pointer, sampled off the main thread every 4 ms from the moment ⌥⇧ goes down until the drawing session ends,
//  each position stamped when it was read. The gesture pump drains it on the main thread.
//
//  Why (the owner, 2026-11-04: "약간 가다가 꺾여"): the pump used to read the pointer in a main-actor hop and stamp it when
//  the hop ran. Whenever the main thread was busy (the notch listening and animating, a capture starting), ticks
//  waited and then ran back to back, so the positions in between were never read: the ink went straight across the
//  gap and turned a corner at its end. Read here, every position the system reports is kept with its own time, and the
//  first ones (inside the 120 ms debounce and the 200 ms commit wait) are there to replay when the ink arms.
//

import CoreGraphics
import Foundation
import QuartzCore

/// The samples between drains: a moved position only, the newest `cap` kept (about a second at 4 ms). Pure, so the
/// tests run it.
struct ArisPointerRing {
    static let cap = 250
    private(set) var samples: [ArisGesturePoint] = []
    private var last: ArisGesturePoint?

    mutating func push(_ p: ArisGesturePoint) {
        if let last, last.x == p.x, last.y == p.y { return }
        last = p
        samples.append(p)
        if samples.count > Self.cap { samples.removeFirst(samples.count - Self.cap) }
    }

    /// Everything since the last drain, oldest first.
    mutating func drain() -> [ArisGesturePoint] {
        defer { samples.removeAll(keepingCapacity: true) }
        return samples
    }

    mutating func reset() {
        samples.removeAll()
        last = nil
    }
}

/// Runs while the gesture key is held or a drawing session runs. Positions are Cocoa global points (bottom-left
/// origin, as NSEvent.mouseLocation), times in ms on CACurrentMediaTime's clock (the controller's).
final class ArisPointerSampler: @unchecked Sendable {
    static let shared = ArisPointerSampler()
    static let intervalMs = 4

    private let queue = DispatchQueue(label: "com.lumenjsn.aris.pointer", qos: .userInteractive)
    private let lock = NSLock()
    private var ring = ArisPointerRing()
    private var timer: DispatchSourceTimer?
    private var keyHeld = false
    private var sessionRunning = false

    /// ⌥⇧ went down (or the press ended): samples are kept from now, before the turn even starts.
    func key(held: Bool) {
        lock.withLock { keyHeld = held }
        update()
    }

    /// The drawing session started or ended.
    func session(running: Bool) {
        lock.withLock { sessionRunning = running }
        update()
    }

    /// Every position read since the last drain, oldest first.
    func drain() -> [ArisGesturePoint] {
        lock.withLock { ring.drain() }
    }

    private func update() {
        let wanted = lock.withLock { keyHeld || sessionRunning }
        queue.async { [self] in
            if wanted, timer == nil {
                lock.withLock { ring.reset() }
                let t = DispatchSource.makeTimerSource(queue: queue)
                t.schedule(deadline: .now(), repeating: .milliseconds(Self.intervalMs), leeway: .microseconds(500))
                t.setEventHandler { [weak self] in self?.sample() }
                t.resume()
                timer = t
            } else if !wanted, let t = timer {
                t.cancel()
                timer = nil
                lock.withLock { ring.reset() }
            }
        }
    }

    private func sample() {
        // Backstop for a key-up the tap never heard: with ⌥⇧ up and no session marked running, it stops. It can't tell
        // a session that ended without calling session(running: false): the controller's teardown must say so.
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let keysDown = flags.contains(.maskAlternate) && flags.contains(.maskShift)
        if !keysDown, !lock.withLock({ sessionRunning }) {
            lock.withLock { keyHeld = false }
            timer?.cancel()
            timer = nil
            lock.withLock { ring.reset() }
            return
        }
        guard let location = CGEvent(source: nil)?.location else { return }
        let height = CGDisplayBounds(CGMainDisplayID()).height
        let p = ArisGesturePoint(x: location.x, y: height - location.y, t: CACurrentMediaTime() * 1000)
        lock.withLock { ring.push(p) }
    }
}
