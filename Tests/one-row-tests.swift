// Tests for "one row per macOS permission" (qa/design-1111/one-row-experiment.md, arrangement K, and its follow-up).
// aris-agent and aris-tools live inside Aris.app, so macOS charges the app for what they do and shows one row, "Aris".
// Pinned here:
// - where the helper is, and the LaunchAgent the app's XPC helper writes for it (same label, the program inside the
//   app, its Login Items name, a KeepAlive that stops when the app is gone), built from constants and the app's place;
// - which places an app may not run its helper from, and what the user is told;
// - the installer's steps against a recorded world: a new Mac, an install made the old way, an app replaced under a
//   running helper, nothing to do; what is written, in which order, and that nothing of the data is removed;
// - no second kickstart within launchd's ten seconds;
// - who may run aris-tools and aris-agent from inside the app: only Aris's own launchd job, or a program macOS
//   charges instead (the security half: a launchd job pointed at them is refused);
// - the helper stops by itself when its app is gone, and reads the skills' files from the app;
// - what the user is told and when: nothing on a good day, one line with a button otherwise;
// - the app captures before the helper does, so macOS's question about the screen names Aris.
// Everything runs on values made here: nothing is asked of macOS, launchd or an agent, and no file outside a
// throwaway value is touched. Called from main.swift; uses its check().
import Foundation

func runOneRowTests() {
    oneRowPlacesTests()
    oneRowRefusalTests()
    oneRowJobTests()
    oneRowStepTests()
    oneRowInstallerTests()
    oneRowKickstartTests()
    oneRowOriginTests()
    oneRowBundleTests()
    oneRowWordsTests()
    oneRowCaptureTests()
    oneRowSourceTests()
    oneRowPaneNameTests()
}

private typealias I = ArisAgentInstall
private let oneRowHome = "/Users/kim"
private let oneRowApp = "/Applications/Aris.app"
private let oneRowService = "/Applications/Aris.app/Contents/XPCServices/ArisXPCHelper.xpc"
private let oneRowRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func oneRowCode(_ path: String) -> String { (try? String(contentsOf: oneRowRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func oneRowPlacesTests() {
    check(I.agentPath(app: oneRowApp) == "/Applications/Aris.app/Contents/MacOS/aris-agent" && I.toolsPath(app: oneRowApp) == "/Applications/Aris.app/Contents/MacOS/aris-tools",
          "one row: the helper and its tools sit directly in the app's Contents/MacOS (only there does macOS count Accessibility as the app's)")
    check(I.toolsLink(home: oneRowHome) == "/Users/kim/.config/aris/aris-tools", "one row: the AIs still call aris-tools at its old path in Aris's folder")
    check(I.plistPath(home: oneRowHome) == "/Users/kim/Library/LaunchAgents/com.lumenjsn.aris.agent.plist" && I.label == ArisAgentKickstart.label,
          "one row: the LaunchAgent keeps its label and its file, so launchd and Login Items see one job")
    check(I.retiredPrograms(home: oneRowHome) == ["/Users/kim/.config/aris/aris-agent", "/Users/kim/.config/aris/aris-agent.new", "/Users/kim/.config/aris/aris-tools.new"],
          "one row: what the old install left to remove is the helper's own copy and half-swapped files, nothing under the data folder")
    check(I.retiredPrograms(home: oneRowHome).allSatisfy { !$0.hasPrefix(I.dataFolder(home: oneRowHome) + "/") } && I.dataFolder(home: oneRowHome) == "/Users/kim/.config/aris/aris",
          "one row: the data folder is never in the list of things removed")
    check(I.app(ofService: oneRowService) == oneRowApp, "one row: the app is the one the XPC helper sits in")
    check(I.app(ofService: "/Users/kim/My Apps/Aris.app/Contents/XPCServices/ArisXPCHelper.xpc") == "/Users/kim/My Apps/Aris.app", "one row: an app in a folder with a space is found")
    for odd in ["/tmp/ArisXPCHelper.xpc", "/Applications/Aris.app/Contents/Helpers/ArisXPCHelper.xpc", "/Applications/Aris/Contents/XPCServices/ArisXPCHelper.xpc",
                "Aris.app/Contents/XPCServices/ArisXPCHelper.xpc", "/Applications/Aris.app/Contents/XPCServices/tool", ""] {
        check(I.app(ofService: odd) == nil, "one row: an XPC helper that is not inside an app's XPCServices installs nothing (\(odd))")
    }
}

private func oneRowRefusalTests() {
    func refusal(_ app: String?, translocated: Bool = false, readOnly: Bool = false, agent: Bool = true, tools: Bool = true) -> I.Refusal? {
        I.refusal(app: app, home: oneRowHome, translocated: translocated, readOnly: readOnly, hasAgent: agent, hasTools: tools)
    }
    check(refusal(oneRowApp) == nil && refusal("/Users/kim/Applications/Aris.app") == nil, "one row: an app in Applications (the Mac's or the user's) may run its helper")
    check(refusal("/private/var/folders/ab/T/AppTranslocation/1F2E/d/Aris.app") == .translocated,
          "one row: an app opened straight from a download runs from a temporary copy, and its helper is not installed from there")
    check(refusal(oneRowApp, translocated: true) == .translocated, "one row: macOS's own word that the app is translocated refuses too")
    check(refusal("/Volumes/Aris/Aris.app", readOnly: true) == .readOnly, "one row: an app on a disk image is refused")
    check(refusal("/Users/kim/.Trash/Aris.app") == .trash && refusal("/Volumes/USB/.Trashes/501/Aris.app") == .trash, "one row: an app in the Trash is refused")
    check(refusal(nil) == .shape && refusal("/Applications/Aris") == .shape && refusal("Aris.app") == .shape && refusal("/Applications/../tmp/Aris.app") == .shape,
          "one row: anything that is not an app at a plain full path is refused")
    check(refusal(oneRowApp, agent: false) == .noHelper && refusal(oneRowApp, tools: false) == .noHelper, "one row: an app with no helper or no tools inside it says so")
    check(refusal("/private/var/folders/ab/T/AppTranslocation/1F2E/d/Aris.app", agent: false) == .translocated, "one row: where the app is comes before what is inside it")
    for why in [I.Refusal.translocated, .readOnly, .trash] {
        check(ArisHelperInstallWords.atLaunch(.refused(why), english: true) == "Move Aris to the Applications folder, then open it again.",
              "one row: an app in the wrong place is told to move to Applications (\(why.rawValue))")
    }
    check(ArisHelperInstallWords.atLaunch(.refused(.translocated), english: false) == "Aris를 응용 프로그램 폴더로 옮긴 다음 다시 열어 주세요.", "one row: the same line in Korean")
}

private func oneRowJobTests() {
    let job = I.job(app: oneRowApp, home: oneRowHome)
    let program = "/Applications/Aris.app/Contents/MacOS/aris-agent"
    check(job["Label"] as? String == "com.lumenjsn.aris.agent", "one row job: the label is the one from before")
    check(job["ProgramArguments"] as? [String] == [program], "one row job: launchd starts the aris-agent inside the app, with no arguments")
    check(job["AssociatedBundleIdentifiers"] as? [String] == ["com.lumenjsn.aris"], "one row job: Login Items lists it under Aris")
    check(job["RunAtLoad"] as? Bool == true, "one row job: it starts when it is loaded and at login")
    check((job["KeepAlive"] as? [String: Any])?["PathState"] as? [String: Bool] == [program: true],
          "one row job: it is kept alive only while its program is there, so a trashed app leaves no retry loop")
    check(job["StandardErrorPath"] as? String == "/Users/kim/.config/aris/aris/agent.log" && job["ProcessType"] as? String == "Interactive",
          "one row job: the log goes where it always went")
    check(Set(job.keys) == ["Label", "ProgramArguments", "AssociatedBundleIdentifiers", "RunAtLoad", "KeepAlive", "ProcessType", "StandardErrorPath"],
          "one row job: nothing else is in it (no environment, no extra arguments)")
    let data = I.jobData(app: oneRowApp, home: oneRowHome)
    check(data != nil && I.isSameJob(data, app: oneRowApp, home: oneRowHome), "one row job: the file it writes is the job it expects to find")
    let binary = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) }.flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
    check(I.isSameJob(binary, app: oneRowApp, home: oneRowHome), "one row job: the same job in another layout is not rewritten")
    check(!I.isSameJob(data, app: "/Users/kim/Applications/Aris.app", home: oneRowHome), "one row job: a job for another place of the app is rewritten")
    let old: [String: Any] = ["Label": "com.lumenjsn.aris.agent", "ProgramArguments": ["/Users/kim/.config/aris/aris-agent"], "RunAtLoad": true, "KeepAlive": true,
                              "ProcessType": "Interactive", "StandardErrorPath": "/Users/kim/.config/aris/aris/agent.log"]
    check(!I.isSameJob(try? PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0), app: oneRowApp, home: oneRowHome),
          "one row job: the job install-aris-agent.sh wrote is not this one")
    check(!I.isSameJob(nil, app: oneRowApp, home: oneRowHome) && !I.isSameJob(Data("not a plist".utf8), app: oneRowApp, home: oneRowHome), "one row job: no file, or one that can't be read, is written")
    check(I.bootstrapArguments(uid: 501, home: oneRowHome) == ["bootstrap", "gui/501", "/Users/kim/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"]
            && I.bootoutArguments(uid: 501) == ["bootout", "gui/501/com.lumenjsn.aris.agent"] && I.printArguments(uid: 501) == ["print", "gui/501/com.lumenjsn.aris.agent"]
            && I.bootoutArguments(uid: 501, label: I.retiredLabel) == ["bootout", "gui/501/com.lumenjsn.aris.aris-agent"],
          "one row job: launchctl's arguments are built from the label and the user's own domain only")
}

