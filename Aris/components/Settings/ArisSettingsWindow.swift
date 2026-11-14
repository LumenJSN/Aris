//
//  ArisSettingsWindow.swift
//  Aris
//
//  The settings window, as measured (SETTINGS-REA.md §2): 1080 × 710, transparent, the whole window one live sidebar
//  material (behind the window, active while it is key) rounded 20 and continuous, the traffic lights at 18, 18; the
//  app a regular app while it is open and back to the menu bar when it closes. Its root picks the appearance (설정 창 모양),
//  the accent, and the characters (the baked sprites). Also the window's shortcut recorder and accent colour panel.
//

import AppKit
import Defaults
import KeyboardShortcuts
import SwiftUI

@MainActor
final class ArisSettingsWindow: NSObject, NSWindowDelegate, ObservableObject {
    static let shared = ArisSettingsWindow()

    /// On screen and not minimised or covered: what polls (the permissions) run only while it is.
    @Published private(set) var visible = false

    static let size = NSSize(width: ArisSidebarMetrics.windowSize.width, height: ArisSidebarMetrics.windowSize.height)
    static let minimum = NSSize(width: ArisSidebarMetrics.windowMinimum.width, height: ArisSidebarMetrics.windowMinimum.height)

    private var window: NSWindow?
    /// The window's material, the content view everything is drawn on.
    private var material: NSVisualEffectView?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        let front = ArisSettingsFront(wasRegular: NSApp.activationPolicy() == .regular, wasActive: NSApp.isActive)
        NSApp.setActivationPolicy(.regular)
        let wasVisible = window.isVisible
        if !wasVisible {
            window.center()
            ArisSettingsNav.shared.opens += 1
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        placeTrafficLights(window)
        visible = true
        if front.reactivates { takeMenuBar(for: window) }
        // Nothing starts focused, so the first key pressed can't land in the search field or a recorder.
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }

    /// Aris turned regular while it was already the active app: macOS still draws the previous app's menus
    /// (ArisSettingsFront). Once the change has settled Aris steps back to the Dock and comes forward again; if the
    /// user went elsewhere meanwhile, nothing is taken back.
    private func takeMenuBar(for window: NSWindow) {
        let own = Bundle.main.bundleIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + ArisSettingsFront.settle) {
            guard window.isVisible, NSApp.isActive,
                  let dock = NSRunningApplication.runningApplications(withBundleIdentifier: ArisSettingsFront.between).first else { return }
            dock.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + ArisSettingsFront.away) {
                guard ArisSettingsFront.comesBack(windowVisible: window.isVisible, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier, own: own) else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func close() { window?.performClose(nil) }

    private func makeWindow() -> NSWindow {
        let window = ArisSettingsNSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = ArisUIWords.text("Aris 설정", "Aris Settings")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = Self.minimum
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle, .fullScreenAuxiliary]
        window.identifier = NSUserInterfaceItemIdentifier("ArisSettingsWindow")
        // Transparent, so the material is the window's whole face (the sidebar and the gutter round the content card).
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        let material = ArisSettingsMaterial.make()
        let host = ArisSettingsHostingView(rootView: ArisSettingsRoot())
        host.frame = material.bounds
        host.autoresizingMask = [.width, .height]
        material.addSubview(host)
        window.contentView = material
        self.material = material
        ArisSettingsMaterial.round(window, radius: ArisSidebarMetrics.windowRadius)
        window.delegate = self
        return window
    }

