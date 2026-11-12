//
//  ArisDesktopLive.swift
//  aris-agent
//
//  The desktop engine's live parts: the running and installed apps (NSWorkspace, every name and bundle id an app has
//  checked against the never-list), their windows front to back (CGWindowList: ids and frames, no Screen Recording
//  needed), aris-agent's Accessibility and Screen Recording grants (Peekaboo runs as its child, so macOS counts it under
//  aris-agent's grants: the responsible process), secure input, the pointer and the front app (kept and put back around
//  a real click), the user's names for the privacy filter, and Apple Vision's text reading. The vision brain is
//  ArisDesktopVision.swift.
//

import AppKit
import ApplicationServices
import Carbon
import Foundation
import Vision

/// The window server's id of an Accessibility window (HIServices; no public equivalent).
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct ArisDesktopLiveApps: ArisDesktopApps {
    /// The app that has the keyboard now (ArisFrontLive): NSWorkspace's answer goes stale in this process (second
    /// upgrade run, bug 1), and "keys may go" must be true at the moment of the key.
    func frontmostPid() -> Int32? { ArisFrontLive.frontPid() }

    func secondsSinceKeyDown() -> Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) }

    func identity(pid: Int32) -> ArisCardTarget? {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, let started = ArisProcessStart.of(pid: pid) else { return nil }
        return ArisCardTarget(pid: pid, bundle: bundle, started: started)
    }

    /// Walks up from the focused element (at most 40 levels): an AXWebArea above it is web content.
    func focusedInWebArea(pid: Int32) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let focused = value, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var element = focused as! AXUIElement
        for _ in 0..<40 {
            var role: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success, role as? String == "AXWebArea" { return true }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success, let next = parent,
                  CFGetTypeID(next) == AXUIElementGetTypeID() else { return false }
            element = next as! AXUIElement
        }
        return nil
    }

    func isAris(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == ArisDataRoute.appBundleId }

    func clipboardChanges() -> Int? { NSPasteboard.general.changeCount }
    func clipboardText() -> String? { NSPasteboard.general.string(forType: .string) }

    /// The window at `frame`, asked for its AXModified (a document window's unsaved-changes mark).
    func documentEdited(pid: Int32, frame: CGRect) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            var position: CFTypeRef?, size: CFTypeRef?
            var origin = CGPoint.zero, dimensions = CGSize.zero
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                  ArisWindowTitles.same(CGRect(origin: origin, size: dimensions), frame) else { continue }
            var modified: CFTypeRef?
            // "AXModified" (kAXModifiedAttribute, which Swift doesn't import): the window's document has unsaved changes.
            guard AXUIElementCopyAttributeValue(window, "AXModified" as CFString, &modified) == .success else { return nil }
            return modified as? Bool
        }
        return nil
    }

    func raiseWindow(pid: Int32, frame: CGRect) {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var position: CFTypeRef?, size: CFTypeRef?
            var origin = CGPoint.zero, dimensions = CGSize.zero
            guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
                  ArisWindowTitles.same(CGRect(origin: origin, size: dimensions), frame) else { continue }
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    func focusedWindowFrame(pid: Int32) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let window = value as! AXUIElement
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    /// NSWorkspace's list lags behind an app that just quit or started again (it is updated by notifications, seen in
    /// the benchmark's relaunches), so it only names the bundle; the process is then asked for afresh.
    func resolve(_ name: String) -> ArisDesktopTarget? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        var listed = NSWorkspace.shared.runningApplications.filter { $0.localizedName?.lowercased() == wanted || $0.bundleIdentifier?.lowercased() == wanted }
        // Said by another of the app's own names (its Korean name on an English Mac, its file's, another spacing): the
        // running apps' names are asked (desk-imp-4: `see --app "메모"` answered "that app isn't running").
        if listed.isEmpty {
            listed = NSWorkspace.shared.runningApplications.filter { app in
                app.activationPolicy == .regular && (app.bundleIdentifier.map { ArisAppIdentity.isNamed(name, among: ArisAppIdentity.names(ofBundle: $0)) } ?? false)
            }
        }
        var bundles = Set(listed.compactMap(\.bundleIdentifier))
        if bundles.isEmpty, let bundle = ArisAppIdentity.bundle(for: name) { bundles = [bundle] }
        let fresh = bundles.isEmpty ? listed : bundles.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        // Only processes still alive (the list can hold one that just quit).
        let found = fresh.filter { !$0.isTerminated && $0.activationPolicy != .prohibited && kill($0.processIdentifier, 0) == 0 }
        if found.count == 1, let app = found.first { return Self.target(app) }
        // None (the list lags behind a fresh launch) or several (a second copy of the app): the window server decides,
        // as Peekaboo targets a window: the one process with a normal window on screen, else the one whose window is
        // frontmost in z-order (a background app behind another's window included) (bench bg_toggle, bg_message).
        return Self.byWindow(wanted: wanted, bundles: bundles, among: Set(found.map(\.processIdentifier))).map(Self.target)
    }

    /// The process owning the frontmost normal on-screen window of an app with this name or one of these bundle ids
    /// (among `pids` when there are several candidates).
    static func byWindow(wanted: String, bundles: Set<String>, among pids: Set<Int32>) -> NSRunningApplication? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where info[kCGWindowLayer as String] as? Int == 0 {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pids.isEmpty || pids.contains(pid),
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated, let bundle = app.bundleIdentifier else { continue }
            // Always by the owner's bundle id (one of the app's): never a window's owner name, which any process can carry.
            if bundles.contains(bundle) { return app }
        }
        return nil
    }

    func installed(_ name: String) -> ArisDesktopTarget? {
        guard let bundle = ArisAppIdentity.bundle(for: name), let url = ArisAppIdentity.url(ofBundle: bundle) else { return nil }
        let display = ArisAppIdentity.name(ofBundle: bundle) ?? url.deletingPathExtension().lastPathComponent
        let names: [String] = [display, bundle, url.deletingPathExtension().lastPathComponent] + Array(ArisAppIdentity.names(ofBundle: bundle))
        // Not running: no process to pin a type to, so never a type at once (security review: the gate checks the exact
        // process the keys reach; an app launched later is another one). Its card asks.
        return Self.target(name: display, bundle: bundle, pid: 0, names: names, known: true, appleSigned: false)
    }

    func dock() -> ArisDesktopTarget? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first.map(Self.target)
    }

    static func target(_ app: NSRunningApplication) -> ArisDesktopTarget {
        let bundle = app.bundleIdentifier
        let name = app.localizedName ?? bundle ?? "?"
        let file = app.bundleURL.map { $0.deletingPathExtension().lastPathComponent }
        let names: [String?] = [name, bundle, file] + (bundle.map { Array(ArisAppIdentity.names(ofBundle: $0)) } ?? [])
        let known = bundle.flatMap(ArisAppIdentity.url(ofBundle:)) != nil
        // The running process itself, signed by Apple as that bundle: only checked for the safe typing apps.
        let signed = bundle.map { ArisRiskPolicy.isSafeTypingApp(name: name, bundle: $0) && ArisAppIdentity.isAppleSigned(pid: app.processIdentifier, bundle: $0) } ?? false
        return target(name: name, bundle: bundle, pid: app.processIdentifier, names: names.compactMap { $0 }, known: known, appleSigned: signed)
    }

    static func target(name: String, bundle: String?, pid: Int32, names: [String], known: Bool, appleSigned: Bool = false) -> ArisDesktopTarget {
        let browser = names.contains { ArisRiskPolicy.isBrowser(name: $0, bundle: bundle, webHandlers: ArisAppIdentity.webHandlers) }
        let sending = names.contains { ArisRiskPolicy.isSendingApp(bundle: bundle, name: $0) }
        return ArisDesktopTarget(name: name, bundle: bundle, pid: pid, known: known, never: ArisRiskPolicy.computerUseIsNever(names),
                                 browser: browser, sending: sending, settings: ArisRiskPolicy.isSystemSettings(names + [bundle]), appleSigned: appleSigned)
    }

    func isRunning(_ target: ArisDesktopTarget) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: target.pid), !app.isTerminated else { return false }
        return app.bundleIdentifier == target.bundle
    }

    var secureInput: Bool { IsSecureEventInputEnabled() }

    /// The folder a Finder window shows: its window (by its window id) through Accessibility, its document URL.
    func shownPath(_ target: ArisDesktopTarget, window: Int?) -> String? {
        guard target.pid > 0, let window else { return nil }
        let app = AXUIElementCreateApplication(target.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let windows = value as? [AXUIElement] else { return nil }
        for element in windows {
            var id: CGWindowID = 0
            guard _AXUIElementGetWindow(element, &id) == .success, Int(id) == window else { continue }
            for attribute in [kAXDocumentAttribute as String, "AXURL"] {
                var document: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, attribute as CFString, &document) == .success else { continue }
                if let text = document as? String, let url = URL(string: text), url.isFileURL { return url.path }
                if let url = document as? URL, url.isFileURL { return url.path }
            }
            return nil
        }
        return nil
    }
}

