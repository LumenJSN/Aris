//
//  ArisAPIGate.swift
//  aris-agent
//
//  The risk gate for an API brain's aris-tools calls: the Codex approve path (ArisCodexDriver.approve) for a command,
//  decided by Aris's own code before anything runs, with the same rules in the same order (cleanroom spec 14, §3.5):
//  ArisRiskPolicy, a careful turn's read judge, R1 = B coverage under the screen, a confirm after outside text for what
//  could carry it out, a remembered yes only while clean, the hands-free rules, a no for the rest of the turn, the user's
//  changed card never run twice. Its state is this conversation's (taint, yeses) and this turn's (a no, ②A duplicates).
//  The parity tests put the same commands to it and to the Codex driver and expect the same answer.
//

import Foundation

enum ArisAPIGateDecision {
    /// Run it now; the audit line.
    case allow(audit: String)
    /// Don't; the audit line and why (for the model).
    case deny(audit: String, reason: String)
    /// A read on a careful turn: the read judge decides (approveOnce or refuseRead), never a card.
    case read(ArisConfirmation, ArisPendingAction, audit: String)
    /// The user's card (or their dictated message's countdown); `remember`: a yes is kept under this key.
    case ask(ArisConfirmation, ArisPendingAction, remember: String?, audit: String)
}

final class ArisAPIGate {
    let tools: String
    let home: String
    /// A background job's gate: careful from its first read.
    let task: Bool

    private(set) var untrustedAt: Date?
    private(set) var screenSeenAt: Date?
    private var approved: [String: Date] = [:]
    private(set) var declinedThisTurn = false
    private var sentForUser: Set<[String]> = []
    private var asked = 0
    /// The user's own words for the gates (ArisMemoryText.ownWords); `attached` keeps the files note for `opensAttachment`.
    var request: String {
        get { ArisMemoryText.ownWords(attached) }
        set { attached = newValue }
    }
    private(set) var attached = ""
    var handsFree = false
    var tier = ArisTier.quick

    /// Keys of the yeses waiting for an answer (by confirmation id).
    private var keys: [String: String] = [:]

    init(tools: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path, task: Bool = false) {
        self.tools = tools
        self.home = home
        self.task = task
    }

    var taint: ArisTaint {
        if untrustedAt != nil || !appsRead.isEmpty { return .outsideText }
        return screenSeenAt != nil ? .screenSeen : .none
    }

    /// The apps whose own windows `aris-tools desktop` read in this conversation (bundle ids).
    private var appsRead: Set<String> = []

    func markAppRead(_ app: String) { appsRead.insert(app) }

    /// The taint as computer use in `app` sees it: its own window isn't outside text for it.
    func taint(forApp app: String) -> ArisTaint {
        if untrustedAt != nil || !appsRead.subtracting([app]).isEmpty { return .outsideText }
        return screenSeenAt != nil ? .screenSeen : .none
    }

    private var careful: Bool { taint != .none || handsFree || task }

    func markUntrusted() { if untrustedAt == nil { untrustedAt = Date() } }
    func markScreenSeen() { if screenSeenAt == nil { screenSeenAt = Date() } }

    /// A new turn: a no and the user's changed cards counted for the last one only.
    func startTurn() {
        declinedThisTurn = false
        sentForUser = []
    }

    /// A new conversation: nothing of the old one counts.
    func reset() {
        untrustedAt = nil
        screenSeenAt = nil
        appsRead = []
        approved = [:]
        keys = [:]
        declinedThisTurn = false
        sentForUser = []
    }

    /// The read the judge checks for `command` on a careful turn (as Codex's readCall for a shell action).
    func readCall(_ command: String) -> ArisReadCall? {
        guard let pieces = ArisCommandPolicy.segments(command), pieces.count == 1, let words = ArisCommandPolicy.words(pieces[0]),
              words.first == tools, words.count > 1 else { return nil }
        let rest = Array(words.dropFirst())
        if let web = ArisReadGate.web(rest), web.tool == "web fetch" { return web }
        return ArisReadGate.isJudgedRead(rest) ? ArisReadGate.call(arisTools: rest) : nil
    }

