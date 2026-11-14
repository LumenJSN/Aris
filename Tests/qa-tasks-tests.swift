// Tests for QA BUG-20 and BUG-21 (QA session on fork 868051ee): a background task's result is shown as Markdown
// (never flattened into one line), never read as "###" or table pipes, saved to a file whenever the user asked for one, and
// the 기록 tab keeps one entry for a handed-out task. Each failed before its change. Called from main.swift; uses its check().
import Foundation

func runQATasksTests() {
    qaTaskResultShownTests()
    qaTaskResultSpokenTests()
    qaTaskFileRequestTests()
    qaTaskSaveTests()
    qaTaskHistoryTests()
}

/// QA's own result: a line to say, then a table under a ### label (shorter than the 250 characters that make a file).
private let qaSquares = """
    1부터 5까지의 제곱을 표로 정리했어요.

    ### 제곱표
    | 수 | 제곱 |
    |---|---|
    | 1 | 1 |
    | 2 | 4 |
    | 3 | 9 |
    | 4 | 16 |
    | 5 | 25 |
    """

private let qaRequest = "QA 테스트로 1부터 5까지 제곱을 표로 정리해서 파일로 저장해 놔"

private func qaSource(_ path: String) -> String {
    let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    return (try? String(contentsOf: tests.appendingPathComponent("../" + path), encoding: .utf8)) ?? ""
}