private func oneRowStepTests() {
    func found(same: Bool = true, loaded: Bool = true, answering: Bool = true, old: Bool = false, app: String? = "abc12345", agent: String? = "abc12345") -> I.Found {
        I.Found(sameJob: same, loaded: loaded, answering: answering, retiredCopy: old, appBuild: app, agentBuild: agent)
    }
    check(I.step(found()) == .none, "one row step: this app's helper running this app's build needs nothing")
    check(I.step(found(same: false, loaded: false, answering: false, agent: nil)) == .reinstall, "one row step: a new Mac gets the job written and loaded")
    check(I.step(found(same: false)) == .reinstall, "one row step: a job pointing somewhere else is rewritten, even while it answers")
    check(I.step(found(old: true)) == .reinstall, "one row step: a leftover copy of the helper in Aris's folder is cleared with a reinstall")
    check(I.step(found(loaded: false, answering: false)) == .load, "one row step: the right job that launchd doesn't have is loaded")
    check(I.step(found(answering: false)) == .restart, "one row step: a loaded helper that doesn't answer is restarted")
    check(I.step(found(agent: "old00000")) == .restart && I.step(found(agent: nil)) == .restart, "one row step: a helper of another build (the app was replaced under it) is restarted")
    check(I.step(found(app: "dev", agent: "old00000")) == .none && I.step(found(app: nil, agent: "x")) == .none, "one row step: a build with no stamp compares nothing")
    for (word, outcome) in [("running", ArisAgentInstallOutcome.running), ("started", .started), ("switched", .switched), ("refused:translocated", .refused(.translocated)),
                            ("refused:noHelper", .refused(.noHelper)), ("failed:load", .failed("load"))] {
        check(outcome.word == word && ArisAgentInstallOutcome(word: word) == outcome, "one row: the installer's answer \(word) crosses XPC whole")
    }
    check(ArisAgentInstallOutcome(word: "") == .failed("answer") && ArisAgentInstallOutcome(word: "refused:bananas") == .failed("answer") && ArisAgentInstallOutcome(word: "ok") == .failed("answer"),
          "one row: an answer that is not one of the installer's is a failure, never a success")
    check(ArisAgentInstallOutcome.running.isUp && ArisAgentInstallOutcome.started.isUp && ArisAgentInstallOutcome.switched.isUp
            && !ArisAgentInstallOutcome.refused(.trash).isUp && !ArisAgentInstallOutcome.failed("load").isUp, "one row: only a helper that answers counts as up")
}

/// A Mac as the installer sees it: files by path, launchd's state, the helper's port. Records everything done.
private final class OneRowWorld {
    var files: [String: Data] = [:]
    var links: [String: String] = [:]
    var folders: Set<String> = []
    var loaded = false
    var listening = false
    var agentBuild: String?
    var appBuild: String? = "new11111"
    var translocated = false
    var readOnly = false
    var bootstrapFailures = 0
    var portNeverFrees = false
    var linkFails = false
    var kickstartAllowed = true
    var done: [String] = []
    var slept: TimeInterval = 0

    func world(service: String = oneRowService) -> ArisAgentInstallWorld {
        ArisAgentInstallWorld(
            servicePath: service, home: oneRowHome, uid: 501,
            launchctl: { [self] arguments in
                done.append("launchctl " + arguments.joined(separator: " "))
                switch arguments.first {
                case "print": return loaded ? 0 : 113
                case "bootout":
                    guard arguments.last == "gui/501/com.lumenjsn.aris.agent" else { return 3 }
                    loaded = false
                    if !portNeverFrees { listening = false }
                    return 0
                case "bootstrap":
                    if bootstrapFailures > 0 { bootstrapFailures -= 1; return 5 }
                    loaded = true; listening = true; agentBuild = appBuild
                    return 0
                case "kickstart":
                    listening = true; agentBuild = appBuild
                    return 0
                default: return 1
                }
            },
            listening: { [self] in listening },
            sleep: { [self] in slept += $0 },
            exists: { [self] in files[$0] != nil || links[$0] != nil || folders.contains($0) },
            isFile: { [self] in files[$0] != nil },
            read: { [self] in files[$0] },
            linkTarget: { [self] in links[$0] },
            isTranslocated: { [self] _ in translocated },
            isReadOnly: { [self] _ in readOnly },
            makePrivateFolder: { [self] in folders.insert($0); done.append("folder " + $0); return true },
            write: { [self] data, path in files[path] = data; done.append("write " + path); return true },
            link: { [self] target, path in
                guard !linkFails else { return false }
                files[path] = nil; links[path] = target; done.append("link " + path + " -> " + target)
                return true
            },
            remove: { [self] path in
                if files[path] != nil || links[path] != nil { done.append("remove " + path) }
                files[path] = nil; links[path] = nil
            },
            appBuild: { [self] _ in appBuild },
            agentBuild: { [self] in agentBuild },
            mayKickstart: { [self] in kickstartAllowed },
            note: { _ in },
            // launchd runs what the LaunchAgent file said when it was loaded (sec-fix-4's tests cover the worlds where it does not).
            loadedJob: { [self] in
                guard loaded else { return nil }
                let arguments = (files[I.plistPath(home: oneRowHome)].flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] })?["ProgramArguments"] as? [String]
                return secFix4PrintOut(path: I.plistPath(home: oneRowHome), program: arguments?.first ?? I.agentPath(app: oneRowApp), arguments: arguments ?? [I.agentPath(app: oneRowApp)], pid: nil)
            })
    }

    /// An app with its helper inside.
    static func withApp() -> OneRowWorld {
        let mac = OneRowWorld()
        mac.files[I.agentPath(app: oneRowApp)] = Data("agent".utf8)
        mac.files[I.toolsPath(app: oneRowApp)] = Data("tools".utf8)
        return mac
    }

    func index(_ prefix: String) -> Int? { done.firstIndex { $0.hasPrefix(prefix) } }
}

