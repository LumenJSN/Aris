//
//  ArisHearSource.swift
//  Aris
//
//  "Hear with Scribe" had two keys (settings-ia D6): the 듣기 dropdown's `arisHearEngine` and the old 목소리 · 언어
//  switch's `arisCloudListening`, which could disagree. `arisHearEngine` is the one source now: Scribe listens when it
//  says "scribe". A user whose two keys disagreed keeps what was really in effect: once, at launch, the engine is
//  written as the page already read it (ArisAIStore.read) and the old key is made to agree. Neither key is renamed.
//  Foundation only (tested).
//

import Foundation

enum ArisHearSource {
    /// Whether Scribe listens (with a key): the hearing choice once one is stored; before any, the old switch, which
    /// was on unless turned off. (The turn itself now asks ArisHearPlan; this stays for the migration's meaning.)
    static func scribeListens(_ pref: (String) -> Any?) -> Bool {
        if let engine = pref(ArisAIPrefKey.hearEngine) as? String, ArisAIStore.hearEngines.contains(engine) { return ArisAIStore.usesScribe(engine) }
        return pref(ArisAIPrefKey.cloudListening) as? Bool ?? true
    }

    /// The writes that leave `arisHearEngine` saying what the two keys meant together: none when they agree, and none
    /// when the old switch is on and nothing was chosen (Scribe then still starts by itself once a key is added).
    static func migration(_ pref: (String) -> Any?, facts: ArisAIStore.Facts) -> [(key: String, value: Any)] {
        guard let cloud = pref(ArisAIPrefKey.cloudListening) as? Bool else { return [] }
        let stored = (pref(ArisAIPrefKey.hearEngine) as? String).flatMap { ArisAIStore.hearEngines.contains($0) ? $0 : nil }
        if let stored, cloud == ArisAIStore.usesScribe(stored) { return [] }
        if stored == nil && cloud { return [] }
        let effective = ArisAIStore.read(pref, facts: facts).hear
        return [(ArisAIPrefKey.hearEngine, effective), (ArisAIPrefKey.cloudListening, ArisAIStore.usesScribe(effective))]
    }

    /// Runs the migration against `store`.
    static func migrate(_ store: UserDefaults, facts: ArisAIStore.Facts) {
        for write in migration({ store.object(forKey: $0) }, facts: facts) { store.set(write.value, forKey: write.key) }
    }
}
