//
//  ArisTurnStats.swift
//  Aris
//
//  One turn in numbers, from the moment Aris stops listening: how long until it understood, until its
//  first sound, until done, how often it asked and was told no. aris-agent keeps them as JSON lines in
//  ~/.config/aris/aris/turns.jsonl, to see whether Aris gets faster and asks less.
//

import Foundation

struct ArisTurnStats {
    /// What was said is kept only this long: enough to recognise the request.
    static let heardLimit = 80

    private let startedAt: ContinuousClock.Instant
    private var said = ""
    private var path = ""
    private var tier = ""
    private var understoodAt: ContinuousClock.Instant?
    private var soundAt: ContinuousClock.Instant?
    private var confirms = 0
    private var declined = 0
    private var apple = ""
    private var whisper = ""
    /// The per-turn screenshot, logged as numbers (plan D4): never the image.
    private var capture: [String: Any]?
    private var shotCount: Int?

    init(startedAt: ContinuousClock.Instant) {
        self.startedAt = startedAt
    }

    /// The words are final and Aris picked a way: "local", "task", or "brain:<name>".
    mutating func heard(_ text: String, path: String, tier: String, at instant: ContinuousClock.Instant) {
        said = String(text.prefix(Self.heardLimit))
        self.path = path
        self.tier = tier
        understoodAt = instant
    }

    /// The turn turned out to be answered by someone else than first recorded (aris-agent itself, with no AI): its
    /// line says who.
    mutating func answered(by path: String) {
        self.path = path
    }

    /// Aris started to speak (only the first time counts).
    mutating func firstSound(at instant: ContinuousClock.Instant) {
        if soundAt == nil { soundAt = instant }
    }

    /// What each recognizer wrote, to tell a mishearing from a misunderstanding.
    mutating func recognized(apple: String, whisper: String?) {
        self.apple = String(apple.prefix(Self.heardLimit))
        self.whisper = String((whisper ?? "").prefix(Self.heardLimit))
    }

    /// How the turn's screenshot went: `source` "cursorDisplay"; bytes of the PNG, milliseconds to take it.
    /// `replaced`: circled shots went instead of it (the screenshot is dropped when a drawing exists).
    mutating func captured(source: String, ok: Bool, bytes: Int, ms: Int, retried: Bool, replaced: Bool = false) {
        capture = ["source": source, "ok": ok, "bytes": bytes, "ms": ms, "retried": retried]
        if replaced { capture?["replaced"] = true }
    }

    /// How many circled shots went with the turn.
    mutating func shots(_ count: Int) {
        shotCount = count
    }

    mutating func asked(allowed: Bool) {
        confirms += 1
        if !allowed { declined += 1 }
    }

    /// `outcome`: "ok", "error", "cancelled" or "unheard" (nothing in the turn was speech).
    func line(outcome: String, at instant: ContinuousClock.Instant) -> [String: Any] {
        var line: [String: Any] = ["heard": said, "path": path, "tier": tier, "outcome": outcome,
                                   "confirms": confirms, "declined": declined, "totalMs": milliseconds(to: instant)]
        if !apple.isEmpty { line["apple"] = apple }
        if !whisper.isEmpty { line["whisper"] = whisper }
        if let understoodAt { line["understoodMs"] = milliseconds(to: understoodAt) }
        if let soundAt { line["firstSoundMs"] = milliseconds(to: soundAt) }
        if let capture { line["capture"] = capture }
        if let shotCount { line["shots"] = shotCount }
        return line
    }

    private func milliseconds(to instant: ContinuousClock.Instant) -> Int {
        Int((instant - startedAt) / .milliseconds(1))
    }
}

/// Who answered a turn, for turns.jsonl's "path" and the log: aris-agent itself when it said so (no AI was asked).
enum ArisTurnPath {
    static let helper = "helper"

    /// The name the log's "… answered" line gives: the brain that was asked, or aris-agent when it answered itself.
    static func answerer(brain: String, helper: Bool) -> String { helper ? "aris-agent" : brain }
}
