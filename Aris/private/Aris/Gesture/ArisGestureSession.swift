//
//  ArisGestureSession.swift
//  Aris
//
//  The drawing session's rules as a reducer: when it begins, commits, turns hands-free, finalizes or aborts; which
//  circles become a capture and which badge each gets. Plus the two pointer helpers the
//  pump uses before the overlay exists: arming (how far the pointer must travel) and the boot ring (the approach
//  path replayed onto the new panel). Pure, so the tests run it.
//
//  The controller (P1.7/P1.8) runs the effects. Each capture carries a `captureId` (monotonic for the life of this
//  value, across sessions); events whose id isn't the capture in flight are ignored, so a late reply from an old
//  session or a refused capture can't land a shot. For `.startCapture` the controller:
//  1. reads the voiced time (`voicedMsNow`) right away, at detection, before any async work;
//  2. hit-tests and reports `.windowPicked`, then waits for `.proceed` (no `.proceed` → abandon the capture);
//  3. crops, reports `.captureDone`, and stores the shot only on `.keepShot`.
//
//  Notes for the wiring:
//  - P1.8 must build gesture frames with the same exclude filter as the per-turn shot (plan D1/D4): Aris's own
//    windows and private apps' windows are never in a frame. `.refusePrivate` only covers a circle *on* such a window.
//  - With the gesture setting off (`arisCircleGesture`) or no Screen Recording grant, the controller creates no
//    overlay and takes no capture at all; it never starts a session. `gesturesEnabled` is only a backstop.
//

import CoreGraphics
import Foundation

// MARK: - Arming

/// Whether the pointer has travelled far enough since commit to raise the draw surface: 32 pt within the first
/// 700 ms, 12 pt after. When the debounce first ends, drift already ≥ 12 pt re-bases the origin once, so jitter
/// during the press doesn't count. While the button is down the origin follows the pointer, so a drag never arms.
/// Feed it each pointer position read from commit on, at the time it was read (ArisPointerSampler keeps moved
/// positions only, every 4 ms; a pointer that doesn't move can't arm, and the re-base waits for its next move). Positions
/// read before commit never reach it: they only join the approach path (ArisBootRing).
struct ArisArming {
    private typealias C = ArisGestureConstants.Session

    private var origin: CGPoint?
    private var committedAt = 0.0
    private var rebased = false
    /// Stays true once armed; the caller acts on the first true.
    private(set) var armed = false

    mutating func commit(at: Double, origin: CGPoint) {
        self.origin = origin
        committedAt = at
        rebased = false
        armed = false
    }

    mutating func sample(_ p: CGPoint, at: Double, buttonDown: Bool) -> Bool {
        if armed { return true }
        guard let start = origin else { return false }
        if buttonDown { origin = p; return false }
        let inDebounce = at - committedAt < C.armDebounceMs
        var base = start
        if !inDebounce && !rebased {
            rebased = true
            if Self.distance(p, start) >= C.armTravel { base = p; origin = p }
        }
        let needed = inDebounce ? C.armDeliberateTravel : C.armTravel
        guard Self.distance(p, base) >= needed else { return false }
        armed = true
        origin = nil
        return true
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}

// MARK: - Boot ring

/// The last 240 distinct pointer positions before the overlay exists, each tagged with its display. Replayed onto
/// a new panel so the stroke starts where the movement really began. Points are kept as pushed: push them in the
/// tagged display's panel-local space.
struct ArisBootRing {
    private typealias C = ArisGestureConstants.Session

    private struct Sample { let p: CGPoint; let t: Double; let display: UInt32 }
    private var samples: [Sample] = []

    var count: Int { samples.count }

    /// Adds a position unless it equals the last one; the oldest drops past 240.
    mutating func push(_ p: CGPoint, t: Double, display: UInt32) {
        if let last = samples.last, last.p == p, last.display == display { return }
        samples.append(Sample(p: p, t: t, display: display))
        if samples.count > C.bootSampleCap { samples.removeFirst(samples.count - C.bootSampleCap) }
    }

    /// Call on every tick while the mouse button is down: a drag's path is never replayed.
    mutating func clear() { samples.removeAll() }

