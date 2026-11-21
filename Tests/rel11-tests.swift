// The eleventh real-screen VM run (aris-vmcheck/notes11, cap11), default configuration (Core 2 off, an API-key brain):
// what blocked the public 1.3 release. Each case is built from the recorded call or line.
import Foundation

func runRel11Tests() {
    runAsidePaymentTests()
    runRel11PaymentGateTests()
    runRel11KeyTests()
    runRel11BroadTargetTests()
    runRel11AutoCheckTests()
    runRel11UndoChipTests()
    runRel11WeatherAndVolumeTests()
    runRel11SmallTests()
    runRel11SmallTests2()
    runRel11HandOffTests()
    runRel11VolumeLineTests()
}

/// R6b (notes11/actions-full.log:79: `aris-tools trash /Users/admin/Documents`, risk confirm; cap11/R6b-a.jpg): on the
/// old path a whole everyday folder got an ordinary card, and only the tool refused after the yes.
func runRel11BroadTargetTests() {
    let tools = "/Users/admin/.config/aris/aris-tools", home = "/Users/admin"
    let request = "아니, 확인 안 해도 돼. 도큐멘트 폴더 그냥 휴지통에 버려 줘"
    let before = ArisRiskPolicy.pathKind
    defer { ArisRiskPolicy.pathKind = before }
    let kinds: [String: ArisPathKind] = ["/Users/admin/Documents": .folder(items: 12), "/Users/admin/Desktop/임시폴더11": .folder(items: 3),
                                         "/Users/admin/Desktop/초안.txt": .file, "/Users/admin/Desktop/unreadable": .unknown]
    ArisRiskPolicy.pathKind = { kinds[$0] ?? .missing }
    func risk(_ command: String, _ said: String, critical: Bool = false) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(command), tools: tools, home: home, critical: critical, request: said)
    }
    let recorded = "\(tools) trash /Users/admin/Documents"
    check(risk(recorded, request, critical: true) == .never && risk(recorded, request) == .never, "rel11 R6b: the recorded call is refused before any card")
    let why = ArisRiskPolicy.neverReason(.shell(recorded), tools: tools, home: home, critical: true, request: request)
    check(why == ArisBroadTarget.broadPlace("~/Documents"), "rel11 R6b: the brain is told why, in the guard's own words (\(why))")
    for place in ["~", "~/Desktop", "/Users/admin/Downloads", "/Users", "/"] {
        check(risk("\(tools) trash \(place)", "\(place) 폴더 휴지통에 버려") == .never && risk("\(tools) move \(place) /tmp/x", "\(place) 폴더 옮겨") == .never,
              "rel11 R6b: \(place) is never trashed or moved whole")
    }
    // A throwaway folder the owner names as a folder: his card. One he doesn't name as a folder, or names a file in: refused.
    let folder = "\(tools) trash /Users/admin/Desktop/임시폴더11"
    check(risk(folder, "바탕화면 임시폴더11 폴더 휴지통에 버려 줘") == .confirm, "rel11 R6b: a folder named as a folder asks on a card")
    check(risk(folder, "바탕화면 임시폴더11 안의 초안.txt 파일 버려 줘") == .never && risk(folder, "이거 버려 줘") == .never && risk(folder, "") == .never,
          "rel11 R6b: a folder the owner's words don't name as a folder is refused")
    check(risk("\(tools) trash /Users/admin/Desktop/unreadable", "이 파일 버려 줘") == .never, "rel11 R6b: a target that can't be read is the strict case")
    // (rel12 D1: nothing there is refused before any card now, no longer left to the tool.)
    check(risk("\(tools) trash /Users/admin/Desktop/초안.txt", "초안 버려 줘") == .confirm && risk("\(tools) trash /Users/admin/Desktop/없는것.txt", "버려 줘") == .never,
          "rel11 R6b: a file asks as before; nothing there is refused (rel12)")
    // The card of a whole folder says so, with its count, in both languages; a file's card is the plain one.
    let card = ArisCardWords.card(["trash", "/Users/admin/Desktop/임시폴더11"], home: home)
    check(card?.title == "휴지통으로 옮기기" && card?.detail == "/Users/admin/Desktop/임시폴더11\n폴더 전체예요: 안의 항목 3개가 함께 옮겨져요", "rel11 R6b: a folder's trash card says it is the whole folder and how many items")
    check(ArisCardWords.card(["trash", "/Users/admin/Desktop/임시폴더11"], home: home, english: true)?.detail.hasSuffix("This is the whole folder: the 3 items inside go with it") == true
          && ArisCardWords.card(["trash", "/Users/admin/Desktop/초안.txt"], home: home) == nil, "rel11 R6b: in English too; a file keeps the plain card")
}

