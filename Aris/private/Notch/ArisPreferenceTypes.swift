//
//  ArisPreferenceTypes.swift
//  Aris
//
//  The values behind the notch, music and display preferences, and the notch's own state and page enums. Raw
//  values are what earlier builds stored, so existing settings keep reading the same (cleanroom-specs/13);
//  legacy spellings still decode. The Defaults conformances are in ArisPreferences.swift.
//

import Foundation
import SwiftUI

/// A choice in the defaults: stored as its raw string, or (`json`) as a JSON string of it — the form Defaults gives a
/// Codable enum, which older builds used for `displayMode`. Either form reads.
enum ArisRawChoice {
    static func decode<Value: RawRepresentable>(_ stored: String) -> Value? where Value.RawValue == String {
        // No raw value starts with a quote, so a quoted string is the JSON form.
        if stored.hasPrefix("\""), let data = stored.data(using: .utf8), let text = try? JSONDecoder().decode(String.self, from: data) {
            return Value(rawValue: text)
        }
        return Value(rawValue: stored)
    }

    static func encode<Value: RawRepresentable>(_ value: Value, json: Bool) -> String? where Value.RawValue == String {
        guard json else { return value.rawValue }
        return (try? JSONEncoder().encode(value.rawValue)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Which display(s) get a notch.
enum DisplayMode: String, CaseIterable, Identifiable {
    case preferredDisplay, fallbackIfPreferredUnavailable, activeDisplay, allDisplays

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .preferredDisplay: "Use preferred display"
        case .fallbackIfPreferredUnavailable: "Automatically switch display if preferred is unavailable"
        case .activeDisplay: "Always follow active display"
        case .allDisplays: "Show on all displays"
        }
    }
}

/// When the notch hides for a full-screen app.
enum HideNotchOption: String, CaseIterable, Identifiable {
    case always, nowPlayingOnly, never

    var id: String { rawValue }
}

/// How a music change peeks out of the closed notch.
enum SneakPeekStyle: String, CaseIterable, Identifiable {
    case standard, inline

    var id: String { rawValue }

    /// Also reads the older "Default" / "Inline" spellings.
    init?(rawValue: String) {
        switch rawValue {
        case "standard", "Default": self = .standard
        case "inline", "Inline": self = .inline
        default: return nil
        }
    }
}

/// Where now-playing information comes from.
enum MediaControllerType: String, CaseIterable, Identifiable {
    case nowPlaying, appleMusic, spotify

    var id: String { rawValue }

    /// Also reads the spellings older builds stored; YouTube Music (retired) becomes Now Playing.
    init?(rawValue: String) {
        switch rawValue {
        case "nowPlaying", "Now Playing", "youtubeMusic", "YouTube Music": self = .nowPlaying
        case "appleMusic", "Apple Music": self = .appleMusic
        case "spotify", "Spotify": self = .spotify
        default: return nil
        }
    }

    /// The direct source for a now-playing app, if it has one.
    init?(nowPlayingBundleIdentifier: String) {
        switch nowPlayingBundleIdentifier {
        case "com.apple.Music": self = .appleMusic
        case "com.spotify.client": self = .spotify
        default: return nil
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .nowPlaying: "Now Playing"
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }

    var localizedString: String { String(localized: localizedResource) }
}

/// How a stored notch height follows the display. The raw values are English sentences, as stored.
enum WindowHeightMode: String, CaseIterable, Identifiable {
    case matchMenuBar = "Match menu bar height"
    case matchRealNotchSize = "Match real notch height"
    case custom = "Custom height"

    var id: String { rawValue }
}

/// The colour of the player's progress bar.
enum SliderColorEnum: String, CaseIterable, Identifiable {
    case white, albumArt, accent

    var id: String { rawValue }

    init?(rawValue: String) {
        switch rawValue {
        case "white", "White": self = .white
        case "albumArt", "Match album art": self = .albumArt
        case "accent", "Accent color": self = .accent
        default: return nil
        }
    }

    var localizedString: String {
        switch self {
        case .white: String(localized: "White", comment: "Player progress bar colour")
        case .albumArt: String(localized: "Match album art", comment: "Player progress bar colour")
        case .accent: String(localized: "Accent color", comment: "Player progress bar colour")
        }
    }
}

/// Whether a display's notch is open.
enum NotchState {
    case closed, open
}

/// The pages of the open notch.
enum NotchViews {
    case home, shelf, claude, aris
}


/// In-app notifications (any spelling works as long as poster and observer agree; these are the old strings).
extension Notification.Name {
    static let selectedScreenChanged = Notification.Name("SelectedScreenChanged")
    static let notchHeightChanged = Notification.Name("NotchHeightChanged")
    static let expandedDragDetectionChanged = Notification.Name("expandedDragDetectionChanged")
    static let accentColorChanged = Notification.Name("AccentColorChanged")
    static let sharingDidFinish = Notification.Name("com.lumenjsn.aris.sharingDidFinish")
}
