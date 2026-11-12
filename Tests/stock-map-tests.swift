// Tests for the stock and map answer cards (the owner's ③C, day range B): aris-tools stock's aliases, Yahoo's replies
// read as data, aris-tools maps --json's pure half, the blocks and the agent's pick, and the app's card values.
// Called from main.swift; uses its check().
import CoreGraphics
import Foundation

func runStockMapTests() {
    stockToolTests()
    stockToolReplyTests()
    stockCardTests()
    mapsToolTests()
    mapCardTests()
    stockMapBlockTests()
    stockMapPickTests()
}

private func cardBlock(_ json: String) -> String { "한 줄.\n```aris-card\n\(json)\n```" }

// MARK: - aris-tools stock: names, tickers, URLs

private func stockToolTests() {
    check(ArisStock.alias("애플")?.symbol == "AAPL" && ArisStock.alias("삼성전자")?.symbol == "005930.KS", "stock: 애플 is AAPL, 삼성전자 is 005930.KS")
    check(ArisStock.alias("삼성전자 주가")?.symbol == "005930.KS" && ArisStock.alias("애플 주식")?.symbol == "AAPL",
          "stock: 주가 / 주식 after the name is left out")
    check(ArisStock.alias("SK 하이닉스")?.symbol == "000660.KS" && ArisStock.alias("하이닉스")?.symbol == "000660.KS", "stock: spaces don't matter")
    check(ArisStock.alias("테슬라")?.symbol == "TSLA" && ArisStock.alias("엔비디아")?.symbol == "NVDA" && ArisStock.alias("코스피")?.symbol == "^KS11"
          && ArisStock.alias("비트코인")?.symbol == "BTC-USD", "stock: a few more aliases")
    check(ArisStock.alias("삼성전자")?.name == "삼성전자" && ArisStock.alias("애플")?.name == nil,
          "stock: a Korean listing keeps its Korean name; a US one takes Yahoo's")
    check(ArisStock.alias("Central") == nil && ArisStock.alias("") == nil, "stock: no alias for anything else")
    check(ArisStock.cleaned("  AAPL ") == "AAPL" && ArisStock.cleaned("-x") == nil && ArisStock.cleaned("") == nil
          && ArisStock.cleaned("a\nb") == nil && ArisStock.cleaned(String(repeating: "a", count: 41)) == nil, "stock: the words are checked")
    for ticker in ["AAPL", "005930.KS", "^GSPC", "BTC-USD", "BRK.B", "KRW=X"] {
        check(ArisStock.looksLikeTicker(ticker), "stock: \(ticker) reads as a ticker")
    }
    for words in ["apple", "Apple Inc", "삼성", "AAPL;rm", "A B"] {
        check(!ArisStock.looksLikeTicker(words), "stock: \(words) isn't a ticker")
    }
    check(ArisStock.isSymbol("005930.KS") && !ArisStock.isSymbol("<b>") && !ArisStock.isSymbol("") && !ArisStock.isSymbol("A/B"),
          "stock: a symbol from Yahoo is checked before it's used")
    let chart = ArisStock.chartURL(symbol: "^GSPC")?.absoluteString ?? ""
    check(chart.hasPrefix("https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?") && chart.contains("interval=5m") && chart.contains("range=1d"),
          "stock: the chart URL escapes the symbol: \(chart)")
    let search = ArisStock.searchURL("samsung electronics")?.absoluteString ?? ""
    check(search.contains("/v1/finance/search?") && search.contains("q=samsung%20electronics") && search.contains("newsCount=0"),
          "stock: the search URL: \(search)")
    check(ArisStock.chartURL(symbol: "a/b") == nil, "stock: no URL for a symbol that isn't one")
}

