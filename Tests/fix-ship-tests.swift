// Tests for the 2026-11-10 ship audit fixes that live in the repository: the build stamp (imp-1) and bringing back an
// agent whose LaunchAgent is not loaded (helper-1).
import Foundation

private final class ShipBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

func runFixShipTests() {
    buildStampTests()
    buildMismatchTests()
    runningAgentFileTests()
    agentBootstrapTests()
}

private func buildStampTests() {
    check(ArisBuildInfo.commit(plist: "3f2a1b9c", marked: "aris-build-commit:dev") == "3f2a1b9c",
          "ship: the app says the commit deploy.sh stamped into its Info.plist")
    check(ArisBuildInfo.commit(plist: nil, marked: "aris-build-commit:3f2a1b9c") == "3f2a1b9c",
          "ship: the agent and tools say the commit compiled into them")
    check(ArisBuildInfo.commit(plist: nil, marked: "aris-build-commit:3f2a1b9c-dirty") == "3f2a1b9c-dirty",
          "ship: a build from uncommitted changes says so in its stamp")
    check(ArisBuildInfo.commit(plist: "", marked: "aris-build-commit:dev") == "dev"
          && ArisBuildInfo.commit(plist: "  \n", marked: "aris-build-commit:dev") == "dev",
          "ship: a build made in Xcode, with no stamp, says dev")
    check(ArisBuildInfo.commit(plist: "$(ARIS_COMMIT)", marked: "aris-build-commit:dev") == "dev",
          "ship: a build setting that was never filled in is not taken for a commit")
    check(ArisBuildInfo.commit(plist: nil, marked: "") == "dev" && ArisBuildInfo.commit(plist: nil, marked: "aris-build-commit:") == "dev",
          "ship: an empty stamp says dev")
    check(ArisBuildInfo.commit(plist: nil, marked: "aris-build-commit:abc\"; rm -rf") == "dev",
          "ship: a stamp with anything but letters, digits, dots and dashes is not repeated")
    check(ArisBuildInfo.versionLine(program: "aris-tools", commit: "3f2a1b9c") == "aris-tools 3f2a1b9c",
          "ship: aris-tools --version is the program's name and its commit")
    check(ArisBuildStamp.marked.hasPrefix("aris-build-commit:") && ArisBuildStamp.marked.utf8.count > 15,
          "ship: the stamp is one whole string the install script can find in the program's bytes")
}

private func buildMismatchTests() {
    check(ArisBuildInfo.mismatch(app: "3f2a1b9c", agent: "3f2a1b9c") == nil, "ship: app and agent from one commit: nothing to say")
    let line = ArisBuildInfo.mismatch(app: "3f2a1b9c", agent: "b9c766bc")
    check(line?.contains("3f2a1b9c") == true && line?.contains("b9c766bc") == true && line?.contains("restarting it from this app") == true && line?.contains(".sh") == false,
          "ship: an agent from another commit than the app is named in the log, with both commits and what the app does about it")
    check(ArisBuildInfo.mismatch(app: "3f2a1b9c", agent: nil)?.contains("no build stamp") == true,
          "ship: a stamped app beside an agent that never said its commit (an older agent) is named too")
    check(ArisBuildInfo.mismatch(app: "dev", agent: "b9c766bc") == nil && ArisBuildInfo.mismatch(app: "dev", agent: nil) == nil,
          "ship: a build made in Xcode has no commit to compare, so nothing is claimed")
    check(ArisBuildInfo.mismatch(app: "3f2a1b9c", agent: "dev")?.contains("dev") == true,
          "ship: a deployed app beside an agent built by hand is a mismatch")
}

private func runningAgentFileTests() {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-ship-tests-\(UUID().uuidString)/aris")
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
    check(ArisBuildInfo.runningAgent(in: folder) == nil, "ship: no record yet: the running agent's commit is unknown")
    let said = ShipBox<[String]>([])
    check(ArisBuildInfo.recordRunningAgent(in: folder, commit: "3f2a1b9c") { said.value.append($0) },
          "ship: the agent writes its commit at start (the folder is made)")
    check(said.value == ["aris-agent: build 3f2a1b9c\n"], "ship: the agent's log says which commit started")
    check(ArisBuildInfo.runningAgent(in: folder) == "3f2a1b9c", "ship: the app reads the commit the running agent wrote")
    check(ArisBuildInfo.recordRunningAgent(in: folder, commit: "b9c766bc") { _ in } && ArisBuildInfo.runningAgent(in: folder) == "b9c766bc",
          "ship: the next agent to start replaces the record")
    let file = folder.appendingPathComponent(ArisBuildInfo.runningAgentFile)
    let mode = (try? FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
    check(mode == 0o600, "ship: the record is the user's own file (0600)")
    try? Data("not a commit; rm -rf ~\n".utf8).write(to: file)
    check(ArisBuildInfo.runningAgent(in: folder) == nil, "ship: a record that is not a commit is not repeated")
    try? Data(String(repeating: "a", count: 5_000).utf8).write(to: file)
    check(ArisBuildInfo.runningAgent(in: folder) == nil, "ship: an oversized record is not read as a commit")
}

private func agentBootstrapTests() {
    let home = "/Users/someone"
    let plist = "/Users/someone/Library/LaunchAgents/com.lumenjsn.aris.agent.plist"
    check(ArisAgentKickstart.plistPath(home: home) == plist, "ship: the agent's LaunchAgent file is in the user's Library")
    check(ArisAgentKickstart.bootstrapArguments(uid: 501, home: home) == ["bootstrap", "gui/501", plist],
          "ship: loading the agent is launchctl bootstrap of that one file, nothing from the caller")

    let ran = ShipBox<[[String]]>([])
    let statuses = ShipBox<[Int32?]>([])
    let runner: ArisProcessRunner = { _, arguments, done in
        ran.value.append(arguments)
        done(statuses.value.isEmpty ? nil : statuses.value.removeFirst())
    }
    let answer = ShipBox<Bool?>(nil)
    func restart(plistThere: Bool) {
        ran.value = []
        answer.value = nil
        ArisAgentRestart.run(using: runner, uid: 501, home: home, plistExists: { $0 == plist && plistThere }) { answer.value = $0 }
    }

    statuses.value = [0]
    restart(plistThere: true)
    check(answer.value == true && ran.value == [["kickstart", "-k", "gui/501/com.lumenjsn.aris.agent"]],
          "ship: a loaded agent is restarted with kickstart alone, as before")

    statuses.value = [113, 0]
    restart(plistThere: true)
    check(answer.value == true && ran.value == [["kickstart", "-k", "gui/501/com.lumenjsn.aris.agent"], ["bootstrap", "gui/501", plist]],
          "ship: 다시 시작 loads an agent whose LaunchAgent is not loaded (kickstart refused, then bootstrap)")

    statuses.value = [113, 5]
    restart(plistThere: true)
    check(answer.value == false && ran.value.count == 2, "ship: when the load is refused too, the restart is reported as failed")

    statuses.value = [113, 0]
    restart(plistThere: false)
    check(answer.value == false && ran.value.count == 1,
          "ship: with no LaunchAgent file (the agent was never installed) nothing is loaded and the restart fails")

    statuses.value = [nil, 0]
    restart(plistThere: true)
    check(answer.value == false && ran.value.count == 1,
          "ship: a launchctl that could not run or hung is not followed by a second command")
}
