//
//  ArisController+ModelVoice.swift
//  Aris
//
//  The model or effort said out loud (ArisModelVoice): the 대화 choice of the brain that answers, for this conversation
//  or saved, and said back on the Mac; the brain's processes for it start at once (POST /warm).
//

import Foundation

extension ArisController {
    func changeModel(_ command: ArisModelVoiceCommand, text: String, heard: String, brain: ArisBrain, tier: ArisTier, korean: Bool) async -> String {
        understood(text, path: "local", tier: tier)
        let store = ArisModelChoiceStore.shared
        let selected = [store.saved.choice(brain, .conversation).model].compactMap { $0 }
        let outcome = ArisModelVoice.outcome(command, brain: brain, options: store.lists.options(brain, selected: selected), korean: korean)
        store.apply(outcome, brain: brain)
        if !outcome.changes.isEmpty { ArisAgentClient.warm(brain) }
        await sayLocal(outcome.line, heard: heard)
        return outcome.line
    }
}