/// BUG-20a: the notch shows the result as the answer renderer draws it, its line breaks kept end to end.
private func qaTaskResultShownTests() {
    let report = ArisSpeakable.report(qaSquares, korean: true)
    check(report.shown.contains("### 제곱표\n| 수 | 제곱 |\n|---|---|\n| 1 | 1 |"), "BUG-20a: the shown result keeps its line breaks")
    let pieces = ArisAnswerDocument.pieces(from: report.shown)
    let rows = [["1", "1"], ["2", "4"], ["3", "9"], ["4", "16"], ["5", "25"]]
    check(pieces == [.lead("1부터 5까지의 제곱을 표로 정리했어요."), .block(.label("제곱표")), .block(.table(header: ["수", "제곱"], rows: rows))],
          "BUG-20a: the result draws as a lead, a label and a table (answer format A)")
    // The announcement shows what is shown, not what is said (the said text is one flattened line).
    let team = qaSource("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("ArisNoticeRoute.jobDone(title: job.title, shown: report.shown") && team.contains("notify(card, saying: report.spoken, parking: report.shown)"),
          "BUG-20a: a finished job's card and parked answer show report.shown, never the spoken line (notify-card)")
    let inbox = qaSource("Aris/private/Aris/ArisController+Inbox.swift")
    check(inbox.contains("ArisNoticeRoute.inbox(kind: item.kind, title: item.title, shown: report.shown") && inbox.contains("notify(card, saying: said, parking: report.shown)"),
          "BUG-20a: a scheduled job's result shows report.shown too")
    let session = ArisSession.announcing("제곱표", report.shown)
    check(session.reply == report.shown, "BUG-20a: the announced session carries the shown Markdown")
}

/// BUG-20a: speech never reads Markdown syntax; a table gets a short spoken summary.
private func qaTaskResultSpokenTests() {
    let report = ArisSpeakable.report(qaSquares, korean: true)
    check(!report.spoken.contains("#") && !report.spoken.contains("|") && !report.spoken.contains("---"),
          "BUG-20a: speech never reads ###, pipes or a table's divider")
    check(report.spoken.hasPrefix("1부터 5까지의 제곱을 표로 정리했어요."), "BUG-20a: speech starts with the line to say")
    check(report.spoken.contains("제곱표") && report.spoken.contains("표로 띄워 뒀어요") && report.spoken.contains("5줄"),
          "BUG-20a: the table is said as a short summary (its label, its size)")
    check(!report.spoken.contains("16") && !report.spoken.contains("25"), "BUG-20a: the table's cells are never read one by one")
    let english = ArisSpeakable.report("Here are the squares.\n\n## Squares\n| n | n² |\n|---|---|\n| 1 | 1 |\n| 2 | 4 |", korean: false)
    check(english.spoken.contains("Squares.") && english.spoken.contains("table") && english.spoken.contains("2 rows")
          && !english.spoken.contains("|") && !english.spoken.contains("#"), "BUG-20a: an English table is summed up the same way")
    let list = ArisSpeakable.report("세 가지예요.\n\n- **첫째** 빠름\n- 둘째\n1. 셋째", korean: true)
    check(!list.spoken.contains("-") && !list.spoken.contains("*") && list.spoken.contains("첫째 빠름") && list.spoken.contains("셋째"),
          "BUG-20a: list markers and bold marks are never read")
    // Code is still never read, and a plain result is said as before.
    check(ArisSpeakable.report("코드예요.\n\n```swift\nlet x = 1\n```", korean: true).spoken == "코드예요.", "BUG-20a: code stays unread")
    check(ArisSpeakable.report("블랙홀은 빛도 빠져나오지 못하는 천체예요.", korean: true).spoken == "블랙홀은 빛도 빠져나오지 못하는 천체예요.",
          "BUG-20a: a plain result is said as it is")
}

/// BUG-20b: a request for a file (the user's own words) is noticed; others aren't.
private func qaTaskFileRequestTests() {
    let asks = [qaRequest, "회의록 정리해서 문서로 만들어 놔", "조사해서 저장해 둬", "결과를 파일에 남겨 놔", "마크다운으로 정리해 놔",
                "Research this and save it", "write it up as a file when you're done", "put it in a document, let me know when done",
                "정리해서 .md로 줘"]
    for words in asks { check(ArisTaskResult.asksForFile(words), "BUG-20b: \"\(words)\" asks for a file") }
    let not = ["블랙홀 조사해서 정리해 놔", "저장된 파일 찾아 놔", "파일로 저장하지 말고 말로만 알려줘", "이 파일 요약해 놔", "don't save anything, just tell me",
               "기억해 둬"]
    for words in not { check(!ArisTaskResult.asksForFile(words), "BUG-20b: \"\(words)\" doesn't ask for a file") }

    // Asked for a file: the rest after the line is the file, however short; a lone sentence is the file itself.
    let toFile = ArisTaskResult.split(qaSquares, toFile: true)
    check(toFile.spoken == "1부터 5까지의 제곱을 표로 정리했어요." && toFile.document?.hasPrefix("### 제곱표\n| 수 | 제곱 |") == true,
          "BUG-20b: asked for a file, a short table is the file")
    let lone = ArisTaskResult.split("오늘 할 일은 세 가지예요.", toFile: true)
    check(lone.spoken == "오늘 할 일은 세 가지예요." && lone.document == "오늘 할 일은 세 가지예요.", "BUG-20b: asked for a file, a lone line is the file")
    // Not asked: the 250-character rule as before.
    check(ArisTaskResult.split(qaSquares).document == nil && ArisTaskResult.split(qaSquares, toFile: false).document == nil,
          "BUG-20b: not asked, a short result isn't a file")
}

/// BUG-20b: the file is saved (in a temp folder here, never the user's Documents) and the answer says where.
private func qaTaskSaveTests() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-qatasks-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let documents = root.appendingPathComponent("Documents/Aris"), own = root.appendingPathComponent("own/results")
    let date = Date(timeIntervalSince1970: 1_794_200_000)
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    let title = ArisHandoff.title(of: qaRequest)
    let delivered = ArisTaskResult.deliver(qaSquares, request: qaRequest, title: title, date: date, timeZone: seoul, folders: [documents, own])
    let name = ArisTaskResult.fileName(title: title, date: date, timeZone: seoul)
    check(delivered.file?.path == documents.appendingPathComponent(name).path, "BUG-20b: asked for a file, the short result is saved in Documents/Aris")
    let text = delivered.file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    check(text == "# \(title)\n\n### 제곱표\n| 수 | 제곱 |\n|---|---|\n| 1 | 1 |\n| 2 | 4 |\n| 3 | 9 |\n| 4 | 16 |\n| 5 | 25 |",
          "BUG-20b: the file holds the title and the table")
    check(delivered.answer.hasPrefix("1부터 5까지의 제곱을 표로 정리했어요.") && delivered.answer.contains("문서 › Aris 폴더에")
          && delivered.answer.contains(name), "BUG-20b: the answer says where it was saved")
    check(!FileManager.default.fileExists(atPath: own.path), "BUG-20b: the fallback folder stays untouched when Documents works")

    // Not asked and short: said, never saved.
    let plain = ArisTaskResult.deliver(qaSquares, request: "1부터 5까지 제곱 표로 정리해 놔", title: "제곱", date: date, timeZone: seoul,
                                       folders: [documents, own])
    check(plain.file == nil && plain.answer == ArisAgentStream.spoken(qaSquares), "BUG-20b: not asked, a short result is the answer as it is")
    // Not asked and long: the 250-character rule saves it, and the answer says where too.
    let long = "블랙홀을 세 가지로 정리했어요.\n\n" + String(repeating: "- 사건의 지평선은 되돌아올 수 없는 경계예요.\n", count: 20)
    let saved = ArisTaskResult.deliver(long, request: "블랙홀 조사해서 정리해 놔", title: "블랙홀", date: date, timeZone: seoul, folders: [documents, own])
    check(saved.file?.deletingLastPathComponent().path == documents.path && saved.answer.contains("문서 › Aris 폴더에"),
          "BUG-20b: a long result is still saved, and the answer says where")

    // Documents can't be written: Aris's own folder, and the answer says so.
    let blocked = root.appendingPathComponent("blocked")
    FileManager.default.createFile(atPath: blocked.path, contents: Data())
    let fallback = ArisTaskResult.deliver(qaSquares, request: qaRequest, title: title, date: date, timeZone: seoul,
                                          folders: [blocked.appendingPathComponent("Aris"), own])
    check(fallback.file?.deletingLastPathComponent().path == own.path && fallback.answer.contains("Aris 폴더에")
          && !fallback.answer.contains("문서 ›"), "BUG-20b: when Documents can't be written, the answer names Aris's own folder")
    // Nowhere can be written: the line, and that it couldn't be saved.
    let nowhere = ArisTaskResult.deliver(qaSquares, request: qaRequest, title: title, date: date, timeZone: seoul,
                                         folders: [blocked.appendingPathComponent("a"), blocked.appendingPathComponent("b")])
    check(nowhere.file == nil && nowhere.answer.contains("저장하지 못했어요"), "BUG-20b: a save that fails says so")
    // English.
    let english = ArisTaskResult.deliver("Here are the squares.\n\n| n | n² |\n|---|---|\n| 1 | 1 |", request: "make a table of squares and save it as a file",
                                         title: "squares", date: date, timeZone: seoul, folders: [documents, own])
    check(english.file != nil && english.answer.contains("Documents › Aris"), "BUG-20b: in English, the answer says where too")
    // The agent delivers through it, with the user's own words (`request`), never the model's.
    let runner = qaSource("ArisAgent/ArisAgentRunner.swift")
    check(runner.contains("ArisTaskResult.deliver(raw, request: request, title: taskTitle, tainted: driver.taint != .none, folders: Self.resultFolders)"),
          "BUG-20b: the agent's task result goes through ArisTaskResult.deliver with the user's words")
}

