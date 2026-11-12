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
    static let maxDownload = 20 * 1_048_576

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
        func inside(_ folder: String) -> [ArisArchiveEntry] {
            folder.isEmpty ? entries : entries.compactMap { entry in
                entry.path.hasPrefix(folder + "/") ? ArisArchiveEntry(path: String(entry.path.dropFirst(folder.count + 1)), data: entry.data) : nil
            }
        }
        if !path.isEmpty || entries.contains(where: { $0.path == ArisSkillFormat.skillFile }) {
            let found = inside(path)
            return found.contains { $0.path == ArisSkillFormat.skillFile } ? .success(found) : .failure("그 폴더에 SKILL.md가 없어요.")
        }
        let folders = entries.filter { $0.path.hasSuffix("/" + ArisSkillFormat.skillFile) }
            .map { String($0.path.dropLast(ArisSkillFormat.skillFile.count + 1)) }
            .filter { $0.split(separator: "/").count <= 3 }
        switch folders.count {
        case 0: return .failure("이 저장소에는 SKILL.md가 없어요.")
        case 1: return .success(inside(folders[0]))
        default:
            let names = folders.prefix(4).map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: ", ")
            return .failure("스킬이 여러 개 있어요 (\(names)…). 링크에 스킬 폴더까지 넣어 주세요.")
        }
    }
}
