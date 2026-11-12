//
//  ArisDesktopRuntime.swift
//  aris-agent
//
//  Peekaboo itself (openclaw/Peekaboo, MIT): off until computer use is first needed, then the pinned release's native
//  archive is downloaded from GitHub Releases, its SHA-256 checked, and only its three files (the CLI, the Swift
//  compatibility library it loads from beside itself, and its licence) are unpacked and checked by their own SHA-256
//  into ~/Library/Application Support/Aris/computer-runtime/. They are checked again before every run, so a changed file
//  is never run (it is put back from the pinned archive). It runs as aris-agent's child, in-process and local only
//  (PEEKABOO_NO_REMOTE: never another Peekaboo host or its daemon), so macOS counts it under aris-agent's own grants.
//  Peekaboo keeps each snapshot's element map in ~/.peekaboo/snapshots/<id>/ (a 0700 folder): Aris removes the ones
//  it made when it forgets them, and stale ones when the agent starts (ArisPeekabooSnapshots). Its config folder is a new
//  empty one for every run, so no config or credentials file is ever read.
//

import CryptoKit
import Foundation

struct ArisDesktopRelease: Equatable {
    struct Archive: Equatable {
        let url: URL
        let sha256: String
        /// The folder the files sit in inside the archive (`peekaboo-macos-arm64`).
        let folder: String
        /// Each file kept from the archive, by name, and its SHA-256.
        let files: [String: String]
    }

    let version: String
    let archives: [String: Archive]

    static let binaryName = "peekaboo"
    static let libraryName = "libswiftCompatibilitySpan.dylib"
    static let licenceName = "LICENSE"

    /// v4.9.8 (2026-11-05), the release the benchmark kept (BENCH-computer-use.md). Archive hashes match the release's
    /// own checksums.txt; the inner files were hashed from those archives.
    static let pinned = ArisDesktopRelease(version: "4.9.8", archives: [
        "arm64": Archive(url: URL(string: "https://github.com/openclaw/Peekaboo/releases/download/v4.9.8/peekaboo-macos-arm64.tar.gz")!,
                         sha256: "5b82b246cd7b257b68d15e136a8234848a8e70a5999cdf5526993fb860685bfe", folder: "peekaboo-macos-arm64",
                         files: [binaryName: "6e2d9f91cf95689cc061d138cb26f023b511c434f571436c1ae139d040a0f3b4",
                                 libraryName: "a9e85f785846635c6c12658d2ace9e70af018ba999dd2dcaeec7ffc067ba986e",
                                 licenceName: "62316704df7426e5a79d2827ff8aca36e9abb3a73b8e68557030749ebefec667"]),
        "x86_64": Archive(url: URL(string: "https://github.com/openclaw/Peekaboo/releases/download/v4.9.8/peekaboo-macos-x86_64.tar.gz")!,
                          sha256: "7792ac5f4cefbd4473c2766d4905ceb486df8da4aa270399cda214b0f4bed877", folder: "peekaboo-macos-x86_64",
                          files: [binaryName: "91c64f58c0f205f302c2232645169bc2a83444b8f6b1e5570849faf0a9663ac1",
                                  libraryName: "e5da58bdc31d865afb51ddeb66568aa276edf3d41db600851200fe94ed475ca1",
                                  licenceName: "62316704df7426e5a79d2827ff8aca36e9abb3a73b8e68557030749ebefec667"]),
    ])

    static var machine: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    var archive: Archive? { archives[Self.machine] }
}

/// Downloads one file; nil on success, else why not.
protocol ArisDesktopDownloading {
    func fetch(_ url: URL, to file: URL) -> String?
}

/// Unpacks only `members` of a .tar.gz into `folder`; false when it couldn't.
protocol ArisDesktopUnpacking {
    func unpack(_ archive: URL, into folder: URL, members: [String]) -> Bool
}

enum ArisDesktopInstallState: Equatable {
    case absent
    case installing
    case ready
    case failed(String)
}

