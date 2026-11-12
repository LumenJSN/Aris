//
//  ArisOnboardingWatch.swift
//  Aris
//
//  What the first-run guide listens to while it shows, in one place so closing it removes every observer: Esc (only
//  while the guide's own window is key), Aris becoming active or not (the overlay steps aside when it isn't), another
//  app coming to the front (the setup window takes its place again while macOS's prompts are answered), the
//  displays changing, the Mac waking and the Space changing (the host display is looked up again), and Reduce Motion
//  (read live). Also whether this launch came from a login item (the guide never resumes for one).
//

import AppKit
import Carbon

@MainActor
final class ArisOnboardingWatch {
    struct Handlers {
        /// Esc while the guide's window is key; returns whether it was taken.
        var escape: @MainActor @Sendable () -> Bool
        var active: @MainActor @Sendable (Bool) -> Void
        /// An app came to the front (Aris or any other): its bundle id, and whether it is an app with a Dock icon.
        var front: @MainActor @Sendable (String?, Bool) -> Void
        /// Displays changed, the Mac woke or the Space changed.
        var host: @MainActor @Sendable () -> Void
        var reduceMotion: @MainActor @Sendable (Bool) -> Void
    }

    private var keyMonitor: Any?
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []

    func start(_ handlers: Handlers) {
        stop()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            return handlers.escape() ? nil : event
        }
        let app = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        observe(app, NSApplication.didBecomeActiveNotification) { handlers.active(true) }
        observe(app, NSApplication.didResignActiveNotification) { handlers.active(false) }
        let frontToken = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let taker = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = taker?.bundleIdentifier, regular = taker?.activationPolicy == .regular
            MainActor.assumeIsolated { handlers.front(bundleID, regular) }
        }
        tokens.append((workspace, frontToken))
        observe(app, NSApplication.didChangeScreenParametersNotification) { handlers.host() }
        observe(workspace, NSWorkspace.didWakeNotification) { handlers.host() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { handlers.host() }
        observe(workspace, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { handlers.reduceMotion(Self.reduceMotion) }
        observe(app, UserDefaults.didChangeNotification) { handlers.reduceMotion(Self.reduceMotion) }
    }

    func stop() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
    }

    /// The system's Reduce Motion or Aris's own 모션 줄이기, now.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || UserDefaults.standard.bool(forKey: "arisReduceMotion")
    }

    /// This launch was macOS opening Aris as a login item (read before the launch event is gone).
    static func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor @Sendable () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { action() } }
        tokens.append((center, token))
    }
}
