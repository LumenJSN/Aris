//
//  ArisDictationPillView.swift
//  Aris
//
//  The pill in its window (ArisDictationPillPanel): anchored 6 above the window's bottom, centred, growing upward,
//  its tooltip 4 above it. What it shows comes from ArisDictationPillCenter as one ArisDictationPillDisplay; the sizes,
//  looks and timing are ArisDictationPillRules', the pieces ArisDictationPillParts'. As the reference pill does, it is
//  one body whose size, corners, fill and line all move together, 0.1 s on cubic-bezier(0.05, 0.6, 0.4, 0.95) (a
//  reversal mid-way only as long as the share covered), and it shows and hides by opacity alone, 0.1 s ease. The size
//  is animated as one value (ArisDictationPillSizing), so the outline, the content's frame and its clip move together
//  and nothing shows outside the pill while it changes. With Reduce Motion sizes change at once and only the content
//  fades; the bars keep the voice but not the wave, and the spinner holds still.
//

import AppKit
import SwiftUI

/// What the pill draws now.
struct ArisDictationPillDisplay: Equatable {
    var phase: ArisDictationPillPhase = .hidden
    /// The last state shown: drawn while the pill fades out, so it leaves at the size it had.
    var drawn: ArisDictationPillPhase = .idle
    /// Changes per dictation, so the level starts over each time.
    var dictation = 0
    /// The hover's tooltip: before the key, the key, after it.
    var hint = ArisDictationPillWords.hint(english: false)
    /// Hands-free under the pointer: how to finish with the key.
    var finishHint = ArisDictationPillWords.finishHint(english: false)
    var english = false
    /// The recovered words were just copied again (the card's label says so for 1.2 s).
    var copiedAgain = false
    /// The system is in light mode: the recovered words' card takes its light colours (the pill stays dark).
    var light = false
    /// The pointer is on the pill (the hands-free row's tooltips).
    var pointerOn = false
    /// How long the size's move into this phase takes (ArisDictationPillRules.Reversal).
    var sizeDuration = ArisDictationPillRules.sizeDuration

    /// What the pointer counts on: the pill, or the recovered words' card.
    var size: CGSize { ArisDictationPillRules.size(phase, english: english, again: copiedAgain) }
}

/// What the pill's controls do.
struct ArisDictationPillActions {
    var start: () -> Void = {}
    var cancel: () -> Void = {}
    var finish: () -> Void = {}
    var copyAgain: () -> Void = {}
    var closeRecovered: () -> Void = {}
}

/// The pill's own words.
enum ArisDictationPillWords {
    static func hint(english: Bool, key: String? = nil) -> (before: String, key: String, after: String) {
        let cap = key ?? (english ? "right ⌥" : "오른쪽 ⌥")
        return english ? ("Click or hold", cap, "to dictate") : ("클릭하거나", cap, "길게 눌러 받아쓰기")
    }

    static func finishHint(english: Bool, key: String? = nil) -> (before: String, key: String, after: String) {
        let cap = key ?? (english ? "right ⌥" : "오른쪽 ⌥")
        return english ? ("Press", cap, "to finish and put it in") : ("", cap, "눌러 끝내고 넣기")
    }

    static func cancel(_ english: Bool) -> String { english ? "Cancel" : "취소" }
    static func finish(_ english: Bool) -> String { english ? "Finish and put it in" : "끝내고 넣기" }
    static func close(_ english: Bool) -> String { english ? "Close" : "닫기" }
}

extension ArisDictationPillDisplay {
    static func == (a: Self, b: Self) -> Bool {
        a.phase == b.phase && a.drawn == b.drawn && a.dictation == b.dictation && a.hint == b.hint && a.finishHint == b.finishHint
            && a.english == b.english && a.copiedAgain == b.copiedAgain && a.light == b.light && a.pointerOn == b.pointerOn
            && a.sizeDuration == b.sizeDuration
    }
}

/// Which tooltip shows over the pill.
enum ArisDictationPillTip: Equatable {
    /// The hover: how to dictate (after 150 ms).
    case dictate
    /// Hands-free under the pointer: how to finish with the key (after 150 ms).
    case finish
    /// Over ✕ or ■ (after 50 ms).
    case cancel, stop

    var delay: Double { self == .cancel || self == .stop ? ArisDictationPillRules.buttonHintDelay : ArisDictationPillRules.hintDelay }
}

