//
//  ArisAgentInstaller.swift
//  Aris
//
//  The XPC helper's installAgent: makes the aris-agent inside this app the helper that runs, with no script and
//  nothing taken from the caller (ArisAgentInstall holds the rules; this file does them).
//   1 The app is the one this XPC helper sits in. A translocated, read-only, trashed or helper-less app is refused
//     with the reason, and nothing is written.
//   2 ~/.config/aris and its data folder exist, mode 700 (install-aris-agent.sh's duty before).
//   3 The job under the label from before the rename is unloaded and its file removed.
//   4 ~/.config/aris/aris-tools is a link to the aris-tools inside the app (what the AIs call), replaced by a rename
//     so it is never followed and never half-written.
//   5 The LaunchAgent file is written only when it differs; then the old job is stopped, its port waited for, the
//     helper's old copies in ~/.config/aris are removed (not the data), and the job is loaded. A job that is right but
//     not loaded is loaded; one that is right but runs another build (the app was replaced under it) is restarted
//     once, never twice within launchd's ten seconds.
//   6 It is done when the helper answers on its port and, for a stamped build, says it is this app's build.
//  A job that is right and loaded but not answering yet (login: launchd is starting it now) is waited for first.
//  What "the job" is comes from launchd itself (`launchctl print`: the program it executes, its arguments, the file it
//  was loaded from, its process and that process's real program), never from the file on disk; before anything is
//  written or loaded the app and both programs inside it are verified by signature; and a job under Aris's label that
//  runs anything else is unloaded, replaced, logged and reported to the app (security review 4, M7).
//  Everything it touches goes through ArisAgentInstallWorld, so the tests run the same steps against a recorded world.
//

import Foundation

/// When the helper was last kickstarted by this XPC helper (restartAgent and installAgent share it).
final class ArisKickstartClock: @unchecked Sendable {
    static let shared = ArisKickstartClock()
    private let lock = NSLock()
    private var last: Date?

    /// True when a kickstart may be sent now; the time is noted then.
    func take(now: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard ArisAgentKickstart.mayKickstart(last: last, now: now) else { return false }
        last = now
        return true
    }
}

struct ArisAgentInstallWorld {
    /// This XPC helper's own bundle.
    var servicePath: String
    var home: String
    var uid: uid_t
    /// launchctl's exit status; nil when it could not be run or took too long.
    var launchctl: (_ arguments: [String]) -> Int32?
    /// Something accepts a connection on the helper's port.
    var listening: () -> Bool
    var sleep: (TimeInterval) -> Void
    var exists: (String) -> Bool
    /// A file of its own at the path (not a link, not a folder).
    var isFile: (String) -> Bool
    var read: (String) -> Data?
    /// Where a link points; nil when the path is not a link.
    var linkTarget: (String) -> String?
    var isTranslocated: (String) -> Bool
    var isReadOnly: (String) -> Bool
    /// Makes the folder (and those above it) and sets it to mode 700.
    var makePrivateFolder: (String) -> Bool
    /// Writes beside the path and renames over it.
    var write: (Data, String) -> Bool
    /// Makes a link at the path pointing to the target, by a rename over whatever is there.
    var link: (_ target: String, _ path: String) -> Bool
    var remove: (String) -> Void
    var appBuild: (_ app: String) -> String?
    var agentBuild: () -> String?
    var mayKickstart: () -> Bool
    var note: (String) -> Void
    /// What `launchctl print` says about the job under Aris's label; nil when launchd has none or can't be asked.
    var loadedJob: () -> String? = { nil }
    /// The real program of a running process; nil when it can't be read.
    var programOf: (Int32) -> String? = { _ in nil }
    /// Whether the app at the path, strictly and with its nested code, and both programs inside it verify as Aris's
    /// (its identifiers, this XPC helper's own team).
    var verifies: (_ app: String) -> Bool = { _ in true }
    /// Whether the file at the path is validly signed as aris-agent by this XPC helper's own team.
    var isArisAgent: (_ path: String) -> Bool = { _ in true }
    /// Whether other users of this Mac can write the app or the folder it is in.
    var othersCanWrite: (_ app: String) -> Bool = { _ in false }
    /// When the app at the path was built (its Info.plist's ArisBuiltAt); nil when it does not say.
    var builtAt: (_ app: String) -> Double? = { _ in nil }
}

