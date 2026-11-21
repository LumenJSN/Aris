//
//  ArisVoiceID.swift
//  Aris
//
//  The owner's voice at work (F1, ARCHITECTURE Part 3): the switch (`arisOwnerVoice`, off until the user has tried it), the
//  print (ArisVoiceIDStore, Keychain, this Mac only), and the three things the rest of Aris asks of it:
//  - check: is this utterance the owner's? (ArisVoiceMatcher; nil when the switch is off or there is no print yet,
//    which every caller reads as "nothing checked": today's behaviour);
//  - learn: an utterance spoken with the talk key held moves the print (ArisVoiceDecisions.learns), so it improves
//    with use and needs no setup step; the enrolment sheet adds a few sentences and the wake word's own recordings at
//    once;
//  - forget: the print is deleted, and with it every effect of this feature.
//  Every vector is made here, on this Mac, by ArisVoiceEmbedder; no audio, vector or score is sent to any model or
//  service, and only a verdict and its score (never the print) reach the log. The work is synchronous and takes about
//  60 ms per utterance: callers run it off the main thread. Foundation and Core ML only (tested from files).
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "voiceid")

final class ArisVoiceID: @unchecked Sendable {
    /// Settings › 부르기 › 내 목소리만 듣기 (the app's own defaults); off by default. Never "arisVoiceID": that key is the
    /// ElevenLabs voice the speaker uses (a String), so the two overwrote each other and a voice id that starts with a
    /// digit read as "on" (VM run 2026-11-19, D2).
    static let key = "arisOwnerVoice"
    /// Posted (main queue) when the print or the switch changed, for Settings.
    static let changed = Notification.Name("ArisVoiceIDChanged")

    static let shared = ArisVoiceID(store: ArisVoiceIDKeychain(), embedder: .shared, isOn: { UserDefaults.standard.bool(forKey: key) })

    /// One utterance, measured: the voice in it and its vector.
    struct Utterance: Equatable {
        let seconds: Double
        let vector: [Float]?
    }

    /// What Settings shows.
    struct Status: Equatable {
        var on = false
        var enrolled = false
        var samples = 0
        var seconds = 0.0
        /// The models are in the app and load.
        var available = true
    }

    private let lock = NSLock()
    private let store: ArisVoiceIDStoring
    private let embedder: ArisVoiceEmbedder
    private let isOnNow: () -> Bool
    private let now: () -> Date
    private var cached: ArisVoiceProfile??
    /// The speakers of the last turns, by turn (the request reads its own: ArisAgentClient).
    private var speakers: [ArisTurnID: ArisTurnSpeaker] = [:]
    /// When a turn last closed for its voice (uptime seconds), for the second chance.
    private var closedAt: Double?

    init(store: ArisVoiceIDStoring, embedder: ArisVoiceEmbedder, isOn: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.embedder = embedder
        self.isOnNow = isOn
        self.now = now
    }

    var isOn: Bool { isOnNow() }

    /// The print, as stored (nil: none, or one from other models).
    var profile: ArisVoiceProfile? {
        lock.withLock {
            if let cached { return cached }
            let loaded = store.load().flatMap { ArisVoiceProfile.decoded($0, model: ArisVoiceEmbedder.modelID) }
            cached = .some(loaded)
            return loaded
        }
    }

    var status: Status {
        let profile = self.profile
        return Status(on: isOn, enrolled: profile?.isEnrolled == true, samples: profile?.samples ?? 0, seconds: profile?.seconds ?? 0,
                      available: embedder.available)
    }

    // MARK: - Measuring

    /// The utterance's voice and vector (16 kHz mono); nil when there is no voice in it.
    func utterance(_ samples: [Float]) -> Utterance? {
        let trimmed = ArisVoiceClip.trimmed(samples)
        guard !trimmed.isEmpty else { return nil }
        let seconds = ArisVoiceClip.voicedSeconds(trimmed)
        return Utterance(seconds: seconds, vector: seconds >= ArisVoiceMatcher.fewestSeconds ? embedder.vector(trimmed) : nil)
    }

    /// Whether the utterance is the owner's; nil when nothing is checked (the switch off, no print yet).
    func check(_ samples: [Float]) -> ArisVoiceMatch? {
        guard isOn, let profile, profile.isEnrolled else { return nil }
        guard let utterance = utterance(samples) else { return .unsure("too-short") }
        return ArisVoiceMatcher.match(utterance.vector, seconds: utterance.seconds, profile: profile)
    }

