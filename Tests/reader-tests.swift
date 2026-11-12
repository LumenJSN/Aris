// Tests for the owner's 1B and 2A (mockups/done-and-reader.html): finished jobs fold into one chip in the open notch, and long
// results open in Aris's own reader (markdown as styled text, links as text, files only from ~/Documents/Aris).
// Called from main.swift; uses its check().
import Foundation

func runReaderTests() {
    doneFoldTests()
    boardBlockTests()
    readerInlineTests()
    readerDocumentTests()
    resultPathTests()
    noteTextTests()
}

// MARK: - 1B: done jobs fold into one chip

private func doneTask(_ title: String, _ state: ArisBackgroundTask.State) -> ArisBackgroundTask {
    ArisBackgroundTask(id: UUID(), title: title, state: state)
}

private func doneFoldTests() {
    let mail = doneTask("메일 요약", .done("답할 메일이 두 통 있어요."))
    let rate = doneTask("환율 확인", .done("1달러에 1,384원이에요."))
    let hole = doneTask("블랙홀 자료 정리", .working("웹 검색 중"))
    let pr = doneTask("PR #214 리뷰", .working(""))
    let broke = doneTask("사진 정리", .failed("못 끝냈어요"))
    let tasks = [mail, rate, hole, broke, pr]

    let fold = ArisDoneFold.fold(tasks, seen: [])
    check(fold.running.map(\.id) == [hole.id, pr.id], "done fold: running jobs stay as tags, oldest first")
    check(fold.done.map(\.id) == [broke.id, rate.id, mail.id], "done fold: every finished one (failed too) is in the chip, newest first")
    check(ArisDoneFold.count(fold.done.count) == "3개 끝남", "done fold: the chip says how many are done")
    check(ArisDoneFold.latest(fold) == "· 사진 정리", "done fold: the chip names the newest one")
    check(ArisDoneFold.label(hole) == "블랙홀 자료 정리 · 웹 검색 중" && ArisDoneFold.label(pr) == "PR #214 리뷰 · 하는 중",
          "done fold: a running tag is its title and what it's doing")
    check(ArisDoneFold.detail(mail) == "답할 메일이 두 통 있어요." && ArisDoneFold.detail(broke) == "못 끝냈어요",
          "done fold: a tray row's words are the answer or what went wrong")

    let seen = ArisDoneFold.seenAll(tasks)
    check(seen == [mail.id, rate.id, broke.id], "done fold: 다 봤어요 marks every finished one, never a running one")
    let cleared = ArisDoneFold.fold(tasks, seen: seen)
    check(cleared.done.isEmpty && cleared.running.count == 2 && ArisDoneFold.latest(cleared) == nil, "done fold: once seen, the chip is gone")
    check(ArisDoneFold.shows(tasks, seen: seen) && !ArisDoneFold.shows([mail, rate], seen: seen) && !ArisDoneFold.shows([], seen: []),
          "done fold: the row shows only while something runs or is unseen")

    // A job finishing after 다 봤어요 brings the chip back with just that one.
    let later = [mail, rate, broke, doneTask("PR #214 리뷰", .done("고칠 곳 두 군데 찾았어요."))]
    check(ArisDoneFold.fold(later, seen: seen).done.map(\.title) == ["PR #214 리뷰"], "done fold: a newly finished job is unseen again")

    // The check lands on the tag first; it slides into the chip after (the mockup's 520 ms).
    let landing = ArisDoneFold.fold(tasks, seen: [], landing: [broke.id])
    check(landing.running.map(\.id) == [hole.id, broke.id, pr.id] && !landing.done.contains { $0.id == broke.id },
          "done fold: a job that just finished stays a tag in its place while its check lands")
    check(ArisDoneFold.label(broke) == "사진 정리", "done fold: a settled tag shows its title alone")
    let long = ArisBackgroundTask(id: UUID(), title: "맥북 프로 M5 가격 지금 얼마인지, 아니면 예전에 찾아본 거 있는지", state: .working("Aside가 브라우저에서 하는 중: 맥북"))
    check(ArisDoneFold.label(long) == "맥북 프로 M5 가격 지금… · Aside가 브라우저에서 하는 중: 맥북",
          "done fold: a long running title is cut (trailing space and comma dropped) so the status shows on the one line")
    check(ArisDoneFold.runningTitle("가나다라마바사아자차카타파하가나") == "가나다라마바사아자차카타파하가나"
          && ArisDoneFold.runningTitle("가나다라마바사아자차카타파하가나다") == "가나다라마바사아자차카타파하가…",
          "done fold: 16 letters stay whole, 17 are cut to 15 and …")
    check(ArisDoneFold.label(ArisBackgroundTask(id: UUID(), title: long.title, state: .done("ok"))) == long.title,
          "done fold: a settled tag keeps its whole title (the tray and 기록 have it too)")
    check(ArisDoneFold.fold(tasks, seen: [], landing: [hole.id]).running.map(\.id) == [hole.id, pr.id],
          "done fold: landing never changes a running job")

    let many = (1...7).map { doneTask("일 \($0)", .done("끝")) }
    let manyFold = ArisDoneFold.fold(many, seen: [])
    check(ArisDoneFold.trayRows == 4 && ArisDoneFold.tray(manyFold).map(\.title) == ["일 7", "일 6", "일 5", "일 4"],
          "done fold: the tray lists the newest four")
    check(ArisDoneFold.more(manyFold.done.count) == "+3개 더 · 기록 탭에 있어요" && ArisDoneFold.more(4) == nil,
          "done fold: more than four points to the 기록 tab")
}

