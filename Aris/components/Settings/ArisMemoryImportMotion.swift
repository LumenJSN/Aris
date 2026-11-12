//
//  ArisMemoryImportMotion.swift
//  Aris
//
//  설정 › 기억 › 다른 AI에서 가져오기: how the sheet moves between its steps. The step on screen slides in a few points
//  from the side it comes from and fades in while the one it replaces fades out quicker, and the sheet's height eases
//  from one step's to the next instead of jumping (the curves and distances: ArisMemoryImportPacing). Every moving
//  part is drawn from "seconds since it started", so the app plays it from a clock SwiftUI animates and the offscreen
//  renders draw any frame of it from the same code (ArisImportScrub). Under Reduce Motion nothing moves: it fades.
//

import AppKit
import SwiftUI

extension ArisMemoryImportPacing.Curve {
    /// The same curve as a SwiftUI animation.
    var animation: Animation { .timingCurve(x1, y1, x2, y2, duration: duration) }
}

/// A frozen moment of the sheet's motion, for the offscreen frame strips only: each field is the seconds since that
/// motion started (nil: not playing, drawn at rest). The app never sets it.
struct ArisImportScrub {
    /// The step change: the step it leaves, and how long ago it started.
    var from: ArisMemoryImportBoard.Step?
    var step: Double?
    /// The preview rows rising in.
    var rise: Double?
    /// A tick on the row numbered `tickRow` (its `n`): seconds since the press went down, and when it was let go
    /// (the box changes from the release, as a button does).
    var tickRow: Int?
    var tick: Double?
    var release = 0.1
    /// The list shown scrolled to its end (the last row above the footer).
    var listAtEnd = false
}

private struct ScrubKey: EnvironmentKey { static let defaultValue: ArisImportScrub? = nil }
private struct StandInKey: EnvironmentKey { static let defaultValue: [Int: ArisMemoryImportRowDetail.Extra] = [:] }

extension EnvironmentValues {
    /// Set only by the offscreen renders: the moment of motion to draw.
    var arisImportScrub: ArisImportScrub? {
        get { self[ScrubKey.self] }
        set { self[ScrubKey.self] = newValue }
    }

    /// Set only by the offscreen renders: a row's stored text and replaced wording by its `n`, standing in for what
    /// the agent does not send yet.
    var arisImportStandIn: [Int: ArisMemoryImportRowDetail.Extra] {
        get { self[StandInKey.self] }
        set { self[StandInKey.self] = newValue }
    }
}

/// Whether this change came from a key (Return, Space): such changes are not animated (the animate skill: nothing
/// driven from the keyboard moves).
@MainActor func arisImportKeyDriven() -> Bool { NSApp?.currentEvent?.type == .keyDown }

/// The step on screen and, while a change plays, the one it replaces. `clock` is what SwiftUI animates: it runs from
/// `base` to `base + 1` over the change's whole time (ArisMemoryImportPacing.stepTotal), and everything is drawn from
/// the seconds that gives: the old step fading (leave), the new one arriving 50 ms in (step), the height (resize).
struct ArisImportStage<Page: View>: View, Animatable {
    typealias P = ArisMemoryImportPacing
    var clock: Double
    let base: Double
    let from: ArisMemoryImportBoard.Step?
    let to: ArisMemoryImportBoard.Step
    let forward: Bool
    /// False while the preview rows rise in: they are the entrance, so the page itself only fades (no double motion).
    let slides: Bool
    let reduced: Bool
    /// Seconds since the change started, when a render gives it (overrides the clock).
    var scrubbed: Double?
    @ViewBuilder let page: (ArisMemoryImportBoard.Step) -> Page

    var animatableData: Double {
        get { clock }
        set { clock = newValue }
    }

    private var seconds: Double { scrubbed ?? max(0, clock - base) * P.stepTotal }

    var body: some View {
        let t = seconds
        let arriving = from == nil ? 1 : reduced ? P.reduced.progress(at: t) : P.step.progress(at: t - P.stepDelay)
        let leaving = from == nil ? 1 : (reduced ? P.reduced : P.leave).progress(at: t)
        let height = from == nil || reduced ? 1 : P.resize.progress(at: t)
        let shift = reduced || !slides ? 0 : P.stepShift * (forward ? 1 : -1)
        // Keyed by step, so the page that was on screen keeps its state (its scroll, its field) while it fades.
        let steps = from.map { $0 == to ? [to] : [to, $0] } ?? [to]
        ArisImportBlendHeight(progress: height) {
            ForEach(steps, id: \.self) { step in
                let onScreen = step == to
                page(step)
                    .opacity(onScreen ? arriving : 1 - leaving)
                    .offset(x: onScreen ? shift * (1 - arriving) : 0)
                    .allowsHitTesting(onScreen)
                    .accessibilityHidden(!onScreen)
            }
        }
        // Clip what overflows below while the height eases, never the sides (the slide is horizontal).
        .mask(Rectangle().padding(.horizontal, -24))
    }
}

/// Lays the step on screen and the one it replaces over each other at the top, as tall as one eased toward the other.
struct ArisImportBlendHeight: Layout {
    /// 0: as tall as the step being left; 1: as tall as the step on screen.
    var progress: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 420
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard let to = heights.first else { return .zero }
        let from = heights.count > 1 ? heights[1] : to
        return CGSize(width: width, height: from + (to - from) * min(max(progress, 0), 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// One item of the preview list rising into place: `seconds` since the rise began, `index` its place in the stagger.
struct ArisImportRise: ViewModifier {
    typealias P = ArisMemoryImportPacing
    let seconds: Double?
    let index: Int
    let reduced: Bool

    func body(content: Content) -> some View {
        let progress = seconds.map { reduced ? P.reduced.progress(at: $0) : P.rise.progress(at: $0 - P.riseDelay(index)) } ?? 1
        content
            .opacity(progress)
            .offset(y: reduced ? 0 : P.riseShift * (1 - progress))
    }
}

/// The clock for a motion that can start again: `clock` animates from `base` to `base + 1`; starting again moves the
/// base to where the clock is headed, so a new start never runs the clock backwards.
struct ArisImportClock: Equatable {
    var clock: Double = 0
    var base: Double = -1

    /// Seconds since this motion started, for a curve that lasts `duration` (nil once it is over).
    func seconds(_ duration: Double) -> Double? {
        let progress = clock - base
        return progress >= 1 ? nil : max(0, progress) * duration
    }

    /// Starts it: the base jumps, the clock is animated toward base + 1 by the caller's transaction.
    mutating func start() {
        base = clock.rounded(.up)
        clock = base + 1
    }

    /// Ends it at once (keyboard, Reduce Motion where nothing should move).
    mutating func finish() {
        clock = clock.rounded(.up) + 1
        base = clock - 1
    }
}

/// Hands its content the seconds since a motion started (nil once it is over), from a clock SwiftUI animates.
struct ArisImportTimed<Content: View>: View, Animatable {
    var clock: Double
    let base: Double
    let duration: Double
    @ViewBuilder let content: (Double?) -> Content

    init(_ timer: ArisImportClock, duration: Double, @ViewBuilder content: @escaping (Double?) -> Content) {
        clock = timer.clock
        base = timer.base
        self.duration = duration
        self.content = content
    }

    var animatableData: Double {
        get { clock }
        set { clock = newValue }
    }

    var body: some View { content(clock - base >= 1 ? nil : max(0, clock - base) * duration) }
}
