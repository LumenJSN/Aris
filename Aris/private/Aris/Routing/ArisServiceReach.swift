//
//  ArisServiceReach.swift
//  Aris
//
//  The services Aris reaches without a browser, by name, for the router's website-work decision. The owner,
//  2026-11-19: "Canvas 확인해서 … 과제 정리해 줘" went to Aside, the browser agent, for eight minutes, though Aris has its
//  own Canvas tool and he had just connected Composio. A request that names a service Aris reaches some other way goes
//  in this order: Aris's own tool for it, then a connected service, and the browser agent only when neither can. The
//  router's guess ("several steps on websites") is kept for every other site. Foundation only (tested).
//

import Foundation

struct ArisServiceReach: Equatable, Sendable {
    /// How Aris reaches a service.
    enum Route: String, Equatable, Sendable {
        /// One of Aris's own tools (`aris-tools canvas`).
        case own
        /// A service in 설정 › 연결된 서비스 (Composio, or the user's own MCP server), through `aris-tools mcp`.
        case connected
    }

    struct Service: Equatable, Sendable {
        /// What it is called: the tool (`canvas`) or the connected service as listed (`composio`).
        let name: String
        let route: Route
        /// The names a request may use for it, lowercased.
        let covers: [String]
    }

    /// In the order they are tried: Aris's own tools first.
    let services: [Service]

    static let none = ArisServiceReach(services: [])

    /// One row of 연결된 서비스 as the agent lists it (never a secret).
    struct ConnectedRow: Equatable, Sendable {
        let name: String
        let enabled: Bool
        let composio: Bool
        /// What its last listing found (nil before any).
        let tools: [String]?
    }

    /// The names of Aris's own Canvas tool.
    static let canvasNames = ["canvas", "캔버스"]

    /// The apps Composio Connect has a toolkit for, by the names a request uses. Composio's tool list is the same few
    /// meta tools for every account (COMPOSIO_SEARCH_TOOLS…), so which toolkits the user linked shows only when one is
    /// called: a toolkit not linked there says so, and the turn goes on to the browser agent.
    static let composioToolkits: [String] = [
        "canvas", "캔버스", "gmail", "지메일", "google calendar", "구글 캘린더", "google drive", "구글 드라이브", "google docs", "구글 문서",
        "google sheets", "구글 시트", "slack", "슬랙", "notion", "노션", "github", "깃허브", "jira", "지라",
        "trello", "트렐로", "asana", "아사나", "discord", "디스코드", "outlook", "아웃룩", "todoist", "dropbox", "드롭박스",
        "figma", "피그마", "airtable", "hubspot", "calendly", "confluence", "컨플루언스", "clickup",
    ]

    /// Words in a tool's or a server's name that name no service.
    private static let generic: Set<String> = ["mcp", "server", "tool", "tools", "get", "list", "search", "find", "fetch", "read", "query", "create",
                                               "update", "delete", "send", "add", "remove", "set", "run", "my", "the", "api"]

    /// What is reachable now: Aris's own Canvas tool when it is set up, then each connected service that is on.
    static func make(canvasSetUp: Bool, connected: [ConnectedRow]) -> ArisServiceReach {
        var services: [Service] = []
        if canvasSetUp { services.append(Service(name: "canvas", route: .own, covers: canvasNames)) }
        for row in connected where row.enabled {
            let covers = row.composio ? composioToolkits : names(server: row.name, tools: row.tools ?? [])
            if !covers.isEmpty { services.append(Service(name: row.name, route: .connected, covers: covers)) }
        }
        return ArisServiceReach(services: services)
    }

    /// The services the words name, in the order they are tried (empty: none, the browser agent as the router said).
    func reaching(_ words: String) -> [Service] {
        let lowered = words.lowercased()
        return services.filter { service in service.covers.contains { Self.names($0, in: lowered) } }
    }

    /// The line the brain's context gets when a request a router took for website work names a service Aris reaches:
    /// the order to try them in, and that the answer says which way it went when it had to fall back. Data, like the
    /// rest of the context.
    static func contextLine(_ reached: [Service]) -> String? {
        guard !reached.isEmpty else { return nil }
        let steps = reached.map { service in
            service.route == .own ? "Aris's own `\(service.name)` tool" : "the connected service \(service.name) (`mcp`)"
        }
        return "reach without a browser: try " + steps.joined(separator: ", then ")
            + ", and hand it to Aside (the browser agent) only if those can't; if you fall back, say in a few words which way you used"
    }

    // MARK: - Names

    /// Whether `name` is in `text` as a word of its own: Latin names not inside a longer Latin word ("canvases" isn't
    /// Canvas); Korean ones anywhere (a particle follows them: "캔버스에서").
    static func names(_ name: String, in text: String) -> Bool {
        guard name.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) else { return text.contains(name) }
        let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: name) + "(?![a-z0-9])"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// The names a server of the user's goes by: the words of its own name and the first word of each tool's
    /// (`canvas_list_assignments` → canvas), none of the generic ones.
    static func names(server: String, tools: [String]) -> [String] {
        let split = { (text: String) in
            text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        }
        let words = split(server) + tools.compactMap { split($0).first }
        var seen: Set<String> = []
        return words.filter { $0.count >= 3 && !generic.contains($0) && seen.insert($0).inserted }
    }
}
