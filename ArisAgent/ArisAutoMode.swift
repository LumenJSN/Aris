//
//  ArisAutoMode.swift
//  aris-agent
//
//  What the automatic check's answer is worth, for every brain (the runner's escalation for Codex and the API brain,
//  ArisActionGate for the Claudes): one place, so no brain's rule differs.
//  - A match lets that one call run with no card. It clears nothing: the conversation's taint stays, so the next
//    action is checked again, and the verdict is bound to the call's exact words and used once (ArisAutoBook).
//  - A mismatch or an unsure answer: the action does not run, and the stopped card goes up (ArisAutoCard).
//  - Words of the user's too few to mean anything, a checker that failed, was late or answered oddly, a call that changed
//    while it was checked, a verdict used twice, or more than `maxChecks` checks in one turn: nothing was decided, so
//    today's card goes up at once, opened with one line that says why (security review 9, L1: one card, as before
//    auto mode, where the stopped card and then today's card made two). After a turn's first stop nothing more is
//    checked in it: each later card is today's card.
//  - A message or a mail to someone the user did not name asks on today's card, with one line saying so, whatever the
//    checker would say; a to-do for a list, or an event for a calendar, that his request doesn't name is today's card
//    too (the list or calendar may be other people's: ArisAutoSend).
//  - A to-do or an event that names no list or calendar goes where new ones go, which may be shared: unless the app
//    said with this turn that that place is his own (ArisAutoPlaces), today's card (security review 9, L2).
//  - A call the checker could not be shown whole and unaltered (ArisAutoAction.read) is never checked: today's card.
//  - No AI able to check: nothing changes, every card is today's. A checker that can't be reached once asked is a
//    failure like any other: the action stops.
//  - A turn that isn't the user's own (a schedule, a background job, a teammate, hands-free, a routine's step), or the
//    hidden switch `arisAutoCheckOff`: nothing here applies and the card is today's.
//  Pure apart from reading that one switch; the tests run it with a recorded checker.
//

import Foundation

/// A pass to check one call: its id and the call's fingerprint when the check began.
struct ArisAutoTicket: Equatable {
    let id: Int
    let fingerprint: String
}

/// One turn's checks: how many began, whether one stopped, and the tickets not yet used.
final class ArisAutoBook: @unchecked Sendable {
    /// The most checks one turn may make. One request rarely needs more than two or three changes; six leaves room
    /// for a list ("이 세 개 할 일에 넣어 줘") and bounds what a brain steered by a page can try (one harmful act cut
    /// into many small ones, or a hundred guesses at what passes), and the time and money the checks take.
    static let maxChecks = 6

    private let lock = NSLock()
    private var began = 0
    private var stopped = false
    private var open: [Int: String] = [:]

    /// A ticket for a call with this fingerprint; nil past the limit or once anything stopped this turn.
    func begin(_ fingerprint: String) -> ArisAutoTicket? {
        lock.withLock {
            guard !stopped, began < Self.maxChecks else { return nil }
            began += 1
            open[began] = fingerprint
            return ArisAutoTicket(id: began, fingerprint: fingerprint)
        }
    }

    /// Uses the ticket: true once, and only for a call whose words are still exactly the ones checked.
    func redeem(_ ticket: ArisAutoTicket, fingerprint: String) -> Bool {
        lock.withLock { open.removeValue(forKey: ticket.id) == fingerprint && ticket.fingerprint == fingerprint && !stopped }
    }

    /// Something stopped: no later action of this turn is let through by a check.
    func noteStop() { lock.withLock { stopped = true } }

    var hasStopped: Bool { lock.withLock { stopped } }
    var checks: Int { lock.withLock { began } }
}

/// Why the stopped card is up: the check said this isn't what the user asked (or couldn't tell), or there was no usable
/// answer (the card then says so instead: a reply must be true).
enum ArisAutoStop: String, Equatable {
    /// The checker said it isn't what he asked (or was unsure): the stopped card.
    case notAsked
    /// No usable answer: today's card with the line why.
    case notChecked
    /// His words now are too few to check anything against: today's card with the line why.
    case tooFew

