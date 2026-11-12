// Tests for the 2026-11-10 audit's confirm-card and background-job findings on the app side (qa/audit-1110/turn.json
// card-*, team.json team-*, imp-*). Called from main.swift; uses its check(). Pure rules and fakes only: no job, brain,
// card, microphone, window or message is ever started, and every file written is in a throwaway folder.
import AppKit
import Foundation

func runFixCardsTests() {
    coveredCardTests()
    waitingCardsTests()
    unansweredReplyTests()
    lostJobsTests()
    failedJobTests()
    jobRoutingTests()
    overlayOwnerTests()
    countdownTruthTests()
    teamSaveFailureTests()
    windowHiccupTests()
    cardsWiringTests()
}

private func cardsSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

// MARK: - card-1: a card that is not on screen is never answerable

private func coveredCardTests() {
    typealias C = ArisCardCover
    check(C.isUp(card: "job-1", shown: "job-1") && !C.isUp(card: "job-1", shown: nil) && !C.isUp(card: "job-1", shown: "turn-9"),
          "card-1: a card is up only while it is the question the notch shows")
    check(C.answer(true, card: "job-1", shown: "job-1") == true && C.answer(false, card: "job-1", shown: "job-1") == false,
          "card-1: a click, Y or N answers the card on screen")
    check(C.answer(true, card: "job-1", shown: "turn-9") == nil && C.answer(true, card: "job-1", shown: nil) == nil,
          "card-1: a job's card that the user's turn covered never takes the yes he gave another card (or any click at all)")
    check(C.answer(nil, card: "job-1", shown: "job-1") == nil, "card-1: no click is no answer")
    check(C.ownsKeys(card: "job-1", shown: "job-1") && C.ownsKeys(card: "job-1", shown: nil) && !C.ownsKeys(card: "job-1", shown: "turn-9"),
          "card-1: a covered card's wait ends without clearing the answer slot or the Y/N keys of the card now on screen")
    check(C.stillOwn(title: "메일 초안", heard: "메일 초안", speaking: true) && !C.stillOwn(title: "메일 초안", heard: "오늘 날씨 어때", speaking: true)
          && !C.stillOwn(title: "메일 초안", heard: "메일 초안", speaking: false),
          "card-1: an announcement that ended under the user's turn never puts his turn's notch back to idle")

    // The one log line of a covered card: no answer, never a yes or a no.
    let source = ArisCardAnswer.source(typed: .click, heard: true, unanswered: true, ended: false, countdown: false, cancelled: false, covered: true)
    check(source == .covered && ArisCardAnswer.line(allow: false, source: source) == "card answer: no answer (covered)" && source.isNoAnswer,
          "card-1: a covered card is logged as no answer, whatever click came for the card after it")
    check(ArisCardAnswer.source(typed: .click, heard: false, unanswered: false, ended: false, countdown: false, cancelled: false) == .click
          && !ArisCardAnswer.Source.click.isNoAnswer && !ArisCardAnswer.Source.voice.isNoAnswer
          && ArisCardAnswer.Source.unanswered.isNoAnswer && ArisCardAnswer.Source.ended.isNoAnswer && ArisCardAnswer.Source.cancelled.isNoAnswer,
          "card-1: an answered card is still logged by where its answer came from")
}

// MARK: - card-1, card-2 = team-1, imp-3: 확인 대기