/// Yahoo's chart reply for Samsung (KRW) and Apple (USD), trimmed.
private let samsungChart = """
{"chart":{"result":[{"meta":{"currency":"KRW","symbol":"005930.KS","regularMarketPrice":193800.0,"chartPreviousClose":201500.0,"previousClose":201500.0,
"regularMarketDayHigh":196500.0,"regularMarketDayLow":179200.0,"regularMarketTime":1793934939,"exchangeTimezoneName":"Asia/Seoul",
"longName":"Samsung Electronics Co., Ltd.","shortName":"SamsungElec","priceHint":2},
"timestamp":[1793925000,1793925300,1793925600,1793925900],"indicators":{"quote":[{"close":[181400.0,null,190000.0,193600.0]}]}}],"error":null}}
"""
private let appleChart = """
{"chart":{"result":[{"meta":{"currency":"USD","symbol":"AAPL","regularMarketPrice":271.42,"chartPreviousClose":268.24,
"regularMarketDayHigh":272.9,"regularMarketDayLow":267.5,"regularMarketTime":1793906760,"longName":"Apple Inc.","shortName":"Apple Inc.","priceHint":2},
"timestamp":[1,2,3],"indicators":{"quote":[{"close":[268.3,270.1,271.5]}]}}],"error":null}}
"""

private func decodeChart(_ json: String) -> ArisStock.ChartReply? { try? JSONDecoder().decode(ArisStock.ChartReply.self, from: Data(json.utf8)) }

