// Tests for the owner's pick A, "깔끔한 문서" (mockups/answer-format.html): every brain writes the same answer
// shape (a conclusion line, then labelled sections: tables, bullets, checklists), the notch and the reader draw it from
// ArisBoardContent's blocks, and `note --markdown` puts the same structure into Apple Notes with real checklists.
// Called from main.swift; uses its check().
import Foundation

func runAnswerFormatTests() {
    answerBlockTests()
    answerPieceTests()
    revealClockTests()
    answerShapePromptTests()
    noteMarkdownHTMLTests()
    noteChecklistPlanTests()
    reviewFixTests()
}

// MARK: - Blocks: labels, checklists, tables with a header or without, bold cells

private let macbook = """
코딩 위주면 에어 15인치, 영상 편집을 자주 하면 프로 14인치예요.

### 비교
| | 에어 15 | 프로 14 |
|---|---|---|
| 가격 | **189만 원** | 269만 원 |
| 팬 | 없음 (조용) | 있음 |
| 배터리 | 18시간 | **22시간** |
| 화면 | 60Hz | **120Hz XDR** |

### 추천 이유
- **코딩**은 에어로도 충분하고 80만 원 아껴요.
- **4K 편집**을 매주 하면 팬 있는 프로가 덜 느려져요.

### 다음에 할 것
- [ ] 학생 할인 가격 확인
- [ ] 매장에서 두 화면 나란히 보기
"""

private let tomorrow = """
내일은 마감 하나, 수업 둘, 약속 하나예요.

### 시간 정해진 것
| 10:00 | 미적분 수업 |
| 13:30 | 물리 실험 |
| 18:00 | 민수랑 저녁 · 강남역 |

### 해야 할 것
- [ ] **물리 보고서** 제출 (밤 11:59 마감)
- [ ] 엄마한테 택배 주소 보내기
- [x] 도서관 책 반납
"""

private func answerBlockTests() {
    let blocks = ArisBoardContent.blocks(from: macbook)
    check(blocks == [
        .paragraph("코딩 위주면 에어 15인치, 영상 편집을 자주 하면 프로 14인치예요."),
        .label("비교"),
        .table(header: ["", "에어 15", "프로 14"], rows: [["가격", "**189만 원**", "269만 원"], ["팬", "없음 (조용)", "있음"],
                                                       ["배터리", "18시간", "**22시간**"], ["화면", "60Hz", "**120Hz XDR**"]]),
        .label("추천 이유"),
        .bullets(["**코딩**은 에어로도 충분하고 80만 원 아껴요.", "**4K 편집**을 매주 하면 팬 있는 프로가 덜 느려져요."]),
        .label("다음에 할 것"),
        .checklist([.init(text: "학생 할인 가격 확인", done: false), .init(text: "매장에서 두 화면 나란히 보기", done: false)]),
    ], "answer blocks: the MacBook answer is a line, labels, a table with a header, bullets and a checklist (\(blocks))")
    let todo = ArisBoardContent.blocks(from: tomorrow)
    check(todo.count == 5 && todo[2] == .table(header: [], rows: [["10:00", "미적분 수업"], ["13:30", "물리 실험"], ["18:00", "민수랑 저녁 · 강남역"]]),
          "answer blocks: a table with no divider row has no header, every row is a row (\(todo))")
    check(todo.last == .checklist([.init(text: "**물리 보고서** 제출 (밤 11:59 마감)", done: false), .init(text: "엄마한테 택배 주소 보내기", done: false),
                                   .init(text: "도서관 책 반납", done: true)]),
          "answer blocks: - [ ] and - [x] are checklist items, done or not")
    check(ArisBoardContent.blocks(from: "- 우유\n- [ ] 계란\n- 빵") == [.bullets(["우유"]), .checklist([.init(text: "계란", done: false)]), .bullets(["빵"])],
          "answer blocks: bullets and checklist items don't run into each other")
    check(ArisBoardContent.blocks(from: "- [") == [.checklist([.init(text: "", done: false)])]
          && ArisBoardContent.blocks(from: "- [ ") == [.checklist([.init(text: "", done: false)])],
          "answer blocks: a checkbox still arriving is already a checklist item (no dot that turns into a ring)")
    check(ArisBoardContent.blocks(from: "- [링크](https://a.com) 보기") == [.bullets(["[링크](https://a.com) 보기"])],
          "answer blocks: a bullet that starts with a link stays a bullet")
    check(ArisBoardContent.blocks(from: "## 둘\n### 셋\n#### 넷") == [.heading(level: 2, text: "둘"), .label("셋"), .label("넷")],
          "answer blocks: ### and deeper are small labels, # and ## stay headings")
    check(ArisBoardContent.winCell("**189만 원**") == "189만 원" && ArisBoardContent.winCell(" **22시간** ") == "22시간"
          && ArisBoardContent.winCell("**4K** 편집") == nil && ArisBoardContent.winCell("189만 원") == nil && ArisBoardContent.winCell("****") == nil,
          "answer blocks: a cell that is all bold is the better value; partly bold is just bold words")
}

