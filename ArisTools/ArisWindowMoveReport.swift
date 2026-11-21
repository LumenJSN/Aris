//
//  ArisWindowMoveReport.swift
//  aris-tools
//
//  What `window <layout>` says once it asked the app to move and size its window: "moved" only when both took. An app
//  can refuse either (a full-screen window, a fixed-size panel, a window that isn't movable), and the old command said
//  "moved" whatever came back (audit 15). Pure, so the tests run it.
//

import Foundation

enum ArisWindowMoveReport {
    struct Report: Equatable {
        /// Whether the window is where it was asked to go (both its place and its size took).
        let done: Bool
        let line: String
    }

    /// `placed`, `sized`: whether the app took the new position and the new size.
    static func report(app: String, layout: String, placed: Bool, sized: Bool) -> Report {
        switch (placed, sized) {
        case (true, true):
            return Report(done: true, line: "moved \(app) \(layout)")
        case (true, false):
            return Report(done: false, line: "\(app)'s window was moved, but it refused the new size (it may have a fixed size), so it isn't \(layout) yet")
        case (false, true):
            return Report(done: false, line: "\(app)'s window took the new size, but it refused to move (it may be full screen or not movable), so it isn't \(layout)")
        case (false, false):
            return Report(done: false, line: "\(app)'s window didn't move: the app refused (it may be full screen, or its window can't be moved or resized)")
        }
    }
}
