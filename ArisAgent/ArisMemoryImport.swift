//
//  ArisMemoryImport.swift
//  aris-agent
//
//  Bringing what another AI remembers about the user into Aris's person memory (설정 › 기억 › 다른 AI에서 가져오기).
//  The user copies Aris's own request (ArisMemoryImport.prompt) into the other AI, pastes what it printed, sees every line
//  in a preview and ticks what comes in. Nothing is summarised: the export is already one fact a line, so each ticked
//  line becomes one typed memory with its date, its source's name and his wording kept; the per-turn recall picks the
//  few a turn needs, so how many there are costs nothing.
//
//  The pasted text is outside text (another AI wrote it, and it can hold anything, sentences shaped like orders to
//  Aris included). So it never reaches a brain here: reading it is this file's rules and nothing else. Each line is
//  shown with what Aris makes of it, and his tick on that line is the gate:
//  - every line is defused as it is read: no < or > survives (a pasted </context> or <worked-before> can't close or
//    forge a block of the prompt it may later ride in), and letters that draw nothing (Hangul fillers, the braille
//    blank, variation selectors) are plain spaces, so what the preview shows is what is stored;
//  - a line that looks like a secret is dropped and shown as dropped (the strict rule memory.md lines pass);
//  - a line that reads as an order to act in any of its clauses (send, delete, pay, install, "ignore previous…", an
//    order ending in Korean, Aris or "you" doing one of those, an address with a token in it, prompt markup) is
//    flagged and not ticked; the check reads the line with look-alike letters folded (NFKC, Cyrillic and Greek
//    look-alikes as Latin), so "Ѕend" is "send";
//  - a line the user should look at before it goes in is not ticked for them, under whatever heading the paste put it (the
//    paste's headings never decide that): a link or an email address, Aris or "you" as a subject, or the shape of an
//    instruction ("always…", "never…", 항상…);
//  - instructions (how a chat AI should answer: "always…", "never…", tone, format) are their own group, not ticked,
//    with a line saying what ticking means; a ticked one is a preference marked as an instruction, as sure as a spoken
//    기억해 and never among the memories every turn gets by import alone;
//  - a line that would replace one of the user's memories says which wording it replaces; it is not ticked when that
//    memory is one he said himself or confirmed, and a date later than tomorrow is no date (it can't win by date);
//  - a line that couldn't be read is shown and never imported.
//  Foundation only (tested).
//

import Foundation

/// The five groups the request asks for, in its order, and whatever stood under no heading.
enum ArisImportCategory: String, CaseIterable, Sendable {
    case instructions, personal, career, projects, preferences, other
}

/// What Aris makes of one line before the user decides.
enum ArisImportState: String, Sendable {
    /// Not in memory yet.
    case new
    /// The same thing is remembered already: importing it makes that memory a little surer.
    case known
    /// The same subject in other words, and this line is the newer: it would replace the old wording.
    case updates
    /// The same subject in other words, and what Aris has is newer: it stays, this line changes nothing.
    case older
    /// Looks like a password, a code, a key or an account number: never kept.
    case secret
    /// Reads as an order to do something, or carries an address with a token: flagged, not ticked.
    case acts
}

struct ArisImportLine: Equatable, Sendable {
    /// Its place in the paste, from 1.
    var number: Int
    var category: ArisImportCategory
    /// The line's own date; nil for [unknown].
    var date: Date?
    /// The wording as it came, defused (ArisMemoryImport.cleaned).
    var text: String
    var kind: ArisMemoryKind
    var state = ArisImportState.new
    /// Something the user should look at before it goes in (ArisMemoryImport.needsLook): never ticked for them.
    var look = false
    /// The wording of the memory this line would replace (state .updates).
    var replaces: String?
    /// The memory it would replace is one the user said themselves or confirmed: never replaced without their own tick.
    var keepsHis = false
    /// It came with a date later than tomorrow: its own line with no date, never ticked for him (the third VM run, B12:
    /// such a line was read as the line above going on, and imported glued to it).
    var futureDate = false

    /// Exactly what is stored when it differs from the line: the memory's short title (ArisMemoryImport.title); nil
    /// when the line is stored as it reads.
    var stored: String? {
        let title = ArisMemoryImport.title(text)
        return title == text ? nil : title
    }