private func waitingCardsTests() {
    typealias P = ArisParkedAsk
    // What a showing's end means for a question the agent holds for a day.
    check(P.next(.yes) == .send(true) && P.next(.no) == .send(false), "card-2: the user's own yes or no goes to the agent")
    check(P.next(.unanswered) == .park(.unanswered),
          "card-2 / team-1: a job's card nobody answers is parked, never sent to the agent as the user's no")
    check(P.next(.covered) == .park(.covered), "card-1: a card the user's turn covered is parked, never answered for him")
    check(P.next(.ended) == .gone, "card-2: a question the agent stopped waiting for is dropped without an answer")
    let ends: [ArisCardEnd] = [.unanswered, .covered, .ended]
    check(ends.allSatisfy { P.next($0) != .send(false) && P.next($0) != .send(true) }, "card-2: only an answer the user gave is ever sent")

    // When a parked card comes back.
    check(P.returns(why: .covered, shows: 1, opened: false, userTurnSince: false) == .show(quiet: false),
          "card-1: a covered card comes back by itself at the next pause")
    check(P.returns(why: .covered, shows: P.selfShows, opened: false, userTurnSince: true) == .wait,
          "card-1: covered a second time, it stays in 확인 대기 instead of coming up after every turn")
    check(P.returns(why: .unanswered, shows: 1, opened: false, userTurnSince: false) == .wait,
          "card-2: a card nobody answered is not asked again into an empty room")
    check(P.returns(why: .unanswered, shows: 1, opened: false, userTurnSince: true) == .show(quiet: false),
          "card-2: it is asked once more after the user's next turn (he is at the Mac again)")
    check(P.returns(why: .unanswered, shows: P.selfShows, opened: false, userTurnSince: true) == .wait,
          "card-2: after that it only waits for his click")
    check(P.returns(why: .unanswered, shows: 5, opened: true, userTurnSince: false) == .show(quiet: true)
          && P.returns(why: .covered, shows: 0, opened: true, userTurnSince: false) == .show(quiet: true),
          "imp-3: a click on the chip always brings the card back, shown without being read aloud")
    check(P.selfShows == 2, "imp-3: a question is read aloud at most twice by itself")

    // The list behind the chips.
    let job = UUID(), at = Date(timeIntervalSince1970: 1_800_000_000)
    let mail = ArisWaitingCard(id: "q1", title: "조사해서 메일 보내 놔", action: "메일 보내기", job: job, why: .unanswered, since: at)
    let schedule = ArisWaitingCard(id: "q2", title: "아침 브리핑", action: "Safari 사용", job: nil, why: .covered, since: at)
    var list = ArisWaitingList()
    check(list.isEmpty && list.jobs.isEmpty, "imp-3: nothing waits at first")
    list = list.parking(mail).parking(schedule)
    check(list.cards == [mail, schedule] && list.jobs == [job] && !list.isEmpty, "imp-3: a job's and a schedule's question wait side by side, oldest first")
    check(list.opening("q1").isOpened("q1") && !list.opening("q1").isOpened("q2") && !list.opening("nope").isOpened("nope"),
          "imp-3: only a card that waits here can be opened")
    let again = ArisWaitingCard(id: "q1", title: mail.title, action: mail.action, job: job, why: .covered, since: at.addingTimeInterval(60))
    let reparked = list.opening("q1").parking(again)
    check(reparked.cards == [again, schedule] && !reparked.isOpened("q1"), "imp-3: a card parked again keeps its place, and waits for a new click")
    check(list.opening("q1").removing("q1").cards == [schedule] && !list.opening("q1").removing("q1").isOpened("q1") && list.removing("q1").jobs.isEmpty,
          "imp-3: a card that is back on screen, answered or no longer wanted leaves 확인 대기")

    check(P.chipLead(english: false) == "확인 대기" && P.chipDetail(mail) == "· 조사해서 메일 보내 놔: 메일 보내기",
          "imp-3: the chip says what waits, whose question it is and what it asks")
    check(P.chipDetail(ArisWaitingCard(id: "q3", title: "메일 보내기", action: "메일 보내기", job: nil, why: .covered, since: at)) == "· 메일 보내기"
          && !P.chipLead(english: true).isEmpty && !P.chipHelp(english: false).isEmpty, "imp-3: a title that already says it isn't said twice")
}

// MARK: - card-3: the rest of the answer survives an unanswered card

private func unansweredReplyTests() {
    typealias W = ArisCardWait
    let compared = "두 노트북을 비교했어요. A는 129만 원, B는 119만 원이라 B가 더 싸요. 장바구니 담기는 승인을 받지 못해서 하지 않았어요."
    let kept = W.replyAfterCards(compared, unanswered: true, declined: false, korean: true)
    check(kept.hasPrefix("확인이 없어서 그 부분은 하지 않았어요.") && kept.contains("B가 더 싸요") && !kept.contains("승인을 받지 못해서"),
          "card-3: what the turn found is kept after the unanswered line, without the sentence that blames the missing approval")
    check(W.replyAfterCards("x", unanswered: true, declined: false, korean: true) == "답이 없어서 하지 않았어요."
          && W.replyAfterCards("", unanswered: true, declined: false, korean: true) == "답이 없어서 하지 않았어요."
          && W.replyAfterCards("폴더 만들기가 거부되어 qa-test 폴더를 만들지 못했어요.", unanswered: true, declined: false, korean: true) == "답이 없어서 하지 않았어요.",
          "card-3: an answer that only says it was refused, or says nothing, is still the fixed unanswered line")
    check(W.replyAfterCards("The folder request was declined.", unanswered: true, declined: false, korean: false) == "No answer, so I didn't do it.",
          "card-3: the same in English")
    let english = W.replyAfterCards("I compared both laptops: B is cheaper at $899. I didn't get a confirmation, so nothing was added to the cart.",
                                    unanswered: true, declined: false, korean: false)
    check(english.hasPrefix(W.unansweredPartLine(korean: false)) && english.contains("B is cheaper at $899.") && !english.contains("confirmation"),
          "card-3, English: the comparison stays, the blame for the missing answer goes")
    let list = "찾은 파일이에요.\n- 보고서.pdf\n- 예산 3.5 버전.xlsx\n\n삭제는 확인이 없어서 하지 않았어요."
    let listed = W.replyAfterCards(list, unanswered: true, declined: false, korean: true)
    check(listed.contains("- 보고서.pdf\n- 예산 3.5 버전.xlsx") && !listed.hasSuffix("\n") && !listed.contains("삭제는"),
          "card-3: a list keeps its lines (a decimal point is no sentence end)")
    check(W.replyAfterCards(compared, unanswered: false, declined: false, korean: true) == compared
          && W.replyAfterCards("요청이 거부되어 폴더를 만들지 않았어요.", unanswered: false, declined: true, korean: true) == "알겠어요, 안 할게요.",
          "card-3: a turn with no unanswered card is told as before")
}

