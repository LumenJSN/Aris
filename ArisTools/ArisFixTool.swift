//
//  ArisFixTool.swift
//  aris-tools
//
//  A call that fails for something the user can fix with one press (a permission of aris-agent's that is off) says which
//  as it fails: the sentence goes to the brain as before, and a note goes to aris-agent (ArisFixDrop), which puts the
//  right button under the turn's answer whatever words the brain then chooses.
//

import Foundation

/// `fail`, with the fix the failure earns; nil is a plain `fail`.
func fail(_ message: String, fix: ArisFix?) -> Never {
    if let fix {
        let task = ProcessInfo.processInfo.environment[ArisConvertWords.taskKey] == "1"
        ArisFixDrop.append(fix, task: task, to: arisFolder.appendingPathComponent(ArisFixDrop.name))
    }
    fail(message)
}

enum ArisToolFix {
    /// osascript's complaint when macOS didn't let aris-agent control the app: Automation's list (ArisFix.appleScript).
    static func appleScript(_ complaint: String) -> ArisFix? { ArisFix.appleScript(complaint) }

    /// A store that couldn't be read for want of Full Disk Access (ArisLocalStore's `noDiskAccess`).
    static func store(_ error: Error) -> ArisFix? {
        if case .noDiskAccess? = error as? ArisLocalStoreError { return .pane(.disk) }
        return nil
    }
}
