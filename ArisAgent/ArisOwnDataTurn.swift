//
//  ArisOwnDataTurn.swift
//  aris-agent
//
//  A request about Aris's own things (ArisOwnData: its schedules and reminders, to-dos, memory, teammates, timers,
//  settings) is done in the turn it was asked in, with Aris's own tool and its card (QA BUG-60: "큐에이 예약 테스트 예약
//  지워 줘" went out as a job, which asked Aside to find and delete it on websites, and "삭제하지 못했어요" came back).
//  Here: what the brain is told for such a turn, what happens when it answers with a jobs block anyway (asked once more
//  to do it itself; then the block is taken out and Aris says so), and the check of a job's "삭제했어요" against Aris's
//  own stores before it is passed on. Pure, but for `ArisOwnDataStores.live`.
//

import Foundation

enum ArisOwnDataTurn {
    /// The agent's schedule titles, for telling one named in a request (ArisOwnData.kind).
    static func scheduleNames(home: String) -> [String] {
        ArisScheduleStore.load(file: ArisScheduleStore.file(home: home)).map(\.title)
    }

    /// How each kind of thing is listed, changed or removed: Aris's own command for it, or (teammates, settings) that
    /// no tool of a brain's changes it.
    private static func how(_ kind: ArisOwnData.Kind, tools: String, task: Bool) -> String {
        let here = "Do it now, in this \(task ? "job" : "turn"), with Aris's own tool: "
        switch kind {
        case .schedule:
            return here + "`\(tools) schedule list` (each with its id), then `\(tools) schedule remove <id>`; a new one is `\(tools) schedule add …`; " +
                "a reminder is `\(tools) remind …`. 예약 here is Aris's own schedule, never a booking on a website."
        case .todo: return here + "`\(tools) todo`, `\(tools) todo add|done|edit …`."
        case .memory: return here + "`\(tools) memory [words]`, `\(tools) remember \"<fact>\"`, `\(tools) forget \"<words>\"`."
        case .timer: return here + "`\(tools) timer …`."
        case .teammate:
            return "No tool of yours changes teammates: say in a sentence that Aris adds or removes one when asked plainly " +
                "(\"<이름> 팀원 지워 줘\", \"… 하는 팀원 만들어 줘\") or in its 팀원 settings, and change nothing."
        case .settings: return "Aris's settings are changed in its own settings window: say where, and change nothing."
        }
    }

    /// The turn's note for the brain. `task`: a background job that got such a request anyway. `named`: the words name
    /// one of Aris's schedules by its title (certain); otherwise they only read like it, and the brain is told what to
    /// do when it turns out to be somewhere else's.
    static func note(_ kind: ArisOwnData.Kind, tools: String, task: Bool, named: Bool = false) -> String {
        let doubt = named ? "" : " If Aris has no such thing (for a schedule: `schedule list` doesn't show it) and it is clearly a booking, an alert or a " +
            "setting of some other place, site or app, say so and ask which; website work goes to Aside only with that site or place named in the brief."
        return "<aris-own-data>\nThis request \(named ? "names one of Aris's own schedules" : "reads as one about Aris's own \(ArisOwnData.noun(kind, korean: false))") " +
            "(Aris keeps its schedules and reminders, to-dos, memory, teammates, timers and settings itself). \(how(kind, tools: tools, task: task)) " +
            "The user is asked on a card where one is needed. " +
            "\(task ? "" : "Never reply with a jobs block for it, and never hand it to a teammate. ")" +
            "Never give it to Aside or the desktop (computer use): nothing of Aris's is on a website or in another app's window. " +
            "Use every name exactly as the user said it (큐에이 stays 큐에이, never QA).\(doubt)\n</aris-own-data>"
    }

    /// Said to the brain once when it answered such a turn with a jobs block.
    static func doItHere(tools: String) -> String {
        "That was a jobs block, but this request is about Aris's own data, which is never handed out. Do it yourself now with " +
            "`\(tools)` (to make a schedule: `\(tools) schedule add …`; to remove one: `\(tools) schedule list`, then `\(tools) schedule remove <id>`), then answer in a short sentence. No jobs block."
    }

    /// Whether the brain is asked once more to do it itself: only a main turn about Aris's own data whose answer hands
    /// work out, only once, and only when the turn did nothing yet (no command, no card: nothing to carry over).
    static func asksAgain(ownData: Bool, task: Bool, asked: Bool, answer: String, acted: Bool, showedCard: Bool, commands: Int) -> Bool {
        ownData && !task && !asked && !acted && !showedCard && commands == 0 && ArisDispatch.jobsBlockRange(in: answer) != nil
    }

    /// Said in place of a jobs block such a turn still answered with.
    static func keptLine(korean: Bool) -> String {
        korean ? "이건 Aris가 직접 하는 일이라 팀원한테 넘기지 않았어요. 한 번만 다시 말해 주세요."
            : "That is Aris's own to do, so I didn't hand it to a teammate. Please ask me once more."
    }

    /// The answer of a main turn about Aris's own data: a jobs block in it is never passed on (the app would hand it
    /// out); the line says so. Anything else is as it was.
    static func kept(_ answer: String, ownData: Bool, task: Bool, korean: Bool) -> String {
        guard ownData, !task, ArisDispatch.jobsBlockRange(in: answer) != nil else { return answer }
        var text = answer
        while let block = ArisDispatch.jobsBlockRange(in: text) { text.removeSubrange(block) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? keptLine(korean: korean) : text + "\n" + keptLine(korean: korean)
    }
}

/// What Aris's own stores hold, to check a job's claim against: each schedule (its id and title), each memory and each
/// teammate. To-dos (Reminders), timers and settings live in the app and can't be read here.
struct ArisOwnDataStores: Equatable {
    var schedules: [String] = []
    var memories: [String] = []
    var teammates: [String] = []

