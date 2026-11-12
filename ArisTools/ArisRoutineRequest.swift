//
//  ArisRoutineRequest.swift
//  aris-tools
//
//  The words of `aris-tools routine …` as the body aris-tools sends the agent (POST /routine-tool), with the turn's
//  credential from the file its environment names (ARIS_MCP_TURN_FILE), exactly as `skill` and `mcp` do. The agent
//  reads the words (ArisRoutineTool); here only the verb is checked.
//

import Foundation

/// The JSON body for POST /routine-tool, or why the words can't be one. Pure, so the tests run it.
func routineRequest(_ args: [String], environment: [String: String]) -> Result<[String: Any], ArisMCPUsage> {
    let usage = #"usage: aris-tools routine list | routine show "<name>" | routine add --name "<name>" --step "<request>" [--step "<request>" …] | routine remove "<name>" | routine wait <id>"#
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools routine works only inside an Aris turn"))
    }
    guard let verb = args.first, ["list", "show", "add", "remove", "wait"].contains(verb), args.count <= 40 else {
        return .failure(ArisMCPUsage(text: usage))
    }
    return .success(["turn": turn, "words": args])
}
