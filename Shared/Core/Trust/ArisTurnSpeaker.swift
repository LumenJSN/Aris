//
//  ArisTurnSpeaker.swift
//  Shared/Core (aris-agent, app, tests)
//
//  Who said a turn's words, as far as Aris knows (F1, the owner's voice: provenance gains a speaker field). Typed, or
//  spoken with the talk key held, or spoken with a voice that matched the owner's print, is the owner. A hands-free
//  utterance whose voice did not match (or could not be told) can still be answered, but for the trust table it counts
//  like content: nothing outward or permanent happens without asking (ArisTrustPolicy). With no print, or with the
//  voice check off, nothing was checked and every turn is the owner's, as before. Pure.
//

import Foundation

enum ArisTurnSpeaker: String, Codable, CaseIterable, Sendable {
    /// Typed in the composer.
    case typed
    /// Spoken while the talk key was held down: holding the key proves it is the owner.
    case keyHeld
    /// Spoken hands-free, and the voice matched the owner's print.
    case voiceMatched
    /// Nothing was checked (no print, the check off, or no audio): as today, the owner.
    case notChecked
    /// Spoken hands-free, and the voice did not match the owner's print or could not be told from another.
    case unverified

    /// Whether the words count as the owner's for the trust table.
    var countsAsOwner: Bool { self != .unverified }

    /// The speaker a request names (the app's `voice` field); anything unknown or missing is `notChecked`.
    static func named(_ raw: String?) -> ArisTurnSpeaker { raw.flatMap(ArisTurnSpeaker.init(rawValue:)) ?? .notChecked }
}