private func stockToolReplyTests() {
    guard let samsung = decodeChart(samsungChart), let apple = decodeChart(appleChart) else {
        return check(false, "stock: Yahoo's chart replies decode")
    }
    let card = ArisStock.card(samsung, displayName: "삼성전자")
    check(card?["symbol"] as? String == "005930.KS" && card?["name"] as? String == "삼성전자" && card?["currency"] as? String == "KRW",
          "stock card: the symbol, the alias's name, the currency")
    check(card?["price"] as? Double == 193800 && card?["previousClose"] as? Double == 201500 && card?["high"] as? Double == 196500
          && card?["low"] as? Double == 179200 && card?["time"] as? Int == 1793934939, "stock card: price, previous close, high, low, time")
    check(card?["decimals"] as? Int == 0, "stock card: won have no decimals")
    check((card?["points"] as? [Double]) == [181400, 190000, 193600, 193800], "stock card: gaps left out, ending at the price: \(card?["points"] ?? "nil")")
    let appleCard = ArisStock.card(apple, displayName: nil)
    check(appleCard?["name"] as? String == "Apple" && appleCard?["decimals"] as? Int == 2, "stock card: Yahoo's short name, without Inc.")
    check(appleCard?["previousClose"] as? Double == 268.24, "stock card: chartPreviousClose when previousClose is missing")
    check(ArisStock.card(decodeChart(#"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found"}}}"#)!, displayName: nil) == nil,
          "stock card: Yahoo's not-found is no card")
    let noPrice = appleChart.replacingOccurrences(of: "\"regularMarketPrice\":271.42,", with: "")
    check(decodeChart(noPrice).flatMap { ArisStock.card($0, displayName: nil) } == nil, "stock card: no price, no card")
    let negative = appleChart.replacingOccurrences(of: "271.42", with: "-3")
    check(decodeChart(negative).flatMap { ArisStock.card($0, displayName: nil) } == nil, "stock card: a price below zero is no card")
    let zeroClose = appleChart.replacingOccurrences(of: "268.24", with: "0")
    check(decodeChart(zeroClose).flatMap { ArisStock.card($0, displayName: nil) } == nil, "stock card: no previous close, no change, no card")
    let badHigh = appleChart.replacingOccurrences(of: "272.9", with: "200")
    let clamped = decodeChart(badHigh).flatMap { ArisStock.card($0, displayName: nil) }
    check(clamped?["high"] as? Double == 271.5 && clamped?["low"] as? Double == 267.5, "stock card: the range always holds the price and the points")
    let wild = appleChart.replacingOccurrences(of: "[268.3,270.1,271.5]", with: "[268.3,99999,271.5]")
    check((decodeChart(wild).flatMap { ArisStock.card($0, displayName: nil) }?["points"] as? [Double]) == [268.3, 271.5, 271.42],
          "stock card: a point far off the day's price is dropped")
    let many = (0..<300).map { 100 + Double($0) / 100 }
    let thin = ArisStock.thin(many, to: 96)
    check(thin.count == 96 && thin.first == many.first && thin.last == many.last, "stock card: a long day is thinned to 96 points, ends kept")
    check(ArisStock.thin([1, 2], to: 96) == [1, 2], "stock card: a short day stays")
    let badName = appleChart.replacingOccurrences(of: "\"shortName\":\"Apple Inc.\"", with: "\"shortName\":\"Apple\\u0007\\nInc.\"")
        .replacingOccurrences(of: "\"longName\":\"Apple Inc.\",", with: "")
    check(decodeChart(badName).flatMap { ArisStock.card($0, displayName: nil) }?["name"] as? String == "Apple",
          "stock card: control characters never reach the name")

    let searchReply = #"{"quotes":[{"symbol":"<x>","quoteType":"EQUITY"},{"symbol":"005930.KS-C1","quoteType":"OPTION"},{"symbol":"005930.KS","quoteType":"EQUITY","shortname":"SamsungElec"},{"symbol":"SMSN.IL","quoteType":"EQUITY"}]}"#
    let reply = try? JSONDecoder().decode(ArisStock.SearchReply.self, from: Data(searchReply.utf8))
    check(reply.flatMap(ArisStock.bestSymbol) == "005930.KS", "stock search: the first listing that is one, never an option or a bad symbol")
    check((try? JSONDecoder().decode(ArisStock.SearchReply.self, from: Data(#"{"quotes":[]}"#.utf8))).flatMap(ArisStock.bestSymbol) == nil,
          "stock search: nothing found, no symbol")

    var orlando = Calendar(identifier: .gregorian)
    orlando.timeZone = TimeZone(identifier: "America/New_York")!
    let quoted = appleCard.flatMap { $0["time"] as? Int }.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
    let text = appleCard.map { ArisStock.summary($0, timeZone: orlando.timeZone, now: quoted) } ?? ""
    check(text == "Apple (AAPL): 271.42 USD, +3.18 (+1.19%) today; high 272.90, low 267.50; quote time, said in the answer's own language and never in the other: Korean “오늘 오후 2시 26분 기준”, English “as of 2:26 p.m. today” (the user's own local time: say only the time, never a city or zone).",
          "stock: the brain's line: \(text)")
    // QA live: "오늘 2.43% 올랐어요" beside yesterday's 4 p.m. quote, and an English "This quote is from 4 p.m. yesterday." in a Korean reply.
    let nextMorning = quoted.addingTimeInterval(19 * 3_600)
    let yesterday = appleCard.map { ArisStock.summary($0, timeZone: orlando.timeZone, now: nextMorning) } ?? ""
    check(!yesterday.contains(") today;") && yesterday.contains("on the last trading day (yesterday") && yesterday.contains("never today's or 오늘"),
          "stock: a quote from yesterday is named yesterday's change, never today's or 오늘: \(yesterday)")
    check(yesterday.contains("Korean “어제 오후 2시 26분 기준”") && yesterday.contains("English “as of 2:26 p.m. yesterday”") && !yesterday.contains("as of 2026"),
          "stock: yesterday's quote time comes worded in Korean and in English, for the answer's own language")
    let close = orlando.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 16))!, midnight = orlando.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 0, minute: 32))!
    let closing = ArisStock.reference(of: close, now: midnight, timeZone: orlando.timeZone)
    check(closing.korean == "어제 오후 4시 기준" && closing.english == "as of 4 p.m. yesterday", "stock: yesterday's 4 p.m. close reads 어제 오후 4시 기준, or as of 4 p.m. yesterday")
    let late = ArisStock.reference(of: midnight, now: midnight, timeZone: orlando.timeZone)
    check(late.korean == "오늘 밤 12시 32분 기준" && late.english == "as of 12:32 a.m. today", "stock: a quote just after midnight reads 밤 12시 32분, never 오전 12시")
    let older = quoted.addingTimeInterval(4 * 86_400)
    check(ArisStock.session(of: quoted, now: older, timeZone: orlando.timeZone).contains("2026-11-05")
          && ArisStock.reference(of: quoted, now: older, timeZone: orlando.timeZone).korean == "11월 5일 오후 2시 26분 기준"
          && ArisStock.reference(of: quoted, now: older, timeZone: orlando.timeZone).english == "as of 2:26 p.m. on Nov 5",
          "stock: an older quote names its own day, in both languages")
    check(stockSource("ArisAgent/ArisAgentPrompt.swift").contains("say it in the answer's language only"),
          "stock: the prompt says the quote's time goes in the answer's language")
}

/// A source file of the app, the agent or the tools, as text.
private func stockSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

// MARK: - The stock card (app)

private func stockCardTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let quoteTime = 1793906760.0   // 2026-11-05 14:26 in Orlando
    let now = Date(timeIntervalSince1970: quoteTime + 900)
    let good: [String: Any] = ["symbol": "AAPL", "name": "Apple", "currency": "USD", "price": 271.42, "previousClose": 268.24, "high": 272.9,
                               "low": 267.5, "time": quoteTime, "points": [268.3, 270.1, 271.5, 271.42], "decimals": 2]
    let card = ArisStockCard.parse(good, now: now)
    check(card?.title == "Apple · AAPL" && card?.priceText == "271.42" && card?.changeText == "+3.18 (+1.19%)" && card?.up == true,
          "stock card: title, price, change: \(card?.changeText ?? "nil")")
    check(card?.highText == "272.90" && card?.lowText == "267.50", "stock card: 고가 · 저가")
    check(card?.asOf(now: now, calendar: calendar) == "오후 2:26 기준", "stock card: the quote's own time today: \(card?.asOf(now: now, calendar: calendar) ?? "")")
    check(card?.caption(now: now, calendar: calendar) == "USD · 오후 2:26 기준", "stock card: the currency, then the time")
    let tomorrow = now.addingTimeInterval(86_400)
    check(card?.asOf(now: tomorrow, calendar: calendar) == "11월 5일 오후 2:26 기준", "stock card: an older quote says its day")
    let won: [String: Any] = ["symbol": "005930.KS", "name": "삼성전자", "currency": "KRW", "price": 193800, "previousClose": 201500, "high": 196500,
                              "low": 179200, "time": quoteTime, "points": [181400, 193800], "decimals": 0]
    let samsung = ArisStockCard.parse(won, now: now)
    check(samsung?.priceText == "193,800" && samsung?.changeText == "−7,700 (−3.82%)" && samsung?.up == false,
          "stock card: won with thousands, a fall with a minus sign: \(samsung?.changeText ?? "nil")")
    check(ArisStockCard.parse(["symbol": "X", "name": "X", "price": 1, "previousClose": 1, "high": 1, "low": 1, "time": quoteTime], now: now)?.title == "X",
          "stock card: a name that is the symbol is said once")

    func with(_ key: String, _ value: Any?) -> ArisStockCard? {
        var object = good
        object[key] = value
        return ArisStockCard.parse(object, now: now)
    }
    check(with("price", "271") == nil && with("price", -1) == nil && with("price", true) == nil && with("price", nil) == nil,
          "stock card: a price that isn't a positive number drops the card")
    check(with("previousClose", 0) == nil && with("high", 260) == nil && with("low", 280) == nil, "stock card: a range that doesn't hold the price drops it")
    check(with("symbol", "<b>") == nil && with("symbol", 7) == nil && with("name", "  ") == nil, "stock card: symbol and name are checked")
    check(with("time", now.timeIntervalSince1970 + 3 * 86_400) == nil && with("time", "x") == nil, "stock card: a quote from the future drops it")
    check(with("currency", "usd1")?.currency == nil && with("currency", "usd1")?.caption(now: now, calendar: calendar) == "오후 2:26 기준",
          "stock card: a currency that isn't one is left off")
    check(with("name", "Apple\nInc")?.name == "Apple Inc", "stock card: no control characters in the name")
    check(with("points", [268.3, "x", 271.5, Double.infinity, true])?.points == [268.3, 271.5], "stock card: bad points are left out")
    check(with("decimals", 9)?.decimals == 2 && with("decimals", nil)?.decimals == 2, "stock card: decimals 0…4, else 2")

    let spark = ArisStockCard.spark([1, 3, 2], previous: 2, size: CGSize(width: 100, height: 60), inset: 8)
    check(spark.first?.x == 2 && spark.last?.x == 98 && spark[1].y == 8 && spark[0].y == 52, "stock card: the sparkline spans the width, high at the top")
    let below = ArisStockCard.spark([5, 6], previous: 4, size: CGSize(width: 100, height: 60), inset: 8)
    check(below[0].y < 52 && below[1].y == 8, "stock card: the previous close is in the chart's range (as the mockup draws it)")
    let flat = ArisStockCard.spark([5, 5, 5], previous: 5, size: CGSize(width: 100, height: 60), inset: 8)
    check(flat.allSatisfy { $0.y == 30 }, "stock card: a flat day is a flat middle line")
    check(ArisStockCard.spark([5], previous: 5, size: CGSize(width: 100, height: 60), inset: 8).isEmpty, "stock card: one point is no line")
}

