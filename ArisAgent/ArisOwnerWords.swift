//
//  ArisOwnerWords.swift
//  aris-agent
//
//  What the user said in the conversation now: their typed and spoken turns, word for word and in order, as the
//  Aris app sent them (POST /ask "request"). The automatic check (ArisAutoCheck) reads these and nothing else as "what
//  was asked". A turn counts only when it is his own: from the app itself, not heard hands-free (anyone near the Mac
//  could have said it), not a background job's brief or a schedule's stored prompt, not a routine's stored step, not
//  text a model wrote, not a turn the app says takes no action (a rewrite of the selection). The note of the files he
//  dropped and their text (ArisMemoryText.filesNote) is cut off first: a file's name or contents are never their words.
//  A new conversation starts the list again, and so does a quiet hour (the app's word that a conversation is new may
//  never arrive: its first turn can fail before it reaches here). The last turn is his request now; the earlier ones
//  only say what it refers to. Nothing here is written to disk. The store is the agent's one conversation's; the
//  reading of the words is pure and tested.
//

import Foundation

final class ArisOwnerWords: @unchecked Sendable {
    static let shared = ArisOwnerWords()

    /// How many of his turns are kept (the newest), and read by the checker.
    static let keptTurns = 12
    /// Turns older than the newest by more than this belong to another conversation, whatever the app said.
    static let quiet: TimeInterval = 3_600

    private let lock = NSLock()
    private var turns: [String] = []
    /// The conversation's turn now is his own (its words are the last of `turns`).
    private var latestIsHis = false
    /// When the last conversation turn of any kind arrived.
    private var lastAt: Date?

    /// A conversation turn arrived (never a background job's). `fresh`: it opens a new conversation. `his`: it is
    /// The user's own typed or spoken turn (see above); any other turn adds nothing and is nobody's words.
    func turn(_ request: String, fresh: Bool, his: Bool, at now: Date = Date()) {
        let words = Self.own(request)
        lock.withLock {
            if fresh || lastAt.map({ now.timeIntervalSince($0) > Self.quiet }) == true { turns = [] }
            lastAt = now
            latestIsHis = his && !words.isEmpty
            if latestIsHis { turns = Array((turns + [words]).suffix(Self.keptTurns)) }
        }
    }

    /// His turns of this conversation, when the turn now is his own and its words are exactly `request` (the words the
    /// acting brain's turn was started with); nil for any other turn: nothing is then checked against anyone's words.
    func said(endingWith request: String) -> [String]? {
        let words = Self.own(request)
        return lock.withLock { latestIsHis && !words.isEmpty && turns.last == words ? turns : nil }
    }

    /// His words alone: without the files note, trimmed.
    static func own(_ request: String) -> String {
        ArisMemoryText.ownWords(request).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Too few words to mean an action

    /// Words that agree, point or only say "do": none of them names an action.
    private static let empty: Set<String> = [
        "yes", "yeah", "yep", "yup", "ok", "okay", "sure", "please", "pls", "do", "it", "that", "this", "these", "those", "go", "ahead", "now", "and",
        "the", "just", "then", "again", "thanks", "thank", "you", "so", "right", "fine", "alright", "y",
        "ㅇㅇ", "ㅇㅋ", "ㅇ", "ㄱㄱ", "응", "어", "네", "넵", "넹", "예", "그래", "그래요", "좋아", "좋아요", "맞아", "맞아요", "해", "해줘", "해요", "해주세요", "줘", "주세요", "줄래",
        "그거", "이거", "저거", "그것", "이것", "그냥", "좀", "빨리", "다시", "부탁해", "부탁해요", "알겠어", "오케이", "고고", "그럼", "그렇게", "진행해", "계속", "계속해",
    ]

    /// Whether his turns name anything at all: at least one word of two or more characters that isn't a bare yes, a
    /// pointing word or "do it", a number, or only loose consonants and vowels (ㅇㅋㅇㅋ). "그거 해 줘", "yes", "ＹＥＳ",
    /// "ok 12" and "ㅇㅇ" name nothing: no action can be what they asked for.
    static func saysSomething(_ turns: [String]) -> Bool {
        turns.contains { turn in
            turn.precomposedStringWithCompatibilityMapping.lowercased()
                .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
                .contains { word in
                    word.count >= 2 && !empty.contains(String(word)) && !word.allSatisfy(\.isNumber)
                        && !word.unicodeScalars.allSatisfy { (0x3131...0x318E).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
                }
        }
    }
}