private func oneRowInstallerTests() {
    let plist = I.plistPath(home: oneRowHome), link = I.toolsLink(home: oneRowHome), tools = I.toolsPath(app: oneRowApp)

    // A new Mac: the app was copied to Applications and opened. No script ran.
    let new = OneRowWorld.withApp()
    check(ArisAgentInstaller.run(new.world()) == .started, "one row install: on a new Mac the app installs and starts its own helper")
    check(new.folders == ["/Users/kim/.config/aris", "/Users/kim/.config/aris/aris"], "one row install: Aris's folder and its data folder are made (mode 700 is the world's own rule)")
    check(I.isSameJob(new.files[plist], app: oneRowApp, home: oneRowHome), "one row install: the LaunchAgent written is the job for this app")
    check(new.links[link] == tools, "one row install: aris-tools in Aris's folder is a link to the one inside the app")
    check(new.done.contains("launchctl bootstrap gui/501 \(plist)") && !new.done.contains { $0.hasPrefix("launchctl kickstart") } && !new.done.contains { $0.hasPrefix("launchctl bootout") },
          "one row install: the job is loaded once, with nothing to stop first")
    check(new.index("write ")! < new.index("launchctl bootstrap")! && new.index("link ")! < new.index("launchctl bootstrap")!,
          "one row install: the file and the link are in place before the helper starts")

    // Again, with everything right: nothing is written, nothing restarted.
    new.done = []
    check(ArisAgentInstaller.run(new.world()) == .running, "one row install: a second launch finds the helper running and does nothing")
    check(new.done.filter { $0.hasPrefix("launchctl") } == ["launchctl print gui/501/com.lumenjsn.aris.agent"] && !new.done.contains { $0.hasPrefix("write") || $0.hasPrefix("link") || $0.hasPrefix("remove") },
          "one row install: launchd is only asked whether the job is loaded; the file and the link are left alone")

    // An install made the old way: the helper's own copy in ~/.config/aris, its job pointing there, and it is running.
    let old = OneRowWorld.withApp()
    let oldJob: [String: Any] = ["Label": "com.lumenjsn.aris.agent", "ProgramArguments": ["/Users/kim/.config/aris/aris-agent"], "RunAtLoad": true, "KeepAlive": true]
    old.files[plist] = try? PropertyListSerialization.data(fromPropertyList: oldJob, format: .xml, options: 0)
    old.files["/Users/kim/.config/aris/aris-agent"] = Data("old agent".utf8)
    old.files[link] = Data("old tools".utf8)
    old.files["/Users/kim/.config/aris/aris-agent.new"] = Data("half".utf8)
    old.files["/Users/kim/.config/aris/claude-hook-token"] = Data("secret".utf8)
    old.files["/Users/kim/.config/aris/aris/schedules.json"] = Data("[]".utf8)
    old.files[I.retiredPlistPath(home: oneRowHome)] = Data("older".utf8)
    old.loaded = true; old.listening = true; old.agentBuild = "old00000"
    check(ArisAgentInstaller.run(old.world()) == .switched, "one row switch: an install made the old way is switched to the helper inside the app")
    check(old.files["/Users/kim/.config/aris/aris-agent"] == nil && old.files["/Users/kim/.config/aris/aris-agent.new"] == nil, "one row switch: the helper's old copies are removed")
    check(old.files[link] == nil && old.links[link] == tools, "one row switch: the old aris-tools file is replaced by the link")
    check(old.files["/Users/kim/.config/aris/claude-hook-token"] != nil && old.files["/Users/kim/.config/aris/aris/schedules.json"] != nil, "one row switch: the token and the data stay")
    check(I.isSameJob(old.files[plist], app: oneRowApp, home: oneRowHome), "one row switch: the job now points inside the app")
    check(old.done.contains("launchctl bootout gui/501/com.lumenjsn.aris.aris-agent") && old.files[I.retiredPlistPath(home: oneRowHome)] == nil,
          "one row switch: the job from before the rename is unloaded and its file removed")
    let bootout = old.index("launchctl bootout gui/501/com.lumenjsn.aris.agent"), write = old.index("write "), remove = old.index("remove /Users/kim/.config/aris/aris-agent"),
        load = old.index("launchctl bootstrap")
    check(bootout != nil && write != nil && remove != nil && load != nil && bootout! < write! && write! < remove! && remove! < load!,
          "one row switch: the old helper is stopped first, then the job is written, the old copies removed, and only then the new one loaded")
    check(old.agentBuild == "new11111", "one row switch: it is done when the helper says it is this app's build")

    // The app was replaced under a running helper (an update): one restart, no rewrite.
    let update = OneRowWorld.withApp()
    update.files[plist] = I.jobData(app: oneRowApp, home: oneRowHome); update.links[link] = tools
    update.loaded = true; update.listening = true; update.agentBuild = "old00000"
    check(ArisAgentInstaller.run(update.world()) == .started, "one row update: a helper of an older build is restarted from the app")
    check(update.done.filter { $0.hasPrefix("launchctl") } == ["launchctl print gui/501/com.lumenjsn.aris.agent", "launchctl kickstart -k gui/501/com.lumenjsn.aris.agent"]
            && !update.done.contains { $0.hasPrefix("write") || $0.hasPrefix("link") }, "one row update: one kickstart, and no file is touched")
    let throttled = OneRowWorld.withApp()
    throttled.files[plist] = I.jobData(app: oneRowApp, home: oneRowHome); throttled.links[link] = tools
    throttled.loaded = true; throttled.listening = true; throttled.agentBuild = "new11111"; throttled.appBuild = "new11111"
    throttled.listening = false; throttled.kickstartAllowed = false
    check(ArisAgentInstaller.run(throttled.world()) == .failed("start") && !throttled.done.contains { $0.hasPrefix("launchctl kickstart") },
          "one row update: inside launchd's ten seconds no second kickstart is sent; the installer only waits")
    check(throttled.slept >= ArisAgentInstaller.answerWait, "one row update: it waits the whole time for the helper to come back before it calls that a failure")

    // At login: launchd has the job loaded and is starting the helper; it opens its port a moment later.
    final class Starting { var looks = 0 }
    let login = OneRowWorld.withApp(), starting = Starting()
    login.files[plist] = I.jobData(app: oneRowApp, home: oneRowHome); login.links[link] = tools
    login.loaded = true; login.listening = false; login.agentBuild = "new11111"
    var loginWorld = login.world()
    loginWorld.listening = { starting.looks += 1; return starting.looks > 6 }
    check(ArisAgentInstaller.run(loginWorld) == .running && !login.done.contains { $0.hasPrefix("launchctl kickstart") },
          "one row login: a helper launchd is still starting is waited for, not restarted (the restart cost every login ten seconds)")
    let dead = OneRowWorld.withApp()
    dead.files[plist] = I.jobData(app: oneRowApp, home: oneRowHome); dead.links[link] = tools
    dead.loaded = true; dead.listening = false; dead.agentBuild = "new11111"
    var deadWorld = dead.world()
    var kicked = false
    let deadLaunchctl = deadWorld.launchctl
    deadWorld.launchctl = { arguments in if arguments.first == "kickstart" { kicked = true }; return deadLaunchctl(arguments) }
    check(ArisAgentInstaller.run(deadWorld) == .started && kicked && dead.slept >= ArisAgentInstaller.startGrace,
          "one row login: one that stays silent for the whole wait is restarted once")

    // The app moved: the link and the job follow.
    let moved = OneRowWorld()
    let elsewhere = "/Users/kim/Applications/Aris.app"
    moved.files[I.agentPath(app: elsewhere)] = Data(); moved.files[I.toolsPath(app: elsewhere)] = Data()
    moved.files[plist] = I.jobData(app: oneRowApp, home: oneRowHome); moved.links[link] = tools
    moved.loaded = true; moved.listening = true; moved.agentBuild = "new11111"
    check(ArisAgentInstaller.run(moved.world(service: elsewhere + "/Contents/XPCServices/ArisXPCHelper.xpc")) == .started, "one row move: an app that was moved gets its job rewritten")
    check(I.isSameJob(moved.files[plist], app: elsewhere, home: oneRowHome) && moved.links[link] == I.toolsPath(app: elsewhere), "one row move: the job and the link point at the app's new place")

    // Refusals write nothing.
    let away = OneRowWorld.withApp()
    away.translocated = true
    check(ArisAgentInstaller.run(away.world()) == .refused(.translocated) && away.done.isEmpty, "one row refusal: a translocated app writes nothing and starts nothing")
    let bare = OneRowWorld()
    check(ArisAgentInstaller.run(bare.world()) == .refused(.noHelper) && bare.done.isEmpty, "one row refusal: an app with no helper inside writes nothing")
    check(ArisAgentInstaller.run(OneRowWorld.withApp().world(service: "/tmp/ArisXPCHelper.xpc")) == .refused(.shape), "one row refusal: an XPC helper outside an app installs nothing")

    // Failures say which step.
    let stuck = OneRowWorld.withApp()
    stuck.loaded = true; stuck.listening = true; stuck.portNeverFrees = true
    check(ArisAgentInstaller.run(stuck.world()) == .failed("port") && stuck.files[plist] == nil, "one row failure: a port the old helper never lets go of stops the install before anything is written")
    let unloadable = OneRowWorld.withApp()
    unloadable.bootstrapFailures = 99
    check(ArisAgentInstaller.run(unloadable.world()) == .failed("load") && unloadable.done.filter { $0.hasPrefix("launchctl bootstrap") }.count == ArisAgentInstaller.loadTries,
          "one row failure: a job launchd won't load is tried five times, then reported")
    let flaky = OneRowWorld.withApp()
    flaky.bootstrapFailures = 2
    check(ArisAgentInstaller.run(flaky.world()) == .started, "one row failure: a load refused twice right after a stop succeeds on the third try")
    let unlinked = OneRowWorld.withApp()
    unlinked.linkFails = true
    check(ArisAgentInstaller.run(unlinked.world()) == .failed("link") && !unlinked.done.contains { $0.hasPrefix("launchctl bootstrap") }, "one row failure: without the link the helper is not started")
}

