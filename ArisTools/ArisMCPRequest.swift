//
//  ArisMCPRequest.swift
//  aris-tools
//
//  The words of `aris-tools mcp …` as the body aris-tools sends the agent (POST /mcp-tool), with the turn's credential
//  from the file its environment names (ARIS_MCP_TURN_FILE). Pure, so the tests run it.
//

import Foundation

struct ArisMCPUsage: Error, Equatable {
    let text: String
}

/// The turn's credential from the file the runner rewrites each turn (at most 128 bytes, one line).
func readCredential(_ path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 128) else { return nil }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The JSON body for POST /mcp-tool, or why the words can't be one.
func mcpRequest(_ args: [String], environment: [String: String]) -> Result<[String: Any], ArisMCPUsage> {
    let usage = "usage: aris-tools mcp list [service] | aris-tools mcp call <service> <tool> '<json arguments>' (or key=value …)"
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools mcp works only inside an Aris turn"))
    }
    switch args.first {
    case "list":
        guard args.count <= 2 else { return .failure(ArisMCPUsage(text: usage)) }
        var body: [String: Any] = ["op": "list", "turn": turn]
        if args.count == 2 { body["service"] = args[1] }
        return .success(body)
    case "wait":
        // A call that outlasted one command: its result, once it comes (the agent's ArisSlowCalls).
        guard args.count == 2 else { return .failure(ArisMCPUsage(text: usage)) }
        return .success(["op": "wait", "turn": turn, "id": args[1]])
    case "call":
        guard args.count >= 3 else { return .failure(ArisMCPUsage(text: usage)) }
        var body: [String: Any] = ["op": "call", "turn": turn, "service": args[1], "tool": args[2]]
        let rest = Array(args.dropFirst(3))
        if rest.isEmpty {
            body["arguments"] = "{}"
        } else if rest.count == 1, rest[0].trimmingCharacters(in: .whitespaces).hasPrefix("{") {
            body["arguments"] = rest[0]
        } else if rest.allSatisfy({ $0.contains("=") && !$0.hasPrefix("=") }) {
            body["pairs"] = rest
        } else {
            return .failure(ArisMCPUsage(text: usage))
        }
        return .success(body)
    default:
        return .failure(ArisMCPUsage(text: usage))
    }
}
