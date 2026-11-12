//
//  ArisDropLearned.swift
//  Aris
//
//  The dropped-file chips that learn ("'이거 누구한테 메일 보내줘' 10번 했으면, 다음에 업로드할 때 '누구한테 메일
//  보내기' 이렇게 뜨냐?"). When the user drops files and then types or says their own request, the request's shape is
//  remembered for that kind of file: (kind, request, how often, when). One he made at least three times in the last
//  sixty days comes up as a chip the next time he drops that kind of file, before the built-in chips, at most two,
//  worded from his own words. Pressing it sends exactly the remembered request with the files, as if he had typed it:
//  the same turn, the same cards and confirmations. Nothing else is ever a chip: only his own typed or spoken words
//  are remembered, never a file's text or an AI's, never a request that looks like it holds a secret, never a long
//  one. The same request about another file is the same shape: file names in it become "이 파일". At most two hundred
//  shapes are kept, the least recently used going first; one not used for sixty days is forgotten.
//  Values only: each change is a new one. Foundation only, so it is tested.
//

import Foundation

/// One request the user made of files of one kind.
struct ArisDropHabit: Codable, Equatable, Identifiable {
    /// The kinds of files it was made of ("pdf", "image+pdf": ArisDropLearned.kindKey).
    var kind: String
    /// The request as it is sent again: his own words, file names replaced.
    var request: String
    /// Uses since it was first made (or since it was last forgotten for lying unused).
    var count: Int
    /// When it was last used, the latest three times (seconds since 1970, oldest first).
    var recent: [Double]

    var last: Double { recent.last ?? 0 }
    var id: String { kind + "\n" + ArisDropLearned.key(request) }
}

struct ArisDropLearned: Equatable {
    /// How many shapes are kept.
    static let most = 200
    /// A request becomes a chip at this many uses …
    static let threshold = 3
    /// … within this long, and one unused for this long is forgotten.
    static let window: TimeInterval = 60 * 86_400
    /// How many learned chips come up.
    static let chipsShown = 2
    /// The longest request that is remembered (a chip is a short, repeated ask, not a brief).
    static let longestRequest = 120
    /// A chip's label is cut to this width (a Korean letter is two wide: ArisTeammateName.width).
    static let labelWidth = 30

    private(set) var habits: [ArisDropHabit] = []

    // MARK: - Kinds

    static func name(_ kind: ArisDropKind) -> String {
        switch kind {
        case .pdf: return "pdf"
        case .document: return "document"
        case .text: return "text"
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .folder: return "folder"
        case .other: return "other"
        }
    }

    /// The kinds of the files dropped, each once, in a fixed order: three PDFs are "pdf", a PDF and a picture "image+pdf".
    static func kindKey(_ kinds: [ArisDropKind]) -> String {
        Set(kinds.map(name)).sorted().joined(separator: "+")
    }

    // MARK: - A request's shape

    private static let fileWord = (korean: "이 파일", english: "this file")
    private static let endMarks = CharacterSet(charactersIn: ".!?~。！？… ")

    static func hasHangul(_ text: String) -> Bool { text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }

