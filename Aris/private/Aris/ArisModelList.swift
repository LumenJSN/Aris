//
//  ArisModelList.swift
//  Aris (also built into aris-agent)
//
//  The models each brain's own tool offers (ArisModelDiscovery asks it: Claude Code's initialize, Codex's model/list,
//  `agy models`), kept with the time they were read, read again in the background when Settings opens and at most once
//  a day. A model the user chose stays on the list even after the tool stops listing it, and a tool that can't list
//  gives today's fixed names. Also: how a turn tells that a chosen model stopped working (ArisModelRetired), and the
//  choice said for one conversation only ("이번엔 깊게 생각해": ArisConversationModels). Pure, so the tests run it.
//

import Foundation

/// One model a tool offers.
struct ArisModelOption: Codable, Equatable, Sendable {
    let id: String
    var title: String
    /// The tool's own line about it ("Opus 5.5 · Best for everyday, complex tasks").
    var detail: String?
    /// The efforts it takes, as the tool says (empty: unknown).
    var efforts: [String] = []
    /// Chosen by the user but no longer listed by the tool.
    var unlisted: Bool? = nil
}

/// One brain's list as its tool gave it.
struct ArisModelList: Codable, Equatable, Sendable {
    let at: Date
    let options: [ArisModelOption]
    /// False: the tool couldn't list, and these are today's fixed names.
    let fromTool: Bool
}

/// Every brain's list, as the app keeps it (one JSON string in Defaults).
struct ArisModelLists: Codable, Equatable, Sendable {
    var lists: [String: ArisModelList] = [:]

    /// Read again at most this often (and only when Settings opens).
    static let refreshAfter: TimeInterval = 86_400
    /// A list the tool couldn't give is asked again sooner.
    static let retryAfter: TimeInterval = 3_600

    static func decode(_ text: String) -> ArisModelLists {
        guard let data = text.data(using: .utf8) else { return ArisModelLists() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode(ArisModelLists.self, from: data)) ?? ArisModelLists()
    }

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    /// Whether `brain`'s list is read again now: never read, a day old, or an hour old when its tool couldn't list.
    func needsRefresh(_ brain: ArisBrain, now: Date) -> Bool {
        guard let list = lists[brain.rawValue] else { return true }
        return now.timeIntervalSince(list.at) >= (list.fromTool ? Self.refreshAfter : Self.retryAfter)
    }

    /// A copy with `brain`'s list replaced (an empty answer keeps the old list, only its time moves on).
    func storing(_ brain: ArisBrain, options: [ArisModelOption], fromTool: Bool, at now: Date) -> ArisModelLists {
        var next = self
        let kept = options.isEmpty ? (lists[brain.rawValue]?.options ?? Self.fixed(brain)) : options
        next.lists[brain.rawValue] = ArisModelList(at: now, options: kept, fromTool: fromTool && !options.isEmpty)
        return next
    }

    /// What `brain`'s dropdown lists: the tool's models (today's fixed names when it couldn't list), then each id in
    /// `selected` the list doesn't have, marked as no longer listed.
    func options(_ brain: ArisBrain, selected: [String]) -> [ArisModelOption] {
        let listed = lists[brain.rawValue]?.options ?? Self.fixed(brain)
        var seen = Set(listed.map(\.id))
        var all = listed
        for id in selected where !seen.contains(id) {
            seen.insert(id)
            all.append(ArisModelOption(id: id, title: id, detail: nil, unlisted: true))
        }
        return all
    }

    /// The efforts `brain` offers for `model` (nil: 자동's model): that model's, else every listed model's, in the
    /// order the CLIs give them; low, medium and high when nothing says.
    func efforts(_ brain: ArisBrain, model: String?) -> [String] {
        guard ArisModelChoices.brains.contains(brain), brain != .antigravity else { return [] }
        let options = lists[brain.rawValue]?.options ?? []
        let own = model.flatMap { id in options.first { $0.id == id }?.efforts } ?? []
        let named = own.isEmpty ? options.flatMap(\.efforts) : own
        let words = ArisModelChoices.effortWords.filter { named.contains($0) }
        return words.isEmpty ? ["low", "medium", "high"] : words
    }

