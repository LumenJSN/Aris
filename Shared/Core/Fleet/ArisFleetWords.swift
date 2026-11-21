//
//  ArisFleetWords.swift
//  Shared/Core (app, aris-agent, tests)
//
//  The words a person uses for a session, Korean and English: numbers ("3번", "삼번", "세 번째", "number three",
//  "#3"), the folder's name as said aloud in Hangul ("아리스" for aris, "알트스위치" for altswitch: compared by their
//  consonant sounds), and what it works on (a few dev words in both languages). Pure.
//

import Foundation

enum ArisFleetWords {
    // MARK: - Numbers

    private static let sino: [String: Int] = ["일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "륙": 6, "칠": 7, "팔": 8, "구": 9, "십": 10]
    private static let native: [String: Int] = ["첫": 1, "한": 1, "하나": 1, "두": 2, "둘": 2, "세": 3, "셋": 3, "네": 4, "넷": 4, "다섯": 5,
                                                "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10]
    private static let english: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                                                 "nine": 9, "ten": 10, "eleven": 11, "twelve": 12]
    private static let ordinals: [String: Int] = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
                                                  "eighth": 8, "ninth": 9, "tenth": 10]

    /// "삼", "십이", "이십": 1…29 in Sino-Korean.
    static func sinoNumber(_ word: String) -> Int? {
        let chars = word.map(String.init)
        guard !chars.isEmpty, chars.count <= 3, chars.allSatisfy({ sino[$0] != nil }) else { return nil }
        if chars.count == 1 { return sino[chars[0]] }
        if chars[0] == "십" { return chars.count == 2 ? 10 + (sino[chars[1]] ?? 0) : nil }
        guard let tens = sino[chars[0]], tens < 10, chars[1] == "십" else { return nil }
        return tens * 10 + (chars.count == 3 ? sino[chars[2]] ?? 0 : 0)
    }

