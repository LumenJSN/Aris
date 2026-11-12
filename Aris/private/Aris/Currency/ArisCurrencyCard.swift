//
//  ArisCurrencyCard.swift
//  Aris
//
//  The currency card's values, from aris-agent's app-only POST /currency (aris-tools currency … --json: the quote of
//  exactly the pair asked). Read as outside data: a value that isn't one drops the card, and nothing a brain wrote
//  reaches it but the words that were asked. The converted amount is this card's own amount × rate, rounded the one
//  way the spoken line rounds it (ArisCurrencyMath), so the two never differ. Also what the live card does with the
//  rate it already has: a typed amount, the pair turned round (the inverse rate, the day's line turned over with it),
//  and the short list a code is changed from. Pure, so the tests run it.
//

import Foundation

struct ArisCurrencyCard: Equatable, Sendable {
    let amount: Double
    let from: String
    let to: String
    /// How many `to` one `from` buys.
    let rate: Double
    /// The rate's own time.
    let time: Date
    /// The day's rates, for the line.
    let points: [Double]
    let high: Double
    let low: Double
    let previousClose: Double?
    /// Worked out through the US dollar from two quotes.
    let computed: Bool
    /// The dollar a bare "달러" was taken as, when either could have been meant.
    let assumed: String?

    static let mostPoints = 300

    static func parse(_ object: [String: Any], now: Date = Date()) -> ArisCurrencyCard? {
        guard let from = code(object["from"]), let to = code(object["to"]), from != to,
              let amount = number(object["amount"]), ArisCurrencyMath.isAmount(amount), let rate = positive(object["rate"]),
              let seconds = number(object["time"]), seconds > 946_684_800, seconds <= now.timeIntervalSince1970 + 86_400 else { return nil }
        // Within a third of the rate either way, as the tool keeps them: anything further is a broken point.
        let near = (rate / 3)...(rate * 3)
        let points = ((object["points"] as? [Any]) ?? []).prefix(mostPoints).compactMap(positive).filter(near.contains)
        let all = points + [rate]
        return ArisCurrencyCard(amount: amount, from: from, to: to, rate: rate, time: Date(timeIntervalSince1970: seconds), points: points,
                                high: max(positive(object["high"]).flatMap { near.contains($0) ? $0 : nil } ?? rate, all.max() ?? rate),
                                low: min(positive(object["low"]).flatMap { near.contains($0) ? $0 : nil } ?? rate, all.min() ?? rate),
                                previousClose: positive(object["previousClose"]).flatMap { near.contains($0) ? $0 : nil },
                                computed: object["computed"] as? Bool ?? false, assumed: code(object["assumed"]))
    }

    /// A JSON number that is one (never a true/false, never infinite).
    private static func number(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return value.isFinite ? value : nil
    }

    private static func positive(_ raw: Any?) -> Double? { number(raw).flatMap { $0 > 0 && $0 < 1e12 ? $0 : nil } }

    private static func code(_ raw: Any?) -> String? {
        (raw as? String).flatMap { $0.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil ? $0 : nil }
    }

    /// The card that answers `ask` from aris-tools' values: only one of exactly the pair asked (never another pair's
    /// rate under the sentence), with the dollar the sentence's bare "달러" was taken as.
    static func answering(_ ask: ArisCurrencyAsk, values: [String: Any]?, now: Date = Date()) -> ArisCurrencyCard? {
        guard let card = values.flatMap({ parse($0, now: now) }), card.from == ask.from, card.to == ask.to else { return nil }
        return card.with(amount: ask.amount).assuming(ask.assumed)
    }

    // MARK: - What it shows

    var converted: Double { amount * rate }
    /// "21.34", "143,250".
    var convertedText: String { ArisCurrencyMath.text(converted, code: to) }
    /// The rounding changed it: said with "약" / "about".
    var about: Bool { ArisCurrencyMath.isRounded(converted, code: to) }
    /// "100", "1,000", "19.5".
    var amountText: String { ArisCurrencyMath.plain(amount) }
    /// "1 CNY = 0.2134 CAD".
    var rateLine: String { ArisCurrencyMath.rateLine(from: from, to: to, rate: rate) }
    var highText: String { ArisCurrencyMath.rateText(high) }
    var lowText: String { ArisCurrencyMath.rateText(low) }
    /// The line's floor and colour: against yesterday's close, or the day's first rate.
    var reference: Double { previousClose ?? points.first ?? rate }
    var up: Bool { rate >= reference }

    /// "오후 2:26 기준" today, "11월 4일 오후 4:00 기준" on another day; "As of 2:26 PM", "As of Nov 4 at 4:00 PM".
    func asOf(now: Date, calendar: Calendar = .current, english: Bool = ArisUIWords.english, locale: Locale? = nil) -> String {
        let today = calendar.isDate(time, inSameDayAs: now)
        let said = ArisUIDates.string(time, korean: today ? "a h:mm" : "M월 d일 a h:mm", template: today ? "jmm" : "MMMdjmm", english: english,
                                      calendar: calendar, locale: locale)
        return english ? "As of " + said : said + " 기준"
    }

    // MARK: - What the live card changes

    /// The same rate for another amount.
    func with(amount: Double) -> ArisCurrencyCard {
        ArisCurrencyCard(amount: amount, from: from, to: to, rate: rate, time: time, points: points, high: high, low: low,
                         previousClose: previousClose, computed: computed, assumed: assumed)
    }

    func assuming(_ code: String?) -> ArisCurrencyCard {
        ArisCurrencyCard(amount: amount, from: from, to: to, rate: rate, time: time, points: points, high: high, low: low,
                         previousClose: previousClose, computed: computed, assumed: code)
    }

