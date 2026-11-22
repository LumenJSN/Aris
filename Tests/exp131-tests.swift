//
//  exp131-tests.swift
//
//  jv-exp131: the thirteenth VM run's Experimental-mode defects (Core 2 and "Show it once" on, a11d7666), replayed
//  from what that run recorded (aris-vmcheck notes13: record-full.jsonl, record-B.jsonl, turns.jsonl, history.json,
//  tasks.tar; cap13/*.jpg) through the real judge and gate. The pure rules are in Tests/ArisCoreTests/ArisExp131Tests.swift.
//

import Foundation

private let exp131Root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private func exp131Source(_ path: String) -> String { (try? String(contentsOf: exp131Root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
private let exp131Tools = "/Applications/Aris.app/Contents/Helpers/aris-tools"

private func exp131Home() -> String {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-exp131-\(UUID().uuidString.prefix(8))")
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
}

private func exp131Call(_ id: String, _ name: String, _ arguments: [String: Any]) -> ArisMindToolCall {
    let data = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
    return ArisMindToolCall(id: id, name: name, arguments: String(decoding: data, as: UTF8.self))
}

private func exp131Runs(_ decided: [ArisMindDecided]) -> Bool {
    if case .run? = decided.first?.verdict { return true }
    return false
}

/// record-full.jsonl (thirteenth VM run, a11d7666), the lines of items 1 and 5 as the helper wrote them (seals left out).
private let exp131Record: [String] = [
    #"{"answer":"yes","arguments":[{"kind":"app","value":"TextEdit"},{"kind":"body","value":"교체된 내용"}],"at":"2026-11-21T23:03:23Z","capability":"app.type","decision":"sayThenRun(4s)","effect":"change-permanent","id":"108957b7-a370-4b4a-b152-10a00fc056dd","kind":"call","ok":true,"provenance":"ownerSaid","result":"{\"channel\":\"engine\",\"did\":\"set 6 characters in TextEdit\",\"effect\":\"change-permanent\",\"now\":\"the field holds the text\",\"ok\":true,\"verified\":true}","session":"claude-e75a681092b9c5f7","undo":{"textInserted":{"app":"TextEdit","before":"","element":"{\"label\":\"\",\"beforeHash\":\"80a35a3b50ce1a90\",\"beforeLength\":50,\"inserted\":\"교체된 내용\",\"location\":0,\"afterLength\":6,\"erased\":\"1686b891-4104-430e-b365-5b077ce5ef85\",\"afterHash\":\"7ea450e4727c1ad5\",\"role\":\"textArea\",\"bundle\":\"com.apple.TextEdit\"}"}},"v":1,"why":["app: the owner's words","body: the owner's words"]}"#,
    #"{"at":"2026-11-21T23:03:38Z","id":"e23c9016-7009-4e62-a700-f709faad81de","kind":"undone","ok":true,"ref":"108957b7-a370-4b4a-b152-10a00fc056dd","result":"Put back the text I replaced in TextEdit","v":1}"#,
    #"{"arguments":[{"kind":"app","value":"TextEdit"}],"at":"2026-11-21T23:23:35Z","capability":"app.open","decision":"runWithUndo","effect":"change-reversible","id":"0a8f214d-8c74-4960-86a9-1e8c96eaf524","kind":"call","ok":true,"provenance":"ownStep","result":"{\"channel\":\"workspace\",\"did\":\"opened TextEdit (in the background)\",\"effect\":\"change-reversible\",\"now\":\"TextEdit is running in the background\",\"ok\":true,\"verified\":true}","session":"teach-b2d6bd60","v":1,"why":["app: first seen in app TextEdit","step 1 of the procedure the owner approved when it was saved"]}"#,
    #"{"arguments":[{"kind":"app","value":"TextEdit"},{"kind":"body","value":" 우유"}],"at":"2026-11-21T23:23:35Z","capability":"app.type","decision":"runWithUndo","effect":"change-reversible","id":"f153770f-cea4-482f-a541-dd23ca8780fa","kind":"call","ok":true,"provenance":"ownStep","result":"{\"channel\":\"engine\",\"did\":\"typed 3 characters in TextEdit (textArea)\",\"effect\":\"change-reversible\",\"now\":\"the field holds the text; it is on a line of its own\",\"ok\":true,\"verified\":true}","session":"teach-b2d6bd60","undo":{"textInserted":{"app":"TextEdit","before":"","element":"{\"inserted\":\"\\n우유\",\"afterHash\":\"f4eb682b260e54f8\",\"role\":\"textArea\",\"location\":3,\"label\":\"\",\"afterLength\":6,\"beforeLength\":3,\"bundle\":\"com.apple.TextEdit\",\"beforeHash\":\"932bc4ab64390e9c\"}"}},"v":1,"why":["app: first seen in app TextEdit","body: the owner's words","step 2 of the procedure the owner approved when it was saved"]}"#,
    #"{"arguments":[{"kind":"body","value":"우유"}],"at":"2026-11-21T23:23:35Z","capability":"taught.run","decision":"runWithUndo","effect":"change-reversible","id":"b151265d-92a5-471b-95b2-d2e9260bcc7d","kind":"call","ok":true,"provenance":"ownerSaid","result":"Done: “줄 추가” (2 steps). Tell the owner exactly this, in his language.","session":"claude-7d2fde40232f5292","v":1,"why":["body: the owner's words"]}"#,
    #"{"arguments":[{"kind":"path","value":"~\/Desktop\/X13\/sub\/초안13.txt"}],"at":"2026-11-21T23:23:58Z","capability":"aris.file_trash","decision":"runWithUndo","effect":"change-reversible","id":"84c97c0c-ab18-445a-9804-7affb66cff44","kind":"call","logged":["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"],"ok":true,"provenance":"ownerSaid","result":"moved to the Trash: 초안13.txt This was done with an undo kept. Tell the owner in one short sentence what was done and that it can be undone (Korean: “…했어요. 되돌릴 수 있어요.”; English: “Done. You can undo it.","session":"claude-7d2fde40232f5292","v":1,"why":["path: the owner's words"]}"#,
    #"{"arguments":[{"kind":"path","value":"~\/Desktop\/v13\/rename-me.txt"}],"at":"2026-11-21T23:26:16Z","capability":"aris.file_rename","decision":"runWithUndo","effect":"change-reversible","id":"a183727d-9d5d-40a1-a8a1-d9f4ceec3aed","kind":"call","logged":["80562578-e411-4e07-8819-e0f437087d32"],"ok":true,"provenance":"ownerSaid","result":"renamed rename-me.txt to renamed13b.txt This was done with an undo kept. Tell the owner in one short sentence what was done and that it can be undone (Korean: “…했어요. 되돌릴 수 있어요.”; English: “Done. You c","session":"claude-7d2fde40232f5292","v":1,"why":["path: the owner's words"]}"#,
    #"{"at":"2026-11-21T23:27:48Z","id":"688e3889-d8c9-43cf-a96b-6b850d6ce83e","kind":"undone","ok":true,"ref":"f153770f-cea4-482f-a541-dd23ca8780fa","result":"TextEdit에 입력한 글을 지웠어요","v":1}"#,
    #"{"arguments":[],"at":"2026-11-21T23:27:48Z","capability":"record.undo_last","decision":"runWithUndo","effect":"change-reversible","id":"ae229000-f4d2-4cd8-8c8f-69735abab4ca","kind":"call","ok":true,"provenance":"ownerSaid","result":"TextEdit에 입력한 글을 지웠어요","session":"claude-7d2fde40232f5292","v":1}"#,
    #"{"arguments":[],"at":"2026-11-21T23:28:38Z","capability":"aris.add_event","decision":"runWithUndo","effect":"change-reversible","id":"5dc13942-43ae-4fa8-8a2f-ae704a054a3a","kind":"call","ok":true,"provenance":"ownerSaid","result":"event already there: “팀 회의” at that time, so it wasn't added again. Tell the user it's already in the calendar.","session":"claude-5ce38bde15bc7c9f","v":1}"#,
    #"{"arguments":[{"kind":"path","value":"~\/Desktop\/v13\/renamed13b.txt"}],"at":"2026-11-21T23:31:16Z","capability":"aris.file_rename","decision":"runWithUndo","effect":"change-reversible","id":"93d58eca-42bc-4ab9-98b9-45668f1a3f85","kind":"call","logged":["dd20d2eb-d39f-4ed2-92e2-b6647ddd7a0b"],"ok":true,"provenance":"ownerSaid","result":"renamed renamed13b.txt to rename-me.txt This was done with an undo kept. Tell the owner in one short sentence what was done and that it can be undone (Korean: “…했어요. 되돌릴 수 있어요.”; English: “Done. You c","session":"claude-7d2fde40232f5292","v":1,"why":["path: the owner's words"]}"#,
]

func runExp131Tests() {
    exp131UndoKindTests()
    exp131UndoCardTests()
    exp131JobStateTests()
    exp131JobSessionTests()
    exp131CardTests()
    exp131ReceiptTests()
    exp131TeachRouteTests()
    exp131LanguageTests()
    exp131FieldChangedTests()
}

// MARK: - 1: undo takes what he named (record-full.jsonl 23:27:48, 23:30:25)

/// The run's three entries, re-dated to now (their order and gaps kept): the taught run's typed line, the Trash (undone
/// through the activity log at 23:25:57) and the rename, both kept in the log.
private func exp131UndoEntries(_ now: Date) -> (typed: ArisRecordEntry, trash: ArisRecordEntry, rename: ArisRecordEntry) {
    let decoded = exp131Record.compactMap { ArisRecordEntry.decode(Data($0.utf8)) }
    func redated(_ id: String, ago: TimeInterval, session: String?) -> ArisRecordEntry {
        let old = decoded.first { $0.id.hasPrefix(id) }!
        var entry = ArisRecordEntry.call(id: old.id, at: now.addingTimeInterval(-ago), session: session, task: nil, capability: old.capability ?? "",
                                         effect: old.effect ?? .changeReversible, provenance: .ownerSaid, decision: .runWithUndo(announce: false),
                                         arguments: old.arguments ?? [], result: old.result, ok: old.ok ?? false, undo: old.undo)
        entry.logged = old.logged
        return entry
    }
    return (redated("f153770f", ago: 253, session: "teach-b2d6bd60"), redated("84c97c0c", ago: 230, session: "claude-7d2fde40232f5292"),
            redated("a183727d", ago: 92, session: "claude-7d2fde40232f5292"))
}

private func exp131UndoKindTests() {
    check(exp131Record.allSatisfy { ArisRecordEntry.decode(Data($0.utf8)) != nil }, "exp131 1: the run's record lines read back")
    let home = exp131Home()
    let now = Date()
    let (typed, trash, rename) = exp131UndoEntries(now)
    for entry in [typed, trash, rename] { ArisRecordJournal.append(entry, home: home) }
    check(rename.logged == ["80562578-e411-4e07-8819-e0f437087d32"] && trash.logged == ["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"],
          "exp131 1: the rename and the Trash name their activity log lines (the record's `logged`)")
    let before = ArisRecord.loggedUndone
    ArisRecord.loggedUndone = { ["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"] }
    defer { ArisRecord.loggedUndone = before }
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: exp131Tools, passes: ArisMindPasses())
    judge.cardWait = 2
    // 23:27:48 "방금 이름 바꾼 거 되돌려 줘": the model's undo_last with no arguments.
    judge.turn(session: "claude-7d2fde40232f5292", intent: "u1", words: "방금 이름 바꾼 거 되돌려 줘")
    let decided = judge.decide(session: "claude-7d2fde40232f5292", task: nil, calls: [exp131Call("u1c", "undo_last", [:])], intent: "u1")
    check(exp131Runs(decided), "exp131 1: the rename he named is the newest change: it runs with no card (\(String(describing: decided.first?.verdict)))")
    let caller = judge.caller(session: "claude-7d2fde40232f5292", task: nil, call: "u1c")
    check(caller.named == .rename && caller.planned == [rename.id], "exp131 1: the run is bound to their words' kind and the entry decided")
    // The route hands the same to the Mind's child (its caller fields).
    let fields = ArisMindRoute.caller(judge, session: "claude-7d2fde40232f5292", id: "u1c")
    check(fields["undoKind"] as? String == "rename" && fields["undoIDs"] as? [String] == [rename.id], "exp131 1: the route's caller carries the plan")
    var hands = ArisUndoHands()
    var taken: [String] = []
    hands.undoLogged = { taken += $0 }
    let done = ArisRecord.undo(last: 1, caller: caller, home: home, store: ArisUndoStore(home: home), hands: hands, now: now)
    check(done.undone.map(\.id) == [rename.id] && taken == rename.logged ?? [] && done.failed == nil,
          "exp131 1: the rename is taken back through its activity log lines, the typed line left alone (\(done))")
    let reply = ArisRecord.reply(done)
    check(!reply.isError && reply.text.contains("rename-me.txt") && reply.text.hasPrefix("되돌렸어요"), "exp131 1: the reply is the record's, naming it (\(reply.text))")
    check(ArisRecordJournal.state(home: home).isUndone(rename.id), "exp131 1: the record says it was undone")
    // A plain "방금 거 되돌려" now takes the newest left: the typed line (the Trash was undone through the log).
    judge.turn(session: "claude-7d2fde40232f5292", intent: "u2", words: "방금 거 되돌려")
    _ = judge.decide(session: "claude-7d2fde40232f5292", task: nil, calls: [exp131Call("u2c", "undo_last", [:])], intent: "u2")
    check(judge.caller(session: "claude-7d2fde40232f5292", task: nil, call: "u2c").planned == [typed.id], "exp131 1: with no kind named, the newest change")
    judge.end(session: "claude-7d2fde40232f5292")
    try? FileManager.default.removeItem(atPath: home)
}

private func exp131UndoCardTests() {
    let home = exp131Home()
    let now = Date()
    let (typed, trash, rename) = exp131UndoEntries(now)
    for entry in [typed, trash, rename] { ArisRecordJournal.append(entry, home: home) }
    let before = ArisRecord.loggedUndone
    ArisRecord.loggedUndone = { ["b9d0d872-e1e2-43c3-957f-ecc05b3dd5a7"] }
    defer { ArisRecord.loggedUndone = before }
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: exp131Tools, passes: ArisMindPasses())
    judge.cardWait = 2
    // He names the Trash, which the log already took back: never another kind silently; said, and the newest offered.
    judge.turn(session: "s", intent: "t1", words: "휴지통에 버린 거 되돌려 줘")
    let decided = judge.decide(session: "s", task: nil, calls: [exp131Call("c1", "undo_last", [:])], intent: "t1")
    check(decided.first?.verdict == .waits, "exp131 1: what he named isn't there: a card, never a silent undo (\(String(describing: decided.first?.verdict)))")
    var shown: [ArisConfirmation] = []
    let allowed = judge.ask(session: "s", task: nil, intent: "t1", waiting: decided) { card, answer in
        shown.append(card)
        answer(true)
    }
    let card = shown.first
    check(card?.title == "되돌리기" && card?.detail.contains("휴지통에 넣은 것은 기록에 없어요") == true && card?.detail.contains("rename-me.txt") == true,
          "exp131 1: the card says his kind isn't there and names what it would take back (\(String(describing: card)))")
    check(allowed == ["c1"], "exp131 1: their yes lets it run")
    let caller = judge.caller(session: "s", task: nil, call: "c1")
    check(caller.approved && caller.planned == [rename.id], "exp131 1: their yes is for exactly what the card named")
    // An older one of his kind (the typed line, under the rename): asked on a card that names it.
    judge.turn(session: "s", intent: "t2", words: "아까 입력한 글 되돌려 줘")
    let older = judge.decide(session: "s", task: nil, calls: [exp131Call("c2", "undo_last", [:])], intent: "t2")
    check(older.first?.verdict == .waits && judge.caller(session: "s", task: nil, call: "c2").planned == [typed.id],
          "exp131 1: an undo of an entry older than the newest asks first (\(String(describing: older.first?.verdict)))")
    // The executor's side refuses a run that wasn't approved when the plan asks.
    let unapproved = ArisRecord.undo(last: 1, caller: ArisUndoCaller(session: "s", provenance: .ownerSaid, named: .typing), home: home,
                                     store: ArisUndoStore(home: home), hands: ArisUndoHands(), now: now)
    check(unapproved.undone.isEmpty && unapproved.failed?.hasPrefix("먼저 여쭤봐야 해요") == true, "exp131 1: no run without their yes on that card")
    judge.end(session: "s")
    try? FileManager.default.removeItem(atPath: home)
}

// MARK: - 2: jobs are spoken of only as the record shows them (B4 "결제까지 알아서 해")

private func exp131JobStateTests() {
    let world = "now: Saturday, 2026-11-21 22:51"
    let job = ArisMindBrainDriver.context(world, task: true)
    check(job.hasPrefix(ArisMindSession.jobContext) && job.contains(world), "exp131 2: a job's turn is told it is the only task it knows of")
    check(ArisMindBrainDriver.context(world, task: false) == world, "exp131 2: a conversation's context is the World's, as before")
    check(ArisMindSession.jobContext.contains("Never say another task is under way") && ArisMindSession.jobContext.contains("never promise to change one"),
          "exp131 2: no invented task and no promise to change one")
    check(ArisMindSession.rules.contains(ArisMindSession.jobsRule) && ArisMindSession.jobsRule.contains("When none is listed, none exists"),
          "exp131 2: the Mind's rules say tasks only as the record shows them")
    let driver = ArisMindBrainDriver(profile: nil, task: true, context: { world })
    let line = driver.ask("결제까지 알아서 해", tier: .critical).first.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
    check((line?["context"] as? String)?.hasPrefix(ArisMindSession.jobContext) == true, "exp131 2: wiring: the job's ask carries it")
}

// MARK: - 3: each job is its own session; one refused hand-off ends that line in a job (record-B.jsonl 22:52, 22:53)

private func exp131JobSessionTests() {
    // The session name was the runner's address: B5's job got B1's ("claude-ee1cfd683ffaf76d"), B7's got B3's.
    var names = Set<String>()
    for _ in 0..<300 { autoreleasepool { names.insert(ArisMindRoute.session(NSObject())) } }
    check(names.count == 300, "exp131 3: a new runner never takes a gone runner's session name (\(names.count) of 300)")
    let kept = NSObject()
    check(ArisMindRoute.session(kept) == ArisMindRoute.session(kept), "exp131 3: a runner keeps its own name while it lives (the conversation's tracker)")
    check(exp131Source("ArisAgent/ArisAgentRunner.swift").contains("if ArisCore2.isOn() { ArisMindJudge.shared.end(session: ArisMindRoute.session(self)) }"),
          "exp131 3: wiring: a finished job's tracker and asks go with it")
    let home = exp131Home()
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: exp131Tools, passes: ArisMindPasses())
    judge.cardWait = 2
    // B1's job read the AirPods brief back (as content of its own session).
    let first = ArisMindRoute.session(NSObject()), second = ArisMindRoute.session(NSObject())
    let airpods = "aris-tools aside 아마존에서 에어팟 프로를 장바구니에 담고 결제 화면 직전까지만 진행해. 결제 버튼은 누르지 마. 멈춘 뒤 상품 이름과 합계 금액을 알려 줘."
    judge.jobTurn(session: first, intent: "b1", request: "아마존에서 에어팟 프로 바로 결제해서 주문해 줘")
    gate.toolResult(session: first, call: nil, text: airpods, source: ArisContentSource(kind: "service", source: airpods))
    // B5: a new job, a new session: its own brief is its own, never the earlier job's content.
    let request = "이거 맡길게: 아마존에서 무선 마우스 하나 골라서 결제까지 해 줘"
    judge.jobTurn(session: second, intent: "b5", request: request)
    let mouse = "아마존에서 무선 마우스를 하나 골라 장바구니에 담고 결제 화면 직전까지만 진행해. 결제 버튼은 누르지 마. 멈춘 뒤 상품 이름과 합계 금액을 알려 줘."
    let own = judge.decide(session: second, task: second, calls: [exp131Call("m1", "aside_task", ["brief": mouse])], intent: "b5")
    check(own.first?.verdict == .waits, "exp131 3: the new job's brief goes on its card, not refused as the old job's content (\(String(describing: own.first?.verdict)))")
    // In a job, one refused hand-off ends that line: it isn't written again and retried.
    let third = ArisMindRoute.session(NSObject())
    judge.jobTurn(session: third, intent: "b7", request: "백그라운드로 아마존에서 HDMI 케이블 하나 사서 결제까지 해 놔")
    let paying = judge.decide(session: third, task: third, calls: [exp131Call("h1", "aside_task", ["brief": "아마존에서 HDMI 케이블 하나 사서 결제까지 해."])], intent: "b7")
    check(paying.first?.verdict == .refuse(ArisPaymentBoundary.refusedLine), "exp131 3: the paying brief is refused (\(String(describing: paying.first?.verdict)))")
    let retry = judge.decide(session: third, task: third, calls: [exp131Call("h2", "aside_task", ["brief": "아마존에서 HDMI 케이블을 장바구니에 담고 결제 직전까지만 진행해."])], intent: "b7")
    check(retry.first?.verdict == .refuse(ArisMindJudge.afterHandOff(english: ArisSkillLanguage.english)) && judge.stoppedActing(session: third),
          "exp131 3: the retry is not tried, and the job says it couldn't (\(String(describing: retry.first?.verdict)))")
    for session in [first, second, third] { judge.end(session: session) }
    try? FileManager.default.removeItem(atPath: home)
}

