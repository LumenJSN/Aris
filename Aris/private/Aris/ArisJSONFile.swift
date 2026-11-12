//
//  ArisJSONFile.swift
//  Aris
//
//  A saved JSON list (the conversation history, the clipboard) read so that a file that can't be decoded never costs
//  its contents: entries that still decode are kept, and a file that isn't JSON at all is moved aside as
//  <name>.corrupt-<date> (never overwritten by the next save) and logged.
//

import Foundation
import os

enum ArisJSONFile {
    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "files")

    struct Decoded<Row> {
        let rows: [Row]
        /// The whole file didn't decode; these rows came one by one, the bad ones dropped.
        let salvaged: Bool
        /// Not a JSON array at all: nothing could be read.
        let unreadable: Bool
    }

    /// The list in `data`: whole when it decodes, else entry by entry.
    static func decodeList<Row: Decodable>(_ type: [Row].Type, from data: Data) -> Decoded<Row> {
        let decoder = JSONDecoder()
        if let rows = try? decoder.decode([Row].self, from: data) { return Decoded(rows: rows, salvaged: false, unreadable: false) }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return Decoded(rows: [], salvaged: false, unreadable: true)
        }
        let rows = entries.compactMap { entry -> Row? in
            guard let piece = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            return try? decoder.decode(Row.self, from: piece)
        }
        return Decoded(rows: rows, salvaged: true, unreadable: false)
    }

    /// The list saved in `file` (empty when there is none). A file that can't be read is moved aside, once, and the
    /// loss is logged; a file with some bad entries loads the rest and is logged too. `what` names it in the log.
    static func load<Row: Decodable>(_ type: [Row].Type, from file: URL, what: String) -> [Row] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let decoded = decodeList(type, from: data)
        if decoded.unreadable {
            let aside = setAside(file, copy: false)
            log.error("\(what, privacy: .public): couldn't read \(file.lastPathComponent, privacy: .public); kept as \(aside ?? "(couldn't move it)", privacy: .public)")
        } else if decoded.salvaged {
            // The next save writes only what decoded: the file as it was is kept aside first, whole.
            let aside = setAside(file, copy: true)
            log.error("\(what, privacy: .public): some entries of \(file.lastPathComponent, privacy: .public) couldn't be read; \(decoded.rows.count, privacy: .public) kept, the file copied as \(aside ?? "(couldn't copy it)", privacy: .public)")
        }
        return decoded.rows
    }

    /// Keeps `file` as `<name>.corrupt-<date>` next to it (a copy, or moved); the new name, or nil when it couldn't be.
    /// Older copies are pruned: the newest `keptCopies`, none older than `copyMaxAge`.
    static func setAside(_ file: URL, copy: Bool) -> String? {
        let name = file.lastPathComponent + ".corrupt-" + stampFormatter.string(from: Date())
        let target = file.deletingLastPathComponent().appendingPathComponent(name)
        do {
            if copy { try FileManager.default.copyItem(at: file, to: target) } else { try FileManager.default.moveItem(at: file, to: target) }
        } catch {
            return nil
        }
        pruneCopies(of: file)
        return name
    }

    static let keptCopies = 3
    static let copyMaxAge: TimeInterval = 30 * 86_400

    private static var stampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    /// Drops `.corrupt-<date>` copies of `file` beyond the newest `keptCopies` or older than `copyMaxAge`.
    static func pruneCopies(of file: URL, now: Date = Date()) {
        let folder = file.deletingLastPathComponent()
        let prefix = file.lastPathComponent + ".corrupt-"
        let copies = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
        for (index, name) in copies.reversed().enumerated() {
            let old = stampFormatter.date(from: String(name.dropFirst(prefix.count))).map { now.timeIntervalSince($0) > copyMaxAge } ?? true
            if index >= keptCopies || old { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        }
    }
}
