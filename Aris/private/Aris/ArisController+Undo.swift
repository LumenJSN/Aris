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
        // By words alone only this conversation's changes or the last minutes' are reached (ArisUndoWords.reach).
        let undoable = items.filter { $0.undoable && !$0.undone }
        let reach = ArisUndoWords.reach(now: Date(), conversationBegan: conversationBeganAt)
        let candidates = undoable.filter { $0.date >= reach }.sorted { $0.date > $1.date }
            .map { ArisUndoWords.Candidate(id: $0.id, summary: $0.summary, action: $0.action, asks: $0.asks) }
        guard !candidates.isEmpty || undoable.isEmpty else { return await undoSay(ArisUndoWords.nothingRecent(korean: korean)) }
        let kind = ArisUndoWords.kind(in: heard)
        let (picked, doubt) = ArisUndoWords.pick(candidates, kind: kind)
        guard let entry = picked else {
            return await undoSay(kind == nil ? (korean ? "되돌릴 일이 없어요." : "There's nothing to undo.") : ArisUndoWords.noneOfKindLine(candidates, korean: korean))
        }
        let leftAsItIs = { await self.undoSay(self.cardUnanswered ? ArisCardWait.unansweredLine(korean: korean) : korean ? "그대로 둘게요." : "I'll leave it as it is.") }
        // An ordinary change: Aris's own card names it, and its yes sends the plain request, as the 한 일 tab's and the
        // receipt's Undo do. One the helper asks about itself goes to the helper first (ArisUndoSteps; third VM run,
        // bug B: the yes used to go with `confirmed`, which aris-agent takes only for a card of its own, so every
        // typed undo was refused).
        if ArisUndoSteps.start(asks: entry.asks) == .ownCard {
            let card = ArisUndoWords.card(for: entry, newest: candidates.first, doubt: doubt, korean: korean)
            guard await askUser(ArisConfirmation(id: "undo-" + entry.id, title: card.title, detail: card.detail), handsFree: turnHandsFree) else {
                return await leftAsItIs()
            }
        }
        var outcome = await undoWaiting(id: entry.id, korean: korean)
        switch ArisUndoSteps.next(after: outcome, entry: entry, newest: candidates.first, doubt: doubt, korean: korean) {
        case .say:
            break
        case .otherEntry:
            log.error("undo: the agent asked about another entry")
            outcome = .failed(korean ? "다른 항목을 물어봐서 멈췄어요." : "It stopped: it asked about another item.")
        case .card(let ask, let echo):
            // The helper's own question (an event Aris made would be deleted, a removed schedule would run again):
            // its card, and only its yes goes back with `confirmed` and the summary the helper gave.
            guard await askUser(ask, handsFree: turnHandsFree) else { return await leftAsItIs() }
            outcome = await undoWaiting(id: entry.id, confirmed: true, shown: ask, echo: echo, korean: korean)
        }
        let reply: String
        switch outcome {
        case .done:
            log.notice("undone")
            reply = ArisUndoWords.doneLine(entry.summary, korean: korean)
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
        session = session.answering(reply)
        await speak { await self.speaker.speak(reply) }
        return reply
    }

    /// The undo, and after a few seconds without an answer the notch says why it waits: macOS is likely asking
    /// aris-agent for a folder (QA BUG-17), named when the log says which.
    private func undoWaiting(id: String?, confirmed: Bool = false, shown: ArisConfirmation? = nil, echo: String? = nil, korean: Bool) async -> ArisUndoOutcome {
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
            if self.session.phase == .thinking { self.session = self.session.working(line) }
            ArisActivityModel.shared.waitingNotice = line
        }
        defer {
            hint.cancel()
            ArisActivityModel.shared.waitingNotice = nil
        }
        return await ArisAgentClient.undo(id: id, confirmed: confirmed, shown: shown, echo: echo)
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
        guard let allow = await speakUp(ask.title, { await self.askUser(ask) }) else {
            return .failed(ArisUIWords.text("지금은 대화 중이에요. 끝나고 다시 눌러 주세요.", "A conversation is going on. Press again once it's over."))
        }
        guard allow else { return nil }
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