    /// The close, minimise and zoom buttons with the close button's corner 18 from the window's left and top, in their
    /// own spacing: the strip that holds them is made as tall as a button plus 18, and they sit at its foot.
    private func placeTrafficLights(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), let close = window.standardWindowButton(.closeButton),
              let strip = close.superview?.superview else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        let stride = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.minX : close.frame.width + 6
        let height = close.frame.height + ArisSidebarMetrics.trafficLights.y
        var frame = strip.frame
        frame.size.height = height
        frame.origin.y = window.frame.height - height
        strip.frame = frame
        for (index, button) in buttons.enumerated() {
            button.setFrameOrigin(NSPoint(x: ArisSidebarMetrics.trafficLights.x + CGFloat(index) * stride, y: 0))
        }
    }

    func windowWillClose(_ notification: Notification) {
        ArisShortcutRecorder.active?.stop()
        visible = false
        NSApp.setActivationPolicy(ArisOnboardingGuide.shared.hasWindow ? .regular : .accessory)
        // Opened from the guide (to change the talk key): the guide comes back in front.
        if ArisOnboardingGuide.shared.showing { DispatchQueue.main.async { ArisOnboardingGuide.shared.settingsClosed() } }
    }

    func windowDidMiniaturize(_ notification: Notification) { visible = false }
    func windowDidDeminiaturize(_ notification: Notification) { visible = true }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard let window else { return }
        visible = window.isVisible && window.occlusionState.contains(.visible)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // The material stays active while the window is key, and rests when it isn't (the measured focus behaviour).
        material?.state = .active
        if let window { placeTrafficLights(window) }
    }

    func windowDidResignKey(_ notification: Notification) {
        material?.state = .inactive
    }

    func windowDidResize(_ notification: Notification) {
        if let window { placeTrafficLights(window) }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        if let window { placeTrafficLights(window) }
    }
}

/// The window's material: one behind-window sidebar material the size of the window, rounded 20 and continuous.
enum ArisSettingsMaterial {
    @MainActor static func make() -> NSVisualEffectView {
        let view = NSVisualEffectView(frame: NSRect(origin: .zero, size: ArisSettingsWindow.size))
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = ArisSidebarMetrics.windowRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.maskImage = nil
        view.autoresizingMask = [.width, .height]
        return view
    }

    /// The window's own corners at `radius` too, where macOS offers it (it is not public API; a Mac without it keeps
    /// its own corners and the material is still rounded 20 inside them).
    @MainActor static func round(_ window: NSWindow, radius: CGFloat) {
        let selector = NSSelectorFromString("_setCornerRadius:")
        guard window.responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, CGFloat) -> Void
        let setter = unsafeBitCast(window.method(for: selector), to: Setter.self)
        setter(window, selector, radius)
    }
}