// MARK: - 4: cards take the action's own title and button (cap13 C3-card1.jpg, U3u-card1.jpg)

private func exp131CardTests() {
    // The gate's action countdown reaches the app as an action's card (it was redrawn as "Send message · To …").
    var mcp = ArisMCPCard(title: "글 바꾸기 · TextEdit", detail: "글 바꾸기 TextEdit 「없어질 글」", full: nil, fields: [], countdown: true, spoken: "바꿀게요")
    mcp.action = true
    let shown = ArisMCPCards.shared.put(mcp, timeout: 30) { _ in }
    check(shown.countdown && shown.action && shown.title == "글 바꾸기 · TextEdit", "exp131 4: the countdown card stays an action's, with its own title")
    ArisMCPCards.shared.cancel([shown.id])
    var message = ArisMCPCard(title: "엄마", detail: "곧 갈게", full: nil, fields: [], countdown: true, spoken: "보낼게요")
    message.action = false
    let sent = ArisMCPCards.shared.put(message, timeout: 30) { _ in }
    check(!sent.action, "exp131 4: a message's countdown is still a message's")
    ArisMCPCards.shared.cancel([sent.id])
    check(exp131Source("ArisAgent/Mind/ArisMindRoute+Live.swift").contains("shown.action = card.action"), "exp131 4: wiring: the route keeps the gate's action flag")
    check(ArisCountdownCopy.goWord(title: "글 바꾸기 · TextEdit", english: false) == "바꾸기" && ArisCountdownCopy.goWord(title: "일정 지우기", english: false) == "지우기"
          && ArisCountdownCopy.goWord(title: "일정 지우기", english: true) == "Delete" && ArisCountdownCopy.goWord(title: "엄마", english: false) == ArisCountdownCopy.go,
          "exp131 4: the button is the action's verb, never Send")
    check(exp131Source("Aris/private/Aris/Home/ArisConfirmCard+Countdown.swift").contains("question.action ? ArisCountdownCopy.goWord(title: question.title, english: countdownEnglish) : ArisCountdownCopy.send"),
          "exp131 4: wiring: the card's button")
    // 23:40:58: the calendar delete, through the real gate: titled 일정 지우기, and the usage error refused before any card.
    let home = exp131Home()
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: exp131Tools, passes: ArisMindPasses())
    judge.cardWait = 2
    judge.turn(session: "s", intent: "e1", words: "아까 넣은 모레 11시 13분 치과 일정 지워 줘")
    let bare = judge.decide(session: "s", task: nil, calls: [exp131Call("d1", "aris", ["args": ["event", "delete", "--id", "E4D92EFC-ADFB-4D6D-AB1F-6533E28F9258:BC9F3013"]])], intent: "e1")
    if case .refuse(let why)? = bare.first?.verdict {
        check(why.contains("usage: event delete --id <id> --title <title>"), "exp131 4: words aris-tools would refuse get the usage, not a card (\(why))")
    } else { check(false, "exp131 4: a delete by id alone is refused before any card (\(String(describing: bare.first?.verdict)))") }
    let whole = judge.decide(session: "s", task: nil, calls: [exp131Call("d2", "aris", ["args": ["event", "delete", "--id", "E4D92EFC-ADFB-4D6D-AB1F-6533E28F9258:BC9F3013",
                                                                                                "--title", "치과", "--start", "2026-11-23 11:13"]])], intent: "e1")
    check(whole.first?.verdict == .waits, "exp131 4: the whole delete goes on its one card (\(String(describing: whole.first?.verdict)))")
    var cards: [ArisConfirmation] = []
    _ = judge.ask(session: "s", task: nil, intent: "e1", waiting: whole) { card, answer in
        cards.append(card)
        answer(false)
    }
    check(cards.count == 1 && cards[0].title.hasPrefix("일정 지우기") && !(cards[0].countdown && !cards[0].action),
          "exp131 4: one card, titled 일정 지우기, never the message template (\(cards.map(\.title)))")
    if let card = cards.first, card.countdown { check(ArisCountdownCopy.goWord(title: card.title, english: false) == "지우기", "exp131 4: its button is 지우기") }
    judge.end(session: "s")
    try? FileManager.default.removeItem(atPath: home)
}

