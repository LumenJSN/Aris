//
//  ArisDictationPillView.swift
//  Aris
//
//  The pill in its window (ArisDictationPillPanel): anchored 6 above the window's bottom, centred, growing upward,
//  the hover hint 6 above it. What it shows comes from ArisDictationPillCenter as one ArisDictationPillDisplay; the
//  sizes and timing are ArisDictationPillRules', the marks ArisDictationPillParts'. Show/hide is opacity + scale from 0.8
//  (0.15 s ease) and every size change 0.15 s ease; with Reduce Motion it only fades (no scale, sizes change at once).
//

import AppKit
import SwiftUI

/// What the pill draws now.
struct ArisDictationPillDisplay: Equatable {
    var phase: ArisDictationPillPhase = .hidden
    /// The last state shown: drawn while the pill fades out, so it leaves at the size it had.
    var drawn: ArisDictationPillPhase = .idle
    /// The app being typed into (the held recording shows it).
    var appIcon: NSImage?
    /// Started with a click on the pill: ✕ and ↑ (hands-free by the key: ✕ and the lock).
    var fromPill = false
    /// How long the recording was, for the ring's pace.
    var recordingSeconds = 0.0
    /// Changes per dictation, so the ring starts empty each time.
    var dictation = 0
    /// The hover hint: before the key, the key, after it.
    var hint = ArisDictationPillWords.hint(english: false)
    var english = false
    /// The recovered words were just copied again (the card's label says so for 1.2 s).
    var copiedAgain = false
    /// The system is in light mode: the recovered words' card takes its light colours (the pill stays dark).
    var light = false

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

    static func cancel(_ english: Bool) -> String { english ? "Cancel" : "취소" }
    static func finish(_ english: Bool) -> String { english ? "Finish and put it in" : "끝내고 넣기" }
    static func close(_ english: Bool) -> String { english ? "Close" : "닫기" }
}

extension ArisDictationPillDisplay {
    static func == (a: Self, b: Self) -> Bool {
        a.phase == b.phase && a.drawn == b.drawn && a.appIcon === b.appIcon && a.fromPill == b.fromPill
            && a.recordingSeconds == b.recordingSeconds && a.dictation == b.dictation
            && a.hint == b.hint && a.english == b.english && a.copiedAgain == b.copiedAgain && a.light == b.light
    }
}

struct ArisDictationPillView: View {
    let display: ArisDictationPillDisplay
    @ObservedObject var audio: ArisAudioLevel
    var actions = ArisDictationPillActions()
    var blending: NSVisualEffectView.BlendingMode? = .behindWindow
    /// Offscreen renders: fixed bar heights and ring share.
    var barsPreset: [CGFloat]?
    var ringPreset: Double?
    var recoveredHover: ArisDictationPillRecoveredHover?
    /// Offscreen renders: the recovered words' card drawn already open.
    var recoveredStill = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Bool { display.phase.shown }
    private var phase: ArisDictationPillPhase { shown ? display.phase : display.drawn }
    /// The pill's own size; while the recovered words' card shows, the pill under it is the (hidden) sliver.
    private var size: CGSize { showsCard ? ArisDictationPillRules.idleSize : ArisDictationPillRules.size(phase) }
    /// The recovered words' card stands in the pill's place (shown, or the last thing shown while it all fades).
    private var showsCard: Bool { if case .recovered = phase { true } else { false } }
    /// The words of the card showing now.
    private var recovered: String? { if case .recovered(let text) = display.phase { text } else { nil } }

    private var ease: Animation {
        let e = ArisDictationPillRules.ease
        return .timingCurve(e.0, e.1, e.2, e.3, duration: ArisDictationPillRules.sizeDuration)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ArisDictationPillHint(before: display.hint.before, key: display.hint.key, after: display.hint.after)
                .opacity(display.phase == .hover ? 1 : 0)
                .scaleEffect(display.phase == .hover || reduceMotion ? 1 : 0.95, anchor: .bottom)
                .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2), value: display.phase == .hover)
                .padding(.bottom, 6)
            pill
        }
        .padding(.bottom, ArisDictationPillRules.bottomPadding)
        .frame(width: ArisDictationPillRules.windowSize.width, height: ArisDictationPillRules.windowSize.height, alignment: .bottom)
        .environment(\.colorScheme, .dark)
    }

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
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || reduceMotion ? 1 : ArisDictationPillRules.hiddenScale, anchor: .center)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: ArisDictationPillRules.showDuration), value: shown)
    }

    /// The pill itself (the recovered words' card stands over it).
    private var basePill: some View {
        ZStack {
            ArisDictationPillShell(size: size, gradientBorder: ArisDictationPillRules.gradientBorder(phase), blending: blending)
            content
                .frame(width: size.width, height: size.height)
                .clipShape(ArisDictationPillShape(size: size))
                .id(contentKey)
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(ArisDictationPillShape(size: size))
        .onTapGesture { if phase == .idle || phase == .hover { actions.start() } }
        .animation(reduceMotion ? nil : ease, value: size)
        .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: ArisDictationPillRules.sizeDuration), value: contentKey)
    }

    /// Content swaps fade (the size, below, eases).
    private var contentKey: String {
        switch phase {
        case .hidden, .idle: "idle"
        case .hover: "hover"
        case .recording(let handsFree): handsFree ? "free" : "hold"
        case .transcribing: "ring-\(display.dictation)"
        case .recovered: "recovered-\(display.dictation)"
        case .error(let line): "error-\(line)"
        }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .hidden, .idle:
            Color.clear
        case .hover:
            Image(systemName: "mic.fill")
                .resizable().scaledToFit()
                .frame(width: 16, height: 13)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 6)
        case .recording(let handsFree):
            if handsFree { handsFreeRow } else { holdRow }
        case .transcribing(let stage):
            ArisDictationPillRingView(stage: stage, recordingSeconds: display.recordingSeconds, preset: ringPreset)
                .padding(.horizontal, 4)
        case .error(let line):
            Text(line)
                .font(.system(size: 14, weight: .semibold))
                .tracking(0.14)
                .foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        case .recovered:
            // The card (ArisDictationPillRecoveredCard) shows instead.
            Color.clear
        }
    }

    /// The held recording: the app's icon (20) and the level, 4.5 apart, 6 in on the left and 10.5 on the right.
    private var holdRow: some View {
        HStack(spacing: 4.5) {
            if let icon = display.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high)
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            ArisDictationPillBarsView(audio: audio, preset: barsPreset)
        }
        .padding(.leading, display.appIcon == nil ? 10.5 : 6)
        .padding(.trailing, 10.5)
    }

    /// Hands-free (or started from the pill): ✕, the level (3 either side), then the lock (↑ on hover) or ↑; 4 apart, 6 in.
    private var handsFreeRow: some View {
        HStack(spacing: 4) {
            ArisDictationPillButton(glyph: .cancel, label: ArisDictationPillWords.cancel(display.english), action: actions.cancel)
            ArisDictationPillBarsView(audio: audio, preset: barsPreset, margin: 3)
            ArisDictationPillButton(glyph: display.fromPill ? .submit : .lock, label: ArisDictationPillWords.finish(display.english),
                                    action: actions.finish)
        }
        .padding(.horizontal, 6)
    }
}
