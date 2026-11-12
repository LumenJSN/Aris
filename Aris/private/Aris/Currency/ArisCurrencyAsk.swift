//
//  ArisCurrencyAsk.swift
//  Aris
//
//  A plain currency question, read here on the Mac with no AI (as the timer and the time are): "100 위안 캐나다 달러로
//  얼마야", "how much is 100 CNY in CAD", "달러 환율", "엔화 환율 알려 줘", "50유로는 원화로?". Every word of the
//  sentence must be an amount, a currency or one of a few small words ("얼마야", "환율", "알려 줘", "how much is"):
//  anything else in it ("달러 인덱스", "환율 뉴스 알려 줘", "100달러짜리 선물 추천해 줘", a stock's name) makes it the
//  AI's, as before. A correction inside the sentence ("100 캐나다 달러가… 아니, 100 중국 돈이 캐나다 달러로") is read
//  from its last part, and only when that part says the whole question. "달러" alone is decided by the Mac's own
//  currency (ArisCurrencyDollar), and one currency with no target is converted to the Mac's own. Foundation only (tested).
//

import Foundation

/// A conversion asked in plain words: this much of `from`, in `to`.
struct ArisCurrencyAsk: Equatable, Sendable {
    let amount: Double
    let from: String
    let to: String
    /// The dollar a bare "달러" was taken as, when either could have been meant: the card says so.
    let assumed: String?

    /// The words aris-tools takes for it: "100 CNY CAD".
    var words: String { "\(ArisCurrencyMath.argument(amount)) \(from) \(to)" }
}

enum ArisCurrencyRead {
    private enum Item: Equatable {
        case amount(Double)
        /// `target`: marked as what to convert into ("…로", "in …", "몇 …"). `short`: a name of one syllable (원, 엔, 동,
        /// 불), which is also half of other words ("원가", "불이").
        case money(ArisCurrencyNames.Named, target: Bool, short: Bool)
        case word(String)
    }

    /// The conversion `spoken` asks for; nil when it is anything but a plain currency question.
    static func parse(_ spoken: String, home: String) -> ArisCurrencyAsk? {
        guard home.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil, spoken.count <= 160 else { return nil }
        let words = lastReading(clean(spoken))
        guard !words.isEmpty, words.count <= 16, let items = lex(words) else { return nil }
        return decide(items, home: home)
    }

    // MARK: - Words

    private static let symbols: [Character: String] = ["$": "$", "€": "eur", "£": "gbp", "₩": "krw", "¥": "jpy"]

    /// Lower case, marks as spaces (a dot or a comma stays only inside a number), and a currency sign as a word of its
    /// own after its number ("$100" is read "100 $").
    static func clean(_ spoken: String) -> [String] {
        let lowered = Array(spoken.lowercased().replacingOccurrences(of: "’", with: "'"))
        var out = ""
        for (index, character) in lowered.enumerated() {
            if let sign = symbols[character] {
                out += " \(sign) "
            } else if character == "." || character == "," {
                let inNumber = index > 0 && index + 1 < lowered.count && isDigit(lowered[index - 1]) && isDigit(lowered[index + 1])
                out.append(inNumber ? character : " ")
            } else {
                out.append(character.isLetter || character.isNumber || character == "'" ? character : " ")
            }
        }
        var words = out.split(whereSeparator: \.isWhitespace).map(String.init)
        for index in words.indices.dropLast() where symbols.values.contains(words[index]) && words[index + 1].first.map(isDigit) == true {
            words.swapAt(index, index + 1)
        }
        return words
    }

    private static func isDigit(_ character: Character) -> Bool { character.isASCII && character.isNumber }

    /// Words that take back what was just said: what follows the last one is the reading.
    private static let corrections: Set<String> = ["아니", "아니야", "아니요", "아니다", "아냐", "아니라", "말고", "잠깐", "잠깐만", "no", "nope", "sorry",
                                                   "actually", "wait", "mean", "rather"]

    static func lastReading(_ words: [String]) -> [String] {
        guard let last = words.lastIndex(where: corrections.contains) else { return words }
        return Array(words[(last + 1)...])
    }

    // MARK: - Amounts

