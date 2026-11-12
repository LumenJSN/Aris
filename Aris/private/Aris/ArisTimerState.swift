//
//  ArisTimerState.swift
//  Aris
//
//  One timer: running toward `endsAt`, or paused with time left. A pomodoro goes focus (25) → break (5), four
//  rounds, a long break (15) after the fourth, until cancelled. Codable, so a running timer survives the app
//  restarting. Pure: ArisTimerModel does the ticking, sounds and saving.
//

import Foundation

struct ArisTimerState: Codable, Equatable {
    enum Phase: String, Codable { case plain, focus, rest }

    static let focusSeconds = 1_500
    static let shortRest = 300
    static let longRest = 900
    static let rounds = 4

    let phase: Phase
    /// This phase's whole length (grows with "5분 추가").
    let total: Int
    /// When it ends, while running.
    let endsAt: Date?
    /// Seconds left, while paused.
    let pausedLeft: Int?
    /// The pomodoro round (1-4).
    let round: Int
    /// A pomodoro: phases follow one another.
    let cycle: Bool

    static func start(seconds: Int, phase: Phase, at now: Date, round: Int = 1, cycle: Bool = false) -> ArisTimerState {
        ArisTimerState(phase: phase, total: seconds, endsAt: now.addingTimeInterval(TimeInterval(seconds)), pausedLeft: nil,
                       round: round, cycle: cycle)
    }

    var isPaused: Bool { pausedLeft != nil }

    func left(at now: Date) -> Int {
        if let pausedLeft { return pausedLeft }
        return max(0, Int((endsAt ?? now).timeIntervalSince(now).rounded(.up)))
    }

    /// 0...1 of the time gone.
    func progress(at now: Date) -> Double {
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - Double(left(at: now)) / Double(total)))
    }

    func paused(at now: Date) -> ArisTimerState {
        guard !isPaused else { return self }
        return ArisTimerState(phase: phase, total: total, endsAt: nil, pausedLeft: left(at: now), round: round, cycle: cycle)
    }

    func resumed(at now: Date) -> ArisTimerState {
        guard let pausedLeft else { return self }
        return ArisTimerState(phase: phase, total: total, endsAt: now.addingTimeInterval(TimeInterval(pausedLeft)), pausedLeft: nil,
                              round: round, cycle: cycle)
    }

    func adding(_ seconds: Int, at now: Date) -> ArisTimerState {
        if let pausedLeft {
            return ArisTimerState(phase: phase, total: total + seconds, endsAt: nil, pausedLeft: pausedLeft + seconds, round: round, cycle: cycle)
        }
        return ArisTimerState(phase: phase, total: total + seconds, endsAt: (endsAt ?? now).addingTimeInterval(TimeInterval(seconds)),
                              pausedLeft: nil, round: round, cycle: cycle)
    }

    /// What follows when this phase ends: in a pomodoro the break or the next round; otherwise nothing.
    func next(at now: Date) -> ArisTimerState? {
        guard cycle else { return nil }
        switch phase {
        case .focus:
            let rest = round >= Self.rounds ? Self.longRest : Self.shortRest
            return .start(seconds: rest, phase: .rest, at: now, round: round, cycle: true)
        case .rest:
            return .start(seconds: Self.focusSeconds, phase: .focus, at: now, round: round >= Self.rounds ? 1 : round + 1, cycle: true)
        case .plain:
            return nil
        }
    }

    /// "24:13", "0:59", "1:02:05".
    static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3_600, minutes = seconds % 3_600 / 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
