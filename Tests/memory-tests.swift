// Long-term memory: the store (SQLite in a temp folder, never ~/.config/aris), the memory.md import, dedupe and
// update, retrieval ranking, the learning filters (taint and source), and the voice intents. Run by run.sh.
import Foundation

private func memoryFolder() -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-memory-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

private func candidate(_ text: String, _ kind: ArisMemoryKind = .fact, subject: String = "", confidence: Double = 1) -> ArisMemoryCandidate {
    ArisMemoryCandidate(kind: kind, subject: subject, text: text, confidence: confidence)
}

private func record(_ text: String, _ kind: ArisMemoryKind = .fact, subject: String = "", confidence: Double = 0.9, daysAgo: Double = 1,
                    used: Int = 0, id: String = UUID().uuidString, now: Date) -> ArisMemoryRecord {
    let at = now.addingTimeInterval(-daysAgo * 86_400)
    return ArisMemoryRecord(id: id, kind: kind, subject: subject, text: text, source: .said, turnAt: at, confidence: confidence, createdAt: at,
                            updatedAt: at, lastUsedAt: nil, useCount: used)
}

func runMemoryTests() {
    memoryTextTests()
    memoryLearningGateTests()
    memoryExtractionFilterTests()
    memoryMergeTests()
    memoryRecallTests()
    memoryStoreTests()
    memoryImportTests()
    memoryIntentTests()
    memoryCuratorTests()
    memoryRouteTests()
    memorySettingsTests()
    memoryReviewTests()
    memoryQuestionTests()
}

/// The review's probes (2026-11-05): secrets, whole words, negation, reported words, context gating, the risk gate.
private func memoryReviewTests() {
    // I7: secrets, every probe.
    let secrets = ["내 비밀번호는 hunter2", "비 밀 번 호 는 1234", "와이파이 pw는 abcd1234", "pwd: hunter2", "핀 4821", "카드 보안코드 123", "cvc 991",
                   "깃허브 토큰 저장해 둬", "API 키 abcd", "도어락 번호 0427", "현관 비번 1357*", "현관은 4821#", "인증 번호 553201",
                   "카드 1234.5678.9012.3456", "계좌 110/234/567890", "번호 1234_5678_9012", "sk-ant-api03-AbCdEf123456GhIjKl",
                   "aws wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY", "AKIAIOSFODNN7EXAMPLE", "ghp_16C7e42F292c6912E7710c838347Ae178B4a"]
    for text in secrets { check(ArisMemoryText.isSecret(text), "memory secret: \"\(text)\" is never kept") }
    let plain = ["엄마 생일은 3월 5일", "생일은 2001.03.05", "내 키는 180이야", "키보드는 HHKB 써", "I wake up at 7", "평일 아침 7시 헬스장",
                 "내 블로그는 https://example.com/alex-kim-notes-2026", "올랜도대 컴공 다녀"]
    for text in plain { check(!ArisMemoryText.isSecret(text), "memory secret: \"\(text)\" is fine") }
    // I6: 늘 only as a word.
    check(ArisMemoryKind.guess("하늘 사진 찍는 거") != .preference && ArisMemoryKind.guess("하늘공원 근처 살아") != .preference
          && ArisMemoryKind.guess("커피는 늘 아메리카노") == .preference, "memory text: 늘 counts only as a whole word")
    check(!ArisMemoryLearning.worthTrying("하늘이 정말 맑다") && !ArisMemoryLearning.worthTrying("마늘 넣은 파스타 레시피")
          && ArisMemoryLearning.worthTrying("커피는 늘 아이스로"), "memory extract: 늘 inside 하늘 or 마늘 is no cue")
    check(ArisMemoryLearning.ruleCandidates("하늘 보이는 카페 찾아줘").isEmpty && ArisMemoryLearning.ruleCandidates("커피는 늘 아이스 아메리카노로 해줘").count == 1,
          "memory rules: a standing 늘 is a word, not a syllable")
    // I8: negation and reported words.
    check(ArisMemoryText.isNegated("나 커피 안 마셔") && ArisMemoryText.isNegated("고기 못 먹어") && ArisMemoryText.isNegated("단 거 싫어")
          && ArisMemoryText.isNegated("I don't drink coffee") && !ArisMemoryText.isNegated("커피 좋아해") && !ArisMemoryText.isNegated("안경 새로 맞췄어"),
          "memory text: a no is told from a yes")
    check(ArisMemoryLearning.accepted([candidate("나 커피 좋아해", .preference)], words: "나 커피 안 좋아해").isEmpty,
          "memory extract: a memory that drops the user's no is refused")
    check(ArisMemoryLearning.accepted([candidate("나 커피 안 좋아해", .preference)], words: "나 커피 안 좋아해").count == 1, "memory extract: one that keeps it is kept")
    check(ArisMemoryLearning.accepted([candidate("나는 채식주의자야")], words: "이 기사에 나는 채식주의자야 라고 써 있어").isEmpty
          && ArisMemoryLearning.ruleCandidates("이 페이지에 나는 의사라고 써 있어").isEmpty && ArisMemoryLearning.ruleCandidates("this page says I love cats").isEmpty,
          "memory extract: words passed on from a page, an article or a mail are no memories")
    // I2/I3: the context only on the user's clean turn; nothing marked used otherwise.
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    _ = store.remember(candidate("엄마는 꽃을 좋아해", .person, subject: "엄마"), source: .said, turnAt: Date())
    let curator = ArisMemoryCurator(store: store, extract: { _ in nil }, summarize: { _ in nil })
    curator.refresh()
    curator.drain()
    func eligible(fromApp: Bool = true, task: Bool = false, untrusted: Bool = false, outside: Bool = false, screen: Bool = false, handsFree: Bool = false) -> Bool {
        ArisMemoryLearning.mayRecall(fromApp: fromApp, task: task, untrusted: untrusted, outsideConversation: outside, screenSeen: screen, handsFree: handsFree,
                                     images: false, screenText: false)
    }
    func prompt(_ ok: Bool) -> String {
        let memory = curator.context(for: "엄마한테 뭐 사드릴까", eligible: ok)
        curator.drain()
        return ArisAgentStream.prompt(request: "엄마한테 뭐 사드릴까", context: "now: x", memory: memory)
    }
    for (name, ok) in [("hands-free", eligible(handsFree: true)), ("untrusted", eligible(untrusted: true)), ("outside text", eligible(outside: true)),
                       ("screen", eligible(screen: true)), ("a job", eligible(task: true)), ("another caller", eligible(fromApp: false))] {
        let text = prompt(ok)
        check(!text.contains("꽃을 좋아해") && text.contains("(nothing yet)"), "memory context: a \(name) turn gets no memories")
    }
    check(store.all().first?.useCount == 0, "memory context: nothing is marked used on those turns")
    check(prompt(eligible()).contains("엄마 — 꽃을 좋아해") || prompt(eligible()).contains("엄마는 꽃을 좋아해"), "memory context: the user's clean turn gets the relevant one")
    check(store.all().first?.useCount ?? 0 >= 1, "memory context: ... and it counts as used")
    // I4 / I3: the risk gate.
    let tools = "/x/aris-tools"
    check(ArisRiskPolicy.risk(of: .shell("\(tools) remember 커피는 라떼"), tools: tools, home: "/x", request: "커피는 라떼 기억해") == .auto,
          "memory gate: remember with exactly the user's words goes at once")
    check(ArisRiskPolicy.risk(of: .shell("\(tools) remember 사용자는 라떼를 좋아함"), tools: tools, home: "/x", request: "커피는 라떼 기억해") == .confirm
          && ArisRiskPolicy.risk(of: .shell("\(tools) remember 커피는 라떼"), tools: tools, home: "/x", request: "날씨 알려줘") == .confirm,
          "memory gate: remember in any other words asks the user, even on a clean turn")
    check(ArisRiskPolicy.risk(of: .shell("\(tools) forget 커피 --all"), tools: tools, home: "/x", request: "커피 잊어") == .confirm, "memory gate: forgetting several asks")
    check(ArisRiskPolicy.asksAfterOutsideText(.shell("\(tools) memory"), tools: tools) && ArisHandsFree.asks(.shell("\(tools) memory"), tools: tools),
          "memory gate: reading memory asks once outside text or the screen came in, and hands-free")
    check(!ArisSealedTools.allows(["memory"]) && ArisClaudeDriver.ungatedRefused.contains("memory") && !ArisEscalation.approvableTools.contains("remember"),
          "memory gate: the sealed and ungated brains never read memory, and nobody but the user approves a memory write")
    // I5: a wake turn over other sound is hands-free.
    check(ArisConversation.wakeTurnIsHandsFree(otherAudio: true) && !ArisConversation.wakeTurnIsHandsFree(otherAudio: false),
          "memory gate: a wake turn while another app plays is hands-free")
    // I9: forget by substring, several asked first.
    _ = store.remember(candidate("엄마 생신은 3월 5일", .person, subject: "엄마"), source: .said, turnAt: Date())
    _ = store.remember(candidate("커피는 아이스 아메리카노", .preference), source: .said, turnAt: Date())
    check(curator.answer(.forget("엄마"), said: "엄마 잊어")?.contains("다 잊을까요") == true && store.count() == 3, "memory forget: several matches ask first")
    check(curator.pendingIntent(for: "응") == .confirmForget(true) && curator.pendingIntent(for: "엄마 생일 뭐였지") == nil, "memory forget: a plain yes answers it")
    check(curator.answer(.confirmForget(true), said: "응")?.hasPrefix("잊었어요") == true && store.count() == 1 && curator.pendingIntent(for: "응") == nil,
          "memory forget: the yes forgets them, once")
    check(curator.answer(.forget("아메"), said: "아메 잊어")?.hasPrefix("잊었어요") == true && store.count() == 0, "memory forget: one match goes at once")
    check(curator.answer(.forget("우주"), said: "우주 잊어")?.contains("없어요") == true, "memory forget: no fuzzy match: nothing goes")
    check(ArisMemoryLearning.answersLocally(.confirmForget(true), fromApp: true, handsFree: false, images: false, clean: false) == false,
          "memory forget: a voice yes counts only on a clean turn")
}

