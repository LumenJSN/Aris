//
//  ArisRiskPolicy+Provenance.swift
//  aris-agent
//
//  The owner's ruling R1 = B: once a conversation has seen the screen, an action still goes as judged only when its target
//  and every word in it come from what the user said this turn (the request, from the microphone or their typing). The screen
//  can't choose a recipient or a word the user didn't say; anything it could have chosen asks them.
//
//  Strict on purpose (security review of P1.3), and only for screenSeen coverage (the untainted countdown keeps the
//  looser dictation matcher): the raw argument may hold only Hangul syllables, ASCII letters and digits, single spaces
//  and a few marks; its tokens must be one exact run of the request's tokens (whole syllables with their final
//  consonant, whole Latin words), with only a closing quotative ending (라고, 이라고…) dropped; a target must be named
//  exactly ("엄마한테", "tell Kim Minji"), never by a prefix. Times, files, schedules and the rest are never covered.
//

import Foundation

extension ArisRiskPolicy {
    private static let coveredMarks = Set(".,!~'\"".unicodeScalars)
    /// At most this many marks in a covered text: a run of them could spell something out.
    private static let marksLimit = 3
    /// What splits words: spaces and punctuation, quotes included.
    private static let tokenSplitters = Set(" .,!?~…'\"‘’“”「」『』:;-()[]".unicodeScalars)
    /// A closing quotative ending the user's words may carry and the sent text may drop (longest first).
    private static let quotatives = ["이라고요", "라고요", "이라고", "라고", "고"]
    /// The particle that makes a word the recipient ("엄마한테").
    private static let recipientParticles = ["한테는", "에게는", "한테", "에게", "께"]
    private static let englishLeads: Set<String> = ["tell", "text", "message", "to"]
    /// Words that ask for a send; never part of the text that is sent.
    private static let coveredSendWords: Set<String> = ["보내", "보내줘", "보내줄래", "보내요", "전해", "전해줘", "문자", "메시지", "메세지",
                                                       "tell", "text", "message", "send"]

    /// Whether `action`'s target and every content field come from `request`. Unknown actions, subcommands, fields,
    /// flags and times are never covered.
    static func coveredByRequest(_ action: ArisAction, tools: String, arguments: [String: Any], request: String) -> Bool {
        let request = ArisMemoryText.ownWords(request)  // a file's text is never the user's words
        let heard = request.precomposedStringWithCanonicalMapping
        guard !tokens(heard).isEmpty, !coversNothing(request) else { return false }
        switch action {
        case .shell(let command):
            guard let pieces = ArisCommandPolicy.segments(command), pieces.count == 1, let words = ArisCommandPolicy.words(command),
                  words.count > 1, words.first == tools, !tools.isEmpty else { return false }
            return coveredCommand(Array(words.dropFirst()), request: heard)
        case .mcp(let server, let tool):
            guard isFullyScoped(server: server, tool: tool, arguments: arguments), !arguments.isEmpty else { return false }
            let targets = Set(ArisToolSchemas.spec(server: server, tool: tool).map { ArisToolSchemas.walk(arguments, spec: $0).targets } ?? [])
            return arguments.allSatisfy { key, value in leafCovered(value, target: isTargetKey(key), targets: targets, request: heard) }
        case .fileChange, .computerUse, .browserTask:
            return false
        }
    }

    /// One aris-tools command, by subcommand: which words are a target and which are text. A flag (times, lists,
    /// notes, titles) is never covered: each one asks.
    private static func coveredCommand(_ words: [String], request: String) -> Bool {
        let rest = Array(words.dropFirst())
        if ArisConvertWords.verbs.contains(words[0]) { return coveredConversion(words, request: request) }
        guard !rest.contains(where: { $0.hasPrefix("-") }) else { return false }
        switch words[0] {
        case "message":
            guard rest.count >= 2 else { return false }
            return coveredMessage(to: rest[0], text: rest.dropFirst().joined(separator: " "), request: request)
        // (Not `note`: a note always shows its card with its title and first lines.)
        case "remember", "forget", "remind":
            return isUsersWords(rest.joined(separator: " "), in: request)
        case "todo":
            guard rest.first == "add" || rest.first == "edit", rest.count >= 2 else { return false }
            return isUsersWords(rest.dropFirst().joined(separator: " "), in: request)
        default:
            // Events (always a time), files, schedules (a model-written prompt), keys, links and the rest.
            return false
        }
    }

