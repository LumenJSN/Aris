// Tests for currency conversion (2026-11-11: the user asked "100 중국 돈이 캐나다 달러로 얼마야?" and the card under the
// right spoken line showed USD/CNY, a stock quote): the names table in Korean and English, the plain sentence read
// on the Mac (and what it must leave to the AI), "달러" alone by the Mac's own currency, a correction inside the
// sentence, rounding per currency, aris-tools currency's pure half against a recorded Yahoo reply (the pair asked is
// the pair fetched and shown; the same pair the other way; the cross through the US dollar), the agent's card pick,
// route, function, prompt and tag words, the app's card values and spoken line, and the live card's arithmetic,
// swap, list and keys. Called from main.swift; uses its check(). No network: every reply here is recorded.
import Foundation

func runFxTests() {
    fxNameTests()
    fxSentenceTests()
    fxDollarTests()
    fxCorrectionTests()
    fxNotCurrencyTests()
    fxMathTests()
    fxToolRequestTests()
    fxQuoteTests()
    fxToolCardTests()
    fxStockTests()
    fxAgentTests()
    fxCardTests()
    fxLiveTests()
    fxKeptQuoteTests()
    fxReplyCeilingTests()
}

private typealias Read = ArisCurrencyRead

private func ask(_ said: String, home: String = "CAD") -> ArisCurrencyAsk? { Read.parse(said, home: home) }

private func pair(_ said: String, home: String = "CAD") -> String {
    guard let found = ask(said, home: home) else { return "nil" }
    return "\(ArisCurrencyMath.argument(found.amount)) \(found.from) \(found.to)" + (found.assumed.map { " (\($0))" } ?? "")
}

// MARK: - The names, in both languages

private func fxNameTests() {
    let korean: [(String, String)] = [
        ("원", "KRW"), ("원화", "KRW"), ("한국 돈", "KRW"), ("엔", "JPY"), ("엔화", "JPY"), ("위안", "CNY"), ("위엔", "CNY"), ("중국 돈", "CNY"),
        ("위안화", "CNY"), ("유로", "EUR"), ("파운드", "GBP"), ("캐나다 달러", "CAD"), ("캐달", "CAD"), ("캐네디언 달러", "CAD"), ("호주 달러", "AUD"),
        ("홍콩 달러", "HKD"), ("대만 달러", "TWD"), ("프랑", "CHF"), ("페소", "MXN"), ("루피", "INR"), ("동", "VND"), ("바트", "THB"),
        ("싱가포르 달러", "SGD"), ("미국 달러", "USD"), ("미화", "USD"),
    ]
    for (name, code) in korean {
        check(ArisCurrencyNames.named(name) == .code(code), "fx names: \(name) is \(code)")
    }
    let english: [(String, String)] = [
        ("won", "KRW"), ("yen", "JPY"), ("yuan", "CNY"), ("RMB", "CNY"), ("CNY", "CNY"), ("euros", "EUR"), ("pounds", "GBP"), ("CAD", "CAD"),
        ("Canadian dollars", "CAD"), ("Australian dollar", "AUD"), ("Hong Kong dollars", "HKD"), ("Taiwan dollar", "TWD"), ("francs", "CHF"),
        ("pesos", "MXN"), ("rupees", "INR"), ("dong", "VND"), ("baht", "THB"), ("Singapore dollars", "SGD"), ("US dollars", "USD"), ("usd", "USD"),
    ]
    for (name, code) in english {
        check(ArisCurrencyNames.named(name) == .code(code), "fx names: \(name) is \(code)")
    }
    check(ArisCurrencyNames.named("달러") == .bareDollar && ArisCurrencyNames.named("dollars") == .bareDollar && ArisCurrencyNames.named("Dollar") == .bareDollar,
          "fx names: 달러 and dollar with no country name no one currency")
    check(ArisCurrencyNames.named("캐나다달러") == .code("CAD") && ArisCurrencyNames.named("canadian  DOLLAR") == .code("CAD"),
          "fx names: spacing and case don't matter")
    check(ArisCurrencyNames.named("인덱스") == nil && ArisCurrencyNames.named("주가") == nil && ArisCurrencyNames.named("") == nil && ArisCurrencyNames.named("try") == nil,
          "fx names: anything else names nothing (and “try” is a word, not Turkey's lira)")
    check(ArisCurrencyNames.isCode("CAD") && ArisCurrencyNames.isCode("SEK") && !ArisCurrencyNames.isCode("cad") && !ArisCurrencyNames.isCode("ZZZZ")
          && !ArisCurrencyNames.isCode("QQQ"), "fx names: an ISO code is three capitals the Mac knows, the table's or not")
    check(ArisCurrencyNames.name("CAD", korean: true) == "캐나다 달러" && ArisCurrencyNames.name("CAD", korean: false) == "Canadian dollars"
          && ArisCurrencyNames.name("CAD", korean: false, one: true) == "Canadian dollar" && ArisCurrencyNames.name("KRW", korean: true) == "원"
          && ArisCurrencyNames.name("JPY", korean: false) == "yen", "fx names: each currency as Aris says it")
    check(!ArisCurrencyNames.name("SEK", korean: true).isEmpty && ArisCurrencyNames.name("SEK", korean: false) != "SEK",
          "fx names: a code outside the table is named as macOS names it: \(ArisCurrencyNames.name("SEK", korean: false))")
    check(Set(ArisCurrencyNames.entries.map(\.code)).count == ArisCurrencyNames.entries.count, "fx names: one entry per currency")
    var seen: [String: String] = [:]
    var clash: [String] = []
    for entry in ArisCurrencyNames.entries {
        for word in entry.words {
            let key = ArisCurrencyNames.key(word)
            if let other = seen[key], other != entry.code { clash.append("\(word): \(other) and \(entry.code)") }
            seen[key] = entry.code
            if ArisCurrencyNames.bareDollarWords.contains(key) { clash.append("\(word) is a bare dollar too") }
        }
    }
    check(clash.isEmpty, "fx names: no word names two currencies: \(clash)")
}

// MARK: - The plain sentence, read on the Mac

private func fxSentenceTests() {
    check(pair("100 캐네디언 달러가… 아니, 100 중국 돈이 캐나다 달러로 얼마야?") == "100 CNY CAD",
          "fx sentence: the user's own sentence is 100 CNY in CAD: \(pair("100 캐네디언 달러가… 아니, 100 중국 돈이 캐나다 달러로 얼마야?"))")
    let plain: [(String, String)] = [
        ("100 위안 캐나다 달러로 얼마야", "100 CNY CAD"), ("100위안 캐나다달러로 얼마야?", "100 CNY CAD"), ("how much is 100 CNY in CAD", "100 CNY CAD"),
        ("How much is 100 yuan in Canadian dollars?", "100 CNY CAD"), ("50유로는 원화로?", "50 EUR KRW"), ("엔화 환율 알려 줘", "100 JPY CAD"),
        ("1,000위안은 원으로 얼마예요", "1000 CNY KRW"), ("19.5 파운드 유로로 얼마지", "19.5 GBP EUR"), ("100 usd to krw", "100 USD KRW"),
        ("convert 250 euros to yen", "250 EUR JPY"), ("5만원 캐나다 달러로 얼마야", "50000 KRW CAD"), ("천 엔 원화로 얼마야", "1000 JPY KRW"),
        ("백 위안이 몇 원이야", "100 CNY KRW"), ("3천5백 엔은 캐나다 달러로 얼마", "3500 JPY CAD"), ("what's 20 pounds in euros", "20 GBP EUR"),
        ("아리스 지금 100 유로 원화로 얼마야", "100 EUR KRW"), ("$100 in won", "100 USD KRW (USD)"), ("how many won is 50 euros", "50 EUR KRW"),
        ("100위안 얼마야", "100 CNY CAD"), ("유로 환율", "1 EUR CAD"), ("원 달러 환율 알려 줘", "1 USD KRW (USD)"), ("유로 달러 환율", "1 EUR USD (USD)"),
        ("달러 엔 환율", "1 USD JPY (USD)"), ("2 million won in cad", "2000000 KRW CAD"), ("5k yen to won", "5000 JPY KRW"),
        ("ten euros in won", "10 EUR KRW"), ("1억 원 캐나다 달러로 얼마야", "100000000 KRW CAD"),
    ]
    for (said, expected) in plain {
        check(pair(said) == expected, "fx sentence: “\(said)” is \(expected): \(pair(said))")
    }
    check(pair("100위안 얼마야", home: "KRW") == "100 CNY KRW" && pair("100 yuan how much", home: "USD") == "100 CNY USD",
          "fx sentence: an amount with one currency converts to the Mac's own")
    check(ask("100 캐나다 달러 얼마야") == nil && ask("원 환율", home: "KRW") == nil, "fx sentence: the Mac's own currency alone asks nothing here")
    check(pair("엔화 환율", home: "KRW") == "100 JPY KRW" && pair("위안 환율", home: "KRW") == "1 CNY KRW" && pair("원화 환율") == "1000 KRW CAD",
          "fx sentence: a rate is told for the usual amount (100엔, 1,000원, one of anything else)")
    check(Read.number("5만") == 50_000 && Read.number("3천5백") == 3_500 && Read.number("천오백") == 1_500 && Read.number("1억2천만") == 120_000_000
          && Read.number("1,000") == 1_000 && Read.number("19.5") == 19.5 && Read.number("백") == 100 && Read.number("1.5만") == 15_000,
          "fx sentence: amounts in digits and in Korean numerals")
    check(Read.number("삼사") == nil && Read.number("십백") == nil && Read.number("") == nil && Read.number("0") == nil && Read.number("만만") == nil,
          "fx sentence: what isn't one number isn't an amount")
}

