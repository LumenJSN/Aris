//
//  ArisUndoArguments.swift
//  aris-tools, aris-agent
//
//  How `aris-tools undo`'s arguments are read: the one parser, used by aris-tools to run it and by the risk gate to judge
//  and describe it, so the gate can never read a command differently from the tool that runs it.
//

import Foundation

enum ArisUndoArguments {
    struct Parsed: Equatable {
        let id: UUID?
        let confirmed: Bool
    }

    /// `[--id <uuid>] [--confirmed]` and nothing else; nil when anything is left over, the id isn't a UUID, or a yes
    /// (`--confirmed`) comes without the id of the entry it is for.
    static func parse(_ arguments: [String]) -> Parsed? {
        var words = arguments
        let confirmed = words.contains("--confirmed")
        words.removeAll { $0 == "--confirmed" }
        var id: UUID?
        if let flag = words.firstIndex(of: "--id") {
            guard flag + 1 < words.count, let parsed = UUID(uuidString: words[flag + 1]) else { return nil }
            id = parsed
            words.removeSubrange(flag...(flag + 1))
        }
        guard words.isEmpty, !confirmed || id != nil else { return nil }
        return Parsed(id: id, confirmed: confirmed)
    }
}
