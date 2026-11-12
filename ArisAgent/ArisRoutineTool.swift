//
//  ArisRoutineTool.swift
//  aris-agent
//
//  `aris-tools routine …` as an AI may call it, and what the AIs are told about routines. Aris itself makes, shows,
//  changes and runs routines from the user's plain words (ArisRoutineTurn); an AI only meets one when their wording was
//  loose ("아침에 메일이랑 일정 보고 슬랙 여는 걸 출근 루틴으로 해 줘"). Then it may list and show them, and ask to add or
//  remove one: aris-tools hands the words to the agent, which reads the routine back to the user on a card and saves only
//  on their yes, on every brain alike. An AI never runs a routine through this tool. Pure.
//

import Foundation

enum ArisRoutineToolCall: Equatable {
    case list
    case show(String)
    case add(name: String, steps: [String])
    case remove(String)
}

enum ArisRoutineTool {
    static let usage = #"usage: routine list | routine show "<name>" | routine add --name "<name>" --step "<request>" [--step "<request>" …] | routine remove "<name>""#

    /// The words after `routine`, read strictly: one name, steps only as --step values, nothing left over.
    static func parse(_ words: [String]) -> ArisRoutineToolCall? {
        switch words.first {
        case "list" where words.count == 1: return .list
        case "show" where words.count == 2: return .show(words[1])
        case "remove" where words.count == 2: return .remove(words[1])
        case "add": return add(Array(words.dropFirst()))
        default: return nil
        }
    }

    private static func add(_ words: [String]) -> ArisRoutineToolCall? {
        var name: String?
        var steps: [String] = []
        var index = 0
        while index < words.count {
            guard index + 1 < words.count else { return nil }
            switch words[index] {
            case "--name" where name == nil: name = words[index + 1]
            case "--step": steps.append(words[index + 1])
            default: return nil
            }
            index += 2
        }
        guard let name, !steps.isEmpty else { return nil }
        return .add(name: name, steps: steps)
    }

    /// How many of a step's words must be the user's own of this turn for it to count as their.
    static let grounding = 0.5
    /// Words every request has, which say nothing about whose it is.
    private static let filler: Set<String> = ["줘", "줘요", "주세요", "줄래", "해", "좀", "please", "me", "my", "the", "a", "an"]

    /// Whether steps an AI passed are the user's own words: their turn is clean (nothing others wrote came in, not heard
    /// hands-free, not a background job) and each step is mostly made of what he just said. Otherwise the routine is
    /// kept as AI-worded, and runs like a schedule's prompt (every step as model-written text).
    static func isOwn(steps: [String], request: String, clean: Bool) -> Bool {
        clean && !steps.isEmpty && steps.allSatisfy { groundedness($0, in: request) >= grounding }
    }

    /// The share of `step`'s words that the user said: a word counts when its first two letters are in their words (an AI
    /// that cuts a sentence into requests changes the endings: "확인하고" comes back as "확인해 줘").
    static func groundedness(_ step: String, in words: String) -> Double {
        let said = ArisRoutineRecent.key(words)
        let tokens = step.split(whereSeparator: \.isWhitespace).map { ArisRoutineRecent.key(String($0)) }.filter { !$0.isEmpty && !filler.contains($0) }
        guard !tokens.isEmpty, !said.isEmpty else { return 0 }
        return Double(tokens.filter { said.contains($0.prefix(2)) }.count) / Double(tokens.count)
    }

    // MARK: - What the AI reads back

    static func listing(_ routines: [ArisRoutine]) -> String {
        guard !routines.isEmpty else { return "(no routines)" }
        return routines.map { "\($0.name) · \($0.steps.count) step\($0.steps.count == 1 ? "" : "s")" }.joined(separator: "\n")
    }

    static func showing(_ routine: ArisRoutine) -> String {
        "\(routine.name):\n" + ArisRoutineCopy.numbered(routine.steps)
    }

