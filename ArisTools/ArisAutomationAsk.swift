//
//  ArisAutomationAsk.swift
//  aris-tools (jv-prompts)
//
//  When aris-tools may send an Apple Event to another app, so macOS's per-app Automation dialog ("Aris wants to
//  control Notes") comes at most once, at the first use, in a turn the user is in front of, after the app's one line
//  of why. What macOS says is read first, never asking (ArisAutomationAccess.state(of:)):
//   · granted, or refused (the event fails at once, with today's words and the pane's button): send it;
//   · never asked, in a turn the user is in front of (ARIS_FOREGROUND): the app says the feature's line through its
//     permission layer (once), then the event goes and macOS asks;
//   · never asked, anywhere else (a scheduled job, a teammate, a background task): nothing is sent and nothing asked;
//   · not known (the app couldn't be asked about): sent as before.
//  A channel used only as a fallback (a calendar add when the app can't do it, a browser tab Accessibility couldn't
//  read) is used only when the grant is already there: it never asks at all. Pure.
//

import Foundation

enum ArisAutomationAsk {
    /// What aris-tools does before the Apple Event.
    enum Step: Equatable {
        /// Send it.
        case send
        /// Have the app say why (ArisPermissionFeature `feature`, once), then send it: macOS asks.
        case sayThenSend(feature: String)
        /// Don't send it; fail with this line.
        case refuse(String)
    }

    /// The environment key aris-agent sets for a turn the user is in front of (ArisAgentRunner.environment).
    static let foregroundKey = "ARIS_FOREGROUND"

    static func isForeground(_ environment: [String: String]) -> Bool { environment[foregroundKey] == "1" }

    /// The step for an event to `app` (its shown name) that `feature` needs, with macOS's answer `state`.
    static func step(state: ArisPermissionState, foreground: Bool, app: String, feature: ArisPermissionFeature) -> Step {
        switch state {
        case .granted, .denied, .unknown: return .send
        case .notAsked: return foreground ? .sayThenSend(feature: feature.rawValue) : .refuse(notAskedLine(app: app))
        }
    }

    /// Whether a fallback channel may be used: only with the grant already there (it never asks).
    static func fallbackAllowed(_ state: ArisPermissionState) -> Bool { state == .granted }

    /// Said when the first ask would come outside a turn the user is in front of. Read by the AI.
    static func notAskedLine(app: String) -> String {
        "NOT DONE: macOS hasn't been asked yet whether Aris may control \(app), and this isn't a conversation the user is in, "
            + "so it wasn't asked now (a question would wait unseen). Nothing was sent to \(app). Tell the user to ask for it once "
            + "in a conversation; macOS asks then, once."
    }
}

/// Which of the four goes without Apple Events. Pure.
enum ArisPowerRoute {
    /// The program and its arguments for `verb` when no app needs to be driven for it; nil for System Events' own.
    static func withoutAppleEvents(_ verb: String) -> [String]? {
        verb == "sleep" ? ["/usr/bin/pmset", "sleepnow"] : nil
    }
}