    /// Today's fixed names, for a tool that can't list (ArisBrain.model(tier:) and ArisThinking's Opus).
    static func fixed(_ brain: ArisBrain) -> [ArisModelOption] {
        switch brain {
        case .claude:
            return [ArisModelOption(id: "opus", title: "Opus"), ArisModelOption(id: "sonnet", title: "Sonnet"), ArisModelOption(id: "haiku", title: "Haiku")]
        case .codex, .antigravity:
            return Set([ArisTier.quick, .work].map { brain.model(tier: $0) }).sorted().map { ArisModelOption(id: $0, title: $0) }
        case .api:
            return []
        }
    }
}

// MARK: - A model that stopped working

enum ArisModelRetired {
    /// Exactly what the tools say when a turn's model doesn't exist or isn't open to this login, and nothing looser
    /// (checked live: Claude Code 2.1.327 "There's an issue with the selected model (x). It may not exist or you may not
    /// have access to it."; codex-cli 0.169.0 "The 'x' model is not supported when using Codex with a ChatGPT account.").
    static let toolWords = [
        #"There's an issue with the selected model \([^)\n]{1,120}\)\. It may not exist or you may not have access to it\."#,
        #"The '[^'\n]{1,120}' model is not supported when using Codex with a"#,
    ]

    static func matches(_ text: String) -> Bool {
        toolWords.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    /// The turn's whole answer when the model failed after the turn had already done something (it is never run twice).
    static func ended(model: String, korean: Bool) -> String {
        korean ? "고른 모델(\(model))을 지금 쓸 수 없어요. 설정 › AI 서비스 › 모델 고르기에서 다른 모델을 골라 주세요."
            : "The model you chose (\(model)) isn't available right now. Pick another in Settings › AI 서비스 › 모델 고르기."
    }

    /// The one sentence the turn starts with when it answered on 자동 instead.
    static func notice(model: String, korean: Bool) -> String {
        korean ? "고른 모델(\(model))을 지금 쓸 수 없어서 이번에는 자동으로 고른 모델로 답할게요."
            : "The model you chose (\(model)) isn't available right now, so this answer uses the automatic one."
    }
}

// MARK: - A choice for this conversation only

/// "이번엔 깊게 생각해", "use sonnet for this": the conversation's own choices over the saved ones. They go with the
/// conversation: the first turn of a new one drops them, unless they were said just before it.
struct ArisConversationModels: Equatable, Sendable {
    private(set) var override = ArisModelChoices.automatic
    /// Said since the last turn went out: the next turn keeps it even when it starts a new conversation.
    private(set) var justSaid = false

    /// A copy with one field said for this conversation (nil: 자동 over the saved choice).
    func saying(_ brain: ArisBrain, _ role: ArisModelRole, _ field: ArisModelChoices.Field, _ value: String?) -> ArisConversationModels {
        var next = self
        next.override = override.setting(brain, role, field, to: value ?? ArisModelChoices.auto)
        next.justSaid = true
        return next
    }

    /// A copy without the conversation's own word on that field (a saved choice was just said for it).
    func forgetting(_ brain: ArisBrain, _ role: ArisModelRole, _ field: ArisModelChoices.Field) -> ArisConversationModels {
        var next = self
        next.override = override.setting(brain, role, field, to: nil)
        return next
    }

    /// A conversation turn going out (`fresh`: it starts a new conversation): the conversation's state after it, and what
    /// the turn carries over `saved`.
    func sending(fresh: Bool, saved: ArisModelChoices) -> (state: ArisConversationModels, choices: ArisModelChoices) {
        let kept = fresh && !justSaid ? ArisConversationModels() : ArisConversationModels(override: override, justSaid: false)
        return (kept, kept.override.merged(over: saved))
    }

    /// What a request carries now without changing anything (a warm-up, a job).
    func current(saved: ArisModelChoices) -> ArisModelChoices { override.merged(over: saved) }
}
