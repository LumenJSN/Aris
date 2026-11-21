//
//  ArisEffectClass.swift
//  Shared/Core (aris-agent, tests)
//
//  ArisEffectClass (the kernel's ArisEffectClass is its reducer's output, another thing). What one capability call does to the world, the first input of the trust policy (ARCHITECTURE Part 2, Judgment:
//  `decide(effect, provenance, grants)`). Every registry entry declares it per call (ArisCapabilityEntry.effect), since
//  it may depend on the arguments: `shell.run` by its command, `file.write` by whether the target exists. Pure.
//

import Foundation

enum ArisEffectClass: String, CaseIterable, Codable, Sendable {
    /// Reads anything, looks, lists: nothing changes.
    case observe
    /// Edits, moves, creates, sets, types into an app: journaled with an undo.
    case changeReversible = "change-reversible"
    /// Deletes for good, overwrites without a copy, runs what can't be taken back.
    case changePermanent = "change-permanent"
    /// Sends to other people, posts, pays, shares, hands work to another agent.
    case outward
    /// The short never-list: refused whoever asks.
    case never

    /// The stronger of two (a command of several parts is as strong as its strongest part).
    static func strongest(_ effects: [ArisEffectClass]) -> ArisEffectClass {
        let order: [ArisEffectClass] = [.observe, .changeReversible, .changePermanent, .outward, .never]
        return effects.max { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! } ?? .observe
    }
}