// MARK: - The notch's pieces: the lead line, then the blocks

private func answerPieceTests() {
    let pieces = ArisAnswerDocument.pieces(from: macbook)
    check(pieces.first == .lead("코딩 위주면 에어 15인치, 영상 편집을 자주 하면 프로 14인치예요.") && pieces.count == 7
          && pieces[1] == .block(.label("비교")), "answer pieces: the first line is the lead, the rest are blocks (\(pieces))")
    check(ArisAnswerDocument.pieces(from: "네, 25분 타이머 맞췄어요.") == [.lead("네, 25분 타이머 맞췄어요.")],
          "answer pieces: a short answer is one lead line")
    check(ArisAnswerDocument.pieces(from: "첫 줄이에요.\n둘째 줄이에요.") == [.lead("첫 줄이에요."), .block(.paragraph("둘째 줄이에요."))],
          "answer pieces: only the first line is the lead")
    check(ArisAnswerDocument.pieces(from: "### 비교\n- 하나") == [.block(.label("비교")), .block(.bullets(["하나"]))]
          && ArisAnswerDocument.pieces(from: "- 하나\n- 둘").first == .block(.bullets(["하나", "둘"])),
          "answer pieces: no lead when the answer opens with a label or a list")
    let long = String(repeating: "아주 긴 문장이에요 ", count: 20)
    check(ArisAnswerDocument.pieces(from: long).first == .block(.paragraph(long.trimmingCharacters(in: .whitespaces))),
          "answer pieces: a first line past \(ArisAnswerDocument.leadLimit) characters is a paragraph, not a bold wall")
    check(ArisAnswerDocument.pieces(from: "  \n\n").isEmpty, "answer pieces: blank is nothing")
    // Streaming: each piece already on screen stays the same while later text arrives (only the last one grows).
    let partial = ArisAnswerDocument.pieces(from: String(macbook.prefix(macbook.count - 6)))
    check(Array(partial.dropLast()) == Array(pieces.prefix(partial.count - 1)),
          "answer pieces: while an answer streams, the pieces before the last don't change")
    check(ArisAnswerDocument.joinsPrevious(.block(.table(header: [], rows: [])), after: .block(.label("비교")))
          && !ArisAnswerDocument.joinsPrevious(.block(.label("둘")), after: .block(.label("하나")))
          && !ArisAnswerDocument.joinsPrevious(.block(.bullets([])), after: .lead("x")),
          "answer pieces: a section's body rises with its label")
}

// MARK: - The reveal: 420 ms, 90 ms apart, a block that streams in later rises at once

private func revealClockTests() {
    var clock = ArisRevealClock()
    let starts = [clock.start(now: 10, joinsPrevious: false), clock.start(now: 10, joinsPrevious: false),
                  clock.start(now: 10, joinsPrevious: true), clock.start(now: 10, joinsPrevious: false)]
    check(zip(starts, [10.12, 10.21, 10.21, 10.30]).allSatisfy { abs($0 - $1) < 0.0001 },
          "reveal: blocks that arrive together rise 90 ms apart after a 120 ms lead-in; a label's body with it (\(starts))")
    check(abs(clock.start(now: 20, joinsPrevious: false) - 20) < 0.0001 && abs(clock.start(now: 20.01, joinsPrevious: false) - 20.09) < 0.0001,
          "reveal: a block streaming in after the others rises at once, still 90 ms after the one before")
    check(ArisRevealClock.duration == 0.42 && ArisRevealClock.rise == 6 && ArisRevealClock.curve == [0.22, 0.61, 0.36, 1],
          "reveal: 420 ms on (.22,.61,.36,1), 6 points up")
}

