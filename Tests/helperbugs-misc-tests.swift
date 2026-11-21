// Tests for jv-helperbugs (misc): audited helper bugs 18-22. agy's rules go to Aris's own agy session, never into
// the user's global settings, and what an earlier Aris wrote there is taken out; Codex gets Notion only with Aris's
// login and a prompt names Canvas only once it is set up; the login shell's PATH never holds a caller up; the API
// brain's budget of rounds and time, and its stops said as such; actions.log keeps only a short head of a body.
// Temp folders only, no model. Called from main.swift; uses its check().
import Foundation

private let miscRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func miscSource(_ path: String) -> String { (try? String(contentsOf: miscRoot.appendingPathComponent(path), encoding: .utf8)) ?? "" }

private func miscHome() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-helperbugs-misc-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.resolvingSymlinksInPath().path
}

private func miscJSON(_ data: Data?) -> [String: Any]? { data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } }

func runHelperbugsMiscTests() {
    miscAgySessionTests()
    miscAgyRestoreTests()
    miscNotionCanvasTests()
    miscLoginPathTests()
    miscAPIBudgetTests()
    miscAuditBodyTests()
}

// MARK: - 18: agy's rules are its session's own

private func miscAgySessionTests() {
    let home = miscHome()
    defer { try? FileManager.default.removeItem(atPath: home) }
    let tools = home + "/.config/aris/aris-tools", folder = home + "/.config/aris/aris"
    let driver = ArisAntigravityDriver(model: "m", instructions: "OPEN", tools: tools)
    driver.isInstalled = { true }
    driver.ensureRules = { tools in ArisAgyRules.session(home: home, tools: tools, folder: folder) }
    driver.prepare()
    let args = driver.arguments
    let given = args.firstIndex(of: "--settings").map { miscJSON(Data(args[$0 + 1].utf8)) } ?? nil
    let deny = (given?["permissions"] as? [String: Any])?["deny"] as? [String] ?? []
    check(!driver.sealed && !args.contains("--sandbox") && deny.contains("command(\(tools) message)") && deny.contains("command(rm)"),
          "agy session: the open agy is started with Aris's rules as its session's own settings (--settings)")
    check(!FileManager.default.fileExists(atPath: ArisAgyRules.settingsFile(home: home).deletingLastPathComponent().path),
          "agy session: nothing is written to the user's Antigravity folder")
    check(!miscSource("ArisAgent/ArisAgyRules.swift").contains("func ensure(") && !miscSource("ArisAgent/ArisAntigravityDriver.swift").contains("ArisAgyRules.ensure"),
          "agy session: wiring: no code writes Aris's rules into the global settings any more")
    check(miscSource("ArisAgent/ArisAntigravityDriver.swift").contains("ArisAgyRules.restoreOnce(home: home, tools: tools, folder: folder)"),
          "agy session: wiring: the live start takes an earlier Aris's rules out of the user's file first")
}

