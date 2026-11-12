//
//  ArisReminderLists.swift
//  Aris
//
//  Which Reminders lists the 할 일 tab shows and where a new item goes, worked out from what the settings chose and
//  the lists that exist. Pure: the same rules answer on the main actor from the lists last read (the tab, the
//  settings) and beside the store, off the main actor, from the lists as they are at that moment (ArisReminderStore).
//  They used to ask EventKit each time, on the main thread.
//

import Foundation

/// What the settings chose for the tab.
struct ArisReminderPrefs: Equatable, Sendable {
    /// The lists to show (arisTodoLists).
    var chosen: [String] = []
    /// He has chosen once, even if he then chose none (arisTodoListsConfigured).
    var configured = false
    /// Where new items go (arisTodoDefaultList); "" when not chosen.
    var defaultChoice = ""
}

enum ArisReminderLists {
    /// The lists chosen in settings that still exist.
    static func chosenIncluded(_ prefs: ArisReminderPrefs, existing: [String]) -> [String] {
        prefs.chosen.filter(existing.contains)
    }

    /// Where new items go: the chosen list if it shows in the tab, else the first list that does, else the chosen
    /// one if it exists at all, else Reminders' own default, else the first list there is.
    static func defaultListID(_ prefs: ArisReminderPrefs, existing: [String], storeDefault: String?) -> String {
        let included = chosenIncluded(prefs, existing: existing)
        if !included.isEmpty { return included.contains(prefs.defaultChoice) ? prefs.defaultChoice : included[0] }
        if !prefs.defaultChoice.isEmpty, existing.contains(prefs.defaultChoice) { return prefs.defaultChoice }
        return storeDefault ?? existing.first ?? ""
    }

    /// The lists the tab shows: the chosen ones, else the default list.
    static func includedIDs(_ prefs: ArisReminderPrefs, existing: [String], storeDefault: String?) -> [String] {
        if prefs.configured || !prefs.chosen.isEmpty { return chosenIncluded(prefs, existing: existing) }
        return [defaultListID(prefs, existing: existing, storeDefault: storeDefault)].filter { !$0.isEmpty }
    }

    /// The tab's items after `saved` was written: gone when its list is not shown, in its old place when it was
    /// there, else added at the end.
    static func taking(_ saved: ArisTodoItem, shown: Bool, into items: [ArisTodoItem]) -> [ArisTodoItem] {
        guard shown else { return items.filter { $0.id != saved.id } }
        guard let index = items.firstIndex(where: { $0.id == saved.id }) else { return items + [saved] }
        var next = items
        next[index] = saved
        return next
    }

    /// "내일로 미루기": the same clock time tomorrow (`now`'s tomorrow), as date components; a day without a time
    /// stays one.
    static func tomorrow(_ due: DateComponents?, now: Date, calendar: Calendar = .current) -> DateComponents? {
        var components = due ?? calendar.dateComponents([.year, .month, .day], from: now)
        guard let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let target = calendar.dateComponents([.year, .month, .day], from: next)
        components.year = target.year
        components.month = target.month
        components.day = target.day
        return components
    }
}
