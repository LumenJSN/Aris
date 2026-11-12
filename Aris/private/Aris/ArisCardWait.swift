//
//  ArisCardWait.swift
//  Aris
//
//  How a confirm card ends (QA BUG-39): only a clear answer does (a click, Y or N, a typed or spoken no, a spoken yes
//  where one counts). Silence or noise keeps it up until its limit, and then nothing is done and nothing is said to
//  have been declined. And a typed yes or no while a card is up answers that card, never a new turn (QA BUG-40). Pure.
//

import Foundation

/// Where a card's answer came from, for its one log line and the ledger (QA BUG-20b live). Pure.
enum ArisCardAnswer {
    enum Source: String {
        case click, key = "Y/N key", typed, voice, band, countdown, unanswered, ended = "turn ended", cancelled
        /// The user's turn or another card took the card's place before an answer (ArisCardCover).
        case covered

        /// Nobody answered: never logged or told as a yes or a no.
        var isNoAnswer: Bool { [.unanswered, .ended, .cancelled, .covered].contains(self) }
    }

    static func source(typed: Source?, heard: Bool, unanswered: Bool, ended: Bool, countdown: Bool, cancelled: Bool, covered: Bool = false) -> Source {
        if covered { return .covered }
        if ended { return .ended }
        if let typed { return typed }
        if heard { return .voice }
        if unanswered { return .unanswered }
        if countdown { return .countdown }
        return cancelled ? .cancelled : .unanswered
    }

    /// A desktop card answered yes hands macOS activation back to the process the card itself names
    /// (ArisActivationHandoff): only for a yes, only a desktop card, never to Aris, and only while that pid is still
    /// the same process (its bundle id and start time as the card had them). Pure.
    static func yieldsActivation(allow: Bool, card: ArisCardTarget?, own: Int32, bundle: String?, started: Double?) -> Bool {
        guard allow, let card, card.pid > 0, card.pid != own else { return false }
        return card.matches(bundle: bundle, started: started)
    }

    /// What the log and the ledger keep of a card's title: a message countdown's names no recipient or body.
    static func loggedTitle(_ title: String, countdown: Bool) -> String { countdown ? "message (countdown)" : title }

    /// Whether the app tells the agent's ledger about a card's answer: only for a card the app handles by itself. A card
    /// the agent made (a turn's, a job's parked one, an inbox one) gets its one line where the agent takes the answer
    /// (QA BUG-60: a job's card was written twice, a second apart, once from each side).
    static func appRecords(waiter: Bool, agentCard: Bool) -> Bool { !waiter && !agentCard }

    static func line(allow: Bool, source: Source) -> String {
        let answer = source.isNoAnswer ? "no answer" : allow ? "yes" : "no"
        return "card answer: \(answer) (\(source.rawValue))"
    }
}

enum ArisCardWait {
    /// How often a card asks the agent whether it still waits for the answer.
    static let waiterCheck: Duration = .seconds(2)
    /// How long a card whose request ended says so before it closes.
    static let endedShown: Duration = .milliseconds(1500)

    /// A card whose turn ended before the user answered: nothing runs.
    static func endedLine(korean: Bool) -> String { korean ? "이 요청은 끝났어요. 아무것도 하지 않았어요." : "This request has ended. Nothing was done." }

    /// The card waited out its limit with no answer at all.
    static func unanswered(_ answer: Bool?) -> Bool { answer == nil }

    /// What typed words do while a card is up: answer it, or nil (an ordinary turn, and the card stays up). Only a bare
    /// yes or no, or a yes with one short verb from the allow-list ("응, 지워", "네 해 줘", "yes, go ahead"); never anything
    /// with a "?" (security review: "yes what is this?" or "응 오늘 날씨" approved the card and swallowed the message).
    static func typedAnswer(_ text: String, cardUp: Bool) -> Bool? {
        guard cardUp, !text.contains("?"), !text.contains("？") else { return nil }
        let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if plain.range(of: typedNo, options: .regularExpression) != nil { return false }
        if plain.range(of: typedYes, options: .regularExpression) != nil { return true }
        return nil
    }