// MARK: - The answer shape, in every brain's prompt

private func answerShapePromptTests() {
    let shape = ArisAgentPrompt.answerShape
    check(shape.contains("### 비교") && shape.contains("- [ ] ") && shape.contains("**bold**") && shape.contains("table")
          && shape.contains("first line") && shape.contains("short answer"), "answer shape: a conclusion line, labels, tables, bullets, checklists")
    let prompts: [(String, String)] = [
        ("Codex", ArisAgentPrompt.system(tools: "/t", notion: true, gated: true)),
        ("Codex task", ArisAgentPrompt.system(tools: "/t", notion: true, gated: true, task: true)),
        ("open Claude", ArisAgentPrompt.system(tools: "/t", reads: true)),
        ("open Claude task", ArisAgentPrompt.system(tools: "/t", task: true, reads: true)),
        ("sealed Claude", ArisAgentPrompt.sealed(tools: "/t")),
        ("sealed Claude hands-free", ArisAgentPrompt.sealed(tools: "/t", handsFree: true)),
        ("sealed Claude task", ArisAgentPrompt.sealed(tools: "/t", task: true)),
        ("agy", ArisAgentPrompt.system(tools: "/t", relay: true)),
        ("agy task", ArisAgentPrompt.system(tools: "/t", task: true, relay: true)),
        ("sealed agy", ArisAgentPrompt.sealedAgy(tools: "/t", handsFree: false, task: false)),
        ("sealed agy hands-free", ArisAgentPrompt.sealedAgy(tools: "/t", handsFree: true, task: false)),
        ("sealed agy task", ArisAgentPrompt.sealedAgy(tools: "/t", handsFree: false, task: true)),
    ]
    for (name, prompt) in prompts {
        check(prompt.components(separatedBy: shape).count == 2, "answer shape: in the \(name) prompt, once")
        check(!prompt.contains("(JSON, lists, dicts, tables)"), "answer shape: the \(name) prompt no longer forbids the shape's tables and lists")
    }
    for (name, prompt) in prompts where !name.hasSuffix("task") {
        check(prompt.contains(ArisAgentPrompt.sayRule), "answer shape: the \(name) prompt says only the <say> line of a long answer")
    }
    // The Claude drivers carry it as their system prompt.
    for sealed in [true, false] {
        let arguments = ArisClaudeDriver(model: "sonnet", tools: "/t", sealed: sealed).arguments
        let prompt = arguments.firstIndex(of: "--system-prompt").map { arguments[$0 + 1] } ?? ""
        check(prompt.contains(shape), "answer shape: the \(sealed ? "sealed" : "open") Claude's --system-prompt has it")
    }
    // Notes: lists and saving go through --markdown with real checklists.
    for gated in [true, false] {
        let prompt = ArisAgentPrompt.system(tools: "/t", gated: gated)
        check(prompt.contains("`/t note --markdown '<markdown>'`") && prompt.contains("- [ ] ") && prompt.contains("prep list")
              && prompt.contains("메모에 저장") && prompt.contains("체크리스트"),
              "notes prompt (\(gated ? "gated" : "ungated")): saving to Notes and any list to write down use --markdown with - [ ] items")
    }
}

// MARK: - note --markdown: Notes' HTML

