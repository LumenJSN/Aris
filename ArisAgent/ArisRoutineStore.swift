//
//  ArisRoutineStore.swift
//  aris-agent
//
//  Where the user's routines are kept: ~/.config/aris/aris/routines.json, beside the schedules and kept the same way
//  (ArisPrivateFile: 0600 in a 0700 folder, replaced whole, never through a link, read entry by entry so one damaged
//  entry never hides the rest). Two routines never share a name, however it is spelled (ArisRoutineNames.key).
//

import Foundation

enum ArisRoutineStore {
    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("routines.json")
    }

    /// The routines; a damaged entry is skipped, and a missing or unreadable store is empty.
    static func load(file: URL) -> [ArisRoutine] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return routines(in: data)
    }

    /// The routines to change: like `load`, but a store that is there and isn't the user's private file is refused, never
    /// replaced by a new list.
    private static func loadForChange(file: URL) throws -> [ArisRoutine] {
        if let data = ArisPrivateFile.read(file) { return routines(in: data) }
        var info = stat()
        guard lstat(file.path, &info) != 0, ArisPrivateFile.isRealFolder(file.deletingLastPathComponent()) else {
            throw ArisScheduleError(message: "the routine store isn't private (check \(file.lastPathComponent)'s owner and permissions)")
        }
        return []
    }

    private static func routines(in data: Data) -> [ArisRoutine] {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? ArisPrivateFile.decoder.decode(ArisRoutine.self, from: one)
        }
    }

    /// Keeps `routine`: a new one is added, one with the same name (any spelling) is replaced by it. Refused past
    /// ArisRoutineRules.maxRoutines.
    static func save(_ routine: ArisRoutine, file: URL) throws {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            let key = ArisRoutineNames.key(routine.name)
            // A changed routine keeps its place in the list.
            if let index = stored.firstIndex(where: { ArisRoutineNames.key($0.name) == key }) {
                return try write(stored.enumerated().map { $0.offset == index ? routine : $0.element }, file: file)
            }
            guard stored.count < ArisRoutineRules.maxRoutines else {
                throw ArisScheduleError(message: "there are already \(ArisRoutineRules.maxRoutines) routines: remove one first")
            }
            try write(stored + [routine], file: file)
        }
    }

    /// Takes the routine with that id out and returns it; throws when it is gone already.
    @discardableResult
    static func remove(id: UUID, file: URL) throws -> ArisRoutine {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            guard let found = stored.first(where: { $0.id == id }) else { throw ArisScheduleError(message: "no routine with that name") }
            try write(stored.filter { $0.id != id }, file: file)
            return found
        }
    }

    private static func write(_ routines: [ArisRoutine], file: URL) throws {
        let encoder = ArisPrivateFile.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try ArisPrivateFile.write(try encoder.encode(routines), to: file)
    }
}
