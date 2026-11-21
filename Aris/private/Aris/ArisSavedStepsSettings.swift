//
//  ArisSavedStepsSettings.swift
//  Aris
//
//  설정 › 기억 › 저장된 단계: the desktop tasks Aris saved to do again without the AI (the agent's saved steps), one row
//  per request with its steps, each with 지우기. The agent words each step in both languages; the rows are plain
//  functions of the snapshot. Foundation only (tested).
//

import Foundation

/// One saved request as the agent's POST /memory {"op": "savedSteps"} gives it.
struct ArisSavedStepsItem: Decodable, Equatable, Identifiable, Sendable {
    let key: String
    /// The words as the user said them.
    let request: String
    let steps: [String]
    let stepsEn: [String]
    let apps: String
    let saved: String
    /// Learned in a conversation that read app windows: the row says so.
    var outside: Bool? = nil
    /// A procedure he taught by showing it once (ArisTaughtRoute): it can be renamed too.
    var taught: Bool? = nil
    var id: String { key }
}

enum ArisSavedStepsSettingsRows {
    static let heading = "저장된 단계"
    static let note = "앱에서 한 일을 AI 없이 다시 할 수 있게 저장해 둔 것이에요. 같은 말을 하면 단계마다 다시 확인하고, 카드가 필요한 단계는 카드를 띄워요. 보내기·지우기·결제·비밀번호는 저장하지 않아요."
    static let emptyTitle = "저장된 단계가 없어요"
    static let emptyDesc = "앱에서 한 일이 다시 할 수 있는 단계로만 되어 있으면 여기에 모여요"
    static let forget = "지우기"
    static let forgotToast = "저장된 단계를 지웠어요"
    /// The second press (fifth VM run, M1), as 배운 것 모두 지우기 asks it.
    static let cancel = "취소"
    static let really = "정말 지우기"
    static let forgetAsk = "지우면 되돌릴 수 없어요. 정말 지울까요?"
    /// 정말 지우기 takes a press only this long after it came up (sixth VM run, item 6b: it comes up right under the
    /// pointer, where 지우기 was, so the second click of a double-click deleted without a second decision).
    static let confirmGrace: TimeInterval = 0.6

    /// Whether a press on 정말 지우기 counts: only once it has been up for `confirmGrace`.
    static func confirmCounts(since shown: Date?, now: Date) -> Bool {
        guard let shown else { return false }
        return now.timeIntervalSince(shown) >= confirmGrace
    }
    static let stepsWord = "단계"
    /// The mark before the steps of one learned in a conversation that read app windows.
    static let outsideMark = "앱 화면을 읽은 대화에서 저장됨"
    /// A taught procedure's row (fourth VM run: what he taught was nowhere here): 이름 바꾸기 turns it into a field.
    static let rename = "이름 바꾸기"
    static let renameSave = "저장"
    static let renamePlaceholder = "새 이름"
    static let renamedToast = "이름을 바꿨어요"
    static let taughtMark = "보여 주고 가르친 것"

    /// Why a new name wasn't taken.
    enum RenameProblem: Equatable {
        /// Another taught procedure or a routine has it.
        case taken
        /// The helper didn't do it.
        case failed

        var line: String {
            switch self {
            case .taken: "그 이름은 이미 있어요. 다른 이름을 써 주세요."
            case .failed: "이름을 바꾸지 못했어요. 바뀐 건 없어요."
            }
        }
    }

    static let english: [String: String] = [
        heading: "Saved steps",
        note: "Desktop tasks saved so Aris can do them again without the AI. Saying the same words checks every step again and shows a card where a step needs one. Sending, deleting, paying and passwords are never saved.",
        emptyTitle: "No saved steps",
        emptyDesc: "They gather here when a task in an app was done with steps that can be done again",
        forget: "Delete",
        forgotToast: "Saved steps deleted",
        really: "Really delete",
        forgetAsk: "This can't be undone. Delete it?",
        outsideMark: "Saved in a conversation that read app windows",
    ]

    /// A recipe's small line: its steps in order (the UI's language), and the apps.
    static func describe(_ item: ArisSavedStepsItem, english: Bool) -> String {
        let steps = english ? item.stepsEn : item.steps
        let count = english ? "\(steps.count) step\(steps.count == 1 ? "" : "s")" : "\(steps.count)\(stepsWord)"
        let line = count + " · " + steps.prefix(4).joined(separator: " → ") + (steps.count > 4 ? " …" : "")
        if item.taught == true { return (english ? ArisSettingsCopy.english(taughtMark) ?? taughtMark : taughtMark) + " · " + line }
        guard item.outside == true else { return line }
        return (english ? Self.english[outsideMark] ?? outsideMark : outsideMark) + " · " + line
    }

    static func sections(_ s: ArisSettingsSnapshot, english: Bool = ArisUILanguage.english) -> [ArisSettingSection] {
        var rows: [ArisSettingItem] = []
        if let items = s.savedSteps, !items.isEmpty {
            rows = items.map { item in
                ArisSettingItem(id: "memory.saved.\(item.key)", icon: .symbol(item.taught == true ? "hand.point.up.left" : "list.bullet.rectangle"),
                                title: "“\(item.request)”", desc: desc(item, s, english: english), control: control(item, s), indexed: false)
            }
        } else if s.savedSteps != nil {
            rows = [ArisSettingItem(id: "memory.saved.none", icon: .none, title: emptyTitle, desc: emptyDesc, control: .empty, indexed: false)]
        }
        guard !rows.isEmpty else { return [] }
        return [ArisSettingSection(id: "memory.saved", heading: heading, note: note, grouped: true, rows: rows)]
    }

    /// The steps, or why the new name wasn't taken while it is being typed.
    private static func desc(_ item: ArisSavedStepsItem, _ s: ArisSettingsSnapshot, english: Bool) -> String {
        if s.savedStepsConfirming == item.key { return english ? Self.english[forgetAsk] ?? forgetAsk : forgetAsk }
        guard s.savedStepsRenaming == item.key, let problem = s.savedStepsRenameProblem else { return describe(item, english: english) }
        return problem.line
    }

    /// 지우기, and for a taught procedure 이름 바꾸기 first; while it is renamed, the name field and its 저장.
    private static func control(_ item: ArisSavedStepsItem, _ s: ArisSettingsSnapshot) -> ArisSettingControl {
        // 지우기 pressed once: 취소 and 정말 지우기, nothing gone yet.
        if s.savedStepsConfirming == item.key {
            return .buttons([ArisSettingButton(title: cancel, action: .keepSavedSteps),
                             ArisSettingButton(title: really, action: .forgetSavedSteps(item.key), kind: .danger)])
        }
        let delete = ArisSettingButton(title: forget, action: .forgetSavedSteps(item.key))
        guard item.taught == true else { return .buttons([delete]) }
        guard s.savedStepsRenaming == item.key else {
            return .buttons([ArisSettingButton(title: rename, action: .renameSavedSteps(item.key)), delete])
        }
        let typed = s.savedStepsName.trimmingCharacters(in: .whitespacesAndNewlines)
        return .field(.savedStepsName, text: s.savedStepsName, placeholder: renamePlaceholder,
                      ArisSettingButton(title: renameSave, action: .saveSavedStepsName(item.key), kind: .primary, enabled: !typed.isEmpty))
    }
}
