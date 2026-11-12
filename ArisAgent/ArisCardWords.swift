//
//  ArisCardWords.swift
//  aris-agent
//
//  Plain words for the cards of file and desktop actions, never the raw command (the BUG-28 class): QA BUG-41 ("폴더
//  열기" over "new ~/Desktop/qa-test" for making a folder) and BUG-48 ("Mac 작업" over "type <text field> --app
//  TextEdit"). A path is shown as Finder names it from home (바탕화면 › qa-test); a desktop action as what it does in
//  which app and window. Korean, as the other cards. Pure, so the tests run it.
//

import Foundation

enum ArisCardWords {
    /// Home's folders as Finder shows them in Korean.
    private static let folders = ["Desktop": "바탕화면", "Documents": "문서", "Downloads": "다운로드", "Pictures": "사진", "Movies": "동영상",
                                  "Music": "음악", "Applications": "응용 프로그램", "Library": "라이브러리", "Public": "공개"]

    /// A brain's word as the card shows it (security review of batch 3): control, bidi and zero-width characters made
    /// visible (ArisDesktopCard.shown), and anything longer than `limit` cut with a visible "…", never silently.
    static func clean(_ text: String, limit: Int = 120) -> String {
        let shown = ArisDesktopCard.shown(text)
        return shown.count > limit ? String(shown.prefix(limit)) + "…" : shown
    }

    /// The path as it really resolves (~, $HOME and ${HOME} expanded, .. and . taken out), then as Finder names it from
    /// home ("~/Desktop/qa-test" → "바탕화면 › qa-test"); outside home, its own parts. Every part is shown cleaned.
    /// `english`: home's folders by their own names (Desktop › qa-test), for a request in English (ArisGateWords).
    static func friendlyPath(_ path: String, home: String, english: Bool = false) -> String {
        var raw = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        for prefix in ["${HOME}", "$HOME", "~"] where raw == prefix || raw.hasPrefix(prefix + "/") {
            raw = home + raw.dropFirst(prefix.count)
            break
        }
        let standard = raw.hasPrefix("/") ? (raw as NSString).standardizingPath : raw
        let base = (home as NSString).standardizingPath
        if standard == base { return english ? "Home" : "홈" }
        var rest = standard, inHome = false
        if rest.hasPrefix(base + "/") { rest.removeFirst(base.count + 1); inHome = true }
        var parts = rest.split(separator: "/").map { clean(String($0), limit: 60) }
        if inHome, !english, let first = parts.first, let named = folders[first] { parts[0] = named }
        guard !parts.isEmpty else { return clean(path) }
        return clean(parts.joined(separator: " › "), limit: 200)
    }

    /// `aris-tools type <text> [--app X]` as the tool itself reads it (`option` in aris-tools; the risk rule reads the
    /// same: ArisRiskPolicy): the app is the value after the FIRST `--app`, when it has one; every other word is
    /// typed, a second `--app` and its value included. Security review 6, H1: the card used to take every `--app`
    /// out and show the last one, so `type '<command>⏎' --app Terminal --app Notes` was asked about as "In: Notes"
    /// and typed, with " --app Notes" after it, into Terminal.
    static func typed(_ words: [String]) -> (text: String, app: String?) {
        var rest = words
        var app: String?
        if let flag = rest.firstIndex(of: "--app"), flag + 1 < rest.count {
            app = rest[flag + 1]
            rest.removeSubrange(flag...(flag + 1))
        }
        return (rest.joined(separator: " "), app)
    }

