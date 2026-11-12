//
//  ArisTuningLog.swift
//  Aris
//
//  Private, local JSON lines for tuning Aris (router guesses, wake-word checks). They live in
//  the app's own Application Support (Aris/), since the sandboxed app can only read ~/.config.
//

import Foundation

enum ArisTuningLog {
    static func append(_ line: [String: Any], to name: String) {
        guard let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Aris", isDirectory: true) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(name)
        ArisLogRotation.rotate(file)
        var stamped = line
        stamped["time"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: stamped) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            FileManager.default.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        }
    }
}
