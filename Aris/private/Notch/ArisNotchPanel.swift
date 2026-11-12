//
//  ArisNotchPanel.swift
//  Aris
//
//  The window a notch draws in: a borderless, non-activating panel above the menu bar on every space, transparent
//  where nothing is drawn. It never becomes main and becomes key only while Claude's keyboard is armed, so a click on
//  the notch never takes focus from the frontmost app. It can also be lifted onto the lock screen.
//

import AppKit
import Combine
import Defaults
import SkyLightWindow

final class ArisNotchPanel: NSPanel, ArisKeyPanel {
    private var watchers: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        hasShadow = false
        isReleasedWhenClosed = false
        // Aris comes forward while a field is typed in (ArisPanelKeys) and steps back after: the notch stays.
        hidesOnDeactivate = false
        appearance = NSAppearance(named: .darkAqua)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        updateBehavior()
        updateSharing()
        Defaults.publisher(.hideNonNotchedFromMissionControl, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateBehavior() }
            .store(in: &watchers)
        Defaults.publisher(.hideFromScreenRecording, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateSharing() }
            .store(in: &watchers)
        screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: self, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBehavior() }
        }
    }

    convenience init(size: CGSize) {
        self.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
                  backing: .buffered, defer: false)
    }

    /// Key for a card's keys (armed), or while one of its fields is typed in (ArisPanelKeys).
    override var canBecomeKey: Bool { MainActor.assumeIsolated { ArisPanelKeys.canBecomeKey(armed: ClaudeStore.keyboardArmed) } }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        MainActor.assumeIsolated { ArisPanelKeys.responderChanged(firstResponder, in: self) }
        return made
    }

    override func resignKey() {
        super.resignKey()
        MainActor.assumeIsolated { ArisPanelKeys.lostKey(self) }
    }
    override var canBecomeMain: Bool { false }

    override func close() {
        stopWatching()
        super.close()
    }

    private func stopWatching() {
        watchers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    private func updateBehavior() {
        let hasNotch = (screen?.safeAreaInsets.top ?? 0) > 0
        collectionBehavior = ArisNotchWindowRules.collectionBehavior(
            hideNonNotchedFromMissionControl: Defaults[.hideNonNotchedFromMissionControl], hasNotch: hasNotch)
    }

    private func updateSharing() {
        sharingType = Defaults[.hideFromScreenRecording] ? .none : .readWrite
    }

    // MARK: - Lock screen

    /// Moves the panel into the SkyLightWindow package's lock-screen space.
    func liftToLockScreen() {
        SkyLightOperator.shared.delegateWindow(self)
    }

    /// Takes the panel back out of that space.
    func lowerFromLockScreen() {
        let skyLight = SkyLightOperator.shared
        ArisSkyLightRemoval.remove(window: windowNumber, connection: skyLight.connection, space: Int(skyLight.space))
    }
}

/// SkyLight's "remove windows from spaces", looked up at run time.
private enum ArisSkyLightRemoval {
    typealias Remove = @convention(c) (Int32, CFArray, CFArray) -> Int32

    static let function: Remove? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
              let symbol = dlsym(handle, "SLSRemoveWindowsFromSpaces") else { return nil }
        return unsafeBitCast(symbol, to: Remove.self)
    }()

    static func remove(window: Int, connection: Int32, space: Int) {
        _ = function?(connection, [window] as CFArray, [space] as CFArray)
    }
}
