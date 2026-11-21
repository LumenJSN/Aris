//
//  ArisSkillLink.swift
//  aris-agent
//
//  A GitHub link the user gives for a skill ("이 링크 스킬 추가해줘 https://github.com/…"): which repository, branch and
//  folder it names, the https addresses Aris fetches it from (GitHub's own API and codeload, never git), and which
//  folder of the fetched tree holds the skill. Pure, so the tests run it.
//

import Foundation

struct ArisGitHubSource: Equatable {
    let owner: String
    let repo: String
    let ref: String?
    /// The skill's folder inside the repository ("" for its root).
    let path: String

    var display: String { "github.com/\(owner)/\(repo)" + (path.isEmpty ? "" : "/" + path) }
}

/// What GitHub says about the repository (best effort: the add goes on without it).
struct ArisGitHubMeta: Equatable {
    var stars: Int?
    var license: String?
    var pushedAt: Date?
}

enum ArisSkillLink {
    /// The hosts a fetch may reach or be sent on to (https only).
    static let hosts: Set<String> = ["github.com", "api.github.com", "codeload.github.com"]
    /// The most a tarball download may be.
    /// The repository's tarball as downloaded (GitHub sends the whole repository; only the skill's folder is kept:
    /// extract).
    static let maxDownload = 100 * 1_048_576

    static let notGitHub: ArisSkillWhy = "GitHub 링크만 받을 수 있어요 (https://github.com/…)."

    /// The first GitHub address in what the user said or typed, if any ("github.com/a/b" without https too).
    static func firstLink(in text: String) -> String? {
        guard let range = text.range(of: #"(?i)(https?://)?(www\.)?github\.com/[^\s<>"'`)\]]+"#, options: .regularExpression) else { return nil }
        return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,!?。"))
    }

    /// The link as a source, or why not (https GitHub only; a plain owner/repo, optionally /tree|blob/<ref>/<folder>).
    static func parse(_ raw: String) -> Result<ArisGitHubSource, ArisSkillWhy> {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("http://") { return .failure("https 링크만 받아요.") }
        if !text.lowercased().hasPrefix("https://") { text = "https://" + text }
        guard let url = URL(string: text), url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, url.port == nil,
              let host = url.host?.lowercased(), host == "github.com" || host == "www.github.com" else { return .failure(notGitHub) }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, isSegment(parts[0]), isSegment(parts[1]) else { return .failure(notGitHub) }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard isSegment(repo) else { return .failure(notGitHub) }
        guard parts.count > 2 else { return .success(ArisGitHubSource(owner: parts[0], repo: repo, ref: nil, path: "")) }
        guard parts.count >= 4, parts[2] == "tree" || parts[2] == "blob", isRef(parts[3]) else { return .failure("저장소나 폴더 링크를 주세요.") }
        var folder = Array(parts.dropFirst(4))
        if parts[2] == "blob" {
            guard folder.last == ArisSkillFormat.skillFile else { return .failure("SKILL.md나 스킬 폴더 링크를 주세요.") }
            folder.removeLast()
        }
        let path = folder.joined(separator: "/")
        guard path.isEmpty || ArisSkillArchive.safe(path) == path else { return .failure("링크의 폴더 경로가 이상해요.") }
        return .success(ArisGitHubSource(owner: parts[0], repo: repo, ref: parts[3], path: path))
    }

    private static func isSegment(_ word: String) -> Bool {
        (1...100).contains(word.count) && word != "." && word != ".." && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    private static func isRef(_ word: String) -> Bool {
        (1...200).contains(word.count) && !word.contains("..") && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
    }

    /// The tarball (GitHub's API sends it on to codeload) and the repository's details.
    static func tarballURL(_ source: ArisGitHubSource) -> URL {
        URL(string: "https://api.github.com/repos/\(source.owner)/\(source.repo)/tarball" + (source.ref.map { "/" + $0 } ?? ""))!
    }

    static func metaURL(_ source: ArisGitHubSource) -> URL {
        URL(string: "https://api.github.com/repos/\(source.owner)/\(source.repo)")!
    }

    /// Whether a fetch may go to (or be redirected to) `url`.
    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.user == nil, url.port == nil, let host = url.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    static func meta(_ data: Data) -> ArisGitHubMeta {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ArisGitHubMeta() }
        let formatter = ISO8601DateFormatter()
        return ArisGitHubMeta(stars: object["stargazers_count"] as? Int,
                              license: ((object["license"] as? [String: Any])?["spdx_id"] as? String).flatMap { $0 == "NOASSERTION" ? nil : $0 },
                              pushedAt: (object["pushed_at"] as? String).flatMap(formatter.date(from:)))
    }

    /// The skill's files from the tree: the linked folder's, or the one folder holding a SKILL.md (the root first).
    static func locate(_ entries: [ArisArchiveEntry], path: String) -> Result<[ArisArchiveEntry], ArisSkillWhy> {
        folder(of: entries.map(\.path), path: path).map { folder in
            entries.compactMap { entry in relative(entry.path, to: folder).map { ArisArchiveEntry(path: $0, data: entry.data) } }
        }
    }

    /// The skill's folder among a tree's file paths: the linked folder, or the one folder holding a SKILL.md (the root
    /// first; "" is the root).
    static func folder(of paths: [String], path: String) -> Result<String, ArisSkillWhy> {
        if !path.isEmpty || paths.contains(ArisSkillFormat.skillFile) {
            return paths.contains(path.isEmpty ? ArisSkillFormat.skillFile : path + "/" + ArisSkillFormat.skillFile) ? .success(path) : .failure("그 폴더에 SKILL.md가 없어요.")
        }
        let folders = paths.filter { $0.hasSuffix("/" + ArisSkillFormat.skillFile) }
            .map { String($0.dropLast(ArisSkillFormat.skillFile.count + 1)) }
            .filter { $0.split(separator: "/").count <= 3 }
        switch folders.count {
        case 0: return .failure("이 저장소에는 SKILL.md가 없어요.")
        case 1: return .success(folders[0])
        default:
            let names = folders.prefix(4).map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: ", ")
            return .failure("스킬이 여러 개 있어요 (\(names)…). 링크에 스킬 폴더까지 넣어 주세요.")
        }
    }

