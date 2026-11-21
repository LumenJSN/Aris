//
//  ArisAppsFace.swift
//  aris-agent (Core 2 app layer, jv-apps)
//
//  The thin shim between the app layer and the capability registry's faces (jv-hands: the MCP server and the API
//  brains' functions). Each capability as a tool (wire name, description, JSON Schema), its effect class for the
//  trust policy before it runs, and a call by wire name that answers with the outcome's JSON text. When the registry
//  lands, its entries are made from `tools` and route to `call`; nothing else needs to change.
//

import Foundation

enum ArisAppsFace {
    struct Tool {
        let name: String
        let description: String
        let inputSchema: [String: Any]
    }

    static var tools: [Tool] {
        ArisApps.Specs.all.map { Tool(name: $0.wireName, description: $0.summary, inputSchema: $0.parameters.any as? [String: Any] ?? [:]) }
    }

    /// The effect class a call would have (nil for a tool that isn't the app layer's).
    static func effect(_ name: String, arguments: [String: Any], hands: ArisAppsHands = .shared) -> ArisApps.Effect? {
        guard ArisApps.Spec.named(name) != nil else { return nil }
        return hands.effect(name, ArisApps.JSON(any: arguments))
    }

    /// Runs a call: the outcome's JSON (compact) and whether it failed.
    static func call(_ name: String, arguments: [String: Any], background: Bool, hands: ArisAppsHands = .shared) -> (text: String, isError: Bool)? {
        run(name, arguments: arguments, background: background, hands: hands).map { ($0.json.text, !$0.ok) }
    }

    /// Runs a call: its whole outcome (with the undo of a change it made).
    static func run(_ name: String, arguments: [String: Any], background: Bool, hands: ArisAppsHands = .shared) -> ArisApps.Outcome? {
        guard ArisApps.Spec.named(name) != nil else { return nil }
        return hands.call(name, ArisApps.JSON(any: arguments), context: ArisAppsHands.Context(background: background))
    }
}
