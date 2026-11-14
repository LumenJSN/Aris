//
//  ArisEntry.swift
//  Aris
//
//  The app: an agent with no scene of its own (the user's status item and settings window are the way in). Launch runs
//  in a fixed order — retire old switches, connect the keychain, migrate the display mode, start the user's subsystems,
//  watch the displays and the lock screen, register the shortcuts, measure the notch, create the notch windows,
//  start the side panels, follow the display mode — and quitting saves the shelf and stops everything.
//

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@main
struct ArisEntry: App {
    @NSApplicationDelegateAdaptor(ArisAppDelegate.self) private var delegate

    var body: some Scene {
        // No scene of its own; the app menu's Settings (⌘,) opens the user's settings window, not an empty one.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { ArisSettingsWindow.shared.show() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

@MainActor
final class ArisAppDelegate: NSObject, NSApplicationDelegate {
    private var windows: ArisNotchWindows?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var activeDisplayObserver: NSObjectProtocol?
    private var modeWatch: Task<Void, Never>?
    private var lastMode: DisplayMode?
    private var autoClose: Task<Void, Never>?

    /// Read before the launch's Apple event is gone: a login-item launch never resumes the first-run guide.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before anything reads a preference: an install from before keeps the wake word and the brain it ran on.
        ArisFirstRun.pinEarlierDefaults(in: .standard, stored: ArisFirstRun.storedKeys())
        launchedAsLoginItem = ArisOnboardingWatch.launchedAsLoginItem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Any main-thread stall over 2 s goes to the log (QA BUG-37).
        ArisStallWatch.shared.start()
        // `kill`, an installer or launchd asking Aris to stop quits it like the menu's Quit (it used to be swallowed).
        ArisTerminationSignal.watch {
            ArisTerminationSignal.quit(quit: { NSApp.terminate(nil) }, force: { _exit(0) })
        }
        // A press on a field in Aris's panels brings Aris forward to type (QA BUG-22).
        ArisPanelKeys.installPressMonitor()
        retireOldSwitches()
        connectKeychain()
        migrateDisplayModeIfNeeded()
        startSubsystems()
        observeSystem()
        registerShortcuts()
        syncNotchHeightIfNeeded()
        _ = QuickShareService.shared
        let windows = ArisNotchWindows()
        self.windows = windows
        windows.prepareInitialWindows()
        windows.setupDragDetectors()
        // Notification cards go under the notch, never while it is open (ArisNoticeCenter).
        ArisNoticeCenter.shared.attach(notchOpen: { [weak windows] in windows?.anyOpen ?? false },
                                       screen: { [weak windows] in windows?.noticeScreen }, changes: windows.openChanges)
        ArisSidePanels.shared.start()
        // Dictation shows in its own pill at the bottom of the screen being typed on (ArisDictationPillCenter).
        ArisDictationPillCenter.shared.start()
        ArisUsageModel.shared.start()
        ArisStatusItem.shared.start()
        // The working tags' clocks count from when each began, whether or not the notch was open then.
        ArisTagClock.shared.start()
        // Which AIs are set up here: a new install answers with one that is, never one that can't start.
        ArisBrainSetup.shared.start()
        followDisplayMode()
        ArisNotchNavigation.shared.firstLaunch = false
        ArisOnboardingGuide.shared.notch = { [weak self] in self?.onboardingNotch() }
        ArisOnboardingGuide.shared.showAtLaunch(loginItem: launchedAsLoginItem)
        // An Aris.app with no helper, or a macOS too old to talk to it, is said plainly (audit no-agent-no-os-check).
        ArisPrerequisiteNotice.sayAtLaunch()
        // The helper inside this app is made the one that runs (a new Mac, a moved app, an install made the old way).
        ArisHelperInstall.shared.atLaunch()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // While the first-run setup is unfinished, opening Aris again brings the setup forward, not Settings (VM bug 6).
        if ArisOnboardingGuide.shared.openedAgain() { return false }
        ArisSettingsWindow.shared.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        // The hook port closes first: after "Aris 다시 시작" the new copy is already waiting for it (audit hook-1).
        ClaudeHookServer.shared.stop()
        // The ad demos' jobs, figures, ink and cards go first: nothing of them outlasts the app.
        ArisAdDemo.shared.stopAll()
        ShelfStateViewModel.shared.flushSync()
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        if let activeDisplayObserver { NSWorkspace.shared.notificationCenter.removeObserver(activeDisplayObserver) }
        activeDisplayObserver = nil
        ArisNowPlaying.shared.destroy()
        ArisOnboardingGuide.shared.closeForQuit()
        windows?.cleanup()
        modeWatch?.cancel()
        autoClose?.cancel()
    }

    // MARK: - Launch steps

    /// Old features' switches stay off on every launch.
    private func retireOldSwitches() {
        Defaults[.showNotHumanFace] = false
        Defaults[.openShelfByDefault] = false
        Defaults[.menubarIcon] = false
    }

    /// Keys come from the keychain; files left by older builds move there in the background.
    private func connectKeychain() {
        ArisKeyFile.secureStore = { ArisKeychain.read($0) }
        ArisKeyFile.isTombstoned = { ArisKeychain.isTombstoned($0) }
        Task.detached(priority: .utility) { await ArisKeychain.migrateFiles() }
    }

    private func migrateDisplayModeIfNeeded() {
        guard UserDefaults.standard.object(forKey: Defaults.Keys.displayMode.name) == nil else { return }
        Defaults[.displayMode] = ArisLaunchRules.migratedDisplayMode(
            showOnAllDisplays: Defaults[.showOnAllDisplays], followActiveDisplay: Defaults[.followActiveDisplay],
            automaticallySwitchDisplay: Defaults[.automaticallySwitchDisplay])
    }

    /// The user's subsystems, in their order.
    private func startSubsystems() {
        ClaudeHookServer.shared.start()
        ClaudeHotKey.register()
        ArisHotKey.register()
        ArisKeyTaps.startWhenAllowed()
        ArisTodoModel.shared.watchDeadlines()
        ArisBoard.shared.watch()
        ArisTimerModel.shared.watchRequests()
        ArisPreview.shared.watch()
        ArisPreview.shared.notch = { [weak self] open in
            guard let windows = self?.windows else { return }
            // The notch of the first display with a camera housing, else the primary one; the pointer stays put.
            let uuid = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }?.displayUUID
            let model = uuid.flatMap { windows.viewModels[$0] } ?? windows.primaryViewModel
            if open { model.open() } else { model.close() }
        }
        ArisClipboardModel.shared.watch()
        ArisClipboardHotKey.register()
        ArisRightPanelHotKey.register()
        _ = ArisTimerModel.shared
        ClaudeStore.shared.onHandOff = { approval in
            TerminalFocus.focus(ClaudeStore.shared.sessions[approval.sessionId], cwd: approval.cwd)
        }
        // The sessions list drops a session whose terminal app has quit (audit claude-1).
        ClaudeStore.shared.runningApps = { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    }

    private func observeSystem() {
        let app = NotificationCenter.default
        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.windows?.screenConfigurationDidChange() }
        observe(app, .selectedScreenChanged) { $0.repositionWindows() }
        observe(app, .notchHeightChanged) { $0.repositionWindows() }
        observe(app, .expandedDragDetectionChanged) { $0.windows?.setupDragDetectors() }
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.windows?.screenLocked() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.windows?.screenUnlocked() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable (ArisAppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, token))
    }

    /// The notch that hosts the first-run guide: the display with a notch when one of the notch windows is there, else
    /// the primary notch window's (notch-less) display (ArisOnboardingStage.display).
    private func onboardingNotch() -> (model: ArisNotchModel, screen: NSScreen)? {
        guard let windows else { return nil }
        let primary = windows.primaryViewModel
        let all = Defaults[.displayMode] == .allDisplays
        let windowed = all ? Set(windows.viewModels.keys) : (windows.window == nil ? [] : Set([primary.screenUUID].compactMap { $0 }))
        let screens = NSScreen.screens.compactMap { screen in
            screen.displayUUID.map { ArisOnboardingStage.Display(uuid: $0, hasNotch: screen.safeAreaInsets.top > 0) }
        }
        let primaryUUID = all ? (NSScreen.main?.displayUUID).flatMap { windows.viewModels[$0] != nil ? $0 : nil } ?? windows.viewModels.keys.sorted().first
            : primary.screenUUID
        guard let uuid = ArisOnboardingStage.display(screens, windowed: windowed, primary: primaryUUID),
              let screen = NSScreen.screen(withUUID: uuid),
              let model = all ? windows.viewModels[uuid] : primary
        else { return nil }
        return (model, screen)
    }

    private func repositionWindows() {
        windows?.adjustWindowPosition(changeAlpha: true)
        windows?.setupDragDetectors()
    }

    // MARK: - Shortcuts

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyDown(for: .toggleNotchOpen) { [weak self] in
            MainActor.assumeIsolated { self?.toggleNotch() }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleSneakPeek) {
            MainActor.assumeIsolated { Self.peekKey(down: true) }
        }
        KeyboardShortcuts.onKeyUp(for: .toggleSneakPeek) {
            MainActor.assumeIsolated { Self.peekKey(down: false) }
        }
    }

    /// Opens the notch under the pointer (all displays) or the primary one, closing it again after 3 s; an open one
    /// closes.
    private func toggleNotch() {
        // The first-run guide holds the notch: the hot key brings its step back (never silently refused).
        if ArisOnboardingGuide.shared.showing { return ArisOnboardingGuide.shared.surface() }
        guard let windows else { return }
        let model: ArisNotchModel
        if Defaults[.displayMode] == .allDisplays {
            let point = NSEvent.mouseLocation
            let uuid = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }?.displayUUID
            model = uuid.flatMap { windows.viewModels[$0] } ?? windows.primaryViewModel
        } else {
            model = windows.primaryViewModel
        }
        autoClose?.cancel()
        autoClose = nil
        guard model.notchState == .closed else { return model.close() }
        guard model.open() else { return }
        autoClose = Task { [weak model] in
            try? await Task.sleep(for: ArisLaunchRules.toggleAutoClose)
            guard !Task.isCancelled else { return }
            model?.close()
        }
    }

    /// Inline style: key-down toggles the inline expansion, key-up the peek. Standard: key-down shows the peek for
    /// 3 s, or hides one that shows.
    private static func peekKey(down: Bool) {
        let navigation = ArisNotchNavigation.shared
        if Defaults[.sneakPeekStyles] == .inline {
            if down {
                navigation.toggleExpandingView(status: !navigation.expandingView.show, type: .music)
            } else {
                navigation.toggleSneakPeek(status: !navigation.isAnySneakPeekShowing, type: .music)
            }
        } else if down {
            navigation.toggleSneakPeek(status: !navigation.isAnySneakPeekShowing, type: .music, duration: ArisLaunchRules.peekShortcutDuration)
        }
    }

    // MARK: - Display mode

    /// Follows the display-mode setting, starting with its current value.
    private func followDisplayMode() {
        modeWatch = Task { [weak self] in
            for await mode in Defaults.updates(.displayMode) {
                self?.displayModeChanged(mode)
            }
        }
    }

    private func displayModeChanged(_ mode: DisplayMode) {
        if ArisLaunchRules.crossesWindowSets(from: lastMode, to: mode) { windows?.cleanupWindows(shouldInvert: true) }
        lastMode = mode
        let workspace = NSWorkspace.shared.notificationCenter
        if mode == .activeDisplay {
            if activeDisplayObserver == nil {
                activeDisplayObserver = workspace.addObserver(forName: Notification.Name("NSWorkspaceActiveDisplayDidChangeNotification"),
                                                              object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.repositionWindows() }
                }
            }
        } else if let activeDisplayObserver {
            workspace.removeObserver(activeDisplayObserver)
            self.activeDisplayObserver = nil
        }
        repositionWindows()
    }
}