    /// `path` inside `folder` ("" is the root), relative to it; nil when it is outside.
    static func relative(_ path: String, to folder: String) -> String? {
        folder.isEmpty ? path : path.hasPrefix(folder + "/") ? String(path.dropFirst(folder.count + 1)) : nil
    }

    /// The skill's files from a repository's tarball, read for its folder only: the tarball is read twice as it
    /// streams (never held inflated), first for the names, then for the folder's files. Only that folder's files count
    /// toward ArisSkillArchive's size and count limits and are checked for links, devices and odd paths; the rest of
    /// the repository is never kept or written (a big repository with one small skill folder is fine; the whole
    /// repository is a skill only when its root has the SKILL.md).
    static func extract(_ tarball: Data, path: String) -> Result<[ArisArchiveEntry], ArisSkillWhy> {
        var listed: [ArisSkillArchive.Listed] = []
        if let problem = ArisSkillArchive.scan(tarball, visit: { listed.append($0); return false }, body: { _, _ in nil }) {
            return .failure(ArisSkillWhy(problem.message))
        }
        let isFile: (UInt8) -> Bool = { $0 == 0 || $0 == UInt8(ascii: "0") || $0 == UInt8(ascii: "7") }
        func parts(_ name: String) -> [String] { name.split(separator: "/", omittingEmptySubsequences: true).map(String.init) }
        // GitHub wraps everything in "<owner>-<repo>-<sha>/": taken off when every file shares one top folder.
        let files = listed.filter { isFile($0.type) }
        let tops = Set(files.map { parts($0.name).first ?? "" })
        let strip = tops.count == 1 && files.allSatisfy { parts($0.name).count > 1 }
        func inner(_ name: String) -> String { (strip ? Array(parts(name).dropFirst()) : parts(name)).joined(separator: "/") }
        func ignored(_ path: String) -> Bool { path.split(separator: "/").contains { ArisSkillFolder.isIgnored(String($0)) } }
        let folder: String
        switch self.folder(of: files.map { inner($0.name) }.filter { !ignored($0) }, path: path) {
        case .failure(let why): return .failure(why)
        case .success(let found): folder = found
        }
        // The folder's own entries: each one plain and safe, and all of them within the limits.
        var count = 0, bytes = 0
        for entry in listed where entry.type != UInt8(ascii: "5") && entry.type != UInt8(ascii: "g") {
            let name = inner(entry.name)
            guard relative(name, to: folder) != nil, !ignored(name) else { continue }
            if entry.type == UInt8(ascii: "1") || entry.type == UInt8(ascii: "2") { return .failure(ArisSkillWhy(ArisArchiveProblem.link(entry.name).message)) }
            guard isFile(entry.type), ArisSkillArchive.safe(entry.name) != nil else { return .failure(ArisSkillWhy(ArisArchiveProblem.unsafePath(entry.name).message)) }
            count += 1
            bytes += entry.size
            if count > ArisSkillArchive.maxEntries { return .failure(ArisSkillWhy(ArisArchiveProblem.tooMany.message)) }
            if bytes > ArisSkillArchive.maxInflated { return .failure(ArisSkillWhy(ArisArchiveProblem.tooBig.message)) }
        }
        var found: [ArisArchiveEntry] = []
        let problem = ArisSkillArchive.scan(tarball, visit: { entry in
            let name = inner(entry.name)
            return isFile(entry.type) && !ignored(name) && relative(name, to: folder) != nil && ArisSkillArchive.safe(entry.name) != nil
        }, body: { entry, data in
            guard let path = relative(inner(entry.name), to: folder), !path.isEmpty else { return nil }
            found.append(ArisArchiveEntry(path: path, data: data))
            return found.count > ArisSkillArchive.maxEntries ? .tooMany : nil
        })
        if let problem { return .failure(ArisSkillWhy(problem.message)) }
        return found.contains { $0.path == ArisSkillFormat.skillFile } ? .success(found) : .failure("그 폴더에 SKILL.md가 없어요.")
    }
}