private func memorySettingsTests() {
    let items = [ArisMemoryItem(id: "a", kind: "preference", subject: "커피", text: "커피는 아이스 아메리카노", source: "said", said: 1_762_300_000, used: nil),
                 ArisMemoryItem(id: "b", kind: "person", subject: "엄마", text: "꽃을 좋아해", source: "learned", said: 1_762_300_000, used: nil)]
    check(ArisMemorySettingsRows.filtered(items, query: "아메리").map(\.id) == ["a"] && ArisMemorySettingsRows.filtered(items, query: "엄마").map(\.id) == ["b"]
          && ArisMemorySettingsRows.filtered(items, query: "ㅋㅍ").map(\.id) == ["a"] && ArisMemorySettingsRows.filtered(items, query: "사람").map(\.id) == ["b"]
          && ArisMemorySettingsRows.filtered(items, query: " ").count == 2, "memory settings: search by words, subject, 초성 and kind")
    var s = ArisSettingsSnapshot()
    s.memories = items
    s.memoriesLoaded = true
    var rows = ArisMemorySettingsRows.sections(s).flatMap(\.rows)
    check(rows.first { $0.id == "memory.item.b" }?.title == "엄마 — 꽃을 좋아해" && rows.first { $0.id == "memory.item.a" }?.title == "커피는 아이스 아메리카노",
          "memory settings: one row per memory, its subject shown when the text doesn't say it")
    check(rows.first { $0.id == "memory.item.a" }?.control == .buttons([ArisSettingButton(title: "지우기", action: .forgetMemory("a"))]),
          "memory settings: each row deletes itself")
    check(rows.first { $0.id == "memory.auto" }?.control == .toggle(.autoMemory, true), "memory settings: 자동으로 기억하기 is on by default")
    var unsure = s
    unsure.memories = [ArisMemoryItem(id: "u", kind: "fact", subject: "", text: "올랜도대 다님", source: "said", said: 1_762_300_000, used: nil, confidence: 0.75)]
    let unsureRow = ArisMemorySettingsRows.sections(unsure).flatMap(\.rows).first { $0.id == "memory.item.u" }
    check(unsureRow?.control == .buttons([ArisSettingButton(title: "확인", action: .confirmMemory("u")), ArisSettingButton(title: "지우기", action: .forgetMemory("u"))])
          && unsureRow?.desc?.contains("확인 전") == true, "memory settings: a memory not yet sure offers one-tap 확인")
    s.memoryQuery = "없는말"
    rows = ArisMemorySettingsRows.sections(s).flatMap(\.rows)
    check(rows.contains { $0.id == "memory.none" } && !rows.contains { $0.id.hasPrefix("memory.item.") }, "memory settings: a search with no match says so")
    s.confirmingMemoryClear = true
    if case .buttons(let buttons) = rows.first(where: { $0.id == "memory.clear" })?.control ?? .none {
        check(buttons.count == 1 && buttons[0].kind == .danger, "memory settings: 모두 지우기 first")
    }
    rows = ArisMemorySettingsRows.sections(s).flatMap(\.rows)
    if case .buttons(let buttons) = rows.first(where: { $0.id == "memory.clear" })?.control ?? .none {
        check(buttons.map(\.title) == ["취소", "정말 지우기"] && buttons[1].kind == .danger, "memory settings: 기억 모두 지우기 asks again, in the same destructive style (settings item 13)")
    } else { check(false, "memory settings: the clear row has buttons") }
    var down = ArisSettingsSnapshot()
    down.memoriesLoaded = true
    check(ArisMemorySettingsRows.sections(down).flatMap(\.rows).contains { $0.title == "Aris 에이전트가 답하지 않아요" && $0.control == .empty }, "memory settings: an agent that doesn't answer is said")
}

