// Tests for QA batch 3 (desktop control, Codex, Peekaboo engine): a type never claims what it can't read back
// (BUG-10), a no binds only its own turn (BUG-11), Korean particles picked by the last syllable (BUG-12), localized app
// names for the local arrange (BUG-13), an even split said in the past tense (BUG-14), and the user's own words typed into a
// safe app on a clean turn without a card (BUG-15).
import CoreGraphics
import Foundation

func runQABatch3Tests() {
    qaUnverifiedTypeTests()
    qaDeclineBindsTurnTests()
    qaParticleTests()
    qaLocalizedAppNameTests()
    qaEvenSplitTests()
    qaSafeTypingTests()
}

private let qa3Fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/peekaboo")
private let qa3Identity = ArisDesktopIdentity(userName: "testuser", fullName: "Alex Tester", home: "/Users/testuser")
private let qa3Bench = ArisDesktopTarget(name: "Aris Testbench", bundle: "dev.example.aris-bench.testbench", pid: 4242, known: true, never: false,
                                         browser: false, sending: false)

/// see-chat with its Message field (elem_59) focused and holding `value`.
private func qa3Chat(_ value: String) -> ArisDesktopObservation? {
    guard let data = try? Data(contentsOf: qa3Fixtures.appendingPathComponent("see-chat.json")),
          var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    var inner = object["data"] as? [String: Any] ?? [:]
    inner["focused_element"] = ["frame": [[461, 1015], [586, 24]], "processIdentifier": 4242, "role": "AXTextField", "windowID": 9189]
    var list = inner["ui_elements"] as? [[String: Any]] ?? []
    for index in list.indices where list[index]["id"] as? String == "elem_59" { list[index]["value"] = value }
    inner["ui_elements"] = list
    object["data"] = inner
    guard let edited = try? JSONSerialization.data(withJSONObject: object), let envelope = ArisDesktopEnvelope.parse(edited) else { return nil }
    return ArisDesktopObservation.make(envelope, target: qa3Bench, window: 9189, identity: qa3Identity)
}

// MARK: - BUG-10: a type Aris can't read back is a failure, worded so it can't pass for success

private func qaUnverifiedTypeTests() {
    // aris-tools type (TextEdit, Notes…: no card): the focused field read back before and after.
    let text = "QA 테스트 문장입니다"
    check(ArisTypeReadback.landed(text, before: "", after: text) && ArisTypeReadback.landed(text, before: "앞 ", after: "앞 " + text),
          "BUG-10: aris-tools type: the text read back in the focused field is typed")
    check(!ArisTypeReadback.landed(text, before: "", after: "") && !ArisTypeReadback.landed(text, before: nil, after: nil)
          && !ArisTypeReadback.landed(text, before: text, after: text) && !ArisTypeReadback.landed("", before: "", after: ""),
          "BUG-10: aris-tools type: an empty field, an unreadable one, or one that held the text already is no proof")
    check(ArisTypeReadback.landed(text.decomposedStringWithCanonicalMapping, before: "", after: text),
          "BUG-10: aris-tools type: compared composed on both sides")
    let failed = ArisTypeReadback.result(text, app: "텍스트 편집기", before: "", after: "")
    check(!failed.ok && failed.line.hasPrefix(ArisTypeReadback.notTypedLead) && failed.line.contains("텍스트 편집기")
          && !failed.line.lowercased().contains("typed \(text.count) characters"),
          "BUG-10: aris-tools type: an unverified type is a failure line, never 'typed N characters': \(failed.line)")
    let unreadable = ArisTypeReadback.result(text, app: "Pages", before: nil, after: nil)
    // The follow-up: keys sent into a field that can't be read back are "not confirmed", never "not typed".
    check(!unreadable.ok && unreadable.line.hasPrefix(ArisTypeReadback.notConfirmedLead), "BUG-10: aris-tools type: a field that can't be read back is not confirmed")
    let done = ArisTypeReadback.result(text, app: "텍스트 편집기", before: "", after: text)
    check(done.ok && done.line.contains("confirmed"), "BUG-10: aris-tools type: a confirmed type says so")
    check(ArisTypeReadback.noFieldLine(app: "TextEdit").hasPrefix(ArisTypeReadback.notTypedLead),
          "BUG-10: aris-tools type: no focused field means nothing typed, said as a failure")

    // The desktop engine's read-back: a field that already held the text proves nothing.
    guard let held = qa3Chat("hello"), let field = held.elements.first(where: { $0.id == "elem_59" }) else {
        return check(false, "BUG-10: the see-chat fixture loads")
    }
    check(ArisDesktopVerify.typed("hello", field: field, after: held, before: field.rawValue) == .notSeen("“\(ArisDesktopVerify.short(field.label))” reads “hello”"),
          "BUG-10: desktop: text the field held before isn't read back as typed")
    if let typedLook = qa3Chat("hello hello") {
        if case .done = ArisDesktopVerify.typed("hello", field: field, after: typedLook, before: field.rawValue) {} else {
            check(false, "BUG-10: desktop: one more copy of it is typed")
        }
    }
    // The ladder's failure: its first words say it wasn't confirmed, so the brain can't call it done.
    let ladder = ArisDesktopSession.typeOutcome(ArisDesktopResult(ok: false, text: "Typing into “Message” isn't confirmed (…)."))
    check(!ladder.ok && ladder.text.hasPrefix(ArisDesktopSession.notTypedLead), "BUG-10: desktop: an unconfirmed type leads with the not-typed line")
    let fine = ArisDesktopSession.typeOutcome(ArisDesktopResult(ok: true, text: "Done (typed in the background): …"))
    check(fine.ok && !fine.text.contains(ArisDesktopSession.notTypedLead), "BUG-10: desktop: a confirmed type is left as it is")
}

