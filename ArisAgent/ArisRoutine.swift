//
//  ArisRoutine.swift
//  aris-agent
//
//  A routine: a name and a few of the user's own requests in order ("출근": 메일 확인해 줘, 오늘 일정 알려 줘, 슬랙 열어 줘).
//  "출근 루틴 해 줘" asks them one after another, each as if he had just said it (ArisRoutineRun), so everything that
//  asks him today asks inside a routine too. A step is words for the AI, never a shell command: one that reads like a
//  command line is refused when the routine is made. Here: the routine itself, how a name is matched the way he says
//  it, and what a routine may hold. Pure.
//

import Foundation

struct ArisRoutine: Codable, Equatable, Identifiable {
    let id: UUID
    /// As the user named it, without the word 루틴 ("출근", "morning").
    let name: String
    /// His requests, in the order they run.
    let steps: [String]
    /// The steps are the user's own words: they said them when they made it, or they were their own requests just before. False
    /// when an AI wrote them (`aris-tools routine add` with steps that aren't in their words): such a routine runs every
    /// step as model-written text, like a schedule's prompt.
    let own: Bool
    let created: Date
    let changed: Date

    /// The same routine with other steps.
    func with(steps: [String], at now: Date) -> ArisRoutine {
        ArisRoutine(id: id, name: name, steps: steps, own: own, created: created, changed: now)
    }
}

/// Why a routine can't be saved as asked.
enum ArisRoutineProblem: Equatable {
    case noName
    case noSteps
    case tooManySteps
    case tooManyRoutines
    /// A step (counted from 1) is too long, reads like a command line, or would run a routine.
    case stepTooLong(Int)
    case stepIsCommand(Int)
    case stepIsRoutine(Int)
}

enum ArisRoutineRules {
    static let maxRoutines = 30
    static let maxSteps = 12
    static let stepLimit = 200
    static let nameLimit = 30

    /// A step as it is kept: one line, single spaces. Nil when it reads like a command line (a path, a pipe, a flag,
    /// aris-tools by name: ArisScheduleArguments.commandShapes), which a routine never holds.
    static func step(_ raw: String) -> String? {
        guard let line = try? ArisScheduleArguments.promptText(raw) else { return nil }
        return ArisSchedule.oneLine(line, limit: stepLimit + 1)
    }

    /// What is wrong with a routine about to be saved; nil when it is fine. `steps` are already cleaned (`step`) where
    /// they could be; `raw` the same steps as given.
    static func problem(name: String, steps raw: [String], others: Int) -> ArisRoutineProblem? {
        guard !ArisRoutineNames.key(name).isEmpty else { return .noName }
        guard !raw.isEmpty else { return .noSteps }
        guard raw.count <= maxSteps else { return .tooManySteps }
        guard others < maxRoutines else { return .tooManyRoutines }
        for (index, one) in raw.enumerated() {
            guard let cleaned = step(one), !cleaned.isEmpty else { return .stepIsCommand(index + 1) }
            if cleaned.count > stepLimit { return .stepTooLong(index + 1) }
            // A routine never runs a routine (its own or another): no loop can be built.
            if ArisRoutineWords.mentions(cleaned) { return .stepIsRoutine(index + 1) }
        }
        return nil
    }
}

/// A routine's name the way the user says it: with or without 루틴, any spacing, any case.
enum ArisRoutineNames {
    private static let leading = ["내", "나의", "저의", "제", "그", "이", "my", "the", "a", "an", "our"]
    /// Words that name no routine ("모든 루틴", "new routine").
    private static let generic: Set<String> = ["", "모든", "전체", "전부", "새", "새로운", "저장된", "내", "이", "그", "all", "new", "every", "any", "some", "a", "an",
                                               "the", "my", "this", "that"]

