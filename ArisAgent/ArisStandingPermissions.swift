//
//  ArisStandingPermissions.swift
//  aris-agent
//
//  The kinds of action the user said Aris may do without asking ("앞으로 이건 그냥 할까?" → 응), each scoped narrowly
//  (kind + app + recipient or target), and how many times in a row he has said yes to each. Kept in
//  ~/.config/aris/aris/permissions.json (0600). A file that is missing, can't be read or isn't 0600 grants nothing.
//

import Foundation

final class ArisStandingPermissions {
    /// Yeses in a row before Aris asks once whether to stop asking.
    static let streakToPropose = 3

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/aris/aris/permissions.json")
    }

    private struct Stored: Codable {
        var granted: [ArisActionScope]
        var streaks: [Streak]
    }

    private struct Streak: Codable {
        let scope: ArisActionScope
        let count: Int
    }

    private let file: URL
    private let lock = NSLock()
    private var granted: [ArisActionScope]
    private var streaks: [ArisActionScope: Int]

    init(file: URL) {
        self.file = file
        // A file others could write (not 0600) might hold grants the user never gave: it counts for nothing.
        let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        let stored = mode & 0o077 != 0 ? nil : (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        granted = stored?.granted.filter(Self.isNarrow) ?? []
        streaks = Dictionary((stored?.streaks ?? []).map { ($0.scope, $0.count) }, uniquingKeysWith: max)
    }

    var all: [ArisActionScope] {
        lock.withLock { granted }
    }

    func contains(_ scope: ArisActionScope) -> Bool {
        lock.withLock { granted.contains(scope) }
    }

    /// A scope with no target would cover every call of that kind: never granted.
    func grant(_ scope: ArisActionScope) {
        guard Self.isNarrow(scope) else { return }
        lock.withLock {
            guard !granted.contains(scope) else { return }
            granted = granted + [scope]
            streaks = streaks.filter { $0.key != scope }
            save()
        }
    }

    func revoke(_ scope: ArisActionScope) {
        lock.withLock {
            granted = granted.filter { $0 != scope }
            streaks = streaks.filter { $0.key != scope }
            save()
        }
    }

    /// The user's answer to a question about `scope`. True when this yes completes a streak and Aris should ask once
    /// whether to stop asking; the streak then starts over, so a "아니" to that question isn't asked again at once.
    func recordApproval(_ scope: ArisActionScope, allowed: Bool) -> Bool {
        guard Self.isNarrow(scope) else { return false }
        return lock.withLock {
            guard !granted.contains(scope) else { return false }
            let count = allowed ? (streaks[scope] ?? 0) + 1 : 0
            let propose = count >= Self.streakToPropose
            streaks = streaks.merging([scope: propose ? 0 : count]) { $1 }.filter { $0.value > 0 }
            save()
            return propose
        }
    }

    private static func isNarrow(_ scope: ArisActionScope) -> Bool {
        !scope.kind.isEmpty && !scope.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Called with `lock` held. Written owner-only from the first byte (a temporary file, then renamed).
    private func save() {
        let stored = Stored(granted: granted, streaks: streaks.map { Streak(scope: $0.key, count: $0.value) }
            .sorted { $0.scope.target < $1.scope.target })
        guard let data = try? JSONEncoder().encode(stored) else { return }
        let folder = file.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let temporary = folder.appendingPathComponent(".\(file.lastPathComponent).\(UUID().uuidString)")
            let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
            guard rename(temporary.path, file.path) == 0 else {
                unlink(temporary.path)
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            // Only the folder and the reason: the file's contents stay out of logs.
            FileHandle.standardError.write(Data("aris-agent: couldn't save standing permissions in \(folder.path): \(error.localizedDescription)\n".utf8))
        }
    }
}
