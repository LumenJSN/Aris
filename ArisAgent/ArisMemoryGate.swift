//
//  ArisMemoryGate.swift
//  aris-agent, aris-tools
//
//  The write gate in front of memory: text that reads like an order to an AI is never stored without the user seeing it.
//  It runs over what Aris writes on another's words (a brain's `aris-tools remember`, an imported line, a work-memory
//  lesson), never over the user's own 기억해 (their words, their memory); a memory learned from their own words on a clean turn
//  is let off the override and standing families only (ArisMemoryStore.waived): leak and credential apply to it. Four
//  families of patterns, Korean and English, kept as data:
//  - override: "ignore your previous instructions", a new system prompt, a role swap, keeping something from the user;
//  - standing: a rule addressed to an AI for later ("from now on say…", "AI는 항상 …", "물어보면 …라고 해");
//  - leak: a standing rule to send data to an address, private data to an address, a link with a slot to fill, a
//    request to show the hidden prompt;
//  - credential: a request to hand over a password, key or token.
//  The first three send the item to Settings › 기억 › 확인할 것 (held, not stored, until the user keeps or drops it); a
//  credential request is refused outright. No model reads anything here.
//  Text is read as the patterns expect it: NFKC, letters that draw nothing removed, Cyrillic and Greek look-alikes
//  as Latin, lowercased, spaces collapsed; each pattern runs within one sentence, and every quantifier is bounded.
//  The pattern families are ported from an MIT-licensed project (THIRD_PARTY_LICENSES).
//  Foundation only (tested).
//

import Foundation

enum ArisMemoryGateFamily: String, CaseIterable, Sendable {
    case override, standing, leak, credential
}

/// One pattern: every regex in `all` must match inside the same sentence (in any order).
struct ArisMemoryGatePattern: Sendable {
    let name: String
    let family: ArisMemoryGateFamily
    let all: [String]
    /// A match right after a negation ("never send your password") or before a Korean "don't" (보내지 마) doesn't count.
    var negatable = false
}

enum ArisMemoryGate {
    struct Hit: Equatable, Sendable {
        let name: String
        let family: ArisMemoryGateFamily
    }

    enum Verdict: Equatable, Sendable {
        case allow
        /// Held for the user's look in Settings (not stored until they keeps it).
        case review(Hit)
        /// Never stored: asks for a credential.
        case refuse(Hit)
    }

    /// The longest text read (a memory is one line; a lesson a few).
    static let mostText = 2_000

    // MARK: - The pieces the patterns share

