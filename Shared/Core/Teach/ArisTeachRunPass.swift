//
//  ArisTeachRunPass.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  One card for a taught procedure's run (jv-quick, the owner's decision of 2026-11-19: a replay asked on a card per
//  step, and he wants "do it" to be done). When he asks to run saved steps, Aris asks once, up front, on a card that
//  lists every step as it will be done; their yes there is a pass for exactly that plan, and nothing else:
//  - bound to the plan shown: every step's call (its place, its id, its tool, its arguments) is kept as it was when the
//    card was made, and a step runs on the pass only when its call at the run is exactly that one;
//  - used a step at a time, in order, each step once (the settled rule: a pass is valid for one call under the content
//    its decision saw);
//  - void the moment a step's call differs from the plan, a step comes out of order, a step fails, the run is stopped,
//    or a new turn starts; a void pass lets nothing run, and every step left asks on its own card as before;
//  - it only ever stands in for a plain ask of a step that is on the list below AND that the gate rated, at the run, no
//    higher than a change with its undo, with no provenance warning, no payment, no browser page, nothing erased and
//    nothing sent. Anything else keeps its own card at the moment it runs: a replace (its card shows what is erased,
//    read then), a send, a delete, a payment, a read-back, a countdown. A refusal stays a refusal.
//  The list is an allowlist (`ArisTeachCover.kinds`), and a miss is never less strict than a hit: a kind not on it, a
//  step whose words name a risk, a step nothing was judged for, all ask. Pure.
//

import Foundation

/// Whether the one card may cover a step, as far as the step itself tells (the run's own judgement comes on top).
enum ArisTeachCover {
    enum Why: Equatable, Sendable {
        case covered
        /// Its kind isn't on the list (keys: Return sends, Delete deletes, and what they do depends on where they land).
        case kind
        /// It replaces what a field holds.
        case replaces
        /// It carries a value recorded when he showed it (the app's content), not their words for this run.
        case recordedValue
        /// Its own words (a label, a menu path, an option) send, submit, delete, pay, overwrite or run something.
        case namesRisk
        /// It acts in a browser, where every act asks on its own card (decision 2).
        case browser
        /// It types after a step of the same app that may have selected text: typing over a selection erases it.
        case mayTypeOver
    }

    /// The step kinds the one card may cover. Anything not here asks.
    static let kinds: Set<ArisTeachStep.Action> = [.open, .menu, .click, .select, .type]

    /// The app layer's concepts (ArisApps.Lexicon) that are never covered.
    /// Cut and paste go over the selection, undo and redo take text away or put it back: content changes with no card.
    static let riskConcepts: Set<String> = ["send", "call", "delete", "run", "replace", "share", "forward", "cut", "paste", "undo", "redo"]
    /// Words that are never covered, whole words of the step's own text, folded (the lexicon may not know them all).
    static let riskWords: Set<String> = ["send", "submit", "post", "publish", "share", "delete", "remove", "erase", "trash", "empty", "discard", "revert",
                                         "overwrite", "replace", "cut", "paste", "clear", "undo", "redo", "pay", "buy", "purchase", "order", "checkout", "run", "execute",
                                         "보내기", "보내", "전송", "제출", "게시", "공유", "삭제", "지우기", "지워", "제거", "휴지통", "비우기", "덮어쓰기",
                                         "바꾸기", "오려두기", "잘라내기", "붙여넣기", "결제", "구매", "주문", "실행"]

    /// The step kinds known to leave the selection of their app as it was: opening the app, and text put in (it leaves
    /// a caret). After any other step of the same app (Select All, any menu command, a click, a choice), typing may go
    /// over a selection and erase it, so that typing is never the one card's: it is decided when it runs, from the
    /// selection read then (ArisTrustGate), and asks on its own card that shows what is erased.
    static let keepsSelection: Set<ArisTeachStep.Action> = [.open, .type]

