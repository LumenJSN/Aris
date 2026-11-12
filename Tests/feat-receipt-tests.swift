// Tests for the receipt under an answer (ArisReceipt, ArisReceiptWords; aris-tools' ArisActSummary): what one act is
// called, read from the activity log's own line; which of the log's rows are this turn's; when the line shows, grows,
// leaves and offers 되돌리기; what it says after an undo; and its five seconds. Everything runs on values made here: no
// log is read, nothing is undone, no agent is asked.
// Called from main.swift; uses its check().
import Foundation

func runFeatReceiptTests() {
    receiptWordsTests()
    receiptToolLinesTests()
    receiptActsTests()
    receiptLineTests()
    receiptDeskTests()
    receiptUndoTests()
    receiptClockTests()
}

private let receiptStart = Date(timeIntervalSince1970: 1_800_000_000.6)

/// A row of the log as the app gets it. `after`: seconds after the turn began (the log keeps whole seconds).
private func receiptRow(_ summary: String, id: String = UUID().uuidString, after: TimeInterval = 2, job: String = "대화", worker: String = "Claude",
                        undoable: Bool = false, undone: Bool = false, asks: Bool = false, teammate: String? = nil) -> ArisActivityItem {
    let date = Date(timeIntervalSince1970: (receiptStart.timeIntervalSince1970 + after).rounded(.down))
    return ArisActivityItem(id: id, date: date, job: job, worker: worker, summary: summary, undoable: undoable, undone: undone, asks: asks, teammate: teammate)
}

private func receiptSpeaking(_ reply: String = "했어요.") -> ArisSession {
    ArisSession().listening().hearing("엄마한테 곧 간다고 보내 줘").thinking().answering(reply)
}

// MARK: - The words, from the log's own line

