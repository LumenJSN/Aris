//
//  ArisGestureCapture.swift
//  Aris
//
//  Turns accepted circles into numbered shots:
//  - a clean frame per drawn display, taken when the pointer arms and re-taken when stale (front app changed, a
//    hands-free click) or older than 4 s held / 1.5 s hands-free; a crop waits for it at most 1.5 s;
//  - at detection (before anything waits) the voiced time is read and the five samples hit-tested, in parallel with a
//    frame refresh; the crop is the circled window or the padded loop;
//  - each shot: crop → ≤ 2560 px → recency ink + badge → JPEG 0.90, and a PNG thumb ≤ 640 w without the number;
//  - at finalize, per drawn display, the drawing reference (budget 1280/800, ink at 0.55, JPEG 0.80); the result is
//    parked for the turn ≤ 30 s, then dropped.
//  - a shot still being made when the key is let go isn't lost (audit imp-1): the result waits for it (at most 0.9 s).
//  Frames come from `ArisScreenCapture` (its filter keeps Aris's own windows and the private apps out of every frame,
//  and it gives nothing under secure input). Nothing is written to disk; frames are released at finalize or abort.
//

import CoreGraphics
import Foundation
import os
import QuartzCore

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "gesture")

/// Where clean frames come from: `ArisScreenCapture` in the app (ArisController+Gesture), a fake in the tests.
protocol ArisGestureFrameSource: Sendable {
    func frame(display: CGDirectDisplayID, budget: ArisImageBudget, showsCursor: Bool) async -> CGImage?
}

@MainActor
final class ArisGestureCapture: ArisGestureCapturing {
    struct Dependencies {
        var screen: ArisGestureFrameSource
        /// The window under each sample (Quartz global points).
        var windowsAt: @MainActor ([CGPoint]) -> [ArisWindowHit]
        /// A display's bounds in Quartz global points (`CGDisplayBounds`).
        var displayBounds: (UInt32) -> CGRect
        /// Milliseconds, the gesture controller's clock.
        var now: () -> Double
        var secureInput: () -> Bool
        /// How long a parked result waits for its turn.
        var parkFor: Duration = .milliseconds(Int(ArisGestureConstants.Session.collectMaxAgeMs))
    }

    private typealias S = ArisGestureConstants.Session

    private struct Frame {
        let task: Task<CGImage?, Never>
        let takenAt: Double
        var stale = false
    }

    private struct Detection {
        let voicedMs: Double
        let capturedAtMs: Double
    }

    private let deps: Dependencies
    private var frames: [UInt32: Frame] = [:]
    private var detections: [Int: Detection] = [:]
    private var made: [Int: ArisGestureShot] = [:]
    private var kept: [Int: ArisGestureShot] = [:]
    /// Shots being made now, by capture id.
    private var making: [Int: Task<Bool?, Never>] = [:]
    /// Shots that were still being made when the key was let go (audit imp-1: the user says the request, circles last and
    /// lets go at once). They may finish after finalize, and its result waits for them: a circle drawn just before the
    /// release is kept, where it used to be dropped as "finalized".
    private var late: Set<Int> = []
    private var lateShots: [Int: ArisGestureShot] = [:]
    /// How long the result waits for such a shot: what the turn's own wait (`collect`, 2.5 s) leaves after the
    /// references' frames (1.5 s), so a slow shot can never cost the turn the shots it already has.
    private static let lateShotWaitMs = S.collectWaitMs - S.shotWaitMs - 100
    private var speech = ArisSpeechActivity()
    private var finishing: Task<ArisGestureResult?, Never>?
    private var expiry: Task<Void, Never>?
    /// Bumped by finalize and abort: work from an earlier session can't land in this one.
    private var generation = 0
    /// Names the current park, so an expiry only ever drops the park it was set for.
    private var parkToken = 0

    init(dependencies: Dependencies) {
        deps = dependencies
    }

    /// Frames held now (for the tests and the release check).
    var heldFrames: Int { frames.count }
    var keptBadges: [Int] { kept.keys.sorted() }
    var isParked: Bool { finishing != nil }

    // MARK: - Speech

    /// The turn's speech window starts (key-down or wake); voiced time counts from here.
    func startSpeech(at ms: Double) {
        speech.start(at: ms)
    }

    /// One 16 kHz chunk from the microphone tee.
    func feedSpeech(_ samples: [Float], at ms: Double) {
        speech.feed(samples, sampleRate: ArisGestureConstants.Speech.sampleRate, at: ms)
    }

    var voicedMsNow: Double { speech.voicedMsNow }

    /// The turn's speech window so far, for picks made without a circle session (the talk key held).
    func speechSummary() -> (startedAtMs: Double, endedAtMs: Double, totalVoicedMs: Double)? {
        speech.summary(endedAt: deps.now())
    }

    // MARK: - ArisGestureCapturing

    func strokeStarted(on screen: ArisGestureScreen) {
        if let frame = frames[screen.id], !frame.stale { return }
        refresh(screen.id)
    }

