// Tests for Aris's news on the notice pill under the notch (cards since the owner's pick B, 2026-11-12; the pill since their
// pick D, 2026-11-16, see notice-pill-tests.swift for the pill itself): the queue (no timer takes Aris's own notice
// away, a key replaces, the newest up is the one drawn), the gate (it waits for a pause), and which of Aris's own
// moments make a notice. Called from main.swift; uses its check(). Nothing is drawn on screen.
import CoreGraphics
import Foundation

private typealias Route = ArisNoticeRoute

private func notifySource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The body of `name` in `source`: from its declaration to the next declaration at the same indent.
private func notifyFunction(_ name: String, in source: String) -> String {
    guard let start = source.range(of: name) else { return "" }
    let rest = source[start.upperBound...]
    let end = rest.range(of: "\n    func ") ?? rest.range(of: "\n    private func ") ?? rest.range(of: "\n}")
    return String(rest[..<(end?.lowerBound ?? rest.endIndex)])
}

private func card(_ kind: ArisNoticeKind = .done, _ body: String = "", key: String? = nil, subtitle: String? = nil,
                  at date: Date = Date(timeIntervalSince1970: 1_000), within: TimeInterval? = nil) -> ArisNotice {
    ArisNotice(key: key, kind: kind, title: "제목", body: body, subtitle: subtitle, posted: date, showsWithin: within)
}

