//
//  ArisRiskPolicy+Dictation.swift
//  aris-agent
//
//  A message the user dictated goes out after a short countdown instead of a question ("엄마한테 ‘곧 갈게’
//  보낼게요", stop it by saying "취소"). Judged against the user's own words (the request, from the microphone),
//  never the AI's: a web page or mail the AI read can't change what the user said. The recipient must be named
//  and the text must be close to what was said; the AI's own wording, or anything it added, is asked about.
//  Hardened by the security review of the countdown on the open Claude: no hidden characters, links, marks, negation
//  or tense the user didn't say, fewer missing syllables for a short message, whole words for the name and the send word.
//

import Foundation

extension ArisRiskPolicy {
    /// How close a message must be to the request (share of its syllables found, in order).
    static let dictationThreshold = 0.65
    /// At most this many of the message's syllables may be missing from the request (reported speech changes a
    /// few endings: 간다고 → 갈게), so a long message can't carry the AI's own sentence along.
    static let unmatchedLimit = 3
    /// The user's own words longer than this (a pasted mail or page, not something they said) cover nothing for the turn:
    /// no countdown, no typing of "their words", no shortcut or recipient, list or calendar named by them (security
    /// review 9, M1: in 20,000 characters a paste someone else wrote names anyone, and a message's syllables are found
    /// in order somewhere in it). The same number as main.swift's maxLearned: memory learns from no longer request either.
    static let maxCoveringWords = 2_000

    /// The request is too long to stand for what the user said themselves (the files note is never their words).
    static func coversNothing(_ request: String) -> Bool { ArisMemoryText.ownWords(request).count > maxCoveringWords }

    /// The share (0...1) of the message's syllables found, in order, in the request. Syllables compare by their
    /// first consonant and vowel, since reported speech changes endings (곧 간다고 → 곧 갈게).
    static func dictation(message: String, request: String) -> Double {
        let said = keys(message)
        guard !said.isEmpty else { return 0 }
        return Double(matched(said, in: keys(request))) / Double(said.count)
    }

    static func matched(_ said: [UInt32], in heard: [UInt32]) -> Int {
        var found = 0, at = heard.startIndex
        for key in said {
            guard let match = heard[at...].firstIndex(of: key) else { continue }
            found += 1
            at = heard.index(after: match)
        }
        return found
    }

    /// Endings a Korean name takes in a request (엄마한테, 민지야, 엄마랑): the name is the word without one of these.
    private static let particles = ["이한테", "이에게", "님한테", "님에게", "님께", "씨한테", "씨에게", "한테", "에게", "께", "이랑", "랑",
                                    "하고", "이", "가", "은", "는", "을", "를", "도", "와", "과", "의", "야", "아", "님", "씨"]

