//
//  ArisSavedStepsLive.swift
//  aris-agent
//
//  The agent's saved steps: their file (aris/saved-steps.json), and the turn a replay runs as. That turn is no brain's:
//  its cards go up on the /ask stream it answers (like agy's relay turn), a read the judge would have to look at is
//  refused (a replay makes no model call at all), and it holds the desktop lock until the replay ends.
//

import Foundation
import Network

enum ArisSavedStepsLive {
    static let store = ArisSavedStepsStore(file: ArisAgentRunner.directory.appendingPathComponent("saved-steps.json"), signing: ArisAPISecrets.signing) {
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(["answer": $0, "question": "saved steps"]), key: "desktop")
    }

    /// The AI's answer doesn't say it failed (the same words a learned shortcut is held to).
    static func learnable(reply: String) -> Bool { !ArisSavedSteps.replySaysFailed(reply) }
}

/// The turn a saved request is done again as: the user's words, the conversation's taint at its start, no brain.
final class ArisSavedStepsTurn: ArisDesktopTurn {
    let brain: ArisBrain
    let ledger = ArisComputerUseLedger(forget: { ArisPeekabooSnapshots.remove($0, record: ArisPeekabooSnapshots.recordFile) })
    let request: String
    let critical: Bool
    let handsFree = false
    let isTask = false
    let screen: Bool
    let relayed = false
    private let lock = NSLock()
    private var current: ArisTaint
    /// The conversation's own taint, the recipe's aside (for a step its live run did clean: ArisSavedStepsReplay.stepTaint).
    private var conversation: ArisTaint
    private var read: Set<String> = []
    private var cards: Set<String> = []
    private var steps = 0
    private let show: (ArisAgentReply) -> Void
    private let isOpen: () -> Bool

    init(brain: ArisBrain, request: String, critical: Bool, taint: ArisTaint, conversation: ArisTaint, screen: Bool, isOpen: @escaping () -> Bool,
         show: @escaping (ArisAgentReply) -> Void) {
        self.brain = brain
        self.request = request
        self.critical = critical
        self.screen = screen
        current = taint
        self.conversation = conversation
        self.isOpen = isOpen
        self.show = show
    }

    var brainName: String { "saved-steps" }
    var live: Bool { isOpen() }
    var taint: ArisTaint { lock.withLock { read.isEmpty ? current : .outsideText } }
    /// An app's own window isn't outside text for computer use in that app; any other app's is (as the drivers keep it).
    /// The step under way's taint for its app (ArisSavedStepsReplay.stepTaint).
    func taint(forApp app: String) -> ArisTaint {
        let clean = ledger.replayStepClean
        return lock.withLock {
            ArisSavedStepsReplay.stepTaint(learned: current, conversation: conversation, stepClean: clean, readOther: !read.subtracting([app]).isEmpty)
        }
    }
    func markAppRead(_ app: String) { lock.withLock { _ = read.insert(app) } }
    func takeOutsideText() {
        lock.withLock {
            current = .outsideText
            conversation = .outsideText
        }
    }
    func desktopStep() -> Int { lock.withLock { steps += 1; return steps } }
    func operating(_ target: ArisOperatingTarget) { show(.operating(target)) }
    func quiet(_ status: String) { show(.status(status)) }
    /// A replay saves nothing (its steps are saved already).
    func noteDesktopAction(_ note: Result<ArisSavedStep, ArisSavedStepsRefusal>) {}
    /// No model is asked: a read that needs the judge is not done.
    func judgeRead(_ call: ArisReadCall, done: @escaping (ArisReadVerdict) -> Void) { done(.blocked(.undecided)) }

    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void) {
        guard isOpen() else { return answer(.no) }
        let shown = ArisMCPCards.shared.put(card, timeout: ArisCardEdit.questionTimeout, answer: answer)
        lock.withLock { _ = cards.insert(shown.id) }
        show(.confirm(shown))
        watch(shown.id)
    }

    /// Every card it put up is a no (the replay ended, or its stream did).
    func cancelAll() {
        let ids = lock.withLock { () -> Set<String> in defer { cards = [] }; return cards }
        ArisMCPCards.shared.cancel(ids)
    }

    private func watch(_ id: String) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, ArisMCPCards.shared.isWaiting(id) else { return }
            if self.isOpen() { self.watch(id) } else { ArisMCPCards.shared.cancel([id]) }
        }
    }

    func audit(_ fields: [String: String]) {
        ArisWhyDesk.shared.gated(ArisAgentRunner.auditJSON(fields))
        ArisAgentRunner.writeAudit(ArisAgentRunner.auditJSON(fields.merging(["question": "saved-steps"]) { $1 }), key: "desktop")
    }
}
