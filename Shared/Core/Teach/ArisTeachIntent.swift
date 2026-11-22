//
//  ArisTeachIntent.swift
//  Shared/Core/Teach (aris-agent, tests, swift test)
//
//  The owner's words about taught procedures (ARCHITECTURE Part 3, F3): starting a demonstration and naming it
//  ("지금부터 하는 거 출근 준비라고 해", "watch me, call it morning setup"), ending it ("다 했어", "done") or dropping
//  it ("배우기 취소"), what was taught ("배운 거 보여 줘"), one of them ("출근 준비 어떻게 해"), renaming and deleting
//  one, and doing one by its name ("출근 준비 해 줘, 제목은 월간 보고"). The stop words are never the wake-level ones
//  the app takes by itself (그만, 멈춰, 취소 alone). A name that matches no stored procedure is no command of this
//  file: those words go on as an ordinary request. Pure.
//

import Foundation

enum ArisTeachIntent: Equatable, Sendable {
    case start(name: String)
    /// "내가 하는 거 보고 배워" with no name.
    case startUnnamed
    case stop
    case cancel
    case list
    case show(ArisTeachProcedure)
    case rename(ArisTeachProcedure, to: String)
    case delete(ArisTeachProcedure)
    /// Do it; `rest`: the words after its name (the run's values).
    case run(ArisTeachProcedure, rest: String)

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func capture(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for group in stride(from: match.numberOfRanges - 1, through: 1, by: -1) {
            if let range = Range(match.range(at: group), in: text), !text[range].isEmpty { return String(text[range]) }
        }
        return nil
    }

