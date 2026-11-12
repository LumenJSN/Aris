// Tests for dispatch after a finished job and for the user's own teammates (2026-11-07): one finished job no longer keeps
// every later conversation from handing work out, and the teammates the user adds on the 팀원 page are offered to the
// brain and dispatched like Claude Code. Called from main.swift; uses its check().
import Foundation

func runTeamDispatchTests() {
    jobContextTests()
    customTeammateTests()
}

private func jobContextTests() {
    typealias C = ArisJobContext
    let done = ArisBackgroundTask(title: "가격 조사", state: .done("아이폰 16은 129만 원"))
    let failed = ArisBackgroundTask(title: "메일 정리", state: .failed("시간 초과"))
    let working = ArisBackgroundTask(title: "보고서 요약", state: .working("파일 읽는 중"))
    // In the conversation the job finished in: its words are outside text (the agent sees "(done:"), as before.
    let now = C.lines([done, working], putAway: [])
    check(now.outside && now.lines.contains(done.contextLine) && now.lines.contains(working.contextLine),
          "job context: a job that finished in this conversation is in it, and the conversation is outside text")
    // The conversation ends (닫기, or the quiet): what had finished is put away for every later one.
    let away = C.puttingAway([done, failed, working], into: [])
    check(away == [done.id, failed.id], "job context: a conversation's end puts away the finished jobs, never a running one")
    let later = C.lines([done, failed, working], putAway: away)
    check(!later.outside && later.lines == [working.contextLine] && !later.lines.joined().contains("(done:")
          && !later.lines.joined().contains("(failed:"),
          "job context: the next conversation carries no finished job's words, so it may dispatch again")
    // A job that finishes during the new conversation still marks it, until it ends in turn.
    let finishedNow = ArisBackgroundTask(id: working.id, title: working.title, state: .done("요약 끝"))
    check(C.lines([done, failed, finishedNow], putAway: away).outside, "job context: a job finishing later marks that conversation")
    // Bounded: ids of jobs no longer kept are let go.
    check(C.puttingAway([working], into: away).isEmpty, "job context: put-away ids of jobs no longer listed are dropped")
}

private func customTeammateTests() {
    let codi = ArisTeammate(id: "mate-ab12cd", name: "코디", role: "문서 정리 담당", look: .standard, brain: "codex",
                            memoryFile: "teammates/mate-ab12cd.md")
    let team = [ArisTeammate.claudeCode, codi]
    // The brain is offered every teammate the user has, each with its role, and how to point it at its window.
    let block = ArisAgentPrompt.teammates(team, home: "/Users/p", addressed: nil)
    check(block.contains("\"mate-ab12cd\" (코디)") && block.contains("문서 정리 담당") && block.contains("\"claude-code\"")
          && block.contains("appHint"), "teammates prompt: the user's own teammate is offered with its role, and its job names its app")
    check(ArisAgentPrompt.teammates(team, home: "/Users/p", addressed: ArisTeamRouting.addressee(in: "코디야 문서 정리해 줘", teammates: team))
            .contains("hand this request to \"mate-ab12cd\""), "teammates prompt: \"코디야 …\" hands the request to 코디")
    // The app takes a jobs block's teammate ids from the list it has (Claude Code always among them).
    let ids = ArisDispatch.teammateIds(team)
    check(ids == ["claude-code", "mate-ab12cd"] && ArisDispatch.teammateIds([]) == ["claude-code"],
          "dispatch ids: every listed teammate, and Claude Code even before the list is in")
    let reply = "```json\n{\"jobs\":[{\"title\":\"소개글\",\"prompt\":\"세 문장\",\"assignee\":\"mate-ab12cd\",\"appHint\":\"TextEdit\"},"
        + "{\"title\":\"x\",\"prompt\":\"y\",\"assignee\":\"mate-zzzzzz\"}]}\n```"
    let specs = ArisDispatch.parse(reply, teammateIds: ids)
    check(specs?.count == 2 && specs?[0].assignee == .teammate("mate-ab12cd") && specs?[0].appHint == "TextEdit" && specs?[1].assignee == .clone,
          "dispatch: the user's teammate takes its job (its window named); an id nobody has is Aris's own clone")
    // One job for a teammate from a clean turn (team v2): the user's words as said, on the teammate's brain, its window kept.
    let plan = ArisHandOutPlan.plan([specs![0]], turn: ArisHandOutPlan.Turn(words: "코디한테 소개글 쓰라고 해", brain: .claude, turnId: "t1"),
                                    brains: ["mate-ab12cd": .codex])
    check(plan.count == 1 && plan[0].spec.assignee == .teammate("mate-ab12cd") && plan[0].spec.appHint == "TextEdit"
          && plan[0].brain == .codex && !plan[0].provenance.untrusted && plan[0].spec.prompt == "코디한테 소개글 쓰라고 해",
          "hand-out: a teammate's one job keeps its teammate and window, as the user's own words on its own brain")
}
