// Tests for security review 4, H1: the helper never runs what sits at the two user-writable paths as Aris without a
// look. Its own tool calls start the aris-tools inside its own app (ArisAppBundle.ownTools); the link the AIs are told
// is kept a link to exactly that program (ArisToolsLink); and an AI's own program that changed signer, lost its
// signature, moved or became writable by others is not started until the owner says yes (ArisProgramApproval).
// Everything runs on values made here and in a throwaway folder; nothing of the user's is read.
// Called from runSecFix4Tests(); uses main.swift's check().
import Foundation

func secFix4H1Tests() {
    secFix4OwnToolsTests()
    secFix4LinkTests()
    secFix4ProgramTests()
    secFix4ProgramListTests()
}

private let h1Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
private func h1Code(_ path: String) -> String {
    ((try? String(contentsOf: h1Root.appendingPathComponent(path), encoding: .utf8)) ?? "").components(separatedBy: "\n")
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
}

private func secFix4OwnToolsTests() {
    typealias B = ArisAppBundle
    let told = "/Users/p/.config/aris/aris-tools", app = "/Applications/Aris.app", own = app + "/Contents/MacOS/aris-tools"
    check(B.ownTools(program: app + "/Contents/MacOS/aris-agent", told: told, exists: { _ in false }) == own,
          "sec4 H1: the helper inside Aris.app runs the aris-tools inside that same app for its own work")
    check(B.ownTools(program: "/Users/p/dev/out/aris-agent", told: told, exists: { $0 == "/Users/p/dev/out/aris-tools" }) == "/Users/p/dev/out/aris-tools"
            && B.ownTools(program: "/Users/p/dev/out/aris-agent", told: told, exists: { _ in false }) == told
            && B.ownTools(program: "/Users/p/.config/aris/aris-agent", told: told, exists: { _ in true }) == told && B.ownTools(program: nil, told: told, exists: { _ in true }) == told,
          "sec4 H1: a loose copy (a developer's build, the old install) runs the aris-tools beside it, and the old path only when there is none")
    check(B.executed(told, told: told, own: own) == own && B.executed("/tmp/fake/aris-tools", told: told, own: own) == "/tmp/fake/aris-tools" && B.executed(own, told: told, own: own) == own,
          "sec4 H1: a call of the helper's own that names the link in the user's folder starts the in-app program instead; any other path is as it was")
    check(B.ownCommand(told + " volume 30", told: told, own: own) == "'\(own)' volume 30" && B.ownCommand(told, told: told, own: own) == "'\(own)'"
            && B.ownCommand("open -a \"Music\"", told: told, own: own) == "open -a \"Music\"" && B.ownCommand(told + "x volume", told: told, own: own) == told + "x volume"
            && B.ownCommand(told + " app Notes", told: told, own: "/Users/p/My Apps/It's/Aris.app/Contents/MacOS/aris-tools") == "'/Users/p/My Apps/It'\\''s/Aris.app/Contents/MacOS/aris-tools' app Notes",
          "sec4 H1: a learned shortcut the helper replays through the shell starts its own aris-tools, quoted, and nothing else in the line changes")
    // No source file of the helper starts aris-tools by the name it is given without going through the one accessor.
    let folder = h1Root.appendingPathComponent("ArisAgent")
    let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasSuffix(".swift") }
    var direct: [String] = []
    var routed = 0
    for file in files {
        let code = h1Code("ArisAgent/\(file)")
        if code.range(of: #"executableURL = URL\(fileURLWithPath: (tools|toolsPath|Self\.toolsPath|ArisAgentRunner\.toolsPath|ArisAppBundle\.toldTools)\)"#, options: .regularExpression) != nil { direct.append(file) }
        routed += code.components(separatedBy: "executableURL = URL(fileURLWithPath: ArisAppBundle.executed(tools))").count - 1
    }
    check(files.count > 200 && direct.isEmpty && routed == 5, "sec4 H1: every place the helper starts aris-tools goes through ArisAppBundle.executed (\(routed) places; by its given name: \(direct))")
    let children = h1Code("ArisAgent/ArisChildren.swift")
    check(children.contains("if let asked = process.executableURL?.path, ArisAppBundle.executed(asked) != asked {\n            process.executableURL = URL(fileURLWithPath: ArisAppBundle.executed(asked))")
            && children.contains("try ArisProgramApproval.check(process.executableURL)\n        lock.lock()"),
          "sec4 H1: and the one place every start goes through never starts the link itself, and looks at an AI's program before it starts it")
    check(h1Code("ArisAgent/ArisAgentRunner.swift").contains("static var toolsPath: String { ArisAppBundle.toldTools }") && h1Code("ArisAgent/ArisAPIHelper.swift").contains("static var toolsPath: String { ArisAppBundle.toldTools }")
            && h1Code("ArisAgent/ArisShortcutStore.swift").contains("process.arguments = [\"-c\", ArisAppBundle.ownCommand(command, told: tools)]"),
          "sec4 H1: wiring: the link is only the name the AIs are told and the gate compares; the shortcut replay runs the helper's own program")
}

