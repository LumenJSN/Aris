//
//  ArisAppsText.swift
//  Shared/Core/Apps
//
//  How a name a person says is compared with an app's names, menu titles and commands. Hangul-aware: syllables are
//  decomposed into jamo so "까톡" is one sound away from "카톡", loanword variants cost little (ㅍ/ㅎ for f, ㅐ/ㅔ,
//  the epenthetic ㅡ of 슬랙/스랙), spacing and case never matter, and a consonant skeleton lets a Hangul spelling of
//  an English name ("피그마", "깃허브") meet the English one as a weak guess. Pure.
//

import Foundation

extension ArisApps {
    enum Text {
        // MARK: - Folding

        /// Words that only say "it's an app" and never tell apps apart.
        static let appWords = ["어플리케이션", "애플리케이션", "프로그램", "어플", "앱", "application", "app"]
        /// Korean particles that can trail a name in speech ("카톡을", "크롬에서").
        static let particles = ["에서", "으로", "한테", "에게", "을", "를", "이", "가", "은", "는", "로", "에", "랑", "도"]

        /// Composed, lowercased, no spaces or punctuation: how names compare.
        static func key(_ text: String) -> String {
            let folded = text.precomposedStringWithCanonicalMapping.lowercased()
                .replacingOccurrences(of: ".app", with: "")
            return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        }

        /// The key without words that only say "app" at either end ("카톡 앱", "the Notes app").
        static func core(_ text: String) -> String {
            var words = text.precomposedStringWithCanonicalMapping.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            while words.count > 1, let last = words.last, appWords.contains(key(last)) { words.removeLast() }
            if words.count > 1, ["the"].contains(words[0]) { words.removeFirst() }
            var joined = key(words.joined())
            for word in appWords where joined.hasSuffix(word) && joined.count > word.count + 1 {
                joined = String(joined.dropLast(word.count))
                break
            }
            return joined
        }

        /// The forms worth trying for a spoken name: itself, then without a trailing particle ("카톡을" → "카톡").
        static func forms(_ text: String) -> [String] {
            let base = core(text)
            var forms = [base]
            if base.unicodeScalars.contains(where: isHangul) {
                for particle in particles where base.hasSuffix(particle) && base.count > particle.count + 1 {
                    forms.append(String(base.dropLast(particle.count)))
                }
            }
            return forms.filter { !$0.isEmpty }
        }

        // MARK: - Jamo

        static func isHangul(_ scalar: Unicode.Scalar) -> Bool { (0xAC00...0xD7A3).contains(scalar.value) }

        private static let initials = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
        private static let medials = Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
        private static let finals: [Character?] = [nil] + Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").map { Optional($0) }

        /// Each syllable as its jamo (compatibility letters), other characters as they are.
        static func jamo(_ text: String) -> [Character] {
            var out: [Character] = []
            for scalar in text.unicodeScalars {
                guard isHangul(scalar) else { out.append(Character(scalar)); continue }
                let index = Int(scalar.value - 0xAC00)
                out.append(initials[index / 588])
                out.append(medials[(index % 588) / 28])
                if let final = finals[index % 28] { out.append(final) }
            }
            return out
        }

        /// Letters that sound alike in loanwords and common misspellings: substituting one for another costs little.
        private static let alike: [Set<Character>] = [
            ["ㄱ", "ㄲ", "ㅋ"], ["ㄷ", "ㄸ", "ㅌ"], ["ㅂ", "ㅃ", "ㅍ"], ["ㅍ", "ㅎ"], ["ㅅ", "ㅆ"], ["ㅈ", "ㅉ", "ㅊ"],
            ["ㅐ", "ㅔ"], ["ㅒ", "ㅖ"], ["ㅙ", "ㅚ", "ㅞ"], ["ㅓ", "ㅗ"], ["ㅡ", "ㅜ"],
            ["c", "k"], ["s", "z"], ["f", "p"], ["i", "y"],
        ]

        static func substitution(_ a: Character, _ b: Character) -> Double {
            if a == b { return 0 }
            return alike.contains { $0.contains(a) && $0.contains(b) } ? 0.3 : 1
        }

        /// Inserting or dropping the loanword's epenthetic ㅡ (슬랙/스랙), or an h sound English spelling hides
        /// (GitHub's "th"), costs little.
        static func indel(_ letter: Character) -> Double { letter == "ㅡ" || letter == "H" ? 0.4 : 1 }

