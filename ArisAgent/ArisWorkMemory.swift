//
//  ArisWorkMemory.swift
//  aris-agent, aris-tools
//
//  The work memory: what Aris DID, kept so the next time costs less. (The person memory, ArisMemory*, is what the user
//  said about himself; this is the other half.)
//
//  What is stored is Aris's own record of its own acts, in fields, never prose from outside:
//  - an episode per finished turn or job that used tools: the user's request (their words), the brain, the steps in order
//    as Aris saw them (tool and subcommand, the arguments Aris kept: paths, app names, ids and flags; the gate's
//    verdict; ok or failed; how long), what was made (files with their paths, items with their ids, from the activity
//    log's own undo records), how it ended (done, failed with Aris's own error class, cancelled, undone later), the
//    taint of the turn, tokens and seconds where known;
//  - lessons, derived by rule from the episodes that may teach (ArisWorkLessons, rule 2 below):"for this kind of request this way works
//    here, that one fails", "this command needs this flag on this Mac", "this usually goes to that folder or app",
//    "the name he used is that path". A lesson keeps its evidence (episode ids), a confidence that rises with each
//    repeat and falls on a later failure, and expires when contradicted.
//  A tool's output, a page's text, a message's body, a file's content, typed text and the clipboard are never stored:
//  a step keeps only the argument kinds named above (ArisWorkSteps), and anything that looks like a key, a token or
//  a password is dropped (ArisWorkSafe).
//
//  What may teach (the owner's ruling, 2026-11-12: "use at your own risk"; security review 8's H1 was decided this way):
//  1. Every episode keeps its taint as data (ArisWorkTaintRule.taint): clean only when the turn was the user's own from
//     the app (no job, no hands-free, no screen, no attached file's text, no outside text in the conversation), the
//     brain's own taint was none when it ended, AND every step is a call whose answer carries nothing anyone else
//     wrote (Aris's strict list: ArisWorkSteps.bringsNothingIn). Anything else is marked with its taint.
//  2. What a turn teaches does not depend on that taint: any conversation turn the user asked from the app, on any brain,
//     clean or not, feeds lessons and may be offered to a later turn (ArisWorkTaintRule.teaches). Not a job (its
//     prompt was written by a model), not a hands-free turn (the hands-free rules keep memory out of those), not
//     another caller's turn. The store refuses a lesson whose evidence isn't all such turns.
//  3. A lesson that rests on any episode whose turn read outside content (the web, mail, a file, the screen, a
//     calendar, a tool's output) carries that mark (ArisWorkLesson.outside): Settings › 기억 shows it ("바깥 글을 본
//     대화에서 배움") beside its 지우기, so the user sees where it came from and can remove it.
//  4. None of this changes a turn's own taint for the gates: a turn that read a page still asks before it sends, and
//     `aris-tools recall --tainted` (which prints tainted episodes themselves) is still outside text to every gate.
//     The block a turn gets is Aris's own wording of its record (fenced: ArisWorkRecall.block), never a page's text.
//
//  Everything lives in memory.sqlite beside the person memory (ArisWorkStore: the same file, lock and protections).
//  Recall is small: at most three lessons and two past episodes in under 150 tokens before a clean turn
//  (ArisWorkRecall), and the rest on demand through `aris-tools recall`. Whether it saves anything is measured, not
//  assumed (ArisWorkStats). Foundation only (tested).
//

import Foundation

/// How far outside content had come into the turn an episode records (ArisTaint's levels, kept as numbers so
/// aris-tools reads them too).
enum ArisWorkTaint: Int, Codable, Comparable, Sendable {
    case clean = 0, screen = 1, outside = 2

    static func < (a: ArisWorkTaint, b: ArisWorkTaint) -> Bool { a.rawValue < b.rawValue }

    /// The mark `aris-tools recall` prints first, so whoever reads the output knows what it is.
    var mark: String {
        switch self {
        case .clean: "clean"
        case .screen: "screen"
        case .outside: "outside-text"
        }
    }
}

/// One argument Aris kept from a call. Only these kinds exist: anything else in the call (a message's text, a note's
/// body, a search's words, typed text) is not kept at all.
struct ArisWorkArg: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// A file or folder.
        case path
        /// An app's name or bundle id.
        case app
        /// An id Aris or an app gave (an event, a schedule, a service's tool).
        case id
        /// A flag's own name ("--focus"), or a fixed word of the command ("25", "png").
        case flag
        /// Who or what it was for, as the command named it (a recipient, a list).
        case name
    }

    var kind: Kind
    var value: String
}