    /// Newest backwards, oldest first in the result: stops at the first sample older than 800 ms, a gap over 150 ms,
    /// or a sample on another display.
    func replay(now: Double, display: UInt32) -> [ArisGesturePoint] {
        var out: [ArisGesturePoint] = []
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            let s = samples[i]
            if now - s.t > C.bootRecencyMs { break }
            if i + 1 < samples.count, samples[i + 1].t - s.t > C.bootMaxGapMs { break }
            if s.display != display { break }
            out.append(ArisGesturePoint(x: s.p.x, y: s.p.y, t: s.t))
        }
        return out.reversed()
    }
}

// MARK: - Session reducer

struct ArisGestureSession {
    private typealias C = ArisGestureConstants.Session

    enum Phase: Equatable { case idle, provisional, committed, finalizing }

    enum Event {
        case keyDown(Double)
        case held200
        /// Released before Aris's 350 ms tap limit: hands-free listening, so the session commits and goes hands-free.
        case tap
        case release
        case handsFreeEnd
        case cancel
        case frontAppChanged
        case buttonDown
        case buttonUp
        case gesture(ArisGesture, display: UInt32, at: Double)
        /// The hit-test's pick for a capture (Aris only, plan D4): a private app's window is refused.
        case windowPicked(captureId: Int, hit: ArisWindowHit?)
        case captureDone(captureId: Int, ok: Bool)
    }

    enum Effect: Equatable {
        case buildPanels, showHint, startPump, stopAll
        /// Click-through on and the cursor pump on.
        case enterHandsFree
        case startCapture(ArisGesture, display: UInt32, revision: Int, badge: Int, captureId: Int)
        /// The circled window may be captured: go on to the crop.
        case proceed(captureId: Int)
        /// A private app's window (or one whose owner is unknown): no capture; re-ink the loop red with the refusal
        /// capsule (the owner's pick B: "암호 앱은 찍지 않아요", ArisGestureChrome.refusalText). Plan D4. The gesture is nil
        /// when the capture is no longer in flight (nothing left to re-ink).
        case refusePrivate(ArisGesture?, captureId: Int)
        /// Store the shot under this badge.
        case keepShot(badge: Int, captureId: Int)
        /// Discard the capture's image: "failed" (no image) or "finalized" (it landed after release).
        case dropShot(captureId: Int, reason: String)
        /// The 8/8 limit: red re-ink, shake and capsule.
        case reject(ArisGesture)
        /// Nothing visible happens; the reason is for the log.
        case ignore(String)
        case markFramesStale
        case finalize
    }

    /// A kept shot's loop, for the IoU dedup.
    struct Region: Equatable {
        let display: UInt32
        let revision: Int
        let bbox: CGRect
    }

    private struct InFlight {
        let id: Int
        let badge: Int
        let gesture: ArisGesture
        let display: UInt32
        let revision: Int
        let at: Double
    }

    static let maxShots = C.maxShots

    /// Whether the circled window may not be captured: a private app's window, or one whose owner can't be resolved
    /// (fail closed: an unknown app could be a password app). No window at all (empty desktop) is fine.
    static func refuses(_ hit: ArisWindowHit?) -> Bool {
        guard let hit else { return false }
        guard let id = hit.bundleId, !id.isEmpty else { return true }
        return ArisCaptureRules.isPrivate(id)
    }

    /// Whether a display's clean frame must be re-taken before a crop: marked stale (front app changed, hands-free
    /// click), or older than 4000 ms held / 1500 ms hands-free.
    static func isStale(frameAgeMs: Double, handsFree: Bool, stale: Bool) -> Bool {
        stale || frameAgeMs > (handsFree ? C.frameHandsFreeMaxAgeMs : C.frameHeldMaxAgeMs)
    }

    /// The gesture setting (`arisCircleGesture`); off → circles are ignored, ink still draws.
    var gesturesEnabled = true
    /// Windows picked by click this turn (ArisWindowPicker): they count toward the 8-shot cap.
    var otherShots = 0
    private(set) var phase: Phase = .idle
    private(set) var handsFree = false
    /// Not the session's but the pointer's, so it survives a new session.
    private(set) var buttonDown = false
    /// Bumped when the front app changes or a hands-free click lands.
    private(set) var revision = 0
    private(set) var regions: [Int: Region] = [:]
    /// Shot ink starts after this stroke time. Moves only on a kept shot.
    private(set) var inkBoundaryMs = 0.0
    private(set) var beganAtMs = 0.0
    private var inFlight: InFlight?
    /// The last capture id handed out; never reset, so ids stay unique across sessions.
    private var lastCaptureId = 0

