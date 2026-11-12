//
//  ArisChunkJudge.swift
//  aris-agent
//
//  Main Aris judging long code in parts (ArisEscalation.judgeChunks): at most a few parts at once, all within one
//  time budget. The answer is yes only when every part said yes (ArisEscalation.combined); any no, a part that
//  didn't answer, or the budget running out is the user's card.
//

import Foundation

final class ArisChunkJudge {
    private let parts: [String]
    private let request: String
    private let environment: [String: String]
    private let done: (ArisJudgement?, String) -> Void
    private let lock = NSLock()
    private var answers: [Int: ArisJudgement] = [:]
    private var reasons: [Int: String] = [:]
    private var next = 0
    private var finished = false

    private init(parts: [String], request: String, environment: [String: String], done: @escaping (ArisJudgement?, String) -> Void) {
        self.parts = parts
        self.request = request
        self.environment = environment
        self.done = done
    }

    /// `done` is called exactly once, on a background queue.
    static func run(parts: [String], request: String, environment: [String: String], budget: TimeInterval,
                    done: @escaping (ArisJudgement?, String) -> Void) {
        let judging = ArisChunkJudge(parts: parts, request: request, environment: environment, done: done)
        guard !parts.isEmpty else { return done(nil, "nothing to judge") }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + budget) { judging.finish(nil, "took too long") }
        for _ in 0..<min(ArisEscalation.judgeParallelism, parts.count) { judging.startNext() }
    }

    private func startNext() {
        let index: Int? = lock.withLock {
            guard !finished, next < parts.count else { return nil }
            next += 1
            return next - 1
        }
        guard let index else { return }
        ArisJudge.judge(action: parts[index], request: request, environment: environment) { [self] judgement, reason in
            let outcome: ArisJudgement?? = lock.withLock {
                answers[index] = judgement
                reasons[index] = reason
                let all = (0..<parts.count).map { answers[$0] }
                let combined = ArisEscalation.combined(all, parts: parts.count)
                // Done on the first no, or once every part said yes.
                return combined == nil ? nil : .some(combined)
            }
            if let outcome { return finish(outcome, reasonText()) }
            startNext()
        }
    }

    private func reasonText() -> String {
        lock.withLock { (0..<parts.count).compactMap { reasons[$0] }.filter { !$0.isEmpty }.joined(separator: " / ") }
    }

    private func finish(_ judgement: ArisJudgement?, _ reason: String) {
        let first = lock.withLock { () -> Bool in
            guard !finished else { return false }
            finished = true
            return true
        }
        if first { done(judgement, reason) }
    }
}