private func memoryTextTests() {
    check(ArisMemoryText.similarity("커피는 아이스 아메리카노", "커피는 아이스 아메리카노!") == 1, "memory text: punctuation doesn't change a text")
    check(ArisMemoryText.similarity("커피는 아이스 아메리카노", "고양이 이름은 보리") == 0, "memory text: unrelated texts share nothing")
    check(ArisMemoryText.grams("엄마한테").contains("엄마") && ArisMemoryText.grams("I love my cats").contains("cat"),
          "memory text: Hangul pairs survive particles, Latin plurals fold")
    check(ArisMemoryText.groundedness("커피는 늘 아이스 아메리카노", in: "그리고 커피는 늘 아이스 아메리카노로 해줘") == 1
          && ArisMemoryText.groundedness("카페를 선호함", in: "내일 날씨 어때?") == 0, "memory text: groundedness is the share in the source")
    check(ArisMemoryText.isSecret("내 비밀번호는 hunter2") && ArisMemoryText.isSecret("카드 1234-5678-9012-3456") && ArisMemoryText.isSecret("my api key is abc")
          && ArisMemoryText.isSecret("token sk1234567890abcdefghijXYZ"), "memory text: passwords, card numbers and keys are secrets")
    check(!ArisMemoryText.isSecret("엄마 생일은 3월 5일") && !ArisMemoryText.isSecret("I wake up at 7"), "memory text: dates and times aren't secrets")
    check(ArisMemoryKind.guess("커피 좋아함") == .preference && ArisMemoryKind.guess("평일 아침마다 7시에 헬스장 감") == .routine
          && ArisMemoryKind.guess("Aris라는 노치 앱 만들고 있어") == .project && ArisMemoryKind.guess("엄마 이름은 김영희") == .person
          && ArisMemoryKind.guess("올랜도대 컴공 다님") == .fact, "memory text: an untyped line gets its likely kind")
    check(ArisMemoryText.cleaned("  커피는\n아메리카노.  ") == "커피는 아메리카노" && ArisMemoryText.cleaned(String(repeating: "가", count: 300)).count == ArisMemoryText.maxLength,
          "memory text: one trimmed line, cut to the limit")
    check(!ArisMemoryRecall.fillerGrams.isEmpty && !ArisMemoryText.latinStopwords.isEmpty, "memory text: the word lists load")
}

private func memoryLearningGateTests() {
    func may(fromApp: Bool = true, task: Bool = false, untrusted: Bool = false, outside: Bool = false, screen: Bool = false, handsFree: Bool = false,
             images: Bool = false, screenText: Bool = false, tainted: Bool = false) -> Bool {
        ArisMemoryLearning.mayLearn(fromApp: fromApp, task: task, untrusted: untrusted, outsideConversation: outside, screenSeen: screen,
                                    handsFree: handsFree, images: images, screenText: screenText, tainted: tainted)
    }
    check(may(), "memory gate: the user's clean turn from the app learns")
    check(!may(tainted: true), "memory gate: a turn whose brain read outside text never learns")
    check(!may(outside: true), "memory gate: a conversation that took in outside text never learns")
    check(!may(untrusted: true), "memory gate: model-written or flagged text never learns")
    check(!may(screen: true) && !may(images: true) && !may(screenText: true), "memory gate: the screen in any form never learns")
    check(!may(handsFree: true), "memory gate: a hands-free turn (anyone's words) never learns")
    check(!may(fromApp: false), "memory gate: a caller other than the Aris app never learns")
    check(!may(task: true), "memory gate: a background task never learns")
    let remember = ArisMemoryIntent.remember("커피는 라떼"), profile = ArisMemoryIntent.profile
    check(ArisMemoryLearning.answersLocally(remember, fromApp: true, handsFree: false, images: false, clean: true), "memory gate: 기억해 on a clean turn is answered here")
    // QA BUG-7 (the owner's ruling): their own parsed 기억해 is their words, so it is answered here after outside text too; other
    // writes (잊어) still go to the gated brain.
    check(ArisMemoryLearning.answersLocally(remember, fromApp: true, handsFree: false, images: false, clean: false)
          && !ArisMemoryLearning.answersLocally(.forget("커피"), fromApp: true, handsFree: false, images: false, clean: false),
          "memory gate: the user's own 기억해 after outside text is answered here; 잊어 goes to the gated brain")
    check(ArisMemoryLearning.answersLocally(profile, fromApp: true, handsFree: false, images: false, clean: false), "memory gate: reading memory back needs no clean turn")
    check(!ArisMemoryLearning.answersLocally(profile, fromApp: true, handsFree: true, images: false, clean: false)
          && !ArisMemoryLearning.answersLocally(profile, fromApp: false, handsFree: false, images: false, clean: true),
          "memory gate: hands-free or another caller never hears the user's memories read out")
}

private func memoryExtractionFilterTests() {
    let said = "나 다음 주부터 올랜도대 컴공 수업 들어. 그리고 커피는 늘 아이스 아메리카노로 해줘"
    check(ArisMemoryLearning.worthTrying(said) && ArisMemoryLearning.worthTrying("I usually go to the gym at 7am"),
          "memory extract: self-statements are worth a try")
    check(!ArisMemoryLearning.worthTrying("내일 날씨 어때?") && !ArisMemoryLearning.worthTrying("이 메일 요약해줘") && !ArisMemoryLearning.worthTrying("타이머 5분"),
          "memory extract: plain requests skip the model")
    // What the on-device model really gave for these words (2026-11-05): two good, one duplicate, one invented.
    let picked = [candidate("커피는 늘 아이스 아메리카노로 해줘", .preference, subject: "커피"), candidate("올랜도대 컴공 수업", .fact, subject: "학교"),
                  candidate("커피는 늘 아이스 아메리카노로 해줘", .routine, subject: "커피"), candidate("카페를 선호함", .preference, subject: "카페"),
                  candidate("학교에서 공부해요", .fact)]
    let kept = ArisMemoryLearning.accepted(picked, words: said)
    check(kept.count == 2 && kept[0].text.hasPrefix("커피는") && kept[1].text == "올랜도대 컴공 수업", "memory extract: only the user's words, each once (\(kept.map(\.text)))")
    check(kept[0].subject == "커피" && kept[1].subject.isEmpty, "memory extract: a subject the user didn't say is dropped")
    check(kept.allSatisfy { $0.confidence <= ArisMemoryStore.learnedConfidence }, "memory extract: picked-out memories start below said ones")
    // An answer's or a tool's words are never the user's: the same filter drops them.
    check(ArisMemoryLearning.accepted([candidate("서울은 내일 비가 와요")], words: "나 서울 살아. 내일 날씨 알려줘").isEmpty,
          "memory extract: words from the answer (not said) are dropped")
    check(ArisMemoryLearning.accepted([candidate("내 비밀번호는 hunter2")], words: "내 비밀번호는 hunter2").isEmpty, "memory extract: secrets are dropped")
    let many = ["나는 사과 좋아해", "우리 집 고양이는 보리", "평일 아침마다 수영해", "올랜도대 다녀", "민지는 내 동생"].map { candidate($0) }
    check(ArisMemoryLearning.accepted(many, words: many.map(\.text).joined(separator: ". ")).count == 3, "memory extract: at most three per turn")
    // Rules, without the on-device model.
    let rules = ArisMemoryLearning.ruleCandidates(said)
    check(rules.count == 2 && rules.contains { $0.kind == .preference && $0.subject == "커피" }, "memory rules: a fact and a standing preference (\(rules.map(\.text)))")
    check(ArisMemoryLearning.ruleCandidates("내가 좋아하는 노래 틀어줘").isEmpty && ArisMemoryLearning.ruleCandidates("내 일정 뭐 있어?").isEmpty,
          "memory rules: requests and questions are no memories")
    check(ArisMemoryLearning.ruleCandidates("I usually go to the gym at 7am on weekdays").first?.kind == .routine, "memory rules: an English routine")
}

