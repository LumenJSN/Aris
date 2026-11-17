// Tests for the notice pill under the notch (the owner's pick D, 2026-11-16, "노치 아래 알약"): 6 under the closed notch in
// the dictation pill's body; one line 38 high, 284 / 364 / 440 wide by its words; under the pointer a 364-wide card of
// corner 24; its motion (from the 36 × 8 bar in 250 ms, content 150 ms; grow 250, fold 180; leave .8 in 150, CSS ease);
// its phases; who has the room under the notch; what waits for a turn or a dictation; the deadline's chip and colours;
// a deadline's and a Claude Code session's notice in Korean and English; and the wiring that put them all on the pill.
// Called from main.swift; uses its check(). Nothing is drawn on screen (notice-pill-render draws it offscreen).
import CoreGraphics
import Foundation

private typealias P = ArisNoticePillLayout
private typealias Phase = ArisNoticePillPhase
private typealias Rules = ArisNoticePillRules

private func pillSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// The mockup's scenes, as their words (notice-mock data.swift).
private let pillMailBody = "내일 오후 3시에 리뷰 괜찮을까요? 시안 두 개만 미리 보내 주시면 좋아요."
private let pillLongBody = "표 3개와 요약 한 쪽을 만들었어요. 바탕화면에 «주간보고.pages»로 저장했어요. 매출 표는 지역별로 나눴고, 비용 표에는 지난달과 비교하는 열을 더했어요. 요약 끝에는 다음 주에 확인할 일 세 가지를 적어 뒀어요."