// MARK: - team-2: jobs under way are kept on disk, and a relaunch says what it cut off

private func job(_ title: String, _ state: ArisJobState, assignee: ArisJobAssignee = .clone, id: UUID = UUID()) -> ArisJob {
    ArisJob(id: id, title: title, prompt: "the prompt, never saved", assignee: assignee, cwd: nil, appHint: nil, target: .notch, state: state,
            created: Date(timeIntervalSince1970: 1_800_000_000))
}

private func lostJobsTests() {
    typealias L = ArisJobLedger
    let running = job("블랙홀 자료 정리", .running(step: "웹 검색 중")), queued = job("메일 초안", .queued), asking = job("예약 확인", .awaitingApproval(id: "q"))
    let code = job("버그 고치기", .running(step: "Claude Code 작업 중"), assignee: .teammate(ArisTeammate.claudeCodeId))
    let all = [job("끝난 일", .done("했어요")), running, job("실패", .failed("x")), queued, job("취소", .cancelled), asking, code]
    let records = L.unfinished(all)
    check(records.map(\.id) == [running.id, queued.id, asking.id, code.id] && records.map(\.claudeCode) == [false, false, false, true],
          "team-2: the jobs still running, waiting or asking are the ones saved; finished ones are not")
    let encoded = String(data: (try? JSONEncoder().encode(records)) ?? Data(), encoding: .utf8) ?? ""
    check(!encoded.contains("never saved") && encoded.contains("블랙홀 자료 정리"), "team-2: a job's prompt is never written to disk, only its name")

    let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-fix-cards-\(UUID().uuidString)")
    let file = folder.appendingPathComponent("Aris/jobs.json")
    defer { try? FileManager.default.removeItem(at: folder) }
    check(L.load(from: file).isEmpty, "team-2: no file, nothing was lost")
    L.note(all, to: file)
    check(L.load(from: file) == records, "team-2: what is under way is on disk as soon as it is handed out")
    let mode = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.posixPermissions] as? Int
    check(mode == 0o600, "team-2: the file is the user's alone")
    // A crash here: the next launch reads the same four.
    let lost = L.load(from: file)
    check(lost.count == 4, "team-2: a relaunch finds the jobs the last run left unfinished")
    L.note([job("끝난 일", .done("했어요"))], to: file)
    check(!FileManager.default.fileExists(atPath: file.path) && L.load(from: file).isEmpty,
          "team-2: once nothing is under way the file is gone, so a launch reports a loss only once")
    try? "not json".write(to: file, atomically: true, encoding: .utf8)
    check(L.load(from: file).isEmpty, "team-2: a file that can't be read reports nothing rather than failing the launch")

    // What the user is told.
    check(L.lostLine(lost[0], korean: true).contains("다시 시작") && L.lostLine(lost[0], korean: true).contains("다시 맡겨"),
          "team-2: a lost job's 기록 entry says it was cut off and to hand it over again")
    check(L.lostLine(lost[3], korean: true).contains("터미널") && !L.lostLine(lost[3], korean: true).contains("다시 맡겨"),
          "team-2: a Claude Code job is said to be still open in its terminal, not cut off")
    check(L.lostSaid([lost[0]], korean: true).contains("‘블랙홀 자료 정리’") && L.lostSaid(lost, korean: true).contains("4개")
          && L.lostSaid([lost[3]], korean: true).contains("터미널") && L.lostSaid([], korean: true).isEmpty && !L.lostSaid(lost, korean: false).isEmpty,
          "team-2: one line is said for all of them: the job by name, or how many")
    check(L.lostTitle([lost[0]], korean: true) == "블랙홀 자료 정리" && L.lostTitle(lost, korean: true) == "끊긴 일 4개", "team-2: the notch opens on the job's name, or the count")
    let shown = L.lostJobs(lost, korean: { _ in true })
    check(shown.map(\.id) == lost.map(\.id) && shown.allSatisfy { if case .failed(let why) = $0.state { !why.isEmpty } else { false } }
          && shown.allSatisfy { $0.prompt.isEmpty } && L.unfinished(shown).isEmpty,
          "team-2: the lost jobs show in the done chip as failed with what happened, and are not counted as under way again")
    // The hand-out's 기록 entry becomes the loss, in place.
    let handed = ArisHistoryEntry(date: Date(timeIntervalSince1970: 1_800_000_000), heard: "블랙홀 자료 조사해서 정리해 놔", reply: "제가 맡았어요, 끝나면 알려줄게요.", job: lost[0].id)
    let after = ArisHistory.finishing(job: lost[0].id, title: lost[0].title, shown: L.lostLine(lost[0], korean: true), file: nil, in: [handed])
    check(after.count == 1 && after[0].heard == handed.heard && after[0].reply.contains("끊겼어요") && !after[0].reply.contains("맡았어요"),
          "team-2: the 기록 entry no longer reads as if the work were still under way")
}

