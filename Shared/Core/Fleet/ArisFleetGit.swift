//
//  ArisFleetGit.swift
//  Shared/Core (aris-agent, tests)
//
//  A session's git branch from its repository's HEAD file, read only (never git itself): "ref: refs/heads/<name>" is
//  that branch, a bare commit is "detached <short>". A worktree's `.git` is a file naming its git folder. Pure.
//

import Foundation

enum ArisFleetGit {
    static func branch(head: String) -> String? {
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("ref: refs/heads/") {
            let name = String(line.dropFirst("ref: refs/heads/".count))
            return name.isEmpty || name.count > 200 ? nil : name
        }
        if line.range(of: "^[0-9a-f]{40,64}$", options: .regularExpression) != nil { return "detached " + line.prefix(7) }
        return nil
    }

    /// The git folder a worktree's `.git` file names ("gitdir: <path>"), made absolute against the folder holding it.
    static func gitdir(file: String, in folder: String) -> String? {
        let line = file.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("gitdir: ") else { return nil }
        let path = String(line.dropFirst("gitdir: ".count))
        return ((path.hasPrefix("/") ? path : folder + "/" + path) as NSString).standardizingPath
    }

    /// The branch of the repository holding `folder` (its own or one up to six parents up); `read` gives a file's text.
    static func branch(of folder: String, read: (String) -> String?, isFolder: (String) -> Bool) -> String? {
        var current = (folder as NSString).standardizingPath
        for _ in 0..<7 {
            let dotGit = current + "/.git"
            if isFolder(dotGit) { return read(dotGit + "/HEAD").flatMap(branch(head:)) }
            if let file = read(dotGit), let dir = gitdir(file: file, in: current) { return read(dir + "/HEAD").flatMap(branch(head:)) }
            let parent = (current as NSString).deletingLastPathComponent
            guard parent != current, !parent.isEmpty, parent != "/" else { return nil }
            current = parent
        }
        return nil
    }
}
