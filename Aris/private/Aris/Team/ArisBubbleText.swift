//
//  ArisBubbleText.swift
//  Aris
//
//  What a teammate's live bubble says (mockup 10-bubble.html, A): the job's step while it runs, then 끝났어요 or
//  못 끝냈어요. Pure. A step is model or tool output, so it is shown as plain text only: at most 256 scalars read, one
//  line, no control, bidi or zero-width characters, at most 3 combining marks on a letter, no markdown markers, a link
//  as its words and host (never something to open), secret-looking words and key values as •••, and at most 24 letters
//  (23 and "…"), then cut again to the width the bubble may take (`fitted`).
//

import CoreGraphics
import Foundation

/// How the bubble looks: working has the sheen, done the green check.
enum ArisBubbleTone: Equatable { case working, waiting, done, failed }

enum ArisBubbleText {
    /// Letters (grapheme clusters) a bubble holds; a longer step is cut to one less and "…".
    static let maxCharacters = 24
    /// What stands in for a word that looks like a key or token.
    static let redacted = "•••"
    /// What is read of a step at most (a model can send anything), and the combining marks kept on one letter.
    static let maxScalars = 256
    static let maxMarks = 3

    static func text(for state: ArisJobState, korean: Bool) -> String? {
        switch state {
        case .queued: return korean ? "대기 중" : "Waiting"
        case .running(let step):
            let clean = sanitized(step)
            // The agent's step comes in Korean: a bubble that speaks English says it in English.
            return clean.isEmpty ? (korean ? "준비 중…" : "Getting ready…") : clipped(sanitized(ArisUIWords.status(clean, english: !korean)))
        case .awaitingApproval: return korean ? "허락 기다리는 중" : "Waiting for your OK"
        case .done: return korean ? "끝났어요" : "Done"
        case .failed: return korean ? "못 끝냈어요" : "Couldn't finish"
        case .cancelled: return nil
        }
    }

    static func tone(for state: ArisJobState) -> ArisBubbleTone? {
        switch state {
        case .queued, .running: return .working
        case .awaitingApproval: return .waiting
        case .done: return .done
        case .failed: return .failed
        case .cancelled: return nil
        }
    }

    static func clipped(_ text: String) -> String {
        text.count > maxCharacters ? String(text.prefix(maxCharacters - 1)) + "…" : text
    }

    /// `text` cut, letter by letter, to what `width` says fits in `maxWidth`, with "…" when cut.
    static func fitted(_ text: String, maxWidth: CGFloat, width: (String) -> CGFloat) -> String {
        guard width(text) > maxWidth else { return text }
        var kept = text
        while !kept.isEmpty {
            kept.removeLast()
            if width(kept + "…") <= maxWidth { return kept + "…" }
        }
        return "…"
    }

    /// One line of plain text from whatever a step said.
    static func sanitized(_ raw: String) -> String {
        let read = String.UnicodeScalarView(raw.unicodeScalars.prefix(maxScalars))
        let visible = calmed(String(String.UnicodeScalarView(read.compactMap(visibleScalar))))
        var out: [String] = []
        var hideNext = false
        for piece in unlinked(visible).split(whereSeparator: \.isWhitespace).map(String.init) {
            if hideNext, piece != "=", piece != ":" {
                out.append(redacted)
                hideNext = false
                continue
            }
            guard let word = cleanWord(piece) else { continue }
            out.append(word)
            // "key: value", "password = value": the value is the next word.
            if word == "=" || word == ":" {
                hideNext = hideNext || out.dropLast().last.map(isSecretName) ?? false
            } else if let last = word.last, last == ":" || last == "=" {
                hideNext = isSecretName(String(word.dropLast()))
            } else {
                hideNext = false
            }
        }
        return out.joined(separator: " ")
    }

    // MARK: pieces

    /// Whitespace and line breaks become a space; control and format characters (bidi overrides, zero-width) go.
    private static func visibleScalar(_ s: Unicode.Scalar) -> Unicode.Scalar? {
        if s.properties.isWhitespace { return " " }
        // The joiner inside emoji sequences (👩‍💻) stays; it can't reorder or hide text.
        if s == "\u{200D}" { return s }
        switch s.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned: return nil
        default: return s
        }
    }

    /// At most `maxMarks` combining marks on any letter (stacked marks can cover the lines around a bubble).
    private static func calmed(_ text: String) -> String {
        String(text.map { letter -> String in
            var marks = 0
            let kept = letter.unicodeScalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .nonspacingMark, .enclosingMark, .spacingMark:
                    marks += 1
                    return marks <= maxMarks
                default:
                    return true
                }
            }
            return String(String.UnicodeScalarView(kept))
        }.joined())
    }

    private static func isSecretName(_ word: String) -> Bool {
        let name = word.lowercased()
        return secretNames.contains { name.hasSuffix($0) }
    }

    /// A markdown link `[words](target)` keeps its words and the target's host.
    private static func unlinked(_ text: String) -> String {
        var out = text
        while let open = out.range(of: "]("), let start = out[..<open.lowerBound].lastIndex(of: "["),
              let close = out[open.upperBound...].firstIndex(of: ")") {
            let words = out[out.index(after: start)..<open.lowerBound]
            let target = String(out[open.upperBound..<close])
            out.replaceSubrange(start...close, with: "\(words) \(host(of: target) ?? "")")
        }
        return out
    }

    private static func cleanWord(_ word: String) -> String? {
        if word.contains("://") { return host(of: word) ?? redacted }
        let bare = word.filter { $0 != "*" && $0 != "`" }
        let unmarked = bare.drop { $0 == "#" || $0 == ">" }
        guard !unmarked.isEmpty else { return nil }
        if let assignment = redactedAssignment(String(unmarked)) { return assignment }
        return looksSecret(String(unmarked)) ? redacted : String(unmarked)
    }

    private static func host(of link: String) -> String? {
        guard let host = URLComponents(string: link)?.host, !host.isEmpty else { return nil }
        return host
    }

    /// Prefixes keys and tokens are known to start with.
    private static let secretPrefixes = ["sk-", "sk_", "ghp_", "gho_", "ghs_", "github_pat_", "xoxb-", "xoxp-", "AKIA", "AIza", "glpat-"]
    private static let secretNames = ["token", "secret", "password", "passwd", "apikey", "api_key", "api-key", "key"]

    /// `TOKEN=…`, `password:…`: the name stays, the value doesn't.
    private static func redactedAssignment(_ word: String) -> String? {
        guard let sep = word.firstIndex(where: { $0 == "=" || $0 == ":" }), sep != word.startIndex, word.index(after: sep) != word.endIndex else { return nil }
        let name = word[..<sep].lowercased()
        guard secretNames.contains(where: { name.hasSuffix($0) }) else { return nil }
        return "\(word[...sep])\(redacted)"
    }

    /// A known key prefix, a dotted token (a JWT: three long base64url parts), or a long run of letters and digits mixed
    /// (a hash, a token, an id).
    private static func looksSecret(_ word: String) -> Bool {
        if secretPrefixes.contains(where: { word.hasPrefix($0) && word.count > $0.count + 3 }) { return true }
        let parts = word.trimmingCharacters(in: .punctuationCharacters).split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 3, parts.allSatisfy({ $0.count >= 8 && $0.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") } }) {
            return true
        }
        let core = word.trimmingCharacters(in: .punctuationCharacters)
        guard core.count >= 20, core.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_+/=".unicodeScalars.contains($0)) })
        else { return false }
        return core.contains(where: \.isLetter) && core.contains(where: \.isNumber)
    }
}
