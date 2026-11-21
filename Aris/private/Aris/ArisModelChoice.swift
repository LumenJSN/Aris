//
//  ArisModelChoice.swift
//  Aris (also built into aris-agent)
//
//  Which model each brain uses for each kind of work, and how hard it thinks there (the owner, 2026-11-18: "모델을 내 마음대로
//  못 바꿔"). Four roles: 대화 (a spoken or typed turn), 깊은 일 (a look-up, careful or screen turn), 작업 (background
//  jobs and teammates) and the small helper (one-shot summaries, dictation's polish, drafts; never a safety judge). Each
//  is 자동 until the user picks: 자동 is exactly the mapping in ArisThinking and ArisBrain, so nothing changes for anyone
//  who never opens the setting. The app keeps the choice in Defaults and sends it with every request, as it sends the
//  brain; aris-agent keeps the last one it heard (ArisModelChoiceBox) for the work no request names (a schedule, a judge
//  that isn't one). Pure, so the tests run it.
//

import Foundation

/// The kinds of work a model is chosen for.
enum ArisModelRole: String, CaseIterable, Sendable {
    case conversation, deep, job, helper

    var title: String {
        switch self {
        case .conversation: return "대화"
        case .deep: return "깊은 일"
        case .job: return "작업"
        case .helper: return "작은 도우미"
        }
    }

    /// The line under the role's row.
    var detail: String {
        switch self {
        case .conversation: return "말하거나 입력한 질문에 답할 때"
        case .deep: return "찾아보거나 신중해야 하거나 화면을 볼 때"
        case .job: return "백그라운드 작업과 팀원"
        case .helper: return "요약, 받아쓰기 다듬기 같은 짧은 일 · 안전 확인은 바꾸지 않아요"
        }
    }

    /// The role a turn of `tier` plays: a background job's own, else a look-up or careful turn's, else a conversation's.
    static func of(tier: ArisTier, task: Bool) -> ArisModelRole {
        if task { return .job }
        return ArisThinking.thinksHard(tier) ? .deep : .conversation
    }
}

/// One role's choice on one brain: nil is 자동.
struct ArisRoleChoice: Equatable, Sendable {
    var model: String?
    var effort: String?
}

/// Every brain's choices, as one flat table ("claude.conversation.model": "opus"), the way Defaults keeps it and the
/// request carries it. Only well-formed entries are ever in it: a known brain that has models to choose, a role, a model
/// id of safe characters, an effort word a CLI takes. "auto" in a conversation's override means 자동 over a saved choice.
struct ArisModelChoices: Equatable, Sendable {
    enum Field: String, Sendable { case model, effort }

    private(set) var entries: [String: String]

    static let automatic = ArisModelChoices(entries: [:])
    static let auto = "auto"
    /// The efforts any of the CLIs takes (Claude Code: low…max; Codex: also minimal and ultra on some models).
    static let effortWords = ["minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    /// The brains whose model is chosen here (an API brain's are its profile's quick and strong ones).
    static let brains: [ArisBrain] = [.claude, .codex, .antigravity]
    static let maxEntries = 32

    /// Only the well-formed entries of `raw` (anything else is dropped, never guessed at).
    init(entries raw: [String: String]) {
        var kept: [String: String] = [:]
        for (key, value) in raw where kept.count < Self.maxEntries {
            guard let field = Self.parts(key)?.2 else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            let valid = trimmed == Self.auto || (field == .model ? Self.isModelID(trimmed) : Self.effortWords.contains(trimmed))
            if valid { kept[key] = trimmed }
        }
        entries = kept
    }

    /// A request's `models` object (strings only); anything else is 자동.
    static func parse(_ value: Any?) -> ArisModelChoices {
        guard let object = value as? [String: Any] else { return .automatic }
        return ArisModelChoices(entries: object.compactMapValues { $0 as? String })
    }

    static func key(_ brain: ArisBrain, _ role: ArisModelRole, _ field: Field) -> String {
        "\(brain.rawValue).\(role.rawValue).\(field.rawValue)"
    }

    static func parts(_ key: String) -> (ArisBrain, ArisModelRole, Field)? {
        let pieces = key.split(separator: ".").map(String.init)
        guard pieces.count == 3, let brain = ArisBrain(rawValue: pieces[0]), brains.contains(brain),
              let role = ArisModelRole(rawValue: pieces[1]), let field = Field(rawValue: pieces[2]) else { return nil }
        return (brain, role, field)
    }

    /// A model id as the CLIs write them ("opus", "claude-fable-5-2[1m]", "gpt-6-luna", "openai/gpt-oss-120b").
    static func isModelID(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/@\[\]+-]{0,119}$"#, options: .regularExpression) != nil
    }