// MARK: - "달러" alone, by the Mac's own currency

private func fxDollarTests() {
    check(pair("달러 환율") == "1 USD CAD (USD)" && pair("100달러 원화로 얼마야") == "100 USD KRW (USD)",
          "fx dollar: on a Canadian Mac a bare 달러 being converted is the US dollar, and the card is told so")
    check(pair("100위안 달러로 얼마야") == "100 CNY CAD (CAD)" && pair("100 yuan in dollars") == "100 CNY CAD (CAD)" && pair("100유로는 몇 달러야") == "100 EUR CAD (CAD)",
          "fx dollar: on a Canadian Mac “…달러로 얼마야” asks for his own dollars, said on the card too")
    check(pair("달러 환율", home: "KRW") == "1 USD KRW" && pair("100위안 달러로 얼마야", home: "KRW") == "100 CNY USD" && pair("100달러 얼마야", home: "KRW") == "100 USD KRW",
          "fx dollar: where no dollar is at home it is the US dollar and nothing is assumed")
    check(pair("100위안 달러로 얼마야", home: "USD") == "100 CNY USD" && ask("달러 환율", home: "USD") == nil && ask("100 dollars how much", home: "USD") == nil,
          "fx dollar: on a US Mac the dollar is the dollar (and alone it asks nothing)")
    check(pair("100 캐나다 달러 달러로 얼마야") == "100 CAD USD (USD)" && pair("100달러 캐나다 달러로 얼마야") == "100 USD CAD (USD)",
          "fx dollar: beside his own dollar the bare one is the other")
    check(pair("유로 달러 환율") == "1 EUR USD (USD)" && pair("원 달러 환율") == "1 USD KRW (USD)" && pair("캐나다 달러 달러 환율") == "1 USD CAD (USD)"
          && pair("달러 원 환율", home: "KRW") == "1 USD KRW", "fx dollar: in “원 달러 환율” the dollar is the US one, whichever way the pair is said")
    check(ask("100달러 달러로 얼마야") == nil, "fx dollar: two bare dollars ask nothing")
    check(pair("what's the exchange rate") == "1 USD CAD (USD)" && ask("what's the rate") == nil && ask("tell me the rate") == nil,
          "fx dollar: in English only “exchange rate” is that question (“the rate” could be any rate)")
    check(pair("환율 알려 줘") == "1 USD CAD (USD)" && pair("환율", home: "KRW") == "1 USD KRW (USD)" && ask("환율 알려 줘", home: "USD") == nil,
          "fx dollar: “환율” alone is the US dollar in the Mac's own money, and the card says which dollar")
    check(ArisCurrencyDollar.resolve(.target, home: "CAD", other: "CNY") == ("CAD", true) && ArisCurrencyDollar.resolve(.source, home: "CAD", other: "KRW") == ("USD", true)
          && ArisCurrencyDollar.resolve(.source, home: "KRW", other: nil) == ("USD", false) && ArisCurrencyDollar.resolve(.target, home: "AUD", other: "JPY") == ("AUD", true),
          "fx dollar: the rule itself")
    check(ArisCurrencyHome.code(Locale(identifier: "en_CA")) == "CAD" && ArisCurrencyHome.code(Locale(identifier: "ko_KR")) == "KRW"
          && ArisCurrencyHome.code(Locale(identifier: "ko_CA")) == "CAD" && ArisCurrencyHome.code(Locale(identifier: "en_US")) == "USD",
          "fx dollar: the Mac's own currency comes from its region")
}

// MARK: - A correction inside the sentence

private func fxCorrectionTests() {
    let corrected: [(String, String)] = [
        ("100 캐나다 달러가 아니 100 위안이 캐나다 달러로 얼마야", "100 CNY CAD"), ("100달러 원화로 아니다 200유로 원화로 얼마야", "200 EUR KRW"),
        ("유로 말고 파운드 환율 알려 줘", "1 GBP CAD"), ("how much is 100 euros in won, no wait, 100 pounds in won", "100 GBP KRW"),
        ("50 yuan in cad, I mean 500 yuan in cad", "500 CNY CAD"), ("100엔, 아니 1000엔 원화로 얼마야", "1000 JPY KRW"),
    ]
    for (said, expected) in corrected {
        check(pair(said) == expected, "fx correction: “\(said)” is its last reading, \(expected): \(pair(said))")
    }
    check(ask("100위안 캐나다 달러로 얼마야 아니 원화로") == nil && ask("100위안 캐나다 달러로 얼마야 아니다") == nil,
          "fx correction: a last part that doesn't say the whole question goes to the AI (never the reading it took back)")
    check(Read.lastReading(["a", "아니", "b", "no", "c", "d"]) == ["c", "d"] && Read.lastReading(["a", "b"]) == ["a", "b"], "fx correction: what follows the last correction")
}

// MARK: - What stays the AI's

private func fxNotCurrencyTests() {
    let others = [
        "달러 인덱스", "달러 인덱스 얼마야", "환율 뉴스 알려 줘", "100달러짜리 선물 추천해 줘", "AAPL", "애플 주가 얼마야", "테슬라 주가", "삼성전자 얼마야",
        "tsla stock price", "KRW=X", "USD/KRW 차트 보여 줘", "달러 왜 올라", "내일 달러 환율 어떨까", "어제 엔화 환율 얼마였어", "100달러 보내 줘",
        "환전 어디서 해", "달러로 얼마야", "이거 달러로 얼마야", "100 달러로 얼마야", "원가 얼마야", "불가능해", "동의해", "who won", "what won",
        "how much is a pound of beef", "매일 아침 달러 환율 알려 줘", "달러 환율 알려 주고 메모에 적어 줘", "5분 타이머", "지금 몇 시야", "얼마야", "100",
        "100 위안", "100위안 캐나다 달러", "비트코인 얼마야", "달러 살까", "1달러 지폐에 누가 있어", "200이면?", "원 달러 환율 전망", "",
        "100 유로 200 파운드 원화로 얼마야", "유로 파운드 엔 환율", "유로로 원화로 얼마야",
    ]
    for said in others {
        check(ask(said) == nil, "fx not currency: “\(said)” is left to the AI: \(pair(said))")
    }
    check(ask(String(repeating: "달러 ", count: 80)) == nil, "fx not currency: a very long sentence is never read here")
    check(ask("100 위안 캐나다 달러로 얼마야", home: "canada") == nil, "fx not currency: with no home currency nothing is read")
}

// MARK: - Rounding, per currency

