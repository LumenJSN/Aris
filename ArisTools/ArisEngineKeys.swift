//
//  ArisEngineKeys.swift
//  aris-tools
//
//  `keys` (and `new`'s ⌘N) through Aris's own engine in the agent (POST /desktop-keys): aris-tools names the app and
//  the agent presses the keys into its focused window in the background, or after a brief turn in front in a gap in
//  The user's input, inside the desktop lock (ArisDesktopKeysRoute). aris-tools itself no longer brings an app forward to
//  press keys, and never posts them to whatever is in front. Asked with the turn's credential or the agent's own held
//  work's id (ArisDesktopHoldPlan); with neither, nothing is sent.
//

import Foundation

/// The agent's line for the keys, and whether they went.
func engineKeys(_ keys: [String], times: Int, bundle: String?) -> (ok: Bool, line: String) {
    var asked: [String: Any] = ["keys": keys, "times": times]
    if let bundle { asked["app"] = bundle }
    switch ArisDesktopHoldPlan.plan(environment: ProcessInfo.processInfo.environment, read: readCredential) {
    case .refuse: return (false, "aris-tools keys works only inside an Aris turn or Aris's own replay, and none was found, so nothing was sent.")
    case .turn(let turn): asked["turn"] = turn
    case .held(let id): asked["held"] = id
    }
    guard let token = ClaudeHookToken.load(), let url = URL(string: "http://127.0.0.1:23351/desktop-keys") else { return (false, "Aris's agent isn't set up (no token)") }
    // The lock's wait, a job's wait for a gap, and a little more.
    let wait: TimeInterval = 150
    var request = URLRequest(url: url, timeoutInterval: wait)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
    request.httpBody = try? JSONSerialization.data(withJSONObject: asked)
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
    guard let reply, let output = reply["output"] as? String else { return (false, "Aris's agent didn't answer, so the keys weren't sent") }
    return ((reply["status"] as? Int) == 0, output)
}
