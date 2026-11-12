//
//  ArisTerminalSetting.swift
//  Aris
//
//  The app's side of a teammate's terminal (ArisTerminal): which one the user last ran Claude Code in themselves, read from
//  the terminal each hook names (TerminalRef), and the one row in Settings › 팀원, "터미널": 자동, or one of the
//  terminals installed on this Mac for someone who wants to pin it. Nothing needs setting: 자동 opens the terminal he
//  last used for Claude Code, else the running one nearest the front, else an installed one. Foundation only (tested).
//

import Foundation

enum ArisTerminalMemory {
    /// The terminal a hook's session runs in, when it is one a teammate can open in (an editor's own terminal isn't).
    static func terminal(of ref: TerminalRef?) -> ArisTerminal? {
        switch ref {
        case .warp?: return .warp
        case .iterm?: return .iTerm
        case .app(let bundle)?: return ArisTerminal(bundleId: bundle)
        case nil: return nil
        }
    }

    /// The terminal to remember from one hook event: Claude Code's own, in a session the user started themselves, at a moment
    /// that is his doing (he sent a prompt) or the session's start. `teammate`: the session is one Aris opened.
    static func used(event: String, agent: String, terminal: TerminalRef?, teammate: Bool) -> ArisTerminal? {
        guard agent == "claude", !teammate, event == "UserPromptSubmit" else { return nil }
        return self.terminal(of: terminal)
    }

    /// The pinned terminal as the agent is told it; nil for 자동 and for anything that isn't a terminal's name.
    static func pinned(_ setting: String) -> String? { ArisTerminal(rawValue: setting)?.rawValue }
}

enum ArisTerminalSetting {
    static let id = "team.terminal"
    static let title = "터미널"
    static let desc = "Claude Code 팀원이 열릴 터미널이에요. 자동이면 Claude Code를 마지막으로 쓴 터미널에서, 없으면 켜져 있는 터미널에서 열어요."
    static let automatic = "자동"
    static let keywords = "터미널, iTerm, Ghostty, Warp, kitty, WezTerm, Alacritty, Claude Code, 팀원 창, terminal"

    /// The row: 자동, then the installed terminals in ArisTerminal's order. A pinned terminal that is no longer
    /// installed shows as 자동 (and opens as 자동 does).
    static func row(pinned: String, installed: [ArisTerminal]) -> ArisSettingItem {
        let listed = ArisTerminal.allCases.filter { $0 == .terminal || installed.contains($0) }
        let options = [ArisSettingOption(id: ArisTerminal.automatic, title: automatic)] + listed.map { ArisSettingOption(id: $0.rawValue, title: $0.title) }
        let selected = listed.contains { $0.rawValue == pinned } ? pinned : ArisTerminal.automatic
        return ArisSettingItem(id: id, icon: .symbol("terminal"), title: title, desc: desc, control: .menu(.teammateTerminal, options, selected: selected))
    }

    static func section(pinned: String, installed: [ArisTerminal]) -> ArisSettingSection {
        ArisSettingSection(id: "team.claude", heading: "Claude Code", rows: [row(pinned: pinned, installed: installed)])
    }

    static let entry = ArisSettingsEntry(id: id, page: .team, title: title, keywords: keywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })

    /// The row's English, by its Korean (ArisSettingsCopyMore). The terminals' names are names.
    static let english = [title: "Terminal",
                          desc: "The terminal a Claude Code teammate opens in. Automatic opens the one you last used Claude Code in, else one that is running."]
}
