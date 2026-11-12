//
//  ArisQuietSpan.swift
//  Aris
//
//  The night hours of quiet time, to the minute, so the user can set any start and any end ("밤에는 조용히, 이거 시간대
//  고를 수 있게 해"). The preference stays one readable string: "off", one of the old ranges ("23-7"), or the two
//  times he picked ("22:30-6:00": hours, and minutes when he chose them). A range may run past midnight (23:00 →
//  07:00); a start and an end at the same minute cover nothing, so that reads as off. A value that can't be read is
//  the standard night, as before: a damaged preference never turns quiet time off by itself.
//  ArisQuietHours (the gate's own type) reads through this. Foundation only, so it is tested.
//

import Foundation

struct ArisQuietSpan: Equatable {
    /// Minutes from midnight, 0..<1440: quiet from `start` until `end`.
    let start: Int
    let end: Int

    static let day = 24 * 60
    /// The Settings row's choice that shows the two menus.
    static let custom = "custom"
    /// The menus offer every half hour.
    static let step = 30

    /// Nil when night quiet is off: stored as "off", or a start and an end that are the same minute. Anything
    /// unreadable is the standard night.
    init?(stored: String) {
        if stored == ArisQuietHours.off { return nil }
        guard let edges = Self.edges(stored) ?? Self.edges(ArisQuietHours.standard), edges.start != edges.end else { return nil }
        start = edges.start
        end = edges.end
    }

    /// The two times a stored value names, in minutes from midnight; nil for "off" and for anything unreadable.
    /// The same minute twice is still two times (the row shows them; the gate reads it as off).
    static func edges(_ stored: String) -> (start: Int, end: Int)? {
        let parts = stored.split(separator: "-", omittingEmptySubsequences: false).map { minute(String($0)) }
        guard parts.count == 2, let start = parts[0], let end = parts[1] else { return nil }
        return (start, end)
    }

    /// "23" or "23:30" as minutes from midnight.
    static func minute(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let hour = number(parts[0], digits: 1...2), (0...23).contains(hour) else { return nil }
        guard parts.count == 2 else { return hour * 60 }
        guard let minutes = number(parts[1], digits: 2...2), (0...59).contains(minutes) else { return nil }
        return hour * 60 + minutes
    }

    /// Plain digits only: no sign, no spaces (Int("+7") would read).
    private static func number(_ text: Substring, digits: ClosedRange<Int>) -> Int? {
        guard digits.contains(text.count), text.allSatisfy({ ("0"..."9").contains($0) }) else { return nil }
        return Int(text)
    }

    /// The range wraps past midnight when it starts later than it ends.
    func contains(minute: Int) -> Bool {
        start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }

    // MARK: - Writing a value

    /// A time as the menus name it and the preference holds it: "7:00", "22:30".
    static func clock(_ minute: Int) -> String {
        let wrapped = ((minute % day) + day) % day
        return "\(wrapped / 60):" + (wrapped % 60 < 10 ? "0" : "") + "\(wrapped % 60)"
    }

    /// The two times as the owner picked them: always with their minutes, so the row knows they are their own even when they
    /// happen to be one of the old ranges.
    static func picked(start: Int, end: Int) -> String { clock(start) + "-" + clock(end) }

    /// What is stored for two times said or set outside the menus: the old range when it is exactly one of them
    /// (the row then shows that choice), "off" never (the same minute twice is kept as said).
    static func stored(start: Int, end: Int) -> String {
        ArisQuietHours.choices.first { edges($0).map { $0 == (start, end) } ?? false } ?? picked(start: start, end: end)
    }

    // MARK: - The Settings row

    /// Which choice the row shows as picked: off, one of the old ranges, or "custom" for two times of his own. An
    /// unreadable value shows as the standard night.
    static func choice(for stored: String) -> String {
        if ArisQuietHours.choices.contains(stored) { return stored }
        return edges(stored) == nil ? ArisQuietHours.standard : custom
    }

    /// What the preference becomes when the row's choice is pressed. "직접 고르기" keeps the hours that were set (the
    /// standard night when quiet time was off), now as two times of his own.
    static func choosing(_ choice: String, current: String) -> String {
        if ArisQuietHours.choices.contains(choice) { return choice }
        guard choice == custom else { return Self.choice(for: choice) == custom ? choice : ArisQuietHours.standard }
        let edges = edges(current) ?? edges(ArisQuietHours.standard) ?? (23 * 60, 7 * 60)
        return picked(start: edges.start, end: edges.end)
    }

    /// One of the two menus was set to `clock` ("22:30"); the other time stays.
    static func setting(start clock: String? = nil, end other: String? = nil, current: String) -> String {
        let edges = edges(current) ?? edges(ArisQuietHours.standard) ?? (23 * 60, 7 * 60)
        return picked(start: clock.flatMap(minute) ?? edges.start, end: other.flatMap(minute) ?? edges.end)
    }

    /// The times a menu lists: every half hour, and the stored time itself when it sits between two of them (set by
    /// voice to 22:45, say), in order.
    static func menuTimes(including chosen: Int) -> [Int] {
        let halves = Array(stride(from: 0, to: day, by: step))
        return halves.contains(chosen) ? halves : (halves + [chosen]).sorted()
    }
}
