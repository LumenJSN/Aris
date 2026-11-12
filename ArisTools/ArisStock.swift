//
//  ArisStock.swift
//  aris-tools
//
//  The pure half of `stock <symbol|name> [--json]`: a name said in Korean goes through a small alias table (Yahoo's
//  search refuses Hangul), a ticker goes as typed, anything else through Yahoo's search; the quote comes from Yahoo
//  Finance's public chart endpoint (no key, no account). Yahoo's reply is outside data: every number is checked, a
//  range always holds the price, a point far off the day is dropped, and names lose control characters. --json is
//  the notch card's values (ArisStockCard in the app reads them again as data).
//

import Foundation

enum ArisStock {
    struct Alias: Equatable {
        let symbol: String
        /// The card's name; nil takes Yahoo's (a Korean listing's short name reads "SamsungElec").
        let name: String?
    }

    static let longestQuery = 40
    /// Points on the card's sparkline at most.
    static let mostPoints = 96
    /// The most that is read of one reply from Yahoo (`stock` and `currency`). A day's chart is 5 to 40 KB and a search
    /// a few KB (the CNYCAD=X day recorded for the tests was 5,254 bytes), so half a megabyte is over ten times the
    /// longest real one; a longer reply is dropped unread.
    static let mostReplyBytes = 512 * 1_024

    private static let table: [String: Alias] = {
        let us: [(String, String)] = [
            ("애플", "AAPL"), ("테슬라", "TSLA"), ("엔비디아", "NVDA"), ("마이크로소프트", "MSFT"), ("마소", "MSFT"),
            ("구글", "GOOGL"), ("알파벳", "GOOGL"), ("아마존", "AMZN"), ("메타", "META"), ("페이스북", "META"),
            ("넷플릭스", "NFLX"), ("인텔", "INTC"), ("에이엠디", "AMD"), ("팔란티어", "PLTR"), ("쿠팡", "CPNG"),
            ("코카콜라", "KO"), ("디즈니", "DIS"), ("나이키", "NKE"), ("스타벅스", "SBUX"), ("브로드컴", "AVGO"),
            ("tsmc", "TSM"), ("버크셔", "BRK-B"), ("나스닥", "^IXIC"), ("에스앤피", "^GSPC"), ("s&p500", "^GSPC"),
            ("다우", "^DJI"), ("비트코인", "BTC-USD"), ("이더리움", "ETH-USD"),
        ]
        let korea: [(String, String, String)] = [
            ("삼성전자", "005930.KS", "삼성전자"), ("삼전", "005930.KS", "삼성전자"), ("sk하이닉스", "000660.KS", "SK하이닉스"),
            ("하이닉스", "000660.KS", "SK하이닉스"), ("네이버", "035420.KS", "NAVER"), ("카카오", "035720.KS", "카카오"),
            ("현대차", "005380.KS", "현대차"), ("현대자동차", "005380.KS", "현대차"), ("기아", "000270.KS", "기아"),
            ("lg에너지솔루션", "373220.KS", "LG에너지솔루션"), ("엘지에너지솔루션", "373220.KS", "LG에너지솔루션"),
            ("삼성바이오로직스", "207940.KS", "삼성바이오로직스"), ("셀트리온", "068270.KS", "셀트리온"), ("lg전자", "066570.KS", "LG전자"),
            ("포스코", "005490.KS", "POSCO홀딩스"), ("코스피", "^KS11", "코스피"), ("코스닥", "^KQ11", "코스닥"),
        ]
        var table = Dictionary(uniqueKeysWithValues: us.map { ($0.0, Alias(symbol: $0.1, name: nil)) })
        for (key, symbol, name) in korea { table[key] = Alias(symbol: symbol, name: name) }
        return table
    }()

    private static let suffixes = ["주가", "주식", "시세", "stock", "shares"]

    /// The alias for a name as said: any case, spaces and a trailing 주가 / 주식 / 시세 left out.
    static func alias(_ query: String) -> Alias? {
        var key = query.lowercased().filter { !$0.isWhitespace }
        for suffix in suffixes where key.hasSuffix(suffix) && key.count > suffix.count { key.removeLast(suffix.count) }
        return table[key]
    }

    /// The words to look up: trimmed, 1…40 characters, no control characters, never starting with "-".
    static func cleaned(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= longestQuery, !text.hasPrefix("-"),
              !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return text
    }

