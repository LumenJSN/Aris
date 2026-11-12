//
//  ArisCurrencyMath.swift
//  Aris (also built into aris-tools)
//
//  The numbers of a currency conversion, the same in the tool's line, the spoken reply and the card: how an amount is
//  rounded for its currency (two decimals, none for won and yen; a very small result keeps two meaningful digits),
//  whether that rounding changed it (only then is it "약" / "about"), how a rate is written ("1 CNY = 0.2134 CAD"),
//  which dollar a bare "달러" is on this Mac, and the amount a person types into the card. Foundation only (tested).
//

import Foundation

/// The Mac's own currency, from its region (Canada: CAD); the US dollar when the region has none.
enum ArisCurrencyHome {
    static func code(_ locale: Locale = .current) -> String {
        let code = locale.currency?.identifier.uppercased() ?? ""
        return code.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil ? code : "USD"
    }
}

/// Which dollar "달러" alone means, by the Mac's own currency.
enum ArisCurrencyDollar {
    /// Where the bare word stood in the request.
    enum Role { case source, target }

    /// The dollar it is taken as, and whether that was a guess worth saying on the card. On a Mac whose own money is a
    /// dollar (Canada), "…달러로 얼마야" asks for that one, and a bare dollar being converted is the US one; both are
    /// said, since either could have been meant. Anywhere else it is the US dollar and nobody wonders.
    /// `other`: the request's other currency; the bare dollar is never the same one.
    static func resolve(_ role: Role, home: String, other: String?) -> (code: String, assumed: Bool) {
        guard ArisCurrencyNames.isDollar(home), home != "USD" else { return ("USD", false) }
        let picked = role == .target ? home : "USD"
        if picked == other { return (picked == home ? "USD" : home, true) }
        return (picked, true)
    }

    /// A request's two currencies with a bare dollar decided: what to convert, into what, and the dollar that was
    /// assumed when one was. Nil when both are bare dollars or both come out the same money.
    static func pair(from: ArisCurrencyNames.Named, to: ArisCurrencyNames.Named, home: String) -> (from: String, to: String, assumed: String?)? {
        let found: (from: String, to: String, assumed: String?)
        switch (from, to) {
        case (.bareDollar, .bareDollar):
            return nil
        case (.code(let code), .code(let other)):
            found = (code, other, nil)
        case (.bareDollar, .code(let other)):
            let dollar = resolve(.source, home: home, other: other)
            found = (dollar.code, other, dollar.assumed ? dollar.code : nil)
        case (.code(let code), .bareDollar):
            let dollar = resolve(.target, home: home, other: code)
            found = (code, dollar.code, dollar.assumed ? dollar.code : nil)
        }
        return found.from == found.to ? nil : found
    }
}

enum ArisCurrencyMath {
    /// Amounts Aris converts: more than nothing, less than a million million.
    static let most = 1e12
    static let mostDecimals = 8

    static func isAmount(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= most }

    /// The amount a rate is told for when none was said: 100엔, 1,000원, one of anything else.
    static func usualAmount(_ code: String) -> Double {
        switch code {
        case "JPY": return 100
        case "KRW": return 1_000
        case "VND", "IDR": return 10_000
        default: return 1
        }
    }

    /// The decimals `value` is shown with in `code`: the currency's own, or as many as leave two meaningful digits
    /// when it is smaller than that shows (0.00095 CAD, never 0.00).
    static func decimals(of value: Double, code: String) -> Int {
        let base = ArisCurrencyNames.decimals(code)
        // What the currency's own decimals still show with two digits: from 0.10, or from 1 with no decimals.
        guard value.isFinite, value > 0, value < pow(10, Double(1 - max(base, 1))) else { return base }
        return min(mostDecimals, max(base, 1 - Int(floor(log10(value)))))
    }

    static func rounded(_ value: Double, code: String) -> Double {
        let scale = pow(10, Double(decimals(of: value, code: code)))
        return (value * scale).rounded() / scale
    }

    /// The rounding changed the amount: it is said with "약" / "about".
    static func isRounded(_ value: Double, code: String) -> Bool {
        abs(rounded(value, code: code) - value) > max(abs(value), 1) * 1e-9
    }

    /// An amount in its currency: "21.34", "143,250", "0.00095".
    static func text(_ value: Double, code: String) -> String {
        format(value, decimals: decimals(of: value, code: code), fixed: true)
    }

    /// The amount asked, as it was given: "100", "1,000", "19.5" (no decimals added).
    static func plain(_ amount: Double) -> String { format(amount, decimals: 6, fixed: false) }

    /// The amount as the tool takes it on its command line: "1000", "19.5".
    static func argument(_ amount: Double) -> String { plain(amount).replacingOccurrences(of: ",", with: "") }

    /// The decimals a rate is written with: four meaningful digits below one, five from one up, none past 10,000.
    static func rateDecimals(_ rate: Double) -> Int {
        guard rate.isFinite, rate > 0 else { return 4 }
        let leading = Int(floor(log10(rate)))
        return min(mostDecimals, max(0, rate >= 1 ? 4 - leading : 3 - leading))
    }

    /// "0.2134", "1.4023", "1,432.5".
    static func rateText(_ rate: Double) -> String { format(rate, decimals: rateDecimals(rate), fixed: true) }

    /// "1 CNY = 0.2134 CAD".
    static func rateLine(from: String, to: String, rate: Double) -> String { "1 \(from) = \(rateText(rate)) \(to)" }

    /// One unit bought through the US dollar: how many `to` for one `from`, from how many of each a dollar buys.
    static func cross(usdToFrom: Double, usdToTo: Double) -> Double? {
        guard usdToFrom.isFinite, usdToTo.isFinite, usdToFrom > 0, usdToTo > 0 else { return nil }
        return usdToTo / usdToFrom
    }

    /// A number typed into the card's amount ("1,000", "19.5", ".5", "1 000"); nil for anything else, nothing or zero.
    static func typed(_ text: String) -> Double? {
        let digits = text.filter { !$0.isWhitespace && $0 != "," }
        guard digits.range(of: #"^(?:[0-9]+\.?[0-9]*|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let value = Double(digits), isAmount(value) else { return nil }
        return value
    }

    private static func format(_ value: Double, decimals: Int, fixed: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fixed ? decimals : 0
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