    private static let sinoDigits: [Character: Double] = ["일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "칠": 7, "팔": 8, "구": 9]
    private static let sinoUnits: [Character: Double] = ["십": 10, "백": 100, "천": 1_000]
    private static let bigUnits: [(String, Double)] = [("억", 1e8), ("만", 1e4)]
    private static let englishNumbers: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90, "a": 1, "an": 1,
    ]
    private static let multipliers: [String: Double] = ["hundred": 100, "thousand": 1_000, "k": 1_000, "million": 1e6, "billion": 1e9]

    /// "100", "1,000", "19.5", "백", "5만", "3천5백", "1억 2천만" (no spaces): the number, or nil.
    static func number(_ text: String) -> Double? {
        var rest = text, total = 0.0
        for (unit, value) in bigUnits {
            guard let at = rest.range(of: unit) else { continue }
            let head = String(rest[..<at.lowerBound])
            guard let count = head.isEmpty ? 1 : small(head), count > 0 else { return nil }
            total += count * value
            rest = String(rest[at.upperBound...])
        }
        if !rest.isEmpty {
            guard let ones = small(rest) else { return nil }
            total += ones
        }
        return ArisCurrencyMath.isAmount(total) ? total : nil
    }

    /// Below 만: digits ("250", "1.5"), or Korean numerals with 천, 백, 십 in falling order ("천오백", "3천").
    private static func small(_ text: String) -> Double? {
        let plain = text.replacingOccurrences(of: ",", with: "")
        if plain.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil { return Double(plain) }
        var total = 0.0, pending: Double?, lastUnit = Double.infinity, digits = ""
        for character in plain {
            if isDigit(character) || character == "." {
                guard pending == nil else { return nil }
                digits.append(character)
                continue
            }
            if !digits.isEmpty {
                guard let value = Double(digits) else { return nil }
                pending = value
                digits = ""
            }
            if let digit = sinoDigits[character] {
                guard pending == nil else { return nil }
                pending = digit
            } else if let unit = sinoUnits[character], unit < lastUnit {
                total += (pending ?? 1) * unit
                pending = nil
                lastUnit = unit
            } else {
                return nil
            }
        }
        if !digits.isEmpty {
            guard pending == nil, let value = Double(digits) else { return nil }
            pending = value
        }
        return total + (pending ?? 0)
    }

    private static func isNumeral(_ character: Character) -> Bool {
        isDigit(character) || character == "," || character == "." || sinoDigits[character] != nil || sinoUnits[character] != nil
            || character == "만" || character == "억"
    }

    /// A number said only in Korean numerals counts when it has a unit ("백", "이천"): "이" alone is "this".
    private static func standsAlone(_ text: String) -> Bool {
        text.contains(where: isDigit) || text.contains { sinoUnits[$0] != nil || $0 == "만" || $0 == "억" }
    }

    // MARK: - Currencies

    /// Particles a currency's name may carry; the first group marks what to convert into.
    private static let targetParticles = ["으로는", "로는", "으로", "로"]
    private static let otherParticles = ["에서", "이면", "은", "는", "이", "가", "을", "를", "의", "도", "면", "에"]
    /// After "몇": "몇 달러야", "몇 원이에요".
    private static let endings = ["이에요", "인가요", "예요", "에요", "인지", "이지", "이야", "이니", "이냐", "이죠", "일까", "인가", "야", "지", "니", "냐", "죠"]
    private static let targetBefore: Set<String> = ["to", "in", "into", "몇", "many"]

    /// The currency named by the words at `index` (up to three, the last one with its particle), how many words it
    /// took, and whether its particle marks it as the target.
    private static func money(at index: Int, in words: [String],
                              after previous: String?) -> (named: ArisCurrencyNames.Named, taken: Int, target: Bool, short: Bool)? {
        let marked = previous.map(targetBefore.contains) ?? false
        for length in stride(from: min(3, words.count - index), through: 1, by: -1) {
            let lead = words[index..<(index + length - 1)].joined()
            let last = words[index + length - 1]
            if let named = ArisCurrencyNames.named(lead + last) { return (named, length, marked, (lead + last).count == 1) }
            for particle in targetParticles + otherParticles + (previous == "몇" ? endings : []) where last.hasSuffix(particle) && last.count > particle.count {
                let name = lead + String(last.dropLast(particle.count))
                guard let named = ArisCurrencyNames.named(name) else { continue }
                return (named, length, marked || targetParticles.contains(particle), name.count == 1)
            }
        }
        return nil
    }