    func pickWindow(captureId: Int, for gesture: ArisGesture, on screen: ArisGestureScreen, handsFree: Bool,
                    done: @escaping (ArisWindowHit?) -> Void) {
        // Read now, before anything waits: the marker goes at the word the user was saying when the loop closed.
        detections[captureId] = Detection(voicedMs: speech.voicedMsNow, capturedAtMs: gesture.points.last?.t ?? deps.now())
        // A missing, stale or old frame is re-taken now, in parallel with the hit-test.
        if frames[screen.id].map({ !isFresh($0, handsFree: handsFree) }) ?? true { refresh(screen.id) }
        let bounds = deps.displayBounds(screen.id)
        let box = gesture.bbox.offsetBy(dx: bounds.minX, dy: bounds.minY)
        let hits = deps.windowsAt(ArisGestureGeometry.samplePoints(in: box))
        done(ArisGestureGeometry.pickWindow(hits, bbox: box))
    }

    func capture(_ request: ArisGestureCaptureRequest, done: @escaping (Bool) -> Void) {
        let generation = self.generation, id = request.captureId
        let task = Task<Bool?, Never> { [weak self] in await self?.make(request, generation: generation) ?? false }
        making[id] = task
        Task { [weak self] in
            let ok = await task.value ?? false
            if self?.making[id] == task { self?.making[id] = nil }
            done(ok)
        }
    }

    func keep(captureId: Int, badge: Int) {
        detections[captureId] = nil
        guard let shot = made.removeValue(forKey: captureId) else { return }
        kept[badge] = shot
    }

    func drop(captureId: Int, reason: String) {
        // The session is over for the reducer, but a shot the release caught mid-make still belongs to its result.
        if late.contains(captureId) { return }
        detections[captureId] = nil
        made[captureId] = nil
        log.debug("gesture shot \(captureId, privacy: .public) dropped: \(reason, privacy: .public)")
    }

    func markFramesStale() {
        for id in frames.keys { frames[id]?.stale = true }
    }

    func finalize(strokes: [UInt32: [[ArisGesturePoint]]], handsFree: Bool) {
        dropParked() // an earlier session's result never reaches this turn
        let shots = kept.values.sorted { $0.badge < $1.badge }
        let summary = speech.summary(endedAt: deps.now())
        let drawn = strokes.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.prefix(S.maxDrawnDisplays)
        let held = frames
        let bounds = deps.displayBounds, secureInput = deps.secureInput
        // Shots still being made as the key was let go: they finish under this result, which waits for them.
        let unfinished = making.sorted { $0.key < $1.key }
        let detected = detections.filter { making[$0.key] != nil } // where the user's words were when each of those loops closed
        clearSession(cancelFrames: false) // the references still need this session's frames
        late = Set(unfinished.map(\.key))
        detections = detected
        guard !drawn.isEmpty || !shots.isEmpty || !unfinished.isEmpty else { return } // never drew: nothing to park
        let generation = self.generation
        finishing = Task { [weak self] in
            var shots = shots
            for (id, task) in unfinished {
                let ok = await Self.value(of: task, within: Self.lateShotWaitMs) ?? false
                guard let self, self.generation == generation else { return nil }
                self.late.remove(id)
                if ok, let shot = self.lateShots.removeValue(forKey: id) { shots.append(shot) }
            }
            shots.sort { $0.badge < $1.badge }
            var references: [Data] = []
            for (display, lines) in drawn {
                guard let task = held[display]?.task, let frame = await Self.value(of: task, within: S.shotWaitMs),
                      !secureInput() else { continue }
                let size = bounds(display).size
                let reference = await Task.detached(priority: .userInitiated) {
                    ArisGestureShots.reference(frame: frame, displaySize: size, strokes: lines)
                }.value
                if let reference { references.append(reference) }
            }
            guard let self, self.generation == generation else { return nil }
            log.notice("gesture result: \(shots.count, privacy: .public) shot(s), \(references.count, privacy: .public) reference(s)")
            return ArisGestureResult(shots: shots, references: references, speech: summary, handsFree: handsFree)
        }
        parkToken += 1
        let token = parkToken, parkFor = deps.parkFor
        expiry = Task { [weak self] in
            try? await Task.sleep(for: parkFor)
            guard !Task.isCancelled, let self, self.parkToken == token else { return }
            log.notice("gesture result not collected in time: dropped")
            self.dropParked()
        }
    }

    func abort() {
        clearSession(cancelFrames: true)
        dropParked()
    }

    /// Forgets a parked result (a new turn begins, or its time is up).
    func dropParked() {
        finishing?.cancel()
        finishing = nil
        expiry?.cancel()
        expiry = nil
        parkToken += 1
    }