private func fxMathTests() {
    typealias M = ArisCurrencyMath
    check(M.text(21.3449, code: "CAD") == "21.34" && M.text(21.345001, code: "CAD") == "21.35" && M.text(143_250.4, code: "KRW") == "143,250"
          && M.text(930.6, code: "JPY") == "931" && M.text(1_234.5, code: "USD") == "1,234.50", "fx rounding: two decimals, none for won and yen")
    check(M.text(0.000952, code: "CAD") == "0.00095" && M.text(0.0537, code: "USD") == "0.054" && M.text(0.5, code: "KRW") == "0.50" && M.text(0.1, code: "EUR") == "0.10",
          "fx rounding: a very small amount keeps two meaningful digits (never 0.00)")
    check(M.isRounded(21.3449, code: "CAD") && !M.isRounded(21.34, code: "CAD") && !M.isRounded(100 * 0.2134, code: "CAD") && M.isRounded(143_250.4, code: "KRW")
          && !M.isRounded(143_250, code: "KRW"), "fx rounding: “약” only when the rounding changed the amount")
    check(M.rateText(0.2134) == "0.2134" && M.rateText(1.40231) == "1.4023" && M.rateText(1_432.52) == "1,432.5" && M.rateText(0.000712345) == "0.0007123"
          && M.rateText(109.853) == "109.85" && M.rateText(25_431.7) == "25,432", "fx rounding: a rate has four or five meaningful digits")
    check(M.rateLine(from: "CNY", to: "CAD", rate: 0.2134) == "1 CNY = 0.2134 CAD", "fx rounding: the rate's line")
    check(M.plain(100) == "100" && M.plain(1_000) == "1,000" && M.plain(19.5) == "19.5" && M.argument(1_000) == "1000" && M.argument(19.5) == "19.5",
          "fx rounding: the amount asked is shown as it was given")
    check(M.cross(usdToFrom: 7.1, usdToTo: 1.4) == 1.4 / 7.1 && M.cross(usdToFrom: 0, usdToTo: 1.4) == nil && M.cross(usdToFrom: 7.1, usdToTo: .nan) == nil,
          "fx rounding: the rate through the US dollar is one quote over the other")
    check(M.typed("200") == 200 && M.typed("1,000") == 1_000 && M.typed("19.5") == 19.5 && M.typed(".5") == 0.5 && M.typed("1 000") == 1_000 && M.typed("7.") == 7,
          "fx rounding: an amount typed into the card")
    check(M.typed("") == nil && M.typed("abc") == nil && M.typed("-5") == nil && M.typed("0") == nil && M.typed("1e9") == nil && M.typed("1.2.3") == nil
          && M.typed("9999999999999") == nil, "fx rounding: what isn't an amount isn't one")
    check(M.usualAmount("JPY") == 100 && M.usualAmount("KRW") == 1_000 && M.usualAmount("USD") == 1, "fx rounding: the usual amount of a rate")
}

// MARK: - aris-tools currency: its words

private func fxToolRequestTests() {
    typealias C = ArisCurrency
    func request(_ words: String, home: String = "CAD") -> String {
        guard let found = C.request(words.split(separator: " ").map(String.init), home: home) else { return "nil" }
        return "\(ArisCurrencyMath.argument(found.amount)) \(found.from) \(found.to)" + (found.assumed.map { " (\($0))" } ?? "")
    }
    let read: [(String, String)] = [
        ("100 CNY CAD", "100 CNY CAD"), ("100 cny cad", "100 CNY CAD"), ("50 유로 원", "50 EUR KRW"), ("100 중국 돈 캐나다 달러", "100 CNY CAD"),
        ("1,000 yuan to Canadian dollars", "1000 CNY CAD"), ("19.5 GBP EUR", "19.5 GBP EUR"), ("100 CNY", "100 CNY CAD"), ("USD KRW", "1 USD KRW"),
        ("JPY", "100 JPY CAD"), ("100 SEK NOK", "100 SEK NOK"), ("100 TRY USD", "100 TRY USD"), ("100 위안 달러", "100 CNY CAD (CAD)"),
        ("100 달러 원", "100 USD KRW (USD)"), ("달러", "1 USD CAD (USD)"),
    ]
    for (words, expected) in read {
        check(request(words) == expected, "fx tool: `currency \(words)` is \(expected): \(request(words))")
    }
    check(request("100 달러 원", home: "KRW") == "100 USD KRW" && request("달러", home: "KRW") == "1 USD KRW", "fx tool: where no dollar is at home, nothing is assumed")
    for words in ["", "100", "100 CAD CAD", "100 QQQ CAD", "100 달러 달러", "-5 CNY CAD", "100 CNY CAD KRW", "abc def", "100 인덱스 CAD", "0 CNY CAD"] {
        check(request(words) == "nil", "fx tool: `currency \(words)` is refused: \(request(words))")
    }
    check(C.symbol(from: "CNY", to: "CAD") == "CNYCAD=X" && ArisStock.chartURL(symbol: C.symbol(from: "CNY", to: "CAD"))?.absoluteString.contains("/chart/CNYCAD%3DX?") == true,
          "fx tool: CNY to CAD is Yahoo's CNYCAD=X, read from the chart endpoint the stock card uses")
}

// MARK: - The quote: recorded replies

/// Yahoo's chart reply for CNYCAD=X, recorded by hand on 2026-11-11 (one in four of its points kept).
private let cnyCadChart = """
{"chart":{"result":[{"meta":{"currency":"CAD","symbol":"CNYCAD=X","regularMarketPrice":0.2134,"previousClose":0.2132,"chartPreviousClose":0.2132,
"regularMarketDayHigh":0.2134,"regularMarketDayLow":0.2128,"regularMarketTime":1794456991,"priceHint":4,"shortName":"CNY/CAD","longName":"CNY/CAD",
"exchangeTimezoneName":"Europe/London"},"timestamp":[1794443700,1794445200,1794446700,1794448200,1794449700,1794451200,1794452700,1794454200,1794455700,
1794456600,1794456900,1794456991],"indicators":{"quote":[{"close":[0.21289999783039093,0.21289999783039093,0.21289999783039093,0.21330000460147858,
0.21330000460147858,0.2134000062942505,0.2134000062942505,0.21330000460147858,0.21320000290870667,0.2134000062942505,null,0.2134000062942505]}]}}],"error":null}}
"""

/// A reply in that shape for any pair.
private func chart(_ symbol: String, rate: Double, closes: [Double?], times: [Int]? = nil, previous: Double? = nil, time: Int = 1_794_456_991) -> String {
    let stamps = times ?? closes.indices.map { 1_794_443_700 + $0 * 300 }
    let prices = closes.map { $0.map { String($0) } ?? "null" }.joined(separator: ",")
    let before = previous.map { "\"previousClose\":\($0)," } ?? ""
    return """
    {"chart":{"result":[{"meta":{"currency":"X","symbol":"\(symbol)","regularMarketPrice":\(rate),\(before)"regularMarketTime":\(time)},
    "timestamp":[\(stamps.map(String.init).joined(separator: ","))],"indicators":{"quote":[{"close":[\(prices)]}]}}],"error":null}}
    """
}

private func decoded(_ json: String) -> ArisCurrency.ChartReply? { try? JSONDecoder().decode(ArisCurrency.ChartReply.self, from: Data(json.utf8)) }

/// A fetch from recorded replies that notes which symbols were asked for.
private final class FxFetch {
    var asked: [String] = []
    let replies: [String: String]

    init(_ replies: [String: String]) { self.replies = replies }

    func callAsFunction(_ symbol: String) -> ArisCurrency.ChartReply? {
        asked.append(symbol)
        return replies[symbol].flatMap(decoded)
    }
}

