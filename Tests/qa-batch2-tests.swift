// Tests for QA batch 2 (jdoe-62): what 기억해 stores (BUG-4), forgetting by topic words (BUG-5), no learning from a
// declined or carded memory turn (BUG-6), the user's own 기억해 after outside text (BUG-7), how many to-dos are read
// (BUG-8), and the settings' stale words and upstream version (BUG-9).
import Foundation

func runQABatch2Tests() {
    qaRememberTextTests()
    qaForgetByWordsTests()
    qaNoLearningFromMemoryTurnsTests()
    qaOwnRememberAfterOutsideTextTests()
    qaTodoCountTests()
    qaSettingsWordsTests()
    qaDeadlineTimeTests()
}

private func qaMemoryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-qa2-memory-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

// MARK: - BUG-4: 기억해 keeps the verb whole, and drops a leading 내가/나는

private func qaRememberTextTests() {
    let cases: [(String, ArisMemoryIntent?)] = [
        ("내가 QA 테스트할 때 망고 좋아한다고 기억해", .remember("QA 테스트할 때 망고 좋아해")),
        ("망고 좋아한다는 거 기억해", .remember("망고 좋아해")),
        ("나는 매일 아침 커피 마신다고 기억해 줘", .remember("매일 아침 커피 마셔")),
        ("민지는 김치 잘 먹는다고 기억해", .remember("민지는 김치 잘 먹어")),
        ("나는 수영이 좋다고 기억해", .remember("수영이 좋아")),
        ("내가 어제 서울 갔다고 기억해", .remember("어제 서울 갔어")),
        ("엄마가 주말에 오자고 했다고 기억해", .remember("엄마가 주말에 오자고 했어")),
        ("내가 망고 좋아하는 거 기억해", .remember("망고 좋아해")),
        ("기억해, 내가 망고 좋아한다는 거", .remember("망고 좋아해")),
        // Unchanged: nouns stay as they were said.
        ("커피는 아이스 아메리카노라는 거 기억해", .remember("커피는 아이스 아메리카노")),
        ("내 생일은 3월 5일이야 기억해 줘", .remember("내 생일은 3월 5일이야")),
        ("꼭 내 자전거 기억해 둬", .remember("내 자전거")),
    ]
    for (said, wanted) in cases {
        let got = ArisMemoryIntent.parse(said)
        check(got == wanted, "BUG-4: \"\(said)\" -> \(wanted.map { "\($0)" } ?? "nil") (got \(got.map { "\($0)" } ?? "nil"))")
    }
    check(ArisMemoryIntent.declarative("좋아한다") == "좋아해" && ArisMemoryIntent.declarative("먹는다") == "먹어"
          && ArisMemoryIntent.declarative("간다") == "가" && ArisMemoryIntent.declarative("본다") == "봐" && ArisMemoryIntent.declarative("좋다") == "좋아"
          && ArisMemoryIntent.declarative("예쁘다") == "예뻐" && ArisMemoryIntent.declarative("했다") == "했어" && ArisMemoryIntent.declarative("마신다") == "마셔"
          && ArisMemoryIntent.declarative("배운다") == "배워" && ArisMemoryIntent.declarative("귀엽다") == "귀여워" && ArisMemoryIntent.declarative("모른다") == "몰라"
          && ArisMemoryIntent.declarative("좋아하냐") == "좋아해" && ArisMemoryIntent.declarative("가자") == "가",
          "BUG-4: a quoted verb becomes the plain 해-form the other memories use")
}

// MARK: - BUG-5: forgetting by its words, across particles, case and spacing

