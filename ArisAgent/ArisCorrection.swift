//
//  ArisCorrection.swift
//  aris-agent
//
//  Whether the user's edit of a field, right after dictation typed into it, was them fixing one misheard word: the change
//  lies inside the dictated words, exactly one word differs, the new word looks like the old one (a misheard name, not
//  a rewrite), and it isn't a path, a file name, or a word he's still typing. These are the safety rules for learning
//  from edits, with a spelling-distance check as the judge of a near miss.
//  Foundation only (tested).
//

import Foundation

enum ArisCorrection {
    struct Change: Equatable {
        let heard: String
        let meant: String
    }

    private static let maxAdded = 10
    private static let maxDeleted = 20
    /// How different the two spellings may be (edit distance over the longer length, letters decomposed).
    private static let maxDistance = 0.6
    private static let edges = CharacterSet.punctuationCharacters.union(.symbols).union(.whitespaces)
    /// Korean particles that stay with the word they follow: "로션에" → "노션에" teaches 노션.
    private static let particles = ["에서", "에게", "한테", "으로", "이랑", "까지", "부터", "처럼", "보다", "은", "는", "이", "가",
                                    "을", "를", "에", "로", "와", "과", "도", "만", "의", "께", "랑"]

    /// The one word the user fixed in what was `inserted`, from the field's value right after the paste (`before`) and
    /// now (`after`); nil when it was anything else.
    static func detect(inserted: String, before: String, after: String) -> Change? {
        let old = Array(before), new = Array(after), typed = Array(inserted)
        guard !typed.isEmpty, !new.isEmpty, old != new, let start = uniqueStart(of: typed, in: old) else { return nil }
        let end = start + typed.count
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let deleted = old.count - prefix - suffix, added = new.count - prefix - suffix
        guard deleted <= maxDeleted, added <= maxAdded + deleted, prefix >= start, old.count - suffix <= end else { return nil }
        let oldWords = words(String(old[start..<end]))
        let newEnd = end + new.count - old.count
        guard newEnd >= start, newEnd <= new.count else { return nil }
        let newWords = words(String(new[start..<newEnd]))
        guard oldWords.count == newWords.count else { return nil }
        let differing = zip(oldWords, newWords).enumerated().filter { $0.element.0 != $0.element.1 }
        guard differing.count == 1, let pair = differing.first?.element else { return nil }
        let (heard, meant) = withoutSharedParticle(core(pair.0), core(pair.1))
        return learnable(heard: heard, meant: meant) ? Change(heard: heard, meant: meant) : nil
    }

    /// Where the typed words start, when they appear exactly once.
    private static func uniqueStart(of typed: [Character], in value: [Character]) -> Int? {
        guard typed.count <= value.count else { return nil }
        var found: Int?
        for index in 0...(value.count - typed.count) where value[index] == typed[0] && Array(value[index..<index + typed.count]) == typed {
            if found != nil { return nil }
            found = index
        }
        return found
    }

    private static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: edges)
    }

    private static func withoutSharedParticle(_ heard: String, _ meant: String) -> (String, String) {
        for particle in particles where heard.hasSuffix(particle) && meant.hasSuffix(particle)
            && heard.count > particle.count && meant.count > particle.count {
            return (String(heard.dropLast(particle.count)), String(meant.dropLast(particle.count)))
        }
        return (heard, meant)
    }

    private static func learnable(heard: String, meant: String) -> Bool {
        guard !heard.isEmpty, !meant.isEmpty, heard != meant else { return false }
        guard !meant.contains(where: \.isWhitespace), !meant.contains("/"), !meant.contains("\\"), !meant.contains("@"),
              meant.range(of: #"\w\.[A-Za-z0-9]{1,5}$"#, options: .regularExpression) == nil else { return false }
        let nameLike = meant.contains(where: \.isUppercase) || meant.contains(where: \.isNumber)
        guard meant.count >= 2 || nameLike else { return false }
        // Cut short or carried on: still typing, not a fix.
        let a = heard.lowercased(), b = meant.lowercased()
        guard a == b || (!a.hasPrefix(b) && !b.hasPrefix(a)) else { return false }
        return distance(letters(a), letters(b)) <= maxDistance
    }

    /// Letters decomposed (Hangul into jamo), so 로션 and 노션 differ by one.
    private static func letters(_ text: String) -> [Unicode.Scalar] {
        Array(text.decomposedStringWithCanonicalMapping.unicodeScalars)
    }

    /// Levenshtein distance over the longer length.
    private static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 1 }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let current = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = current
            }
        }
        return Double(row[b.count]) / Double(max(a.count, b.count))
    }
}
