//
//  ArisVoiceSettings.swift
//  Aris
//
//  The chosen ElevenLabs voice's own saved settings (its sliders on ElevenLabs: stability, similarity, style, speaker
//  boost). A request's `voice_settings` replaces the voice's stored ones, and whatever it leaves out takes ElevenLabs'
//  schema defaults (stability .5, similarity .75, style 0), not the voice's: Aris sent the speed alone, so every line
//  was read at those defaults, flatter than the same voice on ElevenLabs' site. Now the voice's own settings are fetched
//  once (GET /v1/voices/{id}/settings), kept for the run, fetched again for another voice, and sent with Aris's speed.
//

import Foundation

struct ArisVoiceSettings: Equatable, Sendable {
    var stability: Double?
    var similarityBoost: Double?
    var style: Double?
    var useSpeakerBoost: Bool?

    /// `GET /v1/voices/{id}/settings`. Each slider is kept only as a number in 0...1; nil when the body isn't settings.
    static func parse(_ data: Data) -> ArisVoiceSettings? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func unit(_ key: String) -> Double? {
            guard let number = json[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let value = number.doubleValue
            return value.isFinite ? min(1, max(0, value)) : nil
        }
        let boost = (json["use_speaker_boost"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? $0.boolValue : nil }
        let settings = ArisVoiceSettings(stability: unit("stability"), similarityBoost: unit("similarity_boost"), style: unit("style"),
                                         useSpeakerBoost: boost)
        return settings == ArisVoiceSettings() ? nil : settings
    }

    /// Eleven v4 (and v3) take two of the sliders, stability and similarity; style and speaker boost are the v2 models'
    /// (ElevenLabs' Eleven v4 page: "Both variants use two voice settings: Stability and Similarity").
    static func takesStyle(model: String) -> Bool { !model.hasPrefix("eleven_v4") && !model.hasPrefix("eleven_v3") }

    /// The request's `voice_settings`: the voice's saved sliders the model takes, and Aris's speed (in ElevenLabs' range).
    func body(speed: Double, model: String) -> [String: Any] {
        var body: [String: Any] = ["speed": min(max(speed, ArisElevenLabs.speedRange.lowerBound), ArisElevenLabs.speedRange.upperBound)]
        if let stability { body["stability"] = stability }
        if let similarityBoost { body["similarity_boost"] = similarityBoost }
        guard Self.takesStyle(model: model) else { return body }
        if let style { body["style"] = style }
        if let useSpeakerBoost { body["use_speaker_boost"] = useSpeakerBoost }
        return body
    }
}

/// The current voice's saved settings, fetched once and kept; asking for another voice fetches that one's. A fetch that
/// failed isn't tried again for `retryAfter`, so a run without them doesn't wait on every sentence.
actor ArisVoiceSettingsCache {
    typealias Fetch = @Sendable (_ voiceID: String, _ key: String) async -> ArisVoiceSettings?

    static let shared = ArisVoiceSettingsCache { voiceID, key in await ArisElevenLabs.savedSettings(voiceID: voiceID, key: key) }

    private let fetch: Fetch
    private let retryAfter: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private var voiceID: String?
    private var saved: ArisVoiceSettings?
    private var failedAt: ContinuousClock.Instant?
    /// The fetch in flight for `voiceID`, shared by everyone asking meanwhile.
    private var pending: Task<ArisVoiceSettings?, Never>?

    init(retryAfter: Duration = .seconds(60), now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }, fetch: @escaping Fetch) {
        self.fetch = fetch
        self.retryAfter = retryAfter
        self.now = now
    }

    func settings(for voiceID: String, key: String) async -> ArisVoiceSettings? {
        if voiceID != self.voiceID {
            self.voiceID = voiceID
            saved = nil
            failedAt = nil
            pending = nil
        }
        if let saved { return saved }
        if let failedAt, now() - failedAt < retryAfter { return nil }
        let task = pending ?? Task { [fetch] in await fetch(voiceID, key) }
        pending = task
        let got = await task.value
        // Another voice was asked for meanwhile: this answer is that old voice's, kept by nobody.
        guard self.voiceID == voiceID else { return got }
        pending = nil
        if let got { saved = got } else { failedAt = now() }
        return got
    }
}
