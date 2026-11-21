//
//  ArisAppsBook.swift
//  aris-agent (Core 2 app layer, joined to the capability book for jv-teach)
//
//  The app layer's capabilities as entries of the capability book (ArisCapabilityBook.sections), as ArisAppsFace
//  foresaw: one entry per spec (app.find … app.recipe), its wire name, description and schema as they are, its effect
//  class per call from the spec's own assessment, run in the helper through ArisAppsFace.call. So the Mind, the MCP
//  face, and a taught procedure's replay (F3) reach every app through the one trust decision. What a call returns may
//  hold what other people wrote in that app (a window's text, a list's rows): it is marked as the app's content.
//  `hands` and `effectContext` are seams: the tests set a fake app layer and a pure effect context, so no test reads
//  a real app.
//

import Foundation

enum ArisAppsBook {
    /// The app layer the entries run on.
    nonisolated(unsafe) static var hands: () -> ArisAppsHands = { ArisAppsHands.shared }
    /// What a call's effect may depend on besides its arguments (the live hands' by default).
    nonisolated(unsafe) static var effectContext: () -> ArisApps.EffectContext = { hands().effectContext }

    static func effect(_ spec: ArisApps.Spec, _ arguments: [String: Any]) -> ArisEffectClass {
        spec.effect(ArisApps.JSON(any: arguments), effectContext())
    }

    /// A click, choice or command whose words pay (decision 1): the target's words, the element's label from the app's
    /// last read, the option, the command.
    static func pays(_ capability: String, _ arguments: [String: Any]) -> Bool {
        guard ["app.click", "app.select", "app.do", "app.recipe"].contains(capability) else { return false }
        var words = ["target", "option", "command", "action", "task"].compactMap { arguments[$0] as? String }
        if let app = arguments["app"] as? String, let target = arguments["target"] as? String, let label = effectContext().label(app, target) {
            words.append(label)
        }
        return words.contains(where: ArisPaymentSteps.names)
    }

    static func run(_ spec: ArisApps.Spec, _ arguments: [String: Any]) -> ArisToolResult {
        guard let done = ArisAppsFace.run(spec.wireName, arguments: arguments, background: false, hands: hands()) else {
            return ArisToolResult(text: "no capability \(spec.name)", isError: true)
        }
        let app = (arguments["app"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "apps"
        // A change with its undo (text app.type added) carries it to the record, so "되돌려" can take it back.
        return ArisToolResult(text: done.json.text, isError: !done.ok, content: ArisToolResult.Content(kind: "app", source: String(app.prefix(80))),
                              undo: done.ok ? done.undo : nil)
    }
}

extension ArisCapabilityBook {
    static let apps: [ArisCapabilityEntry] = ArisApps.Specs.all.map { spec in
        ArisCapabilityEntry(id: spec.name, name: spec.wireName, description: spec.summary,
                            parameters: spec.parameters.any as? [String: Any] ?? ["type": "object"],
                            effect: { ArisAppsBook.effect(spec, $0) },
                            run: .helper({ arguments, _ in ArisAppsBook.run(spec, arguments) }),
                            payment: { ArisAppsBook.pays(spec.name, $0) })
    }
}
