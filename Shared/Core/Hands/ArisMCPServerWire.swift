//
//  ArisMCPServerWire.swift
//  Shared/Core (aris-agent, tests)
//
//  The wire of Aris's own MCP server (the capability registry's MCP face, ARCHITECTURE 3.4): MCP's JSON-RPC 2.0 over
//  stdio, one message a line, as Claude Code speaks it to a stdio server. Only what a tools-only server needs:
//  initialize (the client's protocol version when it is one this knows, else the newest), ping, tools/list (one page),
//  tools/call (handed to the caller, which answers with `callResult`), notifications/cancelled (handed to the caller),
//  and errors for anything else. Pure: lines in, lines out; the server loop is ArisHandsShim.
//

import Foundation

enum ArisMCPServerWire {
    /// The server's name in the client's config, and so the middle of every tool's name there (mcp__aris__timer).
    static let serverName = "aris"
    static let toolPrefix = "mcp__\(serverName)__"
    /// Newest first: the version answered when the client asks for one not listed.
    static let versions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    /// A longer line is refused unread (a call's arguments are a few kilobytes; a desktop batch's text at most 128 KiB).
    static let longestLine = 1_048_576

    struct Tool: @unchecked Sendable {
        let name: String
        let description: String
        let inputSchema: [String: Any]
    }

    enum Step: @unchecked Sendable {
        /// Write this line back now.
        case reply(Data)
        /// Run this call; answer with `callResult(id:…)`. `id` is the request's own id (a number or a string).
        case call(id: Any, name: String, arguments: [String: Any])
        /// The client gave up on the call with this id.
        case cancel(Any)
        /// A notification that needs nothing.
        case nothing
    }

    /// The tool's name as the client lists it, for a function of the registry.
    static func clientName(_ function: String) -> String { toolPrefix + function }

    /// The function a client-side tool name stands for; nil for any other tool (a built-in one, another server's).
    static func function(clientName: String) -> String? {
        guard clientName.hasPrefix(toolPrefix) else { return nil }
        let name = String(clientName.dropFirst(toolPrefix.count))
        return name.isEmpty ? nil : name
    }

    /// The answer to one line from the client, given the tools this server lists.
    static func step(_ line: Data, tools: [Tool]) -> Step {
        guard line.count <= longestLine, let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            return .reply(error(id: NSNull(), code: -32700, message: "Parse error"))
        }
        let method = object["method"] as? String
        guard let id = object["id"], !(id is NSNull) else {
            // A notification (no id): only a cancel matters.
            if method == "notifications/cancelled", let params = object["params"] as? [String: Any], let request = params["requestId"] {
                return .cancel(request)
            }
            return .nothing
        }
        guard object["jsonrpc"] as? String == "2.0", let method else { return .reply(error(id: id, code: -32600, message: "Invalid Request")) }
        let params = object["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return .reply(result(id: id, [
                "protocolVersion": versions.contains(asked) ? asked : versions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": serverName, "version": "1"],
            ]))
        case "ping":
            return .reply(result(id: id, [:]))
        case "tools/list":
            return .reply(result(id: id, ["tools": tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.inputSchema] as [String: Any] }]))
        case "tools/call":
            guard let name = params["name"] as? String, tools.contains(where: { $0.name == name }) else {
                return .reply(error(id: id, code: -32602, message: "Unknown tool"))
            }
            if let given = params["arguments"], !(given is NSNull), !(given is [String: Any]) {
                return .reply(error(id: id, code: -32602, message: "Arguments must be an object"))
            }
            return .call(id: id, name: name, arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            return .reply(error(id: id, code: -32601, message: "Method not found"))
        }
    }

    /// Where Claude Code puts the id its stream gives the call (checked live on 2.1.328: `params._meta`).
    static let toolUseIdKey = "claudecode/toolUseId"

    /// The provider's own id for a tools/call line (ArisFaceDecisions.wellFormed); nil for any other line or none.
    static func toolUseId(_ line: Data) -> String? {
        guard line.count <= longestLine, let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["method"] as? String == "tools/call", let params = object["params"] as? [String: Any],
              let id = (params["_meta"] as? [String: Any])?[toolUseIdKey] as? String, ArisFaceDecisions.wellFormed(id) else { return nil }
        return id
    }

    /// A call's answer: its text, and whether it failed (refused, declined, or the command's own error).
    /// `meta`: the result's `_meta` (where its content came from: ArisToolResult.meta).
    static func callResult(id: Any, text: String, isError: Bool, meta: [String: Any]? = nil) -> Data {
        var value: [String: Any] = ["content": [["type": "text", "text": text]], "isError": isError]
        if let meta { value["_meta"] = meta }
        return result(id: id, value)
    }

    /// Two request ids name the same request (a number and a string never do).
    static func sameID(_ a: Any, _ b: Any) -> Bool {
        switch (a, b) {
        case (let x as String, let y as String): return x == y
        case (let x as NSNumber, let y as NSNumber): return x == y
        default: return false
        }
    }

    static func result(id: Any, _ value: [String: Any]) -> Data {
        line(["jsonrpc": "2.0", "id": id, "result": value])
    }

    static func error(id: Any, code: Int, message: String) -> Data {
        line(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
    }

    /// One message as one line (JSON never carries a raw line break outside a string).
    private static func line(_ object: [String: Any]) -> Data {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return data + Data("\n".utf8)
    }
}
