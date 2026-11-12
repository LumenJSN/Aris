//
//  ArisSaveAnswer.swift
//  Aris
//
//  "방금 답을 홈 폴더의 aris-qa-tmp 안에 orlando.txt 파일로 저장해 줘": the last answer saved by Aris itself, on
//  The user's card (QA BUG-20b: the brain drove TextEdit's Save panel and saved an unrelated document in front). Only a
//  request that names the last answer and a save; anything else stays the brain's. Pure, so the tests run it.
//

import Foundation

struct ArisSaveAnswer: Equatable {
    /// "~/…": where the file goes.
    let path: String
    /// The user said "이거" or "this", not "방금 답": it is the last answer only while that is fresh (else Aris asks).
    var pronoun = false
    /// "메모에 저장해 줘": an Apple Notes note, not a file (QA retest on 8e236bff: it showed the file card). `path` is
    /// then empty.
    var note = false

    /// How fresh the last answer must be for "이거 파일로 저장해 줘" to mean it.
    static let pronounFresh: TimeInterval = 120

    /// The folders the user names by their Finder names.
    private static let folders: [(words: [String], path: String)] = [
        (["바탕화면", "데스크탑", "데스크톱", "desktop"], "~/Desktop"),
        (["문서 폴더", "문서", "documents"], "~/Documents"),
        (["다운로드", "downloads"], "~/Downloads"),
    ]

