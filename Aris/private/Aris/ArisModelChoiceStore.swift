//
//  ArisModelChoiceStore.swift
//  Aris
//
//  Where the app keeps the model choices (ArisModelChoice): the saved ones in Defaults, the ones said for this
//  conversation in memory, and every brain's model list as its tool gave it (ArisModelLists, refreshed through
//  aris-agent's POST /models when Settings opens, at most daily). Each request to aris-agent carries the choices for its
//  turn (`payload`), as it carries the brain.
//

import Defaults
import Foundation

extension Defaults.Keys {
    /// The saved choices, flat ("claude.conversation.model": "opus"); empty: 자동 everywhere.
    static let arisModelChoices = Key<[String: String]>("arisModelChoices", default: [:])
    /// Every brain's model list with the time it was read (ArisModelLists' JSON).
    static let arisModelLists = Key<String>("arisModelLists", default: "")
}

final class ArisModelChoiceStore: @unchecked Sendable {
    static let shared = ArisModelChoiceStore()

    private let lock = NSLock()
    private var conversation = ArisConversationModels()

    var saved: ArisModelChoices { ArisModelChoices(entries: Defaults[.arisModelChoices]) }

    func save(_ choices: ArisModelChoices) { Defaults[.arisModelChoices] = choices.entries }

    var lists: ArisModelLists { ArisModelLists.decode(Defaults[.arisModelLists]) }

    func store(_ lists: ArisModelLists) { Defaults[.arisModelLists] = lists.encoded() }

    /// What a request to aris-agent carries: a conversation's turn moves the conversation's own choices along (a new
    /// conversation drops them unless they were just said); anything else only reads them.
    func payload(fresh: Bool, conversationTurn: Bool) -> [String: String] {
        let saved = saved
        return lock.withLock {
            guard conversationTurn else { return conversation.current(saved: saved).entries }
            let sent = conversation.sending(fresh: fresh, saved: saved)
            conversation = sent.state
            return sent.choices.entries
        }
    }

    /// A choice made in Settings: saved, and this conversation's own word on it gives way.
    func choose(_ brain: ArisBrain, _ role: ArisModelRole, _ field: ArisModelChoices.Field, _ value: String?) {
        save(saved.setting(brain, role, field, to: value))
        lock.withLock { conversation = conversation.forgetting(brain, role, field) }
    }

    /// A model or effort said out loud (ArisModelVoice): saved, or for this conversation.
    func apply(_ outcome: ArisModelVoice.Outcome, brain: ArisBrain) {
        guard !outcome.changes.isEmpty else { return }
        if outcome.always {
            var choices = saved
            for change in outcome.changes { choices = choices.setting(brain, .conversation, change.field, to: change.value) }
            save(choices)
            // A saved choice said aloud also ends this conversation's own one for the same field.
            lock.withLock {
                for change in outcome.changes { conversation = conversation.forgetting(brain, .conversation, change.field) }
            }
            return
        }
        lock.withLock {
            for change in outcome.changes { conversation = conversation.saying(brain, .conversation, change.field, change.value) }
        }
    }
}
