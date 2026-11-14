//
//  ArisController+Tasks.swift
//  Aris
//
//  Long work handed to Aris (it runs in the background and Aris speaks up when it is done), and
//  asking the user out loud before the AI acts.
//

import AppKit
import AVFoundation
import Defaults
import os
import SwiftUI

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    // MARK: - Background tasks

    /// The open notch's "다 봤어요": every finished job leaves the done chip (ArisDoneFold); the 기록 tab keeps them.
    func markDoneSeen() {
        seenDone = ArisDoneFold.seenAll(tasks)
    }

    /// A row of the done chip's tray: the saved result in the reader, or the job's answer when nothing was saved.
    func openDone(_ task: ArisBackgroundTask) {
        if let file = jobFiles[task.id] {
            ArisBoard.shared.read(file: file)
        } else {
            ArisBoard.shared.show(ArisReaderDocument.answer(ArisDoneFold.detail(task), question: task.title))
        }
    }

    /// The closed notch shows a check for a few seconds.
    func flashTaskDone() {
        taskJustFinished = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.taskJustFinished = false
        }
    }

    /// Aris speaks up on its own (a task is done, or asks something): the notch opens on `title`, music pauses,
    /// and once `work` is over the notch can close. Nil if the user started a turn of their own meanwhile. `shown`: what
    /// the notch draws when it isn't what is said (a result's Markdown, line breaks kept; the said text is one line).
    /// A turn of the user's that took the notch while `work` ran is never closed from here (audit card-1: a job's card that
    /// ended under his turn put the notch back to idle over his answer).
    func speakUp<T>(_ title: String, saying text: String = "", showing shown: String? = nil, _ work: () async -> T) async -> T? {
        guard session.phase == .idle else { return nil }
        // A question brings its own sound (askUser); only news gets the "done" one.
        if !text.isEmpty && !silentSpeech { ClaudeSounds.play(.done) }
        session = ArisSession.announcing(title, shown ?? text)
        // Aris's own initiative (ArisQuiet): in quiet time it is shown, not said, and music plays on.
        if ArisQuietGate.maySound(.aris) { pauseMusic() }
        let result = await ArisQuietGate.unprompted(title, reading: shown ?? text) { await work() }
        guard ArisCardCover.stillOwn(title: title, heard: session.heard, speaking: session.phase == .speaking) else { return result }
        try? await Task.sleep(for: Self.lingerAfterAnswer)
        guard ArisCardCover.stillOwn(title: title, heard: session.heard, speaking: session.phase == .speaking) else { return result }
        session = session.done()
        resumeMusicIfPaused()
        return result
    }

    /// How long Aris waits for a yes or no; silence is a no. In a conversation the yes is a click or Y: a little longer.
    /// What the log has already said about cards that couldn't listen (ArisCardListenLog).
    private static var cardListenLog = ArisCardListenLog()
    static let answerWait: Duration = .seconds(7)
    static let answerWaitInConversation: Duration = .seconds(15)

    /// How a card's wait ended, read where it ended: the answer slot and the flags below are one for the whole app, and
    /// another card may be up a moment later.
    struct CardWait {
        var allow = false
        /// How a click, key or typed answer came; nil when none did.
        var typed: ArisCardAnswer.Source?
        var heard = false
        var unanswered = false
        /// The agent stopped waiting for it while it was up.
        var ended = false
        /// The user's turn or another card took its place before an answer (ArisCardCover).
        var covered = false

        /// For a job's or the inbox's card (ArisParkedAsk).
        var end: ArisCardEnd {
            if covered { return .covered }
            if ended { return .ended }
            if unanswered { return .unanswered }
            return allow ? .yes : .no
        }
    }

    /// Asks out loud (the exact details are on screen) and listens for yes or no. Silence, anything unclear
    /// or trouble with the microphone is a no. `handsFree`: the card is from a hands-free turn or its job, so (as in any
    /// conversation) only a click or Y says yes; a spoken yes counts only once it held still, or from the final words.
    /// `waiter`: the card is the agent's, which waits for the answer; once it no longer does (its turn ended, the brain's
    /// command was killed), the card closes at once: a card on screen is never dead (QA BUG-33 reopened: the agent's no
    /// came 12 s in while the card stayed up for 110 s). `agentCard`: the agent made the card and takes its answer by
    /// POST /confirm (a job's parked card, an inbox card): its ledger line is the agent's, never a second one from here.
    func askUser(_ ask: ArisConfirmation, handsFree: Bool = false, waiter: Bool = false, agentCard: Bool = false) async -> Bool {
        await askCard(ask, handsFree: handsFree, waiter: waiter, agentCard: agentCard).allow
    }

    /// The same, with how the wait ended. `quiet`: the user asked to see the card (확인 대기): it isn't read aloud and only a
    /// click, Y or N answers it.
    func askCard(_ ask: ArisConfirmation, handsFree: Bool = false, waiter: Bool = false, agentCard: Bool = false, quiet: Bool = false) async -> CardWait {
        // Every card path starts with no "unanswered" left from an earlier card, the countdown's too.
        cardUnanswered = false
        cardAnswerSource = nil
        cardHeardAnswer = false
        cardEnded = false
        let wait: CardWait
        if ask.countdown {
            let allow = await countdownSend(ask)
            wait = CardWait(allow: allow, typed: cardAnswerSource, heard: cardHeardAnswer, unanswered: cardUnanswered, ended: cardEnded)
        } else {
            wait = await cardWait(ask, handsFree: handsFree, waiter: waiter, quiet: quiet)
            publish(wait)
        }
        // Exactly one line per card, on every path, with where its answer came from; an app-handled card (none of the
        // agent's) goes into the agent's audit ledger too (QA BUG-20b live: a click was logged nowhere).
        let source = ArisCardAnswer.source(typed: wait.typed, heard: wait.heard, unanswered: wait.unanswered, ended: wait.ended,
                                           countdown: ask.countdown, cancelled: Task.isCancelled, covered: wait.covered)
        // A countdown's title can name the recipient: its log and ledger line never carry it.
        let logged = ArisCardAnswer.loggedTitle(ask.title, countdown: ask.countdown)
        log.notice("\(ArisCardAnswer.line(allow: wait.allow, source: source), privacy: .public): \(logged, privacy: .private)")
        if ArisCardAnswer.appRecords(waiter: waiter, agentCard: agentCard) { ArisAgentClient.recordCardAnswer(id: ask.id, title: logged, allow: wait.allow, source: source) }
        return wait
    }

    /// The flags the card's caller reads right after its answer (what it says for a card nobody answered).
    private func publish(_ wait: CardWait) {
        cardUnanswered = wait.unanswered
        cardHeardAnswer = wait.heard
        cardEnded = wait.ended
    }

    /// The card itself, without its log line (the countdown's fallback card is part of the countdown's one line).
    func cardAnswer(_ ask: ArisConfirmation, handsFree: Bool, waiter: Bool) async -> Bool {
        if ask.countdown { return await countdownSend(ask) }
        let wait = await cardWait(ask, handsFree: handsFree, waiter: waiter, quiet: false)
        publish(wait)
        return wait.allow
    }

    /// The card is this wait's while it is the one on screen (ArisCardCover).
    private func cardUp(_ ask: ArisConfirmation) -> Bool { ArisCardCover.isUp(card: ask.id, shown: session.question?.id) }

    /// The user's turn or another card took this card's place before an answer: it answered nothing (a job's or the inbox's
    /// then waits in 확인 대기).
    private func covered() -> CardWait {
        log.notice("the card was covered before an answer: nothing is answered")
        return CardWait(unanswered: true, covered: true)
    }

    private func cardWait(_ ask: ArisConfirmation, handsFree: Bool, waiter: Bool, quiet: Bool) async -> CardWait {
        log.notice("asking you: \(ask.title, privacy: .private)")
        typedAnswer = nil
        // The owner's ②A: the card's values as they leaves them go to POST /confirm with their answer (ArisCardEditLedger).
        let editor = ArisCardEditor.shared
        editor.start(ask)
        defer {
            // The answer slot and the Y/N keys are let go, unless another card came up meanwhile: they are that card's.
            if ArisCardCover.ownsKeys(card: ask.id, shown: session.question?.id) {
                typedAnswer = nil
                KeyboardFocus.releaseCard()
            }
            ArisCardEditLedger.record(id: ask.id, fields: ask.fields, values: editor.values(for: ask))
        }
        session = session.asking(ask)
        // Its click hold starts now, also when the card before it had the same id (ArisCardHold).
        ArisCardStill.shared.shown(ask.id)
        // And it starts unread (ArisCardRead).
        ArisCardReadLive.shared.shown(ask.id)
        // Y or N answers the card without hovering it, for as long as it waits (released on the answer or timeout).
        KeyboardFocus.armForCard()
        // The user opened it themselves: nothing is read aloud and no microphone opens.
        // Muted, or Aris's own card in quiet time (ArisQuiet): shown, never read aloud, and no microphone opens either.
        if quiet || !ArisQuietGate.maySpeak(heard: session.heard) { return await clickAnswer(ask, waiter: waiter) }
        if !silentSpeech { ClaudeSounds.play(.approval, starter: ArisQuietGate.starter(heard: session.heard)) }
        // In a conversation, or for a hands-free card, a spoken yes isn't taken (the microphone hears more than the user).
        let voiceYes = ArisConfirmReply.voiceYes(inConversation: conversation.isOpen, handsFree: handsFree)
        // Said in the language the card is drawn in (the request's).
        let english = ArisCardEnglish.isEnglish(request: session.heard) || ArisConfirmReply.isEnglish(ask)
        await speak { await self.speaker.speak(ArisConfirmReply.question(for: ask, voiceYes: voiceYes, english: english)) }
        // The user started a turn while the question was read: the card is gone from the screen, and so is its wait.
        guard cardUp(ask) else { return covered() }
        if let typedAnswer { return CardWait(allow: typedAnswer, typed: cardAnswerSource) }
        guard !Task.isCancelled else { return CardWait() }
        let listener = ArisListener()
        // What was said since the last spoken change of the card ("내일로 바꿔"), which is never an answer.
        var heard = ArisCardListening()
        listener.onText = { heard = heard.heard($0, at: Self.uptime) }
        listener.onLevel = { [weak self] in self?.level = $0 }
        do {
            // Heard from now on: not the question Aris just asked (the detector's phrase may have started with it).
            let source = detector, from = detector?.currentSample
            try await Self.within(Self.startTimeout) { try await listener.start(locale: Self.locale, source: source, from: from) }
            Self.cardListenLog = Self.cardListenLog.started()
        } catch {
            // The speech model still being prepared is an expected state: said once as a notice, not as an error per card.
            let logged = Self.cardListenLog.failed((error as? ArisFailure)?.message ?? "")
            Self.cardListenLog = logged.next
            switch logged.level {
            case .error: log.error("couldn't listen for yes or no: \(String(describing: error), privacy: .public)")
            case .notice: log.notice("no spoken yes or no yet: the speech model is still being prepared (said once; cards take a click, Y or N)")
            case .silent: break
            }
            // A start that timed out may still be opening the microphone: it closes as soon as it has (ArisListener.stopped).
            Task { _ = await listener.stop() }
            level = 0
            // The speech model still preparing or downloading, no speech permission, a microphone error: never a no
            // (QA BUG-54: on a fresh Mac every card said "You said no" about 2 s in). The microphone stays closed and the
            // card waits for a click, Y or N up to its limit.
            return await clickAnswer(ask, waiter: waiter)
        }
        let wait = voiceYes ? Self.answerWait : Self.answerWaitInConversation
        var deadline = ContinuousClock.now + wait
        // How often the agent is asked whether it still waits.
        var checkedWaiter = ContinuousClock.now
        var waiterGone = false
        func waiterEnded() async -> Bool {
            guard waiter, ContinuousClock.now - checkedWaiter >= ArisCardWait.waiterCheck else { return false }
            checkedWaiter = ContinuousClock.now
            guard await ArisAgentClient.stillWaits(ask.id) == false else { return false }
            log.notice("the card's waiter is gone: the card closes")
            waiterGone = true
            return true
        }
        // An editable card waits while the user types (and a little after a change), never past the agent's own limit for it.
        let longest = ContinuousClock.now + .seconds(ArisCardTiming.longestWait)
        while ContinuousClock.now < deadline, !Task.isCancelled, cardUp(ask), typedAnswer == nil, heard.answer(at: Self.uptime, voiceYes: voiceYes) == nil {
            // A spoken change re-shows the card and waits again for the answer; it never sends. Only where a spoken yes
            // may count: in a conversation or for a hands-free card the microphone hears more than the user.
            if !ask.fields.isEmpty, voiceYes, let change = heard.revision(at: Self.uptime, fields: ask.fields, values: editor.values(for: ask)) {
                log.notice("the card changed by voice: \(change.keys.sorted().joined(separator: ","), privacy: .public)")
                withAnimation(ArisGlass.resize) { editor.revise(change) }
                heard = heard.consumed(at: Self.uptime)
                deadline = ContinuousClock.now + wait
            }
            if !ask.fields.isEmpty, editor.keepsWaiting() { deadline = min(longest, max(deadline, ContinuousClock.now + .seconds(1))) }
            if await waiterEnded() { break }
            try? await Task.sleep(for: .milliseconds(200))
        }
        // A click, Y or N given while the card was up is its answer, read before the microphone closes (the slot is the
        // next card's after that). Anything else from a card that is no longer up is no answer at all.
        var typed = ArisCardCover.answer(typedAnswer, card: ask.id, shown: session.question?.id)
        var typedSource = typed == nil ? nil : cardAnswerSource
        let final = (try? await Self.within(Self.stopTimeout, cancelsWork: false) { await listener.stop() }) ?? heard.text
        level = 0
        // Words heard by a card that is no longer up may be the user's new request (its "아니" is not this card's no).
        guard typed != nil || cardUp(ask) else { return covered() }
        log.notice("your answer: “\(final, privacy: .private)”\(typed == nil ? "" : " (typed)", privacy: .public)")
        // Only what came after the last spoken change is the answer.
        var answer = typed ?? heard.answer(at: Self.uptime, voiceYes: voiceYes) ?? heard.final(final, at: Self.uptime, voiceYes: voiceYes)
        let heardAnswer = typed == nil && answer != nil
        // Silence, noise or words that are no clear yes or no never answer the card (QA BUG-39: "알겠어요, 그대로 둘게요"
        // eight seconds after a card nobody answered). The microphone closes; the card waits for a click, Y or N.
        if answer == nil, !Task.isCancelled, !waiterGone {
            log.notice("no clear answer: the card waits for a click, Y or N")
            while answer == nil, ContinuousClock.now < longest, !Task.isCancelled, cardUp(ask) {
                if await waiterEnded() { break }
                try? await Task.sleep(for: .milliseconds(200))
                typed = ArisCardCover.answer(typedAnswer, card: ask.id, shown: session.question?.id)
                if typed != nil { typedSource = cardAnswerSource }
                answer = typed
            }
            if answer == nil, !cardUp(ask), !waiterGone { return covered() }
        }
        // The agent stopped waiting (its turn ended): whatever came after is no answer it can take, nothing runs, and the
        // card says so a moment before it goes (security review of BUG-33).
        if waiterGone {
            answer = nil
            await showEnded(ask)
            return CardWait(unanswered: true, ended: true)
        }
        return CardWait(allow: answer ?? false, typed: typedSource, heard: heardAnswer, unanswered: ArisCardWait.unanswered(answer))
    }

    /// The card answered only by a click, Y or N (no microphone): up to the card's limit, or until its waiter is gone.
    /// Nothing at all is "unanswered", never a no the user gave.
    private func clickAnswer(_ ask: ArisConfirmation, waiter: Bool) async -> CardWait {
        log.notice("the card waits for a click, Y or N (no microphone)")
        let longest = ContinuousClock.now + .seconds(ArisCardTiming.longestWait)
        var checked = ContinuousClock.now
        while typedAnswer == nil, ContinuousClock.now < longest, !Task.isCancelled, cardUp(ask) {
            if waiter, ContinuousClock.now - checked >= ArisCardWait.waiterCheck {
                checked = ContinuousClock.now
                if await ArisAgentClient.stillWaits(ask.id) == false {
                    await showEnded(ask)
                    return CardWait(unanswered: true, ended: true)
                }
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard cardUp(ask) else { return covered() }
        let answer = typedAnswer
        return CardWait(allow: answer ?? false, typed: answer == nil ? nil : cardAnswerSource, unanswered: ArisCardWait.unanswered(answer))
    }

    /// The card's request ended before the user answered: it says so a moment, then goes; nothing runs.
    private func showEnded(_ ask: ArisConfirmation) async {
        guard cardUp(ask) else { return }
        // In the app's one UI language (ArisUILanguage), as every other card line.
        let english = ArisUILanguage.english
        session = session.asking(ArisConfirmation(id: ask.id, title: ask.title, detail: ArisCardWait.endedLine(korean: !english)))
        try? await Task.sleep(for: ArisCardWait.endedShown)
    }
}
