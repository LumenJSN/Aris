//
//  ArisTeamTemplates.swift
//  Aris
//
//  Zero setup for teammates: the 팀원 추가 templates (문서 담당, 리서처, 코딩 담당, 일정 비서, 빈 팀원), what kind of
//  work a request is (the same words pick a template), "문서 정리하는 팀원 하나 만들어줘, 이름은 코디" read into a teammate
//  (ArisTeamMaking), and when Aris offers to make one after the same kind of job came up again and again
//  (ArisTeamSuggestion). Pure: no AI, no files; the tests run it.
//

import Foundation

/// A kind of work a template is for.
enum ArisWorkKind: String, CaseIterable, Codable, Sendable {
    case docs, research, code, schedule, math

    /// Words that say a request is this kind (Korean stems, English whole words).
    var words: [String] {
        switch self {
        case .docs: ["문서", "메일", "이메일", "보고서", "발표", "초안", "슬라이드", "편지", "글쓰기", "다듬", "교정", "문장",
                     "document", "documents", "doc", "docs", "email", "emails", "draft", "drafts", "drafting", "report", "slides", "letter", "proofread", "write"]
        case .research: ["자료", "조사", "리서치", "검색", "비교", "알아봐", "찾아봐", "뉴스", "논문", "출처",
                         "research", "compare", "comparing", "look up", "looking up", "sources", "news", "papers"]
        case .code: ["코드", "코딩", "버그", "테스트", "개발", "프로그램", "빌드", "스크립트", "디버그", "리팩",
                     "code", "coding", "bug", "bugs", "test", "tests", "build", "script", "debug", "refactor"]
        case .schedule: ["일정", "약속", "캘린더", "달력", "미리 알림", "할 일", "회의", "스케줄", "예약",
                         "calendar", "schedule", "meeting", "meetings", "events", "remind", "reminder", "reminders", "to-do", "to-dos", "todo", "appointment"]
        case .math: ["계산", "숫자", "수학", "산수", "곱하기", "더하기", "나누기", "환율", "단위 변환", "통계",
                     "math", "maths", "calculate", "calculation", "calculations", "numbers", "arithmetic", "sums"]
        }
    }

    /// The kind `text` is most about; nil when no kind's words come up, or two kinds come up as often.
    static func of(_ text: String) -> ArisWorkKind? {
        let lowered = text.lowercased()
        let scores = allCases.map { kind in (kind, kind.words.filter { mentions($0, in: lowered) }.count) }.filter { $0.1 > 0 }
        guard let best = scores.max(by: { $0.1 < $1.1 }) else { return nil }
        return scores.filter { $0.1 == best.1 }.count == 1 ? best.0 : nil
    }

    private static func mentions(_ word: String, in text: String) -> Bool {
        guard word.unicodeScalars.first?.isASCII == true else { return text.contains(word) }
        return text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil
    }
}

struct ArisTeamTemplate: Identifiable, Equatable {
    let id: String
    let kind: ArisWorkKind?
    let label: String
    let name: String
    let type: String
    let routing: String
    let instructions: String
    let scopes: [String]

    static var docs: ArisTeamTemplate {
        .init(id: "docs", kind: .docs, label: ArisTeamCopy.tplDocs, name: ArisTeamCopy.tplDocsName, type: "cat",
              routing: ArisTeamCopy.tplDocsRouting, instructions: ArisTeamCopy.tplDocsHow, scopes: ["files"])
    }
    static var research: ArisTeamTemplate {
        .init(id: "research", kind: .research, label: ArisTeamCopy.tplResearch, name: ArisTeamCopy.tplResearchName, type: "clover",
              routing: ArisTeamCopy.tplResearchRouting, instructions: ArisTeamCopy.tplResearchHow, scopes: ["web"])
    }
    static var code: ArisTeamTemplate {
        .init(id: "code", kind: .code, label: ArisTeamCopy.tplCode, name: ArisTeamCopy.tplCodeName, type: "blob",
              routing: ArisTeamCopy.tplCodeRouting, instructions: ArisTeamCopy.tplCodeHow, scopes: ["files", "terminal"])
    }
    static var schedule: ArisTeamTemplate {
        .init(id: "schedule", kind: .schedule, label: ArisTeamCopy.tplSchedule, name: ArisTeamCopy.tplScheduleName, type: "cloud",
              routing: ArisTeamCopy.tplScheduleRouting, instructions: ArisTeamCopy.tplScheduleHow, scopes: ["calendar"])
    }
    /// Only for a teammate made in words (BUG-25a): a calculation role's closest fit, never in the 팀원 추가 menu.
    static var calc: ArisTeamTemplate {
        .init(id: "calc", kind: .math, label: ArisTeamCopy.tplCalc, name: ArisTeamCopy.tplCalcName, type: "pebble",
              routing: ArisTeamCopy.tplCalcRouting, instructions: ArisTeamCopy.tplCalcHow, scopes: [])
    }
    static var blank: ArisTeamTemplate {
        .init(id: "blank", kind: nil, label: ArisTeamCopy.tplBlank, name: ArisTeamCopy.tplBlankName, type: "pebble",
              routing: "", instructions: "", scopes: [])
    }

