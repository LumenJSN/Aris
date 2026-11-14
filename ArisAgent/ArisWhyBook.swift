//
//  ArisWhyBook.swift
//  aris-agent
//
//  The last few turns' records (ArisWhyRecord) and what each thing the agent hears adds to the one under way: the AI
//  that is asked, every line that goes to the app on the turn's stream, and the gate's audit lines. Also which record
//  a "왜 그렇게 했어?" is about. A value: every change returns a new book (ArisWhyDesk holds the current one).
//  Foundation only (tested).
//

import Foundation

/// What /ask decided about a turn before any AI ran.
struct ArisWhyStart: Equatable {
    /// The user's request as it came (an attached file's text may follow their words).
    var request: String
    var handsFree = false
    /// The screen is in this turn (images or its text) or was earlier in the conversation.
    var screen = false
    /// Outside text is already in the conversation.
    var outside = false
    /// The turn may be given memories (ArisMemoryLearning.mayRecall), and the block it got (ArisMemoryRecall.block).
    var memoryAllowed = false
    var memory: String?
    /// The AI the user has set and the AI the turn goes to.
    var wanted = ArisBrain.claude
    var routed = ArisBrain.claude
}

/// One fact from an audit line (actions.log's JSON), with nothing of the command itself.
enum ArisWhyAuditFact: Equatable {
    case rated(ArisWhyRated)
    /// Went ahead without the user: the audit's reason ("standing permission", "main judgement").
    case approved(String)
    case refused(String)
    /// What became of the card with this id (the driver's own id for it; a route's line carries no card id, and is
    /// then about the newest card still without an answer).
    case answered(card: String, ArisWhyCardAnswer)
    case stopped

    /// `tools`: where aris-tools is, to name its commands as their cards do. `log`: the activity log an undo's card
    /// reads its entry from.
    static func read(_ line: String, tools: String, log: URL) -> ArisWhyAuditFact? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return nil }
        if let raw = object["risk"] as? String, let risk = ArisRisk(rawValue: raw), let action = object["action"] as? String {
            let why = (object["why"] as? String).flatMap { ArisWhySafe.kept($0, limit: ArisWhyRecord.lineLimit) }
            return .rated(ArisWhyRated(label: label(of: action, tools: tools, log: log), risk: risk, why: why))
        }
        guard let answer = object["answer"] as? String else { return nil }
        if let why = inside(answer, after: "auto-approved (") { return .approved(why) }
        if let why = inside(answer, after: "refused (") { return ArisWhySafe.kept(why, limit: ArisWhyRecord.lineLimit).map(ArisWhyAuditFact.refused) }
        if answer.hasPrefix("stopped (") { return .stopped }
        if let said = cardAnswer(answer) { return .answered(card: object["question"] as? String ?? "", said) }
        return nil
    }

    /// "yes", "yes (countdown)", "yes, changed on the card"; "no", "no (card)"; "unanswered", "expired". Anything else
    /// ("not sent (…)", "refused (…)") is no answer of the user's.
    private static func cardAnswer(_ answer: String) -> ArisWhyCardAnswer? {
        if answer == "yes" || answer.hasPrefix("yes (") || answer.hasPrefix("yes, ") { return .yes }
        if answer == "no" || answer.hasPrefix("no (") { return .no }
        return answer == "unanswered" || answer == "expired" ? .unanswered : nil
    }

    private static func inside(_ answer: String, after lead: String) -> String? {
        guard answer.hasPrefix(lead), answer.hasSuffix(")") else { return nil }
        return String(answer.dropFirst(lead.count).dropLast())
    }

    /// The action as its card's title names it, made from the command by the same code that makes the card
    /// (ArisCodexDriver.describe); a tool by its service and name; never the command, its arguments or a path.
    static func label(of action: String, tools: String, log: URL) -> String? {
        let title: String
        if action.hasPrefix("shell: ") {
            title = ArisCodexDriver.describe(command: String(action.dropFirst("shell: ".count)), tools: tools, log: log).0
        } else if action.hasPrefix("tool: ") {
            title = action.dropFirst("tool: ".count).replacingOccurrences(of: "/", with: " · ")
        } else if action.hasPrefix("files: ") {
            title = "파일 수정"
        } else if action.hasPrefix("computer use: ") {
            title = action.dropFirst("computer use: ".count) + " 사용"
        } else if action.hasPrefix("aside: ") {
            title = "Aside"
        } else {
            return nil
        }
        return ArisWhySafe.kept(title, limit: ArisWhyRecord.titleLimit)
    }
}