/// The app another copy's aris-agent sits in ("…/Aris.app/Contents/MacOS/aris-agent" gives "…/Aris.app"); nil for the
/// old install's loose copy.
enum ArisOtherCopy {
    static func app(ofAgent path: String) -> String? {
        let parts = (path as NSString).pathComponents
        guard parts.count >= 5, parts[parts.count - 2] == "MacOS", parts[parts.count - 3] == "Contents", parts[parts.count - 4].hasSuffix(".app") else { return nil }
        return NSString.path(withComponents: Array(parts.dropLast(3)))
    }
}

enum ArisAgentInstaller {
    /// How long the old helper may take to let go of its port, and the new one to answer.
    static let portFreeWait: TimeInterval = 20
    static let answerWait: TimeInterval = 30
    /// How long a job that is loaded may take to open its port before it is restarted.
    static let startGrace: TimeInterval = 8
    static let loadTries = 5
    static let pause: TimeInterval = 0.25

    /// `enforcing` (ArisRollout): whether the checks the fourth security review added refuse and replace, or only
    /// write down what they would have done and leave the decision to the file on disk as before.
    static func run(_ world: ArisAgentInstallWorld, enforcing: Bool = ArisRollout.enforcing) -> ArisAgentInstallOutcome {
        /// A new refusal: returned when enforcing, written down and passed over when not.
        func refuses(_ refusal: ArisAgentInstall.Refusal, _ why: String) -> Bool {
            world.note("install \(enforcing ? "refused" : "would refuse"): \(why)")
            if !enforcing { ArisRollout.wouldRefuse("the install: \(why)") }
            return enforcing
        }
        let app = ArisAgentInstall.app(ofService: world.servicePath)
        let home = world.home
        if let refusal = ArisAgentInstall.refusal(app: app, home: home, translocated: app.map(world.isTranslocated) ?? false,
                                                 readOnly: app.map(world.isReadOnly) ?? false,
                                                 hasAgent: app.map { world.isFile(ArisAgentInstall.agentPath(app: $0)) } ?? false,
                                                 hasTools: app.map { world.isFile(ArisAgentInstall.toolsPath(app: $0)) } ?? false) {
            world.note("install refused: \(refusal.rawValue)")
            return .refused(refusal)
        }
        guard let app else { return .refused(.shape) }
        // Never from a place other users can write, wherever that is (security review 4, L2).
        if !ArisAgentInstall.isInApplications(app: app, home: home), world.othersCanWrite(app), refuses(.sharedPlace, "the app is where other users can write") {
            return .refused(.sharedPlace)
        }
        // Aris's own folder must be a folder of its own, not a link to somewhere else (security review 4, L5).
        if world.linkTarget(ArisAgentInstall.folder(home: home)) != nil || world.linkTarget(ArisAgentInstall.dataFolder(home: home)) != nil,
           refuses(.linkedFolder, "Aris's folder is a link") {
            return .refused(.linkedFolder)
        }
        // Nothing is written or loaded for an app that is no longer what was signed.
        if !world.verifies(app), refuses(.changed, "the app or a program inside it does not verify as Aris's") {
            return .refused(.changed)
        }
        guard world.makePrivateFolder(ArisAgentInstall.folder(home: home)), world.makePrivateFolder(ArisAgentInstall.dataFolder(home: home)) else {
            return .failed("folder")
        }
        let link = ArisAgentInstall.toolsLink(home: home)
        let tools = ArisAgentInstall.toolsPath(app: app)
        let retiredCopy = ArisAgentInstall.retiredPrograms(home: home).contains(where: world.isFile) || world.isFile(link)
        let appBuild = world.appBuild(app)
        let sameJob = ArisAgentInstall.isSameJob(world.read(ArisAgentInstall.plistPath(home: home)), app: app, home: home)
        let loaded = world.launchctl(ArisAgentInstall.printArguments(uid: world.uid)) == 0
        // What launchd really has under the label. A job it has but will not describe counts as foreign.
        let described = loaded ? world.loadedJob().map(ArisLoadedJob.parse) : nil
        let loadedKind: ArisLoadedJob.Kind? = !loaded ? nil : described.map { job in
            job.kind(agent: ArisAgentInstall.agentPath(app: app), plist: ArisAgentInstall.plistPath(home: home),
                     running: job.pid.flatMap(world.programOf), isArisAgent: world.isArisAgent, exists: world.exists)
        } ?? .foreign
        let foreign = enforcing && loadedKind == .foreign
        if !enforcing, let kind = loadedKind, kind != .own {
            ArisRollout.wouldRefuse("the job launchd has under Aris's label (\(described?.summary ?? "not described")): it would be replaced")
        }
        // Another copy of Aris (or the old install) has the helper's place: this one takes it over only from an
        // Applications folder, or when that copy's helper is gone, and never as an older build over a newer one.
        if case .otherAris(let current)? = loadedKind,
           let refusal = ArisAgentInstall.takeoverRefusal(app: app, home: home, current: current, currentExists: world.exists(current), appBuiltAt: world.builtAt(app),
                                                          currentBuiltAt: ArisOtherCopy.app(ofAgent: current).flatMap(world.builtAt)) {
            if refuses(refusal, "\(refusal.rawValue) (the helper's place is held by \(current))") { return .refused(refusal) }
        }
        if loadedKind == .foreign {
            world.note("install: another program is loaded under Aris's label (\(described?.summary ?? "launchd would not describe it")); \(enforcing ? "replacing it" : "it would be replaced")")
        }
        // At login launchd starts the helper and Aris at the same moment: a job that is right and loaded but not
        // answering yet is given a few seconds to open its port before it counts as silent (it used to be restarted
        // while it was still starting, which cost every login ten seconds).
        if sameJob, loaded, loadedKind == .own || !enforcing, !retiredCopy { _ = wait(world, upTo: startGrace, until: world.listening) }
        let found = ArisAgentInstall.Found(sameJob: sameJob, loaded: loaded, answering: world.listening(), retiredCopy: retiredCopy,
                                           appBuild: appBuild, agentBuild: world.agentBuild(), loadedKind: enforcing ? loadedKind : nil)
        let step = ArisAgentInstall.step(found)
        world.note("install: \(String(describing: step)) (job \(found.sameJob ? "same" : "differs"), \(found.loaded ? "loaded" : "not loaded"), "
            + "\(found.answering ? "answering" : "silent"), old copy \(found.retiredCopy), app \(appBuild ?? "-"), helper \(found.agentBuild ?? "-"))")

        let retiredPlist = ArisAgentInstall.retiredPlistPath(home: home)
        if world.exists(retiredPlist) {
            _ = world.launchctl(ArisAgentInstall.bootoutArguments(uid: world.uid, label: ArisAgentInstall.retiredLabel))
            world.remove(retiredPlist)
        }
        if step != .reinstall, world.linkTarget(link) != tools {
            guard world.link(tools, link) else { return .failed("link") }
        }

        switch step {
        case .none:
            return .running
        case .reinstall:
            if found.loaded { _ = world.launchctl(ArisAgentInstall.bootoutArguments(uid: world.uid)) }
            guard wait(world, upTo: portFreeWait, until: { !world.listening() }) else { return .failed("port") }
            guard let job = ArisAgentInstall.jobData(app: app, home: home), world.write(job, ArisAgentInstall.plistPath(home: home)) else { return .failed("plist") }
            ArisAgentInstall.retiredPrograms(home: home).forEach(world.remove)
            guard world.link(tools, link) else { return .failed("link") }
            guard load(world) else { return .failed("load") }
            guard answers(world, appBuild: appBuild) else { return .failed("start") }
            // The switch from the old install is said first (it has its own lines); a foreign job that was replaced next.
            return found.retiredCopy ? .switched : foreign ? .replaced : .started
        case .load:
            guard load(world) else { return .failed("load") }
            guard answers(world, appBuild: appBuild) else { return .failed("start") }
            return .started
        case .restart:
            // Inside launchd's ten seconds no second kickstart is sent: the helper comes back by itself when they pass.
            if world.mayKickstart() { _ = world.launchctl(ArisAgentKickstart.arguments(uid: world.uid)) }
            // The old process may still hold the port for a moment after the kickstart.
            world.sleep(1)
            guard answers(world, appBuild: appBuild) else { return .failed("start") }
            return .started
        }
    }

    /// A load straight after a bootout can be refused while launchd is still letting go: a few tries.
    private static func load(_ world: ArisAgentInstallWorld) -> Bool {
        for attempt in 1...loadTries {
            if world.launchctl(ArisAgentInstall.bootstrapArguments(uid: world.uid, home: world.home)) == 0 { return true }
            if attempt < loadTries { world.sleep(1) }
        }
        return false
    }

    /// The helper answers and, for a stamped app, has written down this app's build.
    private static func answers(_ world: ArisAgentInstallWorld, appBuild: String?) -> Bool {
        wait(world, upTo: answerWait) {
            guard world.listening() else { return false }
            guard let appBuild, appBuild != ArisBuildInfo.unstamped else { return true }
            return world.agentBuild() == appBuild
        }
    }

    private static func wait(_ world: ArisAgentInstallWorld, upTo limit: TimeInterval, until done: () -> Bool) -> Bool {
        var waited: TimeInterval = 0
        while !done() {
            guard waited < limit else { return false }
            world.sleep(pause)
            waited += pause
        }
        return true
    }
}
