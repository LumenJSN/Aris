//
//  ArisModelVoice.swift
//  Aris
//
//  The model or the effort said out loud: "모델 오퍼스로 바꿔", "use sonnet for this", "이번엔 깊게 생각해", "앞으로 항상
//  하이쿠 써". It sets the 대화 choice of the brain that answers, for this conversation, or as the saved choice when the
//  words say 항상 / always; answered on the Mac, never by a brain. Only a whole short command counts, and only a model
//  name Aris knows: "엑셀로 바꿔" or a question that mentions Opus is not one. Pure, so the tests run it.
//

import Foundation

struct ArisModelVoiceCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A model's spoken name, in its Latin spelling ("opus", "luna").
        case model(String)
        case effort(String)
        /// Back to 자동 (model and effort).
        case automatic
    }

    let kind: Kind
    /// The saved choice (항상, 앞으로, always, from now on), not just this conversation's.
    let always: Bool
}

enum ArisModelVoice {
    /// The model names said aloud, as speech recognition writes them, and the Latin name each means.
    static let names: [(spoken: String, latin: String)] = [
        ("오퍼스|오퍼즈|opus", "opus"), ("소넷|쏘넷|sonnet", "sonnet"), ("하이쿠|haiku", "haiku"), ("페이블|fable", "fable"),
        ("루나|luna", "luna"), ("솔|sol", "sol"), ("테라|terra", "terra"), ("아스트라|astra", "astra"),
        ("플래시|flash", "flash"), ("제미나이 프로|gemini pro", "pro"),
    ]

    private static let alwaysWords = #"(?i)(항상|앞으로|계속|기본으로|늘|always|from now on|by default)"#
    private static let lead = #"^\s*(?:아리스|aris)?[\s,.!]*(?:(?:이번엔|이번에는|이번 대화는|지금부터|앞으로는?|항상|계속|늘|please|always)\s*)*"#
    private static let tail = #"[\s.!?~]*$"#

    static func parse(_ said: String) -> ArisModelVoiceCommand? {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 60 else { return nil }
        let always = text.range(of: alwaysWords, options: .regularExpression) != nil
        if let kind = automatic(text) ?? effort(text) ?? model(text) { return ArisModelVoiceCommand(kind: kind, always: always) }
        return nil
    }

    private static func matches(_ text: String, _ body: String) -> Bool {
        text.range(of: "(?i)" + lead + body + tail, options: .regularExpression) != nil
    }

    private static func automatic(_ text: String) -> ArisModelVoiceCommand.Kind? {
        let korean = #"(?:모델|ai 모델)\s*(?:을|를)?\s*(?:자동|원래대로|기본)\s*(?:으로|로)?\s*(?:돌려|바꿔|해|되돌려)\s*(?:줘|줄래|주세요)?"#
        let english = #"(?:use|go back to|switch back to|set)\s+(?:the\s+)?(?:automatic|auto|default)\s+model(?:\s+again)?(?:\s+for (?:this|now|this conversation))?(?:\s+from now on)?"#
        return matches(text, korean) || matches(text, english) ? .automatic : nil
    }

