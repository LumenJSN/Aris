//
//  ArisSpeakable.swift
//  Aris
//
//  What of an answer the notch shows and the voice reads. Machine blocks a brain was told to emit (the jobs fence, or
//  any fenced or bare JSON) never show: a jobs block that wasn't dispatched becomes one short line. The voice never
//  reads code or JSON at all: fenced blocks (```, ~~~ or full-width ｀｀｀, any length, nested), inline code, JSON
//  objects and arrays, and long symbol runs are taken out of the whole text before it is cut into sentences. Every
//  scan is linear (a 32 KB unclosed array costs one pass). Pure, so the tests run it.
//

import Foundation

enum ArisSpeakable {
    /// Said and shown in place of a jobs block that couldn't be handed over this turn.
    static func refusedJobs(korean: Bool) -> String { korean ? "이 일은 지금 팀원한테 못 넘겨요." : "I can't hand this to a teammate right now." }

    /// Said when nothing in the answer can be read out (it was all code or data): the notch has it.
    static func onScreen(korean: Bool) -> String { korean ? "화면에 띄워 뒀어요." : "It's on the screen." }

    /// Said after the short part of a long answer (ArisSpeechStream): the whole of it is on screen.
    static func moreOnScreen(korean: Bool) -> String { korean ? "자세한 건 화면에 띄워 뒀어요." : "The details are on the screen." }

    /// Shown and said when an answer leaves nothing on screen and no card comes (the brain wrote nothing, or only data):
    /// the notch never goes back to an empty composer without a word.
    static func emptyAnswer(korean: Bool) -> String { korean ? "답을 받지 못했어요. 한 번만 다시 말해 주세요." : "No answer came back. Please ask once more." }

