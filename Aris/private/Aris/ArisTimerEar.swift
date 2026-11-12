//
//  ArisTimerEar.swift
//  Aris
//
//  The timer where you can see it: in the closed notch, a ring filling up (left ear) and the time left as
//  "24:13" (right ear); in the open notch, a row above the music (ArisTimerChip). The ring's ear is the timer's own
//  control (ArisTimerEarControl): click to pause, right-click for +1/+5 minutes or off. The rest of the band is only
//  drawn, so a rest or a click on it opens Aris as on any other band (ArisClosedBand; the second VM run: the whole
//  band took the click and the hover, and Aris could not be opened from most of the pill).
//  Focus is orange, breaks green, a plain timer Aris blue.
//

import SwiftUI

extension ArisTimerState {
    var tint: Color {
        switch phase {
        case .focus: Color(red: 1, green: 0.55, blue: 0.35)
        case .rest: Color(red: 0.49, green: 0.88, blue: 0.64)
        case .plain: ArisOrb.glow
        }
    }

    var icon: String {
        switch phase {
        case .focus: "brain.head.profile"
        case .rest: "cup.and.saucer.fill"
        case .plain: "timer"
        }
    }
}

/// Pause / resume, add time, cancel: the timer's menu, wherever it shows.
struct ArisTimerMenu: View {
    @ObservedObject private var timer = ArisTimerModel.shared

    var body: some View {
        Button(timer.state?.isPaused == true ? ArisUIWords.text("계속", "Resume") : ArisUIWords.text("일시정지", "Pause")) { timer.togglePause() }
        Button(ArisUIWords.text("+1분", "+1 min")) { timer.add(60) }
        Button(ArisUIWords.text("+5분", "+5 min")) { timer.add(300) }
        Divider()
        Button(ArisUIWords.text("타이머 끄기", "Turn the timer off"), role: .destructive) { timer.cancel() }
    }
}

struct ArisTimerEar: View {
    @ObservedObject private var timer = ArisTimerModel.shared

    let height: CGFloat
    let notchWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = timer.state {
                ArisBandRow(height: height, notchWidth: notchWidth) {
                    ring(state, at: context.date)
                } trailing: {
                    Text(ArisTimerState.clock(state.left(at: context.date)))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(state.isPaused ? .white.opacity(0.45) : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
        // Drawn only: the pointer on the camera's width and on the time goes to the notch, which opens.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func ring(_ state: ArisTimerState, at now: Date) -> some View {
        let size = ClaudeEarGlyph.closedSize, line = size * 0.08
        return ZStack {
            Circle().inset(by: line / 2).stroke(.white.opacity(0.15), lineWidth: line)
            Circle()
                .inset(by: line / 2)
                .trim(from: 0, to: state.progress(at: now))
                .stroke(state.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: state.isPaused ? "pause.fill" : state.icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(state.tint)
        }
        .frame(width: size, height: size)
    }
}

/// The timer's control in the closed notch: its ear, the ring's (`width` × the band's height), drawn by the notch's
/// root above its own hover, so the pointer here pauses, resumes or brings the menu and never opens the notch.
struct ArisTimerEarControl: View {
    @ObservedObject private var timer = ArisTimerModel.shared

    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Color.black.opacity(0.001)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { timer.togglePause() }
            .contextMenu { ArisTimerMenu() }
            .help(ArisUIWords.text("클릭: 일시정지/계속 · 오른쪽 클릭: +1분, +5분, 끄기", "Click: pause or resume · right-click: +1 min, +5 min, off"))
            .accessibilityElement()
            .accessibilityLabel(ArisUIWords.text("타이머", "Timer"))
            .accessibilityValue(timer.state.map { ArisTimerState.clock($0.left(at: .now)) } ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { timer.togglePause() }
    }
}
