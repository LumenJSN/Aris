//
//  ArisDataSafety.swift
//  Aris (also built into aris-agent)
//
//  Two small rules the 정보 › 데이터 rows share with the agent's /data route. ArisRedaction takes secrets out of log
//  text before it goes into a diagnostics file: the keys and the token Aris knows, anything shaped like a key or a
//  token, email addresses, and the home folder's path. ArisTypedConfirm is the typed-word check for 데이터 지우기 and
//  제거: the app enables the red button with it and the agent checks the same word again before it removes anything.
//  The word is asked for in the UI's language ("지우기" or "erase", "제거" or "remove").
//

import Foundation

enum ArisRedaction {
    /// What a removed secret becomes.
    static let mark = "[REDACTED]"
    static let email = "[EMAIL]"
    /// A known secret shorter than this is not used (it would cut ordinary words out of the log).
    static let minSecret = 8
    /// A run of letters and digits this long, with both in it, is treated as a key.
    static let minOpaqueRun = 40

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // The patterns are fixed literals: a typo is a programming error caught by the tests.
        try! NSRegularExpression(pattern: pattern)
    }

    /// Replaced whole.
    private static let whole: [NSRegularExpression] = [
        regex(#"sk-[A-Za-z0-9_\-]{12,}"#),
        regex(#"eyJ[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}\.[A-Za-z0-9_\-]{6,}"#),
        regex(#"\b[A-Fa-f0-9]{32,}\b"#),
    ]

    /// The name is kept, the value replaced (group 1 is what stays).
    private static let valued: [NSRegularExpression] = [
        regex(#"(?i)(bearer\s+)[A-Za-z0-9._~+/=\-]{6,}"#),
        regex(#"(?i)((?:x-aris-token|xi-api-key|x-api-key|authorization|api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password)["']?\s*[:=]\s*["']?)(?!bearer\s)[^\s"',;}]{6,}"#),
    ]

    private static let emailPattern = regex(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    private static let opaqueRun = regex(#"[A-Za-z0-9_\-]{40,}"#)

    /// `text` with `secrets` (the token, stored keys), key-shaped values, emails and `home` taken out.
    static func redact(_ text: String, secrets: [String], home: String) -> String {
        var out = text
        for secret in Set(secrets.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where secret.count >= minSecret {
            out = out.replacingOccurrences(of: secret, with: mark)
        }
        for pattern in whole { out = replace(pattern, in: out, with: mark) }
        for pattern in valued { out = replace(pattern, in: out, with: "$1" + mark) }
        out = replace(emailPattern, in: out, with: email)
        out = replaceOpaqueRuns(in: out)
        if home.count > 1 { out = out.replacingOccurrences(of: home, with: "~") }
        return out
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Long runs that mix letters and digits (base64 keys, session ids); a long name made of words is kept.
    private static func replaceOpaqueRuns(in text: String) -> String {
        let matches = opaqueRun.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var out = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: out) else { continue }
            let run = out[range]
            let digits = run.filter(\.isNumber).count, letters = run.filter(\.isLetter).count
            if digits >= 4 && letters >= 4 { out.replaceSubrange(range, with: mark) }
        }
        return out
    }
}

enum ArisTypedConfirm {
    /// What 데이터 지우기 asks the user to type.
    static let wipeWord = "지우기"
    /// What 제거 asks the user to type.
    static let uninstallWord = "제거"
    /// The same words as an English UI asks for them: a Mac with no Korean keyboard can't type the Korean ones
    /// (fresh install, typed-confirm-korean).
    static let englishWords = [wipeWord: "erase", uninstallWord: "remove"]

    /// The word the prompt shows and asks for, in the UI's language.
    static func shown(_ word: String, english: Bool) -> String {
        english ? englishWords[word] ?? word : word
    }

    /// The prompt around the word: "확인하려면 지우기라고 써 주세요", "Type erase to confirm".
    static func prompt(_ word: String, english: Bool) -> (before: String, word: String, after: String) {
        english ? ("Type ", shown(word, english: true), " to confirm") : ("확인하려면 ", word, "라고 써 주세요")
    }

    /// Exactly the word, spaces around it aside; Hangul typed composed or decomposed is the same word. The word's
    /// English form is the same answer in any capitals, whatever the UI's language: the agent checks again with this
    /// and has no UI of its own.
    static func matches(_ typed: String, _ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.precomposedStringWithCanonicalMapping == word.precomposedStringWithCanonicalMapping { return true }
        guard let english = englishWords[word] else { return false }
        return clean.lowercased() == english
    }
}
