//
//  ArisWhyAnswer.swift
//  aris-agent
//
//  The answer to "왜 그렇게 했어?", "왜 물어봐?", "왜 안 돼?" and "왜?": one sentence to say (which memory or rule it
//  was), then the turn's facts as a short list to read. Made only from the turn's record (ArisWhyRecord) and what the
//  activity log holds for those minutes; no AI words it, so nothing in it is a guess. A fact the record doesn't hold
//  is said to be unknown.
//
//  Two things are held back:
//  - memories' own words, when this turn was heard hands-free or its conversation holds the screen or outside text
//    (memories are never brought into such a conversation: ArisMemoryLearning.mayRecall);
//  - names that came out of a turn that read the screen or outside text (a card's title, a done line, a failure's
//    words), when this conversation is a clean one: said back here they would enter it as Aris's own words.
//  The words are ArisWhyCopy's. Foundation only (tested).
//

import Foundation

/// What is read when the question is asked, to go with the record.
struct ArisWhyEvidence: Equatable {
    /// The activity log's lines for the turn's own minutes; nil when the log couldn't be read.
    var done: [String]? = []
    /// Where each memory line came from, by the line as the AI read it.
    var sources: [String: ArisMemorySource] = [:]
}

/// The question as it was asked.
struct ArisWhyAsking: Equatable {
    var focus = ArisWhyFocus.did
    var korean = true
    /// This turn's conversation holds the screen or outside text.
    var tainted = false
    var handsFree = false
    var now = Date()
}

enum ArisWhyAnswer {
    /// The answer from `record`.
    static func text(_ record: ArisWhyRecord, evidence: ArisWhyEvidence, asking: ArisWhyAsking) -> String {
        let copy = ArisWhyCopy(korean: asking.korean)
        let view = View(record: record, evidence: evidence, asking: asking, copy: copy)
        let lead: String
        switch asking.focus {
        case .did: lead = view.didLead
        case .asked: lead = view.askedLead ?? view.didLead
        case .refused: lead = view.refusedLead ?? view.declinedLead
        case .bare: lead = view.refusedLead ?? view.askedLead ?? view.didLead
        }
        let wantsInstead = asking.focus != .asked
        let lines = [view.requestLine, view.brainLine, view.memoryLine, view.readLine, view.doneLine, view.cardLine, view.ruleLine,
                     wantsInstead ? view.insteadLine : nil].compactMap { $0 }
        return shaped(lead, title: copy.factsTitle, lines: lines, say: !asking.tainted)
    }

    /// The turn before isn't in the record. `heard`: the user's words for it. `appDid`: what the app itself logged since.
    /// `latest`: the newest turn the record does hold.
    static func unrecorded(heard: String, appDid: [String], latest: ArisWhyRecord?, asking: ArisWhyAsking) -> String {
        let copy = ArisWhyCopy(korean: asking.korean)
        let said = ArisWhySafe.kept(heard, limit: 40)
        var lines = [copy.unrecordedWhy, copy.unrecordedLocal]
        // The newest first: "that last one" is most likely one of them (final check on a new Mac: the three oldest
        // of the window were named, and the acts made just before the question were the ones left out).
        if !appDid.isEmpty { lines.append(copy.label(copy.doneLabel, copy.list(appDid.reversed().map { asking.korean ? $0 : ArisActivityWords.english($0) }.map(copy.quoted), limit: 3))) }
        if let latest { lines.append(copy.latestRecorded(latest.asked.map { copy.short($0, 40) }, minutes: minutes(since: latest, now: asking.now))) }
        return shaped(copy.unrecordedLead(said), title: copy.unrecordedTitle, lines: lines, say: !asking.tainted)
    }

    /// Nothing has been recorded since the agent started at `since`.
    static func nothing(since: Date, asking: ArisWhyAsking) -> String {
        let copy = ArisWhyCopy(korean: asking.korean)
        return shaped(copy.nothingLead, title: copy.unrecordedTitle, lines: [copy.nothingSince(since), copy.memoryOnly], say: !asking.tainted)
    }

    /// The sentence to say, then the facts to read (the answer shape every AI uses: ArisAgentPrompt.answerShape).
    /// `say`: the app reads only a <say> line aloud; in a conversation with outside text it shows one as written, so
    /// none is used there and the sentence simply comes first.
    private static func shaped(_ lead: String, title: String, lines: [String], say: Bool) -> String {
        let body = lead + "\n\n### " + title + "\n" + lines.map { "- " + $0 }.joined(separator: "\n")
        return say ? "<say>" + lead + "</say>\n" + body : body
    }

