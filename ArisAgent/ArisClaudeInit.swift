//
//  ArisClaudeInit.swift
//  aris-agent
//
//  What a Claude's init line must show before it may answer, and how a Claude Code update that adds a tool stops
//  costing every turn (jv-fastlane). Checked live on claude 2.1.327: `--tools` gives the built-in tools, and a bare name
//  in `--disallowedTools` takes that tool out of the process altogether (it is not listed in init and the model never
//  sees it; a pattern rule such as `Bash(rm:*)` leaves the tool listed). So a tool init lists is never denied whole by
//  the flags, and "dontAsk" refuses only tools that ask for permission: one that needs none would run. The process that
//  shows an unasked-for tool is therefore never let answer (exact match stays the rule). What changes is the next one:
//  the extra tool's name is denied by name at its launch, so it is not there at all, and the turn is asked again once
//  on that new process. An MCP server, a tool missing, or a name that isn't a plain built-in tool name still stops the
//  turn as before.
//

import Foundation

enum ArisClaudeInit {
    enum Verdict: Equatable {
        /// Exactly the expected tools and no MCP server.
        case ok
        /// Stopped, the turn fails (an MCP server, an expected tool missing, a name that can't be denied, no list).
        case refused
        /// Only extra built-in tools: stopped, and the next process starts with these denied by name.
        case relaunch(extra: [String])
    }

    /// A name that can stand alone as a deny rule: a built-in tool's (letters and digits), never a pattern, an MCP tool
    /// (`mcp__…`) or anything with rule syntax in it.
    static func deniable(_ name: String) -> Bool {
        !name.hasPrefix("mcp__") && name.range(of: #"^[A-Z][A-Za-z0-9]{0,63}$"#, options: .regularExpression) != nil
    }

    /// `mcp`: the MCP face's tool names (ArisHandsFace) when this Claude has it: then exactly its one server, connected,
    /// and exactly those MCP tools; the built-in tools are checked as ever. nil: no MCP server at all, as before.
    static func verdict(listed: [String]?, servers: [Any]?, expected: Set<String>, mcp: [String]? = nil) -> Verdict {
        if let mcp {
            guard let listed, let servers, servers.count == 1, let server = servers.first as? [String: Any],
                  server["name"] as? String == ArisMCPServerWire.serverName, server["status"] as? String == "connected",
                  Set(listed).count == listed.count, Set(listed.filter { $0.hasPrefix("mcp__") }) == Set(mcp), Set(mcp).count == mcp.count else { return .refused }
            return verdict(listed: listed.filter { !$0.hasPrefix("mcp__") }, servers: [], expected: expected)
        }
        guard let listed, let servers, servers.isEmpty else { return .refused }
        let names = Set(listed)
        guard names.count == listed.count, expected.isSubset(of: names) else { return .refused }
        let extra = names.subtracting(expected).sorted()
        if extra.isEmpty { return .ok }
        return extra.count <= ArisClaudeToolDrift.most && extra.allSatisfy(deniable) ? .relaunch(extra: extra) : .refused
    }
}

/// The extra tools Claude Code showed this launch of the helper, denied by name in every Claude started after
/// (ArisClaudeDriver's `--disallowedTools`). Only ever grows, so it only ever takes tools away. Shared by every runner.
final class ArisClaudeToolDrift {
    static let shared = ArisClaudeToolDrift()

    /// More than this many new names at once is not an update adding a tool: nothing is learned, the turn just stops.
    static let most = 8

    private let lock = NSLock()
    private var names: [String] = []

    var denied: [String] { lock.withLock { names } }

    /// Learns `extra` (each deniable); false when nothing was learned (too many, any not deniable, or none). At most
    /// twice `most` names in all are ever kept.
    @discardableResult
    func learn(_ extra: [String]) -> Bool {
        guard !extra.isEmpty, extra.count <= Self.most, extra.allSatisfy(ArisClaudeInit.deniable) else { return false }
        let fresh = extra
        return lock.withLock {
            let new = fresh.filter { !names.contains($0) }
            guard names.count + new.count <= Self.most * 2 else { return false }
            names += new
            return true
        }
    }

    /// Tests only.
    func forget() { lock.withLock { names = [] } }
}