    private static let yesWords = #"(응|어|네|넵|예|그래|좋아|오케이|yes|yeah|yep|ok|okay|sure)(요)?"#
    private static let allowedVerbs = #"(해\s*줘|해\s*주세요|해|지워\s*줘|지워|만들어\s*줘|만들어|보내\s*줘|보내|do it|go ahead)(요)?"#
    private static let typedYes = "(?i)^" + yesWords + #"([\s,.!~]+"# + allowedVerbs + #")?[\s.!~]*$"#
    private static let typedNo = #"(?i)^(아니(요|야)?|아뇨|싫어(요)?|취소(해)?(\s*줘)?|안\s*해(요)?|하지\s*마(요)?|no|nope|cancel|don'?t)[\s.!~]*$"#

    /// The brain's reply after the turn's cards, never phrased as the system's refusal (QA BUG-39's copy, BUG-43): a card
    /// nobody answered gives the unanswered line, with whatever else the turn found or did kept after it (audit card-3);
    /// one the user said no to keeps the brain's words unless they say it was denied or refused, which become a plain
    /// "알겠어요, 안 할게요." in his terms.
    static func replyAfterCards(_ answer: String, unanswered: Bool, declined: Bool, korean: Bool) -> String {
        if unanswered { return afterUnanswered(answer, korean: korean) }
        guard declined else { return answer }
        if answer.range(of: systemRefusal, options: .regularExpression) != nil {
            // A routine's account of what it did before his no (its "### " sections) is never thrown away with it.
            return accountAfterNo(answer, korean: korean) ?? (korean ? "알겠어요, 안 할게요." : "OK, I won't.")
        }
        return usersNoWording(answer, korean: korean)
    }

    /// An answer that carries an account (a routine's: a first line, then a "### " section for each step, as
    /// ArisRoutineAccount writes it) after the user's no: kept whole but for the sentences that put their no on the system
    /// ("거부되어…", "was denied"), and a step left with no words says it wasn't done. Nil for an answer with no
    /// sections: a plain refusal sentence, which becomes "알겠어요, 안 할게요." as before.
    static func accountAfterNo(_ answer: String, korean: Bool) -> String? {
        let lines = answer.components(separatedBy: "\n")
        guard lines.contains(where: { $0.hasPrefix("### ") }) else { return nil }
        var kept: [String] = [], inSection = false, sectionHasWords = true
        func closeSection() {
            guard inSection, !sectionHasWords else { return }
            while let last = kept.last, last.trimmingCharacters(in: .whitespaces).isEmpty { kept.removeLast() }
            kept.append(korean ? "하지 않았어요." : "Not done.")
            kept.append("")
        }
        for line in lines {
            if line.hasPrefix("### ") {
                closeSection()
                (inSection, sectionHasWords) = (true, false)
                kept.append(line)
                continue
            }
            let plain = sentences(line).filter { $0.range(of: systemRefusal, options: .regularExpression) == nil }.joined(separator: " ")
            if !plain.trimmingCharacters(in: .whitespaces).isEmpty { sectionHasWords = true }
            // A line that was only such a sentence goes; an empty line of the account stays.
            if !plain.isEmpty || line.trimmingCharacters(in: .whitespaces).isEmpty { kept.append(plain) }
        }
        closeSection()
        let text = kept.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let opens = text.hasPrefix("알겠어요") || text.lowercased().hasPrefix("ok")
        return opens ? text : (korean ? "알겠어요, 안 할게요." : "OK, I won't.") + "\n\n" + text
    }

