//
//  ArisBuildInfo.swift
//  Aris
//
//  Which commit this program was built from, so a deploy that replaced the app but not the agent (or the other way
//  round) can be seen instead of guessed: `aris-tools --version` prints it, aris-agent writes it down when it starts,
//  and the app compares that with its own and says so in its log when they differ.
//

import Foundation

enum ArisBuildInfo {
    /// What a build with no stamp says (one made in Xcode or by hand, not by deploy.sh).
    static let unstamped = "dev"
    /// The app's Info.plist key; deploy.sh fills it through the ARIS_COMMIT build setting.
    static let plistKey = "ArisCommit"
    /// Where the running agent writes its commit, in ~/.config/aris/aris (the app may read that folder).
    static let runningAgentFile = "agent-build"

    /// This program's commit.
    static var commit: String {
        commit(plist: Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, marked: ArisBuildStamp.marked)
    }

    /// The Info.plist value when it is a commit (the app), else the compiled-in stamp after its marker (agent and
    /// tools), else "dev". Only letters, digits, dots and dashes count as a commit, so nothing else is ever repeated.
    static func commit(plist: String?, marked: String) -> String {
        let stamped = marked.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first.map(String.init)
        return [plist, stamped].compactMap { clean($0) }.first ?? unstamped
    }

    static func versionLine(program: String, commit: String = commit) -> String {
        "\(program) \(commit)"
    }

    /// The build as Settings › 정보 shows it inside "버전 0.1.0 (…)": the bundle's build number, then the commit
    /// ("1 · 13758537"; "1 · dev" for a build with no stamp), so a report can say exactly which build it is about.
    static func buildDetail(number: String?, commit: String = commit) -> String {
        "\(number ?? "?") · \(commit)"
    }

    /// A sentence for the log when the app and the agent that answers it come from different commits; nil when they
    /// match, or when this app has no stamp to compare (a build made in Xcode).
    static func mismatch(app: String, agent: String?) -> String? {
        guard app != unstamped else { return nil }
        guard let agent else {
            return "the app is build \(app) but the running helper has no build stamp (an older one?): restarting it from this app"
        }
        guard agent != app else { return nil }
        return "the app is build \(app) but the running helper is build \(agent): restarting it from this app"
    }

    /// aris-agent at start: its commit into `folder` (0600, replaced whole) and a line in agent.log (`say`). False
    /// when the file could not be written; the agent runs on either way.
    @discardableResult
    static func recordRunningAgent(in folder: URL, commit: String = commit,
                                   say: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }) -> Bool {
        say("aris-agent: build \(commit)\n")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent(runningAgentFile)
        let beside = folder.appendingPathComponent(".\(runningAgentFile)-\(getpid()).tmp")
        guard FileManager.default.createFile(atPath: beside.path, contents: Data("\(commit)\n".utf8), attributes: [.posixPermissions: 0o600]),
              rename(beside.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: beside)
            return false
        }
        return true
    }

    /// The commit the running agent wrote; nil when there is no record or it is not a commit.
    static func runningAgent(in folder: URL) -> String? {
        let file = folder.appendingPathComponent(runningAgentFile)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue, size <= 200,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return clean(text)
    }

    /// A commit as it may be shown: trimmed, 1 to 64 letters, digits, dots, dashes or underscores.
    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), (1...64).contains(trimmed.utf8.count),
              trimmed.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) })
        else { return nil }
        return trimmed
    }
}