private func fxQuoteTests() {
    typealias C = ArisCurrency
    let direct = FxFetch(["CNYCAD=X": cnyCadChart, "USDCNY=X": chart("USDCNY=X", rate: 6.658, closes: [6.65, 6.66])])
    let quote = C.quote(from: "CNY", to: "CAD") { direct($0) }
    check(direct.asked == ["CNYCAD=X"], "fx quote: the pair asked is the pair fetched (CNYCAD=X, nothing else): \(direct.asked)")
    check(quote?.series.rate == 0.2134 && quote?.computed == false && quote?.series.time == 1_794_456_991 && quote?.series.previousClose == 0.2132,
          "fx quote: its rate, its time, the close before")
    check(quote?.series.points.count == 11 && quote?.series.high == 0.2134000062942505 && quote?.series.low == 0.2128,
          "fx quote: the day's points (a gap left out) and a range that holds them: \(quote?.series.points.count ?? 0)")

    // Yahoo answering for another symbol is no answer: never USD/CNY under a CNY to CAD question.
    let wrong = FxFetch(["CNYCAD=X": cnyCadChart.replacingOccurrences(of: "\"symbol\":\"CNYCAD=X\"", with: "\"symbol\":\"CNY=X\"")])
    check(C.quote(from: "CNY", to: "CAD") { wrong($0) } == nil, "fx quote: a reply for another pair (CNY=X) is refused, whatever its numbers")
    check(C.isReply("KRW=X", for: "USDKRW=X") && C.isReply("usdkrw=x", for: "USDKRW=X") && !C.isReply("CNY=X", for: "CNYCAD=X") && !C.isReply(nil, for: "CNYCAD=X")
          && !C.isReply("KRW=X", for: "CADKRW=X"), "fx quote: only a US-dollar pair goes by its short name")
    let short = FxFetch(["KRW=X": chart("KRW=X", rate: 1_432.5, closes: [1_430, 1_432.5])])
    check(C.quote(from: "USD", to: "KRW") { short($0) }?.series.rate == 1_432.5 && short.asked == ["USDKRW=X", "KRW=X"], "fx quote: USD to KRW, by either of its names")

    // Four decimals are too few for a small rate: the same pair the other way has the digits.
    let coarse = FxFetch(["KRWCAD=X": chart("KRWCAD=X", rate: 0.001, closes: [0.001, 0.001]),
                          "CADKRW=X": chart("CADKRW=X", rate: 1_050, closes: [1_040, 1_060, 1_050], previous: 1_045)])
    let turned = C.quote(from: "KRW", to: "CAD") { coarse($0) }
    check(coarse.asked == ["KRWCAD=X", "CADKRW=X"] && turned?.computed == false && abs((turned?.series.rate ?? 0) - 1 / 1_050) < 1e-12,
          "fx quote: a rate below 0.1 is read from the pair quoted the other way: \(turned?.series.rate ?? 0)")
    check(turned.map { abs($0.series.high - 1 / 1_040) < 1e-12 && abs($0.series.low - 1 / 1_060) < 1e-12 && abs(($0.series.previousClose ?? 0) - 1 / 1_045) < 1e-12 } == true
          && turned?.series.points.count == 3, "fx quote: turned over, the day's high is the low turned over")
    let onlyCoarse = FxFetch(["KRWCAD=X": chart("KRWCAD=X", rate: 0.001, closes: [0.001])])
    check(C.quote(from: "KRW", to: "CAD") { onlyCoarse($0) }?.series.rate == 0.001, "fx quote: with no other way round, the coarse rate is still this pair's")
    let onlyBack = FxFetch(["CADVND=X": chart("CADVND=X", rate: 18_000, closes: [18_000])])
    check(C.quote(from: "VND", to: "CAD") { onlyBack($0) }.map { abs($0.series.rate - 1 / 18_000) < 1e-15 && !$0.computed } == true,
          "fx quote: a pair quoted only the other way is turned over")

    // No quote of the pair either way: through the US dollar, from two quotes, and it says so.
    let stamps = [100, 400, 700, 1_000]
    let cross = FxFetch(["USDTHB=X": chart("USDTHB=X", rate: 36, closes: [35, 36, nil, 36], times: stamps, previous: 35, time: 1_005),
                         "USDMXN=X": chart("USDMXN=X", rate: 18, closes: [17.5, 18, 18, 18], times: stamps, previous: 17.5, time: 1_001)])
    let crossed = C.quote(from: "THB", to: "MXN") { cross($0) }
    check(cross.asked == ["THBMXN=X", "MXNTHB=X", "USDTHB=X", "USDMXN=X"] && crossed?.computed == true && crossed?.series.rate == 0.5,
          "fx quote: THB to MXN is worked out through USD (18 / 36), and marked computed: \(cross.asked)")
    check(crossed?.series.points == [C.Series.Point(time: 100, rate: 17.5 / 35), C.Series.Point(time: 400, rate: 0.5), C.Series.Point(time: 1_000, rate: 0.5)]
          && crossed?.series.time == 1_001 && crossed?.series.previousClose == 0.5,
          "fx quote: its day is each moment both were quoted, its time the older quote's")
    let nothing = FxFetch([:])
    check(C.quote(from: "THB", to: "MXN") { nothing($0) } == nil && C.quote(from: "USD", to: "KRW") { nothing($0) } == nil, "fx quote: no quote, no rate")
    let half = FxFetch(["USDTHB=X": chart("USDTHB=X", rate: 36, closes: [36])])
    check(C.quote(from: "THB", to: "MXN") { half($0) } == nil, "fx quote: one of the two quotes missing is no rate")

    for broken in [cnyCadChart.replacingOccurrences(of: "\"regularMarketPrice\":0.2134,", with: ""),
                   cnyCadChart.replacingOccurrences(of: "\"regularMarketPrice\":0.2134", with: "\"regularMarketPrice\":-1"),
                   cnyCadChart.replacingOccurrences(of: "\"regularMarketTime\":1794456991", with: "\"regularMarketTime\":0"),
                   #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#] {
        check(decoded(broken).flatMap { C.series($0, symbol: "CNYCAD=X") } == nil, "fx quote: a reply without a rate or a time is no quote")
    }
    let wild = cnyCadChart.replacingOccurrences(of: "0.21330000460147858,\n0.21330000460147858", with: "99,\n0.21330000460147858")
        .replacingOccurrences(of: "\"regularMarketDayHigh\":0.2134", with: "\"regularMarketDayHigh\":50")
    let kept = decoded(wild).flatMap { C.series($0, symbol: "CNYCAD=X") }
    check(kept?.points.count == 10 && kept?.high == 0.2134000062942505, "fx quote: a point or a high far off the rate is dropped: \(kept?.points.count ?? 0)")
}

// MARK: - aris-tools currency: the card and the line

