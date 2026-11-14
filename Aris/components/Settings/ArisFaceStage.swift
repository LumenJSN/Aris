//
//  ArisFaceStage.swift
//  Aris
//
//  What the 팀원 page's 미리보기 strip shows (ArisFaceStageView): which of Aris's three modes is on, the band's size in
//  each, the line under it, and the listening bars' levels (the measured waveform: 4 bars, 2–17 tall, a step every
//  58 ms). Foundation only (tested).
//

import Foundation

/// The 팀원 page's 미리보기 strip (the owner's "Settings A", mockups/face/sa.html): Aris's face at rest beside the camera,
/// listening in the widened band, and working in the pill under the notch, in turn (자동) or held on one. 모션 줄이기
/// holds 자동 at rest.
enum ArisFaceStage {
    enum Mode: CaseIterable, Equatable { case rest, listen, work }

    enum Pin: String, CaseIterable, Equatable {
        case auto, rest, listen, work

        var title: String {
            switch self {
            case .auto: ArisTeamCopy.faceStageAuto
            case .rest: ArisTeamCopy.faceStageRest
            case .listen: ArisTeamCopy.faceStageListen
            case .work: ArisTeamCopy.faceStageWork
            }
        }
    }

    /// Each mode's time on 자동.
    static let interval = 2.2
    /// The working pill's line.
    static var workLine: String { ArisTeamCopy.faceStageWorkLine }

    static func next(_ mode: Mode) -> Mode {
        let all = Mode.allCases
        return all[(all.firstIndex(of: mode)! + 1) % all.count]
    }

    /// What shows `tick` intervals into 자동, or the pinned mode.
    static func mode(pin: Pin, tick: Int, reduced: Bool = false) -> Mode {
        switch pin {
        case .auto: reduced ? .rest : Mode.allCases[((tick % 3) + 3) % 3]
        case .rest: .rest
        case .listen: .listen
        case .work: .work
        }
    }

    static func caption(_ mode: Mode) -> String {
        switch mode {
        case .rest: ArisTeamCopy.faceStageRestCaption
        case .listen: ArisTeamCopy.faceStageListenCaption
        case .work: ArisTeamCopy.faceStageWorkCaption
        }
    }

    /// The band: the closed notch's 150 × 29 (r10), widened to the measured listening 270 × 32 (r13).
    static func notchWidth(_ mode: Mode) -> Double { mode == .listen ? 270 : 150 }
    static func notchHeight(_ mode: Mode) -> Double { mode == .listen ? 32 : 29 }
    static func notchRadius(_ mode: Mode) -> Double { mode == .listen ? 13 : 10 }
}

/// The listening bars' levels in the 미리보기 strip: a voice-like height per bar for each 58 ms step, the same every time.
enum ArisFaceStageWave {
    static let tick = 0.058

    /// Four heights, 2–17 points, for `tick`: a slow swell times a hashed flicker.
    static func heights(tick: Int) -> [Double] {
        (0..<4).map { n in
            let swell = 0.35 + 0.6 * abs(sin(Double(tick) * 0.058 / 0.26 + Double(n) * 1.3))
            let level = min(1, max(0, swell * noise(tick &* 4 &+ n)))
            return ((2 + 15 * level) * 10).rounded() / 10
        }
    }

    /// 0…1 from an integer, deterministic (a small integer hash).
    private static func noise(_ x: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Double(h % 10_000) / 10_000
    }
}
