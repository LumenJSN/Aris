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

    /// The brain to ask for a request meant for `requested`: its fallback while it's out, unless that one is too.
    func brain(for requested: ArisBrain, at now: Date = Date()) -> ArisBrain {
        guard !isAvailable(requested, at: now), let other = requested.fallback, isAvailable(other, at: now) else { return requested }
        return other
    }
}
