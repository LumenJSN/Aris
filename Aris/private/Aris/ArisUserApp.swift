//
//  ArisUserApp.swift
//  Aris
//
//  The app he was in when he asked, for the helper's look (second upgrade run, bug 1): Aris is an AppKit app, so what
//  it knows of the app in front is current, while the helper's own NSWorkspace kept naming TextEdit long after Safari
//  had opened over it. While he types into the notch, Aris itself is the app in front: then the app he was in is the
//  one the notch's field took the keyboard from (ArisPanelFocus.previous). Foundation only, so it is tested.
//

import Foundation

enum ArisUserApp {
    /// `front`: the app in front now (Aris's NSWorkspace); `own`: Aris; `previous`: the app the notch's field took the
    /// keyboard from, while one is being typed in. nil: Aris can't say (the helper then goes by the window order).
    static func pick(front: Int32?, own: Int32, previous: Int32?) -> Int32? {
        guard let front, front > 0 else { return previous }
        return front == own ? previous : front
    }
}