private func secFix4LinkTests() {
    typealias L = ArisToolsLink
    let app = "/Applications/Aris.app", own = app + "/Contents/MacOS/aris-tools", link = "/Users/p/.config/aris/aris-tools"
    check(L.isRight(kind: .link, target: own, own: own), "sec4 H1 link: a link to exactly this app's aris-tools is right")
    for (kind, target, what) in [(ArisSafeFiles.Kind.file, String?.none, "a file of its own (a copy, or someone's program)"), (.link, "/tmp/evil", "a link elsewhere"),
                                 (.link, "/Users/kim/c/Aris.app/Contents/MacOS/aris-tools", "a link to another copy of Aris"), (.link, own + "/", "a link to almost that path"),
                                 (.nothing, nil, "nothing"), (.folder, nil, "a folder"), (.other, nil, "a pipe")] {
        check(!L.isRight(kind: kind, target: target, own: own) && L.step(app: app, kind: kind, target: target, own: own) == .repair, "sec4 H1 link: \(what) is not, and is put right")
    }
    check(L.step(app: nil, kind: .file, target: nil, own: own) == .nothing && L.step(app: app, kind: .link, target: own, own: own) == .nothing,
          "sec4 H1 link: a loose copy of the helper keeps no link; a right link is left alone")
    // The look and the repair, against a recorded folder.
    var there: (ArisSafeFiles.Kind, String?) = (.link, "/tmp/evil")
    var notes: [String] = [], repairs = 0
    func ensure(app: String? = app, repairWorks: Bool = true, enforcing: Bool = true) -> Bool {
        L.ensure(app: app, link: link, own: own, kind: { _ in there.0 }, target: { _ in there.1 },
                 repair: { target, path in repairs += 1; if repairWorks, path == link { there = (.link, target) }; return repairWorks }, note: { notes.append($0) }, enforcing: enforcing)
    }
    check(ensure() && there.1 == own && repairs == 1 && notes.first?.contains("a link to /tmp/evil") == true, "sec4 H1 link: a link that was pointed elsewhere is put back, and the log says what was there")
    check(ensure() && repairs == 1, "sec4 H1 link: a right link costs one look and no write")
    there = (.file, nil)
    check(!ensure(repairWorks: false) && repairs == 2 && notes.last == "the tools link could not be put right", "sec4 H1 link: when it can't be put right the answer is no")
    check(ensure(repairWorks: false, enforcing: false) && repairs == 3, "sec4 H1 link: until the new checks are enforced that is written down and nothing is held back for it")
    there = (.file, nil)
    repairs = 0
    check(ensure(app: nil) && repairs == 0, "sec4 H1 link: a loose copy touches nothing")
    // The real write, in a throwaway folder: whatever is at the path is replaced itself, never followed.
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aris-sec4-link-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let path = scratch.appendingPathComponent("aris-tools").path, victim = scratch.appendingPathComponent("victim").path, target = scratch.appendingPathComponent("real-tools").path
    try? Data("victim".utf8).write(to: URL(fileURLWithPath: victim))
    check(symlink(victim, path) == 0 && ArisSafeFiles.replaceLink(target: target, at: path) && ArisSafeFiles.kind(path) == .link && ArisSafeFiles.linkTarget(path) == target
            && (try? String(contentsOfFile: victim, encoding: .utf8)) == "victim",
          "sec4 H1 link: a link elsewhere is replaced by the right link and what it pointed at is untouched")
    unlink(path)
    try? Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: path))
    check(ArisSafeFiles.kind(path) == .file && ArisSafeFiles.replaceLink(target: target, at: path) && ArisSafeFiles.linkTarget(path) == target, "sec4 H1 link: a regular file at the path is replaced by the link")
    unlink(path)
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    check(!ArisSafeFiles.replaceLink(target: target, at: path) && ArisSafeFiles.kind(path) == .folder
            && ((try? FileManager.default.contentsOfDirectory(atPath: scratch.path)) ?? []).filter { $0.hasSuffix(".tmp") }.isEmpty,
          "sec4 H1 link: a folder at the path is left alone, the write fails, and nothing is left beside it")
    let names = Set((0..<50).map { _ in ArisSafeFiles.besideName(path) })
    check(names.count == 50 && names.allSatisfy { $0.hasPrefix(scratch.path + "/.aris-tools.") && $0.hasSuffix(".tmp") }, "sec4 H1 link: the name it is made under beside its place cannot be guessed")
    check(h1Code("ArisXPCHelper/ArisAgentInstallLive.swift").contains("ArisSafeFiles.replaceLink(target: target, at: path)"), "sec4 H1 link: wiring: the installer's link is this same write")
    let runner = h1Code("ArisAgent/ArisAgentRunner.swift")
    if let look = runner.range(of: "guard ArisToolsLink.ensure() else { return nil }"), let start = runner.range(of: "guard let (executable, arguments) = driver.launch() else { return nil }") {
        check(look.lowerBound < start.lowerBound, "sec4 H1 link: wiring: the link is looked at before an AI is started, and none is started when it can't be put right")
    } else {
        check(false, "sec4 H1 link: wiring: the link is looked at before an AI is started")
    }
    check(runner.contains("if !ArisToolsLink.ensure() { return koreanTurn ? ArisToolsLink.refusedLine : ArisToolsLink.refusedLineEnglish }"), "sec4 H1 link: wiring: the notch then says so in plain words")
    check(h1Code("ArisAgent/ArisCodexDriver.swift").contains("let allow = allow && ArisToolsLink.ensure()"), "sec4 H1 link: wiring: a yes is passed on to the AI only while the link is right")
    check(h1Code("ArisAgent/main.swift").contains("ArisToolsLink.ensure()\nArisToolsLink.startWatching()"), "sec4 H1 link: wiring: the helper looks at its start and whenever something changes in Aris's folder")
    check(ArisToolsLink.refusedLine.contains("실행하지 않았어요") && ArisToolsLink.refusedLineEnglish.contains("nothing was run"), "sec4 H1 link: the line says nothing was run")
}