private func oneRowKickstartTests() {
    let start = Date(timeIntervalSince1970: 1_000)
    check(ArisAgentKickstart.mayKickstart(last: nil, now: start), "one row kickstart: the first restart goes ahead")
    check(!ArisAgentKickstart.mayKickstart(last: start, now: start.addingTimeInterval(3)) && !ArisAgentKickstart.mayKickstart(last: start, now: start.addingTimeInterval(9.9)),
          "one row kickstart: a second one inside launchd's ten seconds is not sent (it would leave the helper down until they pass)")
    check(ArisAgentKickstart.mayKickstart(last: start, now: start.addingTimeInterval(10)), "one row kickstart: after ten seconds it may be restarted again")
    check(ArisAgentKickstart.mayKickstart(last: start, now: start.addingTimeInterval(-60)), "one row kickstart: a clock set back never blocks a restart for good")
    let clock = ArisKickstartClock()
    check(clock.take(now: start) && !clock.take(now: start.addingTimeInterval(5)) && clock.take(now: start.addingTimeInterval(16)), "one row kickstart: the XPC helper keeps the time of its last one")
    final class Count: @unchecked Sendable { var kicks = 0; var answers: [Bool] = [] }
    let count = Count(), shared = ArisKickstartClock()
    let runner: ArisProcessRunner = { _, arguments, done in if arguments.first == "kickstart" { count.kicks += 1 }; done(0) }
    ArisAgentRestart.run(using: runner, uid: 501, mayKickstart: { shared.take(now: start) }) { count.answers.append($0) }
    ArisAgentRestart.run(using: runner, uid: 501, mayKickstart: { shared.take(now: start.addingTimeInterval(2)) }) { count.answers.append($0) }
    check(count.kicks == 1 && count.answers == [true, true], "one row kickstart: the restart button pressed twice kicks once and says the restart is under way both times")
    check(ArisAgentLink.restartWait > ArisAgentKickstart.throttle, "one row kickstart: \"still not connected\" is said only after launchd's ten seconds are over")
    check(ArisAgentLink.restartSettle > ArisAgentKickstart.throttle && ArisAgentLink.quietSettle < ArisAgentKickstart.throttle,
          "one row kickstart: after a quiet restart the app looks again only when launchd's ten seconds are over, so the helper is not called down inside them")
}

