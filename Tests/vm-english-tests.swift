// VM run 2026-11-10, bug 4: on an English Mac, Korean showed everywhere outside the settings window (the side notch's
// hover popover, the side panels, the chips under an answer, the confirm cards' buttons, the answer cards).
//
// The rule these tests hold: a label, tab, button, tooltip, empty state, card heading or date the app draws follows
// the Mac's UI language (ArisUIWords.english); a sentence said in answer to the user, and a confirm card's title and
// detail, follow the language of his request (`korean:` / `english:` where it is made).
//
// The first test reads the sources: in every file of the surfaces, a Korean string literal must have its English
// written beside it (ArisUIWords.text("한국어", "English"), or `korean ? "…" : "…"`), or be on the list of strings that
// are Korean on purpose. A new Korean label added without its English fails here.

import Foundation

func runVMEnglishTests() {
    vmEnglishSourceTests()
    vmEnglishSideTests()
    vmEnglishChipTests()
    vmEnglishCardTests()
    vmEnglishWidgetTests()
    vmEnglishSettingsPathTests()
}

// MARK: - reading the sources

/// The files of the surfaces: the side notch's popover and panels, the chips, the confirm card, the answer cards, and
/// the replies that name a settings page. Every Korean string in them has its English beside it or is listed below.
let vmEnglishFiles: [String] = [
    "Side/ArisActivityModel.swift",
    "Side/ArisActivityTimeline.swift",
    "Side/ArisActivityView.swift",
    "Side/ArisCalendarStrip.swift",
    "Side/ArisDayTimeline.swift",
    "Side/ArisLeftPanel.swift",
    "Side/ArisRightPanel.swift",
    "Side/ArisSidePanelView.swift",
    "Side/ArisSideTab.swift",
    "Side/ArisUsageCard.swift",
    "Side/ArisUsageWords.swift",
    "ArisHistory.swift",
    "ArisAgenda.swift",
    "ArisClipboardView.swift",
    "ArisTodoView.swift",
    "ArisTodoWords.swift",
    "ArisReminders.swift",
    "ArisTodoModel.swift",
    "Home/ArisConfirmCard.swift",
    "Home/ArisConfirmCard+Countdown.swift",
    "Home/ArisConfirmWords.swift",
    "Home/ArisEditableRows.swift",
    "Home/ArisDoneFold.swift",
    "Home/ArisDoneSummary.swift",
    "Home/ArisWidgetCards.swift",
    "Home/ArisStockMapCards.swift",
    "Home/ArisMusicStrip.swift",
    "ArisWidget.swift",
    "ArisWidgetStockMap.swift",
    "ArisTimerEar.swift",
    "ArisTimerWords.swift",
    "ArisTimerModel.swift",
    "ArisSettingsPath.swift",
    "ArisController+Look.swift",
    "ArisLocalReply.swift",
    "ArisUndoWords.swift",
    "ArisSaveAnswer.swift",
    "ArisConfirmReply.swift",
    "Team/ArisStatusLine.swift",
    "Team/ArisBubbleText.swift",
    "ArisUIDates.swift",
    // The pill's line, dictation's hints, the small tooltips, an undo's notices and Claude Code's notices.
    "ArisPanel.swift", "ArisDictationState.swift", "ArisDictationKey.swift", "ArisActivity.swift", "ArisController+Undo.swift",
    "../Claude/ClaudeNoticeLabel.swift", "../Claude/ClaudeNoticeView.swift",
    // The reader window and the circle gesture's hints.
    "ArisReaderView.swift", "ArisReaderDocument.swift", "Gesture/ArisGestureChrome.swift",
]

/// Korean on purpose, file by file: words matched in what the user says, Korean halves whose English a formatter or a
/// branch beside them writes (the tests below run those in English), and names the agent or the catalog is asked by.
let vmEnglishOnPurpose: [String: Set<String>] = [
    // the Korean halves of dates whose English a formatter writes
    "ArisReaderDocument.swift": ["yyyy년 M월 d일 a h:mm", "\\(Int(ago / 60))분 전", "\\(Int(ago / 3_600))시간 전", "M월 d일"],
    // the name the user says to train the wake word
    "ArisPanel.swift": ["Train “아리스”"],
    // the log's own lines, which the tab shows in English (ArisActivityWords), and the conversation's job name
    "Side/ArisActivityTimeline.swift": ["대화", "뽀모도로", "타이머 끔", "볼륨 올림", "볼륨 낮춤", "음소거 바꿈", "할 일 추가: ", "할 일 완료: ", "할 일 지움: ", "옮김: ", "이름 바꿈: ", "새 폴더: ", "휴지통으로: ", "일정 추가: ", "집 위치: ", "예약 취소: ", "예약: ", "변환: ", "합침: ", "나눔: ", "압축: ", "창 배치: ", "타이머: ", "볼륨 "],
    // the Korean hour label; the English one is written by a formatter
    "Side/ArisDayTimeline.swift": ["오전", "오후", "\\(hour < 12 ? \"오전\" : \"오후\") \\(h12)시"],
    // the tabs' Korean titles are the settings catalog's keys (name(english:) is what the panel draws); the popover hint's Korean half
    "Side/ArisSideTab.swift": ["기록", "한 일", "클립보드", "사용량", "할 일", "캘린더", "클릭", "로 열기", "해서 열기"],
    // the Korean halves of lines whose English a formatter writes
    "Side/ArisUsageWords.swift": ["\\(minutes)분 전에 업데이트", "\\(minutes / 60)시간 전에 업데이트", "\\(minutes / 1_440)일 전에 업데이트", "M월 d일 a h:mm", "M월 d일"],
    // the Korean halves of dates whose English a formatter writes
    "ArisHistory.swift": ["\\(Int(seconds / 60))분 전", "\\(Int(seconds / 3600))시간 전", "\\(parts.month ?? 0)월 \\(parts.day ?? 0)일", "오늘 \\(time)", "어제 \\(time)", "M월 d일 (E)"],
    // the Korean halves of dates whose English a formatter writes
    "ArisAgenda.swift": ["\\(minutes)분 후", "\\(minutes / 60)시간 후", "\\(minutes / 60)시간 \\(minutes % 60)분 후", "M월 d일 EEEE"],
    // the Korean half of the alert's time left
    "ArisTodoWords.swift": ["\\(minutes / 60)시간 남았어요", "\\(minutes)분 남았어요"],
    // said after `guard korean`: the spoken summary's Korean sentence
    "ArisTodoModel.swift": ["Canvas 마감은 \\(canvas.joined(separator: \", \"))예요."],
    // the agent's special yes words, matched as they come
    "Home/ArisConfirmWords.swift": ["설치", "로그인"],
    // words matched in a place's name, and the Korean halves of times whose English a formatter writes
    "ArisWidget.swift": ["여기", "집", "\\(clock)시", "오후", "오전", "\\(afternoon ? \"오후\" : \"오전\") \\(clock)시", "\\(minutes)분 뒤", "\\(hours)시간 뒤", "\\(hours)시간 \\(rest)분 뒤", "오늘", "내일", "어제", "M월 d일"],
    // the Korean halves of times whose English a formatter writes
    "ArisWidgetStockMap.swift": ["M월 d일 a h:mm", " 기준", "\\(minutes)분", "\\(minutes / 60)시간", "\\(minutes / 60)시간 \\(minutes % 60)분"],
    // the Korean announcement, beside its English
    "ArisTimerWords.swift": ["타이머", "\\(length) 끝났어요.", "뽀모도로", "\\(round)번째 집중 끝. \\(ArisIntent.duration(nextTotal)) 쉬어요.", "집중", "\\(length) 집중 끝났어요. 잠깐 쉬어요.", "쉬는 시간 끝. \\(nextRound)번째 집중 시작할게요."],
    // the settings window's Korean name, matched in a reply
    // … and the names pages had before the sidebar became 14 pages (a reply that still says one is pointed at the page that has its rows)
    "ArisSettingsPath.swift": ["설정", "(?:설정|Settings)(?:의)?\\\\s*[›>→]\\\\s*", "노치 기능", "캘린더", "할 일", "모양"],
    // the default key's name as the lines written for it carry it (they are rewritten to name the key in use), and the particle after it
    "ArisDictationKey.swift": ["오른쪽 ⌥를", "오른쪽 ⌥", "을", "를"],
    // a row's Korean name looked up in the settings catalog, Korean sentences joined to a reason, and the activity log's lines
    "ArisLocalReply.swift": ["미리 알림 접근이 꺼져 있어요. \\(place)에서 켜 주세요.", "미리 알림 접근", "할 일에 넣지 못했어요.", "체크하지 못했어요: \\(title).", "타이머: \\(max(1, seconds / 60))분", "뽀모도로", "타이머 끔"],
    // Korean sentences beside their English, particles, and Finder's Korean folder names
    "ArisUndoWords.swift": ["데스크탑", "문서", "다운로드", " 폴더", "폴더", "Mac이 \\(name.map { $0.0 + \" 폴더\" } ?? \"폴더\") 접근을 묻고 있어요. 허용하면 이어서 해요.", "‘\\(title)’ \\(noun)\\(ArisUndoWords.objectParticle(noun)) 되돌렸어요.", "를", "을",
                          // the Korean reply's own nouns, by the kind the log's Korean line starts with (the English reply uses the
                          // kind's English from ArisActivityWords), and the two kinds whose line ends with its time
                          "할 일 추가", "할 일 완료", "할 일 지움", "내일로 넘김", "일정 추가", "일정 삭제", "일정 변경", "예약", "예약 취소", "옮김", "이름 바꿈", "새 폴더", "휴지통으로", "집 위치",
                          "변환", "합침", "나눔", "압축", "창 배치", "타이머", "메시지 보냄", "미리 알림 추가", "메모 저장", "기억함", "기억 지움", "기본 캘린더", "메일 답장 초안",
                          "할 일", "일정", "옮긴 것", "이름 바꾼 것", "휴지통에 넣은 것", "합친 것", "나눈 것", "메시지", "미리 알림", "메모", "기억", "기억 지운 것"],
    // folders matched in what the user says, and the Korean card beside its English one
    "ArisSaveAnswer.swift": ["바탕화면", "데스크탑", "데스크톱", "문서 폴더", "문서", "다운로드", "파일로 저장", "저장할 것: 방금 답\\(warning)\\n위치: \\(shown(path))\\n새 파일로 만들어요 (같은 이름의 파일이 있으면 저장하지 않아요)\\n\\(shownPart)\\n\\(head)", "내용 (전체 \\(count)자 중 앞부분):", "내용 (전체 \\(count)자):", "메모 만들기", "저장할 것: 방금 답\\(warning)", "위치: 메모 앱 (새 메모)", "제목: "],
    // words matched in a spoken yes, and the Korean hint beside its English
    "ArisConfirmReply.swift": ["(?i)^\\\\s*((어|음)[\\\\s,.…]+)?", " 허락하시려면 허용을 누르거나 Y를 눌러 주세요."],
    // the Korean pill line beside its English, and a word matched in the agent's status
    "Team/ArisStatusLine.swift": ["\\(running)개 작업 중", "웹 검색"],
]