    /// The sentence as amounts, currencies and the words left; nil when an amount can't be read.
    private static func lex(_ source: [String]) -> [Item]? {
        var words = source, items: [Item] = [], index = 0
        func previousWord() -> String? {
            if case .word(let word)? = items.last { return word }
            return nil
        }
        while index < words.count {
            if let found = money(at: index, in: words, after: previousWord()) {
                items.append(.money(found.named, target: found.target, short: found.short))
                index += found.taken
                continue
            }
            let word = words[index]
            if let amount = amount(at: index, in: &words) {
                items.append(.amount(amount))
                // "100위안": the currency glued to the number is read next, from what is left of the word.
                if words[index] == word { index += 1 }
                index = multiplied(&items, words, index)
                continue
            }
            items.append(.word(word))
            index += 1
        }
        return items
    }

    /// The amount the word at `index` starts with: the whole word ("100", "백" before a currency), or its front with a
    /// currency glued on ("100위안", "5만원"), which is then left in `words[index]`.
    private static func amount(at index: Int, in words: inout [String]) -> Double? {
        let word = words[index]
        if let said = englishNumbers[word] {
            let next = index + 1 < words.count ? words[index + 1] : ""
            let counts = multipliers[next] != nil || (word.count > 2 && money(at: index + 1, in: words, after: nil) != nil)
            return counts ? said : nil
        }
        let run = word.prefix(while: isNumeral)
        for cut in stride(from: run.count, through: 1, by: -1) {
            let front = String(word.prefix(cut)), rest = String(word.dropFirst(cut))
            guard let value = number(front) else { continue }
            if rest.isEmpty {
                if front.contains(where: isDigit) { return value }
                guard standsAlone(front), index + 1 < words.count, money(at: index + 1, in: words, after: nil) != nil else { continue }
                return value
            }
            if rest == "k" { words[index] = "k"; return value }
            var glued = words
            glued[index] = rest
            guard standsAlone(front) || front.count > 1, money(at: index, in: glued, after: nil) != nil else { continue }
            words = glued
            return value
        }
        return nil
    }

    /// "5 thousand", "2 million", "5k": the amount just read, times the word after it.
    private static func multiplied(_ items: inout [Item], _ words: [String], _ index: Int) -> Int {
        guard index < words.count, let times = multipliers[words[index]], case .amount(let value)? = items.last else { return index }
        items[items.count - 1] = .amount(value * times)
        return index + 1
    }

    // MARK: - What is asked

    private static let small: [String] = [
        #"^얼마(야|예요|에요|지|니|냐|죠|인지|인가|인가요|일까|임|나|쯤|정도|돼|돼요|되지|되나|되나요)?$"#, #"^얼만(지|가|가요)$"#,
        #"^환율(은|이|을|로|도|좀)?$"#, #"^환전(하면|해|해줘|해서|시)?$"#, #"^(바꾸면|바꿔|바꿔줘|바꿔서)$"#, #"^계산(해|해줘|하면|해서)?$"#,
        #"^(알려|말해|보여)(줘|줘요|주세요|줄래|줄래요|줘봐|봐)?$"#, #"^(줘|줘요|주세요|줄래|줄래요)$"#, #"^아리스(야)?$"#,
        #"^(좀|지금|현재|오늘|요즘|요|대략|약|한|정도|쯤|몇|하면|이면|면|은|는|이|가|을|를|로|으로|에|에서|어때|어때요|어떻게|돼|돼요|되지|되나|되나요|되는지|되니)$"#,
        #"^(how|much|many|is|are|what|what's|whats|the|a|an|in|to|into|of|for|from|rates?|exchange|convert|conversion|converted|worth|please|now|right|today)$"#,
        #"^(current|currently|me|tell|show|give|can|could|would|will|you|be|get|do|does|i|and|equals?|hey|aris|at|value)$"#,
    ]
    /// A word that makes the sentence a question about a rate or an amount of money.
    private static let asking = #"^(얼마.*|얼만.*|환율.*|환전.*|바꾸면|바꿔.*|계산.*|몇|how|rates?|exchange|convert|conversion|converted|worth|equals?)$"#
    private static let rateWord = #"^(환율.*|rates?|exchange)$"#

    private static func matches(_ word: String, _ pattern: String) -> Bool { word.range(of: pattern, options: .regularExpression) != nil }

