//
//  ClaudeHookToken.swift
//  Aris
//
//  Shared secret between Claude Code's http hooks and the local hook server.
//  install-claude-hooks.py writes it to ~/.config/aris/claude-hook-token
//  and into the hook `headers`; the app reads it through a read-only sandbox exception.
//

import Foundation
import Security

enum ClaudeHookToken {
    static let header = "x-aris-token"
    /// Hooks installed before the rename (Claude Code's settings, the status line, agent-hook.sh) still send this one.
    static let legacyHeader = "x-boring-notch-token"
    static let minLength = 32

    static var defaultURL: URL {
        URL(fileURLWithPath: UserHome.path).appendingPathComponent(".config/aris/claude-hook-token")
    }

    static func load(from url: URL = defaultURL) -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.count >= minLength ? token : nil
    }

    /// Makes the token file when there is none (aris-agent at start: it owns ~/.config/aris): 32 random bytes as hex,
    /// 0600, created exclusively so two starts can't both write one. True when this call made it. The same secret is
    /// then read by the app and written into the hooks by their installer.
    static func createIfMissing(at url: URL = defaultURL) -> Bool {
        guard load(from: url) == nil else { return false }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return false }
        let token = bytes.map { String(format: "%02x", $0) }.joined() + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        do {
            try handle.write(contentsOf: Data(token.utf8))
            return true
        } catch {
            return false
        }
    }

    /// Constant-time so response timing doesn't leak how much of a guess matched.
    static func matches(_ given: String, _ expected: String) -> Bool {
        let a = Array(given.utf8), b = Array(expected.utf8)
        guard !b.isEmpty, a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

enum UserHome {
    /// Real home, not the sandbox container that `NSHomeDirectory()` and `homeDirectoryForCurrentUser` return.
    static let path = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
}