    /// The 팀원 추가 menu's order.
    static var all: [ArisTeamTemplate] { [docs, research, code, schedule, blank] }

    /// The templates a spoken role may match: the menu's and the ones made only in words.
    static var matchable: [ArisTeamTemplate] { all + [calc] }

    static func of(_ kind: ArisWorkKind) -> ArisTeamTemplate {
        matchable.first { $0.kind == kind } ?? blank
    }

    /// The menu's second line.
    var line: String { routing.isEmpty ? ArisTeamCopy.tplBlankLine : routing }
}

/// "문서 정리하는 팀원 하나 만들어줘, 이름은 코디" / "make a teammate that drafts emails, named Cody": a request to make a
/// teammate, read without any AI. Only its name comes from the words (checked like a typed one); its routing line,
/// instructions and scopes are the template's their words fit (security review M5: no spoken text ever becomes a line
/// main Aris routes by), plus the scopes the role's words obviously need (`scopes(forRole:)`: files, the web, the
/// calendar, reading mail; never more), its brain is the main one (ArisTeamEditing.adding).
enum ArisTeamMaking {
    struct Request: Equatable {
        /// The role as said ("문서 정리"), nil when only a name was given.
        let role: String?
        let name: String?
        let template: ArisTeamTemplate
    }

    private static let koreanMake = #"팀원\s*(?:을|를)?\s*(?:하나|한\s*명|한명|1명)?\s*(?:더\s*)?(?:만들|추가|뽑|두어|둬|만들어)"#
    /// What follows the verb when it is asked for (N15): 만들어줘 / 만들어 주세요 / 만들어 줄래, 추가해 / 추가해 줘, 뽑아줘, 둬,
    /// 만들자; never 만드는 방법, 만들지 마, 만들 수 있어?, 만들어?.
    private static let koreanAsk = #"^(?:(?:어|아|해|하여)?\s*(?:줘요|줘|주세요|주십시오|줄래요|줄래|주라|줄\s*수\s*있(?:어요|나요|어)?)\s*(?:[,.!~?]|$|\s)|(?:해요|하자|어|아|해|자|봐|줘)\s*(?:[,.!~]|$|\s))"#
    /// A question or a no anywhere in it.
    private static let koreanNot = #"방법|어떻게|어떡|알려|지\s*마|지\s*말|말아|않|못\s|안\s*(?:만들|추가|해)"#
    /// Asked for in English (N15): the verb leads, maybe after "please", "can you" or "let's"; never "how do I…", "don't…".
    private static let englishMake = #"(?i)^\s*(?:(?:hey\s+)?aris[,!.]?\s+)?(?:please\s+)?(?:(?:can|could|would|will)\s+you\s+(?:please\s+)?|let's\s+|let\s+us\s+)?(?:make|create|add|set\s+up)\s+(?:me\s+)?(?:a|an|one|another|new)?\s*(?:new\s+)?(?:[a-z]+\s+){0,3}?teammate\b"#

    static func parse(_ text: String) -> Request? {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard said.count <= 200 else { return nil }
        if let found = said.range(of: koreanMake, options: .regularExpression) {
            let after = String(said[found.upperBound...])
            guard after.range(of: koreanAsk, options: .regularExpression) != nil, said.range(of: koreanNot, options: .regularExpression) == nil else { return nil }
            return korean(said, before: String(said[..<found.lowerBound]))
        }
        if said.range(of: englishMake, options: .regularExpression) != nil { return english(said) }
        return nil
    }

