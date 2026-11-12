//
//  TerminalRef.swift
//  Aris
//
//  Where a session's terminal lives, read from the terminal headers each hook sends
//  (installed by install-claude-hooks.py). The notch acts on these values (opens a
//  URL, scripts a terminal), so each one must match a strict shape or it is ignored.
//

import Foundation

enum TerminalRef: Equatable {
    /// Warp's own "focus this session" link: warp://session/<32 hex>.
    case warp(URL)
    /// iTerm2 session unique id (the UUID part of ITERM_SESSION_ID).
    case iterm(String)
    /// Just the host app (VS Code, Ghostty, Terminal, …).
    case app(String)

    /// TERM_PROGRAM values for hosts that don't export __CFBundleIdentifier.
    private static let programs = [
        "Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable", "ghostty": "com.mitchellh.ghostty",
        "vscode": "com.microsoft.VSCode", "WezTerm": "com.github.wez.wezterm",
    ]

    /// Most precise first: an exact tab, then the host app; nil when nothing usable was sent.
    init?(headers: [String: String]) {
        if let url = Self.warpURL(headers["x-warp-focus"]) {
            self = .warp(url)
        } else if let id = Self.itermId(headers["x-iterm-session"]) {
            self = .iterm(id)
        } else if let bundle = Self.bundleId(headers["x-bundle-id"]) ?? headers["x-term-program"].flatMap({ Self.programs[$0] }) {
            self = .app(bundle)
        } else {
            return nil
        }
    }

    private static func warpURL(_ value: String?) -> URL? {
        guard let value, value.range(of: "^warp://session/[0-9a-fA-F]{32}$", options: .regularExpression) != nil else { return nil }
        return URL(string: value)
    }

    private static func itermId(_ value: String?) -> String? {
        guard let id = value?.split(separator: ":").last.map(String.init), UUID(uuidString: id) != nil else { return nil }
        return id
    }

    private static func bundleId(_ value: String?) -> String? {
        guard let value, value.count <= 155,
              value.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil else { return nil }
        return value
    }
}
