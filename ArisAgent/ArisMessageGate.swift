//
//  ArisMessageGate.swift
//  aris-agent
//
//  `aris-tools message <to> <text>` for a brain with no gate of its own (the open and the sealed Claude), decided by the
//  agent with the rules Codex's and the API brain's gates use (the owner: no feature locked by brain). A message the user said
//  word for word goes after the countdown (ArisRiskPolicy+Dictation: the recipient he named, the text close to his
//  words, a send word); only in a conversation, never a background job, never after outside text (or the screen, for
//  words they didn't say), never hands-free. Anything else is the user's plain card. The sealed Claude (a turn that saw the
//  screen, or a hands-free one; the owner, 2026-11-08) gets only their plain card, never the countdown, and nothing once its
//  conversation read outside text. The call is the message alone (the turn gate and the sealed hook refuse a chain),
//  so nothing rides along on the card. On a yes the agent sends it (aris-tools as Aris itself), never the brain.
//  Pure apart from `run`, so the tests run it with a fake turn.
//

import Foundation

/// The turn as the message gate sees it (ArisRunnerMessageTurn; a fake in the tests).
protocol ArisMessageTurn: AnyObject {
    /// The user's own words for this turn (from the microphone), never the AI's.
    var request: String { get }
    /// The question as it came, with the note of the files the user gave it (ArisMemoryText.filesNote): only for telling
    /// that one of those files is being opened (ArisRiskPolicy.opensAttachment). His own words when there is none.
    var attached: String { get }
    var isTask: Bool { get }
    var taint: ArisTaint { get }
    var handsFree: Bool { get }
    var critical: Bool { get }
    /// A teammate's job: what it may use (nil for Aris's own turns).
    var scopes: Set<ArisTeammateScope>? { get }
    /// The sealed Claude's turn: the user's plain card only, and refused after outside text.
    var sealed: Bool { get }
    /// Puts the user's card up; `answer` is called once (a no, a timeout or the turn ending is `.no`).
    func ask(_ card: ArisMCPCard, answer: @escaping (ArisMCPAnswer) -> Void)
    func audit(_ fields: [String: String])
    /// A gate's own line for actions.log (the action and how it was judged), written as it is.
    func auditLine(_ line: String)
    /// Read again after the user's yes: the turn is still under way and no outside text came in since the card (L6).
    func stillSendable() -> Bool
    /// What the automatic check needs of this turn (ArisAutoHandOff); nil: the turn is never checked.
    var auto: ArisAutoTurn? { get }
}

extension ArisMessageTurn {
    var attached: String { request }
    var sealed: Bool { false }
    var auto: ArisAutoTurn? { nil }
    func auditLine(_ line: String) {}
}

enum ArisMessageGate {
    enum Card: Equatable {
        /// The user's dictated message: said out loud, sent after the countdown unless they stops it.
        case countdown(to: String, text: String)
        /// The user's card, as Codex shows it for this command.
        case ask(title: String, detail: String)
        case refused(String)
    }

    /// The most of a recipient and a message the route reads.
    static let maxTo = 200
    static let maxText = 4_000

    /// How long aris-tools may take over the send once the user said yes: the contact looked up, the message handed to
    /// Messages, its history watched for it, and one more try as a text message (ArisMessageSend: 44 seconds at the
    /// very most, a few as a rule).
    static let sendLimit: TimeInterval = 50

    static let refusal = "Refused by Aris's safety rules; don't try another way."
    static let declined = "The user said no (or didn't answer), so it wasn't sent. Don't try it another way now. A later request in a new turn gets a new card."
    static let changed = "Not sent: the conversation changed after the user's yes. Don't try it another way."
    /// The sealed Claude after outside text (a read of the user's apps, the web, a service): nothing goes out from it.
    static let afterOutsideText = "Refused: this conversation read outside text, so no message goes out from it. Don't try another way; the user can ask again in a new conversation."

    /// The words aris-tools runs: `message <to> <text>`.
    static func words(to: String, text: String) -> [String] { ["message", to, text] }

