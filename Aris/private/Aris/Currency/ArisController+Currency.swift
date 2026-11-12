//
//  ArisController+Currency.swift
//  Aris
//
//  A plain currency question answered here, with no AI (as the timer and the time are): the sentence is read on the
//  Mac (ArisCurrencyRead), the rate of exactly that pair comes through aris-agent's POST /currency (aris-tools fetches
//  it, as it fetches a stock's quote for its card), and the line Aris says is made from the card's own number. The
//  working tag says what it is ("환율 확인 중"). No rate (offline, a pair nobody quotes): a plain line and no card.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// The conversion the user's own words ask for, when they are a plain currency question; nil for anything else.
    func currencyAsk(_ words: String) -> ArisCurrencyAsk? {
        ArisCurrencyRead.parse(words, home: ArisCurrencyHome.code())
    }

    /// Reads the rate, shows the card under the line and says it. Nil when the turn was stopped meanwhile.
    func answerCurrency(_ ask: ArisCurrencyAsk, heard: String, korean: Bool) async -> String? {
        log.notice("currency: \(ask.from, privacy: .public) to \(ask.to, privacy: .public), answered here")
        session = session.working(ArisUIWords.status(ArisCurrencyCopy.checking))
        let values = await ArisAgentClient.cardValues(path: "currency", body: ["ask": ask.words], timeout: 25)
        guard !Task.isCancelled else { return nil }
        guard let card = ArisCurrencyCard.answering(ask, values: values) else {
            log.error("currency: no rate for \(ask.from, privacy: .public) to \(ask.to, privacy: .public)")
            // The tag goes with it: nothing was checked, so nothing is ticked.
            session = session.thinking()
            let reply = ArisCurrencyCopy.noRate(korean: korean)
            await sayLocal(reply, heard: heard)
            return reply
        }
        let home = ArisCurrencyHome.code()
        let reply = ArisCurrencyCopy.line(card, korean: korean, home: home)
        ArisCurrencyLiveModel.remember([card.from, card.to], home: home)
        ArisWidgetModel.shared.show(.currency(card), request: ArisWidgetRequest(kind: .currency, symbol: ask.words), reply: reply)
        await sayLocal(reply, heard: heard)
        return reply
    }
}
