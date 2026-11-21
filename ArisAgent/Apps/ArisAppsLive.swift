//
//  ArisAppsLive.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  The app layer on the Mac: installed apps from the application folders and LaunchServices (each bundle's names in
//  every language it carries), the running list, opening without activating, `sdef` for scripting dictionaries, the
//  App Intents metadata file, `shortcuts`, the Automation grant asked without a prompt
//  (AEDeterminePermissionToAutomateTarget with askUserIfNeeded false), `osascript` for the scripting channel, the
//  displays' usable areas; and the engine adapter over jv-cu's ArisNativeRunner (by its argv).
//

import AppKit
import CoreServices
import Foundation

/// A child process with a time limit; its output and error read in full.
enum ArisAppsProcess {
    static func run(_ path: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval) -> (status: Int32, output: Data, error: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let out = Pipe(), err = Pipe(), stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return (-1, Data(), Data(error.localizedDescription.utf8)) }
        if let input {
            stdin.fileHandleForWriting.write(input)
            try? stdin.fileHandleForWriting.close()
        }
        // Read while it runs so a full pipe never stalls it.
        var output = Data(), errors = Data()
        let reading = DispatchGroup()
        reading.enter()
        DispatchQueue.global().async { output = out.fileHandleForReading.readDataToEndOfFile(); reading.leave() }
        reading.enter()
        DispatchQueue.global().async { errors = err.fileHandleForReading.readDataToEndOfFile(); reading.leave() }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = reading.wait(timeout: .now() + 2)
            return (-2, output, Data("timed out after \(Int(timeout)) s".utf8))
        }
        _ = reading.wait(timeout: .now() + 5)
        return (process.terminationStatus, output, errors)
    }
}

final class ArisAppsLiveSystem: ArisAppsSystem {
    static let folders = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                          NSHomeDirectory() + "/Applications", "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
    private let lock = NSLock()
    private var shortcutCache: (at: Date, names: [String])?

    // MARK: - Apps

    func installedApps() -> [ArisApps.AppRecord] {
        var seen = Set<String>(), out: [ArisApps.AppRecord] = []
        func add(_ url: URL) {
            guard let record = Self.record(url), !seen.contains(record.bundle.lowercased()) else { return }
            seen.insert(record.bundle.lowercased())
            out.append(record)
        }
        let manager = FileManager.default
        for folder in Self.folders {
            for name in (try? manager.contentsOfDirectory(atPath: folder)) ?? [] {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                if name.hasSuffix(".app") { add(url); continue }
                // One level of folders (/Applications/Microsoft Office/, a vendor's folder).
                var isFolder: ObjCBool = false
                if manager.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
                    for inner in ((try? manager.contentsOfDirectory(atPath: url.path)) ?? []) where inner.hasSuffix(".app") { add(url.appendingPathComponent(inner)) }
                }
            }
        }
        add(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        // Apps kept elsewhere that LaunchServices knows: the catalog's bundles asked by id.
        for row in ArisApps.Catalog.rows {
            for bundle in row.bundles where !seen.contains(bundle.lowercased()) {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { add(url) }
            }
        }
        return out
    }

    /// One app bundle: its id, version and every name it carries.
    static func record(_ url: URL) -> ArisApps.AppRecord? {
        guard let info = bundleInfo(url) else { return nil }
        var names = [url.deletingPathExtension().lastPathComponent]
        for name in info.names + [FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")] where !names.contains(name) {
            names.append(name)
        }
        return ArisApps.AppRecord(bundle: info.bundle, names: names, path: url.path, version: info.version)
    }

