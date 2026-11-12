//
//  ArisActivityTag.swift
//  Aris
//
//  Aris's activity tags: a 28-point capsule per task the AI took on, in a wrapping row under the answer, its icons
//  on the text grid (the pill 8 in, its icon 16; gap 6). Running, its fill breathes .08 ↔ .13 over 2.2 s and a band
//  of light sweeps across (2.6 s, ease-in-out, resting from 55%); both are SwiftUI animations, not a per-frame clock,
//  and both leave with the running state. Done, it settles to .06 over 240 ms and a 10-point check lands.
//  The icon is Aris's star (A5), or the face of whoever the tag is about (Claude Code's ghost on its notices, N8): it
//  turns now and then while the task runs, still once it's done; there's no status dot. The task's
//  next status relabels its tag in place (the words cross-fade), so the row doesn't fill with one tag per status.
//  Long work says more (ArisTagProgress in ArisTagText.swift, ArisTagMeter below): "2/4" after the words when the
//  work counted its steps, and the time since the tag began once it has run ten seconds. A running tag given a
//  `stop` is pressed to stop its work: under the pointer its face becomes the stop square, and it presses in.
//

import AppKit
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

struct ArisActivityTag: View {
    let label: String
    var done = false
    var failed = false
    /// Already settled when it appears (the follow-up's leaving copy): the check doesn't land again.
    var still = false
    /// Whose task it is when it isn't Aris's own (Claude Code's look on its notices, N8); nil: Aris's face.
    var look: ArisCharacterLook?
    /// When the tag began running (ArisTagTimes, or a job's start): past ten seconds it shows the time since. Nil: no clock.
    var since: Date?
    /// A press on the tag while it runs stops its work; nil for a tag that only shows.
    var stop: ArisTagStop?
    /// Drawn as if the pointer were on it (the off-screen render only).
    var previewHover = false

    /// The ten seconds have passed while the tag was on screen (the clock then eases in).
    @State private var clocked = false
    @State private var hovering = false
    @GestureState private var pressed = false
    /// The press under way has ended (acted on or logged): one that goes without ending is logged as taken away.
    @State private var pressEnded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Re-draws this view when the hidden look changes (ArisSiriLookGate).
    @ObservedObject private var siriLook = ArisSiriLookGate.shared

