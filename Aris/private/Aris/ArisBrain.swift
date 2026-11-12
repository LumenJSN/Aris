//
//  ArisBrain.swift
//  Aris (also built into aris-agent)
//
//  The AI that answers Aris's questions: Claude, Codex (the user's
//  ChatGPT plan, the default), Antigravity (Gemini) or an API brain (any provider with a key, or a local model:
//  ArisAPIDriver; which one is the agent's active profile). The default is set in Settings; saying
//  the name first ("GPT한테 물어봐, …", "ask Gemini …") picks one for that request.
//

import Foundation

/// How much a request asks of the AI (Jev decides): a quick answer, real work (several steps, research,
/// writing), or critical work (sending, deleting, money, automating several apps) that gets the strongest
/// setup and asks before anything that acts.
enum ArisTier: String, Sendable {
    case quick, work, critical

    static func named(_ raw: String?) -> ArisTier {
        raw.flatMap(ArisTier.init(rawValue:)) ?? .quick
    }
}

enum ArisBrain: String, CaseIterable, Sendable {
    case claude, codex, antigravity, api

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "GPT (Codex)"
        case .antigravity: return "Antigravity (Gemini)"
        case .api: return "API 브레인"
        }
    }

    /// The name in an English sentence or on an English Mac: the API one is “API model” there, as the settings window
    /// calls it (this file is built into aris-agent too, which has no UI language of its own: the caller says which).
    func title(english: Bool) -> String { english && self == .api ? "API model" : title }

    /// The short name, likewise (“API key”).
    func shortTitle(english: Bool) -> String { english && self == .api ? "API key" : shortTitle }

    /// The short name a settings control shows (대화's 기본으로 답하는 AI, a teammate's 두뇌).
    var shortTitle: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .antigravity: return "Gemini"
        case .api: return "API 키"
        }
    }

    /// The model for a quick answer, or for real work (drafting, comparing, planning). Critical work uses the
    /// same strong model, thinking harder (the driver sets the effort).
    func model(tier: ArisTier) -> String {
        let strong = tier != .quick
        switch self {
        case .claude: return strong ? "sonnet" : "haiku"
        case .codex: return strong ? "gpt-6.1-sol" : "gpt-6-luna"
        case .antigravity: return strong ? "gemini-3.8-flash-high" : "gemini-3.8-flash-low"
        // The profile's own models (ArisAPIProfile.model(tier:)); this only names the runner.
        case .api: return strong ? "api-strong" : "api-quick"
        }
    }

    /// Who answers when this one can't (GPT's usage limit): Gemini for GPT, GPT for the others.
    var fallback: ArisBrain? {
        switch self {
        case .codex: return .antigravity
        case .antigravity, .claude, .api: return .codex
        }
    }

    static func named(_ raw: String?) -> ArisBrain {
        raw.flatMap(ArisBrain.init(rawValue:)) ?? .claude
    }

    /// What each AI may be called out loud (as speech recognition writes it).
    private static let names: [(ArisBrain, String)] = [
        (.codex, "gpt|지피티|쥐피티|챗 ?gpt|chat ?gpt|챗 ?지피티|코덱스|codex|openai|오픈 ?ai"),
        (.antigravity, "안티 ?그래비티|antigravity|anti ?gravity|[제재]미나이|[제재]미니|gemini"),
        (.claude, "클로드|claude"),
        (.api, "api|에이피아이|에이피 아이"),
    ]

    /// "GPT한테 물어봐, 내일 비 와?" → (.codex, "내일 비 와?"). Nil when no AI is named up front,
    /// or nothing is left to ask.
    static func pick(from text: String) -> (brain: ArisBrain, request: String)? {
        let lead = #"^\s*(?:아리스|aris)?[\s,.!]*"#
        for (brain, name) in names {
            let asks = #"(?:물어\s?봐\s?줘?|물어볼래|시켜\s?줘?)"#
            // "API" is also an everyday noun: "API로 받아온 데이터 정리해 줘" is about one, so only "API한테 …" or "API로
            // 물어봐 …" names the API brain (audit intent-2).
            let addressed = brain == .api ? #"(?:(?:한테|에게)\s*"# + asks + #"?|(?:로|으로)\s*"# + asks + ")"
                : #"(?:한테|에게|로|으로|야|아)\s*"# + asks + "?"
            let korean = lead + "(?:" + name + #")\s*"# + addressed + #"[\s,.!?:]*"#
            let english = lead + #"(?:(?:ask|use|hey)\s+)?(?:"# + name + #")\s*(?:[,:]|\s+to\b)?\s*"#
            for pattern in [korean, english] {
                guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
                // English needs "ask/use/hey" or a comma, so a name in passing ("Claude Code 세션") isn't a pick.
                let said = String(text[range])
                if pattern == english, said.range(of: #"(?i)\b(ask|use|hey)\b|[,:]"#, options: .regularExpression) == nil { continue }
                let request = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return request.isEmpty ? nil : (brain, request)
            }
        }
        return nil
    }
}

/// Who works other apps' windows, the user's pick (the owner: compare them, then leave it to the user). Peekaboo is free and
/// the default on every brain (`aris-tools desktop`). Codex's own computer use (cua_repl, its per-step cards and judge)
/// needs Codex installed and the user's pick. Another engine (Claude's) gets a case here.
enum ArisComputerEngine: String, CaseIterable {
    case peekaboo, codex

    /// The app's stored pick (Defaults' key, sent with every question).
    static let preferenceKey = "arisComputerEngine"

    static func named(_ raw: String?) -> ArisComputerEngine { raw.flatMap(ArisComputerEngine.init(rawValue:)) ?? .peekaboo }

    /// What really runs: the pick when it can run here, else the free default.
    static func effective(picked: ArisComputerEngine, codexInstalled: Bool) -> ArisComputerEngine {
        picked == .codex && codexInstalled ? .codex : .peekaboo
    }

    var title: String {
        switch self {
        case .peekaboo: return "Peekaboo (무료)"
        case .codex: return "GPT (Codex)"
        }
    }

    /// The name on an English Mac (“Peekaboo (free)”, as the settings window calls it).
    func title(english: Bool) -> String { english && self == .peekaboo ? "Peekaboo (free)" : title }
}
