//
//  ArisAsideRequest.swift
//  aris-tools
//
//  The words of `aris-tools aside "<brief>"` as the body aris-tools sends the agent (POST /aside-tool), with the turn's
//  credential from the file its environment names (ARIS_MCP_TURN_FILE), exactly as `mcp` does. Pure, so the tests run it.
//

import Foundation

/// The JSON body for POST /aside-tool (the words, joined, are the brief), or why the words can't be one.
func asideRequest(_ args: [String], environment: [String: String]) -> Result<[String: Any], ArisMCPUsage> {
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools aside works only inside an Aris turn"))
    }
    let brief = args.joined(separator: " ")
    guard !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, brief.utf8.count <= 16_384 else {
        return .failure(ArisMCPUsage(text: "usage: aris-tools aside \"<what Aside should do on the websites, and what to report>\""))
    }
    return .success(["turn": turn, "brief": brief])
}
