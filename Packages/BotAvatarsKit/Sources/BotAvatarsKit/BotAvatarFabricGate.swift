import Foundation
import QuartzCore

/* An avatar in fabric is not shown until it can be drawn in it: no smooth
   stand-in first and the pile a moment later. It waits for its bake, and
   comes in once its pile is made and no bake is still under way — so a
   screen of them comes in at once — or after SHOW_WITHIN at most, with the
   web's short fade (opacity over 0.3 s, ease-out). A port of the show gate
   in BotAvatar.tsx at bfb396b (`showWhenBaked`, `showReady`, SHOW_WITHIN). */

/// the longest an avatar waits for its material before it is shown anyway
let SHOW_WITHIN = 4.0
/// the web's `transition: opacity 0.3s ease-out`
let SHOW_FADE = 0.3

/// One avatar's wait to be shown. Main thread only.
///
/// It never keeps the shared frame loop running on its own account beyond
/// the fade: a bake landing nudges one redraw of the canvases (enough for a
/// paused avatar to show its new pile), the fade's frames end with the fade
/// whether or not anything drew, and `stop()` (the view disappearing) lets
/// go at once.
final class FabricShowGate {
    enum Phase: Equatable { case waiting, fading(CFTimeInterval), shown }
    private(set) var phase: Phase = .waiting
    private let since = CACurrentMediaTime()
    private var landed: UUID?
    private var fadeFrames = false
    /// whether this avatar's own pile is made
    private let isReady: () -> Bool

    init(isReady: @escaping () -> Bool) {
        self.isReady = isReady
        landed = FabricBakes.onLanded { [weak self] in self?.bakeLanded() }
        DispatchQueue.main.asyncAfter(deadline: .now() + SHOW_WITHIN) { [weak self] in self?.check() }
    }

    deinit {
        if let landed = landed { FabricBakes.stopLanded(landed) }
        stop()
    }

    /// Let go of the frame loop (the view has disappeared).
    func stop() {
        if !fadeFrames { return }
        fadeFrames = false
        BotAvatarClock.shared.unsubscribe(ObjectIdentifier(self))
    }

    /// Shown once ready with no bake under way, or after SHOW_WITHIN.
    func check() {
        guard phase == .waiting else { return }
        if (isReady() && !FabricBakes.pendingAny) || CACurrentMediaTime() - since >= SHOW_WITHIN {
            phase = .fading(CACurrentMediaTime())
            framesForFade()
        }
    }

    /// The avatar's opacity this frame: nil while it waits (draw nothing).
    func opacity(at now: CFTimeInterval = CACurrentMediaTime()) -> Double? {
        check()
        switch phase {
        case .waiting:
            return nil
        case .fading(let start):
            let t = (now - start) / SHOW_FADE
            if t >= 1 {
                phase = .shown
                stop()
                return 1
            }
            return easeOut(max(0, t))
        case .shown:
            return 1
        }
    }

    private func bakeLanded() {
        if phase == .waiting { check() }
        /* one redraw: a paused avatar shows what landed (its own pile, the
           end of a hold); an animating one redraws anyway */
        if phase != .waiting { BotAvatarClock.shared.nudge() }
    }

    /* frames from the shared clock for the fade (an avatar that is not
       animating has none), for the fade's length and no longer */
    private func framesForFade() {
        if !fadeFrames {
            fadeFrames = true
            BotAvatarClock.shared.subscribe(ObjectIdentifier(self)) { _ in }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + SHOW_FADE + 0.05) { [weak self] in self?.stop() }
    }
}

/// CSS `ease-out`: cubic-bezier(0, 0, 0.58, 1).
func easeOut(_ x: Double) -> Double {
    let x1 = 0.0, y1 = 0.0, x2 = 0.58, y2 = 1.0
    func bez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t }
    func dbez(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * (1 - t) * (1 - t) * a + 6 * (1 - t) * t * (b - a) + 3 * t * t * (1 - b) }
    var t = x
    for _ in 0..<8 {
        let d = dbez(t, x1, x2)
        if abs(d) < 1e-6 { break }
        t = min(1, max(0, t - (bez(t, x1, x2) - x) / d))
    }
    return bez(t, y1, y2)
}
