//
//  ArisWakeCollect.swift
//  Aris
//
//  하루 소리 모으기 (off unless the user turns it on): for one day the waiting wake word keeps short clips of the room, only
//  around a phrase of speech or a phrase stage 1 handed on as a possible “아리스”, so the trained detector can be
//  measured on his real room (false wakes per hour, the calls it would miss). It keeps nothing else: no audio between
//  phrases, no clip longer than a few seconds, never the recognizer's words. It turns itself off after a day, stops
//  keeping at a size cap, and everything goes with 다 지우기. These are the rules; ArisWakeCollectLive applies them.
//  Foundation only (tested).
//

import Foundation

enum ArisWakeCollect {
    /// The UserDefaults keys: on or off, and since when (seconds since 1970).
    static let key = "arisWakeCollect"
    static let sinceKey = "arisWakeCollectSince"

    /// It is on for a day, then off by itself.
    static let lasts: TimeInterval = 24 * 3600
    static let sampleRate = 16_000
    /// Room kept before a phrase starts.
    static let lead = 1.0
    /// A candidate's clip: from just before its phrase, this long (the name and what came right after it).
    static let candidateSeconds = 3.0
    /// The longest clip of anything.
    static let longest = 5.0
    /// A sound shorter than this is no phrase worth keeping (a click, a cough).
    static let shortestPhrase = 0.25
    /// Caps: past either, nothing more is kept until 다 지우기.
    static let maxClips = 600
    static let maxBytes = 150 * 1024 * 1024

    /// On, and still inside its day.
    static func isOn(setting: Bool, since: TimeInterval?, now: TimeInterval) -> Bool {
        guard setting, let since else { return false }
        return now - since < lasts && now >= since - 60
    }

    /// Hours left of the day, rounded up (shown beside the switch).
    static func hoursLeft(since: TimeInterval?, now: TimeInterval) -> Int {
        guard let since else { return 0 }
        return max(0, Int(((lasts - (now - since)) / 3600).rounded(.up)))
    }

    /// Whether one more clip may be kept.
    static func mayKeep(clips: Int, bytes: Int) -> Bool { clips < maxClips && bytes < maxBytes }

    /// The samples of a phrase of speech to keep: from `lead` before it began to where it ended, at most `longest`;
    /// nil for a sound too short to be speech. `oldest`: the first sample still held in memory.
    static func speechWindow(start: Int, end: Int, oldest: Int) -> Range<Int>? {
        guard end - start >= Int(shortestPhrase * Double(sampleRate)) else { return nil }
        let from = max(oldest, start - Int(lead * Double(sampleRate)))
        let to = min(end, from + Int(longest * Double(sampleRate)))
        return to > from ? from..<to : nil
    }

    /// A candidate's samples: from half a second before its phrase, `candidateSeconds`, cut at what has come in.
    static func candidateWindow(start: Int, received: Int, oldest: Int) -> Range<Int>? {
        let from = max(oldest, start - Int(0.5 * Double(sampleRate)))
        let to = min(received, from + Int(candidateSeconds * Double(sampleRate)))
        return to > from ? from..<to : nil
    }

    /// The clip's file: "ambient/20261114-231500-123-speech.wav" (its time, in the Mac's time zone).
    static func file(at date: Date, candidate: Bool) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "ambient/\(format.string(from: date))-\(candidate ? "candidate" : "speech").wav"
    }

    /// A wake that opened a turn and came to nothing (false-wake's quiet close).
    static let falseWake = "false-wake"

    /// The wake check's path, as the manifest keeps it: whether it woke, and how; nothing of what was said.
    static func outcome(path: String) -> String {
        ["voice", "whisper", "recognizer", "rejected", falseWake].contains(path) ? path : "other"
    }
}
