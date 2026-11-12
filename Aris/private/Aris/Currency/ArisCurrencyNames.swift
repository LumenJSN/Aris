//
//  ArisCurrencyNames.swift
//  Aris (also built into aris-tools)
//
//  The currencies Aris converts, by the names people say: an ISO code ("CAD"), or a name in Korean or English ("캐나다
//  달러", "캐달", "위안", "중국 돈", "RMB", "won"). "달러" or "dollar" with no country names no one currency: whoever
//  reads the sentence decides which dollar it is (ArisCurrencyDollar). Also each currency's name as Aris says it, and
//  how many decimals its amounts have. Foundation only (tested).
//

import Foundation

enum ArisCurrencyNames {
    /// What a word names: one currency, or a dollar with no country.
    enum Named: Equatable {
        case code(String)
        case bareDollar
    }

    struct Entry {
        let code: String
        /// As Aris says it in Korean ("캐나다 달러") and in English, one and many ("Canadian dollar", "Canadian dollars").
        let korean: String
        let english: String
        let plural: String
        /// Every other way it is said, any spacing and case.
        let words: [String]
    }

    static let entries: [Entry] = [
        Entry(code: "USD", korean: "미국 달러", english: "US dollar", plural: "US dollars",
              words: ["미국달러", "미달러", "미화", "미국돈", "유에스달러", "미국달러화", "us dollar", "us dollars", "u.s. dollar", "u.s. dollars",
                      "american dollar", "american dollars", "usd"]),
        Entry(code: "CAD", korean: "캐나다 달러", english: "Canadian dollar", plural: "Canadian dollars",
              words: ["캐나다달러", "캐달", "캐나다돈", "캐네디언달러", "캐나디안달러", "캐나디언달러", "캐나다달러화", "canadian dollar", "canadian dollars",
                      "canada dollar", "canada dollars", "loonie", "loonies"]),
        Entry(code: "KRW", korean: "원", english: "won", plural: "won",
              words: ["원", "원화", "한국돈", "한국원", "한화", "한국원화", "won", "korean won", "south korean won"]),
        Entry(code: "JPY", korean: "엔", english: "yen", plural: "yen",
              words: ["엔", "엔화", "일본엔", "일본돈", "일본엔화", "yen", "japanese yen"]),
        Entry(code: "CNY", korean: "위안", english: "yuan", plural: "yuan",
              words: ["위안", "위엔", "위안화", "위엔화", "중국돈", "중국위안", "중국위안화", "인민폐", "런민비", "rmb", "yuan", "renminbi", "chinese yuan"]),
        Entry(code: "EUR", korean: "유로", english: "euro", plural: "euros", words: ["유로", "유로화", "euro", "euros"]),
        Entry(code: "GBP", korean: "파운드", english: "pound", plural: "pounds",
              words: ["파운드", "영국파운드", "파운드화", "영국돈", "pound", "pounds", "pound sterling", "pounds sterling", "british pound",
                      "british pounds", "sterling", "quid"]),
        Entry(code: "AUD", korean: "호주 달러", english: "Australian dollar", plural: "Australian dollars",
              words: ["호주달러", "호주돈", "호달", "australian dollar", "australian dollars", "aussie dollar", "aussie dollars"]),
        Entry(code: "HKD", korean: "홍콩 달러", english: "Hong Kong dollar", plural: "Hong Kong dollars",
              words: ["홍콩달러", "홍달", "홍콩돈", "hong kong dollar", "hong kong dollars"]),
        Entry(code: "TWD", korean: "대만 달러", english: "Taiwan dollar", plural: "Taiwan dollars",
              words: ["대만달러", "타이완달러", "대만돈", "ntd", "taiwan dollar", "taiwan dollars", "new taiwan dollar", "new taiwan dollars"]),
        Entry(code: "SGD", korean: "싱가포르 달러", english: "Singapore dollar", plural: "Singapore dollars",
              words: ["싱가포르달러", "싱가폴달러", "싱달", "singapore dollar", "singapore dollars"]),
        Entry(code: "NZD", korean: "뉴질랜드 달러", english: "New Zealand dollar", plural: "New Zealand dollars",
              words: ["뉴질랜드달러", "new zealand dollar", "new zealand dollars", "kiwi dollar", "kiwi dollars"]),
        Entry(code: "CHF", korean: "스위스 프랑", english: "Swiss franc", plural: "Swiss francs",
              words: ["프랑", "스위스프랑", "franc", "francs", "swiss franc", "swiss francs"]),
        Entry(code: "MXN", korean: "멕시코 페소", english: "Mexican peso", plural: "Mexican pesos",
              words: ["페소", "멕시코페소", "peso", "pesos", "mexican peso", "mexican pesos"]),
        Entry(code: "PHP", korean: "필리핀 페소", english: "Philippine peso", plural: "Philippine pesos",
              words: ["필리핀페소", "philippine peso", "philippine pesos"]),
        Entry(code: "INR", korean: "인도 루피", english: "Indian rupee", plural: "Indian rupees",
              words: ["루피", "인도루피", "rupee", "rupees", "indian rupee", "indian rupees"]),
        Entry(code: "VND", korean: "베트남 동", english: "Vietnamese dong", plural: "Vietnamese dong",
              words: ["동", "베트남동", "동화", "dong", "vietnamese dong"]),
        Entry(code: "THB", korean: "태국 바트", english: "Thai baht", plural: "Thai baht",
              words: ["바트", "밧", "태국바트", "baht", "thai baht"]),
        Entry(code: "IDR", korean: "인도네시아 루피아", english: "Indonesian rupiah", plural: "Indonesian rupiah",
              words: ["루피아", "인도네시아루피아", "rupiah", "indonesian rupiah"]),
        Entry(code: "MYR", korean: "말레이시아 링깃", english: "Malaysian ringgit", plural: "Malaysian ringgit",
              words: ["링깃", "말레이시아링깃", "ringgit", "malaysian ringgit"]),
    ]