/// Which record a why-question is about.
enum ArisWhyPlan: Equatable {
    case explain(ArisWhyRecord)
    /// The turn before this one isn't in the record (the app did it itself, handed it to a background job, or it was
    /// before the agent last started). `heard`: the user's words for it, from the app's history.
    case unrecorded(heard: String)
    /// No turn has been recorded at all.
    case nothing
    /// Not a question the record answers: the AI gets it as any other turn.
    case brain
}

struct ArisWhyBook: Equatable {
    /// How many turns are kept.
    static let kept = 5

    private(set) var records: [ArisWhyRecord] = []
    /// The record each open stream is writing (the turn's connection → the record's id).
    private(set) var open: [AnyHashable: Int] = [:]
    /// The last why-question answered and the record it was about, so "왜?" asked again is about the same turn.
    private(set) var explained: (question: String, record: Int)?
    private var count = 0

    static func == (a: ArisWhyBook, b: ArisWhyBook) -> Bool {
        a.records == b.records && a.open == b.open && a.explained?.question == b.explained?.question && a.explained?.record == b.explained?.record
    }

    // MARK: - Writing

    /// A turn starts on `stream`. A record still open on another stream stays as it is (its connection closed before
    /// a last line came), and takes no more.
    func beginning(_ start: ArisWhyStart, on stream: AnyHashable, at now: Date) -> ArisWhyBook {
        var next = self
        next.count += 1
        let own = ArisMemoryText.ownWords(start.request)
        let record = ArisWhyRecord(
            id: next.count, at: now,
            asked: ArisWhySafe.kept(own, limit: ArisWhyRecord.askedLimit), match: ArisWhyMatch.key(own),
            attached: own != start.request, handsFree: start.handsFree, screen: start.screen, outsideBefore: start.outside,
            memoryAllowed: start.memoryAllowed, memories: Self.memoryLines(start.memory),
            wanted: start.wanted.title, routed: start.routed.title)
        next.records = Array((records + [record]).suffix(Self.kept))
        next.open = [stream: record.id]
        return next
    }

    /// The memory block's lines without their list mark, each cut to a memory's own length.
    static func memoryLines(_ block: String?) -> [String] {
        (block ?? "").split(whereSeparator: \.isNewline).map { line in
            String((line.hasPrefix("- ") ? line.dropFirst(2) : line).prefix(ArisMemoryText.maxLength + 40))
        }.filter { !$0.isEmpty }
    }

    /// `brain` is asked for the turn on `stream`, in place of `requested` when that one is out of quota.
    func asking(_ brain: ArisBrain, instead requested: ArisBrain, on stream: AnyHashable) -> ArisWhyBook {
        changing(stream) { record in
            if brain != requested, !record.passedOver.contains(requested.title) { record.passedOver.append(requested.title) }
            if let last = record.brains.last, last != brain.title, !record.passedOver.contains(last) { record.passedOver.append(last) }
            if record.brains.last != brain.title { record.brains.append(brain.title) }
        }
    }

    /// One line the agent sent the app on `stream`.
    func hearing(_ reply: ArisAgentReply, on stream: AnyHashable, at now: Date) -> ArisWhyBook {
        var next = changing(stream) { record in
            switch reply {
            case .status(let line):
                let kept = String(line.prefix(60))
                if !record.steps.contains(kept), record.steps.count < ArisWhyRecord.keptSteps { record.steps.append(kept) }
            case .confirm(let ask):
                guard record.cards.count < ArisWhyRecord.keptFacts, !record.cards.contains(where: { $0.id == ask.id }) else { return }
                record.cards.append(ArisWhyCard(
                    id: ask.id, title: ArisWhySafe.kept(ask.title, limit: ArisWhyRecord.titleLimit),
                    kind: ask.proposal ? .proposal : ask.countdown ? .countdown : .plain,
                    afterOutside: ask.detail.hasPrefix(ArisEscalation.taintedReason), memory: ask.memoryWrite, answer: nil))
            case .untrusted(_, _, let outside):
                if outside, !record.outsideBefore { record.outsideDuring = true }
            case .answer:
                record.outcome = .answered
                record.ended = now
            case .failure(let line):
                record.outcome = .failed(ArisWhySafe.kept(line, limit: ArisWhyRecord.lineLimit))
                record.ended = now
            case .delta, .file, .turn, .launched, .refusedJobs, .shownOnly, .operating, .skill, .stepFailed, .helperAnswers, .savedSteps, .work:
                break
            }
        }
        if reply.isLast { next.open[stream] = nil }
        return next
    }