    /// The request's words, lowercased, split at spaces and marks (Hangul syllables and letters stay together).
    static func requestWords(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { $0.isWhitespace || ($0.isPunctuation && $0 != "'" && $0 != "\u{2019}") || $0.isSymbol })
            .map { $0.replacingOccurrences(of: "\u{2019}", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// The recipient is a whole word the user said (L5), or that word with a Korean particle (엄마 in 엄마한테, never
    /// in 엄마친구한테), at least two letters long. A name with spaces ("Kim Minji") is matched across the words it spans.
    static func named(_ to: String, in request: String) -> Bool {
        guard !coversNothing(request) else { return false }
        let parts = to.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let name = parts.joined()
        guard name.count >= 2 else { return false }
        let words = requestWords(request)
        let span = max(1, parts.count)
        guard words.count >= span else { return false }
        return (0...(words.count - span)).contains { start in
            let candidate = words[start..<(start + span)].joined()
            return candidate == name || particles.contains { candidate == name + $0 }
        }
    }

    /// A send word in the request (L5): Korean stems inside a word (보내줘, 문자로), English ones only as whole words
    /// (never "context" or "install").
    static func hasSendWord(_ request: String) -> Bool {
        let words = requestWords(request)
        return words.contains { word in koreanSendWords.contains(where: word.contains) || englishSendWords.contains(word) }
    }
    private static let koreanSendWords = ["보내", "문자", "메시지", "메세지", "전해"]
    private static let englishSendWords: Set<String> = ["send", "sends", "sending", "text", "texts", "texting", "message", "messages",
                                                        "messaging", "tell", "tells", "telling"]

    /// At most this many of a message's syllables may be missing from the request: 15% of them, at least one, never more
    /// than `unmatchedLimit` (M2: a short message can't take on a word of the AI's).
    static func allowedUnmatched(_ count: Int) -> Int { min(unmatchedLimit, max(1, count * 15 / 100)) }

    /// `message <to> <text…>` that the request asked for: (to, text) exactly as they'll be sent and shown; nil when it
    /// wasn't (then it is the user's plain card).
    static func dictatedMessage(_ arguments: [String], request: String) -> (to: String, text: String)? {
        let request = ArisMemoryText.ownWords(request)  // a file's text is never the user's words
        guard arguments.count >= 3, arguments[0] == "message", !coversNothing(request) else { return nil }
        let to = arguments[1], text = arguments.dropFirst(2).joined(separator: " ")
        // M2: nothing on the card that isn't seen, no link, no mark the user didn't say, no negation or tense they didn't say.
        guard !hasHidden(to), !hasHidden(text), !hasLink(text), marksCovered(text, by: request),
              !addsMeaning(text, request: request) else { return nil }
        let said = keys(text)
        guard hasSendWord(request), named(to, in: request), !said.isEmpty,
              dictation(message: text, request: request) >= dictationThreshold,
              said.count - matched(said, in: keys(request)) <= allowedUnmatched(said.count) else { return nil }
        return (to, text)
    }

    /// Text to type that is the user's own words for this turn (QA BUG-15): a dictated message's rules without a recipient or
    /// send word. One line, nothing hidden, no link, no mark, negation or tense he didn't say, and its syllables found in
    /// order in his request, a few at most missing.
    static func typesUsersWords(_ text: String, request: String) -> Bool {
        let request = ArisMemoryText.ownWords(request)  // a file's text is never the user's words
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, !coversNothing(request), !ArisCommandPolicy.hasLineBreak(typed), !hasHidden(typed), !hasLink(typed), marksCovered(typed, by: request),
              !addsMeaning(typed, request: request) else { return false }
        let said = keys(typed)
        return !said.isEmpty && dictation(message: typed, request: request) >= dictationThreshold
            && said.count - matched(said, in: keys(request)) <= allowedUnmatched(said.count)
    }

    /// A character the card wouldn't show as itself: a control or format character (zero-width, direction marks, tag
    /// characters), a default-ignorable one (variation selectors…), a private-use or unassigned one, a line separator.
    static func hasHidden(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let properties = scalar.properties
            switch properties.generalCategory {
            case .control, .format, .privateUse, .unassigned, .surrogate, .lineSeparator, .paragraphSeparator: return true
            default: return properties.isDefaultIgnorableCodePoint || properties.isVariationSelector
            }
        }
    }

    /// A web address or a domain (naver.com) anywhere in the text.
    static func hasLink(_ text: String) -> Bool {
        if text.contains("://") || text.lowercased().contains("www.") { return true }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return true }
        return detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Every mark in the text (anything but letters, digits and spaces: ! ? . emoji) is one the user said too.
    static func marksCovered(_ text: String, by request: String) -> Bool {
        let marks = { (words: String) in Set(words.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) }
        return marks(text).isSubset(of: marks(request))
    }

    /// Korean negation (안 갈게, 못 가, 하지 말고, 없어) the user didn't say.
    private static let koreanNegations = ["안", "못", "않", "말", "없", "아니"]
    private static let englishNegations: Set<String> = ["not", "no", "never", "nothing", "nobody", "none", "nor", "neither", "without",
                                                        "cannot", "dont", "wont", "cant"]
    /// English words that change when (was, will, yesterday…).
    private static let englishTenses: Set<String> = ["was", "were", "did", "had", "been", "will", "would", "shall", "won't", "yesterday",
                                                     "tomorrow", "ago", "later", "'ll", "'d"]

    /// The message says no, or another time, where the user's words didn't: a negation, the Korean past (a syllable ending in
    /// ㅆ: 갔어, 했어) or future 겠, or an English tense word or contraction.
    static func addsMeaning(_ text: String, request: String) -> Bool {
        if koreanNegations.contains(where: { text.contains($0) && !request.contains($0) }) { return true }
        let past = { (words: String) in words.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) && ($0.value - 0xAC00) % 28 == 20 } }
        if past(text) && !past(request) { return true }
        if text.contains("겠") && !request.contains("겠") { return true }
        let said = Set(requestWords(request)), written = requestWords(text)
        let english = { (word: String) -> Bool in
            englishNegations.contains(word) || englishTenses.contains(word) || word.hasSuffix("n't")
                || englishTenses.contains { $0.hasPrefix("'") && word.hasSuffix($0) }
        }
        return written.contains { english($0) && !said.contains($0) }
    }

    /// What Aris says before the countdown.
    static func announcement(to: String, text: String, english: Bool = false) -> String {
        english ? "Sending ‘\(text)’ to \(to)" : "\(to)한테 ‘\(text)’ 보낼게요"
    }

    /// Each letter or Hangul syllable as a comparable key (a syllable by its first consonant and vowel).
    static func keys(_ text: String) -> [UInt32] {
        text.lowercased().unicodeScalars.compactMap { scalar in
            if (0xAC00...0xD7A3).contains(scalar.value) { return 0x10000 + (scalar.value - 0xAC00) / 28 }
            return CharacterSet.alphanumerics.contains(scalar) ? scalar.value : nil
        }
    }
}