    /// The name as it is kept and shown: without 루틴 or "routine", a leading 내 or "my", quotes, or "…(이)라는".
    static func clean(_ raw: String) -> String {
        var words = raw.precomposedStringWithCanonicalMapping
            .components(separatedBy: CharacterSet(charactersIn: "\"'“”‘’「」『』`").union(.newlines)).joined(separator: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        while let last = words.last, ["루틴", "routine", "routines"].contains(last.lowercased()) { words.removeLast() }
        while let first = words.first, leading.contains(first.lowercased()), words.count > 1 { words.removeFirst() }
        var name = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,:;!?~ "))
        for tail in ["이라는", "라는", "이라고 하는", "라고 하는", "이란", "란"] where name.hasSuffix(tail) && name.count > tail.count + 1 {
            name = String(name.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        if name.hasSuffix("루틴"), name.count > 2 { name = String(name.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        return String(name.prefix(ArisRoutineRules.nameLimit))
    }

    /// What two spellings of one name share: letters and digits only, lowercased ("출근 루틴", "출근루틴" and "출근" are one).
    static func key(_ raw: String) -> String {
        let name = clean(raw).lowercased()
        let kept = String(String.UnicodeScalarView(name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return generic.contains(kept) ? "" : kept
    }

    /// The stored routine the user means by `said`.
    static func find(_ said: String, in routines: [ArisRoutine]) -> ArisRoutine? {
        let wanted = key(said)
        guard !wanted.isEmpty else { return nil }
        return routines.first { key($0.name) == wanted }
    }
}

/// Cutting what the user said after "… 루틴 만들어 줘:" into steps.
enum ArisRoutineSteps {
    /// Marks that end one step and start the next.
    private static let breaks = #"\s*(?:[,;，、\n]+|\s그리고\s|\s그\s?다음(?:에|으로|엔)?\s|\s그런\s?다음(?:에)?\s|\s그\s?후(?:에)?\s|\s그러고\s?나서\s|\s마지막으로\s|\s(?:and\s+)?then\s|\sand\s+finally\s|\sfinally\s)\s*"#
    /// A Korean verb that goes on to the next act ("확인하고 ", "알려 주고 ", "열고 "): only used when nothing above cut the words.
    /// "하고" only after a word of its own ("메일 확인하고 …"): "메일하고 일정 …" is "mail and schedule", one step.
    private static let goesOn = #"(?<=\S\s\S{1,12}하고|주고|열고|켜고|틀고|읽고|끄고|닫고|찾고)\s+"#

    /// The steps in `text`, each polished (`polished`); empty when there are none.
    static func split(_ text: String) -> [String] {
        let whole = text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = pieces(whole, by: breaks)
        if parts.count == 1 { parts = pieces(whole, by: goesOn) }
        if parts.count == 1, !whole.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            // English with no comma: "check my mail and open Slack" is two steps when each side is a few words.
            let halves = pieces(whole, by: #"\s+and\s+"#)
            if halves.allSatisfy({ $0.split(separator: " ").count >= 2 }) { parts = halves }
        }
        return parts.map(polished).filter { !$0.isEmpty }
    }

    private static func pieces(_ text: String, by pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [text] }
        let marked = regex.stringByReplacingMatches(in: " " + text + " ", range: NSRange(location: 0, length: (" " + text + " ").utf16.count), withTemplate: "\u{1F}")
        return marked.components(separatedBy: "\u{1F}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// How a step that ended on "…고" reads as a request of its own.
    private static let endings: [(String, String)] = [("주고", "줘"), ("하고", "해 줘"), ("열고", "열어 줘"), ("켜고", "켜 줘"), ("틀고", "틀어 줘"),
                                                     ("읽고", "읽어 줘"), ("끄고", "꺼 줘"), ("닫고", "닫아 줘"), ("찾고", "찾아 줘")]

    /// A step as its own request: no leading "그리고" or "and", no closing mark, and "확인하고" said as "확인해 줘".
    static func polished(_ raw: String) -> String {
        var step = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!~。")))
        for lead in ["그리고 ", "그다음에 ", "그 다음에 ", "and then ", "then ", "and "] where step.lowercased().hasPrefix(lead) {
            step = String(step.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        if let (ending, request) = endings.first(where: { step.hasSuffix($0.0) }), step.count > ending.count {
            step = String(step.dropLast(ending.count)) + request
        }
        return step
    }
}
