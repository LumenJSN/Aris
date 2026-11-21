//
//  ArisAnswerWords.swift
//  Shared/Core (Aris, aris-agent, tests)
//
//  The yes and no words a spoken answer to a card is read by: ArisConfirmReply's own lists (the countdown and every
//  card), kept here so the trust policy's asks read answers with the very same words. `no` and `yes` are exactly the
//  card's (unchanged); `negation` adds the forms that make "yes, always" fail closed (안, 말고, 싫어, never, not):
//  a sentence with any of them is never consent. Pure.
//

import Foundation

enum ArisAnswerWords {
    /// A no anywhere in the utterance (ArisConfirmReply.parse checks it first).
    static let no = #"(?i)(아니|취소|하지\s*마|그만|안\s*돼|안\s*해|지\s*마|멈춰|\bno\b|\bnope\b|\bnah\b|\bcancel\b|\bdon'?t\b|\bstop\b|\bnever\s*mind\b|\bnevermind\b|\bnot now\b)"#
    /// One short yes word (ArisConfirmReply.yes is one or two of these and nothing else).
    static let yesWord = #"(네|응|예|그래|좋아|해\s*줘|보내(\s*줘)?|오케이|yes|yeah|yep|yup|ok|okay|sure|alright|all right|go ahead|do it|send it|send)(요)?"#
    /// The natural short answers to "실행할까요?" / "Run it?" and to the card's 허용 button ("실행해", "허용", "진행해 줘",
    /// "해", "그렇게 해", "해도 돼", "run it", "allow it"), with the spacing the Korean recognizer writes ("실행 해"). They
    /// count only as the whole utterance (`yes`); they are not part of `affirmative`, which looks inside a sentence
    /// ("해" is in almost every Korean one).
    static let goWord = #"(실행\s*해(\s*(줘|주세요))?|허용(\s*해(\s*(줘|주세요))?|이요)?|진행\s*해(\s*(줘|주세요))?|그렇게\s*해(\s*(줘|주세요))?|해도\s*돼|해(\s*주세요)?|응응|네네|run it|allow( it)?|proceed|go for it|yes please|please do)(요)?"#
    private static let shortYes = "(" + yesWord + "|" + goWord + ")"
    static let yes = "(?i)^\\s*((어|음)[\\s,.…]+)?" + shortYes + "([\\s,.!~]+" + shortYes + ")?[\\s,.!~]*$"
    /// Every negation, for consent that must fail closed: the card's no words and 안, 말고, 싫어, 않, never, not, n't.
    static let negation = no + #"|(?i)((^|\s)안(\s|$)|안\s|말고|싫어|싫다|않|\bnever\b|\bnot\b|n't\b|\bnone\b)"#
    /// A phrase a negation makes: the word it negates goes with it ("보내지 마", "안 보내", "don't send", "not now").
    static let negatedPhrase = #"(?i)(\S*지\s*(마|말고|않\S*)|안\s*\S+|\bdon'?t\s+\S+|\bnot\s+\S+|\bnever\s+\S+)"#
    /// "Don't ask" said as consent ("앞으로 묻지 마", "don't ask me again"): taken out before negation is looked for.
    static let consentIdioms = #"(?i)(묻지\s*(마|말고|않아도)|물어보지\s*(마|말고|않아도)|확인\s*안\s*해도|don'?t\s+ask(\s+me)?(\s+again)?|no need to ask)"#
    /// Words that make a yes standing.
    static let always = #"(?i)(앞으로|항상|매번|언제나|계속|from now on|always|every time|each time|묻지\s*(마|말고)|물어보지\s*(마|말고)|don'?t\s+ask|no need to ask)"#
    /// An affirmative inside a longer sentence ("앞으로도 그렇게 해", "yes, always").
    static let affirmative = "(?i)(" + yesWord + #"|그렇게\s*해|해도\s*돼|해\s*줘|해줘|보내도\s*돼|ok|좋아요?|do that|go ahead|that's fine|fine)"#

    /// A card's answer from words: a no anywhere wins, then the whole utterance as a short yes; nil is no answer.
    static func answer(_ text: String) -> Bool? {
        if matches(text, no) { return false }
        return matches(text, yes) ? true : nil
    }

    static func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
}