/// One thing Aris ran (or asked to run) during a turn.
struct ArisWorkStep: Codable, Equatable, Sendable {
    /// "aris-tools", "shell" (another program), or "brain" (the AI's own tool: a web search, a file read).
    var tool: String
    /// The subcommand ("music play", "move", "note"), a program's name, or the brain's tool's name.
    var verb: String
    var args: [ArisWorkArg]
    /// The gate's verdict as far as Aris saw it: "auto", "asked", "yes", "no", "unanswered", "refused", or "" (not seen).
    var gate: String = ""
    /// "ok", "failed", "declined" (the user's no or nobody answered), "refused" (the gate) or "unknown".
    var status: String = "ok"
    /// How long until the next step or the answer, in milliseconds.
    var ms: Int = 0
    /// Aris's strict rule (ArisWorkSteps.bringsNothingIn): this call's answer carries nothing anyone else wrote.
    var clean: Bool = false

    var failed: Bool { status == "failed" || status == "refused" }
    var worked: Bool { status == "ok" }

    /// "music play spotify": the verb and the kept arguments, as a brain or the user reads it.
    var line: String { ([verb] + args.map(\.value)).joined(separator: " ") }

    /// The same call (verb and arguments), whatever became of it.
    func sameCall(as other: ArisWorkStep) -> Bool { tool == other.tool && verb == other.verb && args == other.args }
}

/// Something a turn made, from the activity log's own undo record (never from what a tool printed).
struct ArisWorkMade: Codable, Equatable, Sendable {
    /// "file", "moved", "event", "schedule", "todo".
    var kind: String
    /// A file's path (the new place of a moved one), or the item's id.
    var value: String
}

enum ArisWorkOutcome: String, Codable, Sendable {
    case done, failed, cancelled
    /// Done, and everything it changed was undone since.
    case undone
}

/// Aris's own classes for a turn that didn't end with an answer (never the tool's or the brain's words).
enum ArisWorkError: String, Codable, Sendable {
    case none = ""
    /// The brain was out of quota, missing or unreachable.
    case brain
    case timeout
    /// A sealed process broke its rules and was stopped.
    case stopped
    case other
}

struct ArisWorkEpisode: Equatable, Sendable {
    enum Kind: String, Sendable { case turn, job }

    /// 0 until the store gives it one; shown as "E12".
    var id: Int = 0
    var at: Date
    var seconds: Double = 0
    var kind: Kind = .turn
    /// The user's own words, one line, cut short; "" when they looked like a secret.
    var asked: String
    /// What kind of request it was (ArisWorkAsk.key): the same kind asked again has the same key.
    var key: String
    var brain: String
    var steps: [ArisWorkStep] = []
    var made: [ArisWorkMade] = []
    /// The activity log's entries this turn left (their ids), to tell later whether it was undone.
    var acts: [String] = []
    var outcome: ArisWorkOutcome = .done
    var error: ArisWorkError = .none
    var taint: ArisWorkTaint
    /// One line about it (the on-device model's when it passed the check, else made by rule).
    var title: String = ""
    var tokens: Int?
    /// The lessons and episodes ("L3", "E7") that were put into this turn's context before it started.
    var offered: [String] = []
    /// Whether the brain's first step was the offered way's first step; nil when nothing was offered.
    var followed: Bool?
    /// A job's teammate (its id), where it ran and the path of its result.
    var teammate: String = ""
    var place: String = ""
    var result: String = ""
    /// Compacted: the steps are gone, the one-line stub stays.
    var compacted = false
    /// It may teach lessons and be offered to a later turn (ArisWorkTaintRule.teaches): the user's own conversation turn
    /// from the app, not hands-free, whatever its taint.
    var teaches = false

    var name: String { "E\(id)" }
    var clean: Bool { taint == .clean }
}

