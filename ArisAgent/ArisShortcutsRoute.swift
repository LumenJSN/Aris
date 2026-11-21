//
//  ArisShortcutsRoute.swift
//  aris-agent
//
//  The learned shortcuts (ArisShortcuts, aris/shortcuts.json) on the settings page: listed among 설정 › 기억 › 저장된
//  단계 with the saved desktop steps, each with its own 지우기, through POST /memory's existing ops, so the app shows
//  them with the rows it already has:
//    {"op": "savedSteps"}                     -> the saved steps' rows, then one row per learned shortcut (key with
//                                                `keyPrefix`, its commands worded in both languages, the apps)
//    {"op": "savedStepsDelete", "key": "…"}   -> a key with `keyPrefix` forgets that learned shortcut
//  A data wipe of memory removes the file too (ArisDataRoute). Foundation only (tested); the agent's own access is
//  ArisShortcutStore.access.
//

import Foundation

/// What the route may do with the learned shortcuts.
struct ArisShortcutsAccess {
    var all: () -> [String: ArisShortcuts.Learned]
    /// True when that key was there and is gone.
    var forget: (String) -> Bool
}

enum ArisShortcutsRoute {
    /// Marks a row's key as a learned shortcut's. ArisShortcuts.key never starts with a space (its words are joined
    /// by single spaces), so no saved-steps key can look like it.
    static let keyPrefix = " shortcut:"

    /// `savedSteps`: the saved steps' own answer for the same object (ArisSavedStepsRoute), nil for ops that aren't theirs.
    static func handle(_ object: [String: Any], access: ArisShortcutsAccess?, tools: String,
                       savedSteps: () -> (status: Int, body: Data, audit: String?)?) -> (status: Int, body: Data, audit: String?)? {
        switch object["op"] as? String {
        case "savedSteps":
            guard let access else { return savedSteps() }
            let saved = savedSteps()
            var body = saved.flatMap { (try? JSONSerialization.jsonObject(with: $0.body)) as? [String: Any] } ?? ["tampered": false]
            body["recipes"] = (body["recipes"] as? [[String: Any]] ?? []) + rows(access.all(), tools: tools)
            return (200, (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8), saved?.audit)
        case "savedStepsDelete":
            guard let key = object["key"] as? String, key.hasPrefix(keyPrefix) else { return savedSteps() }
            let learned = String(key.dropFirst(keyPrefix.count))
            guard !learned.isEmpty, learned.count <= 400 else { return (400, Data("{}".utf8), nil) }
            let removed = access?.forget(learned) ?? false
            return (200, (try? JSONSerialization.data(withJSONObject: ["removed": removed])) ?? Data("{}".utf8), removed ? "learned shortcut: deleted one" : nil)
        default:
            return savedSteps()
        }
    }

    /// One row per learned shortcut, newest first, in the saved steps' shape (ArisSavedStepsItem in the app).
    static func rows(_ shortcuts: [String: ArisShortcuts.Learned], tools: String) -> [[String: Any]] {
        shortcuts.sorted { $0.value.learned > $1.value.learned }.map { key, learned in
            let apps = learned.commands.compactMap { app(in: $0, tools: tools) }
            return ["key": keyPrefix + key, "request": key, "saved": learned.learned, "outside": false,
                    "steps": learned.commands.map { describe($0, tools: tools, english: false) },
                    "stepsEn": learned.commands.map { describe($0, tools: tools, english: true) },
                    "apps": Array(NSOrderedSet(array: apps)).compactMap { $0 as? String }.joined(separator: ", ")]
        }
    }

    /// The app a command acts on, when it names one.
    static func app(in command: String, tools: String) -> String? {
        if let name = capture(command, #"^osascript -e 'tell application "([^"]+)""#) { return name }
        if let name = capture(command, #"^open -a "([^"]+)"$"#) { return name }
        return capture(command, "^" + NSRegularExpression.escapedPattern(for: tools) + #" app "?([^"]+)"?$"#)
    }

    /// One command in a few words, for the row (never the shell text itself, except as the last resort).
    static func describe(_ command: String, tools: String, english: Bool) -> String {
        let t = "^" + NSRegularExpression.escapedPattern(for: tools)
        if let app = capture(command, #"^osascript -e 'tell application "([^"]+)""#),
           let verb = capture(command, #" to ([a-z ]+)'$"#) {
            let words: [String: (String, String)] = ["play": ("재생", "play"), "pause": ("일시정지", "pause"), "playpause": ("재생·일시정지", "play or pause"),
                                                     "next track": ("다음 곡", "next track"), "previous track": ("이전 곡", "previous track"),
                                                     "activate": ("열기", "open"), "quit": ("종료", "quit")]
            let word = words[verb].map { english ? $0.1 : $0.0 } ?? verb
            return "\(app): \(word)"
        }
        if let level = capture(command, #"^osascript -e 'set volume output volume ([0-9]+)'$"#) ?? capture(command, t + #" volume ([0-9]+)$"#) {
            return english ? "Volume \(level)" : "볼륨 \(level)"
        }
        if command.contains("with output muted") || command.hasSuffix(" volume mute") { return english ? "Mute" : "소리 끄기" }
        if command.contains("without output muted") || command.hasSuffix(" volume unmute") { return english ? "Unmute" : "소리 켜기" }
        if let step = capture(command, t + #" volume (up|down)$"#) { return english ? "Volume \(step)" : (step == "up" ? "볼륨 올리기" : "볼륨 내리기") }
        if let app = capture(command, #"^open -a "([^"]+)"$"#) ?? capture(command, t + #" app "?([^"]+)"?$"#) {
            return english ? "Open \(app)" : "\(app) 열기"
        }
        if let link = capture(command, #"^open "([^"]+)"$"#) ?? capture(command, t + #" link "([^"]+)"$"#) {
            let host = URL(string: link)?.host ?? link
            return english ? "Open link: \(host)" : "링크 열기: \(host)"
        }
        if let name = capture(command, #"^shortcuts run "([^"]+)"$"#) ?? capture(command, t + #" shortcut "?([^"]+)"?$"#) {
            return english ? "Run shortcut: \(name)" : "단축어 실행: \(name)"
        }
        if let action = capture(command, t + #" music (play|pause|next|previous)"#) {
            let words: [String: (String, String)] = ["play": ("음악 재생", "Play music"), "pause": ("음악 일시정지", "Pause music"),
                                                     "next": ("다음 곡", "Next track"), "previous": ("이전 곡", "Previous track")]
            return words[action].map { english ? $0.1 : $0.0 } ?? action
        }
        if let place = capture(command, t + #" window (left|right|full|center)"#) {
            let words: [String: (String, String)] = ["left": ("창 왼쪽 절반", "Window to the left half"), "right": ("창 오른쪽 절반", "Window to the right half"),
                                                     "full": ("창 전체 화면", "Window full screen"), "center": ("창 가운데", "Window to the center")]
            let app = capture(command, t + #" window [a-z]+ (.+)$"#).map { " (\($0))" } ?? ""
            return (words[place].map { english ? $0.1 : $0.0 } ?? place) + app
        }
        if command.range(of: t + " calendar$", options: .regularExpression) != nil { return english ? "Open the calendar" : "캘린더 열기" }
        return command.replacingOccurrences(of: tools, with: "aris-tools")
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
