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

    /// Drawn as an app-icon tile (36) rather than a bare 20-pt glyph.
    var isTile: Bool { if case .logo = self { true } else { false } }
}

struct ArisSettingOption: Equatable {
    let id: String
    let title: String
    var detail: String?
}

/// `select`: the measured settings select (a choice that opens a picker: 쓰는 언어), drawn as ArisSettingSelect.
enum ArisSettingButtonKind: Equatable {
    case ghost, primary, danger, solidRed, select

    /// How a button of `kind` is drawn: a red one that can't be pressed is drawn plain, since red at half strength read
    /// as pressable (VM run 2026-11-18: 모두 지우기 looked ready with nothing learned).
    static func drawn(_ kind: ArisSettingButtonKind, enabled: Bool) -> ArisSettingButtonKind {
        !enabled && (kind == .danger || kind == .solidRed) ? .ghost : kind
    }
}

struct ArisSettingButton: Equatable {
    let title: String
    let action: ArisSettingsAction
    var kind = ArisSettingButtonKind.ghost
    var enabled = true
}

/// A value a control writes.
enum ArisSettingKey: Hashable {
    case wakeWord, minutes, sounds, brain, computerEngine, speed, silence, bargeInSpeakers
    /// 다른 AI로 넘기기 (ArisBrainFallbackSetting).
    case brainFallback
    case dayEndOffer
    /// 하루 정리를 자세히 말하기: the day in review (ArisRecapSwitch, `arisRecap`).
    case recap
    /// Aris's mute, and the night hours of quiet time (ArisQuiet).
    case muted, quietHours
    /// The night hours' own start and end, each a time of the day ("22:30": ArisQuietSpan).
    case quietStart, quietEnd
    /// The terminal a Claude Code teammate opens in ("auto" or ArisTerminal's raw value).
    case teammateTerminal
    /// 받아쓰기 쓰기: dictation as a whole (ArisDictationSwitch).
    case dictationOn
    /// Dictation: polish through a brain when the Mac can't; the writing style for an app kind (ArisAppKind raw value).
    case dictationBrainPolish, dictationStyle(String)
    /// 들은 말 다듬기: a fast model repairs what the recogniser misheard (ArisHeardRepair).
    case hearRepair
    /// 마이크: which microphone Aris listens through (ArisMicSetting's stored value).
    case microphone
    /// Dictation in the pill at the bottom of the screen (the notch stays quiet for it); its idle sliver between dictations.
    case dictationPill, dictationPillIdle
    case todoList(String), todoDefault, newListName
    /// 저장된 단계: the new name typed for a taught procedure (ArisSavedStepsSettingsRows).
    case savedStepsName
    case calendar(String), allDay, joinMeeting, openIn
    case seesScreen, circle
    case autoMemory, memoryQuery
    /// 매주 정리하기 (the weekly tidy-up: ArisMemoryReviewRows).
    case consolidateMemory
    /// 한 일에서 배우기 (the agent's work memory: ArisWorkSettingsRows).
    case workMemory
    case hover, haptics, gestures, heightMode, notchHeight
    /// A side notch's tab showing or not (ArisSideTab's raw value).
    case sideTab(String)
    case theme, accentCustom, reduceMotion, settingsIcon, alwaysTabs
    /// 에코 제거 오디오 (새 엔진): `arisDuplexAudio`.
    case duplexAudio
    /// 내 목소리만 듣기 (F1): `arisOwnerVoice` (ArisVoiceID.key).
    case voiceID
    /// 실험 기능 (ArisLabsSetting): the helper's switches the app owns and sends it (ArisExperimentSwitch).
    case core2, teach
    /// The notch's look (ArisNotchLookSetting): its theme (ArisNotchTheme's raw value), the text backing and the star at rest.
    case notchTheme, textBacking, restStar
    case login, displayMode, screen, appLanguage, userName
    /// 자동으로 업데이트 (ArisUpdater).
    case autoUpdate
    /// The notch, music and shelf rows (ArisMoreSettings).
    case more(ArisMoreKey)
    /// The API brain row's dropdowns: "provider", "quick" or "strong" (ArisAPIBrainModel).
    case apiBrain(String)
    /// 모델 고르기's dropdowns: "claude.conversation.model", "codex.deep.effort"… (ArisModelChoiceRows).
    case modelChoice(String)
    /// What the closed notch's Claude ring shows (ClaudeRingMode's raw value).
    case claudeRing
    /// 하루 소리 모으기 (ArisWakeCollect), on for a day.
    case wakeCollect
    /// The name that wakes Aris (ArisWakeName), saved as it is typed.
    case wakeName
}