struct ArisWorkLesson: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// For this kind of request this way works here; these were tried and failed.
        case way
        /// This command needs this flag or argument on this Mac.
        case flag
        /// This command's target is usually this folder or app.
        case place
        /// A name the user used stands for this path.
        case name
    }

    /// 0 until the store gives it one; shown as "L3".
    var id: Int = 0
    var kind: Kind
    /// The kind of request (way), the command (flag, place) or the name as the user said it (name).
    var key: String
    /// An example of the user's own words for it (from a clean episode).
    var asked: String
    /// The steps that worked, in order.
    var works: [ArisWorkStep]
    /// What was tried and failed.
    var fails: [ArisWorkStep] = []
    /// The episodes it is based on (their ids), oldest first.
    var evidence: [Int]
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date
    var expired = false
    var useCount = 0
    /// It rests on at least one episode whose turn read outside content: Settings › 기억 says so beside it.
    var outside = false

    var name: String { "L\(id)" }

    /// All the words in it, as the write gate reads them (ArisMemoryGate): its key, the user's example, every argument.
    var gateText: String {
        ([key, asked] + (works + fails).flatMap { [$0.verb] + $0.args.map(\.value) }).joined(separator: "\n")
    }

    static let startConfidence = 0.6
    /// Each repeat that worked the same way.
    static let repeatGain = 0.15
    /// Each later failure of the way it says works.
    static let failureLoss = 0.3
    /// Below this it is expired: never offered again.
    static let expiresBelow = 0.3
    /// At least this sure to go into a turn's context.
    static let offeredAt = 0.5
}

/// What the agent knew about a turn when it ended: everything the taint rule reads.
struct ArisWorkTurnFacts: Equatable, Sendable {
    /// The Aris app itself asked (ArisPeer), in a conversation.
    var fromApp = true
    var task = false
    /// The prompt carried outside text (the screen's text, a model's words, another caller).
    var untrusted = false
    /// Outside text was already in the conversation.
    var outsideConversation = false
    var screenSeen = false
    var handsFree = false
    var images = false
    var screenText = false
    /// A file's text came with the request.
    var attached = false
    /// The brain driver's own taint when the turn ended.
    var driver = ArisWorkTaint.clean
}

/// The taint rule, as code. Everything that decides whether an episode may ever reach a later clean turn is here.
enum ArisWorkTaintRule {
    /// The taint an episode is stored with. Clean only when the turn was the user's own clean turn by every sign the agent
    /// has (the same ones the person memory learns under, ArisMemoryLearning.mayLearn), the brain's own taint was none,
    /// and every step is on Aris's strict list of calls that bring nothing in.
    static func taint(of facts: ArisWorkTurnFacts, steps: [ArisWorkStep]) -> ArisWorkTaint {
        if !facts.fromApp || facts.task || facts.untrusted || facts.outsideConversation || facts.handsFree || facts.screenText || facts.attached
            || facts.driver == .outside || steps.contains(where: { !$0.clean }) {
            return .outside
        }
        if facts.screenSeen || facts.images || facts.driver == .screen { return .screen }
        return .clean
    }

    /// Whether a turn's episode may teach: the user's own conversation turn from the app, not hands-free, on any brain and
    /// whatever its taint (the taint is kept, and marks what it teaches).
    static func teaches(_ facts: ArisWorkTurnFacts) -> Bool { facts.fromApp && !facts.task && !facts.handsFree }

    /// Whether an episode may be evidence for a lesson: a conversation turn that may teach, with its steps still kept.
    static func feedsLessons(_ episode: ArisWorkEpisode) -> Bool { episode.teaches && episode.kind == .turn && !episode.compacted }

    /// Whether an episode may be put into a later turn's context by Aris itself: the same rule.
    static func offeredToTurns(_ episode: ArisWorkEpisode) -> Bool { feedsLessons(episode) }

    /// Whether a lesson resting on these episodes carries the outside mark: any of them read outside content.
    static func outside(_ episodes: [ArisWorkEpisode]) -> Bool { episodes.contains { !$0.clean } }

    /// The mark a recall's output carries: the worst taint among what it returns.
    static func mark(of episodes: [ArisWorkEpisode]) -> ArisWorkTaint { episodes.map(\.taint).max() ?? .clean }
}

/// What is safe to keep in an episode: one line, cut to a length, and nothing that looks like a secret (the rule the
/// why-record uses, ArisWhySafe, which aris-tools can't link: the tests hold the two to the same answers).
enum ArisWorkSafe {
    static let askedLimit = 200
    static let argLimit = 300

    /// 24 or more characters of letters, digits, dashes and underscores holding both letters and digits: a token.
    private static let token = #"(?<![A-Za-z0-9_\-])(?=[A-Za-z0-9_\-]*[0-9])(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{24,}(?![A-Za-z0-9_\-])"#
    /// How a private key, a bearer token or a provider's key begins.
    private static let marks = ["-----begin", "bearer ", "sk-", "ghp_", "xoxb-", "xoxp-", "akia"]

    static func looksSecret(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return ArisMemoryText.isSecret(text) || marks.contains(where: lowered.contains) || text.range(of: token, options: .regularExpression) != nil
    }

    /// The user's words as kept: one line, cut; "" when they look like a secret.
    static func asked(_ words: String) -> String {
        let line = ArisMemoryText.ownWords(words).split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !looksSecret(line) else { return "" }
        return String(line.prefix(askedLimit))
    }