private func qaForgetByWordsTests() {
    check(ArisMemoryIntent.parse("QA 테스트 망고 기억 지워") == .forget("QA 테스트 망고"), "BUG-5: the topic words are read")
    let folder = qaMemoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let now = Date()
    _ = store.remember(ArisMemoryCandidate(kind: .preference, subject: "", text: "QA 테스트할 때 망고 좋아해", confidence: 1), source: .said, turnAt: now)
    _ = store.remember(ArisMemoryCandidate(kind: .preference, subject: "커피", text: "커피는 아이스 아메리카노", confidence: 1), source: .said, turnAt: now)
    check(store.matching("QA 테스트 망고").map(\.text) == ["QA 테스트할 때 망고 좋아해"], "BUG-5: every word, not the exact phrase")
    check(store.matching("qa테스트 망고를").map(\.text) == ["QA 테스트할 때 망고 좋아해"], "BUG-5: case, spacing and a particle don't matter")
    check(store.matching("QA 테스트 사과").isEmpty && store.matching("망고 커피").isEmpty, "BUG-5: a word it doesn't have keeps it")
    check(store.matching("아이스 아메리카노").map(\.text) == ["커피는 아이스 아메리카노"], "BUG-5: an exact phrase still matches")
    let curator = ArisMemoryCurator(store: store, extract: { _ in nil }, summarize: { _ in nil })
    check(curator.answer(.forget("QA 테스트 망고"), said: "QA 테스트 망고 기억 지워")?.hasPrefix("잊었어요") == true
          && !store.all().contains { $0.text.contains("망고") } && store.count() == 1, "BUG-5: 기억 지워 forgets it")
}

// MARK: - BUG-6: a memory card's turn, or a declined one, never auto-learns; commands are never facts

private func qaNoLearningFromMemoryTurnsTests() {
    let tools = "/Users/me/.config/aris/aris-tools"
    for command in ["좋아한다고 기억해 망고", "망고 좋아한다고 기억해 줘", "커피 얘기 잊어", "그 기억 지워", "remember that I like mango", "forget the gym"] {
        check(ArisMemoryLearning.isMemoryCommand(command), "BUG-6: \"\(command)\" is a command, never a fact")
    }
    for fact in ["망고 좋아해", "지워지지 않는 펜을 좋아해", "나는 매일 수영해", "I always take the bus"] {
        check(!ArisMemoryLearning.isMemoryCommand(fact), "BUG-6: \"\(fact)\" is no command")
    }
    let raw = ArisMemoryCandidate(kind: .preference, subject: "", text: "좋아한다고 기억해 망고", confidence: 0.6)
    check(ArisMemoryLearning.accepted([raw], words: "좋아한다고 기억해 망고").isEmpty && ArisMemoryLearning.ruleCandidates("좋아한다고 기억해 망고").isEmpty,
          "BUG-6: the command words are never picked out as a memory")
    let folder = qaMemoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let curator = ArisMemoryCurator(store: store, extract: { words in [ArisMemoryCandidate(kind: .preference, subject: "", text: words, confidence: 0.6)] },
                                    summarize: { _ in nil })
    check(curator.learnNow(from: "좋아한다고 기억해 망고", at: Date()).isEmpty && store.count() == 0, "BUG-6: learning skips the words of a 기억해")
    // The turn: a memory card shown (the user's yes or no) means no learning from it at all.
    check(!ArisMemoryLearning.learnsAfterTurn(taint: .none, card: true) && ArisMemoryLearning.learnsAfterTurn(taint: .none, card: false)
          && !ArisMemoryLearning.learnsAfterTurn(taint: .outsideText, card: false) && !ArisMemoryLearning.learnsAfterTurn(taint: .screenSeen, card: false),
          "BUG-6: a turn that showed a memory card (declined or not) never learns")
    check(ArisMemoryLearning.isMemoryWrite(.shell("\(tools) remember \"망고 좋아해\""), tools: tools)
          && ArisMemoryLearning.isMemoryWrite(.shell("/bin/zsh -lc '\(tools) forget 망고'"), tools: tools)
          && ArisMemoryLearning.isMemoryWrite(.shell("\(tools) timer 5 && \(tools) remember x"), tools: tools)
          && !ArisMemoryLearning.isMemoryWrite(.shell("\(tools) timer 5"), tools: tools)
          && !ArisMemoryLearning.isMemoryWrite(.shell("\(tools) memory 망고"), tools: tools)
          && !ArisMemoryLearning.isMemoryWrite(.fileChange(["/x"]), tools: tools),
          "BUG-6: which cards are memory cards (remember or forget)")
    // Follow-up: a memory card is flagged by its action (ArisConfirmation.memoryWrite), never by its title.
    check(ArisConfirmation(id: "m", title: "타이머", detail: "", memoryWrite: true).memoryWrite && !ArisConfirmation(id: "m", title: "기억하기", detail: "").memoryWrite,
          "BUG-6: a memory card is flagged by the gate, not by its title")
}

