//
//  ArisTerminal.swift
//  Aris (also built into aris-agent)
//
//  The terminal a Claude Code teammate opens in: the one the user uses, not only Terminal and iTerm2 ("terminal 말고도,
//  warp 등등 다른 터미널도 지원해줘야 되는 거 아님?"). Seven terminals, which one is picked with nothing set up, and for
//  each the real way to open a window that runs one command (each checked against the terminal's own documentation,
//  November 2026):
//  - Terminal, iTerm2: AppleScript types the line into a new window (ArisClaudeLaunch.script), as before.
//  - Ghostty, kitty, WezTerm, Alacritty: a new instance of the app is started with arguments (what
//    `open -na <App> --args …` does) that run a small launch script. Ghostty `-e`, kitty's trailing program,
//    `wezterm start --always-new-process --`, Alacritty `-e`.
//  - Warp has no AppleScript and its links run no command, but a Tab Config (a small TOML file in
//    ~/.warp/tab_configs) runs its commands when it is opened, and `warp://tab_config/<name>?new_window=true` opens
//    one. That link exists since the builds of late May 2026; an older Warp is passed over for the next terminal,
//    and the teammate's first line says so.
//  The prompt is in none of these: as before it sits in a private file the shell reads ("$(cat …)"). The launch
//  script and the Tab Config hold only the folder, the checked `claude` and that file's path.
//  Foundation only, so the choice and every script and argument list are tested.
//

import Foundation

enum ArisTerminal: String, CaseIterable, Equatable {
    case terminal, iTerm, ghostty, warp, kitty, wezterm, alacritty

    var bundleId: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iTerm: return "com.googlecode.iterm2"
        case .ghostty: return "com.mitchellh.ghostty"
        case .warp: return "dev.warp.Warp-Stable"
        case .kitty: return "net.kovidgoyal.kitty"
        case .wezterm: return "com.github.wez.wezterm"
        case .alacritty: return "org.alacritty"
        }
    }

    /// The app's own name, never translated.
    var title: String {
        switch self {
        case .terminal: return "Terminal"
        case .iTerm: return "iTerm2"
        case .ghostty: return "Ghostty"
        case .warp: return "Warp"
        case .kitty: return "kitty"
        case .wezterm: return "WezTerm"
        case .alacritty: return "Alacritty"
        }
    }

    init?(bundleId: String?) {
        guard let found = Self.allCases.first(where: { $0.bundleId.caseInsensitiveCompare(bundleId ?? "") == .orderedSame }) else { return nil }
        self = found
    }

    /// The setting's value for "pick for me".
    static let automatic = "auto"

    /// Which installed terminal is tried first when nothing says which one the user uses: someone who installed another
    /// terminal uses it, and Terminal is always there.
    static let installOrder: [ArisTerminal] = [.iTerm, .ghostty, .warp, .kitty, .wezterm, .alacritty, .terminal]

    /// A window opened by AppleScript (macOS asks once whether aris-agent may control the app).
    var scripted: ArisClaudeLaunch.Host? {
        switch self {
        case .terminal: return .terminal
        case .iTerm: return .iTerm
        default: return nil
        }
    }
}

/// What the app said about the user's terminal with the launch request: the one pinned in Settings and the one they last
/// ran Claude Code in. Either may be missing or unknown; both are only ever names from ArisTerminal's list.
struct ArisTerminalWish: Equatable {
    var pinned: String?
    var lastUsed: String?

    init(pinned: String? = nil, lastUsed: String? = nil) {
        self.pinned = pinned.flatMap { ArisTerminal(rawValue: $0)?.rawValue }
        self.lastUsed = lastUsed.flatMap { ArisTerminal(rawValue: $0)?.rawValue }
    }
}

