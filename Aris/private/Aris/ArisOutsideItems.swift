//
//  ArisOutsideItems.swift
//  Aris
//
//  The to-dos and events an automatic pass made (the automatic check let the write through with no card, after outside
//  text was read: security review 9, M2). Their words may be a page's or a mail's, and they come back in every later
//  turn's calendar (ArisContext), so there they are labelled as outside text: the brain reads them as data, never as
//  something the user asked. Kept by EventKit's item id (ArisCalendarEvent.id, ArisTodoItem.id) for as long as the activity
//  log keeps a row (30 days), at most `most` of them. Foundation only (tested).
//

import Foundation

final class ArisOutsideItems: @unchecked Sendable {
    static let shared = ArisOutsideItems(defaults: .standard)
    static let key = "arisOutsideItems"
    static let keep: TimeInterval = 30 * 86_400
    static let most = 500

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) { self.defaults = defaults }

    /// The item an /aris/todos or /aris/events answer says it made: an event's `id`, or a to-do's first item's.
    static func madeID(in answer: Data) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: answer)) as? [String: Any], object["ok"] as? Bool == true else { return nil }
        let id = object["id"] as? String ?? ((object["items"] as? [[String: Any]])?.first?["id"] as? String)
        return id.flatMap { $0.isEmpty || $0.count > 200 ? nil : $0 }
    }

    /// Notes the item a route's answer made, when it made one.
    func noteMade(in answer: Data, now: Date = Date()) {
        guard let id = Self.madeID(in: answer) else { return }
        note(id, now: now)
    }

    func note(_ id: String, now: Date = Date()) {
        lock.withLock {
            var kept = current(now: now)
            kept[id] = now.timeIntervalSince1970
            if kept.count > Self.most {
                kept = Dictionary(uniqueKeysWithValues: kept.sorted { $0.value > $1.value }.prefix(Self.most).map { ($0.key, $0.value) })
            }
            defaults.set(kept, forKey: Self.key)
        }
    }

    func contains(_ id: String, now: Date = Date()) -> Bool { lock.withLock { current(now: now)[id] != nil } }

    /// The ids still kept (called with `lock` held).
    private func current(now: Date) -> [String: Double] {
        let stored = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
        return stored.filter { now.timeIntervalSince1970 - $0.value <= Self.keep }
    }
}
