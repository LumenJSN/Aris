//
//  ArisController+Look.swift
//  Aris
//
//  "이거": when the words point at the screen (ArisDeixis), aris-agent looks first (the selection, the browser
//  tab, or the front window) and the AI gets it with the question, so it needn't go looking. "이거 정중하게
//  바꿔줘" on a selection in a text field puts the new text in its place instead of reading it out (⌘Z undoes).
//  jv-focus: the look gets the words and what was circled, and resolves what they point at (ArisFocusResolver);
//  "이 사람한테 답장 써 줘" / "여기에 적어 줘" with the field already focused writes the text into it, never sending.
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
            setSession(session.working(ArisUIWords.status("화면 보는 중")))
            // The app he was in as he asked (ArisUserApp): the helper reads that app's window, never its own stale idea of it.
            let own = ProcessInfo.processInfo.processIdentifier
            look = await ArisAgentClient.look(front: ArisUserApp.pick(front: NSWorkspace.shared.frontmostApplication?.processIdentifier, own: own,
                                                                      previous: ArisPanelKeys.focus.previous),
                                              words: text, regions: ArisTurnCapture.shared.gestureRegions)
            guard !Task.isCancelled else { return nil }
            log.notice("looked: \(look == nil ? "couldn't" : look!.selected ? "a selection" : "the window", privacy: .public)\(ArisLookContext.lacks(look?.needs ?? []), privacy: .public)")
            // The quick path types only at a caret with nothing selected, for words that only ask to write there
            // (ArisTypeHere, twelfth VM run S3): erasing, replacing, rewriting or typing over a selection goes to the
            // normal turn, where the change asks on a card that shows what goes and keeps an undo.
            if let look, look.writesHere, let target = look.target, !target.isEmpty,
               ArisTypeHere.route(words: text, writesHere: look.writesHere, rewrite: look.selected && ArisDeixis.wantsRewrite(text),
                                  selection: ArisTypeHere.selection(selected: look.selected, readable: look.unselected == nil)) == .insertAtCaret,
               case let said = await rewriteSelection(text, look: look, tier: tier, brain: brain, mode: .draft), said != Self.normalPathInstead {
                return said
            }
            guard !Task.isCancelled else { return nil }
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
    /// What the typed text is: the selection rewritten, or a draft written where the caret is (a reply, a line).
    enum FieldWrite { case rewrite, draft }

    private func rewriteSelection(_ text: String, look: ArisAgentClient.Look, tier: ArisTier, brain: ArisBrain, mode: FieldWrite = .rewrite) async -> String? {
        let korean = ArisSpeech.language(of: text) == "ko-KR"
        let instruction = text + (mode == .rewrite ? Self.rewriteInstruction : Self.draftInstruction)
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
                setSession(session.working(ArisUIWords.status(status)))
            case .stepFailed(let label):
                setSession(session.stepFailed(label.map { ArisUIWords.status($0) }))
            case .delta(let piece):
                written += piece
                setSession(session.answering(written))
            case .confirm(let ask):
                // Rewriting needs no actions: anything the AI wants to do is declined.
                if await ArisAgentClient.confirm(ask.id, allow: false, shown: ask) == .refused {
                    await speak { await self.speaker.speak(ArisConfirmResult.refusedNotice(english: ArisUIWords.english)) }
                }
            case .file, .turn, .launched, .untrusted, .refusedJobs, .shownOnly, .operating, .skill, .helperAnswers, .savedSteps, .work:
                break
            case .answer(let answer):
                let new = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !new.isEmpty else {
                    fail(korean ? "바꿀 글을 못 받았어요." : "No new text came back.")
                    return nil
                }
                // Into the field the look read, by its element: never where the keyboard is now (the notch, when he typed).
                // A draft only at its caret (ArisTypeHere): a selection found there now sends the turn to the normal path.
                var undoable = false
                if mode == .draft, let target = look.target, !target.isEmpty {
                    switch await ArisAgentClient.typeAtCaret(new, target: target) {
                    case .typed(let typed):
                        undoable = typed.undo != nil
                        ArisTypedHereLog.shared.note(typed)
                    case .notAtCaret:
                        log.notice("draft not typed: a selection at the caret, so the normal turn")
                        return Self.normalPathInstead
                    case .failed(let problem):
                        log.error("draft not typed: \(problem, privacy: .public)")
                        fail(ArisToolErrorWords.line("쓰지 못했어요", "Couldn't write it", problem: problem))
                        return nil
                    }
                } else if let problem = await ArisAgentClient.insert(new, target: look.target) {
                    log.error("rewrite not typed: \(problem, privacy: .public)")
                    // In the UI's language, the tool's reason too (ArisToolErrorWords).
                    fail(ArisToolErrorWords.line("바꾸지 못했어요", "Couldn't replace it", problem: problem))
                    return nil
                }
                // What actually happened: added at the caret, nothing erased (and how to take it back).
                let said = mode == .rewrite ? (korean ? "바꿨어요. ⌘Z로 되돌릴 수 있어요." : "Replaced it. ⌘Z undoes it.")
                    : ArisTypeHere.insertedLine(korean: korean, undoable: undoable)
                setSession(session.answering(new))
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

    /// rewriteSelection's answer when the draft found a selection at the caret: the turn goes on as a normal one.
    static let normalPathInstead = "\u{1}normal path"

    static let rewriteInstruction = "\n\n(Rewrite the selected text as asked. Answer with only the new text: no quotes, no notes, nothing before or after. It replaces the selection.)"
    /// A draft goes where the caret is and is never sent: the owner reads it and sends it himself.
    static let draftInstruction = "\n\n(Write the text to put in the field where the cursor is, as asked: when it is a reply, a reply to the conversation or mail in the focus, in its language. Answer with only that text: no quotes, no notes, nothing before or after. It is typed into the field and nothing is sent.)"
}
