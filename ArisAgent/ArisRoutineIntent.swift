//
//  ArisRoutineIntent.swift
//  aris-agent
//
//  What the user's words ask of their routines, read from the words alone, Korean and English:
//  "출근 루틴 만들어 줘: 메일 확인하고, 오늘 일정 알려 주고, 슬랙 열어 줘", "방금 한 걸 출근 루틴으로 저장해 줘",
//  "출근 루틴 해 줘", "출근 루틴", "run my morning routine", "루틴 뭐 있어?", "출근 루틴 보여 줘",
//  "출근 루틴에서 슬랙 빼 줘", "출근 루틴에 날씨 알려 줘 추가해 줘", "출근 루틴 지워 줘".
//  Only a whole sentence that is one of these counts. Anything longer or looser ("매일 9시에 출근 루틴 해 줘", "아침 운동
//  루틴 추천해 줘") is nil and goes to the AI as before. Pure.
//

import Foundation

enum ArisRoutineIntent: Equatable {
    /// Make a routine from the steps he just said.
    case create(name: String, steps: [String])
    /// Make one from his last few requests ("방금 한 걸 … 루틴으로 저장해 줘"); no name when he gave none.
    case saveRecent(name: String?)
    case run(ArisRoutine)
    case list
    case show(ArisRoutine)
    case addStep(ArisRoutine, step: String)
    /// `words`: what he called the step ("슬랙", "2번", "the last step").
    case dropStep(ArisRoutine, words: String)
    case delete(ArisRoutine)
    /// A plain routine command (run, change) naming a routine he doesn't have, while he has others.
    case missing(name: String)

    static func parse(_ said: String, routines: [ArisRoutine]) -> ArisRoutineIntent? {
        let text = said.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ArisRoutineWords.mentions(text), text.count <= 1_500 else { return nil }
        let whole = uncalled(text)
        let line = whole.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let recent = saveRecent(line) { return recent }
        if let made = create(whole) { return made }
        if let change = change(line, routines: routines) { return change }
        if lists.contains(where: { groups($0, in: line) != nil }) { return .list }
        // "운동 루틴 알려 줘" asks the AI for a workout: only a routine he has is shown.
        if let routine = named(shows, in: line, routines: routines) { return .show(routine) }
        return run(line, routines: routines)
    }

    // MARK: - Making one

    private static let polite = #"(?:줘요|주세요|줄래요|줄래|줘|둬|놔)?+"#
    private static let makes = [
        #"^(?:내\s*)?(.{1,40}?)\s*루틴\s*(?:을|를|으로|로|은|이라고)?\s*(?:하나\s*)?(?:새로\s*)?(?:만들어|만들자|만들래|저장해|등록해|추가해)\s*"# + polite + #"\s*([.:：,]?)\s*(.+)$"#,
        #"^(?:please\s+)?(?:make|create|save|add|set\s+up|build)\s+(?:me\s+)?(?:a\s+|my\s+)?(?:new\s+)?routine\s+(?:called|named)\s+(.{1,40}?)\s*(:|,|\.|-|–|—|\bwith\b)\s*(.+)$"#,
        #"^(?:please\s+)?(?:make|create|save|add|set\s+up|build)\s+(?:me\s+)?(?:a\s+|an\s+|my\s+|the\s+)?(?:new\s+)?(.{1,40}?)\s+routine\s*(:|,|\.|-|–|—|\bwith\b)\s*(.+)$"#,
    ]

    /// "<이름> 루틴 만들어 줘: <단계들>". Without a colon it must hold two steps or more: "아침 운동 루틴 만들어 줘" asks the
    /// AI for a workout, not Aris for a routine.
    private static func create(_ text: String) -> ArisRoutineIntent? {
        for pattern in makes {
            guard let found = groups(pattern, in: text), let raw = found[0], let rest = found[2] else { continue }
            let name = ArisRoutineNames.clean(raw)
            let steps = ArisRoutineSteps.split(rest)
            let colon = found[1].map { [":", "："].contains($0) } ?? false
            guard isName(name), !steps.isEmpty, steps.count >= 2 || colon else { return nil }
            return .create(name: name, steps: steps)
        }
        return nil
    }

