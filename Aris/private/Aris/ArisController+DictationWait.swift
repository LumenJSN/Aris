//
//  ArisController+DictationWait.swift
//  Aris
//
//  Typing a dictation while the helper may have to wait for the keys (ArisDictationWait): the notch's status says so,
//  the words go on the clipboard once the wait is long, and they are kept for ⌃⌘V before the paste is even asked for.
//

import Foundation

extension ArisController {
    func insertDictationShowingWait(_ text: String, state: ArisDictationState) async -> ArisInsertOutcome {
        // Never lost: ⌃⌘V has them whatever becomes of this paste.
        state.lastText = text
        let started = ContinuousClock.now
        let watch = Task { [weak self] in
            for stage in [ArisDictationWait.Stage.waiting, .waitingCopied] {
                let at = stage == .waiting ? ArisDictationWait.showAfter : ArisDictationWait.copyAfter
                try? await Task.sleep(until: started + at, clock: .continuous)
                guard !Task.isCancelled, let self, ArisDictationWait.stage(after: .now - started) == stage else { return }
                if stage == .waitingCopied { _ = state.copy(text) }
                if let line = ArisDictationWait.status(stage, english: ArisUIWords.english) { self.setSession(self.session.working(line)) }
            }
        }
        defer { watch.cancel() }
        return await ArisAgentClient.insertDictation(text, learn: true, timeout: ArisDictationWait.insertTimeout)
    }
}