private func vmEnglishRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

private func vmEnglishSource(_ path: String) -> String {
    (try? String(contentsOf: vmEnglishRoot().appendingPathComponent(path), encoding: .utf8)) ?? ""
}

func vmEnglishHasHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

/// Surfaces added on the release candidate while this branch was open (the receipt chip, the working tag's stop
/// line, the day-end card, mute and quiet time, the drop chips): each has its own Korean and English copy file. They
/// are read here once they are on the branch (a file that isn't there yet is skipped); the on-purpose lists were made
/// from the release candidate at 007f4e90.
let vmEnglishLaterFiles: [String] = ["ArisReceiptWords.swift", "Home/ArisStopLine.swift", "DayEnd/ArisDayEndCopy.swift", "ArisQuietWords.swift", "Drop/ArisDropCopy.swift"]

let vmEnglishLaterOnPurpose: [String: Set<String>] = [
    // the activity log's labels the chip reads, Korean halves beside their English, and “한 일” as an English line still names the tab
    "ArisReceiptWords.swift": ["See them in the 한 일 tab", "한 일 탭에서 보기", "미리 알림 추가", "할 일 추가", "할 일 완료", "할 일 지움", "내일로 넘김", "일정 추가", "일정 삭제", "일정 변경", "이름 바꿈", "새 폴더", "예약", "예약 취소", "타이머", "타이머 끔", "뽀모도로", "창 배치", "집 위치", "메모 저장", "기억함", "기억 지움", "기본 캘린더", "음소거 바꿈", "변환", "합침", "나눔", "압축", "중간에 멈춤", "\\(count)개 ", "메시지 보냄", "옮김", "휴지통으로", "볼륨"],
    // the cancelled row's word as the job writes it, and the Korean line beside its English
    "Home/ArisStopLine.swift": ["취소됨", " 외 \\(more)건", "여기까지 했어요: \\(named)\\(more > 0 ? \" 외 \\(more)건\" : \"\"). 나머지는 멈췄어요.", " \\($0.text) 단계", "‘\\(words)’\\(status.count.map { \" \\($0.text) 단계\" } ?? \"\")에서 멈췄어요. 나머지는 안 했어요."],
    // the Korean sentence, written by a function of its own beside the English one (koreanSentence, englishSentence), the
    // number words both are said with
    "DayEnd/ArisDayEndCopy.swift": ["오늘 하려던 \\(things(counts.planned))", "모두 ", "\\(lead)를 \\(all)끝냈어요.", "\\(lead)가 아직 남았어요.", "\\(lead)를 \\(all)내일로 넘겼어요.",
                                    "\\(lead) 중 \\(things(counts.done))를 끝냈어요.", "\\(lead) 중 끝낸 건 아직 없어요.", "\\(things(counts.left))가 남았고", "\\(things(counts.left))가 남았어요",
                                    "\\(things(counts.moved))는 내일로 넘겼고", "\\(things(counts.moved))는 내일로 넘겼어요", "은", "는", "\\(who) 확인을 기다리고", "\\(who) 확인을 기다려요",
                                    "확인을 기다리는 일이 \\(alone(count)) 있어요.", "한", "두", "세", "네", "다섯", "여섯", "일곱", "여덟", "아홉", "하나", "둘", "셋", "넷", "열", "스물", "서른", "마흔",
                                    "쉰", "예순", "일흔", "여든", "아흔", "\\(count)가지", "스무 가지", " 가지", "\\(count)개"],
    // what the user says to mute and unmute, word by word
    "ArisQuietWords.swift": ["음소거 해제", "음소거 풀어", "음소거 풀고", "음소거 꺼", "음소거 끄", "음소거 그만", "말해도 돼", "말해도 되", "말해도 좋아", "말해도 괜찮아", "소리 내도 돼", "소리내도 돼", "목소리 켜", "조용히 해", "조용히 하", "조용히 있어", "조용히", "조용", "음소거", "목소리 꺼", "말 그만", "그만 말해", "쉿", "아리스", "이제", "이젠", "이제는", "지금", "지금은", "지금부터", "다시", "잠깐", "잠깐만", "잠시", "잠시만", "좀", "해", "해줘", "해봐", "해라", "줘", "주세요", "줄래", "주실래요", "주시겠어요", "줄", "수", "있어", "있어요", "하자", "모드", "로", "으로", "켜", "켜줘", "야", "요", "돼", "돼요", "응", "그래", "너", "넌", "는", "은", "도"],
    // languages' Korean names, the requests a chip sends in Korean beside their English, and notes for the AI
    "Drop/ArisDropCopy.swift": ["이 파일들 요약해 줘", "이 파일 요약해 줘", "이 영상들에서 오디오만 M4A로 뽑아 줘", "이 영상에서 오디오만 M4A로 뽑아 줘", "이 PDF들을 쪽마다 \\(name) 그림으로 바꿔 줘", "이 PDF를 쪽마다 \\(name) 그림으로 바꿔 줘", "이 파일들 한꺼번에 \\(name)로 바꿔 줘", "이 파일 \\(name)로 바꿔 줘", ". 변환하거나 합칠 때는 이 경로를 그대로 써요 (--finder, --shelf 아님)", "(그림에서 읽은 글자예요)", "\\(first) 외 \\(more)개가 없어졌어요. 다시 끌어다 놓아 주세요.", "\\(first) 파일이 없어졌어요. 다시 끌어다 놓아 주세요."],
]

