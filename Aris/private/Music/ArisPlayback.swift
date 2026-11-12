//
//  ArisPlayback.swift
//  Aris
//
//  What a music source reports at one moment, and how the now-playing adapter's stream (full and partial "diff"
//  payloads) folds into it. Pure values, so the rules can be tested without a player.
//

import Foundation

struct ArisPlayback: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var duration: TimeInterval = 0
    /// The position at `timestamp`.
    var elapsed: TimeInterval = 0
    var timestamp = Date.distantPast
    var rate: Double = 1
    var isPlaying = false
    /// Encoded image bytes, if the source gave any.
    var artwork: Data?
    var bundleID: String?

    /// Where playback is at `date`: moving at `rate` while playing, clamped to the track; held while paused.
    func position(at date: Date) -> TimeInterval {
        let end = max(duration, 0)
        guard isPlaying else { return min(max(elapsed, 0), end) }
        let moved = elapsed + date.timeIntervalSince(timestamp) * rate
        return min(max(moved, 0), end)
    }

    /// Another track, artwork or app (what makes the artwork and its colour change).
    func differsInContent(from other: ArisPlayback) -> Bool {
        title != other.title || artist != other.artist || album != other.album
            || artwork != other.artwork || bundleID != other.bundleID
    }
}

/// The adapter's stream state: the last full payload with every later diff applied.
struct ArisAdapterState {
    private(set) var fields: [String: Any] = [:]

    /// Applies one stream message (`{"type": "data", "diff": Bool, "payload": {…}}`). A full payload replaces
    /// everything; a diff sets the keys it carries and removes the ones it sets to null.
    mutating func apply(_ message: [String: Any]) {
        if let type = message["type"] as? String, type != "data" { return }
        let payload = message["payload"] as? [String: Any] ?? [:]
        if (message["diff"] as? Bool) != true { fields = [:] }
        for (key, value) in payload {
            if value is NSNull { fields[key] = nil } else { fields[key] = value }
        }
    }

    /// The playback these fields describe (times in microseconds, as the adapter's `--micros` option writes them).
    /// The app is the parent application when there is one (a browser's media helper reports its browser).
    func playback(now: Date = Date()) -> ArisPlayback {
        var p = ArisPlayback()
        p.title = fields["title"] as? String ?? ""
        p.artist = fields["artist"] as? String ?? ""
        p.album = fields["album"] as? String ?? ""
        p.duration = micros("durationMicros") ?? 0
        p.elapsed = micros("elapsedTimeMicros") ?? 0
        p.timestamp = micros("timestampEpochMicros").map { Date(timeIntervalSince1970: $0) } ?? now
        p.rate = (fields["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        p.isPlaying = (fields["playing"] as? NSNumber)?.boolValue ?? false
        p.artwork = (fields["artworkData"] as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        p.bundleID = (fields["parentApplicationBundleIdentifier"] as? String) ?? (fields["bundleIdentifier"] as? String)
        return p
    }

    private func micros(_ key: String) -> TimeInterval? {
        (fields[key] as? NSNumber).map { $0.doubleValue / 1_000_000 }
    }
}