    /// The pair turned round, from the rate already here: the inverse rate, each point of the day turned over (so the
    /// day's high is the old low turned over), the same amount now in the other currency.
    var swapped: ArisCurrencyCard {
        ArisCurrencyCard(amount: amount, from: to, to: from, rate: 1 / rate, time: time, points: points.map { 1 / $0 }, high: 1 / low, low: 1 / high,
                         previousClose: previousClose.map { 1 / $0 }, computed: computed, assumed: assumed)
    }

    /// The words aris-tools takes for it: "100 CNY CAD".
    var words: String { "\(ArisCurrencyMath.argument(amount)) \(from) \(to)" }
}

/// The live card (the hidden preference arisCurrencyCard = live): the card with an amount that can be typed, a swap
/// and two codes that can be changed.
enum ArisCurrencyStyle {
    static let key = "arisCurrencyCard"
    static let recentKey = "arisCurrencyRecent"

    /// Plain until he picks: only "live" turns the controls on.
    static func isLive(setting: String?) -> Bool { setting == "live" }
}

/// What the live card holds while it is used. Pure: the view and its model only pass things on.
struct ArisCurrencyLive: Equatable {
    enum Side: Equatable { case from, to }

    /// What a picked code asks for.
    enum Pick: Equatable {
        /// Nothing changes (the code it already is).
        case none
        /// The other side's code: the pair is turned round, with no request.
        case swap
        /// A new pair: one request for these words ("100 EUR CAD").
        case fetch(String)
    }

    private(set) var card: ArisCurrencyCard
    /// The amount as it is being typed; nil while the field rests.
    private(set) var draft: String?

    init(_ card: ArisCurrencyCard) { self.card = card }

    /// The field's text: what is being typed, or the amount.
    var amountText: String { draft ?? card.amountText }
    /// What is typed isn't an amount yet (empty, or not a number): the result waits, dimmed.
    var waits: Bool { draft.map { ArisCurrencyMath.typed($0) == nil } ?? false }

    mutating func beginEditing() {
        if draft == nil { draft = ArisCurrencyMath.argument(card.amount) }
    }

    /// A key typed: the result follows at once from the rate already here, with no request and no AI.
    mutating func type(_ text: String) {
        draft = String(text.prefix(18))
        if let amount = ArisCurrencyMath.typed(text) { card = card.with(amount: amount) }
    }

    /// Return, Esc or the field left: the last amount that was one stays.
    mutating func endEditing() { draft = nil }

    mutating func swap() { card = card.swapped }

    /// What picking `code` for `side` means.
    func pick(_ code: String, for side: Side) -> Pick {
        let current = side == .from ? card.from : card.to, other = side == .from ? card.to : card.from
        if code == current { return .none }
        if code == other { return .swap }
        let from = side == .from ? code : card.from, to = side == .to ? code : card.to
        return .fetch("\(ArisCurrencyMath.argument(card.amount)) \(from) \(to)")
    }

    /// The new pair's card arrived: it is shown with the amount as it is now.
    mutating func arrived(_ fresh: ArisCurrencyCard) { card = fresh.with(amount: card.amount) }

    // MARK: The short list

    static let always = ["USD", "KRW", "JPY", "CNY", "EUR", "GBP"]
    static let mostRecent = 3

    /// The codes a currency is changed from: the Mac's own, the six everyone uses, then the last three he used.
    static func choices(home: String, recent: [String]) -> [String] {
        var seen = Set<String>()
        return ([home] + always + recent.prefix(mostRecent)).filter { seen.insert($0).inserted }
    }

    /// The last-used list after `codes` were used: newest first, three at most, only codes the list doesn't always show.
    static func remembering(_ codes: [String], in recent: [String], home: String) -> [String] {
        let fixed = Set([home] + always)
        var seen = Set<String>()
        return (codes.reversed() + recent).filter { !fixed.contains($0) && $0.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil && seen.insert($0).inserted }
            .prefix(mostRecent).map { $0 }
    }

    /// The code after `code` in the list (`step` -1: before it), going round: the keyboard's ↓ and ↑ on a code.
    /// Never the other side's code (that would only turn the pair round).
    static func stepped(_ code: String, by step: Int, in choices: [String], skipping other: String) -> String {
        let list = choices.filter { $0 != other }
        guard !list.isEmpty else { return code }
        guard let at = list.firstIndex(of: code) else { return step > 0 ? list[0] : list[list.count - 1] }
        return list[((at + step) % list.count + list.count) % list.count]
    }
}

/// The keys of the live card's amount field, as AppKit names them (the field's doCommandBy). Pure.
enum ArisCurrencyKeys {
    /// Where the keyboard is while the field is being edited.
    enum Stop: Equatable, CaseIterable { case amount, from, to }

    enum Action: Equatable {
        /// Tab or Shift-Tab: to the next stop.
        case move(Stop)
        /// ↓ or ↑ on a code: the next or the previous of the list.
        case step(Int)
        /// Return on the amount, or Esc: the field is left. Return on a code goes back to the amount.
        case leave
        /// The field's own (a digit, an arrow inside the number).
        case own
    }

    static func action(for command: String, at stop: Stop) -> Action {
        let stops = Stop.allCases
        let index = stops.firstIndex(of: stop) ?? 0
        switch command {
        case "insertTab:": return .move(stops[(index + 1) % stops.count])
        case "insertBacktab:": return .move(stops[(index + stops.count - 1) % stops.count])
        case "cancelOperation:": return .leave
        case "insertNewline:": return stop == .amount ? .leave : .move(.amount)
        case "moveDown:": return stop == .amount ? .own : .step(1)
        case "moveUp:": return stop == .amount ? .own : .step(-1)
        default: return .own
        }
    }
}