// MARK: - BUG-7: the user's own 기억해 is their words, even after outside text

private func qaOwnRememberAfterOutsideTextTests() {
    check(ArisMemoryLearning.answersLocally(.remember("망고 좋아해"), fromApp: true, handsFree: false, images: false, clean: false),
          "BUG-7: the user's own parsed 기억해 saves at once after outside text (no card)")
    check(ArisMemoryLearning.answersLocally(.remember("망고 좋아해"), fromApp: true, handsFree: false, images: false, clean: true),
          "BUG-7: and on a clean turn, as before")
    check(!ArisMemoryLearning.answersLocally(.remember("망고 좋아해"), fromApp: true, handsFree: true, images: false, clean: false)
          && !ArisMemoryLearning.answersLocally(.remember("망고 좋아해"), fromApp: true, handsFree: false, images: true, clean: false)
          && !ArisMemoryLearning.answersLocally(.remember("망고 좋아해"), fromApp: false, handsFree: false, images: false, clean: false),
          "BUG-7: never hands-free, with screen images or from another caller")
    check(!ArisMemoryLearning.answersLocally(.forget("망고"), fromApp: true, handsFree: false, images: false, clean: false)
          && ArisMemoryLearning.answersLocally(.recall("망고"), fromApp: true, handsFree: false, images: false, clean: false),
          "BUG-7: other writes after outside text still go to the brain's gate, as before")
    let prefixes: [(String, ArisMemoryIntent?)] = [
        ("기억해, 망고 좋아해", .remember("망고 좋아해")),
        ("기억해: 망고 좋아해", .remember("망고 좋아해")),
        ("기억해. 망고 좋아해", .remember("망고 좋아해")),
        ("기억해 주세요, 망고 좋아해", .remember("망고 좋아해")),
        ("기억해요: 민지는 내 동생이야", .remember("민지는 내 동생이야")),
        ("기억해, 이거", nil),
    ]
    for (said, wanted) in prefixes {
        let got = ArisMemoryIntent.parse(said)
        check(got == wanted, "BUG-7: \"\(said)\" -> \(wanted.map { "\($0)" } ?? "nil") (got \(got.map { "\($0)" } ?? "nil"))")
    }
}

// MARK: - BUG-8: the count said is the count read, the newest first

