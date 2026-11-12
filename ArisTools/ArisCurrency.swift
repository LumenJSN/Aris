//
//  ArisCurrency.swift
//  aris-tools
//
//  The pure half of `currency <amount> <FROM> <TO> [--json]`: what is asked (ISO codes or names, ArisCurrencyNames; a
//  bare "달러" decided by the Mac's own currency), which quotes answer it, and the line and the card made from them.
//  The pair is exactly the one asked: CNY to CAD is Yahoo's CNYCAD=X (the same chart endpoint the stock card reads; no
//  key, no account), and a reply for any other symbol is refused. A rate too small for Yahoo's four decimals (0.0007)
//  is read from the same pair quoted the other way; only when neither way is quoted is it worked out through the US
//  dollar from two quotes, and the card then says so. Yahoo's reply is outside data: every number is checked. The
//  line's amount and the card's are one number (ArisCurrencyMath), rounded once.
//

import Foundation

enum ArisCurrency {
    struct Request: Equatable {
        let amount: Double
        let from: String
        let to: String
        /// The dollar a bare "달러" was taken as, when either could have been meant.
        let assumed: String?
    }

    static let usage = "usage: currency <amount> <FROM> <TO> [--json]   (e.g. currency 100 CNY CAD, currency 50 유로 원)"
    /// What `stock` says when it is asked for a currency.
    static let notAStock = "that is a currency, not a stock: use `currency <amount> <FROM> <TO>` (e.g. currency 1 USD KRW)"

    /// Words `stock` was given that ask for a currency or a rate: "달러", "환율", "달러 환율", "엔화".
    static func isCurrencyAsk(_ words: String) -> Bool {
        let parts = words.split(separator: " ").map(String.init).filter { !["환율", "exchange", "rate"].contains($0.lowercased()) }
        return parts.isEmpty || ArisCurrencyNames.named(parts.joined(separator: " ")) != nil
    }

    private static let joiners: Set<String> = ["to", "in", "into", "->", "→", "=>", "=", "에서"]

    /// `currency`'s words: an amount (left out: the usual one), what to convert, and into what (left out: the Mac's
    /// own currency). Each currency is an ISO code or a name of one to three words.
    static func request(_ words: [String], home: String) -> Request? {
        var rest = words.filter { !joiners.contains($0.lowercased()) }
        guard !rest.isEmpty, rest.count <= 7, rest.allSatisfy({ $0.count <= 24 }) else { return nil }
        var amount: Double?
        if let value = ArisCurrencyMath.typed(rest[0]) {
            amount = value
            rest.removeFirst()
        }
        guard !rest.isEmpty else { return nil }
        for cut in stride(from: min(3, rest.count), through: 1, by: -1) {
            guard let from = named(rest[..<cut]) else { continue }
            let after = rest[cut...]
            guard let to = after.isEmpty ? .code(home) : named(after) else { continue }
            return resolved(amount, from: from, to: to, home: home)
        }
        return nil
    }

    private static func named(_ words: ArraySlice<String>) -> ArisCurrencyNames.Named? {
        guard (1...3).contains(words.count) else { return nil }
        let joined = words.joined(separator: " ")
        // A name of the table first ("won" is the won), then any ISO code the Mac knows ("SEK").
        if let named = ArisCurrencyNames.named(joined) { return named }
        return words.count == 1 && ArisCurrencyNames.isCode(joined.uppercased()) ? .code(joined.uppercased()) : nil
    }

    private static func resolved(_ amount: Double?, from: ArisCurrencyNames.Named, to: ArisCurrencyNames.Named, home: String) -> Request? {
        guard let pair = ArisCurrencyDollar.pair(from: from, to: to, home: home) else { return nil }
        return Request(amount: amount ?? ArisCurrencyMath.usualAmount(pair.from), from: pair.from, to: pair.to, assumed: pair.assumed)
    }

    // MARK: - Yahoo's quotes

    /// How Yahoo names one `from` in `to`: "CNYCAD=X".
    static func symbol(from: String, to: String) -> String { "\(from)\(to)=X" }

