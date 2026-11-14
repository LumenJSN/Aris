//
//  ArisMemoryIntent.swift
//  aris-agent
//
//  What the user says to their memory, answered by the agent itself from the store (no brain, the user's words as said):
//    "커피는 아이스 아메리카노라는 거 기억해", "remember that I'm vegetarian"   -> remember
//    "커피 얘기 잊어", "forget about the gym"                                  -> forget
//    "내가 엄마 생일 뭐라고 했지?", "what did I tell you about my mom"         -> recall (no topic: the latest)
//    "나에 대해 뭐 알아?", "what do you know about me"                         -> profile
//    "어제 뭐 했지?", "what did I do yesterday"                                -> day summary
//  "이거/that 기억해" points at something else and is left to the brain; "다 잊어" is the settings' job.
//  Foundation only (tested).
//

import Foundation

enum ArisMemoryIntent: Equatable {
    case remember(String)
    case forget(String)
    case forgetAll
    /// What the user said about a topic, or (nil) the latest things they said.
    case recall(String?)
    case profile
    /// 0 today, -1 yesterday, -2 the day before.
    case day(Int)
    /// The user's yes (or no) to forgetting the several memories their last "잊어" matched (ArisMemoryCurator holds them).
    case confirmForget(Bool)

    /// What the audit line calls it (never the user's words).
    var auditName: String {
        switch self {
        case .remember: "remember"
        case .forget: "forget"
        case .forgetAll: "forget all (sent to settings)"
        case .recall: "recall"
        case .profile: "profile"
        case .day: "day"
        case .confirmForget(let yes): yes ? "forget (confirmed)" : "forget (kept)"
        }
    }

    /// Whether it changes the store (only a clean turn may).
    var writes: Bool {
        switch self {
        case .remember, .forget, .forgetAll, .confirmForget: return true
        case .recall, .profile, .day: return false
        }
    }

    private static let deictic: Set<String> = ["이거", "그거", "저거", "이것", "그것", "저것", "이걸", "그걸", "저걸", "이건", "그건", "얘", "걔",
                                              "this", "that", "it", "these", "those"]

    private static let yesWords: Set<String> = ["응", "어", "네", "예", "그래", "그래요", "좋아", "맞아", "다 잊어", "다 지워", "지워", "잊어", "yes", "yeah", "yep", "sure",
                                                "ok", "okay", "do it", "forget them"]
    private static let noWords: Set<String> = ["아니", "아니야", "아니요", "됐어", "취소", "놔둬", "그냥 둬", "남겨 둬", "남겨둬", "no", "nope", "cancel", "keep them",
                                               "never mind"]

    /// A plain yes or no ("응", "아니", "yes"), for a question Aris asked; nil for anything else.
    static func yesOrNo(_ said: String) -> Bool? {
        let text = said.trimmingCharacters(in: CharacterSet(charactersIn: ".!?。~ ")).lowercased()
            .replacingOccurrences(of: "줘", with: "").trimmingCharacters(in: .whitespaces)
        if yesWords.contains(text) { return true }
        if noWords.contains(text) { return false }
        return nil
    }

