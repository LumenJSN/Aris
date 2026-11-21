//
//  ArisModelChoiceRows.swift
//  Aris
//
//  설정 › AI 서비스 › 모델 고르기 as data: under the chosen brain, one row a role (대화, 깊은 일, 작업; 작은 도우미 under
//  고급), each with its model's dropdown (자동, the models the brain's tool lists, 직접 입력) and, where the brain takes it,
//  its 추론 수준's (자동, then the levels the tool lists). A plain function of the choices and the lists, so the view only
//  draws (ArisModelChoiceSection) and the tests read it. Foundation only (tested).
//

import Foundation

enum ArisModelChoiceRows {
    static let auto = ArisModelChoices.auto
    static let custom = "custom"
    /// The roles shown at once; 작은 도우미 waits under 고급.
    static let shown: [ArisModelRole] = [.conversation, .deep, .job]

    /// One role's row.
    struct Row: Equatable {
        let role: ArisModelRole
        let modelKey: String
        let models: [ArisSettingOption]
        let model: String
        /// Nil: this brain's effort isn't chosen here (agy's models carry their level).
        let effortKey: String?
        let efforts: [ArisSettingOption]
        let effort: String
    }

    /// The setting a dropdown writes: "claude.conversation.model".
    static func key(_ brain: ArisBrain, _ role: ArisModelRole, _ field: ArisModelChoices.Field) -> String {
        ArisModelChoices.key(brain, role, field)
    }

    /// Whether this brain's models are chosen here (an API brain's are its profile's, in its own row).
    static func offered(_ brain: ArisBrain) -> Bool { ArisModelChoices.brains.contains(brain) }

    /// The roles a brain's card lists (`advanced`: 고급 is open).
    static func roles(advanced: Bool) -> [ArisModelRole] { shown + (advanced ? [.helper] : []) }

    static func rows(_ brain: ArisBrain, choices: ArisModelChoices, lists: ArisModelLists, advanced: Bool, typing: Set<ArisModelRole> = []) -> [Row] {
        guard offered(brain) else { return [] }
        return roles(advanced: advanced).map { row(brain, $0, choices: choices, lists: lists, typing: typing.contains($0)) }
    }

    static func row(_ brain: ArisBrain, _ role: ArisModelRole, choices: ArisModelChoices, lists: ArisModelLists, typing: Bool = false) -> Row {
        let choice = choices.choice(brain, role)
        let listed = lists.options(brain, selected: [choice.model].compactMap { $0 })
        let models = [ArisSettingOption(id: auto, title: "자동", detail: autoModelLine(brain, role))]
            + listed.map { ArisSettingOption(id: $0.id, title: $0.title, detail: $0.unlisted == true ? "목록에 없는 모델" : $0.detail ?? ($0.title == $0.id ? nil : $0.id)) }
            + [ArisSettingOption(id: custom, title: "직접 입력", detail: "모델 이름을 써서 골라요")]
        let takesEffort = brain != .antigravity
        let efforts = takesEffort
            ? [ArisSettingOption(id: auto, title: "자동", detail: autoEffortLine(brain, role))]
                + levels(lists.efforts(brain, model: choice.model), chosen: choice.effort).map { ArisSettingOption(id: $0, title: effortTitle($0)) }
            : []
        let effort = takesEffort ? choice.effort ?? auto : auto
        return Row(role: role, modelKey: key(brain, role, .model), models: models, model: typing ? custom : choice.model ?? auto,
                   effortKey: takesEffort ? key(brain, role, .effort) : nil, efforts: efforts, effort: effort)
    }

    /// The levels the tool lists, and a chosen one it doesn't (kept, as a chosen model is), in the CLIs' order.
    static func levels(_ listed: [String], chosen: String?) -> [String] {
        guard let chosen, !listed.contains(chosen) else { return listed }
        return ArisModelChoices.effortWords.filter { listed.contains($0) || $0 == chosen }
    }

    // MARK: - 자동, in words

    /// The model 자동 picks for the role today (ArisThinking, ArisBrain), as the dropdown's line under 자동.
    static func autoModels(_ brain: ArisBrain, _ role: ArisModelRole) -> [String] {
        switch role {
        case .conversation:
            return Array(Set([ArisTier.quick, .work].map { ArisThinking.model(brain, tier: $0) })).sorted()
        case .deep, .job:
            return [ArisThinking.model(brain, tier: .deep)]
        case .helper:
            return [brain.model(tier: .quick)]
        }
    }

    static func autoModelLine(_ brain: ArisBrain, _ role: ArisModelRole) -> String {
        "지금은 " + autoModels(brain, role).joined(separator: ", ")
    }

    static func autoEffortLine(_ brain: ArisBrain, _ role: ArisModelRole) -> String {
        switch role {
        case .conversation: return "말로 묻는 짧은 질문은 낮음, 여러 단계 일은 보통"
        case .deep, .job: return "높음"
        case .helper: return "낮음"
        }
    }

    static func effortTitle(_ level: String) -> String {
        switch level {
        case "minimal": return "최소"
        case "low": return "낮음"
        case "medium": return "보통"
        case "high": return "높음"
        case "xhigh": return "아주 높음"
        case "max": return "최대"
        case "ultra": return "울트라"
        default: return level
        }
    }

    // MARK: - The lines under the card

    /// Where the list came from and when. `installed`: whether the brain's tool is on this Mac, as the helper last said
    /// (ArisBrainSetup.ready; nil before it answered): one that isn't is said so, never "didn't give its list" (fourth VM
    /// run, Claude Code not installed).
    static func source(_ brain: ArisBrain, lists: ArisModelLists, installed: Bool? = nil) -> String {
        let tool: String
        switch brain {
        case .claude: tool = "Claude Code"
        case .codex: tool = "Codex"
        default: tool = "Antigravity"
        }
        if installed == false { return "\(tool)가 이 Mac에 설치되어 있지 않아 기본 이름만 보여요" }
        guard let list = lists.lists[brain.rawValue] else { return "모델 목록을 확인하는 중이에요" }
        return list.fromTool ? "\(tool)가 알려 준 모델이에요" : "\(tool)에서 목록을 받지 못해 기본 이름만 보여요"
    }

    /// The line under the card: the note and where the list came from, each looked up whole and then joined. Joined
    /// first, the source's "%@에서 목록을 받지 못해…" took the whole note as its name, so on an English Mac the note
    /// stayed Korean beside an English source (third VM run, Talking to Aris › AI · Model).
    static func footer(_ brain: ArisBrain, lists: ArisModelLists, installed: Bool? = nil, wording: ArisSettingsWording) -> String {
        [note, source(brain, lists: lists, installed: installed)].map { wording.dotted($0) }.joined(separator: " · ")
    }

    static let heading = "모델 고르기"
    static let note = "자동은 지금처럼 Aris가 일에 맞게 골라요. 고른 모델을 쓸 수 없게 되면 그 답만 자동으로 하고 알려 드려요."
    static let advancedTitle = "고급 설정"
    static let advancedDesc = "작은 도우미의 모델과 추론 수준"
    static let fieldHint = "모델 이름 (예: claude-opus-5-5)"
    static let checking = "확인하는 중…"
    static let checkButton = "확인"
    static let effortLabel = "추론 수준"
    static let badShape = "모델 이름에는 영문, 숫자, - . _ : / 만 쓸 수 있어요."
}
