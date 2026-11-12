//
//  ArisFileIcons.swift
//  Aris
//
//  A file's or an app's icon, asked of the system once and kept while the app runs. The composer's file chips, the
//  clipboard list and the shelf's tiles draw one icon per row, and a SwiftUI body is evaluated again and again: each
//  evaluation used to ask NSWorkspace (and, for an app, Launch Services for where the app is) on the main thread,
//  row by row. Now the first drawing of a path asks, and every later one reads the kept image.
//

import AppKit

enum ArisFileIcons {
    /// How many icons are kept (the oldest go first).
    static let kept = 300

    nonisolated(unsafe) private static let files: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = kept
        return cache
    }()
    nonisolated(unsafe) private static let apps: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = kept
        return cache
    }()

    /// The icon of the file at `path`. `lookup`: how the system is asked (the tests' own).
    static func icon(forFile path: String, lookup: (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) -> NSImage {
        if let known = files.object(forKey: path as NSString) { return known }
        let icon = lookup(path)
        files.setObject(icon, forKey: path as NSString)
        return icon
    }

    /// The icon of the app with that bundle id; nil when it is not on this Mac. Where the app is, is kept too (an
    /// app that was not found is asked for again next time: it may have been installed since).
    static func icon(forApp bundle: String, locate: (String) -> String? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)?.path },
                     lookup: (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }) -> NSImage? {
        let path: String
        if let known = apps.object(forKey: bundle as NSString) {
            path = known as String
        } else {
            guard let found = locate(bundle) else { return nil }
            apps.setObject(found as NSString, forKey: bundle as NSString)
            path = found
        }
        return icon(forFile: path, lookup: lookup)
    }
}