private func miscAgyRestoreTests() {
    let fm = FileManager.default
    func setUp(_ own: String?) -> (home: String, file: URL, tools: String, folder: String) {
        let home = miscHome()
        let tools = home + "/.config/aris/aris-tools", folder = home + "/.config/aris/aris"
        let file = ArisAgyRules.settingsFile(home: home)
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // As an earlier Aris left it: the copy from before, and the file with Aris's rules added.
        let before = own ?? "{}\n"
        try? Data(before.utf8).write(to: file.appendingPathExtension("before-aris"))
        let settings = miscJSON(Data(before.utf8)) ?? [:]
        let merged = ArisAgyRules.merged(settings, tools: tools, folder: folder, home: home) ?? settings
        try? JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys]).write(to: file)
        return (home, file, tools, folder)
    }
    func rules(_ file: URL, _ key: String) -> [String] { (miscJSON(try? Data(contentsOf: file))?["permissions"] as? [String: Any])?[key] as? [String] ?? [] }

    // The user's own settings: theirs stay, Aris's go, a rule they added later stays, their deny rules come back.
    let own = #"{"theme":"dark","permissions":{"allow":["command(git status)"],"deny":["command(rm)","command(my-tool)"],"ask":["x"]}}"#
    let a = setUp(own)
    defer { try? fm.removeItem(atPath: a.home) }
    var later = miscJSON(try? Data(contentsOf: a.file)) ?? [:]
    var permissions = later["permissions"] as? [String: Any] ?? [:]
    permissions["allow"] = (permissions["allow"] as? [String] ?? []) + ["command(npm test)"]
    later["permissions"] = permissions
    try? JSONSerialization.data(withJSONObject: later).write(to: a.file)
    let laterText = try? String(contentsOf: a.file, encoding: .utf8)
    check(ArisAgyRules.restore(home: a.home, tools: a.tools, folder: a.folder) == .restored, "agy restore: an earlier Aris's rules are taken out")
    let after = miscJSON(try? Data(contentsOf: a.file)) ?? [:]
    check(rules(a.file, "allow") == ["command(git status)", "command(npm test)"] && rules(a.file, "deny") == ["command(rm)", "command(my-tool)"]
          && after["theme"] as? String == "dark" && (after["permissions"] as? [String: Any])?["ask"] as? [String] == ["x"],
          "agy restore: the user's own rules and settings stay (a rule they added since too); Aris's are gone")
    check(!fm.fileExists(atPath: a.file.path + ".before-aris") && (try? String(contentsOf: a.file.appendingPathExtension("aris-cleanup"), encoding: .utf8)) == laterText,
          "agy restore: their file as it was is kept beside it first, and the copy from before Aris goes")
    check(ArisAgyRules.restore(home: a.home, tools: a.tools, folder: a.folder) == .nothing, "agy restore: done once; then there is nothing to do")

    // A file Aris made itself (nothing before it): it goes.
    let b = setUp(nil)
    defer { try? fm.removeItem(atPath: b.home) }
    check(ArisAgyRules.restore(home: b.home, tools: b.tools, folder: b.folder) == .restored && !fm.fileExists(atPath: b.file.path),
          "agy restore: a settings file Aris made, holding only its rules, is removed")

    // A file that isn't settings any more: left alone, the copy kept for the uninstall.
    let c = setUp(own)
    defer { try? fm.removeItem(atPath: c.home) }
    try? Data("not json".utf8).write(to: c.file)
    var failed = false
    if case .failed = ArisAgyRules.restore(home: c.home, tools: c.tools, folder: c.folder) { failed = true }
    check(failed && (try? String(contentsOf: c.file, encoding: .utf8)) == "not json" && fm.fileExists(atPath: c.file.path + ".before-aris"),
          "agy restore: a file that isn't settings is never clobbered, and the copy from before stays")

    // Never touched without the copy from before Aris (the user's own file, which Aris never wrote).
    let d = miscHome()
    defer { try? fm.removeItem(atPath: d) }
    let dFile = ArisAgyRules.settingsFile(home: d)
    try? fm.createDirectory(at: dFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    let theirs = #"{"permissions":{"allow":["read_url(*)"],"deny":["command(rm)"]}}"#
    try? Data(theirs.utf8).write(to: dFile)
    check(ArisAgyRules.restore(home: d, tools: d + "/.config/aris/aris-tools", folder: d + "/.config/aris/aris") == .nothing
          && (try? String(contentsOf: dFile, encoding: .utf8)) == theirs,
          "agy restore: a file Aris never wrote (no copy from before) is left exactly as it is, even rules like Aris's")
}

// MARK: - 19: Notion and Canvas only when set up

