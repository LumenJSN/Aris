//
//  ArisHearingLocale.swift
//  Aris
//
//  Which language Apple's on-device recogniser listens in. It was fixed to Korean, so without an ElevenLabs key every
//  other language was written down as nonsense Hangul and sent to the AI like that (audit voice-6). Now it is the
//  first language the user turned on that the Mac's recogniser has; and on a Mac whose languages were never chosen and
//  whose system isn't Korean, the system's language (an English Mac is heard in English). Korean stays the fallback.
//  Pure: the caller hands in the setting, the system's languages and the recogniser's list.
//

import Foundation

enum ArisHearingLocale {
    static let fallback = "ko-KR"

    /// The recogniser's locale, as one of `supported`'s own identifiers (so it is exactly what the recogniser has).
    /// `chosen`: the languages turned on, in order. `chosenByUser`: that setting was ever changed (else it is the
    /// built-in Korean and English). `system`: the Mac's preferred languages. `supported`: the recogniser's locales.
    static func pick(chosen: [String], chosenByUser: Bool, system: [String], supported: [String]) -> String {
        for language in wanted(chosen: chosen, chosenByUser: chosenByUser, system: system) {
            if let found = match(language, system: system, supported: supported) { return found }
        }
        return supported.first { same(parts($0), parts(fallback)) } ?? fallback
    }

    /// The languages to try, best first, one of each. The user's own choice is taken in their order. With the setting
    /// untouched, a Mac that speaks Korean (a Korean language or region among its languages) keeps Korean first, as
    /// before; any other Mac is heard in its own languages first, then English (the likelier second language there
    /// than Korean).
    static func wanted(chosen: [String], chosenByUser: Bool, system: [String]) -> [String] {
        if chosenByUser || system.isEmpty || speaksKorean(system) { return unique(chosen) }
        return unique(system + ["en"] + chosen)
    }

    /// Korean among the Mac's languages, or Korea as a region ("en-KR": an English system in Korea).
    static func speaksKorean(_ system: [String]) -> Bool {
        system.contains { identifier in
            let parts = parts(identifier)
            return parts.language == "ko" || parts.region == "KR"
        }
    }

    /// The recogniser's locale for a language (a code such as "en", "zh-Hant" or "en-GB"): the system's own region of
    /// it when the recogniser has that ("en-GB"), else the region people expect (ArisLanguages.locale: "en-US",
    /// "zh-TW"), else any locale of the language.
    private static func match(_ code: String, system: [String], supported: [String]) -> String? {
        let language = parts(code).language
        let ofLanguage = supported.filter { parts($0).language == language }
        guard !ofLanguage.isEmpty else { return nil }
        let preferred = [parts(code)] + system.map(parts).filter { $0.language == language } + [parts(ArisLanguages.locale(for: code))]
        for want in preferred where want.region != nil {
            if let found = ofLanguage.first(where: { same(parts($0), want) }) { return found }
        }
        return ofLanguage.first
    }

    /// "en_US", "en-US", "zh-Hans-CN" → (en, US), (en, US), (zh, CN). The language is its two-letter base.
    private static func parts(_ identifier: String) -> (language: String, region: String?) {
        let pieces = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        let region = pieces.dropFirst().first { ($0.count == 2 && $0.allSatisfy(\.isLetter)) || ($0.count == 3 && $0.allSatisfy(\.isNumber)) }
        return (ArisLanguages.baseCode(pieces.first ?? identifier), region?.uppercased())
    }

    private static func same(_ one: (language: String, region: String?), _ other: (language: String, region: String?)) -> Bool {
        one.language == other.language && one.region == other.region
    }

    /// The first code of each language.
    private static func unique(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        return codes.filter { !$0.isEmpty && seen.insert(parts($0).language).inserted }
    }

    /// Words the recogniser is told to expect, with Aris's own name while it checks for the wake word in a language
    /// other than Korean: an English recogniser writes an unhinted "Aris" as "Iris" or "Harris".
    static func hints(vocabulary: [String], locale: String, waitingForWakeWord: Bool) -> [String] {
        guard waitingForWakeWord, parts(locale).language != "ko", !vocabulary.contains("Aris") else { return vocabulary }
        return vocabulary + ["Aris"]
    }
}

/// The writing systems a transcript can be in, to tell which recogniser to believe (ArisTranscript.pick): Apple's
/// writes its one language; Whisper's words in another script are another language spoken.
enum ArisScript: Hashable {
    case latin, hangul, kana, han, cyrillic, arabic, hebrew, devanagari, thai, greek, other

    /// The scripts a language is written in (by its code; anything not listed is written in Latin letters).
    static func writing(_ code: String) -> Set<ArisScript> {
        switch ArisLanguages.baseCode(code) {
        case "ko": [.hangul]
        case "ja": [.kana, .han]
        case "zh", "yue": [.han]
        case "ru", "uk", "bg", "mk", "be", "kk", "ky", "mn", "tg": [.cyrillic]
        case "sr": [.cyrillic, .latin]
        case "ar", "fa", "ur", "ps", "sd", "ku": [.arabic]
        case "he": [.hebrew]
        case "hi", "mr", "ne": [.devanagari]
        case "th": [.thai]
        case "el": [.greek]
        case "am", "hy", "as", "bn", "my", "ka", "gu", "kn", "km", "lo", "ml", "or", "pa", "ta", "te": [.other]
        default: [.latin]
        }
    }

    /// The scripts `text` is written in. Latin counts from a word of two letters (as Whisper's English always has);
    /// a lone letter is a unit or a label.
    static func used(in text: String) -> Set<ArisScript> {
        var found = Set<ArisScript>()
        if text.range(of: "[A-Za-z]{2,}", options: .regularExpression) != nil { found.insert(.latin) }
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0000...0x024F, 0x1E00...0x1EFF: continue
            case 0xAC00...0xD7A3, 0x1100...0x11FF, 0x3131...0x318E: found.insert(.hangul)
            case 0x3040...0x30FF, 0x31F0...0x31FF: found.insert(.kana)
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: found.insert(.han)
            case 0x0400...0x052F: found.insert(.cyrillic)
            case 0x0600...0x06FF, 0x0750...0x077F: found.insert(.arabic)
            case 0x0590...0x05FF: found.insert(.hebrew)
            case 0x0900...0x097F: found.insert(.devanagari)
            case 0x0E00...0x0E7F: found.insert(.thai)
            case 0x0370...0x03FF: found.insert(.greek)
            default: if scalar.properties.isAlphabetic { found.insert(.other) }
            }
        }
        return found
    }
}
