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
//  The owner, 2026-11-19: a correct, complete list of the Canvas assignments he hadn't submitted came back red, because
//  any negative anywhere in the answer ("아직 제출하지 않았어요", "the build didn't fail") counted as "it couldn't". What
//  the job says about itself is read apart from what it reports (ArisJobSaid): the agent's own count comes first (a
//  step that failed with nothing done, the agent it handed the work to that came back without an answer); a task that
//  only asks to find, read, check or tell is "couldn't" only when the job says so about its own doing and brought
//  nothing back (a result with a caveat is a result); a task that asks for something done on the Mac stays strict.
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
                                     "바꿔", "설정해", "켜 줘", "켜줘", "꺼 줘", "꺼줘", "실행해", "예약해", "등록해", "올려", "내려받", "다운로드", "이동해",
                                     // Ordering and paying (twelfth VM run, A2: "쿠팡에서 생수 주문 완료해 줘" with no step at all was "done").
                                     "주문해", "주문 완료", "결제해", "결제까지", "구매해", "구입해", "사 줘", "사줘", "장바구니에 담", "담아 줘", "완료해"]
    private static let englishActs = ["type ", "press ", "click ", "open ", "close ", "send ", "add ", "move ", "delete ", "remove ", "save ",
                                      "paste ", "rename ", "turn on ", "turn off ", "launch ", "book ", "upload ", "download ", "fill in ",
                                      "buy ", "order ", "purchase ", "check out", "checkout", "pay "]
    private static let runningWords = ["이미 진행 중", "이미 진행중", "이미 하고 있", "이미 작업 중", "already in progress", "already running", "already working on",
                                       "already under way", "already underway"]

    /// Whether `task` asks for something to be done (not only found, read or answered).
    static func asksForAction(_ task: String) -> Bool {
        let lowered = " " + task.lowercased() + " "
        return koreanActs.contains(where: lowered.contains) || englishActs.contains { lowered.contains(" " + $0) }
    }

    /// The verdict on a job's `answer` to `task`; `work`: what the agent counted (nil from an agent that doesn't say:
    /// never read as "no tools").
    static func judge(task: String, answer: String, work: ArisJobWork?) -> ArisJobVerdict {
        let lowered = answer.lowercased()
        let read = ArisJobSaid.read(task: task, answer: answer)
        let acts = asksForAction(task)
        let tools = work?.tools ?? 0
        if runningWords.contains(where: lowered.contains), tools == 0, read.results == 0 { return .notDone(.alreadyRunning) }
        if saysItCouldNot(read, acts: acts, work: work) { return .notDone(.couldNot) }
        if let work, work.failed > 0, !work.acted { return .notDone(.stepFailed) }
        if tools == 0, read.plans > 0, read.results == 0, read.rest < ArisJobSaid.planRest { return .notDone(.planOnly) }
        if let work, work.tools == 0, acts { return .notDone(.noAction) }
        // The agent it handed the work to (Aside) came back without an answer, and nothing else came of it.
        if work?.delegated == false, read.results == 0, read.rest < ArisJobSaid.longReport { return .notDone(.stepFailed) }
        return .done
    }

    /// The job says it couldn't. An action on the Mac left undone is not done, whatever else was; a find, read, check
    /// or tell is "couldn't" only when the job's own failure stands alone: it leads the answer, or nothing but a few
    /// words came with it (no result line, no partial "…은 확인했고", no long report; after the agent it handed the work
    /// to finished with an answer, only a failure that leads).
    private static func saysItCouldNot(_ read: ArisJobSaid.Reading, acts: Bool, work: ArisJobWork?) -> Bool {
        guard !read.failures.isEmpty else { return false }
        if acts { return true }
        if read.partial || read.results > 0 { return false }
        if read.leadsWithFailure { return true }
        return work?.delegated != true && read.rest < ArisJobSaid.longReport
    }

    /// Whether a not-done job is asked once more (it did nothing yet; a failed step or a "couldn't" after real work is
    /// reported as it is). Never a job that stopped acting (his no on its card, no answer, a hand-off that didn't go
    /// through), nor one about paying that said it couldn't (that is the payment boundary answering: twelfth VM run, B3
    /// and B4, where the second try was pushed on after his no and after a refusal to pay).
    static func retries(_ why: Why, work: ArisJobWork?, task: String = "") -> Bool {
        if work?.stopped == true { return false }
        if why == .couldNot, ArisPaymentBoundary.involves(task) { return false }
        switch why {
        case .noAction, .planOnly, .alreadyRunning: return true
        case .couldNot: return (work?.tools ?? 0) == 0
        case .stepFailed: return false
        }
    }

    /// The firmer instruction the second try gets after the job's own words.
    static func firmer(korean: Bool) -> String {
        korean
            ? "\n\n[Aris] 지난번 답은 일을 하지 않았어요. 이 작업은 다른 곳에서 진행 중이 아니에요. 계획이나 약속만 말하지 말고, 지금 도구를 직접 써서 지켜야 할 규칙 안에서 할 수 있는 만큼 하세요. 거절된 일이나 할 수 없는 일은 다시 시도하지 말고, 왜 못 하는지 정확히 말하세요."
            : "\n\n[Aris] The last answer did not do the work. Nothing else is doing this task. Don't only describe a plan or promise to do it: use your tools now for what may be done within every rule you were given. Don't try again what was refused or can't be done; say exactly why."
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

    /// A not-done job's tray row and reader: why, then what it answered, so the answer stays readable.
    static func shownNotDone(reason: String, answer: String) -> String {
        answer.isEmpty ? reason : reason + "\n\n" + answer
    }

    /// The card's button that hands the job out again.
    static func retryTitle(english: Bool) -> String { english ? "Try again" : "다시 시도" }
    /// The card's title for a job that wasn't done.
    static func notDoneTitle(_ title: String, english: Bool) -> String { (english ? "Not done: " : "못 끝냄: ") + title }
}