    /// A path's secret check, part by part: a file called IMG_20261105_123456.jpg is no card number, so a run of
    /// digits alone doesn't drop a path; a token, a key or a secret's name anywhere in it does.
    static func pathLooksSecret(_ path: String) -> Bool {
        path.split(separator: "/").contains { part in
            let name = String(part)
            let digitsOnly = name.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || " -._".unicodeScalars.contains($0) }
            if digitsOnly { return name.unicodeScalars.filter(CharacterSet.decimalDigits.contains).count >= 12 }
            let lowered = name.lowercased()
            if marks.contains(where: lowered.contains) || name.range(of: token, options: .regularExpression) != nil { return true }
            // The digits taken out, so only a secret's name or a key's look is left to find.
            return ArisMemoryText.isSecret(String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.decimalDigits.contains($0) })))
        }
    }

    /// An id as kept: a UUID as Aris and the apps give them (it would read as a token to the rule above), or another
    /// short plain one that is no secret.
    static func id(_ value: String) -> ArisWorkArg? {
        if UUID(uuidString: value) != nil { return ArisWorkArg(kind: .id, value: value) }
        guard value.range(of: #"^[A-Za-z0-9_.:@\-]{1,80}$"#, options: .regularExpression) != nil else { return nil }
        return arg(.id, value)
    }

    /// An argument as kept, or nil when it must not be: empty, too long, more than one line (any line break, U+2028 and
    /// U+2029 too), a control character, a < or a > (no kept name can open or close a block in a prompt), or a secret
    /// by its kind's rule.
    static func arg(_ kind: ArisWorkArg.Kind, _ value: String) -> ArisWorkArg? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= argLimit, !trimmed.contains(where: \.isNewline), !trimmed.contains("<"), !trimmed.contains(">"),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || $0.value == 0x2028 || $0.value == 0x2029 }) else { return nil }
        guard !(kind == .path ? pathLooksSecret(trimmed) : looksSecret(trimmed)) else { return nil }
        return ArisWorkArg(kind: kind, value: trimmed)
    }
}

/// What kind of request the user's words were, so the same thing asked again is found: their words' own tokens (particles
/// off, fillers out, every number as "#": "25분 타이머" and "10분 타이머" are one kind), sorted.
enum ArisWorkAsk {
    private static let dull: Set<String> = ["해줘", "해", "줘", "좀", "주세요", "줄래", "please", "aris", "아리스", "아리스야", "지금", "그냥", "한번", "해봐",
                                            "해줄래", "해주세요", "can", "you", "could", "would", "me", "for", "now"]

    static func tokens(_ asked: String) -> [String] {
        ArisMemoryRecall.topicTokens(ArisMemoryText.ownWords(asked)).map { token in
            token.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains) ? "#" : token
        }.filter { !dull.contains($0) && !ArisMemoryText.latinStopwords.contains($0) }
    }

    static func key(_ asked: String) -> String { Array(Set(tokens(asked))).sorted().joined(separator: " ") }

    /// The grams two requests are compared by (the person memory's own: syllable pairs, Latin words, numbers), without
    /// the endings and fillers that say nothing about what is asked.
    static func grams(_ asked: String) -> Set<String> {
        ArisMemoryText.grams(ArisMemoryText.ownWords(asked)).subtracting(ArisMemoryRecall.fillerGrams)
    }

    /// 0…1: how alike two requests are (Dice over their grams).
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = grams(a), y = grams(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        return 2 * Double(x.intersection(y).count) / Double(x.count + y.count)
    }

    /// Two requests of the same kind: the same key, or nearly the same words.
    static let sameAt = 0.75

    static func same(_ a: String, _ b: String) -> Bool {
        let first = key(a), second = key(b)
        if !first.isEmpty, first == second { return true }
        return similarity(a, b) >= sameAt
    }
}

extension ArisWorkLesson {
    /// The failed steps, each once, without one that reads exactly like the whole way that worked. A step's line keeps a
    /// flag but not its value, so two calls that differed only in a value read the same; that "failed" half would say
    /// the same step works and fails (the third VM run, B11), and is left out wherever a lesson is said or shown. A
    /// step that failed alone and worked after another one ("window left" before "app Keynote") still counts.
    var distinctFails: [ArisWorkStep] {
        let worked = works.map(\.line).joined(separator: " → ")
        var seen = Set<String>()
        return fails.filter { $0.line != worked && seen.insert($0.line).inserted }
    }
}