/// A string literal of a Swift source: the code written before it since the literal before, its text as written, and
/// the literals inside each `\( )` of it.
struct VMEnglishLiteral {
    var before: String
    var text: String
    /// `#"…"#`: a pattern matched against words.
    var raw: Bool
    var inner: [[VMEnglishLiteral]] = []
}

/// The literals of a source, comments left out, level by level (a literal inside another's `\( )` is in its `inner`).
func vmEnglishLiterals(_ source: String) -> [VMEnglishLiteral] {
    let text = Array(source)
    var i = 0
    func at(_ offset: Int) -> Character? { i + offset < text.count ? text[i + offset] : nil }
    func literal() -> (String, [[VMEnglishLiteral]]) {
        // `i` is just past the opening quote.
        let start = i
        var inner: [[VMEnglishLiteral]] = []
        while i < text.count, text[i] != "\"" {
            if text[i] == "\\" {
                if at(1) == "(" { i += 2; inner.append(code(interpolation: true)); continue }
                i += 2
                continue
            }
            i += 1
        }
        let end = min(i, text.count)
        i += 1
        return (String(text[start..<end]), inner)
    }
    func code(interpolation: Bool) -> [VMEnglishLiteral] {
        var found: [VMEnglishLiteral] = []
        var before = ""
        var depth = 0
        while i < text.count {
            let c = text[i]
            if c == "/", at(1) == "/" {
                while i < text.count, text[i] != "\n" { i += 1 }
            } else if c == "/", at(1) == "*" {
                i += 2
                while i < text.count, !(text[i] == "*" && at(1) == "/") { i += 1 }
                i += 2
            } else if c == "#", at(1) == "\"" {
                i += 2
                let start = i
                while i < text.count, !(text[i] == "\"" && at(1) == "#") { i += 1 }
                found.append(VMEnglishLiteral(before: before, text: String(text[start..<min(i, text.count)]), raw: true))
                before = ""
                i += 2
            } else if c == "\"", at(1) == "\"", at(2) == "\"" {
                i += 3
                let start = i
                while i < text.count, !(text[i] == "\"" && at(1) == "\"" && at(2) == "\"") { i += 1 }
                found.append(VMEnglishLiteral(before: before, text: String(text[start..<min(i, text.count)]), raw: false))
                before = ""
                i += 3
            } else if c == "\"" {
                i += 1
                let (words, inner) = literal()
                found.append(VMEnglishLiteral(before: before, text: words, raw: false, inner: inner))
                before = ""
            } else {
                if interpolation {
                    if c == "(" { depth += 1 }
                    if c == ")" {
                        if depth == 0 { i += 1; return found }
                        depth -= 1
                    }
                }
                before.append(c)
                i += 1
            }
        }
        return found
    }
    return code(interpolation: false)
}

/// The Korean literals of a source that have no English beside them. One has when it is
///  - the Korean (first) string of `…text("한국어", "English"…)`, `line(…)` or `say(…)`, or of a pair `("한국어", "English")`;
///  - an agent status given to `ArisUIWords.status("…")`, which has the English (checked below);
///  - given as `korean:` (a date's Korean format, beside the `template:` the English is written from);
///  - the Korean side of `korean ? "한국어" : "English"` or `english ? "English" : "한국어"`;
///  - a `#"…"#` pattern: words matched in what the user says, never drawn.
func vmEnglishUnpaired(_ source: String) -> [String] {
    func ends(_ code: String, _ words: [String]) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.contains { trimmed.hasSuffix($0) }
    }
    func asks(_ code: String, _ language: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("?") else { return false }
        return trimmed.dropLast().trimmingCharacters(in: .whitespaces).lowercased().hasSuffix(language)
    }
    func only(_ code: String, _ sign: String) -> Bool { code.trimmingCharacters(in: .whitespacesAndNewlines) == sign }
    func unpaired(_ level: [VMEnglishLiteral]) -> [String] {
        var left: [String] = []
        for (index, literal) in level.enumerated() {
            left += literal.inner.flatMap(unpaired)
            // Its own words, the values written into it left out (their strings are looked at on their own).
            guard vmEnglishHasHangul(vmEnglishOwnWords(literal)), !literal.raw else { continue }
            let next = index + 1 < level.count ? level[index + 1] : nil
            let previous = index > 0 ? level[index - 1] : nil
            if ends(literal.before, ["text(", "line(", "say(", "status(", "korean:"]) { continue }
            // ("한국어", "English"): a pair in a table.
            if let next, !vmEnglishHasHangul(vmEnglishOwnWords(next)), only(next.before, ","), ends(literal.before, ["("]) { continue }
            if let next, !vmEnglishHasHangul(vmEnglishOwnWords(next)), only(next.before, ":"), asks(literal.before, "korean") { continue }
            if let previous, !vmEnglishHasHangul(vmEnglishOwnWords(previous)), only(literal.before, ":"), asks(previous.before, "english") { continue }
            left.append(literal.text)
        }
        return left
    }
    return unpaired(vmEnglishLiterals(source))
}

/// A literal's text with each `\( … )` taken out.
func vmEnglishOwnWords(_ literal: VMEnglishLiteral) -> String {
    guard !literal.inner.isEmpty else { return literal.text }
    var out = ""
    let text = Array(literal.text)
    var i = 0
    while i < text.count {
        if text[i] == "\\", i + 1 < text.count, text[i + 1] == "(" {
            i += 2
            var depth = 0
            var quoted = false
            while i < text.count {
                if text[i] == "\\" { i += 2; continue }
                if text[i] == "\"" { quoted.toggle() }
                if !quoted {
                    if text[i] == "(" { depth += 1 }
                    if text[i] == ")" { if depth == 0 { i += 1; break }; depth -= 1 }
                }
                i += 1
            }
            continue
        }
        out.append(text[i])
        i += 1
    }
    return out
}

