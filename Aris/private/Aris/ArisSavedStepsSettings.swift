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
    var id: String { key }
}

enum ArisSavedStepsSettingsRows {
    static let heading = "저장된 단계"
    static let note = "앱에서 한 일을 AI 없이 다시 할 수 있게 저장해 둔 것이에요. 같은 말을 하면 단계마다 다시 확인하고, 카드가 필요한 단계는 카드를 띄워요. 보내기·지우기·결제·비밀번호는 저장하지 않아요."
    static let emptyTitle = "저장된 단계가 없어요"
    static let emptyDesc = "앱에서 한 일이 다시 할 수 있는 단계로만 되어 있으면 여기에 모여요"
    static let forget = "지우기"
    static let forgotToast = "저장된 단계를 지웠어요"
    static let stepsWord = "단계"
    /// The mark before the steps of one learned in a conversation that read app windows.
    static let outsideMark = "앱 화면을 읽은 대화에서 저장됨"

    static let english: [String: String] = [
        heading: "Saved steps",
        note: "Desktop tasks saved so Aris can do them again without the AI. Saying the same words checks every step again and shows a card where a step needs one. Sending, deleting, paying and passwords are never saved.",
        emptyTitle: "No saved steps",
        emptyDesc: "They gather here when a task in an app was done with steps that can be done again",
        forget: "Delete",
        forgotToast: "Saved steps deleted",
        outsideMark: "Saved in a conversation that read app windows",
    ]

    /// A recipe's small line: its steps in order (the UI's language), and the apps.
    static func describe(_ item: ArisSavedStepsItem, english: Bool) -> String {
        let steps = english ? item.stepsEn : item.steps
        let count = english ? "\(steps.count) step\(steps.count == 1 ? "" : "s")" : "\(steps.count)\(stepsWord)"
        let line = count + " · " + steps.prefix(4).joined(separator: " → ") + (steps.count > 4 ? " …" : "")
        guard item.outside == true else { return line }
        return (english ? Self.english[outsideMark] ?? outsideMark : outsideMark) + " · " + line
    }

    static func sections(_ s: ArisSettingsSnapshot, english: Bool = ArisUILanguage.english) -> [ArisSettingSection] {
        var rows: [ArisSettingItem] = []
        if let items = s.savedSteps, !items.isEmpty {
            rows = items.map { item in
                ArisSettingItem(id: "memory.saved.\(item.key)", icon: .symbol("list.bullet.rectangle"), title: "“\(item.request)”",
                                desc: describe(item, english: english),
                                control: .buttons([ArisSettingButton(title: forget, action: .forgetSavedSteps(item.key))]), indexed: false)
            }
        } else if s.savedSteps != nil {
            rows = [ArisSettingItem(id: "memory.saved.none", icon: .none, title: emptyTitle, desc: emptyDesc, control: .empty, indexed: false)]
        }
        guard !rows.isEmpty else { return [] }
        return [ArisSettingSection(id: "memory.saved", heading: heading, note: note, grouped: true, rows: rows)]
    }
}