    /// A reply's symbol is the one asked: itself, or Yahoo's short name for a US-dollar pair ("KRW=X" is USDKRW=X).
    static func isReply(_ replied: String?, for symbol: String) -> Bool {
        guard let replied = replied?.uppercased() else { return false }
        return replied == symbol.uppercased() || (symbol.hasPrefix("USD") && replied == symbol.dropFirst(3).uppercased())
    }

    struct ChartReply: Decodable {
        let chart: Chart

        struct Chart: Decodable {
            let result: [Result]?
        }

        struct Result: Decodable {
            let meta: Meta
            let timestamp: [Int]?
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
        }

        struct Indicators: Decodable {
            let quote: [Quote]?
        }

        struct Quote: Decodable {
            let close: [Double?]?
        }
    }

    /// One pair's day: the rate now, when it was quoted, and the day's prices by their time.
    struct Series: Equatable {
        struct Point: Equatable {
            let time: Int
            let rate: Double
        }

        let rate: Double
        let time: Int
        let previousClose: Double?
        let high: Double
        let low: Double
        let points: [Point]
    }

    /// The day of `symbol` from one chart reply; nil when the reply is for another symbol, or its rate or time isn't
    /// a positive number.
    static func series(_ reply: ChartReply, symbol: String) -> Series? {
        guard let result = reply.chart.result?.first, isReply(result.meta.symbol, for: symbol),
              let rate = positive(result.meta.regularMarketPrice), let time = result.meta.regularMarketTime, time > 0 else { return nil }
        // Within a third of the rate either way: anything further is a broken point.
        let near = (rate / 3)...(rate * 3)
        let closes = result.indicators?.quote?.first?.close ?? []
        let points = zip(result.timestamp ?? [], closes).compactMap { stamp, close -> Series.Point? in
            guard let close, close.isFinite, near.contains(close), stamp > 0 else { return nil }
            return Series.Point(time: stamp, rate: close)
        }
        let rates = points.map(\.rate) + [rate]
        let previous = positive(result.meta.previousClose ?? result.meta.chartPreviousClose).flatMap { near.contains($0) ? $0 : nil }
        return Series(rate: rate, time: time, previousClose: previous,
                      high: max(positive(result.meta.regularMarketDayHigh).flatMap { near.contains($0) ? $0 : nil } ?? rate, rates.max() ?? rate),
                      low: min(positive(result.meta.regularMarketDayLow).flatMap { near.contains($0) ? $0 : nil } ?? rate, rates.min() ?? rate),
                      points: points)
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value < 1e12 else { return nil }
        return value
    }

    /// The same pair read the other way: every rate turned over, so the day's high is the low turned over.
    static func inverted(_ series: Series) -> Series {
        Series(rate: 1 / series.rate, time: series.time, previousClose: series.previousClose.map { 1 / $0 },
               high: 1 / series.low, low: 1 / series.high, points: series.points.map { Series.Point(time: $0.time, rate: 1 / $0.rate) })
    }

    /// `from` in `to` through the US dollar: each moment both were quoted, how many `to` a dollar bought over how many
    /// `from`. The time is the older of the two quotes.
    static func crossed(usdFrom: Series, usdTo: Series) -> Series? {
        guard let rate = ArisCurrencyMath.cross(usdToFrom: usdFrom.rate, usdToTo: usdTo.rate) else { return nil }
        let sources = Dictionary(usdFrom.points.map { ($0.time, $0.rate) }) { first, _ in first }
        let points = usdTo.points.compactMap { point in sources[point.time].map { Series.Point(time: point.time, rate: point.rate / $0) } }
        let rates = points.map(\.rate) + [rate]
        let previous = usdFrom.previousClose.flatMap { from in usdTo.previousClose.map { $0 / from } }
        return Series(rate: rate, time: min(usdFrom.time, usdTo.time), previousClose: previous, high: rates.max() ?? rate, low: rates.min() ?? rate,
                      points: points)
    }

    /// Yahoo quotes a pair to four decimals: below 0.1 that is too few digits to convert with.
    static func isCoarse(_ rate: Double) -> Bool { rate < 0.1 }