    static func parse(_ text: String) -> ArisSaveAnswer? {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = spoken.lowercased()
        let korean = lower.range(of: #"(방금|아까|마지막|위의?|그)\s*(.{0,20}?\s)?(답|답변|대답|내용)(을|를|은|이)?\s"#, options: .regularExpression) != nil
            && lower.range(of: #"저장(해|해줘|해 줘|해주세요|해 주세요|해줄래|해 줄래)\s*[.!?]?$"#, options: .regularExpression) != nil
        let english = lower.range(of: #"^(please\s+)?save\s+(the\s+|that\s+|your\s+)?(last\s+|previous\s+)?(answer|reply|response)\b"#, options: .regularExpression) != nil
        // "이거 파일로 저장해 줘" / "save this to a file": a file is named, and "이거" may be the last answer (QA retest: it
        // was taken as the screen and written into Notes with no card). A note (메모, Notes) is never this path.
        // 메모 / note / Notes wins over the generic 저장: the answer goes to Notes, on a note card.
        // A named .txt/.md file ("notes.md") is still a file.
        let noteWords = lower.range(of: #"(메모|\bnotes?\b)"#, options: .regularExpression) != nil
            && lower.range(of: #"\.(txt|md)\b"#, options: .regularExpression) == nil
        let fileWords = lower.range(of: #"(파일|file|\.txt|\.md)"#, options: .regularExpression) != nil && !noteWords
        let pronounKorean = lower.range(of: #"^(이거|이걸|이것|그거|그걸|그것)(을|를)?\s"#, options: .regularExpression) != nil
            && lower.range(of: #"저장(해|해줘|해 줘|해주세요|해 주세요|해줄래|해 줄래)\s*[.!?]?$"#, options: .regularExpression) != nil
        let pronounEnglish = lower.range(of: #"^(please\s+)?save\s+(this|that|it)\b"#, options: .regularExpression) != nil
        let pronoun = !korean && !english && (fileWords || noteWords) && (pronounKorean || pronounEnglish)
        guard korean || english || pronoun, !lower.contains("?") else { return nil }
        if noteWords { return ArisSaveAnswer(path: "", pronoun: pronoun, note: true) }
        // The file's name: a word ending in .txt or .md, else today's.
        let name = lower.range(of: #"[\p{L}\p{N}_\-][\p{L}\p{N}_\-. ]{0,60}\.(txt|md)\b"#, options: .regularExpression)
            .map { String(spoken[$0]).trimmingCharacters(in: .whitespaces) }
            .map { $0.split(separator: " ").last.map(String.init) ?? $0 } ?? defaultName()
        return ArisSaveAnswer(path: folder(in: spoken) + "/" + name, pronoun: pronoun)
    }

    /// "홈 폴더의 aris-qa-tmp 안에", "바탕화면에", "~/x 에": the folder, else the Desktop.
    static func folder(in text: String) -> String {
        let lower = text.lowercased()
        if let typed = text.range(of: #"~/[\p{L}\p{N}_\-./]{1,80}"#, options: .regularExpression) {
            let path = String(text[typed])
            return path.hasSuffix(".txt") || path.hasSuffix(".md") ? (path as NSString).deletingLastPathComponent : path
        }
        let home = try? NSRegularExpression(pattern: #"(?:홈\s*폴더|home\s*folder)(?:의|에 있는|안의|안에 있는)?\s+([\p{L}\p{N}_\-.]{1,60})\s*(?:폴더\s*)?(?:안에|안|에|속에)"#, options: .caseInsensitive)
        if let match = home?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let named = Range(match.range(at: 1), in: text) {
            let folder = String(text[named])
            if !folder.hasSuffix(".txt"), !folder.hasSuffix(".md") { return "~/" + folder }
        }
        for folder in folders where folder.words.contains(where: lower.contains) { return folder.path }
        return "~/Desktop"
    }

    private static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        return ArisUIWords.text("Aris 답변 \(formatter.string(from: Date())).txt", "Aris answer \(formatter.string(from: Date())).txt")
    }

    /// The card: where, and the first lines of what is written.
    /// In the language of the request (`korean`), like the agent's cards.
    static func card(path: String, text: String, outside: Bool = false, korean: Bool = true) -> (title: String, detail: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).prefix(4).joined(separator: "\n")
        let head = lines.count > 300 ? String(lines.prefix(300)) + "…" : lines
        let shownPart = part(total: text.count, partial: head.count < text.count, korean: korean)
        let warning = outside ? "\n" + outsideWarning(korean: korean) : ""
        if korean {
            return ("파일로 저장", "저장할 것: 방금 답\(warning)\n위치: \(shown(path))\n새 파일로 만들어요 (같은 이름의 파일이 있으면 저장하지 않아요)\n\(shownPart)\n\(head)")
        }
        return ("Save as a file", "Saving: the last answer\(warning)\nWhere: \(shown(path))\nA new file is made (nothing is saved if a file with that name is there)\n\(shownPart)\n\(head)")
    }

    /// "내용 (전체 1,234자 중 앞부분):", "Text (the start of 1,234 characters):".
    private static func part(total: Int, partial: Bool, korean: Bool) -> String {
        let count = NumberFormatter.localizedString(from: NSNumber(value: total), number: .decimal)
        if korean { return partial ? "내용 (전체 \(count)자 중 앞부분):" : "내용 (전체 \(count)자):" }
        return partial ? "Text (the start of \(count) characters):" : "Text (all \(count) characters):"
    }

    private static func outsideWarning(korean: Bool) -> String {
        korean ? "⚠️ 이 답에는 바깥 글(화면, 웹, 파일, 메일)에서 온 내용이 있어요" : "⚠️ This answer holds text from outside (the screen, the web, a file, mail)"
    }

    /// The note card: Notes, the note's title (its first line) and the lines after it, as the agent's `note` card shows.
    static func noteCard(text: String, outside: Bool = false, korean: Bool = true) -> (title: String, detail: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        func cut(_ line: String, _ limit: Int) -> String { line.count > limit ? String(line.prefix(limit)) + "…" : line }
        let title = lines.first.map { cut($0, 80) } ?? ""
        let more = lines.dropFirst().prefix(3).map { cut($0, 100) }
        let rest = lines.count > 4 ? [korean ? "…(\(lines.count - 4)줄 더)" : "…(\(lines.count - 4) more lines)"] : []
        let warning = outside ? "\n" + outsideWarning(korean: korean) : ""
        // Its whole length, as the file card says it.
        let partial = lines.count > 4 || lines.prefix(4).enumerated().contains { $0.element.count > ($0.offset == 0 ? 80 : 100) }
        let shownPart = part(total: text.count, partial: partial, korean: korean)
        if korean {
            return ("메모 만들기", (["저장할 것: 방금 답\(warning)", "위치: 메모 앱 (새 메모)", shownPart, "제목: " + title] + more + rest).joined(separator: "\n"))
        }
        return ("New note", (["Saving: the last answer\(warning)", "Where: Notes (a new note)", shownPart, "Title: " + title] + more + rest).joined(separator: "\n"))
    }

    /// This app's own two reasons a note wasn't made (ArisAgentClient.saveNote says them in Korean; the agent's own
    /// reason, when it gives one, is passed on as it came).
    static func noAnswer(korean: Bool) -> String { korean ? "Aris 에이전트가 답하지 않았어요." : "Aris's helper didn't answer." }
    static func notMade(korean: Bool) -> String { korean ? "메모에 넣지 못했어요." : "The note couldn't be made." }

    /// A reason as saveNote gave it, in the language of the request.
    static func noteProblem(_ why: String, korean: Bool) -> String {
        why == noAnswer(korean: true) ? noAnswer(korean: korean) : why == notMade(korean: true) ? notMade(korean: korean) : why
    }

    /// The reply after the user's no on a save card, like the other cards' no lines.
    static func declinedLine(korean: Bool) -> String { korean ? "알겠어요, 저장하지 않을게요." : "OK, I won't save it." }

    /// "~/aris-qa-tmp/orlando.txt" as Finder names it on this Mac: 홈 › aris-qa-tmp › orlando.txt, or
    /// Home › aris-qa-tmp › orlando.txt where the Mac is English (Finder's names follow the Mac's language).
    static func shown(_ path: String, english: Bool = ArisUIWords.english) -> String {
        var parts = path.split(separator: "/").map(String.init)
        guard parts.first == "~" else { return path }
        parts.removeFirst()
        let names = ["Desktop": ArisUIWords.text("바탕화면", "Desktop", english: english), "Documents": ArisUIWords.text("문서", "Documents", english: english),
                     "Downloads": ArisUIWords.text("다운로드", "Downloads", english: english)]
        if let first = parts.first, let named = names[first] { parts[0] = named } else { parts.insert(ArisUIWords.text("홈", "Home", english: english), at: 0) }
        return parts.joined(separator: " › ")
    }
}