/// The settings window itself: ⌘Q with it in front quits Aris like the menu's Quit (ninth VM pass: it did nothing while
/// the menu bar still belonged to the app before, ArisSettingsFront). The window hears a key equivalent before the menu.
final class ArisSettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, ArisSettingsQuitKey.quits(characters: event.charactersIgnoringModifiers, keyCode: event.keyCode, flags: event.modifierFlags) {
            NSApp.terminate(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The settings window's content. A click on one of its controls counts even when it is the click that brings the
/// window forward: SwiftUI's controls otherwise spend that click on making the window key, so a button pressed while
/// the notch, a side panel or another app had the keyboard did nothing the first time (upgrade VM run 2026-11-11:
/// 다시 시작 needed two clicks).
final class ArisSettingsHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Appearance, accent and characters for the whole window.
struct ArisSettingsRoot: View {
    @Default(.arisSettingsTheme) private var theme
    @State private var accent = Color.effectiveAccent
    /// The notch page's folded groups stay as they were left.
    nonisolated(unsafe) static let folds = ArisSettingsFolds(store: .standard)

    var body: some View {
        ArisLiveSettings()
            .frame(minWidth: ArisSettingsWindow.minimum.width, minHeight: ArisSettingsWindow.minimum.height)
            .environment(\.arisSettingsArt, .live)
            .environment(\.arisSettingsFolds, ArisSettingsRoot.folds)
            .preferredColorScheme(theme == "light" ? .light : theme == "dark" ? .dark : nil)
            .tint(accent)
            .onReceive(NotificationCenter.default.publisher(for: .accentColorChanged)) { _ in accent = .effectiveAccent }
            .ignoresSafeArea()
    }
}

extension ArisSettingsArt {
    /// Aris's face (ArisFace, live) and the teammates' faces as the notch draws them: their baked sprites on a layer.
    @MainActor static let live = ArisSettingsArt(
        star: { size in AnyView(ArisCharacterView(size: size, label: "Aris", follows: false, isAris: true).environment(\.colorScheme, .dark)) },
        aris: { state, size in AnyView(ArisCharacterView(state: state, size: size, label: "Aris", follows: false, isAris: true).environment(\.colorScheme, .dark)) },
        face: { look, size, still in AnyView(ArisCharacterView(look: look, size: size, follows: false, still: still).environment(\.colorScheme, .dark)) })
}

// MARK: - Shortcut recorder

/// Records a shortcut for a KeyboardShortcuts name. The next key with ⌘, ⌥ or ⌃ (or a function key alone) becomes
/// it, unless the system or the menus use it (ArisShortcutCaps.problem, the main menu); esc cancels; ⌫ or ⌦ clears it.
/// Aris's shortcuts are paused only while it records, and it stops whenever the window stops being where the user types
/// (it loses key, the app goes to the back, the window minimises or closes, a page or a detail screen opens), so they
/// can't stay paused. Keys typed into another field are never swallowed: focusing one ends the recording.
@MainActor
final class ArisShortcutRecorder: ObservableObject {
    static weak var active: ArisShortcutRecorder?

    @Published private(set) var recording: String?
    /// Rises after each change, so the caps are read again.
    @Published private(set) var version = 0
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    static let names: [String: KeyboardShortcuts.Name] = ["talkToAris": .talkToAris, "answerClaude": .answerClaude, "openClipboard": .openClipboard,
                                                          "toggleNotchOpen": .toggleNotchOpen, "toggleSneakPeek": .toggleSneakPeek,
                                                          "pasteLastDictation": .pasteLastDictation, "openRightPanel": .openRightPanel]
    private static let functionKeys: Set<UInt16> = [96, 97, 98, 99, 100, 101, 103, 105, 106, 107, 109, 111, 113, 118, 120, 122, 135]

    init() {
        let center = NotificationCenter.default
        let stops: [(Notification.Name, AnyObject?)] = [(NSWindow.didResignKeyNotification, nil), (NSWindow.willMiniaturizeNotification, nil),
                                                         (NSWindow.willCloseNotification, nil), (NSApplication.didResignActiveNotification, NSApp)]
        observers = stops.map { name, object in
            center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let monitor {
            NSEvent.removeMonitor(monitor)
            // Never leave the shortcuts paused.
            Task { @MainActor in KeyboardShortcuts.isEnabled = true }
        }
    }

    func toggle(_ name: String) {
        if recording == name { stop() } else { start(name) }
    }

    private static let dictation = ArisDictationKey.Choice.recorderName

    private func start(_ name: String) {
        stop()
        guard Self.names[name] != nil || name == Self.dictation else { return }
        // Whatever field had the keyboard lets go, so typing can't land in it meanwhile.
        NSApp.keyWindow?.makeFirstResponder(nil)
        recording = name
        Self.active = self
        KeyboardShortcuts.isEnabled = false
        // The dictation key is one modifier held by itself: its recorder hears modifiers too, and nothing dictates meanwhile.
        ArisDictationKeyTap.paused = name == Self.dictation
        monitor = NSEvent.addLocalMonitorForEvents(matching: name == Self.dictation ? [.keyDown, .flagsChanged] : .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        KeyboardShortcuts.isEnabled = true
        ArisDictationKeyTap.paused = false
    }

    func clear(_ name: String) {
        // The dictation key can't be none: there is nothing to clear.
        guard let shortcut = Self.names[name] else { return }
        KeyboardShortcuts.setShortcut(nil, for: shortcut)
        stop()
        version += 1
        ArisSettingsOverlay.shared.show("단축키를 지웠어요")
    }

    /// The event, or nil when the recorder takes it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let recording, Self.names[recording] != nil || recording == Self.dictation else { stop(); return event }
        // Another window, or a field the user clicked into: not the recorder's key.
        if event.window?.identifier != NSUserInterfaceItemIdentifier("ArisSettingsWindow") || event.window?.firstResponder is NSText {
            stop()
            return event
        }
        if recording == Self.dictation { return takeDictationKey(event) }
        switch event.keyCode {
        case 53: stop()
        case 51, 117: clear(recording)
        default: take(event, for: recording)
        }
        return nil
    }

    /// The dictation key's recorder: the modifier key that goes down becomes it, unless it is one that is pressed for
    /// other things all the time (ArisDictationKey.Choice.problem says why, with the talk key when that is the reason).
    /// Esc cancels; any other key is refused with what can be picked.
    private func takeDictationKey(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            if event.keyCode == 53 { stop(); return nil }
            ArisSettingsOverlay.shared.show(ArisDictationKey.Choice.problem(keyCode: nil, talkModifiers: [], talkCaps: [], english: ArisUIWords.english) ?? "", tone: .bad)
            return nil
        }
        // A modifier went down (its own bit is set), not up.
        guard let key = ArisDictationKey.Choice.key(event.keyCode), UInt64(event.modifierFlags.rawValue) & key.flag != 0 else { return event }
        let talk = KeyboardShortcuts.getShortcut(for: .talkToAris)
        let kinds: [(NSEvent.ModifierFlags, ArisDictationKey.Choice.Kind)] = [(.option, .option), (.command, .command), (.control, .control), (.shift, .shift), (.function, .function)]
        let talkModifiers = Set(kinds.filter { talk?.modifiers.contains($0.0) == true }.map(\.1))
        if let problem = ArisDictationKey.Choice.problem(keyCode: key.keyCode, talkModifiers: talkModifiers, talkCaps: talk.map { ArisShortcutCaps.caps($0.description) } ?? [],
                                                         english: ArisUIWords.english) {
            ArisSettingsOverlay.shared.show(problem, tone: .bad)
            return nil
        }
        UserDefaults.standard.set(Int(key.keyCode), forKey: ArisDictationKey.Choice.storeKey)
        ArisDictationKeyTap.shared.reset()
        stop()
        version += 1
        ArisSettingsOverlay.shared.show(ArisDictationKey.Choice.changed(english: ArisUIWords.english))
        return nil
    }

    private func take(_ event: NSEvent, for name: String) {
        guard let key = Self.names[name], let shortcut = KeyboardShortcuts.Shortcut(event: event) else { return }
        let flags = event.modifierFlags
        let modifiers = [(NSEvent.ModifierFlags.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")].filter { flags.contains($0.0) }.map(\.1)
        let letter = event.charactersIgnoringModifiers?.uppercased() ?? ""
        if let problem = ArisShortcutCaps.problem(modifiers: modifiers, key: letter, functionKey: Self.functionKeys.contains(event.keyCode)) {
            return ArisSettingsOverlay.shared.show(problem, tone: .bad)
        }
        if shortcut.isTakenBySystem || Self.inMainMenu(letter, flags) {
            return ArisSettingsOverlay.shared.show("macOS와 앱이 쓰는 단축키예요. 다른 키를 눌러 주세요", tone: .bad)
        }
        KeyboardShortcuts.setShortcut(shortcut, for: key)
        stop()
        version += 1
        ArisSettingsOverlay.shared.show("단축키를 바꿨어요")
    }

    /// The app's main menu has an item on this key and these modifiers.
    private static func inMainMenu(_ key: String, _ flags: NSEvent.ModifierFlags) -> Bool {
        let wanted = flags.intersection([.command, .option, .control, .shift])
        func search(_ menu: NSMenu) -> Bool {
            menu.items.contains { item in
                if let sub = item.submenu, search(sub) { return true }
                return !item.keyEquivalent.isEmpty && item.keyEquivalent.uppercased() == key
                    && item.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == wanted
            }
        }
        return NSApp.mainMenu.map(search) ?? false
    }
}

// MARK: - Accent colour panel

/// The system colour panel for 강조 색's last swatch; each colour picked is passed on.
@MainActor
final class ArisAccentPanel: NSObject {
    static let shared = ArisAccentPanel()
    private var pick: ((NSColor) -> Void)?

    func open(_ pick: @escaping (NSColor) -> Void) {
        self.pick = pick
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) { pick?(panel.color) }
}
