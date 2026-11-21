//
//  ArisLabsSetting.swift
//  Aris
//
//  실험 기능 under 할 수 있는 일 › 컴퓨터 제어: the helper's experimental switches (ArisExperimentSwitch) as rows the app owns.
//  Core 2 (the clean-slate core, ARCHITECTURE Part 2) and 보여 주고 가르치기 (F3, which needs Core 2), both off until
//  The user turns them on. The app stores them in its own defaults and sends them to the helper with every /health, /warm
//  and /ask (ArisAgentClient.switches); a `defaults write` never reached the helper (VM run 2026-11-19, D2). "실험",
//  "Core 2", "코어" or "가르치기" finds them. Foundation only.
//

import Foundation

enum ArisLabsSetting {
    static let sectionID = "control.labs"
    static let heading = "실험 기능"
    static let note = "아직 시험 중인 기능이에요. 켜면 다음 질문부터 적용돼요."

    static let core2ID = "control.core2"
    static let core2Title = "새 코어 (Core 2)"
    static let core2Detail = "Aris가 직접 도구를 다루고, 모든 동작을 한 기준으로 판단해 기록하고 되돌릴 수 있게 해요."
    static let core2Keywords = "실험, 실험 기능, 코어, 새 코어, core 2, core2, 판단, 기록, 되돌리기, labs, experimental"

    static let teachID = "control.teach"
    static let teachTitle = "보여 주고 가르치기"
    static let teachDetail = "새 코어를 켠 채로 한 번 해 보이면, 이름을 붙여 저장하고 그 이름으로 다시 해요."
    static let teachKeywords = "실험, 실험 기능, 가르치기, 보여 주기, 따라 하기, 녹화, 루틴, teach, show it once, labs"

    static func section(core2: Bool, teach: Bool) -> ArisSettingSection {
        ArisSettingSection(id: sectionID, heading: heading, note: note, rows: [
            ArisSettingItem(id: core2ID, icon: .symbol("cpu"), title: core2Title, desc: core2Detail, control: .toggle(.core2, core2)),
            ArisSettingItem(id: teachID, icon: .symbol("mouse-pointer-click"), title: teachTitle, desc: teachDetail, control: .toggle(.teach, teach)),
        ])
    }

    static func words(_ keywords: String) -> [String] {
        keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static let core2Entry = ArisSettingsEntry(id: core2ID, page: .control, title: core2Title, keywords: words(core2Keywords))
    static let teachEntry = ArisSettingsEntry(id: teachID, page: .control, title: teachTitle, keywords: words(teachKeywords))
}
