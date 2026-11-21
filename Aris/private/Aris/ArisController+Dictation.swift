//
//  ArisController+Dictation.swift
//  Aris
//
//  Dictation anywhere: hold the right ⌥ and talk (or tap it twice and let go); the notch opens and listens as for
//  Aris. When it ends, Whisper (or Scribe) writes it down, ArisDictationCleaner takes out the fillers and take-backs,
//  Apple's on-device model polishes it in the app's writing style (raw in IDEs and terminals), and aris-agent types it
//  where the cursor is (no Enter) and watches the field a minute to learn a word the user fixes; with nowhere to type it,
//  the words go on the clipboard and the notch says so (ArisDictationCopy). Music keeps playing.
//  ⌃⌘V types the last one again. 20 minutes at most, with a word at 19.
//

import AppKit
import Defaults
import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "dictation")

enum ArisDictationStage: Equatable {
    case listening
    /// What was said, with the words the cleaner drops, while it's being typed.
    case cleaning([ArisDictationCleaner.Word])
    case typed
}

extension ArisController {
    /// How long "넣었어요" stays before the notch closes.
    static let dictationLinger: Duration = .milliseconds(1200)

    func dictationKey(_ action: ArisDictationKey.Action) {
        // A press waiting for the last words takes the key's actions until they're in (or it's let go).
        if dictationQueue.waiting {
            var queue = dictationQueue
            if queue.take(action) {
                if !queue.waiting { log.notice("dictation: let go before the last words were in") }
                dictationQueue = queue
                return
            }
        }
        switch action {
        case .start: startDictation()
        case .lock: lockDictation()
        case .startLocked:
            // A double tap: hands-free from the start (or, queued behind the last words, once they're in).
            startDictation()
            if dictationQueue.waiting { _ = dictationQueue.take(.lock) } else { lockDictation() }
        case .finish: finishDictation()
        // An accidental tap, a triple tap or Esc: dropped quietly.
        case .cancel: if dictation == .listening { cancel() }
        case .none: break
        }
    }

    /// What Aris is doing now, as the right ⌥ sees it.
    private var dictationTurn: ArisDictationPress.Turn {
        switch session.phase {
        case .idle: .idle
        case .listening: .listening
        case .thinking: .thinking
        case .speaking: session.question == nil ? .speaking : .asking
        case .failed: .failed
        }
    }

    func startDictation() {
        // Already dictating: the key's own presses end it, and there is nothing to start.
        if dictation == .listening, !ArisDictationState.shared.finishing { return }
        // The last dictation still on screen is closed or waited for; Aris reading an answer out (or a failure line)
        // stops for it, as for ⌥Space; a turn that can't be interrupted says why (audit voice-9: never ignored
        // without a sign).
        let typing = dictation.map { $0 != .listening || ArisDictationState.shared.finishing } ?? false
        switch ArisDictationPress.decide(turn: dictationTurn, training: training != nil,
                                         lastTyped: dictation == .typed, lastTyping: typing && dictation != .typed) {
        case .refuse(let why):
            log.notice("dictation: not now (\(String(describing: why), privacy: .public))")
            ArisDictationState.shared.refuse(why)
            return
        case .queue:
            log.notice("dictation: the last words are still going in; this one starts after")
            dictationQueue.press()
            return
        case .replaceTyped:
            endTurn(.dismissed)
            setSession(session.done(), from: nil)
        case .interrupt:
            log.notice("dictation: Aris stops for it")
            // An answer already delivered stays in the history and its turn logs "ok", as 닫기 keeps it.
            if let outcome = ArisTurnClosing.closing(phase: session.phase, remembered: turnMemory.remembered).outcome { finishTurn(outcome) }
            cancel()
        case .start: break
        }
        ArisDictationState.shared.clearRefusal()
        if let problem = Self.permissionProblem() { return askForPermissions(problem) }
        // Dictation takes the microphone: a conversation ends first.
        closeConversation(.dictation)
        stopWaitingForWakeWord()
        ArisDictationState.shared.begin(front: NSWorkspace.shared.frontmostApplication)
        dictation = .listening
        log.notice("dictating")
        // A dictation is a turn of its own: the microphone and every task it starts work for it.
        ArisTurnScope.within(openTurn(.dictation)) {
            openMicrophone()
            watchDictationLimit()
        }
    }