/// Which terminal a teammate opens in.
enum ArisTerminalChoice {
    /// What is known when a teammate is about to open.
    struct Facts: Equatable {
        /// The terminal pinned in Settings › 팀원 › 터미널 (a raw value); nil or "auto": pick.
        var pinned: String?
        /// The terminal the user last ran Claude Code in themselves, as the hooks said (a raw value).
        var lastUsed: String?
        var installed: Set<ArisTerminal> = [.terminal]
        /// The running terminals, the one whose window is nearest the front first.
        var running: [ArisTerminal] = []
        /// The installed Warp can open a Tab Config from a link (ArisWarpLaunch.opensTabConfigs).
        var warpReady = false
    }

    struct Pick: Equatable {
        let terminal: ArisTerminal
        /// A terminal that came first but can't be handed a command (an older Warp): the first line says so.
        var passedOver: ArisTerminal?
    }

    /// The order they are tried in: the pinned one, the one the user last used for Claude Code, the running one nearest
    /// the front, then the installed ones in `installOrder`. Only installed terminals; Terminal is always among them.
    static func order(_ facts: Facts) -> [ArisTerminal] {
        let pinned = facts.pinned.flatMap(ArisTerminal.init(rawValue:)), lastUsed = facts.lastUsed.flatMap(ArisTerminal.init(rawValue:))
        let wanted = [pinned, lastUsed].compactMap { $0 } + facts.running + ArisTerminal.installOrder
        var seen = Set<ArisTerminal>()
        return wanted.filter { ($0 == .terminal || facts.installed.contains($0)) && seen.insert($0).inserted }
    }

    /// The first terminal in order that can run `command`. Warp is passed over when its build has no Tab Config link,
    /// or when the command holds what a Tab Config would read as a blank to fill in.
    static func pick(_ facts: Facts, command: String) -> Pick {
        var passedOver: ArisTerminal?
        for terminal in order(facts) {
            if terminal == .warp, !(facts.warpReady && ArisWarpLaunch.canRun(command)) {
                passedOver = passedOver ?? .warp
                continue
            }
            return Pick(terminal: terminal, passedOver: passedOver)
        }
        return Pick(terminal: .terminal, passedOver: passedOver)
    }
}

/// How one terminal is asked to open a window that runs the teammate's command.
enum ArisTerminalPlan: Equatable {
    /// AppleScript on osascript's stdin.
    case script(String)
    /// A new instance of the app with these arguments; `launchScript`: the text of the script they run, written to
    /// `scriptPath` first.
    case arguments([String], scriptPath: String, launchScript: String)
    /// A file written to `path` (Warp's Tab Config), then this link opened with the app.
    case link(String, path: String, contents: String)
}

enum ArisTerminalLaunch {
    /// The shell the launch script runs in when the account's own can't be read.
    static let fallbackShell = "/bin/zsh"