private func receiptWordsTests() {
    let korean = { (summary: String) in ArisReceiptWords.line(summary, english: false) }
    let english = { (summary: String) in ArisReceiptWords.line(summary, english: true) }
    check(korean(ArisActSummary.messageSent(to: "엄마")) == "엄마에게 보냄", "receipt: a message to a contact reads 엄마에게 보냄")
    check(english(ArisActSummary.messageSent(to: "Mom")) == "Sent to Mom", "receipt: in English it reads Sent to Mom")
    check(korean(ArisActSummary.messageSent(to: "+82 10-1234-5678")) == "메시지 보냄" && korean(ArisActSummary.messageSent(to: "a@b.com")) == "메시지 보냄",
          "receipt: a message to a number or an address says only that it was sent")
    check(korean(ArisActSummary.reminderAdded("우유 사기")) == "미리 알림에 추가함", "receipt: a reminder reads 미리 알림에 추가함, without its text")
    check(korean(ArisActSummary.reminderAdded("회의: 3시")) == "미리 알림에 추가함", "receipt: a reminder whose text holds a colon is still a reminder")
    check(korean(ArisActSummary.noteSaved("장보기")) == "메모에 저장함" && korean(ArisActSummary.noteSaved("")) == "메모에 저장함",
          "receipt: a note reads 메모에 저장함, with or without a title")
    check(korean(ArisActSummary.remembered("엄마 생일은 3월 2일")) == "기억해 둠" && korean(ArisActSummary.forgot(2)) == "기억에서 지움",
          "receipt: a fact remembered or forgotten is said without the fact")
    check(korean(ArisActSummary.calendarChosen("집")) == "기본 캘린더 바꿈", "receipt: the default calendar changed is a setting changed")
    // Every line the tools and the app already write (ArisActivityCommand, ArisMac, ArisTodoCommand, ArisScheduleTool…).
    let known: [(String, String, String)] = [
        ("일정 추가: 치과", "캘린더에 추가함", "Added to Calendar"),
        ("일정 삭제: 치과", "일정 지움", "Deleted an event"),
        ("일정 변경: 치과", "일정 바꿈", "Changed an event"),
        ("할 일 추가: 우유 사기", "할 일에 추가함", "Added to your to-dos"),
        ("할 일 완료: 우유 사기", "할 일 완료함", "Ticked off a to-do"),
        ("할 일 지움: 우유", "할 일 지움", "Removed a to-do"),
        ("옮김: 보고서.pdf → ~/Documents", "보고서.pdf 옮김", "Moved 보고서.pdf"),
        ("이름 바꿈: a.txt → b.txt", "이름 바꿈", "Renamed"),
        ("휴지통으로: 초안.docx", "초안.docx 휴지통으로", "Moved 초안.docx to the Trash"),
        ("새 폴더: 영수증", "폴더 만듦", "Made a folder"),
        ("예약: 아침 정리 (매일 08:00)", "예약함", "Scheduled"),
        ("예약 취소: 아침 정리 (매일 08:00)", "예약 취소함", "Removed a schedule"),
        ("타이머: 5분", "타이머 맞춤", "Set a timer"),
        ("타이머: 5", "타이머 맞춤", "Set a timer"),
        ("타이머 끔", "타이머 끔", "Stopped the timer"),
        ("뽀모도로", "뽀모도로 시작함", "Started a Pomodoro"),
        ("볼륨 30", "볼륨 바꿈", "Changed the volume"),
        ("볼륨 올림", "볼륨 바꿈", "Changed the volume"),
        ("볼륨 up", "볼륨 바꿈", "Changed the volume"),
        ("음소거 바꿈", "볼륨 바꿈", "Changed the volume"),
        ("창 배치: Safari 2개", "창 배치함", "Arranged the windows"),
        ("집 위치: Orlando", "집 위치 저장함", "Saved your home place"),
        ("변환: a.heic → a.jpg", "변환함", "Converted"),
        ("변환: 3개 → JPG", "변환함", "Converted"),
        ("convert: 2개 만듦", "변환함", "Converted"),
        ("합침: 3개 → PDF", "하나로 합침", "Merged"),
        ("나눔: PDF 1개 → 4개", "PDF 나눔", "Split the PDF"),
        ("압축: 2개 → 2개", "용량 줄임", "Made smaller"),
    ]
    for (summary, ko, en) in known {
        check(korean(summary) == ko, "receipt: the log's “\(summary)” reads “\(ko)” (got “\(korean(summary))”)")
        check(english(summary) == en, "receipt: the log's “\(summary)” reads “\(en)” in English (got “\(english(summary))”)")
    }
    check(korean("convert: 2개 (중간에 멈춤)") == "2개 만들고 멈춤" && english("merge: 1개 (중간에 멈춤)") == "Made 1, then stopped",
          "receipt: a conversion stopped half-way says what it made before it stopped")
    check(korean("새로운 종류: 무언가") == "새로운 종류: 무언가", "receipt: a log line the table doesn't know is shown as the log has it")
    let long = String(repeating: "가", count: 80)
    check(korean(long) == String(repeating: "가", count: ArisReceiptWords.lineLimit) + "…", "receipt: an unknown long line is cut with …")
    check(korean("메시지 보냄: 엄\u{200B}마\u{0007}") == "엄마에게 보냄", "receipt: invisible and control characters never reach the line")
    let name = String(repeating: "긴", count: 40) + ".pdf"
    let moved = korean("옮김: \(name) → ~/Desktop")
    check(moved.hasSuffix(".pdf 옮김") && moved.contains("…") && moved.count <= ArisReceiptWords.nameLimit + 4, "receipt: a long file name is cut in the middle and keeps its ending")
    check(ArisReceiptWords.count(3, english: false) == "3가지 함" && ArisReceiptWords.count(3, english: true) == "Did 3 things", "receipt: several acts are counted")
}

