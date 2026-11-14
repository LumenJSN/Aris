//
//  ArisMemoryText.swift
//  aris-agent, aris-tools
//
//  What a long-term memory is (its kind, its record) and the plain text measures the memory code shares: the
//  grams two texts are compared by (Hangul syllable pairs, Latin words, numbers), how alike two texts are, how much
//  of a text is in someone's words, and what is never remembered (passwords, card and account numbers, keys).
//  Foundation only (tested).
//

import Foundation

enum ArisMemoryKind: String, CaseIterable, Codable, Sendable {
    /// Likes, dislikes, defaults ("커피는 늘 아이스 아메리카노").
    case preference
    /// About the user: school, work, places.
    case fact
    /// Ongoing work.
    case project
    /// A contact, with how the user refers to them.
    case person
    /// Something the user does regularly.
    case routine
    /// Something the user said they will do, or was promised ("금요일까지 민수한테 포트폴리오 보내기로 했어").
    case commitment
    /// Something that happens on a day ("목요일에 치과 예약").
    case event

    var korean: String {
        switch self {
        case .preference: "취향"
        case .fact: "나에 대해"
        case .project: "하는 일"
        case .person: "사람"
        case .routine: "습관"
        case .commitment: "약속"
        case .event: "일정"
        }
    }

    /// How fast a memory of this kind stops mattering: after this many days it weighs half as much (an event is
    /// stale within the week, a promise or a taste within a season, a fact about the user or their people for a year).
    var halfLifeDays: Double {
        switch self {
        case .event: 7
        case .preference, .commitment, .routine, .project: 90
        case .fact, .person: 365
        }
    }

    var symbol: String {
        switch self {
        case .preference: "heart"
        case .fact: "person.text.rectangle"
        case .project: "hammer"
        case .person: "person.2"
        case .routine: "repeat"
        case .commitment: "checkmark.circle"
        case .event: "calendar"
        }
    }

    /// The kind a plain sentence most likely is (an imported memory.md line, an `aris-tools remember` fact).
    static func guess(_ text: String) -> ArisMemoryKind {
        let words = text.lowercased()
        func has(_ cues: [String]) -> Bool { cues.contains { words.contains($0) } }
        // How the user wants to be called is about them, a preference, never a person (ninth VM pass: "앞으로 나를 솔이라고
        // 불러" was kept under People).
        if addressesOwner(text) { return .preference }
        if ArisMemoryText.hasWord(text, "늘") || has(["좋아", "싫어", "선호", "즐겨", "항상", "prefer", "like", "love", "hate", "favorite", "favourite"]) { return .preference }
        if has(["매일", "평일", "주말마다", "아침마다", "저녁마다", "매주", "마다 ", "every ", "usually", "each morning", "weekdays"]) { return .routine }
        // Someone by name with their place in the user's life ("민수는 디자인팀 팀장이야", "Jisoo is my coworker"): a person, with
        // a page of their own (seventh VM pass: kept as "About you").
        if ArisMemoryWhen.person(in: text) != nil { return .person }
        if has(["만들고 있", "준비하고 있", "작업하고 있", "하는 중", "프로젝트", "project", "working on", "building"]) { return .project }
        if has(["하기로 했", "하기로 함", "주기로 했", "보내기로", "약속했", "약속함", "promised", "i'll send", "i will send", "agreed to", "owe "]) { return .commitment }
        // Something on a day ("이번 주 금요일에 부산 가", "dinner tomorrow"): an event, kept until that day ends.
        if has(["예약", "면접", "appointment", "interview on"]) || ArisMemoryWhen.namesDay(text) { return .event }
        // The user about themselves ("나는 …", "I'm …"): about them, even with a word for someone in it.
        if ownerSpeaks(words) { return .fact }
        if has(["엄마", "아빠", "형", "누나", "언니", "오빠", "동생", "친구", "여자친구", "남자친구", "교수님", "선생님", "라고 불러", "라고 부르",
                "mom", "dad", "brother", "sister", "friend", "girlfriend", "boyfriend", "professor"]) { return .person }
        return .fact
    }

