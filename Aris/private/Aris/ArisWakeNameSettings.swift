//
//  ArisWakeNameSettings.swift
//  Aris
//
//  Settings › 부르기 › 부를 이름: the name that wakes Aris (ArisWakeName), one row with the window's text field and a
//  button that puts "아리스" back, as 부르는 이름 in 일반 has. Saved as it is typed. Foundation only (tested).
//

import Foundation

enum ArisWakeNameRows {
    static let rowID = "aris.wakeName"
    static let title = "부를 이름"
    static let desc = "이 이름을 부르면 들어요."
    static let reset = "기본값"

    /// The field shows the default name in the UI's language ("Aris" in the English window: it showed "아리스", VM run
    /// 2026-11-18); either spelling is the default (ArisWakeName).
    static func row(name: String, english: Bool = ArisUIWords.english) -> ArisSettingItem {
        let shown = ArisWakeName(name: name).isDefault ? ArisWakeName.defaultName(english: english) : name
        return ArisSettingItem(id: rowID, icon: .symbol("id-card"), title: title, desc: desc,
                        control: .field(.wakeName, text: shown, placeholder: ArisWakeName.defaultName(english: english),
                                        ArisSettingButton(title: reset, action: .resetWakeName, enabled: !ArisWakeName(name: name).isDefault)))
    }

    static let english: [String: String] = [
        title: "Wake name",
        desc: "Aris listens when you call this name.",
        reset: "Default",
    ]
}
