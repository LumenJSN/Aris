//
//  ArisFrontLive.swift
//  aris-agent, aris-tools
//
//  The live half of ArisFrontNow: which app is in front, asked of the window server and of Accessibility at the
//  moment of asking. Neither aris-agent nor aris-tools is an AppKit app: what NSWorkspace says about the app in front
//  is kept up by notifications such a process doesn't get, so after Safari was launched over a TextEdit memo the
//  helper went on "seeing" TextEdit for every look until it was restarted (second upgrade run, bug 1), and a key
//  press's "is that app still in front?" asked the same stale answer. Here:
//  - `windows()`: CGWindowList, front to back, as the screen is now (no permission needed for owners and layers);
//  - `focusedPid()`: the app Accessibility says has the keyboard now (with Accessibility; nil without it);
//  - `frontPid()`: the keyboard's app, else the owner of the topmost window of an app;
//  - `app(_:)`: a process's name, bundle id and whether it is an ordinary app, from AppKit when it knows the process
//    and from the app's own Info.plist when it doesn't.
//

import AppKit
import ApplicationServices
import Darwin

enum ArisFrontLive {
    /// An app as a look or a key press needs it.
    struct App: Equatable {
        let pid: Int32
        let bundleId: String?
        let name: String
        /// It has a Dock icon (not a menu bar extra, a daemon or an app's hidden helper).
        let ordinary: Bool
    }

    /// The windows on screen now, front to back.
    static func windows() -> [ArisFrontNow.Window] {
        let listed = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return listed.compactMap(ArisFrontNow.window)
    }

    /// The app that has the keyboard now, as Accessibility says (nil without Accessibility, or when it can't tell).
    static func focusedPid() -> Int32? {
        guard AXIsProcessTrusted() else { return nil }
        // No messaging timeout here: set on the system-wide element it would become every Accessibility call's in this
        // process. The focused app is answered by the system, not by the app.
        let system = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        return AXUIElementGetPid(value as! AXUIElement, &pid) == .success && pid > 0 ? pid : nil
    }

    /// The app in front now: the keyboard's, else the owner of the topmost window that counts.
    static func frontPid() -> Int32? { ArisFrontNow.frontPid(focused: focusedPid(), windows: windows()) }

    /// The app in front now, with its name and bundle id.
    static func front() -> App? { frontPid().flatMap(app) }

    /// The app that has the keyboard, by Accessibility alone (no window-order guess): for keys and paste (review 9, L4).
    static func keyboardFront() -> App? { focusedPid().flatMap(app) }

    /// A running process as an app; nil when it is gone.
    static func app(_ pid: Int32) -> App? {
        let file = bundle(of: pid)
        let running = NSRunningApplication(processIdentifier: pid)
        guard running != nil || file != nil || kill(pid, 0) == 0 else { return nil }
        let info = file?.infoDictionary
        let bundleId = running?.bundleIdentifier ?? file?.bundleIdentifier
        let name = running?.localizedName ?? (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
            ?? file?.bundleURL.deletingPathExtension().lastPathComponent ?? "?"
        let ordinary = running.map { $0.activationPolicy == .regular } ?? ArisFrontNow.ordinary(bundlePath: file?.bundlePath, info: info)
        return App(pid: pid, bundleId: bundleId, name: name, ordinary: ordinary)
    }

    /// A process's bundle id (AppKit's, else its app's Info.plist).
    static func bundleId(_ pid: Int32) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? bundle(of: pid)?.bundleIdentifier
    }

    /// The .app a process runs from, read from its program's path.
    private static func bundle(of pid: Int32) -> Bundle? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0,
              let path = ArisFrontNow.bundlePath(executable: String(cString: buffer)) else { return nil }
        return Bundle(path: path)
    }
}
