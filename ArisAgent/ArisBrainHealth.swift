//
//  ArisBrainHealth.swift
//  aris-agent
//
//  Which AIs can answer right now. One that ran out of quota or is overloaded (GPT's
//  usage limit) is skipped for a while, and its requests go to the next AI instead
//  (ArisBrain.fallback), so Aris keeps answering rather than saying "limit reached".
//

import Foundation

struct ArisBrainHealth {
    /// How long a brain that ran out is skipped before it's tried again.
    static let cooldown: TimeInterval = 15 * 60

    private var outUntil: [ArisBrain: Date] = [:]

    func isAvailable(_ brain: ArisBrain, at now: Date = Date()) -> Bool {
        outUntil[brain].map { now >= $0 } ?? true
    }

    /// `until`: when the AI said it'll answer again (resetDate); the usual cooldown otherwise.
    mutating func markUnavailable(_ brain: ArisBrain, at now: Date = Date(), until: Date? = nil) {
        outUntil[brain] = until ?? now.addingTimeInterval(Self.cooldown)
    }

    /// A reset time is believed only this far ahead.
    static let longestWait: TimeInterval = 8 * 24 * 3600

    /// Codex's "…try again at Oct 27th, 2026 12:21 AM." as a date (in the Mac's time zone). Nil when there's no
    /// such time, or it's in the past or implausibly far off.
    static func resetDate(in message: String, now: Date = Date(), timeZone: TimeZone = .current) -> Date? {
        guard let found = message.range(of: #"try again at ([A-Z][a-z]{2} \d{1,2})(?:st|nd|rd|th)?(, \d{4} \d{1,2}:\d{2} [AP]M)"#,
                                        options: .regularExpression) else { return nil }
        let said = message[found].dropFirst("try again at ".count)
        let plain = said.replacingOccurrences(of: #"(\d)(st|nd|rd|th),"#, with: "$1,", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy h:mm a"
        guard let date = formatter.date(from: plain), date > now, date.timeIntervalSince(now) < longestWait else { return nil }
        return date
    }

    /// The brain to ask for a request meant for `requested`: its fallback while it's out, unless that one is too, and
    /// only with 다른 AI로 넘기기 on (`fallback`); off, the chosen brain is always the one asked.
    func brain(for requested: ArisBrain, fallback: Bool, at now: Date = Date()) -> ArisBrain {
        guard fallback, !isAvailable(requested, at: now), let other = requested.fallback, isAvailable(other, at: now) else { return requested }
        return other
    }
}

/// 다른 AI로 넘기기 (Settings › AI · 모델, off by default): whether a turn may go to another AI on its own when the chosen
/// one is out of its limit or not on this Mac. Off, nothing starts another provider by itself: the chosen brain answers,
/// or says why it can't. Only the app itself turns it on (anyone else's word counts as off).
enum ArisBrainFallback {
    static let field = "fallback"

    static func allowed(_ object: [String: Any], fromApp: Bool) -> Bool { fromApp && object[field] as? Bool == true }

    /// Whether this turn goes to another brain before the chosen one is asked: only with the switch on, on a first try
    /// that isn't one of agy's relay rounds, when the chosen one is missing or out.
    static func switchesFirst(allowed: Bool, retried: Bool, relayRound: Int, missing: Bool, available: Bool) -> Bool {
        allowed && !retried && relayRound == 0 && (missing || !available)
    }

    /// Whether a turn whose brain said it is out is asked again on another: only with the switch on, once, never after
    /// a handed-off call ran (it would act twice), never in a relay round.
    static func retriesElsewhere(allowed: Bool, retried: Bool, alreadyActed: Bool, relayRound: Int) -> Bool {
        allowed && !retried && !alreadyActed && relayRound == 0
    }
}
