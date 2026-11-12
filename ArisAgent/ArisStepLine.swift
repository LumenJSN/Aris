//
//  ArisStepLine.swift
//  aris-agent
//
//  A status line that says which step of how many ("카카오톡에서 누르는 중… · 2/4"), for work that really knows both
//  numbers: the notch's tag then shows "2/4" beside its words (the app's ArisTagProgress reads this ending; the two
//  programs share no file for it, and the tests hold them to the same form). Only code that counted the steps itself
//  calls this (a desktop batch: its steps are on the user's card). A brain's own guess at its progress never goes here.
//

import Foundation

enum ArisStepLine {
    /// A step of counted work, counted from zero.
    struct Step: Equatable {
        let index: Int
        let of: Int
    }

    /// The app keeps this much of a line (ArisAgentReply.parse).
    static let limit = 80
    /// The app shows a count for 2 to 99 steps (ArisTagProgress.mostSteps).
    private static let mostSteps = 99

    /// `line` with its count; `line` alone for a single step or numbers that aren't a real count. Long words are cut
    /// before the count, never through it.
    static func counted(_ line: String, step: Int, of total: Int) -> String {
        guard (2...mostSteps).contains(total), (1...total).contains(step) else { return line }
        let ending = " · \(step)/\(total)"
        return String(line.prefix(limit - ending.count)) + ending
    }

    static func counted(_ line: String, step: Step?) -> String {
        step.map { counted(line, step: $0.index + 1, of: $0.of) } ?? line
    }
}

extension ArisOperatingTarget {
    /// The same window, its line saying which step of a batch this is; unchanged for a single call.
    func counted(_ step: ArisStepLine.Step?) -> ArisOperatingTarget {
        ArisOperatingTarget(app: app, pid: pid, window: window, line: ArisStepLine.counted(line, step: step))
    }
}
