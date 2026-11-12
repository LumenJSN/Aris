//
//  ArisPreferences.swift
//  Aris
//
//  The notch, music, shelf, calendar and appearance preferences (key strings, types and defaults from
//  cleanroom-specs/13), the in-app notification names and the two global shortcut names. How the choices are stored is
//  in ArisPreferenceStorage.swift.
//

import Defaults
import Foundation
import KeyboardShortcuts

/// The Quick Share provider used when none was chosen: AirDrop if the system offers it, else the first one found,
/// else the system share picker.
enum ArisQuickShareDefault {
    static let airDrop = "AirDrop"
    static let systemShareMenu = "System Share Menu"

    static func pick(_ available: [String]) -> String {
        available.contains(airDrop) ? airDrop : available.first ?? systemShareMenu
    }

    static var current: String {
        guard Thread.isMainThread else { return systemShareMenu }
        return MainActor.assumeIsolated { pick(QuickShareService.shared.availableProviders.map(\.id)) }
    }
}

extension Defaults.Keys {
    // Notch & windows
    static let displayMode = Key<DisplayMode>("displayMode", default: .fallbackIfPreferredUnavailable)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let followActiveDisplay = Key<Bool>("followActiveDisplay", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let musicLiveActivityEnabled = Key<Bool>("musicLiveActivityEnabled", default: true)
    static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let notchHeightMode = Key<WindowHeightMode>("notchHeightMode", default: .matchRealNotchSize)
    static let nonNotchHeightMode = Key<WindowHeightMode>("nonNotchHeightMode", default: .matchMenuBar)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let enableOpeningAnimation = Key<Bool>("enableOpeningAnimation", default: true)
    static let animationSpeedMultiplier = Key<Double>("animationSpeedMultiplier", default: 1.0)
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let enableHorizontalMediaGestures = Key<Bool>("enableHorizontalMediaGestures", default: false)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200)
    static let normalizeGestureDirection = Key<Bool>("normalizeGestureDirection", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    static let hideNonNotchedFromMissionControl = Key<Bool>("hideNonNotchedFromMissionControl", default: true)
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    /// The user's look page has the toggle; nothing reads it yet.
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)

    // Music
    static let mediaController = Key<MediaControllerType>("mediaController", default: .nowPlaying)
    static let didChooseMediaController = Key<Bool>("didChooseMediaController", default: false)
    static let didMigrateMediaControllerChoice = Key<Bool>("didMigrateMediaControllerChoice", default: false)
    static let lastSupportedNowPlayingBundleIdentifier = Key<String?>("lastSupportedNowPlayingBundleIdentifier")
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showRemainingTime = Key<Bool>("showRemainingTime", default: false)
    static let showMediaSourceAppIcon = Key<Bool>("showMediaSourceAppIcon", default: true)
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let sliderColor = Key<SliderColorEnum>("sliderUseAlbumArtColor", default: .white)
    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)

    // Shelf
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let reverseShelfOrdering = Key<Bool>("reverseShelfOrdering", default: false)
    static let quickShareProvider = Key<String>("quickShareProvider") { ArisQuickShareDefault.current }

    // Calendar
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let joinMeetingOnEventTap = Key<Bool>("joinMeetingOnEventTap", default: true)

    // Appearance & general
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData")
    static let appLanguage = Key<AppLanguage>("appLanguage", default: .system)
    /// The release nickname in About; empty until the user names one (the row then shows only the version).
    static let releaseName = Key<String>("releaseName", default: "")

    // Retired, still switched off at launch by the app entry until it is rewritten.
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
}


extension KeyboardShortcuts.Name {
    static let toggleNotchOpen = Self("toggleNotchOpen", default: .init(.i, modifiers: [.shift, .command]))
    static let toggleSneakPeek = Self("toggleSneakPeek", default: .init(.h, modifiers: [.shift, .command]))
}