private func memoryMergeTests() {
    let now = Date()
    let coffee = record("커피는 아이스 아메리카노", .preference, subject: "커피", id: "c", now: now)
    let cat = record("고양이 이름은 보리", .fact, subject: "고양이", id: "b", now: now)
    check(ArisMemoryMerge.plan(candidate("커피는 아이스 아메리카노!", .preference), existing: [coffee, cat]) == .duplicate("c"), "memory merge: said again is a duplicate")
    check(ArisMemoryMerge.plan(candidate("커피는 따뜻한 라떼", .preference, subject: "커피"), existing: [coffee, cat]) == .insert,
          "memory merge: the same subject said quite differently is a second memory (both can be true)")
    check(ArisMemoryMerge.plan(candidate("커피는 아이스 아메리카노 샷 두 번 추가로", .preference, subject: "커피"), existing: [coffee, cat]) == .update("c"),
          "memory merge: the same subject said alike updates")
    let likes = record("나는 커피 좋아해", .preference, id: "likes", now: now)
    check(ArisMemoryMerge.plan(candidate("나는 커피 안 좋아해", .preference), existing: [likes]) == .insert
          && ArisMemoryMerge.plan(candidate("I don't like coffee", .preference), existing: [record("I like coffee", .preference, now: now)]) == .insert,
          "memory merge: a no never merges with a yes")
    check(ArisMemoryMerge.plan(candidate("커피는 요즘도 아이스 아메리카노 큰 걸로", .preference), existing: [coffee]) == .update("c"),
          "memory merge: a close rewording of the same kind updates")
    check(ArisMemoryMerge.plan(candidate("동생은 민지", .person, subject: "민지"), existing: [coffee, cat]) == .insert, "memory merge: something new is inserted")
}

private func memoryRecallTests() {
    let now = Date()
    let mom = record("엄마는 꽃을 좋아해", .person, subject: "엄마", confidence: 1, id: "mom", now: now)
    let coffee = record("커피는 아이스 아메리카노", .preference, subject: "커피", confidence: 0.6, id: "coffee", now: now)
    let gym = record("평일 아침 7시에 헬스장", .routine, confidence: 0.6, id: "gym", now: now)
    let oldMom = record("엄마 생신은 3월 5일", .person, subject: "엄마", confidence: 0.6, daysAgo: 200, id: "old", now: now)
    let picked = ArisMemoryRecall.pick([coffee, gym, oldMom, mom], for: "엄마한테 뭐 사드릴까?", now: now)
    check(picked.relevant.map(\.id) == ["mom", "old"], "memory recall: what's said picks its memories, newer and surer first (\(picked.relevant.map(\.id)))")
    check(!picked.all.contains { $0.id == "gym" }, "memory recall: unrelated low-confidence memories stay out")
    let none = ArisMemoryRecall.pick([coffee, gym], for: "타이머 5분", now: now)
    check(none.all.isEmpty && ArisMemoryRecall.block(none) == nil, "memory recall: nothing relevant and no core: no memory block")
    let core = ArisMemoryRecall.pick([mom, coffee, gym], for: "타이머 5분", now: now)
    check(core.relevant.isEmpty && core.core.map(\.id) == ["mom"], "memory recall: the surest facts about the user come anyway, not counted as used")
    let crowd = (1...40).map { record("엄마 이야기 \($0)번째 아주 긴 문장입니다 정말로 길게 써 볼게요", .person, confidence: 0.5, id: "m\($0)", now: now) }
    let budgeted = ArisMemoryRecall.pick(crowd, for: "엄마", now: now)
    check(budgeted.relevant.count == ArisMemoryRecall.limit, "memory recall: at most \(ArisMemoryRecall.limit) relevant per turn")
    check(ArisMemoryText.tokenEstimate(ArisMemoryRecall.block(budgeted) ?? "") <= ArisMemoryRecall.budget + 10, "memory recall: the block stays inside its token budget")
    check(ArisMemoryRecall.line(mom).hasPrefix("- [사람] 엄마는 꽃을 좋아해 ("), "memory recall: a line names the kind and the day")
    check(ArisMemoryRecall.matching([mom, coffee, oldMom], words: "엄마").map(\.id).sorted() == ["mom", "old"], "memory recall: matching finds by subject or text")
}

