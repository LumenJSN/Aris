//
//  ArisSkillFolder.swift
//  aris-agent
//
//  One skill's folder on disk: what is in it (within Aris's caps, no links, nothing that isn't a plain file or folder),
//  a fingerprint of every file (a change means the skill is checked again before any AI sees it), and reading one of
//  its files for a brain (`aris-tools skill read <name> [file]`), confined to the folder: no "..", no absolute path,
//  no link at any step, and the resolved file must still sit inside the resolved folder. Pure apart from the files.
//

import CryptoKit
import Foundation

struct ArisSkillFile: Equatable {
    enum Kind: String { case skill, script, reference, asset, other }

    /// Relative to the skill folder, "/"-separated.
    let path: String
    let size: Int
    var kind: Kind {
        if path == ArisSkillFormat.skillFile { return .skill }
        if path.hasPrefix("scripts/") { return .script }
        if path.hasPrefix("references/") { return .reference }
        if path.hasPrefix("assets/") { return .asset }
        return .other
    }
}

struct ArisSkillInventory: Equatable {
    let files: [ArisSkillFile]
    var totalBytes: Int { files.reduce(0) { $0 + $1.size } }
    var hasScripts: Bool { files.contains { $0.kind == .script } }
    /// The skill's own files (without Finder's, git's and archivers').
    var visibleFiles: [ArisSkillFile] { files.filter { !$0.path.split(separator: "/").contains(where: { ArisSkillFolder.isIgnored(String($0)) }) } }
}

enum ArisSkillFolder {
    /// Finder's, git's and archivers' own files (security review I2): never fetched, copied or read for a brain (a path
    /// through one is refused), but still counted and fingerprinted when they are in a folder, so adding one is a change.
    static let ignored: Set<String> = [".DS_Store", ".git", "__MACOSX", ".gitignore", ".gitattributes", ".gitmodules", ".svn", ".hg"]

    /// Whether a path part is one of `ignored` or an AppleDouble file ("._x").
    static func isIgnored(_ part: String) -> Bool { ignored.contains(part) || part.hasPrefix("._") }

    /// The caps for those files (counted apart from the skill's own).
    static let maxIgnoredFiles = 50_000
    static let maxIgnoredBytes = 1_024 * 1_048_576

    /// Left out of the fingerprint only: Finder rewrites it whenever the folder is looked at.
    static let unprinted: Set<String> = [".DS_Store"]
    /// The most of one file a brain reads at once.
    static let maxRead = 64 * 1_024

    /// Every file under `folder` within the caps, or the first problem. Never follows a link: a link anywhere is a problem.
    static func inventory(_ folder: URL) -> Result<ArisSkillInventory, ArisSkillProblem> {
        var files: [ArisSkillFile] = []
        var total = 0
        // Finder's, git's and archivers' files have caps of their own (a cloned skill's .git can be large: re-review).
        var ignoredCount = 0, ignoredTotal = 0
        var problem: ArisSkillProblem?
        func walk(_ url: URL, _ relative: String, depth: Int) {
            guard problem == nil else { return }
            guard depth <= ArisSkillFormat.maxDepth else { problem = .tooBig("폴더가 너무 깊어요"); return }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { problem = .unreadable(relative.isEmpty ? "." : relative); return }
            for name in names.sorted() {
                guard problem == nil else { return }
                let child = url.appendingPathComponent(name)
                let path = relative.isEmpty ? name : relative + "/" + name
                var info = stat()
                guard lstat(child.path, &info) == 0 else { problem = .unreadable(path); return }
                switch info.st_mode & S_IFMT {
                case S_IFLNK: problem = .link(path); return
                case S_IFDIR: walk(child, path, depth: depth + 1)
                case S_IFREG:
                    files.append(ArisSkillFile(path: path, size: Int(info.st_size)))
                    if path.split(separator: "/").contains(where: { isIgnored(String($0)) }) {
                        ignoredCount += 1
                        ignoredTotal += Int(info.st_size)
                        if ignoredCount > maxIgnoredFiles || ignoredTotal > maxIgnoredBytes { problem = .tooBig(".git 같은 폴더가 너무 커요"); return }
                        continue
                    }
                    total += Int(info.st_size)
                    if files.count - ignoredCount > ArisSkillFormat.maxFiles { problem = .tooBig("파일 \(ArisSkillFormat.maxFiles)개 넘음"); return }
                    if total > ArisSkillFormat.maxTotalBytes { problem = .tooBig("\(ArisSkillFormat.maxTotalBytes / 1_048_576)MB 넘음"); return }
                default: problem = .unreadable(path); return
                }
            }
        }
        var top = stat()
        guard lstat(folder.path, &top) == 0, top.st_mode & S_IFMT == S_IFDIR else { return .failure(.unreadable(folder.lastPathComponent)) }
        walk(folder, "", depth: 0)
        if let problem { return .failure(problem) }
        guard files.contains(where: { $0.path == ArisSkillFormat.skillFile }) else { return .failure(.noSkillFile) }
        return .success(ArisSkillInventory(files: files))
    }

