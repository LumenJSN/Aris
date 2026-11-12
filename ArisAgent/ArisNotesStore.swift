//
//  ArisNotesStore.swift
//  aris-agent
//
//  Where notes live (ArisNotes): ~/.config/aris/aris/knowhow.md for 앱 노하우, teammates/<id>.md for a teammate's own
//  (its memoryFile; the path always comes from its checked id, never from a stored or requested string). Private files
//  as the scheduler's (0600 in a 0700 folder, never through a link, one writer at a time). Claude and agy may neither
//  read nor write them (ArisClaudeDriver's deny list); the agent alone keeps them, and the app reads and deletes through
//  POST /teammates.
//

import Foundation

enum ArisNotesStore {
    static func knowhowFile(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("knowhow.md")
    }

    /// A teammate's notes; nil for an id that isn't one (it names a file).
    static func teammateFile(home: String, id: String) -> URL? {
        guard ArisTeammate.isValidId(id) else { return nil }
        return ArisPrivateFile.folder(home: home).appendingPathComponent("teammates").appendingPathComponent("\(id).md")
    }

    /// A removed teammate's notes go with it (N18): teammates/<id>.md for each checked id, never Claude Code's (it can't
    /// be removed) and never a path that isn't a valid id. A link is removed as itself, never followed.
    static func removeTeammate(ids: [String], home: String) {
        for id in ids where id != ArisTeammate.claudeCodeId {
            guard let file = teammateFile(home: home, id: id) else { continue }
            unlink(file.path)
        }
    }

    static func load(_ file: URL) -> [ArisKeptNote] {
        ArisPrivateFile.read(file).map { ArisNoteFile.notes(in: String(decoding: $0, as: UTF8.self)) } ?? []
    }

    /// Adds `notes` (a note already there, word for word for the same app, is kept as it was), keeping the newest
    /// learned ones within `limit`: the user's own lines are never dropped (M1).
    @discardableResult
    static func add(_ notes: [ArisKeptNote], to file: URL, limit: Int) -> Bool {
        guard !notes.isEmpty else { return true }
        return change(file) { kept in evicting(kept + notes.filter { note in !kept.contains { $0.text == note.text && $0.app == note.app } }, limit: limit) }
    }

    /// The oldest learned notes go until `limit` is met (or only the user's are left); the order stays.
    static func evicting(_ notes: [ArisKeptNote], limit: Int) -> [ArisKeptNote] {
        var extra = notes.count - limit
        return notes.filter { note in
            guard extra > 0, note.source == .learned else { return true }
            extra -= 1
            return false
        }
    }

    /// The user keeps note `id` (Settings' 확인 필요): turns may read it from now on. False when it isn't there.
    @discardableResult
    static func markKept(id: String, in file: URL) -> Bool {
        guard load(file).contains(where: { $0.id == id }) else { return false }
        return change(file) { notes in notes.map { note in
            guard note.id == id else { return note }
            var kept = note
            kept.kept = true
            return kept
        } }
    }

    /// Removes the note `id` (nil: every note).
    @discardableResult
    static func remove(id: String?, from file: URL) -> Bool {
        change(file) { kept in id.map { gone in kept.filter { $0.id != gone } } ?? [] }
    }

    private static func change(_ file: URL, _ edit: ([ArisKeptNote]) -> [ArisKeptNote]) -> Bool {
        do {
            return try ArisPrivateFile.withLock(file) {
                let data = ArisPrivateFile.read(file)
                // A file that is there but unreadable (a link, not private) is left as it is.
                if data == nil, FileManager.default.fileExists(atPath: file.path) { return false }
                let original = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let now = Date()
                let before = ArisNoteFile.notes(in: original, now: now)
                let after = edit(before)
                guard after != before else { return true }
                // Only the notes' own lines change: the user's headings, their hand-written lines and anything unread stay (re-review 1).
                try ArisPrivateFile.write(Data(ArisNoteFile.rewrite(original, to: after, now: now).utf8), to: file)
                return true
            }
        } catch {
            FileHandle.standardError.write(Data("aris-agent: couldn't keep notes in \(file.lastPathComponent): \(error)\n".utf8))
            return false
        }
    }

    /// What one answer left (ArisNoteFence): app notes to 앱 노하우, a teammate's own to its file. `by`: who wrote it;
    /// `tainted`: the turn had taken in outside text (then no turn reads it until the user keeps it). A model wrote every one
    /// of them, so each is learned, never the user's own (M3).
    /// `isApp`: the name is an app on this Mac (installed or running; re-review 3), so "the" never becomes an app note.
    static func keepFound(_ found: [ArisNoteFence.Found], by: String, teammate: String?, tainted: Bool,
                          home: String = FileManager.default.homeDirectoryForCurrentUser.path, now: Date = Date(),
                          isApp: (String) -> Bool = { _ in false }) {
        let make = { (item: ArisNoteFence.Found) in
            ArisKeptNote(id: UUID().uuidString.lowercased(), text: item.text, app: item.app, date: now, source: .learned, tainted: tainted, by: by)
        }
        add(found.filter { $0.app.map(isApp) ?? false }.map(make), to: knowhowFile(home: home), limit: ArisNoteRules.maxKnowhow)
        if let teammate, let file = teammateFile(home: home, id: teammate) {
            let own = found.filter { $0.app == nil }.map(make)
            add(own, to: file, limit: ArisNoteRules.maxTeammateNotes)
        }
    }
}
