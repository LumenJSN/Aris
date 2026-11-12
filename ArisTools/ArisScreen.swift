//
//  ArisScreen.swift
//  aris-tools
//
//  What the user is looking at, so "이거 요약해줘" works: the selected text, the clipboard,
//  the browser's front tab (and its text), Finder's selection, and the front window's text
//  (a screenshot read with Vision). Password managers are never read.
//

import AppKit
import ApplicationServices
import Foundation
import Vision

private let browsers = ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac"]
private let textLimit = 4000
private let pageLimit = 6000

func selectedText(_ args: [String]) {
    requireAccessibility()
    let system = AXUIElementCreateSystemWide()
    var focused: AnyObject?, selected: AnyObject?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID(),
          AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success,
          let text = selected as? String, !text.isEmpty else {
        return print("nothing selected")
    }
    print(ArisActions.trimmedScreenText(text, limit: textLimit))
}

func clipboard(_ args: [String]) {
    let board = NSPasteboard.general
    if args.first == "set" {
        let text = args.dropFirst().joined(separator: " ")
        board.clearContents()
        board.setString(text, forType: .string)
        return print("copied \(text.count) characters")
    }
    guard let text = board.string(forType: .string), !text.isEmpty else { return print("the clipboard has no text") }
    print(ArisActions.trimmedScreenText(text, limit: textLimit))
}

/// `tab [--text]`: the front browser tab's address and title, and with --text the page's words.
func frontTab(_ args: [String]) {
    var args = args
    // `tab --app <bundle id>`: exactly that browser, for a caller that knows which one it means (ArisTabTarget).
    let named = option("--app", in: &args)
    if args.contains("--app") { fail("usage: tab [--text] [--app <bundle id>]") }
    // The app in front now (ArisFrontLive: NSWorkspace's answer goes stale in a process like this one).
    let front = ArisFrontLive.front()?.bundleId
    let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    let browser: String
    switch ArisTabTarget.choose(named: named, front: front, running: running, browsers: browsers) {
    case .browser(let id): browser = id
    case .refused(let why): fail(why)
    }
    guard let script = ArisActions.tabScript(bundleID: browser) else { fail("no browser is open") }
    let name = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == browser }?.localizedName ?? "the browser"
    let tab = appleScript(script, app: name)
    print(tab)
    guard args.contains("--text"), let address = tab.split(separator: ",").first.map({ String($0).trimmingCharacters(in: .whitespaces) }),
          ArisActions.isWebLink(address), let url = URL(string: address) else { return }
    let page = String(decoding: fetchData(url), as: UTF8.self)
        .replacingOccurrences(of: #"(?is)<(script|style|noscript)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "\n", options: .regularExpression)
        .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
    print("\n" + ArisActions.trimmedScreenText(page, limit: pageLimit))
}

func fetchData(_ url: URL) -> Data {
    var result: Data?
    let done = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 8)) { data, _, _ in
        result = data
        done.signal()
    }.resume()
    done.wait()
    return result ?? Data()
}

func finderSelection(_ args: [String]) {
    let paths = appleScript(ArisActions.finderSelectionScript, app: "Finder")
    print(paths.isEmpty ? "nothing selected in Finder" : paths)
}

