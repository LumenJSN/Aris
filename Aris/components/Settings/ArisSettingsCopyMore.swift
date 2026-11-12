//
//  ArisSettingsCopyMore.swift
//  Aris
//
//  The English of settings rows added after the settings catalog (Settings.xcstrings) was last written: the pages
//  stay written in Korean and look each string up, first in the catalog, then here. Each feature keeps its own pairs
//  beside its rows; this only joins them. When the catalog's owner moves a pair into the catalog, the catalog's
//  wins and the pair here can go. Foundation only (tested).
//

import Foundation

enum ArisSettingsCopyMore {
    /// Korean → English, for every string of the rows built on feat-2.
    static let english: [String: String] = [ArisQuietHoursCopy.english, ArisTerminalSetting.english, ArisDropLearnedSetting.english, ArisWakeHonesty.english,
                                           ArisWorkSettingsRows.english, ArisMemoryImportCopy.english, ArisNotchLookSetting.english]
        .reduce(into: [:]) { all, pairs in all.merge(pairs) { first, _ in first } }

    /// A menu choice's English by its setting and id, before any lookup by its Korean: for a choice whose Korean means
    /// something else elsewhere in the catalog.
    static func option(_ key: ArisSettingKey, id: String) -> String? { ArisNotchLookSetting.optionEnglish(key, id: id) }
}