    var busy: Bool { inFlight != nil }
    var badges: [Int] { regions.keys.sorted() }

    mutating func handle(_ e: Event) -> [Effect] {
        switch e {
        case .keyDown(let t):
            let abort: [Effect] = isLive ? [.stopAll] : []
            reset(phase: .provisional)
            beganAtMs = t
            return abort + [.buildPanels]
        case .held200:
            guard phase == .provisional else { return [] }
            phase = .committed
            return [.showHint, .startPump]
        case .tap:
            switch phase {
            case .provisional:
                phase = .committed
                handsFree = true
                return [.showHint, .startPump, .enterHandsFree]
            case .committed:
                guard !handsFree else { return [] }
                handsFree = true
                return [.enterHandsFree]
            case .idle, .finalizing:
                return []
            }
        case .release, .handsFreeEnd:
            return end()
        case .cancel:
            guard phase != .idle else { return [] }
            reset(phase: .idle)
            return [.stopAll]
        case .frontAppChanged:
            guard phase == .committed else { return [] }
            revision += 1
            return [.markFramesStale]
        case .buttonDown:
            guard !buttonDown else { return [] }
            buttonDown = true
            guard phase == .committed, handsFree else { return [] }
            revision += 1
            return [.markFramesStale]
        case .buttonUp:
            buttonDown = false
            return []
        case .gesture(let g, let display, let at):
            return gesture(g, display: display, at: at)
        case .windowPicked(let id, let hit):
            let current = inFlight?.id == id ? inFlight : nil
            // Fail closed: a private window is refused whatever state the session is in.
            if Self.refuses(hit) {
                if current != nil { inFlight = nil }
                return [.refusePrivate(current?.gesture, captureId: id)]
            }
            return current == nil ? [] : [.proceed(captureId: id)]
        case .captureDone(let id, let ok):
            guard let shot = inFlight, shot.id == id else { return [] }
            inFlight = nil
            guard ok else { return [.dropShot(captureId: id, reason: "failed")] }
            // After finalize the session is gone, so a late shot isn't kept.
            guard phase == .committed else { return [.dropShot(captureId: id, reason: "finalized")] }
            regions[shot.badge] = Region(display: shot.display, revision: shot.revision, bbox: shot.gesture.bbox)
            inkBoundaryMs = shot.gesture.points.last?.t ?? shot.at
            return [.keepShot(badge: shot.badge, captureId: id)]
        }
    }

    /// A detected gesture, through the guards in order.
    private mutating func gesture(_ g: ArisGesture, display: UInt32, at: Double) -> [Effect] {
        guard phase == .committed else { return [.ignore("not live")] }
        guard gesturesEnabled else { return [.ignore("gestures off")] }
        guard !buttonDown else { return [.ignore("button down")] }
        let overlaps = regions.values.contains {
            $0.display == display && $0.revision == revision && ArisGestureGeometry.iou($0.bbox, g.bbox) >= C.dedupIoU
        }
        guard !overlaps else { return [.ignore("overlap")] }
        guard regions.count + max(0, otherShots) < Self.maxShots else { return [.reject(g)] }
        guard inFlight == nil else { return [.ignore("busy")] }
        let badge = ArisGestureGeometry.nextBadge(Set(regions.keys))
        lastCaptureId += 1
        inFlight = InFlight(id: lastCaptureId, badge: badge, gesture: g, display: display, revision: revision, at: at)
        return [.startCapture(g, display: display, revision: revision, badge: badge, captureId: lastCaptureId)]
    }

    /// Release or hands-free end: a committed session finalizes; one that never committed is discarded.
    private mutating func end() -> [Effect] {
        switch phase {
        case .committed:
            phase = .finalizing
            return [.finalize]
        case .provisional:
            reset(phase: .idle)
            return [.stopAll]
        case .idle, .finalizing:
            return []
        }
    }

    private var isLive: Bool { phase == .provisional || phase == .committed }

    private mutating func reset(phase: Phase) {
        self.phase = phase
        handsFree = false
        revision = 0
        regions = [:]
        inkBoundaryMs = 0
        inFlight = nil
        otherShots = 0
    }
}
