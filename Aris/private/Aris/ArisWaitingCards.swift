//
//  ArisWaitingCards.swift
//  Aris
//
//  확인 대기: where a job's or a schedule's question lives while it is not on screen (audit card-1, card-2, imp-3).
//  The agent holds such a question for a day. The app shows its card once, read aloud; when the user's turn covers it, or
//  nobody answers before the card's limit, it is parked here instead of being answered for him: nothing is sent to the
//  agent, and a chip in the open notch brings the card back with one click. A covered card also comes back by itself at
//  the next pause, and one nobody answered after the user's next turn (they is at the Mac again), each at most once more:
//  after that only his click shows it, so a question never nags. Pure.
//

import Foundation

/// How one showing of a card ended.
enum ArisCardEnd: Equatable {
    case yes, no
    /// It waited out its limit with no answer at all.
    case unanswered
    /// The user's turn (or another card) took its place before an answer.
    case covered
    /// The agent stopped waiting for it while it was up.
    case ended
}

/// A question parked off screen.
struct ArisWaitingCard: Equatable, Identifiable {
    enum Why: String, Equatable { case covered, unanswered }

    /// The agent's id for the question.
    let id: String
    /// Whose question it is, as the user named the work (the job's or the schedule's title).
    let title: String
    /// What it asks to do (the card's own title).
    let action: String
    /// The job it belongs to; nil for a scheduled job's question from the inbox.
    let job: UUID?
    let why: Why
    let since: Date
}

struct ArisWaitingList: Equatable {
    /// Oldest first.
    private(set) var cards: [ArisWaitingCard] = []
    /// The ones the user asked to see (a click on the chip), until their card is up again.
    private(set) var opened: Set<String> = []

    var isEmpty: Bool { cards.isEmpty }
    /// The jobs with a question parked here (their running tag gives way to the chip).
    var jobs: Set<UUID> { Set(cards.compactMap(\.job)) }

    /// Parks a card; one parked again keeps its place in the row.
    func parking(_ card: ArisWaitingCard) -> ArisWaitingList {
        var next = self
        if let at = cards.firstIndex(where: { $0.id == card.id }) { next.cards[at] = card } else { next.cards.append(card) }
        next.opened.remove(card.id)
        return next
    }

    /// The card is on screen again, was answered, or is no longer wanted.
    func removing(_ id: String) -> ArisWaitingList {
        var next = self
        next.cards.removeAll { $0.id == id }
        next.opened.remove(id)
        return next
    }

    /// The user clicked its chip. Only a card that is parked here can be opened.
    func opening(_ id: String) -> ArisWaitingList {
        guard cards.contains(where: { $0.id == id }) else { return self }
        var next = self
        next.opened.insert(id)
        return next
    }

    func isOpened(_ id: String) -> Bool { opened.contains(id) }
}

enum ArisParkedAsk {
    /// What a showing's end means for a question the agent holds.
    enum Next: Equatable {
        /// The user answered: their yes or no goes to the agent.
        case send(Bool)
        /// Not answered: it waits in 확인 대기, and nothing is sent (never a no he didn't give).
        case park(ArisWaitingCard.Why)
        /// The agent no longer waits for it.
        case gone
    }

    static func next(_ end: ArisCardEnd) -> Next {
        switch end {
        case .yes: return .send(true)
        case .no: return .send(false)
        case .unanswered: return .park(.unanswered)
        case .covered: return .park(.covered)
        case .ended: return .gone
        }
    }

    /// How many times a card comes up by itself (read aloud): the first time, and once more.
    static let selfShows = 2
    /// How often a parked card asks the agent whether it still waits (a question expires after a day).
    static let waiterCheck: Duration = .seconds(30)

    enum Return: Equatable {
        /// Back on screen at the next pause. `quiet`: the user asked for it, so it isn't read aloud and only a click or Y/N answers.
        case show(quiet: Bool)
        case wait
    }

    /// When a parked card goes back on screen. `shows`: how often it came up by itself so far. `opened`: the user clicked
    /// its chip. `userTurnSince`: he started a turn since it was parked.
    static func returns(why: ArisWaitingCard.Why, shows: Int, opened: Bool, userTurnSince: Bool) -> Return {
        if opened { return .show(quiet: true) }
        guard shows < selfShows else { return .wait }
        switch why {
        case .covered: return .show(quiet: false)
        case .unanswered: return userTurnSince ? .show(quiet: false) : .wait
        }
    }

    /// The chip's words: what waits, then whose it is ("확인 대기 · 메일 보내기").
    static func chipLead(english: Bool) -> String { english ? "Needs your OK" : "확인 대기" }

    static func chipDetail(_ card: ArisWaitingCard) -> String {
        let action = card.action.trimmingCharacters(in: .whitespacesAndNewlines)
        return "· " + (action.isEmpty || action == card.title ? card.title : "\(card.title): \(action)")
    }

    static func chipHelp(english: Bool) -> String { english ? "Show this question" : "이 확인 카드 보기" }
}
