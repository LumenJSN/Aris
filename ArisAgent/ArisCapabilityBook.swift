//
//  ArisCapabilityBook.swift
//  aris-agent
//
//  The tool surface (ARCHITECTURE Part 2, Hands): every capability a brain can call, as one list of entries. The MCP
//  face (ArisHandsFace, the provider's only tools with `arisCore2` on) lists exactly these; the old path's API brains
//  keep their own typed functions (ArisCapabilities.functions, byte for byte as before).
//
//  THE SHAPE OF AN ENTRY (ArisCapabilityEntry):
//    id           dotted, for the trust policy and the record: "shell.run", "aris.timer", "app.find"
//    name         the tool's name as a model sees it: letters, digits, _ and -, at most 64 ("shell_run", "timer")
//    description  one or two sentences for the model
//    parameters   a JSON Schema object (["type": "object", "properties": …, "required": …])
//    effect       (arguments) -> ArisEffectClass: what this call does (observe, change-reversible, change-permanent,
//                 outward, never), per call where it depends on the arguments
//    run          .arisTools(argv:stdin:)  an aris-tools call: judged as the very shell line it is (today's gates), run
//                                          as aris-tools with those words
//                 .helper(body)            runs in the helper: (arguments, ArisCapabilityContext) -> ArisToolResult; a
//                                          result that is content Aris read carries ArisToolResult.Content (its source)
//    sealed       offered to a sealed or hands-free API turn (old path only; false for new entries)
//
//  ADDING CAPABILITIES FROM ANOTHER FILE: write `extension ArisCapabilityBook { static let apps: [ArisCapabilityEntry] =
//  [ … ] }` in your file and add `apps` to `sections` below (one line; nothing else to register). Names must be unique
//  across the book (tests/hands-tests.swift checks it).
//

import Foundation

/// What a helper capability gets besides its arguments: the caller's environment (a Claude's, for the MCP face), Aris's
/// folder, the home folder, aris-tools' path and how long it may take.
struct ArisCapabilityContext: @unchecked Sendable {
    let environment: [String: String]
    let folder: URL
    let home: String
    let tools: String
    var timeout: TimeInterval = 120
    /// A file capability's place as the executor checked it just before the run, in the disk's spelling
    /// (ArisCore2.fileTarget): opened without following a link and confirmed once open. Nil: as given.
    var checkedReal: String?
}

struct ArisCapabilityEntry: @unchecked Sendable {
    enum Run {
        case arisTools(argv: ([String: Any]) -> [String]?, stdin: (([String: Any]) -> String?)?)
        case helper(([String: Any], ArisCapabilityContext) -> ArisToolResult)
    }

    let id: String
    let name: String
    let description: String
    let parameters: [String: Any]
    let effect: ([String: Any]) -> ArisEffectClass
    let run: Run
    var sealed = false
    /// The call is a payment (decision 1): it asks on a card of its own every time (ArisTrustPolicy.payment). Only the
    /// registry says so; an amount or a payee among the arguments alone doesn't.
    var payment: ([String: Any]) -> Bool = { _ in false }

    /// The aris-tools words of a call (an `.arisTools` entry); nil for a helper entry or arguments of the wrong shape.
    func argv(_ arguments: [String: Any]) -> [String]? {
        guard case .arisTools(let make, _) = run, let words = make(arguments), !words.isEmpty, words.count <= 64,
              words.allSatisfy({ !$0.contains("\0") && !$0.contains("\r") && $0.count <= 20_000 }) else { return nil }
        return words
    }
}

enum ArisCapabilityBook {
    /// Every file's list, in the order a brain sees them. Add yours here (see the top of this file).
    static let sections: [[ArisCapabilityEntry]] = [arisTools, core2, fleet, record, recordQuery, apps, taught]

    static var all: [ArisCapabilityEntry] { sections.flatMap { $0 } }

    static func entry(named name: String) -> ArisCapabilityEntry? { all.first { $0.name == name } }
    static func entry(id: String) -> ArisCapabilityEntry? { all.first { $0.id == id } }

    /// The effect class of an aris-tools call, by its row in the inventory (ArisCapabilities); a call no row names, or
    /// that can't be read, is the strongest short of the never-list until a row says otherwise. A desktop call, and a
    /// `keys` press, by its own words and stdin (ArisDesktopEffect: a look observes, a batch is its strongest step).
    static func effect(ofArisTools argv: [String]?, stdin: String? = nil) -> ArisEffectClass {
        guard let argv, let row = ArisCapabilities.capability(argv) else { return .changePermanent }
        // Only a look on the desktop command's allowlist is below the row; anything else is at least the row's class.
        if argv.first == "desktop" { return ArisDesktopEffect.effect(Array(argv.dropFirst()), text: stdin, floor: row.effectClass) }
        if argv.first == "keys" { return ArisEffectClass.strongest([row.effectClass, ArisDesktopEffect.effect(ofKeysCommand: Array(argv.dropFirst()))]) }
        return row.effectClass
    }

    /// The aris-tools section: every typed function of the old catalogue, the generic `aris` included (its words name
    /// any command), judged and run exactly as the shell call it is.
    static let arisTools: [ArisCapabilityEntry] = ArisCapabilities.functions.map { old in
        ArisCapabilityEntry(id: "aris." + old.function.name, name: old.function.name, description: old.function.description,
                            parameters: old.function.parameters, effect: { effect(ofArisTools: old.argv($0), stdin: old.stdin?($0)) },
                            run: .arisTools(argv: old.argv, stdin: old.stdin), sealed: old.sealed,
                            payment: { pays(argv: old.argv($0)) })
    }

    /// An aris-tools line that pays: `mcp call <service> <tool>` whose tool moves money (ArisRiskPolicy's money rule).
    static func pays(argv: [String]?) -> Bool {
        guard let argv, argv.count >= 4, argv[0] == "mcp", argv[1] == "call" else { return false }
        return ArisRiskPolicy.hardLine(of: .mcp(server: argv[2], tool: argv[3])) == .money || ArisPaymentSteps.names(argv[3])
    }
}
