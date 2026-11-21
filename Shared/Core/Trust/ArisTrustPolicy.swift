//
//  ArisTrustPolicy.swift
//  Shared/Core (aris-agent, tests)
//
//  The one function that decides every capability call when `arisCore2` is on (ARCHITECTURE Part 2, Judgment):
//  decide(call, effect, provenance, grants, level) -> run | run with undo | say then run | read back then ask | ask |
//  refuse. In order: the fixed never-list; the table's cell for (level, effect, provenance); a matching standing
//  grant lifts an asking cell (not at the careful level, never for content); then the one hard rule once more, so no
//  table can break it: content never causes an outward action, nor a permanent one without the owner's yes.
//  A payment the capability registry marks (decision 1, 2026-11-18) is decided after every other rule: a refusal
//  stays a refusal, and anything else asks on its own card, at every level, whatever a grant says, never on a
//  countdown; the never-list's payment rule no longer refuses it; one content suggested is refused (the hard rule).
//  Last, the speaker (F1): words whose voice was not the owner's count like content for what they may cause, so an
//  outward or permanent act they ask for waits for the owner (read back, or asked), whatever the cell or a grant says.
//  With no voice print every turn is the owner's (ArisTurnSpeaker.notChecked) and nothing here changes. Pure.
//

import Foundation

enum ArisTrustPolicy {
    /// What the policy needs to know about a call beyond its facts.
    struct Context: Sendable {
        var level: ArisTrustLevel = .standard
        var grants: [ArisStandingGrant] = []
        var table: ArisTrustTable = .standard
        var home: String
        var now: Date = Date()

        init(level: ArisTrustLevel = .standard, grants: [ArisStandingGrant] = [], table: ArisTrustTable = .standard, home: String, now: Date = Date()) {
            self.level = level
            self.grants = grants
            self.table = table
            self.home = home
            self.now = now
        }
    }

    /// `specified`: the owner named the recipient and the content (an outward call's "fully specified").
    /// `ownerNamed`: the key-argument kinds the owner's words gave (the never-list's payment rule).
    static func decide(_ call: ArisCallFacts, effect: ArisEffectClass, provenance: ArisCallProvenance, specified: Bool = false,
                       ownerNamed: Set<ArisKeyArgument.Kind> = [], speaker: ArisTurnSpeaker = .notChecked, context: Context) -> ArisDecision {
        let decided = voiceChecked(decideForOwner(call, effect: effect, provenance: provenance, specified: specified, ownerNamed: ownerNamed, context: context),
                                   effect: effect, speaker: speaker)
        // An act in a browser (decision 2), then a payment (decision 1): each after every other rule, each only stricter.
        let browsed = ArisBrowserActs.decide(decided, call: call, provenance: provenance)
        // What content may drive (input into an app, an address it gave), and a replace that couldn't read what it
        // erases: each only stricter (tenth VM run, items 4, 8 and 9).
        let reached = ArisContentReach.unreadErase(ArisContentReach.decide(browsed, call: call, provenance: provenance), call: call)
        return call.registeredPayment ? payment(reached, call: call, provenance: provenance) : reached
    }

    /// An unverified voice never makes an outward or permanent act happen on its own: one that would run (or run after a
    /// spoken moment) waits for the owner instead. A refusal or a question stays as it is.
    static func voiceChecked(_ decision: ArisDecision, effect: ArisEffectClass, speaker: ArisTurnSpeaker) -> ArisDecision {
        guard !speaker.countsAsOwner, effect == .outward || effect == .changePermanent else { return decision }
        switch decision {
        case .run, .runWithUndo, .sayThenRun: return effect == .outward ? .readBackThenAsk : .ask
        case .readBackThenAsk, .ask, .refuse: return decision
        }
    }

