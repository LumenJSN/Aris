//
//  ArisTaskReplay.swift
//  Shared/Core (aris-agent, tests)
//
//  A task as its journal tells it: the records read in order into one state (who asked what, on which brain, what it
//  did, which card waits, what it said so far, how it ended). The helper's job book and the app's ledger are views of
//  this state. Foundation only.
//

import Foundation

struct ArisTaskState: Equatable {
    struct Step: Equatable {
        let text: String
        let effect: Bool
        let at: Date
    }

    struct Card: Equatable {
        let card: ArisTaskCard
        var allow: Bool?
        var how: String?
        let at: Date
    }

    let job: String
    let title: String
    let request: String
    let prompt: String
    let brain: String
    let model: String
    let origin: ArisTaskOrigin
    let created: Date
    var started: Date?
    var session: String?
    var steps: [Step] = []
    var lastStatus: String?
    var cards: [Card] = []
    var output = ""
    var ending: ArisTaskRecord.Ending?
    var endLine: String?
    var ended: Date?
    var recoveries = 0
    var lastRecovery: ArisTaskRecord.Recovery?
    /// The last time anything was written for it.
    var touched: Date
    var taint = "none"
    /// When the last (re)start or recovery began: a card older than that belongs to a process that is gone.
    var runSince: Date?

    var isOpen: Bool { ending == nil }

    /// Something it did may have changed something.
    var hadSideEffects: Bool { steps.contains(where: \.effect) || cards.contains { $0.allow == true } }

    /// The card it waits on now: the last one asked and not answered.
    var openCard: ArisTaskCard? {
        guard let last = cards.last, last.allow == nil else { return nil }
        return last.card
    }

    /// From a journal's records; nil when it has no `created` record.
    static func replay(_ records: [ArisTaskRecord]) -> ArisTaskState? {
        guard let first = records.first(where: { $0.kind == .created }), let job = first.job else { return nil }
        var state = ArisTaskState(job: job, title: first.title ?? "", request: first.request ?? "", prompt: first.prompt ?? "",
                                  brain: first.brain ?? "", model: first.model ?? "", origin: first.origin ?? ArisTaskOrigin(tier: "work"),
                                  created: first.at, touched: first.at)
        for record in records where record.kind != .created {
            state.apply(record)
        }
        return state
    }

    private mutating func apply(_ record: ArisTaskRecord) {
        touched = max(touched, record.at)
        if let taint = record.taint, Self.rank(taint) > Self.rank(self.taint) { self.taint = taint }
        switch record.kind {
        case .created:
            break
        case .started:
            if started == nil { started = record.at }
            runSince = record.at
        case .session:
            session = record.session
        case .step:
            steps.append(Step(text: record.text ?? "", effect: record.effect ?? true, at: record.at))
        case .status:
            if let text = record.text { lastStatus = text }
        case .card:
            if let card = record.card { cards.append(Card(card: card, allow: nil, how: nil, at: record.at)) }
        case .answer:
            guard let id = record.card?.id, let index = cards.lastIndex(where: { $0.card.id == id && $0.allow == nil }) else { return }
            cards[index].allow = record.allow ?? false
            cards[index].how = record.text
        case .output:
            output = record.text ?? ""
        case .ended:
            ending = record.ending
            endLine = record.text
            ended = record.at
        case .recovered:
            recoveries += 1
            lastRecovery = record.recovery
            runSince = record.at
            // A card asked before the restart belonged to a process that is gone: a resumed or restarted task asks again.
            if record.recovery != .waiting {
                for index in cards.indices where cards[index].allow == nil {
                    cards[index].allow = false
                    cards[index].how = "superseded"
                }
            }
        }
    }

    static func rank(_ taint: String) -> Int {
        switch taint {
        case "outsideText": return 2
        case "screenSeen": return 1
        default: return 0
        }
    }
}