    /// A character that draws nothing and takes room: every space but the plain one (the no-break space, the em and
    /// ideographic spaces and their like), and the blank Braille pattern.
    static func isBlank(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.properties.generalCategory == .spaceSeparator && scalar != " ") || scalar.value == 0x2800
    }

    /// The typed text as the card shows it: all of it, never cut (text past a limit was typed but not shown), with
    /// nothing in it that could pass for a line of the card:
    ///  · control and hidden characters are written out (ArisDesktopCard.shown), and a line break is "⏎" on the same line;
    ///  · a blank that is not the plain space is written out too ("\u{3000}"), and a run of two or more plain spaces
    ///    is shown as that many "␣": room that is only blank could push a made-up "In: Notes" onto a row of its own
    ///    where the text wraps (security review 7, L1).
    static func typedShown(_ text: String) -> String {
        var out = ""
        var spaces = 0
        func flush() {
            out += spaces == 1 ? " " : String(repeating: "␣", count: spaces)
            spaces = 0
        }
        for scalar in ArisDesktopCard.shown(text).unicodeScalars {
            if scalar == " " {
                spaces += 1
                continue
            }
            flush()
            if scalar == "\n" { out += "⏎" } else if isBlank(scalar) { out += String(format: "\\u{%04X}", scalar.value) } else { out.unicodeScalars.append(scalar) }
        }
        flush()
        return out
    }

    /// The card for `aris-tools type …`: the app it goes to, then the text to type, each said as what it is (final VM
    /// run: the card read "hello --app TextEdit"). The app's line comes first, so where the keys go is read before
    /// any of the text, however long the text is (review 7, L1: under 50,000 characters the app could be approved
    /// unseen); the text's line is the last one and the only other one. Nil with no text.
    static func typing(_ words: [String], english: Bool) -> String? {
        let (text, app) = typed(words)
        guard !text.isEmpty else { return nil }
        let line = (english ? "Text to type: " : "입력하는 글: ") + typedShown(text)
        guard let app, !app.isEmpty else { return line }
        return (english ? "In: " : "입력할 곳: ") + typedShown(app) + "\n" + line
    }

    /// The card for `aris-tools <words…>` when these words make one: file actions and desktop actions; nil otherwise.
    /// `text`: what a desktop call takes on stdin (the text to type, or a batch's steps), shown too.
    /// `english`: only what can't be said from ArisGateWords' tables afterwards (a path's folders, a count of lines).
    static func card(_ words: [String], home: String, text: String? = nil, english: Bool = false) -> (title: String, detail: String)? {
        guard let verb = words.first else { return nil }
        let rest = Array(words.dropFirst())
        func friendlyPath(_ path: String, home: String) -> String { Self.friendlyPath(path, home: home, english: english) }
        switch verb {
        case "folder" where rest.first == "new":
            guard rest.count >= 2 else { return ("폴더 만들기", ArisGateWords.word("새 폴더", english: english)) }
            return ("폴더 만들기", friendlyPath(rest[1], home: home))
        case "folder":
            guard let path = rest.first else { return nil }
            return ("폴더 열기", friendlyPath(path, home: home))
        case "rename":
            guard rest.count >= 2 else { return nil }
            return ("이름 바꾸기", "\(friendlyPath(rest[0], home: home)) → \(clean(rest[1]))")
        case "move":
            guard rest.count >= 2 else { return nil }
            return ("옮기기", "\(friendlyPath(rest[0], home: home)) → \(friendlyPath(rest[1], home: home))")
        case "desktop":
            return desktop(rest, text: text)
        case "todo":
            // A to-do in plain words, never "remove 큐에이 오십팔" (QA live on b9c766bc, BUG-48).
            // Every word that will be stored: the text, then a line for each flag with its value (ArisStoredWords: M1).
            let item = ArisStoredWords.todoDetail(Array(rest.dropFirst()), english: english)
            switch rest.first {
            case "add": return ("할 일에 넣기", item)
            case "remove", "delete": return ("할 일에서 빼기", item)
            case "done", "complete": return ("할 일 끝내기", item)
            case "edit": return ("할 일 고치기", item)
            default: return nil
            }
        case "note":
            // A note's title and first lines (its words may be the screen's or a page's): what Notes will hold.
            let body = ArisStoredWords.note(rest)
            let lines = body.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard let first = lines.first else { return ("메모 만들기", ArisGateWords.word("빈 메모", english: english)) }
            let more = lines.dropFirst().prefix(3).map { clean($0, limit: 100) }
            return ("메모 만들기", ([ArisGateWords.word("제목", english: english) + ": " + clean(first, limit: 80)] + more + (lines.count > 4 ? [english ? "…(\(lines.count - 4) more lines)" : "…(\(lines.count - 4)줄 더)"] : [])).joined(separator: "\n"))
        case _ where ArisConvertWords.verbs.contains(verb):
            return conversion(words, home: home, english: english)
        default:
            return nil
        }
    }

    /// The card for an edit of a shell or tool settings file (ArisRiskPolicy.isSettingsEdit: audit gate-17): each file by
    /// its place and its full path, and its whole change, nothing cut (anything invisible made visible). Nil when any
    /// file's change isn't known as text: then there is nothing truthful to show, and the edit is refused.
    static func settingsEdit(_ changes: [[String: Any]], home: String, english: Bool = false) -> (title: String, detail: String)? {
        guard !changes.isEmpty else { return nil }
        var parts = ["셸이나 도구가 시작할 때 읽는 설정 파일이에요. 바뀌는 내용 전체를 확인해 주세요."]
        for change in changes {
            guard let path = change["path"] as? String, let diff = change["diff"] as? String, !diff.isEmpty else { return nil }
            let kind = change["kind"] as? String ?? (change["kind"] as? [String: Any])?["type"] as? String
            let what = english ? (["add": "new file", "delete": "delete", "update": "edit"][kind ?? ""] ?? "edit")
                : (["add": "새로 만들기", "delete": "지우기", "update": "고치기"][kind ?? ""] ?? "고치기")
            // Where the change moves the file to, when it does (ArisCodexChange: security review 2 H2).
            let moved = ArisCodexChange.read(change).destinations.map { "→ \(friendlyPath($0, home: home, english: english)) (\(ArisDesktopCard.shown($0)))\n" }.joined()
            parts.append("\(friendlyPath(path, home: home, english: english)) (\(ArisDesktopCard.shown(path))) · \(what)\n" + moved + ArisDesktopCard.shown(diff))
        }
        return ("설정 파일 수정", parts.joined(separator: "\n"))
    }

    /// The card for restarting, shutting down, logging out or sleeping the Mac (ArisRiskPolicy.powerCommand): what
    /// happens, and that unsaved work can be lost. Only these plain words: the command is one of four fixed System
    /// Events scripts, matched whole (ArisCommandPolicy.powerVerb), and each line says all its script does, so the raw
    /// script under them told nothing more (third VM run: “osascript -e tell application "System Events" to restart”).
    static func power(_ verb: String) -> (title: String, detail: String) {
        switch verb {
        case "restart": return ("Mac 재시동", "Mac을 재시동해요. 저장하지 않은 작업은 잃을 수 있어요.")
        case "shut down": return ("Mac 끄기", "Mac을 꺼요. 저장하지 않은 작업은 잃을 수 있어요.")
        case "log out": return ("로그아웃", "지금 사용자에서 로그아웃해요. 저장하지 않은 작업은 잃을 수 있어요.")
        default: return ("Mac 잠자기", "Mac을 잠자기 상태로 둬요.")
        }
    }

    /// A conversion's card (audit gate-4): every file by its place, or where the owner picked them, and what they become.
    /// Nil for a call aris-tools wouldn't read (it keeps the plain card with its words).
    private static func conversion(_ words: [String], home: String, english: Bool = false) -> (title: String, detail: String)? {
        guard let call = ArisConvertWords.parse(words) else { return nil }
        let titles = ["convert": "파일 변환하기", "merge": "파일 합치기", "split": "PDF 나누기", "compress": "용량 줄이기"]
        let picked = call.selector.map { ArisGateWords.word($0 == .finder ? "Finder에서 고른 파일" : "선반에 둔 파일", english: english) }
        let files = picked ?? call.paths.map { friendlyPath($0, home: home, english: english) }.joined(separator: "\n")
        let options = ["--to", "--max", "--percent", "--quality", "--pages"].compactMap { flag in
            call.options[flag].map { flag == "--to" ? "→ \(clean($0, limit: 20).uppercased())" : "\(flag) \(clean($0, limit: 40))" }
        }
        return (titles[call.verb] ?? "파일 변환하기", files + (options.isEmpty ? "" : "\n" + options.joined(separator: " ")))
    }

    /// `desktop <verb> …`: what it does, in which app (and window, when named), and what it types, presses or does step
    /// by step (shortened with a visible "…"), never the raw arguments.
    static func desktop(_ words: [String], text: String? = nil) -> (title: String, detail: String) {
        let verb = words.first ?? "", second = words.dropFirst().first ?? ""
        let app = (value("--app", in: words) ?? (verb == "app" ? words.dropFirst(2).first : nil)).map { clean($0, limit: 60) }
        let window = value("--title", in: words).map { clean($0, limit: 80) }
        // "TextEdit ‘무제’ 창", "TextEdit 창", or nothing.
        let target = app.map { app in window.map { "\(app) ‘\($0)’ 창" } ?? "\(app) 창" }
        func on(_ particle: String, _ what: String) -> String { target.map { "\($0)\(particle) \(what)" } ?? what }
        // What it carries: the typed text (stdin or a quoted word), the keys, the batch's steps.
        let positional = plainWords(Array(words.dropFirst()))
        var carried: String?
        switch verb {
        case "type", "set-value": carried = (text ?? positional.last).map { "입력하는 글:\n" + clean($0, limit: 400) }
        case "press": carried = positional.isEmpty ? nil : "키: " + clean(positional.joined(separator: " "), limit: 120)
        case "batch": carried = text.map { "단계:\n" + clean($0, limit: 600) }
        default: carried = nil
        }
        func with(_ line: String) -> String { carried.map { line + "\n" + $0 } ?? line }
        // ("" particle: "TextEdit 창 닫기".)
        switch verb {
        case "type": return ("입력하기", with(on("에", "입력하기")))
        case "set-value": return ("값 바꾸기", with(on("의", "칸 내용 바꾸기")))
        case "click", "click-at": return ("클릭하기", on("에서", "클릭하기"))
        case "press": return ("키 누르기", with(on("에서", "키 누르기")))
        case "scroll": return ("스크롤하기", on("에서", "스크롤하기"))
        case "drag": return ("끌어 놓기", on("에서", "끌어 놓기"))
        case "menu": return second == "click" ? ("메뉴 누르기", app.map { "\($0)의 메뉴 누르기" } ?? "메뉴 누르기") : ("메뉴 보기", app.map { "\($0)의 메뉴 보기" } ?? "메뉴 보기")
        case "dialog": return ("대화상자", app.map { "\($0)의 대화상자 다루기" } ?? "대화상자 다루기")
        case "window": return ("창 \(windowWord(second))", on("", windowWord(second)))
        case "app": return ("앱 \(appWord(second))", app.map { "\($0) \(appWord(second))" } ?? "앱 \(appWord(second))")
        case "batch": return ("여러 단계 하기", with(on("에서", "여러 단계 하기")))
        case "see": return ("화면 읽기", on("", "읽기"))
        case "wait": return ("결과 기다리기", "진행 중인 작업의 결과 기다리기")
        default: return ("Mac 작업", on("에서", "작업하기"))
        }
    }

    /// The words that aren't a flag, a flag's value or a ref (`type "hello" --app Notes` → ["hello"]).
    private static let switches: Set<String> = ["--stdin", "--foreground", "--json", "--double", "--right", "--ocr", "--annotate", "--compact"]
    private static func plainWords(_ words: [String]) -> [String] {
        var kept: [String] = [], index = 0
        while index < words.count {
            let word = words[index]
            if word.hasPrefix("--") { index += switches.contains(word) || word.contains("=") ? 1 : 2; continue }
            if !word.hasPrefix("@") && !word.hasPrefix("-") { kept.append(word) }
            index += 1
        }
        return kept
    }

    private static func value(_ flag: String, in words: [String]) -> String? {
        guard let index = words.firstIndex(of: flag), index + 1 < words.count else { return nil }
        return words[index + 1]
    }

    private static func windowWord(_ operation: String) -> String {
        ["focus": "앞으로 가져오기", "close": "닫기", "minimize": "내리기", "restore": "되살리기", "maximize": "최대화",
         "move": "옮기기", "resize": "크기 바꾸기", "list": "목록"][operation] ?? "다루기"
    }

    private static func appWord(_ operation: String) -> String {
        ["launch": "열기", "focus": "앞으로 가져오기", "hide": "숨기기", "quit": "종료"][operation] ?? "다루기"
    }
}