/// The lines aris-tools writes for the acts that had no log entry before.
private func receiptToolLinesTests() {
    check(ArisActSummary.messageSent(to: "엄마") == "메시지 보냄: 엄마", "act line: a sent message names who, never the text")
    check(ArisActSummary.reminderAdded("우유 사기") == "미리 알림 추가: 우유 사기", "act line: a reminder names its text")
    check(ArisActSummary.noteSaved("  장보기 \n") == "메모 저장: 장보기" && ArisActSummary.noteSaved(" ") == "메모 저장", "act line: a note names its title when it has one")
    check(ArisActSummary.forgot(2) == "기억 지움: 2개" && ArisActSummary.remembered("x") == "기억함: x", "act line: memory lines")
    // What the log does to a line (ArisActivity.oneLine) leaves its label readable.
    let logged = ArisActivity.oneLine(ArisActSummary.reminderAdded("줄\n바꿈"))
    check(ArisReceiptWords.line(logged, english: false) == "미리 알림에 추가함", "act line: a line the log flattened still reads as its act")
}

// MARK: - Which rows are this turn's

private func receiptActsTests() {
    let acts = { (items: [ArisActivityItem], earlier: Set<String>) in ArisReceipt.acts(in: items, since: receiptStart, earlier: earlier) }
    check(acts([], []).isEmpty && ArisReceipt(acts([], [])) == nil, "receipt: a turn that only read or answered has no rows and no receipt")
    check(acts([receiptRow("일정 추가: 치과", after: -30)], []).isEmpty, "receipt: a row from before the turn is not this turn's")
    // Logged 0.2 s into the turn: the log keeps whole seconds, so its date is before the turn's start to the millisecond.
    check(acts([receiptRow("일정 추가: 치과", after: 0.2)], []).count == 1, "receipt: a row logged in the turn's first second counts")
    check(acts([receiptRow("옮김: a → ~/b", job: "주간 보고서", worker: "Claude")], []).isEmpty, "receipt: a background job's row is not the turn's")
    check(acts([receiptRow("옮김: a → ~/b", job: "정리", worker: "코디", teammate: "cody")], []).isEmpty, "receipt: a teammate's row is not the turn's")
    check(acts([receiptRow("옮김: a → ~/b", job: "자료 조사", worker: "도우미 2")], []).isEmpty, "receipt: a helper's row is not the turn's")
    check(acts([receiptRow("할 일 추가: 우유", job: "Aris", worker: "user")], []).count == 1, "receipt: a change the app made itself in the turn counts")
    check(acts([receiptRow("메시지 보냄: 엄마", job: "대화", worker: "Codex")], []).count == 1, "receipt: the conversation's row counts whichever brain ran it")
    // A message the agent sends itself (the open Claude's) is logged under whose work it was (ArisSendJob).
    check(acts([receiptRow("메시지 보냄: 엄마", job: ArisSendJob.job(task: false), worker: "Claude")], []).count == 1,
          "receipt: a message the agent sent for the conversation is the turn's")
    check(acts([receiptRow("메시지 보냄: 엄마", job: ArisSendJob.job(task: true), worker: "Claude")], []).isEmpty,
          "receipt: a message a background job sent meanwhile is never put under the user's answer")
    check(acts([receiptRow("일정 추가: 치과", undone: true)], []).isEmpty, "receipt: a row already undone is not on the line")
    check(acts([receiptRow("일정 추가: 치과", id: "A")], ["A"]).isEmpty, "receipt: a row an earlier turn's line showed is never shown again")
    let ordered = acts([receiptRow("휴지통으로: b", id: "2", after: 5), receiptRow("옮김: a → ~/x", id: "1", after: 1)], [])
    check(ordered.map(\.id) == ["1", "2"], "receipt: the turn's acts are in the order they happened")
    let act = acts([receiptRow("일정 추가: 치과", id: "E", undoable: true, asks: true)], []).first
    check(act == ArisReceiptAct(id: "E", summary: "일정 추가: 치과", undoable: true, asks: true), "receipt: an act keeps its id, its line and what its undo needs")
}

