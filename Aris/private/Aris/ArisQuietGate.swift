//
//  ArisQuietGate.swift
//  Aris
//
//  The live side of ArisQuiet: every path that speaks or chimes asks here first. It reads the mute switch and the
//  night hours from the app's preferences and asks macOS whether the screen is locked or asleep, then lets
//  ArisQuiet.decide answer. Nothing here needs a permission: the mute and hours are Aris's own preferences, and the
//  screen's state is the same question the wake word already asks (ArisController.screenIsAwayNow).
//  Foundation and CoreGraphics only, so the chimes' own file (ClaudeSounds) can ask and the wiring is tested.
//

import CoreGraphics
import Foundation

enum ArisQuietGate {
    /// The preferences' names (ArisPreferenceKeys reads and writes the same two).
    static let mutedKey = "arisMuted"
    static let hoursKey = "arisQuietHours"

    /// The titles of Aris's own announcements while they are being delivered (speakUp); usually none or one.
    @MainActor private(set) static var announcing: [String] = []

    /// The user muted Aris.
    static var muted: Bool { UserDefaults.standard.bool(forKey: mutedKey) }

    /// The night hours as stored; the standard ones until Settings wrote any.
    static var storedHours: String { UserDefaults.standard.string(forKey: hoursKey) ?? ArisQuietHours.standard }

    /// The Mac is locked or its main display sleeps.
    static func screenIsAway() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        return locked || CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    /// The decision from plain values (what the live calls below read).
    static func verdict(_ starter: ArisQuiet.Starter, muted: Bool, hours: String, screenAway: Bool, now: Date,
                        calendar: Calendar = .current) -> ArisQuiet.Verdict {
        let moment = ArisQuiet.Moment(screenAway: screenAway, night: ArisQuietHours.isNight(now, stored: hours, calendar: calendar))
        return ArisQuiet.decide(starter: starter, muted: muted, moment: moment)
    }

    /// May something `starter` began make sound right now: the voice, a chime, a tick.
    static func maySound(_ starter: ArisQuiet.Starter) -> Bool {
        verdict(starter, muted: muted, hours: storedHours, screenAway: screenIsAway(), now: Date()).isAloud
    }

    /// Whose words the notch is about to say, given what it shows (`heard`: the turn's words or the announcement's title).
    @MainActor static func starter(heard: String) -> ArisQuiet.Starter {
        ArisQuiet.starter(announcing: announcing, heard: heard)
    }

    /// May the voice read what the notch shows now.
    @MainActor static func maySpeak(heard: String) -> Bool { maySound(starter(heard: heard)) }

    /// Runs the delivery of Aris's own announcement `title` (its voice, or its card): while it holds the notch, what is
    /// said is Aris's own initiative, so quiet time keeps it to text. `text`: the news it shows; kept to text, it holds
    /// the notch for as long as it takes to read (the voice would have held it that long), so the next piece of news
    /// does not replace it at once.
    @MainActor static func unprompted<T>(_ title: String, reading text: String = "", _ work: () async -> T) async -> T {
        let silent = !maySound(.aris)
        announcing = announcing + [title]
        defer { announcing = removingFirst(title, from: announcing) }
        let result = await work()
        if silent, !text.isEmpty, !Task.isCancelled { try? await Task.sleep(for: ArisNotch.readingTime(for: text)) }
        return result
    }

    private static func removingFirst(_ title: String, from titles: [String]) -> [String] {
        guard let at = titles.firstIndex(of: title) else { return titles }
        return Array(titles[..<at] + titles[(at + 1)...])
    }
}