    /// "달러" with no country, as it is said.
    static let bareDollarWords: Set<String> = ["달러", "달라", "달러화", "불", "dollar", "dollars", "bucks", "$"]

    /// The dollars: on a Mac whose own money is one of them, "달러" alone could mean it.
    static let dollars: Set<String> = ["USD", "CAD", "AUD", "HKD", "TWD", "SGD", "NZD"]

    /// No decimals in everyday amounts: 1,432원, 930엔.
    static let wholeOnly: Set<String> = ["KRW", "JPY", "VND", "IDR"]

    private static let byCode: [String: Entry] = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })

    private static let byWord: [String: String] = {
        var table: [String: String] = [:]
        for entry in entries {
            for word in entry.words + [entry.code] { table[key(word)] = entry.code }
        }
        return table
    }()

    /// A name as the table holds it: lower case, no spaces, no dots ("U.S. Dollar" is "usdollar").
    static func key(_ words: String) -> String {
        words.lowercased().filter { !$0.isWhitespace && $0 != "." }
    }

    /// What `words` name: a currency of the table, a dollar with no country, or nothing.
    static func named(_ words: String) -> Named? {
        let key = key(words)
        if bareDollarWords.contains(key) { return .bareDollar }
        return byWord[key].map(Named.code)
    }

    /// An ISO code as typed to the tool ("SEK"), one the Mac knows, whether or not the table names it.
    static func isCode(_ text: String) -> Bool {
        guard text.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else { return false }
        return byCode[text] != nil || isoCodes.contains(text)
    }

    private static let isoCodes: Set<String> = Set(Locale.Currency.isoCurrencies.map { $0.identifier.uppercased() })

    static func isDollar(_ code: String) -> Bool { dollars.contains(code) }

    /// How many decimals an amount in `code` has: none for won and yen, two otherwise.
    static func decimals(_ code: String) -> Int { wholeOnly.contains(code) ? 0 : 2 }

    /// The currency's name as Aris says it: "캐나다 달러", "Canadian dollars" (`one`: "Canadian dollar"). A code the
    /// table doesn't name is said as macOS names it, or as the code itself.
    static func name(_ code: String, korean: Bool, one: Bool = false) -> String {
        if let entry = byCode[code] { return korean ? entry.korean : one ? entry.english : entry.plural }
        return Locale(identifier: korean ? "ko_KR" : "en_US").localizedString(forCurrencyCode: code) ?? code
    }
}
