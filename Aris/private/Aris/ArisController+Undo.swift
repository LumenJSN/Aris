//
//  ArisController+Undo.swift
//  Aris
//
//  "방금 거 취소해": the last thing Aris did (a file moved, a file trashed, an event added, a to-do, the timer, the volume)
//  is put back by aris-agent, asked the way the 한 일 tab asks it (ArisUndoSteps): the plain request first, and
//  `confirmed` only after a card the helper itself asked for. Deleting an event Aris made
//  and bringing a removed schedule back are asked on that card ("일정 지우기", "예약 다시 살리기"). Only the latest change is
//  undone: when it can't be, Aris says so (QA BUG-18). Failures are said in words, never aris-tools' English (QA BUG-17).
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "undo")

extension ArisController {
    /// The reply said. The user's words may name a kind ("방금 만든 거", "지운 거"): the newest entry of that kind is undone; a
    /// bare "되돌려 줘" takes the newest. Its one card always says exactly what (QA BUG-42 retest: "만든 거" undid a
    /// schedule's removal, so it came back); the reply is built from the entry, never the tool's English line.
    func undoLast(korean: Bool, heard: String = "") async -> String {
        // Nil: aris-agent did not answer. That is not "nothing to undo" (audit turn-1).
        let read = await ArisAgentClient.activity(today: false)
        // Stopped while the list was read: no card, nothing said (audit turn-2).
        guard !Task.isCancelled else { return "" }
        guard let items = read else { return await undoSay(ArisLocalReply.undoUnknown(korean: korean)) }
        // By words alone only this conversation's changes or the last minutes' are reached (ArisUndoWords.reach). Both
        // stores' changes, by time; a bare "되돌려" takes the newest, and says so when that one can't be undone, never
        // reaching past it (third VM run, D3); a taught procedure's run is one change.
        let changes = items.filter { !$0.undone }.map {
            ArisUndoWords.Change(id: $0.id, date: $0.date, summary: $0.summary, action: $0.action, asks: $0.asks, undoable: $0.undoable, unit: $0.unit,
                                 passOver: $0.passOver == true)
        }
        let reach = ArisUndoWords.reach(now: Date(), conversationBegan: conversationBeganAt)
        let kind = ArisUndoWords.kind(in: heard)
        // The text the quick path typed at a caret, when it is the newest change (ArisTypeHere; twelfth VM run, S3u).
        if kind == nil, let typed = ArisTypedHereLog.shared.latest(newerThan: changes.map(\.date).max(), since: reach) {
            ArisTypedHereLog.shared.clear()
            let problem = await ArisAgentClient.undoTyped(typed)
            return await undoSay(problem == nil ? (korean ? "방금 써 넣은 글을 지웠어요." : "Took out the text I just typed.")
                                                : ArisUndoWords.failure(problem ?? "", korean: korean))
        }
        let entry: ArisUndoWords.Candidate, candidates: [ArisUndoWords.Candidate], doubt: Bool
        switch ArisUndoWords.reach(changes, since: reach, kind: kind) {
        case .undo(let picked, let newest, let unsure):
            entry = picked
            candidates = newest.map { [$0] } ?? []
            doubt = unsure
        case .cannot(let summary):
            return await undoSay(ArisUndoWords.cannotLine(summary, korean: korean))
        case .noneOfKind(let others):
            return await undoSay(ArisUndoWords.noneOfKindLine(others, korean: korean))
        case .nothing:
            let older = changes.contains { $0.undoable }
            return await undoSay(older ? ArisUndoWords.nothingRecent(korean: korean) : (korean ? "되돌릴 일이 없어요." : "There's nothing to undo."))
        }
        // A card has the UI's own buttons, so its words are the UI's; what is said follows the request (`korean`).
        let cardKorean = !ArisUIWords.english
        let leftAsItIs = { await self.undoSay(self.cardUnanswered ? ArisCardWait.unansweredLine(korean: korean) : korean ? "그대로 둘게요." : "I'll leave it as it is.") }
        // An ordinary change: Aris's own card names it, and its yes sends the plain request, as the 한 일 tab's and the
        // receipt's Undo do. One the helper asks about itself goes to the helper first (ArisUndoSteps; third VM run,
        // bug B: the yes used to go with `confirmed`, which aris-agent takes only for a card of its own, so every
        // typed undo was refused).
        if ArisUndoSteps.start(asks: entry.asks) == .ownCard {
            let card = ArisUndoWords.card(for: entry, newest: candidates.first, doubt: doubt, korean: cardKorean)
            // Nil: the turn ended over the card, which is no "no": nothing is undone, shown or said.
            guard let yes = await askUser(ArisConfirmation(id: "undo-" + entry.id, title: card.title, detail: card.detail), handsFree: turnHandsFree) else { return "" }
            guard yes else { return await leftAsItIs() }
        }
        var outcome = await undoWaiting(id: entry.id, unit: entry.unit != nil, korean: korean)
        switch ArisUndoSteps.next(after: outcome, entry: entry, newest: candidates.first, doubt: doubt, korean: cardKorean) {
        case .say:
            break
        case .otherEntry:
            log.error("undo: the agent asked about another entry")
            outcome = .failed(korean ? "다른 항목을 물어봐서 멈췄어요." : "It stopped: it asked about another item.")
        case .card(let ask, let echo):
            // The helper's own question (an event Aris made would be deleted, a removed schedule would run again):
            // its card, and only its yes goes back with `confirmed` and the summary the helper gave.
            guard let yes = await askUser(ask, handsFree: turnHandsFree) else { return "" }
            guard yes else { return await leftAsItIs() }
            outcome = await undoWaiting(id: entry.id, confirmed: true, shown: ask, echo: echo, unit: entry.unit != nil, korean: korean)
        }
        let reply: String
        switch outcome {
        case .done(let note):
            log.notice("undone")
            // A taught run whose new document (or another step) no undo takes back: what was undone and what stays.
            // What was undone named as what it was ("Removed the text I typed in TextEdit"), and the lesson of a replay.
            reply = ArisUndoWords.doneReply(note, summary: entry.summary, korean: korean)
        case .needsConfirm:
            log.error("undo: asked again after a yes")
            reply = ArisUndoWords.failure("", korean: korean)
        case .failed(let message):
            // The helper's reason can hold the entry's summary (a title or a file name an AI chose): private, like the
            // other lines that carry the user's text (security review 3, I5).
            log.error("undo failed: \(message, privacy: .private)")
            // Aris's own English line (the helper asked about another entry) is said as it is, like its Korean one.
            reply = message.hasPrefix("It stopped:") ? message : ArisUndoWords.failure(message, korean: korean)
        case .refused:
            log.error("undo refused by aris-agent")
            reply = ArisActivityTab.refusedNotice(english: !korean)
        }
        return await undoSay(reply)
    }