    /// Whether the preview shows it ticked: everything that is new or newer, but instructions, anything flagged or to
    /// look at, and a new wording over one of his own memories.
    var ticked: Bool {
        category != .instructions && !look && !futureDate && !(state == .updates && keepsHis) && (state == .new || state == .updates || state == .known)
    }
    /// Whether a tick can import it at all.
    var importable: Bool { state != .secret && state != .older }
}

struct ArisImportParse: Equatable, Sendable {
    var lines: [ArisImportLine] = []
    /// Lines that are neither a heading nor an item, as written (shown, never imported).
    var unreadable: [String] = []
    /// What the export said about itself: true "this is everything", false "there is more"; nil when it said neither.
    var complete: Bool?
}

enum ArisMemoryImport {
    static let mostLines = 600
    static let mostText = 2_000
    static let mostPaste = 200_000

    // MARK: - The request the user copies (Aris's own wording)

    static func prompt(korean: Bool) -> String {
        korean ? """
            지금까지 나에 대해 기억하고 있는 것을 다른 곳으로 옮기려고 해. 저장된 기억과 이 대화들에서 알게 된 것을 빠짐없이 적어 줘.

            아래 다섯 묶음으로, 이 순서대로, 묶음 이름을 한 줄에 쓰고 그 아래에 적어 줘.
            1. 지시 사항: 내가 답하는 방식에 대해 부탁한 것 (말투, 형식, "항상 …", "절대 …")
            2. 개인 정보: 이름, 사는 곳, 가족과 주변 사람, 학교, 관심사
            3. 경력: 하는 일, 다닌 곳, 할 줄 아는 것
            4. 프로젝트: 하고 있거나 했던 일. 프로젝트 하나에 한 줄
            5. 선호: 좋아하는 것과 싫어하는 것, 자주 쓰는 도구, 기본으로 고르는 것

            한 줄에 하나씩 이렇게 써 줘.
            [YYYY-MM-DD] - 내용
            날짜를 모르면 [unknown] - 내용

            묶음 안에서는 오래된 것부터. 내가 한 말은 줄이거나 다듬지 말고 그대로. 전체를 코드 블록 하나에 넣고, 블록 다음 줄에 이게 전부인지 아직 더 있는지 한 문장으로 말해 줘.
            """ : """
            I am moving what you remember about me somewhere else. Write down everything you know about me, from your saved memories and from our conversations, leaving nothing out.

            Use these five groups, in this order, each with its name on a line of its own:
            1. Instructions: what I asked about how you answer (tone, format, "always …", "never …")
            2. Personal details: name, where I live, family and the people around me, school, interests
            3. Career: what I do, where I have worked or studied, what I can do
            4. Projects: what I am working on or have worked on, one line per project
            5. Preferences: likes and dislikes, the tools I use, what I pick by default

            One item per line, written like this:
            [YYYY-MM-DD] - the item
            or, when you don't know the date, [unknown] - the item

            Oldest first inside each group. Keep my own wording: don't shorten or polish it. Put the whole list in one code block, and on the line after the block say in one sentence whether this is everything or there is more.
            """
    }

    // MARK: - Reading the paste

    private static let headings: [(ArisImportCategory, [String])] = [
        (.instructions, ["instructions", "instruction", "custom instructions", "지시 사항", "지시사항", "지시", "요청 사항", "요청사항", "응답 방식", "답변 방식"]),
        (.personal, ["personal details", "personal detail", "personal information", "personal info", "personal", "about me", "개인 정보", "개인정보", "개인 사항", "신상", "나에 대해"]),
        (.career, ["career", "work", "work and education", "professional", "professional background", "경력", "직업", "일", "학력과 경력", "커리어"]),
        (.projects, ["projects", "project", "프로젝트", "하는 일", "진행 중인 일", "작업"]),
        (.preferences, ["preferences", "preference", "likes and dislikes", "선호", "선호 사항", "선호사항", "취향", "좋아하는 것"]),
    ]

