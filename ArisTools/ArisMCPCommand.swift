//
//  ArisMCPCommand.swift
//  aris-tools
//
//  `mcp list [service]` and `mcp call <service> <tool> '<json arguments>'` (or key=value words): the external services
//  The user connected (Composio, their own MCP servers), for every brain the same way. aris-tools holds no service, key or
//  rule itself: it hands the call to the agent (POST /mcp-tool) with its turn's credential, and the agent's one gate
//  decides (reads run, anything that changes or sends shows the user a card and waits). What it prints is the agent's
//  answer, already marked as outside text.
//

import Foundation

func mcp(_ args: [String]) {
    let body: [String: Any]
    switch mcpRequest(args, environment: ProcessInfo.processInfo.environment) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/mcp-tool") else {
        fail("Aris's agent isn't set up (no token)")
    }
    // A card waits up to ten minutes for a background job, a minute in a conversation, then the tool runs.
    let wait: TimeInterval = 720
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = wait
    configuration.timeoutIntervalForResource = wait
    let session = URLSession(configuration: configuration)
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    session.dataTask(with: request) { data, _, _ in
        if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + wait + 5)
    guard let reply, let output = reply["output"] as? String else { fail("Aris's agent didn't answer (is it running?)") }
    let status = (reply["status"] as? Int) ?? 1
    if status == 0 { print(output) } else { FileHandle.standardError.write(Data((output + "\n").utf8)) }
    exit(Int32(clamping: status))
}
