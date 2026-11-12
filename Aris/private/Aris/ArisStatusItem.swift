//
//  ArisStatusItem.swift
//  Aris
//
//  The app's only menu-bar item: a plain sparkle whose menu opens either side panel, settings, restarts or quits (and,
//  while the first-run guide shows, brings its step back; while the setup is put off, continues it where it was left).
//  (It used to draw CodexBar's two-bar usage meter and list every provider's limits; the user dropped that.)
//

import AppKit

@MainActor
final class ArisStatusItem: NSObject, NSMenuDelegate {
    static let shared = ArisStatusItem()

    private var item: NSStatusItem?

    func start() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let mark = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Aris")
        mark?.isTemplate = true
        item.button?.image = mark
        item.button?.toolTip = "Aris"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if ArisOnboardingGuide.shared.showing {
            // The first-run guide is up (maybe folded behind System Settings): bring its step back.
            let guide = NSMenuItem(title: ArisUIWords.text("시작 안내로 돌아가기", "Back to the setup guide"), action: #selector(openGuide), keyEquivalent: "")
            guide.target = self
            menu.addItem(guide)
        } else if ArisOnboarding.postponed(later: UserDefaults.standard.bool(forKey: ArisOnboarding.laterKey), showing: ArisOnboardingGuide.shared.showing) {
            // The setup was put off (its ×, Esc, 나중에 할게요): the one quiet way back, to the page that was left.
            let guide = NSMenuItem(title: ArisSetupWords.continueSetup(english: ArisUIWords.english), action: #selector(continueGuide), keyEquivalent: "")
            guide.target = self
            menu.addItem(guide)
        }
        // One for each side that has a tab left on; none while every side tab is turned off in settings.
        let sides = ArisSideMenu.sides(hidden: ArisSidePanels.shared.hiddenTabs)
        for side in sides {
            let open = NSMenuItem(title: ArisSideMenu.title(side, open: ArisSidePanels.shared.open.contains(side)), action: side == .left ? #selector(openPanel) : #selector(openRightPanel), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
        }
        if !sides.isEmpty { menu.addItem(.separator()) }
        menu.addItem(ArisQuietMenu.item())
        // While the wake word rests, why (a line to read, not to choose).
        if let resting = ArisWakeRestLive.shared.words { menu.addItem(NSMenuItem(title: resting, action: nil, keyEquivalent: "")) }
        for (title, action, key) in [(ArisUIWords.text("설정…", "Settings…"), #selector(openSettings), ","), (ArisUIWords.text("Aris 다시 시작", "Restart Aris"), #selector(restart), ""),
                                     (ArisUIWords.text("Aris 종료", "Quit Aris"), #selector(quit), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
    }

    @objc private func openGuide() { ArisOnboardingGuide.shared.surface() }
    @objc private func continueGuide() { ArisOnboardingGuide.shared.continueSetup() }

    /// The left side on 기록 (or its first tab left on).
    @objc private func openPanel() {
        if ArisSideMenu.act(open: ArisSidePanels.shared.open.contains(.left)) == .close { return ArisSidePanels.shared.collapse(.left) }
        ArisSidePanels.shared.show(.left, tab: .history)
    }

    /// The right side on the tab it last showed (할 일 or 캘린더).
    @objc private func openRightPanel() {
        if ArisSideMenu.act(open: ArisSidePanels.shared.open.contains(.right)) == .close { return ArisSidePanels.shared.collapse(.right) }
        ArisSidePanels.shared.show(.right)
    }

    /// A side panel that is open (and not locked open) folds out of the Settings window's way (ArisStepAside).
    @objc private func openSettings() {
        ArisSettingsWindow.shared.show()
        ArisSidePanels.shared.stepAside()
    }

    /// All of Aris: its helper first (aris-agent keeps what it held from its own start, and the jobs it runs end with
    /// the app anyway), then the app, whatever the helper answers (VM bug 1: the menu left aris-agent running).
    @objc private func restart() {
        Task { @MainActor in
            _ = await ArisHelperClient.shared.restartArisAgent()
            ApplicationRelauncher.restart()
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
