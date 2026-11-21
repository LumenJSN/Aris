//
//  ArisTCCReading.swift
//  aris-agent
//
//  macOS's own decision for Aris, read from its permission database, for the one case where nothing else tells: System
//  Integrity Protection's file protection off (a VM, a developer's Mac). Then every file Full Disk Access guards opens
//  anyway, the database itself among them, so a probe that opens a guarded file says "allowed" with no grant (VM run
//  2026-11-19: Full Disk Access and "3 file folders" both "Allowed" right after a reset; the earlier fix tried a
//  folder only Full Disk Access opens, and with SIP off those open too). The database is readable in exactly that
//  case, and its row for Aris is the decision itself. With SIP on nothing here is used (the user's Mac: the probe decides,
//  as before). Read only, never written; what can't be read is nil, and the callers take nil as "not allowed".
//

import Foundation
import SQLite3

enum ArisTCCReading {
    /// The machine's database: Full Disk Access is decided here.
    static let systemDatabase = "/Library/Application Support/com.apple.TCC/TCC.db"
    /// This user's: the Desktop, Documents and Downloads folders are decided here.
    static var userDatabase: String { NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db" }

    /// What macOS may file this helper's grants under: the app's id (the one "Aris" row), the helper's own signing
    /// identifier (assemble-app.sh), this program's path, and the path builds before the app bundle ran it from.
    static var clients: [String] {
        ["com.lumenjsn.aris", "com.lumenjsn.aris.aris-agent", ProcessInfo.processInfo.arguments.first ?? "",
         NSHomeDirectory() + "/.config/aris/aris-agent"].filter { !$0.isEmpty }
    }

    /// A row's auth_value that allows (0 denied, 1 unknown, 2 allowed, 3 limited).
    static let allowedValue: Int32 = 2

    /// Whether a row in `database` allows `service` for any of `clients`: true when one does, false when none does
    /// (no row, or only refusals), nil when the database can't be opened or read.
    static func allowed(service: String, clients: [String], database: String) -> Bool? {
        guard !clients.isEmpty else { return false }
        // A plain read first; a database whose log this process can't open is read as it is on disk.
        return read(service: service, clients: clients, uri: "file:\(database)?mode=ro")
            ?? read(service: service, clients: clients, uri: "file:\(database)?mode=ro&immutable=1")
    }

    private static func read(service: String, clients: [String], uri: String) -> Bool? {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else { return nil }
        let marks = Array(repeating: "?", count: clients.count).joined(separator: ",")
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT auth_value FROM access WHERE service = ? AND client IN (\(marks))", -1, &statement, nil) == SQLITE_OK else { return nil }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, service, -1, transient)
        for (index, client) in clients.enumerated() { sqlite3_bind_text(statement, Int32(index + 2), client, -1, transient) }
        var allows = false
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: if sqlite3_column_int(statement, 0) == allowedValue { allows = true }
            case SQLITE_DONE: return allows
            default: return nil
            }
        }
    }

    /// The folder's service name ("Desktop" is kTCCServiceSystemPolicyDesktopFolder).
    static func folderService(_ name: String) -> String { "kTCCServiceSystemPolicy\(name)Folder" }
    static let diskService = "kTCCServiceSystemPolicyAllFiles"
}
