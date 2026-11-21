//
//  ArisRouterPatience.swift
//  Aris (Shared/Core)
//
//  How long the quick understanding (설정 › 짧은 명령 빨리 알아듣기) waits for its model, per kind of model, and when it
//  stops asking for a while (tenth VM run, item 7). A chat model picked there (DeepSeek's deepseek-chat) answers a
//  short reply in 1.0-2.2 s warm (median 1.6 s over 29 turns of that run), so the small models' 600 ms was missed on
//  every turn: about 0.9 s lost and a paid call each time, for nothing. Now each kind has its own limit, and after
//  `missesBeforeRest` misses in a row the model is left alone for `restSeconds` (one log line when the rest begins);
//  the keyword rules understand meanwhile. Foundation only (swift test).
//

import Foundation

enum ArisRouterPatience {
    enum Kind: Equatable, Sendable {
        /// TypeSafe's Jev.
        case jev
        /// A provider's small routing model whose price Aris knows (GPT-6 Luna, Haiku, Flash-Lite).
        case smallModel
        /// Any other model of a connected profile: the one that also chats.
        case chatModel
    }

    /// Seconds one routing call may take.
    static func limit(_ kind: Kind) -> Double {
        switch kind {
        case .jev, .smallModel: return 0.6
        case .chatModel: return 2.5
        }
    }

    /// How long the app waits for the whole route: Jev's own limit, or (an API profile, whose model aris-agent knows
    /// and limits itself) the longest of them and the trip to the agent and back.
    static func appWait(api: Bool) -> Double { api ? limit(.chatModel) + 0.3 : limit(.jev) }
}

/// The misses in a row of one choice, and its rest. A value; the app keeps one.
struct ArisRouterRest: Equatable, Sendable {
    /// Misses in a row (no answer in time, or any other failure) before the model is left alone.
    static let missesBeforeRest = 3
    /// How long it is left alone.
    static let restSeconds: TimeInterval = 600

    private(set) var route = ""
    private(set) var misses = 0
    private(set) var until: Date?

    init() {}

    /// Whether `route` (the stored choice) is resting now; another choice than the one counted starts fresh.
    mutating func isResting(route asked: String, now: Date) -> Bool {
        guard asked == route else { return false }
        guard let until else { return false }
        if now < until { return true }
        // The rest is over: one try, and one more miss rests again.
        self.until = nil
        misses = Self.missesBeforeRest - 1
        return false
    }

    /// One miss; true when a rest begins with it (the one line to log).
    mutating func missed(route asked: String, now: Date) -> Bool {
        if asked != route { self = ArisRouterRest(); route = asked }
        misses += 1
        guard misses >= Self.missesBeforeRest, until == nil else { return false }
        until = now.addingTimeInterval(Self.restSeconds)
        return true
    }

    /// It answered.
    mutating func answered(route asked: String) {
        guard asked == route else { return }
        misses = 0
        until = nil
    }
}
