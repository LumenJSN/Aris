//
//  ArisNoStore.swift
//  Shared (app, aris-agent, aris-tools, tests)
//
//  The one way Aris talks over the network (tenth VM run, item 1: the app's request to the helper that saves an API
//  key, body and all, was found in the app's HTTP cache on disk, Cache.db-wal, and "Clear" in Saved keys left it
//  there). Every request to the helper and to a provider (keys, tokens, prompts, audio) goes through a session that
//  keeps nothing: no URL cache, no cookie storage, no credential storage. `URLSession.shared` and a default or bare
//  ephemeral configuration are not used anywhere else (tests/no-store-lint.py holds that). The cache files an earlier
//  build wrote are removed once at launch (`purge`). Foundation only.
//

import Foundation

enum ArisNoStore {
    /// A configuration that writes nothing down and remembers nothing between requests. Callers may set timeouts and
    /// headers on it, never a cache, a cookie store or a credential store.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        return configuration
    }

    /// The process's one session for data, upload, stream and WebSocket tasks.
    static let session = URLSession(configuration: configuration())

    /// The files Foundation's shared URL cache keeps for a bundle, inside its caches folder.
    static let cacheFiles = ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"]

    /// Removes the HTTP cache an earlier build wrote for `bundle` under `caches` (the database, its write-ahead log and
    /// shared memory file, and the folder of larger bodies). Returns how many of them were there and are gone; one
    /// that can't be removed is emptied instead (a truncated file holds nothing) and counted only when that worked.
    @discardableResult
    static func purge(caches: URL, bundle: String, files: FileManager = .default) -> Int {
        guard !bundle.isEmpty, !bundle.contains("/"), bundle != ".", bundle != ".." else { return 0 }
        let folder = caches.appendingPathComponent(bundle, isDirectory: true)
        var removed = 0
        for name in cacheFiles {
            let item = folder.appendingPathComponent(name)
            // The item itself, never what a link there points at.
            guard (try? files.attributesOfItem(atPath: item.path)) != nil else { continue }
            if (try? files.removeItem(at: item)) != nil {
                removed += 1
            } else if (try? Data().write(to: item)) != nil {
                removed += 1
            }
        }
        return removed
    }
}
