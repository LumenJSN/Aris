//
//  ArisMemoryLearning.swift
//  aris-agent
//
//  Learning after a turn, the rules (memory is curated after each turn, on the Mac, from the user's
//  words alone):
//  - Only a clean turn teaches: the user's own turn from the Aris app, in a conversation that never took in outside text
//    or saw the screen, not heard hands-free, not a background task, and whose brain read nothing others wrote
//    (taint none) by the time it answered. Outside text never writes memory.
//  - Only the user's words go in, never the answer or a tool's output.
//  - Most turns hold nothing lasting: words with no sign of the user talking about themselves skip the model entirely.
//  - What the on-device model (or, without one, the rules below) picks out is kept only when it is in the user's words
//    (most of its syllable pairs are), is no secret, and is at most three, each once.
//  Foundation only (tested).
//

import Foundation

enum ArisMemoryLearning {
    /// At most this many memories from one turn.
    static let perTurn = 3
    /// A picked-out memory is in the user's words when this much of it is.
    static let grounding = 0.7

    /// Whether the finished turn may teach memory (and add a day note).
    static func mayLearn(fromApp: Bool, task: Bool, untrusted: Bool, outsideConversation: Bool, screenSeen: Bool, handsFree: Bool,
                         images: Bool, screenText: Bool, tainted: Bool) -> Bool {
        fromApp && !task && !untrusted && !outsideConversation && !screenSeen && !handsFree && !images && !screenText && !tainted
    }

    /// Whether a turn gets memories in its context at all: the same as learning, minus the taint (not known yet). A
    /// hands-free, untrusted, outside-text or screen turn, a caller other than the app, and every job get none (outside
    /// text there could have them sent out).
    static func mayRecall(fromApp: Bool, task: Bool, untrusted: Bool, outsideConversation: Bool, screenSeen: Bool, handsFree: Bool,
                          images: Bool, screenText: Bool) -> Bool {
        mayLearn(fromApp: fromApp, task: task, untrusted: untrusted, outsideConversation: outsideConversation, screenSeen: screenSeen,
                 handsFree: handsFree, images: images, screenText: screenText, tainted: false)
    }

    /// Whether the agent answers a memory intent itself: the user's turn from the app, not hands-free (anyone's words: no
    /// reading his memories out to the room) and without screen images; one that writes only on a clean turn, except
    /// The user's own 기억해 (QA BUG-7): it is parsed from their request alone, never the brain's words, so it saves at once
    /// after outside text too. Anything else goes to the brain as before (whose gate decides: a brain-proposed memory
    /// write after outside text keeps its card).
    static func answersLocally(_ intent: ArisMemoryIntent, fromApp: Bool, handsFree: Bool, images: Bool, clean: Bool) -> Bool {
        guard fromApp, !handsFree, !images else { return false }
        if case .remember = intent { return true }
        return !intent.writes || clean
    }

    // MARK: - Memory commands and cards (QA BUG-6)