private func fxToolCardTests() {
    typealias C = ArisCurrency
    guard let reply = decoded(cnyCadChart), let series = C.series(reply, symbol: "CNYCAD=X") else { return check(false, "fx card: the recorded reply decodes") }
    let request = C.Request(amount: 100, from: "CNY", to: "CAD", assumed: nil)
    let card = C.card(request, C.Quote(series: series, computed: false))
    check(card["from"] as? String == "CNY" && card["to"] as? String == "CAD" && card["amount"] as? Double == 100 && card["rate"] as? Double == 0.2134
          && card["time"] as? Int == 1_794_456_991, "fx card: the pair asked, the amount, the rate and its time")
    check(card["converted"] as? Double == 21.34 && card["about"] as? Bool == false && card["computed"] as? Bool == false && card["assumed"] == nil
          && card["previousClose"] as? Double == 0.2132, "fx card: 100 CNY is 21.34 CAD, exact")
    let points = card["points"] as? [Double] ?? []
    check(points.count == 12 && points.first == 0.2129 && points.last == 0.2134, "fx card: the day's line ends at the rate: \(points)")

    var orlando = Calendar(identifier: .gregorian)
    orlando.timeZone = TimeZone(identifier: "America/New_York")!
    let now = Date(timeIntervalSince1970: 1_794_457_500)
    let line = C.summary(card, timeZone: orlando.timeZone, now: now)
    check(line.hasPrefix("100 CNY (위안 / yuan) = 21.34 CAD (캐나다 달러 / Canadian dollars): say exactly 21.34, with no “약” / “about” (it is exact)"),
          "fx line: the brain is given the card's own number and told to say exactly it: \(line.prefix(120))")
    check(line.contains("Rate: 1 CNY = 0.2134 CAD.") && line.contains("Korean “오늘 밤 11시 16분 기준”") && line.contains("English “as of 11:16 p.m. today”"),
          "fx line: the rate, and its time worded for each language: \(line)")
    check(!line.contains("taken as") && !line.contains("through the US dollar"), "fx line: nothing assumed, nothing computed, nothing said about either")

    let rounded = C.card(C.Request(amount: 333, from: "CNY", to: "CAD", assumed: "CAD"), C.Quote(series: series, computed: true))
    let roundedLine = C.summary(rounded, timeZone: orlando.timeZone, now: now)
    check(rounded["converted"] as? Double == 71.06 && rounded["about"] as? Bool == true && roundedLine.contains("say exactly 71.06, with “약” / “about” (it is rounded)"),
          "fx line: 333 CNY is about 71.06 CAD, said with 약: \(rounded["converted"] ?? "nil")")
    check(rounded["assumed"] as? String == "CAD" && roundedLine.contains("was taken as Canadian dollars (CAD)") && roundedLine.contains("worked out through the US dollar"),
          "fx line: an assumed dollar and a computed rate are both said")
    let won = C.card(C.Request(amount: 100, from: "USD", to: "KRW", assumed: nil),
                     C.Quote(series: C.Series(rate: 1_432.52, time: 1_794_456_991, previousClose: 1_430, high: 1_435, low: 1_428, points: []), computed: false))
    check(won["converted"] as? Double == 143_252 && C.summary(won, timeZone: orlando.timeZone, now: now).contains("= 143,252 KRW") && (won["points"] as? [Double])?.isEmpty == true,
          "fx line: won have no decimals; a day with no points has no line")
    check(C.summary([:]) == "", "fx line: no card, no line")

    // The last quote, kept a moment: the line a brain got and the card read right after are one number.
    let at = Date(timeIntervalSince1970: 1_794_457_000)
    let stored = C.keeping(card, now: at)
    let again = C.kept(stored, for: C.Request(amount: 250, from: "CNY", to: "CAD", assumed: "CAD"), now: at.addingTimeInterval(30))
    check(again?["rate"] as? Double == 0.2134 && again?["amount"] as? Double == 250 && again?["converted"] as? Double == 53.35 && again?["assumed"] as? String == "CAD"
          && again?["keptAt"] == nil, "fx kept: within a minute and a half the same rate answers, for the new amount")
    check(C.kept(stored, for: request, now: at.addingTimeInterval(91)) == nil && C.kept(stored, for: request, now: at.addingTimeInterval(-5)) == nil,
          "fx kept: an older quote (or one from the future) is asked for again")
    check(C.kept(stored, for: C.Request(amount: 100, from: "CAD", to: "CNY", assumed: nil), now: at) == nil && C.kept(nil, for: request, now: at) == nil
          && C.kept(["keptAt": at.timeIntervalSince1970, "from": "CNY", "to": "CAD", "rate": -1.0], for: request, now: at) == nil,
          "fx kept: only this pair's, and only a rate that is one")
    check(C.keptName(request) == "fx-CNYCAD.json", "fx kept: one small file per pair")
}

// MARK: - The stock tool keeps to stocks

private func fxStockTests() {
    check(ArisStock.alias("달러") == nil && ArisStock.alias("환율") == nil && ArisStock.alias("달러 시세") == nil,
          "fx stock: 달러 and 환율 left the stock names (they used to be KRW=X)")
    check(ArisStock.alias("애플")?.symbol == "AAPL" && ArisStock.alias("삼성전자")?.symbol == "005930.KS" && ArisStock.alias("나스닥")?.symbol == "^IXIC"
          && ArisStock.alias("코스피")?.symbol == "^KS11" && ArisStock.alias("비트코인")?.symbol == "BTC-USD" && ArisStock.looksLikeTicker("KRW=X"),
          "fx stock: tickers, names and indices are read as before")
    for words in ["달러", "환율", "달러 환율", "엔화", "위안", "캐나다 달러", "exchange rate", "yen"] {
        check(ArisCurrency.isCurrencyAsk(words), "fx stock: `stock \(words)` is told to use currency")
    }
    for words in ["애플", "삼성전자", "apple", "나스닥", "달러 인덱스", "tesla"] {
        check(!ArisCurrency.isCurrencyAsk(words), "fx stock: `stock \(words)` is still a stock")
    }
    check(ArisCurrency.notAStock.contains("currency <amount> <FROM> <TO>"), "fx stock: the refusal names the command to use")
}

// MARK: - aris-agent: the card's pick, the route, the function, the prompt, the tag

private func fxAgentTests() {
    func pick(_ commands: [String]) -> [String: String]? { ArisWidgetPick.card(commands: commands, tools: "/t") }
    check(pick(["/t currency 100 CNY CAD"]) == ["type": "currency", "ask": "100 CNY CAD"] && pick(["/t currency 50 유로 원 --json"]) == ["type": "currency", "ask": "50 유로 원"],
          "fx agent: a turn that ran `currency` earns the currency card, with the words asked")
    check(pick(["/t stock AAPL", "/t currency 100 CNY CAD"])?["type"] == "currency" && pick(["/t currency 100 CNY CAD", "/t stock AAPL"])?["type"] == "stock",
          "fx agent: the last lookup picks the card")
    check(pick(["/t currency"]) == nil && pick(["/t currency $(x) CAD"]) == nil && pick(["/t currency 1 2 3 4 5 6 7 8"]) == nil, "fx agent: no words or bad ones, no card")
    let attached = ArisWidgetPick.attach(to: "약 21.34 캐나다 달러예요.", commands: ["/t currency 100 CNY CAD"], tools: "/t")
    check(attached.contains("```aris-card\n{\"ask\":\"100 CNY CAD\",\"type\":\"currency\"}\n```"), "fx agent: the block names the card and what was asked, no number: \(attached)")
    check(ArisCurrencyRoute.arguments(request: ["ask": "100 CNY CAD"]) == ["currency", "100", "CNY", "CAD", "--json"]
          && ArisCurrencyRoute.arguments(request: ["ask": "1,000.5 중국 돈 캐나다 달러"]) == ["currency", "1,000.5", "중국", "돈", "캐나다", "달러", "--json"],
          "fx agent: POST /currency hands the words asked back to aris-tools")
    for bad: [String: Any] in [[:], ["ask": ""], ["ask": "-x CNY CAD"], ["ask": "100 CNY; rm"], ["ask": "100 $(id) CAD"], ["ask": 100], ["ask": String(repeating: "a ", count: 40)],
                               ["ask": "100 CNY CAD --set-home"]] {
        let made = ArisCurrencyRoute.arguments(request: bad)
        check(made == nil || made == ["currency", "100", "CNY", "CAD", "--json"], "fx agent: POST /currency takes only an amount and names: \(bad)")
    }
    check(ArisAgentStatus.forCommand("/t currency 100 CNY CAD", tools: "/t") == "환율 확인 중" && ArisAgentStatus.forCommand("/t stock AAPL", tools: "/t") == "주가 가져오는 중",
          "fx agent: the working tag says 환율 확인 중, and 주가 only for a stock")
    check(ArisUIWords.status("환율 확인 중", english: true) == "Checking the rate" && ArisUIWords.status("환율 확인 중", english: false) == "환율 확인 중"
          && ArisCurrencyCopy.checking == ArisCurrencyRoute.status, "fx agent: the tag in English is Checking the rate")

    guard let entry = ArisAPICatalog.entries.first(where: { $0.function.name == "currency" }) else { return check(false, "fx agent: the API brain has a currency function") }
    check(entry.argv(["amount": 100, "from": "CNY", "to": "CAD"]) == ["currency", "100", "CNY", "CAD"] && entry.argv(["from": "달러"]) == ["currency", "달러"]
          && entry.argv(["amount": 19.5, "from": "캐나다 달러", "to": "원"]) == ["currency", "19.5", "캐나다", "달러", "원"],
          "fx agent: the function's arguments become aris-tools' words")
    check(entry.argv([:]) == nil && entry.argv(["from": "$(x)"]) == nil && entry.argv(["amount": true, "from": "CNY"]) == nil && entry.argv(["from": "CNY", "to": 5]) == nil,
          "fx agent: arguments that aren't what the schema says make no call")
    check((entry.function.parameters["required"] as? [String]) == ["from"] && entry.function.description.contains("never stock"), "fx agent: the function says when it is used")

    for prompt in [ArisAgentPrompt.system(tools: "/t"), ArisAgentPrompt.system(tools: "/t", gated: true)] {
        check(prompt.contains("`/t currency <amount> <FROM> <TO>`") && prompt.contains("never `stock`") && prompt.contains("exactly as the tool gives it"),
              "fx agent: each brain is told when to use currency instead of stock, and to say the tool's number")
    }
    check(ArisAgentPrompt.sealed(tools: "/t", handsFree: false).contains("`/t currency <amount> <FROM> <TO>`") || !ArisAgentPrompt.sealed(tools: "/t", handsFree: false).contains("`/t stock"),
          "fx agent: the sealed brain is told about currency wherever it is told about stock")

    // A read like the stock's: free on a clean turn, judged after outside text, never a card that asks.
    check(ArisTurnGate.isOutsideRead(["currency", "100", "CNY", "CAD"]) && !ArisTurnGate.staysLocal(["currency", "100", "CNY", "CAD"])
          && ArisSealedTools.outsideReads.contains("currency"), "fx agent: currency is an outside read, as stock is")
    check(ArisTeammateScope.knownSubcommands.contains("currency") && ArisTeammateScope.needed(forTools: ["currency", "100", "CNY", "CAD"]) == [.web],
          "fx agent: a teammate needs the web for it, as for a stock")
    check(ArisRiskPolicy.risk(of: .shell("/t currency 100 CNY CAD"), tools: "/t", home: "/Users/me") == ArisRiskPolicy.risk(of: .shell("/t stock AAPL"), tools: "/t", home: "/Users/me"),
          "fx agent: the risk gate treats it as it treats a stock (a read: nothing to ask)")
}