// MARK: - team-3: a failed job says why, and its 기록 entry changes

private func failedJobTests() {
    typealias F = ArisJobFailure
    let login = "Gemini 로그인이 필요해요: 터미널에서 agy 를 한 번 실행해 주세요"
    check(F.said(title: "소개글 쓰기", reason: F.reason(login), korean: true) == "소개글 쓰기, 못 끝냈어요. \(login)",
          "team-3: the user hears the job by name and the agent's own reason, not only “못 끝냈어요”")
    check(F.said(title: "소개글 쓰기", reason: "", korean: true) == "소개글 쓰기, 못 끝냈어요." && F.said(title: "Write intro", reason: "", korean: false) == "I couldn't finish: Write intro.",
          "team-3: with no reason, the line is as before")
    let dropped = ArisJobLoss.dropped("소개글 쓰기")
    check(F.said(title: "소개글 쓰기", reason: F.reason(dropped), korean: true) == dropped, "team-3: a reason that already names the job is said once")
    check(F.shown(reason: F.reason(login), korean: true) == "못 끝냈어요: \(login)" && F.shown(reason: "", korean: true) == "못 끝냈어요."
          && F.shown(reason: "quota", korean: false) == "Not finished: quota", "team-3: the 기록 entry says it failed and why")
    let long = String(repeating: "아주 긴 오류 줄 ", count: 60)
    check(F.reason(long).count <= F.longestReason + 1 && F.reason(long).hasSuffix("…") && F.reason("첫 줄\n\n  둘째 줄  ") == "첫 줄 둘째 줄" && F.reason("  \n ").isEmpty,
          "team-3: a long or many-line reason is one short paragraph")
    check(F.cutOff(korean: true).contains("끊겼어요") && F.cutOff(korean: true).contains("다시 맡겨") && !F.cutOff(korean: false).isEmpty,
          "team-3: a job whose stream ended with neither an answer nor an error says it was cut off")
    let handed = ArisHistoryEntry(date: Date(), heard: "소개글 써 놔", reply: "코디가 맡았어요, 끝나면 알려줄게요.", job: UUID())
    let after = ArisHistory.finishing(job: handed.job!, title: "소개글 쓰기", shown: F.shown(reason: login, korean: true), file: nil, in: [handed])
    check(after.count == 1 && after[0].reply == "못 끝냈어요: \(login)" && after[0].heard == "소개글 써 놔", "team-3: the hand-out's 기록 entry becomes the failure")

    let team = cardsSource("Aris/private/Aris/ArisController+Team.swift"), mate = cardsSource("Aris/private/Aris/ArisController+Teammate.swift")
    let failure = team.components(separatedBy: "func reportFailure(").last ?? ""
    check(failure.contains("pastTurns = ArisHistory.finishing(job: job.id") && failure.contains("ArisJobFailure.said(title: job.title, reason: reason"),
          "team-3: every failed job is written to 기록 and said with its reason")
    check(!team.contains(".failed(\"중단됨\")") && !mate.contains(".failed(\"중단됨\")")
          && team.contains("await reportFailure(job, ArisJobFailure.cutOff(") && mate.contains("await reportFailure(job, ArisJobFailure.cutOff("),
          "team-3: a stream that ends without an answer (Aris's own job or a Claude Code job before its launch) is announced and recorded, never a silent “중단됨”")
}

// MARK: - team-7, imp-4: which brain a job asks for

