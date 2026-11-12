//
//  ArisMoreSettingsModel.swift
//  Aris
//
//  ArisMoreSettings wired to the app: reads each value where the app keeps it (Defaults, the coordinator, the music
//  manager, the share service), writes a change back, and tells the settings window when any of them changes, from
//  here or from elsewhere.
//

import Combine
import Defaults
import Foundation

@MainActor
final class ArisMoreSettingsModel: ObservableObject {
    static let shared = ArisMoreSettingsModel()

    private var watchers: Set<AnyCancellable> = []

    private init() {
        let keys: [Defaults._AnyKey] = [
            .minimumHoverDuration, .enableOpeningAnimation, .animationSpeedMultiplier, .closeGestureEnabled,
            .enableHorizontalMediaGestures, .gestureSensitivity, .normalizeGestureDirection, .nonNotchHeightMode,
            .nonNotchHeight, .cornerRadiusScaling, .hideTitleBar, .showOnLockScreen, .hideFromScreenRecording,
            .hideNonNotchedFromMissionControl, .hideNotchOption, .enableSneakPeek, .sneakPeekStyles, .waitInterval,
            .coloredSpectrogram, .playerColorTinting, .shelfEnabled, .expandedDragDetection, .copyOnDrag, .autoRemoveShelfItems,
            .reverseShelfOrdering, .quickShareProvider,
        ]
        Defaults.publisher(keys: keys, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &watchers)
        ArisNowPlaying.shared.$preferredMediaController.map { _ in () }
            .merge(with: ArisNowPlaying.shared.$nowPlayingAvailability.map { _ in () },
                   QuickShareService.shared.$availableProviders.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &watchers)
    }

    var values: ArisMoreSettings {
        let coordinator = ArisNotchNavigation.shared
        let music = ArisNowPlaying.shared
        var m = ArisMoreSettings()
        m.hoverDelay = Defaults[.minimumHoverDuration]
        m.rememberTab = coordinator.openLastTabByDefault
        m.animation = Defaults[.enableOpeningAnimation]
        m.animationSpeed = Defaults[.animationSpeedMultiplier]
        m.closeGesture = Defaults[.closeGestureEnabled]
        m.mediaSwipe = Defaults[.enableHorizontalMediaGestures]
        m.gestureSensitivity = Double(Defaults[.gestureSensitivity])
        m.fixedDirection = Defaults[.normalizeGestureDirection]
        m.flatHeightMode = Defaults[.nonNotchHeightMode] == .custom ? "custom" : "menubar"
        m.flatHeight = Double(Defaults[.nonNotchHeight])
        m.cornerScaling = Defaults[.cornerRadiusScaling]
        m.chin = Defaults[.hideTitleBar]
        m.lockScreen = Defaults[.showOnLockScreen]
        m.hideFromRecording = Defaults[.hideFromScreenRecording]
        m.hideFromMissionControl = Defaults[.hideNonNotchedFromMissionControl]

        m.musicSource = music.preferredMediaController.rawValue
        // Still asking counts as working, so the choice doesn't flicker while the check runs.
        m.nowPlayingWorks = music.nowPlayingAvailability.failure == nil
        m.musicActivity = coordinator.musicLiveActivityEnabled
        m.fullScreen = Defaults[.hideNotchOption].rawValue
        m.peek = Defaults[.enableSneakPeek]
        m.peekStyle = Defaults[.sneakPeekStyles].rawValue
        m.idleWait = Defaults[.waitInterval]
        m.coloredBars = Defaults[.coloredSpectrogram]
        m.tinting = Defaults[.playerColorTinting]

        m.shelf = Defaults[.shelfEnabled]
        m.wideDrop = Defaults[.expandedDragDetection]
        m.copyOnDrag = Defaults[.copyOnDrag]
        m.removeAfterDrag = Defaults[.autoRemoveShelfItems]
        m.reverseOrder = Defaults[.reverseShelfOrdering]
        m.quickShare = Defaults[.quickShareProvider]
        var providers = QuickShareService.shared.availableProviders.map(\.id)
        if !providers.contains(m.quickShare) { providers.insert(m.quickShare, at: 0) }
        m.quickShareOptions = providers.map { ArisSettingOption(id: $0, title: Self.shareTitle($0)) }
        return m
    }

    private static func shareTitle(_ id: String) -> String {
        id == QuickShareProvider.systemShareMenuId ? "공유 메뉴" : id
    }