    /// Only the checker's own "no" shows the stopped card; for the rest nothing was decided (review 9, L1).
    var showsStoppedCard: Bool { self == .notAsked }
}

/// What happens before any model is asked.
enum ArisAutoStep: Equatable {
    /// None of the check's business: today's behaviour.
    case asIs
    /// Today's card, opened with this line.
    case ask(reason: String)
    case stop(ArisAutoStop, ledger: String)
    case check(ArisAutoTicket)
}

enum ArisAutoOutcome: Equatable {
    /// Run this one call: a match.
    case run
    case stop(ArisAutoStop)
}

enum ArisAutoMode {
    /// `defaults write aris-agent arisAutoCheckOff -bool true`: the whole check off, every card as before (to tell a
    /// fault of the check from one of the gate). There is no setting for it.
    static let offKey = "arisAutoCheckOff"
    nonisolated(unsafe) static var isOff: () -> Bool = { UserDefaults.standard.bool(forKey: offKey) }

    /// The app's latest word on whether his default list and calendar are his own, and the calendar `use-calendar`
    /// saved (the tests set both: they never read the user's files).
    nonisolated(unsafe) static var places: () -> ArisAutoPlaces = { ArisAutoPlacesBox.shared.now }
    nonisolated(unsafe) static var savedCalendar: () -> String? = { ArisAutoPlacesBox.savedCalendar() }

    /// A check that passes sooner than this shows no tag at all.
    static let tagDelay: TimeInterval = 0.3

    /// `argv`: a call ArisAutoScope.eligible let through. `action`: that call as the checker can be shown it whole
    /// (ArisAutoAction.read), else nil. `ownerTurns`: the user's turns when the turn now is their own (ArisOwnerWords.said),
    /// the last of them his request now; else nil. `available`: an AI can be asked.
    static func before(argv: [String], action: ArisAutoAction?, ownerTurns: [String]?, available: Bool, book: ArisAutoBook, english: Bool) -> ArisAutoStep {
        guard !isOff(), let now = ownerTurns?.last else { return .asIs }
        if let who = ArisAutoSend.recipient(argv), !ArisAutoSend.named(who, in: [now]) { return .ask(reason: ArisAutoSend.reason(who, english: english)) }
        // Not a checked kind, or not showable whole; after the turn's first stop; or nobody to ask: today's card, one step.
        guard let action, !book.hasStopped, available else { return .asIs }
        // A list or a calendar may be other people's too: its name must be in his request, else today's card.
        if let place = ArisAutoSend.place(action.call), !ArisAutoSend.named(place, in: [now]) { return .asIs }
        // None named: where it goes must be his own, by the app's word with this turn; shared or unknown is today's card.
        guard places().ownsUnnamed(action.call, saved: savedCalendar()) else { return .asIs }
        guard ArisOwnerWords.saysSomething([now]) else {
            book.noteStop()
            return .stop(.tooFew, ledger: "unsure (too few words)")
        }
        guard let ticket = book.begin(action.fingerprint) else {
            book.noteStop()
            return .stop(.notChecked, ledger: "not checked (over \(ArisAutoBook.maxChecks) checks this turn)")
        }
        return .check(ticket)
    }

    /// `argvNow`: the call as it stands when the answer arrives (nil: it is gone). The ledger's word comes back too.
    /// Only a match for the very call that was checked runs; everything else stops.
    static func after(_ run: ArisAutoRun, ticket: ArisAutoTicket, argvNow: [String]?, book: ArisAutoBook) -> (outcome: ArisAutoOutcome, ledger: String) {
        let stop = { (why: ArisAutoStop, ledger: String) -> (ArisAutoOutcome, String) in
            book.noteStop()
            return (.stop(why), ledger)
        }
        switch run {
        case .late: return stop(.notChecked, "late")
        case .failed: return stop(.notChecked, "failed")
        case .answered(let text):
            guard let verdict = ArisAutoCheck.parse(text) else { return stop(.notChecked, "malformed") }
            guard verdict == .match else { return stop(.notAsked, verdict.name) }
            guard book.redeem(ticket, fingerprint: argvNow.map(ArisAutoAction.fingerprint) ?? "") else {
                return stop(.notChecked, "match not used (the call changed, or its ticket was spent)")
            }
            return (.run, verdict.name)
        }
    }

