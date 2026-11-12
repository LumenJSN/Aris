// Tests for the security-review follow-ups, fork A: a spoken yes to the new-teammate card only like any card's
// (MEDIUM 2), voice teammate removal by click or Y only (MEDIUM 3), typed turns and the practice rule (MEDIUM 5),
// pending dropped files (MEDIUM 6), and the LOWs: the files note never saved as a fact (BUG-7), a typed memory-card flag
// (BUG-6), real speech keeps its brackets (BUG-30), and teammate jobs called hands-free or after outside text run
// careful (BUG-25b).
import Foundation

func runQAFollowupATests() {
    followupTeamMadeTests()
    followupPendingFilesTests()
    followupMemoryTests()
    followupTranscriptTests()
    followupHandOutTests()
    followupLearningTests()
}

private func followupSource(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris")
    return (try? String(contentsOf: root.appendingPathComponent(path).standardized, encoding: .utf8)) ?? ""
}

// MARK: - MEDIUM 2, 3, 5

private func followupTeamMadeTests() {
    typealias A = ArisTeamMadeAnswer
    check(A.makes(yes: true, typed: false, inConversation: false, handsFree: false), "M2: a spoken yes after the talk key makes the teammate")
    check(!A.makes(yes: true, typed: false, inConversation: true, handsFree: false), "M2: a spoken yes in an open conversation doesn't (click or Y)")
    check(!A.makes(yes: true, typed: false, inConversation: false, handsFree: true), "M2: a hands-free spoken yes doesn't")
    check(A.makes(yes: true, typed: true, inConversation: true, handsFree: false), "M2: a typed yes is the user's own, in a conversation too")
    check(!A.makes(yes: false, typed: true, inConversation: false, handsFree: false), "M2: a no never makes it")
    check(A.makes(yes: true, typed: false, inConversation: false, handsFree: false) == ArisConfirmReply.voiceYes(inConversation: false, handsFree: false)
          && A.makes(yes: true, typed: false, inConversation: true, handsFree: true) == ArisConfirmReply.voiceYes(inConversation: true, handsFree: true),
          "M2: a spoken yes counts exactly as ArisConfirmReply.voiceYes says")
    let making = followupSource("ArisController+TeamMaking.swift")
    check(making.contains("ArisTeamMadeAnswer.makes(yes: true, typed: turnTyped, inConversation: conversation.isOpen, handsFree: turnHandsFree)"),
          "M2: the made card's yes goes through that rule")
    check(making.contains("askUser(ArisTeamRemoval.confirmation(for: mate), handsFree: true)"),
          "M3: removing a teammate by voice is answered by a click or Y only")
    let typed = followupSource("ArisController+Typed.swift")
    check(typed.contains("practiceTurn = onboardingTalk == .practice") && typed.contains("answer(heard, typed: true)"),
          "M5: a typed turn follows the practice rule both ways and is marked typed")
    check(followupSource("ArisController.swift").contains("turnTyped = typed"), "M5: every turn sets whether it was typed")
}

// MARK: - MEDIUM 6

private func followupPendingFilesTests() {
    let start = Date(timeIntervalSince1970: 1_000_000)
    let given = ArisPendingFiles().adding([URL(fileURLWithPath: "/Users/me/shells.pdf")], at: start)
    let fresh = given.taking(into: "요약해 줘", at: start.addingTimeInterval(60), handsFree: false, shown: true)
    check(ArisPendingFiles.carriesFiles(fresh.text) && fresh.left.files.isEmpty, "M6: a fresh drop rides along with the next request")
    let stale = given.taking(into: "요약해 줘", at: start.addingTimeInterval(ArisPendingFiles.lifetime + 1), handsFree: false, shown: true)
    check(stale.text == "요약해 줘" && stale.left.files.isEmpty, "M6: after 5 minutes they're gone, never attached")
    check(ArisPendingFiles.lifetime == 300, "M6: the files wait 5 minutes")
    let handsFree = given.taking(into: "요약해 줘", at: start.addingTimeInterval(60), handsFree: true, shown: true)
    check(handsFree.text == "요약해 줘" && handsFree.left.files.count == 1, "M6: a hands-free turn never takes them (they stay for the user)")
    let hidden = given.taking(into: "요약해 줘", at: start.addingTimeInterval(60), handsFree: false, shown: false)
    check(hidden.text == "요약해 줘" && hidden.left.files.count == 1, "M6: with the notch closed and no chips on screen, they aren't attached")
    let typed = given.request(with: "요약해 줘")
    check(given.taking(into: typed, at: start.addingTimeInterval(60), handsFree: false, shown: false).text == typed,
          "M6: a typed request already carries them (the composer showed the chips)")
    let again = given.adding([URL(fileURLWithPath: "/Users/me/b.pdf")], at: start.addingTimeInterval(200))
    check(ArisPendingFiles.carriesFiles(again.taking(into: "x", at: start.addingTimeInterval(200 + ArisPendingFiles.lifetime - 1), handsFree: false, shown: true).text),
          "M6: a new drop starts the 5 minutes again")
    let controller = followupSource("ArisController.swift")
    check(controller.contains("ArisAttachments.shared.take(into: said, handsFree: turnHandsFree, shown: ArisNotchPresence.shared.isOpen)"),
          "M6: the turn tells whether it is hands-free and whether the chips can be seen")
}