// MARK: - aris-tools maps --json

private func mapsToolTests() {
    check(ArisMapsCard.request(["search", "Central", "Library", "--json"]) == .search("Central Library"), "maps: search words")
    check(ArisMapsCard.request(["directions", "here", "Central Library", "--json"]) == .directions(from: nil, to: "Central Library")
          && ArisMapsCard.request(["directions", "현재 위치", "Central Library", "--json"]) == .directions(from: nil, to: "Central Library"),
          "maps: directions from here")
    check(ArisMapsCard.request(["directions", "Union Station", "Central Library", "--json"]) == .directions(from: "Union Station", to: "Central Library"),
          "maps: directions from a place")
    check(ArisMapsCard.request(["directions", "a", "--json"]) == nil && ArisMapsCard.request(["search", "--json"]) == nil
          && ArisMapsCard.request(["nearby", "x", "--json"]) == nil, "maps: anything else is refused")
    let current = ArisMapsCard.Point(latitude: 43.66, longitude: -79.39), home = ArisMapsCard.Point(latitude: 43.7, longitude: -79.4)
    check(ArisMapsCard.origin(authorized: true, current: current, home: home)?.kind == .current, "maps: the current location when allowed")
    check(ArisMapsCard.origin(authorized: false, current: current, home: home)?.kind == .home
          && ArisMapsCard.origin(authorized: true, current: nil, home: home)?.kind == .home, "maps: home otherwise (never asks for permission)")
    check(ArisMapsCard.origin(authorized: false, current: nil, home: nil) == nil, "maps: no origin without either")
    check(ArisMapsCard.origin(authorized: false, current: nil, home: ArisMapsCard.Point(latitude: 200, longitude: 0)) == nil, "maps: a broken home is no origin")
    check(ArisMapsCard.primary(["walk": 480, "car": 240, "transit": 540]) == "walk" && ArisMapsCard.primary(["walk": 3_000, "car": 900]) == "car"
          && ArisMapsCard.primary(["walk": 3_000, "transit": 1_500]) == "transit" && ArisMapsCard.primary(["walk": 3_000]) == "walk"
          && ArisMapsCard.primary([:]) == nil, "maps: on foot when it's 20 minutes or less, else by car, else transit")
    check(ArisMapsCard.primary(["walk": 480, "car": 240]) == ArisMapCard.primary([.walk: 480, .car: 240])?.rawValue
          && ArisMapsCard.primary(["walk": 3_000, "car": 900]) == ArisMapCard.primary([.walk: 3_000, .car: 900])?.rawValue,
          "maps: aris-tools and the app pick the same way")
    let route = (0..<500).map { ArisMapsCard.Point(latitude: 43 + Double($0) / 1000, longitude: -79) }
    let thin = ArisMapsCard.thin(route, to: 100)
    check(thin.count == 100 && thin.first == route.first && thin.last == route.last, "maps: a long route is thinned, ends kept")
    let place = ArisMapsCard.Point(latitude: 43.6644, longitude: -79.3997)
    let made = ArisMapsCard.card(name: "Central Library", address: "100 Main St, Orlando", place: place,
                                 origin: (current, .current), eta: ["walk": 480, "car": 240, "transit": 540], distance: ["walk": 650, "car": 1_100],
                                 route: [current, place])
    check(made["name"] as? String == "Central Library" && made["mode"] as? String == "walk" && (made["origin"] as? [String: Any])?["kind"] as? String == "current"
          && (made["eta"] as? [String: Double])?["car"] == 240 && (made["route"] as? [[Double]])?.count == 2, "maps: the card's values")
    check(ArisMapsCard.summary(made) == "Central Library (100 Main St, Orlando): on foot 8 min (650 m), by car 4 min, by transit 9 min, from the current location.",
          "maps: the brain's line: \(ArisMapsCard.summary(made))")
    let far = ArisMapsCard.card(name: "X", address: nil, place: place, origin: nil, eta: [:], distance: [:], route: [])
    check(ArisMapsCard.summary(far) == "X." && far["origin"] == nil, "maps: with no origin, only the place")
}

