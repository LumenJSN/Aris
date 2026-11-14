//
//  ArisDesktopHold.swift
//  aris-tools
//
//  `window …` from inside a brain's turn moves another app's window: before it does, the turn takes its turn at the
//  Mac's keys and pointer from the agent (POST /desktop-hold), exactly as a desktop action does, so a voice turn, a
//  typed turn and a teammate job never move or type at the same time. The agent's own replay of a learned shortcut or a
//  window arrangement holds it already and passes the id it holds it as, which the agent confirms; with neither, the
//  command fails closed (ArisDesktopHoldPlan).
//

import Foundation

/// The turn's hold, or a refusal that stops the command (nothing moved). With no turn and no hold of the agent's own,
/// it fails closed (ArisDesktopHoldPlan).
func desktopHold() {
    let asked: [String: Any]
    switch ArisDesktopHoldPlan.plan(environment: ProcessInfo.processInfo.environment, read: readCredential) {
    case .refuse(let why): fail(why)
    case .turn(let turn): asked = ["turn": turn]
    case .held(let id): asked = ["held": id]
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/desktop-hold") else { fail("Aris's agent isn't set up (no token)") }
    // The lock's own wait (90 s) and a little more.
    let wait: TimeInterval = 120
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: asked)
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
    // Inside a turn the agent is there: no answer, or a refusal, and nothing is moved.
    guard let reply, (reply["status"] as? Int) == 0 else { fail((reply?["output"] as? String) ?? "Aris's agent didn't answer, so the window wasn't moved") }
}