// MARK: - 2A: the board's blocks, numbered lists and quotes added

private func boardBlockTests() {
    let blocks = ArisBoardContent.blocks(from: """
    # 블랙홀 자료 정리

    ## 핵심 세 가지
    - **사건의 지평선**: 돌아올 수 없는 경계예요.
    - 2019년 `M87*`
    1. EHT 공식 사이트
    2. 칼 세이건
    > 블랙홀에는 털이 없다.
    > — 존 휠러
    #### 작은 제목
    """)
    check(blocks == [
        .heading(level: 1, text: "블랙홀 자료 정리"),
        .heading(level: 2, text: "핵심 세 가지"),
        .bullets(["**사건의 지평선**: 돌아올 수 없는 경계예요.", "2019년 `M87*`"]),
        .numbered(["EHT 공식 사이트", "칼 세이건"]),
        .quote("블랙홀에는 털이 없다.\n— 존 휠러"),
        .label("작은 제목"),
    ], "reader blocks: headings, bullets, a numbered list, a quote, a deep heading as a small label (\(blocks))")
    check(ArisBoardContent.blocks(from: "글이에요\n> 인용") == [.paragraph("글이에요"), .quote("인용")],
          "reader blocks: a quote ends the paragraph before it")
    check(ArisBoardContent.blocks(from: "```swift\nlet x = 1\n\nlet y = 2\n```") == [.code("let x = 1\n\nlet y = 2")],
          "reader blocks: a fenced block keeps its blank lines")
    check(ArisBoardContent.blocks(from: "```\n열린 채로") == [.code("열린 채로")], "reader blocks: an unclosed fence runs to the end")
    check(ArisBoardContent.blocks(from: "#태그 글\n####### 일곱") == [.paragraph("#태그 글"), .paragraph("####### 일곱")],
          "reader blocks: a # without a space is words, never a hang")
    check(ArisBoardContent.blocks(from: "|").count <= 1 && ArisBoardContent.blocks(from: "- ").count == 1,
          "reader blocks: odd single lines end")
    check(ArisBoardContent.blocks(from: "<script>alert(1)</script>") == [.paragraph("<script>alert(1)</script>")],
          "reader blocks: HTML is just words")
}

// MARK: - 2A: inline marks, links shown as text