    /// A fact from the gate's audit, for the one turn under way. With none, or more than one, it belongs to no
    /// record (never guessed).
    func audited(_ fact: ArisWhyAuditFact) -> ArisWhyBook {
        guard open.count == 1, let stream = open.keys.first else { return self }
        return changing(stream) { record in
            switch fact {
            case .rated(let rated):
                if record.rated.count < ArisWhyRecord.keptFacts * 4 { record.rated.append(rated) }
            case .approved(let why):
                if record.approved.count < ArisWhyRecord.keptFacts { record.approved.append(why) }
            case .refused(let why):
                if record.refused.count < ArisWhyRecord.keptFacts, !record.refused.contains(why) { record.refused.append(why) }
            case .answered(let card, let said):
                guard let index = record.cards.firstIndex(where: { $0.id == card || $0.id.hasSuffix("/" + card) })
                    ?? record.cards.lastIndex(where: { $0.answer == nil }) else { return }
                record.cards[index].answer = said
            case .stopped:
                record.stopped = true
            }
        }
    }

    /// The book once `question` was answered from `record`.
    func explaining(_ question: String, from record: ArisWhyRecord) -> ArisWhyBook {
        var next = self
        next.explained = (ArisWhyMatch.key(question), record.id)
        return next
    }

    private func changing(_ stream: AnyHashable, _ change: (inout ArisWhyRecord) -> Void) -> ArisWhyBook {
        guard let id = open[stream], let index = records.firstIndex(where: { $0.id == id }) else { return self }
        var next = self
        change(&next.records[index])
        return next
    }

    // MARK: - Reading

    /// Which record `focus` is answered from. `lastHeard`: what the user said in the turn before, by the app's own history
    /// (nil: the conversation has no turn yet, so the newest record is the one, with its age said).
    /// "왜 그렇게 했어?" is always answered here. "왜 물어봐?", "왜 안 돼?" and a bare "왜?" are answered here only when
    /// that turn showed a card or refused something; otherwise they are about what the AI said, and the AI answers,
    /// except a "왜 안 돼?" after a request that ended with nothing done (ArisWhyDeclined).
    func plan(_ focus: ArisWhyFocus, lastHeard: String?) -> ArisWhyPlan {
        let found = target(lastHeard)
        switch focus {
        case .did:
            if let found { return .explain(found) }
            return lastHeard.map { ArisWhyPlan.unrecorded(heard: $0) } ?? .nothing
        case .asked:
            guard let found, !found.cards.isEmpty else { return .brain }
            return .explain(found)
        case .refused:
            // A request the AI turned down in its own words (no card, nothing run, nothing refused by the gate) is still
            // answered from what the record knows (ArisWhyDeclined); a question he asked is about the AI's answer.
            guard let found, found.hasRefusal || ArisWhyDeclined.answersFromRecord(found) else { return .brain }
            return .explain(found)
        case .bare:
            guard let found, found.hasRefusal || !found.cards.isEmpty else { return .brain }
            return .explain(found)
        }
    }

    private func target(_ lastHeard: String?) -> ArisWhyRecord? {
        guard let heard = lastHeard else { return records.last }
        if let latest = records.last, ArisWhyMatch.same(heard: heard, key: latest.match) { return latest }
        // The turn before was itself a why-question: the same record again.
        if let explained, ArisWhyMatch.key(heard) == explained.question { return records.first { $0.id == explained.record } }
        return nil
    }
}