private func memoryStoreTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let now = Date()
    guard case .added(let first) = store.remember(candidate("커피는 아이스 아메리카노", .preference, subject: "커피"), source: .said, turnAt: now) else {
        return check(false, "memory store: the first memory is added")
    }
    check(store.count() == 1 && store.all().first?.text == "커피는 아이스 아메리카노", "memory store: a memory is written and read back")
    var info = stat()
    check(stat(store.file.path, &info) == 0 && info.st_mode & 0o777 == 0o600, "memory store: memory.sqlite is 0600")
    if case .duplicate(let again) = store.remember(candidate("커피는 아이스 아메리카노", .preference, confidence: 0.6), source: .learned, turnAt: now) {
        check(again.id == first.id && store.count() == 1, "memory store: said again stays one memory")
    } else { check(false, "memory store: a repeat is a duplicate") }
    check(first.confidence == ArisMemoryStore.saidConfidence && first.confidence < 0.8, "memory store: 기억해 starts below the core until confirmed")
    if case .duplicate(let again) = store.remember(candidate("커피는 아이스 아메리카노", .preference), source: .said, turnAt: now) {
        check(again.confidence >= ArisMemoryStore.repeatedConfidence, "memory store: said a second time, it is confirmed")
    } else { check(false, "memory store: said again is a duplicate") }
    if case .updated(let changed, let was) = store.remember(candidate("커피는 아이스 아메리카노 샷 두 번 추가로", .preference, subject: "커피", confidence: 0.6),
                                                            source: .learned, turnAt: now) {
        check(changed.id == first.id && was == "커피는 아이스 아메리카노" && changed.source == .learned && changed.confidence == 0.6,
              "memory store: a learned update takes its new source and confidence")
    } else { check(false, "memory store: a new wording updates") }
    check(store.remember(candidate("내 비밀번호는 hunter2"), source: .said, turnAt: now) == .secret && store.count() == 1, "memory store: secrets are refused")
    _ = store.remember(candidate("고양이 이름은 보리", subject: "고양이"), source: .tool, turnAt: now)
    store.markUsed([first.id], at: now)
    check(store.all().first { $0.id == first.id }?.useCount == 1, "memory store: use is counted")
    check(store.matching("고양이").count == 1 && store.delete(ids: store.matching("고양이").map(\.id)).count == 1 && store.count() == 1,
          "memory store: forget removes what contains the words")
    if case .added(let tool) = store.remember(candidate("평일 아침마다 수영 감", confidence: 1), source: .tool, turnAt: now) {
        check(tool.confidence <= ArisMemoryStore.toolConfidence, "memory store: a tool-written memory starts at 0.7 or less")
        check(store.confirm(id: tool.id) && store.all().first { $0.id == tool.id }?.confidence == 1, "memory store: 확인 makes it sure")
        _ = store.delete(id: tool.id)
    } else { check(false, "memory store: a tool memory is added") }
    // A deleted memory leaves no copy in the file or the write-ahead log.
    let marker = "고유표지 ZQXJMARKER77"
    if case .added(let doomed) = store.remember(candidate(marker), source: .said, turnAt: now) {
        _ = store.delete(id: doomed.id)
        let bytes = ((try? Data(contentsOf: store.file)) ?? Data()) + ((try? Data(contentsOf: URL(fileURLWithPath: store.file.path + "-wal"))) ?? Data())
        check(bytes.range(of: Data("ZQXJMARKER77".utf8)) == nil, "memory store: deleted text is gone from memory.sqlite and its log")
    } else { check(false, "memory store: the marker is added") }
    var folderInfo = stat()
    check(stat(folder.path, &folderInfo) == 0 && folderInfo.st_mode & 0o777 == 0o700, "memory store: the folder is 0700")
    check(store.delete(id: first.id) && store.count() == 0 && !store.delete(id: first.id), "memory store: delete one, once")
    check(store.learnsOnItsOwn, "memory store: learning on its own is on by default")
    store.learnsOnItsOwn = false
    check(!ArisMemoryStore.at(folder).learnsOnItsOwn, "memory store: the switch is kept")
    store.learnsOnItsOwn = true
    // Day notes and summaries
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let yesterday = now.addingTimeInterval(-86_400)
    store.addNote("Aris 메모리 기능 테스트 짜는 중", at: yesterday, calendar: calendar)
    store.addNote("ok", at: yesterday, calendar: calendar)
    let day = ArisMemoryText.day(yesterday, calendar: calendar)
    check(store.notes(day: day) == ["Aris 메모리 기능 테스트 짜는 중"], "memory store: day notes keep real requests only")
    check(store.daysToSummarize(before: ArisMemoryText.day(now, calendar: calendar)) == [day], "memory store: an ended day waits for its summary")
    store.setSummary("어제는 Aris 메모리 기능 테스트를 짰어요.", day: day)
    check(store.summary(day: day) != nil && store.daysToSummarize(before: ArisMemoryText.day(now, calendar: calendar)).isEmpty, "memory store: a summary is kept once")
    // Capacity: learned ones go first.
    let busy = ArisMemoryStore.at(memoryFolder())
    defer { try? FileManager.default.removeItem(at: busy.folder) }
    _ = busy.remember(candidate("엄마 생일은 3월 5일", .person, subject: "엄마"), source: .said, turnAt: now)
    // Distinct made-up words, so none merges with another.
    func word(_ n: Int) -> String { String((0..<3).map { Character(UnicodeScalar(97 + (n / Int(pow(26.0, Double($0)))) % 26)!) }) }
    for i in 0..<ArisMemoryStore.capacity {
        _ = busy.remember(candidate("likes \(word(2 * i)) \(word(2 * i + 1))", .fact), source: .learned, turnAt: now)
    }
    check(busy.count() == ArisMemoryStore.capacity && busy.all().contains { $0.text.hasPrefix("엄마 생일") }, "memory store: past capacity a learned memory goes, never a said one")
    // A link where the file should be: memory is off, nothing followed.
    let trap = memoryFolder()
    defer { try? FileManager.default.removeItem(at: trap) }
    try? FileManager.default.createSymbolicLink(at: trap.appendingPathComponent("memory.sqlite"), withDestinationURL: folder.appendingPathComponent("elsewhere"))
    check(ArisMemoryStore.at(trap).remember(candidate("x 좋아"), source: .said, turnAt: now) == .failed, "memory store: never opened through a link")
    // deleteAll
    check(store.deleteAll() && store.count() == 0 && store.notes(day: day).isEmpty && store.summary(day: day) == nil, "memory store: delete all empties everything")
}

