//
//  ArisConfirmReply.swift
//  Aris
//
//  Yes or no, out loud, to something the AI wants to do (send, delete, run a command).
//  "No" is checked first, so "안 해" or "보내지 마" never counts as yes; anything unclear
//  isn't an answer yet.
//

import Foundation

enum ArisConfirmReply {
    /// The words are ArisAnswerWords' (Shared/Core), so the trust policy's cards read answers the same way.
    /// The whole utterance must be a short yes (security review I2): one or two of its yes words, a polite 요, nothing
    /// else, so a sentence that merely starts with "네" or has "ok" in it is no answer. A lone "어" or "음" is someone
    /// thinking, not agreeing: it only leads into a yes ("어 그래").
    static func parse(_ text: String) -> Bool? { ArisAnswerWords.answer(text) }

    /// Whether a spoken yes may count. Always, since 2026-11-15 (the owner: cards answered by voice, "응", "보내", "아니"): the
    /// conversation rule and the hands-free one (security review C1, N3) are gone; the card, its hold and the gate stay.
    static func voiceYes(inConversation: Bool, handsFree: Bool) -> Bool { true }

    /// What a spoken answer counts as: a no always; a yes only when `voiceYes`.
    static func spoken(_ text: String, voiceYes: Bool) -> Bool? {
        let answer = parse(text)
        return !voiceYes && answer == true ? nil : answer
    }

    /// What Aris says when it asks; when a spoken yes won't count, how to say yes.
    /// `english`: the card is drawn in English (ArisCardEnglish.isEnglish, by the request); nil reads it off the card.
    /// `job`: the background task the card is for (its title): the question says which task needs it.
    static func question(for ask: ArisConfirmation, voiceYes: Bool, english: Bool? = nil, job: String? = nil) -> String {
        // The automatic check's stopped card asks nothing: it says that it stopped (ArisStoppedCard).
        if ask.stopped { return ArisStoppedCopy.spoken(ask.title, english: english ?? isEnglish(ask)) }
        guard !voiceYes else { return question(for: ask, english: english, job: job) }
        // The button is named as the card draws it.
        return question(for: ask, english: english, job: job) + (english ?? isEnglish(ask) ? " To allow it, press Allow or the Y key." : " 허락하시려면 허용을 누르거나 Y를 눌러 주세요.")
    }

    /// The card came written in English: its title has words and none of them Korean (the agent writes its computer
    /// use and schedule cards in the request's language).
    static func isEnglish(_ ask: ArisConfirmation) -> Bool {
        !ask.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !ask.title.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }

    /// How long a dictated message waits before it goes out (the confirm card's ring, ArisCountdown).
    static let countdownSeconds = 3

    /// During a countdown: false stops it ("취소", esc), true sends at once (a yes, the button), nil keeps counting
    /// (and once it runs out, `countdownEnd` decides: only silence or a clear yes sends).
    static func countdown(typed: Bool?, heard: String) -> Bool? {
        typed ?? parse(heard)
    }

    /// The final words heard during a countdown, as its decision reads them (ArisCountdownStep).
    static func countdownWords(_ final: String) -> ArisCountdownStep.Words {
        ArisCountdownStep.Words(answer: parse(final), said: saidWords(final))
    }

    /// How a countdown that ran its ring out ends, from the final words heard during it: silence sends (as designed), a
    /// clear yes sends, a clear no stops, and anything else ("잠깐만", "wait", a sentence) pauses it with the card kept.
    static func countdownEnd(final: String) -> ArisCountdownStep {
        ArisCountdownStep.decide(outcome: nil, said: nil, paused: false, final: countdownWords(final), current: true) ?? .send
    }

    /// Words heard mid-countdown that are no clear yes or no and held still as long as a yes must: the ring stops at
    /// once (the card stays for a click), never running out into a send.
    static func countdownPauses(_ heard: String, heldFor seconds: Double) -> Bool {
        parse(heard) == nil && saidWords(heard) && seconds >= ArisSpokenAnswer.stableFor
    }