    /// A conversion (convert, merge, split, compress: audit gate-4) only makes new files beside the originals, so the one
    /// thing the screen could have chosen is which files. It is covered when the owner picked them themselves (--finder, --shelf:
    /// aris-tools reads his selection, the brain names no file) or when his own words hold every file's name (without
    /// its extension, case, spacing and marks aside, at least two characters). The name must begin where one of his
    /// words begins (a particle may follow it: "영수증을"), and a word for any file or a kind of file ("파일", "pdf",
    /// "사진") names none: "이 pdf 파일 png로 변환해 줘" doesn't pick ~/Private/파일.pdf (security review 2 L3). Anything
    /// else asks on his card.
    private static func coveredConversion(_ words: [String], request: String) -> Bool {
        guard let call = ArisConvertWords.parse(words) else { return false }
        if call.selector != nil { return true }
        let heard = ArisMemoryText.words(request)
        // What their words read as from each word's start on, spaces aside ("세금 보고서를" holds the name "세금보고서").
        let starts = heard.indices.map { heard[$0...].joined() }
        return !call.paths.isEmpty && call.paths.allSatisfy { path in
            let name = ArisMemoryText.normalized(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
            return name.count >= 2 && !fileWords.contains(name) && starts.contains { $0.hasPrefix(name) }
        }
    }

    /// Words that mean "a file" or a kind of file: saying one names no particular file.
    private static let fileWords: Set<String> = [
        "파일", "문서", "서류", "사진", "이미지", "그림", "영상", "동영상", "비디오", "음악", "노래", "소리", "녹음", "스크린샷", "캡처", "화면", "이거", "이것", "그거", "저거",
        "file", "files", "document", "documents", "doc", "docs", "image", "images", "picture", "pictures", "photo", "photos", "video", "videos", "movie",
        "audio", "sound", "music", "song", "recording", "screenshot", "this", "that", "these", "it",
        "pdf", "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "svg", "mp4", "mov", "m4v", "m4a", "mp3", "wav", "aiff", "aac",
        "txt", "md", "rtf", "docx", "pages", "pptx", "key", "xlsx", "numbers", "csv", "zip",
    ]

    /// A message: the text is exactly the whole span the user dictated (rule 3), and the recipient is named exactly once,
    /// outside that span (rule 4).
    /// - Korean: one recipient phrase ("엄마한테"); the span is what lies between it and the send verb ("엄마한테 곧 간다고
    ///   보내"), or before it when it sits right before the verb ("곧 간다고 엄마한테 보내").
    /// - English: the name right after tell/text/message/to, once; the span runs from there to the end (a leading "that"
    ///   dropped).
    static func coveredMessage(to: String, text: String, request: String) -> Bool {
        let heard = spoken(tokens(request.precomposedStringWithCanonicalMapping))
        guard let said = plainTokens(text, question: request.contains("?")), let name = plainTokens(to, question: false) else { return false }
        if let span = koreanSpan(name: name, in: heard) { return matchesSpan(said, span) }
        if let span = englishSpan(name: name, in: heard, raw: spoken(rawTokens(request.precomposedStringWithCanonicalMapping)),
                                  request: request.precomposedStringWithCanonicalMapping) { return said == span }
        return false
    }

    /// After outside text or the screen, a maps lookup whose place words aren't all the user's own could carry what was read
    /// to Apple's map service (follow-up M1): it asks on the user's card like anything outbound, never the read judge. "Here"
    /// is nobody's text; a place is the user's when their request holds it, case and spacing aside ("나이아가라 폭포" in
    /// "…나이아가라 폭포까지 …").
    /// An `open` of a file the user gave Aris (its path is in their request's files note): it launches an app on their screen,
    /// so it is a UI action on his card, never at once (QA BUG-35: asking about a dropped PDF opened it in Preview).
    static func opensAttachment(_ action: ArisAction, tools: String, request: String) -> Bool {
        guard case .shell(let command) = action, let note = request.range(of: ArisMemoryText.filesNote),
              let pieces = ArisCommandPolicy.segments(command) else { return false }
        // The note's paths, and each opened path, expanded and standardized (security review LOW 9: ~ against /Users/…).
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standard = { (path: String) in ((path.hasPrefix("~/") ? home + path.dropFirst(1) : path) as NSString).standardizingPath }
        let listed = String(request[note.upperBound...]).components(separatedBy: " — ").first ?? ""
        let attached = Set(listed.components(separatedBy: ", ").map(standard))
        return pieces.contains { piece in
            guard let words = ArisCommandPolicy.words(piece), let first = words.first else { return false }
            let paths: [String]
            if first == tools, words.count > 2, words[1] == "open" { paths = Array(words.dropFirst(2)) }
            else if (first as NSString).lastPathComponent == "open" { paths = Array(words.dropFirst()).filter { !$0.hasPrefix("-") } }
            else { return false }
            return paths.contains { $0.count > 1 && attached.contains(standard($0)) }
        }
    }

    static func mapsLookupCarries(_ action: ArisAction, tools: String, request: String) -> Bool {
        guard case .shell(let command) = action, let pieces = ArisCommandPolicy.segments(command) else { return false }
        let compact = { (text: String) in text.precomposedStringWithCanonicalMapping.lowercased().filter { !$0.isWhitespace } }
        let heard = compact(ArisMemoryText.ownWords(request))
        return pieces.contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.first == tools else { return false }
            let rest = Array(words.dropFirst())
            guard ArisReadGate.isMapsLookup(rest) else { return false }
            return rest.dropFirst(2).dropLast().contains { place in
                guard !ArisWidgetPick.here.contains(place.lowercased()) else { return false }
                let said = compact(place)
                return said.isEmpty || !heard.contains(said)
            }
        }
    }

