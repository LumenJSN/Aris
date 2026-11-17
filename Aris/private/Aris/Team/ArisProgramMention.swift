//
//  ArisProgramMention.swift
//  Aris
//
//  "클로드 앱으로 해", "ChatGPT 열어서 물어봐", "커서로 열어": an app on this Mac named as the one to do or use something.
//  Read here from the user's words and the apps installed in the usual folders (ArisRouter.installedApps), by their names
//  and the names said for them; the turn's context then says which apps the words name, so the AI works them through
//  its `app` and `desktop` tools and never takes the name for a teammate or a person. The words decide nothing here:
//  the line is data for the AI. Pure.
//

import Foundation

enum ArisProgramMention {
    /// Names said for apps that aren't in ArisIntent.appAliases (the AI apps first: their names are brains' names too).
    static let nicknames: [String: String] = [
        "클로드": "Claude", "claude": "Claude", "챗지피티": "ChatGPT", "챗 지피티": "ChatGPT", "챗gpt": "ChatGPT", "챗 gpt": "ChatGPT",
        "chatgpt": "ChatGPT", "chat gpt": "ChatGPT", "커서": "Cursor", "코덱스": "Codex", "안티그래비티": "Antigravity", "제미나이": "Gemini",
        "퍼플렉시티": "Perplexity", "윈드서프": "Windsurf", "옵시디언": "Obsidian", "아이텀": "iTerm", "깃허브 데스크톱": "GitHub Desktop",
        "줌": "zoom.us", "zoom": "zoom.us", "아크": "Arc", "파이어폭스": "Firefox",
    ]

    /// Names that are everyday words or Aris's own (its 설정): never read as an app here.
    private static let skipped: Set<String> = ["설정", "settings", "word", "음악", "사진", "지도", "메모", "메일", "메시지", "줌", "아크"]

    /// After the name: the app itself, or opening it ("앱", "열어서", "을 켜").
    private static let after = #"^\s*(?:앱|어플|애플리케이션|데스크톱|app\b|application\b|desktop\b|(?:을|를)?\s*(?:열|켜|띄|실행)|(?:으로|로|에서)\s*(?:열|켜|띄|실행|해|하|써|물어|작업|돌려|만들|검색|찾|들어가))"#
    /// Before the name, in English ("open ChatGPT", "in Cursor", "use the Claude app").
    private static let lead = #"(?i)\b(?:open|launch|start|use|in|with|using|via)\s+(?:the\s+)?$"#

    /// How names compare: composed, lowercased, without spaces.
    static func key(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace }
    }

    /// The installed apps `text` names as the one to do or use something, by their installed names, in the order
    /// said; and the names said for apps Aris knows that aren't installed here.
    static func named(in text: String, installed: [String]) -> (apps: [String], missing: [String]) {
        let words = text.precomposedStringWithCanonicalMapping
        let byKey = Dictionary(installed.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
        var said: [(name: String, app: String?)] = installed.filter { $0.count >= 2 }.map { ($0, $0) }
        for (nickname, app) in nicknames.merging(ArisIntent.appAliases, uniquingKeysWith: { first, _ in first }) {
            said.append((nickname, byKey[key(app)]))
        }
        var apps: [(at: String.Index, app: String)] = [], missing: [String] = []
        // The longest names first, so "Claude Code" isn't read as "Claude".
        for (name, app) in said.sorted(by: { $0.name.count > $1.name.count }) where !skipped.contains(key(name)) {
            guard let at = mention(of: name, in: words) else { continue }
            if let app {
                if !apps.contains(where: { $0.app == app }) { apps.append((at, app)) }
            } else if let known = nicknames[name] ?? ArisIntent.appAliases[name], !missing.contains(known) {
                missing.append(known)
            }
        }
        return (apps.sorted { $0.at < $1.at }.map(\.app), missing)
    }

    /// Where `name` is said as an app to open or use; nil when it isn't.
    private static func mention(of name: String, in words: String) -> String.Index? {
        let latin = name.unicodeScalars.allSatisfy(\.isASCII)
        let escaped = name.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s*"#)
        let pattern = (latin ? #"(?<![A-Za-z0-9])"# : "") + escaped + (latin ? #"(?![A-Za-z0-9])"# : "")
        var from = words.startIndex
        while let found = words.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: from..<words.endIndex) {
            if words[found.upperBound...].range(of: after, options: [.regularExpression, .caseInsensitive]) != nil
                || words[..<found.lowerBound].range(of: lead, options: .regularExpression) != nil {
                return found.lowerBound
            }
            from = found.upperBound
        }
        return nil
    }

    /// The context's line for them; nil when the words name none.
    static func contextLine(apps: [String], missing: [String]) -> String? {
        var parts: [String] = []
        if !apps.isEmpty {
            parts.append("apps the request names, installed on this Mac (the user means the app: open or use it with `app` and `desktop`; never a teammate or a person): " + apps.joined(separator: ", "))
        }
        if !missing.isEmpty {
            parts.append("apps the request names that aren't installed on this Mac: " + missing.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}