    private static let future = "(?:from now on|going forward|henceforth|from this point (?:on|forward)|in (?:all )?future (?:answers|responses|replies|conversations|sessions|chats))"
    /// Who a rule is addressed to (generic names only).
    private static let agent = "(?:ai assistant|assistant|chatbot|ai agent|agent|llm|aris|bot|ai)"
    private static let agentVocative = "(?:ai assistant|assistant|chatbot|ai agent|agent|llm|aris|bot|ai|(?:language )?model)"
    private static let speech = "(?:say|tell|respond|reply|answer|recommend|mention|claim|state|describe|refer|suggest|output|report|deny|confirm|praise|promote|call|treat|use|ignore|include)"
    private static let action = "(?:forward|send|email|e-mail|cc|bcc|share|reveal|upload|post|transfer|wire|pay|delete|remove|run|execute|invoke|book|buy|approve|grant|disclose)"
    private static let strictSpeech = "(?:say|tell|respond|reply|answer|recommend|mention|claim|state|deny|reveal|disclose|describe|suggest|output)"
    private static let exfilVerb = "(?:forward|send|email|e-mail|cc|bcc|copy|post|upload|transfer|wire|share|leak|exfiltrate|sync|mirror|report|submit|route|reroute|redirect|export|remit|deliver|forwarded|sent|emailed|e-mailed|mailed|copied|posted|uploaded|transferred|wired|shared|leaked|synced|mirrored|reported|submitted|routed|redirected|exported|delivered)"
    private static let standing = "(?:always|from now on|going forward|moving forward|henceforth|whenever|every time|automatically|silently|secretly|quietly|without (?:telling|notifying|asking)|all future|any future|every future|in (?:the )?future|effective immediately|until further notice|from this point(?: on| forward)?|new (?:policy|rule|procedure|process))"
    /// An address, a link, or an address whose domain was cut ("audit@example": a piece of a longer line still names
    /// where things go).
    private static let address = #"(?:[a-z0-9._%+-]{1,64}@[a-z0-9-]{1,30}(?:\.[a-z0-9-]{1,30}){0,4}|(?:https?://|www\.)[^\s<>"']{1,120})"#
    private static let toAddress = #"\b(?:to|with) (?:[a-z-]{1,20} ){0,4}(?:at |on |via )?"# + address
    private static let credential = #"(?:api ?keys?|passwords?|passphrases?|credentials?|secret keys?|access tokens?|auth(?:entication)? tokens?|bearer tokens?|refresh tokens?|private keys?|ssh keys?|seed phrases?|recovery (?:codes?|phrases?)|2fa codes?|one-time (?:codes?|passwords?)|session (?:cookies?|tokens?)|\.env files?)"#
    private static let privateData = #"\b(?:memor(?:y|ies)|conversation history|chat history|system prompt|private notes|user data|"# + credential + #")\b"#
    private static let modal = "(?:always|never|must|should|do not|don't|from now on|going forward|henceforth)"
    // Korean
    private static let koAgent = "(?<![a-z])(?:아리스|aris|ai|에이아이|어시스턴트|비서|챗봇|에이전트|봇|모델)"
    private static let koStanding = "(?:항상|언제나|앞으로|이제부터|지금부터|다음부터|매번|자동으로|몰래|조용히|무조건|반드시|절대)"
    private static let koSpeak = "(?:말해|말하|대답|답해|답하|소개해|불러|부르|설명해|추천해|전해)"
    private static let koAct = "(?:보내|전달|공유|업로드|올려|복사|포워드|넘겨|전송|삭제|지워|실행|설치|결제|송금|승인|숨겨)"
    private static let koSend = "(?:보내|전달|공유|업로드|올려|옮겨|복사|포워드|넘겨|전송|회신|참조)"
    private static let koData = "(?:기억|메모리|대화 ?(?:기록|내용)|시스템 ?프롬프트|비밀번호|비번|api ?키|토큰|개인 ?정보|연락처|메일함)"
    private static let koCredential = "(?:비밀번호|비번|패스워드|암호|api ?키|액세스 ?키|시크릿 ?키|개인 ?키|토큰|인증 ?(?:번호|코드)|otp|시드 ?(?:문구|구문)|복구 ?(?:코드|문구)|보안 ?코드|카드 ?번호)"

    // MARK: - The patterns