private func jobRoutingTests() {
    typealias R = ArisJobRouting
    check(R.brain(forDispatched: .claude) == .codex && R.brain(forDispatched: .antigravity) == .codex && R.brain(forDispatched: .codex) == .codex,
          "team-7: with every brain set up, an untrusted job of a Claude, Gemini or Codex turn asks for Codex, where the agent runs it gated")
    check(R.brain(forDispatched: .api) == .api, "team-7: an API-brain turn's job stays on the API brain (it is gated itself): no Codex needed")
    let noCodex = ["codex": false, "claude": true, "api": true, "antigravity": true]
    check(R.brain(forDispatched: .claude, ready: noCodex) == .api && R.brain(forDispatched: .antigravity, ready: noCodex) == .api,
          "team-7: without Codex on this Mac, the job asks for the API brain instead of failing on a GPT login line")
    check(R.brain(forDispatched: .api, ready: ["api": false, "codex": true]) == .codex, "team-7: an API brain that isn't set up falls back to Codex")
    let neither = ["codex": false, "api": false, "claude": true]
    check(R.brain(forDispatched: .claude, ready: neither) == .claude,
          "team-7: with neither gated brain here the job asks for the turn's own brain, so it says what is missing")
    check(R.isReady(.claude, [:]) && R.isReady(.codex, ["claude": false]) && !R.isReady(.codex, ["codex": false]),
          "team-7: a brain the agent said nothing about counts as set up")

    // The plans carry it.
    let words = "A랑 B 동시에 조사해줘"
    let specs = [ArisJobSpec(title: "a", prompt: "A 조사", assignee: .clone, cwd: nil, appHint: nil), ArisJobSpec(title: "b", prompt: "B 조사", assignee: .clone, cwd: nil, appHint: nil)]
    let clean = ArisHandOutPlan.Turn(words: words, brain: .claude, turnId: "t1")
    check(ArisHandOutPlan.plan(specs, turn: clean, ready: noCodex).allSatisfy { $0.brain == .api && $0.provenance.untrusted }
          && ArisHandOutPlan.plan(specs, turn: clean).allSatisfy { $0.brain == .codex && $0.provenance.untrusted },
          "team-7: parallel helpers ask for a gated brain that is here, still untrusted")
    let screen = ArisHandOutPlan.Turn(words: "이거 정리해 놔", brain: .antigravity, turnId: nil, screenConversation: true)
    let unclean = ArisHandOutPlan.plan([], turn: screen, ready: noCodex)
    check(unclean.count == 1 && unclean[0].brain == .api && unclean[0].provenance.untrusted && unclean[0].cleanContext && unclean[0].provenance.screenConversation,
          "team-7: a hand-out after a screen turn does too, with every safety mark it had (untrusted, no conversation, the screen claim)")
    let apiTurn = ArisHandOutPlan.Turn(words: "이거 정리해 놔", brain: .api, turnId: nil, outsideConversation: true)
    check(ArisHandOutPlan.plan([], turn: apiTurn).first?.brain == .api, "team-7: an API-brain turn's unclean hand-out runs on the API brain")
    let one = ArisHandOutPlan.plan([], turn: ArisHandOutPlan.Turn(words: "조사해서 정리해 놔", brain: .claude, turnId: nil), ready: noCodex)
    check(one.count == 1 && one[0].brain == .claude && !one[0].provenance.untrusted, "team-7: the user's own clean single job stays on his brain, trusted, as before")

    // imp-4: a teammate whose own brain isn't set up.
    let brains: [String: ArisBrain] = ["mate-c": .antigravity, "mate-d": .claude]
    let noGemini = ["antigravity": false, "claude": true, "codex": true]
    let called = [ArisJobSpec(title: "정리", prompt: "코디, 이 폴더 정리해줘", assignee: .teammate("mate-c"), cwd: nil, appHint: "Finder")]
    let fallen = R.withoutUnreadyTeammates(called, brains: brains, ready: noGemini)
    check(fallen.fellBack == ["mate-c"] && fallen.specs.count == 1 && fallen.specs[0].assignee == .clone && fallen.specs[0].prompt == called[0].prompt
          && fallen.specs[0].appHint == "Finder", "imp-4: a teammate whose brain isn't set up hands its job to Aris itself")
    let plan = ArisHandOutPlan.plan(fallen.specs, turn: ArisHandOutPlan.Turn(words: "코디, 이 폴더 정리해줘", brain: .claude, turnId: nil), brains: brains, ready: noGemini)
    check(plan.count == 1 && plan[0].brain == .claude && plan[0].spec.assignee == .clone && !plan[0].provenance.untrusted,
          "imp-4: that job runs on the turn's brain as the user's own words")
    let ready = R.withoutUnreadyTeammates(called, brains: brains, ready: ["antigravity": true])
    check(ready.fellBack.isEmpty && ready.specs == called && R.withoutUnreadyTeammates(called, brains: brains, ready: [:]).specs == called,
          "imp-4: a teammate whose brain is set up (or not yet known) keeps its job")
    let code = [ArisJobSpec(title: "x", prompt: "fix", assignee: .teammate(ArisTeammate.claudeCodeId), cwd: "/p", appHint: nil)]
    check(R.withoutUnreadyTeammates(code, brains: brains, ready: ["claude": false]).specs == code, "imp-4: Claude Code opens in its terminal either way")
    let mixed = [called[0], ArisJobSpec(title: "d", prompt: "문서", assignee: .teammate("mate-d"), cwd: nil, appHint: nil), called[0]]
    let mixedFallen = R.withoutUnreadyTeammates(mixed, brains: brains, ready: noGemini)
    check(mixedFallen.fellBack == ["mate-c"] && mixedFallen.specs.map(\.assignee) == [.clone, .teammate("mate-d"), .clone],
          "imp-4: only the teammate without its brain falls back, named once")
    let line = R.fallbackLine(name: "코디", brain: .antigravity, korean: true)
    check(line.contains("코디") && line.contains("Gemini") && line.contains("제가 대신") && line.contains("설정") && R.fallbackLine(name: "Cody", brain: .antigravity, korean: false).contains("Cody"),
          "imp-4: the hand-off line says who, which brain is missing, that Aris does it, and where to fix it")
    let team = cardsSource("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("ArisJobRouting.withoutUnreadyTeammates(specs, brains: brains, ready: ready)") && team.contains("ready: ready)")
          && cardsSource("Aris/private/Aris/ArisController+Teammate.swift").contains("ArisTeamModel.shared.refreshBrains()"),
          "imp-4: the hand-out reads which brains are set up, asked again as each turn starts")
}

