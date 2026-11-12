//
//  ArisAgentClient+Teammates.swift
//  Aris
//
//  The teammate list through aris-agent (POST /teammates): the sandboxed app can read ~/.config/aris but not write it,
//  so the settings 팀원 page reads and saves here. Sent with this app's pid and start time: only the app itself may
//  change a teammate (ArisPeer), never a model's shell or a Claude Code session holding the token.
//

import Foundation

enum ArisTeamSave: Equatable {
    case saved([ArisTeammate])
    /// 400: what the agent refused ("name", "role", "look", …; ArisTeammateEdit.Problem).
    case invalid(String)
    /// 403: the agent couldn't tell this was the Aris app.
    case refused
    case failed
}

extension ArisAgentClient {
    private static let teammatesURL = URL(string: "http://127.0.0.1:23351/teammates")!

    /// The stored teammates (Claude Code always among them); nil when the agent didn't answer or refused.
    static func teammates() async -> [ArisTeammate]? {
        guard let (status, data) = await sendTeam(["op": "list"]), status == 200 else { return nil }
        return decodeTeam(data)
    }

    /// Replaces the list with `teammates`; the agent checks every entry and writes all or nothing.
    static func saveTeammates(_ teammates: [ArisTeammate]) async -> ArisTeamSave {
        let entries = teammates.map { mate -> [String: Any] in
            var look: [String: Any] = ["type": mate.look.type, "shading": mate.look.shading]
            if let hex = mate.look.colorHex { look["colorHex"] = hex }
            return ["id": mate.id, "name": mate.name, "routing": mate.routing, "instructions": mate.instructions, "scopes": mate.scopes,
                    "look": look, "brain": mate.brain]
        }
        guard let (status, data) = await sendTeam(["op": "save", "teammates": entries]) else { return .failed }
        switch status {
        case 200: return decodeTeam(data).map(ArisTeamSave.saved) ?? .failed
        case 400: return .invalid(((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? "")
        case 403: return .refused
        default: return .failed
        }
    }

    private static func decodeTeam(_ data: Data) -> [ArisTeammate]? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let list = root["teammates"] as? [Any],
              let inner = try? JSONSerialization.data(withJSONObject: list) else { return nil }
        return ArisTeammate.list(from: inner)
    }

    static func sendTeam(_ body: [String: Any]) async -> (Int, Data)? {
        guard let token = ClaudeHookToken.load() else { return nil }
        var payload = body
        payload["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        if let started { payload["started"] = started }
        var request = URLRequest(url: teammatesURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: ClaudeHookToken.header)
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        // URLSession.shared: its sockets live in this process, which is what ArisPeer's socket check reads.
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (status, data)
    }
}