private func memoryImportTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let backup = folder.appendingPathComponent("memory.md")
    try? "- 커피 좋아함 (2026-11-01)\n- 고양이 이름은 보리 (2026-11-02)\n- 커피 좋아함 (2026-11-03)\n\n".write(to: backup, atomically: true, encoding: .utf8)
    let store = ArisMemoryStore.at(folder)
    check(store.importBackupIfNeeded() == 2 && store.count() == 2, "memory import: memory.md's facts come in once each")
    let coffee = store.all().first { $0.text == "커피 좋아함" }
    check(coffee?.kind == .preference && coffee?.source == .imported && ArisMemoryText.day(coffee?.turnAt ?? Date()).hasPrefix("2026-11-0")
          && (coffee?.confidence ?? 1) <= ArisMemoryStore.toolConfidence,
          "memory import: typed, marked imported, dated from the file")
    check(store.importBackupIfNeeded() == 0 && store.count() == 2, "memory import: only once")
    check(FileManager.default.fileExists(atPath: backup.path), "memory import: memory.md stays as the backup")
    _ = store.remember(candidate("고양이 이름은 보리야 귀여워"), source: .said, turnAt: Date())
    if let cat = store.all().first(where: { $0.text.contains("보리") }) {
        check(cat.text == "고양이 이름은 보리야 귀여워", "memory import: an imported memory can be reworded")
        _ = store.delete(id: cat.id)
    }
    check((try? String(contentsOf: backup, encoding: .utf8))?.contains("보리") == false, "memory import: deleting a reworded memory still drops its backup line")
    check(store.exportText().contains("- 커피 좋아함 (2026-11-0"), "memory import: export keeps memory.md's line format")
    check(store.deleteAll() && !FileManager.default.fileExists(atPath: backup.path), "memory import: delete all removes the backup")
    check(ArisMemoryStore.backupFacts("- a (2026-01-02)\nb\n- \n").map(\.0) == ["a", "b"], "memory import: lines with and without dates")
    // A memory.md that is a link is neither read nor marked done.
    let linked = memoryFolder()
    defer { try? FileManager.default.removeItem(at: linked) }
    let elsewhere = memoryFolder()
    defer { try? FileManager.default.removeItem(at: elsewhere) }
    try? "- 남의 파일 내용 (2026-11-01)\n".write(to: elsewhere.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
    try? FileManager.default.createSymbolicLink(at: linked.appendingPathComponent("memory.md"), withDestinationURL: elsewhere.appendingPathComponent("x.md"))
    let linkedStore = ArisMemoryStore.at(linked)
    check(linkedStore.importBackupIfNeeded() == 0 && linkedStore.count() == 0, "memory import: a linked memory.md is never read")
    try? FileManager.default.removeItem(at: linked.appendingPathComponent("memory.md"))
    try? "- 진짜 기억 (2026-11-01)\n".write(to: linked.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
    check(linkedStore.importBackupIfNeeded() == 1, "memory import: ... and not marked done, so the real file comes in later")
}

private func memoryIntentTests() {
    let cases: [(String, ArisMemoryIntent?)] = [
        ("커피는 아이스 아메리카노라는 거 기억해", .remember("커피는 아이스 아메리카노")),
        ("내 생일은 3월 5일이야 기억해 줘", .remember("내 생일은 3월 5일이야")),
        ("기억해 둬, 민지는 내 동생이야", .remember("민지는 내 동생이야")),
        ("이거 기억해", nil),
        ("내 생일 기억해?", .recall("내 생일")),
        ("커피 얘기 잊어", .forget("커피")),
        ("헬스장 잊어줘", .forget("헬스장")),
        ("다 잊어", .forgetAll),
        ("내가 엄마 생일 뭐라고 했지?", .recall("엄마 생일")),
        ("엄마에 대해 내가 뭐라고 했더라", .recall("엄마")),
        ("내가 뭐라고 했지?", .recall(nil)),
        ("나에 대해 뭐 알아?", .profile),
        ("뭘 기억하고 있어?", .profile),
        ("어제 뭐 했지?", .day(-1)),
        ("오늘 뭐 했지", .day(0)),
        ("오늘 뭐 했으면 좋겠어?", nil),
        ("remember that I'm vegetarian", .remember("I'm vegetarian")),
        ("remember to call mom", nil),
        ("forget about the gym", .forget("the gym")),
        ("forget everything", .forgetAll),
        ("what did I tell you about my mom?", .recall("my mom")),
        ("what do you know about me?", .profile),
        ("what did I do yesterday?", .day(-1)),
        ("타이머 5분 맞춰줘", nil),
        ("이 페이지에 나온 주소 기억해", nil),
        ("그 메일 내용 기억해 줘", nil),
        ("자전거 비밀번호는 아니고 자전거 색은 빨강이라는 거 기억해", .remember("자전거 비밀번호는 아니고 자전거 색은 빨강")),
        ("꼭 내 자전거 기억해 둬", .remember("내 자전거")),
        ("remember that I'm vegetarian, please", .remember("I'm vegetarian")),
        ("remember my birthday?", .recall("my birthday")),
        ("do you remember my sister's name?", .recall("my sister's name")),
        ("remember this", nil),
        ("내일 날씨 어때?", nil),
    ]
    for (said, wanted) in cases {
        let got = ArisMemoryIntent.parse(said)
        check(got == wanted, "memory intent: \"\(said)\" -> \(wanted.map { "\($0)" } ?? "nil") (got \(got.map { "\($0)" } ?? "nil"))")
    }
    check(ArisMemoryIntent.yesOrNo("응") == true && ArisMemoryIntent.yesOrNo("아니") == false && ArisMemoryIntent.yesOrNo("엄마 생일") == nil,
          "memory intent: a plain yes or no")
    check(ArisMemoryIntent.remember("x").writes && ArisMemoryIntent.forget("x").writes && !ArisMemoryIntent.profile.writes && !ArisMemoryIntent.day(-1).writes,
          "memory intent: only remember and forget write")
}

private func memoryCuratorTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    var asked: [String] = []
    let model: (String) -> [ArisMemoryCandidate]? = { words in
        asked.append(words)
        return [candidate("커피는 늘 아이스 아메리카노로 해줘", .preference, subject: "커피", confidence: 0.7), candidate("카페를 선호함", .preference)]
    }
    let curator = ArisMemoryCurator(store: store, extract: model, summarize: { _ in nil })
    let now = Date()
    let outcomes = curator.learnNow(from: "커피는 늘 아이스 아메리카노로 해줘", at: now)
    check(outcomes.count == 1 && store.count() == 1 && store.all().first?.source == .learned, "memory curator: learns the grounded pick only")
    _ = curator.learnNow(from: "타이머 5분 맞춰줘", at: now)
    check(asked.count == 1, "memory curator: a plain request never reaches the model")
    _ = curator.learnNow(from: "커피는 늘 아이스 아메리카노로 해줘", at: now)
    check(store.count() == 1, "memory curator: learning the same again piles nothing up")
    store.learnsOnItsOwn = false
    check(curator.learnNow(from: "나는 고양이 좋아해", at: now).isEmpty && store.count() == 1, "memory curator: with 자동으로 기억하기 off nothing is learned")
    store.learnsOnItsOwn = true
    let rulesOnly = ArisMemoryCurator(store: store, extract: { _ in nil }, summarize: { _ in nil })
    _ = rulesOnly.learnNow(from: "나는 고양이 좋아해", at: now)
    check(store.all().contains { $0.text == "나는 고양이 좋아해" }, "memory curator: without the model the rules pick")
    // Context
    curator.refresh()
    curator.drain()
    let block = curator.context(for: "커피 한 잔 주문해줘", eligible: true, now: now) ?? ""
    curator.drain()
    check(block.contains("아이스 아메리카노") && store.all().first { $0.text.contains("아메리카노") }?.useCount == 1, "memory curator: context brings the relevant memory and marks it used")
    // Spoken to
    check(curator.answer(.remember("엄마 생일은 3월 5일"), said: "엄마 생일은 3월 5일이라는 거 기억해")?.hasPrefix("기억할게요") == true
          && store.all().first { $0.text.contains("엄마 생일") }?.source == .said, "memory curator: 기억해 writes the user's words as said")
    check(curator.answer(.recall("엄마"), said: "내가 엄마 뭐라고 했지")?.contains("3월 5일") == true, "memory curator: recall finds it")
    check(curator.answer(.recall("우주선"), said: "내가 우주선 뭐라고 했지") == nil, "memory curator: recall with nothing found goes to the brain")
    check(curator.answer(.profile, said: "나에 대해 뭐 알아")?.contains("가지를 기억하고 있어요") == true, "memory curator: profile lists by kind")
    check(curator.answer(.forget("엄마"), said: "엄마 잊어")?.hasPrefix("잊었어요") == true && !store.all().contains { $0.text.contains("엄마") }, "memory curator: forget")
    check(curator.answer(.forgetAll, said: "다 잊어")?.contains("설정") == true && store.count() > 0, "memory curator: 다 잊어 points to the settings, deletes nothing")
    check(curator.answer(.remember("내 비밀번호는 hunter2"), said: "내 비밀번호는 hunter2라는 거 기억해")?.contains("기억에 넣지 않았어요") == true, "memory curator: secrets are refused aloud, with why (HANDOVERS C: the same line the tool and the learning pass give)")
    // Day summary: a fixed clock and calendar (noon UTC, far from midnight), a store of its own, and each curator's
    // queued roll-up drained before the next step, so nothing depends on the wall clock or on timing.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
    let dayFolder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: dayFolder) }
    let dayStore = ArisMemoryStore.at(dayFolder)
    let dayCurator = ArisMemoryCurator(store: dayStore, calendar: calendar, clock: { noon }, extract: { _ in nil }, summarize: { _ in nil })
    let yesterday = noon.addingTimeInterval(-86_400)
    _ = dayCurator.learnNow(from: "Aris 메모리 설정 화면 만들기", at: yesterday)
    _ = dayCurator.learnNow(from: "SQLite 저장소 테스트 돌려줘", at: yesterday)
    let answer = dayCurator.answer(.day(-1), said: "어제 뭐 했지") ?? ""
    dayCurator.drain()
    check(answer.contains("2번") && answer.contains("메모리") && !answer.contains("“") && !answer.contains("메모리 설정 화면 만들기"),
          "memory curator: 어제 뭐 했지 answers from yesterday's notes, never quoting them (\(answer))")
    let summaryFolder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: summaryFolder) }
    let summarized = ArisMemoryCurator(store: ArisMemoryStore.at(summaryFolder), calendar: calendar, clock: { noon }, extract: { _ in nil },
                                       summarize: { _ in "어제는 메모리 기능을 만들었어요." })
    _ = summarized.learnNow(from: "메모리 기능 마무리", at: noon.addingTimeInterval(-2 * 86_400))
    summarized.rollUp(now: noon)
    check(summarized.answer(.day(-2), said: "그제 뭐 했지")?.hasSuffix("어제는 메모리 기능을 만들었어요.") == true,
          "memory curator: a day's summary comes from the model when there is one")
    let later = ArisMemoryCurator(store: dayStore, calendar: calendar, clock: { noon.addingTimeInterval(10 * 86_400) }, extract: { _ in nil }, summarize: { _ in nil })
    check(later.answer(.day(-1), said: "어제 뭐 했지")?.contains("없어요") == true, "memory curator: a day with no notes says so")
    later.drain()
}

