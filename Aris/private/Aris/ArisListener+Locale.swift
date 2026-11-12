//
//  ArisListener+Locale.swift
//  Aris
//
//  The language the recogniser listens in, from the languages setting, the Mac's languages and what the recogniser
//  has (ArisHearingLocale decides; this reads the three). At launch the recogniser's list is asked for once and the
//  language's speech model installed ahead of the first turn; when the languages setting changes, the new one's too.
//

import Defaults
import Foundation
import Speech

@MainActor
enum ArisHearing {
    /// The recogniser's locales, as it names them. Korean alone until it has been asked (prepare).
    static var supported = [ArisHearingLocale.fallback]

    /// The languages setting was ever changed (untouched, it is what the Mac's own languages start it with).
    static var languagesChosen: Bool { UserDefaults.standard.object(forKey: Defaults.Keys.arisLanguages.name) != nil }

    static var locale: Locale {
        Locale(identifier: ArisHearingLocale.pick(chosen: Defaults[.arisLanguages], chosenByUser: languagesChosen,
                                                  system: Locale.preferredLanguages, supported: supported))
    }
}

@available(macOS 26.0, *)
extension ArisListener {
    /// At launch: which languages the recogniser has, then the speech model for the one Aris listens in, and again
    /// whenever the languages setting changes.
    static func prepareHearing() async {
        let supported = await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        if !supported.isEmpty { ArisHearing.supported = supported }
        NSLog("Aris: listening in \(ArisHearing.locale.identifier)")
        await prepareSpeechAssets(locale: ArisHearing.locale)
        for await _ in Defaults.updates(.arisLanguages, initial: false) {
            NSLog("Aris: the languages changed; listening in \(ArisHearing.locale.identifier)")
            await prepareSpeechAssets(locale: ArisHearing.locale)
        }
    }
}
