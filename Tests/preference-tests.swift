// Acceptance tests for the clean-room preference values (cleanroom-specs/13-preferences-and-data.md).
import Foundation

func runPreferenceTests() {
    check(DisplayMode.allCases.map(\.rawValue) == ["preferredDisplay", "fallbackIfPreferredUnavailable", "activeDisplay", "allDisplays"],
          "prefs: display modes keep their stored raw values")
    check(HideNotchOption.allCases.map(\.rawValue) == ["always", "nowPlayingOnly", "never"]
          && SneakPeekStyle.allCases.map(\.rawValue) == ["standard", "inline"], "prefs: full-screen and peek raw values")
    check(WindowHeightMode.matchMenuBar.rawValue == "Match menu bar height" && WindowHeightMode.matchRealNotchSize.rawValue == "Match real notch height"
          && WindowHeightMode.custom.rawValue == "Custom height", "prefs: height modes are stored as English sentences")
    let sources = ["nowPlaying", "Now Playing", "youtubeMusic", "YouTube Music", "appleMusic", "Apple Music", "spotify", "Spotify", "x"]
    check(sources.map { MediaControllerType(rawValue: $0) } == [.nowPlaying, .nowPlaying, .nowPlaying, .nowPlaying, .appleMusic, .appleMusic, .spotify, .spotify, nil],
          "prefs: music sources decode every stored spelling; YouTube Music becomes Now Playing")
    check(MediaControllerType(nowPlayingBundleIdentifier: "com.apple.Music") == .appleMusic
          && MediaControllerType(nowPlayingBundleIdentifier: "com.spotify.client") == .spotify
          && MediaControllerType(nowPlayingBundleIdentifier: "com.google.Chrome") == nil, "prefs: a now-playing app's direct source")
    check(MediaControllerType.appleMusic.localizedString == "Apple Music", "prefs: source names")
    let colors = ["white", "White", "albumArt", "Match album art", "accent", "Accent color", "red"]
    check(colors.map { SliderColorEnum(rawValue: $0) } == [.white, .white, .albumArt, .albumArt, .accent, .accent, nil],
          "prefs: slider colours decode every stored spelling")
    check(SliderColorEnum.albumArt.localizedString == "Match album art", "prefs: slider colour names")
    let stored: [SneakPeekStyle?] = [ArisRawChoice.decode("inline"), ArisRawChoice.decode("\"inline\""), ArisRawChoice.decode("bogus")]
    check(stored == [.inline, .inline, nil], "prefs: a choice reads as its raw value or as a JSON string")
    check(SneakPeekStyle(rawValue: "Default") == .standard && SneakPeekStyle(rawValue: "Inline") == .inline, "prefs: old peek spellings still read")
    check(ArisRawChoice.encode(DisplayMode.activeDisplay, json: true) == "\"activeDisplay\""
          && ArisRawChoice.encode(DisplayMode.activeDisplay, json: false) == "activeDisplay", "prefs: a choice writes as JSON or raw")
    let height: WindowHeightMode? = ArisRawChoice.decode("\"Custom height\"")
    check(height == .custom, "prefs: sentence raw values read JSON-encoded too")

    check(AppLanguage.hasValue(["a": "", "b": "Hallo"]) && !AppLanguage.hasValue(["a": ""]) && !AppLanguage.hasValue([:]),
          "language: a localization counts only with a non-empty string")
    let picked = AppLanguage.choices(["ko", "de", "en"])
    let names = picked.map(\.displayName)
    check(Set(picked.map(\.rawValue)) == ["ko", "de", "en"]
          && zip(names, names.dropFirst()).allSatisfy { $0.localizedCaseInsensitiveCompare($1) != .orderedDescending },
          "language: sorted by their own names (in the user's collation): \(names)")
    check(AppLanguage.system.displayName == "System default" && AppLanguage(rawValue: "de").displayName == "Deutsch",
          "language: names in their own language, capitalised")
    let defaults = UserDefaults(suiteName: testSuiteName("aris-language-tests"))!
    AppLanguage(rawValue: "ko").applyAppleLanguagesOverride(defaults)
    check(defaults.stringArray(forKey: "AppleLanguages") == ["ko"], "language: choosing one writes AppleLanguages")
    AppLanguage.system.applyAppleLanguagesOverride(defaults)
    check(defaults.persistentDomain(forName: testSuiteName("aris-language-tests"))?["AppleLanguages"] == nil, "language: system removes the override")
    defaults.removePersistentDomain(forName: testSuiteName("aris-language-tests"))
}