    /// A ticker as typed: capitals, digits and . - ^ =, no spaces ("AAPL", "005930.KS", "^GSPC", "BTC-USD").
    static func looksLikeTicker(_ text: String) -> Bool {
        text.range(of: #"^[A-Z0-9^][A-Z0-9.\-=^]{0,14}$"#, options: .regularExpression) != nil
    }

    /// A symbol fit to put in a URL path and on the card.
    static func isSymbol(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9^][A-Za-z0-9.\-=^]{0,19}$"#, options: .regularExpression) != nil
    }

    private static let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    static func chartURL(symbol: String, host: String = "query1") -> URL? {
        guard isSymbol(symbol), let path = symbol.addingPercentEncoding(withAllowedCharacters: plain) else { return nil }
        return URL(string: "https://\(host).finance.yahoo.com/v8/finance/chart/\(path)?interval=5m&range=1d&includePrePost=false")
    }

    static func searchURL(_ words: String, host: String = "query1") -> URL? {
        guard let query = words.addingPercentEncoding(withAllowedCharacters: plain) else { return nil }
        return URL(string: "https://\(host).finance.yahoo.com/v1/finance/search?q=\(query)&quotesCount=6&newsCount=0&listsCount=0")
    }

    // MARK: - Yahoo's replies

    struct ChartReply: Decodable {
        let chart: Chart

        struct Chart: Decodable {
            let result: [Result]?
        }

        struct Result: Decodable {
            let meta: Meta
            let indicators: Indicators?
        }

        struct Meta: Decodable {
            let currency: String?
            let symbol: String?
            let regularMarketPrice: Double?
            let previousClose: Double?
            let chartPreviousClose: Double?
            let regularMarketDayHigh: Double?
            let regularMarketDayLow: Double?
            let regularMarketTime: Int?
            let longName: String?
            let shortName: String?
            let priceHint: Int?
        }

        struct Indicators: Decodable {
            let quote: [Quote]?
        }

        struct Quote: Decodable {
            let close: [Double?]?
        }
    }

    struct SearchReply: Decodable {
        let quotes: [Quote]?

        struct Quote: Decodable {
            let symbol: String?
            let quoteType: String?
        }
    }

    private static let listings: Set<String> = ["EQUITY", "ETF", "INDEX", "CRYPTOCURRENCY", "MUTUALFUND", "CURRENCY", "FUTURE"]

    /// The search's first hit that is a listing (never an option) with a symbol fit to use.
    static func bestSymbol(_ reply: SearchReply) -> String? {
        reply.quotes?.first { quote in
            guard let symbol = quote.symbol, let type = quote.quoteType else { return false }
            return listings.contains(type.uppercased()) && isSymbol(symbol)
        }?.symbol
    }

    /// The card's values from one chart reply; nil when the price or the previous close isn't a positive number.
    static func card(_ reply: ChartReply, displayName: String?) -> [String: Any]? {
        guard let result = reply.chart.result?.first else { return nil }
        let meta = result.meta
        guard let symbol = meta.symbol, isSymbol(symbol),
              let price = positive(meta.regularMarketPrice), let previous = positive(meta.previousClose ?? meta.chartPreviousClose),
              let time = meta.regularMarketTime, time > 0 else { return nil }
        // Within a third of the previous close either way: anything further is a broken point.
        let near = (previous / 3)...(previous * 3)
        let closes = (result.indicators?.quote?.first?.close ?? []).compactMap { $0 }.filter { $0.isFinite && near.contains($0) }
        // Four decimals are plenty for a 60-point-high line (and keep the reply small).
        let points = thin(closes + [price], to: mostPoints).map { ($0 * 10_000).rounded() / 10_000 }
        let high = max(positive(meta.regularMarketDayHigh) ?? price, points.max() ?? price)
        let low = min(positive(meta.regularMarketDayLow) ?? price, points.min() ?? price)
        let name = displayName ?? shortened(meta.shortName ?? meta.longName) ?? symbol
        var card: [String: Any] = ["symbol": symbol, "name": name, "price": price, "previousClose": previous, "high": high, "low": low,
                                   "time": time, "points": points, "decimals": decimals(hint: meta.priceHint, currency: meta.currency)]
        if let currency = meta.currency, currency.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil { card["currency"] = currency }
        return card
    }

    /// At most `count` values, evenly spread, the first and last kept.
    static func thin(_ values: [Double], to count: Int) -> [Double] {
        guard values.count > count, count >= 2 else { return values }
        return (0..<count).map { values[Int((Double($0) * Double(values.count - 1) / Double(count - 1)).rounded())] }
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value < 1e12 else { return nil }
        return value
    }

    /// Won and yen have no decimals; anything else has Yahoo's hint (0…4), or 2.
    private static func decimals(hint: Int?, currency: String?) -> Int {
        if currency == "KRW" || currency == "JPY" { return 0 }
        return hint.flatMap { (0...4).contains($0) ? $0 : nil } ?? 2
    }

