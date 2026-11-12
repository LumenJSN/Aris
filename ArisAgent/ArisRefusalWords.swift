//
//  ArisRefusalWords.swift
//  aris-agent
//
//  What a brain is told when Aris itself stopped an action (audit gate-5, gate-6). A bare decline reads to the brain
//  exactly like the user's own no, so it answered "알겠어요, 안 할게요" for something the user never refused, and could not fix
//  a call it had only worded wrong. Every line here is fixed text made by this code: never the brain's own words, an
//  app's name or a tool's arguments handed back to it.
//

import Foundation

enum ArisRefusalWords {
    private static let lead = "[Aris] Refused by Aris's own safety rules, not by the user (they weren't asked and didn't say no): "
    private static let tail = " Don't try another way to do the same thing. If what the user asked can be done with a command Aris "
        + "allows, use that; otherwise say in a few words what you couldn't do and why, never as the user's own no."

    /// The gate rated `action` never, for `why` (the audit's reason, ArisRiskPolicy.neverReason or the gate's own).
    /// A desktop call the engine couldn't read gets its usage back, so the brain can write it again.
    /// Nil when the refusal only follows the user's own answer (their no earlier this turn, or the card they changed and Aris
    /// already ran): the brain has been told, and it is no rule of Aris's.
    static func neverNote(_ action: ArisAction, why: String, tools: String) -> String? {
        if why.hasPrefix(afterUsersNo) || why.hasPrefix(afterChangedCard) { return nil }
        if case .shell(let command) = action, let problem = ArisRiskPolicy.callProblem(command, tools: tools) { return "[Aris] " + problem }
        return lead + reason(action, why: why) + "." + route(action) + tail
    }

    /// How the gates' own reasons begin when a refusal only follows the user's answer.
    static let afterUsersNo = "the user already said no"
    static let afterChangedCard = "the user's changed card"

    /// The reason without anything the brain chose (an app's or a tool's name).
    private static func reason(_ action: ArisAction, why: String) -> String {
        switch action {
        case .computerUse:
            return why.contains("browser") ? "computer use is never used in a web browser (website work goes to Aside)"
                : why.contains("System Settings") ? "that System Settings pane (privacy, users, passwords) is the user's to change"
                : "computer use is never used in that app (terminals, code editors, password stores, AI and automation apps)"
        case .mcp:
            return why.isEmpty || why.contains("never-list") ? "that tool is one Aris never runs" : why
        case .shell, .fileChange, .browserTask:
            return why.isEmpty ? "it is on Aris's never-list" : why
        }
    }

    /// The allowed way to the same end, where there is one.
    private static func route(_ action: ArisAction) -> String {
        guard case .shell(let command) = action, let program = ArisCommandPolicy.words(command)?.first.map({ ($0 as NSString).lastPathComponent }) else { return "" }
        // shutdown, reboot and halt need root, which Aris never takes: System Events does it after the user's card.
        if ["shutdown", "reboot", "halt"].contains(program) {
            return #" To restart, shut down or log out, run `osascript -e 'tell application "System Events" to restart'` (or `shut down`, `log out`, `sleep`): the user is asked on a card first."#
        }
        return ""
    }

    /// A hands-free turn doesn't send, delete or reach outside: the user asks again by the key.
    static let handsFree = "[Aris] Not done: on a hands-free turn Aris doesn't send, delete or reach outside. That is not the user's no. "
        + "Don't try another way; tell the user: " + ArisHandsFree.askAgainLine

    /// A card nobody answered in time: not a no, and nothing was done.
    static let unanswered = "[Aris] The user didn't answer that confirm card in time, so it was not done. That is not a no from them "
        + "and not a refusal. Don't try it another way now: say plainly that it wasn't done because it is still waiting for their "
        + "yes, and carry on with anything else the request needs (each other action is asked about on its own)."

    /// A hard line refused the action (ArisEscalation.decide): money, or a mail whose text the card couldn't show.
    static func hardLine(_ line: ArisHardLine?) -> String {
        if line == .mailSend {
            return lead + "a mail is sent only when the user's card can show who it goes to, its subject and its whole text. "
                + "Send it with the mail tool's own send, with the recipient, the subject and the full body in that one call "
                + "(never a draft by its id, never a mail program in the shell): the user is then asked on a card. "
                + "A reply is the same: never by the mail's id alone and never to everyone by a switch, since the card couldn't show who "
                + "gets it. Give the recipient's address, the subject and the whole text in the call, or use Aris's own "
                + "`mail reply <#number> --text '<the reply>'` for a mail in Apple Mail (its card shows every address, and it opens as a draft). "
                + "If you can't, leave it as a draft and say so."
        }
        let what = line == .money ? "Aris never pays, orders, subscribes or moves money" : "it is one of the things Aris never does on its own"
        return lead + what + ". Don't try another way. Tell the user plainly that this part is theirs to do, and carry on with anything else the request needs."
    }

    /// The user changed a card into something Aris doesn't do: nothing ran.
    static let changedCard = "[Aris] The user changed that action on its confirm card, and the changed version is one Aris doesn't do, "
        + "so nothing was done. That is not a no from them. Don't run it again; say plainly that it wasn't done."
}
