//
//  ArisWindowWakes.swift
//  Aris
//
//  What tells ArisWindowFollower that its window may have changed. Each source stops when released or on `stop()`.
//  None of them reads a window title or contents: Accessibility is asked only for the window list, the window's
//  number and its position and size, and only to find the one window being followed.
//

import AppKit
import ApplicationServices

enum ArisWindowWakeReason {
    /// Read the frame once; track it only if it moved (a periodic, Space, hide or activation check).
    case check
    /// The window is moving: track it every frame until it settles.
    case track
    /// Closed, minimised or its app quit.
    case gone
    /// The left button went down, was dragged or came up somewhere. The follower arms drag tracking only for a press
    /// on its window.
    case pointerDown, pointerDragged, pointerUp
    /// The displays changed: the tracker's display link may be on a display that no longer exists.
    case screensChanged
}

/// A source of wakes for a followed window.
protocol ArisWindowWake: AnyObject {
    func stop()
}

/// Carries a wake to the follower on the main actor. NSEvent monitors and NSWorkspace/NotificationCenter observers
/// run on the main thread, so `fire` delivers synchronously there, without a Task per event, the way ArisSidePanels'
/// monitors do. AX callouts and the poll timer use `post` instead (see `arisAXWindowCallback`).
final class ArisWakeRelay: @unchecked Sendable {
    private let onWake: @MainActor (ArisWindowWakeReason) -> Void

    init(_ onWake: @escaping @MainActor (ArisWindowWakeReason) -> Void) {
        self.onWake = onWake
    }

    func fire(_ reason: ArisWindowWakeReason) {
        guard Thread.isMainThread else { return post(reason) }
        MainActor.assumeIsolated { onWake(reason) }
    }

    /// On the main actor's next turn. Used from timers (ArisSidePanels saw `assumeIsolated` crash in a timer).
    func post(_ reason: ArisWindowWakeReason) {
        Task { @MainActor in self.onWake(reason) }
    }
}

// MARK: - Accessibility

/// Observes one window through Accessibility. Fails (nil) when Aris isn't trusted, the window can't be found, or the
/// observer can't be added (the app sandbox or the target app refusing), so the follower falls back to polling.
final class ArisAXWindowWake: ArisWindowWake {
    /// Keeps a hung target app from stalling the main thread.
    static let messagingTimeout: Float = 0.25
    /// At most this many windows are compared by frame when the window number can't be read.
    static let frameMatchLimit = 8

    private static let windowNotifications = [kAXWindowMovedNotification, kAXWindowResizedNotification,
                                              kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification]
    private static let appNotifications = [kAXApplicationHiddenNotification, kAXFocusedWindowChangedNotification]

    private let observer: AXObserver
    private let app: AXUIElement
    private let window: AXUIElement
    private let relay: ArisWakeRelay
    private var addedToWindow: [String] = []
    private var addedToApp: [String] = []

    init?(pid: Int32, windowNumber: Int, frame: CGRect?, relay: ArisWakeRelay) {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard let window = Self.window(of: app, number: windowNumber, frame: frame) else { return nil }
        var created: AXObserver?
        guard AXObserverCreate(pid, arisAXWindowCallback, &created) == .success, let observer = created else { return nil }
        self.observer = observer
        self.app = app
        self.window = window
        self.relay = relay
        let refcon = Unmanaged.passUnretained(relay).toOpaque()
        addedToWindow = Self.windowNotifications.filter { AXObserverAddNotification(observer, window, $0 as CFString, refcon) == .success }
        // Failing here runs deinit, which takes back whatever was added.
        guard addedToWindow.contains(kAXWindowMovedNotification), addedToWindow.contains(kAXUIElementDestroyedNotification)
        else { return nil }
        addedToApp = Self.appNotifications.filter { AXObserverAddNotification(observer, app, $0 as CFString, refcon) == .success }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    deinit { stop() }

    func stop() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        addedToWindow.forEach { AXObserverRemoveNotification(observer, window, $0 as CFString) }
        addedToApp.forEach { AXObserverRemoveNotification(observer, app, $0 as CFString) }
        addedToWindow = []
        addedToApp = []
    }

