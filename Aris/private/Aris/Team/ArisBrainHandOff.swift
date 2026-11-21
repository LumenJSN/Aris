//
//  ArisBrainHandOff.swift
//  Aris
//
//  "아니 그냥 클로드 시켜" (the owner, 2026-11-14: Aris answered "지금 클로드라는 팀원은 없어요"): the AIs on this Mac are
//  Aris's brains, not teammates, and naming one as the one to do the work hands the request to it as a background job,
//  the way a teammate's job runs. Decided here in the app from the user's words, never left to a model: Claude (Claude
//  Code, 클로드, 클코), Codex (GPT, 코덱스), Antigravity (Gemini, 제미나이) and an API model by its service (DeepSeek,
//  OpenRouter…), in Korean and English, with the spellings speech recognition writes. A teammate of that name (not
//  the seeded Claude Code, which opens in a terminal with a project folder) still wins. A hand-off that says no task of
//  its own carries the conversation's last request over, with Aris's question back and the answers to it. Pure.
//

import Foundation

/// Who a hand-off names.
enum ArisHandOffTarget: Equatable {
    /// One of the user's own teammates, by its id.
    case teammate(String)
    case brain(ArisBrain)
    /// An API model by its service (a shipped provider's id, "deepseek"); nil: the API brain as such ("API로 해").
    case api(service: String?)

    /// The brain the job runs on; nil for a teammate (its own).
    var brain: ArisBrain? {
        switch self {
        case .teammate: return nil
        case .brain(let brain): return brain
        case .api: return .api
        }
    }
}

struct ArisBrainHandOff: Equatable {
    let target: ArisHandOffTarget
    /// The name as said ("클로드", "Claude Code").
    let said: String
    /// The user's words as said when they also say what to do ("클로드한테 이 보고서 정리하라고 시켜"); nil when they only hand
    /// over ("그냥 클로드 시켜"): the conversation's last request is the job then.
    let task: String?
}

