//
//  ArisTeachLastValues.swift
//  aris-agent
//
//  The values a lesson's last run typed, by lesson and value key, so its value card suggests last time's value and
//  not the example he showed when he taught it (twelfth VM run: "Added line" was offered after runs with "우유").
//  Kept beside taught.json the same way (ArisPrivateFile), memory of the values only, the newest per lesson. A value
//  is only ever a suggestion above an empty field (ArisTeachCopy.suggestion): it is never typed unless he writes it in.
//

import Foundation

enum ArisTeachLastValues {
    static func file(home: String) -> URL { ArisPrivateFile.folder(home: home).appendingPathComponent("taught-last.json") }

    static func load(_ id: UUID, file: URL) -> [String: String] {
        all(file: file)[id.uuidString] ?? [:]
    }

    /// The run's values become the lesson's last ones (an empty set changes nothing).
    static func note(_ id: UUID, values: [String: String], file: URL) {
        let kept = values.filter { !$0.value.isEmpty }.mapValues { String($0.prefix(2_000)) }
        guard !kept.isEmpty else { return }
        var every = all(file: file)
        every[id.uuidString] = kept
        guard let data = try? JSONEncoder().encode(every) else { return }
        do { try ArisPrivateFile.write(data, to: file) } catch {
            try? FileHandle.standardError.write(contentsOf: Data("aris-agent: a lesson's last values couldn't be kept: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func all(file: URL) -> [String: [String: String]] {
        guard let data = ArisPrivateFile.read(file) else { return [:] }
        return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
    }
}
