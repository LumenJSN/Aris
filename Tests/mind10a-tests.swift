// Tenth VM run, items 3 and 4 (jv-mind10a): a local rule takes a request only when it accounts for all of it, and a
// local reply is in the language of the request.
//  3. turns.jsonl line 62: "이 문서에 적힌 할 일 미리 알림에 추가해 줘" was taken by the local to-do rule (path "local"),
//     saved as a to-do called "이 문서에 적힌 미리 알림에". The table below is every local rule with what it takes and
//     what it must leave to the model, Korean and English, through the real funnel (funnelBranch).
//  4. turns.jsonl lines 3, 31, 38, 40, 62: Korean requests answered "It's 3:10 AM.", "Volume set to 30.", "Added to
//     your to-dos: …" in the English UI. Every local reply builder, asked in each language under each UI language.

import Foundation

/// One row: the words, the branch that takes them ("brain" and "screen" are the model's), the world they are said in.
private struct Mind10aRow {
    let rule: String
    let said: String
    let branch: String
    var world: FunnelWorld = .plain
}

private let mind10aHits: [Mind10aRow] = [
    // The recorded good hits (turns.jsonl 3, 28, 31, 38, 40).
    .init(rule: "time", said: "지금 몇 시야?", branch: "onMac"),
    .init(rule: "to-do add", said: "내일 우유 사기 할 일에 추가해 줘", branch: "addTodo"),
    .init(rule: "open app", said: "계산기 열어 줘", branch: "onMac"),
    .init(rule: "undo", said: "방금 거 되돌려 줘", branch: "undo"),
    .init(rule: "volume", said: "볼륨 30으로 해 줘", branch: "control"),
    // Each rule, both languages.
    .init(rule: "time", said: "what time is it", branch: "onMac"),
    .init(rule: "date", said: "오늘 며칠이야", branch: "onMac"),
    .init(rule: "date", said: "what's the date today", branch: "onMac"),
    .init(rule: "open app", said: "open Safari", branch: "onMac"),
    .init(rule: "open app", said: "사파리 좀 켜 줘", branch: "onMac"),
    .init(rule: "volume", said: "set the volume to 30", branch: "control"),
    .init(rule: "volume", said: "볼륨 좀 올려 줘", branch: "control"),
    .init(rule: "brightness", said: "밝기 50으로 맞춰 줘", branch: "control"),
    .init(rule: "brightness", said: "set brightness to 50", branch: "control"),
    .init(rule: "timer", said: "5분 타이머 맞춰 줘", branch: "onMac"),
    .init(rule: "timer", said: "set a timer for 5 minutes", branch: "onMac"),
    .init(rule: "timer", said: "타이머 꺼 줘", branch: "onMac"),
    .init(rule: "timer", said: "cancel the timer", branch: "onMac"),
    .init(rule: "timer left", said: "타이머 얼마나 남았어", branch: "timerLeft"),
    .init(rule: "timer left", said: "how much time is left on the timer", branch: "timerLeft"),
    .init(rule: "undo", said: "되돌려 줘", branch: "undo"),
    .init(rule: "undo", said: "undo that", branch: "undo"),
    .init(rule: "to-do add", said: "할 일에 우유 사기 추가해 줘", branch: "addTodo"),
    .init(rule: "to-do add", said: "add buy milk to my to-do list", branch: "addTodo"),
    .init(rule: "to-do add", said: "remind me to call mom tomorrow", branch: "addTodo"),
    .init(rule: "to-do add", said: "이번 주 장보기 할 일에 추가해 줘", branch: "addTodo"),
    .init(rule: "to-do list", said: "할 일 뭐 남았어", branch: "listTodos"),
    .init(rule: "to-do list", said: "what's on my to-do list", branch: "listTodos"),
    .init(rule: "to-do done", said: "우유 사기 다 했어", branch: "finishTodo", world: .todo),
    .init(rule: "to-do done", said: "mark 우유 사기 as done", branch: "finishTodo", world: .todo),
    .init(rule: "music", said: "다음 곡", branch: "media"),
    .init(rule: "music", said: "next song", branch: "media"),
    .init(rule: "music", said: "음악 멈춰 줘", branch: "media"),
    .init(rule: "music", said: "pause the music", branch: "media"),
    .init(rule: "now playing", said: "지금 무슨 노래야?", branch: "whatsPlaying"),
    .init(rule: "now playing", said: "what's playing", branch: "whatsPlaying"),
    .init(rule: "read again", said: "다시 읽어 줘", branch: "readAgain"),
    .init(rule: "read again", said: "read it again", branch: "readAgain"),
    .init(rule: "brief", said: "오늘 브리핑 해 줘", branch: "brief"),
    .init(rule: "brief", said: "give me my morning briefing", branch: "brief"),
    .init(rule: "Aris mute", said: "조용히 해 줘", branch: "onMac"),
    .init(rule: "windows", said: "엑셀 4개 켜서 4등분", branch: "arrange"),
]

