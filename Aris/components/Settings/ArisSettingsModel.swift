//
//  ArisSettingsModel.swift
//  Aris
//
//  What a settings page is made of, as plain values: sections of rows, each row an icon, a title, a line under it and
//  one control. ArisSettingsBuilder fills them from a snapshot of the settings; ArisSettingsPageView draws them, one
//  card a section (ArisSettingsLayout). Foundation only (tested).
//

import Foundation

enum ArisSettingIcon: Equatable {
    case symbol(String)
    /// A list's or calendar's colour ("#RRGGBB").
    case dot(String)
    /// A permission's state: green when granted.
    case status(Bool)
    /// A service's logo (UsageLogo's id).
    case logo(String)
    case none
}

struct ArisSettingOption: Equatable {
    let id: String
    let title: String
    var detail: String?
}

enum ArisSettingButtonKind: Equatable { case ghost, primary, danger, solidRed }

struct ArisSettingButton: Equatable {
    let title: String
    let action: ArisSettingsAction
    var kind = ArisSettingButtonKind.ghost
    var enabled = true
}

/// A value a control writes.
enum ArisSettingKey: Hashable {
    case wakeWord, minutes, sounds, brain, computerEngine, cloud, speed, silence, bargeInSpeakers
    case dayEndOffer
    /// Aris's mute, and the night hours of quiet time (ArisQuiet).
    case muted, quietHours
    /// The night hours' own start and end, each a time of the day ("22:30": ArisQuietSpan).
    case quietStart, quietEnd
    /// The terminal a Claude Code teammate opens in ("auto" or ArisTerminal's raw value).
    case teammateTerminal
    /// Dictation: polish through a brain when the Mac can't; the writing style for an app kind (ArisAppKind raw value).
    case dictationBrainPolish, dictationStyle(String)
    case todoList(String), todoDefault, newListName
    case calendar(String), allDay, joinMeeting, openIn
    case seesScreen, circle
    case autoMemory, memoryQuery
    /// 한 일에서 배우기 (the agent's work memory: ArisWorkSettingsRows).
    case workMemory
    case hover, haptics, gestures, heightMode, notchHeight
    /// A side notch's tab showing or not (ArisSideTab's raw value).
    case sideTab(String)
    case theme, accentCustom, reduceMotion, settingsIcon, alwaysTabs
    /// The notch's look (ArisNotchLookSetting): its theme (ArisNotchTheme's raw value), the text backing and the star at rest.
    case notchTheme, textBacking, restStar
    case login, displayMode, screen, appLanguage, userName
    /// The notch, music and shelf rows (ArisMoreSettings).
    case more(ArisMoreKey)
    /// The API brain row's dropdowns: "provider", "quick" or "strong" (ArisAPIBrainModel).
    case apiBrain(String)
    /// What the closed notch's Claude ring shows (ClaudeRingMode's raw value).
    case claudeRing
}

enum ArisSettingValue: Equatable {
    case bool(Bool), text(String), number(Double)
}

/// Something a row does that isn't setting a value.
enum ArisSettingsAction: Equatable {
    case trainVoice, listen, editWords, voicePicker, addLanguage, removeLanguage(String)
    case remindersAccess, createList, calendarRefresh, calendarAccess, internetAccounts
    case permission(String), revokeStanding(String)
    case forgetMemory(String), confirmMemory(String), forgetAllMemories, keepMemories, clearMemoryQuery
    /// 일하면서 배운 것: one lesson forgotten, all of it (asked twice), or kept after all.
    case forgetWorkLesson(Int), forgetAllWork, keepWork
    /// 다른 AI에서 가져오기: the import sheet opens (ArisMemoryImportSheet).
    case importMemory
    /// Forgets every learned suggestion for dropped files (ArisDropLearned).
    case forgetDropHabits
    case unhideSides, go(ArisSettingsPage, anchor: String?)
    case export, diagnostics, wipe, uninstall
    case onboarding, restart, quit, openFolder, clearName
    case accent(String?), pickAccent
    /// A slider's drag began (true) or ended.
    case sliding(ArisSettingKey, Bool)
    /// Clears the named shortcut.
    case clearShortcut(String)
    case recheckNowPlaying
    /// Dictation's learned words: add a proposed one, dismiss it, or delete a learned one.
    case learnWord(String), dismissWord(String), forgetWord(String)
}

enum ArisChipTone: Equatable { case plain, ok, warn }

