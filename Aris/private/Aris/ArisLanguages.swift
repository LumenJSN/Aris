//
//  ArisLanguages.swift
//  Aris
//
//  The languages Aris listens and answers in: ElevenLabs Scribe's list (100 languages,
//  Chinese split into Simplified and Traditional). You turn on the ones you speak; Scribe works out which one each
//  turn is in, and the answer and the voice follow it.
//

import Foundation
import NaturalLanguage

struct ArisLanguage: Hashable, Identifiable {
    let code: String
    let name: String
    let native: String
    var id: String { code }
}

enum ArisLanguages {
    static let defaults = ["ko", "en"]

    /// The languages a new install listens in: the Mac's own preferred languages that Aris has, in their order, then
    /// English. A Mac that speaks Korean (the language or the region among its languages, as ArisHearingLocale reads
    /// it) or says nothing starts with Korean and English, as every install did. It is only the preference's default
    /// (VM run 2026-11-11, bug 10: an English Mac listed 한국어 as a language its user speaks): a choice the user
    /// stored is never read through it.
    static func starting(system: [String]) -> [String] {
        let spoken = system.map { $0.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init) }.filter { !$0.isEmpty }
        let korean = spoken.contains { $0[0].lowercased() == "ko" || $0.dropFirst().contains { $0.uppercased() == "KR" } }
        guard !spoken.isEmpty, !korean else { return defaults }
        return (spoken + [["en"]]).compactMap(code).reduce(into: []) { codes, code in
            if !codes.contains(code) { codes.append(code) }
        }
    }

    /// The list's code for a system language given as its parts ("en", "GB" → "en"; "zh", "Hant", "TW" → "zh-Hant";
    /// "nb", "NO" → "no"); nil for a language Aris can't listen in.
    private static func code(_ parts: [String]) -> String? {
        let base = baseCode(parts[0]), rest = parts.dropFirst().map { $0.lowercased() }
        switch base {
        case "zh": return rest.contains("hant") || (!rest.contains("hans") && rest.contains { ["tw", "hk", "mo"].contains($0) }) ? "zh-Hant" : "zh-Hans"
        case "nb", "nn": return "no"
        case "tl": return "fil"
        default: return all.first { $0.code == base }?.code
        }
    }

    /// The Mac's own preferred languages (System Settings › Language & Region), not this app's 앱 언어 choice: which
    /// languages someone speaks doesn't change with the language they read Aris in.
    static var macLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    }

    static let all: [ArisLanguage] = [
        ("af", "Afrikaans", "Afrikaans"), ("am", "Amharic", "አማርኛ"), ("ar", "Arabic", "العربية"), ("hy", "Armenian", "Հայերեն"),
        ("as", "Assamese", "অসমীয়া"), ("ast", "Asturian", "Asturianu"), ("az", "Azerbaijani", "Azərbaycan"),
        ("be", "Belarusian", "Беларуская"), ("bn", "Bengali", "বাংলা"), ("bs", "Bosnian", "Bosanski"), ("bg", "Bulgarian", "Български"),
        ("my", "Burmese", "မြန်မာ"), ("yue", "Cantonese", "粵語"), ("ca", "Catalan", "Català"), ("ceb", "Cebuano", "Cebuano"),
        ("ny", "Chichewa", "Chichewa"), ("hr", "Croatian", "Hrvatski"), ("cs", "Czech", "Čeština"), ("da", "Danish", "Dansk"),
        ("nl", "Dutch", "Nederlands"), ("en", "English", "English"), ("et", "Estonian", "Eesti"), ("fil", "Filipino", "Filipino"),
        ("fi", "Finnish", "Suomi"), ("fr", "French", "Français"), ("ff", "Fulah", "Fulfulde"), ("gl", "Galician", "Galego"),
        ("lg", "Ganda", "Luganda"), ("ka", "Georgian", "ქართული"), ("de", "German", "Deutsch"), ("el", "Greek", "Ελληνικά"),
        ("gu", "Gujarati", "ગુજરાતી"), ("ha", "Hausa", "Hausa"), ("he", "Hebrew", "עברית"), ("hi", "Hindi", "हिन्दी"),
        ("hu", "Hungarian", "Magyar"), ("is", "Icelandic", "Íslenska"), ("ig", "Igbo", "Igbo"), ("id", "Indonesian", "Bahasa Indonesia"),
        ("ga", "Irish", "Gaeilge"), ("it", "Italian", "Italiano"), ("ja", "Japanese", "日本語"), ("jv", "Javanese", "Basa Jawa"),
        ("kea", "Kabuverdianu", "Kabuverdianu"), ("kn", "Kannada", "ಕನ್ನಡ"), ("kk", "Kazakh", "Қазақ"), ("km", "Khmer", "ខ្មែរ"),
        ("ko", "Korean", "한국어"), ("ku", "Kurdish", "Kurdî"), ("ky", "Kyrgyz", "Кыргызча"), ("lo", "Lao", "ລາວ"),
        ("lv", "Latvian", "Latviešu"), ("ln", "Lingala", "Lingála"), ("lt", "Lithuanian", "Lietuvių"), ("luo", "Luo", "Dholuo"),
        ("lb", "Luxembourgish", "Lëtzebuergesch"), ("mk", "Macedonian", "Македонски"), ("ms", "Malay", "Bahasa Melayu"),
        ("ml", "Malayalam", "മലയാളം"), ("mt", "Maltese", "Malti"), ("zh-Hans", "Chinese (Simplified)", "简体中文"),
        ("zh-Hant", "Chinese (Traditional)", "繁體中文"), ("mi", "Māori", "Te Reo Māori"), ("mr", "Marathi", "मराठी"),
        ("mn", "Mongolian", "Монгол"), ("ne", "Nepali", "नेपाली"), ("nso", "Northern Sotho", "Sesotho sa Leboa"),
        ("no", "Norwegian", "Norsk"), ("oc", "Occitan", "Occitan"), ("or", "Odia", "ଓଡ଼ିଆ"), ("ps", "Pashto", "پښتو"),
        ("fa", "Persian", "فارسی"), ("pl", "Polish", "Polski"), ("pt", "Portuguese", "Português"), ("pa", "Punjabi", "ਪੰਜਾਬੀ"),
        ("ro", "Romanian", "Română"), ("ru", "Russian", "Русский"), ("sr", "Serbian", "Српски"), ("sn", "Shona", "chiShona"),
        ("sd", "Sindhi", "سنڌي"), ("sk", "Slovak", "Slovenčina"), ("sl", "Slovenian", "Slovenščina"), ("so", "Somali", "Soomaali"),
        ("es", "Spanish", "Español"), ("sw", "Swahili", "Kiswahili"), ("sv", "Swedish", "Svenska"), ("ta", "Tamil", "தமிழ்"),
        ("tg", "Tajik", "Тоҷикӣ"), ("te", "Telugu", "తెలుగు"), ("th", "Thai", "ไทย"), ("tr", "Turkish", "Türkçe"),
        ("uk", "Ukrainian", "Українська"), ("umb", "Umbundu", "Umbundu"), ("ur", "Urdu", "اردو"), ("uz", "Uzbek", "Oʻzbek"),
        ("vi", "Vietnamese", "Tiếng Việt"), ("cy", "Welsh", "Cymraeg"), ("wo", "Wolof", "Wolof"), ("xh", "Xhosa", "isiXhosa"),
        ("zu", "Zulu", "isiZulu"),
    ].map { ArisLanguage(code: $0.0, name: $0.1, native: $0.2) }

    static func named(_ code: String) -> ArisLanguage? {
        let base = baseCode(code)
        return all.first { $0.code == code } ?? all.first { baseCode($0.code) == base }
    }

    /// "zh-Hans" → "zh", "ko-KR" → "ko", Scribe's three-letter "kor" → "ko".
    static func baseCode(_ code: String) -> String {
        let lower = code.lowercased()
        let base = String(lower.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? Substring(lower))
        return threeLetter[base] ?? base
    }

    /// The voice locale for a language: the region whose voice people expect.
    static func locale(for code: String) -> String {
        switch code {
        case "zh-Hant": return "zh-TW"
        case "yue": return "zh-HK"
        default: break
        }
        let base = baseCode(code)
        return regions[base].map { "\(base)-\($0)" } ?? base
    }

    /// What NaturalLanguage calls a language, for detecting it in text.
    static func recognizerLanguage(for code: String) -> NLLanguage {
        switch code {
        case "zh-Hans": return .simplifiedChinese
        case "zh-Hant", "yue": return .traditionalChinese
        case "no": return .norwegian
        default: return NLLanguage(baseCode(code))
        }
    }

    private static let regions: [String: String] = [
        "ko": "KR", "en": "US", "ja": "JP", "zh": "CN", "fr": "FR", "de": "DE", "es": "ES", "it": "IT", "pt": "BR",
        "ru": "RU", "nl": "NL", "sv": "SE", "da": "DK", "fi": "FI", "no": "NO", "pl": "PL", "tr": "TR", "ar": "SA",
        "he": "IL", "hi": "IN", "th": "TH", "vi": "VN", "id": "ID", "ms": "MY", "uk": "UA", "cs": "CZ", "sk": "SK",
        "hu": "HU", "ro": "RO", "el": "GR", "bg": "BG", "hr": "HR", "ca": "ES",
    ]

    private static let threeLetter: [String: String] = [
        "kor": "ko", "eng": "en", "jpn": "ja", "zho": "zh", "cmn": "zh", "fra": "fr", "deu": "de", "spa": "es",
        "ita": "it", "por": "pt", "rus": "ru", "nld": "nl", "swe": "sv", "dan": "da", "fin": "fi", "nor": "no",
        "pol": "pl", "tur": "tr", "ara": "ar", "heb": "he", "hin": "hi", "tha": "th", "vie": "vi", "ind": "id",
        "msa": "ms", "ukr": "uk", "ces": "cs", "slk": "sk", "hun": "hu", "ron": "ro", "ell": "el", "bul": "bg",
        "hrv": "hr", "cat": "ca", "fil": "fil", "tgl": "fil",
    ]
}
