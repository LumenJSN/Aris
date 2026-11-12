//
//  ArisSpeech.swift
//  Aris
//
//  What Aris says out loud and in which voice. The full answer stays on screen;
//  only the first sentences are spoken, without markdown.
//

import Foundation
import NaturalLanguage

enum ArisSpeech {
    struct Voice: Equatable {
        let identifier: String
        let language: String
        /// AVSpeechSynthesisVoiceQuality raw value: 1 default, 2 enhanced, 3 premium.
        let quality: Int
    }

    static func spokenPart(of text: String, sentences: Int = 2) -> String {
        let plain = plainText(text)
        var spoken: [String] = []
        var current = ""
        let characters = Array(plain)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let ends = ".!?。".contains(character)
            let atBoundary = index + 1 == characters.count || characters[index + 1] == " "
            if ends && atBoundary && !(character == "." && endsWithAbbreviation(current)) {
                spoken.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                if spoken.count == sentences { break }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if spoken.count < sentences && !rest.isEmpty { spoken.append(rest) }
        return spoken.joined(separator: " ")
    }

    /// One sentence from the splitter, as it should be read: whole (a short "네." was already joined to the
    /// sentence after it), without markdown, emoji or addresses.
    static func spoken(_ sentence: String) -> String { plainText(sentence) }

    /// Titles and Latin shorthand whose full stop doesn't end the sentence ("Dr. Kim", "e.g. tomorrow"), and a
    /// lone capital initial ("J. Kim").
    private static let abbreviations: Set<String> = ["dr", "mr", "mrs", "ms", "prof", "st", "vs", "jr", "sr", "no", "fig"]

    /// Whether `text`, which ends in ".", ends in an abbreviation rather than a sentence.
    static func endsWithAbbreviation(_ text: String) -> Bool {
        guard text.hasSuffix(".") else { return false }
        let word = text.dropLast().split(whereSeparator: { $0.isWhitespace || $0 == "(" || $0 == "\"" }).last.map(String.init) ?? ""
        guard !word.isEmpty, word.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == ".") }) else { return false }
        if word.contains(".") { return word.split(separator: ".").allSatisfy { $0.count <= 2 } }  // e.g, i.e, U.S; not hello.txt
        if word.count == 1 { return word.first!.isUppercase }  // an initial
        return abbreviations.contains(word.lowercased())
    }

    /// The voice locale for `text`: Korean for anything with Hangul in it, else whichever of `languages` (the ones
    /// turned on) it reads as, English when nothing fits.
    /// The note Aris itself adds to a request with files (ArisPendingFiles.note, Korean) is never part of the words:
    /// with it, an English request with a dropped file read as Korean, and Aris's own lines for that turn came out in
    /// Korean on an English Mac.
    static func language(of said: String, among languages: [String] = ArisLanguages.defaults) -> String {
        let text = ArisPendingFiles.ownWords(said)
        if text.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }) {
            return "ko-KR"
        }
        let candidates = languages.filter { ArisLanguages.baseCode($0) != "ko" }
        guard candidates.count > 1 else { return ArisLanguages.locale(for: candidates.first ?? "en") }
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = candidates.map(ArisLanguages.recognizerLanguage(for:))
        recognizer.processString(text)
        guard let found = recognizer.dominantLanguage,
              let code = candidates.first(where: { ArisLanguages.recognizerLanguage(for: $0) == found }) else {
            return candidates.contains("en") ? "en-US" : ArisLanguages.locale(for: candidates[0])
        }
        return ArisLanguages.locale(for: code)
    }

    /// The best installed voice: premium over enhanced over default, and a natural
    /// voice over the robotic Eloquence and novelty ones. Another region's voice of the language when there's
    /// none for this one.
    /// `preferred`: the voice picked in settings (AI 서비스 › 말하기 › 목소리). It speaks its own language; any other
    /// language still gets that language's best voice.
    static func pickVoice(from voices: [Voice], language: String, preferred: String = "") -> String? {
        if !preferred.isEmpty, let pick = voices.first(where: { $0.identifier == preferred }),
           ArisLanguages.baseCode(pick.language) == ArisLanguages.baseCode(language) {
            return pick.identifier
        }
        let exact = voices.filter { $0.language == language }
        let base = ArisLanguages.baseCode(language)
        let pool = exact.isEmpty ? voices.filter { ArisLanguages.baseCode($0.language) == base } : exact
        return pool.max { rank($0) < rank($1) }?.identifier
    }

    private static func rank(_ voice: Voice) -> Int {
        let robotic = voice.identifier.contains("eloquence") || voice.identifier.contains("speech.synthesis")
        return voice.quality * 10 + (robotic ? 0 : 5)
    }

    private static func plainText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A table: the |---|---| rule goes, each row is read as its cells.
            if trimmed.hasPrefix("|") {
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if cells.allSatisfy({ $0.allSatisfy { "-:".contains($0) } }) { return nil }
                return cells.joined(separator: ", ") + "."
            }
            return trimmed.replacingOccurrences(of: "^(#+|>+|[-*•]|[0-9]+[.)])\\s+", with: "", options: .regularExpression)
        }
        let joined = lines.joined(separator: " ")
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            // "링크: https://…" says nothing once the address is gone.
            .replacingOccurrences(of: #"(?i)\s*(링크|주소|출처|사이트|link|url|source)\s*:\s*<?https?://\S+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*<?https?://[^\s>]+>?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #":\s*(?=$|[.!?,])"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "~~", with: "")
            .replacingOccurrences(of: "`", with: "")
            // *emphasis* and _emphasis_: the marks go; a lone "5 * 3" stays.
            .replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]*?\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\w)_(?=\S)([^_\n]*?\S)_"#, with: "$1", options: .regularExpression)
        return withoutEmoji(joined)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([.,!?])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Pictographs, their skin tones, joiners and variation selectors: a voice reads 👍 as "thumbs up".
    private static func withoutEmoji(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let pictograph = scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && value >= 0x2300)
            let glue = value == 0x200D || value == 0x20E3 || (0xFE00...0xFE0F).contains(value)
            if !pictograph && !glue { scalars.append(scalar) }
        }
        return String(scalars)
    }
}
