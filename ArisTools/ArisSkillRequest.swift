//
//  ArisSkillRequest.swift
//  aris-tools
//
//  The words of `aris-tools skill …` as the body aris-tools sends the agent (POST /skill-tool), with the turn's
//  credential from the file its environment names (ARIS_MCP_TURN_FILE), exactly as `mcp` does.
//

import Foundation

/// The JSON body for POST /skill-tool, or why the words can't be one. Pure, so the tests run it.
func skillRequest(_ args: [String], environment: [String: String]) -> Result<[String: Any], ArisMCPUsage> {
    let usage = "usage: aris-tools skill list | aris-tools skill read <name> [file] | aris-tools skill run <name> scripts/<file> [arguments…]"
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools skill works only inside an Aris turn"))
    }
    switch args.first {
    case "wait" where args.count == 2:
        // A script still waiting on the user's card: its result (the agent's ArisSlowCalls).
        return .success(["op": "wait", "turn": turn, "id": args[1]])
    case "list" where args.count == 1:
        return .success(["op": "list", "turn": turn])
    case "read" where args.count == 2 || args.count == 3:
        var body: [String: Any] = ["op": "read", "turn": turn, "name": args[1]]
        if args.count == 3 { body["file"] = args[2] }
        return .success(body)
    case "run" where args.count >= 3:
        return .success(["op": "run", "turn": turn, "name": args[1], "script": args[2], "arguments": Array(args.dropFirst(3))])
    default:
        return .failure(ArisMCPUsage(text: usage))
    }
}
