//
//  ArisMailReplyCard.swift
//  aris-agent
//
//  The card for a reply to a mail (`aris-tools mail reply <id> --text …`), on every brain: Codex's and an API brain's
//  own gate, the Claudes' hand-off and Antigravity's relay all describe a command through ArisCodexDriver.describe,
//  which asks here. A reply is written after a mail was read, so its words and its target are steered by outside text.
//  The card therefore takes nothing about where it goes from the AI: Aris reads Mail's own record of that mail and
//  shows every address whole (the real address before any name it gives itself), the subject, the mail being answered,
//  a line for anything odd (an answer asked for somewhere else than it came from, an address that was never on the
//  conversation and that the user didn't say, a name that hides another address), the whole text, and what a yes does: it
//  opens a draft in Mail, and he sends it there. It is asked every time: never learned, never a standing permission,
//  never the judge's (ArisRiskPolicy's hard line for it is `uncertain`). Pure but for the store it reads.
//

import Foundation

enum ArisMailReplyCard {
    static let title = "메일 답장"
    static let englishTitle = "Reply to mail"

    /// The home folder whose Mail store the card reads (the tests point it at a made-up one).
    nonisolated(unsafe) static var home: () -> String = { NSHomeDirectory() }

    /// The card for the words after `mail`; nil when they aren't a reply (the lists and reads never ask).
    static func card(_ words: [String], request: String, zone: TimeZone = .current) -> (String, String)? {
        guard ArisMailReplyWords.isReply(words) else { return nil }
        let english = ArisGateWords.isEnglish(request)
        let title = english ? englishTitle : Self.title
        guard let reply = ArisMailReplyWords.parse(words) else {
            return (title, english ? "(This reply command can't be read, so nothing will be drafted.)" : "(읽을 수 없는 답장 명령이라 초안이 만들어지지 않아요.)")
        }
        guard let plan = plan(reply, request: request) else {
            let lines = english
                ? ["Check: I couldn't find mail #\(reply.id) in Mail, so I can't show who this would go to. Nothing will be drafted.", "Text:", reply.text]
                : ["주의: Mail에서 #\(reply.id) 메일을 찾지 못해서 누구에게 가는지 보여 드릴 수 없어요. 허용해도 초안은 만들어지지 않아요.", "내용:", reply.text]
            return (title, lines.map(ArisDesktopCard.shown).joined(separator: "\n"))
        }
        // Shown as the other cards show an AI's words: line breaks kept, anything invisible made visible.
        return (title, ArisMailReply.cardLines(plan, english: english, zone: zone).map(ArisDesktopCard.shown).joined(separator: "\n"))
    }

    /// The reply as aris-tools will open it, worked out from Mail's own record; nil when that mail can't be read.
    static func plan(_ reply: ArisMailReplyWords, request: String) -> ArisMailReplyPlan? {
        guard let path = try? ArisMailRead.databasePath(home: home()), let db = try? ArisLocalDatabase(path: path),
              let original = try? ArisMailStore.envelope(db, id: reply.id) else { return nil }
        let root = ((path as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
        let replyTo = ArisMailStore.full(root: root, envelope: original).content?.addresses("reply-to").first
        let thread = (try? ArisMailStore.thread(db, id: reply.id).mails) ?? [original]
        return ArisMailReply.plan(reply, original: original, replyTo: replyTo, thread: thread, own: ArisMailStore.own(db), request: request)
    }
}