    /// The parked result, waiting for it at most `timeout` (2.5 s). Once collected it's gone.
    func collect(timeout: Duration = .milliseconds(Int(ArisGestureConstants.Session.collectWaitMs))) async -> ArisGestureResult? {
        guard let task = finishing else { return nil }
        let ms = Double(timeout.components.seconds) * 1000 + Double(timeout.components.attoseconds) / 1e15
        let result = await Self.value(of: task, within: ms)
        if finishing == task { dropParked() } // a newer park made meanwhile stays
        return result
    }

    // MARK: - Shots

    private func make(_ r: ArisGestureCaptureRequest, generation: Int) async -> Bool {
        guard !deps.secureInput() else {
            log.notice("gesture capture: skipped, secure input")
            return false
        }
        // A shot whose session was dropped (or whose wait ran out) before it began takes no frame at all.
        guard isCurrent(generation, r.captureId) else { return false }
        guard let frame = await frame(r.screen.id, handsFree: r.handsFree, session: generation), isCurrent(generation, r.captureId) else { return false }
        let bounds = deps.displayBounds(r.screen.id)
        guard bounds.width > 0 else { return false }
        let pxPerPt = CGFloat(frame.width) / bounds.width
        let box = r.gesture.bbox.offsetBy(dx: bounds.minX, dy: bounds.minY)
        guard let crop = ArisGestureGeometry.crop(window: r.hit?.frame, bbox: box, display: bounds) else {
            log.notice("gesture capture: skipped, crop under 60 pt")
            return false
        }
        let detection = detections[r.captureId]
        let through = detection?.capturedAtMs ?? r.gesture.points.last?.t ?? deps.now()
        let after = r.inkAfterMs, strokes = r.strokes, badge = r.badge
        let started = deps.now()
        let composed = await Task.detached(priority: .userInitiated) {
            ArisGestureShots.compose(frame: frame, cropPt: crop, pxPerPt: pxPerPt, strokes: strokes,
                                     after: after, through: through, badge: badge)
        }.value
        guard let composed, isCurrent(generation, r.captureId), !deps.secureInput() else { return false }
        let shot = ArisGestureShot(badge: r.badge, app: r.hit?.app, title: r.hit?.title, jpeg: composed.jpeg,
                                            thumb: composed.thumb, voicedMsAtCapture: detection?.voicedMs ?? speech.voicedMsNow,
                                            capturedAtMs: through, display: r.screen.id)
        // A shot finished after the release goes to the result that waits for it, not to a session that is gone.
        if generation == self.generation {
            made[r.captureId] = shot
        } else {
            lateShots[r.captureId] = shot
            detections[r.captureId] = nil
        }
        log.notice("gesture capture: shot \(r.badge, privacy: .public): \(composed.jpeg.count, privacy: .public) B, compose \(Int(self.deps.now() - started), privacy: .public) ms")
        return true
    }

    /// The display's clean frame, re-taken when stale or too old; waits at most 1.5 s.
    private func frame(_ display: UInt32, handsFree: Bool, session: Int) async -> CGImage? {
        // The session already finalized and gave its frames up (the release came before this shot began): the shot
        // takes a frame of its own, held nowhere.
        if session != generation {
            let screen = deps.screen
            let task = Task<CGImage?, Never> { await screen.frame(display: display, budget: .gestureFrame, showsCursor: false) }
            return await Self.value(of: task, within: S.shotWaitMs)
        }
        if frames[display].map({ !isFresh($0, handsFree: handsFree) }) ?? true { refresh(display) }
        guard let task = frames[display]?.task else { return nil }
        let image = await Self.value(of: task, within: S.shotWaitMs)
        if image == nil, frames[display]?.task == task { frames[display] = nil } // try again next time
        return image
    }

    /// Whether a shot started under `generation` may still land: its session is the current one, or it was being made
    /// when that session finalized and its result waits for it.
    private func isCurrent(_ generation: Int, _ captureId: Int) -> Bool {
        generation == self.generation || late.contains(captureId)
    }

    private func isFresh(_ frame: Frame, handsFree: Bool) -> Bool {
        !ArisGestureSession.isStale(frameAgeMs: deps.now() - frame.takenAt, handsFree: handsFree, stale: frame.stale)
    }

    private func refresh(_ display: UInt32) {
        let screen = deps.screen
        let task = Task<CGImage?, Never> {
            await screen.frame(display: display, budget: .gestureFrame, showsCursor: false)
        }
        frames[display] = Frame(task: task, takenAt: deps.now())
    }

    /// Drops this session's frames (the finalize task holds its own references until the drawing references are
    /// made), detections and shots, and fences off any work still in flight.
    private func clearSession(cancelFrames: Bool) {
        generation += 1
        if cancelFrames { frames.values.forEach { $0.task.cancel() } }
        frames = [:]
        detections = [:]
        made = [:]
        kept = [:]
        making = [:]
        late = []
        lateShots = [:]
    }

    private static func value<T: Sendable>(of task: Task<T?, Never>, within ms: Double) async -> T? {
        await ArisTaskRace.value(of: task, within: .milliseconds(Int(ms)))
    }
}
