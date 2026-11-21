//
//  ArisSessionHost.swift
//  aris-agent
//
//  Where one of the user's Claude Code sessions lives, from its own process (desktop-bg, phase B: "wherever their
//  sessions actually live"): which `claude` process is the session (Claude Code's own list of its live sessions,
//  `claude agents --json`: id → pid, exact), and from that process's terminal variables and the app it runs under,
//  the way in:
//  - tmux or screen when its tty is one of their panes (exact, no window touched);
//  - WezTerm's and kitty's own command line (exact, by pane or window id);
//  - iTerm2 by its session id (AppleScript writes into that session);
//  - Terminal by its tty; Warp by its focus link; an editor's terminal (VS Code, Cursor, Antigravity, Windsurf/Devin);
//    any other terminal app by a title mark read back from its window;
//  - the Claude app's Code sessions (no terminal: its own window, by the session's link);
//  - an editor's Claude Code panel, a background session, or an app with no terminal: refused, named.
//  Pure.
//

import Foundation

enum ArisSessionHost: Equatable {
    case tmux(socket: String, pane: String)
    case screen(session: String, window: String)
    case wezterm(pane: String, socket: String?)
    case kitty(socket: String, window: String)
    case iterm(session: String)
    case terminalApp
    case warp(focus: String?)
    case editor(bundle: String)
    case window(bundle: String)
    case claudeDesktop
    case editorPanel(bundle: String)
    case background
    case unsupported(app: String)

    /// The app as a person names it, for the card and the lines.
    var name: String {
        switch self {
        case .tmux: return "tmux"
        case .screen: return "screen"
        case .wezterm: return "WezTerm"
        case .kitty: return "kitty"
        case .iterm: return "iTerm2"
        case .terminalApp: return "Terminal"
        case .warp: return "Warp"
        case .editor(let bundle), .editorPanel(let bundle), .window(let bundle): return ArisSessionHost.appNames[bundle] ?? ArisSessionHost.fallbackName(bundle)
        case .claudeDesktop: return "Claude"
        case .background: return "Claude Code 백그라운드"
        case .unsupported(let app): return app
        }
    }

    static let appNames: [String: String] = [
        "com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm2", "dev.warp.Warp-Stable": "Warp", "dev.warp.Warp-Preview": "Warp",
        "com.mitchellh.ghostty": "Ghostty", "net.kovidgoyal.kitty": "kitty", "com.github.wez.wezterm": "WezTerm", "org.alacritty": "Alacritty",
        "io.alacritty": "Alacritty", "co.zeit.hyper": "Hyper", "org.tabby": "Tabby", "dev.zed.Zed": "Zed",
        "com.microsoft.VSCode": "VS Code", "com.microsoft.VSCodeInsiders": "VS Code Insiders", "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.google.antigravity": "Antigravity", "com.google.antigravity-ide": "Antigravity IDE", "com.exafunction.windsurf": "Devin",
        "com.anthropic.claudefordesktop": "Claude", "ai.opencode.desktop": "OpenCode", "com.apple.dt.Xcode": "Xcode",
    ]

    static func fallbackName(_ bundle: String) -> String {
        bundle.split(separator: ".").last.map(String.init) ?? bundle
    }

