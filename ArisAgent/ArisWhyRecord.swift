//
//  ArisWhyRecord.swift
//  aris-agent
//
//  What Aris keeps about each conversation turn so that "왜 그렇게 했어?" is answered from facts, never from a guess:
//  what the user asked (their own words), the memories that went to the AI with it, which AI was asked and whether another
//  took over, whether the screen or outside text was in the conversation, the cards that went up, how the gate rated
//  each action, and how the turn ended.
//
//  What is never kept: a command as the AI wrote it, a card's details (a message's text, a file's changes), the AI's
//  answer, the screen's text, a file's content. A name the gate made for a card (its title) is kept unless it looks
//  like a secret. The last few turns only, in memory only: nothing here is written to disk, and an agent that
//  restarts says it has no record instead of reading one back (a file could be written by anything that runs as the user).
//  Foundation only (tested).
//

import Foundation

/// A confirm card that went up on the turn's stream.
struct ArisWhyCard: Equatable {
    enum Kind: Equatable {
        case plain
        /// A message the user dictated: read out and sent unless they stops it.
        case countdown
        /// "앞으로 이건 그냥 할까?"
        case proposal
    }

    let id: String
    /// The card's title as the gate made it ("메시지 보내기 · 엄마"); nil when it looked like a secret.
    let title: String?
    let kind: Kind
    /// Its details opened with the gate's own "outside content was read" line.
    let afterOutside: Bool
    /// It asked about writing to the user's memory.
    let memory: Bool
    /// The user's answer when the record has it.
    var answer: ArisWhyCardAnswer?
}

/// What became of a card. A card nobody answered is not the user's no (ArisRefusalWords says the same to the AI).
enum ArisWhyCardAnswer: Equatable {
    case yes, no, unanswered
}

/// How the gate rated one action the AI asked for (ArisRiskPolicy), with the gate's reason when it gave one.
struct ArisWhyRated: Equatable {
    /// The title the card for it has or would have had; nil when it looked like a secret.
    let label: String?
    let risk: ArisRisk
    let why: String?
}

/// How a turn ended.
enum ArisWhyOutcome: Equatable {
    /// No last line yet: the turn is still going, or its connection closed before one came.
    case open
    case answered
    /// The line the user was shown instead of an answer; nil when it looked like a secret.
    case failed(String?)
}

struct ArisWhyRecord: Equatable {
    let id: Int
    let at: Date
    var ended: Date?
    /// The user's own words, cut short; nil when they looked like a secret.
    let asked: String?
    /// What the app's own history of the conversation is matched against (ArisWhyMatch).
    let match: String
    /// A file's text came with the request.
    let attached: Bool
    let handsFree: Bool
    /// The screen was in this turn or earlier in its conversation.
    let screen: Bool
    /// Outside text was in the conversation before this turn, and whether more came in during it.
    let outsideBefore: Bool
    var outsideDuring = false
    /// Whether the turn was one that may be given memories at all (ArisMemoryLearning.mayRecall).
    let memoryAllowed: Bool
    /// The memory lines that went to the AI with the question, as it read them.
    let memories: [String]
    /// The AI the user has set, and the one the turn was routed to.
    let wanted: String
    let routed: String
    /// The AIs actually asked, in order (more than one: the next took over).
    var brains: [String] = []
    /// An AI was passed over because it was out of quota or couldn't be reached.
    var passedOver: [String] = []
    /// The notch's status lines this turn, in order, each once. Used only to tell what kind of step was taken; never
    /// quoted (a line may carry the AI's own words).
    var steps: [String] = []
    var cards: [ArisWhyCard] = []
    var rated: [ArisWhyRated] = []
    /// Actions that went ahead without a card because of a standing yes or main Aris's judgement (the audit's words).
    var approved: [String] = []
    /// The gate's reasons for what it refused outright.
    var refused: [String] = []
    /// The AI's process was stopped for breaking its own rules.
    var stopped = false
    var outcome = ArisWhyOutcome.open

    static let askedLimit = 120
    static let titleLimit = 80
    static let lineLimit = 160
    static let keptSteps = 16
    static let keptFacts = 12

    /// Outside text or the screen was part of this turn by the time it ended.
    var tainted: Bool { screen || outsideBefore || outsideDuring || attached }

    /// How many actions ran without asking because the gate rated them safe.
    var autoCount: Int { rated.filter { $0.risk == .auto }.count }

    /// The actions the gate rated never, with its reason.
    var nevers: [ArisWhyRated] { rated.filter { $0.risk == .never } }

    /// A card the user said no to, or that nobody answered.
    var declined: [ArisWhyCard] { cards.filter { $0.answer == .no || $0.answer == .unanswered } }

