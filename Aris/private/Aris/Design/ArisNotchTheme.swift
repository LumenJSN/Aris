//
//  ArisNotchTheme.swift
//  Aris
//
//  The open notch's look as one choice in Settings › 노치 (테마): four looks that were only reachable by hidden
//  preferences until now. A theme changes the notch's surface only, never its controls or layout. It is nothing of
//  its own: a pair of the two preferences that already draw the notch, the glass (ArisGlassLook, `arisGlassLook`) and
//  the voice look (ArisVoiceLook, `arisVoiceLook`), so nothing stored is renamed. 기본 leaves both unset, as a fresh
//  install has them; 밝은 아래 is the light-bottom look's surface alone (`surface-light`). A value set by hand that is
//  none of the four (the frosted glass, the whole light-bottom look with its own controls…) keeps working; the picker
//  then shows none picked.
//  The glass is read as the notch opens and the voice look as the notch opens or a voice state begins, so a new theme
//  shows the next time the notch opens. Foundation only (tested).
//

import Foundation

enum ArisNotchTheme: String, CaseIterable, Equatable {
    /// The shipped glass: the frosted private glass under the black (ArisGlassLook.privateGlass).
    case standard
    /// The same black over the public clear glass: what is behind the notch shows through, sharp.
    case clear
    /// Aris's older floor: black never under 80 % anywhere, over clear glass.
    case solid
    /// Black at the top thinning evenly to a light grey at the bottom, its rim and shadow: the surface only.
    case lightBottom = "light-bottom"

    /// What the glass preference holds for this theme; nil: unset (the shipped glass).
    var glassValue: String? {
        switch self {
        case .standard, .lightBottom: nil
        case .clear: ArisGlassLook.clearGlass.rawValue
        case .solid: ArisGlassLook.floor.rawValue
        }
    }

    /// What the voice look preference holds for this theme; nil: unset (Aris's own).
    var voiceValue: String? { self == .lightBottom ? ArisVoiceLook.surfaceLight.rawValue : nil }

    /// The theme the two stored values make, read the way the notch reads them; nil when they make a look that is
    /// not one of the four (a look set by hand: then no theme is shown as picked).
    static func stored(glass: String?, voice: String?) -> ArisNotchTheme? {
        switch ArisVoiceLook.resolve(voice) {
        case .surfaceLight: return .lightBottom
        case .siri, .siriFrost: return nil
        case .aris: break
        }
        return allCases.first { $0 != .lightBottom && ArisGlassLook(preference: $0.glassValue) == ArisGlassLook(preference: glass) }
    }

    /// Writes the theme into `defaults`: each preference set to the theme's value, or removed where the theme leaves
    /// it unset.
    func write(to defaults: UserDefaults) {
        for (key, value) in [(ArisGlassLook.preferenceKey, glassValue), (ArisVoiceLook.key, voiceValue)] {
            if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    /// Its name in the picker, written in Korean as every settings row is (ArisNotchLookSetting has the English).
    var title: String {
        switch self {
        case .standard: "기본"
        case .clear: "또렷한 유리"
        case .solid: "검정"
        case .lightBottom: "밝은 아래"
        }
    }

    var englishTitle: String {
        switch self {
        case .standard: "Default"
        case .clear: "Clear glass"
        case .solid: "Solid black"
        case .lightBottom: "Light bottom"
        }
    }
}
