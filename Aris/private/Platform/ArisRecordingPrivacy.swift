//
//  ArisRecordingPrivacy.swift
//  Aris
//
//  "Hide from screen recording" for every Aris window, not only the notch and the dictation pill: the side panels,
//  the reader, the permission guide, the setup guide and Settings follow it too. Each window is registered when it is
//  made; a change of the setting reaches every registered window at once. The overlays that never show in a capture
//  (the ink, a window pick, the teammates' panels: ArisCaptureSharing) keep their own rule.
//

import AppKit
import Combine
import Defaults

@MainActor
enum ArisRecordingPrivacy {
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static var watcher: AnyCancellable?

    /// The window follows the setting from now on (it is set at once).
    static func follow(_ window: NSWindow) {
        windows.add(window)
        window.sharingType = ArisCaptureSharing.recording(hidden: Defaults[.hideFromScreenRecording])
        watch()
    }

    private static func watch() {
        guard watcher == nil else { return }
        watcher = Defaults.publisher(.hideFromScreenRecording, options: [])
            .receive(on: DispatchQueue.main)
            .sink { change in
                MainActor.assumeIsolated {
                    let type = ArisCaptureSharing.recording(hidden: change.newValue)
                    windows.allObjects.forEach { $0.sharingType = type }
                }
            }
    }
}
