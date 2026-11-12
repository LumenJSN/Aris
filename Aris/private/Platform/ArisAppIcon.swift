//
//  ArisAppIcon.swift
//  Aris
//
//  An app's icon from its bundle id (the music strip shows the source app's icon when there's no artwork). Helper
//  processes (a browser's web content, "…helper…") are mapped to their app first.
//

import AppKit

enum ArisAppIcon {
    /// The app a (possibly helper-process) bundle id belongs to.
    static func normalized(_ bundleID: String) -> String {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.safaritechnologypreview.") { return "com.apple.SafariTechnologyPreview" }
        if lower.hasPrefix("com.apple.webkit.") || lower.hasPrefix("com.apple.safari.") { return "com.apple.Safari" }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        if let helper = parts.firstIndex(where: { $0.lowercased() == "helper" }), helper > 0 {
            return parts[..<helper].joined(separator: ".")
        }
        return id
    }

    /// A running app picked for an id: regular (Dock) apps first, then the lowest pid.
    struct RunningApp {
        let bundleID: String?
        let bundleURL: URL?
        let isRegular: Bool
        let isTerminated: Bool
        let pid: pid_t
    }

    static func pick(_ apps: [RunningApp], for bundleID: String) -> URL? {
        apps.filter { !$0.isTerminated && $0.bundleURL != nil && $0.bundleID.map(normalized) == bundleID }
            .sorted { ($0.isRegular ? 0 : 1, $0.pid) < ($1.isRegular ? 0 : 1, $1.pid) }
            .first?.bundleURL
    }

    /// Where the app is: the system's registered copy, else a running one.
    static func url(for bundleID: String) -> URL? {
        let id = normalized(bundleID)
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
        let running = NSWorkspace.shared.runningApplications.map {
            RunningApp(bundleID: $0.bundleIdentifier, bundleURL: $0.bundleURL, isRegular: $0.activationPolicy == .regular,
                       isTerminated: $0.isTerminated, pid: $0.processIdentifier)
        }
        return pick(running, for: id)
    }

    /// The size the icon is drawn at when it stands in for album art.
    static let artworkSize = NSSize(width: 256, height: 256)

    /// The app's icon, nil when the app can't be found.
    static func icon(for bundleID: String) -> NSImage? {
        url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// The icon as album art (256 × 256); nil when the app can't be found, so the artwork placeholder shows.
    static func artwork(for bundleID: String) -> NSImage? {
        guard let icon = icon(for: bundleID), let copy = icon.copy() as? NSImage else { return nil }
        copy.size = artworkSize
        return copy
    }
}

func appIconAsNSImage(for bundleID: String) -> NSImage? {
    ArisAppIcon.artwork(for: bundleID)
}