func runNoticePillTests() {
    // --- the numbers
    check(P.height == 38 && P.radius == 19 && P.radius == P.height / 2 && P.expandedRadius == 24 && P.expandedWidth == 364,
          "notice pill: one line 38 high (a capsule, 19), the card 364 wide at corner 24")
    check(P.widths == [284, 364, 440] && P.shortUnder == 40 && P.mediumUnder == 100, "notice pill: 284 / 364 / 440 by length (under 40, under 100)")
    check(P.belowNotch == 6, "notice pill: 6 under the closed notch, where the jobs' pill hangs")
    check(P.barSize == ArisDictationPillRules.idleSize, "notice pill: arrives from the dictation pill's 36 × 8 idle bar")
    check(P.leading == 10 && P.trailing == 13 && P.gap == 8 && P.markSize == 20 && P.textSize == 13,
          "notice pill: 10 in, 13 at the right, gap 8, a 20 mark, 13-pt text")
    check(P.chipHeight == 20 && P.chipPadding == 7 && P.chipSize == 11 && P.chipFill == 0.16, "notice pill: the deadline chip 20 high, 7 in, 11 bold, its colour at .16")
    check(P.textIndent == 28 && P.bodyLine == 19.5 && P.bodyLines == 6 && P.closeSize == 20 && P.buttonHeight == 26,
          "notice card: the text 28 in under the title, 13/19.5 up to 6 lines, a 20 ✕, 26-high buttons")

    // --- the widths by length
    check(P.width(title: String(repeating: "a", count: 20), body: String(repeating: "b", count: 19)) == 284
          && P.width(title: String(repeating: "a", count: 20), body: String(repeating: "b", count: 20)) == 364,
          "notice width: 39 characters 284, 40 364")
    check(P.width(title: "", body: String(repeating: "가", count: 99)) == 364 && P.width(title: "", body: String(repeating: "가", count: 100)) == 440,
          "notice width: 99 characters 364, 100 440")
    check(P.width(title: "23시간 남았어요", body: "PS3 · 내일") == 284 && P.width(title: "김지원", body: pillMailBody) == 364
          && P.width(title: "지난주 보고서 정리", body: pillLongBody) == 440
          && P.width(title: "Jiwon Kim", body: "Does 3 pm tomorrow work for the review? If you can, send the two drafts over beforehand.") == 364,
          "notice width: the mockup's deadline 284, mail 364, long report 440, English mail 364")

    // --- the motion
    check(P.arrive == 0.25 && P.contentFade == 0.15 && abs(P.contentDelay - 0.1) < 1e-9, "notice motion: arrives in 250 ms, its content fading in over the last 150")
    check(P.expand == 0.25 && P.collapse == 0.18 && P.exit == 0.15 && P.exitScale == 0.8, "notice motion: grows 250 ms, folds 180 ms, leaves .8 in 150 ms")
    check(P.ease == ArisDictationPillRules.ease && P.ease == (0.25, 0.1, 0.25, 1.0), "notice motion: CSS ease, the dictation pill's")

    // --- the phases
    check(Phase.of(arrived: false, hovered: false) == .bar && Phase.of(arrived: false, hovered: true) == .bar,
          "notice phase: before it arrives, the bar")
    check(Phase.of(arrived: true, hovered: false) == .collapsed && Phase.of(arrived: true, hovered: true) == .expanded,
          "notice phase: arrived, the line; under the pointer, the card")
    let bar = Phase.bar.size(width: 364), oneLine = Phase.collapsed.size(width: 284), card = Phase.expanded.size(width: 440)
    check(bar.width == 36 && bar.height == 8 && oneLine.width == 284 && oneLine.height == 38 && card.width == 364 && card.height == nil,
          "notice phase: 36 × 8, then its width × 38, then 364 wide as tall as its text")
    check(Phase.radius(height: 8) == 4 && Phase.radius(height: 38) == 19 && Phase.radius(height: 180) == 24,
          "notice phase: the corner 4 on the bar, 19 on the line, 24 on the card")
    check(Phase.bar.duration(to: .collapsed) == 0.25 && Phase.collapsed.duration(to: .expanded) == 0.25
          && Phase.expanded.duration(to: .collapsed) == 0.18 && Phase.bar.duration(to: .expanded) == 0.25,
          "notice phase: arrive 250, grow 250, fold 180")
    check(!Phase.bar.contentShown && Phase.collapsed.contentShown && Phase.expanded.contentShown, "notice phase: no content on the bar")

    // --- who has the room under the notch
    typealias U = Rules.UnderNotch
    check(Rules.underNotch(closed: true, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: true, noticeHere: true) == .notice,
          "under notch: a notice on this display has it over the jobs' pill")
    check(Rules.underNotch(closed: true, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: true, noticeHere: false) == .jobs,
          "under notch: a notice on another display leaves this one to the jobs' pill")
    check(Rules.underNotch(closed: true, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: false, noticeHere: true) == .jobs,
          "under notch: no notice (or it stepped aside): the jobs' pill")
    check(Rules.underNotch(closed: false, hidden: false, musicPeek: false, nowPlaying: false, noticeUp: true, noticeHere: true) == U.none,
          "under notch: nothing while the notch is open")
    check(Rules.underNotch(closed: true, hidden: false, musicPeek: true, nowPlaying: false, noticeUp: true, noticeHere: true) == U.none
          && Rules.underNotch(closed: true, hidden: false, musicPeek: false, nowPlaying: true, noticeUp: true, noticeHere: true) == U.none,
          "under notch: the music peek and the Now Playing notice keep it for their moment")
    check(Rules.underNotch(closed: true, hidden: true, musicPeek: false, nowPlaying: false, noticeUp: true, noticeHere: true) == .notice
          && Rules.underNotch(closed: true, hidden: true, musicPeek: false, nowPlaying: false, noticeUp: false, noticeHere: true) == U.none,
          "under notch: a notice shows over a full-screen app as the cards did; the jobs' pill doesn't")

    // --- priority: the dictation pill and a turn first
    typealias M = ArisNoticeGate.Moment
    check(!ArisNoticeGate.mayShow(M(turn: true)) && ArisNoticeGate.stepsAside(M(turn: true)),
          "notice priority: an Aris turn (or a conversation listening) keeps a notice waiting, and the one up steps aside")
    check(!ArisNoticeGate.mayShow(M(dictating: true)) && ArisNoticeGate.stepsAside(M(dictating: true)),
          "notice priority: a dictation keeps a notice waiting, and the one up steps aside")
    check(ArisNoticeGate.mayShow(M()) && !ArisNoticeGate.stepsAside(M()), "notice priority: at a pause with nothing running it comes up")
    check(!ArisNoticeGate.dictationBusy(.hidden) && !ArisNoticeGate.dictationBusy(.idle) && !ArisNoticeGate.dictationBusy(.hover),
          "notice priority: the dictation pill's idle bar and hover don't hold a notice")
    check(ArisNoticeGate.dictationBusy(.recording(handsFree: false)) && ArisNoticeGate.dictationBusy(.recording(handsFree: true))
          && ArisNoticeGate.dictationBusy(.transcribing(.charging)) && ArisNoticeGate.dictationBusy(.recovered("x")) && ArisNoticeGate.dictationBusy(.error("x")),
          "notice priority: listening, writing down, the copied words and its error line do")
    var waiting = ArisNoticeQueue().posting(ArisNotice(kind: .done, title: "t", body: "b"))
    let first = waiting.pending[0]
    check(waiting.isWaiting(first.id) && waiting.shown.isEmpty, "notice priority: while it waits it stays in line")
    waiting = waiting.presenting(first.id)
    check(waiting.front?.id == first.id, "notice priority: it shows after, when the moment comes")

    // --- one pill at a time
    let older = ArisNotice(kind: .done, title: "old", body: ""), newer = ArisNotice(kind: .incoming, title: "new", body: "")
    let both = ArisNoticeQueue().posting(older).posting(newer).presenting(older.id).presenting(newer.id)
    check(both.front?.id == newer.id && both.shown.count == 2, "notice queue: one pill, the newest; the one under waits its turn")
    check(both.closing(newer.id).front?.id == older.id, "notice queue: closing it brings back the one under")

    // --- its own clock
    let timed = ArisNotice(kind: .reminder, title: "t", body: "", showsFor: 8)
    check(!Rules.clockRuns(ArisNotice(kind: .done, title: "t", body: ""), hovered: nil, aside: false),
          "notice clock: Aris's own news has none (it stays until closed)")
    check(Rules.clockRuns(timed, hovered: nil, aside: false) && !Rules.clockRuns(timed, hovered: timed.id, aside: false)
          && !Rules.clockRuns(timed, hovered: nil, aside: true) && !Rules.clockRuns(nil, hovered: nil, aside: false),
          "notice clock: a deadline's or Claude Code's runs while seen, held under the pointer and while it steps aside")

    // --- marks, lines and what stands at the right
    let posted = Date(timeIntervalSince1970: 10_000)
    let mail = ArisNotice(kind: .incoming, title: "김지원", body: pillMailBody, subtitle: "디자인 리뷰 일정", posted: posted)
    check(mail.mark == .mail && ArisNotice(kind: .done, title: "", body: "").mark == .star && ArisNotice(kind: .problem, title: "", body: "").mark == .star,
          "notice mark: a teammate's question the mail, Aris's own news the star")
    let line = Rules.line(mail)
    check(line.bold == "김지원" && line.rest == pillMailBody && !line.restTinted, "notice line: the title bold, the body dimmed after it")
    check(Rules.trailing(mail, now: posted.addingTimeInterval(20), english: false) == .time("방금")
          && Rules.trailing(mail, now: posted.addingTimeInterval(20), english: true) == .time("now")
          && Rules.trailing(mail, now: posted.addingTimeInterval(5 * 60), english: false) == .time("5분 전")
          && Rules.trailing(mail, now: posted.addingTimeInterval(5 * 60), english: true) == .time("5m ago")
          && Rules.trailing(mail, now: posted.addingTimeInterval(2 * 3_600), english: false) == .time("2시간 전")
          && Rules.trailing(mail, now: posted.addingTimeInterval(2 * 3_600), english: true) == .time("2h ago"),
          "notice time: 방금 / now, then minutes, then hours")

    // --- a deadline (24 h blue, 3 h red)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 15))!
    let ps3 = ArisDue(id: "9", course: "CSC263H1", title: "PS3", at: now.addingTimeInterval(23 * 3_600 + 30 * 60), url: "https://q.exampleu.edu/x")
    let day = ArisNoticeRoute.deadline(ps3, .dayBefore, now: now, english: false)
    check(day.title == "23시간 남았어요" && day.subtitle == "CSC263 · 아직 안 냈어요" && day.body == "PS3 · " + ArisDue.when(ps3.at, now: now).0,
          "deadline notice: 23시간 남았어요, the course and not handed in, what and when")
    check(day.source == .deadline(.dayBefore) && day.mark == .deadline(.dayBefore) && Rules.trailing(day, now: now, english: false) == .chip(.dayBefore)
          && ArisDueAlert.dayBefore.rawValue == "24h", "deadline notice: a day before, the blue 24h chip")
    check(day.key == ArisNoticeRoute.deadlineKey && day.showsFor == 8 && day.tap == .openDue(ps3)
          && day.actions == [ArisNoticeAction(title: "열기", primary: true, role: .openDue(ps3))] && abs((day.showsWithin ?? 0) - (23 * 3_600 + 30 * 60)) < 1,
          "deadline notice: one at a time, 8 s up, a click (or 열기) opens it, never shown after the deadline")
    let dayLine = Rules.line(day)
    check(dayLine.bold == day.body && dayLine.rest == "23시간 남았어요" && dayLine.restTinted, "deadline line: what is due bold, the time left in its colour")
    let lab = ArisDue(id: "todo-1", course: "", title: "Lab 4", at: now.addingTimeInterval(150 * 60), url: nil)
    let hours = ArisNoticeRoute.deadline(lab, .hoursBefore, now: now, english: false)
    check(hours.title == "2시간 남았어요" && hours.mark == .deadline(.hoursBefore) && Rules.trailing(hours, now: now, english: false) == .chip(.hoursBefore)
          && ArisDueAlert.hoursBefore.rawValue == "3h" && hours.subtitle == "할 일 · 아직 안 했어요",
          "deadline notice: three hours before, the red 3h chip; a to-do of his own is not done yet")
    check(hours.actions.isEmpty && hours.tap == .openDue(lab), "deadline notice: nothing to open (no https page): no button, a click dismisses it")
    let english = ArisNoticeRoute.deadline(ps3, .dayBefore, now: now, english: true)
    check(english.title.hasSuffix(" left") && english.subtitle == "CSC263 · not handed in yet" && english.body == "PS3 · tomorrow"
          && english.actions.first?.title == "Open", "deadline notice in English: … left, not handed in yet, PS3 · tomorrow, Open")
    check(ArisNoticeWords.dueWhen(now.addingTimeInterval(3 * 3_600), now: now, english: true, calendar: calendar) == "today 18:00"
          && ArisNoticeWords.dueWhen(now.addingTimeInterval(3 * 3_600), now: now, english: false, calendar: calendar) == "오늘 18:00",
          "deadline when: today 18:00 / 오늘 18:00")
    let glass = pillSource("Aris/private/Aris/Design/ArisGlass.swift")
    let orb = pillSource("Aris/private/Aris/ArisActivity.swift")
    check(glass.contains("static func dueTint(_ alert: ArisDueAlert) -> Color { alert == .hoursBefore ? dueRed : ArisOrb.glow }")
          && glass.contains("static let dueRed = Color(red: 1, green: 0.27, blue: 0.23)") && orb.contains("static let glow = Color(red: 0.45, green: 0.78, blue: 1.0)"),
          "deadline colours: 24h the orb's glow (the alert's blue), 3h the alert's red, as tokens")

    // --- a Claude Code session's notice
    let peek = ClaudePeek(id: "p", kind: .done, title: "Done", detail: "my-app", message: "테스트 **412개**가 모두 통과했어요.", sessionId: "s1")
    let claude = ArisNoticeRoute.claude(peek, english: false)
    check(claude.title == "my-app · 끝났어요" && claude.body == "테스트 412개가 모두 통과했어요." && claude.mark == .ghost && claude.kind == .done,
          "claude notice: its tag's words, its last message as plain text, the ghost")
    check(claude.tap == .focusClaude(sessionId: "s1") && claude.actions == [ArisNoticeAction(title: "터미널 열기", primary: true, role: .focusClaude(sessionId: "s1"))]
          && claude.key == ArisNoticeRoute.claudeKey && claude.showsFor == 6, "claude notice: a click brings its terminal forward; 6 s up; a newer one replaces it")
    let claudeEnglish = ArisNoticeRoute.claude(peek, english: true)
    check(claudeEnglish.title == "my-app · done" && claudeEnglish.actions.first?.title == "Open terminal", "claude notice in English: · done, Open terminal")
    let error = ArisNoticeRoute.claude(ClaudePeek(id: "e", kind: .error, title: "Error", detail: "notch"), english: false)
    check(error.kind == .problem && error.body == "작업 중에 오류가 났어요." && error.actions.isEmpty && error.tap == nil,
          "claude notice: an error with no message says so plainly; no session, nothing to bring forward")
    let limit = ArisNoticeRoute.claude(ClaudePeek(id: "l", kind: .limit, title: "80% used", detail: "5-hour limit", message: "Resets at 7:10 PM"), english: true)
    check(limit.title == "Claude · 5-hour limit 80% used" && limit.body == "Resets at 7:10 PM", "claude notice: a plan limit")

    // --- nothing that must be read is cut (the width measures the whole line, 284 → 364 → 440)
    typealias Fit = ArisNoticePillFit
    check(Fit.chrome == 71 && Fit.textWidth("가나다", size: 13, weight: Fit.regular) > Fit.textWidth("abc", size: 13, weight: Fit.regular)
          && Fit.textWidth("abc", size: 13, weight: Fit.semibold) >= Fit.textWidth("abc", size: 13, weight: Fit.regular) && Fit.textGap > 0,
          "notice fit: 71 of chrome; the words measured in the system font, Hangul wider, semibold no narrower")
    let lab3 = ArisDue(id: "8", course: "CSC209H1", title: "Lab 4", at: now.addingTimeInterval(150 * 60), url: "https://q.exampleu.edu/x")
    let due3 = ArisNoticeRoute.deadline(lab3, .hoursBefore, now: now, english: false)
    check(P.width(due3) == 284 && Fit.width(due3, now: now, english: false) >= 364 && Fit.whole(due3, now: now, english: false) <= Fit.width(due3, now: now, english: false),
          "notice fit: \"Lab 4 · 오늘 18:00  2시간 남았어요\" + 3h steps up from 284 so the time left is whole")
    let longTitle = ArisDue(id: "7", course: "CSC263H1", title: "Problem Set 3 — Amortized analysis, union-find and the long written part", at: now.addingTimeInterval(150 * 60), url: nil)
    let samples: [(String, ArisNotice, Bool)] = [
        ("deadline 24h KO", ArisNoticeRoute.deadline(ps3, .dayBefore, now: now, english: false), false),
        ("deadline 24h EN", ArisNoticeRoute.deadline(ps3, .dayBefore, now: now, english: true), true),
        ("deadline 3h KO", due3, false),
        ("deadline 3h EN", ArisNoticeRoute.deadline(lab3, .hoursBefore, now: now, english: true), true),
        ("deadline long KO", ArisNoticeRoute.deadline(longTitle, .hoursBefore, now: now, english: false), false),
        ("deadline long EN", ArisNoticeRoute.deadline(longTitle, .hoursBefore, now: now, english: true), true),
        ("Claude KO", ArisNoticeRoute.claude(peek, english: false), false),
        ("Claude EN", ArisNoticeRoute.claude(peek, english: true), true),
        ("Claude long name", ArisNoticeRoute.claude(ClaudePeek(id: "n", kind: .done, title: "Done", detail: String(repeating: "aris-feature-", count: 4), message: "ok"), english: false), false),
        ("mail KO", ArisNotice(kind: .incoming, title: "김지원", body: pillMailBody, posted: now), false),
        ("mail EN", ArisNotice(kind: .incoming, title: "Jiwon Kim", body: "Does 3 pm tomorrow work for the review? If you can, send the two drafts over beforehand.", posted: now), true),
        ("Aris news KO", ArisNoticeRoute.jobDone(title: "지난주 보고서 정리", shown: pillLongBody, job: UUID(), english: false), false),
        ("Aris news EN", ArisNoticeRoute.jobDone(title: "Last week's report, tidied into three tables and a summary", shown: "Saved on the Desktop.", job: UUID(), english: true), true),
        ("Aris problem KO", ArisNoticeRoute.helperDown(english: false), false),
        ("timer KO", ArisNoticeRoute.timer(title: "타이머", text: "25분 끝났어요.", at: now), false),
    ]
    for (name, sample, inEnglish) in samples {
        let width = Fit.width(sample, now: now, english: inEnglish)
        check(P.widths.contains(width) && width >= P.width(sample), "notice fit \(name): one of 284 / 364 / 440, never under the length's step")
        let need = Fit.needed(sample, now: now, english: inEnglish)
        check(need > P.widths.last! || need <= width,
              "notice fit \(name): what must be read whole fits at 440 or below (\(Int(need)) in \(Int(width)))")
        check(need <= P.widths.last! || width == P.widths.last!, "notice fit \(name): past 440 it stays 440 and the bold part shortens")
        check(Fit.kept(sample, now: now, english: inEnglish) <= width,
              "notice fit \(name): the time, the chip and a deadline's time left always fit (\(Int(Fit.kept(sample, now: now, english: inEnglish))) in \(Int(width)))")
    }
    let longDue = ArisNoticeRoute.deadline(longTitle, .hoursBefore, now: now, english: false)
    check(Fit.width(longDue, now: now, english: false) == 440 && Fit.whole(longDue, now: now, english: false) > 440,
          "notice fit: a deadline too long for 440 stays 440; its bold part shortens, its time left and chip don't")
    let fitView = pillSource("Aris/private/Aris/Notice/ArisNoticePillView.swift")
    check(fitView.contains(".lineLimit(1).fixedSize().layoutPriority(2)") && fitView.contains("trailing.layoutPriority(3)")
          && fitView.contains(".layoutPriority(line.restTinted ? 0 : 1)") && fitView.contains("ArisNoticePillFit.width(notice, now: now ?? Date(), english: english)"),
          "notice fit: drawn so — a deadline's time left fixed, the chip and time first, the bold part before a preview, the fitted width")

    // --- the words
    check(ArisNoticeWords.open(english: false) == "열기" && ArisNoticeWords.open(english: true) == "Open"
          && ArisNoticeWords.openTerminal(english: false) == "터미널 열기" && ArisNoticeWords.close(english: true) == "Close",
          "notice words: 열기 / Open, 터미널 열기 / Open terminal, 닫기 / Close")

    // --- the wiring
    let root = pillSource("Aris/private/Notch/ArisNotchRoot.swift")
    check(root.contains("ArisNoticePillHost()") && root.contains(".padding(.top, hangHeight + ArisNoticePillLayout.belowNotch)")
          && root.contains("var pillCanShow: Bool { underNotchOwner == .jobs }") && root.contains("pillShown: underNotchTaken"),
          "notice wiring: the notch draws the pill 6 under it, in the jobs' pill's place, and the chips keep away from it")
    check(!root.contains("ArisDueAlertView") && !root.contains("ClaudeNoticeView") && !root.contains("case .dueAlert")
          && !pillSource("Aris/private/Notch/ArisNotchRoot+Behaviour.swift").contains("transientPeek"),
          "notice wiring: no deadline band, no Claude notice opening the notch")
    check(pillSource("Aris/private/Aris/ArisTodoView.swift").contains("ArisDueAlertView") == false
          && pillSource("Aris/private/Claude/ClaudeNoticeView.swift").isEmpty, "notice wiring: the old deadline card and Claude notice page are gone")
    let todo = pillSource("Aris/private/Aris/ArisTodoModel.swift")
    check(todo.contains("ArisNoticeRoute.deadline(next, kind, now: now, english: ArisUIWords.english)") && todo.contains("await ArisController.shared.notify(notice)")
          && !todo.contains("alertShowsFor"), "notice wiring: a deadline's alert goes on the pill, in line with Aris's news")
    let center = pillSource("Aris/private/Aris/Notice/ArisNoticeCenter.swift")
    check(center.contains("ClaudeStore.shared.$transientPeek") && center.contains("ArisNoticeRoute.claude(peek, english: ArisUIWords.english)")
          && center.contains("await ArisController.shared.notify(notice)"), "notice wiring: Claude Code's notice goes on the pill, in line")
    check(center.contains("if case .deadline = notice?.source { ArisTodoModel.shared.dismissAlert() }")
          && center.contains("case .openDue(let due):\n            ArisTodoModel.shared.open(due)")
          && center.contains("TerminalFocus.focus(session, cwd: session.cwd) }\n            store.dismissPeek()"),
          "notice wiring: a deadline opens and is dismissed; Claude Code's terminal comes forward and its notice is dismissed")
    check(center.contains("ArisDictationPillCenter.shared.$display") && center.contains("ArisNotchState.shared.$current")
          && center.contains("turn: state.isActive || state.conversing"), "notice wiring: a turn and the dictation pill are watched")
    check(center.contains("Color.clear.arisStarSeat(.pill)"), "notice wiring: Aris's star hops down into the pill's seat (one star)")
    let view = pillSource("Aris/private/Aris/Notice/ArisNoticePillView.swift")
    check(view.contains("ArisDictationPillShell(size: proxy.size, gradientBorder: true, blending: blending)") && view.contains(".clipShape(ArisDictationPillShape())")
          && view.contains("shadow(color: Look.shadow, radius: Look.shadowRadius, y: Look.shadowY)"),
          "notice look: the dictation pill's own body and outline, the recovered card's shadow")
    check(glass.contains("static var shadow: Color { ArisDictationPillRecoveredTokens.dark.shadow }")
          && pillSource("Aris/private/Aris/Dictation/ArisDictationPillRecoveredCard.swift").contains("shadow: .black.opacity(0.38))"),
          "notice look: the shadow is the recovered card's .38")
    check(view.contains(".scale(scale: L.exitScale)") && view.contains("ease(L.exit)") && view.contains("withAnimation(Self.ease(L.arrive))")
          && view.contains("Self.ease(hovered ? L.expand : L.collapse)") && view.contains("accessibilityReduceMotion"),
          "notice motion: arrives, grows, folds and leaves on the numbers; Reduce Motion only fades")
    for file in ["ArisNoticePill.swift", "ArisNoticePillView.swift", "ArisNoticeCenter.swift"] {
        let text = pillSource("Aris/private/Aris/Notice/" + file)
        check(!text.isEmpty && !text.lowercased().contains("voice" + "os") && !text.contains("repeatForever"),
              "notice sources: \(file) names no other app and nothing blinks or pulses")
    }
}
