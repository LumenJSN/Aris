//
//  ArisControlReply.swift
//  Aris
//
//  What Aris says and logs after a spoken volume or brightness change, decided by whether anything really moved. The
//  usual "볼륨 올렸어요" and its 한 일 line (with the undo) come only when it did. When it did not (sound going out over
//  HDMI or DisplayPort, where the Mac has no volume to set; a display with no brightness the Mac can set; a helper
//  that didn't answer) Aris says so and logs nothing. Foundation only (tested).
//

import Foundation

enum ArisControl: Equatable {
    case volume(ArisIntent.Level)
    case brightness(ArisIntent.Level)

    /// The spoken request when it is one of these. "밝기 음소거" is not: it goes to the AI, as before.
    init?(_ intent: ArisIntent) {
        switch intent {
        case .volume(let level): self = .volume(level)
        case .brightness(let level) where level != .mute: self = .brightness(level)
        default: return nil
        }
    }

    /// What Aris says: the usual line when it changed, otherwise that it could not be changed.
    func reply(changed: Bool, korean: Bool) -> String {
        switch self {
        case .volume(let level):
            if changed, let line = ArisIntent.volume(level).acknowledgement(korean: korean) { return line }
            return korean ? "지금 소리가 나가는 기기는 Mac에서 볼륨을 바꿀 수 없어요." : "The Mac can't change the volume of this sound output."
        case .brightness(let level):
            if changed, let line = ArisIntent.brightness(level).acknowledgement(korean: korean) { return line }
            return korean ? "밝기를 바꾸지 못했어요. Mac에서 밝기를 조절할 수 없는 화면일 수 있어요."
                : "I couldn't change the brightness. This display may not let the Mac set it."
        }
    }

    /// 올려 at 100 %, or 내려 with the sound already off: nothing moved, and Aris says where the volume already is.
    static func limitReply(_ limit: ArisVolumeLimit, korean: Bool) -> String {
        switch limit {
        case .top: korean ? "볼륨이 이미 최대예요." : "The volume is already at its highest."
        case .bottom: korean ? "볼륨이 이미 가장 낮아요." : "The volume is already at its lowest."
        }
    }

    /// The 한 일 line, for a volume change that happened (its undo puts the level back); nil when there is nothing to
    /// log or undo.
    func logSummary(changed: Bool) -> String? {
        guard changed, case .volume(let level) = self else { return nil }
        switch level {
        case .up: return "볼륨 올림"
        case .down: return "볼륨 낮춤"
        case .set(let value): return "볼륨 \(value)"
        case .mute: return "음소거 바꿈"
        }
    }

    /// The output's command for a spoken level ("볼륨 40" is 40 %).
    static func volumeCommand(_ level: ArisIntent.Level) -> ArisVolumeCommand {
        switch level {
        case .up: return .up
        case .down: return .down
        case .set(let value): return .set(Float32(value) / 100)
        case .mute: return .toggleMute
        }
    }
}
