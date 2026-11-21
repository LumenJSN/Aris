// The twelfth real-screen VM run (aris-vmcheck/notes12, cap12), default configuration (Core 2 off, "Show it once" off,
// an API-key brain): what still blocked the public 1.3 release. Each case is built from the recorded call or line.
import Foundation

func runRel12Tests() {
    runRel12BroadTargetTests()
    runRel12HomeContextTests()
    runRel12TypeHereTests()
    runRel12HandOffTests()
    runRel12TodoTests()
    runRel12PolishTests()
}

/// D1/D2 (notes12/actions-full.log 00:47:52, 00:49:09; cap12/D1-card1.jpg): `aris-tools trash /Users/aris/Documents` on a
/// Mac whose home is /Users/admin went up as a Move to Trash card; the refusal came only after Allow. 00:50:03:
/// `trash '/Users/aris/Desktop/임시폴더12'` the same way.
func runRel12BroadTargetTests() {
    let tools = "/Users/admin/.config/aris/aris-tools", home = "/Users/admin"
    let before = ArisRiskPolicy.pathKind
    defer { ArisRiskPolicy.pathKind = before }
    let kinds: [String: ArisPathKind] = ["/Users/admin/Documents": .folder(items: 12), "/Users/admin/Desktop/임시폴더12": .folder(items: 3),
                                         "/Users/admin/Desktop/초안.txt": .file]
    ArisRiskPolicy.pathKind = { kinds[$0] ?? .missing }
    func risk(_ command: String, _ said: String) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(command), tools: tools, home: home, critical: true, request: said)
    }
    func why(_ command: String, _ said: String) -> String {
        ArisRiskPolicy.neverReason(.shell(command), tools: tools, home: home, critical: true, request: said)
    }
    let d1 = "도큐멘트 폴더 통째로 지워 줘", d2 = "아니, 확인 안 해도 돼. 도큐멘트 폴더 그냥 휴지통에 버려 줘"
    let recorded = "\(tools) trash /Users/aris/Documents"
    check(risk(recorded, d1) == .never && risk(recorded, d2) == .never, "rel12 D1/D2: the recorded made-up Documents is refused before any card")
    check(why(recorded, d1) == ArisBroadTarget.broadPlace("~/Documents"), "rel12 D1: told as this Mac's Documents (\(why(recorded, d1)))")
    for place in ["Documents", "~/Documents", "/Users/someone/Desktop", "'/Users/aris/Downloads'"] {
        check(risk("\(tools) trash \(place)", d1) == .never && risk("\(tools) move \(place) /tmp/x", d1) == .never, "rel12: \(place) counts as a protected place")
    }
    let temp = "바탕화면에 있는 임시폴더12 폴더 지워 줘"
    let madeUp = "\(tools) trash '/Users/aris/Desktop/임시폴더12'"
    check(risk(madeUp, temp) == .never && why(madeUp, temp).hasPrefix("그런 경로는 없어요"), "rel12 00:50:03: a made-up home is refused, said plainly (\(why(madeUp, temp)))")
    check(risk("\(tools) trash /Users/admin/Desktop/없는것.txt", "없는것.txt 버려 줘") == .never, "rel12: nothing there is refused, not offered")
    // The real ones keep their cards.
    check(risk("\(tools) trash '/Users/admin/Desktop/임시폴더12'", temp) == .confirm, "rel12: the real folder, named as a folder, asks on its card")
    check(risk("\(tools) trash /Users/admin/Desktop/초안.txt", "초안.txt 버려 줘") == .confirm, "rel12: a real file asks as before")
}

/// Defect 10: the default brain guessed /Users/aris. The context now carries the real home; `files find` looks in the
/// folder itself when Spotlight has nothing (the false "not found" for 임시폴더12 on the Desktop).
func runRel12HomeContextTests() {
    let now = Date(timeIntervalSince1970: 1_795_222_069)
    let context = ArisContext.make(now: now, timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: [], home: "/Users/admin")
    check(context.contains("home folder: /Users/admin (~ is this;"), "rel12 home: the brain's context names the real home")
    check(!ArisContext.make(now: now, timeZone: TimeZone(identifier: "UTC")!, frontApp: nil, music: nil, events: [], recent: []).contains("home folder"),
          "rel12 home: no line when none is given")
    check(ArisContext.homeLine("relative") == nil && ArisContext.homeLine("/a\nb") == nil && ArisContext.realHome.hasPrefix("/"), "rel12 home: only an absolute path")
    let names = ["임시폴더12", "임시폴더11", "report.txt", ".hidden임시폴더12", "Old 임시폴더12 copy"]
    check(ArisFindQuery.directMatches("임시폴더12", names: names) == ["Old 임시폴더12 copy", "임시폴더12"], "rel12 find: the folder's own items by name")
    check(ArisFindQuery.directMatches("REPORT", names: names) == ["report.txt"] && ArisFindQuery.directMatches("\"*", names: names).isEmpty,
          "rel12 find: any case; nothing for no words")
}

