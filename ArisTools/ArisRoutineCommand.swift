//
//  ArisRoutineCommand.swift
//  aris-tools
//
//  `routine list`, `routine show <name>`, `routine add --name N --step S [--step S …]`, `routine remove <name>` and
//  `routine wait <id>`: the user's routines (bundles of their own requests, "출근 루틴 해 줘"), the same way on every brain.
//  aris-tools reads and writes nothing itself: it hands the words to the agent (POST /routine-tool) with its turn's
//  credential, and the agent asks the user on a card before a routine is saved or removed. What it prints is the agent's
//  answer. There is no `routine run`: only Aris itself runs one, step by step, when the user asks.
//

import Foundation

func routine(_ args: [String]) {
    let body: [String: Any]
    switch routineRequest(args, environment: ProcessInfo.processInfo.environment) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/routine-tool") else {
        fail("Aris's agent isn't set up (no token)")
    }
    // The agent answers within seconds: a card still waiting comes back as an id for `routine wait`.
    let wait: TimeInterval = 60
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    let configuration = URLSessionConfiguration.ephemeral
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
    if status == 0 { print(output) } else { FileHandle.standardError.write(Data((output + "\n").utf8)) }
    exit(Int32(clamping: status))
}