private func vmEnglishSourceTests() {
    // The reader itself.
    let sample = """
    let a = ArisUIWords.text("닫기", "Close") // "주석"
    let b = korean ? "안 했어요." : "I left it."
    let c = english ? "Open" : "열기"
    let d = "그냥"
    let e = #"(응|네)"#
    let f = "\\(count)개 \\(done ? "끝" : "남음")"
    let g = ArisUIWords.text("\\(n)분 전", "\\(n) min ago", english: english)
    let h = other ? "가" : "b"
    let i = ArisUIDates.string(date, korean: "M월 d일", template: "MMMd")
    let j = ["음소거 바꿈": ("볼륨 바꿈", "Changed the volume")]
    """
    check(vmEnglishUnpaired(sample) == ["그냥", "끝", "남음", "\\(count)개 \\(done ? \"끝\" : \"남음\")", "가", "음소거 바꿈"],
          "english: a Korean string counts as switched only with its English beside it (text(…), korean ? … : …); a comment and a pattern are left out")

    for file in vmEnglishFiles {
        let source = vmEnglishSource("Aris/private/Aris/" + file)
        let allowed = vmEnglishOnPurpose[file] ?? []
        let left = vmEnglishUnpaired(source).filter { !allowed.contains($0) }
        check(!source.isEmpty && left.isEmpty, "english: every Korean string in \((file as NSString).lastPathComponent) has its English beside it" + (left.isEmpty ? "" : " (\(left.prefix(3)))"))
    }
    check(Set(vmEnglishOnPurpose.keys).isSubset(of: Set(vmEnglishFiles)), "english: the on-purpose list names only files that are read")
    for file in vmEnglishLaterFiles {
        let source = vmEnglishSource("Aris/private/Aris/" + file)
        guard !source.isEmpty else { continue }
        let allowed = vmEnglishLaterOnPurpose[file] ?? []
        let left = vmEnglishUnpaired(source).filter { !allowed.contains($0) }
        check(left.isEmpty, "english: every Korean string in \((file as NSString).lastPathComponent) has its English beside it" + (left.isEmpty ? "" : " (\(left.prefix(3)))"))
    }
}

// MARK: - the side notch: the popover, the tabs, the dates

private let vmUS = Locale(identifier: "en_US")
private func vmCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}
private func vmDate(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    vmCalendar().date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}
/// English: no Korean left, and the words it should carry.
private func vmEnglish(_ text: String, _ words: String...) -> Bool {
    !vmEnglishHasHangul(text) && words.allSatisfy { text.contains($0) }
}

