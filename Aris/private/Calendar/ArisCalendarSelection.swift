//
//  ArisCalendarSelection.swift
//  Aris
//
//  Which calendars Aris shows: all of them, or a chosen set. Stored under `calendarSelectionState` as the JSON
//  string of this two-case enum ({"all":{}} or {"selected":{"_0":[ids]}}), the shape earlier builds wrote.
//

import Foundation

enum ArisCalendarSelection: Codable, Equatable {
    case all
    case selected(Set<String>)

    static let key = "calendarSelectionState"

    func contains(_ id: String) -> Bool {
        switch self {
        case .all: true
        case .selected(let ids): ids.contains(id)
        }
    }

    /// The selection after turning one calendar on or off. Turning one on while everything is shown changes nothing;
    /// otherwise the result is an explicit list (`current` is every calendar and reminder list), which stays a list
    /// even when every calendar is chosen again.
    func setting(_ id: String, on: Bool, among current: Set<String>) -> ArisCalendarSelection {
        var ids: Set<String>
        switch self {
        case .all:
            if on { return .all }
            ids = current
        case .selected(let chosen): ids = chosen
        }
        if on { ids.insert(id) } else { ids.remove(id) }
        return .selected(ids)
    }

    static func load(from defaults: UserDefaults) -> ArisCalendarSelection {
        let raw = defaults.object(forKey: key)
        let data = (raw as? String).map { Data($0.utf8) } ?? raw as? Data
        guard let data, let selection = try? JSONDecoder().decode(ArisCalendarSelection.self, from: data) else { return .all }
        return selection
    }

    func save(to defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.key)
    }
}

/// Coalesces EventKit's change storms (iCloud sync): the first change schedules one reload, later ones wait for it.
struct ArisChangeGate {
    static let delay: Duration = .seconds(2)
    private var pending = false

    /// True when this change should schedule a reload.
    mutating func changed() -> Bool {
        guard !pending else { return false }
        pending = true
        return true
    }

    mutating func reloaded() { pending = false }
}
