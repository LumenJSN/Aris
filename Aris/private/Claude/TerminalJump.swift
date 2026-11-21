//
//  TerminalJump.swift
//  Aris
//
//  "Go to the terminal", decided: what to try for a session, most exact first (its own tab by Warp's focus link or
//  iTerm2's session id; its app; any terminal that runs; its folder in Terminal), and the one line said when the click
//  landed short of the session's own tab (the user's report 2026-11-19: Open terminal on a session in plan mode did
//  nothing he could see). TerminalFocus carries it out. Foundation only (tested).
//

import Foundation

enum TerminalJump {
    enum Step: Equatable {
        /// The session's own tab, by Warp's focus link (`bundle`: the Warp build that runs).
        case warp(URL, bundle: String)
        /// The session's own tab, by iTerm2's session id (an Apple Event to iTerm2).
        case iterm(String)
        /// The app the session runs in, brought forward.
        case app(String)
        /// Another terminal that runs: the session's own isn't known, or isn't running.
        case otherTerminal(String)
        /// The session's folder in a new Terminal window.
        case folder(String)

        /// The app this step brings forward (nil: a folder opened in Terminal).
        var bundle: String? {
            switch self {
            case .warp(_, let bundle): return bundle
            case .iterm: return TerminalRef.itermBundle
            case .app(let bundle), .otherTerminal(let bundle): return bundle
            case .folder: return nil
            }
        }
    }

    static let terminalApp = "com.apple.Terminal"
    /// Terminals tried when the session's own isn't known, in this order.
    static let terminals = ["com.mitchellh.ghostty", TerminalRef.itermBundle, "dev.warp.Warp-Stable", "dev.warp.Warp-Preview",
                            "net.kovidgoyal.kitty", "com.github.wez.wezterm", terminalApp]

    /// What to try, in order, for a session whose terminal is `ref`, with the apps that run now (bundle ids) and whether
    /// its folder `cwd` exists. A tab or app whose app isn't running is skipped: that session's terminal is gone.
    static func steps(for ref: TerminalRef?, running: Set<String>, cwd: String, folderExists: Bool) -> [Step] {
        var own: [Step] = []
        switch ref {
        case .warp(let url)?:
            if let warp = running.sorted().first(where: { $0.hasPrefix(TerminalRef.warpPrefix) }) {
                own = [.warp(url, bundle: warp), .app(warp)]
            }
        case .iterm(let id)?:
            if running.contains(TerminalRef.itermBundle) { own = [.iterm(id), .app(TerminalRef.itermBundle)] }
        case .app(let bundle)?:
            if running.contains(bundle) { own = [.app(bundle)] }
        case nil:
            break
        }
        let others = terminals.filter { running.contains($0) && !own.contains(.app($0)) }.prefix(1).map(Step.otherTerminal)
        let folder: [Step] = folderExists ? [.folder(cwd)] : []
        return own + others + folder
    }

    /// The step reached its tab: no line is said.
    static func isExact(_ step: Step) -> Bool {
        switch step {
        case .warp, .iterm: return true
        case .app, .otherTerminal, .folder: return false
        }
    }

    /// What is said after the click when it didn't reach the session's own tab (nil when it did). `reached`: the step
    /// that worked (nil: none did); `refused`: macOS refused Aris the Apple Event a tab needed (Automation is off).
    /// `name` gives an app's name.
    static func note(reached: Step?, wanted: TerminalRef?, refused: Bool = false, english: Bool, name: (String) -> String) -> String? {
        switch reached {
        case nil:
            return ArisUIWords.text("세션의 터미널을 찾지 못했어요.", "Couldn't find the session's terminal.", english: english)
        case let step? where isExact(step):
            return nil
        case .app(let bundle)?:
            let app = name(bundle)
            if refused {
                return ArisUIWords.text("\(app) 창만 앞으로 가져왔어요. 탭까지 가려면 설정 › 개인정보 보호 › 자동화에서 Aris의 \(app) 항목을 켜 주세요.",
                                        "Brought \(app) forward. To go to the tab, turn on \(app) for Aris in Privacy › Automation.", english: english)
            }
            switch wanted {
            case .warp?, .iterm?:
                return ArisUIWords.text("\(app) 창만 앞으로 가져왔어요. 세션의 탭은 찾지 못했어요.",
                                        "Brought \(app) forward, but couldn't find the session's tab.", english: english)
            default:
                return ArisUIWords.text("\(app) 창을 앞으로 가져왔어요. 이 터미널은 세션의 탭을 알려 주지 않아서 탭까지는 못 가요.",
                                        "Brought \(app) forward. \(app) doesn't say which tab a session is in.", english: english)
            }
        case .otherTerminal(let bundle)?:
            let app = name(bundle)
            return wanted == nil
                ? ArisUIWords.text("이 세션은 어느 터미널인지 알려 주지 않아서 \(app) 창을 앞으로 가져왔어요.",
                                   "This session didn't say which terminal it's in, so \(app) came forward.", english: english)
                : ArisUIWords.text("세션의 터미널이 실행 중이 아니라서 \(app) 창을 앞으로 가져왔어요.",
                                   "The session's terminal isn't running, so \(app) came forward.", english: english)
        case .folder?:
            return ArisUIWords.text("세션의 터미널을 찾지 못해서 그 폴더를 터미널 새 창에서 열었어요.",
                                    "Couldn't find the session's terminal, so its folder opened in a new Terminal window.", english: english)
        default:
            return nil
        }
    }

    /// Names for the terminals Aris knows (others: the app's own name, or its bundle id's last part).
    static func knownName(_ bundle: String) -> String? {
        switch bundle {
        case terminalApp: return "Terminal"
        case TerminalRef.itermBundle: return "iTerm"
        case "com.mitchellh.ghostty": return "Ghostty"
        case "net.kovidgoyal.kitty": return "kitty"
        case "com.github.wez.wezterm": return "WezTerm"
        case "com.microsoft.VSCode": return "VS Code"
        case "com.todesktop.230313mzl4w4u92": return "Cursor"
        default: return bundle.hasPrefix(TerminalRef.warpPrefix) ? "Warp" : nil
        }
    }
}
