//
//  ArisSafeFiles.swift
//  Aris (the XPC helper; also built into aris-agent)
//
//  The few file writes Aris makes in places another process of the same user can reach (~/.config/aris, the
//  LaunchAgents folder), done so that nothing already there is ever followed or half-written: the new thing is made
//  beside its place under a name nobody can guess, then renamed over it. A link at the destination is replaced
//  itself, never followed; a folder there is left alone and the write fails.
//

import Darwin
import Foundation

enum ArisSafeFiles {
    /// What is at a path, links not followed.
    enum Kind: Equatable {
        case nothing, file, link, folder, other
    }

    static func kind(_ path: String) -> Kind {
        var info = stat()
        guard lstat(path, &info) == 0 else { return .nothing }
        switch info.st_mode & S_IFMT {
        case S_IFREG: return .file
        case S_IFLNK: return .link
        case S_IFDIR: return .folder
        default: return .other
        }
    }

    /// Where a link points, as written in it; nil when the path is not a link.
    static func linkTarget(_ path: String) -> String? {
        guard kind(path) == .link else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// A name beside `path` that cannot be guessed (so nobody can put something there first).
    static func besideName(_ path: String, random: () -> UInt64 = { UInt64.random(in: .min ... .max) }) -> String {
        let folder = (path as NSString).deletingLastPathComponent
        return "\(folder)/.\((path as NSString).lastPathComponent).\(String(random(), radix: 36))\(String(random(), radix: 36)).tmp"
    }

    /// The file's whole content beside its place (made new, never through a link), then renamed over it. A folder at
    /// the path is left alone and the write fails.
    static func write(_ data: Data, to path: String, mode: mode_t = 0o644) -> Bool {
        let folder = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let beside = besideName(path)
        let descriptor = open(beside, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard descriptor >= 0 else { return false }
        let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        close(descriptor)
        guard written == data.count, kind(path) != .folder, rename(beside, path) == 0 else {
            unlink(beside)
            return false
        }
        return true
    }

    /// A small regular file's content; nil for anything that is not a file of its own (a link, a pipe, a folder: a
    /// pipe at the path would otherwise hold the reader for good), or larger than `limit`.
    static func readSmallFile(_ path: String, limit: Int = 65_536) -> Data? {
        guard kind(path) == .file else { return nil }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= off_t(limit) else { return nil }
        var data = Data(count: Int(info.st_size))
        let count = data.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
        return count == data.count ? data : nil
    }

    /// Makes the folder (and those above it) when it is not there, then sets it to mode 700 through a descriptor
    /// opened without following a link: a link at the path is never followed and the call fails.
    static func makePrivateFolder(_ path: String) -> Bool {
        if kind(path) == .nothing {
            do {
                try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch { return false }
        }
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        return fchmod(descriptor, 0o700) == 0
    }

    /// Whether someone other than this user (or root) can write the item (links followed: the real folder counts):
    /// it is theirs, or its mode lets everyone. An item that can't be looked at counts as writable.
    static func othersCanWrite(_ path: String, user: uid_t = getuid()) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return true }
        return (info.st_uid != user && info.st_uid != 0) || info.st_mode & S_IWOTH != 0
    }

    /// A new link beside the path, renamed over whatever is at the path (a file, or an older link: replaced itself,
    /// never followed). A folder at the path is left alone and the link fails.
    static func replaceLink(target: String, at path: String) -> Bool {
        let beside = besideName(path)
        guard symlink(target, beside) == 0 else { return false }
        guard kind(path) != .folder, rename(beside, path) == 0 else {
            unlink(beside)
            return false
        }
        return true
    }
}