    static func minutes(since record: ArisWhyRecord, now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(record.ended ?? record.at) / 60))
    }

    /// One record with the question, read as the answer's parts.
    private struct View {
        let record: ArisWhyRecord
        let evidence: ArisWhyEvidence
        let asking: ArisWhyAsking
        let copy: ArisWhyCopy

        /// Names made in a turn that read the screen or outside text stay out of a clean conversation.
        var names: Bool { !record.tainted || asking.tainted }
        /// Memories' own words are said only on the user's own clean turn.
        var memoryWords: Bool { !asking.tainted && !asking.handsFree }

        private func name(_ text: String?) -> String? { names ? text : nil }

        /// An AI's name as the record keeps it (its Korean title), as the answer says it: “API model” in English.
        private func brain(_ title: String) -> String { asking.korean ? title : ArisWhyCopy.englishBrain(title) }

        /// A line of the activity log as the answer quotes it: in English with its names as they are (ArisActivityWords,
        /// the table the 한 일 tab draws from), or as the log has it.
        private func logged(_ line: String) -> String { asking.korean ? line : ArisActivityWords.english(line) }

        // MARK: The sentence

        var brainClause: String {
            guard let last = record.brains.last else { return copy.noBrainClause }
            return record.passedOver.isEmpty ? copy.brainClause(brain(last)) : copy.tookOverClause(brain(last), from: record.passedOver.map(brain).joined(separator: ", "))
        }

        /// A refusal is the sentence when it is all the turn came to (no card went up, nothing was logged as done): that
        /// rule is why it did what it did. Otherwise what he asked and who took it, then the card, the standing yes or
        /// the memory that shaped it; a step refused along the way is in the list.
        var didLead: String {
            if let refusedLead, record.cards.isEmpty, (evidence.done ?? []).isEmpty { return refusedLead }
            let tail: String
            if let card = record.cards.last {
                tail = copy.askedFirstClause(name(card.title))
            } else if record.approved.contains(where: { $0.hasPrefix("standing permission") }) {
                tail = copy.standingClause
            } else if !record.memories.isEmpty, !record.brains.isEmpty {
                tail = copy.memoryClause(memoryWords ? memoryText(record.memories[0], ArisWhyCopy.inSentence) : nil, count: record.memories.count)
            } else {
                tail = record.brains.isEmpty ? copy.plainLocalClause : copy.plainClause
            }
            return copy.didLead(asked: record.asked, brain: brainClause, tail: tail)
        }

        var askedLead: String? {
            guard let card = record.cards.last else { return nil }
            return copy.askedLead(name(card.title), why: askReason(card).short)
        }

        /// The rule that put `card` up: in a few words for the sentence, and whole for the list.
        func askReason(_ card: ArisWhyCard) -> (short: String, whole: String) {
            if card.afterOutside { return (copy.askAfterOutsideShort, copy.askAfterOutside) }
            let streak = ArisStandingPermissions.streakToPropose
            switch card.kind {
            case .countdown: return (copy.askCountdownShort, copy.askCountdown)
            case .proposal: return (copy.askProposalShort(streak), copy.askProposal(streak))
            case .plain:
                if card.memory { return (copy.askMemoryShort, copy.askMemory) }
                return record.handsFree ? (copy.askHandsFreeShort, copy.askHandsFree) : (copy.askPlainShort, copy.askPlain)
            }
        }

        /// The one refusal that says most, as (what was refused, the rule, what to do instead).
        var refusal: (label: String?, rule: String, instead: String?)? {
            if let never = record.nevers.last { return explained(never.label, never.why) }
            if let why = record.refused.last { return explained(nil, why) }
            if let line = record.gateLines.last { return explained(nil, line) }
            if let card = record.declined.last {
                return (name(card.title), card.answer == .no ? copy.declined : copy.unanswered, copy.declinedInstead)
            }
            if record.stopped { return (nil, copy.stopped, copy.askAgainInstead) }
            if case .failed(let line) = record.outcome { return (nil, copy.failed(name(line)), copy.askAgainInstead) }
            return nil
        }

        private func explained(_ label: String?, _ why: String?) -> (label: String?, rule: String, instead: String?) {
            guard let why else { return (name(label), copy.noReasonKept, nil) }
            if let rule = ArisWhyRules.plain(why, korean: asking.korean) { return (name(label), rule.why, rule.instead) }
            return (name(label), names ? copy.asRecorded(why) : copy.reasonHeld, nil)
        }

        var refusedLead: String? { refusal.map { copy.refusedLead($0.label, rule: $0.rule) } }

        /// The rule his own words point at when the turn refused nothing and did nothing (money: ArisWhyDeclined).
        var declinedRule: ArisWhyRule? {
            guard refusal == nil, asking.focus == .refused else { return nil }
            return ArisWhyDeclined.rule(for: record, done: evidence.done, korean: asking.korean)
        }

        /// "왜 안 돼?" about a turn with no refusal on record: Aris's rules refused nothing, the AI answered in its own
        /// words, and the rule when one is known.
        var declinedLead: String {
            let ranNothing = record.steps.isEmpty && record.approved.isEmpty && record.autoCount == 0 && (evidence.done ?? []).isEmpty
            // The AI by the name this answer's language gives it (“API model”, not “API 브레인”, in English).
            return ArisWhyDeclined.lead(brain: record.brains.last.map(brain), ranNothing: ranNothing, rule: declinedRule, korean: asking.korean)
        }

        // MARK: The list

        var requestLine: String {
            let age = ArisWhyAnswer.minutes(since: record, now: asking.now)
            var words = record.asked.map(copy.quoted) ?? copy.secretWords
            if age >= 2 { words += " " + copy.ago(age) }
            if record.attached { words += " " + copy.withFile }
            if record.outcome == .open { words += " " + copy.stillGoing }
            return copy.label(copy.requestLabel, words)
        }

        var brainLine: String {
            guard let last = record.brains.last else { return copy.label(copy.brainLabel, copy.noBrain) }
            var words = record.passedOver.isEmpty ? brain(last) : copy.tookOver(brain(last), from: record.passedOver.map(brain).joined(separator: ", "))
            if record.wanted != record.routed {
                words += " " + copy.routed(from: record.wanted, why: record.handsFree ? copy.routedHandsFree : record.screen ? copy.routedScreen : copy.routedUnknown)
            }
            return copy.label(copy.brainLabel, words)
        }

        var memoryLine: String? {
            guard !record.brains.isEmpty else { return nil }
            guard record.memoryAllowed else {
                return copy.label(copy.memoryLabel, copy.memoryNotGiven(record.handsFree ? copy.becauseHandsFree : record.screen ? copy.becauseScreen
                                                                       : record.outsideBefore ? copy.becauseOutside : copy.becauseOther))
            }
            guard !record.memories.isEmpty else { return copy.label(copy.memoryLabel, copy.memoryNone) }
            guard memoryWords else {
                return copy.label(copy.memoryLabel, asking.handsFree ? copy.memoryHeldHandsFree(record.memories.count) : copy.memoryHeld(record.memories.count))
            }
            let shown = record.memories.prefix(4).map { line in
                copy.quoted(memoryText(line, 60)) + (evidence.sources[line].flatMap(copy.source).map { " (" + $0 + ")" } ?? "")
            }
            return copy.label(copy.memoryLabel, copy.memoryGiven(copy.list(shown, limit: 4, total: record.memories.count)))
        }

        /// "[취향] 커피는 아이스 아메리카노 (2026-11-03)" as just the memory's own words.
        private func memoryText(_ line: String, _ limit: Int) -> String {
            let text = line.replacingOccurrences(of: #"^\[[^\]]{1,12}\] "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" \(\d{4}-\d{2}-\d{2}\)$"#, with: "", options: .regularExpression)
            return copy.short(text, limit)
        }

        var readLine: String {
            var kinds = ArisWhySteps.reads(in: record.steps).map(copy.read)
            if record.screen, !kinds.contains(copy.read(.screen)) { kinds.insert(copy.read(.screen), at: 0) }
            if record.attached { kinds.append(copy.attachedFile) }
            let what = kinds.isEmpty ? nil : kinds.joined(separator: ", ")
            if record.outsideBefore || record.outsideDuring || record.attached { return copy.label(copy.readLabel, copy.readOutside(what)) }
            if record.screen { return copy.label(copy.readLabel, copy.readScreen(what)) }
            return copy.label(copy.readLabel, what.map(copy.readClean) ?? copy.readNothing)
        }

        var doneLine: String {
            guard let done = evidence.done else { return copy.label(copy.doneLabel, copy.doneUnread) }
            guard !done.isEmpty else { return copy.label(copy.doneLabel, copy.doneNothing) }
            return copy.label(copy.doneLabel, names ? copy.list(done.map(logged).map(copy.quoted), limit: 3) : copy.doneHeld(done.count))
        }

        var cardLine: String? {
            guard !record.cards.isEmpty else { return nil }
            guard names else { return copy.label(copy.cardLabel, copy.cardsHeld(record.cards.count)) }
            let shown = record.cards.prefix(3).map { card in
                (card.title.map(copy.quoted) ?? copy.aCard) + " " + (card.answer.map(copy.answered) ?? copy.answerUnknown)
            }
            return copy.label(copy.cardLabel, copy.list(shown, limit: 3, total: record.cards.count))
        }

        var ruleLine: String {
            var rules: [String] = []
            for card in record.cards {
                let why = askReason(card).whole
                if !rules.contains(why) { rules.append(why) }
            }
            if record.approved.contains(where: { $0.hasPrefix("standing permission") }) { rules.append(copy.ruleStanding) }
            if record.approved.contains(where: { !$0.hasPrefix("standing permission") }) { rules.append(copy.ruleJudged) }
            if let refusal { rules.append(copy.refusedLead(refusal.label, rule: refusal.rule)) }
            if let declinedRule { rules.append(ArisWhyDeclined.ruleNote(declinedRule, korean: asking.korean)) }
            if record.cards.isEmpty, record.autoCount > 0 { rules.append(copy.ruleAuto(record.autoCount)) }
            if record.handsFree, !rules.contains(copy.askHandsFree) { rules.append(copy.ruleHandsFree) }
            return copy.label(copy.ruleLabel, rules.isEmpty ? copy.ruleNothing : rules.joined(separator: " "))
        }

        var insteadLine: String? {
            (refusal?.instead ?? declinedRule?.instead).map { copy.label(copy.insteadLabel, $0) }
        }
    }
}