    /// Something of this turn was refused, stopped or failed: what "왜 안 돼?" and a bare "왜?" are about.
    var hasRefusal: Bool {
        if case .failed = outcome { return true }
        return !nevers.isEmpty || !refused.isEmpty || !declined.isEmpty || stopped || !gateLines.isEmpty
    }

    /// The notch lines of this turn that are the gate's own fixed refusals (a blocked read, browser work sent to Aside).
    var gateLines: [String] { steps.filter(ArisWhySteps.isGateLine) }
}

/// Text that is safe to keep and say back: cut to a length, and nil when it looks like a secret (a password, a key, a
/// long number, an opaque token).
enum ArisWhySafe {
    /// 24 or more characters of letters, digits, dashes and underscores holding both letters and digits: a token.
    private static let token = #"(?<![A-Za-z0-9_\-])(?=[A-Za-z0-9_\-]*[0-9])(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{24,}(?![A-Za-z0-9_\-])"#
    /// How a private key, a bearer token or a provider's key begins.
    private static let marks = ["-----begin", "bearer ", "sk-", "ghp_", "xoxb-", "xoxp-", "akia"]

    static func looksSecret(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ArisMemoryText.isSecret(text) || marks.contains(where: lowered.contains)
            || text.range(of: token, options: .regularExpression) != nil
    }

    /// One line of at most `limit` characters, or nil for a secret.
    static func kept(_ text: String, limit: Int) -> String? {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !looksSecret(line) else { return nil }
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }
}

/// Telling whether the app's history line for the turn before is the turn a record holds.
enum ArisWhyMatch {
    /// The key a record keeps: the user's words as letters and digits; a secret-looking one only as its SHA-256.
    static func key(_ words: String) -> String {
        let plain = ArisMemoryText.normalized(firstLine(words))
        return ArisWhySafe.looksSecret(words) ? "#" + ArisAuditWriter.sha256(plain) : plain
    }

    /// Short words must be the same; longer ones may be part of each other (the app keeps the words as heard, the
    /// agent may get them with an instruction after them).
    static func same(heard: String, key: String) -> Bool {
        let plain = ArisMemoryText.normalized(firstLine(heard))
        guard !plain.isEmpty, !key.isEmpty else { return false }
        if key.hasPrefix("#") { return "#" + ArisAuditWriter.sha256(plain) == key }
        if plain == key { return true }
        guard min(plain.count, key.count) >= 6 else { return false }
        return plain.contains(key) || key.contains(plain)
    }

    private static func firstLine(_ text: String) -> String {
        String(text.split(whereSeparator: \.isNewline).first ?? "")
    }

    /// What the user said in the turn before this one, from the context the app sends ("recent:" then "- user: …" and
    /// "  you: …" lines, ArisContext.make); nil when the conversation has no turn yet.
    static func lastHeard(in context: String?) -> String? {
        guard let context else { return nil }
        var inRecent = false
        var last: String?
        for line in context.components(separatedBy: "\n") {
            if line == "recent:" { inRecent = true; continue }
            if line == "background tasks:" { inRecent = false }
            if inRecent, line.hasPrefix("- user: ") { last = String(line.dropFirst("- user: ".count)) }
        }
        return last
    }
}

/// What kind of step a notch status line stands for. The lines are made by ArisAgentStatus and the gates; a line this
/// doesn't know counts as nothing.
enum ArisWhySteps {
    enum Read: String, CaseIterable {
        case web, page, mail, messages, notes, files, screen, selection, clipboard, browser, service
    }

    private static let reads: [(Read, [String])] = [
        (.web, ["웹 검색 중"]), (.page, ["웹 페이지 읽는 중"]), (.mail, ["메일 보는 중"]), (.messages, ["메시지 읽는 중"]),
        (.notes, ["메모 찾는 중", "Obsidian 찾는 중"]), (.files, ["파일 읽는 중", "파일 찾는 중"]), (.screen, ["화면 보는 중", "화면 다루는 중"]),
        (.selection, ["선택한 내용 보는 중"]), (.clipboard, ["클립보드 보는 중"]), (.browser, ["브라우저 보는 중"]),
        (.service, ["Notion 보는 중", "도구 쓰는 중"]),
    ]

    /// The kinds of reading the turn's steps show, each once, in the order above.
    static func reads(in steps: [String]) -> [Read] {
        reads.filter { $0.1.contains(where: steps.contains) }.map(\.0)
    }

    /// A fixed line the gate shows when it refuses: a read its judge blocked, or browser work that is Aside's.
    static func isGateLine(_ line: String) -> Bool {
        line == ArisRiskPolicy.browserRefusal || ArisReadWhy.allCases.contains { ArisReadGate.status($0) == line }
    }
}