    static func normalised(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: ".!?~。")))
    }

    // MARK: - Words

    static let stopPattern = #"^(?:(?:이제|자|됐어|오케이|ok|okay)[,\s]*)?(?:다\s*했어(?:요)?|다\s*했다|다\s*됐어(?:요)?|끝났어(?:요)?|끝(?:이야|이에요)?|여기까지(?:야|예요|요)?|이게\s*다야|이게\s*다예요|다\s*보여\s*줬어(?:요)?|(?:배우기|가르치기|녹화|보여\s*주기)\s*끝(?:내|내\s*줘|났어)?|done|i'?m\s+done|that'?s\s+it|that'?s\s+all|finished|all\s+done|stop\s+(?:watching|recording|the\s+lesson))[\s.!~]*$"#
    static let cancelPattern = #"^(?:(?:배우기|가르치기|녹화|보는\s*거|보기)\s*(?:취소|그만(?:해)?|안\s*할래|하지\s*마)|(?:방금\s*)?(?:배운\s*거|보여\s*준\s*거)\s*(?:취소|버려|저장하지\s*마)|cancel\s+(?:the\s+)?(?:lesson|teaching|recording|demonstration)|never\s*mind\s+(?:the\s+)?(?:lesson|recording)|forget\s+(?:this|it),?\s+don'?t\s+save)(?:\s*해\s*줘|\s*해)?[\s.!~]*$"#
    static let listPattern = #"(?:(?:배운|가르친|가르쳐\s*준|알려\s*준|보여\s*준)\s*(?:거|것|게|순서|일|동작)(?:들)?\s*(?:뭐|뭐뭐|목록|보여|알려|있어|말해))|(?:what\s+(?:have\s+you|did\s+you|you've)\s+learn(?:ed|t)?)|(?:what\s+i\s+(?:taught|showed)\s+you)|(?:list\s+(?:what\s+i\s+(?:taught|showed)|(?:the\s+)?(?:things\s+)?(?:you\s+)?learn(?:ed|t)))"#

    /// The words that begin a demonstration, without a name.
    static let watchPattern = #"(?:(?:지금부터|이제부터|이제|자)\s*)?(?:내가\s*)?(?:하는\s*(?:거|걸|것)|할\s*(?:거|걸))\s*(?:잘\s*)?(?:보고\s*)?(?:배워|기억해|봐\s*줘|봐|봐봐)|(?:보고\s*배워)|(?:^|\s)(?:watch\s+(?:me|what\s+i\s+do|how\s+i)|learn\s+(?:this|what\s+i\s+do))"#

    static let questionWords: Set<String> = ["뭐", "무엇", "뭔데", "뭘", "어떤", "왜", "언제", "어디", "누구", "what", "why", "when", "where", "who"]

    /// The name of a demonstration being started, from the words; nil when they don't start one.
    static func startName(_ text: String) -> String?? {
        // Korean: "지금부터 하는 거 출근 준비라고 해", "지금부터 내가 하는 건 ‘출근 준비’야", "이름은 출근 준비야".
        let korean: [String] = [
            #"(?:지금부터|이제부터|이제|자)\s*(?:내가\s*)?(?:하는|할)\s*(?:거|걸|것|건|게)(?:는|은)?\s*(.+?)(?:이)?라고\s*(?:해|해\s*줘|불러|불러\s*줘|하자|할게|기억해|기억해\s*줘|배워|배워\s*줘|저장해|이름\s*붙여)(?:요)?$"#,
            #"(?:지금부터|이제부터|이제|자)\s*(?:내가\s*)?(?:하는|할)\s*(?:거는|건|것은|게|걸)\s*(.+?)(?:이야|야|이에요|예요|입니다)$"#,
            #"(?:하는|할)\s*(?:거|걸)\s*(?:잘\s*)?(?:보고\s*)?(?:배워|기억해)(?:\s*줘)?[,.\s]+(?:이름은|이름을)\s*(.+?)(?:\s*(?:으로|로)\s*(?:해|해\s*줘|하자))?(?:이야|야|이에요|예요|입니다)?$"#,
            #"^(.+?)\s*(?:하는\s*(?:법|방법)|하는\s*거)\s*(?:보여\s*줄게|알려\s*줄게|가르쳐\s*줄게|보여\s*줄\s*테니\s*(?:배워|봐|기억해)(?:\s*줘)?)(?:요)?$"#,
            #"^(.+?)\s*(?:가르쳐\s*줄게|알려\s*줄게|보여\s*줄게)(?:요)?$"#,
        ]
        let english: [String] = [
            #"(?:watch\s+(?:me|what\s+i\s+do)|learn\s+(?:this|what\s+i\s+do)|from\s+now(?:\s+on)?,?\s+what\s+i\s+do)(?:\s+and)?[,\s]+(?:(?:is\s+)?called|call\s+it|name\s+it|as)\s+(.+)$"#,
            #"(?:i'?ll|let\s+me)\s+(?:show|teach)\s+you\s+(?:how\s+(?:i|to)\s+)?(.+)$"#,
            #"^(?:learn|remember)\s+(.+?)\s+from\s+me$"#,
        ]
        for pattern in korean + english {
            if let name = capture(text, pattern) {
                let bare = name.replacingOccurrences(of: #"^(?:이름은|이름을|이걸|이거)\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"\s*(?:하는\s*)?(?:법|방법)$"#, with: "", options: .regularExpression)
                let cleaned = ArisTeachNames.clean(bare)
                // A question ("지금부터 하는 건 뭐야") names nothing.
                if questionWords.contains(ArisTeachNames.key(cleaned)) { return nil }
                return ArisTeachNames.key(cleaned).isEmpty ? .some(nil) : .some(cleaned)
            }
        }
        // The quoted name of a sentence that starts one ("‘출근 준비’ 보고 배워").
        if matches(text, watchPattern) {
            if let quoted = capture(text, #"[‘'“"「『]([^’'”"」』]{1,30})[’'”"」』]"#) { return .some(ArisTeachNames.clean(quoted)) }
            return .some(nil)
        }
        return nil
    }

    // MARK: - Parsing

    /// What the owner's words mean here; nil when they are no command about taught procedures. `recording`: a
    /// demonstration is under way (then only stopping, cancelling and starting again are read).
    /// Whether the words start a lesson, named or not (as `parse` reads them, with nothing stored): the app's local
    /// actions never take such words (thirteenth VM run, item 6).
    static func startsLesson(_ raw: String) -> Bool {
        switch parse(raw, procedures: [], recording: false) {
        case .start?, .startUnnamed?: return true
        default: return false
        }
    }

    static func parse(_ raw: String, procedures: [ArisTeachProcedure], recording: Bool) -> ArisTeachIntent? {
        let text = normalised(raw)
        guard !text.isEmpty else { return nil }
        if recording {
            if matches(text, stopPattern) { return .stop }
            if matches(text, cancelPattern) { return .cancel }
        } else if matches(text, stopPattern) || matches(text, cancelPattern) {
            // "다 했어" with nothing watched is some other request (a to-do ticked off, an answer to the AI).
            return nil
        }
        // A routine's words are the routine's.
        if text.contains("루틴") || matches(text, #"\broutines?\b"#) { return nil }
        if let start = startName(text) {
            if let name = start { return .start(name: name) }
            return .startUnnamed
        }
        if matches(text, listPattern) { return .list }
        guard !procedures.isEmpty else { return nil }
        if let rename = renaming(text, procedures: procedures) { return rename }
        if let delete = deleting(text, procedures: procedures) { return delete }
        if let (procedure, rest) = ArisTeachNames.leading(text, in: procedures) {
            let after = rest.trimmingCharacters(in: .whitespaces)
            if matches(after, #"^(?:은|는|을|를)?\s*(?:어떻게\s*(?:해|하는\s*거야|하더라)|순서\s*(?:보여|알려)|단계\s*(?:보여|알려)|뭐\s*하는\s*거(?:야)?)"#) {
                return .show(procedure)
            }
            if ArisTeachMatch.onlyAsks(after) { return .run(procedure, rest: "") }
            // The name, a comma or a colon, then its value ("줄 추가, 우유"): a run, with no asking words (tenth VM run, item 1).
            if namedValue(after, raw: raw, of: procedure) { return .run(procedure, rest: after) }
            // Words beside the name: a run only when they fill its values and the sentence asks for it to be done.
            guard ArisTeachMatch.asks(after), !procedure.parameters.isEmpty, !ArisTeachMatch.values(procedure, words: after).isEmpty else { return nil }
            return .run(procedure, rest: after)
        }
        // English: "do morning setup", "run morning setup with subject monthly report".
        if let named = capture(text, #"^(?:please\s+)?(?:do|run|start)\s+(?:the\s+)?(.+)$"#), let (procedure, rest) = ArisTeachNames.leading(named, in: procedures) {
            let after = rest.trimmingCharacters(in: .whitespaces)
            if after.isEmpty || ArisTeachMatch.onlyAsks(after) { return .run(procedure, rest: "") }
            let values = after.replacingOccurrences(of: #"^(?:with|,)\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            guard !procedure.parameters.isEmpty, !ArisTeachMatch.values(procedure, words: values).isEmpty else { return nil }
            return .run(procedure, rest: values)
        }
        return nil
    }

    /// Whether the words after a lesson's name are a separator and then a value for it: never a question about it, and
    /// never for a lesson that takes no value.
    static func namedValue(_ after: String, raw: String, of procedure: ArisTeachProcedure) -> Bool {
        guard let first = after.first, ",，:".contains(first), !procedure.parameters.isEmpty else { return false }
        let value = ArisTeachMatch.rest(after)
        guard !value.isEmpty, !raw.trimmingCharacters(in: .whitespaces).hasSuffix("?"),
              !matches(value, #"(?:^|\s)(?:뭐|뭔|무엇|무슨|어떻게|어떤|왜|언제|어디|누구|what|how|why|when|where|who)"#) else { return false }
        return !ArisTeachMatch.values(procedure, words: after).isEmpty
    }

    private static func renaming(_ text: String, procedures: [ArisTeachProcedure]) -> ArisTeachIntent? {
        let patterns = [#"^(.+?)\s*(?:의\s*)?이름(?:을|은)?\s*(.+?)(?:으로|로)\s*(?:바꿔|바꿔\s*줘|바꾸자|변경해|변경해\s*줘)(?:요)?$"#,
                        #"^(?:rename|call)\s+(.+?)\s+(?:to|as)\s+(.+)$"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let old = Range(match.range(at: 1), in: text), let new = Range(match.range(at: 2), in: text) else { continue }
            let oldName = String(text[old]).replacingOccurrences(of: #"^(?:배운\s*거|가르친\s*거)\s*"#, with: "", options: .regularExpression)
            guard let procedure = ArisTeachNames.find(ArisTeachNames.clean(oldName), in: procedures) else { continue }
            let name = ArisTeachNames.clean(String(text[new]))
            guard !ArisTeachNames.key(name).isEmpty else { continue }
            return .rename(procedure, to: name)
        }
        return nil
    }

    private static func deleting(_ text: String, procedures: [ArisTeachProcedure]) -> ArisTeachIntent? {
        let patterns = [#"^(?:배운\s*거\s*|가르친\s*거\s*)?(.+?)(?:을|를)?\s*(?:지워|지워\s*줘|삭제해|삭제해\s*줘|잊어|잊어\s*줘|잊어버려|없애|없애\s*줘)(?:요)?$"#,
                        #"^(?:delete|forget|remove)\s+(?:the\s+)?(.+?)(?:\s+(?:lesson|procedure))?$"#]
        for pattern in patterns {
            if let name = capture(text, pattern), let procedure = ArisTeachNames.find(ArisTeachNames.clean(name), in: procedures) {
                return .delete(procedure)
            }
        }
        return nil
    }
}
