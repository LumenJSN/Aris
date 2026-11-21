//
//  ArisTurnSideEffects.swift
//  aris-agent
//
//  Whether a turn's tool calls may have changed something, so its turn is never handed to another brain after a limit
//  (that brain would do it again): only a plain read counts as none (a web search or fetch, a file read, one read-only
//  command, one aris-tools read). Anything else, or anything that can't be read word by word, may have. And what the
//  turn then says: what was done, and that the rest was not done and not handed on.
//

import Foundation

enum ArisTurnSideEffects {
    /// Tools that only read (Claude Code's names, Codex's item kinds).
    static let readTools: Set<String> = ["Read", "WebSearch", "WebFetch", "Grep", "Glob", "LS", "webSearch", "web_search"]

    /// Whether `call` may have changed something.
    static func mayChange(_ call: ArisAgentStream.ToolCall, tools: String) -> Bool {
        if readTools.contains(call.name) { return false }
        guard call.name == "Bash", let command = call.command,
              let words = ArisCommandPolicy.words(command), (ArisCommandPolicy.segments(command) ?? []).count == 1, let program = words.first else { return true }
        if program == tools { return !ArisLocalReadPolicy.isRead(Array(words.dropFirst())) }
        if case .runs? = ArisRiskPolicy.readOnlyForm(words) { return false }
        return true
    }

    /// A step as a stopped turn names it: the notch's status line for it, without "… 중".
    static func done(_ call: ArisAgentStream.ToolCall, tools: String) -> String {
        let line = call.name == "Bash" ? call.command.map { ArisAgentStatus.forCommand($0, tools: tools) } ?? call.name
                                       : ArisAgentStatus.forClaudeTool(call.name)
        var trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "…. "))
        if trimmed.hasSuffix(" 중") { trimmed = String(trimmed.dropLast(2)) }
        return trimmed
    }

    /// Whether a turn may go to another brain after this one hit a limit: nothing done that could have changed
    /// anything (`acted`: an action the gate judged; `changed`: a tool call that may have), a conversation's turn, and
    /// someone to take it.
    static func mayHandOff(acted: Bool, changed: Bool, isTask: Bool, canHandOff: Bool) -> Bool {
        !acted && !changed && !isTask && canHandOff
    }

    /// The line for a turn that stopped at a limit after it had done something: the brain's own reason, what it did
    /// (the notch's status lines for those steps, the last few), and that the rest wasn't done and wasn't handed to
    /// another AI so nothing is done twice.
    static func stoppedLine(reason: String, done: [String], korean: Bool) -> String {
        let steps = Array(NSOrderedSet(array: done.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).array as? [String] ?? []).suffix(3)
        if korean {
            let did = steps.isEmpty ? "이미 한 일이 있어서" : "이미 한 일: \(steps.joined(separator: ", ")). 그래서"
            return "\(reason) \(did) 같은 일을 두 번 하지 않도록 다른 AI에게 넘기지 않았어요. 나머지는 하지 않았어요."
        }
        let did = steps.isEmpty ? "It had already done something, so" : "Already done: \(steps.joined(separator: ", ")). So"
        return "\(reason) \(did) it wasn't handed to another AI (nothing is done twice). The rest wasn't done."
    }
}
