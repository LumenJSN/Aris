//
//  ArisCurrencyRoute.swift
//  aris-agent
//
//  Currency conversion on the agent's side (aris-tools currency does the work; ArisCurrencyCard in the app draws it):
//  the answer card a turn earned by running `aris-tools currency …` (ArisWidgetPick), the words POST /currency hands
//  back to aris-tools for that card's values, the line each brain is told about the command (ArisAgentPrompt), the
//  API brain's function (ArisAPICatalog), and the working tag's words (ArisAgentStatus). The card's block carries only
//  the words that were asked ("100 CNY CAD"): aris-tools reads the rate again itself, never a number from a brain.
//

import Foundation

enum ArisCurrencyRoute {
    /// The words asked at most: an amount and two names of up to three words.
    static let longestAsk = 60
    static let mostWords = 7

    /// The working tag while the rate is read ("Checking the rate" in English: ArisUIWords).
    static let status = "환율 확인 중"

    /// What a brain is told about the command: when it is this and not `stock`, and that the answer's number is the tool's.
    static func prompt(_ tools: String) -> String {
        "- Money in another currency, or an exchange rate (\"100위안이 캐나다 달러로 얼마야\", \"달러 환율\", \"how much is 50 euros in won\"): "
            + "`\(tools) currency <amount> <FROM> <TO>` (ISO codes, or the user's own words for them: `\(tools) currency 100 CNY CAD`, "
            + "`\(tools) currency 50 유로 원`; no amount asks for the rate; no <TO> means the user's own currency), never `stock` and never the web. "
            + "Convert exactly the pair the user's last wording names (a correction inside the sentence replaces what came before it). "
            + "When they say only \"달러\" or \"dollar\" with no country, pass that word as it is: the tool decides which dollar and says which it took. "
            + "Say the converted amount exactly as the tool gives it (its digits, and \"약\" / \"about\" only when the tool says it is rounded): "
            + "the card under the answer shows the same number."
    }

    /// The sealed brain's short form of the same.
    static func sealedPrompt(_ tools: String) -> String {
        ", money in another currency or an exchange rate with `\(tools) currency <amount> <FROM> <TO>` "
            + "(the pair the user named; say the amount exactly as it is given)"
    }

    /// The words of a `currency` call that name what was asked (its flags left out), as the card's block carries them;
    /// nil when they aren't an amount and currencies (the card is then left out, never guessed).
    static func ask(_ words: [String]) -> String? {
        let plain = words.filter { !$0.hasPrefix("--") }
        guard !plain.isEmpty, plain.count <= mostWords, plain.allSatisfy(isWord) else { return nil }
        let joined = plain.joined(separator: " ")
        return joined.count <= longestAsk ? joined : nil
    }

    /// The card's block for a turn that ran `currency …`.
    static func card(_ words: [String]) -> [String: String]? {
        ask(words).map { ["type": "currency", "ask": $0] }
    }

    /// POST /currency's arguments: `currency <the words asked> --json`; nil (no card) when "ask" isn't such words.
    static func arguments(request object: [String: Any]) -> [String]? {
        guard let raw = object["ask"] as? String, raw.count <= longestAsk, let ask = ask(raw.split(separator: " ").map(String.init)) else { return nil }
        return ["currency"] + ask.split(separator: " ").map(String.init) + ["--json"]
    }

    /// A word of the ask: letters and digits with . , inside (an amount, a code, a name), never a flag.
    private static func isWord(_ word: String) -> Bool {
        let allowed = CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: ".,"))
        return !word.isEmpty && word.count <= 24 && !word.hasPrefix("-") && word.unicodeScalars.allSatisfy(allowed.contains)
    }

    /// The API brain's function, as the catalog lists it.
    static let function = ArisAPIFunction(
        name: "currency",
        description: "Convert money between currencies, or get an exchange rate. Use this, never stock and never the web. "
            + "Say the converted amount exactly as returned.",
        parameters: [
            "type": "object",
            "properties": [
                "amount": ["type": "number", "description": "How much to convert (leave out for the rate alone)"],
                "from": ["type": "string", "description": "The currency to convert: an ISO code (CNY) or the user's own word for it (위안, dollar)"],
                "to": ["type": "string", "description": "The currency to convert into (leave out for the user's own currency)"],
            ],
            "required": ["from"],
        ])

    /// The function's arguments as aris-tools' words; nil when they aren't what the schema says.
    static func argv(_ arguments: [String: Any]) -> [String]? {
        var words: [String] = []
        if let amount = arguments["amount"], !(amount is NSNull) {
            guard let text = ArisAPICatalog.text(amount) else { return nil }
            words.append(text)
        }
        guard let from = ArisAPICatalog.text(arguments["from"]) else { return nil }
        words += from.split(separator: " ").map(String.init)
        if let to = arguments["to"], !(to is NSNull) {
            guard let text = to as? String else { return nil }
            words += text.split(separator: " ").map(String.init)
        }
        return ask(words).map { ["currency"] + $0.split(separator: " ").map(String.init) }
    }
}