    /// The user's words to their memory ("…기억해", "…잊어", "…지워", "remember …", "forget …"): a command, never a fact to learn.
    static func isMemoryCommand(_ text: String) -> Bool {
        if let intent = ArisMemoryIntent.parse(text), intent.writes { return true }
        let tokens = text.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).union(CharacterSet(charactersIn: "'")).inverted).filter { !$0.isEmpty }
        let korean = tokens.contains { $0.hasPrefix("기억해") || $0.hasPrefix("잊어") || $0 == "잊지" || $0.hasPrefix("잊지마") || commandErase.contains($0) }
        return korean || tokens.contains("remember") || tokens.contains("forget")
    }

    private static let commandErase: Set<String> = ["지워", "지워줘", "지워요", "지워라", "지워주세요", "지워줄래", "지워버려"]

    /// Whether a finished turn teaches memory: nothing others wrote came in, and no card was shown at all (the user's yes
    /// or no to it is his answer, never saved by learning; and a turn that asked to do something was a request, not a
    /// fact about him: QA BUG-6, BUG-6b).
    static func learnsAfterTurn(taint: ArisTaint, card: Bool) -> Bool { taint == .none && !card }

    // MARK: - Requests (QA BUG-6b)

    /// Endings of a Korean request or imperative ("…알려 줘", "…추가해", "…만들어 줘").
    private static let requestEnds = ["줘", "줘요", "주세요", "줄래", "줄래요", "주라", "줘라", "추가해", "추가해요", "만들어", "알려", "보여",
                                      "켜", "꺼", "틀어", "찾아", "예약해", "설정해", "보내", "해봐", "해 봐"]
    /// Starts of an English one ("remind me …", "tell me …", "make …", "add …", "please …").
    private static let englishRequestStarts = ["remind me", "tell me", "make ", "add ", "please", "set ", "create ", "show me", "play ", "send ",
                                               "schedule ", "open ", "can you", "could you", "would you",
                                               // What a command opens with (final VM run: "pay my phone bill", "put it on my list with
                                               // that due date" were kept as facts about him and sent to the AI with later turns).
                                               "put ", "pay ", "call ", "text ", "email ", "mail ", "convert ", "find ", "delete ", "remove ", "move ", "rename ",
                                               "turn ", "start ", "stop ", "cancel ", "book ", "order ", "buy ", "check ", "look ", "search ", "summarize ",
                                               "summarise ", "translate ", "write ", "draft ", "type ", "read ", "list ", "save ", "download ", "run ", "say ",
                                               "mark ", "tick ", "undo ", "close ", "quit ", "launch ", "wrap up", "change ", "update ", "fix ", "show ", "give me",
                                               "get ", "help me", "i need you to", "i want you to", "let's "]

    /// A clause that asks Aris to do something: never a fact to learn, unless it says how the user always wants it
    /// ("커피는 늘 아이스 아메리카노로 해줘": isStanding).
    static func isRequest(_ clause: String) -> Bool {
        let lowered = clause.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        return requestEnds.contains(where: lowered.hasSuffix) || englishRequestStarts.contains(where: lowered.hasPrefix) || lowered.contains(" please")
    }

    /// Says how the user always wants something ("늘", "항상", "앞으로", "always", "from now on").
    static func isStanding(_ clause: String) -> Bool {
        let lowered = clause.lowercased()
        return ArisMemoryText.hasWord(lowered, "늘") || ["항상", "앞으로", "always", "from now on"].contains { lowered.contains($0) }
    }

    private static func isPlainRequest(_ text: String) -> Bool { isRequest(text) && !isStanding(text) }

    /// An action that writes the user's memory (`remember` or `forget`, in any piece of the line).
    static func isMemoryWrite(_ action: ArisAction, tools: String) -> Bool {
        guard case .shell(let raw) = action else { return false }
        let command = ArisCommandPolicy.unwrap(raw)
        return (ArisCommandPolicy.segments(command) ?? [command]).contains { piece in
            guard let words = ArisCommandPolicy.words(piece), words.count > 1, words[0] == tools else { return false }
            return words[1] == "remember" || words[1] == "forget"
        }
    }

    /// The user talking about themselves, their people, their work or their habits: whole words, then phrases.
    private static let koreanWordCues: Set<String> = ["나", "난", "내", "저", "전", "제", "늘", "우리"]
    private static let koreanCues = ["나는", "내가", "저는", "제가", "우리", "좋아", "싫어", "선호", "즐겨", "항상",
                                     "매일", "평일", "주말마다", "아침마다", "저녁마다", "매주", "보통", "주로", "맨날", "라고 불러", "라고 부르", "이름은",
                                     "다니", "다녀", "살아", "살고", "일해", "일하고", "만들고 있", "준비하고 있", "하고 있어", "하는 중", "전공"]
    private static let englishCues = ["i ", "i'm", "im ", "my ", "me ", "we ", "our ", "usually", "always", "every ", "prefer", "favorite", "favourite",
                                      "i like", "i love", "i hate", "call her", "call him", "working on"]

    /// A question, never a fact about the user (QA BUG-59: "내가 제일 좋아하는 과일이 뭐였지?" was learned as their preference): a
    /// question mark, a Korean question ending (뭐였지, 뭐야, …까, …나요), or an English opening that only asks.
    static func asks(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        if trimmed.contains("?") || trimmed.contains("？") { return true }
        let plain = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ".!~。 "))
        // Endings that only ask (never a plain statement: "우리 언니", "내 말이 맞아" stay facts).
        let korean = #"(뭐였지|뭐였더라|뭐더라|뭐지|뭐야|뭔데|뭘까|였지|였더라|었지|었더라|인가|인가요|일까|일까요|할까|줄까|볼까|갈까|될까|을까|까요|했니|있니|없니|였니|나요|어때|어때요|맞지)$"#
        if plain.range(of: korean, options: .regularExpression) != nil { return true }
        // An opening that only asks: never "do", "will" or "have", which also open a plain sentence ("Do not call me before nine").
        let english = #"(?i)^(what|who|whom|whose|when|where|why|how|which|is|are|am|was|were|does|did|can|could|should|would)\b"#
        return plain.range(of: english, options: .regularExpression) != nil
    }

    /// Whether `words` might hold something lasting about the user (else the model isn't asked).
    static func worthTrying(_ words: String) -> Bool {
        let text = " " + words.lowercased() + " "
        guard ArisMemoryText.normalized(words).count >= 6 else { return false }
        return ArisMemoryText.words(words).contains(where: koreanWordCues.contains) || koreanCues.contains { text.contains($0) }
            || englishCues.contains { text.contains(" " + $0) }
    }

    /// Someone else's words the user is passing on ("기사에 …라고 써 있어", "this page says …"): never about them.
    static let reportingMarkers = ["기사", "페이지", "메일", "써 있", "써있", "적혀 있", "적혀있", "라고 했", "라고했", "래요", "says", "said that", "according to"]

    static func isReported(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return reportingMarkers.contains { lowered.contains($0) }
    }

    /// The candidates kept: in the user's words (the clause it came from says no exactly when it does), no secret, not
    /// passed on from elsewhere, cleaned, each once, at most `perTurn`. A subject that isn't in their words is dropped (the
    /// text stays). Picked-out memories stay below the core ones until the user confirms them.
    static func accepted(_ candidates: [ArisMemoryCandidate], words: String) -> [ArisMemoryCandidate] {
        var kept: [ArisMemoryCandidate] = []
        let parts = clauses(words)
        // Words that ask Aris to do something are a request, and the pieces of a request are not facts about him
        // ("i still need to return the library book, …, put it on my list with that due date"; "every day at 2:24 am,
        // say good morning"): from such a turn only what says how he always wants it is kept. He can still say
        // "remember that …".
        let commanded = parts.contains(where: isPlainRequest)
        for raw in candidates {
            let text = ArisMemoryText.cleaned(raw.text)
            guard !commanded || isStanding(text) else { continue }
            // A question is never a fact, nor a value that only repeats what it's about ("내가 제일 좋아하는 과일" → itself).
            guard !asks(text), ArisMemoryText.normalized(text) != ArisMemoryText.normalized(raw.subject),
                  ArisMemoryText.normalized(text).count >= 3, !ArisMemoryText.isSecret(text), !isReported(text), !isMemoryCommand(text), !isPlainRequest(text),
                  ArisMemoryText.groundedness(text, in: words) >= grounding else { continue }
            // The clause it is most in: reported words or a no there count too.
            let source = parts.max { ArisMemoryText.groundedness(text, in: $0) < ArisMemoryText.groundedness(text, in: $1) } ?? words
            guard !isReported(source), !isPlainRequest(source), ArisMemoryText.isNegated(source) == ArisMemoryText.isNegated(text) else { continue }
            let subject = ArisMemoryText.cleaned(raw.subject)
            let groundedSubject = !subject.isEmpty && subject.count <= 20 && ArisMemoryText.normalized(words).contains(ArisMemoryText.normalized(subject))
                && !ArisMemoryText.isSecret(subject)
            let candidate = ArisMemoryCandidate(kind: raw.kind, subject: groundedSubject ? subject : "", text: text,
                                                confidence: min(raw.confidence, ArisMemoryStore.learnedConfidence))
            // The same thing twice, or a shorter piece of one already kept.
            guard !kept.contains(where: { ArisMemoryText.similarity($0.text, text) >= ArisMemoryMerge.rewordAt
                || ArisMemoryText.groundedness(text, in: $0.text) >= 0.7 }) else { continue }
            kept.append(candidate)
            if kept.count == perTurn { break }
        }
        return kept
    }

    // MARK: - Rules (no on-device model)

    /// Clauses of `words`: split at sentence ends, commas and "그리고".
    static func clauses(_ words: String) -> [String] {
        words.replacingOccurrences(of: "그리고", with: ",").replacingOccurrences(of: " and ", with: ",")
            .components(separatedBy: CharacterSet(charactersIn: ".!?,;\n。"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let questionEnds = ["까", "니", "냐", "나요", "어때", "뭐야", "뭐지", "할래", "있어?", "어디야", "언제야"]
    private static let commandEnds = ["해줘", "해 줘", "알려줘", "보여줘", "켜줘", "꺼줘", "틀어줘", "찾아줘", "줘", "주세요"]

    private static let questionWords = ["뭐", "뭘", "언제", "어디", "누구", "왜", "어떻게", "몇", "무슨", "어느"]
    private static let englishQuestionWords: Set<String> = ["what", "when", "where", "who", "why", "how", "which"]

    /// A clause that asks (its "?" was split off with it).
    private static func isQuestion(_ lowered: String) -> Bool {
        let words = lowered.split(separator: " ").map(String.init)
        return words.contains { word in questionWords.contains { word.hasPrefix($0) } } || words.first.map(englishQuestionWords.contains) == true
    }

    /// What the rules pick out of `words`: a clause where the user states a preference, a fact about themselves, a person,
    /// a project or a routine. Never a question; a request only when it says how he always wants it ("늘 …로 해줘").
    static func ruleCandidates(_ words: String) -> [ArisMemoryCandidate] {
        clauses(words).compactMap { clause -> ArisMemoryCandidate? in
            let lowered = clause.lowercased()
            guard ArisMemoryText.normalized(clause).count >= 5, worthTrying(clause), !isReported(clause), !isMemoryCommand(clause) else { return nil }
            guard !questionEnds.contains(where: { lowered.hasSuffix($0) }), !isQuestion(lowered) else { return nil }
            if commandEnds.contains(where: { lowered.hasSuffix($0) }) || isRequest(clause), !isStanding(clause) { return nil }
            return ArisMemoryCandidate(kind: ArisMemoryKind.guess(clause), subject: subject(of: clause), text: clause, confidence: 0.6)
        }
    }

    private static let topicParticles = ["은", "는", "이", "가", "을", "를"]

    /// The clause's topic, when it opens with one ("커피는 …" → 커피; "우리 엄마 이름은 …" → 엄마; "my mom …" → mom).
    static func subject(of clause: String) -> String {
        var words = clause.split(separator: " ").map(String.init)
        while let first = words.first, ["나는", "난", "저는", "전", "내", "제", "우리", "my", "our", "i"].contains(first.lowercased()) { words.removeFirst() }
        guard let first = words.first else { return "" }
        if ArisMemoryText.isKorean(first) {
            for particle in topicParticles where first.hasSuffix(particle) && first.count > particle.count {
                let stem = String(first.dropLast(particle.count))
                return stem.count >= 1 && stem.count <= 8 ? stem : ""
            }
            return ""
        }
        let lowered = first.lowercased()
        return ["mom", "dad", "brother", "sister", "friend", "girlfriend", "boyfriend", "wife", "husband", "professor"].contains(lowered) ? lowered : ""
    }
}
