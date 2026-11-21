//
//  ArisCardJudge.swift
//  Aris
//
//  One listening card's questions to the fast model (ArisCardIntent): the card's loop calls `step` every turn; words
//  that held still and that the word rules call no answer are asked about once, off the loop, with a time limit, and
//  the reading comes back on a later turn, only for words that still stand. No verdict in time, an error, or anything
//  the guards refuse is "no answer": the card goes on exactly as without a model. One log line per reading, without
//  the words. The asker is handed in, so the tests drive it with recorded replies.
//

import Foundation

@MainActor
final class ArisCardJudge {
    /// Asks the model: its verdict, nil when it gave none that can be read; throws `ArisCardIntent.NoModel` when there
    /// is no model to ask.
    typealias Ask = @MainActor (ArisCardIntent.Question) async throws -> ArisCardIntent.Verdict?

    private(set) var wait = ArisCardIntentWait()
    private let card: ArisCardIntent.Card
    private let ask: Ask
    private let limit: Duration
    private let note: (String) -> Void
    private var finished: ArisCardIntent.Reading?
    private var request: Task<Void, Never>?

    init(card: ArisCardIntent.Card, limit: Duration = .milliseconds(Int(ArisCardIntent.timeoutSeconds * 1000)), note: @escaping (String) -> Void = { _ in },
         ask: @escaping Ask) {
        self.card = card
        self.limit = limit
        self.note = note
        self.ask = ask
    }

    /// A request is out and has been long enough for the card to say "one moment".
    func showsThinking(at now: Double) -> Bool { wait.showsThinking(at: now) }

    /// One turn of the card's loop: a reading that came back for the words still standing, else nil (and words that
    /// just settled are asked about).
    func step(_ heard: ArisCardListening, at now: Double) -> ArisCardIntent.Reading? {
        if let reading = finished {
            finished = nil
            let ended = wait.answered(reading, heard: heard)
            wait = ended.wait
            return ended.reading
        }
        guard let words = wait.next(heard, at: now), let question = ArisCardIntent.question(reply: words, card: card) else { return nil }
        wait = wait.asking(words, at: now)
        let started = ContinuousClock.now
        request = Task { [weak self, ask, card, limit] in
            let verdict: ArisCardIntent.Verdict?
            do {
                verdict = try await ArisDeadline.within(limit) { try await ask(question) }
            } catch is ArisCardIntent.NoModel {
                self?.noModel()
                return
            } catch {
                // Too slow, an error, a stopped card: no verdict.
                verdict = nil
            }
            guard let self, !Task.isCancelled else { return }
            let reading = ArisCardIntent.reading(reply: words, verdict: verdict, card: card)
            self.note(ArisCardIntent.logLine(reading, milliseconds: Int((ContinuousClock.now - started) / .milliseconds(1)), source: .model))
            self.finished = reading
        }
        return nil
    }

    /// Whether the microphone stays open a little past the listening window (ArisCardIntentWait.keeping).
    func keeps(_ heard: ArisCardListening, at now: Double, remaining: Double) -> Bool {
        let kept = wait.keeping(heard, at: now, remaining: remaining)
        wait = kept.wait
        return kept.keeps
    }

    /// The card is done listening: a request still out is dropped.
    func stop() {
        request?.cancel()
        request = nil
    }

    private func noModel() { wait = wait.switchedOff() }
}