    private static func effort(_ text: String) -> ArisModelVoiceCommand.Kind? {
        let ask = #"\s*(?:생각해|생각해\s*줘|생각해서\s*(?:답해|대답해)\s*(?:줘)?|고민해|고민해\s*줘)"#
        if matches(text, #"(?:최대한|가장|제일|아주 아주)\s*(?:깊게|깊이|오래)"# + ask)
            || matches(text, #"think as hard as you can|think the hardest|maximum effort|max effort"#) { return .effort("max") }
        if matches(text, #"(?:더\s*)?(?:깊게|깊이|오래|천천히|신중하게|꼼꼼하게)"# + ask)
            || matches(text, #"think (?:harder|hard|deeply|more|carefully)(?:\s+(?:about it|for this|this time|from now on))?"#) { return .effort("high") }
        if matches(text, #"(?:가볍게|빨리|짧게|대충|조금만)"# + ask)
            || matches(text, #"think (?:less|quickly|fast|briefly)(?:\s+(?:for this|this time|from now on))?|(?:answer|be) quick(?:ly)?(?: from now on)?"#) { return .effort("low") }
        if matches(text, #"보통(?:으로)?"# + ask) || matches(text, #"think normally|normal effort"#) { return .effort("medium") }
        return nil
    }

    private static func model(_ text: String) -> ArisModelVoiceCommand.Kind? {
        for (spoken, latin) in names {
            let name = "(?:" + spoken + ")"
            let korean = [
                #"(?:모델|ai 모델)\s*(?:을|를)?\s*"# + name + #"\s*(?:모델)?\s*(?:으로|로)\s*(?:바꿔|바꿔\s*줘|바꿔\s*주세요|바꿀래|해|해\s*줘|써|써\s*줘|쓰자|변경해\s*줘?)"#,
                name + #"\s*(?:모델)?\s*(?:으로|로)\s*(?:바꿔|바꿔\s*줘|바꿔\s*주세요|바꿀래|답해|답해\s*줘|대답해\s*줘?|해\s*줘|써\s*줘)"#,
                name + #"\s*(?:모델)?\s*(?:써|써\s*줘|쓰자|써\s*주세요)"#,
            ]
            let english = #"(?:use|switch to|change (?:the )?model to|set (?:the )?model to)\s+(?:claude\s+|gpt\s+|gemini\s+)?"# + name
                + #"(?:\s+model)?(?:\s+(?:for (?:this|now|this conversation)|from now on|by default))*"#
            if korean.contains(where: { matches(text, $0) }) || matches(text, english) { return .model(latin) }
        }
        return nil
    }

    /// The id `latin` means on a brain whose dropdown lists `options`: Claude Code's own alias when it has one, else the
    /// first listed model whose id or name has it ("luna" → "gpt-6-luna", "fable" → "claude-fable-5-2[1m]"). Nil: that
    /// brain has no such model.
    static func resolve(_ latin: String, brain: ArisBrain, options: [ArisModelOption]) -> String? {
        if brain == .claude, ["opus", "sonnet", "haiku"].contains(latin) { return latin }
        let word = latin.lowercased()
        let named = options.filter { $0.unlisted != true }
        return named.first { $0.id.lowercased() == word }?.id
            ?? named.first { tokens($0.id).contains(word) || tokens($0.title).contains(word) }?.id
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// What the command changes (the 대화 choice of `brain`; nil value: 자동) and what Aris says. No change: it says why.
    struct Outcome: Equatable, Sendable {
        struct Change: Equatable, Sendable {
            let field: ArisModelChoices.Field
            let value: String?
        }

        let changes: [Change]
        let always: Bool
        let line: String
    }

    /// `options`: the brain's dropdown as it is now (ArisModelLists.options).
    static func outcome(_ command: ArisModelVoiceCommand, brain: ArisBrain, options: [ArisModelOption], korean: Bool) -> Outcome {
        let always = command.always
        guard ArisModelChoices.brains.contains(brain) else { return Outcome(changes: [], always: always, line: notChosenHere(brain: brain, korean: korean)) }
        switch command.kind {
        case .automatic:
            return Outcome(changes: [.init(field: .model, value: nil), .init(field: .effort, value: nil)], always: always,
                           line: automaticSet(always: always, korean: korean))
        case .effort(let effort):
            guard brain != .antigravity else { return Outcome(changes: [], always: always, line: noEffort(brain: brain, korean: korean)) }
            return Outcome(changes: [.init(field: .effort, value: effort)], always: always, line: effortSet(effort, always: always, korean: korean))
        case .model(let latin):
            guard let id = resolve(latin, brain: brain, options: options) else {
                return Outcome(changes: [], always: always, line: noSuchModel(latin, brain: brain, korean: korean))
            }
            let title = options.first { $0.id == id }?.title ?? (latin.prefix(1).uppercased() + latin.dropFirst())
            return Outcome(changes: [.init(field: .model, value: id)], always: always, line: modelSet(title, always: always, korean: korean))
        }
    }

    // MARK: - What Aris says

    static func noEffort(brain: ArisBrain, korean: Bool) -> String {
        korean ? "\(brain.shortTitle)는 모델마다 생각 수준이 정해져 있어요. 모델을 바꿔 보세요."
            : "\(brain.shortTitle(english: true)) sets how hard it thinks by model. Try another model instead."
    }

    static func effortName(_ effort: String, korean: Bool) -> String {
        switch effort {
        case "minimal": return korean ? "아주 가볍게" : "very lightly"
        case "low": return korean ? "가볍게" : "lightly"
        case "medium": return korean ? "보통으로" : "normally"
        case "high": return korean ? "깊게" : "hard"
        case "xhigh": return korean ? "아주 깊게" : "very hard"
        default: return korean ? "최대한 깊게" : "as hard as it can"
        }
    }

    static func modelSet(_ title: String, always: Bool, korean: Bool) -> String {
        if korean { return always ? "앞으로 대화는 \(title) 모델로 답할게요." : "이번 대화는 \(title) 모델로 답할게요." }
        return always ? "From now on I'll answer with \(title)." : "I'll answer with \(title) for this conversation."
    }

    static func effortSet(_ effort: String, always: Bool, korean: Bool) -> String {
        let how = effortName(effort, korean: korean)
        if korean { return always ? "앞으로 대화는 \(how) 생각하고 답할게요." : "이번 대화는 \(how) 생각하고 답할게요." }
        return always ? "From now on I'll think \(how) before answering." : "I'll think \(how) before answering in this conversation."
    }

    static func automaticSet(always: Bool, korean: Bool) -> String {
        if korean { return always ? "대화 모델을 자동으로 돌렸어요." : "이번 대화는 자동으로 고른 모델로 답할게요." }
        return always ? "The conversation model is back to automatic." : "I'll use the automatic model for this conversation."
    }

    static func noSuchModel(_ latin: String, brain: ArisBrain, korean: Bool) -> String {
        let name = latin.prefix(1).uppercased() + latin.dropFirst()
        return korean ? "지금 답하는 \(brain.shortTitle)에는 \(name) 모델이 없어요."
            : "\(brain.shortTitle(english: true)), which answers now, has no model called \(name)."
    }

    static func notChosenHere(brain: ArisBrain, korean: Bool) -> String {
        korean ? "API 키로 쓰는 AI의 모델은 설정 › AI 서비스에서 골라요." : "Choose the API model's models in Settings › AI 서비스."
    }
}
