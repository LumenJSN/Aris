//
//  ArisSkillSandbox.swift
//  aris-agent
//
//  The sandbox-exec profiles the skills feature runs things under (security review I7, M9).
//  - SkillSpector: no network at all (its vulnerability lookup falls back offline), reads only the system, its own
//    runtime and the private copy it scans (and the folders above the copy, the runtime and its scratch folder
//    themselves, which Python and SkillSpector check before they open anything; never what else is in them), writes
//    only its scan's scratch folder.
//  - A skill's script (after the user's yes): it may do what scripts do (the card said so), but never write into the skills
//    folder or the runtime, and never read or write Aris's own folder (~/.config/aris: keys, tokens, memories).
//  Paths go in as parameters (-D), never spliced into the profile text. Pure, so the tests read the profiles.
//

import Foundation

enum ArisSkillSandbox {
    static let tool = "/usr/bin/sandbox-exec"

    static let scanProfile = """
        (version 1)
        (deny default)
        (allow process-fork process-exec signal sysctl-read ipc-posix-shm* ipc-posix-sem iokit-open)
        (allow file-read-metadata)
        (allow file-read*
          (literal "/") (subpath "/System") (subpath "/usr/lib") (subpath "/usr/share") (subpath "/usr/libexec")
          (subpath "/private/etc") (subpath "/private/var/db/timezone") (subpath "/private/var/db/dyld") (subpath "/dev")
          (subpath (param "RUNTIME")) (subpath (param "TARGET")) (subpath (param "WORK"))
          (literal (param "UP0")) (literal (param "UP1")) (literal (param "UP2")) (literal (param "UP3")) (literal (param "UP4"))
          (literal (param "UP5")) (literal (param "UP6")) (literal (param "UP7")) (literal (param "UP8")) (literal (param "UP9"))
          (literal (param "TUP0")) (literal (param "TUP1")) (literal (param "TUP2")) (literal (param "TUP3")) (literal (param "TUP4"))
          (literal (param "TUP5")) (literal (param "TUP6")) (literal (param "TUP7")) (literal (param "TUP8")) (literal (param "TUP9"))
          (literal (param "RUP0")) (literal (param "RUP1")) (literal (param "RUP2")) (literal (param "RUP3")) (literal (param "RUP4"))
          (literal (param "RUP5")) (literal (param "RUP6")) (literal (param "RUP7")) (literal (param "RUP8")) (literal (param "RUP9")))
        (allow file-write* (subpath (param "WORK")) (literal "/dev/null") (literal "/dev/tty"))
        (deny network*)
        """

    /// ANC0…ANC11: every folder above the three, up to the home folder, can't be renamed or replaced either (else a
    /// script could move ~/.config away and read it under another name: re-review N1).
    static let scriptProfile = """
        (version 1)
        (allow default)
        (deny file-write* (subpath (param "SKILLS")) (subpath (param "RUNTIME")))
        (deny file-read* file-write* (subpath (param "CONFIG")))
        (deny file-write*
          (literal (param "ANC0")) (literal (param "ANC1")) (literal (param "ANC2")) (literal (param "ANC3")) (literal (param "ANC4"))
          (literal (param "ANC5")) (literal (param "ANC6")) (literal (param "ANC7")) (literal (param "ANC8")) (literal (param "ANC9"))
          (literal (param "ANC10")) (literal (param "ANC11")))
        """

    /// The script sandbox's parameters: the three places and every folder above them below `home` (unused slots name
    /// the first place again).
    static func scriptParameters(skills: String, runtime: String, config: String, home: String) -> [String: String] {
        var parameters = ["SKILLS": skills, "RUNTIME": runtime, "CONFIG": config]
        let top = real(home)
        var above: [String] = []
        for place in [skills, runtime, config] {
            for folder in ancestors(of: place) where folder.hasPrefix(top + "/") && !above.contains(folder) { above.append(folder) }
        }
        for index in 0..<12 { parameters["ANC\(index)"] = index < above.count ? above[index] : real(skills) }
        return parameters
    }

    /// The real path of the folder holding `path` (which itself may not exist yet), its own name dropped.
    private static func realParent(_ path: String) -> String {
        var probe = (path as NSString).deletingLastPathComponent
        var tail: [String] = []
        while realpath(probe, nil) == nil && probe != "/" && !probe.isEmpty {
            tail.insert((probe as NSString).lastPathComponent, at: 0)
            probe = (probe as NSString).deletingLastPathComponent
        }
        let base = real(probe)
        return ([base == "/" ? "" : base] + tail).joined(separator: "/")
    }

    /// The real path (links resolved: /var is /private/var), as the sandbox compares it.
    static func real(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// The scan's parameters: the runtime, the copy, the scratch folder and the scratch folder's parent folders (SkillSpector
    /// checks they're readable before it writes its report: the folders themselves, never what's in them).
    static func scanParameters(runtime: String, target: String, work: String) -> [String: String] {
        var parameters = ["RUNTIME": runtime, "TARGET": target, "WORK": work]
        for (prefix, path) in [("UP", work), ("TUP", target), ("RUP", runtime)] {
            let found = ancestors(of: path)
            for index in 0..<10 { parameters["\(prefix)\(index)"] = index < found.count ? found[index] : "/" }
        }
        return parameters
    }

    /// The folders above `path` (real paths, nearest first, at most 10).
    static func ancestors(of path: String) -> [String] {
        var found: [String] = []
        var current = realParent(path)
        while current != "/" && !current.isEmpty && found.count < 10 {
            found.append(current)
            current = (current as NSString).deletingLastPathComponent
        }
        return found
    }

    /// sandbox-exec's own words before the program: the profile and its parameters.
    static func arguments(profile: String, parameters: [String: String]) -> [String] {
        ["-p", profile] + parameters.keys.sorted().flatMap { ["-D", "\($0)=\(real(parameters[$0]!))"] }
    }
}
