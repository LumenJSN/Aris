//
//  ArisJobVerdict.swift
//  Aris
//
//  Whether a handed-out job's answer is a job done. The seventh VM pass saw a green tick on a job that made no tool
//  call at all ("TextEdit 작업은 이미 진행 중이라, 끝나면 알려드릴게요"), on one that only wrote a plan ("두 가지를 따로
//  진행할게요 … [ ] …"), and on one whose typing failed ("하나를 입력하지 못했어요"). A job is done only when its answer
//  doesn't say it couldn't, isn't only a plan or a promise, and, when its task asks for something to be done on the Mac,
//  it made a tool call and no step of it failed. A job that did nothing is asked once more with a firmer instruction
//  (`firmer`) before it is reported as not done. Foundation only (tested).
//

import Foundation

enum ArisJobVerdict: Equatable {
    case done
    case notDone(Why)

    enum Why: String, Equatable {
        /// The task asks for something to be done and the job made no tool call.
        case noAction
        /// The answer says it couldn't, or didn't.
        case couldNot
        /// The answer is only a plan or a promise ("할게요", "[ ]").
        case planOnly
        /// The answer says the work is already under way elsewhere.
        case alreadyRunning
        /// A step of it failed or wasn't done.
        case stepFailed
    }

    /// Words of a task that asks for something to be done on the Mac (any app, any window), Korean and English.
    private static let koreanActs = ["입력", "눌러", "누르기", "누르고", "누를", "클릭", "열어", "닫아", "보내", "추가해", "옮겨", "지워", "삭제", "저장해", "붙여 넣", "붙여넣",
                                     "바꿔", "설정해", "켜 줘", "켜줘", "꺼 줘", "꺼줘", "실행해", "예약해", "등록해", "올려", "내려받", "다운로드", "이동해"]
    private static let englishActs = ["type ", "press ", "click ", "open ", "close ", "send ", "add ", "move ", "delete ", "remove ", "save ",
                                      "paste ", "rename ", "turn on ", "turn off ", "launch ", "book ", "upload ", "download ", "fill in "]
    /// "…하지 못했어요", "couldn't", "unable": it says it wasn't done.
    private static let couldNotWords = ["못했", "못 했", "못 해", "못해", "못 눌", "못 입력", "할 수 없", "수 없었", "실패", "안 됐", "안됐", "되지 않", "않았어", "않았습니다",
                                        "아직 눌리지", "아직 입력되지", "couldn't", "could not", "can't", "cannot", "unable", "failed", "wasn't able",
                                        "was not able", "didn't", "did not", "not typed", "not done", "nothing was done"]
    /// "…진행할게요", "I'll …", a checklist: only a plan.
    private static let planWords = ["할게요", "할께요", "하겠습니다", "하겠어요", "진행할게", "드릴게요", "알려드릴게", "알려 드릴게", "예정이에요", "예정입니다",
                                    "[ ]", "i'll ", "i will ", "i'm going to", "will do", "let you know when", "plan:"]
    private static let runningWords = ["이미 진행 중", "이미 진행중", "이미 하고 있", "이미 작업 중", "already in progress", "already running", "already working on",
                                       "already under way", "already underway"]

    /// Whether `task` asks for something to be done (not only found, read or answered).
    static func asksForAction(_ task: String) -> Bool {
        let lowered = " " + task.lowercased() + " "
        return koreanActs.contains(where: lowered.contains) || englishActs.contains { lowered.contains(" " + $0) }
    }

    /// The verdict on a job's `answer` to `task`; `work`: what the agent counted (nil from an agent that doesn't say).
    static func judge(task: String, answer: String, work: ArisJobWork?) -> ArisJobVerdict {
        let lowered = answer.lowercased()
        if runningWords.contains(where: lowered.contains), (work?.tools ?? 0) == 0 { return .notDone(.alreadyRunning) }
        if couldNotWords.contains(where: lowered.contains) { return .notDone(.couldNot) }
        if let work, work.failed > 0, !work.acted { return .notDone(.stepFailed) }
        let tools = work?.tools ?? 0
        if tools == 0, planWords.contains(where: lowered.contains) { return .notDone(.planOnly) }
        if let work, work.tools == 0, asksForAction(task) { return .notDone(.noAction) }
        return .done
    }

    /// Whether a not-done job is asked once more (it did nothing yet; a failed step or a "couldn't" after real work is
    /// reported as it is).
    static func retries(_ why: Why, work: ArisJobWork?) -> Bool {
        switch why {
        case .noAction, .planOnly, .alreadyRunning: return true
        case .couldNot: return (work?.tools ?? 0) == 0
        case .stepFailed: return false
        }
    }

    /// The firmer instruction the second try gets after the job's own words.
    static func firmer(korean: Bool) -> String {
        korean
            ? "\n\n[Aris] 지난번 답은 일을 하지 않았어요. 이 작업은 다른 곳에서 진행 중이 아니에요. 계획이나 약속만 말하지 말고, 지금 도구를 직접 써서 이 일을 끝까지 하세요. 할 수 없으면 왜 못 하는지 정확히 말하세요."
            : "\n\n[Aris] The last answer did not do the work. Nothing else is doing this task. Don't only describe a plan or promise to do it: use your tools now and do it to the end. If it can't be done, say exactly why."
    }

    /// Why it wasn't done, in the job's card and its tray row.
    static func reason(_ why: Why, korean: Bool) -> String {
        switch why {
        case .noAction: korean ? "아무 작업도 하지 않고 끝났어요." : "It ended without doing anything."
        case .couldNot: korean ? "하지 못했다고 답했어요." : "It said it couldn't do it."
        case .planOnly: korean ? "계획만 말하고 실제로 하지는 않았어요." : "It only described a plan and didn't do it."
        case .alreadyRunning: korean ? "이미 진행 중이라고만 하고 하지 않았어요." : "It said it was already in progress and didn't do it."
        case .stepFailed: korean ? "단계 하나가 실패해서 끝내지 못했어요." : "A step failed, so it wasn't finished."
        }
    }

    /// The card's button that hands the job out again.
    static func retryTitle(english: Bool) -> String { english ? "Try again" : "다시 시도" }
    /// The card's title for a job that wasn't done.
    static func notDoneTitle(_ title: String, english: Bool) -> String { (english ? "Not done: " : "못 끝냄: ") + title }
}
