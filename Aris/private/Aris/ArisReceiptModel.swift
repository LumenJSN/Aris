//
//  ArisReceiptModel.swift
//  Aris
//
//  The receipt's live half (its rules are ArisReceipt's, pure): when a turn's words are final it starts counting that
//  turn's acts; when the turn's answer is known, when the turn ends (however it ended), and when a change the app made
//  itself reaches the log, it reads today's activity log from aris-agent (the app is sandboxed; the log is in
//  ~/.config/aris) and puts what the turn really did on the line under the answer. The line keeps its own five
//  seconds, leaves with the user's next turn, and its 되돌리기 runs the same undo as the 한 일 tab's (ArisController.undoEntry:
//  the same /undo, the same card first for an event or a schedule). Nothing is read while no turn is open, and a log
//  the agent doesn't answer with raises no line: the receipt never guesses.
//

import Combine
import SwiftUI
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "receipt")

@MainActor
final class ArisReceiptModel: ObservableObject {
    static let shared = ArisReceiptModel()

    /// How long 되돌리기 waits for the notch to be free before an undo that asks on a card (the voice is stopped, and
    /// the turn then ends within ArisController.lingerAfterAnswer).
    private static let freeNotchWait: TimeInterval = 4

    @Published private(set) var desk = ArisReceiptDesk()
    /// The row's height on screen (ArisReceiptRow measures it), for the answer's height budget.
    @Published private(set) var rowHeight: CGFloat = 0
    /// The pointer is on the line: it stays.
    var hovering = false

    private var clock = ArisReceiptClock()
    private var ticking: Task<Void, Never>?
    private var watches: Set<AnyCancellable> = []
    /// The newest entry of the 기록 list when it was last looked at: a new one is a turn's final reply.
    private var newestTurn: UUID?

    /// The line and its gap in the turn's column, when it shows.
    var room: CGFloat { desk.line == nil ? 0 : rowHeight + ArisReceiptRow.gap }

    func measured(_ height: CGFloat) {
        if height != rowHeight { rowHeight = height }
    }

    // MARK: - The turn

    /// The user's words are final and Aris starts on them (ArisController.understood): the line before leaves, and this
    /// turn's acts count from now.
    func turnBegan() {
        watch()
        show(desk.beginning(at: Date()))
    }

    /// The turn is over, however it ended (ArisController.finishTurn): what it really did is read once more, so a
    /// turn that failed or was stopped half-way still gets its line.
    func turnEnded() {
        let ended = desk.ending(at: Date())
        guard ended != desk else { return }
        desk = ended
        read()
    }

    /// A change the app made itself (a to-do, the timer, the volume) has reached the log (ArisAgentClient.logLocalChange).
    func localChangeLogged() { read() }

    /// Reads today's log for the open turn; a turn that began meanwhile takes nothing from it.
    private func read() {
        guard desk.reads(at: Date()) else { return }
        let turn = desk.began
        Task {
            guard let items = await ArisAgentClient.activity(today: true), desk.began == turn else { return }
            show(desk.reading(items, session: ArisController.shared.session))
        }
    }

    /// The controller's turn and its 기록 list, watched from the first turn on (never while this is being made: the
    /// controller makes its own things first).
    private func watch() {
        guard watches.isEmpty else { return }
        let aris = ArisController.shared
        newestTurn = aris.pastTurns.first?.id
        aris.$session.receive(on: DispatchQueue.main).sink { [weak self] session in
            MainActor.assumeIsolated { self?.sessionChanged(session) }
        }.store(in: &watches)
        aris.$pastTurns.map(\.first).receive(on: DispatchQueue.main).sink { [weak self] newest in
            MainActor.assumeIsolated { self?.historyChanged(newest) }
        }.store(in: &watches)
    }

    private func sessionChanged(_ session: ArisSession) {
        show(desk.seeing(session))
    }