    /// The user's own no, said as their choice: "‘qa41’ 폴더는 만들지 못했어요" (a brain that retried and was refused, or a reword)
    /// becomes "알겠어요, ‘qa41’ 폴더는 만들지 않을게요" (QA live on b9c766bc: the same click-no read differently in a second
    /// turn of one session). A reply already in his terms stays.
    static func usersNoWording(_ answer: String, korean: Bool) -> String {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if korean {
            guard trimmed.contains("지 못했어요"), !trimmed.hasPrefix("알겠어요") else { return answer }
            return "알겠어요, " + trimmed.replacingOccurrences(of: "지 못했어요", with: "지 않을게요")
        }
        guard trimmed.range(of: #"(?i)\b(couldn'?t|wasn'?t able to|was unable to)\b"#, options: .regularExpression) != nil,
              !trimmed.lowercased().hasPrefix("ok") else { return answer }
        return "OK, I won't."
    }

    /// Words that put the user's no on the system.
    private static let systemRefusal = #"(?i)(거부(되|돼|당)|거절(되|돼|당)|허용되지\s*않|권한이\s*없|\bdenied\b|\brejected\b|\brefused\b|wasn'?t\s+allowed|not\s+permitted)"#

    /// The reply of a turn whose card nobody answered (audit card-3: the whole answer, a comparison the brain had
    /// already made for one, was replaced with "답이 없어서 하지 않았어요", and was lost to the notch, 읽어 줘 and 기록).
    /// The sentences that only say the step was refused, denied or left unanswered go (they would put the silence on
    /// the system, or on the user); when something else is left it is kept, after one line saying that the part needing their
    /// OK was not done. An answer with nothing else in it is the fixed unanswered line, as before.
    static func afterUnanswered(_ answer: String, korean: Bool) -> String {
        let kept = answer.components(separatedBy: "\n").map { line in
            sentences(line).filter { $0.range(of: unansweredWords, options: .regularExpression) == nil }.joined(separator: " ")
        }.joined(separator: "\n").replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard kept.unicodeScalars.filter(CharacterSet.alphanumerics.contains).count >= substance else { return unansweredLine(korean: korean) }
        return unansweredPartLine(korean: korean) + "\n\n" + kept
    }

    /// How many letters or digits make an answer worth keeping after the unanswered line ("x" or "네." don't).
    static let substance = 4

    /// A line's sentences, each with its own end mark.
    private static func sentences(_ line: String) -> [String] {
        var found: [String] = [], rest = Substring(line)
        while let end = rest.range(of: #"[.!?。]+["”’)]?\s+"#, options: .regularExpression) {
            found.append(String(rest[..<end.upperBound]).trimmingCharacters(in: .whitespaces))
            rest = rest[end.upperBound...]
        }
        if !rest.trimmingCharacters(in: .whitespaces).isEmpty { found.append(String(rest)) }
        return found
    }

    /// A sentence about the card itself: refused, denied, declined, cancelled, not approved or not answered.
    private static let unansweredWords = systemRefusal
        + #"|(?i)(\bdeclined?\b|\bcancell?ed\b|취소(되|됐|했)|(답|답변|응답|대답)이?\s*없|(확인|승인|허락|허용)(을|이)\s*(받지|없|나지|되지|안)|(확인|승인|허락)\s*없이|(승인|허락|허용)\s*(받지|되지|하지)\s*(않|못)"#
        + #"|no\s+(answer|response|reply|confirmation|approval)|(didn'?t|did not|never)\s+(answer|respond|reply|confirm|approve)"#
        + #"|(didn'?t|did not|never)\s+(get|receive|have)\s+(a |an |any |your |the )?(answer|response|reply|confirmation|approval|go-ahead)"#
        + #"|not\s+(confirmed|approved|answered)|without\s+(your\s+|a\s+|an\s+)?(confirmation|approval|answer)|timed\s*out|시간\s*(초과|이\s*지나))"#

    /// Said before what the turn did do, when its card got no answer.
    static func unansweredPartLine(korean: Bool) -> String {
        korean ? "확인이 없어서 그 부분은 하지 않았어요." : "There was no answer on the card, so I left that part undone."
    }

    /// What Aris says when a hands-free card was left unanswered.
    static func unansweredLine(korean: Bool) -> String {
        korean ? "답이 없어서 하지 않았어요." : "No answer, so I didn't do it."
    }
}