    static func bundleInfo(_ url: URL) -> ArisApps.BundleInfo? {
        let contents = url.appendingPathComponent("Contents")
        guard let plist = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")) else { return nil }
        let resources = contents.appendingPathComponent("Resources")
        let loctable = try? Data(contentsOf: resources.appendingPathComponent("InfoPlist.loctable"))
        var strings: [String: Data] = [:]
        if loctable == nil {
            for language in ["ko", "en", "Base", "English", "Korean"] {
                if let data = try? Data(contentsOf: resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")) { strings[language] = data }
            }
        }
        guard var info = ArisApps.BundleInfo.parse(infoPlist: plist, loctable: loctable, strings: strings), !info.bundle.isEmpty else { return nil }
        // Only Korean and English names are kept from a table of forty languages.
        info.localizedNames = info.localizedNames.filter { ["ko", "en", "Base", "English", "Korean", "en_GB"].contains($0.key) }
        return info
    }

    func runningApps() -> [ArisAppsRunning] {
        let front = ArisFrontLive.frontPid()
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, !app.isTerminated, let bundle = app.bundleIdentifier else { return nil }
            return ArisAppsRunning(bundle: bundle, name: app.localizedName ?? bundle, pid: app.processIdentifier, hidden: app.isHidden,
                                   active: app.processIdentifier == front)
        }
    }

    func frontmost() -> ArisAppsRunning? {
        guard let pid = ArisFrontLive.frontPid(), let app = NSRunningApplication(processIdentifier: pid), let bundle = app.bundleIdentifier else { return nil }
        return ArisAppsRunning(bundle: bundle, name: app.localizedName ?? bundle, pid: pid, hidden: app.isHidden, active: true)
    }

