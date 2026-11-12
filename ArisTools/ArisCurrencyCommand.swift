//
//  ArisCurrencyCommand.swift
//  aris-tools
//
//  `currency <amount> <FROM> <TO> [--json]`: this much of one currency in another, the rate and its time, from the
//  quote of exactly that pair (ArisCurrency; Yahoo Finance's chart endpoint, fetched the way `stock` fetches). A quote
//  just read is kept for a minute and a half in Aris's own folder, so the line a brain was given and the card the app
//  reads right after show one number; what was kept is checked value by value before it is used, and a file that
//  fails is deleted. --json: the notch card's values. No rate (offline, or a pair nobody quotes):
//  a plain line on stderr and no card.
//

import Foundation

/// Where the last quote of each pair is kept a moment (Aris's own folder: nothing a brain asks for writes there).
private let currencyKept = arisFolder.appendingPathComponent("cache")

func currency(_ args: [String]) {
    let json = args.contains("--json")
    guard let request = ArisCurrency.request(args.filter { !$0.hasPrefix("--") }, home: ArisCurrencyHome.code()) else { fail(ArisCurrency.usage) }
    let file = currencyKept.appendingPathComponent(ArisCurrency.keptName(request))
    let card = ArisCurrency.kept(at: file, for: request, now: Date()) ?? currencyFetched(request, keptIn: file)
    guard json else { return print(ArisCurrency.summary(card)) }
    let data = (try? JSONSerialization.data(withJSONObject: card, options: [.sortedKeys])) ?? Data("{}".utf8)
    print(String(decoding: data, as: UTF8.self))
}

/// The card from a fresh quote, kept in `file` for the next call; ends the program with a plain line when there is none.
private func currencyFetched(_ request: ArisCurrency.Request, keptIn file: URL) -> [String: Any] {
    var reached = false
    let quote = ArisCurrency.quote(from: request.from, to: request.to) { symbol in
        stockDecode({ ArisStock.chartURL(symbol: symbol, host: $0) }, as: ArisCurrency.ChartReply.self, reached: &reached)
    }
    guard let quote else {
        fail(reached ? "no rate found for \(request.from) to \(request.to): check the two currencies (ISO codes like CNY, CAD, or their names)"
             : "the rate service didn't answer (offline?); try again in a moment")
    }
    let card = ArisCurrency.card(request, quote)
    // Kept when the folder can be written; under a brain's sandbox it can't, and the next call simply asks again.
    if let data = try? JSONSerialization.data(withJSONObject: ArisCurrency.keeping(card, now: Date())) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? data.write(to: file, options: .atomic)
    }
    return card
}