private func oneRowOriginTests() {
    typealias O = ArisOrigin
    let tools = "/Applications/Aris.app/Contents/MacOS/aris-tools", agent = "/Applications/Aris.app/Contents/MacOS/aris-agent"
    check(O.app(ofProgram: tools) == "/Applications/Aris.app" && O.app(ofProgram: "/Users/kim/dev/out/aris-tools") == nil
            && O.app(ofProgram: "/Applications/Aris.app/Contents/Helpers/aris-tools") == nil && O.app(ofProgram: "") == nil,
          "one row origin: a program is inside the app only directly in its Contents/MacOS")
    func facts(program: String = tools, me: pid_t = 900, responsible: pid_t? = 500, responsibleProgram: String? = agent, ancestors: [pid_t] = [800, 700, 500],
               job: O.Job? = O.Job(pid: 500, program: agent), answered: Bool = true, signed: Set<pid_t> = [500], looksLikeJob: Bool = false) -> O.Facts {
        O.Facts(me: me, program: program, responsible: responsible, responsibleProgram: responsibleProgram, ancestors: ancestors, job: job, launchdAnswered: answered,
                signedAsAgent: signed, looksLikeJob: looksLikeJob)
    }
    // These pin the rule of the release before (commit 43428e42), which still decides while ArisRollout.enforcing is off;
    // sec-fix-4's tests pin the new rule.
    check(O.mayRunProven(facts()), "one row origin: aris-tools started by an AI that Aris's own helper started runs")
    check(O.mayRunProven(facts(ancestors: [1])), "one row origin: a tool whose starter detached itself still runs: the helper is the process macOS holds responsible")
    check(O.mayRunProven(facts(responsible: nil, responsibleProgram: nil)), "one row origin: where macOS can't say who is responsible, the helper among the parents is enough")
    check(O.mayRunProven(facts(program: "/Users/kim/dev/out/aris-tools", responsible: 900, responsibleProgram: "/Users/kim/dev/out/aris-tools", ancestors: [], job: nil, signed: [])),
          "one row origin: a copy outside the app is its own row in macOS with none of Aris's grants, and is left alone")
    check(O.mayRunProven(facts(responsible: 300, responsibleProgram: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", ancestors: [850, 300], signed: [])),
          "one row origin: started from Terminal it runs on Terminal's own permissions, as before")
    // The hole the follow-up found: any launchd job pointed at the program inside the app.
    check(!O.mayRunProven(facts(responsible: 900, responsibleProgram: tools, ancestors: [], signed: [])),
          "one row origin: aris-tools started by some launchd job is charged to Aris, so it refuses")
    check(O.mayRunProven(facts(responsible: 880, responsibleProgram: "/Users/kim/bin/runner", ancestors: [880], signed: [])),
          "one row origin: whatever program outside the app macOS holds responsible is the one charged, not Aris")
    check(!O.mayRun(facts(responsible: 900, responsibleProgram: tools, ancestors: [880], signed: [])), "one row origin: through a shell, the tool made responsible for itself still refuses")
    check(!O.mayRun(facts(responsible: nil, responsibleProgram: nil, ancestors: [880], signed: [])), "one row origin: not knowing who is responsible is no excuse: without the helper behind it, it refuses")
    check(!O.mayRun(facts(responsible: 600, responsibleProgram: agent, ancestors: [600], job: O.Job(pid: 500, program: agent), signed: [600])),
          "one row origin: another copy of aris-agent running, properly signed, is not Aris's job: refused")
    check(!O.mayRun(facts(signed: [])), "one row origin: launchd's job with the wrong signature is refused")
    check(!O.mayRun(facts(job: O.Job(pid: 500, program: "/Users/kim/evil/aris-agent"))), "one row origin: a job under Aris's label that runs a program from elsewhere is refused")
    check(!O.mayRun(facts(job: O.Job(pid: nil, program: agent))) && !O.mayRun(facts(job: nil)), "one row origin: with Aris's job not running or not loaded, nothing stands behind the tool")
    check(!O.mayRun(facts(responsible: 400, responsibleProgram: "/Applications/Aris.app/Contents/MacOS/Aris", ancestors: [400], signed: [])),
          "one row origin: the app itself is not what starts the tools; only the helper is")
    check(!O.mayRun(facts(responsible: 900, responsibleProgram: tools, ancestors: [], job: O.Job(pid: 900, program: agent), signed: [])),
          "one row origin: a process never vouches for itself")
    check(!O.mayRun(facts(job: nil, answered: false)) && !O.mayRun(facts(job: nil, answered: false, signed: [])),
          "one row origin: if launchd can't be asked at all, nothing stands behind the tool and it refuses (sec4 L1: no guessing)")
    // aris-agent as the server.
    check(O.mayServe(facts(program: agent, me: 500, responsible: 500, responsibleProgram: agent, ancestors: [], signed: [])), "one row origin: aris-agent serves as launchd's job under Aris's label")
    check(!O.mayServe(facts(program: agent, me: 650, responsible: 650, responsibleProgram: agent, ancestors: [], signed: [])), "one row origin: a second aris-agent started by another job does not serve")
    check(!O.mayServe(facts(program: agent, me: 500, job: O.Job(pid: 500, program: "/Users/kim/.config/aris/aris-agent"))), "one row origin: it does not serve when launchd's job is another program")
    check(!O.mayServe(facts(program: agent, me: 500, job: nil)), "one row origin: it does not serve when launchd has no such job")
    check(!O.mayServe(facts(program: agent, me: 500, job: nil, answered: false, looksLikeJob: true)) && !O.mayServe(facts(program: agent, me: 500, job: nil, answered: false, looksLikeJob: false)),
          "one row origin: if launchd can't be asked, aris-agent does not serve, whatever its parent and its environment say (sec4 L1)")
    check(O.mayServe(facts(program: "/Users/kim/dev/out/aris-agent", me: 500, job: nil, signed: [])), "one row origin: a developer's loose aris-agent serves as before")
    // The agent's "is this the Aris app itself" check: the programs inside the app are never the app.
    let app = "/Applications/Aris.app/Contents/MacOS/Aris"
    check(ArisPeer.countedBundleId(reported: "com.lumenjsn.aris", program: app) == "com.lumenjsn.aris", "one row origin: the app's own program counts as the app")
    for helper in [agent, tools, "/Applications/Aris.app/Contents/XPCServices/ArisXPCHelper.xpc/Contents/MacOS/ArisXPCHelper"] {
        check(ArisPeer.countedBundleId(reported: "com.lumenjsn.aris", program: helper) == nil,
              "one row origin: a helper program inside the app is never taken for the app itself, whatever macOS reports for it (\((helper as NSString).lastPathComponent))")
    }
    check(ArisPeer.countedBundleId(reported: "com.lumenjsn.aris", program: nil) == nil && ArisPeer.countedBundleId(reported: nil, program: app) == nil,
          "one row origin: a process whose program can't be read, or that macOS doesn't know as an app, is not the app")
    check(ArisTeammateGate.appCheck(alive: true, bundleId: ArisPeer.countedBundleId(reported: "com.lumenjsn.aris", program: agent), ownsSocket: true, sameConnection: false) == .bundle
            && ArisTeammateGate.appCheck(alive: true, bundleId: ArisPeer.countedBundleId(reported: "com.lumenjsn.aris", program: app), ownsSocket: true, sameConnection: false) == nil,
          "one row origin: so a request that claims to be the app but comes from aris-agent or aris-tools is refused, and the app's own is taken as before")
    check(!O.refusedLine.isEmpty && !O.refusedLine.contains("/") && O.refusedLine.contains("not started by Aris"), "one row origin: the refusal is one plain line with no path in it")
}

private func oneRowBundleTests() {
    check(ArisAppBundle.skillsFolder(home: oneRowHome, app: oneRowApp).path == "/Applications/Aris.app/Contents/Resources/skills",
          "one row: inside the app the helper reads the built-in skill and the pinned requirements from the app, so no script copies them")
    check(ArisAppBundle.skillsFolder(home: oneRowHome, app: nil).path == "/Users/kim/.config/aris/skills", "one row: a loose helper reads them where the old install put them")
    var misses = 0
    var stops: [Bool] = []
    for exists in [true, false, true, false, false] {
        let next = ArisAppBundle.afterLook(misses: misses, exists: exists)
        misses = next.misses
        stops.append(next.stop)
    }
    check(stops == [false, false, false, false, true], "one row: the helper stops itself when its program is missing at two looks in a row (one miss is an update swapping the app)")
    final class Stopped: @unchecked Sendable { var path: String?; let done = DispatchSemaphore(value: 0) }
    let stopped = Stopped()
    ArisAppBundle.watchGone(program: nil, app: nil, stop: { stopped.path = $0 })
    check(stopped.path == nil, "one row: a loose helper never watches for its app")
}

private func oneRowWordsTests() {
    typealias W = ArisHelperInstallWords
    check(W.atLaunch(.running) == nil && W.atLaunch(.started) == nil && W.atLaunch(.switched) == nil, "one row words: when the helper is up nothing is said at launch, after the switch included")
    check(W.atLaunch(.failed("load"), english: true) == ArisAgentCopy.notRunning(english: true), "one row words: a helper that didn't start gets the line that has the restart button")
    check(W.atLaunch(.refused(.noHelper)) == nil, "one row words: a build with no helper inside is said by the prerequisites line, once")
    check(W.diskLineDue(.switched, hadBefore: true, hasNow: false, saidBefore: false), "one row words: someone whose old helper read Messages and Mail is told once that Aris needs Full Disk Access")
    check(!W.diskLineDue(.switched, hadBefore: false, hasNow: false, saidBefore: false) && !W.diskLineDue(.switched, hadBefore: nil, hasNow: false, saidBefore: false),
          "one row words: someone who never gave it, or of whom it isn't known, is told nothing")
    check(!W.diskLineDue(.switched, hadBefore: true, hasNow: true, saidBefore: false) && !W.diskLineDue(.switched, hadBefore: true, hasNow: nil, saidBefore: false)
            && !W.diskLineDue(.switched, hadBefore: true, hasNow: false, saidBefore: true) && !W.diskLineDue(.started, hadBefore: true, hasNow: false, saidBefore: false)
            && !W.diskLineDue(.running, hadBefore: true, hasNow: false, saidBefore: false),
          "one row words: not when it already works, not twice, and never on a launch that switched nothing")
    for english in [true, false] {
        check(ArisAppFix.fix(forLine: W.diskAfterSwitch(english: english)) == .pane(.disk), "one row words: the Full Disk Access line has the button that opens that list")
        check(ArisAppFix.fix(forLine: W.move(english: english)) == .showApp, "one row words: the move line has the button that shows Aris in Finder")
        check(ArisAppFix.fix(forLine: W.notTyped(appSwitchOn: true, english: english)) == .pane(.accessibility) && ArisAppFix.fix(forLine: W.notTyped(appSwitchOn: false, english: english)) == .pane(.accessibility),
              "one row words: a dictation the helper could not type says so with the button that opens Accessibility")
        for line in [W.diskAfterSwitch(english: english), W.move(english: english), W.accessibilityLost(english: english), W.accessibilityOff(english: english)] {
            check(!line.contains("aris-agent") && !line.contains("~/") && line.count < 90, "one row words: one short line that never names aris-agent or a path (\(line))")
        }
    }
    check(W.notTyped(appSwitchOn: true, english: true) != W.notTyped(appSwitchOn: false, english: true), "one row words: with Aris's own switch on, the line says to switch it off and on, not on")
    check(W.mappingLost(appSwitchOn: true, helperSays: false) && !W.mappingLost(appSwitchOn: true, helperSays: true) && !W.mappingLost(appSwitchOn: true, helperSays: nil)
            && !W.mappingLost(appSwitchOn: false, helperSays: false), "one row words: the log line is for Aris's switch on and the helper's own answer off, nothing else")
    check(ArisFix.showApp.isValid && !ArisFix(kind: .showApp, target: "/Applications/Other.app").isValid && ArisFixWords.title(.showApp, english: true) == "Show Aris in Finder",
          "one row words: the Finder button shows only Aris itself; one that names a file is dropped")
    check(ArisPrerequisites.helperInstalled(app: oneRowApp) { $0.hasSuffix("/aris-agent") || $0.hasSuffix("/aris-tools") }
            && !ArisPrerequisites.helperInstalled(app: oneRowApp) { $0.hasSuffix("/aris-agent") } && !ArisPrerequisites.helperInstalled(app: oneRowApp) { _ in false },
          "one row words: the helper is installed when the app carries both programs")
    check(ArisPrerequisites.helperPath(app: oneRowApp) == I.agentPath(app: oneRowApp), "one row words: the helper's place is inside the app")
    for english in [true, false] {
        let said = ArisPrerequisites.full(.helper, english: english)
        check(!said.contains("install-aris-agent") && !said.contains("installer") && !said.contains("설치 프로그램"), "one row words: a build with no helper is never sent to an installer script (\(said))")
    }
    check(ArisBuildInfo.mismatch(app: "new11111", agent: "old00000")?.contains("install-aris-agent") == false && ArisBuildInfo.mismatch(app: "new11111", agent: nil)?.contains(".sh") == false,
          "one row words: a helper of another build is restarted by the app, and the log no longer tells anyone to run a script")
}

private func oneRowCaptureTests() {
    typealias C = ArisFirstCapture
    let now = Date(timeIntervalSince1970: 10_000_000), day: TimeInterval = 24 * 3_600
    check(C.appCaptureDue(screenGranted: true, lastAllowed: nil, lastTry: nil, now: now), "one row capture: with no yes on record the app captures before the helper does")
    check(!C.appCaptureDue(screenGranted: false, lastAllowed: nil, lastTry: nil, now: now), "one row capture: with Screen Recording off nothing is captured")
    check(!C.appCaptureDue(screenGranted: true, lastAllowed: now.addingTimeInterval(-24 * day), lastTry: nil, now: now), "one row capture: a yes from 24 days ago still stands")
    check(C.appCaptureDue(screenGranted: true, lastAllowed: now.addingTimeInterval(-26 * day), lastTry: nil, now: now),
          "one row capture: after 25 days the app captures again first, so macOS's monthly question names Aris and not the helper's file")
    check(!C.appCaptureDue(screenGranted: true, lastAllowed: nil, lastTry: now.addingTimeInterval(-60), now: now) && C.appCaptureDue(screenGranted: true, lastAllowed: nil, lastTry: now.addingTimeInterval(-601), now: now),
          "one row capture: a try that brought no yes is not repeated at every request, only after ten minutes")
    check(C.appCaptureDue(screenGranted: true, lastAllowed: now.addingTimeInterval(day), lastTry: nil, now: now), "one row capture: a date in the future (the clock was set back) counts as no record")
}

private func oneRowSourceTests() {
    let service = oneRowCode("Shared/ArisHelperService.swift")
    check(service.contains("func installAgent(reply: @escaping (String) -> Void)"), "one row source: the XPC call that installs the helper takes nothing from its caller")
    let listener = oneRowCode("ArisXPCHelper/ArisHelperServiceObject.swift")
    check(listener.contains("connection.setCodeSigningRequirement(ArisXPCTrust.requirement(peer: ArisXPCTrust.appId))"), "one row source: the XPC helper still takes connections from Aris itself only")
    let live = oneRowCode("ArisXPCHelper/ArisAgentInstallLive.swift")
    check(live.contains("servicePath: Bundle.main.bundleURL") && live.contains("ArisSafeFiles.replaceLink(target: target, at: path)") && live.contains("ArisSafeFiles.write($0, to: $1)")
            && oneRowCode("Shared/ArisSafeFiles.swift").contains("rename(beside, path)") && oneRowCode("Shared/ArisSafeFiles.swift").contains("symlink(target, beside)") && oneRowCode("Shared/ArisSafeFiles.swift").contains("O_NOFOLLOW"),
          "one row source: the app's place comes from the XPC helper's own bundle, and the file and the link are made beside their place and renamed over it")
    let tools = oneRowCode("ArisTools/main.swift")
    if let gate = tools.range(of: "ArisOrigin.allows(startFacts, serving: false)"), let version = tools.range(of: "arguments.first == \"--version\""), let job = tools.range(of: "let teammateJob") {
        check(version.lowerBound < gate.lowerBound && gate.lowerBound < job.lowerBound, "one row source: aris-tools asks who started it before it does anything but print its version")
    } else {
        check(false, "one row source: aris-tools asks who started it before it does anything but print its version")
    }
    let agent = oneRowCode("ArisAgent/main.swift")
    if let gate = agent.range(of: "ArisOrigin.allows(origin, serving: !helperMode)"), let helper = agent.range(of: "ArisAPIHelper.runProcess()"), let stamp = agent.range(of: "ArisBuildInfo.recordRunningAgent") {
        check(gate.lowerBound < helper.lowerBound && gate.lowerBound < stamp.lowerBound, "one row source: aris-agent asks who started it before any of its modes runs")
    } else {
        check(false, "one row source: aris-agent asks who started it before any of its modes runs")
    }
    check(agent.contains("ArisAppBundle.watchGone()") && !agent.contains("\"firstCapture\""), "one row source: the helper watches for its app, and takes no first capture of its own")
    check(!oneRowCode("ArisTools/ArisScreen.swift").contains("--first"), "one row source: aris-tools has no capture made only to raise macOS's question")
    let client = oneRowCode("Aris/private/Aris/ArisAgentClient.swift")
    check(client.components(separatedBy: "await ArisAppCaptureFirst.ensure()").count == 3, "one row source: the app's own capture comes before a look and before a turn")
    // No line a user or an AI reads tells anyone to switch on "aris-agent" or to pick its file.
    let userFacing = ["Aris/private/Aris/ArisWidget.swift", "Aris/private/Aris/ArisIntent.swift", "Aris/private/Aris/ArisUIWords.swift", "Aris/components/Settings/ArisLiveSettings.swift",
                      "Aris/components/Settings/ArisSettingsSnapshot.swift", "Aris/components/Settings/ArisSettingsBuilder.swift", "Aris/components/Settings/Settings.xcstrings",
                      "Aris/private/Aris/Onboarding/ArisOnboardingWords.swift", "Aris/private/Aris/ArisPermissionGuide.swift", "ArisAgent/ArisDesktopCopy.swift",
                      "ArisAgent/ArisScreenRead.swift", "ArisAgent/ArisClaudeJobWords.swift", "ArisTools/ArisLocalStore.swift", "ArisTools/ArisWindows.swift"]
    for file in userFacing {
        let lines = oneRowCode(file).components(separatedBy: "\n").filter { line in
            let code = line.trimmingCharacters(in: .whitespaces)
            return !code.hasPrefix("//") && (code.contains("aris-agent를") || code.contains("aris-agent에") || code.contains("aris-agent가") || code.contains("(aris-agent)")
                || code.contains("for aris-agent") || code.contains("allow aris-agent") || code.contains("aris-agent on") || code.contains("config/aris/aris-agent"))
        }
        check(lines.isEmpty, "one row source: \(file) names only Aris where it tells someone which switch to turn on\(lines.first.map { " (\($0.prefix(80)))" } ?? "")")
    }
    for gone in ["Aris/private/Aris/ArisHelperRow.swift", "Aris/private/Aris/ArisHelperRowsLive.swift", "Aris/private/Aris/Onboarding/ArisOnboardingTwoSwitches.swift",
                 "Aris/private/Aris/Dictation/ArisDictationHelperOff.swift", "Aris/private/Aris/ArisHelperFirstCapture.swift", "ArisAgent/ArisHelperCapture.swift"] {
        check(oneRowCode(gone).isEmpty, "one row source: the second row's code is gone (\(gone))")
    }
    let entitlements = oneRowCode("ArisAgent/ArisAgent.entitlements")
    check(entitlements.contains("com.apple.security.automation.apple-events") && !entitlements.contains("disable-library-validation") && !entitlements.contains("allow-dyld-environment-variables"),
          "one row source: under the hardened runtime the helper may send Apple events, and nothing lets another program's library in")
}

// MARK: - What macOS calls each list (macOS 27 renamed Accessibility)

private func oneRowPaneNameTests() {
    typealias P = ArisFix.Pane
    check(P.accessibility.title(english: true, osMajor: 26) == "Accessibility" && P.accessibility.title(english: false, osMajor: 26) == "손쉬운 사용"
            && P.accessibility.title(english: true, osMajor: 14) == "Accessibility", "pane names: up to macOS 26 the list is Accessibility / 손쉬운 사용")
    check(P.accessibility.title(english: true, osMajor: 27) == "Device Control and Data Access" && P.accessibility.title(english: false, osMajor: 27) == "기기 제어 및 데이터 접근"
            && P.accessibility.title(english: true, osMajor: 28) == "Device Control and Data Access",
          "pane names: from macOS 27 it is Device Control and Data Access / 기기 제어 및 데이터 접근 (macOS's own words)")
    check(P.accessibility.anchor == "Privacy_Accessibility" && P.accessibility.rawValue == "accessibility", "pane names: the link and the fix's own word did not change with the name")
    check(P.screen.title(english: true, osMajor: 14) == "Screen Recording" && P.screen.title(english: false, osMajor: 14) == "화면 기록"
            && P.screen.title(english: true, osMajor: 15) == "Screen & System Audio Recording" && P.screen.title(english: false, osMajor: 26) == "화면 및 시스템 오디오 녹음"
            && P.screen.title(english: true, osMajor: 27) == "Screen & System Audio Recording",
          "pane names: the Screen Recording list is Screen & System Audio Recording from macOS 15, in both languages")
    check(P.screen.permission(english: true, osMajor: 27) == "Screen Recording" && P.screen.permission(english: false, osMajor: 27) == "화면 기록"
            && P.accessibility.permission(english: true, osMajor: 27) == "Device Control and Data Access",
          "pane names: in a sentence the screen permission keeps its short name; Accessibility's changes with the list")
    check(P.disk.title(english: true, osMajor: 27) == "Full Disk Access" && P.disk.title(english: false, osMajor: 26) == "전체 디스크 접근 권한"
            && P.folders.title(english: true) == "Files & Folders" && P.automation.title(english: false) == "자동화",
          "pane names: Full Disk Access, Files & Folders and Automation are called the same on 26 and 27")
    check(P.allCases.allSatisfy { pane in [14, 15, 26, 27].allSatisfy { !pane.title(english: true, osMajor: $0).isEmpty && !pane.title(english: false, osMajor: $0).isEmpty } },
          "pane names: every list has a name in both languages on every macOS")
    check(P.accessibility.renamed(in: "Allow Accessibility", english: true, osMajor: 27) == "Allow Device Control and Data Access"
            && P.accessibility.renamed(in: "손쉬운 사용을 허용했어요.", english: false, osMajor: 27) == "기기 제어 및 데이터 접근을 허용했어요."
            && P.accessibility.renamed(in: "Allow Accessibility", english: true, osMajor: 26) == "Allow Accessibility",
          "pane names: a translated line that carries the old name is said with this macOS's name")

    // Every place that names the list, on macOS 26 and on 27.
    func on<T>(_ major: Int, _ body: () -> T) -> T {
        let before = P.osMajorForTests
        P.osMajorForTests = major
        defer { P.osMajorForTests = before }
        return body()
    }
    for (major, english, korean, gone, goneKorean) in [(26, "Accessibility", "손쉬운 사용", "Device Control", "기기 제어"), (27, "Device Control and Data Access", "기기 제어 및 데이터 접근", "Accessibility", "손쉬운 사용")] {
        on(major) {
            let lines: [(String, String)] = [
                ("the fix button", ArisFixWords.title(.pane(.accessibility), english: true)),
                ("a dictation that could not be typed", ArisHelperInstallWords.notTyped(appSwitchOn: false, english: true)),
                ("a dictation the helper may not type", ArisHelperInstallWords.notTyped(appSwitchOn: true, english: true)),
                ("the arrange failure", ArisIntent.arrangeFailure("accessibility", app: "Safari", korean: false)),
                ("the helper's status line", ArisDesktopCopy.needsAccessibility(english: true)),
                ("the helper's line for the AI", ArisDesktopCopy.accessLine),
                ("the helper's line for the AI, for a Korean speaker", ArisDesktopEngine.accessLine),
                ("the selection that could not be read", ArisScreenRead.unselectedLine),
                ("the paste the helper refuses", ArisInsertRefusal.needsAccessibility),
                ("the setup's card", ArisFix.Pane.accessibility.renamed(in: "Allow Accessibility", english: true)),
                ("the panel beside System Settings", ArisFix.Pane.accessibility.renamed(in: "Drag Aris into the Accessibility list, then turn its switch on.", english: true)),
            ]
            for (what, line) in lines {
                check(line.contains(english) && !line.contains(gone), "pane names (macOS \(major)): \(what) names the list as that macOS does (\(line.prefix(70)))")
            }
            let koreanLines: [(String, String)] = [
                ("the fix button", ArisFixWords.title(.pane(.accessibility), english: false)),
                ("a dictation that could not be typed", ArisHelperInstallWords.notTyped(appSwitchOn: false, english: false)),
                ("the arrange failure", ArisIntent.arrangeFailure("accessibility", app: "Safari", korean: true)),
                ("the helper's status line", ArisDesktopCopy.needsAccessibility(english: false)),
                ("the helper's Korean sentence for the AI", ArisDesktopEngine.accessLine),
                ("the diagnostics report", ArisPermissionCard.accessibility == .accessibility ? ArisFix.Pane.accessibility.title(english: false) : ""),
            ]
            for (what, line) in koreanLines {
                check(line.contains(korean) && !line.contains(goneKorean), "pane names (macOS \(major), Korean): \(what) names the list as that macOS does (\(line.prefix(50)))")
            }
            // The helper's Korean status line is translated by the app's table for an English UI: it must be there.
            check(ArisUIWords.status(ArisDesktopCopy.needsAccessibility(english: false), english: true) == ArisDesktopCopy.needsAccessibility(english: true),
                  "pane names (macOS \(major)): the helper's Korean status line still turns into its English one")
            check(ArisAppFix.fix(forLine: ArisHelperInstallWords.notTyped(appSwitchOn: true, english: true)) == .pane(.accessibility)
                    && ArisAppFix.fix(forLine: ArisIntent.arrangeFailure("accessibility", app: "", korean: true)) == .pane(.accessibility),
                  "pane names (macOS \(major)): the lines keep their button whatever the list is called")
        }
    }
    check(on(27) { ArisScreenRead.listName(macOSMajor: 27) } == "Screen & System Audio Recording" && ArisScreenRead.listName(macOSMajor: 14) == "Screen Recording",
          "pane names: the helper's own name for the screen list is the same lookup")
    check(on(26) { ArisLocalStore.screenLine(.noPermission, korean: false) }.contains("Privacy & Security › Screen & System Audio Recording")
            && on(26) { ArisLocalStore.screenLine(.noPermission, korean: true) }.contains("› 화면 및 시스템 오디오 녹음에서"),
          "pane names: a screen read that needs the permission sends the user to the list by the name it has")
    // Wiring: the places that are not pure take the name from the same function.
    let live = oneRowCode("Aris/components/Settings/ArisLiveSettings.swift"), catalog = oneRowCode("Aris/components/Settings/ArisSettingsCatalog.swift")
    check(live.contains(".init(id: \"ax\", title: ArisFix.Pane.accessibility.title(english: false)") && live.contains(".init(id: \"screen\", title: ArisFix.Pane.screen.title(english: false)")
            && catalog.contains("e(\"control.ax\", .control, ArisFix.Pane.accessibility.title(english: false)"),
          "pane names: Settings › Computer control's rows and the search take the lists' names from the lookup")
    let copy = oneRowCode("Aris/private/Aris/Onboarding/ArisOnboardingCopy.swift")
    check(["onboarding.perms.ax.title", "onboarding.perms.ax.done", "onboarding.mac.pane.ax", "onboarding.drag.ax", "onboarding.drag.ax.done"].allSatisfy { copy.contains("axNamed(String(localized: \"\($0)\"") }
            && !copy.contains("axNamed(String(localized: \"onboarding.mac.side.accessibility\""),
          "pane names: the setup's card, the panel's instruction and the pictured list are renamed; the pictured sidebar's Accessibility item (another thing) is not")
    let table = oneRowCode("Aris/components/Settings/Settings.xcstrings")
    check(table.contains("\"기기 제어 및 데이터 접근\"") && table.contains("\"Device Control and Data Access\"") && table.contains("\"화면 및 시스템 오디오 녹음\""),
          "pane names: the Settings translations know the new names")
    for file in ["ArisTools/ArisWindows.swift", "ArisTools/main.swift", "ArisTools/ArisNoteCommand.swift"] {
        let code = oneRowCode(file).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        check(!code.contains("\"Accessibility permission needed") && !code.contains("Accessibility is off\"") && code.contains("ArisFix.Pane.accessibility.title(english: true)"),
              "pane names: \(file) names the list through the lookup")
    }
}