// MARK: - 5: the receipt's Undo for Core 2's Trash and rename (cap13 U1-after.jpg, U2-end.jpg)

private func exp131ReceiptTests() {
    // The record's rows as POST /activity lists them read back as the app reads them (one row it can't read loses them all).
    let entries = exp131Record.compactMap { ArisRecordEntry.decode(Data($0.utf8)) }
    let rows = ArisRecord.activityRows(ArisRecordState(entries))
    let data = (try? JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys])) ?? Data()
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let items = try? decoder.decode([ArisActivityItem].self, from: data)
    check(items != nil && items?.count == rows.count, "exp131 5: the record's rows read back in the app")
    check(rows.allSatisfy { ($0["id"] as? String) != "84c97c0c-ab18-445a-9804-7affb66cff44" && ($0["id"] as? String) != "a183727d-9d5d-40a1-a8a1-d9f4ceec3aed" },
          "exp131 5: the Trash and the rename are listed by their activity log lines, once")
    // Those log lines as aris-tools writes them for a Core 2 call (the conversation's job, the brain's name as worker).
    let log = #"[{"action":"removed","asks":false,"date":"2026-11-21T23:23:58Z","id":"B9D0D872-E1E2-43C3-957F-ECC05B3DD5A7","job":"대화","summary":"휴지통으로 옮김: 초안13.txt","undoable":true,"undone":false,"worker":"OpenAI"}]"#
    let logged = (try? decoder.decode([ArisActivityItem].self, from: Data(log.utf8))) ?? []
    let began = ISO8601DateFormatter().date(from: "2026-11-21T23:23:56Z")!
    let acts = ArisReceipt.acts(in: logged, since: began, earlier: [])
    check(acts.count == 1 && acts.first?.undoable == true && ArisReceipt(acts)?.undoable != nil, "exp131 5: a Core 2 Trash's log line is the turn's receipt, with its Undo")
}

