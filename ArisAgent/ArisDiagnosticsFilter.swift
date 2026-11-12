//
//  ArisDiagnosticsFilter.swift
//  aris-agent
//
//  What of each log may go into a diagnostics file: how Aris behaved, never what was said. agent.log keeps only the
//  agent's own lines (not a model's stream echoed by a drift note, nor a child process's stderr, which can quote a
//  prompt). actions.log keeps each line's kind: the answer's first word, the action's verb, the risk and the time,
//  never the card's question, scope or details. turns.jsonl keeps the numbers and the path, tier and outcome, never
//  the words heard. Redaction (ArisRedaction) runs after this.
//

import Foundation

enum ArisDiagnosticsFilter {
    /// Brains whose stream lines a drift note quotes ("aris-agent: claude: …").
    private static let brainPrefixes = ArisBrain.allCases.map { "aris-agent: \($0.rawValue):" }

    static func agentLog(_ text: String) -> String {
        lines(text).filter { $0.hasPrefix("aris-agent:") && !brainPrefixes.contains(where: $0.hasPrefix) }
            .map { $0 + "\n" }.joined()
    }

    static func actions(_ text: String) -> String {
        jsonLines(text) { object in
            var kept: [String: Any] = [:]
            for key in ["time", "date", "risk", "caller", "count", "window"] where object[key] != nil { kept[key] = object[key] }
            if let answer = object["answer"] as? String { kept["answer"] = firstWord(answer) }
            if let action = object["action"] as? String { kept["action"] = firstWord(action) }
            return kept
        }
    }

    static func turns(_ text: String) -> String {
        jsonLines(text) { object in
            object.filter { key, value in ["path", "tier", "outcome", "time"].contains(key) || value is NSNumber }
        }
    }

    private static func lines(_ text: String) -> [String] { text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }

    /// "refused (the user said no)" → "refused"; "insert: 3 characters" → "insert".
    private static func firstWord(_ text: String) -> String {
        String(text.prefix { $0.isLetter || $0 == "-" || $0 == "_" })
    }

    /// Each JSON line rewritten by `keep` (sorted keys); a line that isn't a JSON object is dropped.
    private static func jsonLines(_ text: String, keep: ([String: Any]) -> [String: Any]) -> String {
        lines(text).compactMap { line -> String? in
            guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: keep(object), options: [.sortedKeys]) else { return nil }
            return String(decoding: data, as: UTF8.self) + "\n"
        }.joined()
    }
}