// MARK: - BUG-7, BUG-6

private func followupMemoryTests() {
    let note = "\n\n(첨부한 파일: /Users/me/shells.pdf — 사용자가 Aris에게 준 파일이에요. \"이 파일\", \"이거\", \"this file\"은 이 파일을 말해요)"
    check(ArisMemoryText.ownWords("커피는 아이스 아메리카노" + note) == "커피는 아이스 아메리카노" && ArisMemoryText.ownWords("그냥 말") == "그냥 말",
          "BUG-7: the user's words without the files' note")
    check(ArisMemoryIntent.parse("기억해: 커피는 아이스 아메리카노" + note) == .remember("커피는 아이스 아메리카노"),
          "BUG-7: a remembered fact never carries the files' note")
    // A memory card is flagged by its action, never by its title.
    let tools = "/Users/me/.config/aris/aris-tools"
    let codex = ArisCodexDriver(model: "m", tools: tools, instructions: "", home: "/Users/me")
    _ = codex.ask("커피는 아이스라고 기억해")
    codex.markUntrusted()
    let request: [String: Any] = ["id": 77, "method": "item/commandExecution/requestApproval",
                                  "params": ["command": "/bin/zsh -lc '\(tools) remember 커피는 아이스'"]]
    let line = (try? JSONSerialization.data(withJSONObject: request)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    if case .confirm(let ask)? = codex.read(line).first {
        check(ask.memoryWrite, "BUG-6: Codex's remember card is flagged a memory write")
    } else {
        check(false, "BUG-6: Codex's remember card is flagged a memory write")
    }
    check(!ArisConfirmation(id: "x", title: "기억하기", detail: "").memoryWrite, "BUG-6: a card titled 기억하기 isn't a memory card by its title")
    check(ArisConfirmation(id: "x", title: "아무거나", detail: "", memoryWrite: true).memoryWrite, "BUG-6: the flag is what counts")
    let gate = ArisAPIGate(tools: tools, home: "/Users/me")
    gate.markUntrusted()
    if case .ask(let ask, _, _, _) = gate.judge("\(tools) forget 커피") {
        check(ask.memoryWrite, "BUG-6: the API brain's forget card is flagged too")
    } else {
        check(false, "BUG-6: the API brain's forget card is flagged too")
    }
}

// MARK: - BUG-30

private func followupTranscriptTests() {
    check(ArisTranscript.pick(whisper: "Open report (final).pdf", apple: "리포트 열어", heardVoice: true) == "Open report (final).pdf",
          "BUG-30: real speech Apple heard too keeps its parentheses")
    check(ArisTranscript.pick(whisper: "Play [the] remix", apple: "리믹스 틀어", heardVoice: true) == "Play [the] remix",
          "BUG-30: and its brackets")
    check(ArisTranscript.pick(whisper: "*sad music*", apple: "", heardVoice: true, voiceFrames: 5, loudest: 0.1246) == "",
          "BUG-30: Whisper alone still drops its annotations")
    check(ArisTranscript.pick(whisper: "(박수)", apple: "", heardVoice: true, voiceFrames: 200, loudest: 0.9) == "", "BUG-30: an annotation alone is nothing")
}

// MARK: - BUG-25b

private func followupHandOutTests() {
    let mate = ArisJobSpec(title: "x", prompt: "17 곱하기 23은?", assignee: .teammate("qa-bot"), cwd: nil, appHint: nil)
    let handsFree = ArisHandOutPlan.plan([mate], turn: ArisHandOutPlan.Turn(words: "큐에이봇, 17 곱하기 23은?", brain: .codex, turnId: "t",
                                                                           handsFree: true), brains: ["qa-bot": .claude])
    check(handsFree.count == 1 && handsFree[0].provenance.handsFree && handsFree[0].turn == nil,
          "BUG-25b: a teammate called hands-free runs marked hands-free (careful), vouching for nothing")
    let outside = ArisHandOutPlan.plan([mate], turn: ArisHandOutPlan.Turn(words: "큐에이봇, 17 곱하기 23은?", brain: .codex, turnId: "t",
                                                                         outsideConversation: true), brains: ["qa-bot": .claude])
    check(outside.count == 1 && outside[0].provenance.untrusted && outside[0].provenance.outsideConversation && outside[0].cleanContext
          && outside[0].turn == nil, "BUG-25b: after outside text it runs untrusted, with none of the conversation")
    let screen = ArisHandOutPlan.plan([mate], turn: ArisHandOutPlan.Turn(words: "큐에이봇, 이거 봐", brain: .codex, turnId: "t",
                                                                        screenConversation: true), brains: ["qa-bot": .claude])
    check(screen.first?.provenance.untrusted == true && screen.first?.provenance.screenConversation == true, "BUG-25b: after the screen too")
    let controller = followupSource("ArisController.swift")
    check(controller.contains("let handed = handOut([job], turn: ArisHandOutPlan.Turn(words: unmarked, brain: brain, turnId: nil, screenConversation: screenConversation,")
          && controller.contains("outsideConversation: outsideConversation, handsFree: turnHandsFree),"),
          "BUG-25b: the teammate called by name hands out with the turn's hands-free and outside-text claims")
}

// MARK: - BUG-6b: requests are never learned, and a turn with any card never teaches

private func followupLearningTests() {
    func picked(_ text: String, _ kind: ArisMemoryKind = .routine) -> [ArisMemoryCandidate] {
        ArisMemoryLearning.accepted([ArisMemoryCandidate(kind: kind, subject: "", text: text, confidence: 0.6)], words: text)
    }
    let qa = "QA 테스트로 매일 아침 9시에 날씨 알려 줘"
    check(picked(qa).isEmpty && ArisMemoryLearning.ruleCandidates(qa).isEmpty, "BUG-6b: QA's schedule request is never learned as a habit")
    for request in ["매일 아침 일정 정리해 줘", "회의 일정 추가해", "주간 보고서 만들어 줘", "remind me to call mom every day", "tell me the weather every morning",
                    "make a note that I like jazz", "add milk to my list", "please play my workout playlist every morning"] {
        check(picked(request).isEmpty && ArisMemoryLearning.ruleCandidates(request).isEmpty, "BUG-6b: \(request) is a request, never learned")
    }
    check(!picked("나는 매일 아침 9시에 운동해").isEmpty && !picked("I usually go to the gym at 7am on weekdays").isEmpty,
          "BUG-6b: what the user says about himself is still learned")
    check(ArisMemoryLearning.learnsAfterTurn(taint: .none, card: false) && !ArisMemoryLearning.learnsAfterTurn(taint: .none, card: true)
          && !ArisMemoryLearning.learnsAfterTurn(taint: .outsideText, card: false), "BUG-6b: a turn that showed any card never teaches")
    let agent = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../ArisAgent").standardized
    let runner = (try? String(contentsOf: agent.appendingPathComponent("ArisAgentRunner.swift"), encoding: .utf8)) ?? ""
    let main = (try? String(contentsOf: agent.appendingPathComponent("main.swift"), encoding: .utf8)) ?? ""
    check(runner.contains("if driver.escalation(for: ask.id)?.read == nil { showedCard = true }")
          && main.contains("ArisMemoryLearning.learnsAfterTurn(taint: taint, card: runner.showedCard"),
          "BUG-6b: every card shown this turn (never a read the judge took) stops learning")
}