    private static let recents = [
        #"^(?:방금|지금|아까|좀\s*전에)\s*(?:까지\s*)?(?:한|했던|시킨|말한|부탁한|요청한)\s*(?:것들|일들|요청들|거|것|걸|일|요청)?(?:를|을)?\s*(?:그대로\s*)?(?:(.{1,30}?)\s*)?루틴\s*(?:으로|로)\s*(?:저장|만들|등록|기억)"#,
        #"^(?:내\s*)?(.{1,30}?)\s*루틴\s*(?:으로|로)\s*(?:방금|지금까지|아까)\s*(?:한|했던)\s*\S*\s*(?:저장|만들|등록)"#,
        #"^(?:please\s+)?(?:save|make|turn|store|keep)\s+(?:what\s+i\s+just\s+(?:did|asked\s+for|asked\s+you|asked|said)|what\s+i\s+did\s+just\s+now|that|those|these|the\s+last\s+(?:few\s+|three\s+|two\s+)?(?:things|requests|steps|ones))\s+(?:as|into)\s+(?:a\s+|my\s+|the\s+)?(?:new\s+)?(?:routine(?:\s+(?:called|named)\s+(.{1,30}?))?|(.{1,30}?)\s+routine)[.!\s]*$"#,
    ]

    private static func saveRecent(_ line: String) -> ArisRoutineIntent? {
        for pattern in recents {
            guard let found = groups(pattern, in: line) else { continue }
            let name = found.compactMap { $0 }.map(ArisRoutineNames.clean).first { isName($0) }
            return .saveRecent(name: name)
        }
        return nil
    }

    // MARK: - Changing one

