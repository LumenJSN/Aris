//
//  ArisTaskRequest.swift
//  aris-tools
//
//  The words of `aris-tools task …` as the body aris-tools sends the agent (POST /task-tool), with the turn's
//  credential from the file its environment names (ARIS_MCP_TURN_FILE), exactly as `routine` does. `task add <id>
//  --stdin` takes the instruction from standard input (`stdin`), so quotes in it need no escaping. The agent reads
//  the words (ArisTaskTool); here only the verb and the shape are checked.
//

import Foundation

let taskUsage = #"usage: aris-tools task list | task status <id> | task add <id> "<instruction>" | task add <id> --stdin | task cancel <id> | task pause <id>"#

/// The JSON body for POST /task-tool, or why the words can't be one. Pure, so the tests run it.
func taskRequest(_ args: [String], environment: [String: String], stdin: () -> String = { "" }) -> Result<[String: Any], ArisMCPUsage> {
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools task works only inside an Aris turn"))
    }
    guard let verb = args.first, ["list", "status", "add", "cancel", "pause"].contains(verb), args.count <= 40 else {
        return .failure(ArisMCPUsage(text: taskUsage))
    }
    var words = args
    if verb == "add", args.count == 3, args[2] == "--stdin" {
        let text = stdin().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(ArisMCPUsage(text: taskUsage)) }
        words = [verb, args[1], text]
    }
    return .success(["turn": turn, "words": words])
}
