//
//  ArisQuiet.swift
//  Aris
//
//  Should Aris make sound now? One answer for the voice and for every chime, from three things: who started what is
//  about to be said, whether the user muted Aris, and whether it is quiet time.
//  - Muted (the notch's switch, the ✦ menu, "조용히 해 줘", Settings): nothing is said and nothing chimes, whoever
//    started it. Answers stay on screen, cards wait for a click or Y/N.
//  - Quiet time (the screen locked or asleep, or night hours): only what Aris brings up by itself goes quiet: a job's
//    or a schedule's result or question, a teammate finishing, a card nobody asked for. It waits as text in the notch.
//    A reply to what the user just asked still speaks (they is plainly there), and so does a timer they set themselves: they asked
//    for that sound at that time, and a timer nobody hears has failed.
//  A macOS Focus is not part of quiet time: the sandboxed app cannot learn it without a new permission prompt
//  (INFocusStatusCenter asks; the Do Not Disturb files are outside the sandbox and guarded), so it is not guessed.
//  Foundation only, so every combination is tested.
//

import Foundation

enum ArisQuiet {
    /// Who started what is about to make sound.
    enum Starter: Equatable, CaseIterable {
        /// The user just asked (by voice, the keyboard or a click): this is the reply.
        case user
        /// A timer or alarm he set himself is going off.
        case userTimer
        /// Aris's own initiative: nobody asked just now.
        case aris
    }

    /// What is known about the moment.
    struct Moment: Equatable {
        /// The Mac is locked or its display sleeps.
        var screenAway = false
        /// Inside the night hours (ArisQuietHours).
        var night = false

        var isQuiet: Bool { screenAway || night }
    }

    enum Why: Equatable { case muted, screenAway, night }

    enum Verdict: Equatable {
        case aloud
        /// Shown, not said; no chime.
        case textOnly(Why)

        var isAloud: Bool { self == .aloud }
    }

    /// The one decision every speaking and chiming path asks.
    static func decide(starter: Starter, muted: Bool, moment: Moment) -> Verdict {
        if muted { return .textOnly(.muted) }
        switch starter {
        case .user, .userTimer:
            return .aloud
        case .aris:
            if moment.screenAway { return .textOnly(.screenAway) }
            return moment.night ? .textOnly(.night) : .aloud
        }
    }

    /// The last door before the loudspeaker, asked by the voice itself (ArisSpeaker) for everything it is handed,
    /// whoever handed it over: a muted Aris says nothing on any path (a typed turn, a spoken one, a card's question,
    /// its own news). The one exception is the Settings window's 미리 듣기: the user pressed it to hear the voice they is
    /// choosing, so it plays even while Aris is muted. Quiet time is decided earlier, by who started the words
    /// (`decide`); this door only makes sure the mute cannot be walked around.
    static func voiceMayPlay(muted: Bool, preview: Bool) -> Bool { preview || !muted }

    /// What the log says as an answer starts: "speaking" only when the voice will really read it.
    static func voiceLog(aloud: Bool) -> String { aloud ? "speaking" : "answering in text: nothing is spoken (muted, or quiet time)" }

    /// Whose words the notch is about to say. Aris's own while an announcement of its own (`announcing`: the titles
    /// being delivered now) still holds the notch; once the user's turn has taken the notch (`heard` is their words), it is
    /// his reply.
    static func starter(announcing: [String], heard: String) -> Starter {
        announcing.contains(heard) ? .aris : .user
    }
}

/// The night part of quiet time: on by default, 23:00 to 07:00, one row in Settings. Stored as "23-7" (first quiet
/// hour, the hour it ends) or "off".
struct ArisQuietHours: Equatable {
    /// 0...23: quiet from the start of `start` until the start of `end`.
    let start: Int
    let end: Int

    static let off = "off"
    static let standard = "23-7"
    /// The choices the Settings row offers, in its order.
    static let choices = [off, "22-7", standard, "0-8"]

    /// Nil when night quiet is off ("off", or a start and an end at the same minute). Anything unreadable is the
    /// standard hours (a damaged preference never turns quiet time off by itself). Read to the minute by
    /// ArisQuietSpan ("22:30-6"); these are its hours.
    init?(stored: String) {
        guard let span = ArisQuietSpan(stored: stored) else { return nil }
        start = span.start / 60
        end = span.end / 60
    }

    /// The hours wrap past midnight (23 → 7).
    func contains(hour: Int) -> Bool {
        start < end ? (start..<end).contains(hour) : hour >= start || hour < end
    }

    static func isNight(_ date: Date, stored: String, calendar: Calendar = .current) -> Bool {
        guard let span = ArisQuietSpan(stored: stored) else { return false }
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return span.contains(minute: (time.hour ?? 0) * 60 + (time.minute ?? 0))
    }

    /// The stored value a Settings row shows as picked (an unreadable one shows as the standard hours).
    static func choice(for stored: String) -> String {
        choices.contains(stored) ? stored : standard
    }
}

/// "음소거 중이라 글로 답할게요": told once, the first time the user talks to a muted Aris by voice, so the silence is
/// never a puzzle. Muting again (or a restart) starts it over; muting by voice has already said it.
struct ArisMuteNotice: Equatable {
    private(set) var told = false

    /// The user just spoke to Aris. `shows`: the note goes up now.
    func hearing(muted: Bool) -> (next: ArisMuteNotice, shows: Bool) {
        guard muted, !told else { return (self, false) }
        return (ArisMuteNotice(told: true), true)
    }

    /// The mute was switched: the next mute tells again. `saidSo`: Aris's reply to "조용히 해 줘" already said it.
    func switched(saidSo: Bool = false) -> ArisMuteNotice {
        ArisMuteNotice(told: saidSo)
    }
}

/// When the open notch's mute switch shows: always while Aris is muted (the state is read at a glance), otherwise
/// while the pointer is on the mark or the switch; never where the band's mark steps aside.
enum ArisMuteSwitchRule {
    static func visible(shown: Bool, muted: Bool, hovering: Bool) -> Bool {
        shown && (muted || hovering)
    }
}
