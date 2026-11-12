//
//  ArisRoutineTier.swift
//  aris-agent
//
//  How careful the turn of one routine step is. When the user asks something themselves the app's router rates it (quick,
//  work, or critical for sending, deleting and money); a routine's steps are asked from the agent, where that router
//  can't be reached. So a step that says to send, delete, share or pay, or that asks for care ("꼼꼼하게", "carefully"),
//  runs as critical: the gate then asks about everything it doesn't know to be harmless. Any other step runs as
//  ordinary work. Never quick: a saved step is a real request. Pure.
//

import Foundation

enum ArisRoutineTier {
    /// The words with which the user asks for the careful setup themselves (the app's ArisRouter.asksForCare).
    private static let care = #"(?i)제대로|신중하게|신중히|꼼꼼하게|꼼꼼히|조심해서|carefully|thoroughly"#

    static func of(_ step: String) -> ArisTier {
        step.range(of: care, options: .regularExpression) != nil || ArisRiskPolicy.mentionsRiskyStep(step) ? .critical : .work
    }
}
