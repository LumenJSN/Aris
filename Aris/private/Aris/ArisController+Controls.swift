//
//  ArisController+Controls.swift
//  Aris
//
//  A spoken volume or brightness change, done and answered: Aris waits to hear whether anything really moved, and
//  what it says and logs follows that (ArisControlReply), never the request alone.
//

import Foundation

extension ArisController {
    /// Does the change and returns what to say. A volume change that happened is logged with the level before, so
    /// "방금 한 거 되돌려" puts it back; one that didn't is not logged.
    func performControl(_ control: ArisControl, korean: Bool) async -> String {
        let changed: Bool
        switch control {
        case .volume(let level):
            let volume = ArisVolume.shared
            let before = volume.currentLevel()
            let outcome = volume.act(ArisControl.volumeCommand(level))
            if let limit = outcome.limit { return ArisControl.limitReply(limit, korean: korean) }
            changed = outcome == .changed
            if let summary = control.logSummary(changed: changed) {
                ArisAgentClient.logLocalChange(kind: "volume", summary: summary, level: before)
            }
        case .brightness(let level):
            let brightness = ArisBrightness.shared
            switch level {
            case .up: changed = await brightness.change(by: ArisBrightness.step)
            case .down: changed = await brightness.change(by: -ArisBrightness.step)
            case .set(let value): changed = await brightness.change(to: Float(value) / 100)
            case .mute: changed = false
            }
        }
        return control.reply(changed: changed, korean: korean)
    }
}