    /// One line for actions.log: which call (its kind's fixed words and its fingerprint, never its text), the verdict,
    /// the model and how long it took.
    static func ledger(_ action: ArisAutoAction, verdict: String, model: String, seconds: TimeInterval?) -> [String: String] {
        var line = ["question": "auto check", "action": action.ledgerName, "answer": "auto check: " + verdict,
                    "model": model.isEmpty ? "none" : String(model.prefix(80))]
        if let seconds { line["ms"] = String(Int((seconds * 1_000).rounded())) }
        return line
    }
}

/// The stopped card and the words around the check, Korean and English (the request's language picks, as for every
/// gate card).
enum ArisAutoCard {
    static func title(_ why: ArisAutoStop, english: Bool) -> String {
        switch why {
        case .notAsked: english ? "Stopped: you didn't ask for this." : "시키지 않은 일이라 멈췄어요."
        case .notChecked, .tooFew: english ? "Stopped: I couldn't check this." : "확인하지 못해서 멈췄어요."
        }
    }

    /// The line today's card opens with when the check decided nothing (review 9, L1); nil for the stopped card's case.
    /// Korean first; the English is looked up (ArisGateWords.lines).
    static func todaysLine(_ why: ArisAutoStop, english: Bool) -> String? {
        let korean: String
        switch why {
        case .notAsked: return nil
        case .notChecked: korean = notCheckedLine
        case .tooFew: korean = tooFewLine
        }
        return english ? ArisGateWords.line(korean) : korean
    }

    static let notCheckedLine = "시킨 일이 맞는지 자동으로 확인하지 못해서 물어봐요"
    static let tooFewLine = "요청만으로는 시킨 일이 맞는지 알 수 없어서 물어봐요"

    /// The running tag while a check is under way.
    static func checking(english: Bool) -> String { english ? "Checking it's what you asked" : "시킨 일이 맞는지 확인 중" }

    /// The stopped card for the action `ask` is about: the sentence, then what was about to happen, made from the
    /// action's own card (its title and details, as the gate's describer wrote them), never from the checker. The
    /// details' first line is the action's title (the gate's own fixed words); every line after it is the action's own
    /// text, which the app draws as one quoted block and never reads as rows (ArisStoppedCard).
    static func stopped(for ask: ArisConfirmation, id: String, why: ArisAutoStop, english: Bool) -> ArisConfirmation {
        var card = ArisConfirmation(id: id, title: title(why, english: english), detail: detail(title: ask.title, detail: ask.detail, english: english))
        card.stopped = true
        return card
    }

    /// The action's title on the first line, then its details, without the line that says why today's card asks.
    static func detail(title: String, detail: String, english: Bool) -> String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ") + "\n" + plain(detail)
    }

    /// A card's details without the gate's own line about outside content (it is no part of the action).
    static func plain(_ detail: String) -> String {
        let reasons = [ArisEscalation.taintedReason, ArisGateWords.line(ArisEscalation.taintedReason)]
        return detail.split(whereSeparator: \.isNewline).map(String.init).filter { !reasons.contains($0) }.joined(separator: "\n")
    }

    /// Today's card for `ask`, opened with one more line (a message to someone the user didn't name).
    static func reasoned(_ ask: ArisConfirmation, _ reason: String) -> ArisConfirmation {
        ArisConfirmation(id: ask.id, title: ask.title, detail: reason + "\n" + ask.detail, full: ask.full.map { reason + "\n" + $0 }, fields: ask.fields,
                         allow: ask.allow, memoryWrite: ask.memoryWrite, desktop: ask.desktop)
    }
}