    /// What the notch shows for `answer`: `shown` as it is; when that is empty and no card comes, its <say> line's words
    /// (all there was), and failing that the short reason.
    static func visible(_ answer: String, shown: String, card: Bool, korean: Bool) -> String {
        guard !card, shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return shown }
        let words = self.shown(answer, korean: korean, say: .unwrap).trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? emptyAnswer(korean: korean) : words
    }

    // MARK: - The spoken line

    /// A brain answering at length opens with <say>one or two sentences to say</say>, then the full answer to show
    /// (ArisAgentPrompt.sayRule). Only the line is read; only the full answer is shown. Honoured only at the very start
    /// of the answer and only when closed; anywhere else (mid-answer, in a code block) or left open, it is plain text.
    static let sayOpen = "<say>", sayClose = "</say>"
    /// A <say> line is read up to this many characters.
    static let sayBudget = 160

    /// What a turn does with a leading <say> line. `honour`: read only it, show only the rest. `unwrap`: a line the
    /// voice didn't take as one (it streamed after other words): its words stay on screen, the tags go. `keep`: an
    /// untrusted or outside-text turn: everything shows and stays as written, so nothing said can be kept off screen.
    enum SayHandling { case honour, unwrap, keep }

    /// The leading <say> line and what follows it; nil unless the answer opens with a closed one.
    static func sayLine(in text: String) -> (line: String, rest: String)? {
        let lead = text.drop { $0.isWhitespace }
        guard lead.prefix(sayOpen.count).lowercased() == sayOpen else { return nil }
        let inside = lead.dropFirst(sayOpen.count)
        guard let close = inside.range(of: sayClose, options: .caseInsensitive) else { return nil }
        return (String(inside[..<close.lowerBound]), String(inside[close.upperBound...]))
    }

    /// The answer as `handling` shows it: honoured, the full answer after the line (or the line's words when nothing
    /// follows); unwrapped, the line's words then the rest; kept, every word as written. Whatever the handling, a <say>
    /// or </say> tag never shows, wherever it is (second upgrade run, bug 6: a sentence before the line left
    /// "<say>…</say>" in the notch, the reader and the copied text): the words between them stay where they are.
    static func withoutSay(_ text: String, _ handling: SayHandling = .honour) -> String {
        guard handling != .keep, let say = sayLine(in: text) else { return withoutSayMarkup(text) }
        let line = withoutSayMarkup(say.line).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = withoutSayMarkup(say.rest).trimmingCharacters(in: .whitespacesAndNewlines)
        if handling == .unwrap { return [line, rest].filter { !$0.isEmpty }.joined(separator: "\n") }
        return rest.isEmpty ? line : rest
    }

    /// An answer kept as written (an untrusted turn's), as the notch draws it: every word, without the spoken line's
    /// tags. The line's words stay first, then the rest; a line still arriving (its close not here yet) loses only its
    /// tags. Nothing said is ever kept off screen.
    static func withoutSayTags(_ text: String) -> String {
        if sayLine(in: text) != nil { return withoutSay(text, .unwrap) }
        return withoutSayMarkup(text)
    }

    /// The text with every <say> and </say> tag taken out (any case, spaces inside the brackets), and the start of one
    /// still arriving at its very end ("<sa", "</"); a tag that sat on a line of its own leaves no empty line. The
    /// words are all kept, and code (a fenced block, `inline code`) is left exactly as written: an answer about the tag
    /// shows it there.
    static func withoutSayMarkup(_ text: String) -> String {
        guard text.range(of: "<", options: .literal) != nil else { return text }
        var out = "", at = text.startIndex
        for fence in fences(in: text) {
            out += untaggedProse(text[at..<fence.range.lowerBound]) + text[fence.range]
            at = fence.range.upperBound
        }
        let tail = untaggedProse(text[at...])
        return (out + tail).replacingOccurrences(of: #"(?i)<(?:/(?:s(?:a(?:y)?)?)?|s(?:a(?:y)?)?)$"#, with: "", options: .regularExpression)
    }

    /// Prose without say tags, its inline code spans kept as written.
    private static func untaggedProse(_ prose: Substring) -> String {
        let text = String(prose)
        guard let code = try? NSRegularExpression(pattern: "`[^`\n]*`") else { return text }
        var out = "", at = text.startIndex
        let strip = { (part: Substring) in
            String(part).replacingOccurrences(of: #"(?im)^[ \t]*<\s*/?\s*say\s*>[ \t]*\n"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)<\s*/?\s*say\s*>"#, with: "", options: .regularExpression)
        }
        for match in code.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            out += strip(text[at..<range.lowerBound]) + text[range]
            at = range.upperBound
        }
        return out + strip(text[at...])
    }

    /// How many characters at the end of `text` could be the start of a </say> still arriving.
    static func partialClose(in text: Substring) -> Int {
        let lower = text.suffix(sayClose.count - 1).lowercased()
        for n in stride(from: min(lower.count, sayClose.count - 1), through: 1, by: -1) where sayClose.hasPrefix(String(lower.suffix(n))) {
            return n
        }
        return 0
    }

    /// "읽어줘" reads the last answer only within this long of it.
    static let readableFor: TimeInterval = 600

    static func stillReadable(since: Date, now: Date = Date()) -> Bool { now.timeIntervalSince(since) < readableFor }

    /// How long a full reading may take before the voice is stopped: the usual 40 s, or more for a long answer (about
    /// five characters a second, slower than any voice reads), so a long reading is never cut off partway.
    static func readingLimit(_ sentences: [String]) -> Duration {
        .seconds(max(40, sentences.reduce(0) { $0 + $1.count } / 5 + 10))
    }

    /// The whole answer for "읽어줘": everything readable in what's shown, cut into sentences, nothing held back.
    static func fullReading(_ answer: String, korean: Bool, say: SayHandling = .honour) -> [String] {
        let text = shown(answer, korean: korean, say: say)
        var prose = "", at = text.startIndex
        for fence in fences(in: text) {
            prose += text[at..<fence.range.lowerBound] + "\n"
            at = fence.range.upperBound
        }
        prose += text[at...]
        // Line by line, so a list's items are read one by one.
        let lines = prose.split(separator: "\n").map { speakable(String($0)) }.filter { !$0.isEmpty }
        var splitter = ArisSentenceSplitter()
        return (splitter.add(lines.joined(separator: "\n") + "\n") + splitter.finish()).map(speakable).filter { !$0.isEmpty }
    }

    /// Where speaking must stop and wait for the whole answer: a fence opening, or JSON starting (a line or the answer
    /// beginning with { or [, or { or [ followed by a quote or another bracket anywhere).
    static func holdPoint(in text: String) -> String.Index? {
        // An unfenced card marker too (the JSON after it may not have come in yet).
        text.range(of: #"```|~~~|｀｀｀|(?:^|\n)[ \t]*[\{\[]|[\{\[]\s*["\{\[]|(?i)(?:^|(?<=\s))"# + ArisWidget.tagPattern + #"(?![\p{L}\p{N}])"#,
                   options: .regularExpression)?.lowerBound
    }

    /// A background job's or inbox item's answer: what the notch shows and the history keeps, and what is said.
    /// The shown Markdown (its line breaks kept: the notch draws it as answer format A); the said text is `readable`.
    static func report(_ answer: String, korean: Bool) -> (shown: String, spoken: String) {
        let shown = shown(answer, korean: korean)
        let spoken = speakable(readable(shown, korean: korean))
        return (shown, spoken.isEmpty ? onScreen(korean: korean) : spoken)
    }

    /// Markdown as it is said: headings, labels and list items without their marks (#, -, 1., **), each its own
    /// sentence; a table as one short line (its label is said before it, then its columns and size, never its cells or
    /// pipes); code is left out, and a saved file's quoted name (ArisTaskResult.savedLine) too.
    static func readable(_ markdown: String, korean: Bool) -> String {
        let text = markdown.replacingOccurrences(of: #"\s*[‘“][^’”\n]*\.md[’”](으로|로)?"#, with: "", options: .regularExpression)
        return ArisBoardContent.blocks(from: text).map { block -> String in
            switch block {
            case .heading(_, let words), .label(let words): return sentence(words)
            case .paragraph(let words), .quote(let words): return plainMarks(words)
            case .bullets(let items), .numbered(let items): return items.map(sentence).joined(separator: " ")
            case .checklist(let items): return items.map { sentence($0.text) }.joined(separator: " ")
            case .table(let header, let rows): return tableLine(header: header, rows: rows, korean: korean)
            case .code: return ""
            }
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// "화면에 표로 띄워 뒀어요: 수, 제곱, 5줄." / "There's a table on the screen: n, n², 2 rows."
    static func tableLine(header: [String], rows: [[String]], korean: Bool) -> String {
        let more = rows.last == ["…"]
        let count = rows.count - (more ? 1 : 0)
        let columns = header.prefix(4).map(plainMarks).filter { !$0.isEmpty }
        let size = korean ? "\(count)줄\(more ? " 넘게" : "")" : "\(more ? "over " : "")\(count) row\(count == 1 && !more ? "" : "s")"
        let what = (columns + [size]).joined(separator: ", ")
        return korean ? "화면에 표로 띄워 뒀어요: \(what)." : "There's a table on the screen: \(what)."
    }

    /// Words with their bold, italic and link marks taken off, ending as a sentence (so the voice pauses after a heading).
    private static func sentence(_ words: String) -> String {
        let plain = plainMarks(words)
        guard let last = plain.last else { return "" }
        return ".!?…。:".contains(last) ? plain : plain + "."
    }

    private static func plainMarks(_ words: String) -> String {
        words.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|(?<![\p{L}\p{N}])[*_](?=\S)|(?<=\S)[*_](?![\p{L}\p{N}])"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Fences

    struct Fence {
        let range: Range<String.Index>
        let language: String
        let body: String
        let closed: Bool
    }

    /// The fenced blocks in order: an opening run of 3 or more ` ~ or ｀, closed by the same run (so a longer outer
    /// fence holds inner ones), or running to the end when never closed.
    static func fences(in text: String) -> [Fence] {
        var found: [Fence] = []
        var from = text.startIndex
        while let open = text.range(of: #"(`{3,}|~{3,}|｀{3,})"#, options: .regularExpression, range: from..<text.endIndex) {
            let marker = String(text[open])
            let close = text.range(of: marker, range: open.upperBound..<text.endIndex)
            let inside = text[open.upperBound..<(close?.lowerBound ?? text.endIndex)]
            let firstLine = inside.prefix { $0 != "\n" }
            let language = firstLine.trimmingCharacters(in: .whitespaces).precomposedStringWithCompatibilityMapping.lowercased()
            let isTag = !language.isEmpty && language.allSatisfy { $0.isLetter || $0.isNumber || "+-_.#".contains($0) }
            let body = isTag || language.isEmpty ? String(inside.drop { $0 != "\n" }) : String(inside)
            found.append(Fence(range: open.lowerBound..<(close?.upperBound ?? text.endIndex), language: isTag ? language : "", body: body,
                               closed: close != nil))
            from = close?.upperBound ?? text.endIndex
            if close == nil { break }
        }
        return found
    }

    private static let machineLanguages: Set<String> = ["json", "jsonc", "json5", "jsonl", "ndjson"]

    /// The answer as the notch shows it: machine blocks (a json/jsonc/json5 fence, a fence whose body is JSON, a cut-off
    /// fence that starts like JSON, or the whole answer being JSON) taken out; when one of them held jobs, teammates or
    /// actions, the refusal line takes its place. Other code stays.
    static func shown(_ answer: String, korean: Bool, say: SayHandling = .honour) -> String {
        let text = ArisWidget.withoutBareCards(withoutSay(answer, say))
        var result = "", refused = false, at = text.startIndex
        for fence in fences(in: text) {
            result += withoutBareWork(text[at..<fence.range.lowerBound], refused: &refused)
            let machine = machineLanguages.contains(fence.language) || isJSON(fence.body)
                || (!fence.closed && looksLikeJSON(fence.body)) || holdsWork(fence.body)
            if machine {
                refused = refused || holdsWork(fence.body)
            } else {
                result += text[fence.range]
            }
            at = fence.range.upperBound
        }
        result += withoutBareWork(text[at...], refused: &refused)
        var trimmed = withoutSourceLabels(result.trimmingCharacters(in: .whitespacesAndNewlines))
        if isJSON(trimmed) || (looksLikeJSON(trimmed) && holdsWork(trimmed)) {
            refused = refused || holdsWork(trimmed)
            trimmed = ""
        }
        guard refused else { return trimmed }
        return trimmed.isEmpty ? refusedJobs(korean: korean) : trimmed + "\n" + refusedJobs(korean: korean)
    }

    /// Prose with any bare JSON object that hands out work (Claude writes the jobs block unfenced at times) taken out,
    /// with a "json" label line left just before it (a fence that lost its backticks). Looked for only when a work key
    /// is there at all.
    private static func withoutBareWork(_ gap: Substring, refused: inout Bool) -> String {
        let text = String(gap)
        guard holdsWork(text) else { return text }
        var out = "", at = text.startIndex
        for span in ArisDispatch.jsonObjects(in: text) where holdsWork(String(text[span])) {
            var head = text[at..<span.lowerBound]
            if let label = head.range(of: #"(?i)(?:^|\n)[ \t]*json[ \t]*\n[ \t]*$"#, options: .regularExpression) {
                head = head[..<label.lowerBound]
            }
            out += head
            refused = true
            at = span.upperBound
        }
        return out + text[at...]
    }

    /// One markdown link, as a pattern.
    private static let sourceLink = #"\[[^\[\]\n]{1,200}\]\([^()\s]{0,2000}\)"#

    /// A source link that is no part of a sentence: a "Sources" or 출처 list of links that closes the answer, one or more
    /// links in round brackets ("… ([AP통신 보도](https://…))"), links after "출처:", and links after a sentence's end on its
    /// line ("…원이에요. [환율 확인](https://…)"). Each pattern with what replaces it. The agent takes the same links out
    /// of the answer it sends (ArisAgentStream.citationLinks; the tests hold them equal).
    static let citationLinks: [(pattern: String, template: String)] = [
        (#"(?i)\n+[ \t]*(?:#{1,6}[ \t]*)?(?:\*\*)?(?:sources?|references?|출처|참고 자료|참고)(?:\*\*)?[ \t]*[:：]?[ \t]*(?:\*\*)?[ \t]*(?:\n[ \t]*(?:[-*•]|\d+[.)])?[ \t]*"# + sourceLink + #"[ \t]*)+\s*$"#, ""),
        (#"[ \t]*[(（][ \t]*(?:"# + sourceLink + #"[ \t,·;]*)+[)）]"#, ""),
        (#"(?mi)[ \t]*(?:출처|sources?)[ \t]*[:：][ \t]*(?:"# + sourceLink + #"[ \t,·;|]*)+[ \t]*$"#, ""),
        (#"(?m)((?<!^[ \t]{0,3}\d{1,2})[.!?。…]|(?<=[요다죠])(?=[ \t]))[ \t]*(?:"# + sourceLink + #"[ \t,·;|]*)+[ \t]*$"#, "$1"),
    ]

    /// A source named after the last sentence with no link: "출처: 한국은행", "(Source: Reuters)", "via AP", or at most three
    /// words ending in 보도 ("AP통신 보도"). Never a list item, a heading or a table row; and never words that could be
    /// the answer itself (“…하나예요. 메일 확인” is a to-do, “…. 팀 발표” an event).
    private static let sourceLabelPattern = try? NSRegularExpression(pattern: #"(?s)^(.*(?<!\d)[.!?。…])[ \t]*(?:\n\s*)?"#
        + #"((?![-*•#|>\d])(?:[^\s.!?。…,·/:：]+[ \t]+){0,2}[^\s.!?。…,·/:：]*보도"#
        + #"|[(（]?(?:출처|(?i:sources?))[ \t]*[:：][ \t]*[^.!?\n]{1,30}[)）]?|(?i:via)[ \t]+[^.!?\n]{1,30})[ \t]*$"#)

    /// The answer without its source labels (QA live: "환율 확인", "AP통신 보도", "애플 발표" at the end of answers, shown and
    /// read out: the labels of source links whose addresses had been taken out). A source link that is no part of a
    /// sentence goes with its label, and so does a source named after the last sentence. A link inside a sentence, a
    /// sentence that only mentions a source, and an answer that is nothing else all stay.
    static func withoutSourceLabels(_ text: String) -> String {
        var cleaned = text
        if cleaned.contains("](") {
            for link in citationLinks {
                cleaned = cleaned.replacingOccurrences(of: link.pattern, with: link.template, options: .regularExpression)
            }
            // Never down to nothing: an answer that is only links keeps them.
            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { cleaned = text }
        }
        // Only the end can hold a bare name: the last few hundred characters are read, never a whole long answer.
        let tail = String(cleaned.suffix(240))
        guard let regex = sourceLabelPattern, let match = regex.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail)),
              let body = Range(match.range(at: 1), in: tail) else { return cleaned == text ? text : cleaned.trimmingCharacters(in: .whitespacesAndNewlines) }
        let dropped = tail.distance(from: body.upperBound, to: tail.endIndex)
        return String(cleaned.dropLast(dropped)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the notch shows of an answer still arriving: without a source link or name at its end, and without the start
    /// of a link whose end hasn't come yet (it would show as "[환율 확인](https://…" for a moment).
    static func streaming(_ text: String) -> String {
        withoutSourceLabels(text.replacingOccurrences(of: #"[ \t]*[(（]?[ \t]*\[[^\[\]\n]{0,200}(?:\]\([^()\s]{0,2000})?$"#, with: "", options: .regularExpression))
    }

    // MARK: - Speech

    /// Text for the voice: no fenced blocks (closed or not), inline code, JSON objects or arrays (nested, or left open
    /// to the end), links or long runs of symbols; spaces collapsed. Empty when nothing readable is left.
    static func speakable(_ raw: String) -> String {
        let text = ArisWidget.withoutBareCards(raw)
        var plain = "", at = text.startIndex
        for fence in fences(in: text) {
            plain += text[at..<fence.range.lowerBound] + " "
            at = fence.range.upperBound
        }
        plain += text[at...]
        // A source link or name is never read out (QA live: "환율 확인" was spoken); a link inside a sentence is read as its
        // words. Bounded, so a long run of data brackets is never scanned again and again (I3).
        let unlinked = withoutSourceLabels(plain).replacingOccurrences(of: #"\[([^\[\]\n]{1,80})\]\([^()\n]{0,300}\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"`[^`\n]*`?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</?say>"#, with: " ", options: .regularExpression)
            // A piece of a tag cut where the stream was split ("<sa" before the line's words): never read.
            .replacingOccurrences(of: #"(?i)</?s(?:a(?:y)?)?(?![a-z>])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: " ", options: .regularExpression)
        let spoken = withoutData(unlinked)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s.,!?~…'"()%]{4,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return spoken.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) ? spoken : ""
    }

    /// One pass over the text with a stack of open brackets: every {…} goes, every […] holding a quote, colon or comma
    /// goes (with whatever it nests), and an object or array left open goes to the end when what follows its opening
    /// looks like data (a quote or another bracket). Linear in the text's length.
    static func withoutData(_ text: String) -> String {
        let characters = Array(text)
        // Dropped spans as +1 at the start and -1 after the end, summed once at the end (nested spans cost nothing).
        var marks = [Int](repeating: 0, count: characters.count + 1)
        var stack: [(index: Int, curly: Bool, data: Bool)] = []
        for (i, character) in characters.enumerated() {
            switch character {
            case "{", "[":
                stack.append((i, character == "{", false))
            case "}", "]":
                guard let open = stack.last, open.curly == (character == "}") else { continue }
                stack.removeLast()
                if open.curly || open.data {
                    marks[open.index] += 1
                    marks[i + 1] -= 1
                    // The enclosing array now holds data.
                    if !stack.isEmpty { stack[stack.count - 1].data = true }
                }
            case "\"", "'", ":", ",":
                if !stack.isEmpty { stack[stack.count - 1].data = true }
            default:
                break
            }
        }
        // Left open: from the outermost unclosed bracket whose next character starts data, to the end.
        if let open = stack.first(where: { start in
            let next = characters[(start.index + 1)...].first { !$0.isWhitespace }
            return next.map { "\"'{[".contains($0) } ?? false
        }) {
            marks[open.index] += 1
            marks[characters.count] -= 1
        }
        // A dropped run leaves one space.
        var kept = "", lastDropped = false, depth = 0
        for (i, character) in characters.enumerated() {
            depth += marks[i]
            if depth > 0 {
                if !lastDropped { kept.append(" ") }
                lastDropped = true
            } else {
                kept.append(character)
                lastDropped = false
            }
        }
        return kept
    }

    private static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{" || trimmed.first == "[", let data = trimmed.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first == "{" || trimmed.first == "["
    }

    /// A block that hands out work: jobs, teammates, actions or an assignee.
    private static func holdsWork(_ body: String) -> Bool {
        body.range(of: #""(jobs|teammates|actions|assignee)"\s*:"#, options: .regularExpression) != nil
    }
}

/// The answer's speech while it streams: pieces go to the voice sentence by sentence up to the first hold point (a
/// fence, or JSON starting; nothing before it can hold either); the rest waits for the whole answer, which is said from
/// its shown form, data and code taken out of the whole remainder before it is cut into sentences. The hold point is looked for only in the new
/// tail (with a short look-back for a marker split across pieces), and a few characters are always kept back until
/// the next piece shows they don't open a fence. Pure, so the tests drive it as the controller does.
///
/// A long answer is not read whole (the owner, 2026-11-04: it used to stop after two sentences without a word): an answer
/// that opens with a closed <say>…</say> has only that line read (up to `ArisSpeakable.sayBudget` characters), and the
/// rest is shown; without one (or on an untrusted turn, `honoursSay` off), its first sentence is read, the second if both
/// fit in `budget` characters, the whole of it if it ends within that. When something shown was left unread, "자세한 건
/// 화면에 띄워 뒀어요." ends it. "읽어줘" reads the whole of it (ArisSpeakable.fullReading).
struct ArisSpeechStream {
    /// Characters read of an answer without a <say> line: a short answer (under it) is read whole.
    static let budget = 120

    private var splitter = ArisSentenceSplitter()
    private(set) var written = ""
    /// Characters of the voice's text (`voice()`) given to the voice.
    private var spoken = 0
    /// Characters of the voice's text already looked through for a hold point.
    private var scanned = 0
    /// Where speaking stopped, in characters of the voice's text.
    private(set) var hold: Int?
    /// Enough to hold back a marker that is still arriving ("``", "{ ").
    private static let lookBack = 8
    /// Whether the answer opens with <say>; nil while its first characters could still be one.
    private var opensWithSay: Bool?
    /// Where the <say> line's words start in `written`.
    private var sayStart = 0
    /// Characters of the sentences read so far, and whether the budget stopped the reading.
    private var read = 0, readCount = 0
    /// Sentences past the second, read only once the whole answer turns out to fit the budget.
    private var waiting: [String] = []
    private(set) var cut = false

    /// Off for an untrusted or outside-text turn: a <say> line is plain text there (ArisSpeakable.SayHandling.keep).
    /// Turned off before the line was read, the answer is read as one without it.
    var honoursSay = true {
        didSet {
            guard !honoursSay, opensWithSay == true, spoken == 0 else { return }
            opensWithSay = false
            scanned = 0
            hold = nil
        }
    }

    /// The answer opened with a closed <say> line and the voice read it as one: the notch shows it honoured.
    var tookSayLine: Bool { opensWithSay == true && sayClosed }

    private var sayClosed: Bool {
        written.dropFirst(sayStart).range(of: ArisSpeakable.sayClose, options: .caseInsensitive) != nil
    }

    var holding: Bool { hold != nil }

    /// What the notch shows while it streams: everything up to the hold point; with a <say> line, that line until the
    /// full answer after it starts coming.
    var display: String {
        switch opensWithSay {
        case nil: return ""
        case false?: return hold.map { String(written.prefix($0)) } ?? written
        case true?:
            let content = written.dropFirst(sayStart)
            guard let close = content.range(of: ArisSpeakable.sayClose, options: .caseInsensitive) else {
                return String(content.prefix(max(0, content.count - ArisSpeakable.partialClose(in: content))))
            }
            let after = String(content[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard after.isEmpty else { return ArisSpeakable.holdPoint(in: after).map { String(after[..<$0]) } ?? after }
            return String(content[..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// A new piece: the sentences it completes before any hold point.
    mutating func add(_ piece: String) -> [String] {
        written += piece
        let (voice, complete) = self.voice()
        guard hold == nil, !cut else { return [] }
        let count = voice.count
        let from = max(0, scanned - Self.lookBack)
        let tail = String(voice.dropFirst(from))
        if let point = ArisSpeakable.holdPoint(in: tail) {
            hold = from + tail.distance(from: tail.startIndex, to: point)
        }
        scanned = count
        let upTo = hold ?? (complete ? count : max(spoken, count - Self.lookBack))
        guard upTo > spoken else { return [] }
        // Before the hold point there is no fence or JSON: its sentences are cut as they come, each made speakable.
        let next = String(voice.dropFirst(spoken).prefix(upTo - spoken))
        spoken = upTo
        return budgeted(clean(splitter.add(next)))
    }

    /// The whole answer as shown (ArisSpeakable.shown): the rest of what may be read, said now, and the line saying
    /// the rest is on screen when anything shown was left unread (never when nothing is shown: a dispatched turn).
    /// `answer`: the raw answer, for a brain that sent it whole (nothing streamed).
    mutating func finish(shown: String, answer: String? = nil, korean: Bool = true) -> [String] {
        var out: [String] = []
        if written.isEmpty, let answer, !answer.isEmpty { out = add(answer) }
        let showsAnything = !shown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A <say> never closed is plain text: nothing of it was read yet, so the answer is read as one without it.
        if opensWithSay == true, !sayClosed {
            opensWithSay = false
            scanned = 0
            hold = nil
        }
        if opensWithSay == true {
            let (voice, _) = self.voice()
            let rest = String(voice.dropFirst(hold ?? spoken))
            let plain = ArisSpeakable.speakable(rest)
            out += budgeted(clean(splitter.add(plain.isEmpty ? "" : " " + plain) + splitter.finish()))
            let content = written.dropFirst(sayStart)
            let after = content.range(of: ArisSpeakable.sayClose, options: .caseInsensitive).map { String(content[$0.upperBound...]) } ?? ""
            if showsAnything, cut || !ArisSpeakable.shown(after, korean: korean).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out.append(ArisSpeakable.moreOnScreen(korean: korean))
            }
            return out
        }
        let said = String(written.prefix(spoken)).trimmingCharacters(in: .whitespacesAndNewlines)
        // The shown answer has no <say> tags (ArisSpeakable.withoutSayMarkup): what streamed is matched to it without them.
        let saidShown = ArisSpeakable.withoutSayMarkup(said)
        let rest: String
        if written.isEmpty || said.isEmpty {
            rest = shown
        } else if shown.hasPrefix(said) {
            rest = String(shown.dropFirst(said.count))
        } else if saidShown != said, shown.hasPrefix(saidShown) {
            rest = String(shown.dropFirst(saidShown.count))
        } else {
            // The shown answer isn't what streamed (the agent took a block or a source label out): what was said stays
            // said, and of the words still waiting for their sentence to end only those the shown answer keeps are said
            // (QA live: a source link's label, "환율 확인", was read out at the end).
            rest = ""
            let given = String(written.prefix(spoken))
            let lead = given.prefix { $0.isWhitespace }.count
            let kept = lead + zip(given.dropFirst(lead), shown).prefix { $0 == $1 }.count
            splitter.keepWaiting(first: kept - (given.count - splitter.waiting.count))
        }
        // The rest may hold code or data: it is made speakable whole, before it is cut into sentences.
        let plain = ArisSpeakable.speakable(rest)
        let lead = rest.first.map { $0.isWhitespace } == true ? " " : ""
        out += budgeted(clean(splitter.add(plain.isEmpty ? "" : lead + plain) + splitter.finish()), ending: true)
        if cut, showsAnything { out.append(ArisSpeakable.moreOnScreen(korean: korean)) }
        return out
    }

    /// The text that may be read so far: the whole answer, or the words of its <say> line once it is closed (nothing
    /// before: a line never closed is plain text, read at the end). Nothing while the first characters could still
    /// open a <say>.
    private mutating func voice() -> (text: String, complete: Bool) {
        if opensWithSay == nil {
            let lead = written.drop { $0.isWhitespace }
            let head = String(lead.prefix(ArisSpeakable.sayOpen.count)).lowercased()
            if honoursSay, lead.isEmpty || (lead.count < ArisSpeakable.sayOpen.count && ArisSpeakable.sayOpen.hasPrefix(head)) { return ("", false) }
            opensWithSay = honoursSay && head == ArisSpeakable.sayOpen
            sayStart = written.count - lead.count + ArisSpeakable.sayOpen.count
        }
        guard opensWithSay == true else { return (written, false) }
        let content = written.dropFirst(sayStart)
        guard let close = content.range(of: ArisSpeakable.sayClose, options: .caseInsensitive) else { return ("", false) }
        return (String(content[..<close.lowerBound]), true)
    }

    /// A <say> line: read up to `sayBudget` characters (the first sentence always). Without one: the first sentence is
    /// read at once, and the second if both fit in `budget` characters. Later ones wait: an answer that ends within the
    /// budget is read whole; one that passes it stops after its first two sentences (the owner's "1–2 sentences, then 화면에").
    private mutating func budgeted(_ sentences: [String], ending: Bool = false) -> [String] {
        var out: [String] = []
        if opensWithSay == true {
            for sentence in sentences where !cut {
                if read > 0, read + sentence.count > ArisSpeakable.sayBudget { cut = true } else {
                    read += sentence.count
                    out.append(sentence)
                }
            }
            return out
        }
        for sentence in sentences where !cut {
            if read + waiting.reduce(0, { $0 + $1.count }) + sentence.count > Self.budget, readCount > 0 {
                cut = true
                waiting = []
            } else if readCount < 2 && waiting.isEmpty {
                read += sentence.count
                readCount += 1
                out.append(sentence)
            } else {
                waiting.append(sentence)
            }
        }
        if ending, !cut {
            out += waiting
            waiting = []
        }
        return out
    }

    private func clean(_ sentences: [String]) -> [String] {
        sentences.map(ArisSpeakable.speakable).filter { !$0.isEmpty }
    }
}
