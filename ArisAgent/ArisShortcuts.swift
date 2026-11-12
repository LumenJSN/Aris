//
//  ArisShortcuts.swift
//  aris-agent
//
//  Learned shortcuts (the Atticus idea): when the AI handles a request with
//  nothing but simple, repeatable actions (next track, set the volume, open an
//  app, run a Shortcut, place a window), those commands are saved under the
//  request. Next time the same words run them directly: no AI, no wait.
//  Anything that reads, searches, remembers or failed is never saved, and only
//  commands of a few exact shapes are ever replayed.
//

import Foundation

enum ArisShortcuts {
    struct Learned: Codable, Equatable {
        let commands: [String]
        let reply: String
        let learned: String
    }

    /// Shortcuts kept (oldest go first).
    static let limit = 200

    /// The request, ignoring Aris's name, punctuation, spacing, case and "좀", with spoken numbers as digits.
    static func key(for request: String) -> String {
        var text = ArisNumbers.normalize(request.lowercased())
        text = text.replacingOccurrences(of: "[.,!?。]", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "^\\s*(아리스|aris)\\b", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(^|\\s)좀(?=\\s|$)", with: " ", options: .regularExpression)
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isReplayable(_ command: String, tools: String) -> Bool {
        let shapes = [
            #"^osascript -e 'tell application "[^"'$`\\]+" to (play|pause|playpause|next track|previous track|activate|quit)'$"#,
            #"^osascript -e 'set volume output volume [0-9]{1,3}'$"#,
            #"^osascript -e 'set volume (with|without) output muted'$"#,
            #"^open -a "[^"$`\\]+"$"#,
            #"^open "https?://[^"\s$`\\]+"$"#,
            #"^shortcuts run "[^"$`\\]+"$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + #" window (left|right|full|center)( [A-Za-z0-9 ._-]+)?$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + #" music (play|pause|next|previous)( spotify| music)?$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + #" volume ([0-9]{1,3}|up|down|mute|unmute)$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + #" (app|shortcut) ("[^"$`\\]+"|[A-Za-z0-9 ._-]+)$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + #" link "https?://[^"\s$`\\]+"$"#,
            "^" + NSRegularExpression.escapedPattern(for: tools) + " calendar$",
        ]
        return shapes.contains { command.range(of: $0, options: .regularExpression) != nil }
    }

    /// A question, not a request (its key has no "?" left): "노션 캘린더 접근할 수 있어" was once learned as opening the
    /// calendar, and then answered that way every time. Never saved or replayed.
    static func isQuestion(_ key: String) -> Bool {
        let korean = ["수 있어", "수 있나", "수 있니", "수 있을까", "수 있냐", "뭐", "무엇", "어떻게", "왜", "언제", "누구", "어디", "몇 ", "인가", "일까"]
        if korean.contains(where: key.contains) { return true }
        return key.range(of: #"^(what|how|why|when|who|where|which|do you|are you|is there|is it|does)\b"#, options: .regularExpression) != nil
    }

    /// Worth saving: at least one action, every one replayable, nothing else used, it worked, and no outside text came
    /// into the turn (a shortcut learned from planted words would replay them).
    static func learnable(commands: [String], usedOtherTools: Bool, reply: String, tools: String, tainted: Bool) -> Bool {
        let failed = ["못 ", "못했", "실패", "없어요", "수 없", "않았", "안 돼", "couldn't", "can't", "cannot", "failed", "error", "not found"]
        return !tainted && !commands.isEmpty && !usedOtherTools
            && commands.allSatisfy { isReplayable($0, tools: tools) }
            && !failed.contains { reply.localizedCaseInsensitiveContains($0) }
    }

    /// The saved shortcuts with `learned` under `key`, oldest dropped past the limit.
    static func saving(_ learned: Learned, as key: String, in shortcuts: [String: Learned]) -> [String: Learned] {
        var updated = shortcuts
        updated[key] = learned
        guard updated.count > limit else { return updated }
        let oldest = updated.sorted { $0.value.learned < $1.value.learned }.prefix(updated.count - limit).map(\.key)
        oldest.forEach { updated.removeValue(forKey: $0) }
        return updated
    }
}
