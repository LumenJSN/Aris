//
//  ArisOnboardingLeave.swift
//  Aris
//
//  What the setup leaves in front when its window closes (VM run 2026-11-11, bug 5: after Finish the user was left
//  looking at System Settings › Screen Recording, because the setup had sent them there). The app in front afterwards
//  is the one the user had, or none of Aris's making: a System Settings the setup started itself, and that the user
//  has not gone back to since, steps out of the way, and the app the user last had comes forward. A System Settings
//  the user already had open, or went back to by themselves, is theirs and is never touched. Pure, so the tests run it;
//  the AppKit calls are in ArisOnboardingGuide+Leave.
//

import Foundation

struct ArisSetupLeave: Equatable {
    /// The System Settings process the setup started (it was not running when a card sent the user there); nil when
    /// it never did, or the user has used it as their own since.
    private(set) var startedPid: Int32?
    /// A card's Allow is about to start System Settings: the next time it comes forward, that process is the setup's.
    private(set) var starting = false
    /// A card sent the user to System Settings and Aris has not come forward since: being there is the setup's doing.
    private(set) var sent = false
    /// The last app the user had in front that is neither Aris nor System Settings (its bundle id).
    private(set) var userApp: String?

    /// `frontApp`: the app in front as the setup opens, when it is another app with a Dock icon.
    init(frontApp: String? = nil) { userApp = frontApp }

    // MARK: - What happens

    /// A card's Allow sends the user to System Settings. `runningPid`: the System Settings running now, if any.
    mutating func sending(runningPid: Int32?) {
        sent = true
        if runningPid == nil {
            starting = true
        } else if runningPid != startedPid {
            // One the user opened: theirs.
            startedPid = nil
            starting = false
        }
    }

    /// An app came to the front. `settingsPid`: the System Settings running now; `sinceForward`: seconds since the
    /// setup window last came forward on purpose (nil when it has not, or a card has sent the user away since).
    mutating func cameForward(_ taker: ArisOnboardingFront.Taker, bundleID: String?, settingsPid: Int32?, sinceForward: Double?) {
        switch taker {
        case .aris:
            sent = false
        case .systemSettings:
            if starting, let settingsPid {
                startedPid = settingsPid
                starting = false
            } else if settingsPid != startedPid {
                startedPid = nil
            } else if !sent, !Self.handedBack(sinceForward) {
                // The user went back to it by themselves: from now it is theirs.
                startedPid = nil
            }
        case .app:
            if let bundleID { userApp = bundleID }
        case .agent:
            break
        }
    }

    /// macOS may hand the screen back to the app before for a moment after the setup comes forward: that is not the
    /// user going there.
    private static func handedBack(_ sinceForward: Double?) -> Bool {
        guard let sinceForward else { return false }
        return sinceForward >= 0 && sinceForward < ArisOnboardingFront.settle
    }

    // MARK: - As the window closes

    struct Plan: Equatable {
        /// System Settings steps out of the way (hidden: its window is gone from the screen, the app stays open).
        var hidesSettings = false
        /// The app to bring forward (a bundle id), if the user had one.
        var activates: String?
    }

    /// What to do as the setup's window closes. Nothing when Aris is quitting mid-way (Quit & Reopen comes back to the
    /// same System Settings), when the setup never started System Settings, when it is no longer that process, or
    /// when the user has used it since.
    func plan(runningPid: Int32?, quitting: Bool) -> Plan {
        guard !quitting, let startedPid, runningPid == startedPid else { return Plan() }
        return Plan(hidesSettings: true, activates: userApp)
    }

    /// After the plan was carried out: nothing of the setup's is left to step back from.
    mutating func done() {
        startedPid = nil
        starting = false
        sent = false
    }

    // MARK: - Across Quit & Reopen

    /// Kept while Aris quits mid-setup (macOS's Quit & Reopen after Screen Recording), read once when it is back.
    static let key = "arisOnboardingLeave"
    private static let pidField = "pid", appField = "app"

    /// What to keep across the quit; nil when there is nothing of the setup's to remember.
    var saved: [String: Any]? {
        guard let startedPid else { return nil }
        var kept: [String: Any] = [Self.pidField: Int(startedPid)]
        if let userApp { kept[Self.appField] = userApp }
        return kept
    }

    /// Back after the quit. What was kept counts only while that same System Settings process still runs; otherwise
    /// the setup starts with nothing of its own. `frontApp`: as in `init(frontApp:)`.
    static func restored(saved: [String: Any]?, runningPid: Int32?, frontApp: String?) -> ArisSetupLeave {
        guard let pid = saved?[pidField] as? Int, let runningPid, Int(runningPid) == pid else { return ArisSetupLeave(frontApp: frontApp) }
        var leave = ArisSetupLeave(frontApp: saved?[appField] as? String ?? frontApp)
        leave.startedPid = runningPid
        return leave
    }
}