    /// Stronger first: with two currencies and no direction ("원 달러 환율", "유로 달러 환율") the rate is told for one of
    /// the stronger in the weaker, as it is quoted.
    private static let quoteOrder = ["GBP", "EUR", "CHF", "USD", "CAD", "SGD", "AUD", "NZD", "MYR", "CNY", "HKD", "TWD", "THB", "MXN", "PHP", "INR",
                                     "JPY", "KRW", "IDR", "VND"]

    private static func decide(_ items: [Item], home: String) -> ArisCurrencyAsk? {
        var amounts: [(index: Int, value: Double)] = [], words: [String] = []
        var monies: [(index: Int, named: ArisCurrencyNames.Named, target: Bool, short: Bool)] = []
        for (index, item) in items.enumerated() {
            switch item {
            case .amount(let value): amounts.append((index, value))
            case .money(let named, let target, let short): monies.append((index, named, target, short))
            case .word(let word): words.append(word)
            }
        }
        guard words.allSatisfy({ word in small.contains { matches(word, $0) } }), amounts.count <= 1, monies.count <= 2 else { return nil }
        let asks = words.contains { matches($0, asking) } || monies.contains { $0.target }
        let rate = words.contains { matches($0, rateWord) }
        guard asks else { return nil }
        // The amount is of the currency said right after it.
        let counted = amounts.first.flatMap { amount in monies.firstIndex { $0.index == amount.index + 1 } }
        if amounts.first != nil, counted == nil { return nil }
        // A one-syllable name is money only where nothing else fits: after its amount, as the target, or beside "환율".
        let loose = monies.enumerated().contains { offset, money in money.short && !money.target && counted != offset }
        if loose, !rate { return nil }
        switch monies.count {
        case 0:
            // "환율 알려 줘", "what's the exchange rate": the US dollar in the Mac's own money, and the card says which
            // dollar. ("What's the rate" could be any rate: the AI's.)
            let exchange = words.contains { matches($0, "^환율.*$") } || (words.contains("exchange") && words.contains { matches($0, "^rates?$") })
            guard exchange, amounts.isEmpty, home != "USD" else { return nil }
            return ask(nil, from: .code("USD"), to: .code(home), home: home, assumed: "USD")
        case 1:
            guard !monies[0].target else { return nil }
            return ask(amounts.first?.value, from: monies[0].named, to: .code(home), home: home)
        default:
            let targets = monies.filter(\.target)
            guard targets.count <= 1 else { return nil }
            let source: Int
            if let target = targets.first {
                source = monies[0].index == target.index ? 1 : 0
            } else if let counted {
                source = counted
            } else if rate {
                // "원 달러 환율": a pair with no direction, where a bare dollar is the US one whichever way it is said.
                source = strength(monies[0].named) <= strength(monies[1].named) ? 0 : 1
                let dollar = { (named: ArisCurrencyNames.Named) in named == .bareDollar ? .code("USD") : named }
                let guessed = monies.contains { $0.named == .bareDollar } && ArisCurrencyNames.isDollar(home) && home != "USD"
                return ask(nil, from: dollar(monies[source].named), to: dollar(monies[1 - source].named), home: home, assumed: guessed ? "USD" : nil)
            } else {
                return nil
            }
            if let counted, counted != source { return nil }
            return ask(amounts.first?.value, from: monies[source].named, to: monies[1 - source].named, home: home)
        }
    }

    private static func strength(_ named: ArisCurrencyNames.Named) -> Int {
        guard case .code(let code) = named else { return quoteOrder.firstIndex(of: "USD") ?? 0 }
        return quoteOrder.firstIndex(of: code) ?? quoteOrder.count
    }

    /// The conversion with each bare dollar decided; nil when both sides are the same money.
    private static func ask(_ amount: Double?, from: ArisCurrencyNames.Named, to: ArisCurrencyNames.Named, home: String,
                            assumed forced: String? = nil) -> ArisCurrencyAsk? {
        guard let pair = ArisCurrencyDollar.pair(from: from, to: to, home: home) else { return nil }
        return ArisCurrencyAsk(amount: amount ?? ArisCurrencyMath.usualAmount(pair.from), from: pair.from, to: pair.to, assumed: forced ?? pair.assumed)
    }
}