// MARK: - The app's card and what Aris says

private func fxCardValues(amount: Double = 100, from: String = "CNY", to: String = "CAD", rate: Double = 0.2134) -> [String: Any] {
    ["amount": amount, "from": from, "to": to, "rate": rate, "time": 1_794_456_991, "points": [0.2129, 0.2133, 0.2134], "high": 0.2134, "low": 0.2128,
     "previousClose": 0.2132, "computed": false, "converted": 1.0, "about": true]
}

private func fxCardTests() {
    let now = Date(timeIntervalSince1970: 1_794_457_500)
    func block(_ json: String) -> String { "한 줄.\n```aris-card\n\(json)\n```" }
    check(ArisWidget.request(in: block(#"{"type":"currency","ask":"100 CNY CAD"}"#)) == ArisWidgetRequest(kind: .currency, symbol: "100 CNY CAD"),
          "fx card: a currency block names what was asked")
    check(ArisWidget.request(in: block(#"{"type":"currency"}"#)) == nil && ArisWidget.request(in: block(#"{"type":"currency","ask":"$(x)"}"#)) == nil
          && ArisWidget.request(in: block(#"{"type":"currency","ask":"--json"}"#)) == nil, "fx card: no words or bad ones, no card")
    let stuffed = ArisWidget.request(in: block(#"{"type":"currency","ask":"100 CNY CAD","rate":9,"converted":900}"#))
    check(stuffed == ArisWidgetRequest(kind: .currency, symbol: "100 CNY CAD"), "fx card: a number a brain wrote into the block reaches nothing")

    guard let card = ArisCurrencyCard.parse(fxCardValues(), now: now) else { return check(false, "fx card: the tool's values parse") }
    check(card.from == "CNY" && card.to == "CAD" && card.amount == 100 && card.rate == 0.2134 && card.convertedText == "21.34" && !card.about,
          "fx card: 21.34 CAD large, from the card's own amount × rate (never a number sent along)")
    check(card.amountText == "100" && card.rateLine == "1 CNY = 0.2134 CAD" && card.highText == "0.2134" && card.lowText == "0.2128" && card.up && card.reference == 0.2132,
          "fx card: 100 CNY, the rate's line, high and low, up against the close before")
    var orlando = Calendar(identifier: .gregorian)
    orlando.timeZone = TimeZone(identifier: "America/New_York")!
    check(card.asOf(now: now, calendar: orlando, english: false) == "오후 11:16 기준" && card.asOf(now: now, calendar: orlando, english: true, locale: Locale(identifier: "en_US")).replacingOccurrences(of: "\u{202F}", with: " ") == "As of 11:16 PM"
          && card.asOf(now: now.addingTimeInterval(86_400 * 2), calendar: orlando, english: false) == "11월 11일 오후 11:16 기준", "fx card: the rate's own time, with its day when it isn't today")
    for (key, value) in [("from", "cny"), ("to", "CNY"), ("rate", 0), ("rate", true), ("amount", -1), ("time", 5), ("from", 3)] as [(String, Any)] {
        check(ArisCurrencyCard.parse(fxCardValues().merging([key: value]) { $1 }, now: now) == nil, "fx card: a bad \(key) (\(value)) is no card")
    }
    let odd = ArisCurrencyCard.parse(fxCardValues().merging(["points": [0.2129, 99.0, -1.0, "x", 0.2133], "high": 50.0, "low": 0.0001, "assumed": "usd", "computed": "yes"]) { $1 }, now: now)
    check(odd?.points == [0.2129, 0.2133] && odd?.high == 0.2134 && odd?.low == 0.2129 && odd?.assumed == nil && odd?.computed == false,
          "fx card: broken points, a range far off the rate and odd flags are dropped: \(odd?.points ?? [])")

    // The pair asked is the pair shown.
    let asked = ArisCurrencyAsk(amount: 100, from: "CNY", to: "CAD", assumed: nil)
    check(ArisCurrencyCard.answering(asked, values: fxCardValues(), now: now) == card, "fx card: the answer to 100 CNY in CAD is that pair's card")
    check(ArisCurrencyCard.answering(asked, values: fxCardValues(from: "USD", to: "CNY", rate: 6.658), now: now) == nil
          && ArisCurrencyCard.answering(asked, values: fxCardValues(from: "CAD", to: "CNY"), now: now) == nil && ArisCurrencyCard.answering(asked, values: nil, now: now) == nil,
          "fx card: values for another pair (USD/CNY, or the pair turned round) are no card at all")
    let assumed = ArisCurrencyCard.answering(ArisCurrencyAsk(amount: 250, from: "CNY", to: "CAD", assumed: "CAD"), values: fxCardValues(), now: now)
    check(assumed?.amount == 250 && assumed?.assumed == "CAD" && assumed?.convertedText == "53.35", "fx card: it carries the sentence's amount and the dollar it assumed")
    check(asked.words == "100 CNY CAD" && ArisCurrencyAsk(amount: 1_000.5, from: "KRW", to: "USD", assumed: nil).words == "1000.5 KRW USD", "fx card: the words asked of aris-tools")

    // The spoken line is the card's number.
    check(ArisCurrencyCopy.line(card, korean: true, home: "CAD") == "100위안은 21.34 캐나다 달러예요." && ArisCurrencyCopy.line(card, korean: false, home: "CAD") == "100 yuan is 21.34 Canadian dollars.",
          "fx line: the user now hears “100위안은 21.34 캐나다 달러예요.”: \(ArisCurrencyCopy.line(card, korean: true, home: "CAD"))")
    let third = card.with(amount: 333)
    check(ArisCurrencyCopy.line(third, korean: true, home: "CAD") == "333위안은 약 71.06 캐나다 달러예요." && ArisCurrencyCopy.line(third, korean: false, home: "CAD") == "333 yuan is about 71.06 Canadian dollars.",
          "fx line: 약 / about only when the amount was rounded")
    guard let won = ArisCurrencyCard.parse(fxCardValues(amount: 1, from: "USD", to: "KRW", rate: 1_432.52).merging(["points": [Double]()]) { $1 }, now: now),
          let loonie = ArisCurrencyCard.parse(fxCardValues(amount: 1, from: "USD", to: "CAD", rate: 1.4023).merging(["points": [Double]()]) { $1 }, now: now) else {
        return check(false, "fx line: other pairs parse")
    }
    check(ArisCurrencyCopy.line(won, korean: true, home: "KRW") == "1달러는 약 1,433원이에요." && ArisCurrencyCopy.line(won, korean: false, home: "KRW") == "1 US dollar is about 1,433 won.",
          "fx line: in Korea the US dollar is just 달러, and won have no decimals: \(ArisCurrencyCopy.line(won, korean: true, home: "KRW"))")
    check(ArisCurrencyCopy.line(loonie, korean: true, home: "CAD") == "1 미국 달러는 약 1.40 캐나다 달러예요." && ArisCurrencyCopy.line(loonie, korean: false, home: "CAD") == "1 US dollar is about 1.40 Canadian dollars.",
          "fx line: where a dollar is at home each dollar is named: \(ArisCurrencyCopy.line(loonie, korean: true, home: "CAD"))")
    check(ArisCurrencyCopy.line(card, korean: true, home: "CAD").contains(card.convertedText) && ArisCurrencyCopy.line(third, korean: false, home: "CAD").contains(third.convertedText),
          "fx line: the number said is the number on the card")
    check(ArisCurrencyCopy.note(card, english: false) == nil && ArisCurrencyCopy.note(loonie.assuming("USD"), english: false) == "미국 달러 기준"
          && ArisCurrencyCopy.note(loonie.assuming("USD"), english: true) == "Assuming US dollars" && ArisCurrencyCopy.note(card.assuming("CAD"), english: false) == "캐나다 달러 기준",
          "fx line: the card's small line says which dollar was assumed")
    let through = ArisCurrencyCard.parse(fxCardValues().merging(["computed": true, "assumed": "USD"]) { $1 }, now: now)
    check(through.flatMap { ArisCurrencyCopy.note($0, english: false) } == "미국 달러 기준 · 미국 달러를 거쳐 계산" && through.flatMap { ArisCurrencyCopy.note($0, english: true) } == "Assuming US dollars · Computed through USD",
          "fx line: and that the rate was worked out through the US dollar")
    check(!ArisCurrencyCopy.noRate(korean: true).isEmpty && ArisCurrencyCopy.noRate(korean: false).hasPrefix("I couldn't get the rate"), "fx line: no rate is a plain line")
}

// MARK: - The live card

private func fxLiveTests() {
    let now = Date(timeIntervalSince1970: 1_794_457_500)
    guard let card = ArisCurrencyCard.parse(fxCardValues(), now: now) else { return check(false, "fx live: the card parses") }
    check(!ArisCurrencyStyle.isLive(setting: nil) && !ArisCurrencyStyle.isLive(setting: "plain") && !ArisCurrencyStyle.isLive(setting: "") && ArisCurrencyStyle.isLive(setting: "live")
          && ArisCurrencyStyle.key == "arisCurrencyCard", "fx live: plain until arisCurrencyCard is live")

    var live = ArisCurrencyLive(card)
    check(live.amountText == "100" && !live.waits, "fx live: at rest it shows the amount asked")
    live.beginEditing()
    live.type("200")
    check(live.card.amount == 200 && live.card.convertedText == "42.68" && live.card.rate == card.rate && live.amountText == "200",
          "fx live: 200 typed is 42.68 CAD at once, from the rate already there")
    live.type("")
    check(live.waits && live.card.amount == 200 && live.amountText == "", "fx live: an empty field waits on the last amount, dimmed")
    live.type("1,500.5")
    check(!live.waits && live.card.amount == 1_500.5 && live.card.convertedText == "320.21" && live.card.about, "fx live: 1,500.5 typed is about 320.21: \(live.card.convertedText)")
    live.type("12abc")
    check(live.waits && live.card.amount == 1_500.5, "fx live: letters change nothing")
    live.endEditing()
    check(live.amountText == "1,500.5" && !live.waits, "fx live: leaving the field keeps the last amount that was one")

    var turned = ArisCurrencyLive(card)
    turned.swap()
    check(turned.card.from == "CAD" && turned.card.to == "CNY" && turned.card.amount == 100 && abs(turned.card.rate - 1 / 0.2134) < 1e-12 && turned.card.convertedText == "468.60",
          "fx live: ↕ makes it 100 CAD in CNY at the inverse rate: \(turned.card.convertedText)")
    check(turned.card.rateLine == "1 CAD = 4.6860 CNY" && abs(turned.card.high - 1 / 0.2128) < 1e-12 && abs(turned.card.low - 1 / 0.2134) < 1e-12
          && turned.card.points.count == 3 && abs(turned.card.points[0] - 1 / 0.2129) < 1e-12 && !turned.card.up,
          "fx live: the day's line is turned over with it (the old low is the new high; up became down)")
    turned.swap()
    check(abs(turned.card.rate - card.rate) < 1e-15 && turned.card.from == "CNY" && turned.card.convertedText == "21.34", "fx live: ↕ twice is where it began")

    check(live.pick("CNY", for: .from) == .none && live.pick("CAD", for: .from) == .swap && live.pick("CNY", for: .to) == .swap,
          "fx live: picking the code it has does nothing; picking the other side's turns the pair round")
    check(live.pick("EUR", for: .from) == .fetch("1500.5 EUR CAD") && live.pick("KRW", for: .to) == .fetch("1500.5 CNY KRW"), "fx live: a new code is one request for the new pair")
    guard let euro = ArisCurrencyCard.parse(fxCardValues(amount: 1, from: "EUR", to: "CAD", rate: 1.52), now: now) else { return check(false, "fx live: the new pair parses") }
    live.arrived(euro)
    check(live.card.from == "EUR" && live.card.amount == 1_500.5 && live.card.convertedText == "2,280.76", "fx live: the new pair arrives with the amount as it is now")

    check(ArisCurrencyLive.choices(home: "CAD", recent: []) == ["CAD", "USD", "KRW", "JPY", "CNY", "EUR", "GBP"]
          && ArisCurrencyLive.choices(home: "KRW", recent: ["THB", "VND", "CHF", "SEK"]) == ["KRW", "USD", "JPY", "CNY", "EUR", "GBP", "THB", "VND", "CHF"],
          "fx live: the list is the Mac's own, the six, and the last three he used")
    check(ArisCurrencyLive.remembering(["THB", "CAD"], in: [], home: "CAD") == ["THB"] && ArisCurrencyLive.remembering(["VND", "CHF"], in: ["THB", "MXN", "INR"], home: "CAD") == ["CHF", "VND", "THB"]
          && ArisCurrencyLive.remembering(["THB"], in: ["VND", "THB"], home: "CAD") == ["THB", "VND"] && ArisCurrencyLive.remembering(["x1", "USD"], in: ["THB"], home: "CAD") == ["THB"],
          "fx live: the last three used, newest first, never one the list always has")
    let list = ["CAD", "USD", "KRW", "JPY", "CNY", "EUR", "GBP"]
    check(ArisCurrencyLive.stepped("CNY", by: 1, in: list, skipping: "CAD") == "EUR" && ArisCurrencyLive.stepped("GBP", by: 1, in: list, skipping: "CAD") == "USD"
          && ArisCurrencyLive.stepped("USD", by: -1, in: list, skipping: "CAD") == "GBP" && ArisCurrencyLive.stepped("THB", by: 1, in: list, skipping: "CAD") == "USD",
          "fx live: ↓ and ↑ on a code go round the list, never onto the other side's code")

    typealias K = ArisCurrencyKeys
    check(K.action(for: "insertTab:", at: .amount) == .move(.from) && K.action(for: "insertTab:", at: .from) == .move(.to) && K.action(for: "insertTab:", at: .to) == .move(.amount)
          && K.action(for: "insertBacktab:", at: .amount) == .move(.to), "fx live: Tab goes amount, the first code, the second, and round")
    check(K.action(for: "cancelOperation:", at: .amount) == .leave && K.action(for: "cancelOperation:", at: .to) == .leave && K.action(for: "insertNewline:", at: .amount) == .leave
          && K.action(for: "insertNewline:", at: .from) == .move(.amount), "fx live: Esc leaves the field; Return leaves it, or comes back from a code")
    check(K.action(for: "moveDown:", at: .from) == .step(1) && K.action(for: "moveUp:", at: .to) == .step(-1) && K.action(for: "moveDown:", at: .amount) == .own
          && K.action(for: "deleteBackward:", at: .amount) == .own, "fx live: ↓ ↑ change a code; in the amount every other key is the field's own")
}

// MARK: - Security review 7, L6: the kept quote is rebuilt from checked values

private func fxKeptQuoteTests() {
    typealias C = ArisCurrency
    guard let reply = decoded(cnyCadChart), let series = C.series(reply, symbol: "CNYCAD=X") else { return check(false, "review-7 L6: the recorded reply decodes") }
    let request = C.Request(amount: 100, from: "CNY", to: "CAD", assumed: nil)
    let at = Date(timeIntervalSince1970: 1_794_457_000)
    let stored = C.keeping(C.card(request, C.Quote(series: series, computed: false)), now: at)
    let soon = at.addingTimeInterval(30)
    let good = C.kept(stored, for: request, now: soon)
    check(good.map { Set($0.keys) } == ["amount", "from", "to", "rate", "time", "converted", "about", "high", "low", "points", "computed", "previousClose"]
          && good?["rate"] as? Double == 0.2134 && good?["time"] as? Int == 1_794_456_991 && (good?["points"] as? [Double])?.count == 12 && good?["computed"] as? Bool == false,
          "review-7 L6: a kept quote comes back as the card's own keys, each from a checked value: \(good?.keys.sorted() ?? [])")
    let planted = stored.merging(["converted": 9_999.0, "about": false, "amount": 5.0, "assumed": "KRW", "name": "<b>", "symbol": "AAPL", "extra": ["x": 1]]) { $1 }
    let rebuilt = C.kept(planted, for: request, now: soon)
    check(rebuilt?["converted"] as? Double == 21.34 && rebuilt?["amount"] as? Double == 100 && rebuilt?["assumed"] == nil && rebuilt?["name"] == nil
          && rebuilt?["symbol"] == nil && rebuilt?["extra"] == nil && rebuilt.map { Set($0.keys) } == good.map { Set($0.keys) },
          "review-7 L6: any other key in the file reaches nothing, and the amount and its result are this request's own")
    let bad: [(String, Any, String)] = [
        ("rate", 1e12, "a rate of a million million"), ("rate", true, "a rate that is true"), ("rate", "0.2134", "a rate in quotes"), ("rate", 0.0, "a rate of nothing"),
        ("time", 1_794_456_991.5, "a time with a fraction"), ("time", 1_794_457_031, "a time after now"), ("time", "1794456991", "a time in quotes"), ("time", 5, "a time before 2000"),
        ("time", true, "a time that is true"), ("points", (0..<97).map { _ in 0.2134 }, "more points than a card has"), ("points", [0.2129, 99.0], "a point far off the rate"),
        ("points", [0.2129, "x"], "a point that is no number"), ("points", "none", "points that are no list"), ("high", 50.0, "a high far off the rate"),
        ("low", 0.0001, "a low far off the rate"), ("low", 0.2135, "a low over the high"), ("previousClose", 99.0, "a close far off the rate"),
        ("previousClose", "0.2132", "a close in quotes"), ("computed", "yes", "a computed that is no true or false"), ("computed", 1, "a computed that is a number"),
        ("keptAt", "now", "a moment that is no number"), ("keptAt", true, "a moment that is true"), ("from", "CAD", "another pair"),
    ]
    for (key, value, what) in bad {
        check(C.kept(stored.merging([key: value]) { $1 }, for: request, now: soon) == nil, "review-7 L6: \(what) is no kept quote")
    }
    for gone in ["rate", "time", "points", "high", "low", "computed", "keptAt"] {
        check(C.kept(stored.filter { $0.key != gone }, for: request, now: soon) == nil, "review-7 L6: without its \(gone) it is no kept quote")
    }
    check(C.kept(stored.filter { $0.key != "previousClose" }, for: request, now: soon)?["previousClose"] == nil
          && C.kept(stored.filter { $0.key != "previousClose" }, for: request, now: soon) != nil, "review-7 L6: a quote with no close before it is still one")

    // The file: one that fails any check is deleted, so the quote is asked for again.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-fx-kept-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent(C.keptName(request))
    func write(_ object: Any) { try? JSONSerialization.data(withJSONObject: object).write(to: file) }
    func there() -> Bool { FileManager.default.fileExists(atPath: file.path) }
    write(stored)
    let read = C.kept(at: file, for: request, now: soon)
    check(read?["rate"] as? Double == 0.2134 && read?["time"] as? Int == 1_794_456_991 && read?["converted"] as? Double == 21.34 && there(),
          "review-7 L6: a good file answers, read back from disk, and stays")
    check(C.kept(at: file, for: request, now: at.addingTimeInterval(91)) == nil && !there(), "review-7 L6: a file older than a minute and a half is deleted")
    write(stored.merging(["rate": 1e13]) { $1 })
    check(C.kept(at: file, for: request, now: soon) == nil && !there(), "review-7 L6: a file with a rate out of range is deleted")
    write(stored.merging(["time": 1_794_457_031]) { $1 })
    check(C.kept(at: file, for: request, now: soon) == nil && !there(), "review-7 L6: a file with a time in the future is deleted")
    try? Data("not json".utf8).write(to: file)
    check(C.kept(at: file, for: request, now: soon) == nil && !there(), "review-7 L6: a file that is no JSON is deleted")
    write(stored.merging(["padding": String(repeating: "x", count: C.mostKeptBytes)]) { $1 })
    check(C.kept(at: file, for: request, now: soon) == nil && !there(), "review-7 L6: a file longer than a kept quote can be is deleted unread")
    let target = folder.appendingPathComponent("elsewhere.json")
    try? JSONSerialization.data(withJSONObject: stored).write(to: target)
    try? FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    check(C.kept(at: file, for: request, now: soon) == nil && !there() && FileManager.default.fileExists(atPath: target.path),
          "review-7 L6: a link in the file's place is removed, never followed (what it pointed at stays)")
    check(C.kept(at: file, for: request, now: soon) == nil, "review-7 L6: no file, no kept quote")
}

// MARK: - Security review 7, L10: a ceiling on what is read of a reply

/// A made-up service: what it answers is set before each request. No network.
private final class FxStubReply: URLProtocol {
    static var status = 200
    static var bytes = 0
    static var saysLength = false
    static var fails = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard !Self.fails, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let headers = Self.saysLength ? ["Content-Length": String(Self.bytes)] : [:]
        guard let response = HTTPURLResponse(url: url, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: headers) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var left = Self.bytes
        while left > 0 {
            let piece = min(left, 32_768)
            client?.urlProtocol(self, didLoad: Data(repeating: 0x20, count: piece))
            left -= piece
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func fxReplyCeilingTests() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FxStubReply.self]
    func get(status: Int = 200, bytes: Int, saysLength: Bool = false, fails: Bool = false, most: Int) -> ArisCappedFetch.Reply {
        (FxStubReply.status, FxStubReply.bytes, FxStubReply.saysLength, FxStubReply.fails) = (status, bytes, saysLength, fails)
        guard let url = URL(string: "https://stub.invalid/v8/finance/chart/CNYCAD=X") else { return .unreachable }
        return ArisCappedFetch.get(URLRequest(url: url), most: most, wait: 5, configuration: configuration)
    }
    // The day recorded for these tests was 5,254 bytes.
    check(get(bytes: 5_254, most: ArisStock.mostReplyBytes) == .ok(Data(repeating: 0x20, count: 5_254)), "review-7 L10: a real-sized reply is read whole")
    check(get(bytes: 1_000, most: 1_000) == .ok(Data(repeating: 0x20, count: 1_000)) && get(bytes: 1_001, most: 1_000) == .tooLong,
          "review-7 L10: a reply is read up to the ceiling, and one byte over is no data")
    check(get(bytes: 2_000_000, most: ArisStock.mostReplyBytes) == .tooLong, "review-7 L10: two megabytes that never said their length are dropped as they grow")
    check(get(bytes: 2_000_000, saysLength: true, most: ArisStock.mostReplyBytes) == .tooLong, "review-7 L10: two megabytes that said so are dropped before any is read")
    check(get(bytes: 100_000, saysLength: true, most: ArisStock.mostReplyBytes) == .ok(Data(repeating: 0x20, count: 100_000)), "review-7 L10: a long day under the ceiling is read")
    check(get(status: 404, bytes: 2_000_000, most: ArisStock.mostReplyBytes) == .refused && get(status: 429, bytes: 10, most: ArisStock.mostReplyBytes) == .refused,
          "review-7 L10: anything but a 200 is refused, its body unread")
    check(get(bytes: 10, fails: true, most: ArisStock.mostReplyBytes) == .unreachable, "review-7 L10: no connection is no answer")
    check(ArisStock.mostReplyBytes >= 10 * 40_000 && ArisStock.mostReplyBytes <= 1_048_576, "review-7 L10: the ceiling is generous for a day's chart and still small: \(ArisStock.mostReplyBytes)")
}