// MARK: - imp-5: one job ending leaves another job's overlay up

private func overlayOwnerTests() {
    let start = Date(timeIntervalSince1970: 2_000)
    let notes = ArisOperatingTarget(app: "메모", pid: 3001, window: 11, line: "메모에서 입력 중…")
    let finder = ArisOperatingTarget(app: "Finder", pid: 3002, window: 22, line: "Finder에서 정리 중…")
    let first = UUID(), second = UUID()
    var state = ArisOperatingState()
    state.heard(notes, at: start, owner: first)
    state.heard(finder, at: start.addingTimeInterval(1), owner: second)
    check(state.current(at: start.addingTimeInterval(2)) == finder, "imp-5: the overlay marks the window most lately worked in")
    state.finished(owner: second)
    check(state.current(at: start.addingTimeInterval(2)) == notes, "imp-5: when one job ends, the other job's window keeps its overlay")
    state.finished(owner: first)
    check(state.current(at: start.addingTimeInterval(2)) == nil, "imp-5: with the last job done, nothing is marked")
    // The conversation's turn and a job.
    state.heard(notes, at: start, owner: first)
    state.heard(finder, at: start.addingTimeInterval(1))
    state.finished()
    check(state.current(at: start.addingTimeInterval(2)) == notes, "imp-5: the turn's answer takes down only the turn's own overlay")
    check(state.current(at: start.addingTimeInterval(ArisOperatingState.idle + 1)) == nil, "imp-5: a job that went quiet still comes down by itself")
    let team = cardsSource("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("ArisOperatingOverlay.shared.end(owner: job.id)") && team.contains("ArisOperatingOverlay.shared.show(target, owner: job.id)"),
          "imp-5: each job shows and ends its overlay under its own id")
}

// MARK: - The dictated message's card never says "sent" by itself