extension ArisBrainHandOff {
    /// What each brain may be called (as said, and as speech recognition writes it), the longest first.
    static let brainNames: [(brain: ArisBrain, pattern: String)] = [
        (.claude, #"클로드\s*코드|클라우드\s*코드|클로드코드|claude[\s-]*code|클코|클로드|클러드|크로드|claude|claud|cloude"#),
        (.codex, #"챗\s*gpt|chat\s*gpt|챗\s*지피티|코덱스|코덱|codex|지피티|쥐피티|gpt|오픈\s*ai|open\s*ai"#),
        (.antigravity, #"안티\s*그래비티|안티\s*그라비티|antigravity|anti[\s-]*gravity|[제재]미나이|[제재]미니|gemini|agy"#),
    ]

    /// The API services Aris ships (ArisAPIPreset's ids), by the names said for them; these are read before the brains,
    /// so "Gemini API" is the API model and "Gemini" alone Antigravity.
    static let services: [(id: String, title: String, pattern: String)] = [
        ("openai", "OpenAI", #"(?:open\s*ai|오픈\s*ai|오픈\s*에이아이|gpt|지피티)\s*(?:api|에이피아이)"#),
        ("anthropic", "Anthropic", #"(?:claude|클로드)\s*(?:api|에이피아이)|anthropic(?:\s*api)?|앤트로픽(?:\s*api)?|앤스로픽(?:\s*api)?"#),
        ("gemini", "Gemini API", #"(?:gemini|[제재]미나이)\s*(?:api|에이피아이)"#),
        ("openrouter", "OpenRouter", #"open\s*router|오픈\s*라우터"#),
        ("groq", "Groq", #"groq|그로크"#),
        ("xai", "xAI", #"xai|grok|그록"#),
        ("mistral", "Mistral", #"mistral|미스트랄"#),
        ("deepseek", "DeepSeek", #"deep\s*seek|딥\s*시크|딥식"#),
        ("ollama", "Ollama", #"ollama|올라마"#),
        ("lmstudio", "LM Studio", #"lm\s*studio|엘엠\s*스튜디오"#),
    ]

    /// The API brain as such.
    static let apiName = #"api\s*(?:모델|브레인|model)?|에이피아이"#

    /// The shipped service's title by its id.
    static func serviceTitle(_ id: String) -> String? { services.first { $0.id == id }?.title }

    // MARK: - The words

    /// Words that hand over with no particle needed ("그냥 클로드 시켜").
    private static let handVerbs = #"시켜|시키자|시킬게|시켜라|맡겨|맡기자|맡길게|맡겨라|넘겨|넘기자|넘길게|(?:시키|맡기|넘기)면\s*(?:돼|되잖아|될\s*것\s*같아)"#
    /// Words that hand over only after a particle ("Claude로 해", "클로드한테 줘", "클로드가 해").
    private static let doVerbs = #"해|하자|할래|하게\s*해|하라고\s*해|해\s*봐|줘|보내|돌려"#
    private static let ending = #"(?:\s*(?:줘|주세요|줄래|주라|요|봐|보자|볼래|버려|놔|둬|라|돼|되잖아|될\s*것\s*같아))*"#
    /// The hand-off ends the words, or a comma or full stop follows it ("클로드 시켜, 회의록 요약해서"): never a question, nor
    /// words that go on about it ("클로드한테 맡겨 놓은 거 어떻게 됐어", "클로드가 해 준 거").
    private static let end = #"\s*(?=$|[,.!~])"#
    /// After the name, before the verb.
    private static let particle = #"(?:한테|에게|께|더러|보고|으로|로|이|가)"#
    private static let softener = #"(?:\s*(?:그냥|좀|한번|한\s*번|다|이거|그거|이것|그것))*"#
    /// Not a Latin letter or digit before the name ("openclaude" is no name); Hangul may run on.
    private static let before = #"(?<![A-Za-z0-9])"#
    /// The name is an app here ("클로드 앱으로 해", "ChatGPT 열어서 물어봐"): ArisProgramMention's, not a hand-off.
    private static let appCue = #"^\s*(?:앱|어플|애플리케이션|데스크톱|app\b|application\b|desktop\b|창|window\b|을\s*열|를\s*열|열어|열고|켜서|켜고|띄워|실행)"#

    /// Words that say nothing of the task ("아니 그냥 … 시켜"): a hand-off with only these carries the last request over.
    private static let fillers: Set<String> = [
        "아니", "아니야", "아뇨", "아냐", "그냥", "걍", "그럼", "그러면", "그래", "음", "어", "응", "좀", "이거", "그거", "저거", "이것", "그것",
        "이건", "그건", "이걸", "그걸", "일", "그일", "이일", "네가", "니가", "너가", "말고", "대신", "차라리", "아리스", "그러니까", "그니까", "그래서",
        "aris", "no", "nah", "just", "then", "ok", "okay", "it", "this", "that", "please", "instead", "actually", "rather", "the", "task", "job",
        "for", "me", "so", "well", "um", "hey",
    ]

    /// The hand-off `text` says, if it is one: a teammate (the user's own, not the seeded Claude Code) named as the one to do
    /// it, else a brain or an API service. Nil when no one is named as the one to do it ("클로드한테 물어봐" picks the
    /// brain that answers the turn: ArisBrain.pick), or the name is an app's ("클로드 앱으로 해").
    static func parse(_ text: String, teammates: [ArisTeammate] = []) -> ArisBrainHandOff? {
        let words = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        // A question about a hand-off ("did you have Claude do it?", "클로드 시켜?") hands nothing over.
        guard !words.isEmpty, !words.hasSuffix("?"), !words.hasSuffix("？") else { return nil }
        // A teammate of that name wins, the longest name first ("Claude Code" isn't taken for a "Claude").
        let mates = teammates.filter { $0.id != ArisTeammate.claudeCodeId && !$0.name.isEmpty }.sorted { $0.name.count > $1.name.count }
        for mate in mates {
            let name = mate.name.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s*"#)
            if let found = handOff(in: words, name: name) { return ArisBrainHandOff(target: .teammate(mate.id), said: found.said, task: found.task) }
        }
        for service in services {
            if let found = handOff(in: words, name: service.pattern) { return ArisBrainHandOff(target: .api(service: service.id), said: found.said, task: found.task) }
        }
        for (brain, pattern) in brainNames {
            if let found = handOff(in: words, name: pattern) { return ArisBrainHandOff(target: .brain(brain), said: found.said, task: found.task) }
        }
        if let found = handOff(in: words, name: apiName, particleOnly: true) { return ArisBrainHandOff(target: .api(service: nil), said: found.said, task: found.task) }
        return nil
    }

    /// The name said and the task (the user's words, when anything but the hand-off is left) for `name` as the one handed to.
    /// `particleOnly`: the name needs a particle ("API로 해", never "API 시켜" in passing).
    private static func handOff(in words: String, name: String, particleOnly: Bool = false) -> (said: String, task: String?)? {
        let named = before + "(" + name + ")"
        let latin = particleOnly ? particle : particle + "?"
        let patterns = [
            // "그냥 클로드 시켜", "클로드 코드한테 맡겨 줘", "이거 코덱스로 넘겨"
            named + #"\s*"# + latin + softener + #"\s*(?:"# + handVerbs + ")" + ending + end,
            // "Claude로 해", "클로드한테 줘", "클로드가 해"
            named + #"\s*"# + particle + softener + #"\s*(?:"# + doVerbs + ")" + ending + end,
            // "클로드한테 이 보고서 정리하라고 시켜": the task between
            named + #"\s*(?:한테|에게|께|더러|보고)\s+(.+?)\s*(?:"# + handVerbs + ")" + ending + #"[\s.!?~]*$"#,
            // English: "have Claude do it", "let Codex handle this", "give it to Gemini", "use Claude", "do it with Codex"
            #"(?i)\b(?:have|let|get)\s+"# + named + #"\s+(?:do|handle|take|run|try|finish|write|make|fix)\b"#,
            #"(?i)\b(?:give|hand|pass|send|delegate|leave)\s+(?:(?:it|this|that|the\s+(?:task|job|rest))\s+)?(?:(?:off|over)\s+)?to\s+"# + named + #"\b"#,
            #"(?i)\bask\s+"# + named + #"\s+to\s+(?:do|handle|take\s+care\s+of)\s+(?:it|this|that)\b"#,
            #"(?i)\b(?:do|run)\s+(?:it|this|that)\s+(?:with|on|using)\s+"# + named + #"\b"#,
            #"(?i)^\s*(?:(?:no|nah|ok|okay|then|just)[\s,]+)*(?:use|try)\s+"# + named + #"(?:\s+(?:instead|for\s+(?:it|this|that)|then))?[\s.!]*$"#,
        ]
        for pattern in patterns {
            guard let range = words.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            guard let said = words.range(of: before + "(?:" + name + ")", options: [.regularExpression, .caseInsensitive], range: range) else { continue }
            // "클로드 앱으로 해", "ChatGPT 열어서 시켜": the app on this Mac, not the brain.
            if words[said.upperBound...].range(of: appCue, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            let rest = withoutFragments(String(words[..<range.lowerBound])) + " " + String(words[range]).replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
                + " " + String(words[range.upperBound...])
            let between = pattern.contains("(.+?)") ? middle(of: words[range], name: name) : ""
            return (String(words[said]), saysTask(rest + " " + between) ? words : nil)
        }
        return nil
    }

    /// The task between the name and the verb ("클로드한테 <이 보고서 정리하라고> 시켜").
    private static func middle(of match: Substring, name: String) -> String {
        let pattern = before + "(?:" + name + #")\s*(?:한테|에게|께|더러|보고)\s+"#
        guard let lead = match.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
              let tail = match.range(of: #"\s*(?:"# + handVerbs + ")" + ending + #"[\s.!?~]*$"#, options: [.regularExpression, .caseInsensitive]) else { return "" }
        guard lead.upperBound <= tail.lowerBound else { return "" }
        return String(match[lead.upperBound..<tail.lowerBound]).replacingOccurrences(of: #"(?:하라고|해\s*달라고|해\s*보라고|해\s*주라고)$"#, with: " 해", options: .regularExpression)
    }

    /// A lone clause left over from what was said before ("물어보면.", "못해서."): one word that ends the way a sentence goes
    /// on (…면, …서, …는데, …니까, …고, …지만), no request of its own (the owner, 2026-11-14: "물어보면. 아니 그냥 클로드 시켜"
    /// was taken as a task of its own, and the marketing request before it was left behind).
    static func isFragment(_ piece: String) -> Bool {
        let tokens = piece.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard tokens.count == 1, let word = tokens.first else { return false }
        return word.range(of: #"(?:면|면은|서|는데|은데|니까|고|지만)$"#, options: .regularExpression) != nil
    }

    /// The words before a hand-off without the sentences that are only a lone clause.
    private static func withoutFragments(_ text: String) -> String {
        text.components(separatedBy: CharacterSet(charactersIn: ".!?…\n")).filter { !isFragment($0) }.joined(separator: " ")
    }

    /// Anything but filler words left.
    static func saysTask(_ rest: String) -> Bool {
        let tokens = rest.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return tokens.contains { !fillers.contains($0) }
    }

    // MARK: - The job

    /// What the job is: its title, its brief, and the user's own words for the agent's policy.
    struct Brief: Equatable {
        let title: String
        let prompt: String
        let request: String
    }

    /// The longest of Aris's lines a carried-over brief quotes.
    static let longestQuote = 600

    /// The job `words` hand over. With a task of their own: the user's words as said. Without one ("그냥 클로드 시켜"): the
    /// conversation's last request, with Aris's question back and the answers to it (the turns that answered a question
    /// go with the request they answered); nil when the conversation has no request (Aris then asks what to hand over).
    /// `whole`: the user's words with the files they gave now and their text (ArisPendingFiles), when there are any.
    static func brief(_ handOff: ArisBrainHandOff, words: String, whole: String? = nil, history: [ArisContext.Turn], to name: String) -> Brief? {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        let given = whole.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0 == said || $0.isEmpty ? nil : $0 }
        if handOff.task != nil { return Brief(title: ArisHandoff.title(of: said), prompt: given ?? said, request: said) }
        let chain = exchange(in: history)
        guard let first = chain.first else { return nil }
        let lines = chain.flatMap { turn -> [String] in
            let reply = turn.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let quoted = reply.count > longestQuote ? String(reply.prefix(longestQuote)) + "…" : reply
            return ["User: \(turn.heard)"] + (quoted.isEmpty ? [] : ["Aris: \(quoted)"])
        }
        let prompt = first.heard + "\n\n(The user asked this earlier in the conversation, then handed it to \(name) with “\(said)”. " +
            "Do what they asked, with what they answered. The conversation so far, oldest first:\n" + lines.joined(separator: "\n") + ")"
            + (given.map { "\n\nWhat they gave with the hand-off:\n" + $0 } ?? "")
        let request = (chain.map(\.heard) + [said]).joined(separator: "\n")
        return Brief(title: ArisHandoff.title(of: first.heard), prompt: prompt, request: request)
    }

    /// The last request and the turns that answered Aris's questions about it, oldest first: from the last turn back,
    /// while the turn before asked something ("어떤 걸로 할까요?"), the turn after it answered. A turn that only handed
    /// over (an earlier "클로드 시켜") is no request, nor one that is only a lone clause ("못해서.").
    static func exchange(in history: [ArisContext.Turn]) -> [ArisContext.Turn] {
        let turns = history.filter { turn in
            guard let handOff = parse(turn.heard) else { return !turn.heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return handOff.task != nil
        }
        guard var start = turns.indices.last else { return [] }
        // A turn that is only a lone clause ("못해서.") goes on from the one before: that one is the request.
        while start > turns.startIndex, ArisFollowUp.asksSomething(turns[start - 1].reply) || isFragment(turns[start].heard) { start -= 1 }
        return Array(turns[start...])
    }

    /// One job as it will run, the way a teammate's or Aris's own single job runs (ArisHandOutPlan): a clean turn hands
    /// The user's request out with the conversation around it; a turn with the screen or outside text in it or its
    /// conversation hands it out untrusted, with none of the conversation, on the brain named (whose own gate for
    /// outside words holds it: ArisJobBrain.untrustedPlan). A teammate's job runs on its own brain, its scopes as ever.
    static func plan(_ brief: Brief, target: ArisHandOffTarget, turn: ArisHandOutPlan.Turn, teammateBrains: [String: ArisBrain] = [:]) -> ArisJobPlan {
        let assignee: ArisJobAssignee
        let brain: ArisBrain
        switch target {
        case .teammate(let id):
            assignee = .teammate(id)
            brain = teammateBrains[id] ?? turn.brain
        case .brain(let named):
            assignee = .clone
            brain = named
        case .api:
            assignee = .clone
            brain = .api
        }
        let spec = ArisJobSpec(title: brief.title, prompt: brief.prompt, assignee: assignee, cwd: nil, appHint: nil)
        guard turn.isClean else {
            let provenance = ArisProvenance(untrusted: true, screenConversation: turn.screenConversation,
                                            outsideConversation: turn.outsideConversation, handsFree: turn.handsFree)
            return ArisJobPlan(spec: spec, brain: brain, provenance: provenance, request: brief.request, cleanContext: true, turn: nil)
        }
        return ArisJobPlan(spec: spec, brain: brain, provenance: ArisProvenance(handsFree: turn.handsFree), request: brief.request,
                           cleanContext: false, turn: nil)
    }

    // MARK: - What is said

    /// The brain's name as Aris says it: the program for the three that run one here, the service for an API model.
    static func name(_ target: ArisHandOffTarget, teammate: String? = nil, english: Bool) -> String {
        switch target {
        case .teammate(let id): return teammate ?? id
        case .brain(.claude): return "Claude Code"
        case .brain(.codex): return "Codex"
        case .brain(.antigravity): return "Antigravity"
        case .brain(.api), .api(service: nil): return english ? "the API model" : "API 모델"
        case .api(service: let id?): return serviceTitle(id) ?? id
        }
    }

    /// The API brain's state as the agent said it (설정 › AI 서비스): the provider that answers, and those that can answer
    /// (a saved key, or a server on this Mac).
    struct APIState: Equatable {
        var active: String?
        var connected: Set<String> = []
    }

    /// Why the job can't go to `target` on this Mac, as said to the user (Korean for a Korean request); nil when it can, or
    /// when the agent hasn't said (`ready` nil: the job then says itself what is missing). `ready`: by the brain's raw
    /// name, as the agent's "brains" answer. Never "no such teammate".
    static func missingLine(_ target: ArisHandOffTarget, ready: [String: Bool]?, api: APIState?, korean: Bool,
                            english: Bool = ArisUIWords.english) -> String? {
        // The sentence in the request's language, the path as the settings window names it (ArisSettingsPath).
        let place = ArisSettingsPath.path(.ai, "답하는 AI", english: english)
        switch target {
        case .teammate:
            return nil
        case .api(service: let id?):
            let title = serviceTitle(id) ?? id
            if let api {
                if !api.connected.contains(id) {
                    return korean ? "\(title) API 키가 아직 없어요. \(place)에서 키를 넣어 주세요." : "There's no \(title) API key yet. Add it in \(place)."
                }
                if api.active != id {
                    return korean ? "지금 답하는 API 모델이 \(ArisHandoffLine.subject(title)) 아니에요. \(place)에서 바꾸면 맡길 수 있어요."
                        : "\(title) is connected, but it isn't the API model that answers. Switch to it in \(place) and I can hand it over."
                }
            }
            guard ready?[ArisBrain.api.rawValue] == false else { return nil }
            return korean ? "\(title) API가 아직 답하지 않아요. \(place)에서 키를 확인해 주세요." : "\(title) isn't answering yet. Check its key in \(place)."
        case .api(service: nil), .brain(.api):
            guard ready?[ArisBrain.api.rawValue] == false else { return nil }
            return korean ? "API 모델이 아직 연결돼 있지 않아요. \(place)에서 API 키를 넣어 주세요." : "No API model is connected yet. Add an API key in \(place)."
        case .brain(let brain):
            guard ready?[brain.rawValue] == false else { return nil }
            let title = name(target, english: !korean)
            return korean ? "\(ArisHandoffLine.subject(title)) 이 Mac에 없거나 로그인돼 있지 않아요. \(place)에서 연결해 주세요."
                : "\(title) isn't on this Mac or isn't logged in. Connect it in \(place)."
        }
    }

    /// Asked when there is nothing to hand over yet.
    static func askLine(_ name: String, korean: Bool) -> String {
        korean ? "\(name)한테 무엇을 맡길까요?" : "What should I hand to \(name)?"
    }
}