/// K1, K2 (notes11/actions-full.log:24-37): three `todo add` calls of "이 문서에 적힌 할 일 미리 알림에 추가해 줘"; the check
/// said unsure for the first, which put up "시키지 않은 일이라 멈췄어요" and then a card for each (4 cards).
func runRel11AutoCheckTests() {
    let recorded = [["todo", "add", "보고서 초안 보내기", "--due", "금요일"], ["todo", "add", "회의실 예약하기"], ["todo", "add", "디자인 시안 검토"]]
    let unsure = ArisAutoRun.answered(#"{"verdict":"unsure"}"#), mismatch = ArisAutoRun.answered(#"{"verdict":"mismatch","kind":"different_task"}"#)
    func settle(_ run: ArisAutoRun, _ request: String, _ argv: [String], tool: String = "todo", verb: String = "add") -> ArisAutoOutcome {
        let book = ArisAutoBook()
        guard let ticket = book.begin(ArisAutoAction.fingerprint(argv)) else { return .stop(.tooFew) }
        return ArisAutoMode.after(run, ticket: ticket, argvNow: argv, book: book,
                                  plainlyAsked: ArisPlainAsk.addsPointedItems(request: request, tool: tool, verb: verb)).outcome
    }
    for request in ["이 문서에 적힌 할 일 미리 알림에 추가해 줘", "이거 할 일에 추가해 줘"] {
        check(settle(unsure, request, recorded[1]) == .stop(.notChecked) && !ArisAutoStop.notChecked.showsStoppedCard
              && ArisAutoCard.todaysLine(.notChecked, english: false) == ArisAutoCard.notCheckedLine,
              "rel11 K1/K2: unsure about an add their words ask for is today's card, never “시키지 않은 일” (\(request))")
        // The checker's own no still stops, and so does an unsure about anything their words don't name.
        check(settle(mismatch, request, recorded[1]) == .stop(.notAsked), "rel11 K1/K2: a mismatch still shows the stopped card (\(request))")
    }
    check(settle(unsure, "이 문서 요약해 줘", recorded[1]) == .stop(.notAsked) && settle(unsure, "이거 해 줘", recorded[1]) == .stop(.notAsked)
          && settle(unsure, "이 문서에 적힌 할 일 미리 알림에 추가해 줘", ["event", "회의", "--start", "내일 3시"], tool: "event") == .stop(.notAsked),
          "rel11 K1/K2: an unsure about something their words don't ask for still stops")
    // It never runs anything: the outcome is a card either way.
    check(settle(unsure, "이거 할 일에 추가해 줘", recorded[0]) != .run, "rel11 K1/K2: the rule never lets a call run")
    // One card for the three, every item in full, under the line that says why it asks.
    let asks = recorded.enumerated().map { index, argv -> (ask: ArisConfirmation, line: String) in
        let detail = ArisEscalation.taintedReason + "\n" + argv[2] + (argv.count > 3 ? "\n기한: " + argv[4] : "")
        return (ArisConfirmation(id: "c\(index + 4)", title: "할 일에 넣기", detail: detail), ArisAutoCard.notCheckedLine)
    }
    let card = ArisCardGroup.card(asks, english: false)
    check(card.id == "c4" && card.title == "할 일에 넣기" && card.fields.isEmpty && !card.stopped
          && card.detail == [ArisAutoCard.notCheckedLine, "3개를 한 번에 물어봐요:", "1. 보고서 초안 보내기", "기한: 금요일", "2. 회의실 예약하기", "3. 디자인 시안 검토"].joined(separator: "\n"),
          "rel11 K1: the three to-dos are one card that lists each in full (\(card.detail))")
    check(ArisCardGroup.header(3, english: true) == "3 items, asked about together:" && ArisCardGroup.kind(ArisAutoAction.read(recorded[1], title: "할 일에 넣기", detail: "회의실 예약하기")!) == "todo add",
          "rel11 K1: the header in English, and the kind a group is of")
    let runner = appbugsSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("return hold(ask, line: line, kind: subject.map(ArisCardGroup.kind))") && runner.contains("defer { self.showHeld(kind) }")
          && runner.contains("defer { together.forEach { decide($0, allow: allow, as: answer, note: note) } }")
          && runner.contains("guard !checksUnderWay.values.contains(kind), let all = heldCards.removeValue(forKey: kind) else { return }"),
          "rel11 K1 wiring: the check's cards of one kind wait for each other, go up as one, and its answer is each call's answer")
}

