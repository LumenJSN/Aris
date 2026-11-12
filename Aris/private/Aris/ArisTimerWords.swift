//
//  ArisTimerWords.swift
//  Aris
//
//  What Aris announces and says when a timer ends, in the UI's language (VM run, bug 4): nobody asked just then, so
//  there is no request whose language it could follow. Foundation only (tested).
//

import Foundation

enum ArisTimerWords {
    /// The announcement's title and its line. `total`: the length that just ended; `nextTotal`, `nextRound`: what
    /// starts now in a pomodoro.
    static func ended(_ phase: ArisTimerState.Phase, cycle: Bool, round: Int, total: Int, nextTotal: Int, nextRound: Int,
                      english: Bool = ArisUIWords.english, locale: Locale? = nil) -> (title: String, text: String) {
        if english {
            let length = ArisUIDates.lengthInWords(seconds: total, locale: locale)
            switch phase {
            case .plain: return ("Timer", "\(length) is up.")
            case .focus where cycle: return ("Pomodoro", "Focus round \(round) is done. Rest for \(ArisUIDates.lengthInWords(seconds: nextTotal, locale: locale)).")
            case .focus: return ("Focus", "\(length) of focus is done. Take a short break.")
            case .rest: return ("Pomodoro", "The break is over. Starting focus round \(nextRound).")
            }
        }
        let length = ArisIntent.duration(total)
        switch phase {
        case .plain: return ("타이머", "\(length) 끝났어요.")
        case .focus where cycle: return ("뽀모도로", "\(round)번째 집중 끝. \(ArisIntent.duration(nextTotal)) 쉬어요.")
        case .focus: return ("집중", "\(length) 집중 끝났어요. 잠깐 쉬어요.")
        case .rest: return ("뽀모도로", "쉬는 시간 끝. \(nextRound)번째 집중 시작할게요.")
        }
    }
}