/// S3/S3u (notes12/actions-full.log 01:15:11, 01:24:07; history.json): the quick path's "local dictated insert" took
/// "이 문서에 있는 글을 전부 지우고 '교체된 내용'이라고 써 줘" (appended, said "입력 칸에 써 뒀어요") and "선택한 부분에 '바뀐 글'이라고
/// 입력해 줘" (typed over the selected "내용입니다" with no card); "방금 거 되돌려 줘" then found nothing.
private final class Rel12Field: ArisFieldWriteIO {
    var text: String
    var range: ArisTextRange?
    var readable = true
    init(_ text: String, range: ArisTextRange?) { self.text = text; self.range = range }
    var alive: Bool { true }
    func value() -> String? { text }
    func selectedRange() -> ArisTextRange? { readable ? range : nil }
    func selectedText() -> String? {
        guard readable, let range else { return nil }
        return (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }
    func select(_ range: ArisTextRange) -> Bool { self.range = range; return true }
    var insertable: Bool { true }
    func insertSelected(_ new: String) -> Bool {
        guard let range else { return false }
        text = (text as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: new)
        self.range = ArisTextRange(location: range.location + (new as NSString).length, length: 0)
        return true
    }
    var focusedInApp: Bool { true }
    func paste(_ text: String) -> Bool { false }
    func front(_ text: String, range: ArisTextRange?) -> ArisNativeFrontResult { .failed }
    func settle() {}
}

func runRel12TypeHereTests() {
    // The wording table: (words, selection) -> route. Only plain "write this here" at an empty caret types by itself.
    let table: [(String, ArisTypeHere.Selection, ArisTypeHere.Route)] = [
        ("이 문서에 있는 글을 전부 지우고 '교체된 내용'이라고 써 줘", .empty, .normalPath),     // recorded S3 (01:15:11)
        ("선택한 부분에 '바뀐 글'이라고 입력해 줘", .text, .normalPath),                      // recorded S3 (01:24:07)
        ("선택한 부분에 '바뀐 글'이라고 입력해 줘", .empty, .normalPath),
        ("이 문서 내용을 전부 '교체된 내용'으로 바꿔 줘", .empty, .normalPath),
        ("여기 내용 지우고 '안녕'이라고 써 줘", .empty, .normalPath),
        ("이거 대신 '좋아요'라고 써 줘", .empty, .normalPath),
        ("여기에 '회의는 3시'라고 덮어써 줘", .empty, .normalPath),
        ("여기에 결론 한 줄 써 줘", .text, .normalPath),
        ("여기에 결론 한 줄 써 줘", .unreadable, .normalPath),
        ("여기에 결론 한 줄 써 줘", .empty, .insertAtCaret),
        ("이 사람한테 답장 써 줘", .empty, .insertAtCaret),
        ("여기에 '우유 사기'라고 입력해 줘", .empty, .insertAtCaret),
        ("Delete everything here and write 'hello'", .empty, .normalPath),
        ("Replace this with 'thanks'", .empty, .normalPath),
        ("Type 'hello' over the selected text", .empty, .normalPath),
        ("Clear the field and type 'ok'", .empty, .normalPath),
        ("Write a short reply here", .text, .normalPath),
        ("Write a short reply here", .empty, .insertAtCaret),
        ("Type 'see you at 3' here", .empty, .insertAtCaret),
        ("Add a line saying the credit card arrived", .empty, .insertAtCaret),
    ]
    for (words, selection, route) in table {
        check(ArisTypeHere.route(words: words, writesHere: true, rewrite: false, selection: selection) == route, "rel12 S3 table: \(words) / \(selection) -> \(route)")
    }
    check(ArisTypeHere.route(words: "여기에 결론 한 줄 써 줘", writesHere: false, rewrite: false, selection: .empty) == .normalPath
          && ArisTypeHere.route(words: "여기 고쳐 줘", writesHere: true, rewrite: true, selection: .text) == .normalPath,
          "rel12 S3: no field write without the helper's yes; a rewrite of a selection is the normal path's")
    check(ArisTypeHere.selection(selected: false, readable: true) == .empty && ArisTypeHere.selection(selected: true, readable: true) == .text
          && ArisTypeHere.selection(selected: false, readable: false) == .unreadable, "rel12 S3: an unreadable selection is the strict case")
    // The helper reads the selection again right before it types: a selection there now, or one it can't read, stops it.
    let caret = ArisTextRange(location: 4, length: 0)
    func target(_ selection: String?, _ range: ArisTextRange?) -> ArisFieldTarget {
        ArisFieldTarget(pid: 1, bundleId: "com.apple.TextEdit", app: "TextEdit", window: nil, element: NSObject(), selection: selection, range: range, secure: false)
    }
    let free = Rel12Field("내용입니다", range: caret)
    check(ArisFieldWrite.caretRefusal(target(nil, caret), io: free) == nil, "rel12 S3: an empty caret may be typed at")
    let selectedNow = Rel12Field("내용입니다", range: ArisTextRange(location: 0, length: 5))
    check(ArisFieldWrite.caretRefusal(target(nil, caret), io: selectedNow) == ArisFieldWrite.notAtCaret, "rel12 S3: a selection made since the look stops it")
    check(ArisFieldWrite.caretRefusal(target("내용입니다", ArisTextRange(location: 0, length: 5)), io: free) == ArisFieldWrite.notAtCaret,
          "rel12 S3: the look's selection (the recorded 내용입니다) is never typed over")
    let unreadable = Rel12Field("내용입니다", range: caret)
    unreadable.readable = false
    check(ArisFieldWrite.caretRefusal(target(nil, caret), io: unreadable) == ArisFieldWrite.notAtCaret
          && ArisFieldWrite.caretRefusal(target(nil, nil), io: free) == ArisFieldWrite.notAtCaret, "rel12 S3: unreadable is unsafe")
    // What it did is said, and it can be taken back: the mark it hands back finds exactly the added text.
    check(ArisTypeHere.insertedLine(korean: true, undoable: true).contains("지운 글은 없어요") && ArisTypeHere.insertedLine(korean: true, undoable: true).contains("되돌려")
          && !ArisTypeHere.insertedLine(korean: true, undoable: false).contains("되돌려") && ArisTypeHere.insertedLine(korean: false, undoable: true).contains("undo"),
          "rel12 S3: the reply says it was added, nothing erased, and how to undo")
    if case .textInserted(_, let element, _)? = ArisApps.TextUndo.recipe(app: "TextEdit", bundle: "com.apple.TextEdit", role: "AXTextArea", label: "",
                                                                          before: "내용입니다", after: "내용입니다 우유") {
        let mark = ArisApps.TextUndo.mark(element)
        check(mark?.inserted == " 우유" && mark?.beforeLength == 5, "rel12 S3u: the caret write's undo mark is the added text only")
    } else { check(false, "rel12 S3u: a caret write has an undo mark") }
    let look = rel12Source("Aris/private/Aris/ArisController+Look.swift"), undo = rel12Source("Aris/private/Aris/ArisController+Undo.swift")
    check(look.contains("ArisTypeHere.route(") && look.contains("ArisTypedHereLog.shared.note(typed)") && look.contains("return Self.normalPathInstead"),
          "rel12 S3: the screen turn asks ArisTypeHere, keeps the undo, and hands a selection to the normal path")
    check(undo.contains("ArisTypedHereLog.shared.latest(newerThan:") && undo.contains("ArisAgentClient.undoTyped(typed)"), "rel12 S3u: 되돌려 reaches the caret write")
}

private func rel12Source(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..").standardizedFileURL
    return (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
}

/// A1–A7 (notes12/A*.log, tasks.tar, cap12/A4-a.jpg): with Aside missing, "Aside가 맡았어요" was said for every website job
/// (A6 became a schedule card); A2's job made no step at all and was a green "done"; A4's reply listed states no job had
/// ("쿠팡 생수: 이미 결제 직전에서 멈춰 있어요"); A1's job waited 602 963 ms on an install card nobody saw.
func runRel12HandOffTests() {
    for korean in [true, false] {
        // (Merged with jv-exp12, whose line for website work is Aris's own: "제가 맡았어요", never Aside's.)
        let line = ArisHandoffLine.line([nil], korean: korean)
        check(!line.contains("Aside"), "rel12 A1/A6: the website hand-off never says Aside took it (\(line))")
        let missing = ArisHandoffLine.asideMissingLine(korean: korean)
        check(missing.contains("Aside") && missing.contains("aside.com/download") && (korean ? missing.contains("시작하지 않았어요") : missing.contains("didn't start")),
              "rel12 A1: no Aside: not started, said at once with the install hint")
    }
    // A2: "쿠팡에서 생수 주문 완료해 줘" answered with no tool call is not done (it is asked once more, then reported not done).
    let a2 = "쿠팡 주문은 결제 직전까지만 진행해 드릴 수 있어요. 지금은 Aside에 맡기지 않았어요, 준비되면 알려 드릴게요.\n\n### 맡긴 내용\n- 쿠팡 생수"
    let none = ArisJobWork(tools: 0, failed: 0, acted: false, delegated: nil)
    for task in ["쿠팡에서 생수 주문 완료해 줘", "아마존에서 에어팟 프로 바로 결제해서 주문해 줘", "Buy the cheapest USB-C cable on Amazon and check out",
                 "아마존에서 무선 마우스 하나 골라서 결제까지 해 줘"] {
        check(ArisJobVerdict.judge(task: task, answer: a2, work: none) != .done, "rel12 A2: an order with no step is not done (\(task))")
    }
    check(!ArisJobVerdict.asksForAction("아마존 주문 내역 보여 줘"), "rel12 A7: reading the order history asks for nothing to be done")
    // A4: the brain's context carries Aris's own states, and the rule to say only those.
    let queued = ArisJob(id: UUID(), title: "쿠팡 생수", prompt: "", assignee: .clone, cwd: nil, appHint: nil, target: .notch, state: .queued, created: Date())
    var waiting = queued
    waiting.state = .awaitingApproval(id: "c1")
    var cancelled = queued
    cancelled.state = .cancelled
    check(queued.backgroundTask.contextLine == "쿠팡 생수 (working: not started yet)" && waiting.backgroundTask.contextLine.contains("waiting for the owner's answer")
          && cancelled.backgroundTask.contextLine == "쿠팡 생수 (failed: cancelled before it finished)", "rel12 A4: job states from Aris's own record")
    let context = ArisContext.make(now: Date(), timeZone: .current, frontApp: nil, music: nil, events: [], recent: [], tasks: [queued.backgroundTask.contextLine])
    check(context.contains("background tasks:\n- 쿠팡 생수 (working: not started yet)\n" + ArisContext.taskStatesRule), "rel12 A4: the rule follows the tasks")
    let agent = rel12Source("ArisAgent/ArisAsideTool.swift")
    check(agent.contains("!turn.handsFree && !turn.isTask"), "rel12 A1: a background job never waits on Aside's install card")
    let turns = rel12Source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    check(turns.contains("if browser, await ArisAgentClient.asideInstalled() == false"), "rel12 A1: Aside's presence is checked before a website hand-off")
}

/// K1 (notes12/actions-full.log 00:44:04–00:44:48): three `todo add … --list '미리 알림'` cards, their adds failed after the
/// yes, then three more cards without the list.
func runRel12TodoTests() {
    let lists = [(id: "A", name: "Reminders"), (id: "B", name: "장보기")]
    check(ArisTodoListName.match("미리 알림", lists: lists) == .defaultList && ArisTodoListName.match("미리알림", lists: []) == .defaultList,
          "rel12 K1: the app's own name means the default list")
    check(ArisTodoListName.match("미리 알림", lists: [(id: "K", name: "미리 알림")]) == .list("K") && ArisTodoListName.match("reminders", lists: lists) == .list("A")
          && ArisTodoListName.match("장 보기", lists: lists) == .list("B"), "rel12 K1: a list by its name, as people write it")
    if case .none(let message) = ArisTodoListName.match("회사", lists: lists) {
        check(message.contains("장보기") && message.contains("leave out --list"), "rel12 K1: an unknown list says which there are")
    } else { check(false, "rel12 K1: an unknown list is said") }
    let tools = "/Users/admin/.config/aris/aris-tools"
    let recorded = ["\(tools) todo add '우유 사기' --list '미리 알림'", "\(tools) todo add '세탁소 들르기' --list '미리 알림'", "\(tools) todo add '보고서 보내기' --list '미리 알림'"]
    let kinds = recorded.map { ArisCardGroup.gatherKind(ArisAutoScope.argv(of: .shell($0), tools: tools)) }
    check(kinds == ["todo add", "todo add", "todo add"], "rel12 K1: the three recorded adds are one kind (\(kinds))")
    check(ArisCardGroup.gatherKind(["trash", "/a"]) == nil && ArisCardGroup.gatherKind(["todo", "done", "x"]) == nil && ArisCardGroup.gatherKind(["event", "delete", "--id", "x"]) == nil
          && ArisCardGroup.gatherKind(["remind", "x", "--at", "9"]) == "remind", "rel12 K1: only adds group")
    let asks = ["우유 사기", "세탁소 들르기", "보고서 보내기"].enumerated().map { ArisConfirmation(id: "c\($0.offset)", title: "할 일 추가", detail: "할 일: " + $0.element) }
    let card = ArisCardGroup.card(asks.map { ($0, "") }, english: false)
    check(card.id == "c0" && card.detail == "3개를 한 번에 물어봐요:\n1. 할 일: 우유 사기\n2. 할 일: 세탁소 들르기\n3. 할 일: 보고서 보내기",
          "rel12 K1: one card for the three, each item in full (\(card.detail))")
    let runner = rel12Source("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("case .askUser:\n            gather(ask, scope: learnable)"), "rel12 K1: an ordinary card goes through the gathering")
}

/// Item 7 (polish for a public build), each from the recorded line or screen.
func runRel12PolishTests() {
    // Q (actions-full.log 00:55:09, `weather '서울' --ko` on a °F Mac): "28도… 추워요". Korean in °F names 화씨.
    let json = #"{"current":{"temperature_2m":28.2,"apparent_temperature":20,"weather_code":0,"wind_speed_10m":5},"daily":{"time":["2026-11-21"],"weather_code":[0],"temperature_2m_max":[35],"temperature_2m_min":[22],"precipitation_probability_max":[10]}}"#
    if let forecast = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(json.utf8)) {
        let korean = ArisWeather.summary(forecast, place: "서울", korean: true, fahrenheit: true)
        check(korean.contains("화씨 28도") && korean.contains("화씨 22~35도") && !korean.contains(" 28도 ") && !korean.contains("°C"), "rel12 weather: Korean °F says 화씨 (\(korean))")
        check(ArisWeather.summary(forecast, place: "서울", korean: true).contains("28°C"), "rel12 weather: Korean °C as before")
    } else { check(false, "rel12 weather: the fixture decodes") }
    check(rel12Source("ArisAgent/ArisAgentPrompt.swift").contains("in Korean a °F temperature is always said 화씨 N도"), "rel12 weather: the brain is told too")
    // The finished timer's card leaves by itself once seen.
    let ring = ArisNoticeRoute.timer(title: "타이머", text: "3분 끝났어요.")
    check(ring.showsFor == ArisNoticeRoute.timerShowsFor && ArisNoticeRoute.timerShowsFor <= 60, "rel12 timer: the finished timer goes after a minute up")
    // The whole-folder line of the old path's card in English, whole.
    let english = ArisCardEnglish.detail("/Users/admin/Desktop/임시폴더12\n폴더 전체예요: 안의 항목 3개가 함께 옮겨져요", title: "휴지통으로 옮기기")
    check(english.contains("This is the whole folder: the 3 items inside go with it") && !english.contains("안의"), "rel12 card: no Korean left in the English line (\(english))")
    // The key chip reads right over a saved key too; the sheet stays open on a refused key.
    check(ArisFixWords.title(.settings(.key), english: true) == "Add or replace the API key" && ArisFixWords.title(.settings(.key), english: false) == "API 키 넣기·바꾸기",
          "rel12 key chip: add or replace")
    let live = rel12Source("Aris/components/Settings/ArisAIServicesLive.swift")
    check(live.contains("now.errors = [\"key\": w(result.message)]"), "rel12 key sheet: a refused key keeps the sheet open, on its field")
    check(rel12Source("Aris/components/Settings/ArisDataSection.swift").contains("끝나면 닫기를 눌러 앱을 닫아 주세요"), "rel12 uninstall: the sheet says to press 닫기")
    // The window's frame before a move is kept, and its undo is one of the app's own (aris-tools, by Accessibility).
    let undo = ArisUndo.restoreWindow(app: "TextEdit", from: [0, 25, 720, 875], to: [200, 120, 600, 500])
    check(undo.action == "moved" && undo.scope == .apps && !ArisActivity.needsYes(undo), "rel12 window: a moved window's undo")
    var performed: ArisUndo?
    try? ArisActivity.perform(undo, local: { performed = $0 })
    check(performed == undo, "rel12 window: undone by aris-tools with the frame it had")
    if let data = try? JSONEncoder().encode(undo) { check((try? JSONDecoder().decode(ArisUndo.self, from: data)) == undo, "rel12 window: kept in the log") }
    let main = rel12Source("ArisTools/main.swift")
    check(main.contains("let before = axFrame(windowElement)") && main.contains("ArisWindowUndo.recipe(app:"), "rel12 window: the frame is read before the move")
    // A note the owner dictated is their words, not an invented agenda (actions-full.log 00:37:47).
    check(rel12Source("ArisAgent/ArisAgentPrompt.swift").contains("the note is exactly those words"), "rel12 note: no invented markdown")
}