    static let patterns: [ArisMemoryGatePattern] = [
        // override
        .init(name: "ignore-instructions", family: .override, all: [
            #"\b(?:ignore|disregard|forget|bypass)\b (?:all |any )?(?:of )?(?:your |the |these |those )?(?:previous|prior|above|earlier|preceding|original|initial|system|safety)\b.{0,21}?\b(?:instructions?|prompts?|rules|guidelines|guardrails|directives|policies|context|messages?)\b"#]),
        .init(name: "ignore-your-rules", family: .override, all: [
            #"\b(?:ignore|disregard|bypass)\b (?:all )?your (?:instructions?|rules|guidelines|programming|system prompt|guardrails)\b"#]),
        .init(name: "forget-everything", family: .override, all: [#"\bforget (?:everything|all (?:of )?the above)\b"#]),
        .init(name: "new-instructions", family: .override, all: [#"\b(?:new|updated|revised) instructions? ?:"#]),
        .init(name: "system-prompt", family: .override, all: [#"\bsystem ?: ?(?:you are|you must|never|always)\b|\bnew system prompt\b"#]),
        .init(name: "role-swap", family: .override, all: [#"\byou are (?:now|actually|really) (?:a|an) [a-z]{1,24}"#]),
        .init(name: "act-now", family: .override, all: [#"\byou (?:must|should) now (?:act|behave|respond)\b"#]),
        .init(name: "unlocked-mode", family: .override, all: [#"\b(?:do anything now|developer mode enabled?|dan mode|jailbreak(?:ed|ing)?)\b"#]),
        .init(name: "conceal-from-user", family: .override, all: [
            #"\b(?:do not|don't|never)\b (?:tell|inform|notify|alert|warn|mention (?:this |it )?to|reveal (?:this |it )?to) (?:the )?(?:user|owner|human|operator)\b"#]),
        .init(name: "conceal-standing", family: .override, all: [
            "\\b\(standing)\\b.{0,160}?\\b(?:never|do not|don't) (?:mention|tell|reveal|disclose|inform|notify|alert|flag) (?:(?:it|this|that|them) (?:to )?)?(?:the user|the owner|the human|me|it|this|that|them)\\b"]),
        .init(name: "ko-ignore-instructions", family: .override, all: [
            "(?:이전|앞의|앞에서|위의|위에|기존|원래|모든|지금까지)(?:의)? ?(?:지시|명령|지침|규칙|프롬프트|설정|안내)(?:사항|들)?(?:은|는|을|를|도)? ?.{0,10}?(?:무시|잊어|잊고|잊으|따르지 ?마|따르지 ?말)"]),
        .init(name: "ko-system-prompt", family: .override, all: ["시스템 ?프롬프트.{0,15}?(?:무시|바꿔|바꾸|잊어|새로)|새 ?시스템 ?프롬프트"]),
        .init(name: "ko-role-swap", family: .override, all: ["(?:너는|넌|당신은|아리스는|aris는) ?(?:이제|이제부터|지금부터) ?.{0,24}?(?:이다|야|이야|입니다|이에요|예요|역할)"]),
        .init(name: "ko-unlocked-mode", family: .override, all: ["개발자 ?모드|탈옥|안전 ?(?:장치|규칙) ?(?:을|를)? ?(?:해제|무시|꺼)"]),
        .init(name: "ko-conceal", family: .override, all: ["(?:사용자|주인|유저|오너)(?:에게|한테|께)? ?.{0,16}?(?:말하지|알리지|알려 ?주지|보여 ?주지|티 ?내지) ?(?:마|말|않)"]),
        // standing
        .init(name: "from-now-on", family: .standing, all: [
            "\\b\(future)\\b.{0,100}?\\b(?:\(speech)|\(action)|(?:is|are|must|should|shall|will) (?:to )?be (?:called|referred to|described|treated|considered|known|listed|presented|named|introduced))\\b"]),
        .init(name: "from-now-on-trail", family: .standing, all: ["\\b(?:\(speech)|\(action))\\b.{0,100}?\\b\(future)\\b"]),
        .init(name: "agent-rule", family: .standing, all: [
            "\\b\(agent)\\b.{0,40}?\\b\(modal)\\b.{0,40}?\\b(?:\(speech)|\(action))\\b|\\b\(agent)\\b (?:is|are|will be|shall be) (?:instructed |required |expected |supposed )?to (?:always |never |only )?(?:\(speech)|\(action))\\b"]),
        .init(name: "agent-note", family: .standing, all: [
            "\\b(?:(?:note|message|reminder|instructions?|attention|attn|memo) (?:to|for) (?:the |any |all |my |our |your )?|(?:dear|hey|hello) (?:the )?)\(agentVocative)\\b(?: ?[:,] ?(?:please )?(?:always |never |only )?(?:\(speech)|\(action))\\b|.{0,200}?\\b\(modal)\\b.{0,40}?\\b(?:\(speech)|\(action))\\b)"]),
        .init(name: "agent-any-reader", family: .standing, all: [
            "\\b(?:to|for) (?:any|all|every) (?:ai |llm )?\(agentVocative)s? (?:reading|seeing|processing|handling|that reads|who reads)\\b"]),
        .init(name: "you-always-say", family: .standing, all: ["\\byou\\b.{0,30}?\\b(?:always|never)\\b.{0,40}?\\b\(strictSpeech)\\b"]),
        .init(name: "always-say", family: .standing, all: ["(?:^|[:;] |- )(?:please )?(?:always|never) \(strictSpeech)\\b"]),
        .init(name: "when-asked-say", family: .standing, all: [
            #"\b(?:when|whenever|if)\b.{0,60}?\b(?:asks?|asked|asking|inquires?|wants to know|comes? up|is brought up)\b.{0,80}?\b(?:say|tell|respond|reply|answer|claim|state|insist|deny|recommend)\b"#]),
        .init(name: "act-without-asking", family: .standing, all: [
            "\\b\(standing)\\b.{0,160}?\\bwithout (?:asking|checking(?: with)?|confirming(?: with)?|consulting|telling|notifying|alerting|informing) (?:the user|the owner|the human|me|anyone|anybody|first)\\b"]),
        .init(name: "ko-agent-rule", family: .standing, all: ["\(koAgent)(?:야|아|는|가|에게|한테|님)?.{0,40}?\(koStanding).{0,40}?(?:\(koSpeak)|\(koAct))"]),
        .init(name: "ko-when-asked", family: .standing, all: [
            "(?:물어보면|물으면|묻거든|묻는다면|질문하면|물어볼 ?때|물어 ?오면|문의하면).{0,60}?(?:라고|이라고|다고) ?(?:말해|말하|대답|답해|답하|해라|하세요|해 ?줘|전해)"]),
        .init(name: "ko-from-now-on", family: .standing, all: [
            "(?:앞으로(?:는)?|이제부터(?:는)?|지금부터(?:는)?|다음부터(?:는)?) ?.{0,60}?(?:(?:라고|이라고) ?\(koSpeak)|\(koAct))"]),
        .init(name: "ko-without-asking", family: .standing, all: [
            "(?:묻지|물어보지|확인하지|허락 ?받지|알리지|말하지) ?(?:말고|않고|않은 ?채)", "(?:\(koStanding)|알아서|바로)"]),
        // leak
        .init(name: "exfil-standing", family: .leak, all: ["\\b\(standing)\\b", "\\b\(exfilVerb)\\b", toAddress]),
        .init(name: "exfil-agent", family: .leak, all: ["\\b\(agent)\\b", "\\b\(exfilVerb)\\b", toAddress]),
        .init(name: "exfil-private-data", family: .leak, all: [privateData, "\\b\(exfilVerb)\\b", address]),
        .init(name: "exfil-copy-in", family: .leak, all: ["\\b\(standing)\\b", "\\b(?:cc|bcc|copy|loop in|e-?mail) (?:in )?\(address)"]),
        .init(name: "exfil-templated-link", family: .leak, all: [#"https?://[^\s)"'<>]{1,200}[?&][a-z0-9_]{1,30}= ?(?:\{|<|\[|%7b|\$\{)"#]),
        .init(name: "show-hidden-prompt", family: .leak, all: [
            #"\b(?:print|output|reveal|show|repeat)\b (?:me )?(?:your )?(?:system prompt|hidden (?:instructions|prompt|rules)|instructions verbatim)\b"#]),
        .init(name: "ko-exfil-standing", family: .leak, all: [koSend, address, koStanding]),
        .init(name: "ko-exfil-private-data", family: .leak, all: [koSend, address, koData]),
        .init(name: "ko-show-hidden-prompt", family: .leak, all: ["(?:시스템 ?프롬프트|숨겨진 ?(?:지시|규칙|프롬프트)).{0,15}?(?:보여|알려|출력|공개|말해|적어)"]),
        // credential
        .init(name: "credential-request", family: .credential, all: [
            "\\b(?:send|email|e-mail|share|reveal|paste|give|forward|upload|disclose|leak|dump|exfiltrate|tell)\\b (?:me |us |them )?(?:all |any |a copy of )?(?:of )?(?:your|the|their|our|my|these|those|all|any) (?:[a-z0-9-]{1,20} )?\(credential)\\b"],
              negatable: true),
        .init(name: "ko-credential-request", family: .credential, all: [
            "\(koCredential)(?:를|을|도|는|은|좀|들|이랑)? ?.{0,12}?(?:보내|알려|공유|붙여 ?넣|전달|넘겨|입력해 ?줘|적어 ?줘|불러 ?줘)"], negatable: true),
    ]

    private static let compiled: [(pattern: ArisMemoryGatePattern, regexes: [NSRegularExpression])] = patterns.map { pattern in
        (pattern, pattern.all.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) })
    }

    /// Whether every pattern compiles (tested: a pattern that doesn't would silently never match).
    static var allCompile: Bool { compiled.allSatisfy { $0.regexes.count == $0.pattern.all.count } }

    // MARK: - Reading

    /// Letters that draw nothing: zero-width, joiners, direction marks, the soft hyphen, the BOM.
    private static func drawsNothing(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00AD, 0x180E, 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x2064, 0x2066...0x2069, 0xFEFF, 0x115F, 0x1160, 0x3164, 0xFFA0: true
        default: false
        }
    }

    /// Cyrillic and Greek letters that look like Latin ones.
    private static let lookAlikes: [Character: Character] = [
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "ѕ": "s", "і": "i", "ј": "j", "ԁ": "d", "ɡ": "g", "һ": "h", "ӏ": "l",
        "ο": "o", "α": "a", "ε": "e", "ι": "i", "κ": "k", "ν": "v", "ρ": "p", "τ": "t", "υ": "u", "χ": "x",
    ]

    /// As the patterns read it: NFKC, nothing invisible, look-alikes folded, lowercased, one space between words,
    /// line breaks kept (they end a sentence).
    static func normalized(_ text: String) -> String {
        let nfkc = String(text.prefix(mostText)).precomposedStringWithCompatibilityMapping
        let visible = String(String.UnicodeScalarView(nfkc.unicodeScalars.filter { !drawsNothing($0) })).lowercased()
        let folded = String(visible.map { lookAlikes[$0] ?? $0 })
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        return folded.components(separatedBy: .newlines).map {
            $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The sentences of normalized text: a line break, or . ! ? followed by a space or the end (so an address or a
    /// link with dots in it stays whole).
    static func sentences(_ normalized: String) -> [String] {
        normalized.components(separatedBy: "\n").flatMap { line in
            line.replacingOccurrences(of: #"([.!?。！？])(?=\s|$)"#, with: "$1\n", options: .regularExpression)
                .components(separatedBy: "\n")
        }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let negationBefore = try? NSRegularExpression(pattern: #"(?:\bnever|\bnot|n't|\bno|절대|안) ?$"#)
    private static let negationAfter = try? NSRegularExpression(pattern: #"^\S{0,3} ?(?:지 ?마|지 ?말|지 ?않|면 ?안)"#)

    private static func negated(_ match: NSRange, in sentence: String) -> Bool {
        let text = sentence as NSString
        let beforeStart = max(0, match.location - 16)
        let before = text.substring(with: NSRange(location: beforeStart, length: match.location - beforeStart))
        let afterEnd = min(text.length, match.location + match.length + 8)
        let after = text.substring(with: NSRange(location: match.location + match.length, length: afterEnd - match.location - match.length))
        let hit = { (regex: NSRegularExpression?, s: String) in regex?.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil }
        return hit(negationBefore, before) || hit(negationAfter, after)
    }

    /// The first pattern `text` matches, or nil.
    static func check(_ text: String) -> Hit? {
        for sentence in sentences(normalized(text)) {
            let range = NSRange(location: 0, length: (sentence as NSString).length)
            for (pattern, regexes) in compiled where !regexes.isEmpty {
                var matched = true
                for regex in regexes {
                    guard let found = regex.firstMatch(in: sentence, range: range) else { matched = false; break }
                    if pattern.negatable, negated(found.range, in: sentence) { matched = false; break }
                }
                if matched { return Hit(name: pattern.name, family: pattern.family) }
            }
        }
        return nil
    }

    static func verdict(_ text: String) -> Verdict {
        guard let hit = check(text) else { return .allow }
        return hit.family == .credential ? .refuse(hit) : .review(hit)
    }

    /// Why an item was held, in Settings' words.
    static func reason(_ family: ArisMemoryGateFamily, korean: Bool) -> String {
        switch family {
        case .override: korean ? "AI의 원래 지시를 바꾸려는 말처럼 보여요" : "Reads like an attempt to override the AI's instructions"
        case .standing: korean ? "AI에게 앞으로 이렇게 하라는 지시처럼 보여요" : "Reads like a standing instruction to the AI"
        case .leak: korean ? "내 정보를 어딘가로 보내라는 말처럼 보여요" : "Reads like a request to send your data somewhere"
        case .credential: korean ? "비밀번호나 키를 넘기라는 말처럼 보여요" : "Reads like a request to hand over a password or key"
        }
    }
}
