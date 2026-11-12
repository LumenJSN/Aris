//
//  ArisReceipt.swift
//  Aris
//
//  The receipt under an answer: after a turn that changed something (a message sent, an event added, a file moved),
//  one line says what was done, for about five seconds. It is built from the activity log's rows for that turn (the
//  record of the act, the same rows the side notch's 한 일 tab lists), never from the brain's words, so it is true even
//  when the brain's sentence is not: a turn that only read or answered has no rows and gets no line, and a turn that
//  failed half-way shows what it really did. One act that has an undo carries 되돌리기; several acts are counted
//  ("3가지 함") and a press opens the 한 일 tab. Only main Aris's own rows count: work in the background (a schedule, a
//  teammate's or a helper's job) never raises a line; it is in the 한 일 tab under whoever did it.
//  Everything here is a value and returns new values, so the tests run the whole of it.
//

import Foundation

/// One thing the turn did, as the log recorded it.
struct ArisReceiptAct: Equatable, Identifiable {
    /// The log entry's id (what an undo names).
    let id: String
    /// The log's own line ("메시지 보냄: 엄마").
    let summary: String
    /// An undo exists and hasn't been done.
    let undoable: Bool
    /// The undo asks on a card first (it deletes an event Aris made, or brings a removed schedule back).
    let asks: Bool
    /// The automatic check let it run (ArisActivityItem.checked): the line carries the quiet "확인함" mark.
    var checked = false
}

/// What one turn did: never empty, oldest first.
struct ArisReceipt: Equatable {
    let acts: [ArisReceiptAct]

    init?(_ acts: [ArisReceiptAct]) {
        guard !acts.isEmpty else { return nil }
        self.acts = acts
    }

    /// The act, when the turn did exactly one thing.
    var single: ArisReceiptAct? { acts.count == 1 ? acts[0] : nil }

    /// The one act's undo, when it has one; several acts are undone from the 한 일 tab, one at a time.
    var undoable: ArisReceiptAct? { single.flatMap { $0.undoable ? $0 : nil } }

    func words(english: Bool) -> String {
        single.map { ArisReceiptWords.line($0.summary, english: english) } ?? ArisReceiptWords.count(acts.count, english: english)
    }

    /// The log's own lines, for the tooltip: what exactly, when the words are short.
    var detail: String { acts.map { ArisUndoWords.clean($0.summary) }.joined(separator: "\n") }

    /// The turn's acts among the log's rows: main Aris's own (the conversation's, or the app's own change; never a
    /// background job's or a teammate's), logged since the turn began, not undone, and not already on an earlier
    /// turn's line. The log keeps whole seconds, so the turn's start counts from the top of its second.
    static func acts(in items: [ArisActivityItem], since began: Date, earlier: Set<String>) -> [ArisReceiptAct] {
        let from = Date(timeIntervalSince1970: began.timeIntervalSince1970.rounded(.down))
        return items.filter { $0.date >= from && !$0.undone && !earlier.contains($0.id) && ArisActivityTab.teammate(of: $0) == ArisActivityTab.mainName }
            .sorted { $0.date < $1.date }
            .map { ArisReceiptAct(id: $0.id, summary: $0.summary, undoable: $0.undoable, asks: $0.asks, checked: $0.checked == true) }
    }
}

/// The line as it is drawn: the receipt, and where its undo stands.
struct ArisReceiptLine: Equatable {
    enum Stage: Equatable {
        /// What was done; 되돌리기 beside it when it can be undone.
        case done
        /// 되돌리기 was pressed and hasn't answered yet: the button waits.
        case undoing
        /// It was undone: the line says so.
        case undone
        /// It wasn't undone, and why; the button stays for another try.
        case notUndone(String)
    }

    let receipt: ArisReceipt
    var stage = Stage.done

    func words(english: Bool) -> String {
        switch stage {
        case .done, .undoing: return receipt.words(english: english)
        case .undone: return ArisReceiptWords.undone(english: english)
        case .notUndone(let why): return why
        }
    }

    /// The line says an undo did not happen, and why.
    var saysNotUndone: Bool {
        if case .notUndone = stage { return true }
        return false
    }

    /// "확인함" shows: the line's one act was let run by the automatic check, and it still stands (not undone).
    var showsChecked: Bool { receipt.single?.checked == true && (stage == .done || stage == .undoing) }