    /// The group a line names, when the whole line is a heading: "## 2. Personal details", "**경력**", "프로젝트:".
    static func heading(_ raw: String) -> ArisImportCategory? {
        var line = raw.trimmingCharacters(in: .whitespaces).lowercased()
        line = line.replacingOccurrences(of: #"^[#>\s]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^[(\[]?\d{1,2}[)\].:]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :：-–—"))
        guard !line.isEmpty, line.count <= 40 else { return nil }
        return headings.first { $0.1.contains(line) }?.0
    }

    private static let unknownDates: Set<String> = ["unknown", "n/a", "na", "none", "?", "알 수 없음", "알수없음", "모름", "미상", "날짜 모름", "날짜 미상", "unknown date"]

    /// "[2025-03-01] - text", "(2025/3/1) – text", "2025.03.01: text", "- [unknown] — text", "[2025-03] - text": the
    /// date (nil for unknown, and for a real date later than tomorrow: `future`) and the text; nil when the line doesn't
    /// open with a date in brackets or a bare date.
    static func dated(_ raw: String, now: Date = Date()) -> (date: Date?, text: String, future: Bool)? {
        let line = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^[-*•·]\s+"#, with: "", options: .regularExpression)
        let bracketed = #"^[\[(（【]\s*([^\])）】]{1,24}?)\s*[\])）】]\s*[-–—:：]?\s*(.+)$"#
        let bare = #"^(\d{4}[-./]\d{1,2}(?:[-./]\d{1,2})?)\s*[-–—:：]\s*(.+)$"#
        for pattern in [bracketed, bare] {
            guard let expression = try? NSRegularExpression(pattern: pattern), let match = expression.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let stamp = Range(match.range(at: 1), in: line), let rest = Range(match.range(at: 2), in: line) else { continue }
            let said = String(line[stamp]).trimmingCharacters(in: .whitespaces)
            let text = String(line[rest]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            if unknownDates.contains(said.lowercased()) { return (nil, text, false) }
            if let date = day(said, now: now) { return (date, text, false) }
            // A real date, only later than tomorrow: still a line of its own, without its date.
            if day(said) != nil { return (nil, text, true) }
        }
        return nil
    }

    /// A day as `day(_:)` reads it, and no later than tomorrow (the UTC day after `now`'s): a date in the future never
    /// makes a line "newer" than one of the user's memories.
    static func day(_ text: String, now: Date) -> Date? {
        guard let date = day(text), date <= latest(now) else { return nil }
        return date
    }

    /// The latest date a line may carry: noon UTC of the day after `now`'s.
    static func latest(_ now: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let today = calendar.startOfDay(for: now)
        return today.addingTimeInterval(86_400 + 12 * 3_600)
    }

    /// A day written as numbers (2025-03-01, 2025/3/1, 2025.03, 2025): a real date of this era, at noon UTC so no time
    /// zone moves it to its neighbour; nil for anything else.
    static func day(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { "-./".contains($0) }).map(String.init)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), (1970...2100).contains(year), parts[0].count == 4 else { return nil }
        let month = parts.count > 1 ? Int(parts[1]) ?? 0 : 1, dayOfMonth = parts.count > 2 ? Int(parts[2]) ?? 0 : 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard (1...12).contains(month), (1...31).contains(dayOfMonth),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 12)),
              calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    private static let saysComplete = ["this is everything", "that is everything", "that's everything", "this is complete", "the export is complete", "is complete", "nothing more",
                                       "nothing else", "that's all", "that is all", "이게 전부", "이것이 전부", "전부입니다", "전부예요", "전부야", "모두입니다", "더 없", "빠짐없이 적었",
                                       "전체입니다", "완전한 목록"]
    private static let saysMore = ["there is more", "there's more", "there are more", "more to come", "not complete", "incomplete", "to be continued", "continued in", "truncated",
                                   "더 있", "아직 남", "이어서", "계속됩니다", "계속할게", "전부는 아니", "전부가 아니", "일부만"]

    /// What a sentence outside the items says about the export: true complete, false more to come, nil neither.
    static func completeness(_ line: String) -> Bool? {
        let lowered = line.lowercased()
        // "more" is asked first: "this is not everything, there is more" says both words.
        if saysMore.contains(where: lowered.contains) { return false }
        return saysComplete.contains(where: lowered.contains) ? true : nil
    }

    /// The paste, line by line. With code fences only what is inside them is the list (the sentence after says whether
    /// it is complete); with none the whole paste is. A line that goes on under an item (no date, no bullet, no
    /// heading) belongs to that item; a bullet with no date is an item of unknown date; anything else is shown as
    /// unreadable, except the talk around the list.
    static func parse(_ pasted: String, now: Date = Date()) -> ArisImportParse {
        var parsed = ArisImportParse()
        let text = String(pasted.prefix(mostPaste)).replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let all = text.components(separatedBy: "\n")
        let fenced = all.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }.count >= 2
        var inside = !fenced, category = ArisImportCategory.other, open = false
        func add(_ date: Date?, _ words: String) {
            // Past the cap nothing more is read into the list, not even onto its last item.
            guard parsed.lines.count < mostLines else { return open = false }
            parsed.lines.append(ArisImportLine(number: parsed.lines.count + 1, category: category, date: date, text: String(clean(words).prefix(mostText)),
                                               kind: .fact))
            open = true
        }
        for raw in all {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if fenced { inside.toggle() }
                open = false
                continue
            }
            guard !line.isEmpty else { open = false; continue }
            guard inside else {
                // Talk around the block: only what it says about being complete is kept.
                if let said = completeness(line) { parsed.complete = said }
                continue
            }
            if let found = heading(line) {
                category = found
                open = false
            } else if let item = dated(line, now: now) {
                add(item.date, item.text)
                if item.future, open, let last = parsed.lines.indices.last { parsed.lines[last].futureDate = true }
            } else if let bullet = line.range(of: #"^[-*•·]\s+"#, options: .regularExpression) {
                add(nil, String(line[bullet.upperBound...]))
            } else if open, let last = parsed.lines.indices.last, completeness(line) == nil {
                // A wrapped line: it goes on from the item above.
                parsed.lines[last].text = String((parsed.lines[last].text + " " + clean(line)).prefix(mostText))
            } else if let said = completeness(line) {
                parsed.complete = said
            } else if !parsed.lines.isEmpty || category != .other {
                if parsed.unreadable.count < 50 { parsed.unreadable.append(String(line.prefix(200))) }
            }
            // (Talk before the first heading or item of a paste with no fence is left out.)
        }
        parsed.lines = parsed.lines.filter { !ArisMemoryText.normalized($0.text).isEmpty }.enumerated().map { index, line in
            var one = line
            one.number = index + 1
            one.kind = kind(of: one)
            return one
        }
        return parsed
    }

    /// Letters that draw nothing yet are no space: Hangul fillers, the halfwidth filler, the braille blank, the
    /// Mongolian separator, the grapheme joiner, Khmer's silent vowels, the object mark (variation selectors below).
    private static let blankLetters: Set<UInt32> = [0x3164, 0x115F, 0x1160, 0xFFA0, 0x2800, 0x180E, 0x034F, 0x17B4, 0x17B5, 0xFFFC, 0x1D159]

    static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        blankLetters.contains(scalar.value) || (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value)
            || (0x1D173...0x1D17A).contains(scalar.value)
    }

    /// One line as it is stored: no control characters, blank-drawing letters as spaces, the prompt's own tags
    /// defused (ArisAgentStream.fenced) and then no < or > at all, single spaces.
    static func cleaned(_ text: String) -> String {
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || isBlank($0) ? " " : $0 }))
        let defused = ArisAgentStream.fenced(plain).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
        return defused.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func clean(_ text: String) -> String { cleaned(text) }

    // MARK: - What each line is

    /// The kind Aris stores a line as: personal details are facts (a line about someone, a person), career is fact,
    /// a project a project, a preference and an instruction preferences; a line under no heading by its own words.
    static func kind(of line: ArisImportLine) -> ArisMemoryKind {
        switch line.category {
        case .instructions, .preferences: return .preference
        case .personal: return namesPerson(line.text) ? .person : .fact
        case .career: return .fact
        case .projects: return .project
        case .other: return ArisMemoryKind.guess(line.text)
        }
    }

    /// Whom a personal detail is about, when it is about someone else: a word for family, a friend or a teacher.
    private static let peopleKorean = ["엄마", "아빠", "어머니", "아버지", "부모님", "형", "누나", "언니", "오빠", "동생", "여동생", "남동생", "친구", "여자친구", "남자친구", "아내",
                                       "남편", "교수님", "선생님", "룸메이트", "할머니", "할아버지"]
    private static let peopleEnglish: Set<String> = ["mom", "mother", "dad", "father", "brother", "sister", "friend", "girlfriend", "boyfriend", "wife", "husband", "partner",
                                                     "professor", "roommate", "boss", "grandmother", "grandfather", "son", "daughter", "mom's", "dad's"]

    static func namesPerson(_ text: String) -> Bool {
        ArisMemoryText.scriptWords(text).contains { word in
            peopleEnglish.contains(word) || (ArisMemoryText.isKorean(word) && peopleKorean.contains { word == $0 || (word.hasPrefix($0) && $0.count >= 2) })
        }
    }

    /// Words that make a line an order to do something, not a thing to know.
    private static let actingEnglish = ["send", "email", "e-mail", "forward", "message", "text", "delete", "remove", "erase", "wipe", "upload", "download", "install", "run",
                                        "execute", "pay", "buy", "purchase", "transfer", "wire", "approve", "grant", "allow", "visit", "open", "click", "post", "share", "reply",
                                        "call", "trash", "reveal", "print", "export", "disable", "bypass", "skip"]
    private static let strongEnglish: Set<String> = ["send", "email", "forward", "delete", "erase", "wipe", "upload", "pay", "transfer", "wire", "install", "execute"]
    private static let aimed = ["ignore previous", "ignore all", "ignore the above", "ignore your", "disregard", "system prompt", "your instructions", "previous instructions",
                                "developer message", "jailbreak", "aris-tools", "without asking", "without confirmation", "do not ask", "don't ask",
                                "이전 지시", "앞의 지시", "위의 지시", "지시를 무시", "무시하고", "시스템 프롬프트", "확인 없이", "묻지 말고", "허락 없이", "승인 없이",
                                // The prompt's own blocks, as ArisAgentStream.fenced leaves a pasted tag.
                                "worked-before", "[context]", "[screen]", "[images]", "[say]", "[skills]", "[skill]", "[teammates]", "[teammate]", "[app-notes]"]
    /// A Korean order at the end of a clause ("…전달해 줘", "…보내"), and the same verbs asked of someone mid-clause.
    private static let actingKorean = #"(보내|전송해|삭제해|지워|제거해|송금|결제해|이체해|설치해|실행해|업로드|다운로드|클릭해|열어|공유해|전달해|승인해|허용해|답장해)[가-힣]{0,4}\s*(줘|주세요|라|해|하라|할 것|한다|하기|해야)?[.!]?$"#
    private static let askedKorean = #"(보내|전송해|삭제해|지워|제거해|송금해|결제해|이체해|설치해|실행해|업로드해|다운로드해|클릭해|열어|공유해|전달해|승인해|허용해|답장해)\s*(줘|주세요|주라|줄래|달라|주고)"#
    private static let fillers: Set<String> = ["please", "always", "never", "do", "don't", "dont", "you", "must", "should", "also", "then", "and", "now", "first", "immediately",
                                               "silently", "secretly", "quietly", "just"]
    /// Who an order is aimed at when it is the subject of a clause.
    private static let addressed: Set<String> = ["aris", "you"]
    private static let modals: Set<String> = ["should", "must", "will", "would", "can", "could", "shall", "may", "need", "needs", "have", "has", "always", "never", "are", "is", "to"]
    private static let answering: Set<String> = ["answer", "reply", "respond", "use", "write", "keep", "tell", "say", "speak", "talk", "ask", "remember", "check", "be", "do"]
    private static let koreanSubjects = ["아리스는", "아리스가", "아리스야", "아리스,", "너는", "네가", "니가", "너가", "당신은", "당신이"]
    private static let koreanOpeners = ["항상 ", "절대 ", "반드시 ", "언제나 "]

    /// Latin look-alikes in Cyrillic and Greek, as the Latin letter they pass for.
    private static let confusables: [UInt32: String] = [
        0x0430: "a", 0x0435: "e", 0x043E: "o", 0x0440: "p", 0x0441: "c", 0x0443: "y", 0x0445: "x", 0x0455: "s", 0x0456: "i", 0x0458: "j", 0x0501: "d",
        0x04BB: "h", 0x043A: "k", 0x0410: "a", 0x0412: "b", 0x0415: "e", 0x041A: "k", 0x041C: "m", 0x041D: "h", 0x041E: "o", 0x0420: "p", 0x0421: "c",
        0x0422: "t", 0x0425: "x", 0x0405: "s", 0x0406: "i", 0x0408: "j", 0x04AE: "y", 0x0423: "y", 0x0457: "i", 0x0491: "r",
        0x03B1: "a", 0x03BF: "o", 0x03C1: "p", 0x03BD: "v", 0x03C4: "t", 0x03B9: "i", 0x03BA: "k", 0x03B5: "e", 0x03C5: "u", 0x0391: "a", 0x0392: "b",
        0x0395: "e", 0x0396: "z", 0x0397: "h", 0x0399: "i", 0x039A: "k", 0x039C: "m", 0x039D: "n", 0x039F: "o", 0x03A1: "p", 0x03A4: "t", 0x03A5: "y", 0x03A7: "x",
    ]

    /// A line as the order check reads it: compatibility forms folded (NFKC: full-width letters, ligatures), Cyrillic
    /// and Greek look-alikes as the Latin letters they pass for, lower case.
    static func folded(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars.map { confusables[$0.value] ?? String($0) }.joined().lowercased()
    }

    /// A folded line's clauses: cut at a sentence's end, a semicolon or colon, a comma, "then", 그리고, and before an
    /// "and" that starts an order.
    static func clauses(_ folded: String) -> [String] {
        let cuts = #"[.!?;:。！？…]+(?=\s|$)|,\s|\s(?:and then|then|and also)\s|\s?(?:그리고|그다음에?|그러고 나서)\s|\s(?:and|&)\s(?=(?:please\s|always\s|also\s)?(?:send|email|e-mail|forward|delete|erase|wipe|upload|pay|transfer|wire|install|execute|share|post|reply|text|message)\b)"#
        return folded.replacingOccurrences(of: cuts, with: "\u{1}", options: .regularExpression)
            .split(separator: "\u{1}").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func words(_ clause: String) -> [String] {
        clause.split(whereSeparator: { !$0.isLetter && $0 != "-" && $0 != "'" }).map(String.init)
    }

    /// "forwards", "emailed", "sending" as the verb they are.
    private static func stem(_ word: String) -> String {
        for end in ["ing", "ed", "es", "s"] where word.count > end.count + 2 && word.hasSuffix(end) {
            let base = String(word.dropLast(end.count))
            if actingEnglish.contains(base) || answering.contains(base) { return base }
            if end == "ed" || end == "es", actingEnglish.contains(base + "e") { return base + "e" }
        }
        return word
    }

    /// Aris or "you" as the subject of a clause, followed by an acting verb (`acting`) or by any verb of answering or a
    /// modal ("you should…", "Aris always…").
    private static func addresses(_ words: [String], acting: Bool) -> Bool {
        for (index, word) in words.enumerated() where addressed.contains(word) && index + 1 < words.count {
            let next = stem(words[index + 1])
            if actingEnglish.contains(next) { return true }
            if !acting, modals.contains(next) || answering.contains(next) { return true }
        }
        return false
    }

    /// Whether a line reads as an order to act, in any of its clauses (the same rule under every heading): words aimed
    /// at the AI's own rules or the prompt's blocks, an address with a token in it, an address or a link together with
    /// a verb that sends, an English order opening a clause, Aris or "you" doing something, or a Korean order. Read
    /// with look-alike letters folded.
    static func acts(_ text: String) -> Bool {
        let lowered = folded(text)
        if aimed.contains(where: lowered.contains) { return true }
        if lowered.range(of: #"https?://\S*[?&#](?:[a-z_\-]*(?:token|key|auth|sig|signature|secret|code|session|password)[a-z_\-]*)="#, options: .regularExpression) != nil { return true }
        let all = words(lowered)
        // "My email is …" names an address, it orders nothing (the third VM run, B12): the noun "email" or "mail"
        // beside an address is no verb that sends; one that opens a clause still is ("Email it to …").
        if hasAddress(lowered), all.contains(where: { (strongEnglish.contains(stem($0)) && !nounMail.contains($0)) || ["sent", "mailed", "text", "message"].contains($0) }) { return true }
        if lowered.range(of: askedKorean, options: .regularExpression) != nil { return true }
        return clauses(lowered).contains { clause in
            let words = words(clause)
            // An English order opens with its verb ("Send…", "Always send…", "Never delete…", "Please forward…"). A
            // plain verb alone opens many ordinary lines ("Open to relocating", "Call me the user"): it is an order only
            // after "always", "never" or "please", or when it is one of the verbs that send, destroy, pay or run.
            let opening = words.drop { fillers.contains($0) }
            // "Email: a@b.com", "Email address …", "Email is …": a label, not the verb.
            if let verb = opening.first, nounMail.contains(verb), opening.count == words.count,
               opening.dropFirst().first.map({ ["is", "address", "addresses", "was", "are", "id"].contains($0) }) ?? true { return addresses(words, acting: true) || clause.range(of: actingKorean, options: .regularExpression) != nil }
            if let verb = opening.first, actingEnglish.contains(verb), opening.count < words.count || strongEnglish.contains(verb) { return true }
            return addresses(words, acting: true) || clause.range(of: actingKorean, options: .regularExpression) != nil
        }
    }

    /// "email" and "mail" as the words for an address.
    private static let nounMail: Set<String> = ["email", "e-mail", "mail"]

    /// Whether a line carries a link or an email address (the reason it waits for the user's own tick).
    static func carriesAddress(_ text: String) -> Bool { hasAddress(folded(text)) }

    /// A link or an email address anywhere in a folded line.
    private static func hasAddress(_ lowered: String) -> Bool {
        lowered.range(of: #"(?:https?://|www\.)\S+|[a-z0-9._%+\-]+@[a-z0-9\-]+"#, options: .regularExpression) != nil
    }

    /// Whether the user should look at a line before it goes in, under whatever heading it came: a link or an email
    /// address, Aris or "you" as a subject, or the shape of an instruction ("always…", "never…", 항상…). Not an order
    /// (`acts`), only never ticked for him.
    static func needsLook(_ text: String) -> Bool {
        let lowered = folded(text)
        if hasAddress(lowered) || koreanSubjects.contains(where: lowered.contains) { return true }
        return clauses(lowered).contains { clause in
            let words = words(clause)
            let first = words.first == "please" ? words.dropFirst().first : words.first
            if ["always", "never", "don't", "dont"].contains(first ?? "") || clause.hasPrefix("do not ") { return true }
            return koreanOpeners.contains(where: clause.hasPrefix) || addresses(words, acting: false)
        }
    }

    /// Each line with what Aris makes of it against what it already remembers (the store's own merge rule), in order:
    /// a secret, an order, already known, a newer or an older wording of something known, or new.
    static func judged(_ lines: [ArisImportLine], existing: [ArisMemoryRecord], now: Date) -> [ArisImportLine] {
        lines.map { line in
            var one = line
            one.look = needsLook(line.text)
            if ArisMemoryText.isSecret(line.text) {
                one.state = .secret
            } else if acts(line.text) {
                one.state = .acts
            } else {
                let judged = state(of: line, existing: existing, now: now)
                one.state = judged.state
                one.replaces = judged.old?.line
                // One he said himself or confirmed is replaced only by his own tick (review 8, M3).
                one.keepsHis = judged.old.map { $0.source == .said || $0.confidence >= ArisMemoryStore.confirmedConfidence } ?? false
            }
            return one
        }
    }

    /// The state, and for an update the memory it would replace.
    private static func state(of line: ArisImportLine, existing: [ArisMemoryRecord], now: Date) -> (state: ArisImportState, old: ArisMemoryRecord?) {
        let candidate = ArisMemoryCandidate(kind: line.kind, subject: "", text: title(line.text), confidence: ArisMemoryStore.toolConfidence)
        switch ArisMemoryMerge.plan(candidate, existing: existing) {
        case .insert: return (.new, nil)
        case .duplicate: return (.known, nil)
        case .update(let id):
            // The newer date wins, never the order things were imported in. A line with no date never replaces anything,
            // and a date later than tomorrow is no date.
            guard let old = existing.first(where: { $0.id == id }), let date = line.date, date <= latest(now) else { return (.older, nil) }
            return date > old.turnAt ? (.updates, old) : (.older, nil)
        }
    }

    /// The memory's own text for a line: the line itself when it fits a memory, else its opening up to a sentence's
    /// end or a clause's (a long project line keeps its whole text beside this: ArisMemoryStore.importDetail).
    static func title(_ text: String) -> String {
        let cleaned = clean(text)
        guard cleaned.count > ArisMemoryText.maxLength else { return cleaned }
        let head = String(cleaned.prefix(ArisMemoryText.maxLength))
        for mark in [". ", "。", "! ", "? ", "; ", ": ", " — ", " - ", ", "] {
            if let cut = head.range(of: mark, options: .backwards), head.distance(from: head.startIndex, to: cut.lowerBound) >= 40 {
                return String(head[..<cut.lowerBound])
            }
        }
        return String(head.prefix(ArisMemoryText.maxLength - 1)) + "…"
    }
}