enum ArisSettingValue: Equatable {
    case bool(Bool), text(String), number(Double)
}

/// Something a row does that isn't setting a value.
enum ArisSettingsAction: Equatable {
    case trainVoice, listen, editWords, voicePicker, addLanguage
    case remindersAccess, createList, calendarRefresh, calendarAccess, internetAccounts
    case permission(String), revokeStanding(String)
    case forgetMemory(String), confirmMemory(String), forgetAllMemories, keepMemories, clearMemoryQuery
    /// 확인할 것: a held item kept or dropped, a conflict settled (`keep`: a memory's id, or "both"); a person's or
    /// project's page removed; a tidy-up change undone (ArisMemoryReviewRows).
    case keepHeldMemory(String), dropHeldMemory(String), settleMemoryConflict(String, keep: String), forgetMemoryEntity(String), undoMemoryChange(Int)
    /// 일하면서 배운 것: one lesson forgotten, all of it (asked twice), or kept after all.
    case forgetWorkLesson(Int), forgetAllWork, keepWork
    /// 저장된 단계: one saved request forgotten (ArisSavedStepsSettingsRows): the first press asks, the second (정말 지우기)
    /// forgets; 취소 keeps it.
    case forgetSavedSteps(String), keepSavedSteps
    /// 저장된 단계: a taught procedure's 이름 바꾸기 (its row turns into a field), and the field's 저장.
    case renameSavedSteps(String), saveSavedStepsName(String)
    /// 다른 AI에서 가져오기: the import sheet opens (ArisMemoryImportSheet).
    case importMemory
    /// A feature's detail sheet opens (ArisFeatureSheet).
    case feature(ArisFeature)
    /// Forgets every learned suggestion for dropped files (ArisDropLearned).
    case forgetDropHabits
    case unhideSides, go(ArisSettingsPage, anchor: String?)
    /// The 팀원 or 스킬 sheet opens ("team", "skills"), on `anchor` when one is named.
    case openSheet(String, anchor: String?)
    case export, diagnostics, wipe, uninstall
    /// 업데이트 확인 (ArisUpdater.checkNow).
    case checkUpdate
    /// Claude Code 연결: Aris's hooks and status line into ~/.claude/settings.json, or out of it (ClaudeConnect).
    case claudeConnect, claudeDisconnect
    case onboarding, restart, quit, openFolder, clearName
    case accent(String?), pickAccent
    /// A slider's drag began (true) or ended.
    case sliding(ArisSettingKey, Bool)
    /// Clears the named shortcut.
    case clearShortcut(String)
    case recheckNowPlaying
    /// Dictation's learned words: add a proposed one, dismiss it, or delete a learned one.
    case learnWord(String), dismissWord(String), forgetWord(String)
    /// 호출어 녹음: the recording sheet opens; every recording erased (asked twice), or kept after all.
    case recordWakeCalls, clearWakeRecordings, keepWakeRecordings
    /// The wake name back to "아리스" (ArisWakeNameRows).
    case resetWakeName
    /// 내 목소리 (ArisVoiceIDRows): the enrolment sheet opens; the print deleted (asked twice), or kept after all.
    case enrolVoice, forgetVoice, keepVoice
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
    /// A shortcut that can be changed, shown as caps (KeyboardShortcuts' name); dimmed and inert when not `enabled`.
    case shortcut(name: String, caps: [String], enabled: Bool = true)
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
    /// A list: its rows share one card (ArisSettingsLayout.blocks); otherwise each row is a card of its own.
    var grouped = false
    var rows: [ArisSettingItem]
    /// Set: the card shows this one line, and its rows only while it is open.
    var fold: ArisSettingFold?
    /// A feature whose detail sheet a small 알아보기 link at the end of the section's title opens.
    var feature: ArisFeature?
}

/// A part of a long page (ArisSettingsParts) and the sections it draws under its title.
struct ArisPartSections: Identifiable, Equatable {
    let part: ArisSettingsPart
    var sections: [ArisSettingSection]
    var id: String { part.id }
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

    /// Each row is its own card, as measured (SETTINGS-REA.md §4.2: no grouped cards and no separators in the settings
    /// tabs), whatever its control. A list (`grouped`: permissions, memories, styles, connected services) and a folded
    /// section stay one card, their rows split by hairlines inset to the words.
    static func blocks(_ section: ArisSettingSection) -> [Block] {
        guard !section.rows.isEmpty else { return [] }
        if section.grouped || section.fold != nil { return [.group(section.rows)] }
        return section.rows.map { .group([$0]) }
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
