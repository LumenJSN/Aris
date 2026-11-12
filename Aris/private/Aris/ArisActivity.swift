//
//  ArisActivity.swift
//  Aris
//
//  The closed notch's star band (ArisStarBand), the compact band (ArisBand) with the seat of Aris's star, a
//  28-point slot 23 in from its left edge. The star itself is drawn once by the notch's root view (ArisStarStage, A6):
//  here while it rests, listens or answers, down in the pill under the notch while the jobs run. One band for whatever
//  holds it, so the seat never moves when one gives way to another:
//  - the main turn: lifted 1.5 points while you talk (the notch's rim sweep is the listening signal), a turn now and then
//    while it works, still after; on the right a blue dot when an answer is waiting (also once the turn is over: the
//    answer is parked until 닫기) or a red one when it failed. Tap to stop.
//  - muted: a still struck speaker in the right ear, beside the dot when there is one (ArisMutedMarks).
//  - background jobs: the star works in the pill, which says what runs and since when (P1), and 끝났어요 at the end;
//    only when the pill can't show (a sneak peek over it) does the star work here, the count (from two on) and the
//    check on the right. Tap to open the Aris tab.
//  - at rest: the star still, nothing on the right; taps and hovers fall through to the notch.
//  Nothing hangs below it; the notch opens once there's something to read.
//

import Defaults
import SwiftUI

struct ArisActivity: View {
    @ObservedObject private var aris = ArisController.shared
    @Default(.arisMuted) private var muted
    /// Files given to Aris that wait for the next request (the band's count, at rest).
    @ObservedObject private var files = ArisAttachments.shared

    let mode: ArisStarBand.Mode
    let height: CGFloat
    let notchWidth: CGFloat
    /// The pill under the notch can show, so it carries the jobs' count and the check, not the band.
    var pillHoldsStatus = false
    /// The jobs' band opens the Aris tab.
    var openTasks: () -> Void = {}

    private var session: ArisSession { aris.session }
    private var running: Int { aris.tasks.filter { !$0.isFinished }.count }

    var body: some View {
        ArisBandRow(height: height, notchWidth: notchWidth) {
            // The band's indicator rule: bars while it listens, the star otherwise (ArisBandMark).
            ArisBandMark(listening: mode == .turn && session.phase == .listening)
        } trailing: {
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { mode == .tasks ? openTasks() : aris.stopFromBand() }
        // Parked (the turn is over) or at rest, a tap falls through to the notch, which opens.
        .allowsHitTesting(mode == .tasks || (mode == .turn && (aris.isActive || aris.conversing)))
        // Said to assistive tools only: a system tooltip over the band kept the notch's hover from arriving, so a rest
        // on the band did not open Aris (the second VM run, on the timer's band).
        .accessibilityHint(mode == .tasks ? ArisUIWords.text("Aris 열기", "Open Aris") : ArisUIWords.text("탭하면 그만", "Tap to stop"))
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: running)
    }

    @ViewBuilder
    private var trailing: some View {
        switch mode {
        case .turn, .parked, .home:
            starEar
        case .tasks where pillHoldsStatus:
            ArisMutedEar(muted: muted)
        case .tasks:
            Group {
                if running > 0 {
                    if let count = ArisStarBand.taskCount(running: running) {
                        Text(count)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                    }
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.49, green: 0.88, blue: 0.64))
                        .accessibilityLabel(ArisUIWords.text("백그라운드 작업 끝남", "Background jobs done"))
                }
            }
            .frame(width: 2 * ArisBand.markCenter)
            .accessibilityLabel(running > 0 ? ArisUIWords.text("백그라운드 작업 \(running)개 진행 중", "\(running) background jobs running") : ArisUIWords.text("백그라운드 작업 끝남", "Background jobs done"))
        }
    }

    /// The star's right ear (ArisBandEar): the lock while Aris listens by itself; the paperclip and count whenever
    /// files wait, the waiting answer's dot or the pause mark on its corner; otherwise the dot, the pause mark or the
    /// muted mark as before.
    @ViewBuilder
    private var starEar: some View {
        let resting = mode == .home
        let paused = !resting && aris.conversing && aris.pausedForOtherAudio
        let lock = aris.handsFree && session.phase == .listening && !paused && !muted
        switch ArisBandEar.shows(resting: resting, files: files.files.count, handsFreeLock: lock, answerDot: dot != nil, paused: paused) {
        case .lock:
            // The hands-free lock, ending 14 points from the band's edge: a press ends the listening.
            ArisHandsFreeLock { aris.stopFromBand() }
                .padding(.trailing, ArisVNotch.edgeInset)
                .frame(width: 2 * ArisBand.markCenter, alignment: .trailing)
        case .files(let count, let badge):
            // The attachment count, ending 14 points from the band's edge: files wait for the next request.
            ArisAttachCount(count: count, dot: badge == .dot ? dot : nil, paused: badge == .paused)
                .padding(.trailing, ArisVNotch.edgeInset)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .answer:
            ArisAnswerEar(dot: dot, paused: paused,
                          mute: ArisMutedMark.place(closed: .star(mode), muted: muted, hasNotch: true, earTaken: paused || dot != nil))
        case .rest:
            ArisMutedEar(muted: muted)
        }
    }

    private var dot: Color? {
        // Between turns of a conversation Aris is listening: no parked-answer dot.
        if aris.conversing { return nil }
        switch session.phase {
        case .failed: return Color(red: 1, green: 0.38, blue: 0.35)
        case .speaking, .idle: return session.reply.isEmpty ? nil : Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
        case .listening, .thinking: return nil
        }
    }
}

/// The sky blue that Aris's orb glowed in, still the accent of Aris's own labels and alerts. (The orb itself is gone:
/// The owner's picks A5 and A6, the star is Aris's only presence.)
enum ArisOrb {
    static let glow = Color(red: 0.45, green: 0.78, blue: 1.0)
}
