//
//  ArisUninstallQuiet.swift
//  aris-agent
//
//  From the moment an uninstall has put the app in the Trash, this helper stops writing where the uninstall removes
//  things: it never puts the aris-tools link back, and when the records go (~/.config/aris whole) it writes nothing
//  there again: no actions.log line, no children.json. An audit line written then goes nowhere: nothing of its content
//  reaches the system log, which other processes read and which outlives the uninstall; only a fixed marker with a
//  count says lines were dropped (security review of vmfix3). The folder's removal used to fail while those were still being
//  written, and what was written after it brought the folder back (VM run 2026-11-19: "uninstall folder failed", then
//  the link, actions.log and children.json there again after the bootout).
//

import Foundation
import os

enum ArisUninstallQuiet {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var linkFrozen = false
    nonisolated(unsafe) private static var folderFrozen = false
    nonisolated(unsafe) private static var dropped = 0
    /// Where the marker goes: the unified log (a test's recorder in the tests). It is given a count, never a line.
    nonisolated(unsafe) static var marker: (Int) -> Void = { count in
        Logger(subsystem: "com.lumenjsn.aris.agent", category: "data").notice("audit line dropped during uninstall (\(count, privacy: .public))")
    }

    /// The uninstall began: the link is never repaired again; nothing more is written in ~/.config/aris when
    /// `removingFolder` (the records go too).
    static func begin(removingFolder: Bool) {
        lock.withLock {
            linkFrozen = true
            folderFrozen = folderFrozen || removingFolder
        }
    }

    /// The aris-tools link is left as the uninstall leaves it.
    static var linkIsFrozen: Bool { lock.withLock { linkFrozen } }

    /// Nothing is written in ~/.config/aris any more.
    static var folderIsFrozen: Bool { lock.withLock { folderFrozen } }

    /// Back to writing: only for a test that began one (a real uninstall ends with this helper).
    static func endForTests() {
        lock.withLock {
            linkFrozen = false
            folderFrozen = false
            dropped = 0
        }
    }

    /// An audit line written once the folder is frozen: dropped, its content written nowhere; the marker counts it.
    static func drop(_ line: String) {
        let count = lock.withLock { () -> Int in
            dropped += 1
            return dropped
        }
        marker(count)
    }
}