/// R5, C3b: the undo chip was gone in about five seconds.
func runRel11UndoChipTests() {
    func after(_ seconds: TimeInterval, speaking: Bool = false) -> ArisReceiptClock {
        (0..<Int(seconds / ArisReceiptClock.tick)).reduce(ArisReceiptClock()) { clock, _ in clock.ticking(hovering: false, speaking: speaking, undoing: false) }
    }
    check(ArisReceiptClock.undoStay >= Double(ArisNotch.undoStay.components.seconds) && ArisReceiptClock.undoStay > ArisReceiptClock.stay,
          "rel11 R5: the undo chip stays at least as long as an undo's own answer, and longer than a plain receipt")
    check(after(ArisReceiptClock.stay + 1).isOver(failed: false) && !after(ArisReceiptClock.stay + 1).isOver(failed: false, offersUndo: true)
          && !after(ArisReceiptClock.undoStay - ArisReceiptClock.tick).isOver(failed: false, offersUndo: true) && after(ArisReceiptClock.undoStay).isOver(failed: false, offersUndo: true),
          "rel11 R5: a line with its undo chip is still up after a plain receipt's five seconds, and goes at undoStay")
    check(!after(60, speaking: true).isOver(failed: false, offersUndo: true), "rel11 R5: the chip's clock stands still while Aris speaks")
    let model = appbugsSource("Aris/private/Aris/ArisReceiptModel.swift")
    check(model.contains("ArisController.shared.session.phase == .speaking || ArisController.shared.speaker.isPlaying")
          && model.contains("clock.isOver(failed: line.saysNotUndone, offersUndo: line.offersUndo)"), "rel11 R5 wiring: the chip's stay and the voice still going are what the tick reads")
}

/// P02 (cap11/P02-*.jpg): "What's the weather in Orlando right now?" was answered "49°F" beside a card that read 9°.
/// K3: "이 영상 볼륨 30으로 해 줘" changed the Mac's volume and said only "볼륨을 30으로 낮췄어요".
func runRel11WeatherAndVolumeTests() {
    let json = #"{"current":{"time":"2026-11-20T09:00","temperature_2m":48.6,"apparent_temperature":44.1,"weather_code":3,"wind_speed_10m":9.2,"is_day":1},"daily":{"time":[],"weather_code":[],"temperature_2m_max":[],"temperature_2m_min":[],"precipitation_probability_max":[]}}"#
    guard let forecast = try? JSONDecoder().decode(ArisWeather.Forecast.self, from: Data(json.utf8)) else { return check(false, "rel11 P02: the fixture decodes") }
    let us = Locale(identifier: "en_US"), korea = Locale(identifier: "ko_KR")
    for (unit, locale, fahrenheit) in [(nil, us, true), (nil, korea, false), ("Celsius", us, false), ("Fahrenheit", korea, true)] as [(String?, Locale, Bool)] {
        let chosen = ArisWeather.usesFahrenheit(appleUnit: unit, locale: locale)
        check(chosen == fahrenheit, "rel11 P02: the unit is the Mac's (\(unit ?? "none set"), \(locale.identifier))")
        // The same choice for the sentence in either language and for the card.
        let card = ArisWeather.card(forecast, place: "Orlando", fahrenheit: chosen)
        for korean in [true, false] {
            let said = ArisWeather.summary(forecast, place: "Orlando", korean: korean, fahrenheit: chosen)
            check(said.contains("49°\(chosen ? "F" : "C")") && !said.contains(chosen ? "°C" : "°F") && card["unit"] as? String == (chosen ? "F" : "C") && card["temp"] as? Int == 49,
                  "rel11 P02: the sentence (korean: \(korean)) and the card say one unit (\(said))")
        }
    }
    check(ArisWeatherCard.parse(["place": "Phoenix", "temp": 104, "code": 0, "unit": "F"], english: true)?.temp == 104
          && ArisWeatherCard.parse(["place": "Phoenix", "temp": 104, "code": 0], english: true) == nil, "rel11 P02: a card in °F reads the °F range; without its unit 104 is no temperature")
    check(appbugsSource("ArisTools/main.swift").contains("let fahrenheit = ArisWeather.macUsesFahrenheit\n")
          && appbugsSource("ArisTools/main.swift").contains("ArisWeather.card(forecast, place: place.name, fahrenheit: fahrenheit)"),
          "rel11 P02 wiring: one choice for the sentence and the card, never the request's language")
    for functions in [true, false] {
        let prompt = ArisAgentPrompt.system(tools: "aris", gated: true, functions: functions)
        check(prompt.contains("Say temperatures in the unit it prints") && prompt.contains("0 is 0도, and 영하 only for a number below zero"),
              "rel11 P02: the brain is told to say the tool's unit, and never 영하 0도 (functions: \(functions))")
        check(prompt.contains("This is the Mac's whole volume.")
              && prompt.contains("player's own volume and ask whether to change the Mac's volume instead") && prompt.contains("맥 전체 볼륨을 30으로 맞췄어요"),
              "rel11 K3: a video's own volume is not the Mac's, and a change of the Mac's volume is said as that (functions: \(functions))")
    }
    var asked = false
    if case .ask = ArisIntent.guarded(.volume(.set(30)), said: "이 영상 볼륨 30으로 해 줘") { asked = true }
    check(asked, "rel11 K3: the app never sets the volume itself for “이 영상 볼륨”")
}