    /// Fills: running, breathing up to, done.
    static let fill = 0.08
    static let breathFill = 0.13
    static let doneFill = 0.06
    /// Running → done: background and colours over 240 ms, CSS `ease`.
    static let settle = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.24)
    /// A tag's new words (same task, next status): 220 ms on a strong ease-out (0.23, 1, 0.32, 1), the width with them.
    static let relabel = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)
    /// A tag's entrance: 220 ms (0.16, 1, 0.3, 1) from 4 points up at 98.5%.
    static let entry: AnyTransition = .opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.985))
        .animation(.timingCurve(0.16, 1, 0.3, 1, duration: 0.22))
    static let height: CGFloat = 28
    static let gap: CGFloat = 6
    /// The pill's own inset before its icon.
    static let leading: CGFloat = 8
    /// A tag row's inset from the notch's content edge: the pill starts early enough that its icon, not its edge, sits
    /// on the text line under the first letter of your words (the owner's pick, 2026-11-10).
    static let rowInset = ArisGlass.textInset - leading

    /// 11.5 points at weight 560 on SF's variation axis (Hangul falls back to Apple SD Gothic Neo and snaps to a
    /// named face).
    private static let labelFont = Font(ArisFont.system(11.5, weight: 560) as CTFont)
    /// −0.01em at 11.5 points.
    private static let tracking: CGFloat = -0.115
    private static let failedTint = Color(red: 1, green: 0.45, blue: 0.4)

    private var settled: Bool { done || failed }
    /// Running, Aris's own task, in the siri look: drawn as Siri's capsule (its glass, its dots, no breathing or sweep).
    private var siriWorking: Bool { ArisSiriLookNow.on && !settled && look == nil }
    private var pressable: Bool { stop != nil && !settled }
    /// The stop square shows in the face's place.
    private var offersStop: Bool { pressable && (hovering || previewHover) }
    /// The label's words and its count ("… · 2/4"); a settled tag shows the words alone.
    private var status: (words: String, count: ArisTagCount?) { ArisTagProgress.split(label) }
    /// Past ten seconds, whether the tag was on screen as they passed or came into view later.
    private var showsClock: Bool { !settled && (clocked || ArisTagProgress.clock(since: since, now: Date()) != nil) }
    private var words: String { showsClock ? ArisTagProgress.withoutMinutes(status.words) : status.words }

    var body: some View {
        HStack(spacing: Self.gap) {
            ZStack {
                if siriWorking {
                    // The siri look: Siri's ring of dots is the work's mark (its small capsule with moving dots and a word).
                    ArisSiriLookDots(size: 11).frame(width: 14, height: 14).opacity(offersStop ? 0 : 1)
                } else {
                    ArisCharacterView(look: look ?? .star, state: settled ? "default" : "working", size: 14, isAris: look == nil)
                        .opacity(offersStop ? 0 : settled ? 0.72 : 1)
                }
                ArisTagStopMark().opacity(offersStop ? 1 : 0)
            }
            .animation(ArisTagMeterLook.hover, value: offersStop)
            HStack(spacing: 0) {
                Text(ArisTagText.oneLine(words))
                    .font(Self.labelFont)
                    .tracking(Self.tracking)
                    .foregroundStyle(.white.opacity(settled ? 0.5 : 0.74))
                    // One line, cut at the end where the row runs out: a long status never widens the notch's column.
                    .lineLimit(1)
                    .truncationMode(.tail)
                    // A new status for the same task: the words blur across in place while the pill eases to its width.
                    .contentTransition(.interpolate)
                if !settled {
                    // The numbers are never cut: the words give way first.
                    ArisTagMeter(count: status.count, since: since, clocked: showsClock, font: Self.labelFont)
                        .layoutPriority(1)
                }
            }
            .arisTextBacking()
            if failed {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Self.failedTint)
                    .frame(width: 10, height: 10)
                    .padding(.leading, -2)
            } else if done {
                ArisTagCheck(landed: still)
            }
        }
        .foregroundStyle(.white.opacity(settled ? 0.56 : 0.78))
        .padding(.leading, Self.leading)
        .padding(.trailing, 11)
        .frame(height: Self.height)
        .background {
            Capsule().fill(.white.opacity(settled ? Self.doneFill : siriWorking ? 0 : Self.fill))
                .overlay {
                    if siriWorking {
                        ArisSiriLookGlass(shape: Capsule())
                    } else if !settled {
                        ArisTagBreath()
                        ArisTagSheen()
                    }
                }
                .clipShape(Capsule())
        }
        // Its own width up to the room it's offered, never past it (a fixed width pushed the whole column off-centre).
        .fixedSize(horizontal: false, vertical: true)
        .animation(Self.settle, value: settled)
        .animation(Self.relabel, value: label)
        .overlay(Capsule().fill(.white.opacity(lift)).allowsHitTesting(false))
        .scaleEffect(pressed && pressable && !reduceMotion ? 0.97 : 1)
        .animation(ArisTagMeterLook.press, value: pressed)
        .animation(ArisTagMeterLook.hover, value: offersStop)
        .contentShape(Capsule())
        // The pointer and the press are taken by one still piece over the tag: nothing in it changes as the clock under
        // it ticks, and no system tooltip sits on it. (The second VM run: with a system tooltip over the tag its hover
        // never arrived, so the stop mark never showed, and a press once the tooltip was up was lost.) It lets go when
        // the pointer leaves the notch, however it leaves (ArisNotchHovered).
        .overlay {
            if pressable {
                // The tag's frame is read when the press ends (ArisTagPress), never from an earlier layout.
                GeometryReader { geometry in
                    Color.clear.contentShape(Capsule())
                        .arisNotchHover($hovering)
                        .gesture(press(in: geometry.size))
                }
                .onDisappear { hovering = false }
            }
        }
        // A press that went down and never ended (the gesture was taken away) is said in the log, once.
        .onChange(of: pressed) { was, now in
            guard was, !now else { return }
            DispatchQueue.main.async {
                if !pressEnded { log.notice("\(ArisTagPress.logLine(ArisTagPress.takenAway), privacy: .public)") }
                pressEnded = false
            }
        }
        // What the press does, in the notch's own tip above the tag, a moment after the stop mark.
        .overlay(alignment: .topLeading) {
            if pressable, let stop {
                ArisHoverTip(text: stop.help)
                    .scaleEffect(offersStop ? 1 : 0.98, anchor: .bottomLeading)
                    .opacity(offersStop ? 1 : 0)
                    .animation(ArisHoverTip.motion.delay(offersStop ? ArisTagMeterLook.tipWait : 0), value: offersStop)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    // Its bottom edge `tipGap` above the tag's top: it rises from a frame of no height on the tag's top edge.
                    .frame(height: 0, alignment: .bottom)
                    .offset(y: -ArisTagMeterLook.tipGap)
            }
        }
        .accessibilityHint(pressable ? stop?.help ?? "" : "")
        .accessibilityAddTraits(pressable ? .isButton : [])
        .accessibilityAction { if pressable { stop?.action() } }
        .task(id: [since?.timeIntervalSinceReferenceDate ?? -1, settled ? 1 : 0]) { await startClock() }
    }

    /// White over the capsule under the pointer, more while held; none on a tag that can't be pressed.
    private var lift: Double {
        !pressable ? 0 : pressed ? ArisTagMeterLook.pressFill : offersStop ? ArisTagMeterLook.hoverFill : 0
    }

    /// Held from the mouse going down; let go anywhere inside the tag as it is then (`size`), its work stops. A press
    /// that does nothing writes one line with the reason (ArisTagPress).
    private func press(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressed) { _, held, _ in held = true }
            .onEnded { value in
                pressEnded = true
                switch ArisTagPress.ended(at: value.location, in: size, pressable: pressable) {
                case .stop: stop?.action()
                case .ignored(let reason): log.notice("\(ArisTagPress.logLine(reason), privacy: .public)")
                }
            }
    }

    /// Waits out what is left of the ten seconds, then eases the clock in (the tag grows once, on the relabel curve).
    private func startClock() async {
        clocked = false
        guard let since, !settled else { return }
        let wait = ArisTagProgress.untilClock(since: since, now: Date())
        guard wait > 0 else { return }
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled else { return }
        withAnimation(Self.relabel) { clocked = true }
    }
}

