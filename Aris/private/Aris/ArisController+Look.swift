//
//  ArisController+Look.swift
//  Aris
//
//  "이거": when the words point at the screen (ArisDeixis), aris-agent looks first (the selection, the browser
//  tab, or the front window) and the AI gets it with the question, so it needn't go looking. "이거 정중하게
//  바꿔줘" on a selection in a text field puts the new text in its place instead of reading it out (⌘Z undoes).
//

import AppKit
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "look")

extension ArisController {
    /// The reply said, or nil when the turn failed or was cancelled.
    /// "아까 복사한 …" brings the clipboard history along the same way (ArisClipboardModel; outside text too).
    func answerAboutScreen(_ text: String, tier: ArisTier, brain: ArisBrain) async -> String? {
        var look: ArisAgentClient.Look?
        // Over the length limit: no look first, the helper's refusal comes at once (ArisAgentCopy.overLimit).
        if ArisDeixis.refersToScreen(text), !ArisAgentCopy.overLimit(text) {
            session = session.working(ArisUIWords.status("화면 보는 중"))
            // The app he was in as he asked (ArisUserApp): the helper reads that app's window, never its own stale idea of it.
            let own = ProcessInfo.processInfo.processIdentifier
            look = await ArisAgentClient.look(front: ArisUserApp.pick(front: NSWorkspace.shared.frontmostApplication?.processIdentifier, own: own,
                                                                      previous: ArisPanelKeys.focus.previous))
            guard !Task.isCancelled else { return nil }
            log.notice("looked: \(look == nil ? "couldn't" : look!.selected ? "a selection" : "the window", privacy: .public)\(ArisLookContext.lacks(look?.needs ?? []), privacy: .public)")
            if let look, look.selected, look.editable, ArisDeixis.wantsRewrite(text) {
                return await rewriteSelection(text, look: look, tier: tier, brain: brain)
            }
        }
        let copies = ArisClipboardModel.shared.items
        let clipboard = ArisDeixis.refersToClipboard(text) && !copies.isEmpty ? ArisDeixis.clipboardContext(copies) : nil
        var looked: String?
        if let look {
            // The app's own screenshot is the screen read: with it in hand the AI isn't told what aris-agent couldn't read.
            let pictured = await ArisTurnCapture.shared.inHand()
            guard !Task.isCancelled else { return nil }
            looked = ArisLookContext.words(context: look.context, unread: look.unread, unselected: look.unselected,
                                           pictured: pictured, rewrite: ArisDeixis.wantsRewrite(text))
        }
        let screen = [looked, clipboard].compactMap { $0 }.joined(separator: "\n\n")
        return await askAndSpeak(text, tier: tier, brain: brain, screen: screen.isEmpty ? nil : screen)
    }

    /// Asks for only the new text, then types it over the selection. The brain is the turn's own (the one the owner chose
    /// or named), or one that is set up here when that one isn't: never one brain for everybody (audit brain-1).
    private func rewriteSelection(_ text: String, look: ArisAgentClient.Look, tier: ArisTier, brain: ArisBrain) async -> String? {
        let korean = ArisSpeech.language(of: text) == "ko-KR"
        let instruction = text + "\n\n(Rewrite the selected text as asked. Answer with only the new text: no quotes, no notes, nothing before or after. It replaces the selection.)"
        var written = ""
        let context = await currentContext()
        guard !Task.isCancelled else { return nil }
        let fresh = freshConversation
        freshConversation = false
        let answering = ArisBrainChoice.answering(brain, ready: ArisBrainSetup.shared.ready)
        // A new conversation the helper never heard of is still new on the next turn (auto L7).
        var reached = false
        defer { if fresh, !reached { freshConversation = true } }
        // `noActions`: this turn declines every card, so nothing in it is ever let run by the automatic check either.
        for await reply in ArisAgentClient.ask(instruction, context: context, tier: tier, brain: answering, screen: look.context, fresh: fresh,
                                                     handsFree: turnHandsFree, noActions: true) {
            if case .failure = reply {} else { reached = true }
            guard !Task.isCancelled else { return nil }
            switch reply {
            case .status(let status):
                session = session.working(status)
            case .stepFailed(let label):
                session = session.stepFailed(label)
            case .delta(let piece):
                written += piece
                session = session.answering(written)
            case .confirm(let ask):
                // Rewriting needs no actions: anything the AI wants to do is declined.
                if await ArisAgentClient.confirm(ask.id, allow: false, shown: ask) == .refused {
                    await speak { await self.speaker.speak(ArisConfirmResult.refusedNotice(english: ArisUIWords.english)) }
                }
            case .file, .turn, .launched, .untrusted, .refusedJobs, .shownOnly, .operating, .skill, .helperAnswers:
                break
            case .answer(let answer):
                let new = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !new.isEmpty else {
                    fail(korean ? "바꿀 글을 못 받았어요." : "No new text came back.")
                    return nil
                }
                if let problem = await ArisAgentClient.insert(new) {
                    log.error("rewrite not typed: \(problem, privacy: .public)")
                    fail(korean ? "바꾸지 못했어요: \(problem)" : "Couldn't replace it: \(problem)")
                    return nil
                }
                let said = korean ? "바꿨어요. ⌘Z로 되돌릴 수 있어요." : "Replaced it. ⌘Z undoes it."
                session = session.answering(new)
                stats?.firstSound(at: .now)
                await speak { await self.speaker.speak(said) }
                return said
            case .failure(let message):
                fail(message)
                return nil
            }
        }
        return nil
    }
}
