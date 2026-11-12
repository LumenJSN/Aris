//
//  ArisCaptureSharing.swift
//  Aris
//
//  Whether Aris's overlay windows (the ink, the gesture hint, the teammates' panels) show in screen recordings and
//  screenshots. The real features keep them out (`.none`); while an ad demo runs, the windows it uses show
//  (`.readOnly`) so the ad session can record them, and go back to `.none` when it ends.
//

import AppKit

enum ArisCaptureSharing {
    /// What the real features use: never in a capture.
    static let hidden: NSWindow.SharingType = .none
    /// What a demo's windows use while it runs: captured, never written to.
    static let demo: NSWindow.SharingType = .readOnly

    static func type(demo shown: Bool) -> NSWindow.SharingType { shown ? demo : hidden }

    /// The ad session records over a borderless `.floating` window: a demo's window must sit above it.
    static func drawsAbove(_ level: NSWindow.Level, backdrop: NSWindow.Level = .floating) -> Bool {
        level.rawValue > backdrop.rawValue
    }
}
