// Tests for the notification card under the notch (the owner's pick B, 2026-11-12): a glass card of its own, 345 wide,
// 64/80/96 high by its text, radius 22, its top 50 under the work area, the measured stack (2 layers peeking 9 below,
// 13 in each), the expanded list (5, gap 8, "+N"), the kinds' tiles, the queue (no timer takes a card away, a key
// replaces, the gate waits for a pause), and which of Aris's own moments now make a card. Called from main.swift; uses
// its check(). Nothing is drawn on screen.
import CoreGraphics
import Foundation

private typealias Lay = ArisNoticeLayout
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
    // --- the measured numbers
    let cardNumbers: [CGFloat] = [Lay.width, Lay.cornerRadius, Lay.padding, Lay.gap, Lay.tileSize]
    check(cardNumbers == [345, 22, 13, 10, 30],
          "notify card: 345 wide, radius 22, padding 13, gap 10, tile 30")
    let heightsMeasured: [CGFloat] = [Lay.compactHeight, Lay.mediumHeight, Lay.largeHeight]
    check(heightsMeasured == [64, 80, 96], "notify card: 64 / 80 / 96 high")
    let text: [CGFloat] = [Lay.titleSize, Lay.titleLine, Lay.bodySize, Lay.bodyLine, Lay.subtitleSize, Lay.subtitleLine, Lay.snippetSize, Lay.snippetLine]
    check(text == [13, 17, 12.5, 16.5, 12.5, 16, 12, 16], "notify card: title 13/17, body 12.5/16.5, subtitle 12.5/16, snippet 12/16")
    let buttons: [CGFloat] = [Lay.buttonHeight, Lay.buttonTextSize, Lay.pressScale, Lay.buttonMinWidth, Lay.buttonPadding, Lay.buttonGap, Lay.buttonsBottom, Lay.buttonsRight]
    check(buttons == [22, 11, 0.97, 52, 11, 5, 8, 10],
          "notify card: 22-pt capsules, 11 pt, min 52, padding 11, gap 5, 8 up and 10 in from the corner, press 0.97")
    check(Lay.primaryColor == 0x0A84FF && Lay.secondaryColor == 0x3A3A40, "notify card: primary #0A84FF, secondary #3A3A40")
    check(Lay.closeSize == 24 && Lay.closeOut == 6, "notify card: 24-pt close circle, a quarter of it past the top-left corner")
    check(Lay.motion == 0.22 && Lay.motionCurve == (0.22, 1, 0.36, 1), "notify card: motion 220 ms on (0.22, 1, 0.36, 1)")
    let stackNumbers: [CGFloat] = [Lay.stackInset, Lay.stackOffset, Lay.expandedGap, Lay.moreRowHeight]
    check(Lay.stackMaxLayers == 2 && Lay.expandedMax == 5 && stackNumbers == [13, 9, 8, 26], "notify stack: 2 layers, inset 13, offset 9; expanded 5, gap 8, +N row 26")
    let margins: [CGFloat] = [Lay.closeOverhang, Lay.shadowMargin, Lay.topBelowWorkArea]
    check(margins == [14, 22, 50],
          "notify window: 14 around, 22 below, the card's top 50 under the work area")
    check(ArisNoticeGate.settle == 0.8 && ArisNoticeGate.recheck == 3, "notify gate: settles 800 ms, looks again every 3 s")

    // --- the window's place
    let work = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let frame = Lay.windowFrame(workArea: work)
    check(frame.width == 373 && abs(frame.midX - 756) <= 0.5, "notify window: 345 + 2 × 14 wide, centred on the display")
    let workTop: CGFloat = work.maxY - 50
    check(frame.maxY - Lay.closeOverhang == workTop, "notify window: the cards' top is 50 under the work area's top")
    let tallest: CGFloat = 14 + 480 + 32 + 26 + 22
    check(frame.height == tallest, "notify window: room for 5 large cards, their gaps and the +N row")
    let second = Lay.windowFrame(workArea: CGRect(x: 1512, y: -200, width: 1920, height: 1055))
    let secondMid: CGFloat = 2472, secondTop: CGFloat = 805
    check(abs(second.midX - secondMid) <= 0.5 && second.maxY - 14 == secondTop, "notify window: on another display, centred on it")

    // --- heights by text
    check(Lay.units("abc") == 3 && Lay.units("가나다") == 6 && Lay.units("a가") == 3, "notify height: Hangul counts as two narrow characters")
    check(Lay.height(card(.done, "Short line.")) == 64, "notify height: a short body is a compact card")
    check(Lay.height(card(.done, String(repeating: "a", count: 43))) == 80, "notify height: over one line is 80")
    check(Lay.height(card(.done, String(repeating: "a", count: 85))) == 96 && Lay.bodyLines(String(repeating: "a", count: 85)) == 3,
          "notify height: over two lines is 96, 3 lines")
    check(Lay.height(card(.done, String(repeating: "가", count: 22))) == 80 && Lay.height(card(.done, String(repeating: "가", count: 21))) == 64,
          "notify height: 22 Hangul syllables fill more than one line")
    check(Lay.height(card(.done, "")) == 64 && Lay.bodyLines("short") == 2, "notify height: no body is compact; a body takes up to 2 lines")
    check(Lay.height(card(.incoming, "", subtitle: "질문이 있어요")) == 64, "notify height: incoming, title and subtitle: 17 + 17 = 34 → 64")
    check(Lay.height(card(.incoming, "hello", subtitle: "x")) == 80, "notify height: incoming with a one-line snippet: 17 + 17 + 18 = 52 → 80")
    check(Lay.height(card(.incoming, String(repeating: "b", count: 50), subtitle: "x")) == 96,
          "notify height: incoming with a two-line snippet → 96")
    check(Lay.height(card(.incoming, "one\ntwo")) == 80 && Lay.snippetLines("one\ntwo") == 2,
          "notify height: a snippet that breaks takes 2 lines (17 + 34 = 51 → 80)")

    // --- the stack
    let one = Lay.stack([64], expanded: false)
    check(one.cards == [CGRect(x: 0, y: 0, width: 345, height: 64)] && one.layers.isEmpty && one.height == 64, "notify stack: one card, no layers")
    let three = Lay.stack([80, 64, 96], expanded: false)
    check(three.cards.count == 1 && three.layers == [CGRect(x: 13, y: 80, width: 319, height: 9), CGRect(x: 26, y: 89, width: 293, height: 9)]
          && three.height == 98, "notify stack: three cards, two layers peeking 9 below, 13 in each")
    check(Lay.stack([64, 64, 64, 64, 64, 64], expanded: false).layers.count == 2 && Lay.layerCount(2) == 1 && Lay.layerCount(0) == 0,
          "notify stack: never more than 2 layers")
    check(Lay.stack([64], expanded: true) == one, "notify stack: one card does not expand")
    let open = Lay.stack([64, 80, 96], expanded: true)
    check(open.cards == [CGRect(x: 0, y: 0, width: 345, height: 64), CGRect(x: 0, y: 72, width: 345, height: 80), CGRect(x: 0, y: 160, width: 345, height: 96)]
          && open.layers.isEmpty && open.hidden == 0 && open.moreRow == nil && open.height == 256, "notify stack: expanded, one under the other 8 apart")
    let seven = Lay.stack(Array(repeating: 64, count: 7), expanded: true)
    check(seven.cards.count == 5 && seven.hidden == 2 && seven.moreRow == CGRect(x: 0, y: 360, width: 345, height: 26),
          "notify stack: expanded shows 5, then a +2 row")
    check(ArisNoticeWords.more(2, english: false) == "+2개 더" && ArisNoticeWords.more(2, english: true) == "+2 more", "notify stack: +N in both languages")
    let hits = Lay.hitRects(three)
    check(hits.first == CGRect(x: -6, y: -6, width: 351, height: 86) && hits.count == 3, "notify hit: the card and its close corner, and each layer's band")
    check(!Lay.hitRects(three).contains { $0.contains(CGPoint(x: 5, y: 95)) }, "notify hit: beside the narrower layers the clicks pass through")

    // --- kinds and tiles
    check(ArisNoticeKind.reminder.tile.mid == 0xF28C00 && ArisNoticeKind.incoming.tile.mid == 0x2478F2 && ArisNoticeKind.done.tile.mid == 0x2EBD54
          && ArisNoticeKind.problem.tile.mid == 0xF0453A && ArisNoticeKind.system.tile.mid == 0x1D1D21,
          "notify tiles: orange reminder, blue incoming, green done, red problem, dark system")
    check(ArisNoticeKind.reminder.glyph == "bell.fill" && ArisNoticeKind.done.glyph == "checkmark.circle.fill"
          && ArisNoticeKind.problem.glyph == "exclamationmark.triangle.fill" && ArisNoticeKind.incoming.glyph == "envelope.fill",
          "notify tiles: bell, check, warning, letter")
    check(Set(ArisNoticeKind.allCases.map(\.glyph)).count == 5 && Set(ArisNoticeKind.allCases.map(\.tile.top)).count == 5, "notify tiles: each kind its own")
    let orange = ArisNoticeTile.components(0xF28C00)
    check(abs(orange.red - 242.0 / 255) < 1e-9 && orange.green == 140.0 / 255 && orange.blue == 0, "notify tiles: hex to sRGB")

    // --- the queue
    let a = card(.done, "a"), b = card(.reminder, "b")
    var q = ArisNoticeQueue().posting(a).posting(b)
    check(q.pending.map(\.id) == [a.id, b.id] && q.shown.isEmpty, "notify queue: cards wait, oldest first")
    q = q.presenting(a.id).presenting(b.id)
    check(q.shown.map(\.id) == [b.id, a.id] && q.front?.id == b.id && q.pending.isEmpty, "notify queue: the newest is the front card")
    check(q.presenting(a.id) == q, "notify queue: a card that no longer waits is not shown twice")
    check(q.dropping(expiredAt: Date(timeIntervalSince1970: 1_000_000)).shown.count == 2, "notify queue: no timer takes a shown card away")
    let expanded = q.expanding()
    check(expanded.expanded && ArisNoticeQueue().posting(a).presenting(a.id).expanding().expanded == false, "notify queue: a click opens a stack of two or more")
    check(!expanded.closing(b.id).expanded && expanded.closing(b.id).shown.map(\.id) == [a.id], "notify queue: closing down to one card closes the list")
    check(expanded.collapsing().expanded == false, "notify queue: Show less closes the list")
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
          "notify gate: shown cards step aside for the open notch, not for a turn")

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
    check(diskCard.orderedActions.last?.primary == true, "notify card: the blue button is the last, at the right edge")

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
    check(notify.contains("self.session = .parked(heard: notice.title, reply: parking)"), "notify history: the notch keeps the news as its parked answer, as before")
    let panel = notifySource("Aris/private/Aris/Notice/ArisNoticePanel.swift")
    check(panel.contains("canBecomeKey: Bool { false }") && panel.contains("canBecomeMain: Bool { false }") && panel.contains(".nonactivatingPanel"),
          "notify panel: never key, never main, non-activating")
    check(panel.contains("mainMenu.rawValue + 2"), "notify panel: one level under the notch's (mainMenu + 3)")
    check(panel.contains("ignoresMouseEvents"), "notify panel: clicks pass through outside the cards")
    let view = notifySource("Aris/private/Aris/Notice/ArisNoticeCardView.swift")
    let surface = notifySource("Aris/private/Aris/Notice/ArisNoticeSurface.swift")
    check(view.contains("accessibilityReduceMotion") && surface.contains("accessibilityReduceTransparency") && surface.contains("shape.fill(palette.solid)"),
          "notify view: Reduce Motion fades only; Reduce Transparency makes the glass card solid")
    check(surface.contains("tint: (0.055, 0.055, 0.065, 0.2)") && surface.contains("tint: (1, 1, 1, 0.06)")
          && surface.contains("title: rgb(24, 31, 39, 0.96), body: rgb(38, 47, 57, 0.68)") && surface.contains("secondaryFill: .white.opacity(0.34)")
          && surface.contains("closeFill: rgb(239, 244, 248, 0.72)") && surface.contains("solid: rgb(232, 237, 242, 1)"),
          "notify look: the measured light tint, dark text, buttons and close circle; the measured dark ones")
    check(surface.contains("material == .opaque ? opaque : scheme == .light ? light : dark"), "notify look: the opaque card stays dark in either appearance")
    check(panel.contains("appearance = nil") && !panel.contains("darkAqua") && !view.contains(".environment(\\.colorScheme, .dark)")
          && notifySource("Aris/private/Aris/Notice/ArisNoticeGlass.swift").contains("view.follow(light: context.environment.colorScheme == .light)"),
          "notify look: the panel and the glass follow the system's appearance, live")
    for file in ["ArisNotice.swift", "ArisNoticeLayout.swift", "ArisNoticeQueue.swift", "ArisNoticeRoute.swift", "ArisNoticeCenter.swift",
                 "ArisNoticePanel.swift", "ArisNoticeCardView.swift", "ArisNoticeSurface.swift", "ArisNoticeGlass.swift",
                 "ArisController+Notice.swift", "ArisNoticeWords.swift"] {
        let text = notifySource("Aris/private/Aris/Notice/" + file)
        check(!text.isEmpty && !text.lowercased().contains("voice" + "os") && !text.contains("repeatForever"),
              "notify sources: \(file) names no other app and has no endless pulse")
    }
}