    static func noSuch(_ name: String, routines: [ArisRoutine]) -> String {
        "no routine named \"\(name)\"" + (routines.isEmpty ? " (the user has none yet)" : ". They have: " + routines.map(\.name).joined(separator: ", "))
    }

    /// Why an `add` can't be put to the user, for the AI to pass on.
    static func refusal(_ problem: ArisRoutineProblem) -> String {
        switch problem {
        case .noName: return "refused: --name is the routine's name in a word or two (without 루틴)"
        case .noSteps: return "refused: a routine needs at least one --step"
        case .tooManySteps: return "refused: a routine holds at most \(ArisRoutineRules.maxSteps) steps"
        case .tooManyRoutines: return "refused: the user already has \(ArisRoutineRules.maxRoutines) routines; one must be removed first"
        case .stepTooLong(let step): return "refused: step \(step) is too long (a sentence or two)"
        case .stepIsCommand(let step): return "refused: step \(step) reads like a command or a path. " + stepRule
        case .stepIsRoutine(let step): return "refused: step \(step) calls a routine; a routine never holds another routine"
        }
    }

    static let stepRule = "Each --step is one request in the user's own plain words (\"메일 확인해 줘\"), never a command, a flag or a path"

    static let handsFree = "refused: routines aren't read out or changed in a hands-free turn. Tell the user to ask with the key held."
    static let declined = "The user said no on the card: nothing was saved or removed. Don't try another way."
    static let unanswered = "The card got no answer: nothing was saved or removed. Say so, and don't try again unless asked."

    // MARK: - What the AIs are told

    /// One line of every brain's instructions. `relay`: Antigravity, whose commands Aris runs for it (no `routine`
    /// command there): it only learns how the user asks.
    static func rule(_ tools: String, relay: Bool = false) -> String {
        let own = "Routines (루틴): the user's saved bundles of their own requests (\"출근 루틴\": 메일 확인해 줘, 오늘 일정 알려 줘, 슬랙 열어 줘). " +
            "Aris itself makes, lists, shows, changes, deletes and runs them when the user says so plainly (\"출근 루틴 만들어 줘: …\", \"출근 루틴 해 줘\", " +
            "\"출근 루틴에서 슬랙 빼 줘\", \"출근 루틴 지워 줘\", \"루틴 뭐 있어?\"), so a routine request only reaches you when its wording was loose. "
        let later = "To run a routine later or on a repeat (\"매일 9시에 출근 루틴 해 줘\"), schedule it as scheduled work whose prompt is exactly " +
            "\"<name> 루틴 해 줘\": Aris then runs its steps in order at that time. A workout, skincare or study routine the user wants advice on is an " +
            "ordinary question, not one of these."
        guard !relay else {
            return own + "You have no command for them here: tell the user in a sentence how to say it (\"출근 루틴 만들어 줘: 메일 확인하고, 일정 알려 주고, " +
                "슬랙 열어 줘\"), and never claim a routine was saved, changed or run. " + later
        }
        return own + "Then: `\(tools) routine list` and `\(tools) routine show \"<name>\"` read them. To make one, split what they asked into their own " +
            "requests and run `\(tools) routine add --name \"<name, without 루틴>\" --step \"<first request, in their words>\" --step \"<next>\"` " +
            "(\(stepRule.prefix(1).lowercased() + stepRule.dropFirst()); the user is asked on a card that reads the steps back, so don't ask them yourself, and a " +
            "name they already have is replaced on that card); `\(tools) routine remove \"<name>\"` deletes one (also on a card). If they want a routine " +
            "and gave no steps, ask which steps. If one is still waiting on its card, the command says so with an id: `\(tools) routine wait <id>` until it " +
            "gives the result. To run one that Aris didn't run for you: `routine show` it, then do its steps yourself one at a time, in order, each " +
            "exactly as if the user had just asked it, with every confirmation it needs; stop at the first step that fails or is declined, and say " +
            "which steps were done and which were not. " + later
    }
}