    private static func decideForOwner(_ call: ArisCallFacts, effect: ArisEffectClass, provenance: ArisCallProvenance, specified: Bool,
                                       ownerNamed: Set<ArisKeyArgument.Kind>, context: Context) -> ArisDecision {
        if let rule = ArisNeverList.rule(for: call, effect: effect, home: context.home, ownerNamed: ownerNamed) {
            // Decision 1: a payment the registry marks is no longer refused for being a payment (it asks on its card,
            // `payment` below); every other rule of the never-list still refuses it.
            let paymentOnly = rule == .unnamedPayment && call.registeredPayment
                && ArisNeverList.rule(for: call, effect: effect, home: context.home, ownerNamed: [.amount, .payee]) == nil
            if !paymentOnly { return .refuse(reason: rule.korean) }
        }
        // A command's reach, read fail-closed: on the never-list it is refused; uncertain, it never runs on its own.
        var uncertain: String?
        for command in call.values(.command) {
            switch ArisNeverList.shellReach(command, home: context.home, cwd: call.cwd) {
            case .never(let rule): return .refuse(reason: rule.korean)
            case .uncertain(let why): uncertain = uncertain ?? why
            case .clear: break
            }
        }
        let column = provenance.column
        var cell = context.table.cell(context.level, effect, column)
        if column != .content, !context.table.grantsIgnoredAt.contains(context.level), context.table.grantLifts.contains(cell),
           context.grants.contains(where: { $0.covers(call, effect: effect, home: context.home, now: context.now) }) {
            cell = context.table.grantBecomes
        }
        if column == .content, !ArisTrustTable.allowed(cell, effect: effect, column: column) {
            cell = effect == .changePermanent ? .ask : .refuse
        }
        let decided = decision(cell, effect: effect, specified: specified, provenance: provenance, delay: context.table.sayDelay)
        if uncertain != nil {
            switch decided {
            case .run, .runWithUndo, .sayThenRun: return .ask
            case .readBackThenAsk, .ask, .refuse: return decided
            }
        }
        return decided
    }

    /// A payment the registry marks (decision 1), after every other rule: a refusal stays a refusal; anything else
    /// becomes a card every time (`.ask`, which the ask plan puts on a card of its own, never covered by an earlier yes,
    /// never a grant, never a countdown, never run on silence), so the owner's explicit yes on it is the only way it
    /// runs. Refused when content suggested it (as every outward act), and when the card couldn't show exactly what
    /// happens: more than one amount or payee, or one too long to show in full.
    static func payment(_ decided: ArisDecision, call: ArisCallFacts, provenance: ArisCallProvenance) -> ArisDecision {
        if case .refuse = decided { return decided }
        if provenance.source != nil { return .refuse(reason: refusal(effect: .outward, provenance: provenance)) }
        if let why = unreadablePayment(call) { return .refuse(reason: why) }
        return .ask
    }

    static let paymentAmountLimit = 40
    static let paymentPayeeLimit = 120

    /// Why a payment's card couldn't show exactly what is paid; nil when it can.
    static func unreadablePayment(_ call: ArisCallFacts) -> String? {
        let distinct = { (values: [String]) in Set(values.map { ArisGrounding.fold($0) }.filter { !$0.isEmpty }) }
        let amounts = distinct(call.values(.amount)), payees = distinct(call.values(.payee) + call.values(.recipient))
        if amounts.count > 1 { return "금액이 여러 개라 무엇을 결제하는지 카드에 정확히 보여 드릴 수 없어서 하지 않았어요. (The payment has more than one amount.)" }
        if payees.count > 1 { return "받는 곳이 여러 곳이라 카드에 정확히 보여 드릴 수 없어서 하지 않았어요. (The payment has more than one payee.)" }
        if amounts.contains(where: { $0.count > paymentAmountLimit }) || payees.contains(where: { $0.count > paymentPayeeLimit }) {
            return "금액이나 받는 곳이 너무 길어 카드에 다 보여 드릴 수 없어서 하지 않았어요. (The amount or payee is too long to show in full.)"
        }
        return nil
    }