    /// Yahoo's short name as plain text, without its legal ending ("Apple Inc." → "Apple").
    private static func shortened(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let spaced = raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }.joined()
        var name = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for ending in [", Inc.", " Inc.", " Inc", " Corporation", " Corp.", " Co., Ltd.", " Ltd.", " plc", " N.V."] where name.hasSuffix(ending) {
            name.removeLast(ending.count)
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return name.isEmpty ? nil : String(name.prefix(longestQuery))
    }

    /// The brain's line: "Apple (AAPL): 271.42 USD, +3.18 (+1.19%) today; high 272.90, low 267.50; quote time: …". The
    /// time is always in the Mac's own zone, so no zone is named (QA BUG-50: "(America/New_York)" came back as "orlando
    /// 시각 오후 1시 2분 기준"). The change is named by the quote's own day (QA: "오늘 2.43% 올랐어요" beside a quote from
    /// yesterday's close), and the quote's time comes worded in Korean and in English, so the answer says it in its own
    /// language (QA: an English "This quote is from 4 p.m. yesterday." in a Korean reply).
    static func summary(_ card: [String: Any], timeZone: TimeZone = .current, now: Date = Date()) -> String {
        guard let price = card["price"] as? Double, let previous = card["previousClose"] as? Double,
              let high = card["high"] as? Double, let low = card["low"] as? Double, let time = card["time"] as? Int else { return "" }
        let digits = card["decimals"] as? Int ?? 2
        let number = { (value: Double) in String(format: "%.\(digits)f", value) }
        let change = price - previous, percent = change / previous * 100
        let sign = change >= 0 ? "+" : "-"
        let currency = (card["currency"] as? String).map { " " + $0 } ?? ""
        let quoted = Date(timeIntervalSince1970: TimeInterval(time))
        let said = reference(of: quoted, now: now, timeZone: timeZone)
        return "\(card["name"] as? String ?? "") (\(card["symbol"] as? String ?? "")): \(number(price))\(currency), "
            + "\(sign)\(number(abs(change))) (\(sign)\(String(format: "%.2f", abs(percent)))%) \(session(of: quoted, now: now, timeZone: timeZone)); high \(number(high)), low \(number(low)); "
            + "quote time, said in the answer's own language and never in the other: Korean “\(said.korean)”, English “\(said.english)” "
            + "(the user's own local time: say only the time, never a city or zone)."
    }

    /// The day the quote is from, against now in the Mac's zone.
    enum QuoteDay: Equatable { case today, yesterday, earlier }

    static func day(of quoted: Date, now: Date, timeZone: TimeZone) -> QuoteDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(quoted, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(quoted, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }

    /// The day the change belongs to, by the quote's own day: "today", or yesterday's or that date's, with the words
    /// that keep it from being told as today's. Pure.
    static func session(of quoted: Date, now: Date, timeZone: TimeZone) -> String {
        switch day(of: quoted, now: now, timeZone: timeZone) {
        case .today: return "today"
        case .yesterday: return "on the last trading day (yesterday: say it as yesterday's change, 어제, never today's or 오늘)"
        case .earlier:
            return "on the last trading day (\(format(quoted, "yyyy-MM-dd", timeZone: timeZone)): say it as that day's change, never today's or 오늘)"
        }
    }

    /// The quote's time as the answer says it, in each language: "오늘 오후 2시 26분 기준" and "as of 2:26 p.m. today",
    /// "어제 오후 4시 기준" and "as of 4 p.m. yesterday", or with its date ("11월 5일 오후 4시 기준", "as of 4 p.m. on Nov 5"). Pure.
    static func reference(of quoted: Date, now: Date, timeZone: TimeZone) -> (korean: String, english: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: quoted)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        let clock = ArisKoreanClock.phrase(hour: hour, minute: minute)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let english = (minute == 0 ? "\(twelve)" : "\(twelve):" + String(format: "%02d", minute)) + (hour < 12 ? " a.m." : " p.m.")
        switch day(of: quoted, now: now, timeZone: timeZone) {
        case .today: return ("오늘 \(clock) 기준", "as of \(english) today")
        case .yesterday: return ("어제 \(clock) 기준", "as of \(english) yesterday")
        case .earlier:
            return ("\(parts.month ?? 1)월 \(parts.day ?? 1)일 \(clock) 기준", "as of \(english) on \(format(quoted, "MMM d", timeZone: timeZone))")
        }
    }

    private static func format(_ date: Date, _ pattern: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
