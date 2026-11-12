//
//  ArisCurrencyCopy.swift
//  Aris
//
//  The words of a currency answer, Korean and English: the line Aris says ("100위안은 약 21.34 캐나다 달러예요."), made
//  from the card's own number so the two can't differ ("약" / "about" only when the amount was rounded), the plain line
//  when no rate could be read, and the card's small words. Pure, so the tests run it.
//

import Foundation

enum ArisCurrencyCopy {
    /// The working tag while the rate is read (the agent's own word for it: ArisCurrencyRoute.status).
    static let checking = "환율 확인 중"

    /// A currency's name in a sentence. The US dollar is just "달러" where no other dollar is at home.
    private static func name(_ code: String, korean: Bool, one: Bool, home: String) -> String {
        if korean, code == "USD", !ArisCurrencyNames.isDollar(home) { return "달러" }
        return ArisCurrencyNames.name(code, korean: korean, one: one)
    }

    /// "100위안", "100 캐나다 달러": a one-word name sits on its number.
    private static func koreanAmount(_ number: String, _ name: String) -> String {
        name.contains(" ") ? "\(number) \(name)" : number + name
    }

    /// What Aris says: "100위안은 약 21.34 캐나다 달러예요.", "100 yuan is about 21.34 Canadian dollars."
    static func line(_ card: ArisCurrencyCard, korean: Bool, home: String) -> String {
        let shown = ArisCurrencyMath.rounded(card.converted, code: card.to)
        let from = name(card.from, korean: korean, one: card.amount == 1, home: home)
        let to = name(card.to, korean: korean, one: shown == 1, home: home)
        guard korean else { return "\(card.amountText) \(from) is \(card.about ? "about " : "")\(card.convertedText) \(to)." }
        let asked = koreanAmount(card.amountText, from), result = koreanAmount(card.convertedText, to)
        return "\(ArisJosa.attach(asked, "은", "는")) \(card.about ? "약 " : "")\(ArisJosa.attach(result, "이에요", "예요"))."
    }

    /// No rate (offline, or nobody quotes the pair): a plain line, and no card.
    static func noRate(korean: Bool) -> String {
        korean ? "지금은 환율을 가져오지 못했어요. 인터넷 연결을 확인하고 다시 물어봐 주세요." : "I couldn't get the rate just now. Check the connection and ask again."
    }

    /// The card's small line: which dollar was assumed, and that the rate was worked out through the US dollar.
    static func note(_ card: ArisCurrencyCard, english: Bool) -> String? {
        var parts: [String] = []
        if let assumed = card.assumed {
            parts.append(english ? "Assuming \(ArisCurrencyNames.name(assumed, korean: false))" : "\(ArisCurrencyNames.name(assumed, korean: true)) 기준")
        }
        if card.computed { parts.append(english ? "Computed through USD" : "미국 달러를 거쳐 계산") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func high(english: Bool) -> String { english ? "High" : "고가" }
    static func low(english: Bool) -> String { english ? "Low" : "저가" }
    static func swap(english: Bool) -> String { english ? "Swap currencies" : "통화 맞바꾸기" }
    static func amount(english: Bool) -> String { english ? "Amount" : "금액" }
    static func change(_ code: String, english: Bool) -> String { english ? "Change \(code)" : "\(code) 바꾸기" }
    /// The new pair's rate could not be read: the card stays on the one it had.
    static func pickFailed(english: Bool) -> String { english ? "Couldn't get that rate" : "그 환율은 가져오지 못했어요" }
}