    static func parse(_ said: String) -> ArisMemoryIntent? {
        let raw = ArisMemoryText.ownWords(said).trimmingCharacters(in: .whitespacesAndNewlines)
        let question = raw.hasSuffix("?")
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".!?。~ ")).precomposedStringWithCanonicalMapping
        guard !text.isEmpty, text.count <= 300 else { return nil }
        let lowered = text.lowercased()
        if let intent = korean(text, question: question) ?? english(lowered, original: text, question: question) { return intent }
        return nil
    }

    // MARK: Korean verbs

    /// A quoted verb ("좋아한다", "먹는다", "좋다", "했다", "좋아하냐", "가자") in the plain 해-form the other memories use
    /// ("좋아해", "먹어", "좋아", "했어"); anything else as it is.
    static func declarative(_ verb: String) -> String {
        var stem: String
        if verb.hasSuffix("는다") {
            stem = String(verb.dropLast(2))
        } else if verb.hasSuffix("다") {
            stem = String(verb.dropLast())
            // Present ㄴ다 after an open syllable: 간다 → 가, 좋아한다 → 좋아하.
            if let last = stem.last.flatMap(Hangul.init), last.tail == Hangul.nieun { stem = String(stem.dropLast()) + last.with(tail: 0).text }
        } else if verb.hasSuffix("냐") {
            stem = String(verb.dropLast())
            if stem.hasSuffix("느") || (stem.hasSuffix("으") && stem.count >= 2) { stem = String(stem.dropLast()) }
        } else if verb.hasSuffix("자") {
            stem = String(verb.dropLast())
        } else {
            return verb
        }
        return conjugated(stem) ?? verb
    }

    /// A verb or adjective stem in the 해-form: 하 → 해, 먹 → 먹어, 보 → 봐, 마시 → 마셔, 모르 → 몰라, 예쁘 → 예뻐, 귀엽 → 귀여워.
    private static func conjugated(_ stem: String) -> String? {
        guard let character = stem.last, let last = Hangul(character) else { return nil }
        let head = String(stem.dropLast())
        let previous = head.last.flatMap(Hangul.init)
        let bright = { (syllable: Hangul?) in syllable.map { [Hangul.a, Hangul.o, Hangul.ya].contains($0.vowel) } ?? false }
        if character == "하" { return head + "해" }
        switch last.tail {
        case Hangul.ssangSiot:
            return stem + "어"
        case Hangul.bieup where !regularBieup.contains(character):
            return head + last.with(tail: 0).text + (last.vowel == Hangul.o ? "와" : "워")
        case Hangul.digeut where irregularDigeut.contains(character):
            return head + last.with(tail: Hangul.rieul).text + "어"
        case 0:
            break
        default:
            return stem + (bright(last) ? "아" : "어")
        }
        switch last.vowel {
        case Hangul.o: return head + last.with(vowel: Hangul.wa).text
        case Hangul.u: return head + last.with(vowel: Hangul.wo).text
        case Hangul.i: return head + last.with(vowel: Hangul.yeo).text
        case Hangul.oe: return head + last.with(vowel: Hangul.wae).text
        case Hangul.eu:
            if last.lead == Hangul.rieulLead, let previous {
                return String(head.dropLast()) + previous.with(tail: Hangul.rieul).text + (bright(previous) ? "라" : "러")
            }
            return head + last.with(vowel: bright(previous) ? Hangul.a : Hangul.eo).text
        default:
            return stem
        }
    }

    /// ㅂ stems that stay regular (잡아, 입어); the rest go 워/와 (귀여워, 도와).
    private static let regularBieup: Set<Character> = ["잡", "입", "뽑", "씹", "접", "업", "좁", "집", "굽"]
    /// ㄷ stems that turn ㄹ (들어, 걸어); the rest stay (받아, 믿어).
    private static let irregularDigeut: Set<Character> = ["듣", "걷", "묻", "싣"]

    /// One precomposed Hangul syllable, in its parts.
    private struct Hangul {
        static let a = 0, ya = 2, eo = 4, yeo = 6, o = 8, wa = 9, wae = 10, oe = 11, u = 13, wo = 14, eu = 18, i = 20
        static let nieun = 4, digeut = 7, rieul = 8, bieup = 17, ssangSiot = 20, rieulLead = 5
        let lead: Int, vowel: Int, tail: Int

        init?(_ character: Character) {
            guard character.unicodeScalars.count == 1, let value = character.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(value) else { return nil }
            let index = Int(value) - 0xAC00
            (lead, vowel, tail) = (index / 588, (index % 588) / 28, index % 28)
        }

        private init(lead: Int, vowel: Int, tail: Int) { (self.lead, self.vowel, self.tail) = (lead, vowel, tail) }

        func with(tail: Int) -> Hangul { Hangul(lead: lead, vowel: vowel, tail: tail) }
        func with(vowel: Int) -> Hangul { Hangul(lead: lead, vowel: vowel, tail: tail) }
        var text: String { String(Character(Unicode.Scalar(UInt32(0xAC00 + lead * 588 + vowel * 28 + tail))!)) }
    }


    // MARK: Korean

    private static let rememberEnds = ["기억해 주세요", "기억해주세요", "기억해 줘", "기억해줘", "기억해 둬", "기억해둬", "기억해 놔", "기억해놔", "기억해 두렴",
                                       "기억하고 있어", "기억해", "잊지 마", "잊지마"]
    private static let forgetEnds = ["기억에서 지워 줘", "기억에서 지워줘", "기억에서 지워", "기억 지워 줘", "기억 지워줘", "기억 지워", "잊어 주세요", "잊어주세요",
                                     "잊어 줘", "잊어줘", "잊어 버려", "잊어버려", "잊어도 돼", "잊어"]

    private static func korean(_ text: String, question: Bool) -> ArisMemoryIntent? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact.contains("나에대해") && (compact.contains("알아") || compact.contains("아는") || compact.contains("기억")) { return .profile }
        if ["뭘기억하고", "뭐기억하고", "기억하는거뭐", "기억하는게뭐", "뭐뭐기억", "기억하는거보여", "기억하는거다말해"].contains(where: compact.contains) { return .profile }
        if let offset = dayOffset(compact), !["했으면", "할까", "하지?"].contains(where: compact.contains), ["뭐했", "뭘했", "무슨일했", "한일", "뭐하고지냈", "뭐했더라"].contains(where: compact.contains) { return .day(offset) }
        if let topic = recallTopic(text) { return .recall(topic.isEmpty ? nil : topic) }
        // "내 생일 기억해?" asks, it doesn't tell.
        if question {
            if let end = rememberEnds.first(where: text.hasSuffix) {
                let topic = span(String(text.dropLast(end.count)))
                return .recall(topic.isEmpty ? nil : topic)
            }
            return nil
        }
        if let end = forgetEnds.first(where: text.hasSuffix) {
            let words = span(String(text.dropLast(end.count)))
            if ["다", "전부", "모두", "싹", "다 전부", "전부 다", "모든 걸", "모든 거", "모든걸", "모든거"].contains(words) { return .forgetAll }
            return isUsable(words) ? .forget(stripTopic(words)) : nil
        }
        if let end = rememberEnds.first(where: text.hasSuffix) {
            let fact = span(String(text.dropLast(end.count)))
            return isUsable(fact) ? .remember(aboutUser(fact)) : nil
        }
        // "기억해: …", "기억해, …", "기억해. …", "기억해 둬, …", "기억해 주세요, …" (longest first).
        let leads = ["기억해 주세요", "기억해주세요", "기억해 줘요", "기억해줘요", "기억해 둬", "기억해둬", "기억해 줘", "기억해줘", "기억해요", "기억해"]
        if let lead = leads.first(where: text.hasPrefix) {
            let rest = String(text.dropFirst(lead.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :,-—.~!"))
            let fact = span(rest)
            if isUsable(fact) { return .remember(aboutUser(fact)) }
        }
        return nil
    }

    private static func dayOffset(_ compact: String) -> Int? {
        if compact.contains("그저께") || compact.contains("그제") { return -2 }
        if compact.contains("어제") { return -1 }
        if compact.contains("오늘") { return 0 }
        return nil
    }

    /// "내가 (엄마 생일) 뭐라고 했지", "(엄마)에 대해 내가 뭐라고 했더라", "내가 뭐라고 했지" → "" (no topic).
    private static func recallTopic(_ text: String) -> String? {
        for marker in ["뭐라고 했", "뭐라고 말했", "뭐라 했", "뭐라고 그랬", "어떻다고 했", "뭐랬"] {
            guard let range = text.range(of: marker) else { continue }
            var topic = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            for lead in ["내가 ", "제가 ", "나 ", "내가", "제가"] where topic.hasPrefix(lead) { topic = String(topic.dropFirst(lead.count)) }
            for tail in ["에 대해서 내가", "에 대해 내가", "에 대해서", "에 대해", "관해서", "얘기", "에 관해", "은", "는", "이", "가", "을", "를", " 내가", " 제가"]
                where topic.hasSuffix(tail) && topic.count > tail.count { topic = String(topic.dropLast(tail.count)) }
            return topic.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The words before the verb, without the quoting tail ("…라는 거", "…라고") and polite fillers.
    /// "앞으로" stays: it is part of what the user wants kept ("앞으로 나를 솔이라고 불러", ninth VM pass).
    private static let spanLeads = ["좀 ", "꼭 ", "Aris ", "아리스 ", "아리스야 "]
    /// The quoting tail, longest first; only one goes. A bare 거/것 only after a space ("자전거" keeps its 거).
    private static let quoteTails = ["이라는 것", "이라는 거", "라는 것", "라는 거", "다는 것", "다는 거", "는 것", "는 거", "인 것", "인 거", "이라고", "라고", "다고", " 것", " 거"]
    private static let fillerTails = [" 꼭", " 좀", " 제발"]

    private static func span(_ text: String) -> String {
        var words = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        var changed = true
        while changed {
            changed = false
            for lead in spanLeads where words.hasPrefix(lead) {
                words = String(words.dropFirst(lead.count))
                changed = true
            }
            for tail in fillerTails where words.hasSuffix(tail) && words.count > tail.count {
                words = String(words.dropLast(tail.count))
                changed = true
            }
        }
        if let quoted = quotedVerb(words) { return quoted }
        if let tail = quoteTails.first(where: { words.hasSuffix($0) && words.count > $0.count }) { words = String(words.dropLast(tail.count)) }
        return words.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
    }

    /// The words with a quoted verb at their end made plain (QA BUG-4): "망고 좋아한다고" / "망고 좋아한다는 거" /
    /// "망고 좋아하는 거" → "망고 좋아해"; nil when they don't end in one (a noun's 라고 / 라는 거 goes as before).
    private static func quotedVerb(_ words: String) -> String? {
        var body = words
        var attributive = false
        if let tail = [" 것", " 거"].first(where: body.hasSuffix) {
            body = String(body.dropLast(tail.count))
            guard body.hasSuffix("는"), !body.hasSuffix("라는"), !body.hasSuffix(" 는") else { return nil }
            body = String(body.dropLast())
            // "좋아한다는 거" quotes 좋아한다; "좋아하는 거" is the verb's own stem.
            if !body.hasSuffix("다") { attributive = true }
        } else if ["다고", "냐고", "자고"].contains(where: body.hasSuffix) {
            body = String(body.dropLast())
        } else {
            return nil
        }
        let start = body.lastIndex(of: " ").map { body.index(after: $0) } ?? body.startIndex
        let verb = String(body[start...]), front = String(body[..<start])
        guard verb.count >= 2 || attributive, let made = attributive ? conjugated(verb) : Optional(declarative(verb)), made != verb else { return nil }
        return (front + made).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
    }

    /// "내가 …", "나는 …": a memory is about the user anyway (QA BUG-4).
    private static let selfLeads = ["내가 ", "나는 ", "난 ", "제가 ", "저는 "]

    private static func aboutUser(_ fact: String) -> String {
        guard let lead = selfLeads.first(where: fact.hasPrefix) else { return fact }
        let rest = String(fact.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        return isUsable(rest) ? rest : fact
    }

    /// "커피 얘기" → "커피"; "엄마에 대한 거" → "엄마".
    /// The topic without the words around it: "좋아하는 과일에 대한 기억 전부" → "좋아하는 과일", "everything about mango" →
    /// "mango" (QA BUG-59: the wrapper was matched literally, so nothing was found). Each wrapper as long as one is left.
    static func stripTopic(_ words: String) -> String {
        var topic = words.trimmingCharacters(in: .whitespaces)
        let tails = ["에 대한 기억", "에 대한 것", "에 대한 거", "에 대해서", "에 대해", "관련된 거", "관련된 것", "관련", "얘기", "이야기", "기억",
                     " 전부 다", " 전부", " 모두", " 싹 다", " 싹", " 다", "은", "는", "을", "를"]
        let leads = ["everything about", "anything about", "all about", "about", "전부", "모두"]
        var changed = true
        while changed {
            changed = false
            for tail in tails where topic.hasSuffix(tail) && topic.count > tail.count {
                topic = String(topic.dropLast(tail.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
            for lead in leads where topic.lowercased().hasPrefix(lead + " ") {
                topic = String(topic.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
                changed = true
                break
            }
        }
        return topic
    }

    /// Words that point at something on screen or elsewhere ("이 페이지에 …", "this email …"): not the user's own fact.
    private static let pointingLeads: Set<String> = ["이", "그", "저", "여기", "거기", "저기", "여기에", "거기에", "이건", "그건", "this", "that", "these", "those",
                                                    "here", "there", "it"]

    private static func isUsable(_ words: String) -> Bool {
        let cleaned = words.trimmingCharacters(in: .whitespaces)
        guard ArisMemoryText.normalized(cleaned).count >= 2 else { return false }
        let lowered = cleaned.lowercased()
        if deictic.contains(lowered) || deictic.contains(where: { lowered == $0 + " 좀" }) { return false }
        let tokens = lowered.split(separator: " ").map(String.init)
        // "이 페이지에 …", "그 메일 …", "this page says …", or a 이거/that anywhere in it.
        if let first = tokens.first, pointingLeads.contains(first) || deictic.contains(first) { return false }
        return !tokens.contains(where: deictic.contains)
    }

    // MARK: English

    /// Without "please", "for me", "okay" around it.
    private static func englishSpan(_ text: String) -> String {
        var words = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        for tail in [", please", " please", " for me", ", okay", " okay", ", ok"] where words.lowercased().hasSuffix(tail) && words.count > tail.count {
            words = String(words.dropLast(tail.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,:"))
        }
        return words
    }

    private static func english(_ lowered: String, original: String, question: Bool) -> ArisMemoryIntent? {
        // "do you remember …?", "remember my birthday?": a question about memory.
        for lead in ["do you remember ", "do you know ", "remember "] where question && lowered.hasPrefix(lead) {
            let topic = englishSpan(String(original.dropFirst(lead.count)))
            return .recall(topic.isEmpty ? nil : topic)
        }
        if ["what do you know about me", "what do you remember about me", "what have you remembered", "what do you remember"].contains(where: lowered.hasPrefix) {
            return .profile
        }
        for (phrase, offset) in [("what did i do yesterday", -1), ("what did i do today", 0), ("what did i work on yesterday", -1), ("what did i work on today", 0)]
            where lowered.hasPrefix(phrase) { return .day(offset) }
        for lead in ["what did i tell you about ", "what did i say about ", "what did i say regarding "] where lowered.hasPrefix(lead) {
            let topic = String(original.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
            return .recall(topic.isEmpty ? nil : topic)
        }
        if ["what did i tell you", "what did i say"].contains(where: { lowered == $0 }) { return .recall(nil) }
        if ["forget everything", "forget all of it", "forget all"].contains(lowered) { return .forgetAll }
        for lead in ["forget about ", "forget that ", "forget "] where lowered.hasPrefix(lead) {
            let words = stripTopic(englishSpan(String(original.dropFirst(lead.count))))
            return isUsable(words) ? .forget(words) : nil
        }
        for lead in ["please remember that ", "please remember ", "remember that ", "remember: ", "remember ", "don't forget that ", "don't forget "]
            where lowered.hasPrefix(lead) {
            let fact = englishSpan(String(original.dropFirst(lead.count)))
            // "remember to …" is a reminder, not a memory.
            guard !fact.lowercased().hasPrefix("to "), isUsable(fact) else { return nil }
            return .remember(fact)
        }
        return nil
    }
}

/// What Aris says back, from the store's records. Korean unless the user spoke English.
enum ArisMemoryAnswer {
    static func remembered(_ outcome: ArisMemoryStore.Outcome, korean: Bool) -> String {
        switch outcome {
        case .added(let r): return korean ? "기억할게요: \(r.text)" : "Got it, I'll remember: \(r.text)"
        case .updated(let r, _): return korean ? "바꿔서 기억할게요: \(r.text)" : "Updated: \(r.text)"
        case .duplicate(let r): return korean ? "이미 기억하고 있어요: \(r.text)" : "I already remember that: \(r.text)"
        // Why, and where it belongs instead (the same line the learning pass and the tool give).
        case .secret: return ArisMemoryStore.secretLine(korean: korean)
        case .empty: return korean ? "뭘 기억할지 못 알아들었어요." : "I didn't catch what to remember."
        case .failed: return korean ? "기억을 저장하지 못했어요." : "I couldn't save that."
        // Never for his own 기억해 (the gate reads only what others wrote), but every outcome has its words.
        case .held: return korean ? "AI에게 내리는 지시처럼 보여서, 설정 › 기억에서 확인한 다음에 넣을게요." : "That reads like an instruction to an AI, so it waits in Settings › Memory for you to check."
        case .refused: return korean ? "비밀번호나 키를 넘기라는 말이라 기억하지 않았어요." : "That asks for a password or key to be handed over, so I didn't keep it."
        }
    }

    static func forgot(_ gone: [ArisMemoryRecord], words: String, korean: Bool) -> String {
        guard !gone.isEmpty else {
            if words.isEmpty { return korean ? "잊을 게 없어요." : "Nothing to forget." }
            return korean ? "‘\(words)’에 대해 기억하는 건 없어요." : "I don't remember anything about \(words)."
        }
        let list = gone.prefix(3).map(\.text).joined(separator: "; ") + (gone.count > 3 ? (korean ? " 외 \(gone.count - 3)개" : " and \(gone.count - 3) more") : "")
        return korean ? "잊었어요: \(list)" : "Forgotten: \(list)"
    }

    /// Several matched: which ones, and whether all of them go.
    static func askForget(_ found: [ArisMemoryRecord], words: String, korean: Bool) -> String {
        let list = found.prefix(4).map(\.text).joined(separator: "; ") + (found.count > 4 ? (korean ? " 외 \(found.count - 4)개" : " and \(found.count - 4) more") : "")
        return korean ? "‘\(words)’ 기억이 \(found.count)개예요: \(list). 다 잊을까요?" : "\(found.count) memories mention \(words): \(list). Forget them all?"
    }

    /// The card for a forget that asks first (several memories, or one found only loosely): every memory that would go,
    /// one a line, so the user's yes is for exactly those (QA BUG-59).
    static func forgetCard(_ found: [ArisMemoryRecord], words: String, korean: Bool) -> ArisMCPCard {
        let lines = found.prefix(forgetCardLines).map { "· " + $0.line }
        let more = found.count > forgetCardLines ? [korean ? "· 외 \(found.count - forgetCardLines)개" : "· and \(found.count - forgetCardLines) more"] : []
        let head = korean ? "‘\(words)’ 기억 \(found.count)개를 잊을까요?" : "Forget these \(found.count) memories about \(words)?"
        let all = found.map { "· " + $0.line }
        return ArisMCPCard(title: korean ? "기억 지우기" : "Forget memories", detail: ([head] + lines + more).joined(separator: "\n"),
                           full: more.isEmpty ? nil : ([head] + all).joined(separator: "\n"), fields: [], allow: korean ? "잊기" : "Forget")
    }

    static let forgetCardLines = 6

    /// What Aris says after the card: left as they were on a no, or when nobody answered.
    static func kept(unanswered: Bool, korean: Bool) -> String {
        if unanswered { return korean ? "답이 없어서 그대로 뒀어요." : "No answer, so I left them as they were." }
        return korean ? "그대로 둘게요." : "Okay, I'll keep them."
    }

    static func forgetAll(korean: Bool) -> String {
        korean ? "전부 지우는 건 설정 › 기억에서 할 수 있어요." : "To forget everything, use Settings › 기억."
    }

    /// "‘엄마’에 대해선 이렇게 기억해요: …"; nil when nothing matches (the brain answers from the conversation).
    static func recall(_ found: [ArisMemoryRecord], topic: String?, korean: Bool) -> String? {
        guard !found.isEmpty else { return nil }
        let list = found.prefix(4).map(\.line).joined(separator: "; ")
        guard let topic else { return korean ? "최근에 말해 준 건 이거예요: \(list)" : "Lately you told me: \(list)" }
        return korean ? "‘\(topic)’에 대해선 이렇게 기억해요: \(list)" : "About \(topic), I remember: \(list)"
    }

    /// Up to eight memories, kind by kind, surest first.
    static func profile(_ records: [ArisMemoryRecord], korean: Bool) -> String {
        guard !records.isEmpty else {
            return korean ? "아직 기억하는 게 없어요. “…기억해”라고 말해 주면 기억할게요." : "I don't remember anything yet. Say “remember …” and I will."
        }
        var lines: [String] = []
        var shown = 0
        for kind in ArisMemoryKind.allCases {
            let ofKind = records.filter { $0.kind == kind }.sorted { $0.confidence > $1.confidence }.prefix(max(0, 8 - shown))
            guard !ofKind.isEmpty else { continue }
            shown += ofKind.count
            lines.append("\(korean ? kind.korean : kind.rawValue): " + ofKind.map(\.line).joined(separator: "; "))
        }
        let head = korean ? "\(records.count)가지를 기억하고 있어요." : "I remember \(records.count) thing\(records.count == 1 ? "" : "s")."
        return ([head] + lines).joined(separator: "\n")
    }

    static func day(_ summary: String?, offset: Int, korean: Bool) -> String {
        let name = korean ? (offset == 0 ? "오늘" : offset == -1 ? "어제" : "그제") : (offset == 0 ? "today" : offset == -1 ? "yesterday" : "the day before yesterday")
        guard let summary else { return korean ? "\(name)는 기록된 대화가 없어요." : "I have nothing from \(name)." }
        return korean ? "\(name) 기록이에요. \(summary)" : "From \(name): \(summary)"
    }

    private static let particles = ["에서는", "에서", "으로", "에게", "한테", "까지", "부터", "이랑", "랑", "하고", "은", "는", "이", "가", "을", "를", "에", "로", "도",
                                    "만", "의", "와", "과"]
    private static let dull: Set<String> = ["오늘", "내일", "어제", "지금", "그거", "이거", "뭐", "좀", "나", "내", "제", "저", "해줘", "알려줘", "보여줘", "틀어줘",
                                            "켜줘", "꺼줘", "찾아줘", "해", "줘", "있어", "어때", "뭐야", "please", "the", "what", "how", "can", "you", "my"]

    /// The words a day's notes come back to most (particles off, fillers out), most first.
    static func topics(_ notes: [String], limit: Int = 3) -> [String] {
        var counts: [String: Int] = [:], order: [String] = []
        for note in notes {
            var seen = Set<String>()
            for raw in ArisMemoryText.words(note) {
                var word = raw
                if ArisMemoryText.isKorean(word), let particle = particles.first(where: { word.hasSuffix($0) && word.count > $0.count + 1 }) {
                    word = String(word.dropLast(particle.count))
                }
                guard word.count >= 2, !dull.contains(word), !word.allSatisfy(\.isNumber), !ArisMemoryText.latinStopwords.contains(word),
                      !(word.hasSuffix("줘") || word.hasSuffix("해")), seen.insert(word).inserted else { continue }
                if counts[word] == nil { order.append(word) }
                counts[word, default: 0] += 1
            }
        }
        return order.enumerated().sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }.prefix(limit).map(\.element)
    }

    /// Without the on-device model: how many times the user talked and what about, never their requests word for word.
    static func plainSummary(_ notes: [String], offset: Int, korean: Bool) -> String? {
        var seen = Set<String>()
        let distinct = notes.filter { seen.insert(ArisMemoryText.normalized($0)).inserted }
        guard !distinct.isEmpty else { return nil }
        let about = topics(distinct)
        if korean {
            return about.isEmpty ? "\(distinct.count)번 이야기했어요." : "\(distinct.count)번 이야기했고, 주로 \(about.joined(separator: ", ")) 이야기였어요."
        }
        return about.isEmpty ? "You talked \(distinct.count) times." : "You talked \(distinct.count) times, mostly about \(about.joined(separator: ", "))."
    }
}