    /// Text that is exactly the whole span the user dictated for a note, a fact, a reminder or a to-do: the request without
    /// its command verb (기억해, 넣어줘, remember…) and where it goes ("할 일에", "메모에").
    static func isUsersWords(_ text: String, in request: String) -> Bool {
        let request = ArisMemoryText.ownWords(request)  // a file's text is never the user's words
        let heard = spoken(tokens(request.precomposedStringWithCanonicalMapping))
        guard let said = plainTokens(text, question: request.contains("?")) else { return false }
        guard heard.contains(where: isCommand) else { return false }
        var span = Array(heard.prefix { !isCommand($0) })
        while let first = span.first, placeWords.contains(first) { span.removeFirst() }
        while let last = span.last, placeWords.contains(last) { span.removeLast() }
        return !span.isEmpty && matchesSpan(said, span)
    }

    /// A target on its own (an MCP target field): only the Korean form, the name plus a dative particle, and the only
    /// recipient phrase in the request. An English name is covered only inside a message.
    static func isNamedTarget(_ name: String, in request: String) -> Bool {
        let heard = spoken(tokens(request.precomposedStringWithCanonicalMapping))
        guard let said = plainTokens(name, question: false), heard.filter(isRecipientPhrase).count == 1 else { return false }
        // The whole recipient run: the phrase opens the request, so every word before the particle is the name.
        return recipientEnds(said, in: heard).contains { $0.korean && $0.next == said.count }
    }

    /// The span after the one Korean recipient phrase up to the send verb, or before the phrase when it sits right
    /// before the verb. Nil unless the request has exactly one recipient phrase, it names `name`, and a send verb ends
    /// the request (only 줘/주세요… may follow it).
    private static func koreanSpan(name: [String], in heard: [String]) -> [String]? {
        guard heard.filter(isRecipientPhrase).count == 1,
              let verb = heard.lastIndex(where: isSendVerb), heard[(verb + 1)...].allSatisfy(politeTails.contains),
              let match = recipientEnds(name, in: heard).first(where: { $0.korean }) else { return nil }
        let phraseStart = match.next - name.count, phraseEnd = match.next
        guard phraseEnd <= verb else { return nil }
        var between = Array(heard[phraseEnd..<verb])
        while let last = between.last, isSendWordToken(last) { between.removeLast() }
        let span: [String]
        if between.isEmpty {
            // Right before the verb ("곧 간다고 엄마한테 (문자) 보내"): the span is everything before the phrase, and it
            // must end in a quotative, so the word next to the phrase can't be part of the name ("…간다고 김 민지한테").
            span = Array(heard[..<phraseStart])
            // The ending must sit on a longer word ("간다고", never a lone "고" or "라고", which could be a name or have
            // a name in front of it), so the span ends exactly where the phrase begins.
            guard let last = span.last, let ending = quotatives.first(where: { last.hasSuffix($0) }), last.count > ending.count else { return nil }
        } else {
            // The phrase opens the request: every word before the particle is the name, so "민지" never stands in for
            // "김 민지".
            guard phraseStart == 0 else { return nil }
            span = between
        }
        return span.isEmpty || span.contains(where: isSendWordToken) ? nil : span
    }