/// BUG-21: a handed-out task is one entry in the 기록 tab, updated with its result.
private func qaTaskHistoryTests() {
    let job = UUID(), other = UUID()
    let asked = Date(timeIntervalSince1970: 1_794_200_000)
    let handoff = ArisHistoryEntry(date: asked, heard: qaRequest, reply: "제가 맡았어요, 끝나면 알려줄게요.", job: job)
    let later = ArisHistoryEntry(date: asked.addingTimeInterval(3), heard: "날씨 어때", reply: "맑아요.")
    let list = ArisHistory.adding(later, to: ArisHistory.adding(handoff, to: []))
    let title = ArisHandoff.title(of: qaRequest)
    let done = ArisHistory.finishing(job: job, title: title, shown: "1부터 5까지의 제곱을 표로 정리했어요.", file: "/tmp/x.md", in: list)
    check(done.count == 2, "BUG-21: the result updates the hand-out's entry instead of adding one")
    let updated = done.first { $0.id == handoff.id }
    check(updated?.reply == "1부터 5까지의 제곱을 표로 정리했어요." && updated?.file == "/tmp/x.md" && updated?.isTask == true
          && updated?.sawOutside == true && updated?.heard == qaRequest && updated?.date == asked,
          "BUG-21: the entry keeps the user's words and place, and takes the result, its file and the job's marks")
    check(done.filter { $0.heard.hasPrefix("QA 테스트로") }.count == 1, "BUG-21: the request is listed once")
    // No entry for it (deleted, or a job no turn recorded): added as before.
    let added = ArisHistory.finishing(job: other, title: "다른 일", shown: "끝났어요.", file: nil, in: list)
    check(added.count == 3 && added.first?.heard == "다른 일" && added.first?.isTask == true, "BUG-21: a job without an entry is added as before")
    // History saved before the change (no job field) still loads.
    let old = #"[{"id":"\#(UUID().uuidString)","date":0,"heard":"a","reply":"b","isTask":false}]"#
    let decoded = try? JSONDecoder().decode([ArisHistoryEntry].self, from: Data(old.utf8))
    check(decoded?.first?.job == nil && decoded?.first?.heard == "a", "BUG-21: an entry saved before still loads")
    // The controller links the hand-out's entry to its one job and finishes it on the result.
    let team = qaSource("Aris/private/Aris/ArisController+Team.swift")
    check(team.contains("pastTurns = ArisHistory.finishing(job: job.id"), "BUG-21: a finished job updates its entry")
    let controller = qaSource("Aris/private/Aris/ArisController.swift")
    // The teammate called by name (BUG-25b) hands out too, so it records its job the same way.
    check(controller.components(separatedBy: "recordTurn(heard: unmarked, reply: reply, job: handed.job)").count == 3
          && controller.contains("recordTurn(heard: request ?? text, reply: handed.line, job: handed.job)"),
          "BUG-21: both hand-out turns record their job")
}
