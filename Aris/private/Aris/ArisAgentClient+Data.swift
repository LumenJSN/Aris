//
//  ArisAgentClient+Data.swift
//  Aris
//
//  Settings 정보 › 데이터 and API 키 through aris-agent (POST /data, ArisDataRoute): memory, the agent's logs and the
//  old key files are in ~/.config/aris, which the sandboxed app can read but not write. Sent with this app's pid and
//  start time: the agent answers only the Aris app itself (ArisPeer).
//

import Foundation

extension ArisAgentClient {
    private static let dataURL = URL(string: "http://127.0.0.1:23351/data")!

    struct DataSummary: Equatable {
        let memoryFacts: Int
        let logBytes: Int
    }

    struct DataExport {
        let memory: String
        let teammates: [Any]
        /// Each memory's source, mark and whole text ("memoryDetails") and the work memory ("work").
        var extras: [String: Any] = [:]
    }

    static func dataSummary() async -> DataSummary? {
        guard let object = await sendData(["op": "summary"]) else { return nil }
        return DataSummary(memoryFacts: object["memoryFacts"] as? Int ?? 0, logBytes: object["logBytes"] as? Int ?? 0)
    }

    static func dataExport() async -> DataExport? {
        guard let object = await sendData(["op": "export"]) else { return nil }
        return DataExport(memory: object["memory"] as? String ?? "", teammates: object["teammates"] as? [Any] ?? [],
                          extras: object.filter { ["memoryDetails", "work"].contains($0.key) })
    }

    /// The agent's logs for a diagnostics file, already redacted: (file name, text).
    static func diagnosticLogs() async -> [(name: String, text: String)]? {
        guard let object = await sendData(["op": "diagnostics"]), let logs = object["logs"] as? [[String: Any]] else { return nil }
        return logs.compactMap { log in
            guard let name = log["name"] as? String, let text = log["text"] as? String else { return nil }
            return (name, text)
        }
    }

    /// Removes memory and/or the agent's logs (`items`: "memory", "logs"); `confirm` is the word the user typed.
    static func wipeAgentData(_ items: [String], confirm: String) async -> Bool {
        await sendData(["op": "wipe", "items": items, "confirm": confirm]) != nil
    }

    /// The old hand-placed key file `name`; `keychain` is what a fresh Keychain read showed ("saved" or "deleted",
    /// ArisKeychain.dropVerifiedFile): the agent refuses without it.
    static func dropKeyFile(_ name: String, keychain: String) async -> Bool {
        await sendData(["op": "dropKeyFile", "name": name, "keychain": keychain]) != nil
    }

    /// The agent's uninstall, step by step in order (it stops after the app if the app couldn't go to the Trash, and
    /// stops itself after replying); or that it refused, or couldn't be reached or didn't answer within 3 minutes.
    static func uninstall(confirm: String, keepData: Bool) async -> ArisUninstallReply {
        // The agent does every step before it answers (a large ~/.config/aris takes a while to remove).
        let (status, body) = await sendDataStatus(["op": "uninstall", "confirm": confirm, "keepData": keepData], timeout: 180)
        return ArisUninstallReply.from(status: status, body: body)
    }

    /// The reply's JSON object on 200; nil when the agent is off, refused (403) or rejected the request (400).
    private static func sendData(_ body: [String: Any], timeout: TimeInterval = 15) async -> [String: Any]? {
        let (status, object) = await sendDataStatus(body, timeout: timeout)
        return status == 200 ? object ?? [:] : nil
    }

    /// The reply's status and JSON object; a nil status when the agent couldn't be reached or didn't answer.
    private static func sendDataStatus(_ body: [String: Any], timeout: TimeInterval) async -> (status: Int?, object: [String: Any]?) {
        guard let token = ClaudeHookToken.load() else { return (nil, nil) }
        var request = URLRequest(url: dataURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: identified(body))
        // ArisNoStore.session: its sockets live in this process, which is what ArisPeer's socket check reads.
        guard let (data, response) = try? await ArisNoStore.session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return (nil, nil) }
        return (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
    }
}
