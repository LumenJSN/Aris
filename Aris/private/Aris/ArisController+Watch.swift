//
//  ArisController+Watch.swift
//  Aris
//
//  The net under every turn (ArisTurnWatch): when a turn's task ends by itself and the notch is still "생각 중" or
//  "말하는 중" with no card and nothing touching it, no code is left that would ever end that state, so the wake
//  word, job results and cards would wait for the next key press. It is put back to idle, and logged as the defect it is.
//

import Foundation
import os

private let log = Logger(subsystem: "com.lumenjsn.aris", category: "turn")

extension ArisController {
    /// Called with every new turn task: looks at the notch once that task has ended.
    func watchTurnEnd(_ task: Task<Void, Never>?) {
        // The preview harness sets the notch by hand, with no turn behind it.
        guard let task, !silentSpeech else { return }
        Task { @MainActor [weak self] in
            await task.value
            guard let self else { return }
            let busy = { @MainActor in self.session.phase == .thinking || self.session.phase == .speaking }
            guard ArisTurnWatch.mayBeLeftBehind(busy: busy(), asking: self.session.question != nil, stopped: task.isCancelled,
                                                replaced: self.turn != task) else { return }
            let left = self.session
            try? await Task.sleep(for: ArisTurnWatch.patience)
            guard ArisTurnWatch.isLeftBehind(busy: busy(), asking: self.session.question != nil, stopped: task.isCancelled,
                                             replaced: self.turn != task, untouched: self.session == left) else { return }
            log.error("a turn ended and left the notch \(self.session.phase == .thinking ? "thinking" : "speaking", privacy: .public): back to idle")
            self.finishTurn("left")
            self.dropPendingAnswer()
            self.session = self.session.done()
            self.resumeMusicIfPaused()
        }
    }
}