    /// The folder's SKILL.md, read and parsed (after the inventory says the folder is fine).
    static func manifest(_ folder: URL) -> Result<ArisSkillManifest, ArisSkillProblem> {
        switch inventory(folder) {
        case .failure(let problem): return .failure(problem)
        case .success: break
        }
        guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(ArisSkillFormat.skillFile).path) else {
            return .failure(.unreadable(ArisSkillFormat.skillFile))
        }
        guard data.count <= ArisSkillFormat.maxSkillFile else { return .failure(.tooBig("SKILL.md")) }
        return ArisSkillFormat.parse(String(decoding: data, as: UTF8.self))
    }

    /// A hash of every file's path and bytes: equal exactly when nothing in the folder changed. Nil when it can't be read.
    /// `skippingIgnored`: Finder's, git's and archivers' files left out too (what a copy of the folder holds).
    static func fingerprint(_ folder: URL, skippingIgnored: Bool = false) -> String? {
        guard case .success(let inventory) = inventory(folder) else { return nil }
        var hasher = SHA256()
        for file in inventory.files where !unprinted.contains((file.path as NSString).lastPathComponent)
            && !(skippingIgnored && file.path.split(separator: "/").contains(where: { isIgnored(String($0)) })) {
            hasher.update(data: Data((file.path + "\u{0}" + String(file.size) + "\u{0}").utf8))
            // Finder's, git's and archivers' files count by their size, times and inode (never read for a brain).
            if file.path.split(separator: "/").contains(where: { isIgnored(String($0)) }) {
                var info = stat()
                guard lstat(folder.appendingPathComponent(file.path).path, &info) == 0 else { return nil }
                hasher.update(data: Data("\(info.st_mtimespec.tv_sec).\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ino)".utf8))
                continue
            }
            guard let data = FileManager.default.contents(atPath: folder.appendingPathComponent(file.path).path) else { return nil }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The file `relative` names inside `folder`, or why not: a plain relative path ("SKILL.md", "references/a.md"),
    /// each step a real folder or, last, a regular file (no link), resolving inside the resolved folder.
    static func resolve(_ relative: String, in folder: URL) -> Result<URL, ArisSkillProblem> {
        let path = relative.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, path.count <= 512, !path.hasPrefix("/"), !path.hasPrefix("~"), !path.contains("\u{0}"), !path.contains("\\") else {
            return .failure(.outside(relative))
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty, !parts.contains(where: { $0 == ".." || $0 == "." || isIgnored($0) }), !ArisSkillText.hasHidden(path) else {
            return .failure(.outside(relative))
        }
        guard let root = realpath(folder.path, nil) else { return .failure(.unreadable(".")) }
        let base = String(cString: root)
        free(root)
        var current = URL(fileURLWithPath: base, isDirectory: true)
        for (index, part) in parts.enumerated() {
            current = current.appendingPathComponent(part)
            var info = stat()
            guard lstat(current.path, &info) == 0 else { return .failure(.unreadable(relative)) }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK { return .failure(.link(relative)) }
            let last = index == parts.count - 1
            guard last ? type == S_IFREG : type == S_IFDIR else { return .failure(.unreadable(relative)) }
        }
        guard let real = realpath(current.path, nil) else { return .failure(.unreadable(relative)) }
        let resolved = String(cString: real)
        free(real)
        guard resolved.hasPrefix(base + "/") else { return .failure(.outside(relative)) }
        return .success(URL(fileURLWithPath: resolved))
    }

    /// A file's bytes (at most `limit`), opened without following a link and checked to be the very file `resolve`
    /// found (the same device and inode: security review M10).
    static func readData(_ relative: String, in folder: URL, limit: Int) -> Result<Data, ArisSkillProblem> {
        switch resolve(relative, in: folder) {
        case .failure(let problem): return .failure(problem)
        case .success(let url):
            var expected = stat()
            guard lstat(url.path, &expected) == 0 else { return .failure(.unreadable(relative)) }
            let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else { return .failure(.link(relative)) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var opened = stat()
            guard fstat(descriptor, &opened) == 0, opened.st_dev == expected.st_dev, opened.st_ino == expected.st_ino,
                  opened.st_mode & S_IFMT == S_IFREG else { return .failure(.unreadable(relative)) }
            return .success((try? handle.read(upToCount: limit)) ?? Data())
        }
    }

    /// Whether bytes are plain UTF-8 text (no NUL, no zip or compiled-Python header): what a script must be to run.
    static func isPlainText(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x50, 0x4B]) { return false }
        if bytes.count == 4, bytes[2] == 0x0D, bytes[3] == 0x0A { return false }
        return !data.contains(0) && String(data: data, encoding: .utf8) != nil
    }

    /// A file's text for a brain: at most `maxRead` bytes (said when cut); a file that isn't text is named, not read.
    static func readText(_ relative: String, in folder: URL) -> Result<String, ArisSkillProblem> {
        switch readData(relative, in: folder, limit: maxRead + 1) {
        case .failure(let problem): return .failure(problem)
        case .success(let data):
            let cut = data.count > maxRead
            let shown = data.prefix(maxRead)
            guard !shown.contains(0), let text = String(data: shown, encoding: .utf8) ?? (cut ? String(data: shown.dropLast(3), encoding: .utf8) : nil) else {
                return .success("(\(relative) is not a text file: \(data.count) bytes)")
            }
            return .success(cut ? text + "\n[cut at \(maxRead / 1_024)KB]" : text)
        }
    }
}