/// What no local rule may take: a reference to other content, or meaning left over. All are the model's.
private let mind10aMisses: [Mind10aRow] = [
    // The recorded hijack (turns.jsonl 62) and its family.
    .init(rule: "to-do add", said: "이 문서에 적힌 할 일 미리 알림에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "여기 있는 거 할 일에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "이거 할 일에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "그 보고서 검토 할 일에 넣어 줘", branch: "model"),
    .init(rule: "to-do add", said: "선택한 문장 할 일에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "화면에 보이는 일정 할 일에 넣어 줘", branch: "model"),
    .init(rule: "to-do add", said: "방금 말한 거 미리 알림에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "메일에 나온 마감들 할 일에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "할 일 미리 알림에 추가해 줘", branch: "model"),
    .init(rule: "to-do add", said: "add that to my to-dos", branch: "model"),
    .init(rule: "to-do add", said: "add the tasks in this email to my reminders", branch: "model"),
    .init(rule: "to-do add", said: "add what you just said to my to-do list", branch: "model"),
    .init(rule: "to-do add", said: "remind me to reply to this email", branch: "model"),
    .init(rule: "to-do add", said: "remind me about the meeting mentioned above", branch: "model"),
    .init(rule: "to-do add", said: "add the selected text to my reminders", branch: "model"),
    .init(rule: "to-do add", said: "put everything on this page on my to-do list", branch: "model"),
    .init(rule: "to-do list", said: "이 문서에 적힌 할 일 뭐 남았어", branch: "model"),
    .init(rule: "to-do list", said: "오늘 할 일 목록 메일로 보내 줘", branch: "model"),
    .init(rule: "to-do done", said: "이거 다 했어", branch: "model", world: .todo),
    .init(rule: "to-do done", said: "이 문서에 적힌 거 다 했어", branch: "model", world: .todo),
    .init(rule: "to-do done", said: "mark that as done", branch: "model", world: .todo),
    .init(rule: "time", said: "지금 몇 시인지 이 문서에 적어 줘", branch: "model"),
    .init(rule: "time", said: "what time is it in the document I have open", branch: "model"),
    .init(rule: "date", said: "이 문서에 적힌 날짜가 오늘이야", branch: "model"),
    .init(rule: "date", said: "put today's date in this file", branch: "model"),
    .init(rule: "open app", said: "이 파일 열어 줘", branch: "model"),
    .init(rule: "open app", said: "선택한 파일 열어 줘", branch: "model"),
    .init(rule: "open app", said: "여기 있는 링크 열어 줘", branch: "model"),
    .init(rule: "open app", said: "open it", branch: "model"),
    .init(rule: "open app", said: "open that app", branch: "model"),
    .init(rule: "open app", said: "open the selected file", branch: "model"),
    .init(rule: "open app", said: "open the link on this page", branch: "model"),
    .init(rule: "open app", said: "메모 앱 열고 어제 회의 내용 정리해 줘", branch: "model"),
    .init(rule: "volume", said: "이 영상 볼륨 30으로 해 줘", branch: "model"),
    .init(rule: "volume", said: "이 문서에 적힌 대로 볼륨 맞춰 줘", branch: "model"),
    .init(rule: "volume", said: "set the volume to what it says here", branch: "model"),
    .init(rule: "brightness", said: "이 사진 밝기 올려 줘", branch: "model"),
    .init(rule: "brightness", said: "make this photo brighter", branch: "model"),
    .init(rule: "timer", said: "이 레시피에 적힌 시간만큼 타이머 맞춰 줘", branch: "model"),
    .init(rule: "timer", said: "여기 나온 시간으로 타이머 맞춰 줘", branch: "model"),
    .init(rule: "timer", said: "set a timer for the time written in this recipe", branch: "model"),
    .init(rule: "undo", said: "방금 보낸 메일 취소해", branch: "model"),
    .init(rule: "undo", said: "이 문서에서 방금 지운 문단 되돌려 줘", branch: "model"),
    .init(rule: "undo", said: "undo the last edit in this document", branch: "model"),
    .init(rule: "music", said: "이 영상 멈춰 줘", branch: "model"),
    .init(rule: "music", said: "이 페이지에 있는 노래 틀어 줘", branch: "model"),
    .init(rule: "music", said: "play the song mentioned in this article", branch: "model"),
    .init(rule: "now playing", said: "이 문서에 나온 노래 제목 뭐야", branch: "model"),
    .init(rule: "read again", said: "이 메일 읽어 줘", branch: "model"),
    .init(rule: "read again", said: "read this page to me", branch: "model"),
    .init(rule: "brief", said: "이 문서 브리핑해 줘", branch: "model"),
    .init(rule: "brief", said: "give me a brief of this document", branch: "model"),
    .init(rule: "windows", said: "이 파일들 4개 켜서 4등분", branch: "model"),
]

private final class Mind10aFlag: @unchecked Sendable { var done = false }

private func mind10aRuleTests() {
    let flag = Mind10aFlag()
    Task { @MainActor in
        for row in mind10aHits {
            let found = await funnelBranch(row.said, row.world).branch
            check(found == row.branch, "mind10a 3 hit (\(row.rule)): “\(row.said)” -> \(row.branch) (got \(found))")
        }
        for row in mind10aMisses {
            let found = await funnelBranch(row.said, row.world).branch
            check(["brain", "screen", "background"].contains(found), "mind10a 3 must not hit (\(row.rule)): “\(row.said)” is the model's (got \(found))")
        }
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
    // The recorded turn, at the parser: never a to-do, whoever picked it (the router's guess goes through `guarded` too).
    let recorded = "이 문서에 적힌 할 일 미리 알림에 추가해 줘"
    if case .ask = ArisIntent.parse(recorded) {} else { check(false, "mind10a 3: the recorded hijack is left to the model by the parser") }
    if case .ask = ArisIntent.guarded(.addTodo("문서의 할 일"), said: recorded) {} else { check(false, "mind10a 3: and when the router picks the to-do rule for it") }
    if case .ask = ArisIntent.guarded(.openApp("Safari"), said: "이 페이지에 있는 링크 사파리로 열어 줘") {} else {
        check(false, "mind10a 3: the router's 'open Safari' for a sentence about a page's link is left to the model")
    }
    if case .addTodo(let item) = ArisIntent.guarded(.addTodo("우유 사기"), said: "할 일에 우유 사기 추가해 줘") {
        check(item == "우유 사기", "mind10a 3: a plain add the router picked is still done here")
    } else { check(false, "mind10a 3: a plain add the router picked is still done here") }
}

// MARK: - 4: the language of every local reply

private func mind10aHasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
}

/// Aris's own words of a line: what is the owner's (a title, an app's name, a number's unit he said) is taken out.
private func mind10aOwn(_ line: String, without owned: [String]) -> String {
    owned.reduce(line) { $0.replacingOccurrences(of: $1, with: "") }
}

private func mind10aLanguageTests() {
    // The request decides, under either UI language (the VM's was English).
    let asked: [(said: String, korean: Bool)] = [
        ("지금 몇 시야?", true), ("계산기 열어 줘", true), ("방금 거 되돌려 줘", true), ("볼륨 30으로 해 줘", true), ("이 문서에 적힌 할 일 미리 알림에 추가해 줘", true),
        ("내일 우유 사기 할 일에 추가해 줘", true), ("Safari 열어 줘", true),
        ("what time is it", false), ("open Calculator", false), ("undo that", false), ("set the volume to 30", false), ("add buy milk to my to-do list", false),
    ]
    for uiEnglish in [true, false] {
        for row in asked {
            check(ArisReplyLanguage.korean(request: row.said, uiEnglish: uiEnglish) == row.korean,
                  "mind10a 4: “\(row.said)” is answered in \(row.korean ? "Korean" : "English") with the UI in \(uiEnglish ? "English" : "Korean")")
        }
    }
    // Every local reply builder, in each language: a Korean reply has Hangul, an English one has none (the owner's own
    // title and the app's own name aside).
    let now = Date(timeIntervalSince1970: 1_795_000_000)
    let title = "우유 사기", english = "buy milk"
    for korean in [true, false] {
        let own = korean ? english : title
        var lines: [(String, String)] = []
        let intents: [ArisIntent] = [.tellTime, .tellDate, .openApp("Calculator"), .arrange(app: "Safari", count: 2), .media(.play), .media(.pause), .media(.next),
                                     .media(.previous), .volume(.set(30)), .volume(.up), .volume(.down), .volume(.mute), .brightness(.set(50)), .brightness(.up),
                                     .brightness(.down), .addTodo(own), .finishTodo(own), .timer(seconds: 180, focus: false), .timer(seconds: 1_500, focus: true),
                                     .cancelTimer, .pomodoro, .pauseTimer, .resumeTimer, .addTime(60)]
        for intent in intents { lines.append(("\(intent)", intent.acknowledgement(korean: korean, now: now) ?? "")) }
        for media in [ArisIntent.Media.play, .pause, .next, .previous] { lines.append(("media failed \(media)", media.reply(done: false, korean: korean))) }
        for intent in [ArisIntent.cancelTimer, .pauseTimer, .resumeTimer, .addTime(60)] {
            for (running, paused) in [(false, false), (true, false), (true, true)] {
                if let change = ArisTimerChange.plan(intent, running: running, paused: paused, korean: korean) { lines.append(("timer \(intent) \(running) \(paused)", change.reply)) }
            }
        }
        lines.append(("no timer", ArisLocalReply.noTimer(korean: korean)))
        lines.append(("app not opened", ArisLocalReply.appNotOpened(korean ? "계산기" : "Calculator", korean: korean)))
        lines.append(("to-do no access", ArisLocalReply.todoAdded(.noAccess, korean: korean)))
        lines.append(("to-do demo", ArisLocalReply.todoAdded(.demo, korean: korean)))
        lines.append(("to-do no title", ArisLocalReply.todoAdded(.noTitle, korean: korean)))
        lines.append(("to-dos unread", ArisLocalReply.todosUnread(korean: korean)))
        lines.append(("to-do not ticked", ArisLocalReply.todoNotTicked(own, why: nil, korean: korean)))
        lines.append(("undo unknown", ArisLocalReply.undoUnknown(korean: korean)))
        lines.append(("undo nothing recent", ArisUndoWords.nothingRecent(korean: korean)))
        lines.append(("undo cannot", ArisUndoWords.cannotLine(own, korean: korean)))
        lines.append(("undo failed", ArisUndoWords.failure("", korean: korean)))
        lines.append(("undo done", ArisUndoWords.doneReply("", summary: own, korean: korean)))
        lines.append(("now playing", ArisIntent.nowPlayingLine(title: own, artist: "", playing: true, korean: korean)))
        lines.append(("nothing playing", ArisIntent.nowPlayingLine(title: "", artist: "", playing: false, korean: korean)))
        lines.append(("no answer", ArisTurnWatchdog.line(korean: korean)))
        lines.append(("looking", ArisThinking.lookingLine(korean: korean)))
        lines.append(("on the screen", ArisSpeakable.onScreen(korean: korean)))
        for (name, line) in lines {
            // A way through Settings names the pages as the UI shows them (ArisSettingsPath), whatever the sentence's language.
            let sentence = line.components(separatedBy: "Settings › ").first ?? line
            let words = mind10aOwn(sentence, without: [own, "Calculator", "Safari"])
            check(!line.isEmpty && mind10aHasHangul(words) == korean, "mind10a 4: \(name) in \(korean ? "Korean" : "English") (\(line))")
        }
    }
    // The VM's lines, as they are said now to the same requests.
    check(ArisIntent.volume(.set(30)).acknowledgement(korean: ArisReplyLanguage.korean(request: "볼륨 30으로 해 줘", uiEnglish: true)) == "볼륨 30으로 맞췄어요.",
          "mind10a 4: '볼륨 30으로 해 줘' in the English UI says '볼륨 30으로 맞췄어요.', not 'Volume set to 30.'")
    check(mind10aHasHangul(ArisIntent.tellTime.acknowledgement(korean: ArisReplyLanguage.korean(request: "지금 몇 시야?", uiEnglish: true), now: now) ?? ""),
          "mind10a 4: '지금 몇 시야?' in the English UI is told in Korean, not 'It's 3:10 AM.'")
    check(ArisIntent.volume(.set(30)).acknowledgement(korean: ArisReplyLanguage.korean(request: "set the volume to 30", uiEnglish: false)) == "Volume set to 30.",
          "mind10a 4: and an English request in the Korean UI is answered in English")
    // The turn hands its words over once, and every claim's `korean` comes from them.
    let runs = (try? String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/mind10a-tests.swift", with: "Aris/private/Aris/Routing/ArisController+TurnRuns.swift"), encoding: .utf8)) ?? ""
    check(runs.contains("static var replyKorean: Bool { ArisReplyLanguage.korean(uiEnglish: ArisUIWords.english) }")
            && runs.contains("static var todoKorean: Bool { replyKorean }")
            && runs.contains("ArisReplyLanguage.heard(request.heard?.unmarked ?? request.said)"),
          "mind10a 4: the turn's own words decide replyKorean and todoKorean, set where the claim runs")
    let undo = (try? String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/mind10a-tests.swift", with: "Aris/private/Aris/ArisController+Undo.swift"), encoding: .utf8)) ?? ""
    check(undo.contains("let cardKorean = !ArisUIWords.english") && undo.contains("doubt: doubt, korean: cardKorean)")
            && !undo.contains("ArisUndoWords.card(for: entry, newest: candidates.first, doubt: doubt, korean: korean)"),
          "mind10a 4: the undo's card keeps the UI's language (its buttons are the UI's), the lines said follow the request")
}

func runMind10aTests() {
    mind10aRuleTests()
    mind10aLanguageTests()
}
