//
//  ArisHelperCaches.swift
//  aris-agent
//
//  The HTTP caches the helper and aris-tools could have written before every request went through ArisNoStore (tenth
//  VM run, item 1): a program with no bundle caches under ~/Library/Caches/<its name>, one inside Aris.app may cache
//  under a bundle id. Requests they made carried the hook token, and the usage fetch a sign-in token. The folders are
//  named here, never searched for.
//

import Foundation

enum ArisHelperCaches {
    static let names = ["aris-agent", "aris-tools", "com.lumenjsn.aris.agent", "com.lumenjsn.aris.tools"]

    /// Removes those caches' files under `home`/Library/Caches; how many were there and are gone.
    static func purge(home: URL) -> Int {
        let caches = home.appendingPathComponent("Library/Caches", isDirectory: true)
        return names.reduce(0) { $0 + ArisNoStore.purge(caches: caches, bundle: $1) }
    }
}