    /// The session number a reference names, if it names one: "3", "3번", "#3", "삼번", "삼 번", "세 번째", "첫번째",
    /// "number three", "no. 3", "session 3", "the third one".
    static func number(in reference: String) -> Int? {
        let text = reference.lowercased().precomposedStringWithCanonicalMapping
        // Digits standing alone (never inside a name such as "v2" or "aris-jv-3").
        if let match = firstMatch(#"(?:^|[\s#(])(?:no\.?\s*|number\s*|session\s*|#)?([0-9]{1,2})(?:\s*(?:번째|번|호|째|th|st|nd|rd))?(?=$|[\s.,!?)이가은는을를에한]|번|호)"#, in: text) {
            return Int(match)
        }
        // Korean number words: Sino-Korean with 번 or 번째 ("삼번"), native ones only with 번째 ("세 번째"; "세 번" is
        // "three times").
        if let regex = try? NSRegularExpression(pattern: #"(?<![가-힣])([가-힣]{1,3})\s*번(째)?"#) {
            for found in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(found.range(at: 1), in: text) else { continue }
                let word = String(text[range]), ordinal = found.range(at: 2).location != NSNotFound
                // "이번" is "this time", never number two (speech writes 2번 as digits).
                if word != "이", let value = sinoNumber(word) { return value }
                if ordinal, let value = native[word] { return value }
            }
        }
        let words = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (index, word) in words.enumerated() {
            if (word == "number" || word == "no" || word == "session"), index + 1 < words.count, let value = english[words[index + 1]] { return value }
            if let value = ordinals[word] { return value }
        }
        return nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let found = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), found.numberOfRanges > 1,
              let range = Range(found.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Sounds

    /// A word's consonant sounds, the same for its Hangul spelling and its Latin one ("아리스" and "aris" are "RS",
    /// "알트스위치" and "altswitch" "RTSC"), repeats collapsed.
    static func skeleton(_ word: String) -> String {
        let hangul = word.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
        let raw = hangul ? hangulSkeleton(word) : latinSkeleton(word.lowercased())
        return raw.reduce(into: "") { result, char in if result.last != char { result.append(char) } }
    }

    private static let initials: [Character?] = ["K", "K", "N", "T", "T", "R", "M", "P", "P", "S", "S", nil, "C", "C", "C", "K", "T", "P", nil]
    private static let finals: [String] = ["", "K", "K", "K", "N", "N", "N", "T", "R", "K", "M", "R", "R", "R", "P", "R", "M", "P", "P", "T",
                                           "T", "N", "T", "T", "K", "T", "P", "T"]

    private static func hangulSkeleton(_ word: String) -> String {
        var out = ""
        for scalar in word.unicodeScalars {
            guard (0xAC00...0xD7A3).contains(scalar.value) else { continue }
            let index = Int(scalar.value - 0xAC00)
            if let initial = initials[index / (21 * 28)] { out.append(initial) }
            out += finals[index % 28]
        }
        return out
    }

    private static func latinSkeleton(_ word: String) -> String {
        let letters = Array(word.filter { $0.isASCII && $0.isLetter })
        var out = ""
        var index = 0
        func at(_ offset: Int) -> Character? { index + offset < letters.count ? letters[index + offset] : nil }
        while index < letters.count {
            let char = letters[index]
            let pair = String(char) + (at(1).map(String.init) ?? "")
            if pair == "tc", at(2) == "h" { out.append("C"); index += 3; continue }
            switch pair {
            case "ch": out.append("C"); index += 2; continue
            case "sh": out.append("S"); index += 2; continue
            case "ph": out.append("P"); index += 2; continue
            case "th": out.append("T"); index += 2; continue
            case "ng": out.append("N"); index += 2; continue
            case "ck": out.append("K"); index += 2; continue
            default: break
            }
            switch char {
            case "b", "p", "f", "v": out.append("P")
            case "d", "t": out.append("T")
            case "l", "r": out.append("R")
            case "m": out.append("M")
            case "n": out.append("N")
            case "s", "z": out.append("S")
            case "j": out.append("C")
            case "k", "g", "q": out.append("K")
            case "x": out += "KS"
            case "c": out.append(["e", "i", "y"].contains(at(1) ?? " ") ? "S" : "K")
            default: break
            }
            index += 1
        }
        return out
    }

    /// Whether a Hangul word sounds like a Latin one: the same consonants, or the same once the r's Korean drops are
    /// left out ("자비스", "jarvis").
    static func soundsAlike(_ hangul: String, _ latin: String) -> Bool {
        let one = skeleton(hangul), two = skeleton(latin)
        guard one.count >= 2, two.count >= 2 else { return false }
        if one == two { return true }
        let a = one.replacingOccurrences(of: "R", with: ""), b = two.replacingOccurrences(of: "R", with: "")
        return a.count >= 3 && a == b
    }

    static func isHangul(_ word: String) -> Bool { word.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }

    // MARK: - Words

    /// The words a reference is cut into: lower case, Korean particles taken off the end.
    static func tokens(_ reference: String) -> [String] {
        let text = reference.lowercased().precomposedStringWithCanonicalMapping
        return text.split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" && $0 != "." }
            .map { strip(String($0).trimmingCharacters(in: CharacterSet(charactersIn: "-_."))) }
            .filter { !$0.isEmpty }
    }

    private static let particles = ["에서는", "에서", "한테서", "한테", "에게", "께서", "이랑", "랑", "하고", "으로", "로", "에", "의", "은", "는",
                                    "이", "가", "을", "를", "도", "쪽", "꺼", "거", "것"]

    /// A Korean word without the particle on its end ("altswitch에서" → "altswitch", "아리스쪽" → "아리스").
    static func strip(_ word: String) -> String {
        for particle in particles where word.hasSuffix(particle) && word.count > particle.count + (isHangul(word) ? 1 : 0) {
            return String(word.dropLast(particle.count))
        }
        return word
    }

    static let stopwords: Set<String> = [
        "the", "a", "an", "one", "ones", "in", "on", "at", "of", "for", "to", "that", "this", "session", "sessions", "agent", "which", "who",
        "is", "it", "its", "and", "with", "folder", "project", "repo", "working", "doing", "tell", "ask", "guy", "thing", "please", "there",
        "애", "애들", "거", "것", "놈", "친구", "세션", "폴더", "프로젝트", "하는", "있는", "돌고", "도는", "그", "저", "이", "번", "작업", "하고",
        "있어", "중인", "중", "띄운", "켜둔", "켜놓은",
    ]

    /// Dev words in both languages: a Korean word and the English stems it means.
    static let meanings: [String: [String]] = [
        "테스트": ["test"], "빌드": ["build"], "버그": ["bug"], "고치": ["fix", "repair", "수정"], "고친": ["fix", "수정"], "수정": ["fix", "edit", "change", "고치"],
        "배포": ["deploy", "release"], "리뷰": ["review"], "문서": ["doc"], "디자인": ["design"], "리팩터": ["refactor"], "리팩토링": ["refactor"],
        "로그인": ["login", "auth"], "번역": ["translat"], "검색": ["search"], "설정": ["setting", "config"], "알림": ["notif"],
        "음성": ["voice", "speech"], "화면": ["screen", "ui"], "타이머": ["timer"], "메모리": ["memory"], "속도": ["speed", "perf", "fast"],
    ]

    /// The parts of a Korean verb or noun worth matching ("고치는" → "고치", "테스트를" → "테스트").
    static func stems(_ token: String) -> [String] {
        guard isHangul(token) else {
            var stem = token
            for suffix in ["ing", "ed", "es", "s"] where stem.hasSuffix(suffix) && stem.count - suffix.count >= 3 {
                stem = String(stem.dropLast(suffix.count))
                break
            }
            return Array(Set([token, stem]))
        }
        var forms = [token]
        for ending in ["하는", "하던", "는", "던", "고있는", "고", "한", "할"] where token.hasSuffix(ending) && token.count > ending.count {
            forms.append(String(token.dropLast(ending.count)))
        }
        return forms
    }
}