    /// The account's login shell when it is a plain absolute path; else zsh.
    static func shell(_ login: String?) -> String {
        guard let login, login.hasPrefix("/"), login.count <= 200,
              login.range(of: #"^[A-Za-z0-9/._+-]+$"#, options: .regularExpression) != nil, !login.contains("..") else { return fallbackShell }
        return login
    }

    static func scriptFileName(_ id: UUID) -> String { "cc-\(id.uuidString.lowercased()).sh" }

    /// The launch script: it deletes itself, runs the command as Terminal would have typed it, and leaves a shell
    /// open in the window when Claude Code ends, as Terminal does. Run by the account's shell as a login,
    /// interactive one (`<shell> -l -i <script>`), so the PATH is the one the user's own windows have.
    static func launchScript(command: String, shell: String, path: String) -> String {
        "rm -f -- \(ArisClaudeLaunch.shellQuoted(path))\n\(command)\nexec \(ArisClaudeLaunch.shellQuoted(shell)) -l -i\n"
    }

    /// The window that runs `command` in `terminal`. `shell`: ArisTerminalLaunch.shell's; `folder`: the private work
    /// folder (0700) the launch script goes in; `warpFolder`: Warp's own tab_configs folder; `id`: this launch's.
    static func plan(_ terminal: ArisTerminal, command: String, shell: String, folder: String, warpFolder: String, id: UUID) -> ArisTerminalPlan {
        if let host = terminal.scripted { return .script(ArisClaudeLaunch.script(command: command, host: host)) }
        if terminal == .warp {
            let name = ArisWarpLaunch.configName(id)
            return .link(ArisWarpLaunch.link(name), path: warpFolder + "/" + name + ".toml", contents: ArisWarpLaunch.tabConfig(command: command))
        }
        let path = folder + "/" + scriptFileName(id)
        let run = [shell, "-l", "-i", path]
        let arguments: [String]
        switch terminal {
        // -e runs its arguments as they are (no shell reads them again) in a window of this new instance, which
        // quits when the command ends; the windows Ghostty would restore stay out of it.
        case .ghostty: arguments = ["--window-save-state=never", "-e"] + run
        // kitty [options] [program-to-run ...]
        case .kitty: arguments = run
        // --always-new-process: the window belongs to the instance just started, so Aris knows whose it is.
        case .wezterm: arguments = ["start", "--always-new-process", "--"] + run
        // -e, --command <COMMAND>...: must be the last argument.
        case .alacritty: arguments = ["-e"] + run
        case .terminal, .iTerm, .warp: arguments = run
        }
        return .arguments(arguments, scriptPath: path, launchScript: launchScript(command: command, shell: shell, path: path))
    }
}

/// Warp: a Tab Config that runs the command, opened by its link.
enum ArisWarpLaunch {
    /// The first builds whose `warp://tab_config/<name>` link is sure to be there (the link was merged on 2026-05-15;
    /// Warp's version is its build date: "v0.2026.06.03.08.12.stable_02").
    static let firstBuild = (year: 2026, month: 6, day: 1)
    /// The names of the files Aris writes there, so only its own are ever removed.
    static let prefix = "aris_teammate_"
    /// How long a Tab Config stays before Aris removes it (Warp has read it long before).
    static let lifetime: TimeInterval = 30

    /// Whether a Warp of this version (its Info.plist's CFBundleShortVersionString) opens Tab Configs from a link.
    static func opensTabConfigs(version: String?) -> Bool {
        guard let version, let match = version.range(of: #"20\d\d\.\d\d\.\d\d"#, options: .regularExpression) else { return false }
        let parts = version[match].split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        return (parts[0], parts[1], parts[2]) >= (firstBuild.year, firstBuild.month, firstBuild.day)
    }

    /// A Tab Config fills `{{name}}` in from a form before it runs: a command holding one can't be handed over.
    static func canRun(_ command: String) -> Bool { !command.contains("{{") }

    static func configName(_ id: UUID) -> String { prefix + id.uuidString.lowercased().replacingOccurrences(of: "-", with: "") }

    static func link(_ name: String) -> String { "warp://tab_config/\(name)?new_window=true" }

    /// A TOML basic string: backslashes, quotes and control characters escaped.
    static func tomlString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// One terminal pane that runs the command when the tab opens. No `[params]`: nothing is asked before it runs.
    static func tabConfig(command: String) -> String {
        """
        name = "Aris · Claude Code"

        [[panes]]
        id = "main"
        type = "terminal"
        commands = [\(tomlString(command))]

        """
    }
}

/// The lines about the terminal: the teammate's first line when one was passed over, and the Settings row.
enum ArisTerminalWords {
    /// What the job's row says once the window is open in another terminal than the one that came first.
    static func passedOver(_ skipped: ArisTerminal, openedIn: ArisTerminal, english: Bool) -> String {
        english ? "Claude Code at work · this \(skipped.title) can't be handed a command, so it opened in \(openedIn.title)"
            : "Claude Code 작업 중 · 이 \(skipped.title)는 명령을 받아 주지 못해서 \(openedIn.title)에서 열었어요"
    }

    /// A terminal that isn't scripted couldn't be started.
    static func notOpened(_ terminal: ArisTerminal) -> String { "터미널을 열지 못했어요: \(terminal.title)" }
}
