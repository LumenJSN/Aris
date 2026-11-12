//
//  ArisDisplayIdentity.swift
//  Aris
//
//  Which display is which, across reboots and re-plugging: the system's display UUID (upper-case, dashed) is the
//  key Aris stores in preferences and per-display maps. A small directory maps UUIDs back to the current NSScreen
//  objects and is rebuilt whenever the screen setup changes.
//

import AppKit
import CoreGraphics

/// The display UUID for a CoreGraphics display id, as the system spells it (`CFUUIDCreateString`).
enum ArisDisplayUUID {
    static func string(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String?
    }
}

/// UUID → screen, for any screen-like object (tests use stand-ins). Screens without a UUID are skipped.
struct ArisScreenDirectory<Screen: AnyObject> {
    private(set) var all: [Screen] = []
    private var byUUID: [String: Screen] = [:]

    init(screens: [Screen], uuid: (Screen) -> String?) {
        rebuild(screens: screens, uuid: uuid)
    }

    mutating func rebuild(screens: [Screen], uuid: (Screen) -> String?) {
        var map: [String: Screen] = [:]
        var kept: [Screen] = []
        for screen in screens {
            guard let key = uuid(screen), map[key] == nil else { continue }
            map[key] = screen
            kept.append(screen)
        }
        byUUID = map
        all = kept
    }

    func screen(for uuid: String) -> Screen? { byUUID[uuid] }

    var uuids: [String: Screen] { byUUID }
}

/// The app-wide directory of the current screens, refreshed on every screen-parameter change.
@MainActor
final class ArisScreens {
    static let shared = ArisScreens()

    private var directory = ArisScreenDirectory<NSScreen>(screens: [], uuid: { $0.displayUUID })
    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        directory.rebuild(screens: NSScreen.screens, uuid: { $0.displayUUID })
    }

    /// The screen showing the display with this UUID. A miss, or a screen object the system has since replaced,
    /// refreshes the directory once, so a lookup made before the change notification arrives is still right.
    func screen(for uuid: String) -> NSScreen? {
        let current = NSScreen.screens
        if let hit = directory.screen(for: uuid), current.contains(where: { $0 === hit }) { return hit }
        refresh()
        return directory.screen(for: uuid)
    }

    var byUUID: [String: NSScreen] {
        if directory.all.contains(where: { screen in !NSScreen.screens.contains { $0 === screen } }) { refresh() }
        return directory.uuids
    }
}

extension NSScreen {
    /// The CoreGraphics id of this screen's display.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The display's stable UUID string, or nil when the system has none for it.
    var displayUUID: String? {
        displayID.flatMap(ArisDisplayUUID.string(for:))
    }

    @MainActor
    static func screen(withUUID uuid: String) -> NSScreen? {
        ArisScreens.shared.screen(for: uuid)
    }

    @MainActor
    static var screensByUUID: [String: NSScreen] {
        ArisScreens.shared.byUUID
    }
}