    func defaultBrowser() -> String? {
        guard let url = URL(string: "https://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return Bundle(url: app)?.bundleIdentifier
    }

    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = request.front
        configuration.addsToRecentItems = false
        let done = DispatchSemaphore(value: 0)
        let box = ArisAppsBox<String?>(nil)
        let finish: (Error?) -> Void = { error in box.value = error?.localizedDescription; done.signal() }
        let app = request.bundle.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        if let link = request.url ?? request.path.map({ URL(fileURLWithPath: $0).absoluteString }), let url = URL(string: link) {
            if request.path != nil, !FileManager.default.fileExists(atPath: request.path!) { return (false, "no file at \(request.path!)") }
            if request.reveal, let path = request.path {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                return (true, "shown")
            }
            if let app {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in finish(error) }
            } else {
                NSWorkspace.shared.open(url, configuration: configuration) { _, error in finish(error) }
            }
        } else if let app {
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in finish(error) }
        } else {
            return (false, "nothing to open")
        }
        guard done.wait(timeout: .now() + 15) == .success else { return (false, "it didn't open within 15 seconds") }
        return box.value.map { (false, $0) } ?? (true, "opened")
    }

    func quit(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.terminate() ?? false }
    func hide(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.hide() ?? false }
    func activate(pid: Int32) -> Bool { NSRunningApplication(processIdentifier: pid)?.activate() ?? false }

    /// The app's main window (the one it keeps as main while another app is in front), else its focused one, raised.
    func raiseMainWindow(pid: Int32) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { continue }
            AXUIElementPerformAction(value as! AXUIElement, kAXRaiseAction as CFString)
            return
        }
    }

    func bundleInfo(path: String) -> ArisApps.BundleInfo? { Self.bundleInfo(URL(fileURLWithPath: path)) }

    // MARK: - Channels

    func scriptingDictionary(path: String) -> Data? {
        let result = ArisAppsProcess.run("/usr/bin/sdef", [path], timeout: 10)
        return result.status == 0 && !result.output.isEmpty ? result.output : nil
    }

    /// Only Apple's shared scripting definitions are read this way.
    func includedDictionary(path: String) -> Data? {
        guard path.hasPrefix("/System/Library/ScriptingDefinitions/"), !path.contains("..") else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }

    func intentsMetadata(path: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent("Contents/Resources/Metadata.appintents/extract.actionsdata"))
    }

    func shortcuts() -> [String] {
        if let cached = lock.withLock({ shortcutCache }), Date().timeIntervalSince(cached.at) < 300 { return cached.names }
        let result = ArisAppsProcess.run("/usr/bin/shortcuts", ["list"], timeout: 10)
        let names = result.status == 0 ? String(decoding: result.output, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.isEmpty } : []
        lock.withLock { shortcutCache = (Date(), names) }
        return names
    }

    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String) {
        var arguments = ["run", name]
        var inputFile: URL?
        if let input {
            inputFile = FileManager.default.temporaryDirectory.appendingPathComponent("aris-apps-shortcut-\(UUID().uuidString).txt")
            try? Data(input.utf8).write(to: inputFile!)
            arguments += ["--input-path", inputFile!.path]
        }
        let outputFile = FileManager.default.temporaryDirectory.appendingPathComponent("aris-apps-shortcut-\(UUID().uuidString).out")
        arguments += ["--output-path", outputFile.path]
        defer {
            if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
            try? FileManager.default.removeItem(at: outputFile)
        }
        let result = ArisAppsProcess.run("/usr/bin/shortcuts", arguments, timeout: 60)
        let output = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? String(decoding: result.error, as: UTF8.self)
        return (result.status == 0, output)
    }

    /// The permission layer's check (ArisAutomationAccess, shared with the app), never asking; at most 4 s.
    func automation(bundle: String) -> ArisApps.Grant {
        let answer = ArisAppsBox<ArisPermissionState?>(nil)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            answer.value = ArisAutomationAccess.state(of: bundle)
            done.signal()
        }
        guard done.wait(timeout: .now() + 4) == .success, let state = answer.value else { return .unknown }
        return ArisApps.Grant(state)
    }

    static func grant(_ status: OSStatus) -> ArisApps.Grant { ArisApps.Grant(ArisAutomationAccess.state(status: status)) }

    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?) {
        let result = ArisAppsProcess.run("/usr/bin/osascript", ["-"], input: Data(source.utf8), timeout: timeout)
        let output = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: result.error, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.status == 0 ? (true, output, nil) : (false, error, Self.errorCode(error))
    }

    /// osascript's "… (-1743)" at the end of its error line.
    static func errorCode(_ text: String) -> Int? {
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        return Int(text[text.index(after: open)..<close])
    }

    func pathKind(_ path: String) -> ArisApps.PathKind {
        let expanded = (path as NSString).expandingTildeInPath
        var url = URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
        // A Finder alias opens what it points at.
        if (try? url.resourceValues(forKeys: [.isAliasFileKey]))?.isAliasFile == true, let target = try? URL(resolvingAliasFileAt: url) {
            url = target.resolvingSymlinksInPath()
        }
        var isFolder: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
        return ArisApps.Risk.kind(resolved: url.path, isFolder: isFolder.boolValue, executable: !isFolder.boolValue && FileManager.default.isExecutableFile(atPath: url.path),
                                  exists: exists, home: NSHomeDirectory())
    }

    func displays() -> [ArisApps.Rect] {
        let screens = NSScreen.screens
        guard let mainHeight = screens.first?.frame.height else { return [] }
        return screens.map { screen in
            let visible = screen.visibleFrame
            return ArisApps.Rect(x: Double(visible.minX), y: Double(mainHeight - visible.maxY), width: Double(visible.width), height: Double(visible.height))
        }
    }
}

/// A value set on another thread and read after a wait.
final class ArisAppsBox<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}

/// The computer-use engine (jv-cu's), called by its argv; its JSON envelope back.
final class ArisAppsNativeEngine: ArisAppsEngine {
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON {
        let (_, output) = ArisNativeRunner.shared.run(arguments, context: ArisNativeContext(job: background))
        return ArisApps.JSON(any: try? JSONSerialization.jsonObject(with: output))
    }
}

extension ArisAppsHands {
    /// The helper's app layer: the Mac's seams, and what it learns kept in Aris's own folder.
    static let shared: ArisAppsHands = {
        let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/aris/aris/apps")
        let hands = ArisAppsHands(system: ArisAppsLiveSystem(), ax: ArisAppsLiveAccessibility(), engine: ArisAppsNativeEngine(), store: ArisAppsFileStore(folder: folder))
        // What a replace erases is kept in the undo store, verified, so "되돌려" puts it back (fourth VM run, D1).
        hands.keepText = { text in ArisUndoStore(home: NSHomeDirectory()).keep(data: Data(text.utf8)) }
        // The app the owner was in, for putting it back after an app was brought forward (sixth VM run, item 4).
        ArisAppsOwnerFront.shared.start()
        return hands
    }()
}