    /// The English span. The request names exactly one recipient (a lead word followed by a word, counted over the whole
    /// request) and no Korean one; the lead right before the name is tell/text/message, or "to" right after send/message;
    /// the name is the whole run there: its capitalized words ("Kim Minji", never "Kim"; "I" is never a name), or the
    /// one lowercase word ("mom"). Then the rest of the request, a leading "that" dropped, with no other naming in it.
    private static func englishSpan(name: [String], in heard: [String], raw: [String], request: String) -> [String]? {
        guard raw.count == heard.count, !heard.contains(where: isRecipientPhrase) else { return nil }
        let namings = heard.indices.dropFirst().filter { englishLeads.contains(heard[$0 - 1]) && !englishLeads.contains(heard[$0]) }
        guard namings.count == 1, let start = namings.first else { return nil }
        let lead = heard[start - 1]
        guard ["tell", "text", "message"].contains(lead) || (lead == "to" && start >= 2 && ["send", "message"].contains(heard[start - 2])) else { return nil }
        var end = start + 1
        if isCapitalized(raw[start]) {
            while end < raw.count, isCapitalized(raw[end]) { end += 1 }
        }
        guard Array(heard[start..<end]) == name else { return nil }
        // A lowercase name ("mom") with more words after it could be the start of a longer name: only a clear separator
        // right after it ("that", ":" or ",") says where it ends.
        if !isCapitalized(raw[start]), end < heard.count, heard[end] != "that",
           !separated(lead: lead, name: Array(raw[start..<end]), in: request) { return nil }
        var span = Array(heard[end...])
        if span.first == "that" { span.removeFirst() }
        return span.isEmpty || span.contains(where: coveredSendWords.contains) ? nil : span
    }

    /// The request's words without one leading call of Aris's own name (아리스야, 아리스, 아리스아, Aris, Hey Aris; a comma
    /// after it is a splitter anyway). Nothing else is ever dropped.
    private static func spoken(_ words: [String]) -> [String] {
        let lowered = words.prefix(2).map { $0.lowercased() }
        if lowered.count == 2, lowered == ["hey", "aris"] { return Array(words.dropFirst(2)) }
        if let first = lowered.first, ["아리스야", "아리스", "아리스아", "aris"].contains(first) { return Array(words.dropFirst()) }
        return words
    }

    /// "<lead> <name>," or "<lead> <name>:" in the request as written.
    private static func separated(lead: String, name: [String], in request: String) -> Bool {
        let pattern = "(?i)\\b" + NSRegularExpression.escapedPattern(for: lead) + "\\s+"
            + name.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s+") + "\\s*[,:]"
        return request.range(of: pattern, options: .regularExpression) != nil
    }

    /// A word that could be part of a name: an ASCII capital first, and not the pronoun "I".
    private static func isCapitalized(_ word: String) -> Bool {
        guard let first = word.unicodeScalars.first, word != "I" else { return false }
        return ("A"..."Z").contains(Character(first))
    }

    /// The request's words as written (case kept), split the same way as `tokens`.
    private static func rawTokens(_ text: String) -> [String] {
        text.unicodeScalars.split(whereSeparator: { tokenSplitters.contains($0) }).map { String(String.UnicodeScalarView($0)) }
    }

    /// The text equals the span, or the span with the quotative ending of its last word taken off (the longest one:
    /// 이라고요, 라고요, 이라고, 라고, or 고 attached to that word); a quotative standing alone ('곧 갈게'라고) is dropped.
    private static func matchesSpan(_ said: [String], _ span: [String]) -> Bool {
        var span = span
        if let last = span.last, quotatives.contains(last) {
            span.removeLast()
            return !span.isEmpty && said == span
        }
        if said == span { return true }
        guard let last = span.last, let ending = quotatives.first(where: { last.hasSuffix($0) && last.count > $0.count }) else { return false }
        return said == Array(span.dropLast()) + [String(last.dropLast(ending.count))]
    }

