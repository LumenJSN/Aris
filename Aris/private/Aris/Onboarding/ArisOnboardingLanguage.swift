//
//  ArisOnboardingLanguage.swift
//  Aris
//
//  The onboarding's language: the app's one UI language (ArisUILanguage: its preferred languages, which include
//  Aris's own language override, the first one Aris is written in; English when none is). Voice lines are picked by that
//  language (OnboardingAudio/voice/<lang>/…); a language without a recording speaks through the system's speech
//  synthesizer in that same language, never another's voice. Pure.
//

import Foundation

enum ArisOnboardingLanguage {
    /// The first preferred language that has the onboarding, by the app's one rule; English when none does.
    static func choose(preferred: [String], available: Set<String>) -> String {
        ArisUILanguage.choose(preferred: preferred, available: available)
    }

    /// The synthesizer's voice for a language with no recording.
    static func synthesizerVoice(for language: String) -> String {
        switch language {
        case "ko": "ko-KR"
        case "en": "en-US"
        case "ja": "ja-JP"
        case "de": "de-DE"
        case "fr": "fr-FR"
        case "es": "es-ES"
        default: language
        }
    }

    /// A voice line's resource path (no extension) inside the app's Resources.
    static func voiceFile(_ name: String, language: String) -> String { "OnboardingAudio/voice/\(language)/\(name)" }

    /// A sound cue's resource path (no extension).
    static func cueFile(_ name: String) -> String { "OnboardingAudio/sfx/\(name)" }
}
