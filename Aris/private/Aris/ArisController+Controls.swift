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
        switch control {
        case .volume(let asked):
            let volume = ArisVolume.shared
            let before = volume.currentLevel()
            // A relative change ("10 줄여", "조금", "반으로") is sent as the level it comes to from the level now.
            let level = before.flatMap { ArisControl.target(asked, current: $0, step: Self.volumeStepPoints) }.map(ArisIntent.Level.set) ?? asked
            let outcome = volume.act(ArisControl.volumeCommand(level))
            if let limit = outcome.limit { return ArisControl.limitReply(limit, korean: korean) }
            let changed = outcome == .changed
            if let summary = control.logSummary(changed: changed) {
                ArisAgentClient.logLocalChange(kind: "volume", summary: summary, level: before)
            }
            let after: Int? = level == .mute || !changed ? nil : Self.levelAfter(level, before: before)
            return control.reply(changed: changed, korean: korean, level: after, muted: asked == .mute ? volume.isMutedNow() : nil)
        case .brightness(let asked):
            let brightness = ArisBrightness.shared
            let changed: Bool
            var after: Int?
            switch asked {
            case .up: changed = await brightness.change(by: ArisBrightness.step)
            case .down: changed = await brightness.change(by: -ArisBrightness.step)
            case .set(let value): changed = await brightness.change(to: Float(value) / 100)
            case .mute: changed = false
            case .change(let change):
                // From the level now, read with a step of nothing; without it, a step that way.
                if let now = await ArisHelperClient.shared.adjustScreenBrightness(by: 0) {
                    let target = change.target(from: Int((now * 100).rounded()), step: Int(ArisBrightness.step * 100))
                    changed = await brightness.change(to: Float(target) / 100)
                    after = target
                } else {
                    changed = await brightness.change(by: ArisControl.goesUp(asked) == false ? -ArisBrightness.step : ArisBrightness.step)
                }
            }
            return control.reply(changed: changed, korean: korean, level: after)
        }
    }

    /// The volume's step in points (ArisVolumeRules: 1/16).
    static let volumeStepPoints = Int((ArisVolumeRules.step * 100).rounded())

    /// The level after a volume change, as far as it is known here: the set level, or the level now once the step went.
    private static func levelAfter(_ level: ArisIntent.Level, before: Int?) -> Int {
        if case .set(let value) = level { return value }
        return ArisVolume.shared.currentLevel() ?? before ?? 0
    }
}
