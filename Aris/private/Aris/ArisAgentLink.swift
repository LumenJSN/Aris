//
//  ArisAgentLink.swift
//  Aris
//
//  Whether aris-agent answers, as the notch shows it (the owner's pick ① B, mockups/audit-1-agent-down.html). A cheap
//  probe (ArisAgentClient.probe) every 30 s; refused twice in a row, the app restarts the agent quietly (a token that
//  won't load is never a refusal: no kickstart); only if two quiet restarts don't bring it back does the star doze beside the camera (its asleep rest pose, grey, tilted, still).
//  Hovering it shows a chip under the notch with 다시 시작; while that runs the chip says so, then 다시 연결됐어요 for
//  1.5 s, or 아직 연결이 안 돼요 and the probe keeps trying every 10 s. Pure: ArisAgentMonitor runs it.
//

import Foundation

/// One probe's answer. A missing token says nothing about the agent, so it never counts as a refusal.
enum ArisAgentProbe: Equatable {
    /// Something answered (a slow or odd answer too: the turn meets the stream's own limits).
    case answered
    /// Nothing listens on the agent's port.
    case refused
    /// The token couldn't be loaded, so nothing was asked.
    case noToken

    static func from(hasToken: Bool, refused: Bool) -> Self {
        guard hasToken else { return .noToken }
        return refused ? .refused : .answered
    }
}

enum ArisAgentLink: Equatable {
    /// Answering, or not known to be down yet.
    case up
    case down
    /// The user pressed 다시 시작.
    case restarting
    /// It answered after the user's restart (held `backHold`).
    case back
    /// The user's restart didn't bring it back within `restartWait`.
    case failed

    /// Refused probes in a row before the first quiet restart.
    static let refusalsBeforeRestart = 2
    static let quietRestarts = 2
    static let probeEvery: TimeInterval = 30
    static let probeDownEvery: TimeInterval = 10
    /// Longer than launchd's ten seconds between two starts of one job (ArisAgentKickstart.throttle): a helper that
    /// was restarted a moment ago comes back only when they are over, and that is not "still not connected".
    static let restartWait: TimeInterval = 15
    static let backHold: TimeInterval = 1.5
    /// After a refusal, the next probe comes this soon.
    static let quietSettle: TimeInterval = 3
    /// After a quiet restart the next probe waits out launchd's ten seconds between two starts of one job: a helper
    /// that was restarted a moment ago is not "down" before they are over, and no second restart is sent inside them.
    static let restartSettle: TimeInterval = ArisAgentKickstart.throttle + 2

    /// A probe's answer: the next state, and whether to restart the agent quietly now. `refusals` counts the refused
    /// probes in a row, this one included; `quietTries` the quiet restarts so far this outage.
    static func afterProbe(_ link: Self, probe: ArisAgentProbe, refusals: Int, quietTries: Int) -> (Self, Bool) {
        switch probe {
        case .answered: return (link == .restarting || link == .back ? .back : .up, false)
        case .noToken: return (link, false)
        case .refused:
            switch link {
            case .down, .failed, .restarting: return (link, false)
            case .up, .back:
                if refusals < refusalsBeforeRestart { return (link, false) }
                return quietTries < quietRestarts ? (.up, true) : (.down, false)
            }
        }
    }

    /// Whether the helper counts as answering after a probe: a refusal is "no", an answer is "yes", and a token that
    /// could not be loaded says nothing either way.
    static func answering(_ probe: ArisAgentProbe, was: Bool) -> Bool {
        switch probe {
        case .answered: true
        case .refused: false
        case .noToken: was
        }
    }

    static func restartTimedOut(_ link: Self) -> Self { link == .restarting ? .failed : link }

    /// The star dozes beside the camera.
    var dozes: Bool { self == .down || self == .failed }

    static func chipShows(_ link: Self, hovered: Bool) -> Bool {
        switch link {
        case .up: false
        case .down, .failed: hovered
        case .restarting, .back: true
        }
    }

    var chipText: String {
        switch self {
        case .up, .down: Self.lostWords
        case .restarting: ArisUIWords.text("다시 시작하는 중", "Restarting")
        case .back: ArisUIWords.text("다시 연결됐어요", "Connected again")
        case .failed: ArisUIWords.text("아직 연결이 안 돼요", "Still not connected")
        }
    }

    /// The chip's words, in the UI's language (ArisUIWords).
    static var lostWords: String { ArisUIWords.text("에이전트 연결 끊김", "Helper disconnected") }
    static var restartWords: String { ArisUIWords.text("다시 시작", "Restart") }

    var offersRestart: Bool { dozes }

    /// Whether the user's restart goes ahead: when the star dozes; and, `asked` (the helper was asked a moment ago and
    /// did not answer), also while it still counts as up. Never a second time while one is under way or just done.
    static func restarts(_ link: Self, asked: Bool) -> Bool { link.offersRestart || (asked && link == .up) }

    /// What the unsandboxed helper runs: the agent's own LaunchAgent, killed and started again.
    static func kickstartArguments(uid: uid_t) -> [String] {
        ArisAgentKickstart.arguments(uid: uid)
    }
}