// MARK: - 6: teaching words win over the Notes route (turns.jsonl 23:06:06 "지금부터 하는 거 메모 쓰기이라고 해")

private func exp131TeachRouteTests() {
    let said = "지금부터 하는 거 메모 쓰기이라고 해"
    check(ArisTeachIntent.startsLesson(said) && ArisTeachIntent.startsLesson("지금부터 하는 거 줄 추가이라고 해") && ArisTeachIntent.startsLesson("watch me, call it morning setup"),
          "exp131 6: the lesson's start words are read as such")
    check(ArisIntent.guarded(.openApp("메모"), said: said) == .ask(said), "exp131 6: the router's open_app never takes a lesson's words")
    check(!ArisTeachIntent.startsLesson("메모 열어 줘") && !ArisTeachIntent.startsLesson("메모 써 줘: 내일 3시 회의"), "exp131 6: other words aren't a lesson")
    if case .openApp = ArisIntent.guarded(.openApp("메모"), said: "메모 열어 줘") {} else { check(false, "exp131 6: \"메모 열어 줘\" still opens Notes") }
}

// MARK: - 7: Korean requests get Korean lines; a seen result leaves the chip (history.json, cap13 C3-after.jpg)

private func exp131LanguageTests() {
    check(!ArisSkillLanguage.english(for: "줄 추가, 우유", ui: true) && !ArisSkillLanguage.english(for: "줄 하나 더 넣어 줘 ‘우유’로", ui: true)
          && ArisSkillLanguage.english(for: "Open example.com", ui: false) && ArisSkillLanguage.english(for: "42", ui: true) && !ArisSkillLanguage.english(for: "42", ui: false),
          "exp131 7: the request's language, the UI's when it shows none")
    let english = ArisSkillLanguage.english(for: "줄 하나 더 넣어 줘 ‘우유’로", ui: true)
    check(ArisMindStep.declinedLine(english: english) == "허락하지 않으신 일은 하지 않았어요.", "exp131 7: the decline line to a Korean request is Korean")
    let procedure = ArisTeachProcedure(name: "줄 추가", steps: [ArisTeachStep(action: .open, app: "TextEdit", bundle: "com.apple.TextEdit")], parameters: [], created: Date())
    check(ArisTeachCopy.account(procedure, outcome: .done(steps: 2), english: ArisSkillLanguage.english(for: "줄 추가, 우유", ui: true)) == "‘줄 추가’ 다 했어요. (2단계)",
          "exp131 7: a taught run's account to a Korean request is Korean")
    check(exp131Source("ArisAgent/Mind/ArisMindBrain.swift").contains("loop.english = ArisSkillLanguage.english(for: words, ui: english)")
          && exp131Source("ArisAgent/Mind/ArisMindSession.swift").contains("loop.english = ArisSkillLanguage.english(for: words)")
          && exp131Source("ArisAgent/Mind/ArisMindTaught+Live.swift").contains("let english = ArisSkillLanguage.english(for: now.request)"),
          "exp131 7: wiring: the Mind's and the taught run's own lines")
    let job = UUID()
    check(ArisDoneFold.seeing(job, in: []) == [job], "exp131 7: a result put in front of him is seen")
    let tasks = [ArisBackgroundTask(id: job, title: "결제까지 알아서 해", state: .failed("못 끝냈어요"))]
    check(ArisDoneFold.fold(tasks, seen: ArisDoneFold.seeing(job, in: [])).done.isEmpty, "exp131 7: and leaves the chip: no \"6 not done\" all session")
    let team = exp131Source("Aris/private/Aris/ArisController+Team.swift")
    check(team.components(separatedBy: "self.seenDone = ArisDoneFold.seeing(job.id, in: self.seenDone)").count == 3, "exp131 7: wiring: a done and a failed job's notice")
}

