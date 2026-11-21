//
//  ArisContentReach.swift
//  Shared/Core (aris-agent, tests)
//
//  Two rules about what content may drive, each after the table and only ever stricter (tenth VM run, items 8 and 9:
//  for "다운로드 폴더 열어 줘" the model pressed cmd+shift+g and typed "~/Downloads" into Finder with no card, each call
//  marked as coming from what was read; and a web page was fetched with no card):
//    · input put into an app (keys, text, a press, a choice, a command) by a call that is the content's: it asks.
//      Opening an app or a window move is not input; the table's own cell stands for those (run, undo kept, said).
//    · an address that first appeared in content the owner didn't point at: the call asks, whatever it does with the
//      address (fetch it, open it), except an address from a page Aris itself fetched from the public web as a look
//      (a search's results): following those is the search, and what such a read may carry out is ArisWebCarry's rule.
//  An address in the owner's own words is his: that call is decided by the table alone (a look runs with no card).
//  The lists are allowlists of what counts as input; nothing here ever makes a call less strict. Pure.
//

import Foundation

enum ArisContentReach {
    /// The app layer's capabilities that put input into an app.
    static let inputCapabilities: Set<String> = ["app.press", "app.type", "app.click", "app.select", "app.do", "app.recipe"]
    /// aris-tools commands that put input into an app (a desktop look is rated observe and never gets here).
    static let inputCommands: Set<String> = ["keys", "type", "desktop"]

    /// Whether a call puts input into an app.
    static func isInput(capability: String, effect: ArisEffectClass, argv: [String]?) -> Bool {
        guard effect != .observe else { return false }
        if let command = argv?.first { return inputCommands.contains(command) }
        return inputCapabilities.contains(capability)
    }

    /// The decision once content's reach is weighed: a call the content drives that would run on its own asks instead.
    static func decide(_ decided: ArisDecision, call: ArisCallFacts, provenance: ArisCallProvenance) -> ArisDecision {
        guard provenance.source != nil, call.inputAct || call.contentAddress else { return decided }
        switch decided {
        case .run, .runWithUndo, .sayThenRun: return .ask
        case .readBackThenAsk, .ask, .refuse: return decided
        }
    }

    /// A replace whose erased text couldn't be read is a card every time (item 4): never run on its own or after a
    /// spoken moment, whoever asked.
    static func unreadErase(_ decided: ArisDecision, call: ArisCallFacts) -> ArisDecision {
        guard let erases = call.erases, erases.text == nil else { return decided }
        switch decided {
        case .run, .runWithUndo, .sayThenRun: return .ask
        case .readBackThenAsk, .ask, .refuse: return decided
        }
    }
}
