//
//  ArisTurnLog.swift
//  aris-agent
//
//  The notch app's one line per turn (ArisTurnStats), kept in ~/.config/aris/aris/turns.jsonl.
//  Only known fields of plain types are written, cut short, so the file stays small and readable.
//

import Foundation

enum ArisTurnLog {
    static let textLimit = 80
    private static let textFields: Set<String> = ["heard", "apple", "whisper", "path", "tier", "outcome"]
    private static let numberFields: Set<String> = ["understoodMs", "firstSoundMs", "totalMs", "confirms", "declined"]

    /// The fields worth keeping; nil when none are.
    static func clean(_ line: [String: Any]) -> [String: Any]? {
        var kept: [String: Any] = [:]
        for (key, value) in line {
            if textFields.contains(key), let text = value as? String { kept[key] = String(text.prefix(textLimit)) }
            if numberFields.contains(key), let number = value as? Int { kept[key] = number }
        }
        return kept.isEmpty ? nil : kept
    }

    static func append(_ line: [String: Any], in directory: URL) {
        guard var kept = clean(line) else { return }
        kept["time"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: kept, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        let file = directory.appendingPathComponent("turns.jsonl")
        ArisLogRotation.rotate(file)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }
}