    /// Two quick presses: hands-free until the next press.
    func lockDictation() {
        guard dictation == .listening else { return }
        log.notice("dictation: hands-free")
        ArisDictationState.shared.locked = true
    }

    /// The 20-minute cap, with a gentle word a minute before; the state is let go when the dictation ends any way.
    private func watchDictationLimit() {
        let started = ContinuousClock.now
        let state = ArisDictationState.shared, generation = state.generation
        Task { [weak self] in
            watch: while let self, self.dictation == .listening, state.generation == generation, !state.finishing {
                try? await Task.sleep(for: .seconds(1))
                guard self.dictation == .listening, state.generation == generation, !state.finishing else { break }
                switch ArisDictationLimit.stage(after: .now - started) {
                case .fine: break
                case .warning: if !state.warning { state.warning = true }
                case .over:
                    log.notice("dictation: 20 minutes, typing it")
                    ArisDictationKeyTap.shared.reset()
                    self.finishDictation()
                    break watch
                }
            }
            if state.generation == generation {
                state.end()
                ArisDictationKeyTap.shared.dictationEnded()
            }
        }
    }

    func finishDictation() {
        // Once: the key and the 20-minute cap can both end it.
        guard dictation == .listening, session.phase == .listening, !ArisDictationState.shared.finishing else { return }
        guard let listener = listener as? ArisListener else { return cancel() }
        // Voice the level meter counted, or words a recogniser wrote: a quiet microphone can stay under the voice
        // level while every word is written (audit voice-10).
        guard ArisDictationEnd.saidSomething(heardVoice: lastVoiceAt != nil, wroteWords: lastWordsAt != nil) else {
            log.notice("dictation: nothing said")
            return cancel()
        }
        let state = ArisDictationState.shared
        state.finishing = true
        if ArisQuietGate.maySound(.user) { Self.heardSound?.play() }
        stats = ArisTurnStats(startedAt: .now)
        let starting = self.starting
        let style = state.style
        let polish = state.takeForPolish()
        runTurn(.dictation) {
            await starting?.value
            let apple = (try? await Self.within(Self.stopTimeout, cancelsWork: false) { await listener.stop() }) ?? session.heard
            // Any length up to the five minutes the recording holds goes to Whisper whole: past 30 s it reads window by
            // window, each cut where the voice was quietest (ArisLongTurn), and the live recognizer's text is kept only
            // when Whisper isn't ready, runs out of time (3 s, plus 2 s a window, at most 12 s), or the dictation outran
            // the recording. Before, past 28 s Whisper was skipped and the weaker live text typed (2026-11-18 audit).
            let recording = listener.secondListenSamples
            self.listener = nil
            level = 0
            let heard = await secondListen(recording, apple: apple)
            let cleaned = ArisDictationCleaner.clean(heard, endStop: style.endsWithStop)
            understood(heard, path: "dictation", tier: .quick)
            guard !Task.isCancelled, dictation == .listening else { return }
            guard !cleaned.isEmpty else { return cancel() }
            dictation = .cleaning(ArisDictationCleaner.marked(heard))
            setSession(session.hearing(heard).thinking())
            let text = await polishedDictation(cleaned, style: style, session: polish.session, context: polish.context)
            guard !Task.isCancelled else { return }
            // The notch says when it waits for the keys; the words are kept for ⌃⌘V and copied if the wait is long.
            let outcome = await insertDictationShowingWait(text, state: state)
            guard !Task.isCancelled else { return }
            // Nowhere took it (no app read the paste, or it couldn't be typed): it goes on the clipboard instead.
            let copied = ArisDictationCopy.copies(outcome)
            if case .failed(let problem) = outcome { log.notice("dictation not typed: \(problem, privacy: .public)") }
            if outcome == .helperOff {
                // The helper may not press keys. With Aris's own switch on that is macOS no longer counting the helper as
                // the app: said as it is, with the button that opens the list (the words are kept on the clipboard).
                let appOn = AXIsProcessTrusted()
                if ArisHelperInstallWords.mappingLost(appSwitchOn: appOn, helperSays: false) { log.error("\(ArisHelperInstallWords.mappingLostLog, privacy: .public)") }
                _ = state.copy(text)
                let line = ArisHelperInstallWords.notTyped(appSwitchOn: appOn)
                // The pill has room for a few words: the whole reason, with the list to open, goes on the notice pill.
                guard ArisDictationPillGate.on else { return failDictation(line) }
                let notice = ArisNoticeRoute.problem(line: line, title: ArisDictationWait.pillLine(english: ArisUIWords.english), english: ArisUIWords.english)
                ArisTurnScope.outside { Task { [weak self] in await self?.notify(notice) } }
                return failDictation(ArisDictationWait.pillLine(english: ArisUIWords.english))
            }
            if copied {
                guard state.copy(text) else {
                    // Still there for ⌃⌘V (state.lastText).
                    log.error("dictation: nowhere to type it and the clipboard refused it")
                    return failDictation(ArisUIWords.text("입력하지 못했어요", "Couldn't type it"))
                }
                log.notice("dictation: nowhere to type it; copied")
            }
            state.lastText = text
            state.copied = copied
            dictation = .typed
            setSession(session.answering(text))
            finishTurn("ok")
            if startQueuedDictation() { return }
            await lingerAfterDictation(copied: copied)
            guard !Task.isCancelled, dictation == .typed else { return }
            setSession(session.done())
        }
    }