struct ArisDictationPillView: View {
    let display: ArisDictationPillDisplay
    @ObservedObject var audio: ArisAudioLevel
    /// The level's state across redraws (the center's, or a render's own).
    let level: ArisDictationPillLevel
    var actions = ArisDictationPillActions()
    var blending: NSVisualEffectView.BlendingMode? = .behindWindow
    /// Offscreen renders: fixed bar heights and spinner time.
    var barsPreset: [CGFloat]?
    var spinnerPreset: Double?
    var recoveredHover: ArisDictationPillRecoveredHover?
    /// Offscreen renders: the recovered words' card drawn already open.
    var recoveredStill = false
    /// Offscreen renders: the size as drawn at one instant of a move (the motion's keyframes); nil: the phase's.
    var sizePreset: CGSize?
    /// Offscreen renders: the look drawn at that instant (the colours move with the size); nil: the phase's.
    var lookPreset: ArisDictationPillLookBlend?
    /// Offscreen renders: a tooltip shown at once; nil: as the pointer has it.
    var tipPreset: ArisDictationPillTip?
    /// Offscreen renders of a move's first 100 ms: no tooltip (it waits 150 ms).
    var tipsShown = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var buttonHovered: ArisDictationPillTip?

    private typealias R = ArisDictationPillRules

    private var shown: Bool { display.phase.shown }
    private var phase: ArisDictationPillPhase { shown ? display.phase : display.drawn }
    /// The pill's own size; while the recovered words' card shows, the pill under it is the (hidden) sliver.
    private var size: CGSize { showsCard ? R.idleSize : R.size(phase) }
    /// The recovered words' card stands in the pill's place (shown, or the last thing shown while it all fades).
    private var showsCard: Bool { if case .recovered = phase { true } else { false } }
    /// The words of the card showing now.
    private var recovered: String? { if case .recovered(let text) = display.phase { text } else { nil } }
    private var kind: ArisDictationPillLookKind { lookPreset?.to ?? R.look(phase) }

    private static func curve(_ c: ArisDictationPillCurve, _ duration: Double) -> Animation {
        .timingCurve(c.x1, c.y1, c.x2, c.y2, duration: duration)
    }