struct ArisDesktopLiveWindows: ArisDesktopWindows {
    func windows(of pid: Int32) -> [ArisDesktopWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // The window server gives titles only with Screen Recording; Accessibility (which the engine has) gives them
        // too, so a window named by its title is found either way (QA BUG-47's follow-up).
        return ArisWindowTitles.titled(Self.windows(in: list, pid: pid), accessibility: Self.accessibilityTitles(of: pid))
    }

    /// The app's windows as Accessibility has them: each one's frame (top-left, as the window server's) and title.
    static func accessibilityTitles(of pid: Int32) -> [(frame: CGRect, title: String)] {
        guard AXIsProcessTrusted() else { return [] }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { window in
            var title: CFTypeRef?, position: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success, let text = title as? String,
                  AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
                  let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero, dimensions = CGSize.zero
            guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
            return (CGRect(origin: origin, size: dimensions), text)
        }
    }

    /// Every on-screen window at any level, front to back.
    private static var everything: [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    /// Aris's own processes (the app draws the overlay over the window being worked on; it passes clicks through).
    private static var arisPids: Set<Int32> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.lumenjsn.aris").map(\.processIdentifier))
    }

    func topWindow(at point: CGPoint) -> (pid: Int32, id: Int)? {
        ArisPointerHit.topWindow(at: point, in: Self.everything, skipping: Self.arisPids, displays: Self.displays, system: Self.system)
    }