// MARK: - The line

private func receiptLineTests() {
    let one = { (row: ArisActivityItem) in ArisReceipt(ArisReceipt.acts(in: [row], since: receiptStart, earlier: [])).map { ArisReceiptLine(receipt: $0) } }
    let event = one(receiptRow("일정 추가: 치과", undoable: true, asks: true))
    check(event?.words(english: false) == "캘린더에 추가함" && event?.offersUndo == true && event?.opensActivity == false,
          "receipt line: one act that can be undone says what was done and offers 되돌리기")
    let sent = one(receiptRow("메시지 보냄: 엄마"))
    check(sent?.words(english: false) == "엄마에게 보냄" && sent?.offersUndo == false, "receipt line: a sent message has no 되돌리기")
    let rows = [receiptRow("옮김: a → ~/x", after: 1, undoable: true), receiptRow("휴지통으로: b", after: 2, undoable: true), receiptRow("일정 추가: c", after: 3, undoable: true)]
    let many = ArisReceipt(ArisReceipt.acts(in: rows, since: receiptStart, earlier: [])).map { ArisReceiptLine(receipt: $0) }
    check(many?.words(english: false) == "3가지 함" && many?.opensActivity == true && many?.offersUndo == false,
          "receipt line: several acts are one counted line that opens the 한 일 tab, with no 되돌리기 of its own")
    check(many?.receipt.detail == "옮김: a → ~/x\n휴지통으로: b\n일정 추가: c", "receipt line: its tooltip lists the log's own lines")
}

// MARK: - From one turn to the next

private func receiptDeskTests() {
    let sent = receiptRow("메시지 보냄: 엄마", id: "M")
    let fresh = ArisReceiptDesk()
    check(fresh.line == nil && !fresh.reads(at: receiptStart), "receipt desk: before any turn there is no line and nothing to read")
    check(fresh.reading([sent], session: receiptSpeaking()).line == nil, "receipt desk: rows never make a line when no turn began")
    let open = fresh.beginning(at: receiptStart)
    check(open.reads(at: receiptStart.addingTimeInterval(40)), "receipt desk: while a turn is open its rows are read")
    check(open.reading([], session: receiptSpeaking()).line == nil, "receipt desk: a turn that changed nothing shows no line")
    let thinking = ArisSession().listening().hearing("보내 줘").thinking()
    check(open.reading([sent], session: thinking).line == nil, "receipt desk: no line while Aris is still working on the turn")
    let shown = open.reading([sent], session: receiptSpeaking())
    check(shown.line?.words(english: false) == "엄마에게 보냄", "receipt desk: once the answer is up, the turn's act is on the line")
    check(shown.reading([sent], session: receiptSpeaking()) == shown, "receipt desk: reading the same rows again changes nothing")
    let more = shown.reading([sent, receiptRow("미리 알림 추가: 우유", id: "R", after: 3)], session: receiptSpeaking())
    check(more.line?.words(english: false) == "2가지 함", "receipt desk: a row that lands later is counted on the line")
    // A turn that failed half-way: the failure line is up, and the receipt says what was really done.
    let failed = ArisSession().listening().hearing("둘 다 보내 줘").thinking().failing("연결이 끊겼어요.")
    check(open.reading([sent], session: failed).line?.words(english: false) == "엄마에게 보냄", "receipt desk: a turn that failed half-way shows what it really did")
    let stopped = receiptSpeaking("하나는 보냈고").done()
    check(open.reading([sent], session: stopped).line != nil, "receipt desk: a turn the user stopped mid-answer shows what it had already done")
    let silent = ArisSession().listening().hearing("둘 다 보내 줘").thinking().done()
    check(open.reading([sent], session: silent).line == nil, "receipt desk: a turn stopped before any answer leaves the notch no turn to put a line under")

    // Leaving.
    check(shown.seeing(receiptSpeaking().done()).line != nil, "receipt desk: the line stays while the answer is still parked in the notch")
    check(shown.seeing(ArisSession().listening()).line != nil, "receipt desk: listening for a follow-up with nothing heard yet is not a new turn")
    check(shown.seeing(ArisSession().listening().hearing("그리고")).line == nil, "receipt desk: the line leaves when the user's next words are heard")
    check(shown.seeing(thinking).line == nil, "receipt desk: the line leaves when Aris starts on the next turn")
    check(shown.seeing(ArisSession()).line == nil, "receipt desk: the line leaves with the answer on 닫기")
    check(shown.seeing(failed).line != nil && shown.closing().line == nil, "receipt desk: it stays under a failure line until its time is up")
    check(open.reading([sent], session: ArisSession()).line == nil, "receipt desk: rows that arrive after 닫기 raise no line")

    // The next turn.
    let next = shown.beginning(at: receiptStart.addingTimeInterval(0.3))
    check(next.line == nil, "receipt desk: a new turn starts with no line")
    check(next.reading([sent], session: receiptSpeaking()).line == nil, "receipt desk: the act the last line showed is not shown again by a turn in the same second")
    check(next.reading([sent, receiptRow("일정 추가: 치과", id: "E", after: 4, undoable: true)], session: receiptSpeaking()).line?.words(english: false) == "캘린더에 추가함",
          "receipt desk: the new turn's line holds only its own act")

    // The app's own change is logged a moment after the reply.
    let ended = open.ending(at: receiptStart.addingTimeInterval(10))
    check(ended.reads(at: receiptStart.addingTimeInterval(10 + ArisReceiptDesk.lateLog)) && !ended.reads(at: receiptStart.addingTimeInterval(10 + ArisReceiptDesk.lateLog + 1)),
          "receipt desk: a change logged just after the turn ended is still read; minutes later it isn't")
    check(ended.ending(at: receiptStart.addingTimeInterval(99)) == ended, "receipt desk: a turn ends once")
}