    /// The choice for `role` on `brain` (nil fields: 자동).
    func choice(_ brain: ArisBrain, _ role: ArisModelRole) -> ArisRoleChoice {
        let value = { (field: Field) -> String? in
            entries[Self.key(brain, role, field)].flatMap { $0 == Self.auto ? nil : $0 }
        }
        return ArisRoleChoice(model: value(.model), effort: value(.effort))
    }

    /// A copy with one field set (nil: back to 자동, the entry removed).
    func setting(_ brain: ArisBrain, _ role: ArisModelRole, _ field: Field, to value: String?) -> ArisModelChoices {
        var next = entries
        next[Self.key(brain, role, field)] = value
        return ArisModelChoices(entries: next)
    }

    /// `self` over `saved`: an entry here wins, and "auto" here takes the saved one away.
    func merged(over saved: ArisModelChoices) -> ArisModelChoices {
        let both = saved.entries.merging(entries) { _, mine in mine }
        return ArisModelChoices(entries: both.filter { $0.value != Self.auto })
    }

    /// The choice with `role`'s model on `brain` back at 자동 (a model that stopped working, for one turn).
    func automaticModel(_ brain: ArisBrain, _ role: ArisModelRole) -> ArisModelChoices {
        setting(brain, role, .model, to: nil)
    }
}

/// aris-agent's last word from the app on the choices, for the work no request names. Set from each request of the app
/// itself; read by the drivers when they pick an effort, and by the one-shot helpers.
final class ArisModelChoiceBox: @unchecked Sendable {
    static let shared = ArisModelChoiceBox()

    private let lock = NSLock()
    private var value = ArisModelChoices.automatic

    var current: ArisModelChoices { lock.withLock { value } }

    /// True when it changed.
    @discardableResult
    func set(_ choices: ArisModelChoices) -> Bool {
        lock.withLock {
            guard value != choices else { return false }
            value = choices
            return true
        }
    }
}

// MARK: - The model and effort a turn uses

extension ArisThinking {
    /// The model a conversation turn or job of `brain` uses: the role's choice, else today's (`model(_:tier:)`).
    static func model(_ brain: ArisBrain, tier: ArisTier, task: Bool = false, choices: ArisModelChoices) -> String {
        choices.choice(brain, .of(tier: tier, task: task)).model ?? model(brain, tier: tier)
    }

    /// A job's model when the caller has its own 자동 (a schedule, a job moved to another brain): the 작업 choice, else it.
    static func jobModel(_ brain: ArisBrain, auto: String, choices: ArisModelChoices) -> String {
        choices.choice(brain, .job).model ?? auto
    }

    /// A one-shot helper's model (never a safety judge's): the 작은 도우미 choice, else the caller's own.
    static func helperModel(_ brain: ArisBrain, auto: String, choices: ArisModelChoices) -> String {
        choices.choice(brain, .helper).model ?? auto
    }

    /// A one-shot helper's effort: the 작은 도우미 choice, else low as today.
    static func helperEffort(_ brain: ArisBrain, choices: ArisModelChoices) -> String {
        choices.choice(brain, .helper).effort ?? "low"
    }

    /// Claude Code's effort for a turn of `tier` on a runner of `model`: the role's chosen effort; else, on a model the
    /// user chose for this role, the tier's own row of the table (an Opus chosen for 대화 answers a quick turn at low, not
    /// at the high Opus has as a look-up model); else today's (`claudeEffort(model:tier:)`).
    static func claudeEffort(model: String, tier: ArisTier, task: Bool, choices: ArisModelChoices) -> String {
        let choice = choices.choice(.claude, .of(tier: tier, task: task))
        if let effort = choice.effort { return effort }
        if let chosen = choice.model, chosen == model { return effort(tier).claude }
        return claudeEffort(model: model, tier: tier)
    }

    /// Codex's effort for a turn of `tier`: the role's chosen effort, else the table's.
    static func codexEffort(tier: ArisTier, task: Bool, choices: ArisModelChoices) -> String {
        choices.choice(.codex, .of(tier: tier, task: task)).effort ?? codexEffort(tier: tier)
    }
}
