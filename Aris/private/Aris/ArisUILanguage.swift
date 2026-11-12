//
//  ArisUILanguage.swift
//  Aris
//
//  The one language Aris's own words are in (fresh install F5: on an English Mac the guide was English while cards and
//  failure lines were Korean, because three places each worked the language out their own way). It is the first of the
//  Mac's preferred languages that Aris is written in, Korean or English; the app-language setting comes first in that
//  list when it is set, since it overrides the Mac's order for this app. A Mac in neither reads English. The guide
//  (ArisOnboardingCopy), the team pages (ArisTeamCopy) and every status and card line (ArisUIWords) ask here.
//  Foundation only, so it is tested.
//

import Foundation

enum ArisUILanguage {
    /// The languages Aris's own words exist in.
    static let languages: Set<String> = ["ko", "en"]
    /// Where neither is preferred.
    static let fallback = "en"

    /// The first preferred language Aris has ("ko-KR" → "ko"); English when it has none of them.
    static func choose(preferred: [String], available: Set<String> = languages) -> String {
        for identifier in preferred {
            let code = String(identifier.split(separator: "-").first ?? Substring(identifier)).lowercased()
            if available.contains(code) { return code }
        }
        return fallback
    }

    /// The language for this run, read once (the app's language needs a restart to change anyway).
    static let code: String = choose(preferred: Locale.preferredLanguages)

    /// The UI reads English. A process with no app bundle (the tests, a tool) has no UI language of its own: its lines
    /// stay Korean, as the app's source is written.
    static var english: Bool { Bundle.main.bundleIdentifier != nil && code != "ko" }
}
