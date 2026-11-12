//
//  ArisMusicRules.swift
//  Aris
//
//  The decisions of the music layer, as plain functions: which source to fall back to when Now Playing doesn't
//  work, what the notice says, when the player counts as idle, and when a change peeks out of the closed notch.
//

import Foundation

/// Why Now Playing isn't in use: its files are missing (setup), its self-test failed (probe), or a running stream
/// died (runtime).
enum NowPlayingFailure: Equatable {
    case setup, probe, runtime
}

enum NowPlayingAvailability: Equatable {
    case unchecked, checking, available
    case unavailable(NowPlayingFailure)

    var failure: NowPlayingFailure? {
        if case .unavailable(let failure) = self { failure } else { nil }
    }
}

/// The card the closed notch shows when Aris had to leave a Now Playing source the user picked.
struct NowPlayingFallbackNotice: Identifiable {
    let id = UUID()
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
}

enum ArisMusicRules {
    /// How long the notice stays after it is first shown.
    static let noticeDuration: Duration = .seconds(6)
    /// The wait before Now Playing is tried again after its stream died.
    static let retryDelay: Duration = .seconds(1)
    /// Self-test attempts, and how long one may take.
    static let probeAttempts = 3
    static let probeTimeout: TimeInterval = 10
    /// The pause before self-test attempt n + 1 is n times this.
    static let probeBackoff: Duration = .milliseconds(350)
    /// How long a standard peek shows.
    static let peekDuration: TimeInterval = 1.5

    /// The direct source for when Now Playing can't be used: the music app it last reported, else Music.
    static func fallback(lastSupported bundleID: String?) -> MediaControllerType {
        bundleID.flatMap(MediaControllerType.init(nowPlayingBundleIdentifier:)) ?? .appleMusic
    }

    /// The bundle id to remember as "last supported": a music app with its own source, seen through Now Playing.
    static func supportedBundle(_ bundleID: String?, source: MediaControllerType) -> String? {
        guard source == .nowPlaying, let bundleID, MediaControllerType(nowPlayingBundleIdentifier: bundleID) != nil else { return nil }
        return bundleID
    }

    /// The notice for a fallback, only when the user picked Now Playing themselves.
    static func notice(for failure: NowPlayingFailure, using source: MediaControllerType, chosen: Bool) -> NowPlayingFallbackNotice? {
        guard chosen else { return nil }
        let name = source.localizedString
        switch failure {
        case .setup:
            return NowPlayingFallbackNotice(title: "Now Playing components unavailable", subtitle: "Using \(name) instead")
        case .probe:
            return NowPlayingFallbackNotice(title: "Could not verify Now Playing", subtitle: "Using \(name) temporarily")
        case .runtime:
            return NowPlayingFallbackNotice(title: "Now Playing connection lost", subtitle: "Using \(name) temporarily")
        }
    }

    /// Idle: not playing, and paused for at least `wait` seconds.
    static func isIdle(playing: Bool, pausedSince: Date?, now: Date, wait: TimeInterval) -> Bool {
        guard !playing else { return false }
        guard let pausedSince else { return true }
        return now.timeIntervalSince(pausedSince) >= wait
    }

    enum Peek: Equatable { case standard, inline }

    /// The peek for a playback or track change: only while playing a track with a title and an artist, and only
    /// when peeks are on.
    static func peek(enabled: Bool, style: SneakPeekStyle, playing: Bool, title: String, artist: String) -> Peek? {
        guard enabled, playing, !title.isEmpty, !artist.isEmpty else { return nil }
        return style == .inline ? .inline : .standard
    }
}