// MARK: - BUG-11: a no binds only the turn it was said in

private func qaDeclineBindsTurnTests() {
    check(ArisAgentPrompt.declineRule.contains("only the turn") && !ArisAgentPrompt.declineRule.contains("rest of the conversation"),
          "BUG-11: the decline rule binds a no to its own turn")
    let gated = ArisAgentPrompt.system(tools: "/t", gated: true)
    check(gated.contains(ArisAgentPrompt.declineRule) && !gated.contains("for the rest of the conversation") && gated.contains("don't try another way"),
          "BUG-11: the gated prompt carries it, and working around a no in the same turn stays forbidden")
    let tools = "/Users/me/.config/aris/aris-tools"
    let codex = ArisCodexDriver(model: "m", tools: tools, instructions: "", home: "/Users/me")
    _ = codex.ask("바탕화면 a.txt 휴지통에 버려 줘")
    let command = #"{"id":%d,"method":"item/commandExecution/requestApproval","params":{"command":"/bin/zsh -lc '\#(tools) trash /Users/me/Desktop/a.txt'"}}"#
    guard case .confirm(let first)? = codex.read(String(format: command, 501)).first else { return check(false, "BUG-11: the trash asks first") }
    _ = codex.decide(first.id, allow: false)
    if case .confirm? = codex.read(String(format: command, 502)).first { check(false, "BUG-11: in the same turn, after a no, it isn't asked again") }
    _ = codex.ask("바탕화면 a.txt 휴지통에 버려 줘")
    if case .confirm? = codex.read(String(format: command, 503)).first {} else { check(false, "BUG-11: a new turn asking again gets a new card") }
}

// MARK: - BUG-12: 은/는, 이/가, 을/를, 와/과, (으)로 from the last syllable

private func qaParticleTests() {
    check(ArisJosa.attach("텍스트 편집기", "은", "는") == "텍스트 편집기는" && ArisJosa.attach("캘린더", "이", "가") == "캘린더가"
          && ArisJosa.attach("엄마 생일", "을", "를") == "엄마 생일을" && ArisJosa.attach("메모", "과", "와") == "메모와",
          "BUG-12: the particle follows the last syllable's batchim")
    check(ArisJosa.ro("서울") == "로" && ArisJosa.ro("부산") == "으로" && ArisJosa.ro("학교") == "로", "BUG-12: (으)로: ㄹ takes 로")
    check(ArisJosa.attach("“텍스트 편집기”", "은", "는") == "“텍스트 편집기”는" && ArisJosa.particle("TextEdit", "은", "는") == "은"
          && ArisJosa.particle("Safari", "은", "는") == "는" && ArisJosa.particle("Notes 3", "은", "는") == "은",
          "BUG-12: closing marks are skipped; a Latin or digit ending is read as said")
    let request = (try? ArisDesktopWords.parse(["click", "@s8f3k2:e2"]).get())
    let editor = ArisDesktopTarget(name: "텍스트 편집기", bundle: "com.apple.TextEdit", pid: 77, known: true, never: false, browser: false, sending: false)
    if let request {
        let card = ArisDesktopCard.card(request, target: editor, element: nil, remember: true, wiped: false)
        check(card.detail.contains("텍스트 편집기는 다시 묻지 않아요") && !card.detail.contains("(는)"), "BUG-12: the desktop card: \(card.detail)")
    } else {
        check(false, "BUG-12: a click request parses")
    }
    // No placeholder particle left anywhere in Aris's copy.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let pattern = #"은\(는\)|는\(은\)|이\(가\)|가\(이\)|을\(를\)|를\(을\)|와\(과\)|과\(와\)|\(으\)로|\(이\)에요"#
    var leaks: [String] = []
    if let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
        for case let file as URL in walk where file.pathExtension == "swift" && !file.path.contains("/build") && !file.path.contains("/Tests/") {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (number, line) in source.components(separatedBy: "\n").enumerated() where line.range(of: pattern, options: .regularExpression) != nil
                && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                leaks.append("\(file.lastPathComponent):\(number + 1)")
            }
        }
    }
    check(leaks.isEmpty, "BUG-12: no 은(는)-style placeholder in the copy: \(leaks)")
}