    /// Whether the one card may cover the step at `index` of `steps`: the step's own answer (`why(_:ownerGave:)`), and
    /// for typing, that no step of its app before it may have changed the selection.
    static func why(at index: Int, in steps: [ArisTeachStep], ownerGave: Set<String>) -> Why {
        let step = steps[index]
        let own = why(step, ownerGave: ownerGave)
        guard own == .covered, step.action == .type else { return own }
        let selects = steps[..<index].contains { $0.bundle == step.bundle && (!keepsSelection.contains($0.action) || $0.replaces) }
        return selects ? .mayTypeOver : .covered
    }

    /// As far as the step alone tells (typing also depends on the steps before it: `why(at:in:ownerGave:)`).
    static func why(_ step: ArisTeachStep, ownerGave: Set<String>) -> Why {
        guard kinds.contains(step.action) else { return .kind }
        if ArisBrowserActs.bundles.contains(step.bundle.lowercased()) || ArisBrowserActs.names.contains(ArisGrounding.fold(step.app)) { return .browser }
        if step.replaces { return .replaces }
        if namesRisk(step) { return .namesRisk }
        if step.action != .open, step.carriesRecordedValue(ownerGave: ownerGave) { return .recordedValue }
        return .covered
    }

    /// Whether the step's own words (never the text it types, which is the owner's for a covered step) name a risk.
    static func namesRisk(_ step: ArisTeachStep) -> Bool {
        let texts = ([step.label, step.target, step.option].compactMap { $0 } + (step.menu ?? [])).filter { !$0.isEmpty }
        return texts.contains { text in
            if ArisPaymentSteps.names(text) { return true }
            if !riskConcepts.isDisjoint(with: ArisApps.Lexicon.units(text).flatMap(ArisApps.Lexicon.meanings)) { return true }
            return !riskWords.isDisjoint(with: ArisApps.Lexicon.pieces(text))
        }
    }
}

/// The owner's yes on the run's one card, as a pass for exactly the plan the card showed.
struct ArisTeachRunPass: Equatable, Sendable {
    /// Why the pass no longer lets anything run.
    enum Void: Equatable, Sendable {
        /// The call of the step at `at` (from 0) isn't the plan's.
        case differs(at: Int)
        /// A step came that isn't the next one (one skipped, or one taken twice).
        case outOfOrder(at: Int)
        /// The step at `at` ran and failed.
        case failed(at: Int)
        /// The run was stopped (his stop, a newer request).
        case stopped
        /// A new turn started.
        case newTurn
    }

    /// What the gate decided about a step's call at the run.
    struct Judged: Equatable, Sendable {
        var effect: ArisEffectClass
        /// The decision is a plain ask (not a read-back, a countdown or a refusal).
        var asks: Bool
        /// Content Aris read is why the call is made (the card would say "읽은 내용이 제안한 일이에요").
        var content = false
        var payment = false
        /// It acts on a browser's page.
        var browser = false
        /// It erases a field's text.
        var erases = false
        /// It was rated a send of something private.
        var sends = false

        /// Whether the pass may stand in for this step's card: a plain ask of nothing higher than a change with its undo.
        var coverable: Bool {
            asks && (effect == .observe || effect == .changeReversible) && !content && !payment && !browser && !erases && !sends
        }
    }

    /// How the one card marks a step.
    enum Mark: Equatable, Sendable {
        /// It runs with no card today, and so it does now.
        case runs
        /// It would ask, and the one card's yes covers it.
        case covered
        /// It asks on its own card at the moment it runs.
        case asksAgain

        /// `covered`: the step is on the card's list (ArisTeachCover); `waits`: the policy would wait for the owner;
        /// `judged`: what it would decide, when known.
        static func of(covered: Bool, waits: Bool, judged: Judged?) -> Mark {
            guard waits else { return .runs }
            return covered && judged?.coverable == true ? .covered : .asksAgain
        }
    }

    /// The one card is asked only when it stands in for at least one step's own card; else the run is as it was.
    static func asksOnce(_ marks: [Mark]) -> Bool { marks.contains(.covered) }

