//
//  ArisUndoScope.swift
//  Shared/Core (aris-agent, tests)
//
//  Which record entries an undo may reach, decided by provenance like every other call:
//    · the owner's own words of this turn ("아까 그거 되돌려", in any conversation): any entry of the last day; an older
//      one only when he names it (its id), and then it is read back and asked;
//    · Aris's own step, the owner's earlier words, or content: only entries made by the same session (a conversation)
//      or task, of the last day;
//    · a background task: only its own entries, whoever asked.
//  Undoing is a change that can be taken back, except where the undo itself is stronger (taking back an event Aris made
//  deletes it from the calendar: change-permanent); then that effect's row of the table decides, with the caller's
//  provenance.
//  The speaker counts too (F1): words in a voice that was not the owner's are not "the owner's own words" here, so they
//  reach only their own session's entries, never an older one, and the policy reads the speaker as for any change.
//  Pure.
//

import Foundation

/// Who asks for an undo: the conversation or task, and the provenance of the call.
struct ArisUndoCaller: Equatable, Sendable {
    var session: String?
    var task: String?
    var provenance: ArisCallProvenance
    /// The owner already said yes on the card for this undo.
    var approved = false
    /// Who spoke the turn that asks (F1); `notChecked`: as before.
    var speaker: ArisTurnSpeaker = .notChecked

    init(session: String?, task: String? = nil, provenance: ArisCallProvenance, approved: Bool = false, speaker: ArisTurnSpeaker = .notChecked) {
        self.session = session
        self.task = task
        self.provenance = provenance
        self.approved = approved
        self.speaker = speaker
    }

    /// The owner's own words of this turn, in his own voice (or no voice was checked).
    var ownerSaid: Bool { provenance == .ownerSaid && speaker.countsAsOwner }
}

enum ArisUndoScope {
    static let recentWindow: TimeInterval = 24 * 3_600
    static let mostAtOnce = 10

    struct Verdict: Equatable, Sendable {
        /// The entries it would undo, newest first.
        let ids: [String]
        let decision: ArisDecision
        /// What is read back when it asks.
        let line: String
    }

    /// What undoing a recipe does to the world.
    static func effect(of recipe: ArisUndoRecipe) -> ArisEffectClass {
        switch recipe {
        case .itemCreated: .changePermanent
        case .fileCreated, .fileChanged, .fileMoved, .fileTrashed, .itemChanged, .setting, .textInserted, .windowMoved: .changeReversible
        }
    }

    /// Whether the caller may reach this entry at all (before the time window).
    static func reaches(_ entry: ArisRecordEntry, caller: ArisUndoCaller) -> Bool {
        if let task = caller.task { return entry.task == task }
        if caller.ownerSaid { return true }
        return entry.session != nil && entry.session == caller.session && entry.task == nil
    }

    /// `id`: undo_entry's entry; else undo_last's `count` (1 when nil).
    static func decide(id: String?, count: Int?, state: ArisRecordState, caller: ArisUndoCaller, context: ArisTrustPolicy.Context) -> Verdict {
        let since = context.now.addingTimeInterval(-recentWindow)
        var chosen: [ArisRecordEntry]
        var older = false
        if let id {
            guard let entry = state.calls.first(where: { $0.id == id.lowercased() }) else { return refuse("그런 기록이 없어요.") }
            guard !state.isUndone(entry.id) else { return refuse("이미 되돌렸어요.") }
            guard entry.ok == true, entry.undo != nil else { return refuse("그건 되돌릴 수 없어요.") }
            guard reaches(entry, caller: caller) else {
                return refuse(caller.task != nil ? "작업은 자기가 한 일만 되돌릴 수 있어요." : "다른 대화에서 한 일은 직접 말씀하셔야 되돌릴 수 있어요.")
            }
            if entry.at < since {
                // An older entry: only when the owner named it, and he hears what it is first.
                guard caller.ownerSaid, caller.task == nil else { return refuse("오래된 일은 직접 말씀하셔야 되돌릴 수 있어요.") }
                older = true
            }
            chosen = [entry]
        } else {
            chosen = Array(state.undoable.filter { $0.at >= since && reaches($0, caller: caller) }.prefix(min(max(count ?? 1, 1), mostAtOnce)))
            guard !chosen.isEmpty else { return refuse("되돌릴 게 없어요.") }
        }
        let strongest = ArisEffectClass.strongest([.changeReversible] + chosen.compactMap { $0.undo.map(effect(of:)) })
        let facts = ArisCallFacts(capability: "record.undo", arguments: chosen.flatMap { entry in
            (entry.undo?.paths ?? []).map { ArisKeyArgument(kind: .path, value: $0) }
        })
        var decision = ArisTrustPolicy.decide(facts, effect: strongest, provenance: caller.provenance, speaker: caller.speaker, context: context)
        if older, !decision.waitsForOwner, !isRefusal(decision) { decision = .readBackThenAsk }
        if caller.approved, decision.waitsForOwner { decision = .runWithUndo(announce: false) }
        let line = chosen.map(summary).joined(separator: ", ")
        return Verdict(ids: chosen.map(\.id), decision: decision, line: "되돌리기: " + line)
    }

    static func summary(_ entry: ArisRecordEntry) -> String {
        let target = (entry.arguments ?? []).first { [.recipient, .path, .app, .url].contains($0.kind) }
            .map { $0.kind == .path ? ($0.value as NSString).lastPathComponent : $0.value }
        return [entry.capability, target].compactMap { $0 }.joined(separator: " · ")
    }

    private static func isRefusal(_ decision: ArisDecision) -> Bool {
        if case .refuse = decision { return true }
        return false
    }

    private static func refuse(_ reason: String) -> Verdict { Verdict(ids: [], decision: .refuse(reason: reason), line: reason) }
}