private func vmEnglishSideTests() {
    check(ArisSideTab.allCases.map { $0.name(english: true) } == ["History", "Activity", "Clipboard", "Usage", "To-dos", "Calendar"]
          && ArisSideTab.allCases.map { $0.name(english: false) } == ArisSideTab.allCases.map(\.title) && ArisSideTab.history.title == "기록",
          "side: the tabs are named in English on an English Mac, and in Korean as before (the settings catalog's keys stay Korean)")
    let key = ArisSideMenu.openHint(byKey: true, english: true), click = ArisSideMenu.openHint(byKey: false, english: true)
    let korean = ArisSideMenu.openHint(byKey: true, english: false)
    check(key.lead == "Open with" && key.key == "⌃⌥V" && key.tail.isEmpty && click.key == "a click" && korean.lead.isEmpty && korean.key == "⌃⌥V" && korean.tail == "로 열기"
          && ArisSideMenu.openHint(byKey: false, english: false).tail == "해서 열기",
          "side: the hover popover says “Open with ⌃⌥V” in English and “⌃⌥V 로 열기” in Korean")

    // 기록: the group headings and the times.
    let zone = TimeZone(identifier: "America/New_York")!, now = vmDate(11, 10, 15)
    let today = ArisHistory.sessionHeader(vmDate(11, 10, 8, 23), now: now, timeZone: zone, english: true, locale: vmUS)
    let earlier = ArisHistory.sessionHeader(vmDate(10, 20, 15, 42), now: now, timeZone: zone, english: true, locale: vmUS)
    check(vmEnglish(today, "Today", "8:23") && vmEnglish(ArisHistory.sessionHeader(vmDate(11, 9, 8, 23), now: now, timeZone: zone, english: true, locale: vmUS), "Yesterday", "8:23")
          && vmEnglish(earlier, "Oct", "20", "3:42") && ArisHistory.sessionHeader(vmDate(11, 10, 8, 23), now: now, timeZone: zone, english: false) == "오늘 오전 8:23",
          "side: 기록's headings read “Today, 8:23 AM” on an English Mac, written by the system's formatter, and “오늘 오전 8:23” as before (\(today) / \(earlier))")
    check(ArisHistory.when(now.addingTimeInterval(-20), now: now, timeZone: zone, english: true, locale: vmUS) == "Just now"
          && vmEnglish(ArisHistory.when(now.addingTimeInterval(-300), now: now, timeZone: zone, english: true, locale: vmUS), "5")
          && ArisHistory.when(vmDate(11, 9, 8), now: now, timeZone: zone, english: true, locale: vmUS) == "Yesterday"
          && vmEnglish(ArisHistory.when(vmDate(10, 20, 8), now: now, timeZone: zone, english: true, locale: vmUS), "Oct", "20")
          && ArisHistory.when(now.addingTimeInterval(-300), now: now, timeZone: zone, english: false) == "5분 전",
          "side: how long ago a turn was is said in English too")
    check(vmEnglish(ArisUIDates.time(vmDate(11, 10, 15, 5), english: true, calendar: vmCalendar(), locale: Locale(identifier: "en_GB")), "15:05")
          && ArisUIDates.time(vmDate(11, 10, 15, 5), english: false, calendar: vmCalendar()) == "오후 3:05" && ArisUIDates.day(vmDate(11, 10, 15), english: false, calendar: vmCalendar()) == "11월 10일"
          && ArisUIDates.englishLocale(current: Locale(identifier: "en_GB")).identifier == "en_GB" && ArisUIDates.englishLocale(current: Locale(identifier: "fr_FR")).identifier == "en_US",
          "dates: an English Mac's own region keeps its clock and order (en_GB: 15:05); a Mac in another language reads US English; Korean is exactly as it was")
    check(ArisUIDates.length(minutes: 150, locale: vmUS) == "2h 30m" && ArisUIDates.length(minutes: 45, locale: vmUS) == "45m" && vmEnglish(ArisUIDates.length(minutes: 1_560, locale: vmUS), "1d", "2h")
          && vmEnglish(ArisUIDates.lengthInWords(seconds: 1_500, locale: vmUS), "25 minutes") && vmEnglish(ArisUIDates.relative(seconds: -180, locale: vmUS), "3", "ago"),
          "dates: a length of time and how long ago come from the system's formatters")

    // 한 일.
    check(ArisActivityTab.footer(teammates: 1, today: 4, english: true) == "1 teammate · 4 today" && ArisActivityTab.footer(teammates: 2, today: 4, english: false) == "팀원 2명 · 오늘 4개"
          && ArisActivityTab.dayTitle(name: "Cody", role: "code", english: true) == "Cody · code · Today" && ArisActivityTab.dayTitle(name: "코디", role: nil, english: false) == "코디 · 오늘"
          && ArisActivityTab.undoPhrase(english: true) == "“undo that”" && ArisActivityTab.undoWord(english: true) == "Undo" && vmEnglish(ArisActivityTab.refusedNotice(english: true), "actions.log")
          && ArisIntent.parse("undo that") == .undo,
          "side: 한 일's footer, headings and undo read English, and the phrase it offers is one Aris takes")
    let log = ["할 일 추가: buy milk": "To-do added: buy milk", "변환: 3개 → PNG": "Converted: 3 → PNG", "합침: a.pdf 외 2개 → all.pdf": "Merged: a.pdf and 2 more → all.pdf",
               "타이머: 25분": "Timer: 25 min", "뽀모도로": "Pomodoro", "볼륨 40": "Volume 40", "옮김: 사과 3개.pdf → 문서": "Moved: 사과 3개.pdf → 문서",
               "예약 취소: standup (매일 09:00)": "Schedule cancelled: standup (every day at 09:00)", "something else": "something else"]
    check(log.allSatisfy { ArisActivityWords.shown($0.key, english: true) == $0.value } && log.keys.allSatisfy { ArisActivityWords.shown($0, english: false) == $0 },
          "side: a line of the activity log is drawn in English with its names as they are, and the log itself is never changed")
    check(ArisActivityTab.confirmation(id: "a", summary: "일정 추가: 회의", revivesSchedule: false, english: true).detail == "일정 추가: 회의"
          && ArisActivityTab.confirmation(id: "a", summary: "x", revivesSchedule: true, english: true).title == "Bring the schedule back",
          "side: an undo's card keeps the log's own line as its detail (the agent checks it), under an English title")

    // 사용량.
    let reset = now.addingTimeInterval(4 * 3_600 + 12 * 60)
    let pace = ArisUsagePace(expectedUsedPercent: 40, deltaPercent: -6, etaSeconds: nil, willLastToReset: true)
    let behind = ArisUsagePace(expectedUsedPercent: 40, deltaPercent: 28, etaSeconds: 7 * 3_600 + 240, willLastToReset: false)
    check(ArisUsageWords.resets(reset, now: now, english: true, locale: vmUS) == "Resets in 4h 12m" && ArisUsageWords.resets(reset, now: now, english: false) == "4시간 12분 후 재설정"
          && ArisUsageWords.remaining(ArisUsageWords.session(english: true), percent: 62, english: true) == "Session 62% left"
          && ArisUsageWords.pace(pace, now: now, english: true, locale: vmUS) == "6% to spare · lasts until the reset" && ArisUsageWords.pace(pace, now: now, english: false) == pace.line(now: now)
          && ArisUsageWords.pace(behind, now: now, english: true, locale: vmUS) == "28% over the pace · runs out in 7h 4m",
          "side: 사용량's limits, resets and pace read English, the lengths of time from a formatter; Korean is ArisUsage's own line")
    check(ArisUsageWords.updated(minutes: 0, english: true) == "Updated just now" && vmEnglish(ArisUsageWords.updated(minutes: 12, english: true, locale: vmUS), "Updated", "12")
          && ArisUsageWords.updated(minutes: 12, english: false) == "12분 전에 업데이트" && ArisUsageWords.week(1, english: true) == "Last week" && ArisUsageWords.week(5, english: false) == "2주 전"
          && vmEnglish(ArisUsageWords.range(vmDate(11, 3, 9), vmDate(11, 10, 9), withTime: true, english: true, calendar: vmCalendar(), locale: vmUS), "Nov 3", "Nov 10", "9:00")
          && ArisUsageWords.range(vmDate(11, 3, 9), vmDate(11, 10, 9), withTime: false, english: false, calendar: vmCalendar()) == "11월 3일 – 11월 10일",
          "side: 사용량's update time and its weeks' dates read English")
    let words = [ArisUsageWords.loading(english: true), ArisUsageWords.costLoading(english: true), ArisUsageWords.weekly(english: true), ArisUsageWords.today(english: true),
                 ArisUsageWords.thisWeek(english: true), ArisUsageWords.todayTokens(english: true), ArisUsageWords.weekTokens(english: true), ArisUsageWords.monthCost(english: true),
                 ArisUsageWords.monthTokens(english: true), ArisUsageWords.recentWeeks(english: true), ArisUsageWords.topModel("opus", english: true), ArisUsageWords.costNote(english: true)]
    check(words.allSatisfy { !vmEnglishHasHangul($0) && !$0.isEmpty }, "side: every label of the 사용량 tab has its English")

    // 할 일 and 캘린더.
    let calendar = vmCalendar()
    let timed = ArisTodoItem(id: "a", title: "report", due: vmDate(11, 10, 15), hasTime: true, listID: "l", listName: "List", colorHex: "#ffffff")
    let later = ArisTodoItem(id: "b", title: "milk", due: vmDate(11, 14, 0), hasTime: false, listID: "l", listName: "List", colorHex: "#ffffff")
    check(vmEnglish(timed.dueLabel(now: now, calendar: calendar, english: true, locale: vmUS) ?? "가", "Today", "3:00")
          && vmEnglish(later.dueLabel(now: now, calendar: calendar, english: true, locale: vmUS) ?? "가", "Sat", "Nov 14") && timed.dueLabel(now: now, calendar: calendar, english: false) == timed.dueText(now: now, calendar: calendar)
          && ArisTodoGroup.allCases.map { $0.name(english: true) } == ["Overdue", "Today", "Tomorrow", "This week", "Later", "No date"] && ArisTodoGroup.today.name(english: false) == "오늘",
          "side: a to-do's due date and the groups' headings read English")
    check(vmEnglish(ArisDue.whenLabel(vmDate(11, 10, 17), now: now, calendar: calendar, english: true, locale: vmUS).0, "Today", "17:00") && ArisDue.whenLabel(vmDate(11, 11, 17), now: now, calendar: calendar, english: true, locale: vmUS).0 == "Tomorrow"
          && ArisDue.whenLabel(vmDate(11, 10, 17), now: now, calendar: calendar, english: false).0 == "오늘 17:00" && ArisTodoWords.left(minutes: 130, english: true, locale: vmUS) == "2h left"
          && ArisTodoWords.left(minutes: 45, english: false) == "45분 남았어요" && ArisTodoWords.deadlines(demo: false, english: true) == "Canvas deadlines"
          && vmEnglish(ArisTodoWords.failed(.save, "disk full", english: true), "disk full") && ArisTodoWords.failed(.missing, english: false) == "항목을 찾지 못했어요. 새로 고친 후 다시 시도해 주세요.",
          "side: a deadline's tag, the alert's time left and Reminders' errors read English")
    check(ArisAgenda.dayTitle(now, now: now, calendar: calendar, english: true) == "Today" && vmEnglish(ArisAgenda.dayTitle(vmDate(11, 14, 9), now: now, calendar: calendar, english: true, locale: vmUS), "Saturday", "Nov 14")
          && ArisAgenda.dayTitle(vmDate(11, 14, 9), now: now, calendar: calendar, english: false) == "11월 14일 토요일" && ArisAgenda.until(now.addingTimeInterval(135 * 60), now: now, english: true, locale: vmUS) == "in 2h 15m"
          && ArisAgenda.until(now.addingTimeInterval(135 * 60), now: now, english: false) == "2시간 15분 후"
          && vmEnglish(ArisAgenda.timeRange(vmDate(11, 10, 15), vmDate(11, 10, 16), calendar: calendar, english: true, locale: vmUS), "3:00", "4:00", "PM")
          && ArisAgenda.timeRange(vmDate(11, 10, 15), vmDate(11, 10, 16), calendar: calendar, english: false) == "오후 3:00 – 4:00",
          "side: 캘린더's day, how far off an event is and its hours read English, from the system's formatters")
}

// MARK: - the chips under an answer