    private static let takesOut = #"\s*(?:은|는|을|를|도)?\s*(?:좀\s*)?(?:빼|지워|삭제해|없애|제외해)\s*(?:줘요|주세요|줄래요|줄래|줘|버려)?[.!~\s]*$"#
    private static let drops = [
        (#"^(?:내\s*)?(.{1,40}?)\s*루틴\s*에서\s*(.{1,80}?)"# + takesOut, name: 0, words: 1),
        // Said without 에서, only with 빼 ("출근 루틴 슬랙 빼 줘"): "… 지워 줘" there would be about the thing itself.
        (#"^(?:내\s*)?(.{1,40}?)\s*루틴\s+(.{1,80}?)\s*(?:은|는|을|를|도)?\s*(?:좀\s*)?빼\s*(?:줘요|주세요|줄래요|줄래|줘|버려)?[.!~\s]*$"#, name: 0, words: 1),
        (#"^(?:please\s+)?(?:remove|delete|drop|take)\s+(.{1,80}?)\s+(?:from|out\s+of)\s+(?:my\s+|the\s+)?(.{1,40}?)\s+routine[.!\s]*$"#, name: 1, words: 0),
    ]
    private static let adds = [
        (#"^(?:내\s*)?(.{1,40}?)\s*루틴\s*에(?:다가|다|도)?\s+(.{1,200}?)\s*(?:도|를|을)?\s*(?:좀\s*)?(?:추가해|넣어|더해)\s*(?:줘요|주세요|줄래요|줄래|줘)?[.!~\s]*$"#, name: 0, words: 1),
        (#"^(?:please\s+)?add\s+(.{1,200}?)\s+to\s+(?:my\s+|the\s+)?(.{1,40}?)\s+routine[.!\s]*$"#, name: 1, words: 0),
    ]
    private static let deletes = [
        #"^(?:내\s*)?(.{1,40}?)\s*루틴"# + takesOut,
        #"^(?:please\s+)?(?:delete|remove|erase|get\s+rid\s+of)\s+(?:my\s+|the\s+)?(.{1,40}?)\s+routine[.!\s]*$"#,
    ]

    private static func change(_ line: String, routines: [ArisRoutine]) -> ArisRoutineIntent? {
        for (pattern, name, words) in drops {
            guard let found = groups(pattern, in: line), let raw = found[name], let what = found[words] else { continue }
            guard let routine = ArisRoutineNames.find(raw, in: routines) else { return missing(raw, routines: routines) }
            return .dropStep(routine, words: what.trimmingCharacters(in: .whitespaces))
        }
        for (pattern, name, words) in adds {
            guard let found = groups(pattern, in: line), let raw = found[name], let what = found[words] else { continue }
            guard let routine = ArisRoutineNames.find(raw, in: routines) else { return missing(raw, routines: routines) }
            // "add that to my morning routine": what "that" is, only the AI can tell, so the sentence is its to take
            // (ArisPointsBack; never a step called "that").
            if ArisPointsBack.only(what) { return nil }
            return .addStep(routine, step: ArisRoutineSteps.polished(what))
        }
        // Only a routine he has: "운동 루틴 지워 줘" may be about a note or a memory.
        return named(deletes, in: line, routines: routines).map(ArisRoutineIntent.delete)
    }

    // MARK: - Listing, showing, running

    private static let lists = [
        #"^(?:내|내가\s*만든|저장된|저장한|지금\s*있는)?\s*루틴\s*(?:은|이|들|들이|들은)?\s*(?:뭐|뭐가|뭐뭐|뭘|어떤\s*거|어떤\s*게|무슨\s*거|몇\s*개)\s*(?:가\s*)?(?:있어|있지|있나|있니|있더라|있는지)\S{0,4}[?.!~\s]*$"#,
        #"^(?:내|내가\s*만든|저장된|저장한|모든|전체)?\s*루틴\s*(?:들)?\s*(?:목록|리스트|전부|다|모두)?\s*(?:좀\s*)?(?:보여|알려|말해|읽어)\s*(?:줘요|주세요|줄래요|줄래|줘)[?.!~\s]*$"#,
        #"^(?:내\s*)?루틴\s*(?:목록|리스트)[?.!~\s]*$"#,
        #"^(?:what|which)\s+routines\s+(?:do\s+i\s+have|are\s+there|have\s+i\s+(?:got|saved|made))[?.!\s]*$"#,
        #"^what\s+are\s+my\s+routines[?.!\s]*$"#,
        #"^(?:please\s+)?(?:list|show)(?:\s+me)?(?:\s+(?:all\s+my|all\s+the|my|all|the))?\s+routines[?.!\s]*$"#,
        #"^my\s+routines[?.!\s]*$"#,
    ]
    private static let shows = [
        #"^(?:내\s*)?(.{1,40}?)\s*루틴\s*(?:은|는|이|가|을|를|에|에는|엔)?\s*(?:좀\s*)?(?:보여\s*(?:줘요|주세요|줄래요|줄래|줘)|알려\s*(?:줘요|주세요|줘)|뭐\s*였지|뭐였더라|뭐야|뭐지|뭐더라|뭐\s*(?:가\s*)?(?:들어\s*)?있\S{1,4}|뭐\s*하는\s*거\S{1,3}|확인해?\s*(?:줘|주세요)?|단계\s*(?:보여|알려)\s*(?:줘|주세요))[?.!~\s]*$"#,
        #"^(?:please\s+)?(?:show|tell)(?:\s+me)?\s+(?:my\s+|the\s+)?(.{1,40}?)\s+routine[?.!\s]*$"#,
        #"^what(?:'s|’s|\s+is)\s+(?:in\s+)?(?:my\s+|the\s+)?(.{1,40}?)\s+routine[?.!\s]*$"#,
    ]
    private static let runVerb = #"해\s*줘요?|해\s*주세요|해\s*줄래요?|해\s*줄\s*수\s*있(?:어요?|니|나요?)|해요|해|하자|실행(?:해\s*(?:줘요?|주세요)|해)?|시작(?:해\s*(?:줘요?|주세요)|하자|해)?|돌려\s*(?:줘요?|주세요)|틀어\s*(?:줘요?|주세요)|켜\s*(?:줘요?|주세요)|가자|부탁해요?|고고|ㄱㄱ"#
    private static let runs = [
        #"^(?:내\s*)?(.{1,40}?)\s*루틴\s*(?:을|를|으로|로)?\s*(?:좀|다시|지금|바로|한\s*번\s*더)?\s*("# + runVerb + #")?[?.!~\s]*$"#,
        #"^(?:please\s+)?(?:(run|start|do|begin|launch|play|go\s+through)\s+)?(?:my\s+|the\s+)?(.{1,40}?)\s+routine(?:\s+(?:again|please|now))?[.!\s]*$"#,
    ]
    /// Words that make it a request for later or on a repeat: a schedule, which the AI sets up on its card.
    private static let later = #"매일|매주|매달|마다|\d\s*시|\d{1,2}:\d{2}|내일|모레|이따|나중에|\d\s*(?:분|시간)\s*(?:뒤|후|있다)|아침에|저녁에|every\s|\bdaily\b|\bweekly\b|tomorrow|\blater\b|\bat\s+\d|\bin\s+\d+\s*(?:min|hour)"#

    /// "출근 루틴 해 줘", "출근 루틴", "run my morning routine": only a routine he has runs; one he doesn't have is said
    /// so when the words plainly ask to run it.
    private static func run(_ line: String, routines: [ArisRoutine]) -> ArisRoutineIntent? {
        guard groups(later, in: line) == nil else { return nil }
        for (index, pattern) in runs.enumerated() {
            guard let found = groups(pattern, in: line) else { continue }
            let raw = (index == 0 ? found[0] : found[1]) ?? ""
            let verb = (index == 0 ? found[1] : found[0]) != nil
            // "출근 루틴?" alone asks about it: shown, not run.
            if let routine = ArisRoutineNames.find(raw, in: routines) { return !verb && line.contains("?") ? .show(routine) : .run(routine) }
            return verb ? missing(raw, routines: routines) : nil
        }
        return nil
    }

    /// The routine a scheduled job's words run. A schedule's prompt should be just "출근 루틴 해 줘", but an AI may have
    /// kept the time in it ("매일 9시에 출근 루틴 해 줘"): the name is then the words right before 루틴, and the sentence must
    /// still end by asking to run it.
    static func scheduled(_ prompt: String, routines: [ArisRoutine]) -> ArisRoutine? {
        if case .run(let routine)? = parse(prompt, routines: routines) { return routine }
        let line = prompt.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let before = groups(#"^(.{1,80}?)\s*루틴\s*(?:을|를)?\s*(?:"# + runVerb + #")[.!~\s]*$"#, in: line)?.first.flatMap({ $0 }) {
            let words = before.split(separator: " ")
            return (1...min(4, max(1, words.count))).reversed().lazy
                .compactMap { ArisRoutineNames.find(words.suffix($0).joined(separator: " "), in: routines) }.first
        }
        let english = groups(#"^(?:please\s+)?(?:run|start|do)\s+(?:my\s+|the\s+)?(.{1,40}?)\s+routine\b"#, in: line)?.first.flatMap { $0 }
        return english.flatMap { ArisRoutineNames.find($0, in: routines) }
    }

    // MARK: - Helpers

    /// The routine of his that a one-name pattern names.
    private static func named(_ patterns: [String], in line: String, routines: [ArisRoutine]) -> ArisRoutine? {
        for pattern in patterns {
            guard let found = groups(pattern, in: line), let raw = found[0] else { continue }
            return ArisRoutineNames.find(raw, in: routines)
        }
        return nil
    }

    /// He named a routine he doesn't have. Only someone who keeps routines is told so: for anyone else "모닝 루틴 틀어 줘"
    /// is an ordinary request for the AI.
    private static func missing(_ raw: String, routines: [ArisRoutine]) -> ArisRoutineIntent? {
        let name = ArisRoutineNames.clean(raw)
        return !routines.isEmpty && isName(name) ? .missing(name: name) : nil
    }

    /// A few words that can be a routine's name: not a sentence, not a number.
    private static func isName(_ name: String) -> Bool {
        !ArisRoutineNames.key(name).isEmpty && name.count <= ArisRoutineRules.nameLimit && name.split(separator: " ").count <= 4
            && name.rangeOfCharacter(from: CharacterSet(charactersIn: "?!:,.")) == nil
    }

    /// Without "아리스," or "Aris," in front.
    private static func uncalled(_ text: String) -> String {
        guard let call = text.range(of: #"^(?:hey\s+)?(?:아리스(?:야|아)?|aris)\s*[,!]?\s+"#, options: [.regularExpression, .caseInsensitive]) else { return text }
        return String(text[call.upperBound...])
    }

    /// The pattern's groups in `text` (nil for one that took nothing); nil when it doesn't match.
    static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<max(1, match.numberOfRanges)).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

/// Which step of a routine the user means by "슬랙", "2번", "마지막", "the second step" or "the open notes step".
enum ArisRoutineStepPick {
    private static let ordinals: [(String, Int)] = [("첫", 1), ("두", 2), ("세", 3), ("네", 4), ("다섯", 5), ("first", 1), ("second", 2), ("third", 3),
                                                    ("fourth", 4), ("fifth", 5)]

    /// The step's place (from 0), or nil when the words fit none or more than one.
    static func index(of words: String, in steps: [String]) -> Int? {
        let found = matches(of: words, in: steps)
        return found.count == 1 ? found[0] : nil
    }

    /// Every step the words could mean: the one a number, an ordinal or "last" names, else each step that holds all of
    /// their words. Several: the caller lists them and asks which.
    static func matches(of words: String, in steps: [String]) -> [Int] {
        let said = words.precomposedStringWithCanonicalMapping.lowercased().trimmingCharacters(in: .whitespaces)
        func one(_ index: Int?) -> [Int] { index.map { [$0] } ?? [] }
        if said.range(of: #"^(?:the\s+)?(?:마지막|맨\s*끝|끝|last)(?:\s*(?:단계|거|것|step|one))?$"#, options: .regularExpression) != nil { return one(steps.indices.last) }
        if let number = ArisRoutineIntent.groups(#"^(?:step\s*|#)?(\d{1,2})\s*(?:번째|번|단계)?(?:\s*(?:단계|거|것))?$"#, in: said)?.first.flatMap({ $0 }).flatMap(Int.init) {
            return one(steps.indices.contains(number - 1) ? number - 1 : nil)
        }
        if let ordinal = ordinals.first(where: { said.range(of: "^(?:the\\s+)?\($0.0)\\s*(?:번째|step|one)", options: .regularExpression) != nil }) {
            return one(steps.indices.contains(ordinal.1 - 1) ? ordinal.1 - 1 : nil)
        }
        // By its words: every word he said is in the step, whatever the case and the verb's form ("the open notes step"
        // and "opening notes" are "open Notes"; "메일 확인하는 거" is "메일 확인해 줘"; a closing 을/를/은/는 aside). Words
        // that only point ("the", "step", "거") name nothing.
        let wanted = said.split(separator: " ").map { compact(String($0)) }.filter { !$0.isEmpty && !pointing.contains($0) }
        guard !wanted.isEmpty else { return [] }
        func fits(_ words: [String]) -> [Int] {
            steps.indices.filter { index in
                let step = compact(steps[index])
                return words.allSatisfy { word in forms(word).contains { step.contains($0) } }
            }
        }
        let all = fits(wanted)
        // A Korean verb said as "… 여는 (거)" may not be the step's own form ("열어 줘"): the words before it decide.
        if all.isEmpty, wanted.count > 1, let last = wanted.last, ["는", "은", "던"].contains(String(last.suffix(1))), ArisMemoryText.isKorean(last) {
            return fits(Array(wanted.dropLast()))
        }
        return all
    }

    private static let particles: Set<String> = ["을", "를", "은", "는", "이", "가", "도"]
    /// Words that point at a step without naming it.
    private static let pointing: Set<String> = ["the", "a", "an", "my", "that", "this", "step", "steps", "one", "part", "item", "단계", "거", "것", "그", "저"]

    /// A word as a step may hold it: itself, without a closing particle, and a verb without its ending ("opening" →
    /// "open", "checks" → "check", "확인하는" → "확인").
    private static func forms(_ word: String) -> [String] {
        var forms = [word]
        if word.count > 2, particles.contains(String(word.suffix(1))) { forms.append(String(word.dropLast())) }
        for ending in ["ing", "es", "ed", "s"] where word.hasSuffix(ending) && word.count - ending.count >= 3 && word.unicodeScalars.allSatisfy(\.isASCII) {
            forms.append(String(word.dropLast(ending.count)))
        }
        for ending in ["하는", "하기", "했던", "하던", "한", "할", "해"] where word.hasSuffix(ending) && word.count - ending.count >= 2 {
            forms.append(String(word.dropLast(ending.count)))
        }
        return forms
    }

    private static func compact(_ text: String) -> String {
        String(String.UnicodeScalarView(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }
}

extension ArisRoutineIntent {
    /// Whether the request may reach an AI: only a run (each of its steps is a turn of its own). Making, changing,
    /// listing, showing and deleting a routine are aris-agent's own, with no AI asked.
    var asksAnAI: Bool {
        if case .run = self { return true }
        return false
    }
}
