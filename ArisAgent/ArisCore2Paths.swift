//
//  ArisCore2Paths.swift
//  aris-agent
//
//  The file capabilities' paths as the disk has them (Core 2 review, 2026-11-19). A path is decided on where it lands,
//  links followed (the shell sandbox's own resolution: the deepest existing folder resolved, the rest kept), so a
//  link `~/w/l -> ~/.ssh` is ~/.ssh to the never-list. The executor resolves it again just before the read or write,
//  refuses when it lands somewhere else than when it was decided or on the never-list, and opens the place it checked
//  without following a link on its last part (O_NOFOLLOW), the file or folder it opened confirmed by its own path
//  (F_GETPATH). Capabilities with a path: read_file and write_file (`path`), edit_file (`path`), search_files (`in`).
//

import Darwin
import Foundation

extension ArisCore2 {
    /// Each file capability's path argument.
    static let pathArgument: [String: String] = ["file.read": "path", "file.write": "path", "file.edit": "path", "file.search": "in"]

    /// `path` (~ expanded, standardized) where it lands: links followed (ArisShellSandbox.real), written from `home` as
    /// given when it is under it (the never-list and the undo compare with that spelling).
    static func resolved(_ path: String, home: String) -> String {
        let full = ((path as NSString).expandingTildeInPath as NSString).standardizingPath
        let real = ArisShellSandbox.real(full)
        let base = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        let realHome = ArisShellSandbox.real(base)
        if real == realHome { return base }
        if real.hasPrefix(realHome + "/") { return base + real.dropFirst(realHome.count) }
        return real
    }

    /// `resolved` back in the disk's own spelling (what F_GETPATH says of the file once it is open).
    static func realForm(_ resolved: String, home: String) -> String {
        let base = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        if resolved == base || resolved.hasPrefix(base + "/") { return ArisShellSandbox.real(base) + resolved.dropFirst(base.count) }
        return resolved
    }

    /// The same place: equal but for the system's own /private links and letter case (APFS).
    static func samePlace(_ one: String, _ other: String) -> Bool {
        let plain = { (path: String) -> String in
            for place in ["/private/var", "/private/tmp", "/private/etc"] where path == place || path.hasPrefix(place + "/") {
                return ArisProtectedPlaces.key(String(path.dropFirst("/private".count)))
            }
            return ArisProtectedPlaces.key(path)
        }
        return plain(one) == plain(other)
    }

    /// A file capability's path as the decision resolves it, in the disk's own spelling (so it compares the same in
    /// any process, whatever its home folder is called); nil for any other call (or a path that isn't absolute).
    static func decidedPath(_ capability: String, _ arguments: [String: Any]) -> String? {
        guard let key = pathArgument[capability], let raw = ArisAPICatalog.text(arguments[key]), raw.hasPrefix("/") || raw.hasPrefix("~") else { return nil }
        return ArisShellSandbox.real(((raw as NSString).expandingTildeInPath as NSString).standardizingPath)
    }

    static let movedRefusal = "Not done: that path leads somewhere else now than when it was decided (a link on the way changed), so nothing was read or written."
    static let relativeRefusal = "Not done: give the file's full path."

    /// Just before a file capability runs: its path resolved again, the same place as `decided` (or, when the decision
    /// didn't say, no link on the way at all), and not on the never-list. The path to act on (as given when no link is
    /// on the way, else where it lands) and that place in the disk's own spelling; or why not.
    static func fileTarget(_ capability: String, _ arguments: [String: Any], decided: String?, home: String) -> Result<(path: String, real: String), ArisFileRefusal> {
        guard let key = pathArgument[capability], let raw = ArisAPICatalog.text(arguments[key]), raw.hasPrefix("/") || raw.hasPrefix("~") else {
            return .failure(ArisFileRefusal(text: relativeRefusal))
        }
        let given = ((raw as NSString).expandingTildeInPath as NSString).standardizingPath
        let now = resolved(given, home: home)
        if let decided, ArisProtectedPlaces.key(decided) != ArisProtectedPlaces.key(ArisShellSandbox.real(given)) {
            return .failure(ArisFileRefusal(text: movedRefusal))
        }
        let linked = !samePlace(given, now)
        if decided == nil, linked { return .failure(ArisFileRefusal(text: movedRefusal)) }
        let writing = capability == "file.write" || capability == "file.edit"
        if fileEffect(given, writing: writing, edit: capability == "file.edit", home: home) == .never {
            return .failure(ArisFileRefusal(text: ArisCapabilityGate.neverLine))
        }
        return .success((linked ? now : given, realForm(now, home: home)))
    }

    // MARK: - Opening without following a link

    /// The path the kernel has for an open descriptor.
    static func openedPath(_ descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    /// A regular file opened to read, its last part never followed, confirmed to be `real` once open; nil otherwise.
    static func openNoFollow(_ path: String, real: String) -> FileHandle? {
        let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, let opened = openedPath(descriptor),
              ArisProtectedPlaces.key(opened) == ArisProtectedPlaces.key(real) else { return nil }
        return handle
    }

    /// A folder opened, its last part never followed, confirmed to be `real`; its descriptor (the caller closes it).
    static func openFolderNoFollow(_ path: String, real: String) -> Int32? {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        guard let opened = openedPath(descriptor), ArisProtectedPlaces.key(opened) == ArisProtectedPlaces.key(real) else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    struct NoFollowError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// `data` written whole at `path` (a new file next to it, renamed over it inside the folder that was checked), never
    /// through a link: a link put there since is replaced, not followed. An existing file keeps its permissions.
    static func writeNoFollow(_ data: Data, to path: String, real: String) throws {
        let folder = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
        guard let directory = openFolderNoFollow(folder, real: (real as NSString).deletingLastPathComponent) else {
            throw NoFollowError(message: "its folder isn't the one that was checked")
        }
        defer { close(directory) }
        var info = stat()
        let mode: mode_t = fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 && info.st_mode & S_IFMT == S_IFREG ? info.st_mode & 0o7777 : 0o644
        let temporary = ".aris-write-" + UUID().uuidString
        let descriptor = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw NoFollowError(message: String(cString: strerror(errno))) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            guard fchmod(descriptor, mode) == 0 else { throw NoFollowError(message: String(cString: strerror(errno))) }
            try handle.close()
        } catch {
            unlinkat(directory, temporary, 0)
            throw error
        }
        guard renameat(directory, temporary, directory, name) == 0 else {
            let failure = String(cString: strerror(errno))
            unlinkat(directory, temporary, 0)
            throw NoFollowError(message: failure)
        }
    }
}

/// Why a file capability's path was refused just before it ran.
struct ArisFileRefusal: Error, Equatable {
    let text: String
}
