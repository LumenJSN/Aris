//
//  ArisVoiceProfile.swift
//  Shared/Core (app, tests)
//
//  The owner's voice print (F1): one direction in the embedding model's space, the mean of the utterances it was
//  made from, and how many there were. It holds no audio and no words, only the 256 numbers and two counts, and it
//  never leaves the Mac (ArisVoiceIDStore keeps it in the Keychain, this device only, never synced).
//  The update rule: every utterance moves the print towards itself by 1/(n+1) while n is small, so the first ones are
//  an exact mean; past `steadyAt` each new one counts 1/steadyAt, so the print follows a voice that changes (a cold,
//  a new microphone) without one odd utterance moving it far. Pure: every change returns a new profile.
//

import Foundation

struct ArisVoiceProfile: Codable, Equatable, Sendable {
    static let version = 1
    /// Utterances (and seconds of voice in them) before the print is used at all: below this, behaviour is today's.
    static let enrolledAt = 3
    static let enrolledSeconds = 6.0
    /// Past this many utterances, each new one moves the print by 1/steadyAt.
    static let steadyAt = 40
    /// The sizes a print may have (the model's is 256): anything else is not one of ours.
    static let sizes = 64...1024

    let version: Int
    /// The embedding model the print was made with: a print from another model means nothing and is not used.
    let model: String
    /// Unit length.
    let centroid: [Float]
    /// Utterances it was made from, and their seconds of voice.
    let samples: Int
    let seconds: Double
    let created: Date
    let updated: Date

    /// A print with nothing in it yet.
    static func empty(model: String, at now: Date) -> ArisVoiceProfile {
        ArisVoiceProfile(version: version, model: model, centroid: [], samples: 0, seconds: 0, created: now, updated: now)
    }

    /// Enough of the owner's voice to tell it from others.
    var isEnrolled: Bool { samples >= Self.enrolledAt && seconds >= Self.enrolledSeconds && !centroid.isEmpty }

    /// The print with one more utterance in it; nil when the vector is not one this print can take.
    func adding(_ vector: [Float], seconds voiced: Double, at now: Date) -> ArisVoiceProfile? {
        guard voiced.isFinite, voiced > 0, Self.sizes.contains(vector.count), let unit = ArisVoiceVector.normalized(vector) else { return nil }
        let next: [Float]
        if centroid.isEmpty {
            next = unit
        } else {
            guard centroid.count == unit.count,
                  let moved = ArisVoiceVector.blended(centroid, unit, weight: 1 / Float(min(samples + 1, Self.steadyAt))) else { return nil }
            next = moved
        }
        return ArisVoiceProfile(version: version, model: model, centroid: next, samples: samples + 1, seconds: seconds + voiced,
                                created: created, updated: now)
    }

    /// The print made from several utterances at once (the enrolment sheet), on top of this one.
    func adding(_ utterances: [(vector: [Float], seconds: Double)], at now: Date) -> ArisVoiceProfile {
        utterances.reduce(self) { profile, utterance in profile.adding(utterance.vector, seconds: utterance.seconds, at: now) ?? profile }
    }

    // MARK: - Stored form

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    /// A stored print, if it is well formed and was made with `model`; anything else reads as no print.
    static func decoded(_ data: Data, model: String) -> ArisVoiceProfile? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let profile = try? decoder.decode(ArisVoiceProfile.self, from: data), profile.version == version, profile.model == model,
              profile.samples >= 0, profile.seconds.isFinite, profile.seconds >= 0 else { return nil }
        if profile.centroid.isEmpty { return profile.samples == 0 ? profile : nil }
        guard sizes.contains(profile.centroid.count), let unit = ArisVoiceVector.normalized(profile.centroid),
              zip(unit, profile.centroid).allSatisfy({ abs($0 - $1) < 1e-3 }) else { return nil }
        return profile
    }
}
