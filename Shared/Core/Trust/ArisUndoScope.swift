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
    /// The kind of change the owner's words of the turn name ("이름 바꾼 거 되돌려"), read by the gate from their words,
    /// never from the model's (thirteenth VM run, item 1); nil: none named, the newest is meant.
    var named: ArisUndoKind?
    /// The entries the card he said yes to named: with `approved`, exactly those are undone, or none.
    var planned: [String]?

    init(session: String?, task: String? = nil, provenance: ArisCallProvenance, approved: Bool = false, speaker: ArisTurnSpeaker = .notChecked,
         named: ArisUndoKind? = nil, planned: [String]? = nil) {
        self.session = session
        self.task = task
        self.provenance = provenance
        self.approved = approved
        self.speaker = speaker
        self.named = named
        self.planned = planned
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

    /// The capabilities whose aris-tools run keeps its own undo in the activity log (the record's entry names those lines,
    /// `logged`): taken back there, by those lines (an allowlist; anything else needs a recipe of the record's own).
    static let loggedUndoable: Set<String> = ["aris.file_rename", "aris.file_trash", "aris.file_move"]

    /// Whether an entry can be undone: its own recipe, or its activity log lines for a capability of `loggedUndoable`.
    static func canUndo(_ entry: ArisRecordEntry) -> Bool {
        guard entry.ok == true else { return false }
        return entry.undo != nil || (loggedUndoable.contains(entry.capability ?? "") && !(entry.logged ?? []).isEmpty)
    }

    /// The entries an undo may take, newest first: not undone in the record, nor through the activity log (`loggedUndone`).
    static func candidates(_ state: ArisRecordState, loggedUndone: Set<String>) -> [ArisRecordEntry] {
        state.calls.filter { canUndo($0) && !state.isUndone($0, loggedUndone: loggedUndone) }.sorted { $0.at > $1.at }
    }

    /// The effect undoing an entry has: its recipe's, or a file put back where it was (its log lines).
    static func undoEffect(_ entry: ArisRecordEntry) -> ArisEffectClass { entry.undo.map(effect(of:)) ?? .changeReversible }

    /// The paths an undo touches, for the decision: its recipe's, or the call's own paths.
    static func undoPaths(_ entry: ArisRecordEntry) -> [String] {
        entry.undo?.paths ?? (entry.arguments ?? []).filter { $0.kind == .path }.map(\.value)
    }

    /// Whether the caller may reach this entry at all (before the time window).
    static func reaches(_ entry: ArisRecordEntry, caller: ArisUndoCaller) -> Bool {
        if let task = caller.task { return entry.task == task }
        if caller.ownerSaid { return true }
        return entry.session != nil && entry.session == caller.session && entry.task == nil
    }

    /// `id`: undo_entry's entry; else undo_last's `count` (1 when nil). `loggedUndone`: the activity log's undone ids.
    /// undo_last takes the newest change, or, when their words name a kind (`caller.named`), the newest of that kind; it
    /// never takes another kind silently: with none of that kind it says so and offers the newest on a card, and an
    /// entry older than the newest is taken only on a card that names it (thirteenth VM run, item 1).
    static func decide(id: String?, count: Int?, state: ArisRecordState, caller: ArisUndoCaller, context: ArisTrustPolicy.Context,
                       loggedUndone: Set<String> = []) -> Verdict {
        let since = context.now.addingTimeInterval(-recentWindow)
        var chosen: [ArisRecordEntry]
        var older = false
        var named: String?
        if let id {
            guard let entry = state.calls.first(where: { $0.id == id.lowercased() }) else { return refuse("그런 기록이 없어요.") }
            guard !state.isUndone(entry, loggedUndone: loggedUndone) else { return refuse("이미 되돌렸어요.") }
            guard canUndo(entry) else { return refuse("그건 되돌릴 수 없어요.") }
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
            let pool = candidates(state, loggedUndone: loggedUndone).filter { $0.at >= since && reaches($0, caller: caller) }
            guard let newest = pool.first else {
                return refuse(caller.named.map { "최근에 한 일 중 되돌릴 \($0.korean)이 없어요." } ?? "되돌릴 게 없어요.")
            }
            if caller.approved, let planned = caller.planned {
                // His yes was for exactly the entries its card named: those, or nothing (the record changed since).
                chosen = planned.compactMap { id in pool.first { $0.id == id } }
                guard !planned.isEmpty, chosen.count == planned.count else { return refuse("카드를 띄운 뒤 기록이 바뀌어서 되돌리지 않았어요.") }
                older = chosen.contains { $0.id != newest.id }
            } else if let kind = caller.named {
                if let match = pool.first(where: { ArisUndoKind.of($0) == kind }) {
                    chosen = [match]
                    older = match.id != newest.id
                } else {
                    // None of what he named: never another kind silently; the newest, offered on a card that says so.
                    chosen = [newest]
                    older = true
                    named = "최근에 \(kind.korean)은 기록에 없어요. 가장 최근에 한 일은 이거예요: "
                }
            } else {
                chosen = Array(pool.prefix(min(max(count ?? 1, 1), mostAtOnce)))
            }
        }
        let strongest = ArisEffectClass.strongest([.changeReversible] + chosen.map(undoEffect))
        let facts = ArisCallFacts(capability: "record.undo", arguments: chosen.flatMap { entry in
            undoPaths(entry).map { ArisKeyArgument(kind: .path, value: $0) }
        })
        var decision = ArisTrustPolicy.decide(facts, effect: strongest, provenance: caller.provenance, speaker: caller.speaker, context: context)
        if older, !isRefusal(decision) {
            // An entry other than the newest (an older one he named, one of the kind he named, or the newest offered in
            // place of what isn't there): asked on a card that names it, every time.
            if !decision.waitsForOwner { decision = id == nil ? .ask : .readBackThenAsk }
        }
        if caller.approved, decision.waitsForOwner { decision = .runWithUndo(announce: false) }
        let line = (named ?? "") + chosen.map(ArisRecordQuery.ownerSummary).joined(separator: ", ")
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

/// An undo call's plan as the gate decided it: the kind their words named and the entries its card named, for its run.
struct ArisUndoPlanned: Equatable, Sendable {
    let named: ArisUndoKind?
    let ids: [String]
}
