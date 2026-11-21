//
//  ArisUndoStore.swift
//  aris-agent
//
//  Where a file's earlier bytes wait so an edit or an overwrite can be taken back: undo-store/<id> in the helper's
//  folder, 0600 in a 0700 folder, never through a link. A copy is kept only within a size cap (one file, and all of
//  them together); copies older than `keptDays` go, and the oldest go first when the total would pass the cap. A copy
//  counts only once it is read back and matches the file's bytes (size and SHA-256), and the file hasn't changed since
//  it was read. An overwrite is change-reversible only when such a copy can be kept (`canKeep`: a plain file within
//  the cap, room on the disk) and the write then proceeds only after it was (ArisMindExecutor); a file that can't be
//  copied has no undo, and its overwrite counts as permanent (the gate asks for it as such).
//

import CryptoKit
import Darwin
import Foundation

struct ArisUndoStore {
    static let keptDays = 14
    static let fileCap = 50 * 1_024 * 1_024
    static let totalCap = 500 * 1_024 * 1_024

    let folder: URL
    var fileCap = ArisUndoStore.fileCap
    var totalCap = ArisUndoStore.totalCap
    var keptDays = ArisUndoStore.keptDays

    init(home: String) {
        folder = ArisPrivateFile.folder(home: home).appendingPathComponent("undo-store")
    }

    init(folder: URL, fileCap: Int = ArisUndoStore.fileCap, totalCap: Int = ArisUndoStore.totalCap, keptDays: Int = ArisUndoStore.keptDays) {
        self.folder = folder
        self.fileCap = fileCap
        self.totalCap = totalCap
        self.keptDays = keptDays
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// The file's SHA-256 now; nil when it can't be read as a plain file.
    static func hash(of path: String) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, let data = FileManager.default.contents(atPath: path) else { return nil }
        return sha256(data)
    }

    /// A copy of the plain file at `path` (not a link, not a folder) kept and verified: read back, it has the file's
    /// size and SHA-256, and the file still has them. Its id, or nil when it is too big, can't be read, the store can't
    /// be written, or the copy doesn't match (then nothing of it is left).
    func keep(_ path: String, now: Date = Date()) -> String? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, Int(info.st_size) <= fileCap,
              let data = FileManager.default.contents(atPath: path), ArisPrivateFile.prepareFolder(folder) else { return nil }
        prune(now: now, making: data.count)
        guard used() + data.count <= totalCap else { return nil }
        let id = UUID().uuidString.lowercased()
        guard (try? ArisPrivateFile.write(data, to: folder.appendingPathComponent(id))) != nil else { return nil }
        let want = Self.sha256(data)
        guard let kept = copy(id), kept.count == data.count, Self.sha256(kept) == want, Self.hash(of: path) == want else {
            remove(id)
            return nil
        }
        return id
    }

    /// A copy of `data` (the text an app's field held before a replace set it: fourth VM run, D1) kept and verified the
    /// same way: read back, it has the same size and SHA-256. Its id, or nil when it is too big or can't be kept.
    func keep(data: Data, now: Date = Date()) -> String? {
        guard data.count <= fileCap, ArisPrivateFile.prepareFolder(folder) else { return nil }
        prune(now: now, making: data.count)
        guard used() + data.count <= totalCap else { return nil }
        let id = UUID().uuidString.lowercased()
        guard (try? ArisPrivateFile.write(data, to: folder.appendingPathComponent(id))) != nil else { return nil }
        guard let kept = copy(id), kept.count == data.count, Self.sha256(kept) == Self.sha256(data) else {
            remove(id)
            return nil
        }
        return id
    }

    /// Room a copy leaves on the disk, beyond its own size (decision 4).
    static let spaceMargin: Int64 = 64 * 1_024 * 1_024
    /// The free bytes of the disk a folder is on (nil: unknown). A seam for the tests.
    nonisolated(unsafe) static var freeBytes: (String) -> Int64? = { path in
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
    }

    /// Whether a copy of the file at `path` can be kept now, so an overwrite of it is change-reversible (decision 4): a
    /// plain file (not a link, not a folder), readable, within the cap, with room for it on the home folder's disk
    /// (where the store is). No: its overwrite is change-permanent and asks.
    static func canKeep(_ path: String, home: String, fileCap: Int = ArisUndoStore.fileCap) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, Int(info.st_size) <= fileCap, access(path, R_OK) == 0,
              let free = freeBytes(home) else { return false }
        return free >= Int64(info.st_size) + spaceMargin
    }

    /// Whether a copy of an app's text can be kept now (a replace's undo): within the cap, with room on the disk.
    static func canKeep(text: String, home: String, fileCap: Int = ArisUndoStore.fileCap) -> Bool {
        let size = text.utf8.count
        guard size <= fileCap, let free = freeBytes(home) else { return false }
        return free >= Int64(size) + spaceMargin
    }

    /// The kept bytes of `id`; nil when they are gone (aged out) or not the helper's own private file.
    func copy(_ id: String) -> Data? {
        guard UUID(uuidString: id) != nil else { return nil }
        return ArisPrivateFile.read(folder.appendingPathComponent(id.lowercased()))
    }

    func remove(_ id: String) {
        guard UUID(uuidString: id) != nil else { return }
        unlink(folder.appendingPathComponent(id.lowercased()).path)
    }

    /// Copies past their days go; then the oldest, while `making` more bytes would pass the cap.
    func prune(now: Date = Date(), making: Int = 0) {
        var copies = listing()
        for copy in copies where now.timeIntervalSince(copy.date) > Double(keptDays) * 86_400 { unlink(copy.url.path) }
        copies = listing().sorted { $0.date == $1.date ? $0.url.path < $1.url.path : $0.date < $1.date }
        var total = copies.reduce(0) { $0 + $1.size }
        for copy in copies where total + making > totalCap {
            unlink(copy.url.path)
            total -= copy.size
        }
    }

    func used() -> Int { listing().reduce(0) { $0 + $1.size } }

    private func listing() -> [(url: URL, size: Int, date: Date)] {
        guard ArisPrivateFile.isRealFolder(folder), let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { UUID(uuidString: $0) != nil }.compactMap { name in
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
            let seconds = TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
            return (url, Int(info.st_size), Date(timeIntervalSince1970: seconds))
        }
    }
}
