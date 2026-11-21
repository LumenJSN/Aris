//
//  ArisSecondPass.swift
//  Aris (Shared/Core, Foundation only)
//
//  The second listen (ElevenLabs Scribe's commit, or Whisper on the Mac) never holds the turn for more than a small
//  budget: past it the turn goes on with the best words it has (Scribe's live text, else Apple's), and a better
//  transcript that comes later replaces them only while the request has not been sent (ArisLateWords).
//
//  The budgets, from the code they replace: Scribe's commit "usually takes about 0.1 s" and had 2.5 s; 0.6 s is six
//  times the usual and still a quarter of the old wait. Whisper on one window (≤ 30 s of audio) "costs ~0.15 s" when it
//  runs during the pause and had 3 s; 0.8 s covers a cold first read of a short turn. Scribe's own 2.5 s timeout
//  still runs behind the budget, so its health count (ArisCloudHealth) is unchanged.
//

import Foundation

enum ArisSecondPass {
    static let scribeBudget: Duration = .milliseconds(600)
    static let whisperBudget: Duration = .milliseconds(800)

    /// Runs `pass` and waits at most `budget` for it: its result, or nil when the budget ran out first. A result that
    /// comes after the budget goes to `late` instead.
    @MainActor
    static func within<T: Sendable>(_ budget: Duration, _ pass: @escaping @MainActor () async -> T,
                          late: @escaping @MainActor (T) -> Void = { _ in }) async -> T? {
        let race = Race<T>()
        return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            race.waiter = continuation
            race.timer = Task { @MainActor in
                guard (try? await Task.sleep(for: budget)) != nil else { return }
                race.expire()
            }
            Task { @MainActor in
                let result = await pass()
                if !race.finish(result) { late(result) }
            }
        }
    }

    @MainActor
    private final class Race<T: Sendable> {
        var waiter: CheckedContinuation<T?, Never>?
        var timer: Task<Void, Never>?

        /// True when the result came in time.
        func finish(_ result: T) -> Bool {
            guard let waiter else { return false }
            self.waiter = nil
            timer?.cancel()
            waiter.resume(returning: result)
            return true
        }

        func expire() {
            waiter?.resume(returning: nil)
            waiter = nil
        }
    }
}

/// A turn that went on with its fallback words, and a better transcript that came after the budget: it replaces them
/// only if the request has not been sent yet.
struct ArisLateWords: Equatable, Sendable {
    /// The words the turn went on with (after the same clean-up every transcript gets).
    private(set) var fallback: String?
    private(set) var better: String?
    private(set) var sent = false

    /// The turn went on with `words` because the second listen was late.
    mutating func wentOn(with words: String) {
        fallback = words
        better = nil
        sent = false
    }

    /// The late transcript came (cleaned up). True when it is kept (the request is still unsent and it differs).
    @discardableResult
    mutating func arrived(_ words: String) -> Bool {
        guard !sent, let fallback, !words.isEmpty, words != fallback else { return false }
        better = words
        return true
    }

    /// The request is going out with `words`: the better transcript when one came for exactly these words, else
    /// `words`. From here on a late transcript is ignored.
    mutating func send(_ words: String) -> String {
        defer { sent = true }
        guard !sent, let fallback, let better, words == fallback else { return words }
        return better
    }
}