private func readerInlineTests() {
    let runs = ArisReaderInline.runs("블랙홀은 **빛도** 못 나와요. `r_s` 식, *기울임*.")
    check(runs == [
        .init(text: "블랙홀은 ", style: .plain), .init(text: "빛도", style: .strong), .init(text: " 못 나와요. ", style: .plain),
        .init(text: "r_s", style: .code), .init(text: " 식, ", style: .plain), .init(text: "기울임", style: .emphasis),
        .init(text: ".", style: .plain),
    ], "reader inline: bold, code and italics (\(runs))")

    let eht = URL(string: "https://eventhorizontelescope.org")!
    check(ArisReaderInline.runs("EHT 공식 사이트 https://eventhorizontelescope.org") ==
          [.init(text: "EHT 공식 사이트 ", style: .plain), .init(text: "https://eventhorizontelescope.org", style: .link(eht))],
          "reader inline: a bare address is a link shown as its text")
    check(ArisReaderInline.runs("[EHT](https://eventhorizontelescope.org)") ==
          [.init(text: "EHT ", style: .plain), .init(text: "https://eventhorizontelescope.org", style: .link(eht))],
          "reader inline: a named link shows its words and then its real address")
    check(ArisReaderInline.runs("[https://eventhorizontelescope.org](https://eventhorizontelescope.org)") ==
          [.init(text: "https://eventhorizontelescope.org", style: .link(eht))], "reader inline: a link that is its address shows once")
    let sneaky = ArisReaderInline.runs("[여기](javascript:alert(1)) [파일](file:///etc/passwd)")
    check(!sneaky.contains { if case .link = $0.style { return true }; return false }
          && sneaky.map(\.text).joined() == "여기 파일", "reader inline: only http, https and mailto become links; others are words")
    let image = ArisReaderInline.runs("![그림](https://example.com/x.png)")
    check(image == [.init(text: "그림", style: .plain)], "reader inline: an image is its words, never loaded")
    check(ArisReaderInline.runs("끝 https://a.org/x.") == [.init(text: "끝 ", style: .plain), .init(text: "https://a.org/x", style: .link(URL(string: "https://a.org/x")!)),
                                                       .init(text: ".", style: .plain)], "reader inline: a sentence's last stop isn't part of the address")
    check(ArisReaderInline.runs("<b>굵게</b> & 끝").map(\.text).joined() == "<b>굵게</b> & 끝", "reader inline: HTML stays words")
    check(ArisReaderInline.safeLink(URL(string: "mailto:user@example.com")) != nil && ArisReaderInline.safeLink(URL(string: "ftp://x")) == nil
          && ArisReaderInline.safeLink(URL(string: "https://")) == nil, "reader inline: safe links are http(s) with a host, or mailto")
}

// MARK: - 2A: the reader's document, copy text and words

private func readerDocumentTests() {
    let seoul = TimeZone(identifier: "Asia/Seoul")!
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour, parts.minute) = (2026, 11, 5, 15, 41)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = seoul
    let modified = calendar.date(from: parts)!
    let markdown = "# 블랙홀 자료 정리\n\n## 한 줄 요약\n블랙홀은 **빛도** 못 나와요.\n\n- 하나\n- 둘\n\n1. 첫째\n\n```\nr_s = 2GM / c²\n```\n> 털이 없다.\n\n[EHT](https://eventhorizontelescope.org)"
    let path = "/Users/p/Documents/Aris/2026-11-05 블랙홀 자료 정리.md"
    let doc = ArisReaderDocument.result(markdown: markdown, file: path, modified: modified, timeZone: seoul)
    check(doc.title == "블랙홀 자료 정리" && doc.file == path, "reader doc: the title is the file's first heading")
    check(doc.meta == "2026년 11월 5일 오후 3:41 · Aris", "reader doc: the line under the title is when it was saved (\(doc.meta ?? "nil"))")
    check(doc.blocks.first == .heading(level: 1, text: "블랙홀 자료 정리") && doc.blocks.count == 8, "reader doc: every block is kept (\(doc.blocks.count))")
    check(ArisReaderDocument.result(markdown: "그냥 글", file: path, modified: modified, timeZone: seoul).title == "블랙홀 자료 정리",
          "reader doc: without a heading the title comes from the file name, less its date")

    let plain = ArisReaderDocument.plainText(doc.blocks)
    check(plain == "블랙홀 자료 정리\n\n한 줄 요약\n\n블랙홀은 빛도 못 나와요.\n\n• 하나\n• 둘\n\n1. 첫째\n\nr_s = 2GM / c²\n\n털이 없다.\n\nEHT https://eventhorizontelescope.org",
          "reader doc: 복사 gives the words without markdown marks (\(plain))")

    let now = modified
    check(ArisReaderDocument.subtitle(modified: now.addingTimeInterval(-20), now: now) == "방금 · ~/Documents/Aris"
          && ArisReaderDocument.subtitle(modified: now.addingTimeInterval(-600), now: now) == "10분 전 · ~/Documents/Aris"
          && ArisReaderDocument.subtitle(modified: now.addingTimeInterval(-7_300), now: now) == "2시간 전 · ~/Documents/Aris"
          && ArisReaderDocument.subtitle(modified: now.addingTimeInterval(-200_000), now: now, timeZone: seoul) == "11월 3일 · ~/Documents/Aris",
          "reader doc: the bar says how long ago and where the file is")

    let answer = ArisReaderDocument.answer("## 정리\n- 하나", question: "정리해 줘")
    check(answer.file == nil && answer.title == "Aris" && answer.blocks.first == .heading(level: 3, text: "정리해 줘"),
          "reader doc: 답 열기 keeps the question as a heading and has no file")
    check(ArisReaderDocument.answer("짧은 답", question: "").blocks == [.paragraph("짧은 답")], "reader doc: no question, no heading")
}