private func qaTodoCountTests() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func item(_ index: Int) -> ArisTodoItem {
        ArisTodoItem(id: "t\(index)", title: "할 일 \(index)", notes: nil, due: nil, hasTime: false, listID: "l", listName: "미리 알림",
                     colorHex: "#ff0000", created: now.addingTimeInterval(Double(index) * 60))
    }
    let nine = (1...9).map(item)
    let said = ArisTodoSpeech.line(nine, korean: true, now: now)
    check(said == "할 일 9개 있어요: 할 일 9, 할 일 8, 할 일 7, 할 일 6, 할 일 5 외 4개.", "BUG-8: past 7, five read and the rest counted: \(said)")
    let seven = (1...7).map(item)
    let all = ArisTodoSpeech.line(seven.shuffled(), korean: true, now: now)
    check(all == "할 일 7개 있어요: 할 일 7, 할 일 6, 할 일 5, 할 일 4, 할 일 3, 할 일 2, 할 일 1.", "BUG-8: up to 7, all of them, newest first: \(all)")
    check(ArisTodoSpeech.line([], korean: true, now: now) == "할 일은 비어 있어요." && ArisTodoSpeech.line(nine, korean: false, now: now).hasSuffix("and 4 more."),
          "BUG-8: empty, and English")
    let undated = ArisTodoItem(id: "old", title: "예전 일", notes: nil, due: nil, hasTime: false, listID: "l", listName: "미리 알림", colorHex: "#ff0000")
    check(ArisTodoSpeech.ordered([undated] + seven).first?.id == "t7" && ArisTodoSpeech.ordered([undated] + seven).last?.id == "old",
          "BUG-8: an item with no creation date goes last")
    let decoded = try? JSONDecoder().decode(ArisTodoItem.self, from: Data(##"{"id":"a","title":"x","hasTime":false,"listID":"l","listName":"n","colorHex":"#000000"}"##.utf8))
    check(decoded?.created == nil && decoded?.title == "x", "BUG-8: an item saved before the creation date still reads")
}

// MARK: - BUG-9: settings words and Aris's own version

private func qaSettingsWordsTests() {
    let rows = ArisSettingsBuilder.sections(.ai, ArisSettingsSnapshot()).flatMap(\.rows)
    let teamBrain = rows.first { $0.id == "ai.teamBrain" }?.desc ?? ""
    check(!teamBrain.isEmpty && !teamBrain.contains("Codex만"), "BUG-9a: a teammate may use any brain: \(teamBrain)")
    let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Aris.xcodeproj/project.pbxproj")
    let text = (try? String(contentsOf: project, encoding: .utf8)) ?? ""
    let marketing = text.components(separatedBy: "\n").filter { $0.contains("MARKETING_VERSION") }
    let build = text.components(separatedBy: "\n").filter { $0.contains("CURRENT_PROJECT_VERSION") }
    check(!marketing.isEmpty && marketing.allSatisfy { $0.contains("MARKETING_VERSION = 0.1.0;") }
          && !build.isEmpty && build.allSatisfy { $0.contains("CURRENT_PROJECT_VERSION = 1;") } && !text.contains("2.8-beta"),
          "BUG-9b: every target is Aris 0.1.0 (1), never Boring Notch's 2.8-beta.0 (272)")
}

// MARK: - BUG-32: a 17:00 deadline reads 17:00, never 05:00

private func qaDeadlineTimeTests() {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let five = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today)!, nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!
    let tag = ArisDue.when(five, now: nine, calendar: calendar)
    check(tag == ("오늘 17:00", true), "BUG-32: the side 할 일 tab's tag for a 17:00 deadline today: \(tag.0)")
    check(ArisDue.when(calendar.date(bySettingHour: 9, minute: 5, second: 0, of: today)!, now: nine, calendar: calendar).0 == "오늘 09:05",
          "BUG-32: a morning deadline is 09:05 (24-hour, no 오전/오후 needed)")
    let due = ArisDue(id: "a", course: "CSC263H1", title: "Problem Set 3", at: five, url: nil)
    let said = due.spoken(now: nine, calendar: calendar)
    check(said == "CSC263 Problem Set 3 (오늘 17:00)", "BUG-32: 할 일 뭐 있어's Canvas line says 17:00: \(said)")
    check(ArisDue.when(calendar.date(byAdding: .day, value: 1, to: five)!, now: nine, calendar: calendar) == ("내일", false),
          "BUG-32: tomorrow is still 내일")
    // aris-tools canvas (the agent's side) and the brief already say 17:00; held here.
    let item = ArisCanvas.Item(kind: "assignment", course: "CSC263H1", title: "Problem Set 3", date: five, submitted: false, unread: false, id: "x", url: nil)
    check(ArisCanvas.summary([item], now: nine, timeZone: calendar.timeZone).contains("17:00 · CSC263H1 · Problem Set 3"),
          "BUG-32: aris-tools canvas says 17:00")
}