    func holds(_ kind: ArisOwnData.Kind) -> [String]? {
        switch kind {
        case .schedule: return schedules
        case .memory: return memories
        case .teammate: return teammates
        case .todo, .timer, .settings: return nil
        }
    }
}

/// A job that says it changed Aris's own data is believed only when Aris's own store shows the change (QA BUG-60: a job
/// could report "삭제했어요" for a schedule that was still there). Pure.
enum ArisOwnDataHonesty {
    /// Words that say something was changed ("삭제했어요", "deleted the reminder").
    static let claims = #"(?i)(삭제했|삭제됐|지웠|지워졌|없앴|취소했|취소됐|추가했|만들었|넣었|바꿨|수정했|멈췄|잊었|\b(deleted|removed|cancel(l)?ed|added|created|changed|updated|paused|forgot)\b)"#
    /// Words that say one was made ("예약했어요", "I've scheduled", "set that up"): read only against a request that
    /// itself asked for Aris's own data, where the store can bear them out or not.
    static let madeClaims = #"(?i)(예약했|예약해 (뒀|놨)|설정했|맞췄|\b(scheduled|set (it|that|this|them)? ?up)\b)"#

    /// The line said instead of a claim the store doesn't bear out.
    static func unchangedLine(_ kind: ArisOwnData.Kind, korean: Bool) -> String {
        let noun = ArisOwnData.noun(kind, korean: korean)
        return korean ? "\(ArisJosa.attach(noun, "을", "를")) 바꿨다는 답이 왔지만, 확인해 보니 Aris에는 바뀐 게 없어요. 저한테 직접 말해 주시면 바로 할게요."
            : "The job said it changed the \(noun), but I checked and nothing of Aris's changed. Ask me directly and I'll do it right away."
    }

    /// The line for a kind Aris can't read from here (to-dos, timers, settings).
    static func uncheckedLine(_ kind: ArisOwnData.Kind, korean: Bool) -> String {
        let noun = ArisOwnData.noun(kind, korean: korean)
        return korean ? "\(ArisJosa.attach(noun, "을", "를")) 바꿨다는 답이 왔는데, 정말 바뀌었는지는 확인하지 못했어요. 한 번 확인해 주세요."
            : "The job said it changed the \(noun), but I couldn't check that it really did. Please take a look."
    }

    /// A job's answer, as it may be passed on. `request`: the user's words for the job. When they ask for one of Aris's own
    /// things and the answer says it was changed, the answer stands only if that store did change while the job ran;
    /// otherwise the fixed line. When only the answer reads like such a change (weaker: the job was about something
    /// else), it stands, with one line saying Aris's own data didn't change. Anything else is as it was.
    static func checked(_ answer: String, request: String, scheduleNames: [String], before: ArisOwnDataStores, after: ArisOwnDataStores, korean: Bool) -> String {
        let claimsChange = answer.range(of: claims, options: .regularExpression) != nil
        if let kind = ArisOwnData.kind(of: request, scheduleNames: scheduleNames) {
            // "Scheduled", "set up" are a claim only under a request to make one: under "list my schedules" they are
            // the list itself ("… is scheduled for 2:25").
            let asksToMake = ArisOwnData.kind(of: request, scheduleNames: scheduleNames, making: false) == nil
            guard claimsChange || (asksToMake && answer.range(of: madeClaims, options: .regularExpression) != nil) else { return answer }
            guard let was = before.holds(kind), let now = after.holds(kind) else { return uncheckedLine(kind, korean: korean) }
            return was == now ? unchangedLine(kind, korean: korean) : answer
        }
        // The job was about something else: the note is added only where the answer itself reads as a change of
        // Aris's own thing, by the words that say a change and the rule that reads listing, changing and removing (as
        // before the making of a schedule was read: review 6, L6: "Your daily standup is scheduled for 9:30 every
        // morning" is no claim about Aris's schedules, and the note under it was neither asked for nor to the point).
        guard claimsChange, let kind = ArisOwnData.kind(of: answer, scheduleNames: scheduleNames, making: false),
              let was = before.holds(kind), was == after.holds(kind) else { return answer }
        let noun = ArisOwnData.noun(kind, korean: korean)
        return answer + (korean ? "\n(확인해 보니 Aris의 \(ArisJosa.attach(noun, "은", "는")) 바뀌지 않았어요.)" : "\n(I checked: Aris's own \(noun) didn't change.)")
    }
}

extension ArisOwnDataStores {
    /// The stores as they are now.
    static func live(home: String) -> ArisOwnDataStores {
        let schedules = ArisScheduleStore.load(file: ArisScheduleStore.file(home: home))
            .map { "\($0.id.uuidString)|\($0.title)" }
        return ArisOwnDataStores(schedules: schedules.sorted(), memories: ArisMemoryStore.live.all().map { "\($0.id)|\($0.text)" }.sorted(),
                                 teammates: ArisTeammateStore.load(file: ArisTeammateStore.file(home: home)).map { "\($0.id)|\($0.name)" }.sorted())
    }
}