    /// A turn's audio at its end: its verdict (nil: nothing checked) and, for a held key, the print learns from it.
    func turnEnded(_ samples: [Float], entry: ArisTurnEntry) -> ArisVoiceMatch? {
        guard isOn, ArisVoiceDecisions.checks(entry) || entry == .keyHeld else { return nil }
        let profile = self.profile
        guard !samples.isEmpty else { return ArisVoiceDecisions.noAudio(on: true, enrolled: profile?.isEnrolled == true, entry: entry) }
        guard let utterance = utterance(samples) else {
            return profile?.isEnrolled == true && ArisVoiceDecisions.checks(entry) ? .unsure("too-short") : nil
        }
        let match = profile?.isEnrolled == true ? ArisVoiceMatcher.match(utterance.vector, seconds: utterance.seconds, profile: profile) : nil
        if ArisVoiceDecisions.learns(entry: entry, seconds: utterance.seconds, match: match), let vector = utterance.vector {
            add([(vector, utterance.seconds)])
        }
        return ArisVoiceDecisions.checks(entry) ? match : nil
    }

    // MARK: - The print

    /// The enrolment sheet's sentences and the wake word's recordings: every clip with enough voice goes into the print,
    /// except one clearly in another voice than the print already holds. Returns how many went in.
    @discardableResult
    func enrol(_ clips: [[Float]]) -> Int {
        let utterances = clips.compactMap(utterance).filter { $0.seconds >= ArisVoiceMatcher.fewestSeconds }
        let current = profile
        let kept: [([Float], Double)] = utterances.compactMap { utterance in
            guard let vector = utterance.vector else { return nil }
            if let current, current.isEnrolled,
               ArisVoiceMatcher.match(vector, seconds: utterance.seconds, profile: current).verdict == .notOwner { return nil }
            return (vector, utterance.seconds)
        }
        add(kept)
        return kept.count
    }

    private func add(_ utterances: [([Float], Double)]) {
        guard !utterances.isEmpty else { return }
        let changed: Bool = lock.withLock {
            let base = (cached ?? nil) ?? store.load().flatMap { ArisVoiceProfile.decoded($0, model: ArisVoiceEmbedder.modelID) }
                ?? ArisVoiceProfile.empty(model: ArisVoiceEmbedder.modelID, at: now())
            let next = base.adding(utterances.map { (vector: $0.0, seconds: $0.1) }, at: now())
            guard next != base, let data = next.encoded() else { return false }
            // Kept in memory only when the Keychain took it: a print that isn't stored isn't used either.
            guard store.save(data) else { return false }
            cached = .some(next)
            return true
        }
        if changed {
            log.notice("voice id: the print learned \(utterances.count, privacy: .public) utterance(s)")
            announce()
        }
    }

    /// 목소리 정보 지우기: the print is gone, and Aris is as it was before it.
    @discardableResult
    func forget() -> Bool {
        let gone: Bool = lock.withLock {
            guard store.delete() else { return false }
            cached = .some(nil)
            speakers = [:]
            closedAt = nil
            return true
        }
        if gone { log.notice("voice id: the print was deleted") }
        announce()
        return gone
    }

    /// The switch changed (Settings): the print stays; with the switch off nothing is checked or learned.
    func switched() { announce() }

    private func announce() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.changed, object: nil) }
    }

    // MARK: - Per turn

    func note(_ speaker: ArisTurnSpeaker, for turn: ArisTurnID?) {
        guard let turn else { return }
        lock.withLock {
            speakers[turn] = speaker
            if speakers.count > 16, let oldest = speakers.keys.min() { speakers[oldest] = nil }
        }
    }

    /// The speaker of `turn`, when its voice was checked.
    func speaker(for turn: ArisTurnID?) -> ArisTurnSpeaker? {
        guard let turn else { return nil }
        return lock.withLock { speakers[turn] }
    }

    func closedForVoice(at uptime: Double) { lock.withLock { closedAt = uptime } }

    /// When the notice about a voice close last came (uptime seconds).
    private var noticedAt: Double?

    /// Whether the notice may come now; if so, it is counted as come.
    func takeNotice(at uptime: Double) -> Bool {
        lock.withLock {
            guard ArisVoiceDecisions.noticeDue(last: noticedAt, now: uptime) else { return false }
            noticedAt = uptime
            return true
        }
    }

    var lastVoiceClose: Double? { lock.withLock { closedAt } }
}