    private static func korean(_ said: String, before: String) -> Request {
        let name = capture(#"이름(?:은|는|을|를)?\s*["'“‘]?([^\s,.!?"'”’]{1,12}?)["'”’]?\s*(?:으로|로|라고|이라고|이야|야|이에요|예요|요|$|[\s,.!?])"#, in: said)
            // A quoted name whole, else the word before 라는 with a Latin word before it ("QA 도우미", QA retest: "도우미" lost
            // its "QA").
            ?? capture(#"["“‘']([^"”’']{1,24})["”’']\s*(?:이)?라는\s*(?:이름의\s*)?팀원"#, in: said)
            ?? capture(#"((?:[A-Za-z0-9][A-Za-z0-9.&+-]{0,11}\s+)?[^\s,.!?"'”’]{1,12})(?:이)?라는\s*(?:이름의\s*)?팀원"#, in: said)
        var role = before.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let name { role = role.replacingOccurrences(of: name + "라는", with: "").replacingOccurrences(of: name + "이라는", with: "") }
        role = role.replacingOccurrences(of: #"^(?:아리스\s*,?\s*|우리\s+|나한테\s+|내\s+)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*(?:이름의)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let phrase = strip(role, suffixes: ["하는", "해 주는", "해주는", "할"]) ?? strip(role, suffixes: ["담당하는", "담당", "맡는", "전담"])
            ?? (!role.isEmpty && role.count <= 40 ? role : nil)
        return request(role: phrase, name: name)
    }

    private static func english(_ said: String) -> Request {
        let name = capture(#"(?i)\b(?:named|called)\s+["'“]?([A-Za-z0-9가-힣][\w가-힣-]{0,11})"#, in: said)
        let role = capture(#"(?i)\bteammate\s+(?:that|who|to|for)\s+(.+?)(?:,|\.|\s+named\b|\s+called\b|$)"#, in: said)
            ?? capture(#"(?i)\b(?:a|an|one|new)\s+([a-z][a-z ]{1,30}?)\s+teammate\b"#, in: said)
        return request(role: role, name: name)
    }

    /// The role only picks the template; a name that a typed one couldn't be (tags, invisible letters, too wide, Aris's)
    /// is dropped.
    private static func request(role: String?, name: String?) -> Request {
        let template = (role ?? "").isEmpty ? ArisTeamTemplate.blank : ArisWorkKind.of(role ?? "").map(ArisTeamTemplate.of) ?? .blank
        let cleanName = name.flatMap { said in ArisTeamEditing.nameProblem(said, id: "", in: []) == nil ? ArisTeammateName.validate(said) : nil }
        return Request(role: role, name: cleanName, template: template)
    }

    /// What a spoken role obviously needs (audit team-8: "번역하는 팀원" started with nothing and could only refuse):
    /// files, the web, the calendar, reading mail, each from words that name it. Only these four: sending, using apps,
    /// websites through Aside and the terminal act on other people or the whole Mac, so they stay the user's to switch on.
    /// The made card shows the result as chips before anything is saved, and every risky step still asks on its card.
    private static let roleScopes: [(ArisTeammateScope, [String])] = [
        (.files, ["파일", "문서", "폴더", "번역", "보고서", "초안", "노트", "메모", "사진", "이미지", "다운로드", "엑셀", "스프레드시트", "슬라이드", "발표",
                  "file", "files", "document", "documents", "doc", "docs", "folder", "folders", "translate", "translates", "translating", "translation",
                  "translations", "report", "reports", "draft", "drafts", "notes", "pdf", "pdfs", "photos", "images", "spreadsheet", "spreadsheets", "slides"]),
        (.web, ["웹", "인터넷", "검색", "조사", "리서치", "뉴스", "사이트", "가격", "날씨", "주식", "환율", "논문", "출처", "알아봐", "찾아봐",
                "web", "internet", "search", "searches", "research", "news", "website", "websites", "price", "prices", "weather", "stock", "stocks", "look up", "looks up"]),
        (.calendar, ["일정", "캘린더", "달력", "미리 알림", "리마인드", "할 일", "회의", "약속", "스케줄", "예약",
                     "calendar", "schedule", "schedules", "reminder", "reminders", "meeting", "meetings", "to-do", "to-dos", "todo", "todos", "appointment", "appointments"]),
        (.mail, ["메일", "메시지", "문자", "카톡", "카카오톡", "받은 편지함", "mail", "email", "emails", "message", "messages", "inbox", "imessage"]),
    ]

    static func scopes(forRole role: String?) -> Set<ArisTeammateScope> {
        guard let role = role?.lowercased(), !role.isEmpty else { return [] }
        return Set(roleScopes.filter { $0.1.contains { mentions($0, in: role) } }.map(\.0))
    }

    /// Korean stems anywhere, English as whole words (as ArisWorkKind reads a request).
    private static func mentions(_ word: String, in text: String) -> Bool {
        guard word.unicodeScalars.first?.isASCII == true else { return text.contains(word) }
        return text.range(of: "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b", options: .regularExpression) != nil
    }

    /// The teammate this request makes on top of `teammates`, with `brain` (the main brain); nil when the list is full.
    static func make(_ request: Request, in teammates: [ArisTeammate], aris: ArisCharacterLook, brain: String,
                     suffix: () -> String = ArisTeamEditing.randomSuffix) -> ArisTeammate? {
        guard teammates.count < ArisTeamEditing.maxTeammates else { return nil }
        var template = request.template
        // A role that fits no template still gets a way to work (BUG-25a).
        if template.id == "blank", request.role != nil {
            template = ArisTeamTemplate(id: "blank", kind: nil, label: template.label, name: template.name, type: template.type, routing: "",
                                        instructions: ArisTeamCopy.genericHow, scopes: [])
        }
        // On top of the template's own: what the role's words obviously need (nothing when they name none of it).
        let wanted = Set(template.scopes).union(scopes(forRole: request.role).map(\.rawValue))
        if wanted != Set(template.scopes) {
            template = ArisTeamTemplate(id: template.id, kind: template.kind, label: template.label, name: template.name, type: template.type,
                                        routing: template.routing, instructions: template.instructions,
                                        scopes: ArisTeammateScope.canonical(Array(wanted)))
        }
        let added = ArisTeamEditing.adding(to: teammates, aris: aris, template: template, brain: brain, name: request.name, suffix: suffix)
        guard added.count > teammates.count, var made = added.last else { return nil }
        // Never an empty routing line: one built only from its checked name ("이름(큐에이봇)을 부를 때").
        if made.routing.isEmpty { made.routing = ArisTeamCopy.routingByName(made.name) }
        return made
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        let found = text[range].trimmingCharacters(in: .whitespaces)
        return found.isEmpty ? nil : found
    }

    private static func strip(_ text: String, suffixes: [String]) -> String? {
        for suffix in suffixes where text.hasSuffix(suffix) {
            let stem = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if !stem.isEmpty { return stem }
        }
        return nil
    }
}

/// A teammate asked for in words, shown on the notch's card before anything is saved (security review M5): what was
/// heard, the unsaved preview, and what makes it again if the list changed before 확인.
struct ArisTeamMade: Equatable {
    let heard: String
    let preview: ArisTeammate
    let request: ArisTeamMaking.Request
    let brain: String
}

/// When Aris offers a teammate (the owner: ask once, never nag): the same kind of job (ArisWorkKind of the user's words) done
/// `threshold` times within `window`, while no teammate is for that kind, and that kind was never offered before. A
/// yes or a no both end it for that kind: it is never asked again.
struct ArisTeamSuggestion: Codable, Equatable {
    static let threshold = 3
    static let window: TimeInterval = 14 * 86_400
    /// Kept per kind.
    static let kept = 10

    var seen: [String: [Date]] = [:]
    var asked: Set<String> = []

    /// A job of `words` finished at `now`: the record with it counted, and the kind to offer now (if any).
    func recording(_ words: String, at now: Date, teammates: [ArisTeammate]) -> (ArisTeamSuggestion, ArisWorkKind?) {
        guard let kind = ArisWorkKind.of(words) else { return (self, nil) }
        var next = self
        let recent = ((seen[kind.rawValue] ?? []) + [now]).filter { now.timeIntervalSince($0) <= Self.window }.suffix(Self.kept)
        next.seen[kind.rawValue] = Array(recent)
        guard recent.count >= Self.threshold, !asked.contains(kind.rawValue), !Self.covered(kind, by: teammates) else { return (next, nil) }
        return (next, kind)
    }

    /// Asked (whatever the answer): never again for that kind.
    func asking(_ kind: ArisWorkKind) -> ArisTeamSuggestion {
        var next = self
        next.asked.insert(kind.rawValue)
        return next
    }

    /// A teammate (not Claude Code) whose 언제 부를까요 is about this kind already.
    static func covered(_ kind: ArisWorkKind, by teammates: [ArisTeammate]) -> Bool {
        teammates.contains { $0.id != ArisTeammate.claudeCodeId && ArisWorkKind.of($0.routing + " " + $0.instructions) == kind }
            || (kind == .code && teammates.contains { $0.id == ArisTeammate.claudeCodeId })
    }
}