// MARK: - 되돌리기

private func receiptUndoTests() {
    let event = receiptRow("일정 추가: 치과", id: "E", undoable: true, asks: true)
    let shown = ArisReceiptDesk().beginning(at: receiptStart).reading([event], session: receiptSpeaking())
    let sent = ArisReceiptDesk().beginning(at: receiptStart).reading([receiptRow("메시지 보냄: 엄마")], session: receiptSpeaking())
    check(sent.pressingUndo() == nil, "receipt undo: a line with no undo has nothing to press")
    guard let pressed = shown.pressingUndo() else { return check(false, "receipt undo: a line with an undo takes the press") }
    check(pressed.act.id == "E" && pressed.act.asks && pressed.desk.line?.stage == .undoing, "receipt undo: the press names the entry and the button waits")
    check(pressed.desk.pressingUndo() == nil, "receipt undo: a second press while the first is out does nothing")
    check(pressed.desk.line?.words(english: false) == "캘린더에 추가함", "receipt undo: while it waits the line still says what was done")
    let next = ArisSession().listening().hearing("다음").thinking()
    check(pressed.desk.seeing(next).line != nil, "receipt undo: the line never leaves while its undo is still out")
    check(pressed.desk.reading([], session: receiptSpeaking()) == pressed.desk, "receipt undo: the log read meanwhile doesn't replace a line whose undo is out")

    let done = pressed.desk.undoEnded(.done("일정 추가: 치과"), for: pressed.act, english: false)
    check(done.line?.words(english: false) == "되돌렸어요" && done.line?.offersUndo == false, "receipt undo: undone, the line says 되돌렸어요 and the button is gone")
    check(done.reading([event], session: receiptSpeaking()) == done, "receipt undo: 되돌렸어요 is not replaced by the log's old row")
    check(pressed.desk.undoEnded(.done(""), for: pressed.act, english: true).line?.words(english: true) == "Undone", "receipt undo: in English it says Undone")

    let exists = pressed.desk.undoEnded(.failed("couldn't undo \"x\": a.pdf already exists there, so nothing was overwritten"), for: pressed.act, english: false)
    check(exists.line?.words(english: false) == "그 자리에 같은 이름이 있어서 덮어쓰지 않았어요." && exists.line?.offersUndo == true,
          "receipt undo: not undone, the line says why in Aris's words and keeps the button")
    check(exists.pressingUndo() != nil, "receipt undo: after a failure it can be pressed again")
    let busy = pressed.desk.undoEnded(.failed("지금은 대화 중이에요. 끝나고 다시 눌러 주세요."), for: pressed.act, english: false)
    check(busy.line?.words(english: false) == "지금은 대화 중이에요. 끝나고 다시 눌러 주세요.", "receipt undo: a card that couldn't be asked during a conversation says so")
    check(pressed.desk.undoEnded(.failed("that was already undone"), for: pressed.act, english: false).line?.stage == .undone,
          "receipt undo: something undone elsewhere meanwhile reads as undone")
    check(pressed.desk.undoEnded(nil, for: pressed.act, english: false).line?.stage == .done, "receipt undo: a no on the card leaves the line as it was")
    check(pressed.desk.undoEnded(.refused, for: pressed.act, english: false).line?.words(english: false) == ArisActivityTab.refusedNotice,
          "receipt undo: an undo the agent refused says so")
    if case .notUndone(let why)? = pressed.desk.undoEnded(.needsConfirm(id: "E", summary: "x"), for: pressed.act, english: false).line?.stage {
        check(why == "되돌리지 못했어요.", "receipt undo: an undo that asked again after a yes is told as not undone")
    } else {
        check(false, "receipt undo: an undo that asked again after a yes is told as not undone")
    }
    // The answer came back after the line had moved on to another turn's act.
    let other = pressed.desk.beginning(at: receiptStart.addingTimeInterval(20))
        .reading([receiptRow("할 일 추가: 우유", id: "T", after: 22, job: "Aris", worker: "user", undoable: true)], session: receiptSpeaking())
    check(other.undoEnded(.done(""), for: pressed.act, english: false) == other, "receipt undo: an old undo's answer never changes a newer turn's line")
}

