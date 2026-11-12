//
//  ArisNotchModel.swift
//  Aris
//
//  One display's notch: open or closed, its sizes, whether it hides over a full-screen app, and its drop targets.
//  Opening and closing follow ArisNotchRules; the shared page and peek live in ArisNotchNavigation.
//

import AppKit
import Combine
import Defaults
import SwiftUI

@MainActor
final class ArisNotchModel: NSObject, ObservableObject {
    @Published private(set) var notchState: NotchState = .closed
    /// The display this notch is on (nil: the main one). The window layer moves it.
    @Published var screenUUID: String? {
        didSet { if screenUUID != oldValue { updateHidden(animated: false) } }
    }
    /// The size drawn now: the closed size, or the open size while open. The window layer may set it.
    @Published var notchSize: CGSize
    @Published private(set) var closedNotchSize: CGSize
    /// Hidden while closed because its display shows a full-screen app.
    @Published private(set) var hideOnClosed = false
    /// A popover keeps the open notch open.
    @Published var isPopoverActive = false
    @Published var isHoveringCalendar = false
    /// The first-run guide holds this notch (ArisOnboardingGuide): it draws the guide instead of its usual content and
    /// doesn't open for anything else meanwhile.
    @Published var guide: ArisOnboardingGuide?

    let dropInteraction = DropInteractionState()

    private var watchers: Set<AnyCancellable> = []

    init(screenUUID: String? = nil) {
        self.screenUUID = screenUUID
        let closed = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = closed
        notchSize = closed
        super.init()
        ArisFullscreenWatch.shared.$fullscreenStatus.map { _ in () }
            .merge(with: Defaults.publisher(.hideNotchOption, options: []).map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.updateHidden(animated: true) }
            .store(in: &watchers)
    }

    // MARK: - Open and close

    /// Opens the notch; false if it was already open or the app is in its first launch. A pending Claude approval
    /// selects the Claude page either way.
    @discardableResult
    func open() -> Bool {
        // The first-run guide holds the notch (the notch hot key and the status item bring it forward instead; a drag
        // or a hover mustn't pull its step back from System Settings).
        guard guide == nil else { return false }
        let navigation = ArisNotchNavigation.shared
        let opening = ArisNotchRules.opening(isOpen: notchState == .open, firstLaunch: navigation.firstLaunch,
                                             approvalPending: ClaudeStore.hasPendingApproval)
        if opening.selectClaude { navigation.currentView = .claude }
        guard opening.opens else { return false }
        notchSize = openNotchSize
        notchState = .open
        ArisNotchPresence.shared.set(open: true, for: self)
        ArisNowPlaying.shared.forceUpdate()
        return true
    }

    /// Closes the notch, unless a share is in progress.
    func close() {
        guard !SharingStateManager.shared.preventNotchClose else { return }
        let navigation = ArisNotchNavigation.shared
        closedNotchSize = getClosedNotchSize(screenUUID: screenUUID)
        notchSize = closedNotchSize
        notchState = .closed
        // A field typed in goes, and the user's app gets the keyboard back (QA BUG-22).
        ArisPanelKeys.closed(NSApp.windows.first { $0 is ArisNotchPanel && $0.isKeyWindow })
        ArisNotchPresence.shared.set(open: false, for: self)
        isPopoverActive = false
        if navigation.shouldShowSneakPeek(on: displayUUID) {
            navigation.toggleSneakPeek(status: false, type: .music, targetScreenUUID: displayUUID)
        }
        if let page = ArisNotchRules.pageAfterClose(current: navigation.currentView, rememberLastTab: navigation.openLastTabByDefault) {
            navigation.currentView = page
        }
    }

    // MARK: - Derived

    /// The closed height to draw: 0 for a hidden notch on a display without a notch (or one that is gone).
    var effectiveClosedNotchHeight: CGFloat {
        ArisNotchRules.effectiveClosedHeight(hidden: hideOnClosed, connected: screen != nil, hasNotch: hasNotch,
                                             closedHeight: closedNotchSize.height)
    }

    var hasNotch: Bool {
        ((screen ?? NSScreen.main)?.safeAreaInsets.top ?? 0) > 0
    }

    /// The invisible strip under the closed notch down to the menu bar's bottom.
    var chinHeight: CGFloat {
        guard let screen else { return 0 }
        return ArisNotchRules.chinHeight(hideTitleBar: Defaults[.hideTitleBar], connected: true, closed: notchState == .closed,
                                         effectiveHeight: effectiveClosedNotchHeight,
                                         menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    /// The shelf's insertion animation.
    var animation: Animation? { StandardAnimations.bouncy }

    private var screen: NSScreen? {
        guard let screenUUID else { return NSScreen.main }
        return NSScreen.screen(withUUID: screenUUID)
    }

    private var displayUUID: String? {
        screenUUID ?? NSScreen.main?.displayUUID
    }

    private func updateHidden(animated: Bool) {
        let fullscreen = displayUUID.flatMap { ArisFullscreenWatch.shared.fullscreenStatus[$0] } ?? false
        let hidden = ArisNotchRules.hiddenWhileClosed(option: Defaults[.hideNotchOption], fullscreen: fullscreen)
        guard hidden != hideOnClosed else { return }
        if animated { withAnimation(.smooth) { hideOnClosed = hidden } } else { hideOnClosed = hidden }
    }
}
