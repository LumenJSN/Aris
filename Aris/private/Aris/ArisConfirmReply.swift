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
    private static let no = #"(?i)(아니|취소|하지\s*마|그만|안\s*돼|안\s*해|지\s*마|멈춰|\bno\b|\bnope\b|\bcancel\b|\bdon'?t\b|\bstop\b)"#
    /// The whole utterance must be a short yes (security review I2): one or two of these, a polite 요, nothing else, so
    /// a sentence that merely starts with "네" or has "ok" in it is no answer. A lone "어" or "음" is someone thinking,
    /// not agreeing: it only leads into a yes ("어 그래").
    private static let yesWord = #"(네|응|예|그래|좋아|해\s*줘|오케이|yes|yeah|ok|okay|sure)(요)?"#
    private static let yes = "(?i)^\\s*((어|음)[\\s,.…]+)?" + yesWord + "([\\s,.!~]+" + yesWord + ")?[\\s,.!~]*$"

    static func parse(_ text: String) -> Bool? {
        if text.range(of: no, options: .regularExpression) != nil { return false }
        if text.range(of: yes, options: .regularExpression) != nil { return true }
        return nil
    }

    /// Whether a spoken yes may count (security review C1, N3): not in a conversation (the microphone hears more than
    /// The user), and never for a card from a hands-free turn or its job, whatever the session; then only a click or Y.
    static func voiceYes(inConversation: Bool, handsFree: Bool) -> Bool { !inConversation && !handsFree }

    /// What a spoken answer counts as: a no always; a yes only when `voiceYes`.
    static func spoken(_ text: String, voiceYes: Bool) -> Bool? {
        let answer = parse(text)
        return !voiceYes && answer == true ? nil : answer
    }

    /// What Aris says when it asks; when a spoken yes won't count, how to say yes.
    /// `english`: the card is drawn in English (ArisCardEnglish.isEnglish, by the request); nil reads it off the card.
    static func question(for ask: ArisConfirmation, voiceYes: Bool, english: Bool? = nil) -> String {
        // The automatic check's stopped card asks nothing: it says that it stopped (ArisStoppedCard).
        if ask.stopped { return ArisStoppedCopy.spoken(ask.title, english: english ?? isEnglish(ask)) }
        guard !voiceYes else { return question(for: ask, english: english) }
        // The button is named as the card draws it.
        return question(for: ask, english: english) + (english ?? isEnglish(ask) ? " To allow it, press Allow or the Y key." : " 허락하시려면 허용을 누르거나 Y를 눌러 주세요.")
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
    /// (and once it runs out, the message goes).
    static func countdown(typed: Bool?, heard: String) -> Bool? {
        typed ?? parse(heard)
    }

    /// What Aris says out loud; the exact details are on screen.
    static func question(for ask: ArisConfirmation, english: Bool? = nil) -> String {
        let inEnglish = english ?? isEnglish(ask)
        let title = inEnglish ? ArisCardEnglish.title(ask.title) : ask.title
        // "앞으로 이건 그냥 할까?" is a question already.
        if ask.proposal { return title }
        return inEnglish ? "\(title). Shall I go ahead?" : "\(title), 해도 될까요?"
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