// MARK: - 2A: only saved results, never a way out of the folder

private func resultPathTests() {
    let fm = FileManager.default
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aris-reader-tests-\(UUID().uuidString)")
    let docs = root.appendingPathComponent("Documents/Aris"), fallback = root.appendingPathComponent("config/results")
    let outside = root.appendingPathComponent("secret")
    for folder in [docs, fallback, outside, docs.appendingPathComponent("sub"), docs.appendingPathComponent("dir.md")] {
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    defer { try? fm.removeItem(at: root) }
    let write = { (url: URL) in try? Data("# 제목\n".utf8).write(to: url) }
    let good = docs.appendingPathComponent("2026-11-05 블랙홀.md")
    write(good)
    write(docs.appendingPathComponent("notes.txt"))
    write(docs.appendingPathComponent("sub/deep.md"))
    write(outside.appendingPathComponent("keys.md"))
    write(fallback.appendingPathComponent("saved.md"))
    try? fm.createSymbolicLink(at: docs.appendingPathComponent("link.md"), withDestinationURL: outside.appendingPathComponent("keys.md"))
    try? fm.createSymbolicLink(at: docs.appendingPathComponent("folder"), withDestinationURL: outside)

    let both = [docs, fallback]
    check(ArisResultPath.resolve(good.path, in: both)?.lastPathComponent == "2026-11-05 블랙홀.md", "result path: a saved result opens")
    check(ArisResultPath.resolve(fallback.appendingPathComponent("saved.md").path, in: both) != nil
          && ArisResultPath.resolve(fallback.appendingPathComponent("saved.md").path, in: [docs]) == nil,
          "result path: the fallback folder is read, but 파일로 열기 only takes ~/Documents/Aris")
    check(ArisResultPath.resolve(docs.path + "/../../secret/keys.md", in: both) == nil, "result path: .. never leaves the folder")
    check(ArisResultPath.resolve(docs.path + "/sub/../2026-11-05 블랙홀.md", in: both) == nil, "result path: any .. is refused, even one that lands inside")
    check(ArisResultPath.resolve(docs.appendingPathComponent("link.md").path, in: both) == nil, "result path: a link out of the folder is refused")
    check(ArisResultPath.resolve(docs.appendingPathComponent("folder/keys.md").path, in: both) == nil, "result path: a linked folder is refused")
    check(ArisResultPath.resolve(docs.appendingPathComponent("notes.txt").path, in: both) == nil, "result path: only .md files")
    check(ArisResultPath.resolve(docs.appendingPathComponent("sub/deep.md").path, in: both) == nil, "result path: only files right in the folder")
    check(ArisResultPath.resolve(docs.appendingPathComponent("dir.md").path, in: both) == nil, "result path: a folder named .md is not a file")
    check(ArisResultPath.resolve(docs.appendingPathComponent("missing.md").path, in: both) == nil, "result path: a missing file is refused")
    check(ArisResultPath.resolve("2026-11-05 블랙홀.md", in: both) == nil && ArisResultPath.resolve("", in: both) == nil
          && ArisResultPath.resolve(good.path + "\u{0}.txt", in: both) == nil, "result path: relative, empty or NUL paths are refused")
    check(ArisResultPath.resolve(outside.appendingPathComponent("keys.md").path, in: both) == nil, "result path: a file elsewhere is refused")
}

// MARK: - 2A: 메모에 저장's words

private func noteTextTests() {
    let text = ArisResultPath.noteText("# 블랙홀 자료 정리\n\n## 핵심\n- **사건의 지평선**: 경계\n* `M87*` 그림자\n1. 첫째\n\n\n```\nr_s = 2GM\n```\n> 털이 없다.\n[EHT](https://eventhorizontelescope.org) ![그림](https://x.com/a.png)")
    check(text == "블랙홀 자료 정리\n\n핵심\n• 사건의 지평선: 경계\n• M87* 그림자\n1. 첫째\n\nr_s = 2GM\n털이 없다.\nEHT (https://eventhorizontelescope.org) 그림",
          "note text: the title first, marks dropped, links keep their address, images their words (\(text))")
    check(ArisResultPath.noteText("\n\n   \n").isEmpty, "note text: nothing to save is empty")
}
