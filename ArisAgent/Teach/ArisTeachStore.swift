//
//  ArisTeachStore.swift
//  aris-agent
//
//  Where taught procedures are kept (F3): ~/.config/aris/aris/taught.json, beside routines.json and kept the same way
//  (ArisPrivateFile: 0600 in a 0700 folder, replaced whole, never through a link, read entry by entry so one damaged
//  entry never hides the rest). Two procedures never share a name, however it is spelled (ArisTeachNames.key); a
//  procedure never takes a routine's name (ArisTeachDesk checks that before the card). The switch is here too:
//  Settings › 할 수 있는 일 › 컴퓨터 제어 › 실험 기능 › 보여 주고 가르치기, which the app sends the helper
//  (ArisHelperSwitches); off by default, and it works only with `arisCore2` on (a replay is Core 2's calls through the
//  one trust decision).
//

import Foundation

enum ArisTeachSwitch {
    static let key = ArisExperimentSwitch.teach.rawValue
    nonisolated(unsafe) static var isOn: () -> Bool = { ArisHelperSwitches.shared.isOn(.teach) && ArisCore2.isOn() }
}

enum ArisTeachStore {
    static let most = 50

    static func file(home: String) -> URL {
        ArisPrivateFile.folder(home: home).appendingPathComponent("taught.json")
    }

    /// The procedures; a damaged entry is skipped, and a missing or unreadable store is empty.
    static func load(file: URL) -> [ArisTeachProcedure] {
        guard let data = ArisPrivateFile.read(file) else { return [] }
        return procedures(in: data)
    }

    private static func procedures(in data: Data) -> [ArisTeachProcedure] {
        guard let entries = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return entries.compactMap { entry in
            guard JSONSerialization.isValidJSONObject(entry), let one = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? ArisPrivateFile.decoder.decode(ArisTeachProcedure.self, from: one)
        }
    }

    /// The store to change: a store that is there and isn't the owner's private file is refused, never replaced.
    private static func loadForChange(file: URL) throws -> [ArisTeachProcedure] {
        if let data = ArisPrivateFile.read(file) { return procedures(in: data) }
        var info = stat()
        guard lstat(file.path, &info) != 0, ArisPrivateFile.isRealFolder(file.deletingLastPathComponent()) else {
            throw ArisScheduleError(message: "the taught store isn't private (check \(file.lastPathComponent)'s owner and permissions)")
        }
        return []
    }

    /// Keeps `procedure`: one with the same id or the same name (any spelling) is replaced in place, else it is added.
    static func save(_ procedure: ArisTeachProcedure, file: URL) throws {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            let key = ArisTeachNames.key(procedure.name)
            if let index = stored.firstIndex(where: { $0.id == procedure.id || ArisTeachNames.key($0.name) == key }) {
                let kept = stored.enumerated().compactMap { offset, old -> ArisTeachProcedure? in
                    if offset == index { return procedure }
                    // A rename onto another's name: that other one goes (the card said so).
                    return old.id != procedure.id && ArisTeachNames.key(old.name) == key ? nil : old
                }
                return try write(kept, file: file)
            }
            guard stored.count < most else { throw ArisScheduleError(message: "there are already \(most) taught procedures: remove one first") }
            try write(stored + [procedure], file: file)
        }
    }

    @discardableResult
    static func remove(id: UUID, file: URL) throws -> ArisTeachProcedure {
        try ArisPrivateFile.withLock(file) {
            let stored = try loadForChange(file: file)
            guard let found = stored.first(where: { $0.id == id }) else { throw ArisScheduleError(message: "no taught procedure with that name") }
            try write(stored.filter { $0.id != id }, file: file)
            return found
        }
    }

    private static func write(_ procedures: [ArisTeachProcedure], file: URL) throws {
        let encoder = ArisPrivateFile.encoder
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try ArisPrivateFile.write(try encoder.encode(procedures), to: file)
    }
}