private func noteMarkdownHTMLTests() {
    let plan = ArisNoteMarkdown.plan(tomorrow.replacingOccurrences(of: "내일은 마감 하나, 수업 둘, 약속 하나예요.", with: "# 내일 할 일"))
    check(plan?.title == "내일 할 일", "note markdown: the first line is the title, without its #")
    check(plan?.html == "<div><h1>내일 할 일</h1></div><div><h3>시간 정해진 것</h3></div>"
          + "<table><tr><td>10:00</td><td>미적분 수업</td></tr><tr><td>13:30</td><td>물리 실험</td></tr><tr><td>18:00</td><td>민수랑 저녁 · 강남역</td></tr></table>"
          + "<div><h3>해야 할 것</h3></div><div><b>물리 보고서</b> 제출 (밤 11:59 마감)</div><div>엄마한테 택배 주소 보내기</div><div>도서관 책 반납</div>",
          "note markdown: labels as subheadings, a table, the checklist items as plain lines for ⇧⌘L (\(plan?.html ?? "nil"))")
    let mixed = ArisNoteMarkdown.plan("여행 준비물\n**꼭** 챙기기 <중요> & 확인\n- 여권\n- *충전기*\n1. 첫째\n> 인용\n- [ ] 칫솔\n`코드` [사이트](https://a.com)")
    check(mixed?.html == "<div><h1>여행 준비물</h1></div><div><b>꼭</b> 챙기기 &lt;중요&gt; &amp; 확인</div><ul><li>여권</li><li><i>충전기</i></li></ul>"
          + "<ol><li>첫째</li></ol><div>인용</div><div>칫솔</div><div>코드 사이트 (https://a.com)</div>",
          "note markdown: bold, italics, lists, quotes; HTML escaped; code loses its marks; a link keeps its address as text (\(mixed?.html ?? "nil"))")
    check(ArisNoteMarkdown.plan("제목\\n- [ ] 우유\\n- [ ] 계란")?.html == "<div><h1>제목</h1></div><div>우유</div><div>계란</div>",
          "note markdown: a literal \\n is a new line (as the board takes it)")
    check(ArisNoteMarkdown.plan("   \n\n") == nil && ArisNoteMarkdown.plan("### \n- [ ] 우유") == nil,
          "note markdown: no title, no note")
    check(ArisNoteMarkdown.plan("<script>x</script>\n- <img src=x onerror=y>")?.html == "<div><h1>&lt;script&gt;x&lt;/script&gt;</h1></div><ul><li>&lt;img src=x onerror=y&gt;</li></ul>",
          "note markdown: markup in the words is only words")
    check(ArisActions.noteRequest(["--markdown", "제목\n- [ ] 우유"]) == .markdown("제목\n- [ ] 우유")
          && ArisActions.noteRequest(["--markdown"]) == .invalid && ArisActions.noteRequest(["--markdown", "  "]) == .invalid,
          "note: --markdown takes the whole markdown as one argument")
}

// MARK: - note --markdown: which paragraphs become a checklist, and the keys