    /// The sentence says how to call or address the user ("나를 솔이라고 불러", "날 솔로 불러 줘", "call me the user").
    static func addressesOwner(_ text: String) -> Bool {
        let korean = #"(?:^|\s)(?:나를|날|저를|절|나한테|저한테)\s?(?:그냥\s)?\S{1,20}?(?:이?라고|으?로)\s?(?:불러|부르|불러줘|불러 줘|불러주|불러 주|불러요|호칭)"#
        let english = #"(?i)\b(?:call me|address me as|refer to me as)\b"#
        return text.range(of: korean, options: .regularExpression) != nil || text.range(of: english, options: .regularExpression) != nil
    }

    /// A sentence that opens with the user as its subject.
    private static func ownerSpeaks(_ lowered: String) -> Bool {
        let first = lowered.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return ["나는", "난", "저는", "전", "내가", "제가", "i", "i'm", "im", "i've", "i'd"].contains(first)
    }
}

/// Where a memory came from.
enum ArisMemorySource: String, Codable, Sendable {
    /// Where it came from as the user reads it, in three words: their own words (직접 말함), what Aris or an AI made of
    /// them (추정), or another place (가져옴).
    func label(korean: Bool) -> String {
        switch self {
        case .said: korean ? "직접 말함" : "said"
        case .learned, .tool: korean ? "추정" : "inferred"
        case .imported: korean ? "가져옴" : "imported"
        }
    }

    /// The user said "기억해" (the agent wrote their words as said).
    case said
    /// Picked out of a clean turn of the user's own words, after it was answered.
    case learned
    /// `aris-tools remember`, through the brain's risk gate.
    case tool
    /// memory.md, once.
    case imported
}

struct ArisMemoryRecord: Equatable, Sendable {
    let id: String
    var kind: ArisMemoryKind
    /// What it is about, as the user calls it ("커피", "엄마"); may be empty.
    var subject: String
    var text: String
    var source: ArisMemorySource
    /// When the user said it (the turn it came from).
    var turnAt: Date
    /// 0…1: said or imported start high, picked-out ones lower; each repeat raises it.
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date
    /// When it last went into a turn's context because it was relevant.
    var lastUsedAt: Date?
    var useCount: Int
    /// From when it holds (nil: from when it was said) and until when (nil: still).
    var validFrom: Date? = nil
    var validUntil: Date? = nil
    /// Set on an older wording kept as history: the memory that replaced it (never shown or recalled by default).
    var supersededBy: String? = nil

    /// Still true at `now`: not replaced, and not past its end.
    func isCurrent(at now: Date) -> Bool { supersededBy == nil && (validUntil.map { $0 > now } ?? true) }

    /// "엄마 — 꽃을 좋아해" for a subject the text doesn't name, else the text.
    var line: String {
        let trimmed = subject.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !ArisMemoryText.normalized(text).contains(ArisMemoryText.normalized(trimmed)) else { return text }
        return "\(trimmed) — \(text)"
    }
}

/// A memory about to be written: from the user's words, the on-device model or a tool.
struct ArisMemoryCandidate: Equatable, Sendable {
    var kind: ArisMemoryKind
    var subject: String
    var text: String
    var confidence: Double
    /// A learned one: the whole sentence of the user's words it was picked from, which the write gate reads too.
    var sentence: String? = nil
}

enum ArisMemoryText {
    /// The note the app adds when dropped files ride along with a request (ArisPendingFiles.note).
    static let filesNote = "\n\n(첨부한 파일: "

    /// The user's words without that note: a file's path is never a fact about them (QA follow-up to BUG-7), and a file's text
    /// (read in after the note, ArisAttachmentText) is never their words to any gate: it can't name an app or a window, make
    /// a place or typed text "his", or cover an action (security review of BUG-35). Only `opensAttachment` sees the note.
    static func ownWords(_ text: String) -> String {
        text.range(of: filesNote).map { String(text[..<$0.lowerBound]) } ?? text
    }

    /// A memory longer than this is cut (it is one fact, not a document).
    static let maxLength = 200

