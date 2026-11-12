//
//  ArisStepOutcome.swift
//  aris-agent
//
//  Whether a step the AI took ended with an error, read from what each brain's process says when a call is over: the
//  API brain's helper gives the exit status, Codex the command's exit code, Claude Code an error tool result. The app
//  then shows that step's tag without a tick (VM run 2026-11-10, bug 7: "Adding a to-do ✓" under "I couldn't add it").
//  Nothing here judges or gates anything; it only reports. Pure (tested).
//

import Foundation

enum ArisStepOutcome {
    /// The API helper's `tool_done` for a call that ran `argv`: failed when its exit status isn't 0. The step is named
    /// by the same words its status had; with the command no longer known, the step running now.
    static func api(toolDone object: [String: Any], argv: [String]?, tools: String) -> [ArisBrainEvent] {
        guard let exit = object["exit"] as? Int, exit != 0 else { return [] }
        return [.stepFailed(argv.map { ArisAgentStatus.forCommand(ArisAPICatalog.command(tools: tools, argv: $0), tools: tools) })]
    }

    /// Codex's `item/completed` item: a command that ran and exited non-zero (or that Codex marks failed). A command
    /// that was declined never ran, and says nothing here.
    static func codex(completed item: [String: Any], tools: String) -> [ArisBrainEvent] {
        guard item["type"] as? String == "commandExecution" else { return [] }
        let exit = item["exitCode"] as? Int
        guard (exit ?? 0) != 0 || (exit == nil && item["status"] as? String == "failed") else { return [] }
        let command = (item["command"] as? String).map(ArisCommandPolicy.unwrap)
        return [.stepFailed(command.map { ArisAgentStatus.forCommand($0, tools: tools) })]
    }

    /// Claude Code's stream line: a user message carrying a tool result marked as an error. Claude Code doesn't say
    /// here which call it was for in words, so it is the step running now.
    static func claude(line: String) -> [ArisBrainEvent] {
        guard line.contains("\"is_error\""), let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["type"] as? String == "user",
              let content = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return [] }
        let failed = content.contains { $0["type"] as? String == "tool_result" && $0["is_error"] as? Bool == true }
        return failed ? [.stepFailed(nil)] : []
    }
}
