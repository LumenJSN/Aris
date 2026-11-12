//
//  ArisConfirmCard+Countdown.swift
//  Aris
//
//  A message the user dictated, in the confirm card (the owner's pick C, mockups/countdown-card): the card's own numbers, the
//  title 메시지 보내기, 받는 사람 and the message as rows, then a lane with "“취소”라고 하면 멈춰요" and two buttons of the same
//  height, weight and brightness: 취소 (a 1-point rim) and the dark-glass 보내기 with a 14-point ring that empties
//  clockwise over the countdown (ArisCountdown). The lane stays under the rows however long the message. Nothing glows,
//  blinks or runs around the panel. When it ends the card settles into one line: on its way ("보내는 중…", until the
//  answer says whether Messages sent it) or not sent (ArisCountdownEndCard).
//

import SwiftUI

extension ArisConfirmCard {
    var countdownCard: some View {
        VStack(spacing: 0) {
            ArisFadingScroll(budget: max(0, min(Self.maxHeight, budget) - Self.allowLane - 2 * Self.verticalPadding)) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    countdownRows
                }
            }
            countdownLane
        }
        .padding(.vertical, Self.verticalPadding)
        .cardSurface()
        .cardStill(question.id)
    }

    private var countdownRows: some View {
        VStack(spacing: 0) {
            countdownRow(ArisCountdownCopy.to, question.title, font: .system(size: 12.5), opacity: 0.88)
            Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
            countdownRow(ArisCountdownCopy.message, question.detail, font: .system(size: 15, weight: .semibold), opacity: 0.95)
        }
        .padding(EdgeInsets(top: 2, leading: 14, bottom: 6, trailing: 14))
    }

    private func countdownRow(_ label: String, _ value: String, font: Font, opacity: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38)).fixedSize()
            Spacer(minLength: 0)
            Text(value).font(font).foregroundStyle(.white.opacity(opacity))
                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 9)
    }

    /// The hint, 취소 (esc) and 보내기 (↩) with its ring.
    private var countdownLane: some View {
        HStack(spacing: 8) {
            Text(ArisCountdownCopy.hint).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
            Spacer(minLength: 0)
            Button { ArisController.shared.answerQuestion(false) } label: {
                laneLabel(Text(ArisCountdownCopy.cancel))
                    .padding(.horizontal, 16).frame(height: Self.buttonHeight)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("esc")
            Button { ArisController.shared.answerQuestion(true) } label: {
                HStack(spacing: 8) {
                    ArisCountdownRing(started: countdownStarted)
                    laneLabel(Text(ArisCountdownCopy.send))
                }
                .padding(.horizontal, 18).frame(height: Self.buttonHeight)
                .background(ArisDarkGlassButton())
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(held ? Self.restOpacity : 1)
            .animation(Self.wakeEase, value: held)
            .help("↩")
        }
        .padding(.horizontal, Self.allowTrailing)
        .frame(height: Self.allowLane)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }
    }

    /// Both buttons' words: 13 / 600, +0.01 em, white 95%.
    private func laneLabel(_ text: Text) -> some View {
        text.font(.system(size: 13, weight: .semibold)).tracking(0.13).foregroundStyle(.white.opacity(0.95)).fixedSize()
    }
}

/// A clock the offscreen renders hold still (nil in the app: the ring follows the real one).
private struct ArisCountdownClockKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    var arisCountdownClock: Date? {
        get { self[ArisCountdownClockKey.self] }
        set { self[ArisCountdownClockKey.self] = newValue }
    }
}

/// 14 points, a 2-point line: the track at white 18%, what's left at 92%, from 12 o'clock clockwise.
struct ArisCountdownRing: View {
    /// When the countdown began; nil while Aris still says the message (the ring is full).
    let started: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.arisCountdownClock) private var clock

    static let size: CGFloat = 14
    static let line: CGFloat = 2

    var body: some View {
        if let started, clock == nil {
            if reduceMotion {
                TimelineView(.periodic(from: started, by: 1)) { ring(at: $0.date) }
            } else {
                TimelineView(.animation) { ring(at: $0.date) }
            }
        } else {
            ring(at: clock ?? Date())
        }
    }

    private func ring(at date: Date) -> some View {
        let left = ArisCountdown.remaining(elapsed: started.map { date.timeIntervalSince($0) }, stepped: reduceMotion)
        return ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: Self.line)
            Circle().trim(from: 0, to: left)
                .stroke(.white.opacity(0.92), style: StrokeStyle(lineWidth: Self.line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Radius 6, as the mockup's circle in its 14-point box.
        .padding(Self.line / 2)
        .frame(width: Self.size, height: Self.size)
    }
}

/// The countdown's end: one line in the card's surface, a mark, what happened and a note on the right.
struct ArisCountdownEndCard: View {
    let end: ArisCountdownEnd

    var body: some View {
        HStack(spacing: 8) {
            mark
            // Let go, it is on its way: never "보냈어요" before Messages is known to have sent it (the answer says that).
            Text(end.stopped != nil ? ArisStoppedCopy.skipped(english: end.stoppedEnglish)
                 : end.sent ? ArisCountdownCopy.sending(to: end.to, message: end.message) : ArisCountdownCopy.notSent)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if !end.sent {
                // The stopped card's line names the action that was not done; a stopped message says 취소됨.
                Text(end.stopped ?? ArisCountdownCopy.cancelled)
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.38)).lineLimit(1)
                    .fixedSize(horizontal: end.stopped == nil, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 2, leading: 14, bottom: 0, trailing: 14))
        .padding(.vertical, ArisConfirmCard.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(keys: false)
    }

    /// An 18-point mark drawn on a 24-unit grid: a quiet arrow up for a message on its way (no green check: it isn't
    /// known to be sent yet), or a quiet cross.
    private var mark: some View {
        Canvas { context, size in
            let unit = size.width / 24
            let circle = Path(ellipseIn: CGRect(x: 2 * unit, y: 2 * unit, width: 20 * unit, height: 20 * unit))
            var stroke = Path()
            if end.sent {
                context.fill(circle, with: .color(.white.opacity(0.14)))
                stroke.move(to: CGPoint(x: 12 * unit, y: 16.5 * unit))
                stroke.addLine(to: CGPoint(x: 12 * unit, y: 7.8 * unit))
                stroke.move(to: CGPoint(x: 8.2 * unit, y: 11.4 * unit))
                stroke.addLine(to: CGPoint(x: 12 * unit, y: 7.6 * unit))
                stroke.addLine(to: CGPoint(x: 15.8 * unit, y: 11.4 * unit))
                context.stroke(stroke, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round, lineJoin: .round))
            } else {
                context.fill(circle, with: .color(.white.opacity(0.14)))
                stroke.move(to: CGPoint(x: 9 * unit, y: 9 * unit))
                stroke.addLine(to: CGPoint(x: 15 * unit, y: 15 * unit))
                stroke.move(to: CGPoint(x: 15 * unit, y: 9 * unit))
                stroke.addLine(to: CGPoint(x: 9 * unit, y: 15 * unit))
                context.stroke(stroke, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 2 * unit, lineCap: .round))
            }
        }
        .frame(width: 18, height: 18)
    }

    /// It settles in over 0.3 s ease-out from 40% and 4 points below; with Reduce Motion it's simply there.
    static func entry(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : AnyTransition.modifier(active: Settle(on: true), identity: Settle(on: false)).animation(.easeOut(duration: 0.3))
    }

    private struct Settle: ViewModifier {
        let on: Bool
        func body(content: Content) -> some View { content.opacity(on ? 0.4 : 1).offset(y: on ? 4 : 0) }
    }
}
