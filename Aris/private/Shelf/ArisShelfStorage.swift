//
//  ArisShelfStorage.swift
//  Aris
//
//  Where the shelf keeps things: security-scoped bookmarks to files, items.json in the container's Application
//  Support (folder name kept from earlier builds), and Aris's own temporary files for dropped data, text and links.
//

import Foundation
import os

/// A security-scoped bookmark: resolve it (refreshing a stale one), and open the file only while it is used.
struct ArisBookmark {
    let data: Data

    static func make(for url: URL) -> ArisBookmark? {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return ArisBookmark(data: data)
        }
        return (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)).map(ArisBookmark.init)
    }

    /// The file, and fresh bookmark bytes when the system said the old ones were stale.
    func resolve() -> (url: URL, refreshed: Data?)? {
        var stale = false
        let url = (try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url else { return nil }
        guard stale else { return (url, nil) }
        let refreshed = ArisBookmark.withAccess(to: url) { ArisBookmark.make(for: $0)?.data }
        return (url, refreshed)
    }

    /// The file, resolved at most once every couple of seconds per bookmark (tiles redraw often; a moved file is
    /// picked up on the next resolve).
    func resolvedURL() -> URL? { ArisBookmarkCache.shared.url(for: self) }

    /// Runs `body` with the file's scoped access open, and always closes it.
    static func withAccess<T>(to url: URL, _ body: (URL) throws -> T) rethrows -> T {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }
}

/// Recently resolved bookmarks.
final class ArisBookmarkCache: @unchecked Sendable {
    static let shared = ArisBookmarkCache()
    static let lifetime: TimeInterval = 2

    private let lock = NSLock()
    private var entries: [Data: (url: URL?, at: Date)] = [:]

    func url(for bookmark: ArisBookmark, now: Date = Date()) -> URL? {
        lock.lock()
        if let hit = entries[bookmark.data], now.timeIntervalSince(hit.at) < Self.lifetime {
            lock.unlock()
            return hit.url
        }
        lock.unlock()
        let url = bookmark.resolve()?.url
        lock.lock()
        entries[bookmark.data] = (url, now)
        lock.unlock()
        return url
    }
}

/// items.json, pretty-printed. Items are read one by one: a bad item is skipped, the rest load. A file that can't be
/// read at all is copied to items.json.corrupt and reported, so the shelf doesn't overwrite it unasked.
struct ArisShelfArchive {
    let file: URL

    static var standard: ArisShelfArchive {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ArisShelfArchive(file: support.appendingPathComponent("boringNotch/Shelf/items.json"))
    }

    var corruptCopy: URL { file.appendingPathExtension("corrupt") }

    /// One element of the array; nil when that element doesn't decode.
    private struct Lenient: Decodable {
        let item: ShelfItem?
        init(from decoder: Decoder) throws { item = try? ShelfItem(from: decoder) }
    }

    /// The items, and whether the file was readable (a missing file is fine: an empty shelf).
    func read() -> (items: [ShelfItem], intact: Bool) {
        guard FileManager.default.fileExists(atPath: file.path) else { return ([], true) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file), let entries = try? decoder.decode([Lenient].self, from: data) else {
            try? FileManager.default.removeItem(at: corruptCopy)
            try? FileManager.default.copyItem(at: file, to: corruptCopy)
            Log.shelf.error("shelf: items.json could not be read; kept a .corrupt copy and won't overwrite it unasked")
            return ([], false)
        }
        let items = entries.compactMap(\.item)
        if items.count < entries.count { Log.shelf.error("shelf: skipped \(entries.count - items.count, privacy: .public) unreadable items") }
        return (items, true)
    }

    func load() -> [ShelfItem] { read().items }

    func save(_ items: [ShelfItem]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(items).write(to: file, options: .atomic)
        } catch {
            Log.shelf.error("shelf: could not save: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Aris's own files for things dropped without one: one uuid folder each under the temporary directory.
struct ArisShelfTempFiles {
    var root = FileManager.default.temporaryDirectory

    private static let scratchLock = NSLock()
    nonisolated(unsafe) private static var scratch: Set<URL> = []

    /// Marks a file made only for a moment (text opened in an app, data sent from the share tile): it goes when
    /// `removeScratch` runs (after the share, or at quit).
    static func markScratch(_ file: URL) {
        scratchLock.lock(); scratch.insert(file); scratchLock.unlock()
    }

    static func removeScratch(_ files: [URL]? = nil) {
        scratchLock.lock()
        let gone = files.map { Set($0).intersection(scratch) } ?? scratch
        scratch.subtract(gone)
        scratchLock.unlock()
        let temp = ArisShelfTempFiles()
        gone.forEach(temp.remove)
    }

    private func folder() throws -> URL {
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Dropped bytes, under their suggested name (else "<uuid>.dat").
    func data(_ data: Data, named name: String?) -> URL? {
        let clean = name.map { $0.replacingOccurrences(of: "/", with: ":") }.flatMap { $0.isEmpty ? nil : $0 }
        return try? write(data, as: clean ?? UUID().uuidString + ".dat")
    }

    /// Text as a UTF-8 .txt file.
    func text(_ text: String) -> URL? {
        try? write(Data(text.utf8), as: UUID().uuidString + ".txt")
    }

    /// A link as a .webloc (an XML plist with its URL), named after the host.
    func link(_ url: URL) -> URL? {
        guard let plist = try? PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
        else { return nil }
        return try? write(plist, as: (url.host ?? UUID().uuidString) + ".webloc")
    }

    private func write(_ data: Data, as name: String) throws -> URL {
        let file = try folder().appendingPathComponent(name)
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Deletes a file made here, with its folder. Anything outside the temporary folder is left alone.
    func remove(_ file: URL) {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent().path == root.standardizedFileURL.path else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func owns(_ file: URL) -> Bool {
        file.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path
    }
}

/// Runs the latest request once things have been quiet for `delay` (the shelf saves 1 s after the last change).
final class ArisDebouncer {
    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> Void

    private let delay: TimeInterval
    private let schedule: Scheduler
    private var generation = 0
    private var pending: (() -> Void)?

    init(delay: TimeInterval, schedule: @escaping Scheduler = { delay, work in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work) }) {
        self.delay = delay
        self.schedule = schedule
    }

    func call(_ work: @escaping () -> Void) {
        generation += 1
        let mine = generation
        pending = work
        schedule(delay) { [weak self] in
            guard let self, mine == self.generation else { return }
            self.flush()
        }
    }

    /// Runs the waiting work now, if any.
    func flush() {
        let work = pending
        pending = nil
        work?()
    }
}