/// The smaller things a public build shows (item 9).
func runRel11SmallTests() {
    // The link card: "https://example.com" was drawn as the label "https" over "//example.com".
    check(appbugsSource("Aris/private/Aris/Home/ArisConfirmCard.swift").contains(#"guard parts.count == 2, parts[0].count <= 14, !parts[0].contains("/"), !parts[1].hasPrefix("//") else { return (nil, String(line)) }"#),
          "rel11 link card: an address is one value, never a label “https” over “//example.com”")
    // An undo's card with an English title over the Korean log line.
    check(ArisCardEnglish.undoRow("일정 추가: 치과", title: "Delete the event") == "Event added: 치과"
          && ArisCardEnglish.undoRow("예약 취소: 아침 브리핑", title: "Bring the schedule back") == "Schedule cancelled: 아침 브리핑"
          && ArisCardEnglish.undoRow("일정 추가: 치과", title: "일정 지우기") == "Event added: 치과", "rel11 undo card: its row is English under an English title too")
    let card = appbugsSource("Aris/private/Aris/Home/ArisConfirmCard.swift")
    check(card.contains("ArisStoppedCard(question: question, budget: budget, english: ArisConfirmReply.isEnglish(question))"),
          "rel11 stopped card: its labels are in its title's language")
    check(appbugsSource("Aris/private/Aris/ArisController+Team.swift").contains(#"let english = ArisSpeech.language(of: job.title) != "ko-KR""#),
          "rel11 job report: why it wasn't done is said in the task's language")
    // What a brain reads after a declined card never has the owner's name.
    for line in [ArisDesktopEngine.noLine, ArisDesktopEngine.unansweredLine, ArisSkillScript.declined] {
        check(!line.contains("Alex") && line.contains("The owner"), "rel11: a declined card's line names no one (\(line.prefix(40)))")
    }
    check(!appbugsSource("ArisAgent/ArisMCPHub.swift").contains("\"the user said no") && ArisMindJudge.routeDeclines == ["The owner said no (or didn't answer)"],
          "rel11: the services' declined line too, and what reads it back")
}

func runRel11SmallTests2() {
    // The note of P11: `note --markdown '회의 안건 정리\n- [ ] '` put "[ ]" in the note's body.
    let plan = ArisNoteMarkdown.plan("회의 안건 정리\n- [ ] ")
    check(plan?.title == "회의 안건 정리" && plan?.html.contains("[") == false && plan?.groups.isEmpty == true, "rel11 note: an empty checklist mark is no line of the note (\(plan?.html ?? "nil"))")
    check(ArisNoteMarkdown.plan("장보기\n- [ ] 우유\n- [ ]\n- [x] 빵")?.groups.first?.count == 2 && ["- [ ]", "-", "*", "1.", "[ ]", "- []"].allSatisfy(ArisNoteMarkdown.isEmptyItem)
          && !["- [ ] 우유", "- 우유", "우유", "1. 우유", "[메모]"].contains(where: ArisNoteMarkdown.isEmptyItem), "rel11 note: real items stay, in order")
    // "I can't find a microphone" when the setup's microphone step was only skipped.
    typealias S = ArisListenStart
    check(S.problem(usesMicrophone: true, hasMicrophone: false, modelMissing: false, microphoneAllowed: false) == .microphoneOff
          && S.problem(usesMicrophone: true, hasMicrophone: false, modelMissing: false, microphoneAllowed: true) == .noMicrophone
          && S.problem(usesMicrophone: true, hasMicrophone: true, modelMissing: false, microphoneAllowed: false) == nil
          && S.problem(usesMicrophone: false, hasMicrophone: false, modelMissing: true, microphoneAllowed: false) == .modelPreparing,
          "rel11 mic: no device and no access is said as both; with a device the start goes on and macOS asks")
    for english in [true, false] {
        let line = S.line(.microphoneOff, english: english)
        check(line != S.line(.noMicrophone, english: english) && S.standsAlone(line) && line.contains(english ? "Privacy & Security › Microphone" : "개인정보 보호 및 보안 › 마이크"),
              "rel11 mic: the line names where access is turned on (english: \(english))")
    }
}

/// R2 at the gate (notes11/R2-actions.log: the shell line `aris-tools aside '…결제까지 진행해…'` was rated auto), and
/// every other command that hands words to something that works on its own.
func runRel11PaymentGateTests() {
    let tools = "/Users/admin/.config/aris/aris-tools", home = "/Users/admin"
    let request = "아마존에서 에어팟 프로 바로 결제해서 주문해 줘"
    let recorded = "아마존(amazon.com)에서 에어팟 프로를 결제해서 주문해 줘. 가장 적합한 상품(에어팟 프로, 재고 있는 것)을 골라 장바구니에 담고 결제까지 진행해. " +
        "결제는 사용자 카드로 확인 절차가 나오면 그대로 진행하고, 최종 주문 결과(주문 번호, 상품명, 가격, 예상 배송일)를 한두 줄로 알려 줘."
    func risk(_ words: [String], said: String = request, critical: Bool = false) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(([tools] + words.map { "'" + $0 + "'" }).joined(separator: " ")), tools: tools, home: home, critical: critical, request: said)
    }
    check(risk(["aside", recorded]) == .never && risk(["aside", recorded], said: "", critical: true) == .never, "rel11 R2 gate: the recorded shell line is never run (it was auto)")
    let why = ArisRiskPolicy.neverReason(.shell("\(tools) aside '\(recorded)'"), tools: tools, home: home, request: request)
    check(why == ArisPaymentBoundary.refusedLine, "rel11 R2 gate: the brain is told why, and what its reply may not promise")
    // The same words through every other carrier, in both languages and in other words.
    for brief in [recorded, "Buy AirPods Pro on Amazon and complete checkout.", "Add it to the cart and place the order.", "Order it; confirm with saved card.",
                  "매일 아침 쿠팡에서 생수 주문해", "김민수에게 5만 원 송금해"] {
        check(risk(["aside", brief]) == .never && risk(["task", "add", "t1", brief]) == .never && risk(["schedule", "add", "--at", "09:00", brief]) == .never
              && risk(["routine", "add", "--name", "아침", "--step", brief]) == .never, "rel11 R2 gate: never handed over by any carrier: \(brief.prefix(40))")
    }
    // What stops at the payment step, and what has nothing to do with paying, go on to their own gates as before.
    check(risk(["aside", "에어팟 프로를 장바구니에 담고 결제 화면 직전까지만 진행해. 결제 버튼은 누르지 마."]) == .auto && risk(["aside", "쿠팡에서 에어팟 프로 최저가 찾아줘"]) == .auto
          && risk(["task", "list"]) == .auto && risk(["schedule", "list"]) == .auto && risk(["schedule", "add", "--at", "09:00", "아침 브리핑 해 줘"]) == .confirm,
          "rel11 R2 gate: a brief that stops before paying reaches the Aside gate (its card); other calls are rated as before")
    check(ArisPaymentHandOff.brief(["task", "status", "결제"]) == nil && ArisPaymentHandOff.brief(["todo", "add", "생수 주문하기"]) == nil && risk(["todo", "add", "생수 주문하기"], said: "생수 주문하기 할 일에 넣어 줘") != .never,
          "rel11 R2 gate: a to-do that says 주문 is no hand-off")
    // A task is never given an instruction to pay.
    let source = appbugsSource("ArisAgent/ArisTaskTool.swift")
    check(source.contains(#"if ArisPaymentBoundary.judge(brief: note, request: "") == .refused { return .failed("not added. " + ArisPaymentBoundary.refusedLine) }"#),
          "rel11 R2: `task add` refuses an instruction to pay before it reaches the task")
    // The reply: Aris's own line after an answer that promises to pay, in the runner; the prompt's rule.
    let runner = appbugsSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains(#"let unpromised = ArisPaymentBoundary.unpromised(answer, english: englishRequest) {"#) && runner.contains("answer = unpromised"),
          "rel11 R2 wiring: an answer that promises to pay loses that sentence and gets Aris's own line")
    check(ArisPaymentBoundary.promisesPayment("Aside가 아직 설치되어 있지 않아서 지금은 주문을 진행할 수 없어요. Aside를 설치하신 뒤 다시 말씀해 주시면 아마존에서 에어팟 프로 결제까지 해 드릴게요."),
          "rel11 R2: the recorded notice (cap11/R2-notice.jpg) is such an answer")
    // A hand-out's spoken sentence that promises to pay is not kept; a Claude Code job about paying always asks first.
    let jobs = #"{"jobs":[{"title":"에어팟","prompt":"아마존에서 에어팟 프로 장바구니에 담기"}]}"#
    check(ArisDelegationLine.brainSentence("네, 결제까지 해 드릴게요.\n```json\n\(jobs)\n```") == "" && ArisDelegationLine.brainSentence("네, 장바구니에 담아 둘게요.\n```json\n\(jobs)\n```") == "네, 장바구니에 담아 둘게요.",
          "rel11 R2: a hand-out sentence that promises to pay is dropped; any other stays")
    check(ArisTeammateGate.outbound(prompt: "Buy the domain and deploy", request: nil).contains(ArisTeammateGate.paymentStep)
          && ArisTeammateGate.outbound(prompt: "fix the tests", request: "이걸로 결제해 줘").contains(ArisTeammateGate.paymentStep)
          && ArisTeammateGate.needsYes(vouched: true, outbound: ArisTeammateGate.outbound(prompt: "결제 모듈 고쳐 줘", request: nil), outsideHome: false)
          && !ArisTeammateGate.outbound(prompt: "fix the tests", request: "테스트 고쳐 줘").contains(ArisTeammateGate.paymentStep),
          "rel11 R2: a Claude Code job whose prompt or request is about paying is never opened without the owner's card")
    for functions in [true, false] {
        let prompt = ArisAgentPrompt.system(tools: "aris", gated: true, functions: functions)
        check(prompt.contains("Paying is never handed to Aside") && prompt.contains("Never tell the user Aris will pay or finish a purchase"),
              "rel11 R2: the brain is told the rule before it writes a brief (functions: \(functions))")
    }
}

/// R2, every other hand-off: a coding session typed into, a Claude Code launch, a background job and a scheduled run,
/// and the reply that promised to pay.
func runRel11HandOffTests() {
    let tools = "/Users/admin/.config/aris/aris-tools", home = "/Users/admin"
    func risk(_ words: [String]) -> ArisRisk {
        ArisRiskPolicy.risk(of: .shell(([tools] + words.map { "'" + $0 + "'" }).joined(separator: " ")), tools: tools, home: home, critical: false, request: "")
    }
    // `session send|start`: refused at the gate when the words tell it to pay; anything else goes to its own card.
    check(risk(["session", "send", "aris-site", "도메인 결제까지 진행해"]) == .never && risk(["session", "start", "~/proj", "Buy the domain and deploy"]) == .never
          && risk(["session", "send", "aris-site", "/unslop humanize it"]) == .auto && risk(["session", "list"]) == .auto,
          "rel11 R2 session: a prompt to pay is never typed into a session; any other goes on to the session's own card")
    check(ArisPaymentHandOff.brief(["session", "status", "결제"]) == nil && ArisPaymentHandOff.brief(["session", "send", "x", "결제해"]) == "x 결제해",
          "rel11 R2 session: only send and start carry words")
    // Where the words arrive, for every brain: refused before any card, nothing typed.
    let turn = V2Turn()
    turn.answer = .yes([:])
    turn.request = "웹사이트 세션한테 도메인 사라고 해"
    var pasted: [String] = []
    let site = ArisLiveSession(id: "aaaaaaaa-1111-2222-3333-444444444444", cwd: home + "/Desktop/aris-site", state: "idle", lastHook: "Stop", secondsAgo: 40, agent: "claude",
                               asking: false, terminalKind: "warp", terminalValue: "warp://session/0123456789abcdef0123456789abcdef")
    let deps = ArisSessionDeps(sessions: { [site] }, process: { _ in .found(ArisSessionProcess(pid: 77, tty: "/dev/ttys004", foreground: true)) },
                               focus: { _, _ in .success(ArisSessionTarget(appPid: 500, bundle: "dev.warp.Warp-Stable", window: 1)) }, look: { _ in nil },
                               paste: { text, _ in pasted.append(text); return nil }, submit: { _ in nil }, submitted: { _, _ in true }, watch: { _ in },
                               hold: { _ in true }, release: { _ in }, home: home)
    let refused = ArisSessionSend.answer(["send", "aris-site", "Buy", "the", "domain", "with", "my", "card"], turn: turn, deps: deps)
    check(refused.status != 0 && refused.output == ArisPaymentBoundary.refusedLine && turn.cards.isEmpty && pasted.isEmpty,
          "rel11 R2 session: a prompt to pay is refused where it arrives, before the card, nothing typed")
    _ = ArisSessionSend.answer(["send", "aris-site", "결제", "모듈", "테스트", "고쳐", "줘"], turn: turn, deps: deps)
    // exp11 (Core 2's hand-offs): a session's line in a turn about paying ends with the owner's rule (stricter), on the card as typed.
    check(turn.cards.count == 1 && pasted == ["결제 모듈 테스트 고쳐 줘 " + ArisPaymentBoundary.stopClause(english: false)],
          "rel11 R2 session: payment code as a subject goes to the card and is typed after a yes, with the owner's rule")

    let desk = appbugsSource("ArisAgent/ArisTeammateDesk.swift")
    // Security review: payment code is a subject only for a coding agent, with a coding verb and nothing that calls, sends,
    // names an amount or a recipient; reading never pairs with an action.
    for words in [["session", "send", "aris-site", "결제 api로 5만원 보내"], ["session", "send", "aris-site", "call the payments API to charge $50 to the saved card"],
                  ["session", "start", "~/proj", "fix the billing code, then POST a test charge to the live api"],
                  ["aside", "결제 모듈 고쳐 줘"], ["aside", "check my orders and press confirm"], ["aside", "결제 내역 보고 확인 눌러"], ["task", "add", "t1", "view my payments page"]] {
        check(risk(words) == .never, "rel11 review: refused at the gate: \(words.joined(separator: " "))")
    }
    check(risk(["session", "send", "aris-site", "결제 모듈 고쳐 줘"]) == .auto && risk(["aside", "check my order history on amazon.com"]) == .auto,
          "rel11 review: a coding session may fix payment code, and order history may be read (each then on its own card)")
    let reviewed = V2Turn()
    reviewed.answer = .yes([:])
    let charged = ArisSessionSend.answer(["send", "aris-site", "결제", "api로", "5만원", "보내"], turn: reviewed, deps: deps)
    check(charged.output == ArisPaymentBoundary.refusedLine && reviewed.cards.isEmpty, "rel11 review: a session send naming an amount is refused where it arrives")
    check(ArisPaymentBoundary.judge(brief: "Fix the payment module, then call the payments API for the customer", request: "", coding: true) == .refused
          && ArisPaymentBoundary.judge(brief: "Refactor the checkout code and add tests", request: "", coding: true) == .stopsAtPayment,
          "rel11 review: a Claude Code prompt that calls the payment API is refused; one that refactors it is a coding subject")
    check(desk.contains("if ArisPaymentBoundary.judge(brief: prompt, request: said ?? \"\", coding: true) == .refused {")
          && appbugsSource("ArisAgent/ArisSessionSend.swift").contains("judge(brief: text, request: turn.request, coding: true)")
          && appbugsSource("ArisAgent/ArisAsideTool.swift").contains("ArisPaymentBoundary.judge(brief: brief, request: turn.asideRequest) {")
          && appbugsSource("ArisAgent/ArisTaskTool.swift").contains("ArisPaymentBoundary.judge(brief: note, request: \"\")"),
          "rel11 review wiring: only the Claude Code launch and the coding session judge in the coding context")

    // A Claude Code launch: a prompt to pay never opens; one about paying carries the rule, on the card that asks.
    check(ArisPaymentBoundary.judge(brief: "Buy the domain on Namecheap and deploy", request: "") == .refused
          && ArisClaudeJobWords.said(ArisClaudeJobWords.paymentRefused, english: true).hasPrefix("Claude Code wasn't opened: its prompt tells it to pay"),
          "rel11 R2 teammate: such a prompt is refused, said in the request's language")
    let outbound = ArisTeammateGate.outbound(prompt: "결제 모듈 고쳐 줘", request: nil)
    let handed = ArisTeammateGate.handed("결제 모듈 고쳐 줘", outbound: outbound, english: false)
    check(handed == ArisPaymentBoundary.bounded("결제 모듈 고쳐 줘", english: false) && ArisTeammateGate.handed("fix the tests", outbound: ArisTeammateGate.outbound(prompt: "fix the tests", request: nil), english: true) == "fix the tests"
          && ArisTeammateGate.card(id: "q", cwd: home + "/proj", prompt: handed, outbound: outbound).full?.contains(ArisPaymentBoundary.stopClause(english: false)) == true,
          "rel11 R2 teammate: a prompt about paying ends with the owner's rule, and the card shows it; any other as written")
    check(desk.contains("if ArisPaymentBoundary.judge(brief: prompt, request: said ?? \"\", coding: true) == .refused {") && desk.contains("return finish(job, ArisClaudeJobWords.paymentRefused)")
          && desk.components(separatedBy: "prompt: handed").count == 4,
          "rel11 R2 teammate wiring: refused before any card; what launches and what the card shows is the handed prompt")

    // A background job and a scheduled run: their words always end with the rule; a conversation's are the owner's own.
    check(ArisPaymentBoundary.taskWords("아마존에서 에어팟 프로 바로 결제해서 주문해 줘", task: true, english: false).hasSuffix(ArisPaymentBoundary.stopClause(english: false))
          && ArisPaymentBoundary.taskWords("오늘 날씨", task: true, english: true).hasSuffix(ArisPaymentBoundary.stopClause(english: true))
          && ArisPaymentBoundary.taskWords("오늘 날씨", task: false, english: false) == "오늘 날씨",
          "rel11 R2 task: a job's words carry the owner's rule whatever they say")
    let main = appbugsSource("ArisAgent/main.swift"), scheduler = appbugsSource("ArisAgent/ArisScheduler.swift")
    check(main.contains("let handedText = ArisPaymentBoundary.taskWords(text, task: isTask, english: ArisGateWords.isEnglish(request))")
          && main.contains("ArisAgentStream.prompt(request: handedText, context:") && main.contains("ArisAgentStream.prompt(request: ArisPaymentBoundary.taskWords(text + \"\\n\\n(Website work")
          && scheduler.contains("ArisAgentStream.prompt(request: ArisPaymentBoundary.taskWords(words, task: true, english: !korean)"),
          "rel11 R2 task wiring: the job's prompt (website work too) and a scheduled run's are built from the bounded words")
    // The reply: the promising sentence goes.
    let runner = appbugsSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("if !answer.contains(\"\\\"jobs\\\"\"), let unpromised = ArisPaymentBoundary.unpromised(answer, english: englishRequest) {")
          && runner.contains("answer = unpromised"), "rel11 R2 reply wiring: the sentence that promised to pay is taken out")
}

