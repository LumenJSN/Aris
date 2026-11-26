import Foundation

// Fourteenth VM run: after "오늘 서울 날씨 어때?" the next action's card opened with "외부 내용을 읽은 뒤라 한 번 더
// 확인할게요" ("Asking once more because outside content was read"), which read as alarming for a weather lookup.
// The card stays (the weather service's answer is outside text, Core 2's trust gate); only its line is said plainly:
// what was fetched, and that it asks first because of it.

private let card132Tools = "/Users/me/.config/aris/aris-tools"
private let card132Korean = "이 대화에서 가져온 정보(날씨·웹 등)가 있어서 먼저 물어봐요."
private let card132English = "Asking first, since this chat has info I fetched (weather, web, etc.)."

private func card132Driver() -> ArisAPIDriver {
    let preset = ArisAPIPreset.named("openai")!
    let profile = ArisAPIProfile(id: "openai", quick: preset.quick.isEmpty ? "local-model" : preset.quick,
                                 strong: preset.strong.isEmpty ? "local-model" : preset.strong, baseURL: "http://127.0.0.1:1/v1", vision: nil, tools: nil)
    return ArisAPIDriver(profile: profile, tools: card132Tools, home: "/Users/me", executable: URL(fileURLWithPath: "/usr/bin/true"))
}

private func card132Call(_ id: String, _ argv: [String]) -> String {
    let line: [String: Any] = ["type": "tool_request", "id": id, "name": "aris", "arguments": ArisAPIDialects.jsonText(["args": argv]), "round": 1]
    return String(decoding: try! JSONSerialization.data(withJSONObject: line), as: UTF8.self)
}

private func card132Confirm(_ events: [ArisBrainEvent]) -> ArisConfirmation? {
    for case .confirm(let card) in events { return card }
    return nil
}

private func card132Sent(_ events: [ArisBrainEvent]) -> Bool {
    events.contains { if case .send = $0 { return true }; return false }
}

func runCard132Tests() {
    // The line itself: plain words naming what was fetched, Korean and English, the same in the agent and the app.
    check(ArisEscalation.taintedReason == card132Korean && ArisGateWords.line(card132Korean) == card132English
          && ArisCardEnglish.outsideReason == card132Korean,
          "card132: the outside-content line says what was fetched (weather, web) and that it asks first, in Korean and English")
    check(!card132Korean.contains("외부 내용") && !card132Korean.contains("한 번 더") && !card132English.contains("once more")
          && !card132Korean.contains(":") && !card132English.contains(":"),
          "card132: no 'outside content' or 'once more' wording, and no colon a card would read as a labelled row")

    // VM 14, P01 then P11 on the API brain: the weather service's answer still makes the conversation outside text.
    let driver = card132Driver()
    _ = driver.ask("오늘 서울 날씨 어때?", tier: .quick)
    let weather = driver.read(card132Call("w1", ["weather", "서울", "--ko"]))
    check(card132Confirm(weather) == nil, "card132: the weather lookup itself runs without a card, as before")
    _ = driver.read(#"{"type":"tool_done","id":"w1","exit":0,"bytes":120}"#)
    check(driver.taint == .outsideText, "card132: the weather's answer is still outside text (gate unchanged)")

    _ = driver.ask("메모에 '회의 안건 정리' 써 줘", tier: .quick)
    let noteEvents = driver.read(card132Call("n1", ["note", "회의 안건 정리"]))
    guard let asked = card132Confirm(noteEvents) else { return check(false, "card132: the note after the weather is still carded") }
    check(!card132Sent(noteEvents), "card132: the note after the weather is still carded and nothing runs before the answer")

    // What every brain's card passes through (ArisAgentRunner): the escalation gate, unchanged, then its line.
    let command = ArisAPICatalog.command(tools: card132Tools, argv: ["note", "회의 안건 정리"])
    let action = ArisAction.shell(command)
    let approvable = ArisEscalation.autoApprovable(action, tools: card132Tools)
    let scope = ArisRiskPolicy.scope(of: action, tools: card132Tools)
    let tainted = driver.taint.blocks(covered: false)
    let card = ArisEscalation.card(for: asked, approvable: approvable, hardLine: nil, tainted: tainted)
    check(approvable && tainted && card.detail.hasPrefix(card132Korean + "\n") && card.detail.hasSuffix(asked.detail) && !card.countdown,
          "card132: the note's card after the weather opens with the plain line, then exactly what would be written")
    if case .askUser = ArisEscalation.decide(scope: scope, approvable: approvable, hardLine: nil, tainted: tainted, standing: [scope], judgement: .proceed) {
        check(ArisEscalation.learnable(scope, approvable: approvable, hardLine: nil, tainted: tainted) == nil,
              "card132: after the weather neither a standing grant nor the judge's yes lets it through, and a yes is never learned (gate unchanged)")
    } else { check(false, "card132: after the weather neither a standing grant nor the judge's yes lets it through, and a yes is never learned (gate unchanged)") }

    // The same note on a clean conversation: no line (nothing fetched, nothing to explain).
    check(ArisEscalation.card(for: asked, approvable: approvable, hardLine: nil, tainted: false) == asked,
          "card132: without anything fetched the card has no such line")

    // In English: the agent's words, and the app's, for a note's card (its own lines are the user's words; the gate's line
    // that opens it is not: VM 14 P11 showed it in Korean in an English UI).
    check(ArisGateWords.detail(card.detail).hasPrefix(card132English + "\n"), "card132: the agent says the line in English for an English request")
    let english = ArisCardEnglish.detail(card.detail, title: "메모 만들기").components(separatedBy: "\n")
    check(english.first == card132English && english.dropFirst().joined(separator: "\n") == ArisCardEnglish.detail(asked.detail, title: "메모 만들기"),
          "card132: an English window shows the line in English on a note's card too, and the note's own lines as before")
    check(ArisCardEnglish.detail("회의 안건 정리\n" + card132Korean, title: "메모 만들기") == "회의 안건 정리\n" + card132Korean,
          "card132 (hostile): the same words further down a note are its own text and stay")

    // The automatic check's stopped card still leaves the line out (it is no part of the action).
    check(ArisAutoCard.plain(card.detail) == asked.detail && ArisAutoCard.plain(ArisGateWords.detail(card.detail)) == ArisGateWords.detail(asked.detail),
          "card132: the stopped card drops the line in either language")

    // The event after the weather (VM 14 P10) asks the same way.
    _ = driver.ask("내일 오후 3시에 치과 예약 일정 추가해 줘", tier: .quick)
    let eventEvents = driver.read(card132Call("e1", ["event", "치과 예약", "--start", "2026-11-23 15:00", "--minutes", "60"]))
    if let eventAsk = card132Confirm(eventEvents) {
        let eventAction = ArisAction.shell(ArisAPICatalog.command(tools: card132Tools, argv: ["event", "치과 예약", "--start", "2026-11-23 15:00", "--minutes", "60"]))
        let eventCard = ArisEscalation.card(for: eventAsk, approvable: ArisEscalation.autoApprovable(eventAction, tools: card132Tools), hardLine: nil,
                                            tainted: driver.taint.blocks(covered: false))
        check(!card132Sent(eventEvents) && eventCard.detail.hasPrefix(card132Korean + "\n"), "card132: the event after the weather is carded with the same plain line")
    } else { check(false, "card132: the event after the weather is carded with the same plain line") }
}
