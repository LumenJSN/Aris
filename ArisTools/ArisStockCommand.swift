//
//  ArisStockCommand.swift
//  aris-tools
//
//  `stock <symbol|name> [--json]`: the price, today's change, high and low and the quote's time, from Yahoo Finance's
//  public chart endpoint (no key, no account; ArisStock reads the reply). An alias or a ticker as typed goes straight
//  to the chart; anything else through Yahoo's search first. query2 is tried when query1 refuses. A reply is read
//  only up to a ceiling (ArisCappedFetch). --json: the notch card's values.
//

import Foundation

private let stockAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

/// Yahoo answers 429 without a browser's User-Agent. The reply is read up to ArisStock.mostReplyBytes; a longer one
/// is no data (ArisCappedFetch).
private func stockGet(_ url: URL) -> ArisCappedFetch.Reply {
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.setValue(stockAgent, forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    return ArisCappedFetch.get(request, most: ArisStock.mostReplyBytes)
}

/// Tries query1, then query2; `reached` turns true once Yahoo answered at all.
func stockDecode<T: Decodable>(_ make: (String) -> URL?, as type: T.Type, reached: inout Bool) -> T? {
    for host in ["query1", "query2"] {
        guard let url = make(host) else { return nil }
        switch stockGet(url) {
        case .ok(let data):
            reached = true
            return try? JSONDecoder().decode(T.self, from: data)
        case .refused: reached = true
        // No answer, or one too long to be a quote: the other host is asked, and with neither the command says so.
        case .unreachable, .tooLong: continue
        }
    }
    return nil
}

func stock(_ args: [String]) {
    let json = args.contains("--json")
    guard let query = ArisStock.cleaned(args.filter { !$0.hasPrefix("--") }.joined(separator: " ")) else {
        fail("usage: stock <symbol or name> [--json]   (e.g. stock AAPL, stock 삼성전자)")
    }
    // A currency or "환율" is `currency`'s (a conversion is no stock quote); a ticker as typed ("KRW=X") is still read here.
    if !ArisStock.looksLikeTicker(query), ArisCurrency.isCurrencyAsk(query) { fail(ArisCurrency.notAStock) }
    let alias = ArisStock.alias(query)
    var reached = false
    let chart = { (symbol: String) -> [String: Any]? in
        stockDecode({ ArisStock.chartURL(symbol: symbol, host: $0) }, as: ArisStock.ChartReply.self, reached: &reached)
            .flatMap { ArisStock.card($0, displayName: alias?.name) }
    }
    var card: [String: Any]?
    if let alias {
        card = chart(alias.symbol)
    } else {
        if ArisStock.looksLikeTicker(query) { card = chart(query) }
        if card == nil, let symbol = stockDecode({ ArisStock.searchURL(query, host: $0) }, as: ArisStock.SearchReply.self, reached: &reached)
            .flatMap(ArisStock.bestSymbol) {
            card = chart(symbol)
        }
        // "aapl" typed in lower case.
        if card == nil, !ArisStock.looksLikeTicker(query), ArisStock.looksLikeTicker(query.uppercased()) { card = chart(query.uppercased()) }
    }
    guard let card else {
        fail(reached ? "couldn't find a stock called \(query): try its ticker (AAPL, 005930.KS) or its English name"
             : "the stock service didn't answer; try again in a moment")
    }
    guard json else { return print(ArisStock.summary(card)) }
    let data = (try? JSONSerialization.data(withJSONObject: card, options: [.sortedKeys])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}