    /// 되돌리기 shows: one act with an undo that hasn't happened.
    var offersUndo: Bool { receipt.undoable != nil && stage != .undone }

    /// Several acts: the line is the way to the 한 일 tab.
    var opensActivity: Bool { receipt.acts.count > 1 }

    /// How an undo's outcome reads on the line. Nil: the user said no on its card, and the line is as it was.
    static func stage(after outcome: ArisUndoOutcome?, english: Bool) -> Stage {
        switch outcome {
        case .done?: return .undone
        case nil: return .done
        // Undone elsewhere meanwhile (the 한 일 tab, "방금 거 취소해"): it is undone, which is what the line says.
        case .failed(let reason)? where reason.lowercased().contains("already undone"): return .undone
        case .failed(let reason)?: return .notUndone(ArisReceiptWords.notUndone(reason, english: english))
        case .refused?: return .notUndone(ArisReceiptWords.refused(english: english))
        case .needsConfirm?: return .notUndone(ArisReceiptWords.notUndone("", english: english))
        }
    }
}

/// How long the line stays: about five seconds of its own clock. The clock stands still while Aris is still saying the
/// answer and while an undo is on its way; while the pointer is on the line it counts the pointer's time instead, so
/// a pointer left there keeps the line (and the notch it holds open) only so long.
struct ArisReceiptClock: Equatable {
    static let stay: TimeInterval = 5
    /// A line that says an undo did not happen stays this long: it is the only place that says so, and five seconds
    /// were easy to miss (final check on a new Mac: an undo that failed looked like a receipt that just went away).
    static let failedStay: TimeInterval = 15
    static let tick: TimeInterval = 0.25
    static let longestHover: TimeInterval = 30

    /// Time the line has been up with nothing holding it.
    private(set) var counted: TimeInterval = 0
    /// Time it has been up under the pointer.
    private(set) var hovered: TimeInterval = 0

    /// One tick later.
    func ticking(hovering: Bool, speaking: Bool, undoing: Bool) -> ArisReceiptClock {
        if speaking || undoing { return self }
        return hovering ? ArisReceiptClock(counted: counted, hovered: hovered + Self.tick) : ArisReceiptClock(counted: counted + Self.tick, hovered: hovered)
    }

    var isOver: Bool { isOver(failed: false) }

    /// `failed`: the line says why an undo did not happen.
    func isOver(failed: Bool) -> Bool { counted >= (failed ? Self.failedStay : Self.stay) || hovered >= Self.longestHover }
}

/// The receipt's state from one turn to the next.
struct ArisReceiptDesk: Equatable {
    /// How long after a turn's end a change the app logged itself still counts as that turn's (the log line is
    /// written by aris-agent a moment after the reply).
    static let lateLog: TimeInterval = 3
    /// The ids of earlier lines' acts that are kept, so one act is never on two turns' lines.
    static let earlierLimit = 200

    /// When the turn whose acts may still be read began; nil before the first turn.
    private(set) var began: Date?
    private(set) var ended: Date?
    /// Acts already on an earlier turn's line (the newest last).
    private(set) var earlier: [String] = []
    private(set) var line: ArisReceiptLine?

    /// The user's words are final and Aris starts on them: the line before leaves, and what it showed is never shown again.
    func beginning(at now: Date) -> ArisReceiptDesk {
        let shown = line?.receipt.acts.map(\.id) ?? []
        return ArisReceiptDesk(began: now, earlier: Array((earlier + shown).suffix(Self.earlierLimit)))
    }

    /// The turn is over, however it ended (answered, failed, stopped).
    func ending(at now: Date) -> ArisReceiptDesk {
        guard began != nil, ended == nil else { return self }
        var next = self
        next.ended = now
        return next
    }

    /// The log is worth reading for this turn: one is open, or ended a moment ago.
    func reads(at now: Date) -> Bool {
        guard began != nil else { return false }
        return ended.map { now.timeIntervalSince($0) <= Self.lateLog } ?? true
    }

    /// The log as it is now. A line appears when the turn did something, grows when it did more, and is left alone
    /// once its undo was pressed. Nothing appears over the user's next turn or after 닫기 (`session`).
    func reading(_ items: [ArisActivityItem], session: ArisSession) -> ArisReceiptDesk {
        guard let began, line?.stage ?? .done == .done, !Self.leaves(on: session),
              let receipt = ArisReceipt(ArisReceipt.acts(in: items, since: began, earlier: Set(earlier))), receipt != line?.receipt else { return self }
        var next = self
        next.line = ArisReceiptLine(receipt: receipt)
        return next
    }

