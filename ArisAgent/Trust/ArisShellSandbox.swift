//
//  ArisShellSandbox.swift
//  aris-agent
//
//  Every shell.run child (Core 2) runs under this sandbox-exec profile, so the never-list's places hold even when the
//  words of a command fooled the text check (ArisNeverList.shellReach): no read or write of Aris's own folder (keys,
//  token, journals, the record, the trust settings; its work folder excepted), its LaunchAgent, the keychains, or the
//  credential folders of the brains and tools (ArisNeverList.credentialPlaces); no write into Aris's app; and the
//  folders above those places can't be renamed or replaced (else a command could move ~/.config away and read it under
//  another name, as the skills sandbox guards: ArisSkillSandbox). Paths go in as parameters (-D), never into the text.
//  jv-hands' executor calls `command(_:cwd:home:)` and runs what it returns.
//

import Darwin
import Foundation

enum ArisShellSandbox {
    static let tool = ArisSkillSandbox.tool
    static let shell = "/bin/zsh"

    /// The places no shell line reads or writes, relative to home: Aris's own (O…) and the credential stores (C…).
    static var ownRelative: [String] { ArisNeverList.ownPlaces }
    static var credentialRelative: [String] { ArisNeverList.credentialPlaces }
    static var deniedRelative: [String] { ownRelative + credentialRelative }

    /// In SBPL the last rule that matches wins, so the order is the protection: Aris's own folder denied, then its work
    /// folder (inside it) allowed, then every credential store denied after that allow, so no path the allow covers (a
    /// link in the work folder, the work folder replaced by one) ever reaches a credential; the sandbox matches the
    /// real path an operation lands on. Last, no writes into the app or renames of the folders above.
    static var profile: String {
        let own = (0..<ownRelative.count).map { "(subpath (param \"O\($0)\"))" }.joined(separator: " ")
        let credentials = (0..<credentialRelative.count).map { "(subpath (param \"C\($0)\"))" }.joined(separator: " ")
        let above = (0..<12).map { "(literal (param \"ANC\($0)\"))" }.joined(separator: " ")
        return """
        (version 1)
        (allow default)
        (deny file-read* file-write* \(own) (literal (param "AGENT")))
        (allow file-read* file-write* (subpath (param "WORK")))
        (deny file-read* file-write* \(credentials) (subpath (param "SYSKEYS")))
        (deny file-write* (subpath (param "APP")) \(above))
        """
    }

    /// Where the work folder must be: the literal name `work` under Aris's own folder resolved (never the work folder
    /// itself resolved: a link there would carry the allow elsewhere).
    static func workPath(home: String) -> String {
        real(home + "/" + (ArisNeverList.ownWorkFolder as NSString).deletingLastPathComponent) + "/" + (ArisNeverList.ownWorkFolder as NSString).lastPathComponent
    }

    /// A work folder that isn't a real folder (a link, a file) is removed and made again, 0700. The path the profile
    /// allows, or nil when it can't be a safe one (not under Aris's own folder, or holding or inside a credential place).
    @discardableResult
    static func prepareWork(home: String) -> String? {
        let work = workPath(home: home)
        var info = stat()
        if lstat(work, &info) == 0, info.st_mode & S_IFMT != S_IFDIR {
            guard unlink(work) == 0 else { return nil }
        }
        guard ArisPrivateFile.prepareFolder(URL(fileURLWithPath: work)), lstat(work, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { return nil }
        return safeWork(work, home: home) ? work : nil
    }

    /// The work path is under Aris's own folder, and no credential place is it, holds it or lies inside it.
    static func safeWork(_ work: String, home: String) -> Bool {
        let own = real(home + "/" + ArisNeverList.ownPlaces[0])
        guard work.hasPrefix(own + "/"), !work.contains("/../"), !work.hasSuffix("/..") else { return false }
        let credentials = credentialRelative.map { real(home + "/" + $0) } + ArisNeverList.credentialAbsolute
        return !credentials.contains { work == $0 || work.hasPrefix($0 + "/") || $0.hasPrefix(work + "/") }
    }

    /// Where the allow points when the work folder can't be made safe: a place that doesn't exist.
    static let noWork = "/var/empty/aris-no-work"

    /// The parameters for `home`: each denied place, Aris's work folder (`work`: prepareWork's answer), the app, and
    /// every folder above a denied place below home (unused slots name the first place again).
    static func parameters(home: String, work: String?) -> [String: String] {
        var parameters: [String: String] = [:]
        let places = deniedRelative.map { home + "/" + $0 }
        // Every place by its real path, also before it exists (a folder made later is still under a real parent).
        for (index, place) in ownRelative.enumerated() { parameters["O\(index)"] = real(home + "/" + place) }
        for (index, place) in credentialRelative.enumerated() { parameters["C\(index)"] = real(home + "/" + place) }
        parameters["SYSKEYS"] = "/Library/Keychains"
        parameters["AGENT"] = real(home + "/Library/LaunchAgents/com.lumenjsn.aris.agent.plist")
        parameters["WORK"] = work.flatMap { safeWork($0, home: home) ? $0 : nil } ?? noWork
        parameters["APP"] = ArisNeverList.ownAbsolute[0]
        let top = real(home)
        var above: [String] = []
        for place in places {
            // Real paths as the sandbox compares them (never standardized: that turns /private/var into /var).
            var folder = real((place as NSString).deletingLastPathComponent)
            while folder.hasPrefix(top + "/") {
                if !above.contains(folder) { above.append(folder) }
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        for index in 0..<12 { parameters["ANC\(index)"] = index < above.count ? above[index] : real(places[0]) }
        return parameters
    }

    /// The real path of `path`, also when it doesn't exist yet: its nearest existing folder resolved, the rest kept.
    static func real(_ path: String) -> String {
        var probe = path
        var tail: [String] = []
        while realpath(probe, nil) == nil && probe != "/" && !probe.isEmpty {
            tail.insert((probe as NSString).lastPathComponent, at: 0)
            probe = (probe as NSString).deletingLastPathComponent
        }
        let base = ArisSkillSandbox.real(probe)
        return tail.isEmpty ? base : ([base == "/" ? "" : base] + tail).joined(separator: "/")
    }

    /// The program and arguments that run `line` in `cwd` under the profile (cwd is set by the caller's Process).
    static func command(_ line: String, home: String) -> (executable: String, arguments: [String]) {
        let parameters = parameters(home: home, work: prepareWork(home: home))
        // The parameters go in as they are: real paths already, the work folder's last part literal (ArisSkillSandbox's
        // own `arguments` would resolve it, and a link there would carry the allow elsewhere).
        let words = ["-p", profile] + parameters.keys.sorted().flatMap { ["-D", "\($0)=\(parameters[$0]!)"] }
        return (tool, words + [shell, "-f", "-c", line])
    }
}