    /// Each step's call as the plan has it, in order (`print`).
    let steps: [String]
    /// Whether each step is on the card's list.
    let covered: [Bool]
    /// The plan's fingerprint: every step's call, in order (for the log; what is compared is each step's own print).
    let hash: String
    /// The step that may come next (from 0).
    private(set) var next = 0
    private(set) var void: Void?

    init(plan: ArisTeachReplay.Plan) {
        steps = plan.calls.enumerated().map { Self.print($0.offset, $0.element) }
        covered = plan.calls.indices.map { index in
            plan.calls[index] != nil && index < plan.steps.count && ArisTeachCover.why(at: index, in: plan.steps, ownerGave: plan.ownerGave) == .covered
        }
        hash = Self.digest(steps.joined(separator: "\u{1E}"))
    }

    /// One step's call written out whole: its place, its id, its tool, and its arguments with their keys in order.
    static func print(_ index: Int, _ call: ArisMindToolCall?) -> String {
        guard let call else { return "\(index)\u{1F}-" }
        let arguments = call.object.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? call.arguments
        return [String(index), call.id, call.name, arguments].joined(separator: "\u{1F}")
    }

    /// FNV-1a over the text's bytes, as hex.
    static func digest(_ text: String) -> String {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        return String(value, radix: 16)
    }

    /// The step at `index` comes up with `call`: the pass after it, and whether the step runs on it in place of its own
    /// card. `judged`: what the gate decided about the call (nil: unknown, or it didn't wait).
    func taking(_ index: Int, _ call: ArisMindToolCall?, judged: Judged?) -> (pass: ArisTeachRunPass, runs: Bool) {
        guard void == nil else { return (self, false) }
        guard index == next else { return (voided(.outOfOrder(at: index)), false) }
        guard steps.indices.contains(index), call != nil, Self.print(index, call) == steps[index] else { return (voided(.differs(at: index)), false) }
        var after = self
        after.next = index + 1
        return (after, covered[index] && judged?.coverable == true)
    }

    /// The pass made void (the first reason stays).
    func voided(_ why: Void) -> ArisTeachRunPass {
        guard void == nil else { return self }
        var gone = self
        gone.void = why
        return gone
    }
}

/// A run's pass, as the run's steps take it one after another.
final class ArisTeachPassBox: @unchecked Sendable {
    private let lock = NSLock()
    private var held: ArisTeachRunPass

    init(_ pass: ArisTeachRunPass) { held = pass }

    var pass: ArisTeachRunPass { lock.withLock { held } }

    func take(_ index: Int, _ call: ArisMindToolCall?, judged: ArisTeachRunPass.Judged?) -> Bool {
        lock.withLock {
            let taken = held.taking(index, call, judged: judged)
            held = taken.pass
            return taken.runs
        }
    }

    func void(_ why: ArisTeachRunPass.Void) { lock.withLock { held = held.voided(why) } }
}

extension ArisTeachReplay {
    /// The owner's yes on the run's one card, for the run: its pass, what the gate judged about a call (by its id), and
    /// where a step that ran on the pass is told (the record).
    struct Approval: @unchecked Sendable {
        let box: ArisTeachPassBox
        var judged: (String) -> ArisTeachRunPass.Judged?
        var used: (String) -> Void = { _ in }
    }

    /// The step's ports with the pass in front of the ask: every step's call is taken against the plan (so the pass moves
    /// with the run, or goes void), and a step that waits and is covered runs with its undo, with no card of its own.
    static func passing(_ ports: ArisMindPorts, plan: Plan, approval: Approval?) -> ArisMindPorts {
        guard let approval else { return ports }
        var passed = ports
        passed.decide = { calls in
            ports.decide(calls).map { item in
                guard let index = plan.calls.firstIndex(where: { $0?.id == item.call.id }) else {
                    approval.box.void(.differs(at: plan.calls.count))
                    return item
                }
                let runs = approval.box.take(index, item.call, judged: item.verdict == .waits ? approval.judged(item.call.id) : nil)
                guard runs, item.verdict == .waits else { return item }
                approval.used(item.call.id)
                return ArisMindDecided(call: item.call, verdict: .run(undo: true, announce: false))
            }
        }
        return passed
    }
}