    /// The notch's turn changed: the line leaves when the user's next turn is under way or the answer was put away,
    /// never while its own undo is still out.
    func seeing(_ session: ArisSession) -> ArisReceiptDesk {
        guard line != nil, line?.stage != .undoing, Self.leaves(on: session) else { return self }
        return closing()
    }

    /// A line put up as it is (an undo that did not happen, whose own line had left).
    func showing(_ line: ArisReceiptLine) -> ArisReceiptDesk {
        var next = self
        next.line = line
        return next
    }

    /// Its time is up.
    func closing() -> ArisReceiptDesk {
        var next = self
        next.line = nil
        return next
    }

    /// 되돌리기 was pressed; nil when the line has no undo to run right now.
    func pressingUndo() -> (desk: ArisReceiptDesk, act: ArisReceiptAct)? {
        guard let line, line.offersUndo, line.stage != .undoing, let act = line.receipt.undoable else { return nil }
        var next = self
        next.line = ArisReceiptLine(receipt: line.receipt, stage: .undoing)
        return (next, act)
    }

    /// The undo for `act` came back: the line says what happened. A line that is no longer that act's stays as it is.
    func undoEnded(_ outcome: ArisUndoOutcome?, for act: ArisReceiptAct, english: Bool) -> ArisReceiptDesk {
        guard let line, line.stage == .undoing, line.receipt.undoable == act else { return self }
        var next = self
        next.line = ArisReceiptLine(receipt: line.receipt, stage: ArisReceiptLine.stage(after: outcome, english: english))
        return next
    }

    /// The user's next turn is under way (their words are being heard, or Aris is working on them), or the notch has no
    /// answer for the line to sit under (닫기, or a turn stopped before it said anything: the notch shows no turn
    /// then, and what it did is in the 한 일 tab). Listening with nothing heard yet (the pause for a follow-up) is not a
    /// new turn.
    static func leaves(on session: ArisSession) -> Bool {
        switch session.phase {
        case .listening: return !session.heard.isEmpty
        case .thinking: return true
        case .idle: return session.reply.isEmpty
        case .speaking, .failed: return false
        }
    }
}

/// What a press on the line's 되돌리기 came to, in words for the log, and the line for an undo that did not happen
/// once its own line has left (final check on a new Mac: three presses on “Moved to tomorrow”'s Undo changed nothing
/// and left no trace of why).
enum ArisReceiptUndo {
    /// Why a press found nothing to undo, for the log.
    static func why(_ line: ArisReceiptLine?) -> String {
        guard let line else { return "no line is up" }
        if line.stage == .undoing { return "its undo is already on its way" }
        if line.receipt.undoable == nil { return "the line has no single act that can be undone" }
        return "the line no longer offers it"
    }

    /// An undo's outcome in a few words, for the log.
    static func said(_ outcome: ArisUndoOutcome?) -> String {
        switch outcome {
        case .done?: return "undone"
        case nil: return "left as it was (no on its card)"
        case .failed(let reason)?: return "failed: \(reason)"
        case .refused?: return "refused by the helper"
        case .needsConfirm?: return "it asked again"
        }
    }

    /// The line for an undo that did not happen when the line it was pressed on is gone; nil when it happened or was
    /// left as it was.
    static func orphaned(_ outcome: ArisUndoOutcome?, act: ArisReceiptAct, english: Bool) -> ArisReceiptLine? {
        let stage = ArisReceiptLine.stage(after: outcome, english: english)
        guard case .notUndone = stage else { return nil }
        guard let receipt = ArisReceipt([act]) else { return nil }
        return ArisReceiptLine(receipt: receipt, stage: stage)
    }
}

/// When a new receipt line may show (ArisReceiptRow): once the place it goes has stood still, so it never slides away
/// from a click (second upgrade run, A6). Pure.
enum ArisReceiptSettle {
    /// How long the row's place must stay where it is.
    static let still: TimeInterval = 0.5

    /// `shown`: the line is already up (it stays); `movedAt`: when the row's place last moved.
    static func shows(shown: Bool, movedAt: Date, now: Date) -> Bool { shown || now.timeIntervalSince(movedAt) >= still }
}
