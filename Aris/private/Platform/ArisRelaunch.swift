//
//  ArisRelaunch.swift
//  Aris
//
//  Restarting Aris: start a fresh copy of the app, and only once that copy is on its way, quit this one.
//  If the new copy can't be started, Aris logs it and keeps running. The copy started is the one that is running:
//  with several builds on disk, the system's pick for the bundle id is often another one.
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "app")

/// The relaunch steps with the system calls passed in, so they can be checked without quitting anything.
struct ArisRelauncher {
    var open: (URL, NSWorkspace.OpenConfiguration, @escaping (Bool) -> Void) -> Void
    var noteChange: (URL) -> Void
    var terminate: () -> Void

    func relaunch(at app: URL?, beforeTerminate: (() -> Void)? = nil) {
        guard let app else {
            log.error("relaunch: no app URL to start")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        open(app, configuration) { started in
            guard started else {
                log.error("relaunch: could not start \(app.path, privacy: .public)")
                return
            }
            noteChange(app.deletingLastPathComponent())
            beforeTerminate?()
            terminate()
        }
    }
}

extension ArisRelauncher {
    /// The app to start: the one asked for; else the copy running now; and only when that copy has been moved or
    /// deleted (or isn't an app bundle), the copy the system has registered for the bundle id.
    static func target(asked: URL?, running: URL, exists: (URL) -> Bool, registered: () -> URL?) -> URL? {
        if let asked { return asked }
        if running.pathExtension == "app", exists(running) { return running }
        return registered()
    }

    @MainActor
    static let live = ArisRelauncher(
        open: { app, configuration, done in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { running, error in
                if let error { log.error("relaunch: \(error.localizedDescription, privacy: .public)") }
                let started = running != nil && error == nil
                DispatchQueue.main.async { done(started) }
            }
        },
        noteChange: { folder in NSWorkspace.shared.noteFileSystemChanged(folder.path) },
        terminate: { NSApp.terminate(nil) })
}

/// The entry points the user's menus and permission notices call.
enum ApplicationRelauncher {
    /// Relaunches the app at `app`, or the copy that is running now (ArisRelauncher.target).
    @MainActor
    static func restart(at app: URL? = nil, beforeTerminate: (() -> Void)? = nil) {
        let target = ArisRelauncher.target(
            asked: app, running: Bundle.main.bundleURL, exists: { FileManager.default.fileExists(atPath: $0.path) },
            registered: { Bundle.main.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) } })
        ArisRelauncher.live.relaunch(at: target, beforeTerminate: beforeTerminate)
    }
}