    /// The microphone changed or went away mid-dictation (a headset connected, a device unplugged): what was said so
    /// far is typed, or copied, as if the key had been let go; with nothing said it ends and the notch says why.
    /// Never a turn for the AI (audit voice-1).
    func dictationInterrupted() {
        guard dictation == .listening, session.phase == .listening, !ArisDictationState.shared.finishing else { return }
        log.notice("dictation: the microphone changed")
        // The key may still be down: its release must not act on a dictation that is already over.
        ArisDictationKeyTap.shared.reset()
        switch ArisMicInterruption.outcome(dictating: true, heardWords: lastWordsAt != nil, heardVoice: lastVoiceAt != nil) {
        case .typeDictation:
            finishDictation()
        case .endDictation, .endTurn, .failTurn:
            failDictation(ArisMicInterruption.dictationLine, endsDictation: true)
        }
    }

    /// A dictation went wrong. With the pill on, the line shows in the pill and the turn ends quietly (the notch stays
    /// quiet for dictation); otherwise the notch says it, as before (`endsDictation`: the stage goes first, so the notch
    /// shows the line as a failed turn).
    func failDictation(_ line: String, endsDictation: Bool = false) {
        // A dictation that is over fails nothing: the turn after it is not its to end.
        guard turnIsCurrent else { return }
        guard ArisDictationPillGate.on else {
            if endsDictation { dictation = nil }
            return fail(line)
        }
        log.notice("dictation: failed, said in the pill")
        ArisDictationState.shared.showPillError(line)
        gestureCancelled()
        finishTurn("error")
        endTurn(.failed)
        releaseListener()
        level = 0
        setSession(session.done(), from: nil)
        resumeMusicIfPaused()
    }

    /// 받아쓰기 쓰기 was turned off: a dictation still listening is dropped, and a press waiting for the last words is
    /// forgotten (words already on their way in still go in).
    func dictationTurnedOff() {
        dictationQueue = ArisDictationQueue()
        guard dictation == .listening, !ArisDictationState.shared.finishing else { return }
        log.notice("dictation: turned off, dropping the one listening")
        cancel()
    }

