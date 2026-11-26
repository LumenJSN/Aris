//
//  ArisSessionCommand.swift
//  aris-tools
//
//  `session list` and `session send <session folder or id> <text…>`: the user's own Claude Code sessions, and a prompt typed
//  into one of them after his card (the owner, 2026-11-15). aris-tools holds no rule and types nothing: it hands the
//  words to the agent (POST /session-tool) with its turn's credential, and the agent picks the session, asks the user on
//  his card, checks the session and its tab, and types (ArisSessionSend). Every brain the same.
//

import Foundation

/// The body for POST /session-tool, or why not.
func sessionRequest(_ args: [String], environment: [String: String]) -> Result<[String: Any], ArisMCPUsage> {
    guard let path = environment["ARIS_MCP_TURN_FILE"], path.hasPrefix("/"), let turn = readCredential(path), !turn.isEmpty else {
        return .failure(ArisMCPUsage(text: "aris-tools session works only inside an Aris turn"))
    }
    let usage = "usage: aris-tools session list | status <session> | send <session> <text> | interrupt <session> | answer <session> allow|deny"
        + " | start <folder> <instruction> [--tool claude|codex] | stop <session>"
    // The same forms the sealed list allows (ArisSealedTools.sessionForm); the agent reads them again.
    guard ArisSealedTools.sessionForm(args) else { return .failure(ArisMCPUsage(text: usage)) }
    return .success(["turn": turn, "words": args])
}

func session(_ args: [String]) {
    let body: [String: Any]
    switch sessionRequest(args, environment: ProcessInfo.processInfo.environment) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/session-tool") else { fail("Aris's agent isn't set up (no token)") }
    // The user's card waits up to ten minutes for a background job, then the checks and the typing take seconds.
    let wait: TimeInterval = 720
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = ArisNoStore.configuration()
    configuration.timeoutIntervalForRequest = wait
    configuration.timeoutIntervalForResource = wait
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var reply: [String: Any]?
    URLSession(configuration: configuration).dataTask(with: request) { data, _, _ in
        if let data { reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        done.signal()
    }.resume()
    _ = done.wait(timeout: .now() + wait + 5)
    guard let reply, let output = reply["output"] as? String else { fail("Aris's agent didn't answer (is it running?)") }
    let status = (reply["status"] as? Int) ?? 1
    if status == 0 { print(output) } else { try? FileHandle.standardError.write(contentsOf: Data((output + "\n").utf8)) }
    exit(Int32(clamping: status))
}
