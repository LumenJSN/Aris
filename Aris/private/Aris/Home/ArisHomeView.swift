//
//  ArisHomeView.swift
//  Aris
//
//  The open notch: the turn (your words, Aris's answer) on top, then whatever is going on — work
//  handed to Aris (finished jobs folded into one chip), a timer, what's playing, what's on the shelf — and the input
//  row at the bottom. While something is dragged over the notch the middle becomes the two drop targets. Height
//  follows the content.
//

import Defaults
import SwiftUI

struct ArisHomeView: View {
    @EnvironmentObject private var vm: ArisNotchModel
    @ObservedObject private var aris = ArisController.shared
    @ObservedObject private var music = ArisNowPlaying.shared
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    @ObservedObject private var timer = ArisTimerModel.shared
    @ObservedObject private var coordinator = ArisNotchNavigation.shared
    @ObservedObject private var widgets = ArisWidgetModel.shared
    @ObservedObject private var team = ArisTeamModel.shared
    @ObservedObject private var desk = ArisCardDesk.shared
    /// A sent request is being edited in its card: the composer steps aside (ArisPromptEditing).
    @ObservedObject private var promptEdit = ArisPromptEditing.shared
    /// 노치 기능 › 선반 › 첫 화면에도 보이기.
    @Default(.shelfOnHome) private var shelfOnHome
    /// The rows that share the notch with a turn, measured for the answer's height budget.
    @State private var tasksHeight: CGFloat = 0
    @State private var timerHeight: CGFloat = 0
    @State private var composerHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.dropInteraction.anyDropZoneTargeting {
                ArisDropZones().transition(.opacity)
            } else {
                // Over a turn put back from the 기록 tab: when it was (ArisHistoryRestore).
                ArisRestoredCaption()
                if showsTurn {
                    // The card's entrance (in at .965 from the top) and the result's exit (out 4 up at .985), on the
                    // opening clock with the surface.
                    ArisTurnView(room: room).transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.965, anchor: .top)),
                        removal: ArisTurnView.exit))
                }
                if showsTasks {
                    ArisTaskTags().transition(.opacity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tasksHeight = $0 }
                }
                if showsTimerChip {
                    ArisTimerChip().transition(.opacity)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { timerHeight = $0 }
                }
                // Right after the first-run setup: one line and three things to try (ArisFirstTries).
                ArisFirstTriesRow(hidden: showsTurn)
                // The evening's offer of the day-end summary waits here as a chip (ArisDayEndChip).
                ArisDayEndRow(hidden: showsTurn)
                // While the wake word rests (a call, the battery), one line says why (ArisWakeRestRow).
                ArisWakeRestRow(hidden: showsTurn)
                // A turn has the notch to itself; music and the shelf come back once it's put away.
                if !showsTurn && (!music.isPlayerIdle || music.isPlaying) {
                    ArisMusicStrip().transition(.opacity)
                }
                if ArisShelfTileLayout.homeRowShown(files: ArisShelfChips.visible(shelf.items).count, turnShowing: showsTurn, onHome: shelfOnHome) {
                    ArisShelfChips { coordinator.currentView = .shelf }.transition(.opacity)
                }
            }
            // The input hides while Aris listens, works or asks; it's back under the answer for a follow-up,
            // coming in from 4 points up at .985 on the opening clock. It leaves at once (no exit animation).
            if !working && !promptEdit.active {
                ArisComposer().transition(.asymmetric(insertion: Self.composerEnter, removal: .identity))
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        // On the composer's own 340 ms clock, so the answer gives up its line as the composer takes it.
                        if height != composerHeight { withAnimation(ArisGlass.resize) { composerHeight = height } }
                    }
            }
        }
        .frame(width: ArisGlass.contentWidth)
        .padding(.top, 2)
        // The inset under the content: 8 while the composer shows (the notch's own), 12 without it.
        .padding(.bottom, ArisVNotch.expandedBottomInset(composerShown: !working && !promptEdit.active) - ArisGlass.bottomInset)
        .animation(ArisGlass.opening, value: showsTurn)
        .animation(ArisGlass.opening, value: working)
        .animation(ArisGlass.opening, value: promptEdit.active)
        .animation(ArisGlass.resize, value: vm.dropInteraction.anyDropZoneTargeting)
    }

    /// The composer's entrance: from 4 points up at .985.
    private static let composerEnter: AnyTransition = .opacity.combined(with: .offset(y: -4)).combined(with: .scale(scale: 0.985, anchor: .top))

    /// The surface max on this display, less the band and every row but the turn's own (each with its 12-point gap).
    private var room: ArisAnswerRoom {
        ArisAnswerRoom(
            surfaceMax: arisSurfaceMax(screenUUID: vm.screenUUID),
            band: vm.openBandHeight,
            context: (showsTasks ? tasksHeight + 12 : 0) + (showsTimerChip ? timerHeight + 12 : 0),
            composer: working || promptEdit.active ? 0 : composerHeight)
    }

    /// Jobs running, or finished and not yet seen (the done chip, ArisDoneFold), or a question waiting off screen (확인 대기).
    private var showsTasks: Bool { !madeCardUp && (ArisDoneFold.shows(aris.tasks, seen: aris.seenDone) || !desk.waiting.isEmpty) }

    /// A turn under way, or a card waiting for the user (a confirm card, or the new-teammate card: QA BUG-36, drawn over
    /// the done chip and the composer when it left them up): the card has the content area.
    private var working: Bool {
        [.listening, .thinking].contains(aris.session.phase) || aris.session.question != nil || madeCardUp
    }

    private var madeCardUp: Bool { team.made.map { $0.heard == aris.session.heard } ?? false }

    /// The timer's row, unless the answer's timer card shows the same timer.
    private var showsTimerChip: Bool {
        timer.isRunning && !(showsTurn && widgets.card(for: aris.session.reply)?.content == .timer)
    }

    /// The live turn, or the last answer until it's put away.
    private var showsTurn: Bool {
        aris.isActive || !aris.session.reply.isEmpty || aris.training != nil
    }
}

/// A running timer as one row: ring, time left, what it is, pause / +5 / stop.
struct ArisTimerChip: View {
    @ObservedObject private var timer = ArisTimerModel.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let state = timer.state {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 2.5)
                        Circle().trim(from: 0, to: state.progress(at: context.date))
                            .stroke(ArisOrb.glow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                    }
                    .frame(width: 18, height: 18)
                    Text(ArisTimerState.clock(state.left(at: context.date)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(ArisGlass.text)
                    Text(Self.label(state)).font(.system(size: 12)).foregroundStyle(ArisGlass.secondaryText).lineLimit(1).arisTextBacking()
                    Spacer(minLength: 0)
                    button(state.isPaused ? "play.fill" : "pause.fill") { timer.togglePause() }
                    button("goforward.5") { timer.add(300) }
                    button("xmark") { timer.cancel() }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
    }

    private static func label(_ state: ArisTimerState) -> String {
        switch state.phase {
        case .plain: return state.isPaused ? ArisUIWords.text("타이머 · 멈춤", "Timer · paused") : ArisUIWords.text("타이머", "Timer")
        case .focus: return ArisUIWords.text("집중 \(state.round)/\(ArisTimerState.rounds)", "Focus \(state.round)/\(ArisTimerState.rounds)")
        case .rest: return ArisUIWords.text("휴식", "Break")
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(ArisGlass.text)
                .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}
