//
//  ArisController+DayEnd.swift
//  Aris
//
//  The day-end summary (ArisDayEnd) in the notch, the way the morning brief shows (ArisController+Brief): on "오늘
//  정리해 줘" its one sentence is the turn's answer, with the folded 목록 row under it, and when the user asked by voice the
//  sentence is said (through the same voice path as every answer); with the day in review on, four or five sentences
//  take its place (ArisDayEndRecap), and "뭐 남았어" gets what is left; typed, or opened from the evening chip, nothing is
//  said and it holds for a few seconds. The history keeps one fixed line, never the titles on the list. 보기 on a
//  waiting row brings that 확인 대기 card back.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "dayend")

extension ArisController {
    /// How long the summary holds the notch when nothing is said (hovering keeps it open longer, as any answer).
    static let dayEndHold: Duration = .seconds(12)

    /// From launch on, the evening is watched for the chip's moment.
    func watchForDayEnd() {
        ArisDayEndModel.shared.watch()
    }

    /// Asked for in a turn: the sentence and its list, in the UI's language whatever the request's was (third VM run:
    /// an English Mac asked in Korean showed 목록 / 할 일 / 내일로 넘기기 beside English chips, and a Korean Mac asked in
    /// English showed "List"). The user's own titles stay as they wrote them. Returns what the history keeps; nil when the turn
    /// was stopped meanwhile.
    func showDayEnd(heard: String) async -> String? {
        let model = ArisDayEndModel.shared
        let english = ArisUIWords.english
        let made = await model.compose(english: english)
        guard !Task.isCancelled else { return nil }
        let sentence = Self.dayEndLine(made, heard: heard)
        model.show(made, line: sentence)
        stats?.firstSound(at: .now)
        setSession(session.answering(sentence))
        // Remembered before the voice starts, so 닫기 or a row's button mid-sentence loses nothing.
        let remembered = ArisDayEndCopy.remembered(english: english)
        recordTurn(heard: heard, reply: remembered)
        if turnTyped {
            try? await Task.sleep(for: Self.dayEndHold)
        } else {
            await speak { await self.speaker.speak(sentence) }
        }
        return Task.isCancelled ? nil : remembered
    }

    /// The evening chip was clicked: the summary comes up by itself, in the app's language, and nothing is said.
    func openDayEnd() {
        let model = ArisDayEndModel.shared
        guard session.phase == .idle, training == nil, !model.opening else { return }
        model.opening = true
        startTurn(.dayEnd) {
            let english = ArisUILanguage.english
            let made = await model.compose(english: english)
            // A turn of the user's began while the facts were read: the chip stays for later.
            guard !Task.isCancelled, session.phase == .idle, training == nil else {
                model.opening = false
                return
            }
            let line = Self.dayEndLine(made, heard: "")
            model.show(made, line: line)
            remember(ArisHistoryEntry(date: Date(), heard: ArisDayEndCopy.title(english: english), reply: ArisDayEndCopy.remembered(english: english)))
            setSession(ArisSession.announcing(ArisDayEndCopy.title(english: english), line))
            try? await Task.sleep(for: Self.dayEndHold)
            guard !Task.isCancelled, model.shown(for: session) != nil else { return }
            setSession(session.done())
        }
    }

    /// What stands above the list and is said: with the day in review on (ArisRecapSwitch) its four or five sentences,
    /// about the whole day or, for "뭐 남았어", what is left (ArisDayEndRecap); else the card's one sentence.
    static func dayEndLine(_ made: ArisDayEndModel.Made, heard: String) -> String {
        guard ArisRecapSwitch.isOn() else {
            let card = made.summary
            return ArisDayEndCopy.answer(card.counts, unread: card.activityUnread, english: card.english, phrase: ArisIntent.phrase(of: heard))
        }
        let focus = ArisRecapAsk.focus(ArisIntent.phrase(of: heard))
        return ArisDayEndRecap.spoken(made.summary, made.facts, focus: focus, now: made.at)
    }

    /// 보기 on a waiting row. The summary's own hold (or its voice) ends first, so the question can come up at once;
    /// the list stays parked behind it.
    func dayEndShow(card id: String) {
        if session.phase == .speaking, ArisDayEndModel.shared.shown(for: session) != nil {
            finishTurn("ok")
            cancel()
        }
        log.notice("day end: a waiting card was asked for")
        openWaitingCard(id)
    }
}
