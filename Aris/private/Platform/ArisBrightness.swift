//
//  ArisBrightness.swift
//  Aris
//
//  Screen brightness for voice commands ("밝기 올려 / 30"), through the XPC helper. Steps that arrive while a
//  change is on its way are added up and sent together next, so no press is lost. A change can be waited on to hear
//  whether the display really took it (a third-party display with the lid closed doesn't; neither does a helper that
//  fails or never answers), so Aris never says "올렸어요" for one that didn't.
//

import Foundation

/// Adds up brightness steps while one is being sent.
struct ArisStepQueue {
    private(set) var inFlight = false
    private var pending: Float = 0

    /// The step to send now, or nil when one is already on its way (then it waits, added to the others).
    mutating func add(_ delta: Float) -> Float? {
        if inFlight {
            pending += delta
            return nil
        }
        inFlight = true
        return delta
    }

    /// After a send: the steps that piled up meanwhile, to send next; nil (and idle) when there are none.
    mutating func finished() -> Float? {
        guard pending != 0 else {
            inFlight = false
            return nil
        }
        defer { pending = 0 }
        return pending
    }
}

@MainActor
final class ArisBrightness {
    static let shared = ArisBrightness(adjust: helperAdjust, set: helperSet)

    nonisolated private static func helperAdjust(_ delta: Float) async -> Bool {
        await ArisHelperClient.shared.adjustScreenBrightness(by: delta) != nil
    }

    nonisolated private static func helperSet(_ level: Float) async -> Bool {
        await ArisHelperClient.shared.setScreenBrightness(level)
    }

    /// The step for "up" / "down".
    static let step: Float = 0.15

    /// How long a change waits for the helper before it counts as not made.
    nonisolated static let patience: Duration = .seconds(3)

    private let sendAdjust: @Sendable (Float) async -> Bool
    private let sendSet: @Sendable (Float) async -> Bool
    private let patience: Duration
    private var steps = ArisStepQueue()
    /// Whoever asked for a step that is waiting to be sent, to be told how its send went.
    private var waiting: [CheckedContinuation<Bool, Never>] = []

    init(adjust: @escaping @Sendable (Float) async -> Bool, set: @escaping @Sendable (Float) async -> Bool,
         patience: Duration = ArisBrightness.patience) {
        sendAdjust = adjust
        sendSet = set
        self.patience = patience
    }

    /// Moves the brightness by `delta` (±0.15 for up / down), without waiting to hear how it went.
    func adjust(by delta: Float) {
        queue(delta, asked: nil)
    }

    /// Sets the brightness to `level`, clamped to 0…1, without waiting to hear how it went.
    func set(_ level: Float) {
        Task { _ = await change(to: level) }
    }

    /// Moves the brightness by `delta`; true only when the display took it.
    func change(by delta: Float) async -> Bool {
        await withCheckedContinuation { queue(delta, asked: $0) }
    }

    /// Sets the brightness to `level`, clamped to 0…1; true only when the display took it.
    func change(to level: Float) async -> Bool {
        let clamped = min(1, max(0, level))
        let send = sendSet
        return await answered { await send(clamped) }
    }

    private func queue(_ delta: Float, asked: CheckedContinuation<Bool, Never>?) {
        guard let now = steps.add(delta) else {
            if let asked { waiting.append(asked) }
            return
        }
        Task { await send(now, for: asked.map { [$0] } ?? []) }
    }

    /// Sends `delta`, then whatever piled up meanwhile; each send's answer goes to those who asked for its steps.
    private func send(_ delta: Float, for first: [CheckedContinuation<Bool, Never>]) async {
        var next: Float? = delta
        var asked = first
        var changed = false
        while let step = next {
            let send = sendAdjust
            changed = await answered { await send(step) }
            asked.forEach { $0.resume(returning: changed) }
            next = steps.finished()
            asked = waiting
            waiting = []
        }
        // Steps that cancelled each other out (up, then down): nothing more to send; the display answered as it just did.
        asked.forEach { $0.resume(returning: changed) }
    }

    /// The helper's answer, or false when it hasn't come within `patience`.
    private func answered(_ send: @escaping @Sendable () async -> Bool) async -> Bool {
        let work = Task<Bool?, Never> { await send() }
        return await ArisTaskRace.value(of: work, within: patience) ?? false
    }
}