    /// The gate's answer for one command the model asked to run.
    func judge(_ command: String) -> ArisAPIGateDecision {
        let action = ArisAction.shell(command)
        let (title, detail) = ArisCodexDriver.describe(command: command, tools: tools, request: request)
        var risk = ArisRiskPolicy.risk(of: action, tools: tools, home: home, critical: tier == .critical, request: request)
        let assessed = risk
        // Follow-up M1: after outside text or the screen, a maps lookup with words that aren't the user's asks, never judged.
        let carries = taint != .none && ArisRiskPolicy.mapsLookupCarries(action, tools: tools, request: request)
        let judgedRead = careful && assessed == .auto && !carries ? readCall(command) : nil
        let covered = taint == .screenSeen && !handsFree && ArisRiskPolicy.coveredByRequest(action, tools: tools, arguments: [:], request: request)
        let blocked = taint.blocks(covered: covered)
        if risk == .auto || risk == .countdown, blocked, judgedRead == nil, ArisRiskPolicy.asksAfterOutsideText(action, tools: tools) { risk = .confirm }
        if carries, risk == .auto { risk = .confirm }
        if risk == .auto, ArisRiskPolicy.opensAttachment(action, tools: tools, request: attached) { risk = .confirm }
        // A conversion after outside text or the screen: refused, never carded (as Codex and the open Claude).
        var neverWhy = assessed == .never ? ArisRiskPolicy.neverReason(action, tools: tools, home: home, critical: tier == .critical, request: request) : nil
        func refuse(_ why: String) { if risk != .never || neverWhy == nil { neverWhy = why }; risk = .never }
        if taint != .none, ArisRiskPolicy.refusedAfterOutsideText(action, tools: tools) { refuse("a conversion after outside text came in") }
        if risk != .never, ArisRiskPolicy.bringsInUntrusted(action, tools: tools, home: home) { markUntrusted() }
        let anyKey = ArisRiskPolicy.isRepeatable(action, tools: tools) ? ArisCodexDriver.rememberKey(action, cwd: "api") : nil
        let key = blocked || handsFree ? nil : anyKey
        let remembered = anyKey.flatMap { approved[$0] }.map { Date().timeIntervalSince($0) < ArisCodexDriver.approvalMemory } ?? false
        if risk == .confirm, key != nil, remembered { risk = .auto }
        let blockedByTaint = risk == .confirm && blocked && remembered
        if handsFree, judgedRead == nil { risk = ArisHandsFree.risk(risk, of: action, tools: tools) }
        if handsFree, ArisCodexDriver.readsMemory(action, tools: tools) { refuse("the user's memories are never read on a hands-free turn") }
        if declinedThisTurn && (risk == .confirm || risk == .countdown) { refuse("the user already said no to a card this turn; nothing else that asks runs after it") }
        if !sentForUser.isEmpty, let again = ArisEditableAction.parse(action, tools: tools), sentForUser.contains(again.arguments) { refuse("the user's changed card already did this") }
        if risk != .never { neverWhy = nil }
        let audit = ArisCodexDriver.auditLine(action, risk: risk, raw: command, why: neverWhy)
        if risk == .auto, let judgedRead, !(handsFree && ArisCodexDriver.readsMemory(action, tools: tools)) {
            asked += 1
            let ask = ArisConfirmation(id: ArisLaunch.confirmId(asked), title: "읽기 확인", detail: judgedRead.tool)
            return .read(ask, ArisPendingAction(action: action, arguments: [:], connector: "", read: judgedRead), audit: audit)
        }
        switch risk {
        case .auto:
            return .allow(audit: audit)
        case .never:
            return .deny(audit: audit, reason: handsFree ? ArisHandsFree.askAgainLine
                         : ArisRiskPolicy.callProblem(command, tools: tools) ?? "Refused by Aris's safety rules (\(neverWhy ?? "the never-list")); don't try another way.")
        case .confirm, .countdown:
            asked += 1
            let reason = blockedByTaint ? ArisEscalation.taintedReason + "\n" : ""
            let dictated = risk == .countdown ? ArisCodexDriver.dictatedMessage(in: action, tools: tools, request: request) : nil
            let ask = dictated.map { ArisConfirmation(id: ArisLaunch.confirmId(asked), title: $0.to, detail: $0.text, countdown: true,
                                                      spoken: ArisRiskPolicy.announcement(to: $0.to, text: $0.text)) }
                ?? ArisConfirmation(id: ArisLaunch.confirmId(asked), title: title, detail: reason + detail,
                                    memoryWrite: ArisMemoryLearning.isMemoryWrite(action, tools: tools))
            if let key { keys[ask.id] = key }
            return .ask(ask, ArisPendingAction(action: action, arguments: [:], connector: "", covered: covered), remember: key, audit: audit)
        }
    }

    /// The user's answer to a card: a yes is remembered (only while it could be), a no closes the rest of the turn.
    func answered(_ id: String, allow: Bool) {
        let key = keys.removeValue(forKey: id)
        if allow, taint != .outsideText, let key { approved[key] = Date() }
        if !allow { declinedThisTurn = true }
    }

    /// A yes from the escalation gate or the read judge: this call only, never remembered.
    func approvedOnce(_ id: String) { keys[id] = nil }

    /// The owner's ②A: the agent ran their changed card itself; the same action again this turn is never run.
    func sentEdited(_ action: ArisAction?, arguments: [String]) {
        if let action, let asked = ArisEditableAction.parse(action, tools: tools) { sentForUser.insert(asked.arguments) }
        sentForUser.insert(arguments)
    }
}
