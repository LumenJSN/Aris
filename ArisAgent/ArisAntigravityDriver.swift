//
//  ArisAntigravityDriver.swift
//  aris-agent
//
//  Antigravity (Gemini) through `agy --input-format stream-json`: one long-lived
//  process, one JSON line per question, a "result" event per answer. agy has no
//  system-prompt flag, so Aris's instructions ride on the first question of each
//  process. What it may run is set by the allow/deny rules in ~/.gemini/antigravity-cli/settings.json,
//  which the agent itself checks and writes before the open agy starts (ArisAgyRules); headless agy refuses the rest.
//  When those rules can't be written (a settings file Aris can't add to, or can't write), the deny rules that stand in
//  for a gate may be missing: that agy never starts open. It starts sealed instead (no tools at all, Aris runs what it
//  asks for through the relay), and opens again once the rules are there (security review L3).
//  It takes no images (P1.0: image content parts are an error, image fields are ignored), so takesImages stays
//  false: screenshot turns go to the sealed Claude (ArisImageRouting), or come without the image and say so.
//

import Foundation

final class ArisAntigravityDriver: ArisBrainDriver {
    /// agy's stream-json events that carry nothing for Aris on their own (a running step, the init line).
    static let quietKinds: Set<String> = ["init", "step_update", "result", "user", "thought"]
    var quietKinds: Set<String> { Self.quietKinds }
    private let model: String
    /// The instructions this agy was made with; `instructions` is what the process started now is told.
    private let givenInstructions: String
    private var instructions: String
    /// aris-tools' path, to tell a clean aris-tools step from one that reads outside content.
    private let tools: String
    private var introduced = false

    /// The sealed agy (ArisAgyRelay): every tool denied for its session, the terminal sandbox on, aris-tools sealed,
    /// and stopped at the first tool step it starts. It answers from what Aris ran for it: a hands-free turn, a
    /// conversation that read the user's messages, mail or notes, or an agy whose own rules couldn't be written (`prepare`).
    private(set) var sealed: Bool
    /// Made sealed: it stays so whatever the rules say.
    private let sealedFromStart: Bool

    /// Whether agy is installed, and Aris's rules for it made sure of (the tests say; live: ArisAgyRules.ensure).
    var isInstalled: () -> Bool = { ArisAntigravityDriver.installed(ArisAntigravityDriver.places) != nil }
    var ensureRules: (_ tools: String) -> ArisAgyRules.Outcome = { tools in
        ArisAgyRules.ensure(home: FileManager.default.homeDirectoryForCurrentUser.path, tools: tools, folder: (tools as NSString).deletingLastPathComponent + "/aris")
    }

    static let places = ["~/.local/bin/agy", "/opt/homebrew/bin/agy", "/usr/local/bin/agy"]

    init(model: String, instructions: String, tools: String = "", sealed: Bool = false) {
        self.model = model
        givenInstructions = instructions
        self.instructions = instructions
        self.tools = tools
        self.sealed = sealed
        sealedFromStart = sealed
    }

    func launch() -> (URL, [String])? {
        guard let agy = Self.installed(Self.places) else { return nil }
        return (agy, arguments)
    }

    /// The open agy runs aris-tools only when its global settings allow it: the rules are checked now, and written when
    /// any is missing (agy installed after Aris, or never started: audit agy-rules-7). The sealed agy brings its own.
    /// Called before each start, ahead of `launch`: when the rules couldn't be made sure of, this start is the sealed
    /// agy's (its settings deny every tool for the session, and Aris's relay does what it asks for); nothing is
    /// written on a Mac without agy. Once the rules are there, the next start is open again.
    func prepare() {
        guard !sealedFromStart, tools.hasPrefix("/"), isInstalled() else { return }
        switch ensureRules(tools) {
        case .ready: open()
        case .written:
            open()
            FileHandle.standardError.write(Data("aris-agent: added Aris's rules to Antigravity's settings\n".utf8))
        case .failed(let why):
            // Without Aris's deny rules an open agy has no gate at all (whatever the owner's own rules allow would run).
            sealed = true
            instructions = ArisAgentPrompt.sealedAgy(tools: tools, handsFree: false, task: false)
            FileHandle.standardError.write(Data("aris-agent: Antigravity's settings weren't changed (\(why)); it starts without tools of its own, and Aris runs what it asks for\n".utf8))
        }
    }

    private func open() {
        sealed = false
        instructions = givenInstructions
    }

    var arguments: [String] {
        ["--input-format", "stream-json", "--output-format", "stream-json", "--model", model]
            + (sealed ? ["--settings", ArisAgyRelay.noToolsSettings, "--sandbox"] : [])
    }

    var isolatedFolder: Bool { sealed }

    /// The step types that carry only agy's own words: the question it got, its answer and its thinking.
    static let plainSteps: Set<String> = ["user_input", "agent_response", "thought", "thinking"]

    /// Said when a sealed agy started a tool and was stopped.
    static let sealedStop = "도구를 쓰려고 해서 멈췄어요. 다시 물어봐 주세요."

    func ask(_ prompt: String, tier: ArisTier) -> [Data] {
        let content = introduced ? prompt : instructions + "\n\n" + prompt
        introduced = true
        return [Self.line(["event": "user", "message": ["content": content]])]
    }

    func read(_ line: String) -> [ArisBrainEvent] {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        switch object["event"] as? String {
        case "step_update":
            let step = object["step_update"] as? [String: Any] ?? [:]
            // The sealed agy has no tools: any step but its own text or thinking (a tool, a subagent, anything new), from the
            // moment it starts (ACTIVE), stops the process (R2).
            if sealed, !Self.plainSteps.contains(step["step_type"] as? String ?? "") { return [.abort(Self.sealedStop)] }
            guard step["step_type"] as? String == "tool", step["state"] as? String == "DONE",
                  let name = step["tool_name"] as? String else { return [] }
            let parameters = (step["tool_info"] as? [String: Any])?["parameters"] as? [String: Any]
            let call = name == "run_command" ? (parameters?["CommandLine"] as? String).map { ArisAgentStream.ToolCall(name: "Bash", command: $0) } : nil
            // Any step but a clean aris-tools call brings outside content in (ArisClaudeDriver.bringsInOutside).
            if ArisClaudeDriver.bringsInOutside(call ?? ArisAgentStream.ToolCall(name: name, command: nil), tools: tools) { answered = true }
            return [.tools([call ?? ArisAgentStream.ToolCall(name: name, command: nil)])]
        case "result":
            answered = true
            let result = object["result"] as? [String: Any] ?? [:]
            guard result["status"] as? String == "SUCCESS" else {
                return [ArisBrainFailure.event(result["error"] as? String ?? "", brain: .antigravity)]
            }
            return [.result((result["response"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))]
        default:
            return []
        }
    }

    /// agy has no per-turn gate: aris-tools refuses it the user's messages, mail and notes (it asks Aris to read them:
    /// ArisAgyRelay); the sealed agy's aris-tools is sealed too.
    var environment: [String: String] { sealed ? [ArisSealedTools.environmentKey: "1"] : [ArisSealedTools.ungatedKey: "1"] }

    func reset() {
        introduced = false
        answered = false
        screen = false
    }

    /// agy's tool use can't be fully observed (its read_url and file tools run inside it), so a process that has
    /// answered a turn counts as outside text; one that was only started (warmed) or never answered is clean.
    private var answered = false
    private var screen = false

    var taint: ArisTaint { answered ? .outsideText : screen ? .screenSeen : .none }

    func markUntrusted() { answered = true }

    func markScreenSeen() { screen = true }
}