    /// The text's words when its raw characters are all plain (rule 1), single-spaced, with at most a few marks and
    /// no send word; nil otherwise.
    private static func plainTokens(_ text: String, question: Bool) -> [String]? {
        guard isCoveredPlain(text, question: question), !text.contains("  "), text == text.trimmingCharacters(in: .whitespaces),
              text.unicodeScalars.filter({ coveredMarks.contains($0) || $0 == "?" }).count <= marksLimit else { return nil }
        let said = tokens(text)
        return said.isEmpty || said.contains(where: isSendWordToken) ? nil : said
    }

    /// A word that names a recipient: it ends in a dative particle ("함께", together, isn't one).
    private static func isRecipientPhrase(_ token: String) -> Bool {
        token != "함께" && recipientParticles.contains { token.hasSuffix($0) && token.count > $0.count }
    }

    private static func isSendVerb(_ token: String) -> Bool {
        ["보내", "전해", "send", "tell", "text"].contains { token.hasPrefix($0) } || ["문자", "메시지", "메세지", "message"].contains(token)
    }

    private static func isSendWordToken(_ token: String) -> Bool { coveredSendWords.contains(token) || isSendVerb(token) }

    /// What may follow the send verb ("보내 줘").
    private static let politeTails: Set<String> = ["줘", "줘요", "주세요", "줄래", "줄래요", "줄래?", "please"]

    /// Where a note, fact or to-do goes: never part of it.
    private static let placeWords: Set<String> = ["할", "일에", "할일에", "메모에", "메모로", "목록에", "리마인더에", "미리", "알림에", "투두에", "노트에"]

    /// The verb that asks for a note, a fact, a reminder or a to-do.
    private static func isCommand(_ token: String) -> Bool {
        ["기억", "메모해", "적어", "넣어", "추가해", "알려", "잊어", "지워", "remember", "note", "add", "remind", "forget"].contains { token.hasPrefix($0) }
    }

    /// Each exact naming of `name` in the request: Korean, a run whose last word is the name plus a dative particle;
    /// English, a run right after tell/text/message/to. `next`: the word after the run.
    private static func recipientEnds(_ said: [String], in heard: [String]) -> [(korean: Bool, next: Int)] {
        guard !said.isEmpty, said.count <= heard.count, let last = said.last else { return [] }
        var found: [(Bool, Int)] = []
        for start in 0...(heard.count - said.count) {
            let window = Array(heard[start..<(start + said.count)])
            guard Array(window.dropLast()) == Array(said.dropLast()), let end = window.last else { continue }
            if recipientParticles.contains(where: { end == last + $0 }) { found.append((true, start + said.count)) }
            if end == last, start > 0, englishLeads.contains(heard[start - 1]) { found.append((false, start + said.count)) }
        }
        return found
    }

    private static func leafCovered(_ value: Any, target: Bool, targets: Set<String>, request: String) -> Bool {
        switch value {
        case let text as String:
            return target || targets.contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
                ? isNamedTarget(text, in: request) : isUsersWords(text, in: request)
        case let list as [Any]:
            return !list.isEmpty && list.allSatisfy { leafCovered($0, target: target, targets: targets, request: request) }
        case let object as [String: Any]:
            return !object.isEmpty && object.allSatisfy { key, inner in
                leafCovered(inner, target: target || isTargetKey(key), targets: targets, request: request)
            }
        case let number as NSNumber:
            // A true/false says nothing; a number must be a word the user said, exactly.
            return CFGetTypeID(number) == CFBooleanGetTypeID() || tokens(request).contains(number.stringValue)
        default:
            return false
        }
    }

    /// Only Hangul syllables, ASCII letters and digits, U+0020 and . , ! ~ ' " (and ? when the user asked one). No other
    /// space, mark, digit, jamo, compatibility or decomposed form: the raw text that is sent, unfolded.
    private static func isCoveredPlain(_ text: String, question: Bool) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            (0xAC00...0xD7A3).contains(scalar.value)
                || (scalar.isASCII && (("a"..."z").contains(Character(scalar)) || ("A"..."Z").contains(Character(scalar)) || ("0"..."9").contains(Character(scalar))))
                || scalar == " " || coveredMarks.contains(scalar) || (question && scalar == "?")
        }
    }

    /// Words split on spaces and punctuation (quotes included), ASCII letters lowercased.
    static func tokens(_ text: String) -> [String] {
        text.lowercased().unicodeScalars.split(whereSeparator: { tokenSplitters.contains($0) }).map { String(String.UnicodeScalarView($0)) }
    }
}
