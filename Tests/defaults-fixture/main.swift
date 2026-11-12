// Defaults fixture (cleanroom-specs/13 test 2, QUESTIONS A16): every choice key, written in the shapes older builds
// left in the plist (JSON string and raw string, legacy spellings), must read back through the real Defaults package
// and the new bridges; writes must land in the old shape (displayMode as a JSON string, the rest raw).
import Defaults
import Foundation

nonisolated(unsafe) var failures = 0
func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if condition { print("ok   \(name)") } else { failures += 1; print("FAIL \(name) (line \(line))") }
}

let domain = "aris-defaults-fixture"
let suite = UserDefaults(suiteName: domain)!
suite.removePersistentDomain(forName: domain)

func reads<Value: Defaults.Serializable & Equatable>(_ key: String, _ stored: [(String, Value)], default fallback: Value) {
    let defaultsKey = Defaults.Key<Value>(key, default: fallback, suite: suite)
    for (shape, expected) in stored {
        suite.set(shape, forKey: key)
        check(Defaults[defaultsKey] == expected, "fixture: \(key) stored as \(shape) reads as \(expected)")
    }
    suite.removeObject(forKey: key)
    check(Defaults[defaultsKey] == fallback, "fixture: \(key) absent reads as the default \(fallback)")
}

func writes<Value: Defaults.Serializable>(_ key: String, _ value: Value, as shape: String, default fallback: Value) {
    let defaultsKey = Defaults.Key<Value>(key, default: fallback, suite: suite)
    Defaults[defaultsKey] = value
    check(suite.string(forKey: key) == shape, "fixture: \(key) = \(value) is written as \(shape) (\(suite.string(forKey: key) ?? "nil"))")
}

reads("displayMode", [("\"allDisplays\"", DisplayMode.allDisplays), ("\"preferredDisplay\"", .preferredDisplay),
                      ("\"activeDisplay\"", .activeDisplay), ("\"fallbackIfPreferredUnavailable\"", .fallbackIfPreferredUnavailable),
                      ("activeDisplay", .activeDisplay), ("allDisplays", .allDisplays)], default: .fallbackIfPreferredUnavailable)
writes("displayMode", DisplayMode.activeDisplay, as: "\"activeDisplay\"", default: .fallbackIfPreferredUnavailable)

reads("hideNotchOption", [("always", HideNotchOption.always), ("nowPlayingOnly", .nowPlayingOnly), ("never", .never),
                          ("\"never\"", .never)], default: .nowPlayingOnly)
writes("hideNotchOption", HideNotchOption.never, as: "never", default: .nowPlayingOnly)

reads("sneakPeekStyles", [("standard", SneakPeekStyle.standard), ("inline", .inline), ("Default", .standard), ("Inline", .inline),
                          ("\"inline\"", .inline)], default: .standard)
writes("sneakPeekStyles", SneakPeekStyle.inline, as: "inline", default: .standard)

reads("mediaController", [("nowPlaying", MediaControllerType.nowPlaying), ("appleMusic", .appleMusic), ("spotify", .spotify),
                          ("Now Playing", .nowPlaying), ("Apple Music", .appleMusic), ("Spotify", .spotify),
                          ("youtubeMusic", .nowPlaying), ("YouTube Music", .nowPlaying), ("\"spotify\"", .spotify)], default: .nowPlaying)
writes("mediaController", MediaControllerType.appleMusic, as: "appleMusic", default: .nowPlaying)

for key in ["notchHeightMode", "nonNotchHeightMode"] {
    reads(key, [("Match menu bar height", WindowHeightMode.matchMenuBar), ("Match real notch height", .matchRealNotchSize),
                ("Custom height", .custom), ("\"Custom height\"", .custom)], default: .matchMenuBar)
    writes(key, WindowHeightMode.custom, as: "Custom height", default: .matchMenuBar)
}

reads("sliderUseAlbumArtColor", [("white", SliderColorEnum.white), ("albumArt", .albumArt), ("accent", .accent),
                                 ("White", .white), ("Match album art", .albumArt), ("Accent color", .accent),
                                 ("\"accent\"", .accent)], default: .white)
writes("sliderUseAlbumArtColor", SliderColorEnum.albumArt, as: "albumArt", default: .white)

reads("appLanguage", [("system", AppLanguage.system), ("ko", AppLanguage(rawValue: "ko")), ("zh-Hans", AppLanguage(rawValue: "zh-Hans")),
                      ("\"en\"", AppLanguage(rawValue: "en"))], default: .system)
writes("appLanguage", AppLanguage(rawValue: "ko"), as: "ko", default: .system)

// calendarSelectionState is read and written by the calendar store itself (JSON string, old shape).
suite.set(#"{"selected":{"_0":["A","B"]}}"#, forKey: ArisCalendarSelection.key)
check(ArisCalendarSelection.load(from: suite) == .selected(["A", "B"]), "fixture: calendarSelectionState in the old JSON shape reads")
ArisCalendarSelection.all.save(to: suite)
check(suite.string(forKey: ArisCalendarSelection.key) == #"{"all":{}}"#, "fixture: calendarSelectionState is written in the old JSON shape")

suite.removePersistentDomain(forName: domain)
print(failures == 0 ? "\nFIXTURE PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