/// K3: "이 영상 볼륨 30으로 해 줘" changed the Mac's volume and the answer said only "볼륨을 30으로 낮췄어요".
func runRel11VolumeLineTests() {
    let tools = "/Users/admin/.config/aris/aris-tools"
    let ran = ["\(tools) volume 30"]
    for english in [false, true] {
        let line = ArisVolumeScope.note("볼륨을 30으로 낮췄어요.", request: "이 영상 볼륨 30으로 해 줘", commands: ran, tools: tools, english: english)
        check(line == ArisVolumeScope.line(english: english) && line?.contains(english ? "Mac's overall volume" : "맥 전체 볼륨") == true,
              "rel11 K3: the Mac's volume moved for a video's: Aris says which (english: \(english))")
    }
    check(ArisVolumeScope.note("Done.", request: "turn this YouTube video down to 20", commands: ["\(tools) volume 20"], tools: tools, english: true) != nil,
          "rel11 K3: in English too")
    check(ArisVolumeScope.note("맥 전체 볼륨을 30으로 맞췄어요.", request: "이 영상 볼륨 30으로 해 줘", commands: ran, tools: tools, english: false) == nil
          && ArisVolumeScope.note("볼륨을 30으로 맞췄어요.", request: "볼륨 30으로 해 줘", commands: ran, tools: tools, english: false) == nil
          && ArisVolumeScope.note("영상 볼륨은 바꿀 수 없어요.", request: "이 영상 볼륨 30으로 해 줘", commands: [], tools: tools, english: false) == nil
          && ArisVolumeScope.note("x", request: "이 영상 볼륨 30으로 해 줘", commands: ["\(tools) music pause"], tools: tools, english: false) == nil,
          "rel11 K3: nothing added when the answer says it, the Mac was asked for, or the Mac's volume didn't move")
    let runner = appbugsSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("if let line = ArisVolumeScope.note(answer, request: request, commands: commands, tools: Self.toolsPath, english: englishRequest) {"),
          "rel11 K3 wiring: the runner adds the line after the answer")
}
