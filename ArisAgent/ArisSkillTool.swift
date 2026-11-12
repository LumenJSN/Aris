//
//  ArisSkillTool.swift
//  aris-agent
//
//  What `aris-tools skill …` does once the agent knows whose turn it is (ArisSkillRoutes for the brains' own calls,
//  the agy relay for Antigravity's): list, read (inside the skill's folder only, and the answer gets its tag), or run a
//  script after the user's yes on a card, never on a turn that saw the screen, its output outside text from then on.
//  Blocks while a card waits. The skills are handed in, so the tests run it in a temp home with a fake turn.
//

import Foundation

enum ArisSkillTool {
    static var node: String? {
        ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// One `skill …` line of agy's aris-run block.
    static func relayed(_ words: [String], turn: ArisMCPTurn, skills: ArisSkills, note: @escaping (String) -> Void) -> String {
        let rest = Array(words.dropFirst())
        var object: [String: Any] = ["op": rest.first ?? ""]
        if rest.count >= 2 { object["name"] = rest[1] }
        if rest.first == "read", rest.count == 3 { object["file"] = rest[2] }
        if rest.first == "run", rest.count >= 3 { object["script"] = rest[2]; object["arguments"] = Array(rest.dropFirst(3)) }
        return String(answer(object, turn: turn, skills: skills, note: note).output.prefix(ArisAgyRelay.maxResult * 2))
    }

    /// Blocks (a card may wait for the user).
    /// `executor`: how a planned script runs (the tests run it unsandboxed: a sandbox can't be nested).
    static func answer(_ object: [String: Any], turn: ArisMCPTurn, skills: ArisSkills, executor: (ArisSkillRunPlan, ArisSkills) -> ArisSkillProcessResult = { execute($0, skills: $1) },
                       note: @escaping (String) -> Void) -> ArisMCPOutcome {
        let name = object["name"] as? String ?? ""
        switch object["op"] as? String {
        case "list":
            return ArisMCPOutcome(status: 0, output: skills.listText())
        case "read":
            switch skills.read(name, file: object["file"] as? String) {
            case .failure(let why): return .failed(why.message)
            case .success(let (record, text)):
                note(record.title)
                turn.audit(["answer": "skill read", "action": "\(record.name) \(object["file"] as? String ?? "SKILL.md")", "brain": turn.brainName])
                return ArisMCPOutcome(status: 0, output: text)
            }
        case "run":
            return run(name, script: object["script"] as? String ?? "", arguments: (object["arguments"] as? [String]) ?? [], turn: turn, skills: skills, executor: executor, note: note)
        default:
            return .failed("usage: aris-tools skill list | skill read <name> [file] | skill run <name> scripts/<file> [arguments…]")
        }
    }

    private static func run(_ name: String, script: String, arguments: [String], turn: ArisMCPTurn, skills: ArisSkills,
                            executor: (ArisSkillRunPlan, ArisSkills) -> ArisSkillProcessResult, note: @escaping (String) -> Void) -> ArisMCPOutcome {
        if turn.screen { return .failed(ArisSkillScript.screenRefusal) }
        let record: ArisSkillRecord, plan: ArisSkillRunPlan
        switch skills.plan(name, script: script, arguments: arguments, node: node) {
        case .failure(let why): return .failed(why.message)
        case .success(let found): (record, plan) = found
        }
        let shown = ArisSkillScript.card(title: record.title, plan: plan)
        let card = ArisMCPCard(title: shown.title, detail: shown.detail, full: nil, fields: [])
        let what = "\(record.name) \(script)"
        let done = DispatchSemaphore(value: 0)
        let box = ArisSkillAnswerBox()
        turn.ask(card) { answer in
            box.set(answer)
            done.signal()
        }
        if done.wait(timeout: .now() + 900) == .timedOut || !box.isYes {
            turn.audit(["answer": "no", "action": "skill run " + what, "brain": turn.brainName])
            return .failed(ArisSkillScript.declined)
        }
        turn.audit(["answer": "yes", "action": "skill run " + what + " " + String(arguments.joined(separator: " ").prefix(300)), "brain": turn.brainName])
        // What the script prints may carry anything (the web, files): outside text from here on.
        turn.takeOutsideText()
        note(record.title)
        let result = executor(plan, skills)
        return ArisMCPOutcome(status: result.ok ? 0 : 1, output: ArisSkillScript.output(name: record.name, script: script, status: result.status,
                                                                                       stdout: result.stdout, stderr: result.stderr, timedOut: result.timedOut))
    }

    /// Runs a planned script: in a scratch folder of its own (its working directory, removed after), Python from an
    /// ephemeral environment made for this run from the runtime's base interpreter (never the scanner's), under the
    /// script sandbox (the skills folder and the runtime read-only, ~/.config/aris out of reach: security review I6, M9).
    static func execute(_ plan: ArisSkillRunPlan, skills: ArisSkills, sandboxed: Bool = true) -> ArisSkillProcessResult {
        let home = skills.deps.home
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aris-skill-run-\(UUID().uuidString)")
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else {
            return ArisSkillProcessResult(status: -1, stdout: "", stderr: "couldn't make a scratch folder", timedOut: false)
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        var executable = plan.executable
        // The interpreter is the installed one, checked against its manifest first (re-review minor).
        if plan.python, !skills.deps.setup.verify() {
            return ArisSkillProcessResult(status: -1, stdout: "", stderr: ArisSkillSetup.damaged, timedOut: false)
        }
        if plan.python {
            let venv = scratch.appendingPathComponent(".venv")
            let made = ArisSkillProcess.run(plan.executable, ["-I", "-m", "venv", "--without-pip", venv.path],
                                            environment: ArisSkillScript.environment(home: home, extraPath: nil), directory: scratch.path, timeout: 60)
            guard made.ok else { return ArisSkillProcessResult(status: -1, stdout: "", stderr: "couldn't prepare Python for the script", timedOut: false) }
            executable = venv.appendingPathComponent("bin/python").path
        }
        var environment = ArisSkillScript.environment(home: home, extraPath: plan.python ? scratch.appendingPathComponent(".venv/bin").path : nil)
        environment["TMPDIR"] = scratch.path
        let sandbox = ArisSkillSandbox.arguments(profile: ArisSkillSandbox.scriptProfile, parameters: ArisSkillSandbox.scriptParameters(
            skills: skills.folder.path, runtime: skills.deps.setup.folder.path,
            config: URL(fileURLWithPath: home).appendingPathComponent(".config/aris").path, home: home))
        return ArisSkillProcess.run(sandboxed ? ArisSkillSandbox.tool : executable, (sandboxed ? sandbox + [executable] : []) + plan.arguments,
                                    environment: environment, directory: scratch.path, timeout: ArisSkillScript.timeout, maxOutput: ArisSkillScript.maxOutput)
    }
}

private final class ArisSkillAnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ArisMCPAnswer?
    func set(_ answer: ArisMCPAnswer) { lock.withLock { if stored == nil { stored = answer } } }
    var value: ArisMCPAnswer? { lock.withLock { stored } }
    var isYes: Bool { if case .yes = value { return true } else { return false } }
}