    /// The editors whose integrated terminal reports TERM_PROGRAM=vscode.
    static let editors: Set<String> = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.google.antigravity",
                                       "com.google.antigravity-ide", "com.exafunction.windsurf", "com.vscodium"]

    /// The way in for a session's process: `environment` its terminal variables, `tty` its terminal (nil: none),
    /// `hostBundle` the app it runs under (its first ordinary app among its parents), `background` Claude Code's own
    /// list says it is a background session.
    static func classify(environment env: [String: String], tty: String?, hostBundle: String?, hostName: String?, background: Bool) -> ArisSessionHost {
        if background { return .background }
        let bundle = env["__CFBundleIdentifier"].flatMap { $0.isEmpty ? nil : $0 } ?? hostBundle
        guard tty != nil else {
            switch env["CLAUDE_CODE_ENTRYPOINT"] {
            case "claude-desktop": return .claudeDesktop
            case "claude-vscode": return .editorPanel(bundle: bundle ?? "com.microsoft.VSCode")
            default:
                if bundle == "com.anthropic.claudefordesktop" { return .claudeDesktop }
                return .unsupported(app: bundle.map { appNames[$0] ?? fallbackName($0) } ?? hostName ?? "?")
            }
        }
        if let socket = tmuxSocket(env["TMUX"]), let pane = env["TMUX_PANE"], pane.range(of: #"^%[0-9]{1,6}$"#, options: .regularExpression) != nil {
            return .tmux(socket: socket, pane: pane)
        }
        if let session = env["STY"], session.range(of: #"^[0-9]{1,8}\.[A-Za-z0-9._-]{1,80}$"#, options: .regularExpression) != nil,
           let window = env["WINDOW"], window.range(of: #"^[0-9]{1,4}$"#, options: .regularExpression) != nil {
            return .screen(session: session, window: window)
        }
        return outer(environment: env, bundle: bundle)
    }

    /// The terminal app around a multiplexer (or none): what's left after tmux or screen.
    static func outer(environment env: [String: String], bundle: String?) -> ArisSessionHost {
        if let pane = env["WEZTERM_PANE"], pane.range(of: #"^[0-9]{1,8}$"#, options: .regularExpression) != nil {
            return .wezterm(pane: pane, socket: env["WEZTERM_UNIX_SOCKET"].flatMap { $0.hasPrefix("/") ? $0 : nil })
        }
        if let window = env["KITTY_WINDOW_ID"], window.range(of: #"^[0-9]{1,8}$"#, options: .regularExpression) != nil,
           let socket = env["KITTY_LISTEN_ON"], socket.hasPrefix("unix:") {
            return .kitty(socket: socket, window: window)
        }
        if let id = env["ITERM_SESSION_ID"]?.split(separator: ":").last.map(String.init), UUID(uuidString: id) != nil { return .iterm(session: id) }
        switch env["TERM_PROGRAM"] {
        case "Apple_Terminal": return .terminalApp
        case "WarpTerminal": return .warp(focus: env["WARP_FOCUS_URL"].flatMap(warpLink))
        case "vscode": return .editor(bundle: bundle.flatMap { editors.contains($0) ? $0 : nil } ?? bundle ?? "com.microsoft.VSCode")
        default: break
        }
        if env["WARP_FOCUS_URL"] != nil { return .warp(focus: env["WARP_FOCUS_URL"].flatMap(warpLink)) }
        if let bundle, editors.contains(bundle) { return .editor(bundle: bundle) }
        if bundle == "com.apple.Terminal" { return .terminalApp }
        if bundle == "com.googlecode.iterm2" { return .window(bundle: bundle!) }
        return bundle.map { .window(bundle: $0) } ?? .unsupported(app: "?")
    }

    /// TMUX is "<socket>,<server pid>,<session>": its socket path.
    static func tmuxSocket(_ value: String?) -> String? {
        guard let value, let socket = value.split(separator: ",").first.map(String.init), socket.hasPrefix("/"), !socket.contains("..") else { return nil }
        return socket
    }

    static func warpLink(_ value: String) -> String? {
        value.range(of: "^warp://session/[0-9a-fA-F]{32}$", options: .regularExpression) != nil ? value : nil
    }
}

/// Claude Code's own list of its live sessions (`claude agents --json`): the session id's process, and whether it is a
/// background one. Pure.
enum ArisSessionAgents {
    struct Entry: Equatable {
        let sessionId: String
        let pid: Int32
        let background: Bool
        let cwd: String
        /// When it started (seconds since 1970), its name (Claude Code's own, may be model-written) and its status
        /// ("busy", "idle", "waiting"): what the fleet takes from the list.
        var started: Double? = nil
        var name: String? = nil
        var status: String? = nil
    }

    static func parse(_ data: Data) -> [Entry]? {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        return list.compactMap { item in
            guard let id = item["sessionId"] as? String, !id.isEmpty, let pid = (item["pid"] as? NSNumber)?.int32Value, pid > 1 else { return nil }
            return Entry(sessionId: id, pid: pid, background: (item["kind"] as? String) == "background", cwd: item["cwd"] as? String ?? "",
                         started: (item["startedAt"] as? NSNumber).map { $0.doubleValue / 1_000 }, name: item["name"] as? String,
                         status: item["status"] as? String)
        }
    }

    /// The session's entry, only when exactly one has its id.
    static func entry(for id: String, in entries: [Entry]) -> Entry? {
        let found = entries.filter { $0.sessionId == id }
        return found.count == 1 ? found[0] : nil
    }
}
