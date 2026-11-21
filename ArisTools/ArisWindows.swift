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
    // Never macOS's own alert from here: it came up again at every call while the switch was off. The app asks
    // once (ArisPermissions) and the fix names the pane.
    guard AXIsProcessTrusted() else {
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
    // The turn's turn at the keys and pointer, in a moment with no input from the user (ArisDesktopHold).
    desktopHold()
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
    ArisBoundedRun.capture("/usr/bin/osascript", ["-e", script], limit: ArisBoundedRun.appleScriptLimit,
                           atLimit: automationWait("/usr/bin/osascript", ["-e", script]))?.status == 0
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
    // The new windows come up in front: only in the turn's turn at the keys and pointer, with no input from the user then.
    desktopHold()
    let app = activate(name)
    let before = standardWindows(of: app).count
    for _ in 0..<count {
        if !tryAppleScript("tell application \(ArisActions.quoted(app.localizedName ?? name)) to make new document") {
            requireAccessibility()
            // ⌘N by Aris's own engine (the key that types "n" on the layout in use, to the app's process).
            let sent = engineKeys(["cmd+n"], times: 1, bundle: app.bundleIdentifier)
            if !sent.ok { fail(sent.line) }
        }
        usleep(500_000)
    }
    // Windows take a moment to appear; report what's there.
    for _ in 0..<20 where standardWindows(of: app).count < before + count { usleep(250_000) }
    print("\(app.localizedName ?? name) now has \(standardWindows(of: app).count) window(s)")
}

// MARK: - keys, typing

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

/// `keys <chord> [--app X] [--times N]`: by Aris's own engine in the agent (ArisEngineKeys): into the app's focused
/// window in the background, or with a brief turn in front in a gap in the user's input; never into whatever is in front.
func keys(_ args: [String]) {
    requireAccessibility()
    var words = args
    let app = option("--app", in: &words)
    let times = min(20, max(1, Int(option("--times", in: &words) ?? "1") ?? 1))
    guard let written = words.first, ArisKeyChord.parse(written) != nil else { fail("usage: keys cmd+shift+t [--app X] [--times N]") }
    let target: NSRunningApplication
    if let app {
        target = keysTarget(app)
    } else {
        guard let front = keyboardApp() else { fail("no app has the keyboard to send keys to") }
        target = front
    }
    guard let bundle = target.bundleIdentifier else { fail("\(target.localizedName ?? "that app") has no bundle id, so no keys were sent") }
    let sent = engineKeys([written], times: times, bundle: bundle)
    if sent.ok { print(sent.line) } else { fail(sent.line) }
}

/// The app `name` names exactly, running (opened behind the front app when it isn't), never a terminal: the app keys
/// go to. Nothing is brought forward here.
func keysTarget(_ name: String) -> NSRunningApplication {
    let resolved = appFileName(for: name)
    var app = runningApp(named: name)
    if app == nil {
        run("/usr/bin/open", ["-g", "-a", resolved ?? name])
        for _ in 0..<50 where app?.isFinishedLaunching != true {
            usleep(200_000)
            app = runningApp(named: name)
        }
    }
    guard let app, app.isFinishedLaunching else { fail("\(name) didn't open") }
    let file = app.bundleURL?.deletingPathExtension().lastPathComponent
    guard ArisAppNames.isExactly(name, resolved: resolved, localizedName: app.localizedName, fileName: file) else { fail("no app is named exactly \(name)") }
    guard ArisActions.isTypingSafe(bundleID: app.bundleIdentifier) else { fail("won't type into \(app.localizedName ?? name)") }
    return app
}

/// `type '<text>' [--app X] [--title <window>] [--at end|start]`: the text typed into the field with the keyboard focus in that app's window, by the agent's
/// desktop engine (ArisTypeRequest): aris-tools itself never types.
func typeText(_ args: [String]) {
    let front = keyboardApp().flatMap { $0.bundleIdentifier ?? $0.localizedName }
    switch ArisTypeRequest.call(args, keyboardApp: front) {
    case .failure(let why): fail(why.line)
    case .success(let call): desktopCall(call.words, text: call.text)
    }
}