/// The breathing half of the running fill: a layer that takes .08 to .13 and back, 1.1 s each way (a 2.2 s
/// breath, ease-in-out). Gone with the running state, and its animation with it.
private struct ArisTagBreath: View {
    /// Over white .08, this much more white makes .13.
    private static let layer = (ArisActivityTag.breathFill - ArisActivityTag.fill) / (1 - ArisActivityTag.fill)

    @State private var high = false

    var body: some View {
        Capsule()
            .fill(.white.opacity(Self.layer))
            .opacity(high ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { high = true }
            }
    }
}

/// A band of light 55% of the tag wide, from 180% left of it to 420% right over the first 55% of each 2.6 s (CSS
/// ease-in-out), then resting off the edge.
private struct ArisTagSheen: View {
    private static let period = 2.6
    private static let sweep = 0.55

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * 0.55
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .white.opacity(0.13), location: 0.5),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
            .keyframeAnimator(initialValue: CGFloat(-1.8), repeating: true) { band, x in
                band.offset(x: width * x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(CGFloat(4.2), duration: Self.period * Self.sweep, timingCurve: .easeInOut)
                    LinearKeyframe(CGFloat(4.2), duration: Self.period * (1 - Self.sweep))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The done check: 10 points at .58. It lands over 460 ms (0.34, 1.56, 0.64, 1), its width 0 → 10 (the pill grows to
/// make room, overshooting a little) as it blurs 5 → 0 into focus.
private struct ArisTagCheck: View {
    @State private var landed: Bool

    init(landed: Bool) { _landed = State(initialValue: landed) }

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.58))
            .frame(width: 10, height: 10)
            .frame(width: landed ? 10 : 0, alignment: .leading)
            // Its margin goes −6 → −2 against the 6-point gap.
            .padding(.leading, landed ? -2 : -6)
            .blur(radius: landed ? 0 : 5)
            .opacity(landed ? 1 : 0)
            .onAppear {
                guard !landed else { return }
                withAnimation(.timingCurve(0.34, 1.56, 0.64, 1, duration: 0.46)) { landed = true }
            }
    }
}

// MARK: - Long work (ArisTagProgress): the numbers after a running tag's words, and the stop mark
//
// "2/4" when the work counted its steps, and the time since it began once that is past ten seconds: tabular digits in
// the tag's own type at a quieter tone, so the tag's width holds still while they count; the digits change in place,
// with no fade and nothing that blinks. Under the pointer the face of a tag that can be pressed gives way to the
// header's stop square (8 points, 1.6 round), so the press that stops the work is found by looking; the tag lifts a
// little there and presses in to 97%, and after a moment the notch's own tip (ArisHoverTip) says what the press does.

/// What a press on a running tag does, and the tip that says so.
struct ArisTagStop {
    let help: String
    let action: () -> Void
}

