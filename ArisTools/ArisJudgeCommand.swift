//
//  ArisJudgeCommand.swift
//  aris-tools
//
//  The hooks' question to the read judge (ArisReadGate): aris-tools, running as a Claude's PreToolUse hook inside that
//  brain's own process tree, asks the agent (POST /mcp-tool, op "judge") with its turn's credential. The agent knows
//  The user's own words for the turn (never the brain's), runs the judge on the brain the owner chose and answers. No credential,
//  no agent, no answer in time or an odd one: a block.
//

import Foundation

func askReadJudge(_ call: ArisReadCall, environment: [String: String] = ProcessInfo.processInfo.environment) -> ArisReadVerdict {
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty,
          let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/mcp-tool") else { return .blocked(.undecided) }
    let wait = ArisReadGate.timeout + 8
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: ArisReadGate.body(call, turn: turn))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = wait
    configuration.timeoutIntervalForResource = wait
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
        if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + wait + 2)
    return ArisReadGate.verdict(reply: reply)
}
