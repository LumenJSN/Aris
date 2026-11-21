//
//  ArisWindowUndo.swift
//  aris-tools
//
//  The undo of `window left|right|full|center`: the frame the window had before the move, kept in the activity log, and
//  put back on the app's window that is still where the move left it (twelfth VM run: "방금 창 옮긴 거 되돌려 줘" had no
//  undo, so the brain guessed `window center`). A window moved again since, or gone, is left as it is and said so.
//

import AppKit
import ApplicationServices

enum ArisWindowUndo {
    /// How far (points) a window may be from where the move left it and still be that window.
    static let slack: Double = 4

    static func frame(_ rect: CGRect) -> [Double] { [rect.origin.x, rect.origin.y, rect.width, rect.height].map(Double.init) }

    /// The log's undo for a move from `before` to `after`; nil when either couldn't be read.
    static func recipe(app: String, before: CGRect?, after: CGRect?) -> ArisUndo? {
        guard let before, let after, !app.isEmpty else { return nil }
        return .restoreWindow(app: app, from: frame(after), to: frame(before))
    }

    /// Whether `now` is where the move left the window (`from`).
    static func matches(_ now: [Double], _ from: [Double]) -> Bool {
        now.count == 4 && from.count == 4 && zip(now, from).allSatisfy { abs($0 - $1) <= slack }
    }
}

/// Puts the app's window that is at `from` back at `to`.
func restoreWindow(app name: String, from: [Double], to: [Double]) throws {
    guard AXIsProcessTrusted() else { throw ArisActivity.UndoError(message: "Aris needs Accessibility to move the window back") }
    guard to.count == 4, let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
        throw ArisActivity.UndoError(message: "\(name) isn't open any more, so its window was left as it is")
    }
    var value: AnyObject?
    AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &value)
    let windows = (value as? [AXUIElement]) ?? []
    guard let window = windows.first(where: { axFrame($0).map { ArisWindowUndo.matches(ArisWindowUndo.frame($0), from) } ?? false }) else {
        throw ArisActivity.UndoError(message: "\(name)'s window was moved again since, so it was left where it is")
    }
    var origin = CGPoint(x: to[0], y: to[1]), size = CGSize(width: to[2], height: to[3])
    let sized = AXValueCreate(.cgSize, &size).map { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, $0) == .success } ?? false
    let placed = AXValueCreate(.cgPoint, &origin).map { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, $0) == .success } ?? false
    guard placed && sized else { throw ArisActivity.UndoError(message: "\(name) didn't let Aris move its window back") }
}