// MARK: - The map card (app)

private func mapCardTests() {
    let good: [String: Any] = ["name": "Central Library", "address": "100 Main St, Orlando", "latitude": 43.6644, "longitude": -79.3997,
                               "origin": ["latitude": 43.6596, "longitude": -79.3972, "kind": "current"],
                               "eta": ["walk": 480, "car": 240, "transit": 540], "distance": ["walk": 650, "car": 1_100],
                               "route": [[43.6596, -79.3972], [43.6620, -79.3990], [43.6644, -79.3997]]]
    let card = ArisMapCard.parse(good)
    check(card?.name == "Central Library" && card?.address == "100 Main St, Orlando" && card?.route.count == 3, "map card: place, address, route")
    check(card?.primary == .walk && card?.primaryLine?.eta == "8분" && card?.primaryLine?.how == "걸어서 · 650m", "map card: 8분, 걸어서 · 650m")
    check(card?.othersLine == "차로 4분 · 대중교통 9분", "map card: the other ways: \(card?.othersLine ?? "nil")")
    check(ArisMapCard.duration(59) == "1분" && ArisMapCard.duration(3_900) == "1시간 5분" && ArisMapCard.duration(7_200) == "2시간"
          && ArisMapCard.duration(0) == "1분", "map card: durations")
    check(ArisMapCard.distance(650) == "650m" && ArisMapCard.distance(4_240) == "4.2km" && ArisMapCard.distance(12_400) == "12km",
          "map card: distances")
    let url = card?.mapsURL?.absoluteString ?? ""
    check(url == "maps://?daddr=43.6644,-79.3997&dirflg=w", "map card: Maps opens the way there on foot: \(url)")
    var fromHome = good
    fromHome["origin"] = ["latitude": 43.7, "longitude": -79.4, "kind": "home"]
    fromHome["eta"] = ["car": 900]
    let homeURL = ArisMapCard.parse(fromHome)?.mapsURL?.absoluteString ?? ""
    check(homeURL == "maps://?saddr=43.7,-79.4&daddr=43.6644,-79.3997&dirflg=d", "map card: from home, Maps starts there: \(homeURL)")

    func with(_ key: String, _ value: Any?) -> ArisMapCard? {
        var object = good
        object[key] = value
        return ArisMapCard.parse(object)
    }
    check(with("name", "") == nil && with("name", 3) == nil && with("latitude", 91) == nil && with("longitude", "x") == nil
          && with("latitude", true) == nil, "map card: no name or a broken place drops it")
    check(with("eta", ["walk": -5, "car": 1e9, "transit": "x", "boat": 3])?.eta.isEmpty == true, "map card: bad times are left out")
    check(with("eta", ["walk": -5])?.primaryLine == nil && with("eta", ["walk": -5])?.othersLine == nil, "map card: no time, no ETA line")
    check(with("route", [[43.66, -79.39], [500, 0], "x", [1]])?.route.count == 1, "map card: bad route points are left out")
    check(with("origin", ["latitude": 999, "longitude": 0, "kind": "current"])?.origin == nil
          && with("origin", ["latitude": 43, "longitude": -79, "kind": "moon"])?.origin == nil, "map card: a broken origin is left out")
    check(with("address", "100 Main\u{0007} St")?.address == "100 Main St" && with("address", 5)?.address == nil,
          "map card: the address is plain text")
    check(with("name", "A&daddr=0,0")?.mapsURL?.absoluteString.contains("A&") == false, "map card: the name never goes into the link")

    // The snapshot's region: the place (and the start, when near) in the part the label doesn't cover.
    guard let card else { return }
    let region = card.region(width: 416, height: 216, covered: 76)
    let top = region.center.latitude + region.latitudeDelta / 2, bottom = region.center.latitude - region.latitudeDelta / 2
    let visibleBottom = top - region.latitudeDelta * (216 - 76) / 216
    let points = [card.place] + (card.origin.map { [$0] } ?? [])
    check(points.allSatisfy { $0.latitude < top && $0.latitude > visibleBottom } && bottom < visibleBottom,
          "map card: the place and the start sit above the label")
    let halfWidth = region.longitudeDelta / 2
    check(points.allSatisfy { abs($0.longitude - region.center.longitude) < halfWidth }, "map card: and inside the width")
    let lone = ArisMapCard.parse(["name": "X", "latitude": 37.5, "longitude": 127.0])
    check(lone.map { $0.region(width: 416, height: 216, covered: 76).latitudeDelta > 0.004 } == true && lone?.mapsURL?.absoluteString == "maps://?daddr=37.5,127.0",
          "map card: a lone place gets a street-level view and a plain link")
}