    /// His words as they are remembered: on one line, the dropped files' names (and anything that reads as a file's
    /// name) replaced by "이 파일" / "this file", end marks off. Nil when nothing is to be remembered: no words, too
    /// long, or something in them looks like a secret.
    static func normalized(_ words: String, fileNames: [String]) -> String? {
        var text = words.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let stand = hasHangul(text) ? fileWord.korean : fileWord.english
        // The longest name first: "report.final.pdf" before its own "report".
        let names = fileNames.flatMap { name -> [String] in
            let base = (name as NSString).deletingPathExtension
            return base.count >= 3 && base != name ? [name, base] : [name]
        }.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        for name in names {
            text = text.replacingOccurrences(of: name, with: stand, options: [.caseInsensitive])
        }
        let types = (ArisDropKind.documentTypes.union(ArisDropKind.textTypes).union(ArisDropKind.imageTypes).union(ArisDropKind.videoTypes)
            .union(ArisDropKind.audioTypes).union(["pdf", "xlsx", "xls", "pptx", "ppt", "key", "pages", "numbers", "zip", "hwp", "hwpx"])).sorted { $0.count > $1.count }
        let named = #"[^\s"'“”‘’]+\.(?:"# + types.joined(separator: "|") + #")(?![A-Za-z0-9])"#
        text = text.replacingOccurrences(of: named, with: stand, options: [.regularExpression, .caseInsensitive])
        // "이 파일 이 파일" after both a name and its base were said.
        text = text.replacingOccurrences(of: "(?:" + NSRegularExpression.escapedPattern(for: stand) + #"\s*){2,}"#, with: stand + " ", options: .regularExpression)
        // "send the budget to Minsu" with budget.xlsx dropped: "send this file to Minsu".
        text = text.replacingOccurrences(of: #"\b(?:the|my|that)\s+this file\b"#, with: fileWord.english, options: [.regularExpression, .caseInsensitive])
        text = text.trimmingCharacters(in: endMarks)
        // Judged once the files' names are out of it: a name is never stored, whatever it looks like.
        guard !text.isEmpty, text.count <= longestRequest, !looksSecret(text) else { return nil }
        return text
    }

    /// What two requests are compared by: small letters, no spaces ("보내 줘" is "보내줘").
    static func key(_ request: String) -> String {
        String(request.lowercased().unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    /// Whether the words look like they hold a secret: a word the drop guard holds a file back for (a password, a
    /// token, a key file's name: ArisDropGuard), or a long run of letters and digits that reads as a key itself.
    static func looksSecret(_ words: String) -> Bool {
        let tokens = words.split(whereSeparator: \.isWhitespace).map(String.init)
        // Each word that reads as a file's or a key's name is judged as one (".env", "id_rsa", "passwords.txt") …
        let names = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’,()[]")) }.filter { $0.contains(".") || $0.contains("_") }
        if names.contains(where: { ArisDropGuard.looksSecret($0, isKeynote: { _ in true }) }) { return true }
        // … and the sentence as one name ("api key", "seed phrase", "비밀번호"), its dots and slashes as spaces.
        let sentence = words.map { ".\\/:".contains($0) ? " " : $0 }.map(String.init).joined()
        if ArisDropGuard.looksSecret(sentence, isKeynote: { _ in true }) { return true }
        return tokens.contains(where: looksLikeKey)
    }

    /// Twenty or more of a key's letters in a row, with letters and digits both ("sk-ant-api03-…", a JWT, a hash).
    private static func looksLikeKey(_ token: String) -> Bool {
        let runs = token.split { !($0.isASCII && ($0.isLetter || $0.isNumber || "_-+/=.".contains($0))) }
        return runs.contains { run in
            run.count >= 20 && run.contains(where: \.isNumber) && run.contains(where: \.isLetter) && !run.contains("/")
        }
    }

    // MARK: - Remembering

    /// The user asked `words` of files of `kinds` (named `fileNames`). The same shape again counts once more.
    func recording(_ words: String, kinds: [ArisDropKind], fileNames: [String], at now: Date = Date()) -> ArisDropLearned {
        guard !kinds.isEmpty, let request = Self.normalized(words, fileNames: fileNames) else { return self }
        let kind = Self.kindKey(kinds), key = Self.key(request), time = now.timeIntervalSince1970
        // What has lain unused for the window is forgotten first: it starts again from one.
        var kept = habits.filter { time - $0.last <= Self.window }
        if let index = kept.firstIndex(where: { $0.kind == kind && Self.key($0.request) == key }) {
            let old = kept[index]
            kept[index] = ArisDropHabit(kind: kind, request: request, count: old.count + 1, recent: Array((old.recent + [time]).suffix(Self.threshold)))
        } else {
            kept.append(ArisDropHabit(kind: kind, request: request, count: 1, recent: [time]))
        }
        if kept.count > Self.most {
            kept = Array(kept.sorted { $0.last > $1.last }.prefix(Self.most))
        }
        return ArisDropLearned(habits: kept)
    }

    /// The requests that come up as chips for files of `kinds`: made at least three times within the last sixty days,
    /// the most used first (then the most recent), at most two.
    func chips(for kinds: [ArisDropKind], at now: Date = Date()) -> [ArisDropHabit] {
        guard !kinds.isEmpty else { return [] }
        let kind = Self.kindKey(kinds), time = now.timeIntervalSince1970
        let earned = habits.filter { habit in
            habit.kind == kind && habit.recent.count >= Self.threshold && time - habit.recent[habit.recent.count - Self.threshold] <= Self.window
        }
        return Array(earned.sorted { ($0.count, $0.last) > ($1.count, $1.last) }.prefix(Self.chipsShown))
    }

    func forgetting(_ habit: ArisDropHabit) -> ArisDropLearned {
        ArisDropLearned(habits: habits.filter { $0.id != habit.id })
    }

    func forgettingAll() -> ArisDropLearned { ArisDropLearned() }

    // MARK: - Reading the turn's words

    /// The paths in a request's files' note (ArisPendingFiles.request), in order.
    static func paths(in text: String) -> [String] {
        guard let start = text.range(of: "\n\n" + ArisPendingFiles.note) else { return [] }
        let listed = text[start.upperBound...].components(separatedBy: " — ").first ?? ""
        return listed.components(separatedBy: ", ").filter { $0.hasPrefix("/") }
    }

    // MARK: - Stored

    var data: Data { (try? JSONEncoder().encode(habits)) ?? Data() }

    /// What a stored file holds; nothing when it can't be read (a damaged file starts the learning over).
    init(data: Data) {
        let read = (try? JSONDecoder().decode([ArisDropHabit].self, from: data)) ?? []
        habits = Array(read.filter { !$0.kind.isEmpty && !$0.request.isEmpty && $0.request.count <= Self.longestRequest && $0.count > 0 && !$0.recent.isEmpty }.prefix(Self.most))
    }

    init(habits: [ArisDropHabit] = []) { self.habits = habits }
}

/// A learned chip as it is drawn: its label, and the habit it sends.
struct ArisDropLearnedChip: Equatable, Identifiable {
    let habit: ArisDropHabit
    let label: String
    var id: String { habit.id }

    static func make(_ habits: [ArisDropHabit]) -> [ArisDropLearnedChip] {
        habits.map { ArisDropLearnedChip(habit: $0, label: ArisDropLearnedWords.label($0.request)) }
    }
}

/// One pill of the chips' first row: his own first, then the built-in ones in their order.
enum ArisDropRowItem: Equatable, Identifiable {
    case learned(ArisDropLearnedChip)
    case builtIn(ArisDropChip)

    var id: String {
        switch self {
        case .learned(let chip): return "learned:" + chip.id
        case .builtIn(let chip): return chip.id
        }
    }

    static func firstRow(learned: [ArisDropLearnedChip], main: [ArisDropChip]) -> [ArisDropRowItem] {
        learned.prefix(ArisDropLearned.chipsShown).map(ArisDropRowItem.learned) + main.map(ArisDropRowItem.builtIn)
    }
}

/// A learned chip's words: its label from the user's own request, and the lines around forgetting.
enum ArisDropLearnedWords {
    private static let leading = #"^(?:이\s*파일들?|이거|이것들?|이걸|요거|얘)(?:을|를|은|는|도)?\s+(?:좀\s+)?"#
    private static let asking = #"\s*(?:좀\s*)?(?:줘요|줘봐|줘라|줘|주세요|주실래요|주시겠어요|줄래요|줄래|주라)$"#
    /// Verbs whose "-기" isn't made by a rule: said as they are.
    private static let nouns = ["써": "쓰기", "꺼": "끄기", "잘라": "자르기", "골라": "고르기", "불러": "부르기", "눌러": "누르기", "도와": "돕기",
                                "놔": "놓기", "켜": "켜기", "펴": "펴기", "가": "가기", "사": "사기", "봐": "보기", "와": "오기", "넣어": "넣기",
                                "들어": "듣기", "물어": "묻기", "실어": "싣기", "구워": "굽기", "주워": "줍기"]

    /// The chip's label: "이거 민수에게 메일로 보내 줘" → "민수에게 메일로 보내기"; an English request as it was said, with a
    /// capital. Cut in the middle to the chip's width (ClaudeNoticeLabel.shortened), so its verb stays in sight.
    static func label(_ request: String) -> String {
        var text = request
        if ArisDropLearned.hasHangul(text) {
            text = text.replacingOccurrences(of: leading, with: "", options: .regularExpression)
            if let ask = text.range(of: asking, options: .regularExpression) {
                text = noun(String(text[..<ask.lowerBound]))
            }
        } else {
            text = text.replacingOccurrences(of: #"^(?:please|can you|could you|would you)\s+|\s+please$"#, with: "", options: [.regularExpression, .caseInsensitive])
            text = text.prefix(1).uppercased() + text.dropFirst()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        return ClaudeNoticeLabel.shortened(text.isEmpty ? request : text, limit: ArisDropLearned.labelWidth)
    }

    /// "… 보내" → "… 보내기", "… 요약해" → "… 요약하기", "… 만들어" → "… 만들기", "… 올려" → "… 올리기", "… 바꿔" → "… 바꾸기".
    /// A verb form this can't be sure of keeps "주기" ("… 해 주기"), which is always right.
    static func noun(_ stem: String) -> String {
        let words = stem.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let verb = words.last else { return stem }
        let head = words.dropLast().joined(separator: " ")
        let join = { (made: String) in head.isEmpty ? made : head + " " + made }
        if let known = nouns[verb] { return join(known) }
        if verb.hasSuffix("해") { return join(String(verb.dropLast()) + "하기") }
        guard let last = verb.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(last) else { return stem + " 주기" }
        let index = last - 0xAC00, lead = index / 588, vowel = (index % 588) / 28, tail = index % 28
        let rest = String(verb.dropLast())
        let syllable = { (vowel: UInt32) in String(UnicodeScalar(0xAC00 + lead * 588 + vowel * 28)!) }
        guard tail == 0 else { return stem + " 주기" }
        switch vowel {
        case 1, 5: return join(verb + "기")                                   // ㅐ, ㅔ: 보내 → 보내기
        case 6 where !rest.isEmpty: return join(rest + syllable(20) + "기")    // ㅕ → ㅣ: 올려 → 올리기
        case 14 where !rest.isEmpty: return join(rest + syllable(13) + "기")   // ㅝ → ㅜ: 바꿔 → 바꾸기
        case 4, 0:
            // A whole "어" or "아" after a closed syllable: 만들어 → 만들기, 찾아 → 찾기.
            guard lead == 11, let before = rest.unicodeScalars.last?.value, (0xAC00...0xD7A3).contains(before), (before - 0xAC00) % 28 != 0 else {
                return stem + " 주기"
            }
            return join(rest + "기")
        default: return stem + " 주기"
        }
    }

    static func forget(english: Bool) -> String { english ? "Forget this suggestion" : "이 제안 지우기" }

    /// The pill's tooltip: whose it is, and how it goes away.
    static func help(_ request: String, english: Bool) -> String {
        english ? "You often ask this: “\(request)”. Right-click to forget it." : "자주 한 요청이에요: “\(request)”. 오른쪽 클릭으로 지울 수 있어요."
    }
}