    /// Any letter or digit: a word was heard (a lone "음" counts; silence and noise don't).
    static func saidWords(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
    }

    /// The most characters of a question said aloud (2026-11-19, the owner's say: a card's question took about four
    /// seconds to read). The whole is on the card.
    static let questionLimit = 60
    /// How much of a card's title, and of a task's name, is said.
    static let titleLimit = 40
    static let jobLimit = 16

    /// What Aris says out loud, short: the action in a few words and "할까요?"; the exact details are on screen. The
    /// card's title leads with what is done (보내기, 지우기, 결제, 글 바꾸기), so a cut title still says it; a card that
    /// came with its own short question in the card's language (a taught run's: "…지워져요. 할까요?") is asked in those words.
    static func question(for ask: ArisConfirmation, english: Bool? = nil, job: String? = nil) -> String {
        let inEnglish = english ?? isEnglish(ask)
        let title = clipped(inEnglish ? ArisCardEnglish.title(ask.title) : ask.title, titleLimit)
        // "앞으로 이건 그냥 할까?" is a question already.
        if ask.proposal { return title }
        // A background task's card: which task needs what, in one sentence.
        if let job = job?.trimmingCharacters(in: .whitespacesAndNewlines), !job.isEmpty {
            let name = clipped(job, jobLimit)
            return inEnglish ? "The “\(name)” task needs your OK to \(title.prefix(1).lowercased() + title.dropFirst())." : "‘\(name)’ 작업에서 \(title), 해도 될지 물어봐요."
        }
        if !ask.countdown, let own = ask.spoken?.trimmingCharacters(in: .whitespacesAndNewlines), !own.isEmpty, own.count <= questionLimit,
           hasHangul(own) != inEnglish {
            return own
        }
        // A title that asks already ("‘출근 준비’ 배울까요? (4단계)") is the question, without a bracketed note after it.
        if let asks = asked(title) { return asks }
        return inEnglish ? "\(title). Go ahead?" : "\(title), 할까요?"
    }

    /// A title that is a question already, up to its question mark: one that ends there, or has only a bracketed note
    /// after it. Nil for any other (words after the mark may be what the card is about).
    static func asked(_ title: String) -> String? {
        guard let mark = title.lastIndex(of: "?") else { return nil }
        let rest = title[title.index(after: mark)...].trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || (rest.hasPrefix("(") && rest.hasSuffix(")") && rest.dropFirst().dropLast().allSatisfy { $0 != "(" && $0 != ")" }) else { return nil }
        return String(title[...mark])
    }

    /// `text` in at most `limit` characters, the "…" counted.
    static func clipped(_ text: String, _ limit: Int) -> String {
        text.count > limit ? text.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    /// Whether a sentence is Korean, by its own words: a name it quotes (“전체 바꾸기”, ‘보내기’) is not its language.
    static func hasHangul(_ text: String) -> Bool {
        var own = "", closing: Character?
        for character in text {
            if let end = closing {
                if character == end { closing = nil }
            } else if character == "“" || character == "‘" {
                closing = character == "“" ? "”" : "’"
            } else {
                own.append(character)
            }
        }
        return own.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    }
}

/// A spoken yes or no as the recognizer writes it (security review N3): a no counts at once, but a yes only once its
/// words held still for `stableFor` (a streaming "네" can still grow into "네 근데 그거 말고"), or from the final
/// transcript (ArisConfirmReply.spoken).
struct ArisSpokenAnswer: Equatable {
    static let stableFor: Double = 0.6

    private(set) var text = ""
    private(set) var since: Double = 0

    /// The recognizer's text now; `now` in seconds.
    func heard(_ text: String, at now: Double) -> ArisSpokenAnswer {
        guard text != self.text else { return self }
        return ArisSpokenAnswer(text: text, since: now)
    }

    func answer(at now: Double, voiceYes: Bool) -> Bool? {
        guard let parsed = ArisConfirmReply.parse(text) else { return nil }
        guard parsed else { return false }
        return voiceYes && now - since >= Self.stableFor ? true : nil
    }
}