private func memoryRouteTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    _ = store.remember(candidate("커피는 아이스 아메리카노", .preference), source: .said, turnAt: Date())
    func call(_ object: [String: Any]) -> (Int, [String: Any], String?) {
        let reply = ArisMemoryRoute.handle(object, store: store)
        return (reply.status, (try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any]) ?? [:], reply.audit)
    }
    let list = call(["op": "list"])
    let rows = list.1["memories"] as? [[String: Any]] ?? []
    check(list.0 == 200 && rows.count == 1 && rows[0]["kind"] as? String == "preference" && list.1["auto"] as? Bool == true, "memory route: list gives the rows and the switch")
    check(call(["op": "nope"]).0 == 400 && call(["op": "delete"]).0 == 400 && call(["op": "auto", "on": "yes"]).0 == 400, "memory route: bad requests are 400")
    check(call(["op": "auto", "on": false]).1["auto"] as? Bool == false && !store.learnsOnItsOwn, "memory route: the switch turns off")
    check(call(["op": "clear"]).0 == 400 && store.count() == 1, "memory route: clear needs its word")
    let id = rows.first?["id"] as? String ?? ""
    let deleted = call(["op": "delete", "id": id])
    check(deleted.1["removed"] as? Bool == true && store.count() == 0 && deleted.2?.contains("아메리카노") == false, "memory route: delete one; the audit never carries its words")
    _ = store.remember(candidate("고양이 이름은 보리"), source: .said, turnAt: Date())
    check(call(["op": "clear", "confirm": ArisMemoryRoute.clearWord]).1["cleared"] as? Bool == true && store.count() == 0, "memory route: clear all")
}