    private func undoSay(_ reply: String) async -> String {
        stats?.firstSound(at: .now)
        setSession(session.answering(reply))
        await speak { await self.speaker.speak(reply) }
        return reply
    }

    /// The undo, and after a few seconds without an answer the notch says why it waits: macOS is likely asking
    /// aris-agent for a folder (QA BUG-17), named when the log says which.
    private func undoWaiting(id: String?, confirmed: Bool = false, shown: ArisConfirmation? = nil, echo: String? = nil, unit: Bool = false,
                             korean: Bool) async -> ArisUndoOutcome {
        let hint = Task { @MainActor [weak self] in
            // The folder is looked up only once the undo has really waited (ArisUndoSteps.asksFolder): asked at the
            // start, the look-up was dropped the moment a quick undo came back, and aris-agent logged a refusal for a
            // connection that was already closed.
            try? await Task.sleep(for: .seconds(ArisUndoWords.hintAfter))
            guard !Task.isCancelled, ArisUndoSteps.asksFolder(waited: ArisUndoWords.hintAfter) else { return }
            let folder = await ArisAgentClient.undoFolder(id: id)
            guard !Task.isCancelled, let self else { return }
            let line = ArisUndoWords.waitingLine(folder: folder, korean: korean)
            log.notice("undo: still waiting (folder prompt?)")
            if self.session.phase == .thinking { self.setSession(self.session.working(line)) }
            ArisActivityModel.shared.waitingNotice = line
        }
        defer {
            hint.cancel()
            ArisActivityModel.shared.waitingNotice = nil
        }
        return await ArisAgentClient.undo(id: id, confirmed: confirmed, shown: shown, echo: echo, unit: unit)
    }

    /// The 한 일 tab's 되돌리기 on entry `id`: the same /undo as "방금 거 취소해". One that deletes an event Aris made or
    /// brings a removed schedule back answers 409; it is asked on the notch's card first (heard and shown, as voice undo
    /// asks), and only a yes repeats it with `confirmed`, for that entry alone. Nil: left as it was (the user said no).
    func undoEntry(_ id: String) async -> ArisUndoOutcome? {
        // Nobody said anything: the tab's button was pressed, so the lines follow the Mac's language, as the tab does.
        let korean = !ArisUIWords.english
        let outcome = await undoWaiting(id: id, korean: korean)
        guard case .needsConfirm(let asked, let summary, let revives) = outcome else { return await sayIfRefused(outcome) }
        guard asked == id else {
            log.error("undo: the agent asked about another entry")
            return .failed(ArisUIWords.text("다른 항목을 물어봐서 멈췄어요.", "It stopped: it asked about another item."))
        }
        let ask = ArisActivityTab.confirmation(id: id, summary: summary, revivesSchedule: revives)
        // A turn of the user's has the notch: nothing is asked or undone; they can tap again once it's over.
        guard let answered = await speakUp(ask.title, { await self.askUser(ask) }) else {
            return .failed(ArisUIWords.text("지금은 대화 중이에요. 끝나고 다시 눌러 주세요.", "A conversation is going on. Press again once it's over."))
        }
        // No, or the card's turn ended before an answer: nothing is undone.
        guard answered == true else { return nil }
        let confirmed = await undoWaiting(id: id, confirmed: true, shown: ask, korean: korean)
        if case .needsConfirm = confirmed { log.error("undo: asked again after a yes") }
        return await sayIfRefused(confirmed)
    }

    /// A refused undo (403) is said out loud as well as shown in the tab: the user tapped and expects to hear why.
    private func sayIfRefused(_ outcome: ArisUndoOutcome) async -> ArisUndoOutcome {
        guard outcome == .refused else { return outcome }
        log.error("undo refused by aris-agent")
        let said = ArisActivityTab.refusedNotice()
        _ = await speakUp(ArisUIWords.text("되돌리기", "Undo"), saying: said) { await self.speak { await self.speaker.speak(said) } }
        return outcome
    }
}