enum ArisSettingControl: Equatable {
    case none
    case toggle(ArisSettingKey, Bool, enabled: Bool = true)
    /// A segmented control; `lead` is a button before it (들어 보기).
    case choice(ArisSettingKey, [ArisSettingOption], selected: String, disabled: [String] = [], lead: ArisSettingButton? = nil)
    case menu(ArisSettingKey, [ArisSettingOption], selected: String)
    case buttons([ArisSettingButton])
    /// A green dot when `ok`, and a button.
    case status(ok: Bool, ArisSettingButton?)
    /// A shortcut that can be changed, shown as caps (KeyboardShortcuts' name).
    case shortcut(name: String, caps: [String])
    /// Caps that can't be changed.
    case caps([String])
    /// The whole row is a button with a chevron, and the current value before it.
    case link(ArisSettingsAction, value: String?)
    /// A range slider that moves in steps of `step` (whole numbers unless said); its value is written beside it with
    /// `unit`, or as `zero` at 0 ("바로").
    case slider(ArisSettingKey, value: Double, min: Double, max: Double, unit: String, step: Double = 1, zero: String? = nil)
    case chip(String, tone: ArisChipTone)
    /// Plain small words at the row's end, for a state that needs nothing done (허용됨).
    case said(String)
    /// Not a setting: the card has nothing to list yet. The title is drawn centred in the second ink, the line under
    /// it smaller (plain centred text).
    case empty
    /// Not a setting: the list is on its way. The title shimmers (2.4 s sweep; still under Reduce Motion).
    case loading
    case field(ArisSettingKey, text: String, placeholder: String, ArisSettingButton)
    /// A control at the row's end drawn by the app (the voice picker).
    case trailing(String)
    /// The whole row drawn by the app (an API key, the about card).
    case custom(String)
}

/// What sits under a row's text.
enum ArisSettingExtra: Equatable {
    case none
    /// Removable chips (the languages: code and title).
    case chips([ArisSettingOption], removable: Bool)
    /// The accent colours, and the one picked.
    case swatches([String], selected: String?)
}

struct ArisSettingItem: Identifiable, Equatable {
    let id: String
    var icon: ArisSettingIcon
    let title: String
    var desc: String?
    var control: ArisSettingControl
    var extra = ArisSettingExtra.none
    /// The row destroys something. It is drawn like any other row: the red is on its button alone (item 13).
    var danger = false
    /// False for rows the index finds elsewhere (a link to another page's setting, one row of a list).
    var indexed = true
}

/// A section that is one line until it is pressed (the owner's pick 7-A, the notch page's rarely used groups): its name,
/// what is inside in a few words, and an icon. Open or closed is remembered (ArisSettingsFolds).
struct ArisSettingFold: Equatable {
    let title: String
    let desc: String
    let symbol: String
}

struct ArisSettingSection: Identifiable, Equatable {
    let id: String
    var heading: String?
    var note: String?
    /// Every section is one card now; kept so a section written the old way (`grouped: true`) still builds.
    var grouped = false
    var rows: [ArisSettingItem]
    /// Set: the card shows this one line, and its rows only while it is open.
    var fold: ArisSettingFold?
}

/// Where a range slider lands: dragged to a point along its track, or moved one step by VoiceOver.
enum ArisSliderStep {
    /// The value at `fraction` (0…1) of the track, on a step and inside the range.
    static func value(at fraction: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let t = min(max(fraction, 0), 1)
        return snap(range.lowerBound + t * (range.upperBound - range.lowerBound), in: range, step: step)
    }

    /// One step up or down from `value`.
    static func nudge(_ value: Double, up: Bool, in range: ClosedRange<Double>, step: Double) -> Double {
        snap(value + (up ? step : -step), in: range, step: step)
    }

    /// Steps count from the bottom of the range (0.1, 0.2 … from 0.1), and the float noise is cut (0.30000004 → 0.3).
    static func snap(_ value: Double, in range: ClosedRange<Double>, step: Double) -> Double {
        let steps = ((value - range.lowerBound) / step).rounded()
        let snapped = ((range.lowerBound + steps * step) * 1_000_000).rounded() / 1_000_000
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    /// The value as it is written beside the slider: "0.3초", "38pt", or `zero` at 0.
    static func label(_ value: Double, step: Double, unit: String, zero: String? = nil) -> String {
        if value == 0, let zero { return zero }
        return spoken(value, step: step) + unit
    }

    /// What VoiceOver reads: whole numbers for whole steps, else one decimal.
    static func spoken(_ value: Double, step: Double) -> String {
        step >= 1 ? "\(Int(value.rounded()))" : String(format: "%.1f", value)
    }
}

enum ArisSettingsLayout {
    enum Block: Equatable {
        case group([ArisSettingItem])
    }

    /// Every section is one card with its rows split by hairlines (the owner's pick 2-B, the shape of the AI 서비스 page),
    /// whatever its rows are and however it was written: a switch, a menu or a button added to a section's rows
    /// takes its place in the card with no case of its own.
    static func blocks(_ section: ArisSettingSection) -> [Block] {
        section.rows.isEmpty ? [] : [.group(section.rows)]
    }

    /// The folded section that holds `id` (the section itself, or one of its rows): a search that lands there opens it first.
    static func fold(holding id: String, in sections: [ArisSettingSection]) -> String? {
        sections.first { $0.fold != nil && ($0.id == id || $0.rows.contains { $0.id == id }) }?.id
    }

    /// The folds that are open, as they are kept between launches and read back (ids, in order; anything else is none).
    static func openFolds(stored: Any?) -> Set<String> { Set((stored as? [String]) ?? []) }
    static func stored(openFolds: Set<String>) -> [String] { openFolds.sorted() }

    /// Every tag a page's view carries for `sections` (ArisSettingsPageView): each section, each row.
    static func tags(_ sections: [ArisSettingSection]) -> Set<String> {
        Set(sections.flatMap { [$0.id] + $0.rows.map(\.id) })
    }
}
