//
//  ArisMusicEvents.swift
//  Aris
//
//  The Apple Events for Music and Spotify (their scripting suites' codes, from each app's sdef), how a state read
//  goes, and when one runs: reads come on demand (the app's change notification, a notch opening, a question about
//  the song), a fresh one is reused for a moment, reads never overlap, and a failing read is logged once until one
//  works again (QA BUG-37's follow-up: a state poll on every turn, each logging its failure). Pure but for the sends.
//

import Foundation

enum ArisMusicEvents {
    /// The suite a player's own commands are in: Spotify's `spfy`, Music's `hook`.
    static func suite(for bundleID: String) -> String {
        bundleID == "com.spotify.client" ? "spfy" : "hook"
    }

    /// The command's event: suite and id.
    static func command(_ command: ArisMusicCommand, bundleID: String) -> String {
        let id = switch command {
        case .play: "Play"
        case .pause: "Paus"
        case .toggle: "PlPs"
        case .next: "Next"
        case .previous: "Prev"
        }
        return suite(for: bundleID) + id
    }

    /// Player state codes (both apps): stopped, playing, paused.
    static let stopped = "kPSS", playing = "kPSP"

    /// The app's state, read property by property: player state, then the current track's name, artist, album and
    /// duration (in `durationUnit` seconds), and the position.
    static func read(_ client: ArisAppleEventClient, durationUnit: Double, at date: Date) async throws -> ArisPlayback {
        var playback = ArisPlayback()
        playback.bundleID = client.bundle
        playback.timestamp = date
        let state = try await value(client, ["pPlS"])
        guard case .enumerated(let code) = state, code != stopped else { return playback }
        playback.isPlaying = code == playing
        playback.title = text(try await value(client, ["pTrk", "pnam"]))
        playback.artist = text(try await value(client, ["pTrk", "pArt"]))
        playback.album = text(try await value(client, ["pTrk", "pAlb"]))
        playback.duration = number(try await value(client, ["pTrk", "pDur"])) * durationUnit
        playback.elapsed = number(try await value(client, ["pPos"]))
        return playback
    }

    /// Music's artwork bytes (raw data of artwork 1 of current track).
    static func musicArtwork(_ client: ArisAppleEventClient) async throws -> Data? {
        let result = try await client.send(ask: false, { ArisAppleEvents.get(["pTrk"], element: "cArt", index: 1, property: "pRaw", of: $0) },
                                           read: { ArisAppleEvents.value(of: $0) })
        if case .data(let data) = result, !data.isEmpty { return data }
        return nil
    }

    /// Spotify's artwork address (artwork url of current track).
    static func spotifyArtworkURL(_ client: ArisAppleEventClient) async throws -> URL? {
        URL(string: text(try await value(client, ["pTrk", "aUrl"])))
    }

    private static func value(_ client: ArisAppleEventClient, _ path: [String]) async throws -> ArisAEValue {
        try await client.send(ask: false, { ArisAppleEvents.get(path, of: $0) }, read: { ArisAppleEvents.value(of: $0) })
    }

    static func text(_ value: ArisAEValue) -> String {
        if case .text(let text) = value { return text }
        return ""
    }

    static func number(_ value: ArisAEValue) -> Double {
        if case .number(let number) = value { return number }
        return 0
    }
}

/// When a player's state is read. Values only.
struct ArisMusicReadGate: Equatable {
    /// A read this recent is reused for a refresh that wasn't announced by the app.
    static let freshFor: TimeInterval = 1.5

    private(set) var lastRead: TimeInterval?
    private(set) var reading = false
    /// A refresh came during a read: one more read after it.
    private(set) var again = false
    private(set) var failureLogged = false

    /// A refresh at `now`: whether to read now. `announced`: the app said it changed (always read, after any read in
    /// flight).
    mutating func wants(now: TimeInterval, announced: Bool) -> Bool {
        if reading {
            if announced { again = true }
            return false
        }
        if !announced, let lastRead, now - lastRead < Self.freshFor { return false }
        reading = true
        return true
    }

    /// The read ended: whether to log its failure (only the first in a row), and whether to read once more.
    mutating func finished(now: TimeInterval, ok: Bool) -> (logFailure: Bool, readAgain: Bool) {
        reading = false
        let log = !ok && !failureLogged
        // A failed read waits as long as a good one before the next unannounced try.
        lastRead = now
        failureLogged = !ok
        let more = again
        again = false
        return (log, more)
    }
}