// MARK: - 8: after "the field changed, nothing replaced" the turn stops and asks him (record-full.jsonl 23:04:16–23:04:44)

private func exp131FieldChangedTests() {
    let home = exp131Home()
    let gate = ArisTrustGate(home: home, world: { _ in ArisWorldFacts(home: home) })
    let judge = ArisMindJudge(gate: gate, tools: exp131Tools, passes: ArisMindPasses())
    judge.cardWait = 2
    judge.turn(session: "s", intent: "r1", words: "이 문서 내용을 전부 '없어질 글'로 바꿔 줘")
    let replace: [String: Any] = ["app": "TextEdit", "text": "없어질 글", "replace": true]
    let first = judge.decide(session: "s", task: nil, calls: [exp131Call("p1", "app_type", replace)], intent: "r1")
    // 23:04:16: their yes, and the run found the field changed.
    let changed = #"{"did":"what the field holds changed since this step was checked: nothing was replaced","effect":"change-permanent","ok":false,"verified":false}"#
    judge.finish(session: "s", item: first[0], result: ArisMindResult(text: changed, isError: true), disposition: .ran)
    check(judge.stoppedByFieldChange(session: "s"), "exp131 8: the turn knows its replace changed nothing")
    let look = judge.decide(session: "s", task: nil, calls: [exp131Call("p2", "app_read", ["app": "TextEdit"])], intent: "r1")
    check(exp131Runs(look), "exp131 8: a look still runs")
    let again = judge.decide(session: "s", task: nil, calls: [exp131Call("p3", "app_type", replace)], intent: "r1")
    check(again.first?.verdict == .refuse(ArisMindJudge.afterFieldChanged(english: ArisSkillLanguage.english)),
          "exp131 8: the replace is not put on a new card at once (\(String(describing: again.first?.verdict)))")
    check(ArisMindJudge.afterFieldChanged(english: false).contains("칸의 글이 바뀌어서 아무것도 바꾸지 않았어요") && ArisMindJudge.afterFieldChanged(english: true).contains("ask whether to try again"),
          "exp131 8: the model is told to say so and ask him")
    // His next words are a new turn: he may ask for it again.
    judge.turn(session: "s", intent: "r2", words: "응, 다시 바꿔 줘")
    check(!judge.stoppedByFieldChange(session: "s"), "exp131 8: his next turn may try again")
    judge.end(session: "s")
    try? FileManager.default.removeItem(atPath: home)
}
