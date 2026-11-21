//
//  ArisPreviewGate.swift
//  Aris
//
//  Whether the preview harness (ArisPreview) listens at all. It can drive real turns and delete history and
//  reminders, from a file and a distributed notification any process of the user can make, so no build made for use
//  has it, whatever its bundle id (the public release, a build from the public source, the owner's own deployed
//  build): only one compiled with DEBUG (Xcode's Debug configuration; the Release configuration never sets it).
//  Foundation only (tested).
//

import Foundation

enum ArisPreviewGate {
    static func enabled(bundleId: String?, debug: Bool) -> Bool {
        // The bundle id opens nothing: it is read only so a test can show that no id does.
        debug
    }

    /// This build's answer.
    static var here: Bool {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return enabled(bundleId: Bundle.main.bundleIdentifier, debug: debug)
    }
}
