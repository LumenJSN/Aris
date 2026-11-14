//
//  ArisListener+Locale.swift
//  Aris
//
//  The language the recogniser listens in, from the languages setting, the Mac's languages and what the recogniser
//  has (ArisHearingLocale decides; this reads the three). At launch the recogniser's list is asked for once and the
//  language's speech model installed ahead of the first turn; when the languages setting changes, the new one's too.
//  Both engines (ArisListenEngine) are asked the same way; the older one has no model to install.
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

extension ArisListener {
    /// At launch: which languages the recogniser has, then the speech model for the one Aris listens in, and again
    /// whenever the languages setting changes. The older engine (macOS 14 and 15) has its own list and no model to
    /// install: it is the language the same rule picks (ArisHearingLocale, the first of Aris's languages it has), on
    /// the Mac when it has that language's on-device model.
    static func prepareHearing() async {
        let engine = ArisListenEngine.current()
        var supported: [String] = []
        if engine == .analyzer, #available(macOS 26.0, *) {
            supported = await ArisAnalyzerRecognizer.supportedLocales()
        } else {
            supported = ArisSFSpeechTasks.supportedLocales()
        }
        if !supported.isEmpty { ArisHearing.supported = supported }
        NSLog("Aris: listening in \(ArisHearing.locale.identifier) (\(engine.rawValue) engine\(placeNote(engine)))")
        await prepareSpeechAssets(locale: ArisHearing.locale)
        for await _ in Defaults.updates(.arisLanguages, initial: false) {
            NSLog("Aris: the languages changed; listening in \(ArisHearing.locale.identifier)")
            await prepareSpeechAssets(locale: ArisHearing.locale)
        }
    }

    private static func placeNote(_ engine: ArisListenEngine) -> String {
        guard engine == .legacy, let place = ArisSFSpeechTasks.place(ArisHearing.locale) else { return "" }
        return place == .onDevice ? ", on this Mac" : ", on Apple's servers"
    }
}

/// What Settings › 목소리 · 언어 › 듣기 엔진 shows for this Mac now (ArisListenEngineWords.settingsLine).
@MainActor
enum ArisHearingShown {
    static func line(defaults: UserDefaults = .standard) -> String {
        let major = ArisListenEngine.osMajor, force = defaults.bool(forKey: ArisListenEngine.forceLegacyKey)
        let engine = ArisListenEngine.pick(osMajor: major, forceLegacy: force)
        let place = engine == .legacy ? ArisSFSpeechTasks.place(ArisHearing.locale) : nil
        return ArisListenEngineWords.settingsLine(engine: engine, place: place, osMajor: major,
                                                  forced: ArisListenEngine.forced(osMajor: major, forceLegacy: force))
    }
}