/// `screen [--image]`: the front window's text (Vision), and with --image the screenshot's path.
/// `screen [--image]`: the front window's text; `screen --around x,y,w,h`: the text in that part of the screen
/// (global points from the top left), for what the pointer is on.
func screenText(_ args: [String]) {
    // `screen --access`: whether Screen Recording is on for whoever started this (aris-agent), as macOS has it now. The
    // agent asks here because a process that is already running keeps the answer it got when it started (VM bug 1).
    // Nothing is captured and macOS is asked to show nothing.
    if args.first == "--access" { return print(CGPreflightScreenCaptureAccess() ? "on" : "off") }
    var args = args
    // `screen --pid <n>`: that app's window, when the one in front is Aris itself or a macOS prompt (ArisLookTarget).
    // aris-agent's alone; a pid that is no running app fails, and `--around` takes none (ArisScreenTarget).
    let flagged = args.contains("--pid"), around = args.contains("--around"), value = option("--pid", in: &args)
    let named: NSRunningApplication?
    switch ArisScreenTarget.named(flagged: flagged, value: value, around: around, environment: ProcessInfo.processInfo.environment,
                                  runs: { NSRunningApplication(processIdentifier: $0) != nil }) {
    case .front: named = nil
    case .pid(let pid):
        guard let found = NSRunningApplication(processIdentifier: pid) else { fail(ArisScreenTarget.notRunning(String(pid))) }
        named = found
    case .refused(let why): fail(why)
    }
    guard let app = named ?? ArisFrontLive.frontPid().flatMap({ NSRunningApplication(processIdentifier: $0) }) else { fail("no app in front") }
    // Apps whose windows are never captured or read: the one list shared with Aris (`ArisCaptureRules`).
    guard !ArisCaptureRules.isPrivate(app.bundleIdentifier) else { fail("\(app.localizedName ?? "That app") is private; I don't read it") }
    var words = args
    if let region = option("--around", in: &words) {
        let parts = region.split(separator: ",").compactMap { Int($0) }
        guard parts.count == 4, parts[2] > 0, parts[3] > 0, parts[2] <= 2_000, parts[3] <= 2_000 else { fail("usage: screen --around x,y,w,h") }
        // A private app's window anywhere in that part of the screen: nothing is captured (the look's own rule).
        let part = CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
        guard !ArisScreenTarget.coversPrivate(part, windows: onScreenWindows(), isPrivate: ArisCaptureRules.isPrivate) else { fail(ArisScreenTarget.privateThere) }
        let folder = arisFolder.appendingPathComponent("work")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("pointer.png")
        run("/usr/sbin/screencapture", ["-x", "-R", parts.map(String.init).joined(separator: ","), file.path])
        defer { try? FileManager.default.removeItem(at: file) }
        guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fail(ArisLocalStore.screenLine(CGPreflightScreenCaptureAccess() ? .captureError("no image") : .noPermission), fix: CGPreflightScreenCaptureAccess() ? nil : .pane(.screen))
        }
        let lines = recognizedLines(image)
        // Without Screen Recording macOS hands over the picture with no windows in it: said as what it is, never "no text".
        if lines.isEmpty, !CGPreflightScreenCaptureAccess() { fail(ArisLocalStore.screenLine(.noPermission)) }
        return print(lines.isEmpty ? "(no text there)" : ArisActions.trimmedScreenText(lines.joined(separator: "\n"), limit: 1_500))
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let listed = windows.compactMap { window -> ArisScreenTarget.Listed? in
        guard let number = window[kCGWindowNumber as String] as? Int, let pid = window[kCGWindowOwnerPID as String] as? Int32,
              let layer = window[kCGWindowLayer as String] as? Int else { return nil }
        return ArisScreenTarget.Listed(number: number, pid: pid, layer: layer)
    }
    // `--window <id>` (the look's, with --pid): exactly that window, while it is still that app's own on screen.
    let requested = named == nil ? nil : option("--window", in: &words)
    if named == nil, words.contains("--window") { fail(ArisScreenTarget.windowUsage) }
    let picked = ArisScreenTarget.window(requested: requested ?? (words.contains("--window") ? "" : nil), pid: app.processIdentifier, windows: listed)
    if case .refused(let why) = picked { fail(why) }
    guard case .window(let number) = picked, let window = windows.first(where: { ($0[kCGWindowNumber as String] as? Int) == number }) else {
        fail(ArisLocalStore.screenLine(.noWindow(app.localizedName ?? "앱")))
    }
    let folder = arisFolder.appendingPathComponent("work")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("screen.png")
    run("/usr/sbin/screencapture", ["-x", "-o", "-l", String(number), file.path])
    guard let image = NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail(ArisLocalStore.screenLine(CGPreflightScreenCaptureAccess() ? .captureError("no image") : .noPermission), fix: CGPreflightScreenCaptureAccess() ? nil : .pane(.screen))
    }
    let lines = recognizedLines(image)
    if lines.isEmpty, !CGPreflightScreenCaptureAccess() { fail(ArisLocalStore.screenLine(.noPermission)) }
    print("\(app.localizedName ?? "") — \(window[kCGWindowName as String] as? String ?? "")")
    print(lines.isEmpty ? "(no text on screen)" : ArisActions.trimmedScreenText(lines.joined(separator: "\n"), limit: textLimit))
    if args.contains("--image") { print("image: \(file.path)") }
}

/// The lines of text Vision reads in an image (Korean and English).
func recognizedLines(_ image: CGImage) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(cgImage: image).perform([request])
    } catch {
        fail(ArisLocalStore.screenLine(CGPreflightScreenCaptureAccess() ? .captureError(error.localizedDescription) : .noPermission), fix: CGPreflightScreenCaptureAccess() ? nil : .pane(.screen))
    }
    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}
