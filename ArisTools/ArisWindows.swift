//
//  ArisWindows.swift
//  aris-tools
//
//  Several windows at once, new windows, and keys: "Word 4개 켜서 4등분" is
//  `new "Microsoft Word" --count 4` then `tile "Microsoft Word" --grid 2x2`. Moving
//  windows and pressing keys need Accessibility for aris-agent.
//

import AppKit
import ApplicationServices
import Foundation

func requireAccessibility() {
    ArisOrigin.refuseUnlessStillAllowed()
    guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
        fail("\(ArisFix.Pane.accessibility.title(english: true)) permission needed: System Settings → Privacy & Security → \(ArisFix.Pane.accessibility.title(english: true)) → allow Aris, then try again", fix: .pane(.accessibility))
    }
}

/// A running app by its shown name or its file name: on a Korean Mac TextEdit shows as "텍스트 편집기". A name said
/// another way ("텍스트편집기", an alias) finds it by its file name (ArisAppNames).
func runningApp(named name: String) -> NSRunningApplication? {
    func find(_ name: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            let file = app.bundleURL?.deletingPathExtension().lastPathComponent
            return app.activationPolicy == .regular && !app.isTerminated
                && (app.localizedName?.localizedCaseInsensitiveContains(name) == true || file?.localizedCaseInsensitiveContains(name) == true)
        }
    }
    if let app = find(name) { return app }
    return appFileName(for: name).flatMap { $0 == name ? nil : find($0) }
}

/// The installed apps (the usual folders), each by its shown (localized) name and file name; read once.
private let installedApps: [ArisAppNames.App] = {
    let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                   NSHomeDirectory() + "/Applications"]
    return folders.flatMap { folder -> [ArisAppNames.App] in
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        return names.filter { $0.hasSuffix(".app") }.map { name in
            let file = String(name.dropLast(4))
            var shown = FileManager.default.displayName(atPath: folder + "/" + name)
            if shown.hasSuffix(".app") { shown = String(shown.dropLast(4)) }
            return ArisAppNames.App(display: shown, file: file)
        }
    }
}()

/// The app's file name for a name as said or shown ("텍스트 편집기" → TextEdit); nil when none matches.
func appFileName(for name: String) -> String? { ArisAppNames.match(name, in: installedApps) }

/// What `open -a` is given for a name as said or shown: the app's file name when it is known, else the name itself.
func appOpenName(for name: String) -> String { ArisAppNames.openName(name, in: installedApps) }

/// The app's normal, visible windows, front to back.
func standardWindows(of app: NSRunningApplication) -> [AXUIElement] {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else { return [] }
    return windows.filter { window in
        var subrole: AnyObject?, minimized: AnyObject?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
        return subrole as? String == kAXStandardWindowSubrole as String && (minimized as? Bool) != true
    }
}

func title(of window: AXUIElement) -> String {
    var value: AnyObject?
    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value)
    return value as? String ?? ""
}

/// Moves a window to `frame` in screen coordinates (which grow upward); Accessibility measures from the
/// top left of the main display.
func place(_ window: AXUIElement, at frame: CGRect) {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.maxY
    var origin = ArisDisplayGeometry.topLeft(frame, primaryHeight: primaryHeight).origin, size = frame.size
    // Size first: moved first, a tall window is pushed back by the screen's edge and keeps a clipped height (QA BUG-14).
    if let dimensions = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) }
    if let position = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) }
    if let dimensions = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) }
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
}

/// The window's size as the app has it now (nil when it can't be read).
func windowSize(_ window: AXUIElement) -> CGSize? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value) == .success, let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}

// MARK: - windows, tile

func listWindows(_ args: [String]) {
    requireAccessibility()
    let name = args.joined(separator: " ")
    let apps = name.isEmpty ? NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular } : [runningApp(named: name)].compactMap { $0 }
    guard !apps.isEmpty else { fail("\(name) isn't running") }
    let lines = apps.flatMap { app in standardWindows(of: app).map { "\(app.localizedName ?? "?") — \(title(of: $0))" } }
    print(lines.isEmpty ? "no windows" : lines.prefix(40).joined(separator: "\n"))
}

