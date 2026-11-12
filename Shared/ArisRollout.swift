//
//  ArisRollout.swift
//  Aris (the app, the XPC helper, aris-agent and aris-tools)
//
//  One switch for everything the fourth security review added that can refuse, hold back or replace something a
//  working Aris does today: the helper's own yes for a tool (M2), who is charged read from a signature (M3), the
//  bundle's seal (M1), the app known by its signature (M5), an AI program that changed (H1), a tools link that can't be
//  put right (H1), and the installer's new refusals and its replacing of a job it does not know (M7, L2, L5).
//
//  While `enforcing` is false each of them is worked out exactly as it will be, and where it would have refused it
//  writes one line that begins "would refuse" and lets the proven rule of the release before (commit 43428e42, run in
//  the VM) decide instead. Nothing that was refused before is let through by this. It is set to true once a VM run has
//  shown every chain Aris really makes passing with no such line.
//

import Foundation
import os

//  The run that decides the switch: while `enforcing` is false a tool gathers only what the proven rule reads and
//  works out the new rule's verdict afterwards, off its path, so a tool that ends within a few milliseconds writes no
//  line at all, and "no would-refuse line" proves nothing for it (security review 6, L2). For that run, turn the
//  rollout audit on:
//
//      defaults write com.lumenjsn.aris.rollout audit -bool true      (off again: defaults delete com.lumenjsn.aris.rollout audit)
//
//  With it on, aris-tools and aris-agent's helper modes gather everything before they run (a start then costs what
//  the new checks cost), the second look of a waiting tool does too, and each start writes one line that begins
//  "evaluated", saying whether the new rule agrees. It changes no decision: the proven rule still decides. The key is
//  read once per process, from the preference's own file (give `defaults write` a second to reach the disk); a helper
//  mode already running keeps what it read. Off by default.
//

enum ArisRollout {
    static let enforcing = false

    /// The rollout audit's preference: its own domain, read by aris-tools and aris-agent (neither is sandboxed).
    static let auditDomain = "com.lumenjsn.aris.rollout"
    static let auditKey = "audit"

    /// The preference as it is on disk, in the account's own Library (never the environment's HOME): one small file
    /// read, with no question to the preferences daemon, since a tool asks at every start. `defaults write` puts it
    /// there within a moment.
    static func stored(_ key: String, _ domain: String) -> Any? {
        guard let home = getpwuid(getuid()).flatMap({ String(validatingCString: $0.pointee.pw_dir) }), home.hasPrefix("/") else { return nil }
        return NSDictionary(contentsOfFile: "\(home)/Library/Preferences/\(domain).plist")?[key]
    }

    /// Whether the rollout audit is on. Only a plain `true` turns it on.
    static func auditing(read: (String, String) -> Any? = stored) -> Bool {
        guard let value = read(auditKey, auditDomain) as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return value.boolValue
    }

    /// Read once per process.
    static let isAuditing = auditing()

    /// The audit's line for one start (or one second look): written whether the new rule agrees or not.
    static func evaluated(_ what: String) {
        log.notice("evaluated: \(what, privacy: .public)")
    }

    private static let log = Logger(subsystem: "com.lumenjsn.aris", category: "rollout")

    /// The line for something a new check would have refused, in the system log (`log show --predicate 'subsystem ==
    /// "com.lumenjsn.aris" AND category == "rollout"'`), where it never mixes with what a tool prints for an AI.
    static func wouldRefuse(_ what: String) {
        log.notice("would refuse: \(what, privacy: .public)")
    }
}