    /// What the 노치 기능 page needs fresh: whether Now Playing answers, and the share services on this Mac.
    func pageOpened() async {
        ArisNowPlaying.shared.ensureNowPlayingAvailabilityChecked()
        await QuickShareService.shared.discoverAvailableProviders()
    }

    func recheckNowPlaying() {
        ArisNowPlaying.shared.refreshNowPlayingAvailability()
    }

    func set(_ key: ArisMoreKey, _ value: ArisSettingValue) {
        let on: Bool? = if case .bool(let b) = value { b } else { nil }
        let text: String = if case .text(let t) = value { t } else { "" }
        let number: Double = if case .number(let n) = value { n } else { 0 }
        let coordinator = ArisNotchNavigation.shared
        switch key {
        case .hoverDelay: Defaults[.minimumHoverDuration] = ArisMoreRounding.hoverDelay(number)
        case .rememberTab: coordinator.openLastTabByDefault = on ?? coordinator.openLastTabByDefault
        case .animation: Defaults[.enableOpeningAnimation] = on ?? true
        case .animationSpeed: Defaults[.animationSpeedMultiplier] = ArisMoreRounding.animationSpeed(number)
        case .closeGesture: Defaults[.closeGestureEnabled] = on ?? true
        case .mediaSwipe: Defaults[.enableHorizontalMediaGestures] = on ?? false
        case .gestureSensitivity: if let points = Double(text) { Defaults[.gestureSensitivity] = CGFloat(points) }
        case .fixedDirection: Defaults[.normalizeGestureDirection] = on ?? true
        case .flatHeightMode: setFlatHeightMode(text)
        case .flatHeight:
            // The notch hears it when the drag starts and ends (.sliding), not at every step.
            Defaults[.nonNotchHeight] = CGFloat(ArisMoreRounding.flatHeight(number))
        case .cornerScaling: Defaults[.cornerRadiusScaling] = on ?? true
        case .chin: Defaults[.hideTitleBar] = on ?? true
        case .lockScreen: Defaults[.showOnLockScreen] = on ?? false
        case .hideFromRecording: Defaults[.hideFromScreenRecording] = on ?? false
        case .hideFromMissionControl: Defaults[.hideNonNotchedFromMissionControl] = on ?? true
        case .musicSource: if let source = MediaControllerType(rawValue: text) { ArisNowPlaying.shared.selectMediaController(source) }
        case .musicActivity: coordinator.musicLiveActivityEnabled = on ?? coordinator.musicLiveActivityEnabled
        case .fullScreen: if let option = HideNotchOption(rawValue: text) { Defaults[.hideNotchOption] = option }
        case .peek: Defaults[.enableSneakPeek] = on ?? false
        case .peekStyle: if let style = SneakPeekStyle(rawValue: text) { Defaults[.sneakPeekStyles] = style }
        case .idleWait: Defaults[.waitInterval] = ArisMoreRounding.idleWait(number)
        case .coloredBars: Defaults[.coloredSpectrogram] = on ?? true
        case .tinting: Defaults[.playerColorTinting] = on ?? true
        case .shelf: Defaults[.shelfEnabled] = on ?? true
        case .wideDrop:
            Defaults[.expandedDragDetection] = on ?? true
            NotificationCenter.default.post(name: .expandedDragDetectionChanged, object: nil)
        case .copyOnDrag: Defaults[.copyOnDrag] = on ?? false
        case .removeAfterDrag: Defaults[.autoRemoveShelfItems] = on ?? false
        case .reverseOrder: Defaults[.reverseShelfOrdering] = on ?? false
        case .quickShare: Defaults[.quickShareProvider] = text
        }
        objectWillChange.send()
    }

    /// "메뉴 막대" follows the menu bar's height; "직접" starts from what's there (the key's 32 when it was hidden).
    private func setFlatHeightMode(_ id: String) {
        if id == "custom" {
            Defaults[.nonNotchHeightMode] = .custom
            let current = Double(Defaults[.nonNotchHeight])
            let start = current == 0 ? Double(Defaults.Keys.nonNotchHeight.defaultValue) : current
            Defaults[.nonNotchHeight] = CGFloat(ArisMoreRounding.flatHeight(start))
        } else {
            Defaults[.nonNotchHeightMode] = .matchMenuBar
            Defaults[.nonNotchHeight] = getMenuBarHeight(hasNotch: false)
        }
        NotificationCenter.default.post(name: .notchHeightChanged, object: nil)
    }
}