    /// The AX window whose CG window number is `number`; by frame (among the first few windows) when the number
    /// can't be read.
    private static func window(of app: AXUIElement, number: Int, frame: CGRect?) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        if let match = windows.first(where: { windowNumber(of: $0) == number }) { return match }
        guard let frame else { return nil }
        return windows.prefix(frameMatchLimit).first { Self.frame(of: $0) == frame }
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Private but long-stable (window managers rely on it): the CG window number behind an AX window. Looked up at
    /// run time so a release without it falls back to matching by frame instead of failing to launch.
    private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    private static func windowNumber(of element: AXUIElement) -> Int? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? Int(id) : nil
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var position = CGPoint.zero, size = CGSize.zero
        guard let p = attribute(kAXPositionAttribute, of: element), AXValueGetValue(p, .cgPoint, &position),
              let s = attribute(kAXSizeAttribute, of: element), AXValueGetValue(s, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

/// Runs on the main run loop, where the observer's source is added.
///
/// Every AX wake is posted to the next main-actor turn, never fired synchronously: `.gone` runs `finish()` →
/// `stop()`, which releases ArisAXWindowWake and its AXObserver, and that must not happen while HIServices is still
/// inside this observer's callout. Posting `.track` and `.check` too keeps any AX-origin teardown out of the callout
/// (a failed read in either also ends the follow). The posted Task holds the relay, so it outlives the wake.
private func arisAXWindowCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                                  _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let relay = Unmanaged<ArisWakeRelay>.fromOpaque(refcon).takeUnretainedValue()
    switch notification as String {
    case kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification: relay.post(.gone)
    case kAXWindowMovedNotification, kAXWindowResizedNotification: relay.post(.track)
    default: relay.post(.check)
    }
}

// MARK: - Fallback and system events

/// Without Accessibility, as a last resort: a check every `interval` seconds while following, and never otherwise.
final class ArisPollWindowWake: ArisWindowWake {
    private var timer: Timer?

    init(every interval: TimeInterval, relay: ArisWakeRelay) {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in relay.post(.check) }
        timer.tolerance = interval / 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { stop() }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Left-button presses and drags anywhere (the follower decides whether a press was on its window), app hide,
/// unhide and activation, Space and display changes, and the target app quitting. Mouse monitors need no
/// permission; key events are never watched.
final class ArisSystemWindowWake: ArisWindowWake {
    private var monitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []

    init(pid: Int32, relay: ArisWakeRelay) {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            switch event.type {
            case .leftMouseDown: relay.fire(.pointerDown)
            case .leftMouseDragged: relay.fire(.pointerDragged)
            default: relay.fire(.pointerUp)
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        @Sendable func ours(_ note: Notification) -> Bool {
            (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier == pid
        }
        func on(_ name: Notification.Name, _ handler: @escaping @Sendable (Notification) -> Void) -> NSObjectProtocol {
            workspace.addObserver(forName: name, object: nil, queue: .main, using: handler)
        }
        workspaceObservers = [
            on(NSWorkspace.activeSpaceDidChangeNotification) { _ in relay.fire(.check) },
            on(NSWorkspace.didActivateApplicationNotification) { _ in relay.fire(.check) },
            on(NSWorkspace.didHideApplicationNotification) { note in if ours(note) { relay.fire(.check) } },
            on(NSWorkspace.didUnhideApplicationNotification) { note in if ours(note) { relay.fire(.check) } },
            on(NSWorkspace.didTerminateApplicationNotification) { note in if ours(note) { relay.fire(.gone) } },
        ]
        appObservers = [
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                   object: nil, queue: .main) { _ in relay.fire(.screensChanged) },
        ]
    }

    deinit { stop() }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers = []
        appObservers = []
    }
}
