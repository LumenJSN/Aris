//
//  ArisHandoff.swift
//  Aris
//
//  "조사해서 정리해 놔", "끝나면 알려줘": long work handed to Aris runs in the background, so
//  the conversation stays free; Aris says when it's done.
//

import Foundation

enum ArisHandoff {
    private static let handoff = #"(?i)(해\s*놔|해\s*놓아|해\s*둬|해\s*두어|맡길게|맡겨|끝나면\s*알려|다\s*되면\s*알려|백그라운드|in the background|when you'?re done|let me know when|take your time)"#
    /// The "tell me when it's done" part, which isn't part of the task itself.
    private static let tellMe = #"(?i)[,\s]*(끝나면|다\s*되면)\s*알려\s*줘?[.!]*\s*$|[,\s]*(and\s+)?let me know when (you'?re|it'?s) done[.!]*\s*$"#
    private static let longestTitle = 40

    /// A recurring request ("매일 아침 8시에 날씨 알려 줘, 해 둬") is never handed off: the schedule is made in the turn, on
    /// its 예약 추가 card (QA follow-up).
    static func isHandoff(_ text: String) -> Bool {
        text.range(of: handoff, options: .regularExpression) != nil && !ArisIntent.isRecurring(text) && !ArisOwnData.mentions(text)
    }

    /// A short name for the task (shown in the notch, and in the context for "그거 어떻게 됐어?").
    static func title(of text: String) -> String {
        let task = text.replacingOccurrences(of: tellMe, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return task.count > longestTitle ? String(task.prefix(longestTitle)) + "…" : task
    }
}

/// Long work handed to Aris, running in the background.
struct ArisBackgroundTask: Identifiable, Equatable {
    enum State: Equatable {
        /// What the AI is doing ("" until it says).
        case working(String)
        case done(String)
        case failed(String)
    }

    var id = UUID()
    let title: String
    var state = State.working("")

    var isFinished: Bool {
        if case .working = state { return false }
        return true
    }

    /// One line for the AI's context, so "그거 어떻게 됐어?" can be answered.
    var contextLine: String {
        switch state {
        case .working(let status): return status.isEmpty ? "\(title) (working)" : "\(title) (working: \(status))"
        case .done(let answer): return "\(title) (done: \(answer))"
        case .failed(let message): return "\(title) (failed: \(message))"
        }
    }
}

/// The jobs a turn's context names. A finished job's words were written by an untrusted job, so a conversation that
/// hears them is outside text and hands nothing out (the agent reads "(done:" and "(failed:" itself). Those already
/// finished when a conversation ended were reported then and stay out of every later conversation: one finished job no
/// longer keeps dispatch off until Aris restarts (2026-11-07).
enum ArisJobContext {
    /// The context lines, and whether they make the conversation outside text.
    static func lines(_ tasks: [ArisBackgroundTask], putAway: Set<UUID>) -> (lines: [String], outside: Bool) {
        let kept = tasks.filter { !putAway.contains($0.id) }
        return (kept.map(\.contextLine), kept.contains(where: \.isFinished))
    }

    /// At a conversation's end: the finished jobs join the put-away ones; ids of jobs no longer listed are let go.
    static func puttingAway(_ tasks: [ArisBackgroundTask], into putAway: Set<UUID>) -> Set<UUID> {
        putAway.union(tasks.filter(\.isFinished).map(\.id)).intersection(tasks.map(\.id))
    }
}