private func miscNotionCanvasTests() {
    let list = { (auth: String, enabled: Bool) in #"[{"name":"github","auth_status":"bearer_token","enabled":true},{"name":"aris_notion","auth_status":"\#(auth)","enabled":\#(enabled)}]"# }
    check(ArisNotionLink.connected(inList: list("o_auth", true)) == true && ArisNotionLink.connected(inList: list("bearer_token", true)) == true,
          "notion: Aris's server logged in (OAuth or a token) is connected")
    check(ArisNotionLink.connected(inList: list("not_logged_in", true)) == false && ArisNotionLink.connected(inList: list("o_auth", false)) == false
          && ArisNotionLink.connected(inList: #"[{"name":"github","auth_status":"o_auth"}]"#) == false,
          "notion: not logged in, turned off, or not there at all: not connected")
    check(ArisNotionLink.connected(inList: "codex: error") == nil && ArisNotionLink.connected(inList: #"[{"name":"aris_notion"}]"#) == nil,
          "notion: output that doesn't say is no answer")
    var answer: Bool? = false
    let watch = ArisNotionLink.Watch(ask: { answer })
    check(watch.value() == true, "notion: before Codex has said anything, Codex keeps Notion as before")
    watch.settle()
    check(watch.value() == false, "notion: once Codex says Aris's login isn't there, Codex gets no Notion")
    answer = nil
    watch.refresh()
    watch.settle()
    check(watch.value() == false, "notion: a Codex that couldn't answer leaves what was known")

    // Its launch reads the user's own Codex config, so the switch is checked in its source (the tests never read it).
    check(miscSource("ArisAgent/ArisCodexDriver.swift").contains("let notion = self.notion ? Self.notionSwitches : []"),
          "notion: wiring: a Codex without the login is started without Aris's Notion server")
    let runner = miscSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("let notion = ArisNotionLink.isConnected") && runner.contains("notion: notion, gated: true") && runner.contains("codex.notion = notion")
          && !runner.contains("ArisAgentPrompt.system(tools: toolsPath, notion: true"),
          "notion: wiring: Codex's prompt and its server follow the login")
    check(!ArisAgentPrompt.system(tools: "/t", notion: false, gated: true).contains("notion-search"), "notion: no Notion part in a prompt without it")

    let saved = ArisAgentPrompt.canvasSetUp
    defer { ArisAgentPrompt.canvasSetUp = saved }
    ArisAgentPrompt.canvasSetUp = { false }
    let without = [ArisAgentPrompt.system(tools: "/t"), ArisAgentPrompt.system(tools: "/t", notion: true, gated: true), ArisAgentPrompt.system(tools: "/t", reads: true)]
    check(without.allSatisfy { !$0.contains("School (Canvas)") && !$0.contains("/t canvas") && !$0.contains("\n\n- Showing something") },
          "canvas: a prompt names Canvas only once it is set up, with no gap left")
    ArisAgentPrompt.canvasSetUp = { true }
    check(ArisAgentPrompt.system(tools: "/t").contains("- School (Canvas): `/t canvas`") && ArisAgentPrompt.system(tools: "/t", notion: true, gated: true).contains("School (Canvas)"),
          "canvas: set up, every brain is told about it")
    let folder = URL(fileURLWithPath: miscHome())
    defer { try? FileManager.default.removeItem(at: folder) }
    FileManager.default.createFile(atPath: folder.appendingPathComponent("canvas-host").path, contents: Data("q.example.edu".utf8))
    let half = ArisCanvasSetup.isSetUp(folder: folder)
    FileManager.default.createFile(atPath: folder.appendingPathComponent("canvas-key").path, contents: Data())
    check(!half && ArisCanvasSetup.isSetUp(folder: folder), "canvas: set up only with both its token and its school saved")
    check(miscSource("ArisAgent/main.swift").contains("ArisAgentPrompt.canvasSetUp = { ArisCanvasSetup.isSetUp("), "canvas: wiring: the agent says whether it is set up")
}

// MARK: - 20: the login shell's PATH never holds a caller up

private func miscLoginPathTests() {
    let folder = URL(fileURLWithPath: miscHome())
    defer { try? FileManager.default.removeItem(at: folder) }
    let shell = folder.appendingPathComponent("slow/zsh")
    try? FileManager.default.createDirectory(at: shell.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data("#!/bin/sh\nsleep 1.5; PATH='/fake/nvm/bin:/usr/bin'; eval \"$4\"\n".utf8).write(to: shell)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shell.path)
    var kept: [[String]] = []
    let lookup = ArisLoginPath.Lookup(shell: { shell.path }, limit: 10, retryAfter: 1_800) { kept.append($0) }
    let started = Date()
    let first = lookup.folders()
    check(first.isEmpty && Date().timeIntervalSince(started) < 0.5, "login path: a lookup never waits on the shell (none yet, at once)")
    _ = lookup.folders()
    lookup.settle()
    check(lookup.folders() == ["/fake/nvm/bin", "/usr/bin"] && kept == [["/fake/nvm/bin", "/usr/bin"]],
          "login path: the shell is asked once, in the background, and its PATH is kept (and written down for the gate)")
    let broken = ArisLoginPath.Lookup(shell: { "/nonexistent/zsh" }, limit: 1, retryAfter: 1_800)
    _ = broken.folders()
    broken.settle()
    check(broken.folders().isEmpty, "login path: a shell that can't answer leaves only the usual folders")
    check(miscSource("ArisAgent/main.swift").contains("ArisLoginPath.warm()"), "login path: wiring: the agent asks at its start")
}

// MARK: - 21: the API brain's budget

private func miscAPIBudgetTests() {
    let preset = ArisAPIPreset.named("openai")!
    let profile = ArisAPIProfile(id: "openai", quick: preset.quick, strong: preset.strong, baseURL: "http://127.0.0.1:1/v1", vision: nil, tools: nil)
    let make = { (task: Bool) in ArisAPIDriver(profile: profile, tools: "/t/aris-tools", task: task, home: "/Users/me", executable: URL(fileURLWithPath: "/usr/bin/true")) }
    let asked = { (driver: ArisAPIDriver) -> Int? in miscJSON(driver.ask("q", tier: .quick).first)?["maxRounds"] as? Int }
    let chat = make(false), job = make(true)
    check(asked(chat) == ArisAPIDriver.roundBudget && ArisAPIDriver.roundBudget >= 20 && chat.opening().isEmpty,
          "api budget: a question may take \(ArisAPIDriver.roundBudget) rounds of tools (eight stopped ordinary work halfway)")
    check(asked(job) == ArisAPIDriver.taskRoundBudget && miscJSON(job.opening().first)?["turn"] as? Double == ArisAPIDriver.taskTurnBudget,
          "api budget: a background job gets more rounds and more time for its turn")
    check(ArisAPIHelper.defaultRounds >= ArisAPIDriver.taskRoundBudget, "api budget: the helper's ceiling lets the budget through")
    let request = { (round: Int) -> String in
        String(decoding: try! JSONSerialization.data(withJSONObject: ["type": "tool_request", "id": "r\(round)", "name": "timer", "arguments": #"{"minutes":1}"#, "round": round]), as: UTF8.self)
    }
    _ = chat.ask("q", tier: .quick)
    let past = chat.read(request(ArisAPIDriver.roundBudget + 1))
    check(past.contains { if case .abort(let line) = $0 { return line == ArisAPIDriver.roundsStop }; return false }, "api budget: past its rounds the turn stops")
    _ = chat.ask("q", tier: .quick)
    let timeUp = chat.read(#"{"type":"error","kind":"timeout","message":"the turn took too long"}"#)
    check(timeUp.contains { if case .abort(let line) = $0 { return line == ArisAPIDriver.timeStop }; return false },
          "api budget: past its time the turn stops and says so (not \"can't reach the server\")")
    check(ArisAPIDriver.roundsStop.contains("도구 횟수") && ArisAPIDriver.timeStop.contains("시간을 다 써서")
          && ArisGateWords.line(ArisAPIDriver.timeStop).contains("used up this question's time") && ArisGateWords.line(ArisAPIDriver.roundsStop).contains("tool calls"),
          "api budget: each stop says which budget ran out, in Korean and in English")
    check(miscSource("ArisAgent/ArisAPIHelper.swift").contains("ArisAPIError(kind: .timeout, message: \"the turn took too long\")")
          && ArisAPIDriver.turnTimeUp == "the turn took too long", "api budget: wiring: the helper's time-up words are the ones the driver reads")
}

// MARK: - 22: actions.log keeps a short head of a body

private func miscAuditBodyTests() {
    let body = String(repeating: "엄마 오늘 저녁 7시에 집에 갈게요 ", count: 20)
    let command = "/t/aris-tools message 엄마 '\(body)'"
    let line = ArisAuditWriter.capped(ArisAuditWriter.auditJSON(["action": "shell: " + command, "command": command, "risk": "confirm", "raw": command]))
    let kept = miscJSON(Data(line.utf8)) ?? [:]
    let action = kept["action"] as? String ?? ""
    check(action.hasPrefix("shell: /t/aris-tools message 엄마 '") && action.contains(String(body.prefix(ArisAuditWriter.bodyHead)))
          && !action.contains(String(body.prefix(ArisAuditWriter.bodyHead + 10))) && action.contains("자›'"),
          "audit body: a message's text keeps only its head; the program, subcommand and recipient stay")
    check(kept["action_len"] as? Int == ("shell: " + command).utf8.count && kept["action_sha256"] as? String == ArisAuditWriter.sha256("shell: " + command)
          && (kept["raw"] as? String)?.contains(String(body.prefix(ArisAuditWriter.bodyHead + 10))) == false && kept["risk"] as? String == "confirm",
          "audit body: the whole field's length and SHA-256 stay as evidence; every field is cut alike")
    let heredoc = "cat > /Users/me/notes.txt <<'EOF'\n" + String(repeating: "비밀 메모 ", count: 50) + "\nEOF"
    let cutHeredoc = ArisAuditWriter.withoutBodies(heredoc)
    check(cutHeredoc.hasPrefix("cat > /Users/me/notes.txt <<'EOF'\n") && cutHeredoc.count < 120, "audit body: what follows a command's first line keeps only its head")
    let plain = "/t/aris-tools trash '/Users/me/Documents/old report.pdf' --force"
    check(ArisAuditWriter.withoutBodies(plain) == plain && ArisAuditWriter.capped(#"{"action":"shell: ls -la","risk":"auto"}"#) == #"{"action":"shell: ls -la","risk":"auto"}"#,
          "audit body: short arguments and paths are kept as they are")
    check(ArisAuditWriter.withoutBodies(#"say "a \"quoted\" word" "# + "'" + String(repeating: "x", count: 100)).hasSuffix("…‹+60자›"),
          "audit body: escaped quotes and a quote left open are read right")
}