    // MARK: - The pill's controls

    /// A click on the idle pill: a hands-free dictation into the app in front (the pill's panel never activates Aris,
    /// so that app keeps the keyboard). ✕ cancels it, ↑ or the key puts it in.
    func startDictationFromPill() {
        // 받아쓰기 쓰기 off: the pill is hidden, and a click that still lands where it was does nothing.
        guard ArisDictationSwitch.on, dictation != .listening else { return }
        startDictation()
        guard dictation == .listening else { return }
        log.notice("dictation: started from the pill")
        lockDictation()
        ArisDictationState.shared.fromPill = true
        ArisDictationKeyTap.shared.lockFromPill()
    }

    func cancelDictationFromPill() {
        guard dictation == .listening, !ArisDictationState.shared.finishing else { return }
        ArisDictationKeyTap.shared.reset()
        cancel()
    }

    func finishDictationFromPill() {
        guard dictation == .listening, !ArisDictationState.shared.finishing else { return }
        ArisDictationKeyTap.shared.reset()
        finishDictation()
    }

    /// "넣었어요" a moment; the copied card longer, and while the pointer is on it (at most ArisNotch.longestHover).
    private func lingerAfterDictation(copied: Bool) async {
        try? await Task.sleep(for: copied ? ArisDictationCopy.linger : Self.dictationLinger)
        guard copied else { return }
        let state = ArisDictationState.shared, started = ContinuousClock.now
        while state.cardHovered, ContinuousClock.now - started < ArisNotch.longestHover, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(300))
        }
    }

    /// The last words are in: a press that waited for them starts its dictation now (hands-free if it was a double
    /// tap). True when one started.
    private func startQueuedDictation() -> Bool {
        var queue = dictationQueue
        let next = queue.typed()
        dictationQueue = queue
        guard next.start else { return false }
        setSession(session.done())
        startDictation()
        if next.locked { lockDictation() }
        return true
    }

    /// The cleaned words through polish: on this Mac first; a brain (no tools) only when the user turned it on; else as
    /// they are. Raw styles (IDEs, terminals) never go through a model.
    private func polishedDictation(_ text: String, style: ArisWritingStyle, session prepared: AnyObject?,
                                   context: (before: String, after: String)?) async -> String {
        guard style.polishes else { return text }
        let started = ContinuousClock.now
        if let local = await ArisDictationPolish.polish(text, with: prepared, before: context?.before, after: context?.after) {
            log.notice("dictation: polished on this Mac in \(Int((ContinuousClock.now - started) / .milliseconds(1)), privacy: .public) ms")
            return local
        }
        guard Defaults[.arisDictationBrainPolish] else { return text }
        let reply = await ArisAgentClient.polishDictation(text, style: style, words: ArisVocabulary.load(), context: context)
        guard let polished = ArisDictationPolish.checked(text, reply) else {
            log.notice("dictation: no polish (\(reply == nil ? "no reply" : "not the same words", privacy: .public))")
            return text
        }
        log.notice("dictation: polished by the brain in \(Int((ContinuousClock.now - started) / .milliseconds(1)), privacy: .public) ms")
        return polished
    }

    /// ⌃⌘V: the last dictation typed again where the cursor is, once the shortcut's keys are let go (so ⌃ isn't
    /// still down when ⌘V is pressed).
    func pasteLastDictation() {
        guard ArisDictationSwitch.on, let text = ArisDictationState.shared.lastText, dictation == nil else { return }
        Task {
            for _ in 0..<50 where !NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
                try? await Task.sleep(for: .milliseconds(20))
            }
            if case .failed(let problem) = await ArisAgentClient.insertDictation(text, learn: false) {
                log.error("last dictation not typed: \(problem, privacy: .public)")
                // Said in the notch, never over a turn that started meanwhile.
                if session.phase == .idle { fail(ArisToolErrorWords.line("마지막 받아쓰기를 넣지 못했어요", "Couldn't type the last dictation", problem: problem)) }
            }
        }
    }
}