private func noteChecklistPlanTests() {
    guard let plan = ArisNoteMarkdown.plan("장보기\n- [ ] 우유\n- [ ] 계란\n- [ ] 빵") else { return check(false, "note plan: a checklist note plans") }
    check(plan.paragraphs == ["장보기", "우유", "계란", "빵"] && plan.groups == [ArisNoteMarkdown.Group(start: 1, count: 3)],
          "note plan: one paragraph per line, the items' group (\(plan.paragraphs), \(plan.groups))")
    check(ArisNoteMarkdown.keys(for: plan.groups[0], in: plan) == ArisActions.checklistKeys(items: 3),
          "note plan: items at the end take the old keys exactly (⌘↓, ⌥⇧↑ per item, ⇧⌘L)")
    guard let middle = ArisNoteMarkdown.plan("준비물\n### 챙길 것\n- [ ] 여권\n- [ ] 충전기\n### 메모\n- 공항 2시간 전\n- 환전") else {
        return check(false, "note plan: a note with a checklist in the middle plans")
    }
    check(middle.groups == [ArisNoteMarkdown.Group(start: 2, count: 2)] && middle.paragraphs.count == 7,
          "note plan: a checklist in the middle (\(middle.groups), \(middle.paragraphs))")
    check(ArisNoteMarkdown.keys(for: middle.groups[0], in: middle)
          == ["cmd+down", "opt+up", "opt+up", "opt+up", "left", "opt+shift+up", "opt+shift+up", "cmd+shift+l"],
          "note plan: from the end, up to the line after the items, back one, select the items, ⇧⌘L")
    check(ArisNoteMarkdown.keys(for: middle.groups[0], in: middle)?.allSatisfy { ArisKeyChord.parse($0) != nil } == true,
          "note plan: every key is one Aris can press")
    guard let table = ArisNoteMarkdown.plan("내일\n- [ ] 보고서\n### 시간\n| 10:00 | 수업 |\n### 또\n- [ ] 반납") else {
        return check(false, "note plan: a note with a table plans")
    }
    check(table.groups == [ArisNoteMarkdown.Group(start: 1, count: 1), ArisNoteMarkdown.Group(start: 5, count: 1)] && table.tables == [3],
          "note plan: a table is one place the keys never count across (\(table.groups), \(table.tables))")
    check(ArisNoteMarkdown.keys(for: table.groups[0], in: table) == ["cmd+up", "opt+down", "right", "opt+shift+down", "cmd+shift+l"]
          && ArisNoteMarkdown.keys(for: table.groups[1], in: table) == ["cmd+down", "opt+shift+up", "cmd+shift+l"],
          "note plan: items before a table are reached from the top, items after it from the end")
    let walled = ArisNoteMarkdown.plan("t\n| a |\n- [ ] x\n| b |")
    check(walled.map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0) } == .some(nil),
          "note plan: items between two tables are left as lines (no safe way to count to them)")
    let many = ArisNoteMarkdown.plan("t\n" + (1...31).map { "- [ ] \($0)" }.joined(separator: "\n"))
    check(many.map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0) } == .some(nil)
          && ArisNoteMarkdown.plan("t\n" + (1...30).map { "- [ ] \($0)" }.joined(separator: "\n")).map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0) != nil } == true,
          "note plan: \(ArisActions.checklistLimit) items at most per checklist")
    let far = ArisNoteMarkdown.plan("t\n- [ ] x\n" + (1...200).map { "줄 \($0)" }.joined(separator: "\n"))
    check(far.map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0) != nil } == true
          && far.map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0)!.count <= ArisNoteMarkdown.keyLimit } == true,
          "note plan: the shorter way round is taken (\(ArisNoteMarkdown.keyLimit) keys at most)")
    let deep = ArisNoteMarkdown.plan("t\n" + (1...100).map { "줄 \($0)" }.joined(separator: "\n") + "\n- [ ] x\n" + (1...100).map { "끝 \($0)" }.joined(separator: "\n"))
    check(deep.map { ArisNoteMarkdown.keys(for: $0.groups[0], in: $0) } == .some(nil), "note plan: too far from both ends is left as lines")
    check(ArisNoteMarkdown.plan("t\n- 우유")?.groups.isEmpty == true, "note plan: no checklist items, no keys (the note stays in the background)")
    // The note on screen must be exactly the planned one before any key: the title, and the items where planned.
    let shop = plan.groups[0]
    check(ArisNoteMarkdown.matchesGroup(text: "장보기\n우유\n계란\n빵\n", group: shop, plan: plan)
          && ArisNoteMarkdown.matchesGroup(text: "장보기\n우유\n계란\n빵", group: shop, plan: plan)
          && !ArisNoteMarkdown.matchesGroup(text: "장보기\n우유\n빵", group: shop, plan: plan)
          && !ArisNoteMarkdown.matchesGroup(text: "다른 메모\n우유\n계란\n빵", group: shop, plan: plan)
          && !ArisNoteMarkdown.matchesGroup(text: "장보기\n우유\n계란\n빵\n더", group: shop, plan: plan),
          "note plan: the note on screen must have the title and the planned paragraphs before any key goes")
    check(ArisNoteMarkdown.matchesGroup(text: "준비물\n챙길 것\n여권\n충전기\n메모\n공항 2시간 전\n환전", group: middle.groups[0], plan: middle)
          && !ArisNoteMarkdown.matchesGroup(text: "준비물\n챙길 것\n충전기\n여권\n메모\n공항 2시간 전\n환전", group: middle.groups[0], plan: middle),
          "note plan: bold and labels are compared as their words, in their places")
    let shown = "내일\n보고서\n시간\n\u{FFFC}\n또\n반납"
    check(ArisNoteMarkdown.matchesGroup(text: shown, group: table.groups[1], plan: table)
          && ArisNoteMarkdown.matchesGroup(text: shown, group: table.groups[0], plan: table)
          && !ArisNoteMarkdown.matchesGroup(text: "내일\n보고서\n시간\n\u{FFFC}\n또\n다른 것", group: table.groups[1], plan: table),
          "note plan: with a table, each group is checked only up to the end it's reached from")
}

// MARK: - Security review of the first cut (I1, I2, M1, M3-M7, M9)

