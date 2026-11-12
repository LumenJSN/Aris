//
//  ArisAgentKickstart.swift
//  Aris
//
//  How aris-agent is restarted (audit ① B's 다시 시작): launchctl kickstart -k of its own LaunchAgent, run by the
//  unsandboxed XPC helper. Fixed here, in both targets: nothing the caller sends reaches launchctl.
//  kickstart only restarts a LaunchAgent that is loaded. After a failed install or a `launchctl bootout` it is not,
//  so the helper then loads it (bootstrap of the agent's own plist) and that starts it.
//  launchd starts a job again at most once in ten seconds: a second kickstart inside that time leaves the helper down
//  until the ten seconds are over (follow-up experiment, 3-xpc-install.txt), so one is never sent (mayKickstart) and
//  "not answering yet" inside that time is the wait, not a failure.
//

import Foundation

enum ArisAgentKickstart {
    static let label = "com.lumenjsn.aris.agent"
    static let launchctl = "/bin/launchctl"
    /// launchd's own wait between two starts of one job.
    static let throttle: TimeInterval = 10

    /// Whether a kickstart may be sent now: never within `throttle` of the one before.
    static func mayKickstart(last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= throttle || now < last
    }

    static func arguments(uid: uid_t) -> [String] {
        ["kickstart", "-k", "gui/\(uid)/\(label)"]
    }

    /// The agent's LaunchAgent file (the XPC helper writes it: ArisAgentInstall), under the user's real home.
    static func plistPath(home: String) -> String {
        "\(home)/Library/LaunchAgents/\(label).plist"
    }

    /// Loads the agent's LaunchAgent, which also starts it (RunAtLoad).
    static func bootstrapArguments(uid: uid_t, home: String) -> [String] {
        ["bootstrap", "gui/\(uid)", plistPath(home: home)]
    }
}
