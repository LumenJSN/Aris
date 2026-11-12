//
//  ArisNoFollow.swift
//  aris-agent
//
//  File access for POST /data that never goes through a symbolic link: wipe and diagnostics touch only regular
//  files and real folders (lstat), and open with O_NOFOLLOW, so a link planted in ~/.config/aris can't make the agent
//  read, empty or remove something elsewhere.
//

import Foundation

enum ArisNoFollow {
    private static func mode(_ url: URL) -> mode_t? {
        var info = stat()
        return lstat(url.path, &info) == 0 ? info.st_mode & S_IFMT : nil
    }

    static func isFile(_ url: URL) -> Bool { mode(url) == S_IFREG }
    static func isDirectory(_ url: URL) -> Bool { mode(url) == S_IFDIR }

    /// The names in a real folder (empty for a link or anything else).
    static func contents(_ folder: URL) -> [String] {
        isDirectory(folder) ? ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []) : []
    }

    /// A regular file's bytes (its last `tail` bytes when given); nil for a link, a folder or anything unreadable.
    static func read(_ url: URL, tail: Int? = nil) -> Data? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        if let tail, info.st_size > tail { try? handle.seek(toOffset: UInt64(info.st_size) - UInt64(tail)) }
        return try? handle.readToEnd() ?? Data()
    }

    static func text(_ url: URL) -> String? { read(url).map { String(decoding: $0, as: UTF8.self) } }

    /// Empties a regular file in place (never through a link). False when it isn't one.
    static func truncate(_ url: URL) -> Bool {
        let fd = open(url.path, O_WRONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return false }
        return ftruncate(fd, 0) == 0
    }

    /// Removes a regular file (a link or a folder by that name is left alone). True when it's gone or never was.
    @discardableResult
    static func removeFile(_ url: URL) -> Bool {
        guard let mode = mode(url) else { return true }
        return mode == S_IFREG && unlink(url.path) == 0
    }

    /// A new file, 0600 from its first byte (never through a link, never over an existing one).
    static func createPrivate(_ url: URL, _ data: Data) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw CocoaError(.fileWriteFileExists) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: data)
    }

    /// Writes `data` to a regular file's place: a temp file next to it, then rename (a link is replaced by nothing:
    /// the caller checks isFile first).
    static func replace(_ url: URL, with data: Data) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).aris-\(UUID().uuidString)")
        try data.write(to: temp, options: .withoutOverwriting)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path), let permissions = attributes[.posixPermissions] {
            try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
        }
        guard rename(temp.path, url.path) == 0 else {
            try? FileManager.default.removeItem(at: temp)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