final class ArisDesktopInstaller {
    let root: URL
    let release: ArisDesktopRelease
    private let downloader: ArisDesktopDownloading
    private let unpacker: ArisDesktopUnpacking
    private let lock = NSLock()
    private var current = ArisDesktopInstallState.absent
    private var failedAt: Date?
    /// After a failed install, the next try waits this long (each call doesn't download again).
    let retryAfter: TimeInterval

    /// `~/Library/Application Support/Aris/computer-runtime`.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Aris/computer-runtime")
    }

    init(root: URL = ArisDesktopInstaller.defaultRoot, release: ArisDesktopRelease = .pinned, downloader: ArisDesktopDownloading = ArisDesktopLiveDownload(),
         unpacker: ArisDesktopUnpacking = ArisDesktopTar(), retryAfter: TimeInterval = 60) {
        self.root = root
        self.release = release
        self.downloader = downloader
        self.unpacker = unpacker
        self.retryAfter = retryAfter
    }

    var state: ArisDesktopInstallState { lock.withLock { current } }
    var folder: URL { root.appendingPathComponent("peekaboo-\(release.version)") }
    var binary: URL { folder.appendingPathComponent(ArisDesktopRelease.binaryName) }
    /// Peekaboo's working folder (its config dir and the screenshots Aris asks for), apart from the user's own.
    var stateFolder: URL { root.appendingPathComponent("state") }

    /// Whether the pinned files are in place, exactly as released (checked by their SHA-256, every time).
    func isInstalled() -> Bool {
        guard let archive = release.archive else { return false }
        return archive.files.allSatisfy { Self.sha256(of: folder.appendingPathComponent($0.key)) == $0.value }
    }

    /// The checked binary, installing it first when it's missing or changed. Blocks (a download): never on a queue that
    /// answers anyone. One install at a time; a failed one isn't tried again for `retryAfter`.
    func ready() -> Result<URL, ArisDesktopUsage> {
        lock.lock()
        defer { lock.unlock() }
        if isInstalled() {
            guard makePrivate() else { return .failure(ArisDesktopUsage(text: "couldn't make the computer-use folder private")) }
            current = .ready
            return .success(binary)
        }
        if case .failed(let why) = current, let failedAt, Date().timeIntervalSince(failedAt) < retryAfter {
            return .failure(ArisDesktopUsage(text: why))
        }
        current = .installing
        if let why = install() {
            current = .failed(why)
            failedAt = Date()
            return .failure(ArisDesktopUsage(text: why))
        }
        guard makePrivate() else { return .failure(ArisDesktopUsage(text: "couldn't make the computer-use folder private")) }
        current = .ready
        return .success(binary)
    }

    /// The folder and its state folder are the user's alone (0700): screenshots of other apps' windows pass through it.
    private func makePrivate() -> Bool {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: stateFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The config folder an older Aris kept: never read again (each run gets a new empty one).
        try? fileManager.removeItem(at: stateFolder.appendingPathComponent("config"))
        for folder in [root, stateFolder] {
            guard (try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)) != nil else { return false }
        }
        return true
    }

    /// Nil when installed; else why not (safe to show).
    private func install() -> String? {
        guard let archive = release.archive else { return "computer use isn't available for this Mac's processor" }
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.createDirectory(at: stateFolder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { return "couldn't make the computer-use folder" }
        let work = root.appendingPathComponent("install-\(UUID().uuidString.prefix(8))")
        defer { try? fileManager.removeItem(at: work) }
        guard (try? fileManager.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else {
            return "couldn't make the computer-use folder"
        }
        let download = work.appendingPathComponent("archive.tar.gz")
        if let why = downloader.fetch(archive.url, to: download) { return "couldn't download Peekaboo (\(why))" }
        guard Self.sha256(of: download) == archive.sha256 else { return "the downloaded Peekaboo isn't the pinned release (its SHA-256 differs), so it wasn't installed" }
        let unpacked = work.appendingPathComponent("files")
        let members = archive.files.keys.sorted().map { "\(archive.folder)/\($0)" }
        guard (try? fileManager.createDirectory(at: unpacked, withIntermediateDirectories: false)) != nil,
              unpacker.unpack(download, into: unpacked, members: members) else { return "couldn't unpack Peekaboo" }
        let files = unpacked.appendingPathComponent(archive.folder)
        for (name, hash) in archive.files {
            let file = files.appendingPathComponent(name)
            guard Self.isPlainFile(file), Self.sha256(of: file) == hash else { return "Peekaboo's files aren't the pinned release's, so they weren't installed" }
            try? fileManager.setAttributes([.posixPermissions: name == ArisDesktopRelease.licenceName ? 0o600 : 0o700], ofItemAtPath: file.path)
        }
        // Swapped in whole: the old folder (a changed or partial one) goes first.
        try? fileManager.removeItem(at: folder)
        do { try fileManager.moveItem(at: files, to: folder) } catch { return "couldn't put Peekaboo in place" }
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        // Any other engine or version left in the folder (an older Peekaboo, or the agent-desktop Aris used before) goes.
        for old in (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        where (old.hasPrefix("peekaboo-") || old.hasPrefix("agent-desktop-")) && old != folder.lastPathComponent {
            try? fileManager.removeItem(at: root.appendingPathComponent(old))
        }
        return isInstalled() ? nil : "Peekaboo's files changed while it was installed"
    }

    /// A regular file (no link), at most 96 MB.
    private static func isPlainFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && (values.fileSize ?? 0) <= 96 << 20
    }

    static func sha256(of url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// GitHub Releases over https (its redirect to the release file host included), at most 64 MB.
struct ArisDesktopLiveDownload: ArisDesktopDownloading {
    func fetch(_ url: URL, to file: URL) -> String? {
        guard url.scheme == "https" else { return "not https" }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 240
        let session = URLSession(configuration: configuration)
        let done = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var problem: String? = "no answer"
        session.downloadTask(with: url) { location, response, error in
            defer { done.signal() }
            if let error { problem = error.localizedDescription; return }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, http.url?.scheme == "https", let location else {
                problem = "the server said \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                return
            }
            let size = (try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= 64 << 20 else { problem = "unexpected size"; return }
            do { try FileManager.default.moveItem(at: location, to: file); problem = nil } catch { problem = "couldn't save it" }
        }.resume()
        guard done.wait(timeout: .now() + 250) == .success else { return "it took too long" }
        return problem
    }
}

/// /usr/bin/tar, only the named members, nothing else of the archive.
struct ArisDesktopTar: ArisDesktopUnpacking {
    func unpack(_ archive: URL, into folder: URL, members: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", folder.path, "--no-same-owner", "--"] + members
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try ArisChildren.run(process) } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

/// Runs Peekaboo once: its argv, its working folder, a time limit; what it printed on stdout.
protocol ArisDesktopRunning {
    func run(_ binary: URL, _ arguments: [String], stateFolder: URL, timeout: TimeInterval) -> (status: Int32, output: Data)
}

struct ArisDesktopProcess: ArisDesktopRunning {
    /// The most of its output read (a large window's tree is cut by Aris anyway).
    static let maxOutput = 8 << 20

    /// Local and in-process only: never a Peekaboo Bridge host, its daemon, its agent, its MCP autoconnect or its
    /// on-screen visualiser. `config`: Peekaboo's config folder, a new empty one for each run (removed after it), so no
    /// config or credentials file anyone left is ever read (security review I11).
    static func environment(stateFolder: URL, config: URL) -> [String: String] {
        let basics = ProcessInfo.processInfo.environment.filter { ["PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LANG"].contains($0.key) || $0.key.hasPrefix("LC_") }
        return basics.merging(["PEEKABOO_NO_REMOTE": "1", "PEEKABOO_DISABLE_AGENT": "1", "PEEKABOO_DISABLE_MCP_AUTOCONNECT": "1",
                               "PEEKABOO_VISUAL_FEEDBACK": "false", "PEEKABOO_CONFIG_DIR": config.path,
                               "PEEKABOO_CONFIG_DISABLE_MIGRATION": "1"]) { $1 }
    }

    func run(_ binary: URL, _ arguments: [String], stateFolder: URL, timeout: TimeInterval) -> (status: Int32, output: Data) {
        let config = stateFolder.appendingPathComponent("config-\(UUID().uuidString.prefix(12))")
        guard (try? FileManager.default.createDirectory(at: config, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else {
            return (126, Data())
        }
        defer { try? FileManager.default.removeItem(at: config) }
        // posix_spawn, never Process: Process decomposes its argv (typed Korean arrived as jamo).
        return ArisSpawn.run(binary.path, arguments, environment: Self.environment(stateFolder: stateFolder, config: config),
                             directory: stateFolder.path, timeout: timeout, maxOutput: Self.maxOutput)
    }
}

/// Peekaboo's own snapshot folders (~/.peekaboo/snapshots/<id>), removed once Aris forgets the snapshot: they hold the
/// element map of another app's window (and a screenshot when one was asked for). Aris keeps a record of the ids it made
/// (`made-snapshots.txt` in its state folder), and only ever removes those: never a folder another Peekaboo user made
/// (re-review 4).
enum ArisPeekabooSnapshots {
    static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".peekaboo/snapshots") }
    static let recordName = "made-snapshots.txt"
    /// The agent's record (its installer's state folder).
    static var recordFile: URL { ArisDesktopInstaller.defaultRoot.appendingPathComponent("state").appendingPathComponent(recordName) }
    /// The most ids kept in the record (the oldest go first).
    static let maxRecorded = 4_096
    private static let lock = NSLock()

    static func isSnapshotId(_ id: String) -> Bool { id.range(of: #"^ps1_[0-9a-f]{32}$"#, options: .regularExpression) != nil }

    /// The ids in a record.
    static func made(record: URL) -> [String] {
        lock.withLock { read(record) }
    }

    /// Aris made this snapshot: it goes in the record.
    static func noteMade(_ id: String, record: URL) {
        guard isSnapshotId(id) else { return }
        lock.withLock {
            var ids = read(record).filter { $0 != id } + [id]
            if ids.count > maxRecorded { ids.removeFirst(ids.count - maxRecorded) }
            write(ids, to: record)
        }
    }

    private static func read(_ record: URL) -> [String] {
        guard let values = try? record.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink != true,
              let text = try? String(contentsOf: record, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init).filter(isSnapshotId)
    }

    private static func write(_ ids: [String], to record: URL) {
        let data = Data(ids.map { $0 + "\n" }.joined().utf8)
        guard FileManager.default.fileExists(atPath: record.deletingLastPathComponent().path) else { return }
        try? data.write(to: record, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
    }

    /// How old a snapshot folder Aris made may be when the agent starts: older ones are a run's that ended before it
    /// could forget them (I12).
    static let staleAge: TimeInterval = 10 * 60

    /// At agent start: every folder Aris made (by its record) last changed more than `age` ago goes, and the record
    /// drops ids whose folder is gone. Folders it didn't make stay, whatever their age.
    static func clean(olderThan age: TimeInterval = staleAge, in root: URL = folder, record: URL = recordFile, now: Date = Date()) {
        let ids = made(record: record)
        let old = ids.filter { id in
            guard let values = try? root.appendingPathComponent(id).resourceValues(forKeys: [.contentModificationDateKey]),
                  let changed = values.contentModificationDate else { return false }
            return now.timeIntervalSince(changed) > age
        }
        remove(old, in: root)
        lock.withLock {
            let left = read(record).filter { FileManager.default.fileExists(atPath: root.appendingPathComponent($0).path) }
            write(left, to: record)
        }
    }

    /// Removes these snapshots' folders (only well-formed ids, only real folders right under `in`); with a `record`,
    /// their ids leave it too.
    static func remove(_ ids: [String], in root: URL = folder, record: URL? = nil) {
        let fileManager = FileManager.default
        for id in ids where isSnapshotId(id) {
            let path = root.appendingPathComponent(id)
            guard let values = try? path.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try? fileManager.removeItem(at: path)
        }
        if let record {
            let gone = Set(ids)
            lock.withLock { write(read(record).filter { !gone.contains($0) }, to: record) }
        }
    }
}