    func hitsAris(_ point: CGPoint) -> Bool {
        ArisPointerHit.hitsAris(point, arisWindows: ArisPointerHit.arisWindows(in: Self.everything, aris: Self.arisPids, displays: Self.displays))
    }

    /// The Dock (by its bundle id), the window manager (by its), and the window server (by its executable's path: it is
    /// no app).
    private static var system: ArisPointerHit.System {
        // The Dock by its bundle id and its executable's path both.
        let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").map(\.processIdentifier)
            .first { path(of: $0) == "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock" }
        var others = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").map(\.processIdentifier))
        let owners = Set(everything.compactMap { $0[kCGWindowOwnerPID as String] as? Int32 })
        for pid in owners where path(of: pid) == "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer" { others.insert(pid) }
        return ArisPointerHit.System(dock: dock, others: others)
    }

    private static func path(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Every display's frame (global points).
    private static var displays: [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    func promptOnScreen() -> String? {
        Self.everything.compactMap { info -> String? in
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0, let owner = info[kCGWindowOwnerName as String] as? String else { return nil }
            let bundle = (info[kCGWindowOwnerPID as String] as? Int32).flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
            return ArisRiskPolicy.isAuthPrompt(owner) || bundle.map(ArisRiskPolicy.isAuthPrompt) == true ? owner : nil
        }.first
    }

    /// The list is front to back: this process's normal, visible, real-sized windows in that order.
    static func windows(in list: [[String: Any]], pid: Int32) -> [ArisDesktopWindow] {
        list.compactMap { info -> ArisDesktopWindow? in
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let number = info[kCGWindowNumber as String] as? Int, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any], let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 60, frame.height >= 40 else { return nil }
            return ArisDesktopWindow(id: number, frame: frame, title: info[kCGWindowName as String] as? String)
        }
    }
}

final class ArisDesktopLiveAccess: ArisDesktopAccess {
    private let lock = NSLock()
    private var guided: Set<String> = []

    var trusted: Bool { AXIsProcessTrusted() }
    /// As macOS has it now, not as it was when the agent started (the stale answer of VM bug 1 would keep --ocr and
    /// click-at refused after the user switched aris-agent on, until the agent restarted).
    var screenRecording: Bool { ArisScreenAccess.now }

    func guide() { open("Privacy_Accessibility") }
    func guideScreen() { open("Privacy_ScreenCapture") }

    /// System Settings at that pane, once per agent run each.
    private func open(_ pane: String) {
        let first = lock.withLock { guided.insert(pane).inserted }
        guard first, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        DispatchQueue.main.async { NSWorkspace.shared.open(url) }
    }
}

struct ArisDesktopLivePointer: ArisDesktopPointer {
    func save() -> ArisDesktopPointerState {
        ArisDesktopPointerState(location: CGEvent(source: nil)?.location, frontmost: ArisFrontLive.frontPid())
    }

    /// The pointer back where it was (no click), and the app that was in front back in front.
    func restore(_ state: ArisDesktopPointerState) {
        if let location = state.location { CGWarpMouseCursorPosition(location) }
        if let pid = state.frontmost, pid != ArisFrontLive.frontPid() {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }
}

enum ArisDesktopLiveIdentity {
    static var current: ArisDesktopIdentity {
        ArisDesktopIdentity(userName: NSUserName(), fullName: NSFullUserName(), home: FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

/// Apple Vision, accurate, Korean and English: each line of text with its box (top-left origin, unit square).
struct ArisDesktopLiveText: ArisDesktopTextReader {
    func read(png: Data) -> [(text: String, box: CGRect)] {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true
        do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, observation.confidence >= 0.3 else { return nil }
            let box = observation.boundingBox
            return (text, CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
        }
    }
}

extension ArisDesktopEngine {
    /// The agent's one engine; Peekaboo's snapshot folders go when a conversation forgets them.
    static let shared = ArisDesktopEngine(installer: ArisDesktopInstaller(), apps: ArisDesktopLiveApps(), access: ArisDesktopLiveAccess(),
                                          windows: ArisDesktopLiveWindows(), pointer: ArisDesktopLivePointer(),
                                          vision: ArisDesktopLiveVision(environment: ArisAgentRunner.environment()), reader: ArisDesktopLiveText(),
                                          identity: ArisDesktopLiveIdentity.current, tools: ArisAgentRunner.toolsPath,
                                          computerEngine: { ArisComputerEngineChoice.current })
}
