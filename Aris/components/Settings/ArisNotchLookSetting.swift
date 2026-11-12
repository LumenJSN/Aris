//
//  ArisNotchLookSetting.swift
//  Aris
//
//  The notch's look in Settings › 노치, rows at the end of the 위 노치 card: 테마 (ArisNotchTheme, a menu of its
//  names, as the page's other choices are), 글자 뒤 받침 (ArisTextBacking) and 쉬는 동안 별 보이기 (ArisRestStar).
//  Written in Korean as every row is, with their English beside them (ArisSettingsCopyMore). Foundation only (tested).
//

import Foundation

enum ArisNotchLookSetting {
    static let themeID = "notch.theme"
    static let themeTitle = "테마"
    static let themeDesc = "고른 모양은 다음에 노치가 열릴 때 바뀌어요."
    static let backingID = "notch.textBacking"

    static let backingTitle = "글자 뒤 받침"
    static let backingDesc = "밝은 창 위에서도 작은 글씨가 잘 보이게 받쳐 줘요."
    static let restStarID = "notch.restStar"
    static let restStarTitle = "쉬는 동안 별 보이기"
    static let restStarDesc = "할 일이 없을 때도 닫힌 노치에서 별이 잠들어 있어요."

    /// `theme`: ArisNotchTheme's raw value, or "" when the stored preferences make none of them.
    static func rows(theme: String, backing: Bool, restStar: Bool) -> [ArisSettingItem] {
        [
            ArisSettingItem(id: themeID, icon: .symbol("paintpalette"), title: themeTitle, desc: themeDesc, control: .menu(.notchTheme, ArisNotchTheme.allCases.map { .init(id: $0.rawValue, title: $0.title) }, selected: theme)),
            ArisSettingItem(id: backingID, icon: .symbol("textformat"), title: backingTitle, desc: backingDesc, control: .toggle(.textBacking, backing)),
            ArisSettingItem(id: restStarID, icon: .symbol("moon.zzz"), title: restStarTitle, desc: restStarDesc, control: .toggle(.restStar, restStar)),
        ]
    }

    /// The search's entries for the rows.
    static let entries = [
        ArisSettingsEntry(id: themeID, page: .notch, title: themeTitle,
                          keywords: ["테마", "모양", "유리", "투명", "검정", "밝은", "색", "노치 모양", "theme", "look", "glass"]),
        ArisSettingsEntry(id: backingID, page: .notch, title: backingTitle,
                          keywords: ["받침", "글자", "글씨", "잘 안 보여", "대비", "가독성", "밝은 창", "그림자", "contrast", "readable"]),
        ArisSettingsEntry(id: restStarID, page: .notch, title: restStarTitle,
                          keywords: ["별", "캐릭터", "잠", "자는 별", "쉬는 동안", "닫힌 노치", "숨기기", "star", "sleep"]),
    ]

    /// The rows' English, by their Korean (ArisSettingsCopyMore).
    static let english: [String: String] = [
        themeTitle: "Theme", themeDesc: "The look you pick shows the next time the notch opens.",
        backingTitle: "Text backing", backingDesc: "Puts a soft dark patch behind small text so it reads over bright windows.",
        restStarTitle: "Show the star while resting", restStarDesc: "The star sleeps in the closed notch even when nothing is going on.",
    ]

    /// A theme's English in the menu, by the theme itself rather than its Korean: 기본 is "default" elsewhere in the
    /// settings catalog, and here it is the theme "Default" (ArisSettingsWording asks this first).
    static func optionEnglish(_ key: ArisSettingKey, id: String) -> String? {
        key == .notchTheme ? ArisNotchTheme(rawValue: id)?.englishTitle : nil
    }
}