// MARK: - About five seconds

private func receiptClockTests() {
    /// The clock after `ticks` ticks of one kind.
    func run(_ clock: ArisReceiptClock = ArisReceiptClock(), ticks: Int, hovering: Bool = false, speaking: Bool = false, undoing: Bool = false) -> ArisReceiptClock {
        (0..<ticks).reduce(clock) { clock, _ in clock.ticking(hovering: hovering, speaking: speaking, undoing: undoing) }
    }
    let second = Int(1 / ArisReceiptClock.tick)
    check(!run(ticks: 5 * second - 1).isOver && run(ticks: 5 * second).isOver, "receipt clock: the line stays five seconds")
    check(!run(ticks: 20 * second, speaking: true).isOver, "receipt clock: its time stands still while Aris is still saying the answer")
    check(!run(ticks: 60 * second, undoing: true).isOver, "receipt clock: its time stands still while an undo is on its way")
    check(!run(ticks: 20 * second, hovering: true).isOver, "receipt clock: it stays while the pointer is on the line")
    check(run(ticks: Int(ArisReceiptClock.longestHover) * second, hovering: true).isOver, "receipt clock: a pointer left on the line doesn't keep it for good")
    let hoveredFirst = run(run(ticks: 2 * second, hovering: true), ticks: 5 * second - 1)
    check(!hoveredFirst.isOver && run(hoveredFirst, ticks: 1).isOver, "receipt clock: two seconds under the pointer make it seven in all")
    check(run(run(ticks: 4 * second), ticks: 8 * second, speaking: true).counted == 4, "receipt clock: what was counted before a hold is kept")
}
