//
//  ArisAppsWindowOrder.swift
//  aris-agent (Core 2 app layer)
//
//  Putting the windows back in the order the owner had them, after a step had to bring its app forward (ninth VM
//  run, item 2, cap9/F1-order-quad.jpg: Finder active with only the desktop focused, two Finder windows over
//  TextEdit's; the step raised TextEdit, Finder was made active again, and TextEdit's window stayed above Finder's,
//  three times out of three). The eighth run's fix raised the owner's app's main window, and an app whose key
//  "window" is the desktop has none (no AXMainWindow, no AXFocusedWindow): nothing was raised. So the order itself is
//  kept: before the app is brought forward the windows on screen are listed front to back (who owns each and where it
//  is: the window server's list, no title, no picture, no permission), and when the owner's app goes back the windows
//  that lay over the app brought forward are raised again, the backmost first, by Accessibility's AXRaise. No pointer
//  or key event, and nothing of Aris's own is moved. Pure; the live half is ArisAppsLive+WindowOrder.
//

import Foundation

/// One window on screen: its owner and its frame (top-left origin, as the window server and Accessibility give it).
struct ArisAppsWindowPlace: Equatable, Sendable {
    var pid: Int32
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ArisAppsWindowOrder {
    /// No more than this many windows are raised (the frontmost ones).
    static let most = 12
    /// A window's frame read two ways (the window server, Accessibility) is the same within this many points.
    static let slack = 2.0

    /// The windows to raise again, in the order to raise them (the last ends on top). `before`: the windows on screen
    /// before the step, front to back; `brought`: the apps the step brought forward; `skip`: Aris's own processes.
    /// They are the ones that lay over the frontmost window of an app brought forward; an app that had no window on
    /// screen had every window over it.
    static func toRaise(before: [ArisAppsWindowPlace], brought: Set<Int32>, skip: Set<Int32>) -> [ArisAppsWindowPlace] {
        let top = before.firstIndex { brought.contains($0.pid) } ?? before.count
        let above = before[..<top].filter { !skip.contains($0.pid) && !brought.contains($0.pid) }
        return Array(above.prefix(most).reversed())
    }

    /// Whether `place` is the window at this frame.
    static func same(_ place: ArisAppsWindowPlace, x: Double, y: Double, width: Double, height: Double) -> Bool {
        abs(place.x - x) <= slack && abs(place.y - y) <= slack && abs(place.width - width) <= slack && abs(place.height - height) <= slack
    }
}