func runNotifyCardTests() {
    check(ArisNoticeGate.settle == 0.8 && ArisNoticeGate.recheck == 3, "notify gate: settles 800 ms, looks again every 3 s")

    // --- the queue
    let a = card(.done, "a"), b = card(.reminder, "b")
    var q = ArisNoticeQueue().posting(a).posting(b)
    check(q.pending.map(\.id) == [a.id, b.id] && q.shown.isEmpty, "notify queue: cards wait, oldest first")
    q = q.presenting(a.id).presenting(b.id)
    check(q.shown.map(\.id) == [b.id, a.id] && q.front?.id == b.id && q.pending.isEmpty, "notify queue: the newest is the front card")
    check(q.presenting(a.id) == q, "notify queue: a card that no longer waits is not shown twice")
    check(q.dropping(expiredAt: Date(timeIntervalSince1970: 1_000_000)).shown.count == 2, "notify queue: no timer takes a shown card away")
    check(q.closing(b.id).front?.id == a.id, "notify queue: the one under comes back as the front one goes")
    let down = card(.problem, "down", key: "helper"), down2 = card(.problem, "still down", key: "helper")
    var keyed = ArisNoticeQueue().posting(down).posting(a)
    keyed = keyed.posting(down2)
    check(keyed.pending.map(\.id) == [down2.id, a.id], "notify queue: a waiting card with the same key is replaced in its place")
    keyed = keyed.presenting(down2.id).posting(down)
    check(keyed.shown.map(\.id) == [down.id] && !keyed.isWaiting(down.id), "notify queue: a shown card with the same key is replaced at once")
    check(keyed.withdrawing(key: "helper").shown.isEmpty && keyed.withdrawing(key: "helper").isWaiting(a.id), "notify queue: withdrawing a key takes only its card")
    let timer = card(.reminder, "25분 끝났어요.", at: Date(timeIntervalSince1970: 0), within: 600)
    let waits = ArisNoticeQueue().posting(timer)
    check(waits.dropping(expiredAt: Date(timeIntervalSince1970: 599)).isWaiting(timer.id)
          && !waits.dropping(expiredAt: Date(timeIntervalSince1970: 601)).isWaiting(timer.id), "notify queue: a timer's card that waited over 10 min is dropped")

    // --- the gate
    typealias M = ArisNoticeGate.Moment
    check(ArisNoticeGate.mayShow(M()), "notify gate: idle at a pause, notch closed: shown")
    check(!ArisNoticeGate.mayShow(M(pause: false)), "notify gate: mid-turn (not idle): queued")
    check(!ArisNoticeGate.mayShow(M(notchOpen: true)) && !ArisNoticeGate.mayShow(M(onboarding: true)), "notify gate: never under the open notch or the setup")
    check(ArisNoticeGate.stepsAside(M(notchOpen: true)) && !ArisNoticeGate.stepsAside(M(pause: false)),
          "notify gate: the notice up steps aside for the open notch, not for a pause ending")

    // --- the moments (what each makes)
    let job = UUID()
    let done = Route.jobDone(title: "보고서 정리", shown: "## 끝\n- 표 **3개**\n- 요약", job: job, english: false)
    check(done.kind == .done && done.title == "보고서 정리" && done.body == "끝 표 3개 요약"
          && done.actions == [ArisNoticeAction(title: "보기", primary: true, role: .openJob(job))], "notify route: a job's result is a done card with 보기")
    check(Route.jobFailed(title: "t", shown: "못 끝냈어요").kind == .problem && Route.jobFailed(title: "t", shown: "x").actions.isEmpty,
          "notify route: a failed job is a problem card")
    check(Route.lostJobs(title: "t", said: "끊겼어요").kind == .problem, "notify route: jobs cut off at the last quit: a problem card")
    let asks = Route.teammateAsks(title: "PR 리뷰", said: "어느 브랜치요?", english: false)
    check(asks.kind == .incoming && asks.subtitle == "질문이 있어요" && asks.body == "어느 브랜치요?", "notify route: a teammate's question is an incoming card")
    let result = Route.inbox(kind: "result", title: "아침 요약", shown: "날씨 맑음", file: "/tmp/x.md", english: true)
    check(result.kind == .done && result.actions.first?.role == .openFile("/tmp/x.md") && result.actions.first?.title == "View",
          "notify route: a schedule's result with a saved file: View opens it")
    check(Route.inbox(kind: "result", title: "t", shown: "s", file: nil, english: false).actions.first?.role == .openAnswer(question: "t", text: "s"),
          "notify route: a schedule's result with nothing saved: 보기 shows the answer")
    check(Route.inbox(kind: "failure", title: "t", shown: "s", file: nil, english: false).kind == .problem
          && Route.inbox(kind: "note", title: "t", shown: "s", file: nil, english: false).kind == .system, "notify route: a schedule's failure is a problem, a note is system")
    let ended = ArisTimerWords.ended(.plain, cycle: false, round: 1, total: 1500, nextTotal: 0, nextRound: 1, english: false)
    let ring = Route.timer(title: ended.title, text: ended.text)
    check(ring.kind == .reminder && ring.title == "타이머" && ring.showsWithin == 600 && ring.actions.isEmpty, "notify route: a timer is a reminder card, for 10 min")
    check(Route.announcement(title: "t", text: "x", kind: .problem).kind == .problem, "notify route: other announcements keep their kind")

    // --- problems: the fix on the blue button, the same as under the line
    let disk = ArisHelperInstallWords.diskAfterSwitch(english: false)
    let diskCard = Route.problem(line: disk, english: false)
    check(diskCard.kind == .problem && diskCard.body == disk && diskCard.title == "확인이 필요해요"
          && diskCard.actions == [ArisNoticeAction(title: ArisFixWords.title(.pane(.disk), english: false), primary: true, role: .fixes([.pane(.disk)]))],
          "notify route: Full Disk Access after the switch: its button opens the list")
    let notRunning = Route.problem(line: ArisAgentCopy.notRunning(english: true), english: true)
    check(notRunning.actions.first?.role == .fixes([.settings(.helper, again: true)]) && notRunning.actions.first?.title == "Restart the helper"
          && notRunning.title == "Needs your attention", "notify route: the helper not running: Restart the helper")
    check(Route.problem(line: ArisHelperInstallWords.move(english: false), english: false).actions.first?.role == .fixes([.showApp]),
          "notify route: move Aris to Applications: Show Aris in Finder")
    let rows = Route.problem(line: ArisHelperInstallWords.oldRows(english: false), english: false)
    check(rows.actions.first?.role == .fixes(ArisHelperInstallWords.oldRowsLists.map(ArisFix.pane)), "notify route: the old rows: one button for the three lists")
    let afterOne = Route.afterFix(rows, pressed: 1, english: false)
    check(afterOne?.actions.first?.title == ArisFixWords.title(.pane(.screen), english: false) && afterOne?.id == rows.id,
          "notify route: after the first list the button opens the next")
    check(Route.afterFix(rows, pressed: 3, english: false) == nil && Route.afterFix(diskCard, pressed: 1, english: false) == nil,
          "notify route: after the last fix the card goes")
    check(Route.problem(line: ArisStartFailure.tookTooLong(english: false), english: false).actions.isEmpty,
          "notify route: a fix that asks again (it needs a request) is never on a card")
    let helperless = Route.problem(line: ArisPrerequisites.remedy(.helper, english: false), title: ArisPrerequisites.line(.helper, english: false), english: false)
    check(helperless.title == ArisPrerequisites.line(.helper, english: false) && helperless.actions.isEmpty, "notify route: a build with no helper: no button")
    check(Route.helperDown(english: false).key == Route.helperKey && Route.helperDown(english: false).actions.first?.role == .restartHelper
          && Route.helperDown(english: false).actions.first?.title == "다시 시작", "notify route: the dozing helper: 다시 시작 on its card")
    check(Route.helperCard(from: .up, to: .down) == .post && Route.helperCard(from: .restarting, to: .failed) == .post
          && Route.helperCard(from: .down, to: .failed) == .keep && Route.helperCard(from: .down, to: .restarting) == .keep
          && Route.helperCard(from: .restarting, to: .back) == .withdraw && Route.helperCard(from: .down, to: .up) == .withdraw,
          "notify route: the helper's card comes when the star dozes and goes when it answers")
    check(Route.plain("1. one\n2. two") == "one two" && Route.plain("> `code` __x__") == "code x", "notify route: Markdown as one plain paragraph")
    check(diskCard.orderedActions.last?.primary == true, "notify card: the main button is the last, at the right edge")

    // --- the wiring: each moment goes to a card, confirm cards stay in the notch
    let team = notifySource("Aris/private/Aris/ArisController+Team.swift")
    check(notifyFunction("func reportDone(", in: team).contains("ArisNoticeRoute.jobDone(") && notifyFunction("func reportDone(", in: team).contains("await notify(card")
          && !notifyFunction("func reportDone(", in: team).contains("speakUp("), "notify wiring: a job's result is a card, no longer the notch")
    check(notifyFunction("func reportFailure(", in: team).contains("ArisNoticeRoute.jobFailed(") && notifyFunction("func reportFailure(", in: team).contains("await notify(card")
          && !notifyFunction("func reportFailure(", in: team).contains("speakUp("), "notify wiring: a job's failure is a card")
    let mate = notifySource("Aris/private/Aris/ArisController+Teammate.swift")
    check(notifyFunction("func reportLostJobs(", in: mate).contains("notify(ArisNoticeRoute.lostJobs(")
          && notifyFunction("private func teammateAsked(", in: mate).contains("notify(ArisNoticeRoute.teammateAsks(")
          && !mate.contains("speakUp("), "notify wiring: cut-off jobs and a teammate's question are cards")
    let inbox = notifySource("Aris/private/Aris/ArisController+Inbox.swift")
    check(inbox.contains("ArisNoticeRoute.inbox(") && inbox.contains("await notify(card") && !inbox.contains("speakUp("), "notify wiring: a schedule's result is a card")
    check(inbox.contains("askParked(item, ask)") && inbox.contains("settleCard(ask"), "notify wiring: a schedule's parked question stays a confirm card")
    let brief = notifySource("Aris/private/Aris/ArisController+Brief.swift")
    check(notifyFunction("func announce(title:", in: brief).contains("notify(") && !notifyFunction("func announce(title:", in: brief).contains("ArisSession.announcing"),
          "notify wiring: a timer's announcement is a card")
    check(notifySource("Aris/private/Aris/ArisTimerModel.swift").contains("kind: .reminder"), "notify wiring: the timer's card is a reminder")
    check(notifySource("Aris/private/Aris/ArisHelperInstall.swift").contains("ArisNoticeRoute.problem(line:")
          && !notifySource("Aris/private/Aris/ArisHelperInstall.swift").contains("ArisController.shared.fail("), "notify wiring: the install's lines at launch are cards")
    check(notifySource("Aris/private/Aris/ArisPrerequisiteNotice.swift").contains("ArisNoticeRoute.problem(line:")
          && !notifySource("Aris/private/Aris/ArisPrerequisiteNotice.swift").contains(".fail("), "notify wiring: what the install lacks is a card")
    check(notifySource("Aris/private/Aris/ArisAgentMonitor.swift").contains("ArisNoticeRoute.helperCard("), "notify wiring: the dozing helper puts up its card")
    let park = notifySource("Aris/private/Aris/ArisController+CardPark.swift")
    check(park.contains("self.askCard(ask") && !park.contains("notify("), "notify wiring: confirm cards stay inside the notch")
    let notify = notifySource("Aris/private/Aris/Notice/ArisController+Notice.swift")
    check(notify.contains("guard ArisQuietGate.maySound(.aris) else { return }") && notify.contains("guard !silentSpeech else { return }"),
          "notify speech: said only when Aris may speak (mute, quiet hours)")
    check(notify.contains("announce(recheck: .seconds(ArisNoticeGate.recheck), when: { center.mayShow })")
          && notify.contains("try? await Task.sleep(for: .seconds(ArisNoticeGate.settle))") && notify.contains("guard self.isPause(present: false), center.mayShow"),
          "notify gate: a card waits its turn and a pause, the notch closed, settles 800 ms and looks again")
    check(notify.contains("self.setSession(.parked(heard: notice.title, reply: parking))"), "notify history: the notch keeps the news as its parked answer, as before")
    for file in ["ArisNotice.swift", "ArisNoticePill.swift", "ArisNoticeQueue.swift", "ArisNoticeRoute.swift", "ArisNoticeCenter.swift",
                 "ArisNoticePillView.swift", "ArisController+Notice.swift", "ArisNoticeWords.swift"] {
        let text = notifySource("Aris/private/Aris/Notice/" + file)
        check(!text.isEmpty && !text.lowercased().contains("voice" + "os") && !text.contains("repeatForever"),
              "notify sources: \(file) names no other app and has no endless pulse")
    }
}