    struct Quote: Equatable {
        let series: Series
        /// Worked out through the US dollar from two quotes (no quote of the pair itself).
        let computed: Bool
    }

    /// The quote for `from` in `to`. `fetch` gets a symbol's chart reply (nil: none). The pair itself first; quoted
    /// the other way when that has more digits or is the only one; through the US dollar last.
    static func quote(from: String, to: String, fetch: (String) -> ChartReply?) -> Quote? {
        func read(_ symbol: String) -> Series? {
            // A US-dollar pair also goes by its short name ("KRW=X").
            for name in symbol.hasPrefix("USD") ? [symbol, String(symbol.dropFirst(3))] : [symbol] {
                if let found = fetch(name).flatMap({ series($0, symbol: symbol) }) { return found }
            }
            return nil
        }
        let direct = read(symbol(from: from, to: to))
        if let direct, !isCoarse(direct.rate) { return Quote(series: direct, computed: false) }
        if let back = read(symbol(from: to, to: from)) { return Quote(series: inverted(back), computed: false) }
        if let direct { return Quote(series: direct, computed: false) }
        guard from != "USD", to != "USD", let usdFrom = read(symbol(from: "USD", to: from)), let usdTo = read(symbol(from: "USD", to: to)) else { return nil }
        return crossed(usdFrom: usdFrom, usdTo: usdTo).map { Quote(series: $0, computed: true) }
    }

    // MARK: - The card and the line

    /// Points on the card's line at most.
    static let mostPoints = 96

    /// The card's values (ArisCurrencyCard in the app reads them again as data).
    static func card(_ request: Request, _ quote: Quote) -> [String: Any] {
        let series = quote.series
        let converted = request.amount * series.rate
        // Enough digits for a rate of any size (0.00068), and a small reply.
        let trimmed = { (value: Double) in Double(String(format: "%.6g", value)) ?? value }
        let points = ArisStock.thin(series.points.map(\.rate) + [series.rate], to: mostPoints).map(trimmed)
        var card: [String: Any] = [
            "amount": request.amount, "from": request.from, "to": request.to, "rate": series.rate, "time": series.time,
            "converted": ArisCurrencyMath.rounded(converted, code: request.to), "about": ArisCurrencyMath.isRounded(converted, code: request.to),
            "high": series.high, "low": series.low, "points": points.count >= 2 ? points : [], "computed": quote.computed,
        ]
        if let previous = series.previousClose { card["previousClose"] = previous }
        if let assumed = request.assumed { card["assumed"] = assumed }
        return card
    }

    /// The brain's line: "100 CNY = 21.34 CAD …; rate: 1 CNY = 0.2134 CAD; rate time …". The amount is the card's own
    /// number, so the answer is told to say exactly it; the time comes worded for a Korean and for an English answer
    /// (as a stock quote's does).
    static func summary(_ card: [String: Any], timeZone: TimeZone = .current, now: Date = Date()) -> String {
        guard let amount = card["amount"] as? Double, let from = card["from"] as? String, let to = card["to"] as? String,
              let rate = card["rate"] as? Double, let time = card["time"] as? Int else { return "" }
        let converted = ArisCurrencyMath.text(amount * rate, code: to)
        let about = ArisCurrencyMath.isRounded(amount * rate, code: to)
        let said = ArisStock.reference(of: Date(timeIntervalSince1970: TimeInterval(time)), now: now, timeZone: timeZone)
        var line = "\(ArisCurrencyMath.plain(amount)) \(from) (\(ArisCurrencyNames.name(from, korean: true)) / \(ArisCurrencyNames.name(from, korean: false))) = "
            + "\(converted) \(to) (\(ArisCurrencyNames.name(to, korean: true)) / \(ArisCurrencyNames.name(to, korean: false))): say exactly \(converted), "
            + (about ? "with “약” / “about” (it is rounded)" : "with no “약” / “about” (it is exact)")
            + ", never a rounder figure: the card under the answer shows this number. "
            + "Rate: \(ArisCurrencyMath.rateLine(from: from, to: to, rate: rate)). "
            + "Rate time, said in the answer's own language and never in the other: Korean “\(said.korean)”, English “\(said.english)” "
            + "(the user's own local time: say only the time, never a city or zone)."
        if let assumed = card["assumed"] as? String {
            line += " “달러” / “dollar” with no country was taken as \(ArisCurrencyNames.name(assumed, korean: false)) (\(assumed)): the card says so, and so may the answer."
        }
        if card["computed"] as? Bool == true { line += " No direct quote of this pair: worked out through the US dollar (the card says so)." }
        return line
    }

