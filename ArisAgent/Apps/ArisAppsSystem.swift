//
//  ArisAppsSystem.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  Every system call the app layer makes, behind four protocols, so the capabilities run against fakes in the tests
//  and against the Mac in the helper: the workspace (LaunchServices, the running list, Info.plists, sdef, App Intents
//  metadata, Shortcuts, the Automation grant, scripts), Accessibility (the menu bar, read and pressed; full screen),
//  the computer-use engine (jv-cu's ArisNativeRunner, called by its argv and never edited here), and a small store for
//  what the layer learns (aliases, channels, the command cache).
//

import CoreGraphics
import Foundation

/// A running app.
struct ArisAppsRunning: Equatable {
    var bundle: String
    var name: String
    var pid: Int32
    var hidden = false
    var active = false
}

/// What app.open is asked to open.
struct ArisAppsOpenRequest: Equatable {
    var bundle: String?
    var path: String?
    var url: String?
    /// Bring it forward (never for a background task).
    var front = false
    /// Show `path` selected in its Finder window instead of opening it.
    var reveal = false
}

protocol ArisAppsSystem: AnyObject {
    /// Every installed app (its file name and the shown names its bundle carries in each language).
    func installedApps() -> [ArisApps.AppRecord]
    func runningApps() -> [ArisAppsRunning]
    func frontmost() -> ArisAppsRunning?
    /// The default browser's bundle id.
    func defaultBrowser() -> String?
    func open(_ request: ArisAppsOpenRequest) -> (ok: Bool, message: String)
    func quit(pid: Int32) -> Bool
    func hide(pid: Int32) -> Bool
    func activate(pid: Int32) -> Bool
    func bundleInfo(path: String) -> ArisApps.BundleInfo?
    /// The app's scripting dictionary with its includes expanded (`sdef <path>`), nil when it has none.
    func scriptingDictionary(path: String) -> Data?
    /// A file a scripting dictionary includes (CocoaStandard.sdef and the like), by its path.
    func includedDictionary(path: String) -> Data?
    /// Contents/Resources/Metadata.appintents/extract.actionsdata, nil when it has none.
    func intentsMetadata(path: String) -> Data?
    /// The owner's Shortcuts by name.
    func shortcuts() -> [String]
    func runShortcut(_ name: String, input: String?) -> (ok: Bool, output: String)
    /// The Automation grant for a target, asked without ever bringing up the prompt.
    func automation(bundle: String) -> ArisApps.Grant
    /// Runs one AppleScript line (the scripting channel); `code` is the Apple Event error when it failed.
    func runScript(_ source: String, timeout: TimeInterval) -> (ok: Bool, output: String, code: Int?)
    /// What a path is once its aliases and links are resolved (a folder, a document, an app, something that runs).
    func pathKind(_ path: String) -> ArisApps.PathKind
    /// Each display's usable area (below the menu bar, beside the Dock), top-left origin, the main display first.
    func displays() -> [ArisApps.Rect]
    /// The app the owner has in front, never Aris itself: when Aris has the keyboard (a card he clicked, the composer),
    /// the app he was in last (sixth VM run, item 4). Nil when there is none.
    func ownerFront() -> ArisAppsRunning?
    /// Raises the app's own main window above the other apps' windows (Accessibility's AXRaise; no new permission).
    func raiseMainWindow(pid: Int32)
    /// The ordinary windows on screen, front to back: who owns each and where it is (the window server's list: no
    /// title, no picture, no permission).
    func windowOrder() -> [ArisAppsWindowPlace]
    /// Raises these windows one after another (the last ends on top), each by Accessibility's AXRaise on its owner's
    /// window at that frame. No pointer or key event.
    func raise(_ windows: [ArisAppsWindowPlace])
}

extension ArisAppsSystem {
    /// Nothing by default (the fakes of earlier tests): only the live system has windows to raise.
    func raiseMainWindow(pid: Int32) {}
    func windowOrder() -> [ArisAppsWindowPlace] { [] }
    func raise(_ windows: [ArisAppsWindowPlace]) {}

    /// By default the app in front, when it isn't Aris.
    func ownerFront() -> ArisAppsRunning? {
        frontmost().flatMap { ArisAppsHands.isAris($0.bundle) ? nil : $0 }
    }
}