    static func decision(_ cell: ArisTrustCell, effect: ArisEffectClass, specified: Bool, provenance: ArisCallProvenance, delay: TimeInterval) -> ArisDecision {
        switch cell {
        case .run: return effect == .changeReversible ? .runWithUndo(announce: false) : .run
        case .runWithUndo: return .runWithUndo(announce: false)
        case .runWithUndoSaid: return .runWithUndo(announce: true)
        case .sayThenRun: return .sayThenRun(delay: delay)
        case .sendIfSpecified: return specified ? .sayThenRun(delay: delay) : .readBackThenAsk
        case .runIfSpecified: return specified ? .run : .readBackThenAsk
        case .readBackThenAsk: return .readBackThenAsk
        case .ask: return .ask
        case .refuse: return .refuse(reason: refusal(effect: effect, provenance: provenance))
        }
    }

    /// Why a table's refuse refused, for the owner.
    static func refusal(effect: ArisEffectClass, provenance: ArisCallProvenance) -> String {
        if let source = provenance.source {
            return "읽은 내용(\(source.spoken))이 시킨 일이라 하지 않았어요. 원하시면 직접 말씀해 주세요."
        }
        return "이건 지금 설정으로는 하지 않아요."
    }
}

// MARK: - Grants

extension ArisStandingGrant {
    /// Whether this grant covers the call: its capability (exact, or a family "mail.*"), its effect, its target (every
    /// target of that kind in the call must fall under it, and the call must have one), and its time.
    func covers(_ call: ArisCallFacts, effect: ArisEffectClass, home: String, now: Date) -> Bool {
        guard isWellFormed, isSafe(home: home), effect != .never else { return false }
        if let expires, now >= expires { return false }
        if let capability {
            if capability.hasSuffix(".*") {
                guard call.capability.hasPrefix(String(capability.dropLast())) else { return false }
            } else if capability != call.capability {
                return false
            }
        }
        if let wanted = self.effect, wanted != effect { return false }
        guard let target else { return true }
        let values = call.values(target.kind)
        guard !values.isEmpty else { return false }
        return values.allSatisfy { target.matches($0, home: home) }
    }
}

extension ArisStandingGrant {
    /// A grant whose scope is a whole root, the home folder (or above it), a volume, a system folder, or Aris's own or
    /// a credential place never exists: it isn't made, isn't kept, and covers nothing.
    func isSafe(home: String) -> Bool {
        guard let target else { return true }
        switch target.kind {
        case .path:
            let path = ArisNeverList.normalized(target.pattern, home: home), folded = ArisNeverList.normalized(home, home: home)
            if path == "/" || path == folded || folded.hasPrefix(path + "/") { return false }
            if path == "/volumes" || (path.hasPrefix("/volumes/") && path.split(separator: "/").count <= 2) { return false }
            let system = ["/system", "/library", "/usr", "/bin", "/sbin", "/etc", "/private", "/var", "/applications", "/opt", "/cores", "/users"]
            if system.contains(where: { path == $0 || (path.hasPrefix($0 + "/") && !path.hasPrefix("/usr/local/")) }) && !path.hasPrefix(folded + "/") { return false }
            if ArisNeverList.pathRule(target.pattern, effect: .observe, home: home) != nil { return false }
            if path == folded + "/library" { return false }
            return true
        case .recipient, .payee, .app, .url:
            return ArisNeverList.appRule(target.pattern) == nil
        case .command, .body, .amount:
            return false
        }
    }
}

extension ArisStandingGrant.Target {
    func matches(_ value: String, home: String) -> Bool {
        let fold = { (text: String) in text.precomposedStringWithCompatibilityMapping.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        switch kind {
        case .path:
            let folder = ArisNeverList.normalized(pattern, home: home), path = ArisNeverList.normalized(value, home: home)
            return path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
        case .url:
            let host = { (text: String) in URL(string: text)?.host?.lowercased() ?? fold(text) }
            return host(value) == host(pattern)
        case .recipient, .payee:
            let wanted = fold(value)
            return wanted == fold(pattern) || addresses.map(fold).contains(wanted)
        case .app, .command, .body, .amount:
            return fold(value) == fold(pattern)
        }
    }
}