    /// The card for this message on this turn (ArisAPIGate.judge's steps, then the runner's: no countdown when tainted or in a job).
    static func card(to: String, text: String, turn: ArisMessageTurn, tools: String, home: String) -> Card {
        guard !to.isEmpty, !text.isEmpty, to.count <= maxTo, text.count <= maxText,
              !ArisCommandPolicy.hasLineBreak(to) else { return .refused(refusal) }
        let line = ArisFileRelay.commandLine(words(to: to, text: text), tools: tools)
        let action = ArisAction.shell(line)
        if let scopes = turn.scopes, !ArisTeammateScope.permits(action, scopes: scopes, tools: tools) { return .refused(refusal) }
        // The sealed Claude: never after outside text (the screen alone is why it is sealed, so that is fine).
        if turn.sealed, turn.taint >= .outsideText { return .refused(afterOutsideText) }
        var risk = ArisRiskPolicy.risk(of: action, tools: tools, home: home, critical: turn.critical, request: turn.request)
        let covered = turn.taint == .screenSeen && !turn.handsFree
            && ArisRiskPolicy.coveredByRequest(action, tools: tools, arguments: [:], request: turn.request)
        // After outside text (or the screen, for words the user didn't say): their card, never the countdown (on Codex the
        // runner's escalation makes a tainted countdown a question: ArisEscalation.card).
        if risk == .countdown, turn.taint.blocks(covered: covered) { risk = .confirm }
        if turn.handsFree { risk = ArisHandsFree.risk(risk, of: action, tools: tools) }
        // A background job's message is the user's card: only in a conversation is they right there to stop it.
        if turn.isTask, risk == .countdown { risk = .confirm }
        // The sealed Claude's message is always the user's plain card.
        if turn.sealed, risk == .countdown { risk = .confirm }
        if risk == .never { return .refused(refusal) }
        if risk == .countdown, let message = ArisRiskPolicy.dictatedMessage(words(to: to, text: text), request: turn.request) {
            return .countdown(to: message.to, text: message.text)
        }
        let (title, detail) = ArisCodexDriver.describe(command: line, tools: tools)
        return .ask(title: title, detail: detail)
    }

    /// The card the user sees (ArisMCPCards), nil for a refusal.
    static func shown(_ card: Card) -> ArisMCPCard? {
        switch card {
        case .countdown(let to, let text):
            return ArisMCPCard(title: to, detail: text, full: nil, fields: [], countdown: true,
                               spoken: ArisRiskPolicy.announcement(to: to, text: text))
        case .ask(let title, let detail): return ArisMCPCard(title: title, detail: detail, full: nil, fields: [])
        case .refused: return nil
        }
    }

    /// Decides, asks the user and, on their yes, sends (`run`, aris-tools as Aris): what the brain's aris-tools prints. Blocks
    /// until the user answers (or `limit` passes: a no).
    static func answer(to: String, text: String, turn: ArisMessageTurn, tools: String, home: String, limit: TimeInterval,
                       run: ([String]) -> ArisMCPOutcome) -> ArisMCPOutcome {
        let decided = card(to: to, text: text, turn: turn, tools: tools, home: home)
        guard let shown = shown(decided) else {
            // The gate's own reason goes back (audit gate-23: the brain was told only "refused by the safety rules", so
            // it couldn't say that a new conversation can send it). Fixed words of Aris's, never anything read.
            let why: String
            if case .refused(let reason) = decided { why = reason } else { why = refusal }
            turn.audit(["answer": why == afterOutsideText ? "refused (after outside text)" : "refused", "action": "message"])
            return .failed(why)
        }
        let done = DispatchSemaphore(value: 0)
        let yes = ArisFileRelayAnswer()
        turn.ask(shown) { answer in
            if case .yes = answer { yes.set() }
            done.signal()
        }
        let kind = shown.countdown ? "countdown" : "card"
        guard done.wait(timeout: .now() + limit) == .success, yes.isSet else {
            turn.audit(["answer": "no (\(kind))", "action": "message"])
            return .failed(declined)
        }
        guard turn.stillSendable() else {
            turn.audit(["answer": "not sent (the turn ended or read outside text after the yes)", "action": "message"])
            return .failed(changed)
        }
        turn.audit(["answer": "yes (\(kind))", "action": "message"])
        // Exactly the words on the card, once: the pass aris-tools needs to send it (ArisMessagePass).
        guard ArisMessagePass.mint(to: to, text: text) else { return .failed("couldn't send it") }
        return run(words(to: to, text: text))
    }

    /// What the brain reads back after a send: fixed words and its own recipient only, never anything Messages said,
    /// so a send brings no outside text into the conversation.
    /// `output`: what aris-tools printed (ArisMessageResult: "sent to <to>" only when Messages' own history shows it
    /// sent). A send that isn't known to have gone out (not shown as sent yet, unchecked, or cut off at the time limit)
    /// comes back as "not confirmed", never as "couldn't send it": that would have the brain send it a second time.
    static func reported(to: String, output: String) -> ArisMCPOutcome {
        for sent in [ArisMessageResult.sent(to), ArisMessageResult.sentAsText(to)] where output == sent {
            return ArisMCPOutcome(status: 0, output: sent)
        }
        if output.contains("couldn't find exactly one contact") {
            return .failed("couldn't find exactly one contact named \(to) (none, or more than one): ask who")
        }
        if output.hasPrefix(ArisMessageResult.notConfirmedLead) {
            return .failed(ArisMessageResult.notConfirmed(to, output.contains("Full Disk Access") ? .unreadable : .notShown))
        }
        if output == ArisAgyRelay.tookTooLong { return .failed(ArisMessageResult.notConfirmed(to, .tookTooLong)) }
        if output.hasPrefix(ArisMessageResult.notSentLead) {
            for known in [ArisMessageResult.notSent(to), ArisMessageResult.noAccount, ArisMessageResult.notAllowed] where output == known {
                return .failed(known)
            }
            return .failed(ArisMessageResult.failed)
        }
        return .failed("couldn't send it")
    }
}
