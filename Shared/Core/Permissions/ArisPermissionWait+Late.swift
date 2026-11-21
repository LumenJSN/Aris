//
//  ArisPermissionWait+Late.swift
//  Shared/Core (aris-tools, tests)
//
//  A script that was sent while macOS was asking the owner about its app (the eleventh VM run, P11: the note was made
//  once he allowed it, 35 s in, and the reply said Notes hadn't answered). The look at a script's limit can't be relied
//  on to read "not asked" while the dialog is up, so what macOS said when the script went (`before`) decides too: the
//  same script waits out his time, is never started again, and at the end what is said is what is known. Whether it
//  did go through is read back where that can be done without sending anything again (ArisNoteCommand). Pure.
//

import Foundation

extension ArisPermissionWait {
    /// How long a script may still take once macOS's dialog has been answered yes.
    static let grace: TimeInterval = 20

    /// `before`: macOS's answer for each app when the script was sent; `states`: its answer now, at the limit.
    static func automationExtension(before: [ArisPermissionState], states: [ArisPermissionState], waited: TimeInterval) -> TimeInterval? {
        guard waited < dialog, !states.contains(.denied) else { return nil }
        if states.contains(.notAsked) { return dialog - waited }
        guard before.contains(.notAsked) else { return nil }
        // Allowed just now: a short while for the same script to finish. Anything else can't be read as an answer.
        let answered = !states.isEmpty && states.allSatisfy { $0 == .granted }
        return answered ? min(grace, dialog - waited) : dialog - waited
    }

    static func automationTimeoutLine(app: String, before: [ArisPermissionState], states: [ArisPermissionState], waited: TimeInterval) -> String? {
        if let line = automationTimeoutLine(app: app, states: states, waited: waited) { return line }
        guard before.contains(.notAsked) else { return nil }
        return "macOS was asking, in its own dialog, whether Aris may control \(app) when this was sent, and it hadn't finished after \(Int(waited)) seconds. "
            + "Whether it went through isn't known (it may still, or already did): don't repeat it. Tell the user to check \(app)."
    }

    enum LateOutcome: Equatable, Sendable {
        /// What it was to make is there: it went through.
        case done
        /// Not found, or it couldn't be looked for: said as not known, never as failed, never repeated.
        case unknown
    }

    /// `found`: whether what the script was to make is there now; nil when that couldn't be read.
    static func lateOutcome(found: Bool?) -> LateOutcome { found == true ? .done : .unknown }

    /// Added to a command's own "done" line when that was learned by reading back.
    static let lateDoneNote = " (the app answered late; found by reading it back)"
}

/// Whether the note a late script was to make is among Notes' newest (`notes`: title and when it last changed).
enum ArisNoteLate {
    /// Clocks and Notes' own rounding: a note changed this long before the script went still counts as its.
    static let slack: TimeInterval = 2

    static func exists(_ notes: [(title: String, modified: Date)], titled title: String, since: Date) -> Bool {
        let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !wanted.isEmpty && notes.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == wanted && $0.modified >= since.addingTimeInterval(-slack) }
    }
}