private func vmEnglishChipTests() {
    // Every status the agent's table can send has its English.
    let table = vmEnglishLiterals(vmEnglishSource("ArisAgent/ArisAgentStatus.swift")).filter { vmEnglishHasHangul($0.text) && $0.inner.isEmpty }.map(\.text)
    let left = table.filter { vmEnglishHasHangul(ArisUIWords.status($0, english: true)) }
    check(table.count > 50 && left.isEmpty, "chips: every status of the agent's table is shown in English on an English Mac" + (left.isEmpty ? "" : " (\(left.prefix(4)))"))
    let others = ["Aside가 브라우저에서 하는 중", "Aside 로그인 코드를 받는 중", "컴퓨터 사용 도구 설치 중…", "Aris에 손쉬운 사용 권한을 켜 주세요", "Aris에 기기 제어 및 데이터 접근 권한을 켜 주세요", "Claude Code 여는 중", "확인 기다리는 중",
                  "Aris가 대신 읽는 중", "Aris가 판단해서 진행", "읽기 막음 · 요청하지 않은 일이라 막았어요", "읽기 막음 · 판단 못 했어요", "대기 중", "확인 중", "영상·소리 변환하는 중 (3분째)"]
    check(others.allSatisfy { !vmEnglishHasHangul(ArisUIWords.status($0, english: true)) } && others.allSatisfy { ArisUIWords.status($0, english: false) == $0 },
          "chips: Aside's, a teammate's and the read gate's status lines are English too, and Korean as they came")
    check(ArisUIWords.status("카카오톡에서 입력 중…", english: true) == "Typing in 카카오톡…" && ArisUIWords.status("Safari 보는 중…", english: true) == "Looking at Safari…"
          && ArisUIWords.status("메모에서 누르는 중…", english: true) == "Working in 메모…" && ArisUIWords.status("Claude 한도 → Codex", english: true) == "Claude limit → Codex"
          && ArisUIWords.status("something new", english: true) == "something new",
          "chips: computer use's line keeps the app's name, and a status with no English comes as it is")
    // The app's own status words go through the same table.
    let look = vmEnglishSource("Aris/private/Aris/ArisController+Look.swift")
    check(look.contains(#"session.working(ArisUIWords.status("화면 보는 중"))"#) && ArisUIWords.status("화면 보는 중", english: true) == "Looking at the screen",
          "chips: “화면 보는 중” under a screen question is shown in the UI's language (it was Korean under an English answer)")
    let task = ArisBackgroundTask(id: UUID(), title: "report", state: .working("웹 검색 중"))
    check(ArisDoneFold.label(task, english: true) == "report · Searching the web" && ArisDoneFold.label(task, english: false) == "report · 웹 검색 중"
          && ArisDoneFold.count(3, english: true) == "3 done" && ArisDoneFold.count(3, english: false) == "3개 끝남" && ArisDoneFold.detail(task, english: true) == "Searching the web"
          && ArisDoneFold.more(ArisDoneFold.trayRows + 2, english: true) == "+2 more · in the History tab",
          "chips: a background job's tag and the done chip read English")
    check(ArisBubbleText.text(for: .running(step: "웹 검색 중"), korean: false) == "Searching the web" && ArisBubbleText.text(for: .running(step: "웹 검색 중"), korean: true) == "웹 검색 중"
          && ArisStatusLine.phase(fromStatus: "웹 검색 중") == .searching,
          "chips: a teammate's bubble says the step in the language it speaks; the step itself stays as the agent sent it")
}

// MARK: - the confirm card

private func vmEnglishCard(_ title: String, _ detail: String = "") -> ArisConfirmation { ArisConfirmation(id: "c", title: title, detail: detail) }

private func vmEnglishCardTests() {
    check(ArisCardEnglish.isEnglish(request: "make a folder called qa on my desktop", uiEnglish: false) && !ArisCardEnglish.isEnglish(request: "바탕화면에 qa 폴더 만들어 줘", uiEnglish: true)
          && ArisCardEnglish.isEnglish(request: "", uiEnglish: true) && !ArisCardEnglish.isEnglish(request: " ", uiEnglish: false),
          "card: a card is in the language of the request it answers; with no request, the Mac's")
    // The buttons follow the card, so it is one language through and through.
    check(ArisConfirmWords.cancel(english: true) == "Cancel" && ArisConfirmWords.allow(nil, sends: false, english: true) == "Allow" && ArisConfirmWords.allow(nil, sends: true, english: true) == "Send"
          && ArisConfirmWords.allow(nil, sends: false, english: false) == "허용" && ArisConfirmWords.allow(nil, sends: true, english: false) == "보내기" && ArisConfirmWords.cancel(english: false) == "취소"
          && ArisConfirmWords.allow("설치", sends: false, english: true) == "Install" && ArisConfirmWords.allow("Sign in", sends: false, english: false) == "로그인"
          && ArisConfirmWords.whole(expanded: false, english: true) == "Show all" && ArisConfirmWords.noHelp(english: true) == "No (N)" && ArisConfirmWords.yesHelp(english: false) == "응 (Y)"
          && vmEnglish(ArisConfirmWords.refused(time: true, english: true), "2026-11-06 18:00") && ArisConfirmWords.was(english: true) == "Was ",
          "card: 취소, 허용, 보내기 and the card's hints have their English, and the yes button's special word is drawn in the card's language")
    check(vmEnglishCard("Aside", "").allow == nil && ArisConfirmation(id: "c", title: "t", detail: "", allow: "Install").allow == "Install"
          && ArisConfirmation(id: "c", title: "t", detail: "", allow: "설치").allow == "설치" && ArisConfirmation(id: "c", title: "t", detail: "", allow: "Run it").allow == nil,
          "card: Aside's English cards keep their “Install” and “Sign in” (they were dropped, leaving 허용), and any other word is still dropped")

    // The agent's Korean card, drawn in English.
    let titles = vmEnglishLiterals(vmEnglishSource("ArisAgent/ArisCardWords.swift")).filter { literal in
        let before = literal.before.trimmingCharacters(in: .whitespacesAndNewlines)
        return vmEnglishHasHangul(vmEnglishOwnWords(literal)) && literal.inner.isEmpty && (before.hasSuffix("return (") || before.hasSuffix("? (") || before.hasSuffix(": ("))
    }.map(\.text)
    let untitled = titles.filter { vmEnglishHasHangul(ArisCardEnglish.title($0)) }
    check(titles.count >= 20 && untitled.isEmpty, "card: every title ArisCardWords gives a card has its English" + (untitled.isEmpty ? "" : " (\(untitled.prefix(4)))"))
    let driver = ["메시지 보내기", "메일 보내기", "휴지통으로 옮기기", "키 누르기", "입력하기", "새 창 열기", "창 배치", "창 옮기기", "앱 열기", "링크 열기", "폴더 열기", "음악", "볼륨", "미리 알림", "일정 추가",
                  "메모", "클립보드", "단축어 실행", "기억하기", "잊기", "타이머", "지도 열기", "파일 변환하기", "파일 합치기", "PDF 나누기", "용량 줄이기", "Mac 작업", "길 찾기", "명령 실행", "되돌리기",
                  "파일 수정", "읽기 확인", "컴퓨터 사용 코드 실행", "일정 지우기", "일정 바꾸기", "파일 옮기기", "새 폴더 만들기", "앞으로 이건 그냥 할까?", "Claude Code 열기", "창 닫기", "앱 종료", "설정 파일 수정", "Mac 재시동", "Mac 끄기", "로그아웃", "Mac 잠자기",
                  "미리 알림 · 추가", "메모 · 찾기", "폴더 만들기 · 옮기기", "Safari 제어", "명령 실행 (python3)", "컴퓨터 사용 · click"]
    let undone = driver.filter { vmEnglishHasHangul(ArisCardEnglish.title($0)) }
    check(undone.isEmpty && ArisCardEnglish.title("폴더 만들기") == "New folder" && ArisCardEnglish.title("미리 알림 · 추가") == "Reminder · Add" && ArisCardEnglish.title("Safari 제어") == "Control Safari"
          && ArisCardEnglish.title("명령 실행 (python3)") == "Run command (python3)" && ArisCardEnglish.title("Click") == "Click" && ArisCardEnglish.title("새로운 제목") == "새로운 제목",
          "card: the agent's titles are drawn in English in the agent's own words (ArisGateWords): a noun with its verb, several commands, an app's name kept; an unknown one as it came" + (undone.isEmpty ? "" : " (\(undone.prefix(4)))"))
    check(ArisCardEnglish.detail("바탕화면 › qa-test", title: "폴더 만들기") == "Desktop › qa-test" && ArisCardEnglish.detail("새 폴더", title: "폴더 만들기") == "New folder"
          && ArisCardEnglish.detail("문서 › a.txt → b.txt", title: "이름 바꾸기") == "Documents › a.txt → b.txt" && ArisCardEnglish.detail("홈", title: "폴더 열기") == "Home",
          "card: a file card's path is named as Finder names it in English (“바탕화면 › qa-test” → “Desktop › qa-test”)")
    check(ArisCardEnglish.detail("받는 사람: 엄마\n내용: 문 열기", title: "메시지 보내기") == "To: 엄마\nText: 문 열기"
          && ArisCardEnglish.detail("새 폴더", title: "할 일에 넣기") == "새 폴더" && ArisCardEnglish.detail("제목: 문서 › 열기\n바탕화면 › 정리\n…(3줄 더)", title: "메모 만들기") == "Title: 문서 › 열기\n바탕화면 › 정리\n…(3 more lines)"
          && ArisCardEnglish.detail("빈 메모", title: "메모 만들기") == "Empty note",
          "card: the user's own words on a card (a message, a to-do, a note's lines) are never translated, only the labels beside them")
    check(ArisCardEnglish.detail("TextEdit ‘무제’ 창에 입력하기\n입력하는 글:\n창 닫기", title: "입력하기") == "Type in the TextEdit window “무제”\nText to type:\n창 닫기"
          && ArisCardEnglish.detail("TextEdit 창 닫기", title: "창 닫기") == "Close the TextEdit window" && ArisCardEnglish.detail("Safari 종료", title: "앱 종료") == "Quit Safari"
          && ArisCardEnglish.detail("Finder의 메뉴 누르기", title: "메뉴 누르기") == "Choose a menu item in Finder",
          "card: a desktop card's first line says what is done in which window, and the text to type stays as it is")
    check(ArisCardEnglish.detail("저장할 것: 방금 답\n위치: 메모 앱 (새 메모)\n제목: 회의", title: "메모 만들기") == "Saving: the last answer\nWhere: Notes (a new note)\nTitle: 회의"
          && ArisCardEnglish.detail("위치: 바탕화면 › a.txt", title: "파일로 저장") == "Where: Desktop › a.txt" && ArisCardEnglish.label("받는 사람") == "To" && ArisCardEnglish.label("메모장") == "메모장"
          && ArisCardEnglish.detail("TextEdit 창에 입력하기\n입력하는 글:\n메모 창 닫기", title: "입력하기").hasSuffix("Text to type:\n메모 창 닫기"),
          "card: a row's label and an agent-written value are English where the card draws them; the text to type is never taken for a line of the agent's")
    check(ArisCardEnglish.detail("Type in Notes", title: "Type") == "Type in Notes" && ArisCardEnglish.detail("캘린더 일정이 지워져요: 일정 추가: 회의", title: "되돌리기") == "A calendar event will be removed: 일정 추가: 회의",
          "card: a card the agent wrote in English is left alone, and an undo's line keeps the log's words after its warning")

    // What Aris says when it asks.
    let folder = vmEnglishCard("폴더 만들기", "바탕화면 › qa")
    check(ArisConfirmReply.question(for: folder, english: true) == "New folder. Shall I go ahead?" && ArisConfirmReply.question(for: folder, english: false) == "폴더 만들기, 해도 될까요?"
          && ArisConfirmReply.question(for: folder) == "폴더 만들기, 해도 될까요?" && ArisConfirmReply.question(for: vmEnglishCard("Click")) == "Click. Shall I go ahead?"
          && ArisConfirmReply.question(for: folder, voiceYes: false, english: true) == "New folder. Shall I go ahead? To allow it, press Allow or the Y key."
          && ArisConfirmReply.question(for: folder, voiceYes: false) == "폴더 만들기, 해도 될까요? 허락하시려면 허용을 누르거나 Y를 눌러 주세요.",
          "card: the question is asked in the card's language and names the button as the card draws it")

    // The app's own save cards follow the request too.
    let file = ArisSaveAnswer.card(path: "~/Desktop/a.txt", text: "hello\nworld", outside: true, korean: false), note = ArisSaveAnswer.noteCard(text: "Title\nbody", korean: false)
    check(file.title == "Save as a file" && file.detail.contains("Saving: the last answer\n⚠️ This answer holds text from outside") && file.detail.contains("Where: 바탕화면 › a.txt\nA new file is made")
          && file.detail.contains("Text (all 11 characters):\nhello") && note.title == "New note" && vmEnglish(note.detail, "Where: Notes", "Title: Title")
          && ArisSaveAnswer.card(path: "~/Desktop/a.txt", text: "hello").title == "파일로 저장" && ArisSaveAnswer.noteCard(text: "제목\n본문").detail.contains("위치: 메모 앱 (새 메모)"),
          "card: the save-answer cards are English for an English request and Korean as before")
    check(ArisSaveAnswer.shown("~/Desktop/a.txt", english: true) == "Desktop › a.txt" && ArisSaveAnswer.shown("~/qa/a.txt", english: true) == "Home › qa › a.txt"
          && ArisSaveAnswer.shown("~/Desktop/a.txt", english: false) == "바탕화면 › a.txt",
          "card: a saved file's place is named as Finder names it on this Mac")
    check(ArisCardTime.friendly("2026-11-11 18:00", now: vmDate(11, 10, 9), calendar: vmCalendar(), english: true, locale: vmUS).map { vmEnglish($0, "Tomorrow", "6:00") } == true
          && ArisCardTime.friendly("2026-11-11 18:00", now: vmDate(11, 10, 9), calendar: vmCalendar()) == "내일 오후 6:00",
          "card: the time under a field is said in the card's language")
}

// MARK: - the answer cards

private func vmEnglishWidgetTests() {
    let object: [String: Any] = ["place": "Orlando", "temp": 6, "code": 0, "high": 11, "low": 3, "hours": [["hour": 4, "code": 2, "temp": 5], ["hour": 15, "code": 61, "temp": 9]]]
    let weather = ArisWeatherCard.parse(object, english: true, locale: vmUS), korean = ArisWeatherCard.parse(object, english: false)
    check(weather?.hours.first?.label == "Now" && weather.map { vmEnglish($0.hours[1].label, "4", "AM") && vmEnglish($0.hours[2].label, "3", "PM") } == true
          && weather?.range(english: true) == "High 11° Low 3°" && korean?.hours.map(\.label) == ["지금", "오전 4시", "오후 3시"] && korean?.range(english: false) == "최고 11° 최저 3°",
          "weather: 지금, the hours and 최고 · 최저 read “Now”, “4 AM”, “High 11° Low 3°” on an English Mac")
    let codes = [0, 1, 2, 3, 45, 48, 51, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 82, 85, 86, 95, 99, 123]
    check(codes.allSatisfy { !vmEnglishHasHangul(ArisWeatherCard.condition($0, english: true)) } && ArisWeatherCard.condition(0, english: true) == "Clear" && ArisWeatherCard.condition(0, english: false) == "맑음",
          "weather: every sky has its English word")
    let now = vmDate(11, 10, 9), calendar = vmCalendar()
    let events = [ArisWidgetEvent(start: vmDate(11, 10, 10), end: vmDate(11, 10, 11), title: "", location: nil, allDay: false),
                  ArisWidgetEvent(start: vmDate(11, 10, 0), end: vmDate(11, 11, 0), title: "trip", location: nil, allDay: true)]
    let day = ArisCalendarCard.make(events, now: now, calendar: calendar, english: true, locale: vmUS)
    check(vmEnglish(day.trailing, "Tuesday", "Nov 10", "· 2") && day.rows.map(\.time).contains("All day") && day.rows.map(\.title).contains("No title") && day.rows.compactMap(\.chip) == ["in 1h"]
          && ArisCalendarCard.make(events, now: now, calendar: calendar, english: false).trailing == "11월 10일 화요일 · 2개" && ArisCalendarCard.chip(events[0], now: vmDate(11, 10, 10, 30), english: true) == "Now",
          "calendar card: the date, 종일, 제목 없음 and how far off the next event is read English")
    check(vmEnglish(ArisTodoCard.dueText(vmDate(11, 10, 23, 59), hasTime: true, now: now, calendar: calendar, english: true, locale: vmUS), "Today", "23:59")
          && ArisTodoCard.dueText(vmDate(11, 12, 9), hasTime: false, now: now, calendar: calendar, english: true, locale: vmUS) == "Thursday"
          && vmEnglish(ArisTodoCard.dueText(vmDate(11, 20, 9), hasTime: false, now: now, calendar: calendar, english: true, locale: vmUS), "Nov 20")
          && ArisTodoCard.dueText(vmDate(11, 10, 23, 59), hasTime: true, now: now, calendar: calendar, english: false) == "오늘 23:59",
          "to-do card: when a to-do is due reads English")
    let timer = ArisTimerState.start(seconds: 600, phase: .plain, at: now)
    check(timer.cardLabel(english: true) == "Timer · 10 min" && timer.cardLabel(english: false) == "타이머 · 10분",
          "timer card: its line reads “Timer · 10 min”")
    let ended = ArisTimerWords.ended(.plain, cycle: false, round: 1, total: 1_500, nextTotal: 0, nextRound: 1, english: true, locale: vmUS)
    let rest = ArisTimerWords.ended(.focus, cycle: true, round: 2, total: 1_500, nextTotal: 300, nextRound: 2, english: true, locale: vmUS)
    check(ended.title == "Timer" && ended.text == "25 minutes is up." && rest.title == "Pomodoro" && vmEnglish(rest.text, "round 2", "5 minutes")
          && ArisTimerWords.ended(.plain, cycle: false, round: 1, total: 1_500, nextTotal: 0, nextRound: 1, english: false) == ("타이머", "\(ArisIntent.duration(1_500)) 끝났어요."),
          "timer: what Aris announces when it ends is in the Mac's language (nobody asked just then)")
    let saved = vmDate(11, 5, 15, 41), zone = TimeZone(identifier: "America/New_York")!
    check(vmEnglish(ArisReaderDocument.meta(modified: saved, timeZone: zone, english: true, locale: vmUS), "Nov 5, 2026", "3:41", "· Aris")
          && ArisReaderDocument.meta(modified: saved, timeZone: zone, english: false) == "2026년 11월 5일 오후 3:41 · Aris"
          && ArisReaderDocument.subtitle(modified: saved, now: saved.addingTimeInterval(20), timeZone: zone, english: true) == "Just now · ~/Documents/Aris"
          && vmEnglish(ArisReaderDocument.subtitle(modified: saved, now: saved.addingTimeInterval(600), timeZone: zone, english: true, locale: vmUS), "10", "ago")
          && vmEnglish(ArisReaderDocument.subtitle(modified: saved, now: saved.addingTimeInterval(3 * 86_400), timeZone: zone, english: true, locale: vmUS), "Nov 5")
          && ArisReaderDocument.subtitle(modified: saved, now: saved.addingTimeInterval(600), timeZone: zone, english: false) == "10분 전 · ~/Documents/Aris",
          "reader: when an answer was saved reads English in the reader window")
    check(ArisMapCard.Mode.allCases.map { $0.words(english: true) } == ["Walking", "Transit", "Driving"] && ArisMapCard.Mode.walk.words(english: false) == "걸어서"
          && ArisMapCard.duration(3_900, english: true, locale: vmUS) == "1h 5m" && ArisMapCard.duration(3_900, english: false) == "1시간 5분",
          "map card: how to get there and how long read English")
}

// MARK: - a settings page named in a reply

private func vmEnglishSettingsPathTests() {
    let file = vmEnglishRoot().appendingPathComponent("Aris/components/Settings/Settings.xcstrings")
    let pairs = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: file)) ?? Data())
    ArisSettingsCopy.install(pairs)
    check(ArisSettingsPath.path(.todo, english: true) == "Settings › " + (pairs["할 일 · 캘린더"] ?? "?") && pairs["할 일 · 캘린더"] == "To-dos · Calendar" && ArisSettingsPath.path(.todo, english: false) == "설정 › 할 일 · 캘린더"
          && ArisSettingsPath.path(.team, english: true) == "Settings › Teammates" && ArisSettingsPath.path(.control, english: true) == "Settings › Computer control",
          "settings path: a page is named as the settings window's sidebar names it on this Mac (“Settings › To-dos · Calendar” on an English one)")
    let row = ArisSettingsPath.path(.todo, "미리 알림 접근", english: true)
    check(row == "Settings › To-dos · Calendar › " + (ArisSettingsCopy.translatedPages.contains(.todo) ? ArisSettingsCopy.t("미리 알림 접근") : "미리 알림 접근")
          && ArisSettingsPath.path(.todo, "미리 알림 접근", english: false) == "설정 › 할 일 · 캘린더 › 미리 알림 접근",
          "settings path: a row is named as its page shows it: in Korean until that page has its English")
    check(ArisSettingsPath.shown("Turn it on in Settings › 할 일.", english: true) == "Turn it on in Settings › To-dos · Calendar."
          && ArisSettingsPath.shown("설정 › 캘린더에서 골라요. 설정 › 모양도 봐요.", english: false) == "설정 › 할 일 · 캘린더에서 골라요. 설정 › 일반도 봐요."
          && ArisSettingsPath.shown("설정 › 할 일 · 캘린더 › 미리 알림 접근", english: false) == "설정 › 할 일 · 캘린더 › 미리 알림 접근"
          && ArisSettingsPath.shown("Settings > 노치 기능", english: true) == "Settings › Music · Shelf"
          && ArisSettingsPath.shown("설정 › 팀원 › 쓸 수 있는 것에서 켜 주세요.", english: true) == "Settings › Teammates › 쓸 수 있는 것에서 켜 주세요."
          && ArisSettingsPath.shown("Open Settings > 기억 to see it.", english: true) == "Open Settings › Memory to see it."
          && ArisSettingsPath.shown("설정 › 노치 · 사이드 노치", english: true) == "Settings › Notch"
          && ArisSettingsPath.shown("설정 › 할 일에서 켜 주세요.", english: false) == "설정 › 할 일 · 캘린더에서 켜 주세요." && ArisSettingsPath.shown("설정 › 팀원에서 봐요.", english: false) == "설정 › 팀원에서 봐요."
          && ArisSettingsPath.shown("할 일 3개 있어요.", english: true) == "할 일 3개 있어요.",
          "settings path: a reply that points to a page reads as the window names it, a page's former name as the page that has its rows now (settings pick 6-B); a reply that names no page is untouched")
    check(ArisLocalReply.noRemindersAccess(korean: true) == "미리 알림 접근이 꺼져 있어요. 설정 › 할 일 · 캘린더 › 미리 알림 접근에서 켜 주세요."
          && ArisLocalReply.noRemindersAccess(korean: false) == "Aris can't use Reminders yet. Turn it on in Settings (설정 › 할 일 · 캘린더 › 미리 알림 접근)."
          && ArisSession().listening().hearing("x").thinking().answering("설정 › 팀원").reply == "설정 › 팀원",
          "settings path: the Korean reply is as it was, and an English reply on a Korean Mac names the page as that Mac's window does")
    ArisSettingsCopy.install([:])
}