/// QA BUG-59: the learner saved "내가 제일 좋아하는 과일이 뭐였지?" as the user's preference; after the real fact was forgotten,
/// the next ask read the question back as what Aris remembered. And forgetting "…에 대한 기억 전부" matched nothing.
private func memoryQuestionTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let model: (String) -> [ArisMemoryCandidate]? = { words in [candidate(words, .preference, subject: "내가 제일 좋아하는 과일", confidence: 0.7)] }
    let curator = ArisMemoryCurator(store: store, extract: model, summarize: { _ in nil })
    let now = Date()
    let question = "내가 제일 좋아하는 과일이 뭐였지?"
    // 1. The question is asked: nothing is learned from it, whatever the model picked out.
    check(curator.learnNow(from: question, at: now).isEmpty && store.count() == 0, "BUG-59 (1): a question is never learned as a fact")
    check(ArisMemoryLearning.asks(question) && ArisMemoryLearning.asks("내가 제일 좋아하는 과일이 뭐였지") && ArisMemoryLearning.asks("what's my favourite fruit")
          && !ArisMemoryLearning.asks("나는 큐에이망고를 제일 좋아해") && !ArisMemoryLearning.asks("우리 언니") && !ArisMemoryLearning.asks("내 말이 맞아"),
          "BUG-59: a question is told from a fact, Korean and English")
    check(ArisMemoryLearning.accepted([candidate(question, .preference, subject: "내가 제일 좋아하는 과일")], words: question).isEmpty
          && ArisMemoryLearning.accepted([candidate("내가 제일 좋아하는 과일", .preference, subject: "내가 제일 좋아하는 과일")], words: "내가 제일 좋아하는 과일").isEmpty,
          "BUG-59: a learned value that is a question, or only its own key, is refused")
    // 2. The real fact, and the junk row an earlier learner left.
    _ = store.remember(candidate("나는 큐에이망고를 제일 좋아해", .preference, subject: "과일"), source: .said, turnAt: now, now: now)
    _ = store.remember(candidate(question, .preference, subject: "내가 제일 좋아하는 과일", confidence: 0.7), source: .learned, turnAt: now, now: now)
    // 3. "큐에이망고 얘기 잊어 줘" forgets the real one.
    guard case .forget(let mango)? = ArisMemoryIntent.parse("큐에이망고 얘기 잊어 줘") else { return check(false, "BUG-59 (3): the forget is understood") }
    _ = curator.answer(.forget(mango), said: "큐에이망고 얘기 잊어 줘", now: now)
    check(!store.all().contains { $0.text.contains("큐에이망고") }, "BUG-59 (3): the real fact is forgotten")
    // 4. Asked again: the stored question is never read back as what Aris remembers.
    // (The question goes to the brain, which gets Aris's memory lines: the place the junk was read back from.)
    curator.refresh()
    Thread.sleep(forTimeInterval: 0.2)
    let reply = ArisMemoryIntent.parse(question).flatMap { curator.answer($0, said: question, now: now) }
    check(!(reply ?? "").contains("뭐였지") && !(curator.context(for: question, eligible: true, now: now) ?? "").contains("뭐였지"),
          "BUG-59 (4): a stored question is never said or given to a brain as a memory: \(reply ?? "nil (the brain answers, with no junk in its memory)")")
    // The cleanup: the wrapper words come off the topic, and the junk row is found.
    check(ArisMemoryIntent.stripTopic("좋아하는 과일에 대한 기억 전부") == "좋아하는 과일" && ArisMemoryIntent.stripTopic("everything about mango") == "mango"
          && ArisMemoryIntent.stripTopic("바다") == "바다" && ArisMemoryIntent.stripTopic("망고 얘기") == "망고",
          "BUG-59: forget's topic loses its wrapper words, never a word's own ending")
    guard case .forget(let wrapped)? = ArisMemoryIntent.parse("좋아하는 과일에 대한 기억 전부 잊어 줘") else { return check(false, "BUG-59: the wrapped forget is understood") }
    let forgot = curator.answer(.forget(wrapped), said: "좋아하는 과일에 대한 기억 전부 잊어 줘", now: now) ?? ""
    check(wrapped == "좋아하는 과일" && store.count() == 0 && !forgot.contains("기억하는 건 없어요"), "BUG-59: forgetting by topic finds the row by its key: \(forgot)")
    // Several rows: listed on the confirm card, never deleted at once.
    _ = store.remember(candidate("나는 사과를 좋아해", .preference, subject: "좋아하는 과일"), source: .said, turnAt: now, now: now)
    _ = store.remember(candidate("나는 배도 좋아해", .preference, subject: "좋아하는 과일"), source: .said, turnAt: now, now: now)
    let several = curator.forgetAsks("좋아하는 과일") ?? []
    let card = ArisMemoryAnswer.forgetCard(several, words: "좋아하는 과일", korean: true)
    check(several.count == 2 && card.title == "기억 지우기" && card.allow == "잊기" && card.detail.contains("‘좋아하는 과일’ 기억 2개를 잊을까요?")
          && card.detail.contains("사과") && card.detail.contains("배도"),
          "BUG-59: several matches go on a confirm card that lists each one: \(card.detail.replacingOccurrences(of: "\n", with: " / "))")
    _ = curator.answer(.forget("좋아하는 과일"), said: "좋아하는 과일 잊어 줘", now: now)
    check(store.count() == 2, "BUG-59: several matches are asked about, never deleted in bulk")
    check(ArisMemoryAnswer.kept(unanswered: false, korean: true) == "그대로 둘게요." && ArisMemoryAnswer.kept(unanswered: true, korean: true).contains("답이 없어서"),
          "BUG-59: a no, or no answer, on the card leaves them")
    let gone = curator.forget(several, korean: true)
    check(store.count() == 0 && gone.hasPrefix("잊었어요"), "BUG-59: the user's yes on the card removes exactly those: \(gone)")
    memoryLooseForgetTests()
}

/// QA BUG-59, the seen case: "좋아하는 과일에 대한 기억 전부 잊어 줘" answered "…기억하는 건 없어요" although the memory was
/// there (kept as "과일 — 나는 큐에이망고를 제일 좋아해": the verb said another way). Found by overlap, and asked about first.
private func memoryLooseForgetTests() {
    let folder = memoryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ArisMemoryStore.at(folder)
    let curator = ArisMemoryCurator(store: store, extract: { _ in nil }, summarize: { _ in nil })
    let now = Date()
    _ = store.remember(candidate("나는 큐에이망고를 제일 좋아해", .preference, subject: "과일"), source: .said, turnAt: now, now: now)
    _ = store.remember(candidate("나는 수영을 좋아해", .preference, subject: "운동"), source: .said, turnAt: now, now: now)
    let said = "좋아하는 과일에 대한 기억 전부 잊어 줘"
    guard case .forget(let topic)? = ArisMemoryIntent.parse(said) else { return check(false, "BUG-59: the seen request is a forget") }
    check(topic == "좋아하는 과일" && store.matching(topic).isEmpty && store.overlapping(topic).map(\.subject) == ["과일"],
          "BUG-59: the topic's words find the memory by overlap (좋아하는 finds 좋아해), and only the one about fruit")
    let asked = curator.answer(.forget(topic), said: said, now: now) ?? ""
    check(store.count() == 2 && asked.contains("큐에이망고") && asked.contains("잊을까요") && !asked.contains("기억하는 건 없어요") && !asked.contains("수영"),
          "BUG-59: a memory found only loosely is asked about first, never removed at once: \(asked)")
    check(curator.forgetAsks(topic)?.map(\.subject) == ["과일"] && curator.forgetAsks("큐에이망고") == nil && curator.forgetAsks("바나나") == nil,
          "BUG-59: the card is for several or loosely found memories; one named as said goes at once, and nothing found asks nothing")
    _ = curator.answer(.forget(topic), said: said, now: now)
    guard let yes = curator.pendingIntent(for: "응", now: now) else { return check(false, "BUG-59: a spoken yes answers the question") }
    _ = curator.answer(yes, said: "응", now: now)
    check(store.all().map(\.subject) == ["운동"], "BUG-59: on yes exactly that memory goes; the other stays")
    check(ArisMemoryRecall.overlapping(store.all(), words: "좋아하는 과일").isEmpty && ArisMemoryRecall.overlapping(store.all(), words: "좋아하는 운동").count == 1
          && ArisMemoryRecall.overlapping(store.all(), words: "다").isEmpty,
          "BUG-59: every word of the topic must be in the memory; one shared verb is not enough")
    // The wrappers, in English too; and what counts as a question.
    check(ArisMemoryIntent.parse("forget everything about mango") == .forget("mango") && ArisMemoryIntent.parse("forget about my birthday") == .forget("my birthday")
          && ArisMemoryIntent.parse("망고 얘기 전부 다 잊어 줘") == .forget("망고") && ArisMemoryIntent.parse("전부 잊어 줘") == .forgetAll,
          "BUG-59: “everything about …”, “… 얘기 전부 다” come off the topic; “전부 잊어 줘” alone is still everything")
    check(!ArisMemoryLearning.asks("Do not call me before nine") && !ArisMemoryLearning.asks("내 강아지 이름은 하니") && ArisMemoryLearning.asks("Is my favourite fruit mango")
          && ArisMemoryLearning.asks("내가 좋아하는 과일이 뭐더라"),
          "BUG-59: a plain sentence that only looks like a question is still a fact")
    let told = ArisMemoryRecord(id: "a", kind: .fact, subject: "", text: "what I like most is tea", source: .said, turnAt: now, confidence: 1, createdAt: now, updatedAt: now,
                                lastUsedAt: nil, useCount: 0)
    var learned = told
    learned.source = .learned
    check(ArisMemoryCurator.usable([told, learned]).map(\.source) == [.said], "BUG-59: only a question the learner stored is left out; what the user told Aris to remember stays")
}

