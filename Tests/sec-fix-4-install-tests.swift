// Tests for security review 4: M7 (the installer decides from what launchd has loaded, verifies the app before it
// writes or loads anything, and replaces and reports a job under Aris's label that runs anything else), M4 (the
// one-time line about the old helper's rows), L2 (which copy of Aris may take the helper's place), L3 (the XPC
// helper's entitlement) and L5 (the installer's file handling, and the home folder).
// The launchd print-outs are written here in the shape that was measured (qa/design-1111/one-row-experiment.md, U3);
// files are made in a throwaway folder. Called from runSecFix4Tests(); uses main.swift's check().
import Foundation

func secFix4InstallTests() {
    secFix4LoadedJobTests()
    secFix4InstallerTests()
    secFix4TakeoverTests()
    secFix4OldRowsTests()
    secFix4FilesTests()
    secFix4EntitlementTests()
}

private typealias Install = ArisAgentInstall
private let installRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func installCode(_ path: String) -> String {
    ((try? String(contentsOf: installRoot.appendingPathComponent(path), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

/// `launchctl print gui/501/<label>` as launchd prints it: the job's lines one tab in, its arguments as a list.
func secFix4PrintOut(path: String, program: String, arguments: [String], pid: Int32?, label: String = "com.lumenjsn.aris.agent") -> String {
    var lines = ["gui/501/\(label) = {", "\tactive count = \(pid == nil ? 0 : 1)", "\tpath = \(path)", "\ttype = LaunchAgent", "\tstate = \(pid == nil ? "not running" : "running")", "",
                 "\tprogram = \(program)", "\targuments = {"] + arguments.map { "\t\t\($0)" } + ["\t}", "", "\tinherited environment = {", "\t\tSSH_AUTH_SOCK = /private/tmp/x/Listeners",
                 "\t\tpath = /tmp/not-the-job", "\t}", "", "\tdefault environment = {", "\t\tPATH = /usr/bin:/bin:/usr/sbin:/sbin", "\t}", "", "\tdomain = gui/501 [100003]", "\tminimum runtime = 10"]
    if let pid { lines.append("\tpid = \(pid)") }
    return (lines + ["\tspawn type = interactive (4)", "\tproperties = keepalive | runatload", "}"]).joined(separator: "\n")
}

private let home = "/Users/kim", app = "/Applications/Aris.app"
private let agent = app + "/Contents/MacOS/aris-agent", plist = "/Users/kim/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"

private func secFix4LoadedJobTests() {
    typealias J = ArisLoadedJob
    let own = J.parse(secFix4PrintOut(path: plist, program: agent, arguments: [agent], pid: 812))
    check(own == J(path: plist, program: agent, arguments: [agent], pid: 812) && own.starts(agent), "sec4 M7: launchd's print-out is read: the file the job came from, the program it executes, its arguments, its process")
    check(own.kind(agent: agent, plist: plist, running: agent, isArisAgent: { _ in true }) == .own, "sec4 M7: this app's helper, loaded from Aris's file and running that program, is its own")
    check(J.parse(secFix4PrintOut(path: plist, program: agent, arguments: [agent], pid: nil)).kind(agent: agent, plist: plist, running: nil, isArisAgent: { _ in true }) == .own,
          "sec4 M7: so is the same job while it has no process")
    // The measured shapes (U3): launchd executes Program and prints both keys.
    let script = J.parse(secFix4PrintOut(path: plist, program: "/tmp/x.sh", arguments: [agent, "--agent", "u3a"], pid: 3104))
    check(script.program == "/tmp/x.sh" && script.arguments == [agent, "--agent", "u3a"] && !script.starts(agent)
            && script.kind(agent: agent, plist: plist, running: agent, isArisAgent: { _ in true }) == .foreign,
          "sec4 M7: a job whose Program is a script and whose first argument names the helper (U3, case A) is another program, though its process is the real helper by now")
    for (what, job, running) in [
        ("a shell that execs the helper", J(path: plist, program: "/bin/sh", arguments: ["/bin/sh", "-c", "exec " + agent], pid: 5), agent),
        ("env", J(path: plist, program: "/usr/bin/env", arguments: ["/usr/bin/env", agent], pid: 5), agent),
        ("the helper with extra arguments", J(path: plist, program: agent, arguments: [agent, "--usage-report"], pid: 5), agent),
        ("the helper under another first argument (U3, case B)", J(path: plist, program: agent, arguments: ["/tmp/x.sh", "--agent"], pid: 5), agent),
        ("a job loaded from another file", J(path: "/Users/kim/evil.plist", program: agent, arguments: [agent], pid: 5), agent),
        ("a job whose process is not the program launchd was told to start", J(path: plist, program: agent, arguments: [agent], pid: 5), "/tmp/evil"),
        ("a job whose process can't be read", J(path: plist, program: agent, arguments: [agent], pid: 5), String?.none),
        ("another program entirely", J(path: plist, program: "/Users/kim/bin/miner", arguments: ["/Users/kim/bin/miner"], pid: 5), "/Users/kim/bin/miner"),
        ("a job launchd says nothing about", J(), nil)] {
        check(job.kind(agent: agent, plist: plist, running: running, isArisAgent: { _ in true }) == .foreign, "sec4 M7: \(what) under Aris's label is another program")
    }
    let copy = "/Users/kim/Desktop/Aris.app/Contents/MacOS/aris-agent", old = "/Users/kim/.config/aris/aris-agent"
    check(J(path: plist, program: copy, arguments: [copy], pid: 9).kind(agent: agent, plist: plist, running: copy, isArisAgent: { _ in true }) == .otherAris(program: copy)
            && J(path: plist, program: old, arguments: [old], pid: nil).kind(agent: agent, plist: plist, running: nil, isArisAgent: { _ in true }) == .otherAris(program: old),
          "sec4 M7: the helper of another copy of Aris, or of the install made the old way, is Aris's and not “another program”")
    check(J(path: plist, program: copy, arguments: [copy], pid: 9).kind(agent: agent, plist: plist, running: copy, isArisAgent: { _ in false }) == .foreign,
          "sec4 M7: a file named aris-agent that is not signed as Aris's is another program")
    check(J(path: plist, program: copy, arguments: [copy], pid: nil).kind(agent: agent, plist: plist, running: nil, isArisAgent: { _ in false }, exists: { _ in false }) == .otherAris(program: copy),
          "sec4 M7: a helper whose app was moved or deleted is still Aris's, only gone (the app that is opened takes its place, and nothing is said about “another program”)")
    check(J.parse("") == J() && J.parse("Could not find service \"com.lumenjsn.aris.agent\" in domain for port") == J()
            && J.parse(secFix4PrintOut(path: plist, program: agent, arguments: [agent], pid: nil)).pid == nil,
          "sec4 M7: text that is no print-out gives a job with nothing in it; a job that isn't running has no process")
    check(J.parse("x = {\n\tpath = /a\n\tpath = /b\n\tenvironment = {\n\t\tprogram = /evil\n\t\tpid = 7\n\t}\n\tprogram = /p\n}").program == "/p"
            && J.parse("x = {\n\tpath = /a\n\tpath = /b\n}").path == "/a" && J.parse("x = {\n\tenvironment = {\n\t\tpid = 7\n\t}\n}").pid == nil,
          "sec4 M7: only the job's own lines count: a variable named program, path or pid inside its environment is not read as the job's")
}

/// A Mac as the installer sees it, with launchd's own record apart from the file on disk.
private final class Mac {
    var files: [String: Data] = [:]
    var links: [String: String] = [:]
    var loaded: ArisLoadedJob?
    var running: [Int32: String] = [:]
    var listening = false
    var verifies = true
    var shared = false
    var builtAt: [String: Double] = [:]
    var notes: [String] = []
    var done: [String] = []

    init(app: String = "/Applications/Aris.app") {
        files[Install.agentPath(app: app)] = Data("agent".utf8)
        files[Install.toolsPath(app: app)] = Data("tools".utf8)
    }

    func world(app: String = "/Applications/Aris.app") -> ArisAgentInstallWorld {
        ArisAgentInstallWorld(
            servicePath: app + "/Contents/XPCServices/ArisXPCHelper.xpc", home: home, uid: 501,
            launchctl: { [self] arguments in
                done.append("launchctl " + arguments.joined(separator: " "))
                switch arguments.first {
                case "print": return loaded == nil ? 113 : 0
                case "bootout":
                    if arguments.last == "gui/501/com.lumenjsn.aris.agent" { loaded = nil; listening = false }
                    return 0
                case "bootstrap":
                    // launchd loads what the file says.
                    let arguments = (files[plist].flatMap { try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any] })?["ProgramArguments"] as? [String] ?? []
                    loaded = ArisLoadedJob(path: plist, program: arguments.first, arguments: arguments, pid: 900)
                    running[900] = arguments.first
                    listening = true
                    return 0
                default: return 0
                }
            },
            listening: { [self] in listening }, sleep: { _ in },
            exists: { [self] in files[$0] != nil || links[$0] != nil }, isFile: { [self] in files[$0] != nil }, read: { [self] in files[$0] },
            linkTarget: { [self] in links[$0] }, isTranslocated: { _ in false }, isReadOnly: { _ in false },
            makePrivateFolder: { [self] in done.append("folder " + $0); return true },
            write: { [self] data, path in files[path] = data; done.append("write " + path); return true },
            link: { [self] target, path in files[path] = nil; links[path] = target; done.append("link " + path); return true },
            remove: { [self] in files[$0] = nil; links[$0] = nil },
            appBuild: { _ in "dev" }, agentBuild: { nil }, mayKickstart: { true }, note: { [self] in notes.append($0) },
            loadedJob: { [self] in loaded.map { secFix4PrintOut(path: $0.path ?? "-", program: $0.program ?? "-", arguments: $0.arguments, pid: $0.pid) } },
            programOf: { [self] in running[$0] },
            verifies: { [self] _ in verifies },
            isArisAgent: { [self] in files[$0] == Data("agent".utf8) },
            othersCanWrite: { [self] _ in shared },
            builtAt: { [self] in builtAt[$0] })
    }

    /// The right file on disk, the right link, the helper answering.
    func installed(app: String = "/Applications/Aris.app") -> Mac {
        files[plist] = Install.jobData(app: app, home: home)
        links[Install.toolsLink(home: home)] = Install.toolsPath(app: app)
        loaded = ArisLoadedJob(path: plist, program: Install.agentPath(app: app), arguments: [Install.agentPath(app: app)], pid: 700)
        running[700] = Install.agentPath(app: app)
        listening = true
        return self
    }
}

private func secFix4InstallerTests() {
    let right = Mac().installed()
    check(ArisAgentInstaller.run(right.world(), enforcing: true) == .running && !right.done.contains { $0.hasPrefix("write") || $0.contains("bootout") || $0.contains("bootstrap") },
          "sec4 M7: this app's helper, as launchd has it, is left running and nothing is written")
    // The hijack the review describes: the file on disk is right, something answers on the port, and launchd runs another program under the label.
    let hijacked = Mac().installed()
    hijacked.loaded = ArisLoadedJob(path: "/Users/kim/evil.plist", program: "/tmp/x.sh", arguments: [agent], pid: 3104)
    hijacked.running[3104] = agent
    check(ArisAgentInstaller.run(hijacked.world(), enforcing: true) == .replaced, "sec4 M7: a job under Aris's label that runs another program is replaced though the file on disk is right and the port answers, and the app is told")
    check(hijacked.loaded == ArisLoadedJob(path: plist, program: agent, arguments: [agent], pid: 900) && hijacked.done.contains("launchctl bootout gui/501/com.lumenjsn.aris.agent")
            && hijacked.done.contains("write " + plist) && hijacked.notes.contains { $0.contains("another program is loaded under Aris's label") && $0.contains("/tmp/x.sh") },
          "sec4 M7: it is unloaded, Aris's own job is written and loaded, and the log says what was there")
    if let out = hijacked.done.firstIndex(of: "launchctl bootout gui/501/com.lumenjsn.aris.agent"), let write = hijacked.done.firstIndex(of: "write " + plist),
       let load = hijacked.done.firstIndex(where: { $0.hasPrefix("launchctl bootstrap") }) {
        check(out < write && write < load, "sec4 M7: unloaded first, then written, then loaded")
    } else {
        check(false, "sec4 M7: unloaded first, then written, then loaded")
    }
    check(ArisAgentInstaller.run(hijacked.world(), enforcing: true) == .running, "sec4 M7: the next look finds Aris's own helper and says nothing more")
    let silent = Mac().installed()
    silent.loaded = ArisLoadedJob()
    check(ArisAgentInstaller.run(silent.world(), enforcing: true) == .replaced, "sec4 M7: a job launchd has but describes as nothing of Aris's is replaced too")
    let wrongProcess = Mac().installed()
    wrongProcess.running[700] = "/tmp/evil"
    check(ArisAgentInstaller.run(wrongProcess.world(), enforcing: true) == .replaced, "sec4 M7: so is a job whose process is not the program launchd was told to start")
    // Verified before anything is written or loaded.
    let changed = Mac()
    changed.verifies = false
    check(ArisAgentInstaller.run(changed.world(), enforcing: true) == .refused(.changed) && changed.done.isEmpty && changed.files[plist] == nil,
          "sec4 M7: an app that no longer verifies as Aris's (the bundle, or one of the two programs) gets nothing written, loaded or even asked of launchd")
    let changedRunning = Mac().installed()
    changedRunning.verifies = false
    check(ArisAgentInstaller.run(changedRunning.world(), enforcing: true) == .refused(.changed) && changedRunning.loaded?.pid == 700, "sec4 M7: and nothing that runs is touched for it")
    check(ArisAgentInstallOutcome.replaced.word == "replaced" && ArisAgentInstallOutcome(word: "replaced") == .replaced && ArisAgentInstallOutcome.replaced.isUp
            && ArisAgentInstallOutcome(word: "refused:changed") == .refused(.changed) && !ArisAgentInstallOutcome.refused(.changed).isUp,
          "sec4 M7: both answers cross XPC whole")
    check(ArisHelperInstallWords.atLaunch(.replaced, english: false) == "Aris의 도우미 자리에 다른 프로그램이 등록돼 있어서 바꿨어요."
            && ArisHelperInstallWords.atLaunch(.replaced, english: true)?.contains("replaced it") == true && ArisHelperInstallWords.atLaunch(.started) == nil
            && ArisHelperInstallWords.atLaunch(.refused(.changed), english: false)?.contains("다시 설치해 주세요") == true,
          "sec4 M7: the app says once that another program sat in the helper's place and was replaced; a changed copy is told to install Aris again")
    check(Install.step(Install.Found(sameJob: true, loaded: true, answering: true, retiredCopy: false, appBuild: "a", agentBuild: "a", loadedKind: .foreign)) == .reinstall
            && Install.step(Install.Found(sameJob: true, loaded: true, answering: true, retiredCopy: false, appBuild: "a", agentBuild: "a", loadedKind: .otherAris(program: "/x/aris-agent"))) == .reinstall
            && Install.step(Install.Found(sameJob: true, loaded: true, answering: true, retiredCopy: false, appBuild: "a", agentBuild: "a", loadedKind: .own)) == .none
            && Install.step(Install.Found(sameJob: true, loaded: false, answering: false, retiredCopy: false, appBuild: "a", agentBuild: "a", loadedKind: nil)) == .load,
          "sec4 M7: the step follows launchd's own record: anything but this app's helper under the label is reinstalled, whatever the file says")
    check(Install.agentSigningId == ArisOrigin.agentSigningId && Install.toolsSigningId == ArisOrigin.toolsSigningId && Install.appId == ArisXPCTrust.appId,
          "sec4 M7: the installer verifies the programs under the identifiers they check each other by")
    let live = installCode("ArisXPCHelper/ArisAgentInstallLive.swift")
    check(live.contains("loadedJob: { capture(ArisAgentKickstart.launchctl, ArisAgentInstall.printArguments(uid: getuid())) }") && live.contains("proc_pidpath(pid, &buffer, UInt32(buffer.count))")
            && live.contains("kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures") && live.contains("SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: flags), wanted)")
            && live.contains("ArisXPCTrust.requirement(peer: identifier)"),
          "sec4 M7: wiring: the real world asks launchctl print, the process's real program, and the signatures (strict, nested code, own team)")
    let installer = installCode("ArisXPCHelper/ArisAgentInstaller.swift")
    if let verify = installer.range(of: "if !world.verifies(app), refuses(.changed"), let folder = installer.range(of: "guard world.makePrivateFolder"), let ask = installer.range(of: "world.launchctl(ArisAgentInstall.printArguments") {
        check(verify.lowerBound < folder.lowerBound && folder.lowerBound < ask.lowerBound, "sec4 M7: wiring: the app is verified before the first folder is made or launchd is asked")
    } else {
        check(false, "sec4 M7: wiring: the app is verified first")
    }
}

private func secFix4TakeoverTests() {
    let desktop = "/Users/kim/Desktop/Aris.app", desktopAgent = desktop + "/Contents/MacOS/aris-agent"
    check(Install.isInApplications(app: "/Applications/Aris.app", home: home) && Install.isInApplications(app: "/Users/kim/Applications/Aris.app", home: home)
            && Install.isInApplications(app: "/Applications/Tools/Aris.app", home: home) && !Install.isInApplications(app: desktop, home: home)
            && !Install.isInApplications(app: "/Users/Shared/Aris.app", home: home) && !Install.isInApplications(app: "/Users/lee/Applications/Aris.app", home: home)
            && !Install.isInApplications(app: "/ApplicationsX/Aris.app", home: home),
          "sec4 L2: the Applications folders are the Mac's and the user's own")
    check(Install.takeoverRefusal(app: app, home: home, current: desktopAgent, currentExists: true, appBuiltAt: nil, currentBuiltAt: nil) == nil
            && Install.takeoverRefusal(app: desktop, home: home, current: agent, currentExists: true, appBuiltAt: nil, currentBuiltAt: nil) == .notInApplications
            && Install.takeoverRefusal(app: desktop, home: home, current: agent, currentExists: false, appBuiltAt: nil, currentBuiltAt: nil) == nil,
          "sec4 L2: a copy takes the helper's place over from an Applications folder, or when the copy that has it is gone; a second copy opened elsewhere does not")
    check(Install.takeoverRefusal(app: app, home: home, current: desktopAgent, currentExists: true, appBuiltAt: 1_790_000_000, currentBuiltAt: 1_795_000_000) == .older
            && Install.takeoverRefusal(app: app, home: home, current: desktopAgent, currentExists: true, appBuiltAt: 1_795_000_000, currentBuiltAt: 1_790_000_000) == nil
            && Install.takeoverRefusal(app: app, home: home, current: desktopAgent, currentExists: true, appBuiltAt: 1_790_000_000, currentBuiltAt: nil) == nil
            && Install.takeoverRefusal(app: app, home: home, current: desktopAgent, currentExists: false, appBuiltAt: 1_790_000_000, currentBuiltAt: 1_795_000_000) == nil,
          "sec4 L2: an older build never silently replaces a newer one that is still there; builds that don't say when they were made are not compared")
    check(Install.builtAt("1795000000") == 1_795_000_000 && Install.builtAt(NSNumber(value: 1_795_000_000)) == 1_795_000_000 && Install.builtAt("") == nil && Install.builtAt("$(ARIS_BUILT_AT)") == nil
            && Install.builtAt("12") == nil && Install.builtAt(nil) == nil,
          "sec4 L2: the build time is a date in seconds or nothing (a build the scripts did not stamp)")
    check(installCode("Aris/Info.plist").contains("<key>ArisBuiltAt</key>\n\t<string>$(ARIS_BUILT_AT)</string>"), "sec4 L2: the app's Info.plist carries the build time the scripts fill")
    // Against the recorded Mac.
    let second = Mac(app: desktop).installed()
    second.files[agent] = Data("agent".utf8)
    check(ArisAgentInstaller.run(second.world(app: desktop), enforcing: true) == .refused(.notInApplications) && second.loaded?.program == agent && !second.done.contains { $0.contains("bootout") || $0.hasPrefix("write") },
          "sec4 L2: opening a second copy on the Desktop leaves the installed Aris's helper alone and writes nothing")
    let moved = Mac(app: desktop).installed()
    moved.files[agent] = nil
    moved.files[Install.toolsPath(app: app)] = nil
    check(ArisAgentInstaller.run(moved.world(app: desktop), enforcing: true) == .started && moved.loaded?.program == desktopAgent, "sec4 L2: when the copy that had the place is gone (the app was moved), the one that is opened takes it")
    let update = Mac().installed(app: desktop)
    update.files[desktopAgent] = Data("agent".utf8)
    check(ArisAgentInstaller.run(update.world(), enforcing: true) == .started && update.loaded?.program == agent, "sec4 L2: the copy in Applications takes the place from one elsewhere")
    let downgrade = Mac().installed(app: "/Users/kim/Applications/Aris.app")
    downgrade.files["/Users/kim/Applications/Aris.app/Contents/MacOS/aris-agent"] = Data("agent".utf8)
    downgrade.builtAt = [app: 1_790_000_000, "/Users/kim/Applications/Aris.app": 1_795_000_000]
    check(ArisAgentInstaller.run(downgrade.world(), enforcing: true) == .refused(.older) && downgrade.loaded?.pid == 700, "sec4 L2: an older build in Applications does not replace the newer one that runs; the app says so")
    let sharedPlace = Mac(app: "/Users/Shared/Aris.app")
    sharedPlace.shared = true
    check(ArisAgentInstaller.run(sharedPlace.world(app: "/Users/Shared/Aris.app"), enforcing: true) == .refused(.sharedPlace) && sharedPlace.done.isEmpty,
          "sec4 L2: from a place other users can write nothing is installed at all")
    let inApps = Mac()
    inApps.shared = true
    check(ArisAgentInstaller.run(inApps.world(), enforcing: true) == .started, "sec4 L2: /Applications itself (which the Mac's admins can write) is where Aris belongs")
    for refusal in [Install.Refusal.sharedPlace, .notInApplications] {
        check(ArisHelperInstallWords.atLaunch(.refused(refusal), english: false) == ArisHelperInstallWords.move(english: false), "sec4 L2: refused for \(refusal.rawValue), the app asks to move Aris to Applications")
    }
    check(ArisHelperInstallWords.atLaunch(.refused(.older), english: false) == "지금 쓰는 Aris가 이것보다 새 빌드라서, 이 Aris로 바꾸지 않았어요.", "sec4 L2: and says when it was the older build")
    for refusal in Install.Refusal.allCases {
        check(ArisAgentInstallOutcome(word: ArisAgentInstallOutcome.refused(refusal).word) == .refused(refusal), "sec4 L2: the refusal \(refusal.rawValue) crosses XPC whole")
    }
}

private func secFix4OldRowsTests() {
    typealias W = ArisHelperInstallWords
    check(W.oldRows(english: false) == "예전 도우미 줄(aris-agent)이 남아 있어요. 지금은 쓰지 않으니 지워 두는 게 안전해요." && W.oldRows(english: true).contains("aris-agent"),
          "sec4 M4: the line says the old helper's rows are still there and are better removed")
    check(W.oldRowsBecomeDue(.switched, checkedBefore: true, wasSetUp: true) && W.oldRowsBecomeDue(.switched, checkedBefore: false, wasSetUp: false),
          "sec4 M4: it becomes due when the install is switched from the old way")
    check(W.oldRowsBecomeDue(.running, checkedBefore: false, wasSetUp: true) && W.oldRowsBecomeDue(.started, checkedBefore: false, wasSetUp: true),
          "sec4 M4: and once on a Mac where Aris was already set up when this build first ran (it was switched before, or may have been: Aris cannot read macOS's lists)")
    check(!W.oldRowsBecomeDue(.started, checkedBefore: false, wasSetUp: false) && !W.oldRowsBecomeDue(.running, checkedBefore: true, wasSetUp: true)
            && !W.oldRowsBecomeDue(.failed("load"), checkedBefore: false, wasSetUp: true) && !W.oldRowsBecomeDue(.refused(.trash), checkedBefore: false, wasSetUp: true),
          "sec4 M4: a new install is never told, an install is looked at once, and nothing is said while the helper isn't up")
    check(W.oldRowsSaidNow(due: true, saidBefore: false) && !W.oldRowsSaidNow(due: true, saidBefore: true) && !W.oldRowsSaidNow(due: false, saidBefore: false), "sec4 M4: said once, never again")
    check(W.oldRowsLists == [.accessibility, .screen, .disk], "sec4 M4: the lists the old rows are in")
    // The notch's own fix path: the line earns its button, and the button opens the lists one after another.
    let lists = W.oldRowsLists.map(ArisFix.pane)
    for english in [false, true] {
        let line = W.oldRows(english: english)
        check(ArisAppFix.fixes(forLine: line) == lists && ArisAppFix.fix(forLine: line) == lists[0], "sec4 M4: the line is the app's own and earns the lists' buttons (\(english ? "English" : "Korean"))")
        let moment = ArisFixMoment(phase: .failed, heard: "", reply: line, asking: false)
        var desk = ArisFixDesk()
        check(desk.offer(moment) == ArisFixOffer(fix: lists[0], again: false), "sec4 M4: first the button opens the first list")
        desk = desk.pressing(lists[0], under: line)
        check(desk.offer(moment)?.fix == lists[1], "sec4 M4: pressed, it becomes the next list's")
        desk = desk.pressing(lists[1], under: line)
        check(desk.offer(moment)?.fix == lists[2], "sec4 M4: then the third's")
        desk = desk.pressing(lists[2], under: line)
        check(desk.offer(moment) == nil, "sec4 M4: and when all three were opened there is no button left")
        check(desk.pressing(lists[0], under: "another line").offer(moment)?.fix == lists[0], "sec4 M4: a press under another line counts for nothing here")
    }
    ArisFix.Pane.osMajorForTests = 27
    check(ArisFixWords.title(lists[0], english: false) == "기기 제어 및 데이터 접근 권한 열기" && ArisFixWords.title(lists[0], english: true) == "Open Device Control and Data Access",
          "sec4 M4: on macOS 27 the first button names the list as that macOS does")
    ArisFix.Pane.osMajorForTests = 26
    check(ArisFixWords.title(lists[0], english: false) == "손쉬운 사용 권한 열기" && ArisFixWords.title(lists[2], english: true) == "Open Full Disk Access", "sec4 M4: and on macOS 26 as that one does")
    ArisFix.Pane.osMajorForTests = nil
    check(ArisAppFix.fixes(forLine: ArisHelperInstallWords.diskAfterSwitch(english: false)) == [.pane(.disk)] && ArisAppFix.fixes(forLine: "아무 말") == [],
          "sec4 M4: every other line keeps its one button, or none")
    let install = installCode("Aris/private/Aris/ArisHelperInstall.swift")
    check(install.contains("ArisController.shared.fail(line)") && install.contains("await say(ArisHelperInstallWords.oldRows())") && install.contains("defaults.set(true, forKey: ArisHelperInstallWords.oldRowsSaidKey)")
            && install.contains("wasSetUp: defaults.bool(forKey: ArisOnboarding.seenKey)") && !install.contains("ArisSettingsNav"),
          "sec4 M4: wiring: it is said through the notch's fix line (never a settings page), remembered once said, and kept due until the notch is quiet")
}

private func secFix4FilesTests() {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aris-sec4-files-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    func at(_ name: String) -> String { scratch.appendingPathComponent(name).path }
    // A pipe at the job file's path used to hold the install queue for good.
    check(mkfifo(at("job.plist"), 0o600) == 0 && ArisSafeFiles.kind(at("job.plist")) == .other && ArisSafeFiles.readSmallFile(at("job.plist")) == nil,
          "sec4 L5: a pipe at the job file's path is not read (it is not a file of its own), and nothing waits on it")
    check(ArisSafeFiles.write(Data("job".utf8), to: at("job.plist")) && ArisSafeFiles.kind(at("job.plist")) == .file && ArisSafeFiles.readSmallFile(at("job.plist")) == Data("job".utf8),
          "sec4 L5: the write replaces the pipe with the file")
    try? Data("secret".utf8).write(to: URL(fileURLWithPath: at("elsewhere")))
    check(symlink(at("elsewhere"), at("linked.plist")) == 0 && ArisSafeFiles.readSmallFile(at("linked.plist")) == nil, "sec4 L5: a link at the path is not read through")
    check(ArisSafeFiles.write(Data("job".utf8), to: at("linked.plist")) && ArisSafeFiles.kind(at("linked.plist")) == .file && (try? String(contentsOfFile: at("elsewhere"), encoding: .utf8)) == "secret",
          "sec4 L5: nor written through: the link is replaced and what it pointed at is untouched")
    try? Data(repeating: 0x41, count: 70_000).write(to: URL(fileURLWithPath: at("big.plist")))
    check(ArisSafeFiles.readSmallFile(at("big.plist")) == nil && ArisSafeFiles.readSmallFile(at("none.plist")) == nil, "sec4 L5: a file larger than a job file, or none, reads as nothing")
    try? FileManager.default.createDirectory(atPath: at("folder.plist"), withIntermediateDirectories: false)
    check(!ArisSafeFiles.write(Data("job".utf8), to: at("folder.plist")) && ArisSafeFiles.kind(at("folder.plist")) == .folder, "sec4 L5: a folder at the path is left alone and the write fails")
    check(((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).filter { $0.hasSuffix(".tmp") }.isEmpty, "sec4 L5: nothing is left beside the files")
    // Aris's folder: mode 700 through a descriptor that follows no link.
    check(ArisSafeFiles.makePrivateFolder(at("config/aris")), "sec4 L5: Aris's folder is made")
    var info = stat()
    check(stat(at("config/aris"), &info) == 0 && info.st_mode & 0o777 == 0o700, "sec4 L5: with mode 700")
    chmod(at("config/aris"), 0o755)
    check(ArisSafeFiles.makePrivateFolder(at("config/aris")) && stat(at("config/aris"), &info) == 0 && info.st_mode & 0o777 == 0o700, "sec4 L5: a folder that was opened up is closed again")
    try? FileManager.default.createDirectory(atPath: at("victim"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
    check(symlink(at("victim"), at("config/linked")) == 0 && !ArisSafeFiles.makePrivateFolder(at("config/linked")) && stat(at("victim"), &info) == 0 && info.st_mode & 0o777 == 0o755,
          "sec4 L5: a link where Aris's folder should be is not followed: the call fails and the folder it points at keeps its mode")
    check(!ArisSafeFiles.makePrivateFolder(at("job.plist")), "sec4 L5: a file where the folder should be fails too")
    let linked = Mac()
    linked.links[Install.folder(home: home)] = "/Users/kim/elsewhere"
    check(ArisAgentInstaller.run(linked.world(), enforcing: true) == .refused(.linkedFolder) && !linked.done.contains { $0.hasPrefix("folder") || $0.hasPrefix("write") || $0.hasPrefix("link") },
          "sec4 L5: with ~/.config/aris a link to somewhere else the install is refused in plain words and nothing is written through it")
    let linkedData = Mac()
    linkedData.links[Install.dataFolder(home: home)] = "/tmp/x"
    check(ArisAgentInstaller.run(linkedData.world(), enforcing: true) == .refused(.linkedFolder) && ArisHelperInstallWords.atLaunch(.refused(.linkedFolder), english: false)?.contains("~/.config/aris") == true,
          "sec4 L5: the same for its data folder; the app says which folder")
    check(ArisSafeFiles.othersCanWrite("/tmp") && ArisSafeFiles.othersCanWrite(at("nothing-here")) && !ArisSafeFiles.othersCanWrite(at("config/aris")) && !ArisSafeFiles.othersCanWrite("/usr/bin"),
          "sec4 L2: a world-writable folder, and one that can't be read, count as writable by others; the user's own and root's do not")
    let live = installCode("ArisXPCHelper/ArisAgentInstallLive.swift")
    check(live.contains("read: { ArisSafeFiles.readSmallFile($0) }") && live.contains("makePrivateFolder: { ArisSafeFiles.makePrivateFolder($0) }") && live.contains("write: { ArisSafeFiles.write($0, to: $1) }")
            && !live.contains("getpid()).tmp") && !live.contains("getpid()).link") && !live.contains("chmod(path"),
          "sec4 L5: wiring: the installer reads, writes and makes its folders only this way, and no temporary name can be guessed")
    let safe = installCode("Shared/ArisSafeFiles.swift")
    check(safe.contains("open(path, O_RDONLY | O_NOFOLLOW | O_DIRECTORY)") && safe.contains("fchmod(descriptor, 0o700)") && safe.contains("open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)")
            && safe.contains("open(beside, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)"),
          "sec4 L5: wiring: the mode is set on a descriptor opened without following a link; a read never waits; a write is made new beside its place")
    // The home folder.
    typealias O = ArisOrigin
    check(O.settledHome(program: "/Applications/Aris.app/Contents/MacOS/aris-agent", account: "/Users/kim") == "/Users/kim"
            && O.settledHome(program: "/Applications/Aris.app/Contents/MacOS/aris-tools", account: "/Users/kim") == "/Users/kim"
            && O.settledHome(program: "/Users/kim/dev/out/aris-agent", account: "/Users/kim") == nil && O.settledHome(program: "/Applications/Aris.app/Contents/MacOS/aris-tools", account: nil) == nil,
          "sec4 L5: inside the app, HOME in the environment is set back to the account's own home folder (getpwuid) before anything reads it; a loose copy keeps what it was given")
    check(installCode("ArisAgent/main.swift").contains("if helperMode { ArisOrigin.armRecheck() }\nArisOrigin.settleHome()") && installCode("ArisTools/main.swift").contains("ArisOrigin.armRecheck()\nArisOrigin.settleHome()")
            && installCode("ArisAgent/ArisOrigin.swift").contains("facts.homeRedirected = environment[\"CFFIXED_USER_HOME\"] != nil")
            && installCode("ArisXPCHelper/ArisAgentInstallLive.swift").contains("let home = ArisAgentRestart.realHome")
            && installCode("ArisXPCHelper/ArisHelperServiceObject.swift").contains("getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }"),
          "sec4 L5: wiring: both programs do that right after their start check, a redirected CFFIXED_USER_HOME is still refused there, and the installer takes the home folder from the account")
    let readsHome = ["ArisAgent", "ArisTools"].flatMap { folder in
        ((try? FileManager.default.contentsOfDirectory(atPath: installRoot.appendingPathComponent(folder).path)) ?? []).filter { $0.hasSuffix(".swift") }
            .filter { installCode("\(folder)/\($0)").range(of: #"environment\[\"HOME\"\]\s*(\?\?|\)|,|$)|getenv\(\"HOME\"\)"#, options: .regularExpression) != nil }
    }
    check(readsHome.isEmpty, "sec4 L5: no source file of the helper or the tools takes the home folder from HOME in the environment \(readsHome)")
}

private func secFix4EntitlementTests() {
    let xpc = (try? String(contentsOf: installRoot.appendingPathComponent("ArisXPCHelper/ArisXPCHelper.entitlements"), encoding: .utf8)) ?? ""
    check(!xpc.contains("<key>com.apple.security.automation.apple-events</key>") && xpc.contains("<key>com.apple.security.app-sandbox</key>"),
          "sec4 L3: the XPC helper has no entitlement to send Apple events")
    let folder = installRoot.appendingPathComponent("ArisXPCHelper")
    let sources = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".swift") }
    let senders = sources.filter { installCode("ArisXPCHelper/\($0)").range(of: "NSAppleScript|NSAppleEventDescriptor|osascript|AESend|OSAScript|ScriptingBridge", options: .regularExpression) != nil }
    check(sources.count >= 5 && senders.isEmpty, "sec4 L3: and none of its sources sends one \(senders)")
    let agent = (try? String(contentsOf: installRoot.appendingPathComponent("ArisAgent/ArisAgent.entitlements"), encoding: .utf8)) ?? ""
    check(agent.contains("com.apple.security.automation.apple-events") && !agent.contains("get-task-allow") && !agent.contains("disable-library-validation")
            && !agent.contains("allow-dyld-environment-variables") && !agent.contains("allow-unsigned-executable-memory"),
          "sec4 L3: the helper's and the tools' file still carries what they use, and nothing that weakens the hardened runtime")
}

// MARK: - The rollout switch: what decides while the new checks are not enforced

func secFix4RolloutTests() {
    typealias O = ArisOrigin
    check(ArisRollout.enforcing == false, "sec4 rollout: this build writes down what the new checks would refuse and lets the rule of the release before decide (set to true once a VM has shown every chain passing)")
    let app = "/Applications/Aris.app", agent = app + "/Contents/MacOS/aris-agent", tools = app + "/Contents/MacOS/aris-tools"
    func facts(program: String = tools, me: pid_t = 900, responsible: pid_t? = 500, responsibleProgram: String? = agent, identity: O.Identity = .aris, ancestors: [pid_t] = [800, 500],
               job: O.Job? = O.Job(pid: 500, program: agent), answered: Bool = true, signed: Set<pid_t> = [500], vouchedBy: pid_t? = 500, seal: Bool = true) -> O.Facts {
        O.Facts(me: me, program: program, responsible: responsible, responsibleProgram: responsibleProgram, responsibleIdentity: identity, ancestors: ancestors, job: job,
                launchdAnswered: answered, signedAsAgent: signed, vouchedBy: vouchedBy, looksLikeJob: true, sealIntact: seal)
    }
    // The chains the VM saw working at 43428e42 pass both rules, with nothing written down.
    for (what, chain) in [("helper → aris-tools for a look", [pid_t(500)]), ("helper → the AI's program → zsh → aris-tools", [820, 810, 500]), ("a scheduled job's AI → aris-tools", [760, 500])] {
        check(O.decision(facts(ancestors: chain), serving: false, enforcing: false) == O.Decision(allowed: true, wouldRefuse: false)
                && O.decision(facts(ancestors: chain), serving: false, enforcing: true) == O.Decision(allowed: true, wouldRefuse: false),
              "sec4 rollout: \(what), vouched for by the helper, runs under either rule and nothing is written down")
    }
    check(O.decision(facts(program: agent, me: 500, responsible: 500, ancestors: [], signed: [], vouchedBy: nil), serving: true, enforcing: false) == O.Decision(allowed: true, wouldRefuse: false),
          "sec4 rollout: launchd's own job serves under either rule")
    // Where the new rule is stricter: not enforced, the proven rule decides and the line is written; enforced, it is refused.
    for (what, found) in [("a tool the helper is a parent of but did not vouch for (the pre-forked tool, or a vouch that failed)", facts(vouchedBy: nil)),
                          ("a tool in a bundle whose seal does not verify", facts(seal: false))] {
        check(O.decision(found, serving: false, enforcing: false) == O.Decision(allowed: true, wouldRefuse: true) && O.decision(found, serving: false, enforcing: true) == O.Decision(allowed: false, wouldRefuse: false),
              "sec4 rollout: \(what) is let through and written down until enforced, then refused")
    }
    let copy = "/Users/kim/c/Aris.app/Contents/MacOS/Aris"
    check(O.decision(facts(responsible: 300, responsibleProgram: copy, identity: .aris, ancestors: [300], vouchedBy: nil), serving: false, enforcing: false) == O.Decision(allowed: true, wouldRefuse: true),
          "sec4 rollout: a copy of Aris as the responsible process still counts as another program by its path until enforced, and that is written down")
    check(O.decision(facts(program: agent, me: 500, responsible: 500, ancestors: [], signed: [], vouchedBy: nil, seal: false), serving: true, enforcing: false) == O.Decision(allowed: true, wouldRefuse: true)
            && O.mayYetBeJob(facts(program: agent, me: 500, job: nil, seal: false), enforcing: false),
          "sec4 rollout: aris-agent still serves from a bundle whose seal does not verify until enforced, and that is written down")
    // What the release before refused stays refused, whatever the switch.
    let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
    for (what, found) in [("a launchd job pointed at aris-tools (its parents do not lead to the helper)", facts(responsible: 900, responsibleProgram: tools, ancestors: [], vouchedBy: nil)),
                          ("zsh -lc started by another job", facts(responsible: 900, responsibleProgram: tools, ancestors: [850], vouchedBy: nil)),
                          ("a tool under a job that is a shell, env or a script", facts(job: O.Job(pid: 500, program: "/bin/sh", argument0: "/bin/sh"), vouchedBy: nil)),
                          ("a tool when launchd is silent", facts(job: nil, answered: false, vouchedBy: nil)),
                          ("a tool whose parent is not signed as aris-agent", facts(signed: [], vouchedBy: nil)),
                          ("aris-tools in Contents/Helpers", facts(program: app + "/Contents/Helpers/aris-tools"))] {
        check(O.decision(found, serving: false, enforcing: false) == O.Decision(allowed: false, wouldRefuse: false) && !O.decision(found, serving: false, enforcing: true).allowed,
              "sec4 rollout: \(what) is refused under either rule")
    }
    check(!O.decision(facts(program: agent, me: 650, responsible: 650, ancestors: []), serving: true, enforcing: false).allowed
            && !O.decision(facts(program: agent, me: 500, job: O.Job(pid: 500, program: "/tmp/x.sh", argument0: agent)), serving: true, enforcing: false).allowed,
          "sec4 rollout: aris-agent under another label, or as a job whose Program is a script, does not serve under either rule")
    check(O.decision(facts(responsible: 300, responsibleProgram: terminal, identity: .another, ancestors: [850, 300], signed: [], vouchedBy: nil), serving: false, enforcing: false) == O.Decision(allowed: true, wouldRefuse: false),
          "sec4 rollout: from Terminal the tool runs on Terminal's permissions under either rule")
    check(O.decision(facts(responsible: 300, responsibleProgram: terminal, identity: .unknown, ancestors: [850, 300], signed: [], vouchedBy: nil), serving: false, enforcing: false) == O.Decision(allowed: true, wouldRefuse: true),
          "sec4 rollout: a terminal whose signature can't be told is still Terminal by its path until enforced, and that is written down")
    // The installer: not enforced, it decides from the file as before and writes down what it would have done.
    let hijacked = Mac().installed()
    hijacked.loaded = ArisLoadedJob(path: "/Users/kim/evil.plist", program: "/tmp/x.sh", arguments: [agent], pid: 3104)
    check(ArisAgentInstaller.run(hijacked.world(), enforcing: false) == .running && hijacked.loaded?.program == "/tmp/x.sh" && hijacked.notes.contains { $0.contains("it would be replaced") },
          "sec4 rollout: the installer leaves a job it would replace as it is until enforced, and says so in its log")
    let changed = Mac()
    changed.verifies = false
    changed.shared = true
    changed.links[Install.dataFolder(home: home)] = "/tmp/x"
    check(ArisAgentInstaller.run(changed.world(app: "/Users/Shared/Aris.app"), enforcing: false) == .refused(.noHelper), "sec4 rollout: what the installer refused before it still refuses")
    let soft = Mac(app: "/Users/Shared/Aris.app")
    soft.verifies = false
    soft.shared = true
    check(ArisAgentInstaller.run(soft.world(app: "/Users/Shared/Aris.app"), enforcing: false) == .started && soft.notes.filter { $0.hasPrefix("install would refuse") }.count == 2,
          "sec4 rollout: its new refusals (a shared place, an app that does not verify) are written down and the install goes on as before")
    // Every gate reads the one switch.
    for (file, gate) in [("ArisAgent/ArisOrigin.swift", "static func decision(_ facts: Facts, serving: Bool, enforcing: Bool = ArisRollout.enforcing)"),
                         ("ArisAgent/ArisToolsLink.swift", "enforcing: Bool = ArisRollout.enforcing) -> Bool {"),
                         ("ArisAgent/ArisProgramApproval.swift", "enforcing: Bool = ArisRollout.enforcing) throws {"),
                         ("ArisAgent/ArisPeer.swift", "enforcing: ArisRollout.enforcing)"),
                         ("ArisXPCHelper/ArisAgentInstaller.swift", "static func run(_ world: ArisAgentInstallWorld, enforcing: Bool = ArisRollout.enforcing)")] {
        check(installCode(file).contains(gate), "sec4 rollout: wiring: \(file) reads the one switch")
    }
    check(installCode("ArisTools/main.swift").contains("guard ArisOrigin.allows(startFacts, serving: false) else {") && installCode("ArisAgent/main.swift").contains("guard ArisOrigin.allows(origin, serving: !helperMode) else {")
            && installCode("ArisAgent/ArisOrigin+Recheck.swift").contains("let made = decision(found, serving: false, enforcing: enforcing)"),
          "sec4 rollout: wiring: both programs decide through it at their start, and the second look does too")
    check(installCode("Shared/ArisRollout.swift").contains("static let enforcing = false") && installCode("Shared/ArisRollout.swift").contains("log.notice(\"would refuse: \\(what, privacy: .public)\")"),
          "sec4 rollout: wiring: one constant, and one kind of line in the system log")
}
