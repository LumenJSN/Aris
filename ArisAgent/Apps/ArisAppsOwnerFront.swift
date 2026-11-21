//
//  ArisAppsOwnerFront.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  Which app the owner has in front, never Aris: the app with the keyboard when it isn't Aris, else the app he was in
//  last. Sixth VM run, item 4: a replay brought TextEdit forward to press Edit › Select All and left it there. The app
//  in front at that press was Aris itself (he had just clicked its card), and Aris is never put back in front, so the
//  earlier fix (82a72bf3) put nothing back and Finder, the app he had, stayed behind. Every app that comes to the front
//  is noted here, Aris's own left out, so the app to go back to is his.
//

import AppKit

final class ArisAppsOwnerFront: @unchecked Sendable {
    static let shared = ArisAppsOwnerFront()

    private let lock = NSLock()
    private var lastPid: pid_t?
    private var token: NSObjectProtocol?

    /// Starts noting the apps that come to the front (once); the one in front now is the first.
    func start() {
        let first = lock.withLock { () -> Bool in
            guard token == nil else { return false }
            token = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.note(app)
            }
            return true
        }
        if first, let front = NSWorkspace.shared.frontmostApplication { note(front) }
    }

    private func note(_ app: NSRunningApplication) {
        guard let bundle = app.bundleIdentifier, !ArisAppsHands.isAris(bundle) else { return }
        lock.withLock { lastPid = app.processIdentifier }
    }

    /// The app he was in last that is still running, never Aris.
    func last() -> ArisAppsRunning? {
        guard let pid = lock.withLock({ lastPid }), let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated,
              let bundle = app.bundleIdentifier, !ArisAppsHands.isAris(bundle) else { return nil }
        return ArisAppsRunning(bundle: bundle, name: app.localizedName ?? bundle, pid: pid, hidden: app.isHidden, active: app.isActive)
    }
}

extension ArisAppsLiveSystem {
    func ownerFront() -> ArisAppsRunning? {
        if let front = frontmost(), !ArisAppsHands.isAris(front.bundle) { return front }
        return ArisAppsOwnerFront.shared.last()
    }
}