        /// Weighted edit distance (with swaps of neighbours at cost 1).
        static func distance(_ a: [Character], _ b: [Character]) -> Double {
            if a.isEmpty { return b.reduce(0) { $0 + indel($1) } }
            if b.isEmpty { return a.reduce(0) { $0 + indel($1) } }
            var table = Array(repeating: Array(repeating: 0.0, count: b.count + 1), count: a.count + 1)
            for i in 1...a.count { table[i][0] = table[i - 1][0] + indel(a[i - 1]) }
            for j in 1...b.count { table[0][j] = table[0][j - 1] + indel(b[j - 1]) }
            for i in 1...a.count {
                for j in 1...b.count {
                    var best = min(table[i - 1][j] + indel(a[i - 1]), table[i][j - 1] + indel(b[j - 1]),
                                   table[i - 1][j - 1] + substitution(a[i - 1], b[j - 1]))
                    if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { best = min(best, table[i - 2][j - 2] + 1) }
                    table[i][j] = best
                }
            }
            return table[a.count][b.count]
        }

        /// A letter said twice in a row counts once (슬랙's final ㄹ before 랙's ㄹ, as 스랙 is said).
        static func merged(_ letters: [Character]) -> [Character] {
            var out: [Character] = []
            for letter in letters where out.last != letter { out.append(letter) }
            return out
        }

        /// 0…1: how alike two keys are, Hangul compared by jamo.
        static func similarity(_ a: String, _ b: String) -> Double {
            let left = merged(jamo(a)), right = merged(jamo(b))
            let longest = max(left.count, right.count)
            guard longest > 0 else { return 0 }
            return max(0, 1 - distance(left, right) / Double(longest))
        }

        // MARK: - Consonant skeleton (cross-script)

        /// Sound classes for the skeleton: a Hangul spelling of an English name and the name itself meet here.
        private static func soundClass(_ letter: Character) -> Character? {
            switch letter {
            case "ㅂ", "ㅃ", "ㅍ", "b", "p", "f", "v": return "P"
            case "ㄱ", "ㄲ", "ㅋ", "g", "k", "c", "q", "x": return "K"
            case "ㄷ", "ㄸ", "ㅌ", "d", "t": return "T"
            case "ㅅ", "ㅆ", "s", "z": return "S"
            case "ㅈ", "ㅉ", "ㅊ", "j": return "J"
            case "ㄹ", "l", "r": return "L"
            case "ㄴ", "n": return "N"
            case "ㅁ", "m": return "M"
            case "ㅎ", "h": return "H"
            default: return nil
            }
        }

        /// The consonant sounds in order, repeats merged. English digraphs first ("tion" → S, "ch"/"sh" → J/S, "ph" → P).
        static func skeleton(_ text: String) -> [Character] {
            var spelled = key(text)
            for (from, to) in [("tion", "sn"), ("sion", "sn"), ("ph", "f"), ("sh", "s"), ("ch", "j"), ("ck", "k"), ("th", "t"), ("wh", "w")] {
                spelled = spelled.replacingOccurrences(of: from, with: to)
            }
            var letters: [Character] = []
            for scalar in spelled.unicodeScalars {
                if isHangul(scalar) {
                    let index = Int(scalar.value - 0xAC00)
                    letters.append(initials[index / 588])
                    // A final ㅅ, ㅈ, ㅊ, ㅌ or ㅎ is said as ㄷ (깃허브: git), a final ㅇ as ng.
                    if let final = finals[index % 28] { letters.append(final == "ㅇ" ? "ŋ" : "ㅅㅆㅈㅊㅌㅎ".contains(final) ? "ㄷ" : final) }
                } else {
                    letters.append(Character(scalar))
                }
            }
            var out: [Character] = []
            for letter in letters {
                guard let sound = soundClass(letter) else { continue }
                if out.last != sound { out.append(sound) }
            }
            return out
        }

        /// 0…1 across scripts by the skeleton; 0 when either has fewer than two consonant sounds.
        static func soundsLike(_ a: String, _ b: String) -> Double {
            let left = skeleton(a), right = skeleton(b)
            guard left.count >= 2, right.count >= 2 else { return 0 }
            let distance = distance(left, right)
            return max(0, 1 - distance / Double(max(left.count, right.count)))
        }

        static func hasHangul(_ text: String) -> Bool { text.unicodeScalars.contains(where: isHangul) }
    }
}