private func secFix4ProgramTests() {
    typealias A = ArisProgramApproval
    typealias F = ArisProgramFacts
    let me: UInt32 = 501
    // The installs the finder's own lists and comments name: the native Claude Code (a link in ~/.local/bin to a signed
    // file in a versions folder), an npm launcher script under Homebrew, nvm or an npm prefix, a Homebrew build in the
    // Cellar, and the Codex inside ChatGPT.app.
    let native = F(path: "/Users/p/.local/bin/claude", real: "/Users/p/.local/share/claude/versions/2.1.0", size: 190_000_000, modified: 1_000, owner: me, mode: 0o755, team: "ANTHROPIC1", identifier: "com.anthropic.claude-code")
    var updated = native
    updated.real = "/Users/p/.local/share/claude/versions/2.2.0"
    updated.size = 191_000_000
    updated.modified = 2_000
    check(A.verdict(approved: nil, now: native, user: me) == .record, "sec4 H1 program: the first time an AI is used, what was started is written down")
    check(A.verdict(approved: native, now: native, user: me) == .run, "sec4 H1 program: the same program runs")
    check(A.verdict(approved: native, now: updated, user: me) == .record, "sec4 H1 program: an update by the same signer runs without a question, and is written down")
    var moved = updated
    moved.path = "/opt/homebrew/bin/claude"
    moved.real = "/opt/homebrew/Caskroom/claude-code/2.2.0/claude"
    check(A.verdict(approved: native, now: moved, user: me) == .record, "sec4 H1 program: the same signer's program in another place (another way of installing it) runs too")
    var other = updated
    other.team = "EVILTEAM99"
    check(A.verdict(approved: native, now: other, user: me) == .ask(.signer), "sec4 H1 program: a program signed by someone else is not started")
    var renamed = updated
    renamed.identifier = "com.example.other"
    check(A.verdict(approved: native, now: renamed, user: me) == .ask(.signer), "sec4 H1 program: nor the same team's other program")
    var stripped = native
    stripped.team = nil
    stripped.identifier = nil
    check(A.verdict(approved: native, now: stripped, user: me) == .ask(.unsigned), "sec4 H1 program: a signed program that is unsigned now (a script put at ~/.local/bin/claude) is not started")
    let npm = F(path: "/opt/homebrew/bin/claude", real: "/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js", size: 9_000_000, modified: 1_000, owner: me, mode: 0o755, team: nil, identifier: nil)
    var npmUpdated = npm
    npmUpdated.size = 9_100_000
    npmUpdated.modified = 2_000
    check(A.verdict(approved: npm, now: npmUpdated, user: me) == .record, "sec4 H1 program: an unsigned launcher updated in its own folder (npm) runs without a question")
    let nvm = F(path: "/Users/p/.nvm/versions/node/v22.1.0/bin/codex", real: "/Users/p/.nvm/versions/node/v22.1.0/lib/node_modules/@openai/codex/bin/codex.js", size: 4_000, modified: 1, owner: me, mode: 0o755, team: nil, identifier: nil)
    var nvmNext = nvm
    nvmNext.path = "/Users/p/.nvm/versions/node/v24.0.2/bin/codex"
    nvmNext.real = "/Users/p/.nvm/versions/node/v24.0.2/lib/node_modules/@openai/codex/bin/codex.js"
    check(A.verdict(approved: nvm, now: nvmNext, user: me) == .record, "sec4 H1 program: the same install under a newer node (nvm) is the same folder")
    let brew = F(path: "/opt/homebrew/bin/codex", real: "/opt/homebrew/Cellar/codex/0.42.0/bin/codex", size: 30_000_000, modified: 1, owner: me, mode: 0o555, team: nil, identifier: nil)
    var brewNext = brew
    brewNext.real = "/opt/homebrew/Cellar/codex/0.43.1_1/bin/codex"
    check(A.verdict(approved: brew, now: brewNext, user: me) == .record, "sec4 H1 program: a Homebrew upgrade (a new version's folder in the Cellar) is the same folder")
    var elsewhere = npm
    elsewhere.real = "/private/tmp/evil/cli.js"
    check(A.verdict(approved: npm, now: elsewhere, user: me) == .ask(.moved), "sec4 H1 program: an unsigned program whose real file is somewhere else now (the link re-pointed) is not started")
    var inHome = npm
    inHome.path = "/Users/p/.local/bin/claude"
    inHome.real = "/Users/p/.local/bin/claude"
    check(A.verdict(approved: npm, now: inHome, user: me) == .ask(.moved), "sec4 H1 program: nor a new file earlier on the search path (~/.local/bin is looked in first)")
    var open = npmUpdated
    open.mode = 0o777
    var others = npmUpdated
    others.owner = 502
    check(A.verdict(approved: npm, now: open, user: me) == .ask(.writable) && A.verdict(approved: npm, now: others, user: me) == .ask(.writable),
          "sec4 H1 program: nor one that others can write now, or that is another user's")
    var rootOwned = npmUpdated
    rootOwned.owner = 0
    check(A.verdict(approved: npm, now: rootOwned, user: me) == .record, "sec4 H1 program: root's file that nobody else can write is fine")
    check(A.verdict(approved: open, now: open, user: me) == .run, "sec4 H1 program: what the owner accepted as it is keeps running as it is")
    var signedNow = npm
    signedNow.team = "SOMEONE123"
    signedNow.identifier = "x.y"
    check(A.verdict(approved: npm, now: signedNow, user: me) == .ask(.moved), "sec4 H1 program: an unsigned program replaced by a signed one is asked about once (a different kind of install)")
    check(A.installFolder("/opt/homebrew/Cellar/codex/0.42.0/bin/codex") == "/opt/homebrew/Cellar/codex/*/bin" && A.installFolder("/Users/p/.local/share/claude/versions/2.1.0") == "/Users/p/.local/share/claude/versions"
            && A.installFolder("/Users/p/.nvm/versions/node/v22.1.0/lib/x.js") == "/Users/p/.nvm/versions/node/*/lib",
          "sec4 H1 program: a version-numbered folder is “the same folder” across versions")
    check(A.isVersion("1.2.3") && A.isVersion("v22.1.0") && A.isVersion("0.43.1_1") && A.isVersion("2.1.0-beta.3") && !A.isVersion("versions") && !A.isVersion("node") && !A.isVersion("v")
            && !A.isVersion("22") && !A.isVersion("evil.d") && !A.isVersion("..") && !A.isVersion("x1.2"),
          "sec4 H1 program: only a version number counts as one")
    check(A.brain(ofProgram: "/Users/p/.local/bin/claude") == .claude && A.brain(ofProgram: "/opt/homebrew/bin/codex") == .codex && A.brain(ofProgram: "/usr/local/bin/agy") == .antigravity
            && A.brain(ofProgram: "/bin/zsh") == nil && A.brain(ofProgram: "/Applications/Aris.app/Contents/MacOS/aris-tools") == nil,
          "sec4 H1 program: the AI programs are known by their names; anything else the helper starts is not looked at here")
    check(A.changedLine(.claude, korean: true) == "Claude Code가 바뀌었어요. 계속 쓸까요?" && A.changedLine(.codex, korean: false) == "Codex has changed. Keep using it?",
          "sec4 H1 program: the notch asks in plain words")
}

