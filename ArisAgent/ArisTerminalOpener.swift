//
//  ArisTerminalOpener.swift
//  aris-agent
//
//  Opens the teammate's window in the terminal ArisTerminalChoice picks (ArisTerminal.swift says how each one is
//  asked). What is found out here: which terminals are installed and running, whose window is nearest the front,
//  whether this Warp opens Tab Configs from a link, and the account's shell. A terminal that isn't scripted gets a
//  small launch script in the private work folder (0700; the script 0700, a new file that can't be a link) or, for
//  Warp, a Tab Config in Warp's own folder (0600, a new file that can't be a link, removed half a minute later).
//  Neither holds the prompt: only the folder, the checked `claude` and the prompt file's path.
//

import AppKit
import Foundation

enum ArisTerminalOpener {
    /// How long a terminal started with arguments may take to come up.
    static let openTimeout: TimeInterval = 30

    struct Opened {
        let pid: Int32
        let windowNumber: Int?
        let terminal: ArisTerminal
        let passedOver: ArisTerminal?
    }

    static func appURL(_ terminal: ArisTerminal) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleId)
    }

    /// The running terminals: those with a window on screen first, front to back, then the rest.
    static func running() -> [ArisTerminal] {
        let apps = NSWorkspace.shared.runningApplications
        let byPid = Dictionary(apps.compactMap { app in ArisTerminal(bundleId: app.bundleIdentifier).map { (app.processIdentifier, $0) } }) { first, _ in first }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let front = windows.compactMap { entry -> ArisTerminal? in
            guard entry[kCGWindowLayer as String] as? Int == 0, let pid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
            return byPid[Int32(pid)]
        }
        var seen = Set<ArisTerminal>()
        return (front + byPid.values.sorted { $0.rawValue < $1.rawValue }).filter { seen.insert($0).inserted }
    }

    static func facts(_ wish: ArisTerminalWish) -> ArisTerminalChoice.Facts {
        let installed = Set(ArisTerminal.allCases.filter { appURL($0) != nil })
        let warp = appURL(.warp).flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
        return ArisTerminalChoice.Facts(pinned: wish.pinned, lastUsed: wish.lastUsed, installed: installed, running: running(),
                                        warpReady: ArisWarpLaunch.opensTabConfigs(version: warp))
    }

    static var loginShell: String {
        ArisTerminalLaunch.shell(getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) })
    }

    /// Opens the window running `command`; which terminal it is in, and one that was passed over for it.
    static func open(command: String, wish: ArisTerminalWish, home: String) throws -> Opened {
        let pick = ArisTerminalChoice.pick(facts(wish), command: command)
        let folder = ArisTeammateLauncher.launchFolder(home: home)
        let warpFolder = URL(fileURLWithPath: home).appendingPathComponent(".warp/tab_configs")
        let plan = ArisTerminalLaunch.plan(pick.terminal, command: command, shell: loginShell, folder: folder.path, warpFolder: warpFolder.path, id: UUID())
        // The window is the one that was not there before: the terminal's front window is the user's own while the new one opens.
        let before = Set(NSRunningApplication.runningApplications(withBundleIdentifier: pick.terminal.bundleId).first.map { ArisWindowLocator.windows(pid: $0.processIdentifier) } ?? [])
        let pid: Int32
        switch plan {
        case .script(let script):
            try ArisTeammateLauncher.runScript(script)
            guard let found = NSRunningApplication.runningApplications(withBundleIdentifier: pick.terminal.bundleId).first?.processIdentifier else {
                throw ArisTeammateLaunchError(message: ArisTeammateLauncher.terminalNotFound)
            }
            pid = found
        case .arguments(let arguments, let scriptPath, let launchScript):
            guard ArisPrivateFile.prepareFolder(folder) else { throw ArisTeammateLaunchError(message: "작업 폴더를 쓸 수 없어요.") }
            try write(launchScript, to: scriptPath, mode: 0o700)
            do {
                pid = try start(pick.terminal, arguments: arguments)
            } catch {
                ArisTeammateLauncher.remove(URL(fileURLWithPath: scriptPath))
                throw error
            }
        case .link(let link, let path, let contents):
            pid = try openWarp(link: link, path: path, contents: contents, folder: warpFolder)
        }
        // A terminal just started takes a moment to show its window.
        for _ in 0..<(pick.terminal.scripted == nil ? 30 : 10) {
            if let window = ArisQuietLaunch.newWindow(before: before, after: ArisWindowLocator.windows(pid: pid)) {
                return Opened(pid: pid, windowNumber: window, terminal: pick.terminal, passedOver: pick.passedOver)
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return Opened(pid: pid, windowNumber: nil, terminal: pick.terminal, passedOver: pick.passedOver)
    }

    /// A new file with `text`: never over a file or a link already there.
    static func write(_ text: String, to path: String, mode: mode_t) throws {
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(.terminal) + " (\(String(cString: strerror(errno))))") }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } catch {
            unlink(path)
            throw ArisTeammateLaunchError(message: "터미널을 열지 못했어요: \(error.localizedDescription)")
        }
    }

    /// A new instance of the terminal with `arguments` (what `open -na <App> --args …` does); its pid.
    /// `activates`: false for a teammate's window, which must not take the keyboard (ArisQuietOpener).
    static func start(_ terminal: ArisTerminal, arguments: [String], activates: Bool = true) throws -> Int32 {
        guard let app = appURL(terminal) else { throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(terminal)) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.createsNewApplicationInstance = true
        configuration.activates = activates
        return try wait(terminal) { done in NSWorkspace.shared.openApplication(at: app, configuration: configuration, completionHandler: done) }
    }

    /// Writes the Tab Config and opens its link with Warp; Warp's pid.
    static func openWarp(link: String, path: String, contents: String, folder: URL, activates: Bool = true) throws -> Int32 {
        // Warp's own folder must be a plain folder of the user's; tab_configs is made when Warp hasn't yet.
        guard let app = appURL(.warp), let url = URL(string: link), ArisPrivateFile.isRealFolder(folder.deletingLastPathComponent()) else {
            throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(.warp))
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        guard ArisPrivateFile.isRealFolder(folder) else { throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(.warp)) }
        sweepWarp(folder, olderThan: ArisWarpLaunch.lifetime)
        try write(contents, to: path, mode: 0o600)
        let file = URL(fileURLWithPath: path)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + ArisWarpLaunch.lifetime) { ArisTeammateLauncher.remove(file) }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = activates
            return try wait(.warp) { done in NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration, completionHandler: done) }
        } catch {
            ArisTeammateLauncher.remove(file)
            throw error
        }
    }

    /// Removes Aris's own Tab Configs left from earlier launches (a regular file only, never through a link).
    static func sweepWarp(_ folder: URL, olderThan age: TimeInterval, now: Date = Date()) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(ArisWarpLaunch.prefix) && name.hasSuffix(".toml") {
            let file = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(file.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { continue }
            if now.timeIntervalSince1970 - Double(info.st_mtimespec.tv_sec) > age { unlink(file.path) }
        }
    }

    static func wait(_ terminal: ArisTerminal, _ open: (@escaping (NSRunningApplication?, Error?) -> Void) -> Void) throws -> Int32 {
        let done = DispatchSemaphore(value: 0)
        var result: Result<Int32, Error> = .failure(ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(terminal)))
        open { app, error in
            if let app { result = .success(app.processIdentifier) } else if let error {
                result = .failure(ArisTeammateLaunchError(message: "터미널을 열지 못했어요: \(error.localizedDescription.prefix(150))"))
            }
            done.signal()
        }
        guard done.wait(timeout: .now() + openTimeout) == .success else { throw ArisTeammateLaunchError(message: ArisTerminalWords.notOpened(terminal)) }
        return try result.get()
    }
}