// MARK: - BUG-13: the Mac's Korean app names, and no raw system error in the reply

private func qaLocalizedAppNameTests() {
    check(ArisIntent.parse("텍스트 편집기 2개 켜서 반반으로 나눠 줘") == .arrange(app: "TextEdit", count: 2)
          && ArisIntent.parse("미리보기 2개 켜서 반반") == .arrange(app: "Preview", count: 2)
          && ArisIntent.parse("지도 2개 켜서 반반") == .arrange(app: "Maps", count: 2),
          "BUG-13: Korean names become the app's own")
    let installed = [ArisAppNames.App(display: "텍스트 편집기", file: "TextEdit"), ArisAppNames.App(display: "미리보기", file: "Preview"),
                     ArisAppNames.App(display: "Microsoft Excel", file: "Microsoft Excel")]
    check(ArisAppNames.match("텍스트 편집기", in: installed) == "TextEdit" && ArisAppNames.match("텍스트편집기", in: installed) == "TextEdit"
          && ArisAppNames.match("textedit", in: installed) == "TextEdit" && ArisAppNames.match("미리 보기", in: installed) == "Preview"
          && ArisAppNames.match("microsoft excel", in: installed) == "Microsoft Excel",
          "BUG-13: aris-tools finds an installed app by its shown name, any spacing or case")
    check(ArisAppNames.match("텍스트 편집", in: installed) == "TextEdit" && ArisAppNames.match("메모", in: []) == "Notes",
          "BUG-13: the aliases cover the names said aloud, even with no install list")
    check(ArisAppNames.match("없는 앱", in: installed) == nil && ArisAppNames.match("", in: installed) == nil, "BUG-13: nothing else matches")
    let raw = "Unable to find application named '텍스트 편집기'"
    let korean = ArisIntent.arrangeFailure(raw, app: "TextEdit", korean: true), english = ArisIntent.arrangeFailure(raw, app: "TextEdit", korean: false)
    check(korean == "텍스트 편집기 앱을 찾지 못했어요." && english == "I couldn't find TextEdit.", "BUG-13: a missing app in words: \(korean) / \(english)")
    for message in ["Accessibility permission needed: System Settings → …", "no windows to arrange", "new took too long", "something odd: kAXErrorCannotComplete"] {
        let line = ArisIntent.arrangeFailure(message, app: "TextEdit", korean: true)
        check(!line.contains("Accessibility permission") && !line.contains("kAX") && !line.contains("took too long") && !line.contains("no windows")
              && line.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }, "BUG-13: no raw system text: \(message) -> \(line)")
    }
}

// MARK: - BUG-14: halves exactly equal, said once done, with the app's proper name

private func qaEvenSplitTests() {
    let visible = CGRect(x: 0, y: 37.5, width: 1512, height: 907.5)
    let halves = ArisWindowGrid.frames(count: 2, grid: ArisWindowGrid.Grid(rows: 1, columns: 2), in: visible)
    check(halves.count == 2 && halves[0].size == halves[1].size && halves.allSatisfy { $0.height == $0.height.rounded() && $0.width == $0.width.rounded() }
          && halves[0].maxX <= halves[1].minX && halves[1].maxX <= visible.maxX && halves.allSatisfy { $0.minY >= visible.minY && $0.maxY <= visible.maxY },
          "BUG-14: two halves of the visible frame, the same whole-point size: \(halves)")
    let grid = ArisWindowGrid.frames(count: 4, grid: ArisWindowGrid.Grid(rows: 2, columns: 2), in: CGRect(x: 0, y: 25, width: 1441, height: 875))
    check(Set(grid.map(\.size)).count == 1, "BUG-14: every cell the same size")
    check(ArisIntent.arrange(app: "TextEdit", count: 2).doneLine(korean: true) == "텍스트 편집기 창 2개를 나눴어요."
          && ArisIntent.arrange(app: "TextEdit", count: 2).doneLine(korean: false) == "Put 2 TextEdit windows side by side.",
          "BUG-14: the reply once done is in the past tense")
    check(ArisIntent.arrange(app: "TextEdit", count: 2).acknowledgement(korean: true) == "텍스트 편집기 창 2개를 띄워서 나눌게요."
          && ArisIntent.parse("textedit 2개 켜서 반반") == .arrange(app: "TextEdit", count: 2),
          "BUG-14: the app's proper name (텍스트 편집기, TextEdit), never \"Textedit\"")
    check(ArisIntent.displayName("Microsoft Excel", korean: true) == "Microsoft Excel" && ArisIntent.displayName("Notes", korean: true) == "메모"
          && ArisIntent.displayName("Notes", korean: false) == "Notes", "BUG-14: display names per language")
}

