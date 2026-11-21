//
//  ArisVoiceDecisions.swift
//  Shared/Core (app, tests)
//
//  What a voice match changes (F1). Each rule degrades to today's behaviour when the match is unsure, and none of them
//  ignores the owner without a way back:
//  - The wake word: a wake-word turn (or a conversation's follow-up heard without the key) whose voice is clearly not
//    the owner's closes quietly before its request runs, as a turn that wasn't Aris's does today (ArisWakeEvidence),
//    and a one-line notice (at most every `noticeEvery`) says the talk key always works. A call repeated within
//    `secondChanceSeconds` of such a close gets a second chance only when its voice is near the print (within
//    `secondChanceMargin` under the not-owner line): a misheard owner is heard on his second try, a clearly different
//    voice is not let through by repeating itself. Unsure or the owner: the turn goes on as today.
//  - No usable audio while a print is enrolled and the switch is on is `unsure` (the turn is unverified for the trust
//    table), never "nothing checked".
//  - A request sent before the turn is over (the speculative turn) goes only when the voice so far is the owner's, and
//    the turn takes it only when the final check gives the same owner-or-not (`sameTag`), so no request leaves with a
//    stronger speaker than the turn's final one.
//  - A spoken yes on a card: refused only when the voice is clearly not the owner's; the card then stays up for a
//    click, Y or a held-key answer, and Aris says why. A spoken no always counts (stopping is never refused).
//  - The turn's speaker for the trust table (ArisTurnSpeaker): key held or typed is the owner; a hands-free turn is the
//    owner only when the voice matched; unsure counts like content (it asks before anything outward or permanent).
//  - Learning: only an utterance made while the key was held (or in the enrolment sheet) moves the print, and only
//    when it has enough voice and is not clearly someone else (a video playing while the key is held).
//  With the check off or no print, every rule here answers as today. Pure.
//

import Foundation

/// How a turn's words came in.
enum ArisTurnEntry: String, Equatable, Sendable {
    case typed
    /// The talk key held down for the whole turn.
    case keyHeld
    /// The talk key tapped: Aris listened until a pause.
    case tapped
    /// The wake word started it.
    case wakeWord
    /// A conversation's next turn, heard without the key or the name.
    case followUp
}

enum ArisVoiceDecisions {
    /// A call repeated this soon after a voice close may get a second chance (ArisWakeDoubt's), when it is near the print:
    /// at most this far under the not-owner line (long: 0.32...0.40, short: 0.30...0.38).
    static let secondChanceSeconds = 8.0
    static let secondChanceMargin: Float = 0.08
    /// The notice that a turn was closed for its voice comes at most this often.
    static let noticeEvery = 600.0

    /// Whether the voice is checked for this entry at all: never for typed words or a held key.
    static func checks(_ entry: ArisTurnEntry) -> Bool {
        switch entry {
        case .typed, .keyHeld: false
        case .tapped, .wakeWord, .followUp: true
        }
    }

    // MARK: - The wake word

    enum Wake: Equatable {
        case goOn
        /// Close the turn quietly: the voice was clearly not the owner's.
        case closeNotOwner
    }

    /// A turn heard without the key, at its end before the request runs. `lastClose`: when a turn last closed for its
    /// voice (seconds, the same clock as `now`).
    static func wake(_ match: ArisVoiceMatch?, entry: ArisTurnEntry, lastClose: Double?, now: Double) -> Wake {
        guard entry == .wakeWord || entry == .followUp, let match, match.verdict == .notOwner else { return .goOn }
        if let lastClose, now >= lastClose, now - lastClose <= secondChanceSeconds, nearPrint(match) { return .goOn }
        return .closeNotOwner
    }

    /// A not-owner verdict close to the line, where a misheard owner may land (a cold, a far microphone).
    static func nearPrint(_ match: ArisVoiceMatch) -> Bool {
        guard let score = match.score else { return false }
        return score >= ArisVoiceMatcher.lines(seconds: match.seconds).other - secondChanceMargin
    }

    /// Whether the notice may come now (`last`: when it last came; seconds on the same clock as `now`).
    static func noticeDue(last: Double?, now: Double) -> Bool {
        guard let last, now >= last else { return true }
        return now - last >= noticeEvery
    }

    /// The notice: why Aris didn't listen, and that the key always works (Korean first).
    static func closedLine(english: Bool) -> String {
        english ? "That didn't sound like your voice, so I didn't listen. Hold the shortcut and talk: that always works."
            : "목소리가 달라서 듣지 않았어요. 단축키를 누른 채 말하면 언제든 들어요."
    }

    // MARK: - No audio, and the early request

    /// A turn with no usable audio: unsure when a print is enrolled and the switch is on (and the entry is checked);
    /// nothing checked otherwise, as today.
    static func noAudio(on: Bool, enrolled: Bool, entry: ArisTurnEntry) -> ArisVoiceMatch? {
        on && enrolled && checks(entry) ? .unsure("no-audio") : nil
    }

    /// Whether a request may go before the turn is over: only for the owner's voice (nil: nothing checked, as today).
    static func early(_ match: ArisVoiceMatch?) -> Bool { match.map { $0.verdict == .owner } ?? true }

    /// What an early request and the turn's own must agree on: whether the speaker counts as the owner (nil: nothing
    /// noted, the owner as today).
    static func ownerTag(_ speaker: ArisTurnSpeaker?) -> Bool { speaker?.countsAsOwner ?? true }

    static func sameTag(early: ArisTurnSpeaker?, final: ArisTurnSpeaker?) -> Bool { ownerTag(early) == ownerTag(final) }

    // MARK: - A spoken yes

    /// Whether a spoken yes counts: always, unless the voice was clearly not the owner's.
    static func yesCounts(_ match: ArisVoiceMatch?) -> Bool { match?.verdict != .notOwner }

    /// What Aris says when it did not take a spoken yes (Korean first).
    static func yesRefusedLine(english: Bool) -> String {
        english ? "That didn't sound like your voice, so I didn't take the yes. Press Allow or Y if you meant it."
            : "목소리가 달라서 ‘네’로 받지 않았어요. 맞으면 허용이나 Y를 눌러 주세요."
    }

    // MARK: - The trust table

    /// The turn's speaker. `match` nil: nothing was checked (the check off, no print, no audio).
    static func speaker(_ entry: ArisTurnEntry, match: ArisVoiceMatch?) -> ArisTurnSpeaker {
        switch entry {
        case .typed: return .typed
        case .keyHeld: return .keyHeld
        case .tapped, .wakeWord, .followUp:
            guard let match, match.why != "no-print" else { return .notChecked }
            return match.verdict == .owner ? .voiceMatched : .unverified
        }
    }

    // MARK: - Learning

    /// Least voice an utterance needs to move the print.
    static let learnsFrom = 1.0

    /// Whether this utterance may move the print. `match`: the utterance against the print as it is (nil: no print yet).
    static func learns(entry: ArisTurnEntry, seconds: Double, match: ArisVoiceMatch?) -> Bool {
        guard entry == .keyHeld, seconds >= learnsFrom else { return false }
        return match?.verdict != .notOwner
    }
}