    /// Lowercased and composed, letters and digits only ("커피는, 늘!" → "커피는늘").
    static func normalized(_ text: String) -> String {
        String(text.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        })
    }

    /// Words: runs of letters and digits, lowercased and composed.
    static func words(_ text: String) -> [String] {
        text.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool { (0xAC00...0xD7A3).contains(scalar.value) }

    /// English words that say nothing about what a text is about.
    static let latinStopwords: Set<String> = [
        "a", "an", "the", "i", "im", "me", "my", "mine", "you", "your", "we", "our", "is", "am", "are", "was", "were", "be",
        "to", "of", "in", "on", "at", "for", "and", "or", "that", "this", "it", "its", "with", "do", "does", "did", "what",
        "about", "so", "as", "by", "from", "please", "can", "could", "would", "will", "just",
    ]

    /// What two texts are compared by: each Hangul run as its syllable pairs (a one-syllable run as itself), each Latin
    /// word (stopwords out, a plural s dropped) and each number.
    static func grams(_ text: String) -> Set<String> {
        var grams = Set<String>()
        for word in words(text) {
            var run: [Character] = [], latin = ""
            func flushRun() {
                if run.count == 1 { grams.insert(String(run)) }
                if run.count > 1 { for i in 0..<(run.count - 1) { grams.insert(String(run[i...i + 1])) } }
                run = []
            }
            func flushLatin() {
                if !latin.isEmpty, !latinStopwords.contains(latin) {
                    grams.insert(latin.count > 3 && latin.hasSuffix("s") && !latin.hasSuffix("ss") ? String(latin.dropLast()) : latin)
                }
                latin = ""
            }
            for character in word {
                if let scalar = character.unicodeScalars.first, isHangul(scalar) {
                    flushLatin()
                    run.append(character)
                } else {
                    flushRun()
                    latin.append(character)
                }
            }
            flushRun()
            flushLatin()
        }
        return grams
    }

    /// 0…1: how alike two texts are (Dice over their grams).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = grams(a), y = grams(b)
        guard !x.isEmpty, !y.isEmpty else { return normalized(a) == normalized(b) && !normalized(a).isEmpty ? 1 : 0 }
        return 2 * Double(x.intersection(y).count) / Double(x.count + y.count)
    }

    /// 0…1: how much of `text` is in `source` (the share of its grams that `source` has).
    static func groundedness(_ text: String, in source: String) -> Double {
        let x = grams(text)
        guard !x.isEmpty else { return 0 }
        return Double(x.intersection(grams(source)).count) / Double(x.count)
    }

    /// Matched with spaces taken out ("비 밀 번 호", "인증 번호", "api key").
    private static let secretPhrases = ["비밀번호", "비번", "암호", "패스워드", "카드번호", "계좌", "주민번호", "주민등록", "인증번호", "보안코드", "핀번호",
                                        "토큰", "password", "passcode", "passwd", "pincode", "pinnumber", "apikey", "accesskey", "secretkey", "privatekey",
                                        "token", "socialsecurity", "cvv", "cvc", "cardnumber", "accountnumber", "securitycode"]
    /// Matched only as whole words ("키" is a key; "키는 180" is a height).
    private static let secretWords: Set<String> = ["핀", "키", "pin", "pw", "pwd", "ssn", "otp"]
    /// What a key or token starts with.
    private static let keyPrefixes = ["sk-", "sk_", "pk_", "rk_", "ghp_", "gho_", "ghs_", "github_pat_", "glpat-", "xoxb-", "xoxp-", "akia", "asia", "aiza"]

    /// Never remembered: a password, PIN, code or key (by name, or by its look: a long run of digits, a key-like string),
    /// or a door code.
    static func isSecret(_ text: String) -> Bool {
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased()
        let squashed = String(lowered.filter { !$0.isWhitespace })
        if secretPhrases.contains(where: { squashed.contains($0) }) { return true }
        if scriptWords(lowered).contains(where: secretWords.contains) { return true }
        if lowered.range(of: #"(도어락|현관)\D{0,12}\d"#, options: .regularExpression) != nil { return true }
        if longDigits(lowered) { return true }
        return lowered.split(whereSeparator: \.isWhitespace).contains { raw in looksLikeKey(String(raw)) }
    }

    // MARK: - What the user asks to remember

    /// A credential's own name, spaces inside it allowed ("비 밀 번 호", "api key").
    private static let credentialKorean = #"(?:비\s*밀\s*번\s*호|비\s*번|암\s*호|패\s*스\s*워\s*드|카\s*드\s*번\s*호|주\s*민\s*(?:등\s*록\s*)?번\s*호|인\s*증\s*번\s*호|보\s*안\s*코\s*드|핀\s*번\s*호|(?:api|에이피아이|액세스|시크릿|비밀|개인)\s*키)"#
    private static let credentialLatin = #"(?<![a-z])(?:password|passcode|passwd|pin[\s_-]*code|pin[\s_-]*number|api[\s_-]*key|access[\s_-]*key|secret[\s_-]*key|private[\s_-]*key|cvv|cvc|card[\s_-]*number|security[\s_-]*code|social\s*security(?:\s*number)?|ssn)(?![a-z])"#
    /// Words that are a credential's name only with a value beside them ("토큰 이코노미" and "pin the note" are not).
    private static let credentialLoose = #"(?<![a-z가-힣])(?:토큰|핀|token|pin|pw|pwd|otp)(?![a-z])"#
    /// What follows a name before its value: a particle or "is", a colon or an equals sign.
    private static let saysIs = #"\s*(?:은|는|이|가|도|is|was|:|=)\s*[:=]?\s*"#
    /// A value written in plain keyboard characters: three or more of them with a digit among them.
    private static let digitValue = #"(?=[!-~]{3,})[!-~]*\d[!-~]*"#
    /// English words that follow "password is …" without being one.
    private static let notValues: Set<String> = ["too", "not", "the", "a", "an", "in", "on", "at", "saved", "stored", "kept", "weak", "strong", "long", "short",
                                                 "old", "new", "same", "different", "expired", "wrong", "right", "for", "what", "something", "still", "also",
                                                 "always", "never", "required", "needed", "optional", "hard", "easy", "safe", "secure", "changed", "updated",
                                                 "reset", "going", "about", "like", "one", "that", "this", "there", "here", "really", "very", "just", "now"]

    /// What isn't kept even when the user says 기억해: something that is plainly a credential's value. A key or
    /// token by its look, a password, PIN or code named with its value ("비밀번호는 hunter2", "cvc 991"), a door code, a
    /// card number, a resident number. Nothing else is held back from his own request: a phone number, a student
    /// number, his height, an account to send money to, and ordinary words like 암호학, 계좌 이체 or 토큰 이코노미 are
    /// remembered (audit mem-1). What Aris picks up on its own stays under the stricter `isSecret`.
    static func isCredential(_ text: String) -> Bool {
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased()
        if lowered.split(whereSeparator: \.isWhitespace).contains(where: { looksLikeKey(String($0)) }) { return true }
        if lowered.range(of: #"(도어락|현관)\D{0,12}\d{3,}"#, options: .regularExpression) != nil { return true }
        // A card number (15 or 16 digits) or a resident number (six digits, a dash, seven more).
        if longDigits(lowered, atLeast: 15) || lowered.range(of: #"(?<!\d)\d{6}\s*-\s*[1-4]\d{6}(?!\d)"#, options: .regularExpression) != nil { return true }
        // A Korean name for one, then anything typed in keyboard characters: Korean sentences about a password go on in Hangul.
        if lowered.range(of: credentialKorean + #"(?:\s*(?:은|는|이|가|도|를|을))?\s*[:=]?\s*[!-~]{3,}"#, options: .regularExpression) != nil { return true }
        // An English name, then a value with a digit in it, or "is <something>".
        if lowered.range(of: credentialLatin + #"\s*[:=]?\s*"# + digitValue, options: .regularExpression) != nil { return true }
        if saysValue(after: credentialLatin, in: lowered) { return true }
        // A loose name, then "is <something>", or a value of four or more characters with a digit that isn't a count ("토큰 1000개").
        if saysValue(after: credentialLoose, in: lowered) { return true }
        return lowered.range(of: credentialLoose + #"\s*(?=[!-~]{4,})[!-~]*\d[!-~]*(?![!-~])(?![개번명원시분일월년살층호장권대차회])"#, options: .regularExpression) != nil
    }

    /// "<name> is <value>" (or 는, a colon, an equals sign): a value of three or more keyboard characters that isn't an
    /// ordinary English word after "is" ("my password is too weak").
    private static func saysValue(after name: String, in lowered: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: name + saysIs + #"([!-~]{3,})"#) else { return false }
        let range = NSRange(lowered.startIndex..., in: lowered)
        return expression.matches(in: lowered, range: range).contains { match in
            guard let found = Range(match.range(at: 1), in: lowered) else { return false }
            let value = lowered[found].trimmingCharacters(in: CharacterSet(charactersIn: ".,!?\"'"))
            return value.count >= 3 && !notValues.contains(value)
        }
    }

    /// Eight or more digits in one run, with spaces, dashes, dots, slashes or underscores inside it (a card, an account,
    /// a phone); a date (2026.11.05, 2026-11-05) isn't one.
    private static func longDigits(_ text: String, atLeast: Int = 8) -> Bool {
        let undated = text.replacingOccurrences(of: #"\b\d{4}[./-]\d{1,2}[./-]\d{1,2}\b"#, with: " ", options: .regularExpression)
        var digits = 0
        for scalar in undated.unicodeScalars {
            if CharacterSet.decimalDigits.contains(scalar) {
                digits += 1
                if digits >= atLeast { return true }
            } else if !" -./_".unicodeScalars.contains(scalar) {
                digits = 0
            }
        }
        return false
    }

    /// One word as written (split at spaces only, so sk-ant-… and an AWS key with / stay whole): a known key prefix,
    /// or 20+ characters of letters and digits mixed that isn't a plain link.
    private static func looksLikeKey(_ raw: String) -> Bool {
        let token = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’()[]{}<>,.;:!?"))
        if token.count >= 12, keyPrefixes.contains(where: token.hasPrefix) { return true }
        guard token.count >= 20, !(token.hasPrefix("http") && !token.contains("=")) else { return false }
        return token.contains(where: \.isNumber) && token.contains(where: \.isLetter)
    }

    private static let koreanNegations: Set<String> = ["안", "못", "말고", "아니", "아니야", "아니고", "아냐"]
    private static let englishNegations: Set<String> = ["not", "don't", "dont", "doesn't", "doesnt", "never", "no", "isn't", "isnt", "can't", "cant",
                                                        "cannot", "won't", "wont", "hate", "dislike"]

    /// Whether `text` says no to something ("커피 안 마셔", "고기 못 먹어", "단 거 싫어", "I don't drink coffee"): a negated
    /// text and a plain one are never the same memory, and a memory must keep its words' no.
    static func isNegated(_ text: String) -> Bool {
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased()
        let spaced = lowered.split(whereSeparator: \.isWhitespace).map { $0.trimmingCharacters(in: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'"))) }
        if spaced.contains(where: englishNegations.contains) || spaced.contains(where: { $0.hasSuffix("n't") }) { return true }
        return words(lowered).contains { word in
            koreanNegations.contains(word) || word.contains("않") || word.contains("싫") || word.hasPrefix("못") && word.count <= 3
        }
    }

    /// Words, also split where Hangul meets other letters ("pw는" → "pw", "는").
    static func scriptWords(_ text: String) -> [String] {
        words(text).flatMap { word -> [String] in
            var parts: [String] = [], current = "", hangul: Bool?
            for character in word {
                let isHangul = character.unicodeScalars.first.map(Self.isHangul) ?? false
                if let hangul, hangul != isHangul { parts.append(current); current = "" }
                hangul = isHangul
                current.append(character)
            }
            if !current.isEmpty { parts.append(current) }
            return parts
        }
    }

    /// Whether `word` is one of `text`'s words (whole: "늘" in "커피는 늘 라떼", not in "하늘").
    static func hasWord(_ text: String, _ word: String) -> Bool { words(text).contains(word) }

    /// About how many tokens a text costs a brain: a Hangul syllable about one, other text about four characters each.
    static func tokenEstimate(_ text: String) -> Int {
        var hangul = 0, other = 0
        for scalar in text.unicodeScalars {
            if isHangul(scalar) { hangul += 1 } else if !CharacterSet.whitespaces.contains(scalar) { other += 1 }
        }
        return hangul + (other + 3) / 4
    }

    /// One line, trimmed and cut to `maxLength`.
    static func cleaned(_ text: String) -> String {
        let flat = text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".,;:·-–—\"'“”‘’")))
        return String(flat.prefix(maxLength))
    }

    static func isKorean(_ text: String) -> Bool { text.unicodeScalars.contains(where: isHangul) }

    /// "yyyy-MM-dd" in `calendar`'s time zone.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
