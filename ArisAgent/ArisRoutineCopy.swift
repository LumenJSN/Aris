//
//  ArisRoutineCopy.swift
//  aris-agent
//
//  Every word the user reads or hears about their routines: the cards that read a routine back before it is saved, changed
//  or deleted, and what Aris says after. Korean in 해요 style, or English when his request has no Hangul
//  (ArisScheduleCard.isEnglish). None of these lines uses a word the app takes for "the system refused" or "nobody
//  answered" (ArisCardWait), so the notch shows them as written. Pure.
//

import Foundation

/// A card about a routine: its title and the lines under it.
struct ArisRoutineCard: Equatable {
    let title: String
    let detail: String
}

enum ArisRoutineCopy {
    /// "‘출근’ 루틴" / "the “morning” routine".
    static func label(_ name: String, korean: Bool) -> String {
        korean ? "‘\(name)’ 루틴" : "the “\(name)” routine"
    }

    /// "1. 메일 확인해 줘\n2. …"
    static func numbered(_ steps: [String]) -> String {
        steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private static func count(_ steps: Int, korean: Bool) -> String {
        korean ? "\(steps)단계" : steps == 1 ? "1 step" : "\(steps) steps"
    }

    /// How he runs it, in his language.
    private static func howToRun(_ name: String, korean: Bool) -> String {
        korean ? "“\(name) 루틴 해 줘”" : "“run my \(name) routine”"
    }

    // MARK: - Saving

    /// The card that reads a new routine back. `replacing`: the routine of that name he already has. `written`: an AI
    /// worded the steps (they aren't his own words), which the card says.
    static func saveCard(name: String, steps: [String], replacing: ArisRoutine?, written: Bool = false, korean: Bool) -> ArisRoutineCard {
        var lines: [String]
        if let replacing {
            lines = [korean ? "\(label(name, korean: true))이 이미 있어요. 이렇게 바꿀까요?" : "You already have a “\(name)” routine. Change it to this?",
                     numbered(steps), "", korean ? "지금은:" : "Now it is:", numbered(replacing.steps)]
        } else {
            lines = [korean ? "\(label(name, korean: true))을 이렇게 저장할까요?" : "Save \(label(name, korean: false)) like this?", numbered(steps)]
        }
        if written {
            lines += ["", korean ? "AI가 정리한 단계라서, 실행할 때는 단계마다 더 꼼꼼히 확인해요."
                                 : "An AI worded these steps, so each one is checked more carefully when it runs."]
        }
        let title = replacing == nil ? (korean ? "루틴 저장" : "Save routine") : (korean ? "루틴 바꾸기" : "Change routine")
        return ArisRoutineCard(title: title, detail: lines.joined(separator: "\n"))
    }

    static func saved(_ routine: ArisRoutine, korean: Bool) -> String {
        korean ? "\(label(routine.name, korean: true))을 저장했어요. \(howToRun(routine.name, korean: true))라고 하면 \(count(routine.steps.count, korean: true))를 차례로 해요."
               : "Saved \(label(routine.name, korean: false)). Say \(howToRun(routine.name, korean: false)) and I'll do its \(count(routine.steps.count, korean: false)) in order."
    }

    /// After a no, or a card nobody answered: nothing was saved, changed or deleted.
    static func left(unanswered: Bool, saving: Bool, korean: Bool) -> String {
        switch (unanswered, saving) {
        case (false, true): return korean ? "알겠어요, 저장하지 않았어요. 단계가 다르게 나뉘었다면 쉼표로 끊어서 다시 말해 주세요."
                                           : "OK, I didn't save it. If the steps were cut in the wrong places, say them again with commas between."
        case (true, true): return korean ? "카드를 기다리다가 저장하지 않고 넘어갔어요." : "I waited on the card and saved nothing."
        case (false, false): return korean ? "알겠어요, 그대로 둘게요." : "OK, I'll leave it as it is."
        case (true, false): return korean ? "카드를 기다리다가 그대로 두고 넘어갔어요." : "I waited on the card and left it as it is."
        }
    }

    static func problem(_ problem: ArisRoutineProblem, korean: Bool) -> String {
        switch problem {
        case .noName:
            return korean ? "루틴 이름을 알아듣지 못했어요. “출근 루틴 만들어 줘: 메일 확인하고, 일정 알려 줘”처럼 이름을 붙여 말해 주세요."
                          : "I didn't catch a name for the routine. Say it like “make a morning routine: check my mail, tell me today's schedule”."
        case .noSteps:
            return korean ? "넣을 단계를 알아듣지 못했어요. “출근 루틴 만들어 줘: 메일 확인하고, 일정 알려 줘”처럼 말해 주세요."
                          : "I didn't catch any steps. Say it like “make a morning routine: check my mail, tell me today's schedule”."
        case .tooManySteps:
            return korean ? "루틴 하나에는 \(ArisRoutineRules.maxSteps)단계까지 넣을 수 있어요. 둘로 나눠서 만들어 주세요."
                          : "A routine holds up to \(ArisRoutineRules.maxSteps) steps. Please split it into two."
        case .tooManyRoutines:
            return korean ? "루틴은 \(ArisRoutineRules.maxRoutines)개까지 둘 수 있어요. 하나를 지우고 다시 말해 주세요."
                          : "You can keep up to \(ArisRoutineRules.maxRoutines) routines. Delete one and ask again."
        case .stepTooLong(let step):
            return korean ? "\(step)번째 단계가 너무 길어요. 한두 문장으로 줄여서 다시 말해 주세요." : "Step \(step) is too long. Say it in a sentence or two."
        case .stepIsCommand(let step):
            return korean ? "\(step)번째 단계가 명령어처럼 보여서 넣지 않았어요. 루틴에는 평소 말하듯이 부탁하는 말만 넣을 수 있어요."
                          : "Step \(step) reads like a command line, so I left it out. A routine holds only requests in plain words."
        case .stepIsRoutine(let step):
            return korean ? "\(step)번째 단계가 루틴을 부르는 말이라 넣지 않았어요. 루틴 안에 다른 루틴은 넣을 수 없어요."
                          : "Step \(step) calls a routine, so I left it out. A routine can't hold another routine."
        }
    }

    static func saveFailed(korean: Bool) -> String {
        korean ? "루틴을 저장하다가 문제가 생겼어요. 바뀐 건 없어요. 한 번 더 말해 주세요." : "Something went wrong saving the routine. Nothing changed. Please ask once more."
    }

    // MARK: - From what he just asked

    static func recentNone(korean: Bool) -> String {
        korean ? "방금 한 요청 중에 루틴에 넣을 만한 걸 찾지 못했어요. “출근 루틴 만들어 줘: 메일 확인하고, 일정 알려 줘”처럼 단계를 말해 주세요."
               : "I found nothing among your last requests to put in a routine. Say the steps, like “make a morning routine: check my mail, tell me today's schedule”."
    }

    static func recentNeedsName(steps: [String], korean: Bool) -> String {
        (korean ? "어떤 이름으로 저장할까요? “방금 한 걸 출근 루틴으로 저장해 줘”처럼 이름을 붙여 말해 주세요. 넣을 단계는 이거예요."
                : "What should I call it? Say it with a name, like “save what I just did as my morning routine”. These would be its steps.")
            + "\n" + numbered(steps)
    }

    // MARK: - Listing and showing

    static func list(_ routines: [ArisRoutine], korean: Bool) -> String {
        guard !routines.isEmpty else {
            return korean ? "아직 루틴이 없어요. “출근 루틴 만들어 줘: 메일 확인하고, 일정 알려 주고, 슬랙 열어 줘”처럼 말하면 만들어요."
                          : "You have no routines yet. Say “make a morning routine: check my mail, tell me today's schedule, open Slack” to make one."
        }
        let head = korean ? "루틴이 \(routines.count)개 있어요." : routines.count == 1 ? "You have 1 routine." : "You have \(routines.count) routines."
        return ([head, ""] + routines.map { "- **\($0.name)**: \(count($0.steps.count, korean: korean))" }).joined(separator: "\n")
    }

    static func show(_ routine: ArisRoutine, korean: Bool) -> String {
        let head = korean ? "\(label(routine.name, korean: true))은 \(count(routine.steps.count, korean: true))예요."
                          : "\(label(routine.name, korean: false).capitalizedFirst) has \(count(routine.steps.count, korean: false))."
        return head + "\n\n" + numbered(routine.steps)
    }

    static func missing(_ name: String, routines: [ArisRoutine], korean: Bool) -> String {
        let names = routines.map(\.name).joined(separator: ", ")
        return korean ? "\(label(name, korean: true))은 없어요. 지금 있는 루틴: \(names)." : "There's no “\(name)” routine. You have: \(names)."
    }

    // MARK: - Changing and deleting

    /// The card for one step added or taken out: what changes, then the routine as it would be.
    static func changeCard(_ routine: ArisRoutine, steps: [String], added: String?, removed: String?, korean: Bool) -> ArisRoutineCard {
        let name = label(routine.name, korean: korean)
        let head = added != nil ? (korean ? "\(name)에 이 단계를 넣을까요?" : "Add this step to \(name)?")
                                : (korean ? "\(name)에서 이 단계를 뺄까요?" : "Take this step out of \(name)?")
        return ArisRoutineCard(title: korean ? "루틴 바꾸기" : "Change routine",
                               detail: [head, "“\(added ?? removed ?? "")”", "", korean ? "바꾸면 이렇게 돼요:" : "It would then be:", numbered(steps)]
                                   .joined(separator: "\n"))
    }

    static func changed(_ routine: ArisRoutine, korean: Bool) -> String {
        korean ? "\(label(routine.name, korean: true))을 바꿨어요. 이제 \(count(routine.steps.count, korean: true))예요."
               : "Changed \(label(routine.name, korean: false)). It has \(count(routine.steps.count, korean: false)) now."
    }

    static func whichStep(_ routine: ArisRoutine, korean: Bool) -> String {
        (korean ? "\(label(routine.name, korean: true))에서 어느 단계인지 모르겠어요. “\(routine.name) 루틴에서 2번 빼 줘”처럼 번호로 말해 주세요."
                : "I can't tell which step of \(label(routine.name, korean: false)) you mean. Say its number, like “remove step 2 from my \(routine.name) routine”.")
            + "\n\n" + numbered(routine.steps)
    }

    /// His words fit more than one step: those steps with their numbers, and how to say which.
    static func whichOf(_ routine: ArisRoutine, steps found: [Int], korean: Bool) -> String {
        let listed = found.map { "\($0 + 1). \(routine.steps[$0])" }.joined(separator: "\n")
        return (korean ? "\(label(routine.name, korean: true))에 그 말에 맞는 단계가 \(found.count)개 있어요. “\(routine.name) 루틴에서 \(found[0] + 1)번 빼 줘”처럼 번호로 말해 주세요."
                       : "\(found.count) steps of \(label(routine.name, korean: false)) match that. Say which by its number, like “remove step \(found[0] + 1) from my \(routine.name) routine”.")
            + "\n\n" + listed
    }

    static func onlyStep(_ routine: ArisRoutine, korean: Bool) -> String {
        korean ? "\(label(routine.name, korean: true))은 단계가 하나뿐이에요. 루틴을 없애려면 “\(routine.name) 루틴 지워 줘”라고 해 주세요."
               : "\(label(routine.name, korean: false).capitalizedFirst) has only one step. To remove the routine, say “delete my \(routine.name) routine”."
    }

    /// `schedules`: the schedules that run this routine, each as "제목 (매일 09:00)".
    static func deleteCard(_ routine: ArisRoutine, schedules: [String], korean: Bool) -> ArisRoutineCard {
        var lines = [korean ? "\(label(routine.name, korean: true))을 지울까요?" : "Delete \(label(routine.name, korean: false))?", numbered(routine.steps)]
        if !schedules.isEmpty {
            let list = schedules.joined(separator: ", ")
            lines += ["", korean ? "이 루틴을 실행하는 예약이 있어요: \(list). 루틴을 지우면 그 예약은 할 일을 찾지 못해요."
                                 : "A schedule runs this routine: \(list). Once the routine is gone, that schedule finds nothing to do."]
        }
        return ArisRoutineCard(title: korean ? "루틴 지우기" : "Delete routine", detail: lines.joined(separator: "\n"))
    }

    static func deleted(_ routine: ArisRoutine, korean: Bool) -> String {
        korean ? "\(label(routine.name, korean: true))을 지웠어요." : "Deleted \(label(routine.name, korean: false))."
    }

    // MARK: - Running

    /// A step that would run a routine: never done, so no routine can call itself or loop.
    static func nested(korean: Bool) -> String {
        korean ? "루틴 안에서 다른 루틴은 실행하지 않아요." : "A routine doesn't run another routine."
    }

    static func handedOut(korean: Bool) -> String {
        korean ? "이 단계는 팀원에게 맡기는 일이라 루틴 안에서는 하지 않았어요. 따로 말해 주세요."
               : "This step is work for a teammate, which a routine doesn't hand out. Ask for it on its own."
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
