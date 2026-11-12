//
//  ArisSkillCommand.swift
//  aris-tools
//
//  `skill list`, `skill read <name> [file]` and `skill run <name> <scripts/file> [arguments…]`: the user's skills, the same
//  way on every brain. aris-tools reads and runs nothing itself: it hands the words to the agent (POST /skill-tool) with
//  its turn's credential, and the agent finds the skill (only one that's switched on and checked), keeps every read
//  inside the skill's folder, and asks the user on a card before any script runs. What it prints is the agent's answer.
//

import Foundation

func skill(_ args: [String]) {
    let body: [String: Any]
    switch skillRequest(args, environment: ProcessInfo.processInfo.environment) {
    case .failure(let why): fail(why.text)
    case .success(let made): body = made
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/skill-tool") else {
        fail("Aris's agent isn't set up (no token)")
    }
    // A script's card waits up to ten minutes for a background job, then the script may take two.
    let wait: TimeInterval = 900
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