private func reviewFixTests() {
    // I1: a 20,000-pipe row and 500 rows stay a small table, parsed quickly.
    let huge = "제목\n\n" + "|" + String(repeating: "a|", count: 20_000) + "\n" + (1...500).map { "| \($0) | 값 |" }.joined(separator: "\n")
    let started = Date()
    let hugeBlocks = ArisBoardContent.blocks(from: huge)
    let hugePieces = ArisAnswerDocument.pieces(from: huge)
    let took = Date().timeIntervalSince(started)
    if case .table(let header, let rows) = hugeBlocks.last {
        check(header.isEmpty && rows.count == ArisBoardContent.tableRows + 1 && rows.last == ["…"]
              && rows.allSatisfy { $0.count <= ArisBoardContent.tableColumns } && rows[0].count == ArisBoardContent.tableColumns && rows[0].last == "…",
              "table caps: at most \(ArisBoardContent.tableColumns) columns and \(ArisBoardContent.tableRows) rows, the rest as … (\(rows.count) rows)")
    } else { check(false, "table caps: the huge table parses as a table (\(hugeBlocks.count) blocks)") }
    check(took < 1, "table caps: a 20k-pipe row and 500 rows parse in under a second (\(took) s, \(hugePieces.count) pieces)")
    let longCell = ArisBoardContent.blocks(from: "| " + String(repeating: "가", count: 5_000) + " | b |")
    if case .table(_, let rows) = longCell.first {
        check(rows[0][0].count == ArisBoardContent.cellLength + 1 && rows[0][0].hasSuffix("…") && rows[0][1] == "b", "table caps: a cell is cut at \(ArisBoardContent.cellLength) characters")
    } else { check(false, "table caps: a long cell's row is a table") }
    check(ArisBoardContent.blocks(from: "| a | b |\n|---|---|\n| 1 | 2 |") == [.table(header: ["a", "b"], rows: [["1", "2"]])],
          "table caps: a small table is untouched")

    // I2: at most four lists and a key budget per note; the selection right before ⇧⌘L must be exactly the items.
    let six = ArisNoteMarkdown.plan("t\n" + (1...6).map { "### \($0)\n- [ ] 일 \($0)" }.joined(separator: "\n"))!
    let pressing = ArisNoteMarkdown.pressing(six)
    check(six.groups.count == 6 && pressing.lists.count == ArisNoteMarkdown.listLimit && pressing.skipped == 2
          && pressing.lists.map(\.group) == Array(six.groups.prefix(4)),
          "note caps: the first \(ArisNoteMarkdown.listLimit) lists get keys, the rest stay lines")
    let heavy = ArisNoteMarkdown.plan("t\n" + (1...4).map { n in (1...6).map { "메모 \(n)-\($0)\n" }.joined() + (1...30).map { "- [ ] \(n)-\($0)" }.joined(separator: "\n") }.joined(separator: "\n"))!
    let heavyPress = ArisNoteMarkdown.pressing(heavy)
    check(heavyPress.lists.reduce(0) { $0 + $1.keys.count } <= ArisNoteMarkdown.keyBudget && heavyPress.skipped > 0,
          "note caps: no more than \(ArisNoteMarkdown.keyBudget) keys a note (\(heavyPress.lists.count) lists pressed)")
    let shop = ArisNoteMarkdown.plan("장보기\n- [ ] **우유**\n- [ ] 계란")!
    check(ArisNoteMarkdown.selectionMatches("우유\n계란", group: shop.groups[0], plan: shop)
          && ArisNoteMarkdown.selectionMatches("우유\n계란\n", group: shop.groups[0], plan: shop)
          && !ArisNoteMarkdown.selectionMatches("우유", group: shop.groups[0], plan: shop)
          && !ArisNoteMarkdown.selectionMatches("장보기\n우유\n계란", group: shop.groups[0], plan: shop)
          && !ArisNoteMarkdown.selectionMatches("", group: shop.groups[0], plan: shop),
          "note keys: ⇧⌘L only when exactly the list's items are selected")

    // M1: bold and italics in one pass, nested properly; a lone marker stays.
    check(ArisNoteMarkdown.inline("**a *b* c**") == "<b>a <i>b</i> c</b>" && ArisNoteMarkdown.inline("*a **b** c*") == "<i>a <b>b</b> c</i>"
          && ArisNoteMarkdown.inline("**열린 *닫힌*") == "**열린 <i>닫힌</i>" && ArisNoteMarkdown.inline("2 * 3 * 4") == "2 * 3 * 4"
          && ArisNoteMarkdown.words("**a *b* c**") == "a b c",
          "note inline: emphasis nests (\(ArisNoteMarkdown.inline("**a *b* c**")), \(ArisNoteMarkdown.inline("**열린 *닫힌*")))")
    // M3: no control or format characters.
    let sneaky = ArisNoteMarkdown.plan("제\u{202E}목\u{0007}\n- [ ] 우\u{200B}유\tA")!
    check(sneaky.title == "제목" && sneaky.paragraphs[1] == "우유\tA" && !sneaky.html.contains("\u{202E}"),
          "note text: bidi overrides, zero-width and control characters are dropped (tabs kept)")
    // M4: lines are cut, so emphasis never runs long.
    let stars = String(repeating: "*a", count: 60_000)
    let starStart = Date()
    let starPlan = ArisNoteMarkdown.plan("t\n" + stars)
    check(Date().timeIntervalSince(starStart) < 1 && (starPlan?.paragraphs[1].count ?? .max) <= ArisNoteMarkdown.lineLength,
          "note text: a 120k-character line is cut at \(ArisNoteMarkdown.lineLength) and done quickly")
    check(ArisNoteMarkdown.plan((1...3_000).map { "줄 \($0)" }.joined(separator: "\n"))!.paragraphs.count == ArisNoteMarkdown.lineCount,
          "note text: at most \(ArisNoteMarkdown.lineCount) lines")
    // M7: a literal \n is a line break only in one-line markdown, never after a backslash.
    check(ArisNoteMarkdown.newlines("a\\nb") == "a\nb" && ArisNoteMarkdown.newlines("C:\\\\new") == "C:\\\\new"
          && ArisNoteMarkdown.newlines("코드\n\\n 그대로") == "코드\n\\n 그대로",
          "note text: \\n becomes a line only where it can't be a path or code")
    // M5: a hands-free turn asks before a note with lists (it would bring Notes forward); a plain note doesn't.
    check(ArisHandsFree.asks(.shell("/t note --markdown 'x\\n- [ ] y'"), tools: "/t") && ArisHandsFree.asks(.shell("/t note t --checklist a"), tools: "/t")
          && !ArisHandsFree.asks(.shell("/t note \"메모\""), tools: "/t"),
          "notes: a hands-free note with lists waits for the user's yes")
    // M6: 메모에 저장 sends at most 200 KB, cut at a line.
    let bigResult = "# 큰 결과\n" + String(repeating: "가나다라마바사 아자차카타파하\n", count: 20_000)
    let cut = ArisResultPath.noteMarkdown(bigResult)
    check(cut.utf8.count <= ArisResultPath.noteLimit + 4 && cut.hasSuffix("\n…") && cut.hasPrefix("# 큰 결과")
          && ArisResultPath.noteMarkdown("# 작은\n- [ ] a") == "# 작은\n- [ ] a",
          "reader note: a result over 200 KB is cut at a line")
    // M9: table pipes inside single quotes don't start commands; everything that could still does.
    let risk = { (command: String) in ArisRiskPolicy.risk(of: .shell(command), tools: "/t", home: "/Users/p") }
    check(risk("/t note --markdown '제목\\n| sudo | su |\\n| dd | 값 |'") != .never,
          "never: a note's table cells in single quotes aren't commands")
    // Audit gate-7: inside double quotes only $( and a backtick start a command; a pipe there is text.
    check(risk("echo \"| sudo x\"") != .never && risk("echo \"`sudo x`\"") == .never, "never: a pipe inside double quotes is text; a backtick there still runs")
    check(["echo 'x' ; sudo y", "echo \"$(sudo x)\"", "echo 'a' | sudo tee f",
           "true # '\nsudo rm x # '", "cat <<EOF\n'\nEOF\nsudo x\ncat <<EOF\n'\nEOF", "echo $'a\\'' ; sudo x ''", "echo 'open ; sudo x",
           "echo \\'x ; sudo y \\'"].allSatisfy { risk($0) == .never },
          "never: commands outside single quotes, comments, heredocs, $'…' and open quotes are still caught")
}