    /// The size's (and the colours') move into this phase.
    private var sizeAnimation: Animation { Self.curve(R.sizeCurve, display.sizeDuration) }
    private var showAnimation: Animation { Self.curve(R.showCurve, R.showDuration) }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            tooltips
            pill
        }
        .padding(.bottom, R.bottomPadding)
        .frame(width: R.windowSize.width, height: R.windowSize.height, alignment: .bottom)
        .environment(\.colorScheme, .dark)
        // A row that goes away under the pointer never says its button was left.
        .onChange(of: display.phase) { buttonHovered = nil }
    }

    // MARK: - Tooltips

    private var tip: ArisDictationPillTip? {
        if let tipPreset { return tipPreset }
        guard shown, tipsShown else { return nil }
        switch display.phase {
        case .hover: return .dictate
        case .recording(handsFree: true): return buttonHovered ?? (display.pointerOn ? .finish : nil)
        default: return nil
        }
    }

    /// Each tooltip over its spot: shown after its delay with a 120 ms ease, gone at once.
    private var tooltips: some View {
        ZStack(alignment: .bottom) {
            tooltip(.dictate, ArisDictationPillTooltip(before: display.hint.before, key: display.hint.key, after: display.hint.after))
            tooltip(.finish, ArisDictationPillTooltip(before: display.finishHint.before, key: display.finishHint.key,
                                                      after: display.finishHint.after))
            tooltip(.cancel, ArisDictationPillTooltip(before: ArisDictationPillWords.cancel(display.english)))
                .offset(x: -Self.buttonOffset, y: -(R.buttonHintGap - R.hintGap))
            tooltip(.stop, ArisDictationPillTooltip(before: ArisDictationPillWords.finish(display.english)))
                .offset(x: Self.buttonOffset, y: -(R.buttonHintGap - R.hintGap))
        }
        .padding(.bottom, R.hintGap)
    }

    /// A button's centre from the pill's: half the hands-free pill, less its inset and half the button.
    static var buttonOffset: CGFloat {
        let row = ArisDictationPillButton.size * 2 + ArisDictationPillWave.width + 2 * handsFreeGap
        return row / 2 - ArisDictationPillButton.size / 2
    }

    private func tooltip(_ which: ArisDictationPillTip, _ view: ArisDictationPillTooltip) -> some View {
        let on = tip == which
        return view
            .opacity(on ? 1 : 0)
            .animation(on && tipPreset == nil ? Self.curve(.ease, R.hintFade).delay(which.delay) : nil, value: on)
    }

    // MARK: - The pill

    private var pill: some View {
        ZStack(alignment: .bottom) {
            basePill
                .opacity(showsCard ? 0 : 1)
            if let recovered {
                ArisDictationPillRecoveredCard(text: recovered, english: display.english, again: display.copiedAgain, light: display.light,
                                               blending: blending, copy: actions.copyAgain, close: actions.closeRecovered,
                                               hover: recoveredHover, still: recoveredStill)
                    .id("recovered-\(display.dictation)")
                    // It grows in by itself; it leaves with a fade and a small shrink (only the fade with Reduce Motion).
                    .transition(.asymmetric(insertion: .identity,
                                            removal: reduceMotion ? .opacity
                                                : .opacity.combined(with: .scale(scale: ArisDictationPillRecoveredLayout.leaveScale, anchor: .bottom))))
            }
        }
        .animation(.easeOut(duration: ArisDictationPillRecoveredLayout.leaveDuration), value: recovered == nil)
        // Showing and hiding: opacity alone (no scale, so Reduce Motion is the same).
        .opacity(shown ? 1 : 0)
        .animation(showAnimation, value: shown)
    }

    /// The pill itself (the recovered words' card stands over it), drawn at the size as it moves: the body, the
    /// content's frame and the clip are all that one size, so a content that comes in mid-change grows with the pill.
    private var basePill: some View {
        ArisDictationPillSizing(size: sizePreset ?? size) { current in
            ZStack {
                ArisDictationPillBody(size: current, kind: kind, blend: lookPreset)
                content
                    .frame(width: current.width, height: current.height)
                    .id(contentKey)
                    .transition(.opacity)
            }
            .frame(width: current.width, height: current.height)
            .clipShape(ArisDictationPillOutline())
        }
        .contentShape(ArisDictationPillOutline())
        .onTapGesture { tapped() }
        // Reduce Motion: the size (and colours) change at once; the content fades in the same 0.1 s.
        .animation(reduceMotion ? nil : sizeAnimation, value: size)
        .animation(reduceMotion ? nil : sizeAnimation, value: kind)
        .animation(reduceMotion ? .easeOut(duration: R.reducedFade) : sizeAnimation, value: contentKey)
    }

    /// A click on the sliver or its hover starts hands-free; on the held recording it finishes.
    private func tapped() {
        switch phase {
        case .idle, .hover: actions.start()
        case .recording(handsFree: false): actions.finish()
        default: break
        }
    }

    /// Content swaps fade with the size's move. The sliver and its hover are one content (the mic is there or not, and
    /// the growing clip reveals it), so growing under the pointer never crossfades two layouts.
    private var contentKey: String {
        switch phase {
        case .hidden, .idle, .hover: "rest"
        case .recording(let handsFree): handsFree ? "free" : "hold"
        case .transcribing: "writing-\(display.dictation)"
        case .recovered: "recovered-\(display.dictation)"
        case .error(let line): "error-\(line)"
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .hidden, .idle, .hover:
            ArisDictationPillGlyphs.mic.opacity(phase == .hover ? 1 : 0)
        case .recording(let handsFree):
            if handsFree { handsFreeRow } else { bars(.live) }
        case .transcribing:
            HStack(spacing: Self.writingGap) {
                bars(.still)
                ArisDictationPillSpinnerView(preset: spinnerPreset)
            }
        case .error(let line):
            Text(line)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, R.errorPadding / 2)
        case .recovered:
            // The card (ArisDictationPillRecoveredCard) shows instead.
            Color.clear
        }
    }

    /// The writing row: the still level, 6, the spinner (states.css:158).
    static let writingGap: CGFloat = 6
    /// The hands-free row: ✕, 4, the level, 4, ■ (states.css:107).
    static let handsFreeGap: CGFloat = 4

    private func bars(_ mode: ArisDictationPillBarsMode) -> some View {
        ArisDictationPillBarsView(audio: audio, level: level, mode: mode, preset: mode == .live ? barsPreset : nil)
    }

    private var handsFreeRow: some View {
        HStack(spacing: Self.handsFreeGap) {
            ArisDictationPillButton(glyph: .cancel, label: ArisDictationPillWords.cancel(display.english), action: actions.cancel,
                                    hovered: { buttonHovered = $0 ? .cancel : (buttonHovered == .cancel ? nil : buttonHovered) })
            bars(.live)
            ArisDictationPillButton(glyph: .stop, label: ArisDictationPillWords.finish(display.english), action: actions.finish,
                                    hovered: { buttonHovered = $0 ? .stop : (buttonHovered == .stop ? nil : buttonHovered) })
        }
    }
}

/// The pill's content at its size as it moves: SwiftUI animates `size` as one value and draws the content at each step,
/// so the outline, the content and its clip never part (a content swapped in mid-change is laid out at the size then,
/// not at the end size outside the pill).
struct ArisDictationPillSizing<Content: View>: View, Animatable {
    var size: CGSize
    @ViewBuilder let content: (CGSize) -> Content

    var animatableData: CGSize.AnimatableData {
        get { size.animatableData }
        set { size.animatableData = newValue }
    }

    var body: some View { content(size) }
}