    /// A turn's final reply was just recorded (ArisController.recordTurn, before the voice reads it): everything the
    /// turn did is in the log by now, so the line comes up with the answer. A background job's result is not a turn.
    private func historyChanged(_ newest: ArisHistoryEntry?) {
        guard newest?.id != newestTurn else { return }
        newestTurn = newest?.id
        if let newest, !newest.isTask { read() }
    }

    // MARK: - The line

    /// The line appears and leaves on the notch's size clock (its outline follows only animated layout changes);
    /// each new line, and each new thing it says, gets its five seconds.
    private func show(_ next: ArisReceiptDesk) {
        guard next != desk else { return }
        let changed = next.line != desk.line
        if (next.line == nil) != (desk.line == nil) {
            withAnimation(ArisGlass.resize) { desk = next }
        } else {
            desk = next
        }
        guard changed else { return }
        clock = ArisReceiptClock()
        if next.line == nil { hovering = false } else { startClock() }
    }

    private func startClock() {
        guard ticking == nil else { return }
        ticking = Task { [weak self] in
            while let self, !Task.isCancelled, self.desk.line != nil {
                try? await Task.sleep(for: .seconds(ArisReceiptClock.tick))
                self.tick()
            }
            self?.ticking = nil
        }
    }

    private func tick() {
        guard let line = desk.line else { return }
        clock = clock.ticking(hovering: hovering, speaking: ArisController.shared.session.phase == .speaking, undoing: line.stage == .undoing)
        if clock.isOver(failed: line.saysNotUndone) { show(desk.closing()) }
    }

    /// The notch stays open while the line is up (the end of a turn in ArisNotchRoot): back once it has left. The
    /// line's own clock bounds the wait.
    func holdWhileShown() async {
        while desk.line != nil, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(ArisReceiptClock.tick))
        }
    }

    // MARK: - Presses

    /// 되돌리기: the 한 일 tab's undo for the line's one act, and then the line says what happened.
    func undo() {
        // Every press leaves a line in the log, also one that found nothing to undo (final check on a new Mac: three
        // presses on “Moved to tomorrow”'s Undo changed nothing and left no trace of why).
        guard let pressed = desk.pressingUndo() else {
            return log.notice("receipt: Undo pressed with nothing to undo (\(ArisReceiptUndo.why(self.desk.line), privacy: .public))")
        }
        log.notice("receipt: Undo pressed for \(pressed.act.id, privacy: .public)")
        show(pressed.desk)
        Task {
            if pressed.act.asks { await waitForFreeNotch() }
            let outcome = await ArisController.shared.undoEntry(pressed.act.id)
            log.notice("receipt: the undo ended: \(ArisReceiptUndo.said(outcome), privacy: .public)")
            // The line that was pressed is no longer up (another turn's line took its place): an undo that did not
            // happen is still said, on a line of its own, never dropped.
            if desk.undoEnded(outcome, for: pressed.act, english: ArisUIWords.english) == desk,
               let failed = ArisReceiptUndo.orphaned(outcome, act: pressed.act, english: ArisUIWords.english) { show(desk.showing(failed)) }
            show(desk.undoEnded(outcome, for: pressed.act, english: ArisUIWords.english))
            // The card above the line (the to-dos, today's events) lists what is there now, without what was undone.
            ArisWidgetModel.shared.undoHappened()
            // The 한 일 tab's row for it, when the tab is open.
            await ArisActivityModel.shared.refresh()
        }
    }

    /// An undo that asks on a card first (an event Aris made would be deleted) needs the notch free for the card. The
    /// press is the user's: the voice still reading the answer stops, and the turn is over a moment later.
    private func waitForFreeNotch() async {
        let aris = ArisController.shared
        if aris.session.phase == .speaking, aris.session.question == nil { aris.speaker.stop() }
        let deadline = Date().addingTimeInterval(Self.freeNotchWait)
        while aris.session.phase != .idle, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// A press on a counted line ("3가지 함"): the side notch's 한 일 tab, where each act is listed with its own 되돌리기.
    func openActivity() {
        ArisSidePanels.shared.show(.left, tab: .activity)
    }
}