// MARK: - BUG-15: the user's own words typed into a safe app on a clean turn: no card, as aris-tools type

private func qaSafeTypingTests() {
    let request = "TextEdit 창에 QA 테스트 문장입니다 라고 써 줘"
    var editor = ArisDesktopTarget(name: "텍스트 편집기", bundle: "com.apple.TextEdit", pid: 77, known: true, never: false, browser: false, sending: false)
    editor.appleSigned = true   // the follow-up: only Apple's own signed app (qa-followup-b-tests)
    func decide(_ text: String, target: ArisDesktopTarget = editor, context: ArisDesktopContext? = nil, secure: Bool = false,
                element: ArisDesktopElement? = nil) -> ArisDesktopDecision? {
        guard let typed = try? ArisDesktopWords.parse(["type", "@s8f3k2:e2", "--stdin"], text: text).get() else { return nil }
        return ArisDesktopGate.decide(typed, target: target, context: context ?? ArisDesktopContext(request: request), remembered: false,
                                      secureInput: secure, element: element)
    }
    check(decide("QA 테스트 문장입니다") == .run, "BUG-15: the user's own words into TextEdit on a clean turn run at once (as aris-tools type)")
    check(ArisRiskPolicy.isSafeTypingApp(name: "Notes", bundle: "com.apple.Notes") && ArisRiskPolicy.isSafeTypingApp(name: "텍스트 편집기", bundle: "com.apple.TextEdit")
          && !ArisRiskPolicy.isSafeTypingApp(name: "Terminal", bundle: "com.apple.Terminal"), "BUG-15: the safe typing apps are aris-tools type's")
    if case .ask? = decide("rm -rf ~ 그리고 다른 말") {} else { check(false, "BUG-15: words the user didn't say keep the card") }
    if case .ask? = decide("QA 테스트 문장입니다", context: ArisDesktopContext(taintForApp: .outsideText, request: request)) {} else {
        check(false, "BUG-15: after outside text the card stays")
    }
    if case .ask? = decide("QA 테스트 문장입니다", context: ArisDesktopContext(screen: true, request: request)) {} else { check(false, "BUG-15: a screen turn keeps the card") }
    if case .ask? = decide("QA 테스트 문장입니다", context: ArisDesktopContext(handsFree: true, request: request)) {} else { check(false, "BUG-15: hands-free keeps the card") }
    if case .ask? = decide("QA 테스트 문장입니다", context: ArisDesktopContext(request: request, critical: true)) {} else { check(false, "BUG-15: a critical turn keeps the card") }
    let unknown = ArisDesktopTarget(name: "텍스트 편집기", bundle: "com.apple.TextEdit", pid: 77, known: false, never: false, browser: false, sending: false)
    if case .ask? = decide("QA 테스트 문장입니다", target: unknown) {} else { check(false, "BUG-15: an app that isn't the installed, signed one keeps the card") }
    let chat = ArisDesktopTarget(name: "카카오톡", bundle: "com.kakao.KakaoTalkMac", pid: 78, known: true, never: false, browser: false, sending: true)
    if case .ask? = decide("QA 테스트 문장입니다", target: chat) {} else { check(false, "BUG-15: a sending app keeps its card") }
    let other = ArisDesktopTarget(name: "Xcode", bundle: "com.apple.dt.Xcode", pid: 79, known: true, never: false, browser: false, sending: false)
    if case .ask? = decide("QA 테스트 문장입니다", target: other) {} else { check(false, "BUG-15: an app that isn't a safe typing app keeps its card") }
    check(decide("QA 테스트 문장입니다", secure: true) == .refuse(ArisDesktopGate.secureRefusal)
          && decide("QA 테스트 문장입니다", element: ArisDesktopElement(id: "e", role: "textField", label: "Password", axRole: "AXSecureTextField")) == .refuse(ArisDesktopGate.secureFieldRefusal),
          "BUG-15: secure input and password fields are still refused")
}