/// `tile <app>[,<app>…] [--grid RxC]`: the apps' windows in a grid on the main screen.
func tile(_ args: [String]) {
    requireAccessibility()
    var words = args
    let named = option("--grid", in: &words)
    let names = words.joined(separator: " ").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard !names.isEmpty, !names[0].isEmpty else { fail("usage: tile <app>[,<app>…] [--grid 2x2]") }
    let windows = names.flatMap { name -> [AXUIElement] in
        guard let app = runningApp(named: name) else { fail("\(name) isn't running") }
        return standardWindows(of: app)
    }
    guard !windows.isEmpty else { fail("no windows to arrange") }
    let grid: ArisWindowGrid.Grid
    if let named {
        guard let parsed = ArisWindowGrid.grid(named: named) else { fail("grid must look like 2x2 (rows x columns)") }
        grid = parsed
    } else {
        grid = ArisWindowGrid.grid(for: windows.count)
    }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { fail("no screen") }
    let frames = ArisWindowGrid.frames(count: windows.count, grid: grid, in: screen.visibleFrame)
    // Windows that were just opened may still be animating in and ignore the first move: place them twice.
    for pass in 0..<2 {
        if pass > 0 { usleep(400_000) }
        for (window, frame) in zip(windows, frames) { place(window, at: frame) }
    }
    // Read back: a window that still isn't its cell's size is placed once more.
    usleep(200_000)
    for (window, frame) in zip(windows, frames) {
        if let size = windowSize(window), abs(size.width - frame.width) > 1 || abs(size.height - frame.height) > 1 { place(window, at: frame) }
    }
    print("arranged \(frames.count) window(s) in \(grid.rows)x\(grid.columns)")
}

// MARK: - new windows

/// AppleScript that may fail (an app without `make new document`): false instead of quitting.
func tryAppleScript(_ script: String) -> Bool {
    // With AppleScript's time limit, like every other script: an app that hangs counts as one that can't.
    ArisBoundedRun.capture("/usr/bin/osascript", ["-e", script], limit: ArisBoundedRun.appleScriptLimit)?.status == 0
}

/// Opens the app if needed and brings it to the front; the running app once it's up.
func activate(_ name: String) -> NSRunningApplication {
    for attempt in 0..<50 {
        if let app = runningApp(named: name) {
            if app.isFinishedLaunching {
                app.activate()
                usleep(300_000)
                return app
            }
        } else if attempt % 15 == 0 {
            // Not running (or it was just quitting): open it by its file name (`open -a` doesn't know a Korean name), and
            // again later if it still isn't there.
            run("/usr/bin/open", ["-a", appFileName(for: name) ?? name])
        }
        usleep(200_000)
    }
    fail("\(name) didn't open")
}

/// `new <app> [--count N]`: N new windows or documents.
func newWindows(_ args: [String]) {
    var words = args
    let count = min(9, max(1, Int(option("--count", in: &words) ?? "1") ?? 1))
    let name = words.joined(separator: " ")
    guard !name.isEmpty, !name.contains("/") else { fail("usage: new <app> [--count N]") }
    let app = activate(name)
    let before = standardWindows(of: app).count
    for _ in 0..<count {
        if !tryAppleScript("tell application \(ArisActions.quoted(app.localizedName ?? name)) to make new document") {
            requireAccessibility()
            app.activate()
            // ⌘N by the key that types "n" on the layout in use (audit desk-10).
            press(ArisKeyChord.parse("cmd+n", layout: ArisKeyLayout.current) ?? ArisKeyChord(key: 45, command: true, shift: false, option: false, control: false))
        }
        usleep(500_000)
    }
    // Windows take a moment to appear; report what's there.
    for _ in 0..<20 where standardWindows(of: app).count < before + count { usleep(250_000) }
    print("\(app.localizedName ?? name) now has \(standardWindows(of: app).count) window(s)")
}

// MARK: - keys, typing

func press(_ chord: ArisKeyChord) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: chord.key, keyDown: down)
        event?.flags = chord.flags
        event?.post(tap: .cghidEventTap)
        usleep(20_000)
    }
}

/// Brings `name` to the front for keys or typing, or stops: it must be exactly that app (not one whose name merely
/// contains it), not a terminal or password app, and really in front, so nothing lands anywhere else.
@discardableResult
func typingTarget(_ name: String) -> NSRunningApplication {
    // The name is resolved once (an alias, another spacing), and that same answer says whether the app found is the one.
    let resolved = appFileName(for: name)
    let app = activate(name)
    let file = app.bundleURL?.deletingPathExtension().lastPathComponent
    guard ArisAppNames.isExactly(name, resolved: resolved, localizedName: app.localizedName, fileName: file) else { fail("no app is named exactly \(name)") }
    guard ArisActions.isTypingSafe(bundleID: app.bundleIdentifier) else { fail("won't type into \(app.localizedName ?? name)") }
    guard ArisFrontNow.keysGo(focused: ArisFrontLive.focusedPid(), target: app.processIdentifier) else {
        fail("\(app.localizedName ?? name) didn't come to the front")
    }
    return app
}