// MARK: - The blocks

private func stockMapBlockTests() {
    check(ArisWidget.request(in: cardBlock(#"{"type":"stock","symbol":"AAPL"}"#)) == ArisWidgetRequest(kind: .stock, symbol: "AAPL"),
          "widget: a stock block names its symbol")
    check(ArisWidget.request(in: cardBlock(#"{"type":"stock","symbol":"삼성전자"}"#))?.symbol == "삼성전자", "widget: or the name said")
    check(ArisWidget.request(in: cardBlock(#"{"type":"stock"}"#)) == nil && ArisWidget.request(in: cardBlock(#"{"type":"stock","symbol":"$(x)"}"#)) == nil
          && ArisWidget.request(in: cardBlock(#"{"type":"stock","symbol":"--json"}"#)) == nil, "widget: no symbol or a bad one, no card")
    check(ArisWidget.request(in: cardBlock(#"{"type":"todo"}"#) + "\n" + cardBlock(#"{"type":"stock","symbol":"<b>"}"#)) == nil,
          "widget: a last stock block with a bad symbol isn't covered by an earlier card")
    let stuffed = ArisWidget.request(in: cardBlock(#"{"type":"stock","symbol":"AAPL","price":1,"place":"Seoul"}"#))
    check(stuffed == ArisWidgetRequest(kind: .stock, symbol: "AAPL"), "widget: numbers and other keys in a stock block are ignored")
    check(ArisWidget.request(in: cardBlock(#"{"type":"map","place":"Central Library"}"#)) == ArisWidgetRequest(kind: .map, place: "Central Library"),
          "widget: a map block names its place")
    check(ArisWidget.request(in: cardBlock(#"{"type":"map","place":"Central Library","from":"Union Station"}"#))
          == ArisWidgetRequest(kind: .map, place: "Central Library", from: "Union Station"), "widget: and where from")
    check(ArisWidget.request(in: cardBlock(#"{"type":"map","place":"Central Library","from":"여기"}"#))?.from == nil, "widget: from here is no from")
    check(ArisWidget.request(in: cardBlock(#"{"type":"map"}"#)) == nil && ArisWidget.request(in: cardBlock(#"{"type":"map","place":"a;b"}"#)) == nil
          && ArisWidget.request(in: cardBlock(#"{"type":"map","place":"X","from":"$(y)"}"#)) == nil, "widget: a map block needs a real place")
    let screen = ArisWidget.presentation(in: cardBlock(#"{"type":"map","place":"Central Library"}"#), untrusted: true)
    check(screen?.request.place == "Central Library" && screen?.actions == false, "widget: an untrusted turn's map card shows (opening Maps waits for a click)")
    check(ArisWidget.symbol("BTC-USD") == "BTC-USD" && ArisWidget.symbol("^GSPC") == "^GSPC" && ArisWidget.symbol("KRW=X") == "KRW=X"
          && ArisWidget.symbol("-x") == nil && ArisWidget.symbol(String(repeating: "a", count: 41)) == nil, "widget: symbols")
    check(ArisWidget.mapPlace("McDonald's, 100 Main St.") != nil && ArisWidget.mapPlace(String(repeating: "가", count: 81)) == nil
          && ArisWidget.mapPlace("여기") == nil, "widget: map places")
}

// MARK: - The agent's pick and routes

private func stockMapPickTests() {
    let pick = { (commands: [String]) in ArisWidgetPick.card(commands: commands, tools: "/t") }
    check(pick(["/t stock AAPL"]) == ["type": "stock", "symbol": "AAPL"] && pick(["/t stock 삼성전자 --json"]) == ["type": "stock", "symbol": "삼성전자"],
          "pick: a stock command earns the stock card")
    check(pick(["/t stock"]) == nil, "pick: a bare stock earns nothing")
    check(pick(["/t maps search \"Central Library\" --json"]) == ["type": "map", "place": "Central Library"], "pick: a maps lookup earns the map card")
    check(pick(["/t maps directions here \"Central Library\" --json"]) == ["type": "map", "place": "Central Library"], "pick: from here")
    check(pick(["/t maps directions \"Union Station\" \"Central Library\" --json"]) == ["type": "map", "place": "Central Library", "from": "Union Station"],
          "pick: from somewhere")
    check(ArisWidgetPick.here == ArisMapsLink.here, "pick: here means what aris-tools maps takes it to mean")
    check(pick(["/t maps search \"Central Library\""]) == nil && pick(["/t maps directions here X"]) == nil, "pick: Maps opened is no card")
    let attached = ArisWidgetPick.attach(to: "애플은 271달러예요.", commands: ["/t stock 애플"], tools: "/t")
    check(ArisWidget.request(in: attached) == ArisWidgetRequest(kind: .stock, symbol: "애플"), "pick: the app reads the agent's stock block")
    check(ArisWidgetPick.stockArguments(request: ["symbol": "AAPL"]) == ["stock", "AAPL", "--json"]
          && ArisWidgetPick.stockArguments(request: [:]) == nil && ArisWidgetPick.stockArguments(request: ["symbol": "-x"]) == nil
          && ArisWidgetPick.stockArguments(request: ["symbol": 5]) == nil, "pick: POST /stock runs aris-tools stock <symbol> --json, or nothing")
    check(ArisWidgetPick.mapsArguments(request: ["place": "Central Library"]) == ["maps", "search", "Central Library", "--json"]
          && ArisWidgetPick.mapsArguments(request: ["place": "Central Library", "from": "Union Station"])
             == ["maps", "directions", "Union Station", "Central Library", "--json"]
          && ArisWidgetPick.mapsArguments(request: ["place": "X", "from": NSNull()]) == ["maps", "search", "X", "--json"],
          "pick: POST /maps runs aris-tools maps … --json")
    check(ArisWidgetPick.mapsArguments(request: [:]) == nil && ArisWidgetPick.mapsArguments(request: ["place": "a;b"]) == nil
          && ArisWidgetPick.mapsArguments(request: ["place": "X", "from": "--y"]) == nil, "pick: POST /maps refuses what isn't a place")
    check(ArisAgentStatus.forCommand("/t stock AAPL", tools: "/t") == "주가 가져오는 중"
          && ArisAgentStatus.forCommand("/t maps search X --json", tools: "/t") == "길 찾는 중"
          && ArisAgentStatus.forCommand("/t maps search X", tools: "/t") == "지도 여는 중", "status: stock and the maps lookup")
    let tools = "/Users/me/.config/aris/aris-tools"
    check(ArisRiskPolicy.risk(of: .shell("\(tools) stock AAPL"), tools: tools, home: "/Users/me")
          == ArisRiskPolicy.risk(of: .shell("\(tools) weather Seoul"), tools: tools, home: "/Users/me"), "risk: a stock price is a read, like the weather")
    check(!ArisTurnGate.staysLocal(["stock", "AAPL"]) && !ArisTurnGate.isClean(["stock", "AAPL"]),
          "turn gate: a price lookup leaves the Mac, so it's off after outside text")
    let prompt = ArisAgentPrompt.system(tools: "/t")
    check(prompt.contains("`/t stock AAPL`") && prompt.contains("--json"), "prompts: the brain is told about stock and the maps lookup")
}
