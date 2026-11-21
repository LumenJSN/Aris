//
//  ArisCheckLog.swift
//  Aris
//
//  A check's own build may log what a card asks (eleventh VM run, item 10: the log says "asking you: <private>", so a
//  check on a real screen can't read the question that was spoken). Only in a build compiled with ARIS_CHECK_LOG
//  (xcodebuild … OTHER_SWIFT_FLAGS='$(inherited) -DARIS_CHECK_LOG'): the project sets that flag nowhere, so a release
//  build has none of this code and logs a card's words as private, as before. There is no setting and no default to
//  turn it on at run time.
//

import Foundation
import os

enum ArisCheckLog {
    /// Whether this build was compiled for a check.
    static var compiledIn: Bool {
        #if ARIS_CHECK_LOG
        return true
        #else
        return false
        #endif
    }

    /// The card as it is asked: its title and the sentence said aloud, readable in the log of a check's build only.
    static func card(_ ask: ArisConfirmation) {
        #if ARIS_CHECK_LOG
        Logger(subsystem: "com.lumenjsn.aris", category: "check")
            .notice("card asked: title=\(ask.title, privacy: .public) spoken=\(ask.spoken ?? "", privacy: .public)")
        #endif
    }
}
