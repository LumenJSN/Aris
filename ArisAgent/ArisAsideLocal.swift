//
//  ArisAsideLocal.swift
//  aris-agent
//
//  Aside is the user's browser agent: it sees websites and nothing on the Mac. A brief about an app or a session on
//  this Mac is refused before any card (the owner, 2026-11-15: "Warp 터미널의 데빈 세션 2개가 뭔 내용인지, 뭔 답변
//  보냈는지 알려줘" was handed to Aside after a look at Warp was refused, and came back "못 끝냈어요"). What counts as
//  local: a Mac-only app by name (Warp, iTerm, Finder, Xcode…), a coding agent's session in a terminal (Claude Code,
//  Codex, Devin, Gemini CLI: "세션" with its name or a terminal's), or an app installed here named as the app ("Notion
//  앱", "the Slack app": many are websites too, so the name alone isn't enough). A brief that names a site (an address,
//  "웹사이트", "website", "browser"…) is a website's work and goes on as before. Pure.
//

import Foundation

enum ArisAsideLocal {
    /// Apps that exist only on the Mac, as people say and recognition writes them.
    private static let macOnly = #"(?i)(?<![a-z])(warp|iterm2?|ghostty|wezterm|kitty|finder|xcode|terminal\.app|apple terminal|textedit|preview\.app)(?![a-z])|워프|아이텀|파인더|엑스코드|맥\s*터미널|터미널\s*(앱|창|탭)"#
    /// A coding agent named with a session, the CLI, or a terminal ("데빈 세션", "Claude Code session", "codex cli").
    private static let agents = #"(?i)claude\s*code|클로드\s*코드|클코|(?<![a-z])claude(?![a-z])|클로드|(?<![a-z])codex(?![a-z])|코덱스|(?<![a-z])devin(?![a-z])|데빈|(?<![a-z])gemini\s*cli(?![a-z])|제미나이\s*cli"#
    private static let sessionWords = #"(?i)(?<![a-z])(sessions?|cli|terminal|tui)(?![a-z])|세션|터미널"#
    /// Words that say the work is on a website.
    private static let webWords = #"(?i)https?://|www\.|(?<![a-z0-9-])[a-z0-9-]+\.(com|ai|io|dev|net|org|co|kr)(?![a-z])|웹사이트|웹\s*사이트|사이트|웹에서|웹\s*앱|\bwebsite\b|\bweb\s*app\b|\bsites?\b|\bbrowser\b|브라우저|\bonline\b|온라인|로그인해서|\bdashboard\b|대시보드"#
    /// Words that say "the app" (with an installed app's name: the Mac app is meant).
    private static let appWords = #"(?i)\bapp\b|\bdesktop app\b|\bwindow\b|앱|어플|창에|창을|창의|\bon (my|this) mac\b|맥에|설치된"#
    private static func has(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    /// Whether `brief` is about an app or a session on this Mac. `installed`: the names of the apps installed here.
    static func isLocal(_ brief: String, installed: [String] = []) -> Bool {
        let text = brief.precomposedStringWithCanonicalMapping
        guard !has(webWords, text) else { return false }
        if has(macOnly, text) { return true }
        if has(agents, text), has(sessionWords, text) { return true }
        let lowered = text.lowercased()
        for name in installed {
            let app = name.lowercased().trimmingCharacters(in: .whitespaces)
            guard app.count >= 4, lowered.range(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: app) + "(?![\\p{L}\\p{N}])",
                                                options: .regularExpression) != nil else { continue }
            if has(appWords, text) { return true }
        }
        return false
    }

    /// What the brain reads: refused, and the right way.
    static let line = "Refused: Aside works only on websites, and this is about an app or a session on this Mac, which Aside can't see. "
        + "Use the right way instead: a Claude Code session's state or last reply is in the context's \"claude code sessions\" lines and a prompt "
        + "goes to it with the session tool (`session send`); Devin's sessions are read with `devin sessions`; another app's window with a look at "
        + "the screen (`desktop see`) where Aris allows it. If none of these can do it, say plainly in one line that you can't, never that Aside will."

    /// The names of the apps installed in /Applications and ~/Applications (top level and one folder down).
    static func installedApps(home: String) -> [String] {
        let folders = ["/Applications", "/System/Applications", home + "/Applications"]
        var names: [String] = []
        let fm = FileManager.default
        for folder in folders {
            for item in (try? fm.contentsOfDirectory(atPath: folder)) ?? [] {
                if item.hasSuffix(".app") { names.append(String(item.dropLast(4))); continue }
                guard !item.hasPrefix("."), let inner = try? fm.contentsOfDirectory(atPath: folder + "/" + item) else { continue }
                names += inner.filter { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
            }
        }
        return names
    }
}
