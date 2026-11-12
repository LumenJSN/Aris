//
//  TerminalFocus.swift
//  Aris
//
//  "Go to the terminal": the session's exact tab when its terminal says where it is
//  (Warp's focus link, iTerm2's session id), else its host app, else any running terminal.
//

import AppKit

enum TerminalFocus {
    private static let bundleIds = [
        "com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty", "com.github.wez.wezterm", "com.apple.Terminal",
    ]

    /// Brings the session's own terminal forward; falls back to `focus(cwd:)`.
    static func focus(_ session: ClaudeSession?, cwd: String) {
        switch session?.terminal {
        case .warp(let url)?:
            NSWorkspace.shared.open(url)
        case .iterm(let id)?:
            // Out of process and off the main thread (QA BUG-37): the tab is selected when osascript says so.
            Task { @MainActor in
                if await !selectITermSession(id) { _ = activate("com.googlecode.iterm2") || fallback(cwd) }
            }
        case .app(let bundleId)?:
            _ = activate(bundleId) || fallback(cwd)
        case nil:
            focus(cwd: cwd)
        }
    }

    /// Activates the first running terminal app; falls back to opening `cwd` in Terminal.
    static func focus(cwd: String) {
        let running = NSWorkspace.shared.runningApplications
        if let app = bundleIds.lazy.compactMap({ id in running.first { $0.bundleIdentifier == id } }).first {
            app.activate()
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func fallback(_ cwd: String) -> Bool {
        focus(cwd: cwd)
        return true
    }

    private static func activate(_ bundleId: String) -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else { return false }
        return app.activate()
    }

    /// `id` is a validated UUID (TerminalRef), so it is safe to put in the script.
    private static func selectITermSession(_ id: String) async -> Bool {
        let source = """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if unique id of s is "\(id)" then
                            select w
                            tell t to select
                            tell s to select
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
        do {
            return try await ArisAppleScript.run(source, timeout: 5) == "true"
        } catch {
            NSLog("[Claude] iTerm focus failed: %@", error.localizedDescription)
            return false
        }
    }
}