/// The app in front now, asked at this moment (ArisFrontLive): NSWorkspace's answer is kept up by notifications this
/// process never gets, so it stays what it was at the first look (a "still in front?" check before each key would
/// never see the user switch apps).
func frontApp() -> NSRunningApplication? {
    ArisFrontLive.frontPid().flatMap { NSRunningApplication(processIdentifier: $0) }
}

/// The app that has the keyboard, by Accessibility alone, for keys and typing (review 9, L4): nil when it can't tell.
func keyboardApp() -> NSRunningApplication? {
    ArisFrontLive.focusedPid().flatMap { NSRunningApplication(processIdentifier: $0) }
}

/// The app's focused window; nil when it has none.
func focusedWindow(of pid: pid_t) -> AXUIElement? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

/// An element's frame as Accessibility gives it (the primary display's top left, y down); nil when it can't be read.
func axFrame(_ element: AXUIElement) -> CGRect? {
    var position: AnyObject?, size: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
          let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: origin, size: dimensions)
}

/// The app's focused UI element (where typed keys go), and its text; nil when there is none or it can't be read.
func focusedElement(of pid: pid_t) -> AXUIElement? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

func elementText(_ element: AXUIElement) -> String? {
    var value: AnyObject?
    guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

/// `keys <chord> [--app X] [--times N]`.
func keys(_ args: [String]) {
    requireAccessibility()
    var words = args
    let app = option("--app", in: &words)
    let times = min(20, max(1, Int(option("--times", in: &words) ?? "1") ?? 1))
    guard let written = words.first, let chord = ArisKeyChord.parse(written, layout: ArisKeyLayout.current) else { fail("usage: keys cmd+shift+t [--app X] [--times N]") }
    guard let target = app.map({ typingTarget($0) }) ?? keyboardApp() else { fail("no app has the keyboard to send keys to") }
    let shown = target.localizedName ?? app ?? "the app in front"
    for _ in 0..<times {
        // Each press only while that app is still in front, so no key lands in another one.
        guard ArisFrontNow.keysGo(focused: ArisFrontLive.focusedPid(), target: target.processIdentifier) else {
            fail(ArisTypeReadback.keysLine(written, times: times, app: shown, stayedInFront: false).line)
        }
        press(chord)
        usleep(80_000)
    }
    print(ArisTypeReadback.keysLine(written, times: times, app: shown, stayedInFront: true).line)
}

/// `type <text> [--app X]`: types the text as if from the keyboard (any language).
func typeText(_ args: [String]) {
    requireAccessibility()
    var words = args
    let app = option("--app", in: &words)
    let text = words.joined(separator: " ")
    guard !text.isEmpty else { fail("usage: type <text> [--app X]") }
    guard let target = app.map({ typingTarget($0) }) ?? keyboardApp() else { fail("no app has the keyboard to type into") }
    let shown = target.localizedName ?? app ?? "the app in front"
    // Its window, on whichever display it is (QA BUG-33: one left of and above the main display), raised and made the
    // app's main window so the keys go there; one on no display is never typed into.
    if let window = focusedWindow(of: target.processIdentifier) {
        if let frame = axFrame(window), let primary = NSScreen.screens.first?.frame.height,
           ArisDisplayGeometry.display(for: frame, screens: NSScreen.screens.map(\.frame), primaryHeight: primary) == nil {
            fail(ArisTypeReadback.offScreenLine(app: shown))
        }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        usleep(150_000)
    }
    // Where the keys will go, read before anything is typed (QA BUG-10): no focused field, nothing typed.
    guard let field = focusedElement(of: target.processIdentifier) else { fail(ArisTypeReadback.noFieldLine(app: shown)) }
    let before = elementText(field)
    let source = CGEventSource(stateID: .hidSystemState)
    let characters = Array(text.utf16)
    for start in stride(from: 0, to: characters.count, by: 16) {
        let chunk = Array(characters[start..<min(start + 16, characters.count)])
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            event?.post(tap: .cghidEventTap)
        }
        usleep(15_000)
    }
    // Read back: the text must be in the focused field now, or it is a failure the brain can't call done.
    usleep(250_000)
    // The field the keys were aimed at first (another display's window may hand the focus elsewhere after), then whatever
    // has the focus now.
    let after = elementText(field) ?? focusedElement(of: target.processIdentifier).flatMap(elementText)
    let outcome = ArisTypeReadback.result(text, app: shown, before: before, after: after)
    guard outcome.ok else { fail(outcome.line) }
    print(outcome.line)
}