    // MARK: - The last quote, kept a moment

    /// A quote is kept this long, so the line a brain was given and the card read right after it show one number.
    static let keptFor: TimeInterval = 90

    /// The card kept for `request`, when it was kept under `keptFor` ago; nil otherwise. What was kept is a file, so it
    /// is read as outside data and the card is built again from checked values only: this pair, a rate that is one, a
    /// whole time that isn't in the future, a day of at most `mostPoints` points near the rate, a range near it too.
    /// Any other key in the file reaches nothing, and the amount and what it converts to are this request's own.
    static func kept(_ stored: [String: Any]?, for request: Request, now: Date) -> [String: Any]? {
        let moment = now.timeIntervalSince1970
        guard let stored, let at = keptNumber(stored["keptAt"]), moment - at >= 0, moment - at < keptFor,
              stored["from"] as? String == request.from, stored["to"] as? String == request.to,
              let rate = keptNumber(stored["rate"]), rate > 0, rate < 1e12,
              let stamp = keptNumber(stored["time"]), stamp == stamp.rounded(), stamp > 946_684_800, stamp <= moment,
              let computed = stored["computed"] as? NSNumber, CFGetTypeID(computed) == CFBooleanGetTypeID(),
              let raw = stored["points"] as? [Any], raw.count <= mostPoints else { return nil }
        // Within a third of the rate either way, as a quote's own points are kept.
        let near = (rate / 3)...(rate * 3)
        let points = raw.compactMap(keptNumber).filter(near.contains)
        guard points.count == raw.count, let high = keptNumber(stored["high"]), let low = keptNumber(stored["low"]),
              near.contains(high), near.contains(low), low <= high else { return nil }
        let converted = request.amount * rate
        var card: [String: Any] = [
            "amount": request.amount, "from": request.from, "to": request.to, "rate": rate, "time": Int(stamp),
            "converted": ArisCurrencyMath.rounded(converted, code: request.to), "about": ArisCurrencyMath.isRounded(converted, code: request.to),
            "high": high, "low": low, "points": points, "computed": computed.boolValue,
        ]
        if let before = stored["previousClose"] {
            guard let previous = keptNumber(before), near.contains(previous) else { return nil }
            card["previousClose"] = previous
        }
        if let assumed = request.assumed { card["assumed"] = assumed }
        return card
    }

    /// A number of the kept file that is one: never a true/false, never infinite.
    private static func keptNumber(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    /// A kept quote is a kilobyte or two; nothing longer is read.
    static let mostKeptBytes = 16 * 1024

    /// The card kept in `file` for `request`. A file that is there and fails any check (too old, too long, not a plain
    /// file, not this pair, a value that isn't one) is deleted, so the quote is simply asked for again.
    static func kept(at file: URL, for request: Request, now: Date) -> [String: Any]? {
        // What is there itself, a link never followed (and asked of the disk each time: a URL remembers its answers).
        guard let facts = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
        var card: [String: Any]?
        if facts[.type] as? FileAttributeType == .typeRegular, let size = (facts[.size] as? NSNumber)?.intValue, size <= mostKeptBytes,
           let data = try? Data(contentsOf: file), let stored = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            card = kept(stored, for: request, now: now)
        }
        if card == nil { try? FileManager.default.removeItem(at: file) }
        return card
    }

    /// `card` as it is kept: with the moment it was read.
    static func keeping(_ card: [String: Any], now: Date) -> [String: Any] {
        card.merging(["keptAt": now.timeIntervalSince1970]) { $1 }
    }

    /// The kept quote's file name for a pair: "fx-CNYCAD.json".
    static func keptName(_ request: Request) -> String { "fx-\(request.from)\(request.to).json" }
}