enum ArisTagMeterLook {
    /// Between the words and a number, and between two numbers.
    static let gap: CGFloat = 5
    /// The numbers sit back from the words (.74 while running).
    static let tone = 0.5
    /// The pointer over a tag that can be pressed, and the press: white added over the tag's fill.
    static let hoverFill = 0.06
    static let pressFill = 0.12
    /// The face ↔ stop mark, and the fill under the pointer: 140 ms ease-out, as the header's stop button.
    static let hover = Animation.easeOut(duration: 0.14)
    /// The press, in to 97% and back: the settings' press curve (ArisPressStyle).
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)
    /// The stop square, the header button's (ArisStopButton).
    static let stopSide: CGFloat = 8
    static let stopRadius: CGFloat = 1.6
    /// The tip that says what a press does: above the tag by this much, after the pointer has rested this long.
    static let tipGap: CGFloat = 5
    static let tipWait = 0.6
}

/// "2/4" and the clock, each `gap` after what is before it. Nothing at all (and no width) while neither shows.
struct ArisTagMeter: View {
    let count: ArisTagCount?
    /// When the tag began running; the clock shows only once `clocked`.
    let since: Date?
    let clocked: Bool
    let font: Font

    var body: some View {
        HStack(spacing: 0) {
            if let count {
                number(count.text)
                    .contentTransition(.numericText())
                    .transition(.opacity)
            }
            if clocked, let since {
                // One redraw a second, and only once the clock is up.
                TimelineView(.periodic(from: since, by: 1)) { context in
                    number(ArisTagProgress.elapsed(context.date.timeIntervalSince(since)))
                }
                .transition(.opacity)
            }
        }
    }

    private func number(_ text: String) -> some View {
        Text(verbatim: text)
            .font(font.monospacedDigit())
            .foregroundStyle(.white.opacity(ArisTagMeterLook.tone))
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, ArisTagMeterLook.gap)
    }
}

/// The stop square that takes the face's place under the pointer.
struct ArisTagStopMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ArisTagMeterLook.stopRadius, style: .continuous)
            .fill(.white.opacity(0.9))
            .frame(width: ArisTagMeterLook.stopSide, height: ArisTagMeterLook.stopSide)
    }
}

/// The turn's footer: its tags in a wrapping row on the text grid, below the answer. Pointer events pass through them,
/// but for the running one when it can be pressed to stop the turn.
struct ArisActivityFooter: View {
    let tags: [ArisStep]
    var still = false
    /// When each running tag began (ArisTagTimes), by its id.
    var times: [Int: Date] = [:]
    /// Stops the turn (a press on its running tag); nil for a footer that only shows.
    var stop: ArisTagStop?

    var body: some View {
        ArisFlowRow(spacing: ArisActivityTag.gap) {
            // By the tag's place, not its label: a relabelled tag (보는 중 → 쓰는 중) stays and cross-fades its words.
            ForEach(tags) { tag in
                ArisActivityTag(label: tag.label, done: tag.done, failed: tag.failed, still: still, since: tag.done ? nil : times[tag.id],
                                stop: tag.done ? nil : stop)
                    .allowsHitTesting(!tag.done && stop != nil)
                    .transition(ArisActivityTag.entry)
            }
        }
        .padding(.horizontal, ArisActivityTag.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row that wraps (ArisFlowLines), lines `spacing` apart as well.
struct ArisFlowRow: Layout {
    var spacing: CGFloat

    /// Each view at its own size, but never wider than the row: a wider one is offered the row's width (and cuts).
    private func sizes(_ subviews: Subviews, limit: CGFloat) -> [CGSize] {
        subviews.map { subview in
            let own = subview.sizeThatFits(.unspecified)
            return own.width > limit ? subview.sizeThatFits(ProposedViewSize(width: limit, height: nil)) : own
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(subviews, limit: proposal.width ?? .infinity)
        let lines = ArisFlowLines.lines(widths: sizes.map(\.width), limit: proposal.width ?? .infinity, spacing: spacing)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for line in lines {
            let lineSizes = sizes[line]
            let gaps = spacing * CGFloat(lineSizes.count - 1)
            width = max(width, lineSizes.reduce(0) { $0 + $1.width } + gaps)
            height += lineSizes.reduce(0) { max($0, $1.height) }
        }
        height += spacing * CGFloat(max(0, lines.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(subviews, limit: bounds.width)
        var y = bounds.minY
        for line in ArisFlowLines.lines(widths: sizes.map(\.width), limit: bounds.width, spacing: spacing) {
            var x = bounds.minX
            let lineHeight = sizes[line].reduce(0) { max($0, $1.height) }
            for index in line {
                subviews[index].place(at: CGPoint(x: x, y: y + (lineHeight - sizes[index].height) / 2), proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += lineHeight + spacing
        }
    }
}