private func secFix4ProgramListTests() {
    typealias A = ArisProgramApproval
    typealias F = ArisProgramFacts
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aris-sec4-programs-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: scratch) }
    let file = scratch.appendingPathComponent("approved-programs.json"), app = "/Applications/Aris.app", claude = URL(fileURLWithPath: "/Users/p/.local/bin/claude")
    var there = F(path: claude.path, real: "/Users/p/.local/share/claude/versions/2.1.0", size: 1, modified: 1, owner: 501, mode: 0o755, team: "ANTHROPIC1", identifier: "com.anthropic.claude-code")
    func start(_ executable: URL = claude, app: String? = app) -> A.Changed? {
        do { try A.check(executable, app: app, file: file, probe: { _, _ in there }, user: 501, enforcing: true); return nil } catch { return error as? A.Changed }
    }
    check(start() == nil && A.load(file)["claude"] == there, "sec4 H1 list: the first start is written down, in Aris's own data folder")
    var mode = stat()
    check(stat(file.path, &mode) == 0 && mode.st_mode & 0o777 == 0o600, "sec4 H1 list: readable and writable by the user alone")
    there.real = "/Users/p/.local/share/claude/versions/2.2.0"
    check(start() == nil && A.load(file)["claude"]?.real.hasSuffix("2.2.0") == true && !A.isWaiting(.claude), "sec4 H1 list: an update by the same signer starts and replaces what was written down")
    let approved = there
    there.team = nil
    there.identifier = nil
    there.real = "/Users/p/.local/bin/claude"
    check(start() == A.Changed(brain: .claude, reason: .unsigned) && A.isWaiting(.claude) && A.load(file)["claude"] == approved,
          "sec4 H1 list: a script put in the program's place is not started, the notch has something to ask, and what was approved stays as it was")
    check(start() == A.Changed(brain: .claude, reason: .unsigned), "sec4 H1 list: it is refused every time until the owner answers")
    check((try? A.check(claude, app: app, file: file, probe: { _, _ in there }, user: 501, enforcing: false)) != nil && A.load(file)["claude"] == approved,
          "sec4 H1 list: until the new checks are enforced the changed program is started as before, that is written down, and the list keeps what was approved")
    check(!A.accept(.codex, file: file) && A.isWaiting(.claude), "sec4 H1 list: a yes for another AI accepts nothing")
    check(A.accept(.claude, file: file) && !A.isWaiting(.claude) && A.load(file)["claude"] == there && start() == nil, "sec4 H1 list: the owner's yes writes the new one down, and it starts")
    check(!A.accept(.claude, file: file), "sec4 H1 list: with nothing waiting a yes does nothing (nobody can approve a program in advance)")
    there.real = "/private/tmp/evil"
    check(start(app: nil) == nil && A.load(file)["claude"]?.real == "/Users/p/.local/bin/claude", "sec4 H1 list: a loose copy of the helper keeps no list and holds nothing back")
    check(start(URL(fileURLWithPath: "/bin/zsh")) == nil && start(URL(fileURLWithPath: "/usr/bin/osascript")) == nil, "sec4 H1 list: a program that is no AI's starts as before")
    _ = A.accept(.claude, file: file)
    try? Data("not json".utf8).write(to: file)
    check(A.load(file).isEmpty, "sec4 H1 list: a list that can't be read is an empty one (the next start is written down again)")
    // The real probe, on files made here.
    let script = scratch.appendingPathComponent("lib/cli.js"), link = scratch.appendingPathComponent("bin/claude")
    try? FileManager.default.createDirectory(at: script.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data("#!/usr/bin/env node\n".utf8).write(to: script)
    chmod(script.path, 0o755)
    check(symlink(script.path, link.path) == 0, "sec4 H1 probe: a launcher link was made")
    let probed = A.probe(link.path, approved: nil)
    check(probed?.path == link.path && probed?.real == script.resolvingSymlinksInPath().path.replacingOccurrences(of: "/var/", with: "/private/var/").replacingOccurrences(of: "/private/private/", with: "/private/")
            && probed?.isSigned == false && probed?.owner == getuid() && probed?.mode == 0o755 && probed?.size == 20,
          "sec4 H1 probe: an npm-style launcher is read as its real file, unsigned, with its owner and mode")
    check(A.probe(scratch.appendingPathComponent("bin/none").path, approved: nil) == nil, "sec4 H1 probe: a program that isn't there has no facts")
    check(A.signer(ofFile: "/bin/ls")?.identifier == nil || A.signer(ofFile: "/bin/ls")?.team.isEmpty == false, "sec4 H1 probe: a system program has no team to write down, or a real one")
    // The fix, the words and the route.
    check(ArisFix.acceptProgram("claude").isValid && !ArisFix.acceptProgram("api").isValid && !ArisFix.acceptProgram("/bin/sh").isValid && ArisFix.acceptProgram("codex").again
            && ArisFix.parse(ArisFix.acceptProgram("claude").json) == ArisFix.acceptProgram("claude"),
          "sec4 H1 fix: the button names an AI and nothing else, and travels on the stream like every fix")
    check(ArisFixWords.title(.acceptProgram("claude"), english: false) == "계속 쓰기" && ArisFixWords.title(.acceptProgram("claude"), english: true) == "Keep using it", "sec4 H1 fix: its words")
    for brain in [ArisBrain.claude, .codex, .antigravity] {
        check(ArisBrainFix.fix(forLine: A.changedLine(brain, korean: true), another: { _ in nil }) == .acceptProgram(brain.rawValue)
                && ArisBrainFix.fix(forLine: A.changedLine(brain, korean: false), another: { _ in .claude }) == .acceptProgram(brain.rawValue),
              "sec4 H1 fix: the changed-program line of \(brain.rawValue) earns the button, in both languages")
    }
    var accepted: [ArisBrain] = []
    var world = ArisTeamExtrasRoute.World(ready: { _ in true }, resolve: { _ in nil }, openTerminal: { _ in false }, notes: { _ in [] }, forget: { _, _ in false },
                                          knowhowFile: scratch.appendingPathComponent("k"), teammateFile: { _ in nil })
    world.acceptProgram = { accepted.append($0); return $0 == .claude }
    check(ArisTeamExtrasRoute.ops.contains("acceptProgram") && ArisTeamExtrasRoute.handle(["op": "acceptProgram", "brain": "claude"], world: world).status == 200 && accepted == [.claude]
            && ArisTeamExtrasRoute.handle(["op": "acceptProgram", "brain": "codex"], world: world).status == 404
            && ArisTeamExtrasRoute.handle(["op": "acceptProgram", "brain": "api"], world: world).status == 400
            && ArisTeamExtrasRoute.handle(["op": "acceptProgram"], world: world).status == 400 && accepted == [.claude, .codex],
          "sec4 H1 fix: the helper's route accepts for a named AI only, and says when nothing was waiting")
    let main = h1Code("ArisAgent/main.swift")
    check(main.contains("if let op = object[\"op\"] as? String, ArisTeamExtrasRoute.ops.contains(op) {\n            guard failure == nil else { return respond(connection, \"403 Forbidden\", Data(\"{}\".utf8)) }"),
          "sec4 H1 fix: wiring: that route is answered only to the Aris app itself")
    check(h1Code("Aris/private/Aris/ArisFixModel.swift").contains("case .acceptProgram:") && h1Code("Aris/private/Aris/ArisAgentClient+TeamExtras.swift").contains("sendTeam([\"op\": \"acceptProgram\", \"brain\": brain])")
            && h1Code("ArisAgent/ArisAgentRunner.swift").contains("if ArisProgramApproval.isWaiting(brain) { return ArisProgramApproval.changedLine(brain, korean: koreanTurn) }"),
          "sec4 H1 fix: wiring: the notch says the line, the app's button sends the yes")
}
