//
//  ArisMailText.swift
//  aris-tools (also built into aris-agent)
//
//  A mail's text made fit to hand to an AI and to read: an HTML mail reduced to the words the user would see (nothing
//  hidden, no scripts or styles, a quoted block marked as a quote), the history a reply drags along folded to one
//  line so a long thread doesn't repeat itself, characters that show nothing taken out, sign-in codes masked, and a
//  huge mail cut at a stated length. Pure, so the tests run it.
//

import Foundation

enum ArisMailText {
    /// The most of one mail's text that is given back at once; the rest is asked for with `--part 2`.
    static let partLength = 6_000
    /// The most of a whole thread.
    static let threadLength = 14_000
    /// The most of each mail inside a thread.
    static let threadMailLength = 2_500

    // MARK: - HTML

    private static let blockTags: Set<String> = ["p", "div", "br", "tr", "li", "h1", "h2", "h3", "h4", "h5", "h6", "table", "ul", "ol", "blockquote", "hr",
                                                 "pre", "section", "article", "header", "footer", "dt", "dd"]
    private static let droppedTags: Set<String> = ["script", "style", "head", "title", "template", "noscript", "svg", "object", "iframe"]
    private static let voidTags: Set<String> = ["br", "img", "hr", "input", "meta", "link", "wbr", "area", "base", "col", "embed", "source", "track"]
    private static let entities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©", "reg": "®", "hellip": "…", "mdash": "—", "ndash": "–",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”", "middot": "·", "bull": "•", "trade": "™", "laquo": "«", "raquo": "»", "zwnj": "", "zwj": "",
    ]

    /// An HTML mail as text: what a reader sees, one block a line. Text styled so it can't be seen (display:none, a
    /// zero font size, hidden) is left out, since the user never saw it; a quoted block's lines start with ">".
    /// Read as Mail's own page reads it where that decides what is seen: a ">" inside a quoted attribute doesn't end
    /// the tag, a closing tag that closes nothing doesn't end a hidden block, and a class or id that the mail's own
    /// style sheet hides is hidden too.
    static func html(_ source: String) -> String {
        let sheet = hiddenBySheet(source)
        var out = "", quote = 0
        // The tags open inside a block that can't be seen, the one that hides it first; empty when text shows.
        var hidden: [String] = []
        var index = source.startIndex
        func newline() { if !out.hasSuffix("\n") && !out.isEmpty { out += "\n" } }
        func emit(_ text: String) {
            guard hidden.isEmpty else { return }
            for character in text {
                let space = character == " " || character == "\n" || character == "\t" || character == "\r" || character == "\u{A0}"
                if space { if !out.isEmpty && !out.hasSuffix(" ") && !out.hasSuffix("\n") { out += " " }; continue }
                if quote > 0, out.isEmpty || out.hasSuffix("\n") { out += String(repeating: ">", count: min(quote, 5)) + " " }
                out.append(character)
            }
        }
        while index < source.endIndex {
            let character = source[index]
            if character == "<", startsTag(source, at: index) {
                if source[index...].hasPrefix("<!--") {
                    index = source.range(of: "-->", range: index..<source.endIndex)?.upperBound ?? source.endIndex
                    continue
                }
                let close: String.Index
                switch tagEnd(source, from: index) {
                case .at(let found): close = found
                // A quote that never closes takes the rest of the mail into the tag, on screen too: nothing after it shows.
                case .openQuote: index = source.endIndex; continue
                // No ">" at all: no tag, so its text is kept.
                case .none: emit(String(source[index...])); index = source.endIndex; continue
                }
                let tag = readTag(source[source.index(after: index)..<close])
                index = source.index(after: close)
                if tag.name.isEmpty { continue }
                if droppedTags.contains(tag.name) {
                    // Everything up to its own closing tag is left out (a script's or a style's text holds no tags).
                    if !tag.closing, !(tag.selfClosing && tag.name == "svg") {
                        index = source.range(of: "</" + tag.name, options: .caseInsensitive, range: index..<source.endIndex)?.lowerBound ?? source.endIndex
                    }
                    continue
                }
                // (Only a tag that never has content is closed by itself: "<div …/>" opens a div.)
                let empty = voidTags.contains(tag.name)
                // A paragraph, a list item or a table cell ends where the next one begins, with no closing tag.
                if hidden.count == 1, !tag.closing, endsUnclosed(hidden[0], at: tag.name) { hidden = [] }
                if !hidden.isEmpty {
                    // Only a tag opened inside the hidden block closes one: a stray "</span>" never ends it early.
                    if tag.closing { if let opened = hidden.lastIndex(of: tag.name) { hidden.removeSubrange(opened...) } } else if !empty { hidden.append(tag.name) }
                    continue
                }
                if !tag.closing, !empty, hides(tag.attributes, sheet: sheet) { hidden = [tag.name]; continue }
                if blockTags.contains(tag.name) { newline() }
                if tag.name == "blockquote" { quote = max(0, quote + (tag.closing ? -1 : 1)) }
                if tag.name == "li", !tag.closing { emit("- ") }
            } else if character == "&", let semicolon = source[index...].prefix(12).firstIndex(of: ";"),
                      let decoded = entity(source[source.index(after: index)..<semicolon]) {
                emit(decoded)
                index = source.index(after: semicolon)
            } else {
                emit(String(character))
                index = source.index(after: index)
            }
        }
        return out.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether an open `tag` ends by itself where `next` opens (HTML's optional closing tags, the common ones).
    private static func endsUnclosed(_ tag: String, at next: String) -> Bool {
        switch tag {
        case "p": return blockTags.contains(next) && next != "br"
        case "li": return next == "li"
        case "td", "th": return ["td", "th", "tr"].contains(next)
        case "tr": return next == "tr"
        default: return false
        }
    }

    /// Whether the "<" here begins a tag (a letter, "/", "!" or "?" follows); any other "<" is text ("a < b").
    private static func startsTag(_ source: String, at index: String.Index) -> Bool {
        let next = source.index(after: index)
        guard next < source.endIndex else { return false }
        return source[next].isLetter || source[next] == "/" || source[next] == "!" || source[next] == "?"
    }

    private enum TagEnd {
        case at(String.Index), openQuote, none
    }

    /// Where the tag that begins at `index` ends: its first ">" outside a quoted attribute value (title="a>b").
    private static func tagEnd(_ source: String, from index: String.Index) -> TagEnd {
        var position = source.index(after: index)
        // "<!doctype …>" and "<?xml …>" have no attributes: their first ">" ends them.
        if source[position] == "!" || source[position] == "?" { return source[position...].firstIndex(of: ">").map { .at($0) } ?? .none }
        var quote: Character?, afterEquals = false
        while position < source.endIndex {
            let character = source[position]
            if let open = quote {
                if character == open { quote = nil }
            } else if (character == "\"" || character == "'") && afterEquals {
                quote = character
            } else if character == ">" {
                return .at(position)
            }
            // A value's quote comes right after "=" (spaces may lie between).
            if quote == nil { afterEquals = character == "=" || (afterEquals && character.isWhitespace) }
            position = source.index(after: position)
        }
        return quote != nil ? .openQuote : .none
    }

    private static func readTag(_ inside: Substring) -> (name: String, closing: Bool, selfClosing: Bool, attributes: String) {
        var text = inside.trimmingCharacters(in: .whitespacesAndNewlines)
        let closing = text.hasPrefix("/")
        if closing { text.removeFirst() }
        let selfClosing = text.hasSuffix("/")
        let name = text.prefix { $0.isLetter || $0.isNumber }.lowercased()
        return (name, closing, selfClosing, String(text.dropFirst(name.count)))
    }

    /// A tag's attributes by name (lowercased), each value as the page reads it: quotes off, character names decoded
    /// (style="display&#58;none" is display:none).
    private static func attributeValues(_ attributes: String) -> [String: String] {
        var found: [String: String] = [:]
        let characters = Array(attributes)
        var index = 0
        while index < characters.count {
            while index < characters.count, characters[index].isWhitespace || characters[index] == "/" { index += 1 }
            var name = ""
            while index < characters.count, !characters[index].isWhitespace, characters[index] != "=", characters[index] != "/" { name.append(characters[index]); index += 1 }
            while index < characters.count, characters[index].isWhitespace { index += 1 }
            var value = ""
            if index < characters.count, characters[index] == "=" {
                index += 1
                while index < characters.count, characters[index].isWhitespace { index += 1 }
                if index < characters.count, characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    while index < characters.count, characters[index] != quote { value.append(characters[index]); index += 1 }
                    index += 1
                } else {
                    while index < characters.count, !characters[index].isWhitespace { value.append(characters[index]); index += 1 }
                }
            }
            if !name.isEmpty, found[name.lowercased()] == nil { found[name.lowercased()] = decoded(value) }
        }
        return found
    }

    /// Text with its character names (&#58; &amp;) read.
    private static func decoded(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = "", index = text.startIndex
        while index < text.endIndex {
            if text[index] == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";"), let character = entity(text[text.index(after: index)..<semicolon]) {
                out += character
                index = text.index(after: semicolon)
            } else {
                out.append(text[index])
                index = text.index(after: index)
            }
        }
        return out
    }

    /// Whether a tag keeps its text from being seen: the `hidden` attribute, its own style, or a class or id the
    /// mail's style sheet hides.
    private static func hides(_ attributes: String, sheet: (classes: Set<String>, ids: Set<String>)) -> Bool {
        let found = attributeValues(attributes)
        if found["hidden"] != nil { return true }
        if let style = found["style"], hidesStyle(style) { return true }
        if let id = found["id"], sheet.ids.contains(id.trimmingCharacters(in: .whitespaces)) { return true }
        if let classes = found["class"], classes.split(whereSeparator: \.isWhitespace).contains(where: { sheet.classes.contains(String($0)) }) { return true }
        return false
    }

    /// Whether style declarations keep text from being seen: nothing shown, no size or a size too small to read,
    /// see-through, cut to nothing, or pushed off the page. (Text in the page's own colour can't be told from here.)
    static func hidesStyle(_ css: String) -> Bool {
        let compact = String(css.lowercased().replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression).filter { !$0.isWhitespace })
        let start = "(^|;)", end = "(;|!|$)", zero = "0+(\\.0+)?(px|pt|em|rem|%)?", dot = "(" + zero + "|1(px|pt))"
        func has(_ pattern: String) -> Bool { compact.range(of: pattern, options: .regularExpression) != nil }
        let plain = ["display:none", "visibility:(hidden|collapse)", "mso-hide:all", "opacity:0+(\\.0+)?%?" + end,
                     "font-size:(0+(\\.\\d+)?|\\.\\d+)(px|pt)?" + end, "font-size:1(\\.\\d+)?(px|pt)" + end, "font-size:0+(\\.0+)?(em|rem|%|ex|vw|vh)" + end,
                     "max-height:" + zero + end,
                     "color:transparent", "color:(rgba|hsla)\\([^)]*,0+(\\.0+)?%?\\)", "color:#([0-9a-f]{6}00|[0-9a-f]{3}0)" + end,
                     "text-indent:-\\d{3,}", "clip:rect\\(([01](px)?,?){4}\\)", "clip-path:inset\\((50|100)%\\)"]
        if plain.contains(where: { has(start + $0) }) { return true }
        if has(start + "overflow:hidden"), has(start + "(max-)?(height|width):" + dot + end) { return true }
        return has(start + "position:(absolute|fixed)") && has(start + "(left|top|right|bottom|margin-left|margin-top):-\\d{3,}")
    }

    /// The classes and ids the mail's own style sheet hides (".preheader{display:none}"): rules at the top level of a
    /// <style> block whose selector ends in one class or one id. A rule inside @media is left alone (it hides only on
    /// another size of screen), and so is a selector with a state or an attribute in it.
    static func hiddenBySheet(_ source: String) -> (classes: Set<String>, ids: Set<String>) {
        var classes = Set<String>(), ids = Set<String>()
        guard let blocks = try? NSRegularExpression(pattern: #"<style\b[^>]*>([\s\S]*?)</style"#, options: .caseInsensitive) else { return (classes, ids) }
        for match in blocks.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let css = source[range].replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            var selector = "", body = "", depth = 0, skipping = false
            for character in css {
                if character == "{" {
                    depth += 1
                    if depth == 1 { skipping = selector.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@") }
                } else if character == "}" {
                    depth = max(0, depth - 1)
                    guard depth == 0 else { continue }
                    if !skipping, hidesStyle(body) {
                        for name in selector.split(separator: ",") {
                            let last = name.split(whereSeparator: { $0.isWhitespace || $0 == ">" || $0 == "+" || $0 == "~" }).last.map(String.init) ?? ""
                            guard last.range(of: #"^[A-Za-z0-9]*[.#][A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                                  let mark = last.firstIndex(where: { $0 == "." || $0 == "#" }) else { continue }
                            if last[mark] == "." { classes.insert(String(last[last.index(after: mark)...])) } else { ids.insert(String(last[last.index(after: mark)...])) }
                        }
                    }
                    (selector, body, skipping) = ("", "", false)
                } else if depth == 0 {
                    selector.append(character)
                } else if depth == 1 {
                    body.append(character)
                }
            }
        }
        return (classes, ids)
    }

    private static func entity(_ name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return entities[String(name)] ?? entities[name.lowercased()]
    }

    // MARK: - Quoted history

    /// A line that introduces the mail being answered ("On … wrote:", "…님이 작성:").
    private static func attributes(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count <= 300 else { return false }
        return trimmed.range(of: #"(wrote|writes|schrieb|a écrit|escribió)\s*:$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || trimmed.range(of: #"(작성|님이 씀|님이 쓴 글|보냄|写道|書きました)\s*[:：]$"#, options: .regularExpression) != nil
    }

    /// A line where an older mail begins without ">" marks (Outlook, Korean web mail): the divider, or the first of
    /// the copied header lines.
    private static func startsOlderMail(_ lines: [String], at index: Int) -> Bool {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        if line.range(of: #"^-{2,}\s*(original message|원본 메시지|원본 메일|원문)\s*-{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return true }
        let header = #"^(from|보낸 사람|보낸사람|발신)\s*[:：]"#, more = #"^(sent|date|to|subject|보낸 날짜|날짜|받는 사람|받는사람|제목|수신)\s*[:：]"#
        guard line.range(of: header, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        // Copied headers come together: two more of them in the next four lines.
        let next = lines[(index + 1)..<min(lines.count, index + 5)].filter {
            $0.trimmingCharacters(in: .whitespaces).range(of: more, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return next.count >= 2
    }

    /// The text with the older mails it quotes folded away: each run of ">" lines (with the line that introduces it),
    /// and everything from an older mail's copied header to the end. A mail that is only a forwarded one keeps it.
    /// `folded`: how many lines went.
    static func foldQuotes(_ text: String) -> (text: String, folded: Int) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var kept: [String] = [], folded = 0, run = 0, saidSomething = false
        func dropEmptyEnd() { while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty { kept.removeLast() } }
        func closeRun() {
            guard run > 0 else { return }
            // The line that led into the quote goes with it.
            dropEmptyEnd()
            if let last = kept.last, attributes(last) { kept.removeLast(); run += 1; dropEmptyEnd() }
            kept.append(quoteMark(run))
            folded += run
            run = 0
        }
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") { run += 1; continue }
            // An empty line inside a quote belongs to it.
            if run > 0, trimmed.isEmpty, lines[(index + 1)...].first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces).hasPrefix(">") == true { run += 1; continue }
            closeRun()
            if saidSomething, startsOlderMail(lines, at: index) {
                let rest = lines.count - index
                while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty || last.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "_" || $0 == "-" }) { kept.removeLast() }
                kept.append(quoteMark(rest))
                return (kept.joined(separator: "\n"), folded + rest)
            }
            if !trimmed.isEmpty { saidSomething = true }
            kept.append(line)
        }
        closeRun()
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), folded)
    }

    static func quoteMark(_ lines: Int) -> String { "[앞선 메일을 인용한 \(lines)줄은 접었어요]" }

    // MARK: - Cleaning and cutting

    /// Text as it is handed on: control characters and characters that show nothing (zero-width, direction marks) out,
    /// tabs as spaces, lines trimmed at the end, more than one empty line folded to one.
    static func clean(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.replacingOccurrences(of: "\r\n", with: "\n").unicodeScalars {
            if scalar == "\n" { scalars.append(scalar); continue }
            if scalar == "\t" || scalar == "\u{A0}" || scalar == "\r" { scalars.append(" "); continue }
            if scalar == "\u{FFFC}" || CharacterSet.controlCharacters.contains(scalar) || scalar.properties.generalCategory == .format
                || scalar.properties.generalCategory == .lineSeparator || scalar.properties.generalCategory == .paragraphSeparator { continue }
            scalars.append(scalar)
        }
        let lines = String(scalars).components(separatedBy: "\n").map { line -> String in
            var line = line
            while line.hasSuffix(" ") { line.removeLast() }
            return line
        }
        return lines.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sign-in codes and passwords masked line by line (ArisLocalStore.redact): a line counts as about a code when it,
    /// the line above it or the mail's subject says so, so an invoice's amounts stay readable.
    static func masked(_ text: String, subject: String) -> String {
        let aboutCode = ArisLocalStore.mentionsCode(subject)
        var above = false
        return text.components(separatedBy: "\n").map { line -> String in
            let result = ArisLocalStore.redact(line, codeContext: aboutCode || above)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { above = ArisLocalStore.mentionsCode(line) }
            return result
        }.joined(separator: "\n")
    }

    /// One window of a long text: part 1 is its first `length` characters. `note`: said under a cut text, naming how
    /// much there is and how to get the rest; nil when all of it is here.
    static func part(_ text: String, number: Int, length: Int = partLength, id: Int64? = nil) -> (text: String, note: String?) {
        let total = text.count
        guard total > length else { return (text, nil) }
        let parts = (total + length - 1) / length
        let wanted = min(max(1, number), parts)
        let window = String(text.dropFirst((wanted - 1) * length).prefix(length))
        let rest = wanted < parts ? " 이어서 보려면: mail read \(id.map(String.init) ?? "<id>") --part \(wanted + 1)" : ""
        return (window, "…여기서 잘랐어요. 이 메일은 \(total)자라서 \(parts)개로 나눴고, 지금은 \(wanted)번째예요.\(rest)")
    }

    /// Every line of a mail's own words behind a bar, so nothing a mail says can pass for a line of Aris's.
    static func barred(_ text: String) -> String {
        text.components(separatedBy: "\n").map { $0.isEmpty ? "│" : "│ " + $0 }.joined(separator: "\n")
    }

    /// "3.2 MB", "48 KB".
    static func size(_ bytes: Int) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1_024 { return "\(bytes / 1_024) KB" }
        return "\(bytes) B"
    }
}
