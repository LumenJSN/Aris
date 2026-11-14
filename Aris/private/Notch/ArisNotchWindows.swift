//
//  ArisNotchWindows.swift
//  Aris
//
//  The notch windows: one per display in "all displays" mode (each with its own notch model), otherwise one window
//  for the long-lived primary model on the display the mode picks. Windows join the private notch space, follow
//  display changes, can stay on the lock screen, and get a drag watcher that opens the notch when a file is dragged
//  to where the open notch would be.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ArisNotchWindows {
    /// The model of the single-display window.
    let primaryViewModel: ArisNotchModel
    /// "All displays" mode: windows and models by display UUID.
    private(set) var windows: [String: NSWindow] = [:]
    private(set) var viewModels: [String: ArisNotchModel] = [:]
    /// The single-display window.
    private(set) var window: NSWindow?

    /// How long after unlocking the windows leave the lock-screen space (sooner flickers).
    static let unlockDelay: Duration = .milliseconds(150)

    private var detectors: [DragDetector] = []
    /// Each window's "changed screen" observer (the drag watchers follow it).
    private var screenObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    private var lastScreens: ArisNotchWindowRules.ScreenSet?
    private var isLocked = false

    init() {
        LegacyNonNotchHeightMigration.applyIfNeeded()
        _ = ArisNotchSpace.shared
        primaryViewModel = ArisNotchModel()
    }

    private var allDisplays: Bool { Defaults[.displayMode] == .allDisplays }

    // MARK: - Creating and placing

    /// Creates the windows for the current mode and remembers the display set.
    func prepareInitialWindows() {
        adjustWindowPosition()
        if lastScreens == nil { lastScreens = currentScreens() }
    }

    /// Brings the windows in line with the displays and the mode, and places them.
    func adjustWindowPosition(changeAlpha: Bool = false) {
        if allDisplays { placeAllDisplays(changeAlpha: changeAlpha) } else { placeSingleDisplay(changeAlpha: changeAlpha) }
    }

    private func placeAllDisplays(changeAlpha: Bool) {
        let screens = NSScreen.screens.filter { $0.displayUUID != nil }
        let present = Set(screens.compactMap(\.displayUUID))
        for uuid in windows.keys where !present.contains(uuid) {
            closeWindow(windows[uuid])
            windows[uuid] = nil
            viewModels[uuid] = nil
        }
        for screen in screens {
            guard let uuid = screen.displayUUID else { continue }
            let model = viewModels[uuid] ?? ArisNotchModel(screenUUID: uuid)
            viewModels[uuid] = model
            let panel = windows[uuid] ?? makeWindow(for: model)
            windows[uuid] = panel
            place(panel, on: screen, changeAlpha: changeAlpha)
            if model.notchState == .closed { model.close() }
        }
    }

    private func placeSingleDisplay(changeAlpha: Bool) {
        let navigation = ArisNotchNavigation.shared
        let screens = NSScreen.screens
        guard let uuid = ArisNotchWindowRules.display(mode: Defaults[.displayMode], preferred: navigation.preferredScreenUUID,
                                                      screens: screens.compactMap(\.displayUUID), main: NSScreen.main?.displayUUID),
              let screen = NSScreen.screen(withUUID: uuid) else {
            // The preferred display is unplugged: show nothing until it is back.
            window?.alphaValue = 0
            return
        }
        let panel = window ?? makeWindow(for: primaryViewModel)
        window = panel
        primaryViewModel.screenUUID = uuid
        if navigation.selectedScreenUUID != uuid { navigation.selectedScreenUUID = uuid }
        place(panel, on: screen, changeAlpha: changeAlpha)
        panel.alphaValue = 1
        if primaryViewModel.notchState == .closed { primaryViewModel.close() }
    }

    private func makeWindow(for model: ArisNotchModel) -> ArisNotchPanel {
        let panel = ArisNotchPanel(size: windowSize)
        panel.contentView = ArisNotchHostingView(rootView: ArisNotchRoot().environmentObject(model))
        panel.orderFrontRegardless()
        ArisNotchSpace.shared.add(panel)
        screenObservers[ObjectIdentifier(panel)] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setupDragDetectors() }
        }
        if isLocked && Defaults[.showOnLockScreen] { panel.liftToLockScreen() }
        return panel
    }

    private func place(_ panel: NSWindow, on screen: NSScreen, changeAlpha: Bool) {
        let origin = ArisNotchWindowRules.origin(screenFrame: screen.frame, windowSize: panel.frame.size)
        if changeAlpha { panel.alphaValue = 0 }
        panel.setFrameOrigin(origin)
        if changeAlpha { panel.alphaValue = 1 }
    }

    private func closeWindow(_ window: NSWindow?) {
        guard let window else { return }
        if let observer = screenObservers.removeValue(forKey: ObjectIdentifier(window)) {
            NotificationCenter.default.removeObserver(observer)
        }
        ArisNotchSpace.shared.remove(window)
        window.close()
    }

    // MARK: - Drag watchers

    /// One watcher per window on the open notch's area (with "expanded drag detection" on); a content drag entering
    /// it opens that notch on the home page while the shelf is on. Always, one on the strip just under the closed notch
    /// (ArisNotchWindowRules.dragHoverRegion): a content drag there makes the notch's drag strip hittable (BUG-24c).
    func setupDragDetectors() {
        stopDragDetectors()
        let pairs: [(NSWindow, ArisNotchModel)] = allDisplays
            ? windows.compactMap { uuid, window in viewModels[uuid].map { (window, $0) } }
            : window.map { [($0, primaryViewModel)] } ?? []
        let single = !allDisplays
        for (window, model) in pairs {
            guard let screen = single ? Self.singleScreen(of: window) : window.screen else { continue }
            let uuid = screen.displayUUID
            let near = DragDetector(notchRegion: ArisNotchWindowRules.dragHoverRegion(screenFrame: screen.frame, width: openNotchSize.width))
            let setNear = { [weak model] (on: Bool) in MainActor.assumeIsolated { model?.dropInteraction.dragNear = on } }
            near.onDragEntersNotchRegion = { setNear(true) }
            near.onDragExitsNotchRegion = { setNear(false) }
            near.onDragEnds = { setNear(false) }
            near.startMonitoring()
            detectors.append(near)
            guard Defaults[.expandedDragDetection] else { continue }
            let detector = DragDetector(notchRegion: ArisNotchWindowRules.openNotchRegion(screenFrame: screen.frame, openSize: openNotchSize))
            detector.onDragEntersNotchRegion = { [weak window, weak model] in
                MainActor.assumeIsolated {
                    guard let window, let model, Defaults[.shelfEnabled] else { return }
                    if single && Self.singleScreen(of: window)?.displayUUID != uuid { return }
                    if model.open() { ArisNotchNavigation.shared.currentView = .home }
                }
            }
            detector.startMonitoring()
            detectors.append(detector)
        }
    }

    /// The single-display window's screen; while the window has none, the selected display, then the main one.
    private static func singleScreen(of window: NSWindow) -> NSScreen? {
        window.screen ?? NSScreen.screen(withUUID: ArisNotchNavigation.shared.selectedScreenUUID) ?? NSScreen.main
    }

    private func stopDragDetectors() {
        detectors.forEach { $0.stopMonitoring() }
        detectors = []
    }

    // MARK: - Tearing down

    /// Closes the windows of the current mode — or, inverted, of the other mode (the one being left when the mode
    /// crosses between "all displays" and a single display).
    func cleanupWindows(shouldInvert: Bool = false) {
        let closeAll = shouldInvert ? !allDisplays : allDisplays
        if closeAll { closeAllDisplays() } else { closeSingle() }
        stopDragDetectors()
    }

    private func closeAllDisplays() {
        windows.values.forEach(closeWindow)
        windows = [:]
        viewModels = [:]
    }

    private func closeSingle() {
        closeWindow(window)
        window = nil
    }

    /// Displays changed: if the set really did, re-measure, rebuild the windows and the watchers (next main turn).
    func screenConfigurationDidChange() {
        let now = currentScreens()
        guard now != lastScreens else { return }
        lastScreens = now
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                syncNotchHeightIfNeeded()
                self.closeAllDisplays()
                self.closeSingle()
                self.adjustWindowPosition()
                self.setupDragDetectors()
            }
        }
    }

    private func currentScreens() -> ArisNotchWindowRules.ScreenSet {
        ArisNotchWindowRules.ScreenSet(NSScreen.screens.map { ($0.displayUUID, $0.frame) })
    }

    // MARK: - Lock screen

    func screenLocked() {
        isLocked = true
        if Defaults[.showOnLockScreen] {
            panels.forEach { $0.liftToLockScreen() }
        } else {
            stopDragDetectors()
            closeAllDisplays()
            closeSingle()
        }
    }

    func screenUnlocked() {
        isLocked = false
        if Defaults[.showOnLockScreen] {
            let lifted = panels
            Task {
                try? await Task.sleep(for: Self.unlockDelay)
                lifted.forEach { $0.lowerFromLockScreen() }
            }
        } else {
            adjustWindowPosition()
            setupDragDetectors()
        }
    }

    /// The windows of the current mode.
    private var panels: [ArisNotchPanel] {
        (allDisplays ? Array(windows.values) : [window].compactMap { $0 }).compactMap { $0 as? ArisNotchPanel }
    }

    // MARK: - For the notification cards (ArisNoticeCenter)

    /// A notch of the current mode is open.
    var anyOpen: Bool {
        allDisplays ? viewModels.values.contains { $0.notchState == .open } : primaryViewModel.notchState == .open
    }

    /// The display the cards go on: the single notch's, or in "all displays" mode the main one.
    var noticeScreen: NSScreen? {
        if !allDisplays, let window { return Self.singleScreen(of: window) }
        return NSScreen.main
    }

    /// Each time a notch may have opened or closed.
    var openChanges: AnyPublisher<Void, Never> {
        let models = [primaryViewModel] + Array(viewModels.values)
        return Publishers.MergeMany(models.map { $0.$notchState.map { _ in () } }).eraseToAnyPublisher()
    }

    /// Everything off (the app is quitting).
    func cleanup() {
        stopDragDetectors()
        closeAllDisplays()
        closeSingle()
        ArisNotchSpace.shared.destroy()
    }
}

/// The notch's content. A click on one of its controls counts even when another app has the keyboard and the notch's
/// panel is not key: SwiftUI otherwise may spend that click on the window (the Settings window had the same: its
/// button needed two clicks). Third VM run, bug D: a press on the running tag was lost twice, both times after a
/// card's Allow had handed the keyboard back to the app behind.
/// It stays true for all of the notch, a card's buttons included (security review 3, L2, asked whether cards should be
/// left out by the click's place): the state in which macOS asks this is the one right after a card's Allow, so in a
/// run of cards it is the next card's Allow that would lose its click, as the tag did, and a click lost there is a card
/// that can't be answered by the pointer. What a first click must not do is say yes to a card that has only just come
/// down under it, and that is decided where the yes is taken, for every click: ArisCardHold.
final class ArisNotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
