//
//  ArisSettingsSlots.swift
//  Aris
//
//  The places option A keeps for rows other branches are building (settings-ia/OPTIONS.md). Each slot is empty here
//  and sits in its part already; its owner fills it with a one-line change (and adds the row's search entry to
//  ArisSettingsIndex with its old page, which lands it in this part: ArisSettingsParts.slots). Foundation only (tested).
//

import Foundation

enum ArisSettingsSlots {
    /// jv-wake (landed): the wake-word name field under “아리스”라고 부르기; why the wake word is or is not listening is
    /// that row's own line (ArisWakeStatus).
    static func wakeRows(_ s: ArisSettingsSnapshot) -> [ArisSettingItem] { [ArisWakeNameRows.row(name: s.wakeName)] }

    /// 다른 AI로 넘기기 (ArisBrainFallbackSetting), off by default, under 답하는 AI in its own small section.
    static func fallback(_ s: ArisSettingsSnapshot) -> ArisSettingSection {
        ArisSettingSection(id: ArisSettingsViewSlots.fallback, heading: "안 될 때", grouped: true, rows: [
            ArisSettingItem(id: "ai.fallback", icon: .symbol("arrow.triangle.branch"), title: "다른 AI로 넘기기",
                            desc: s.brainFallback ? "고른 AI가 한도에 닿거나 이 Mac에 없으면 다른 AI가 대신 답해요."
                                                  : "꺼 두면 고른 AI만 답해요. 안 될 때는 왜 안 되는지 말해요.",
                            control: .toggle(.brainFallback, s.brainFallback)),
        ])
    }

    /// jv-trust (later): "how much Aris asks", three positions, and its standing permissions, in 컴퓨터 제어 before 묻지
    /// 않고 하는 일 (section id "control.trust").
    static func trust(_ s: ArisSettingsSnapshot) -> [ArisSettingSection] { [] }

    /// jv-perms (landed): the one list of permissions with live state, in 앱 › 권한: every permission a setting can ask
    /// for (the microphone, speech recognition, Accessibility, Input Monitoring, Screen Recording, Full Disk Access and
    /// the folders, as ArisLiveSettings reads them; speech recognition and Input Monitoring ask through
    /// ArisPermissionCenter), then system audio, Reminders and Calendar, the rows the other pages held.
    static func permissions(_ s: ArisSettingsSnapshot) -> [ArisSettingItem] {
        ArisSettingsBuilder.permissionRows(s.permissions) + [ArisSettingsBuilder.systemAudioRow(s),
                                                             ArisSettingsBuilder.remindersAccessRow(s), ArisSettingsBuilder.calendarAccessRow(s)]
    }

    /// 노치에 설정 아이콘 (#89): the notch draws the icon it promises (jv-appbugs), so the row is shown. The flag stays for the
    /// tests that pin both states.
    static let settingsIconWired = true

    static func settingsIconRow(_ s: ArisSettingsSnapshot) -> [ArisSettingItem] {
        guard settingsIconWired else { return [] }
        return [ArisSettingItem(id: "look.settingsIcon", icon: .symbol("gearshape"), title: "노치에 설정 아이콘", desc: "열린 노치 위에 설정으로 가는 작은 아이콘을 보여요.",
                                control: .toggle(.settingsIcon, s.settingsIcon))]
    }
}

/// The views' own slots in AI · 모델 (drawn by ArisLiveSettings, not built as rows): their owners replace these lines.
enum ArisSettingsViewSlots {
    /// jv-models: the per-role model and effort pickers (대화, 깊은 일, 작업, and the small helper folded), under 답하는 AI
    /// (view id "ai.models": ArisModelChoiceSection).
    static let models = "ai.models"
    /// 다른 AI로 넘기기's section under 답하는 AI (ArisSettingsSlots.fallback), drawn by the AI view from the builder's sections.
    static let fallback = "ai.fallbackSection"
}