protocol ArisAppsAccessibility: AnyObject {
    /// The app's menu bar (the Apple menu left out), nil when Accessibility shows none.
    func menuBar(pid: Int32) -> ArisApps.MenuBar?
    /// Presses the item at this path by Accessibility (opening a lazily built submenu on the way when needed).
    func pressMenu(pid: Int32, path: [String]) -> (ok: Bool, message: String)
    func setFullScreen(pid: Int32, window: Int, on: Bool) -> Bool
    /// The focused element's role in the engine's short form ("textField", "textArea"), nil when it can't be read.
    func focusedRole(pid: Int32) -> String?
    /// app.type's at=end: the caret put at the end of a text element of the app by setting its selected text range
    /// (never by keys): the element at `point` (global, top-left origin), or with none the focused one.
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd
}

extension ArisAppsAccessibility {
    /// Fail closed: an Accessibility that can't say is no text element, so at=end types nothing.
    func caretToEnd(pid: Int32, at point: (x: Double, y: Double)?) -> ArisApps.CaretEnd { .notText }
}

/// The computer-use engine by its argv (`see`, `click`, `type`, `press`, `window …`, `app …`): its JSON envelope back.
protocol ArisAppsEngine: AnyObject {
    func run(_ arguments: [String], background: Bool) -> ArisApps.JSON
}

/// What the app layer keeps between runs.
protocol ArisAppsStore: AnyObject {
    func loadAliases() -> ArisApps.Aliases
    func saveAliases(_ aliases: ArisApps.Aliases)
    func loadBook() -> ArisApps.ChannelBook
    func saveBook(_ book: ArisApps.ChannelBook)
    /// Commands discovered for one app version (its BundleInfo.versionKey), without the menu bar's live state.
    func cachedCommands(_ versionKey: String) -> [ArisApps.Command]?
    func cacheCommands(_ commands: [ArisApps.Command], for versionKey: String)
}

/// A store in memory (the tests, and the helper before its folder is known).
final class ArisAppsMemoryStore: ArisAppsStore {
    private var aliases = ArisApps.Aliases(), book = ArisApps.ChannelBook(), cache: [String: [ArisApps.Command]] = [:]
    private let lock = NSLock()
    func loadAliases() -> ArisApps.Aliases { lock.withLock { aliases } }
    func saveAliases(_ aliases: ArisApps.Aliases) { lock.withLock { self.aliases = aliases } }
    func loadBook() -> ArisApps.ChannelBook { lock.withLock { book } }
    func saveBook(_ book: ArisApps.ChannelBook) { lock.withLock { self.book = book } }
    func cachedCommands(_ versionKey: String) -> [ArisApps.Command]? { lock.withLock { cache[versionKey] } }
    func cacheCommands(_ commands: [ArisApps.Command], for versionKey: String) { lock.withLock { cache[versionKey] = commands } }
}

/// A store in a folder: aliases.json, channels.json and one file per app version under commands/.
final class ArisAppsFileStore: ArisAppsStore {
    let folder: URL
    private let lock = NSLock()

    init(folder: URL) { self.folder = folder }

    private func read<T: Decodable>(_ name: String, _ type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, _ name: String) {
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            try? FileHandle.standardError.write(contentsOf: Data("aris apps: couldn't save \(name): \(error.localizedDescription)\n".utf8))
        }
    }

    /// A file name for a version key (bundle@version(build)): letters, digits, dots, dashes and underscores only.
    static func fileName(_ versionKey: String) -> String {
        String(versionKey.map { $0.isLetter || $0.isNumber || ".-_".contains($0) ? $0 : "_" }.prefix(150)) + ".json"
    }

    func loadAliases() -> ArisApps.Aliases { lock.withLock { read("aliases.json", ArisApps.Aliases.self) ?? ArisApps.Aliases() } }
    func saveAliases(_ aliases: ArisApps.Aliases) { lock.withLock { write(aliases, "aliases.json") } }
    func loadBook() -> ArisApps.ChannelBook { lock.withLock { read("channels.json", ArisApps.ChannelBook.self) ?? ArisApps.ChannelBook() } }
    func saveBook(_ book: ArisApps.ChannelBook) { lock.withLock { write(book, "channels.json") } }
    func cachedCommands(_ versionKey: String) -> [ArisApps.Command]? {
        lock.withLock { read("commands/" + Self.fileName(versionKey), [ArisApps.Command].self) }
    }
    func cacheCommands(_ commands: [ArisApps.Command], for versionKey: String) {
        lock.withLock { write(commands, "commands/" + Self.fileName(versionKey)) }
    }
}
