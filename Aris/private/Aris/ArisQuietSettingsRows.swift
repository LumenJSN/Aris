//
//  ArisQuietSettingsRows.swift
//  Aris
//
//  The mute and quiet time in Settings › Aris › 알림, as two rows of the existing settings components: a switch for
//  the mute (the same one the notch and the ✦ menu flip), and the night hours as a choice, 23–7시 picked on a fresh
//  install. The settings pages are written in Korean, so these rows are too; ArisQuietCopy holds the English for the
//  day the pages are translated. Foundation only (tested).
//

import Foundation

enum ArisQuietSettingsRows {
    static func mute(_ muted: Bool, english: Bool = false) -> ArisSettingItem {
        ArisSettingItem(id: "aris.mute", icon: .symbol("speaker.slash"), title: ArisQuietCopy.muteTitle(english: english),
                        desc: ArisQuietCopy.muteDesc(english: english), control: .toggle(.muted, muted))
    }

    /// `stored`: the hours as the preference holds them; one that can't be read shows as the standard night.
    static func hours(_ stored: String, english: Bool = false) -> ArisSettingItem {
        let options = ArisQuietHours.choices.map { ArisSettingOption(id: $0, title: ArisQuietCopy.hoursLabel($0, english: english)) }
        return ArisSettingItem(id: "aris.quietHours", icon: .symbol("moon"), title: ArisQuietCopy.hoursTitle(english: english),
                               desc: ArisQuietCopy.hoursDesc(english: english),
                               control: .choice(.quietHours, options, selected: ArisQuietHours.choice(for: stored)))
    }
}