private func countdownTruthTests() {
    let (language, bundle) = (ArisCountdownCopy.language, ArisCountdownCopy.bundle)
    defer { (ArisCountdownCopy.language, ArisCountdownCopy.bundle) = (language, bundle) }
    ArisCountdownCopy.use("en", in: Bundle(path: NSTemporaryDirectory())!)
    check(ArisCountdownCopy.sending(to: "Mom", message: "on my way") == "Sending ‘on my way’ to Mom…", "countdown truth: once let go, the card says the message is being sent")
    let catalog = (try? JSONSerialization.jsonObject(with: Data(cardsSource("Aris/Localizable.xcstrings").utf8))) as? [String: Any]
    let entry = ((catalog?["strings"] as? [String: Any])?["countdown.sending"] as? [String: Any])?["localizations"] as? [String: Any]
    let value = { (code: String) in ((entry?[code] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String ?? "" }
    check(value("ko") == "%2$@에게 ‘%1$@’ 보내는 중…" && value("en") == "Sending ‘%1$@’ to %2$@…", "countdown truth: the sending line is in the catalog in Korean and English")
    let card = cardsSource("Aris/private/Aris/Home/ArisConfirmCard+Countdown.swift")
    let end = card.components(separatedBy: "struct ArisCountdownEndCard").last ?? ""
    check(end.contains("ArisCountdownCopy.sending(to: end.to, message: end.message)") && !end.contains("ArisCountdownCopy.sent(") && !end.contains("\"iMessage\"")
          && !end.contains("Self.green"),
          "countdown truth: when the countdown ends the card shows “보내는 중”, never “보냈어요”, a green check or a service it doesn't know")
    // The end of the countdown is still told apart from a stop, and the card goes with the answer that says what happened.
    let ask = ArisConfirmation(id: "c1", title: "엄마", detail: "곧 갈게", countdown: true, spoken: "엄마한테 ‘곧 갈게’ 보낼게요")
    let asking = ArisSession().listening().hearing("엄마한테 곧 갈게 보내줘").thinking().asking(ask)
    check(asking.counted(sent: true).countdownEnd?.sent == true && asking.counted(sent: false).countdownEnd?.sent == false
          && asking.counted(sent: true).answered().answering("엄마에게 보내지 못했어요.").countdownEnd == nil,
          "countdown truth: the card's line gives way to the answer, which says whether it really went out")
}

// MARK: - A save that still fails puts the 팀원 page back

private func teamSaveFailureTests() {
    typealias S = ArisTeamSaveRule
    let cody = ArisTeammate(id: "mate-c", name: "코디", routing: "", look: .standard, brain: "codex", scopes: [], memoryFile: "teammates/mate-c.md")
    let fresh = ArisTeammate(id: "mate-n", name: "새 팀원", routing: "", look: .standard, brain: "codex", scopes: [], memoryFile: "teammates/mate-n.md")
    check(S.shownAfterFailure(shown: [cody, fresh], stored: [cody], newerEdit: false) == [cody],
          "team save: after a save that still fails, the page shows the stored list again, not the unsaved one")
    check(S.shownAfterFailure(shown: [cody, fresh], stored: [cody], newerEdit: true) == [cody, fresh], "team save: a newer edit on its way is left alone")
    check(S.shownAfterFailure(shown: [cody, fresh], stored: nil, newerEdit: false) == [cody, fresh], "team save: with no stored list known, nothing is thrown away")
    check(S.failedNotice(putBack: true).contains("되돌렸어요") && S.failedNotice(putBack: true).contains("저장하지 못했어요") && !S.failedNotice(putBack: false).contains("되돌렸어요"),
          "team save: the notice says the list was put back only when it was")
    let model = cardsSource("Aris/private/Aris/Team/ArisTeamModel.swift")
    let failed = model.components(separatedBy: "case .failed:").last ?? ""
    check(failed.contains("ArisTeamSaveRule.shownAfterFailure(shown: teammates, stored: stored, newerEdit: pending != nil)") && failed.contains("teammates = back"),
          "team save: the model applies it when the retry failed too")
}

// MARK: - A window list that didn't come back is not a closed window

private func windowHiccupTests() {
    let listed: [[String: Any]] = [[kCGWindowNumber as String: 41, kCGWindowOwnerPID as String: Int32(7), kCGWindowLayer as String: 0, kCGWindowIsOnscreen as String: true,
                                    kCGWindowBounds as String: ["X": 10, "Y": 20, "Width": 300, "Height": 200]]]
    var asked = 0
    let answers = { (alive: Bool) -> () -> Bool in { asked += 1; return alive } }
    check(ArisWindowLocator.presence(in: listed, pid: 7, windowNumber: 41, serverAnswers: answers(false)) == .onScreen(CGRect(x: 10, y: 20, width: 300, height: 200)) && asked == 0,
          "window presence: a window that is listed is read as before, with no second look")
    check(ArisWindowLocator.presence(in: [], pid: 7, windowNumber: 41, serverAnswers: answers(true)) == .closed
          && ArisWindowLocator.presence(in: nil, pid: 7, windowNumber: 41, serverAnswers: answers(true)) == .closed,
          "window presence: not listed while the window server answers: the window is closed")
    check(ArisWindowLocator.presence(in: [], pid: 7, windowNumber: 41, serverAnswers: answers(false)) == .offScreen
          && ArisWindowLocator.presence(in: nil, pid: 7, windowNumber: 41, serverAnswers: answers(false)) == .offScreen,
          "window presence: an empty answer while no window at all is listed is a hiccup, read as out of sight, never as closed")
    check(ArisWindowLocator.presence(in: listed, pid: 8, windowNumber: 41, serverAnswers: answers(false)) == .closed,
          "window presence: a number that now belongs to another app is closed for this one")
    check(ArisCharacterDirector.whenGone(.offScreen) == .park, "window presence: on a hiccup the figure waits where it is rather than going home for good")
}

// MARK: - The controller is wired to these rules

private func cardsWiringTests() {
    let tasks = cardsSource("Aris/private/Aris/ArisController+Tasks.swift")
    check(tasks.contains("while ContinuousClock.now < deadline, !Task.isCancelled, cardUp(ask), typedAnswer == nil")
          && tasks.contains("while answer == nil, ContinuousClock.now < longest, !Task.isCancelled, cardUp(ask)")
          && tasks.contains("while typedAnswer == nil, ContinuousClock.now < longest, !Task.isCancelled, cardUp(ask)"),
          "card-1: every wait of a card stops as soon as the card is no longer the one on screen")
    check(tasks.contains("ArisCardCover.answer(typedAnswer, card: ask.id, shown: session.question?.id)")
          && tasks.contains("if ArisCardCover.ownsKeys(card: ask.id, shown: session.question?.id) {\n                typedAnswer = nil\n                KeyboardFocus.releaseCard()"),
          "card-1: the shared answer slot is read, cleared and its keys let go only by the card on screen")
    check(tasks.contains("guard typed != nil || cardUp(ask) else { return covered() }"),
          "card-1: words heard after the card was covered (the user's new request) are never its answer")
    let speakUp = tasks.components(separatedBy: "func speakUp<T>").last?.components(separatedBy: "static let answerWait").first ?? ""
    check(speakUp.components(separatedBy: "ArisCardCover.stillOwn(title: title, heard: session.heard, speaking: session.phase == .speaking)").count == 3
          && !speakUp.contains("guard session.phase == .speaking else { return result }"),
          "card-1: speaking up closes the notch only while the notch is still its own, before and after the linger")
    check(!tasks.contains("preferredLocalizations") && tasks.contains("let english = ArisUILanguage.english"),
          "ui language: the ended card's line follows the app's one language rule")

    let team = cardsSource("Aris/private/Aris/ArisController+Team.swift"), inbox = cardsSource("Aris/private/Aris/ArisController+Inbox.swift")
    let park = cardsSource("Aris/private/Aris/ArisController+CardPark.swift")
    check(team.contains("await settleCard(ask, title: job.title, job: job.id, handsFree: handsFree)") && inbox.contains("self.settleCard(ask, title: item.title, job: nil, handsFree: false"),
          "card-2: a job's and the inbox's question both go through the held-question runner")
    check(!team.contains("ArisAgentClient.confirm(ask.id, allow: allow") && !inbox.contains("ArisAgentClient.confirm(")
          && park.components(separatedBy: "ArisAgentClient.confirm(").count == 2 && park.contains("case .send(let allow): return .answered(await send(allow, for: ask, title: title))"),
          "card-2 / team-1: the only POST /confirm for such a card carries an answer the user gave")
    check(park.contains("self.askCard(ask, handsFree: handsFree, agentCard: true, quiet: quietNow)") && park.contains("switch ArisParkedAsk.next(wait.end)")
          && park.contains("desk.park(ArisWaitingCard(id: ask.id, title: title, action: ask.title, job: job, why: why, since: Date()))"),
          "card-1: the card is the agent's (one ledger line), and one that was covered or left unanswered waits in 확인 대기")
    check(park.contains("await ArisAgentClient.stillWaits(ask.id)") && park.contains("case nil: return .unreachable") && !inbox.contains("ArisAgentClient.isWaiting(")
          && inbox.contains("case .unreachable:"),
          "card-2: an agent that didn't answer whether it still waits never gets a scheduled question acknowledged away")
    check(cardsSource("Aris/private/Aris/Home/ArisTaskTags.swift").contains("waiting: desk.waiting.cards.map(Self.chip), openWaiting: { aris.openWaitingCard($0) }")
          && cardsSource("Aris/private/Aris/Home/ArisHomeView.swift").contains("|| !desk.waiting.isEmpty"),
          "imp-3: the open notch shows a 확인 대기 chip for each parked question, even with no job running")
    check(cardsSource("Aris/private/Aris/ArisController+Conversation.swift").contains("guard !Task.isCancelled else { return reply }"),
          "card-1: a card of a turn the user replaced never says “답이 없어서…” over his new turn")
    check(team.contains("ArisJobLedger.note(jobs)") && cardsSource("Aris/private/Aris/ArisController+Teammate.swift").contains("Task { [weak self] in self?.reportLostJobs() }"),
          "team-2: the jobs under way are noted as they change, and a launch reports the ones the last run lost")
}
