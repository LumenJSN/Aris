//
//  ArisHelperListing.swift
//  aris-agent, aris-tools
//
//  How macOS lists aris-agent and aris-tools once they touch AppKit. Both sit in Aris.app/Contents/MacOS, so macOS
//  takes the app's Info.plist as theirs: the first time one of them asks for the screens or puts an app in front
//  (measured on this Mac: NSScreen.screens, NSApplication.shared and NSRunningApplication.activate do it; looking up
//  running apps, the clipboard's count, window lists and Accessibility do not), LaunchServices lists it as a second
//  "Aris" with the app's bundle id, com.lumenjsn.aris. A quit sent to that id or that name could then reach the
//  helper, which has no quit to run: `tell application id "com.lumenjsn.aris" to quit` failed with -600 while the app
//  was running, and a deploy fell through to its forced kill (VM fourth re-check, #4).
//  So each program, first thing, gives itself its own id and name in the copy of the app's Info.plist it holds in
//  memory (com.lumenjsn.aris.agent, "aris-agent"): a listing then never answers for the app. Nothing on disk changes
//  (the app's file, the signatures, what macOS charges the helper for: still the app's one row per permission), and
//  the program's defaults stay the app's, read once before the id changes.
//

import Foundation

enum ArisHelperListing {
    /// The app's id as it stands in Aris.app's Info.plist.
    static let appId = "com.lumenjsn.aris"

    /// What a program changes in its main bundle's info before it touches AppKit: its own id and name, when it is not
    /// its bundle's own program (aris-agent or aris-tools inside the app). Nil for the app itself, for a loose copy (a
    /// developer's build, whose main bundle is no app) and when the change was already made.
    static func changes(info: [String: Any], program: String) -> [String: String]? {
        let name = (program as NSString).lastPathComponent
        guard !name.isEmpty, let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
              let executable = info["CFBundleExecutable"] as? String, executable != name else { return nil }
        let own = "\(id).\(suffix(of: name))"
        guard !id.hasSuffix(".\(suffix(of: name))") else { return nil }
        return ["CFBundleIdentifier": own, "CFBundleName": name, "CFBundleDisplayName": name]
    }

    /// "aris-agent" -> "agent"; any other name as it is, made of what a bundle id may hold.
    static func suffix(of name: String) -> String {
        let short = name.hasPrefix("aris-") ? String(name.dropFirst("aris-".count)) : name
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let kept = String(short.map { allowed.contains($0) ? $0 : "-" })
        return kept.isEmpty ? "helper" : kept
    }

    /// The changes made to `info` (the main bundle's dictionary, which CFBundle keeps mutable).
    static func apply(_ changes: [String: String], to info: NSMutableDictionary) {
        for (key, value) in changes { info[key] = value }
    }

    /// Called first thing by aris-agent and aris-tools, before any AppKit use.
    static func settle(program: String? = ownProgram()) {
        guard let program, let main = CFBundleGetMainBundle(), let raw = CFBundleGetInfoDictionary(main),
              let info = (raw as NSDictionary) as? [String: Any], let changes = changes(info: info, program: program) else { return }
        // The defaults domain is worked out from the id the first time it is asked: asked here, it stays the app's.
        _ = UserDefaults.standard.object(forKey: "arisHelperListing")
        apply(changes, to: unsafeBitCast(raw, to: NSMutableDictionary.self))
    }

    /// This process's program as the kernel has it.
    static func ownProgram() -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
