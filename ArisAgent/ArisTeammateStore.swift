//
//  ArisTeammateStore.swift
//  aris-agent
//
//  Aris's teammates in ~/.config/aris/aris/teammates.json: 0600 in a 0700 folder, replaced whole, never through a link,
//  read entry by entry (ArisPrivateFile, as the scheduler's files). A missing file is seeded with Claude Code. A file
//  that isn't the user's own, or that others could read or write, counts for nothing and is never replaced. Claude and
//  agy may neither read nor write it.
//

import Foundation

enum ArisTeammateStore {
    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("teammates.json")
    }

    /// The teammates. Missing: seeded (and written) with Claude Code. Unusable (a link, not private): Claude Code only,
    /// and the file is left as it is.
    static func load(file: URL) -> [ArisTeammate] {
        if let data = ArisPrivateFile.read(file) { return ArisTeammate.list(from: data) }
        guard isMissing(file) else {
            FileHandle.standardError.write(Data("aris: \(file.path) isn't a private file of yours: left as it is\n".utf8))
            return [.claudeCode]
        }
        do {
            try save([.claudeCode], file: file)
        } catch {
            FileHandle.standardError.write(Data("aris: couldn't seed \(file.lastPathComponent): \(error)\n".utf8))
        }
        return [.claudeCode]
    }

    /// Replaces the list; refused when the file there isn't the user's private file (or sits in a linked folder).
    static func save(_ teammates: [ArisTeammate], file: URL) throws {
        try ArisPrivateFile.withLock(file) {
            guard ArisPrivateFile.read(file) != nil || isMissing(file) else {
                throw ArisScheduleError(message: "the teammate list isn't private (check \(file.lastPathComponent)'s owner and permissions)")
            }
            try ArisPrivateFile.write(try ArisPrivateFile.encoder.encode(teammates.compactMap { $0.checked() }), to: file)
        }
    }

    /// Nothing is there (not even a link), in a real folder or one still to be made.
    private static func isMissing(_ file: URL) -> Bool {
        var info = stat()
        guard lstat(file.path, &info) != 0 else { return false }
        let folder = file.deletingLastPathComponent()
        return ArisPrivateFile.isRealFolder(folder) || lstat(folder.path, &info) != 0
    }
}
