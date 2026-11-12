//
//  ArisNotchNavigation.swift
//  Aris
//
//  What every notch shares: the open page, the display the notch lives on, the tab settings, and the music peek.
//  Stored values keep the keys older builds used.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ArisNotchNavigation: ObservableObject {
    static let shared = ArisNotchNavigation()

    static let firstLaunchKey = "firstLaunch"
    static let preferredDisplayKey = "preferred_screen_uuid"
    static let legacyDisplayNameKey = "preferred_screen_name"
    /// How long the inline peek stays.
    static let inlinePeekDuration: Duration = .seconds(3)

    /// The page every open notch shows.
    @Published var currentView: NotchViews = .home
    /// True until the app has launched once; no notch opens meanwhile.
    @Published var firstLaunch: Bool {
        didSet { UserDefaults.standard.set(firstLaunch, forKey: Self.firstLaunchKey) }
    }
    @Published var musicLiveActivityEnabled: Bool {
        didSet { Defaults[.musicLiveActivityEnabled] = musicLiveActivityEnabled }
    }
    @Published var alwaysShowTabs: Bool {
        didSet {
            guard alwaysShowTabs != oldValue else { return }
            Defaults[.alwaysShowTabs] = alwaysShowTabs
            apply(ArisNotchRules.alwaysShowTabsChanged(to: alwaysShowTabs, rememberLastTab: openLastTabByDefault,
                                                       shelfEmpty: ShelfStateViewModel.shared.isEmpty,
                                                       openShelfByDefault: Defaults[.openShelfByDefault]))
        }
    }
    @Published var openLastTabByDefault: Bool {
        didSet {
            guard openLastTabByDefault != oldValue else { return }
            Defaults[.openLastTabByDefault] = openLastTabByDefault
            apply(ArisNotchRules.rememberLastTabChanged(to: openLastTabByDefault, alwaysShowTabs: alwaysShowTabs))
        }
    }
    /// The display picked in settings; choosing one also moves the notch there.
    @Published var preferredScreenUUID: String? {
        didSet {
            UserDefaults.standard.set(preferredScreenUUID, forKey: Self.preferredDisplayKey)
            if let preferredScreenUUID { selectedScreenUUID = preferredScreenUUID }
            NotificationCenter.default.post(name: .selectedScreenChanged, object: nil)
        }
    }
    /// The display the single-display notch is on.
    @Published var selectedScreenUUID: String

    @Published private(set) var expandingView = ArisInlinePeek()
    @Published private var peeks = ArisPeekBoard()

    private var inlineShow = 0
    private var watchers: Set<AnyCancellable> = []

    private init() {
        let defaults = UserDefaults.standard
        // Observed properties get their storage directly: no didSet may run (or post) while `shared` is created.
        _firstLaunch = Published(initialValue: defaults.object(forKey: Self.firstLaunchKey) as? Bool ?? true)
        _musicLiveActivityEnabled = Published(initialValue: Defaults[.musicLiveActivityEnabled])
        _alwaysShowTabs = Published(initialValue: Defaults[.alwaysShowTabs])
        _openLastTabByDefault = Published(initialValue: Defaults[.openLastTabByDefault])
        let main = NSScreen.main?.displayUUID
        selectedScreenUUID = main ?? ""
        let preferred = ArisNotchRules.preferredDisplay(
            storedUUID: defaults.string(forKey: Self.preferredDisplayKey), legacyName: defaults.string(forKey: Self.legacyDisplayNameKey),
            screens: NSScreen.screens.map { ($0.localizedName, $0.displayUUID) }, mainUUID: main)
        if preferred.store { defaults.set(preferred.uuid, forKey: Self.preferredDisplayKey) }
        if preferred.clearLegacyName { defaults.removeObject(forKey: Self.legacyDisplayNameKey) }
        // Set the storage directly: the didSet would post selectedScreenChanged, whose observers rebuild the
        // windows and read `ArisNotchNavigation.shared` while it is still being created (a dispatch_once deadlock).
        _preferredScreenUUID = Published(initialValue: preferred.uuid)
        if let uuid = preferred.uuid { selectedScreenUUID = uuid }

        Defaults.publisher(.shelfEnabled, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self, !change.newValue, self.currentView == .shelf else { return }
                self.currentView = .home
            }
            .store(in: &watchers)
    }

    private func apply(_ settings: ArisNotchRules.TabSettings) {
        if alwaysShowTabs != settings.alwaysShowTabs { alwaysShowTabs = settings.alwaysShowTabs }
        if openLastTabByDefault != settings.rememberLastTab { openLastTabByDefault = settings.rememberLastTab }
        if settings.selectHome { currentView = .home }
    }

    // MARK: - Music peek

    var isAnySneakPeekShowing: Bool { peeks.anyShowing }

    func shouldShowSneakPeek(on screenUUID: String?) -> Bool {
        sneakPeekState(for: screenUUID).show
    }

    /// The peek on a display (nil: the main one); hidden for a display that has none.
    func sneakPeekState(for screenUUID: String?) -> SneakPeekState {
        peeks.state(for: screenUUID ?? NSScreen.main?.displayUUID)
    }

    /// Shows (for `duration`, then hides) or hides the music peek on one display, or on all when none is named.
    func toggleSneakPeek(status: Bool, type: SneakContentType, duration: TimeInterval = 1.5, value: CGFloat = 0, icon: String = "",
                         accent: Color? = nil, targetScreenUUID: String? = nil) {
        let targets = ArisPeekBoard.targets(targetScreenUUID, displays: NSScreen.screens.compactMap(\.displayUUID), main: NSScreen.main?.displayUUID)
        guard status else {
            withAnimation(.smooth) { for display in targets { peeks.hide(display) } }
            return
        }
        var scheduled: [(display: String, show: Int)] = []
        withAnimation(.smooth) { scheduled = peeks.show(type, value: value, icon: icon, accent: accent, on: targets) }
        for (display, show) in scheduled {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self else { return }
                withAnimation(.smooth) { self.peeks.hide(display, show: show) }
            }
        }
    }

    /// Shows (for 3 s) or hides the inline peek.
    func toggleExpandingView(status: Bool, type: SneakContentType, value: CGFloat = 0) {
        inlineShow += 1
        let show = inlineShow
        withAnimation(.smooth) { expandingView = ArisInlinePeek(show: status, type: type, value: value) }
        guard status else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Self.inlinePeekDuration)
            guard let self, self.inlineShow == show else { return }
            withAnimation(.smooth) { self.expandingView.show = false }
        }
    }
}
