//
//  ArisDesktopHonesty.swift
//  aris-agent
//
//  A reply about computer use is held to what really happened (moved out of ArisDesktopEngine.swift, unchanged): one
//  that names another window than the one acted in, claims an action none of which was done, or words a refusal as
//  The user's no, is replaced by a fixed true line. Honesty doesn't depend on the brain. Pure.
//

import CoreGraphics
import Foundation

/// What Aris says about where it typed comes from where it really did (QA BUG-47 reopened: the reply named "무제" for a
/// type into "무제 2"). The titles a reply mentions are found longest first, so "무제" inside "무제 2" isn't one; a reply
/// that names a window of the turn other than the one the action really happened in is replaced with the fixed line.
/// Honesty doesn't depend on the brain. Pure.
enum ArisWindowHonesty {
    static func mentioned(in text: String, titles: Set<String>) -> Set<String> {
        var rest = ArisWindowTitleMatch.normalized(text)
        var found: Set<String> = []
        for title in titles.sorted(by: { ArisWindowTitleMatch.normalized($0).count > ArisWindowTitleMatch.normalized($1).count }) {
            let key = ArisWindowTitleMatch.normalized(title)
            guard key.count >= 2, rest.contains(key) else { continue }
            found.insert(title)
            rest = rest.replacingOccurrences(of: key, with: "\u{1}")
        }
        return found
    }

    /// The fixed line for where it really happened.
    static func fixedLine(window: String, typed: Bool, korean: Bool) -> String {
        let shown = ArisWindowTitleMatch.safeTitle(window)
        if korean { return typed ? "‘\(shown)’ 창에 입력했어요." : "‘\(shown)’ 창에서 했어요." }
        return typed ? "Typed it into the window “\(shown)”." : "Done in the window “\(shown)”."
    }

    /// The reply, or the fixed line when it names another window of this turn than the one acted in.
    static func checked(_ answer: String, done: (window: String, typed: Bool)?, titles: Set<String>, korean: Bool) -> String {
        guard let done else { return answer }
        let named = mentioned(in: answer, titles: titles.union([done.window]))
        guard !named.isEmpty, !named.contains(done.window) else { return answer }
        return fixedLine(window: done.window, typed: done.typed, korean: korean)
    }
}

/// A reply that claims a desktop action worked when none of the turn's actions was done (QA BUG-33 reopened: "‘무제’
/// 창에 … 입력했어요" after a no) is replaced with the fixed true line. Pure.
enum ArisDesktopHonesty {
    /// The words are an action (it changes something), not a look.
    static func isAction(_ words: [String]) -> Bool {
        guard let verb = words.first else { return false }
        let two = words.prefix(2).joined(separator: " ")
        return ["click", "type", "set-value", "press", "scroll", "drag", "click-at", "batch"].contains(verb)
            || ["menu click", "dialog click", "dialog input", "dialog file"].contains(two)
            || (verb == "window" && words.count > 1 && words[1] != "list") || verb == "app"
    }

    /// A shell line that is only `aris-tools desktop …` (its wait too) or `aris-tools type <text>` (the desktop engine's
    /// `desktop type --focused`, ArisTypeRequest: tenth VM pass, a turn typed that way was never saved as steps), nothing
    /// else chained.
    static func isDesktopCommand(_ command: String, tools: String) -> Bool {
        guard let pieces = ArisCommandPolicy.segments(command), !pieces.isEmpty else { return false }
        return pieces.allSatisfy { piece in
            guard let words = ArisCommandPolicy.words(piece), words.count > 1 else { return false }
            guard words[0] == tools || (words[0] as NSString).lastPathComponent == "aris-tools" else { return false }
            return words[1] == "desktop" || (words[1] == "type" && words.count > 2)
        }
    }

    /// Words that say it was done (past, Korean or English), with no "not" in them.
    private static let claims = #"(?i)(입력했|눌렀|저장했|보냈|지웠|삭제했|바꿨|옮겼|열었|만들었|추가했|완료했|했어요|됐어요|\b(typed|pressed|clicked|saved|sent|deleted|done|entered)\b)"#
    private static let negation = #"(?i)(못|않|안 |없|실패|거부|취소|\b(not|didn'?t|couldn'?t|wasn'?t|unable|failed|no)\b)"#

    /// A reply worded as if the user declined ("알겠어요, 덧붙이지 않았어요") when no card of their was a no: the actions were
    /// refused by Aris's rules or failed (QA retest on 0c370061). The acknowledgement goes, and "didn't" becomes
    /// "couldn't"; only the user's own no gets the "알겠어요" lines.
    static func declineWorded(_ answer: String, done: Bool, notDone: Int, declined: Int, korean: Bool) -> String {
        guard !done, notDone > 0, declined == 0 else { return answer }
        let lead = #"^\s*(네[,.]?\s*)?(알겠어요|알겠습니다|알았어요|okay|ok|alright|got it|sure)\b[,.!]?\s*"#
        guard let range = answer.range(of: lead, options: [.regularExpression, .caseInsensitive]) else { return answer }
        var rest = String(answer[range.upperBound...])
        for (from, to) in [("지 않았어요", "지 못했어요"), ("지 않을게요", "지 못했어요"), ("안 했어요", "하지 못했어요"), ("I didn't", "I couldn't"), ("I won't", "I couldn't")] {
            rest = rest.replacingOccurrences(of: from, with: to)
        }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty else { return korean ? "창에서 하려던 일은 하지 못했어요." : "That couldn't be done in the app's window." }
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    static func checked(_ answer: String, done: Bool, notDone: Int, korean: Bool) -> String {
        guard !done, notDone > 0, answer.range(of: claims, options: .regularExpression) != nil,
              answer.range(of: negation, options: .regularExpression) == nil else { return answer }
        return korean ? "창에서 하려던 일은 되지 않았어요." : "That wasn't done in the app's window."
    }
}
