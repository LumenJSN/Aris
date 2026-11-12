//
//  ArisWorkIntent.swift
//  aris-agent
//
//  What the user asks about Aris's own past work, answered by the agent itself from the episodes (no brain), like "어제 뭐
//  했지" from the day notes:
//    "어제 그 파일 어디 저장했지?", "아까 합친 PDF 어디 있어?", "where did you save that file yesterday"   -> where
//    "지난번에 키노트 창 정리 어떻게 했지?", "how did you do the PDF merge last time"                      -> how
//  Only when one episode (or a few) clearly matches: otherwise the turn goes to the brain, which has `recall`.
//  The answer is made from the episode's own fields (when, their words then, the steps, the paths). An answer that
//  rests on a tainted episode is said to the user all the same, and the caller marks the conversation as having outside
//  text from there on (its paths and names may be someone else's choice).
//  Also "…잊어" for a lesson, when no memory about him matches the words. Foundation only (tested).
//

import Foundation

enum ArisWorkIntent: Equatable {
    /// Where something was saved, made or moved. `day`: 0 today, -1 yesterday, -2 the day before; nil when not said.
    case whereSaved(topic: String, day: Int?)
    /// How something was done before.
    case how(topic: String, day: Int?)

    var auditName: String {
        switch self {
        case .whereSaved: "work: where"
        case .how: "work: how"
        }
    }

    // MARK: - Parsing

    private static let whereKorean = ["어디저장했", "어디에저장했", "어디다저장했", "어디에다저장했", "어디뒀", "어디에뒀", "어디다뒀", "어디두었", "어디에두었", "어디만들었",
                                      "어디에만들었", "어디로옮겼", "어디에옮겼", "어디다옮겼", "어디넣었", "어디에넣었", "어디다넣었", "어디로보냈"]
    /// "어디 있지" is about Aris's work only with a word that says Aris made or moved it.
    private static let whereIsKorean = ["어디있지", "어디있어", "어디에있지", "어디에있어", "어디있더라", "어디에있더라", "어디있죠", "어디있나"]
    private static let madeKorean = ["만든", "저장한", "옮긴", "합친", "변환한", "바꾼", "정리한", "내보낸", "나눈", "압축한", "받은", "만들어준", "저장해준"]
    private static let howKorean = ["어떻게했", "어떻게한", "어떻게하셨", "어떻게처리했", "어떻게해결했"]
    private static let beforeKorean = ["지난번", "저번", "전에", "아까", "어제", "그때", "그제", "그저께", "방금", "예전", "이전", "지난주", "요전"]
    /// Words that are the question itself or point without naming: never the topic.
    private static let dullKorean: Set<String> = ["그", "그거", "그것", "그건", "그걸", "이거", "저거", "파일", "문서", "내", "내가", "네가", "너", "니가", "아리스", "아리스가", "한", "한거", "거",
                                                  "건", "것", "좀", "혹시", "또", "다시", "지", "더라", "했지", "했더라", "했어", "했었지", "했는지", "때", "에", "는", "은"]
    private static let dullEnglish: Set<String> = ["how", "did", "you", "do", "that", "it", "this", "the", "last", "time", "before", "earlier", "yesterday", "today", "where",
                                                   "save", "saved", "put", "store", "stored", "move", "moved", "file", "is", "was", "made", "again", "please", "one", "a", "an",
                                                   "we", "i", "my", "thing", "stuff", "aris", "create", "created", "make"]

    static func parse(_ said: String) -> ArisWorkIntent? {
        let raw = ArisMemoryText.ownWords(said).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".!?。~ ")).precomposedStringWithCanonicalMapping
        guard !text.isEmpty, text.count <= 200 else { return nil }
        let lowered = text.lowercased()
        let compact = lowered.replacingOccurrences(of: " ", with: "")
        let day = dayOffset(compact, lowered: lowered)
        if whereKorean.contains(where: compact.contains) || (whereIsKorean.contains(where: compact.contains) && (madeKorean + beforeKorean).contains(where: compact.contains)) {
            return .whereSaved(topic: koreanTopic(text), day: day)
        }
        if howKorean.contains(where: compact.contains), beforeKorean.contains(where: compact.contains) {
            return .how(topic: koreanTopic(text), day: day)
        }
        if lowered.range(of: #"^where did (you|we|i) (save|put|store|move|create|make)\b"#, options: .regularExpression) != nil
            || lowered.range(of: #"^where('s| is) (the|that) .*\b(you|we) (made|saved|created|moved)\b"#, options: .regularExpression) != nil {
            return .whereSaved(topic: englishTopic(lowered), day: day)
        }
        if lowered.range(of: #"^how did (you|we) (do|make|fix|handle|set up)\b"#, options: .regularExpression) != nil,
           ["last time", "before", "yesterday", "earlier", "the other day", "previously"].contains(where: lowered.contains) {
            return .how(topic: englishTopic(lowered), day: day)
        }
        return nil
    }

    private static func dayOffset(_ compact: String, lowered: String) -> Int? {
        if compact.contains("그저께") || compact.contains("그제") { return -2 }
        if compact.contains("어제") || lowered.contains("yesterday") { return -1 }
        if compact.contains("오늘") || compact.contains("아까") || compact.contains("방금") || lowered.contains("today") || lowered.contains("earlier") { return 0 }
        return nil
    }

    /// How the question's own verb begins ("저장했지", "뒀더라", "있어"): never the topic.
    private static let questionVerbs = ["저장했", "뒀", "두었", "만들었", "옮겼", "넣었", "보냈", "있지", "있어", "있더라", "있죠", "있나", "했지", "했더라", "했어", "했었",
                                        "했는", "처리했", "해결했", "하셨"]

    /// The words that name what it was about: the request without the question, the time words and the pointing words.
    private static func koreanTopic(_ text: String) -> String {
        ArisMemoryRecall.topicTokens(text).filter { token in
            guard !dullKorean.contains(token), !dullEnglish.contains(token) else { return false }
            if (beforeKorean + ["오늘", "어디", "어떻게"]).contains(where: token.hasPrefix) { return false }
            return !questionVerbs.contains(where: token.hasPrefix)
        }.joined(separator: " ")
    }

    private static func englishTopic(_ lowered: String) -> String {
        ArisMemoryText.words(lowered).filter { !dullEnglish.contains($0) && !ArisMemoryText.latinStopwords.contains($0) }.joined(separator: " ")
    }

    // MARK: - Answering

    struct Answer: Equatable {
        var text: String
        /// It rests on an episode from a turn that read outside content.
        var tainted: Bool
    }

    static let whereDays = 14.0
    static let howThreshold = 0.45
    static let most = 3

    /// The answer, or nil when nothing (or too much) matches: the brain takes the turn then. `episodes`: every one,
    /// tainted ones too (the answer is for the user).
    static func answer(_ intent: ArisWorkIntent, episodes: [ArisWorkEpisode], now: Date, korean: Bool, calendar: Calendar = .current) -> Answer? {
        switch intent {
        case .whereSaved(let topic, let day): return whereAnswer(topic: topic, day: day, episodes: episodes, now: now, korean: korean, calendar: calendar)
        case .how(let topic, let day): return howAnswer(topic: topic, day: day, episodes: episodes, now: now, korean: korean, calendar: calendar)
        }
    }

    private static func onDay(_ episode: ArisWorkEpisode, _ day: Int, now: Date, calendar: Calendar) -> Bool {
        guard let wanted = calendar.date(byAdding: .day, value: day, to: now) else { return false }
        return calendar.isDate(episode.at, inSameDayAs: wanted)
    }

    /// What an answer calls the request an episode was: his own words for a turn, quoted as said; for a job its title
    /// (a job's prompt was written by a model, never their words).
    static func asked(_ episode: ArisWorkEpisode, korean: Bool) -> String {
        guard episode.kind == .job else { return korean ? "‘\(episode.asked)’" : "“\(episode.asked)”" }
        let title = episode.place.isEmpty ? episode.title : episode.place
        return korean ? "‘\(title)’ 작업" : "the job “\(title)”"
    }

    /// The paths an episode left: files it made or moved, and a job's result.
    static func places(_ episode: ArisWorkEpisode) -> [String] {
        episode.made.filter { $0.kind == "file" || $0.kind == "moved" }.map(\.value) + (episode.result.isEmpty ? [] : [episode.result])
    }

    private static func whereAnswer(topic: String, day: Int?, episodes: [ArisWorkEpisode], now: Date, korean: Bool, calendar: Calendar) -> Answer? {
        let grams = ArisWorkAsk.grams(topic)
        let found = episodes.filter { episode in
            guard !places(episode).isEmpty, episode.outcome != .cancelled, episode.at <= now else { return false }
            if let day { guard onDay(episode, day, now: now, calendar: calendar) else { return false } }
            else if now.timeIntervalSince(episode.at) > whereDays * 86_400 { return false }
            guard !grams.isEmpty else { return true }
            let names = ArisMemoryText.grams(places(episode).map { ($0 as NSString).lastPathComponent }.joined(separator: " "))
            return ArisWorkRecall.relevance(asked: episode.asked + " " + episode.title, steps: episode.steps, query: grams) >= 0.3 || !names.intersection(grams).isEmpty
        }.sorted { $0.at > $1.at }
        // One clearly; a few are all said; with nothing to go by but "that file" and many candidates, the brain asks.
        guard !found.isEmpty, found.count <= most else { return nil }
        let lines = found.map { episode -> String in
            let time = ArisWorkWords.when(episode.at, now: now, korean: korean, calendar: calendar)
            let paths = places(episode).prefix(3).joined(separator: ", ")
            let undone = episode.outcome == .undone ? (korean ? " (나중에 되돌렸어요)" : " (undone since)") : ""
            return korean ? "\(time) \(asked(episode, korean: true)): \(paths)\(undone)" : "\(time), \(asked(episode, korean: false)): \(paths)\(undone)"
        }
        let text: String
        if lines.count == 1 {
            text = korean ? "여기 있어요. \(lines[0])" : "Here: \(lines[0])"
        } else {
            text = (korean ? "\(lines.count)개를 찾았어요." : "I found \(lines.count).") + "\n" + lines.map { "· " + $0 }.joined(separator: "\n")
        }
        return Answer(text: text, tainted: found.contains { !$0.clean })
    }

    private static func howAnswer(topic: String, day: Int?, episodes: [ArisWorkEpisode], now: Date, korean: Bool, calendar: Calendar) -> Answer? {
        let grams = ArisWorkAsk.grams(topic)
        // "그거 어떻게 했지" names nothing: the conversation knows what "그거" is, the record doesn't.
        guard !grams.isEmpty else { return nil }
        let scored = episodes.filter { episode in
            guard !episode.steps.isEmpty, episode.at <= now else { return false }
            return day.map { onDay(episode, $0, now: now, calendar: calendar) } ?? true
        }.map { ($0, ArisWorkRecall.relevance(asked: $0.asked + " " + $0.title, steps: $0.steps, query: grams)) }
            .filter { $0.1 >= howThreshold }
            .sorted { ($0.1, $0.0.at) > ($1.1, $1.0.at) }
        guard let best = scored.first else { return nil }
        // Clearly this one: alone, well ahead, or the next one is the same kind of request (then the newest of them).
        if scored.count > 1, scored[1].1 > best.1 - 0.15, !ArisWorkAsk.same(scored[1].0.asked, best.0.asked) { return nil }
        let episode = scored.filter { ArisWorkAsk.same($0.0.asked, best.0.asked) }.map(\.0).max { $0.at < $1.at } ?? best.0
        let steps = episode.steps.prefix(6).enumerated().map { index, step -> String in
            let note = step.failed ? (korean ? " (안 됨)" : " (failed)") : step.status == "declined" ? (korean ? " (하지 않음)" : " (not done)") : ""
            return "\(index + 1)) \(step.line)\(note)"
        }.joined(separator: "  ")
        let time = ArisWorkWords.when(episode.at, now: now, korean: korean, calendar: calendar)
        let end: String
        switch episode.outcome {
        case .done: end = korean ? "잘 끝났어요." : "It worked."
        case .failed: end = korean ? "그때는 끝까지 못 했어요." : "It didn't finish that time."
        case .cancelled: end = korean ? "중간에 멈췄어요." : "It was stopped partway."
        case .undone: end = korean ? "나중에 되돌렸어요." : "It was undone afterwards."
        }
        let text = korean ? "\(time)에 \(asked(episode, korean: true))\(episode.kind == .job ? "은" : " 요청은") 이렇게 했어요: \(steps). \(end)"
                          : "\(time), \(asked(episode, korean: false)) went like this: \(steps). \(end)"
        return Answer(text: text, tainted: !episode.clean)
    }

    // MARK: - "…잊어" for a lesson

    /// The lessons `words` name: their request, command or target holds the words as said, or every word of them.
    static func lessons(matching words: String, in lessons: [ArisWorkLesson]) -> [ArisWorkLesson] {
        let wanted = ArisMemoryText.normalized(words)
        guard wanted.count >= 2 else { return [] }
        let tokens = ArisMemoryRecall.topicTokens(words).filter { $0.count >= 2 }
        return lessons.filter { lesson in
            let haystack = ArisMemoryText.normalized(([lesson.asked, lesson.key] + (lesson.works + lesson.fails).map(\.line)).joined(separator: " "))
            return haystack.contains(wanted) || (!tokens.isEmpty && tokens.allSatisfy { haystack.contains(ArisMemoryText.normalized($0)) })
        }
    }

    /// What "…잊어" does when no memory about the user matches `words`: the one lesson they name is removed; several are
    /// listed and none removed (설정 › 기억 has a button for each); nil when no lesson matches either.
    static func forget(_ words: String, store: ArisWorkStore, korean: Bool) -> String? {
        let found = lessons(matching: words, in: store.lessons())
        guard let first = found.first else { return nil }
        guard found.count == 1 else {
            let list = found.prefix(3).map { ArisWorkWords.sentence($0, korean: korean) }.joined(separator: " / ")
            return korean ? "‘\(words)’에 맞는, 일하면서 배운 게 \(found.count)개예요: \(list) 설정 › 기억에서 골라 지울 수 있어요."
                          : "\(found.count) things I learned from work match \(words): \(list) You can remove each in Settings › Memory."
        }
        guard store.deleteLesson(id: first.id) else { return korean ? "지우지 못했어요." : "I couldn't remove it." }
        return korean ? "일하면서 배운 걸 잊었어요: \(ArisWorkWords.sentence(first, korean: true))" : "Forgotten, from what I learned at work: \(ArisWorkWords.sentence(first, korean: false))"
    }
}

/// POST /memory, the work memory's part (설정 › 기억 › 일하면서 배운 것; only the Aris app itself: ArisPeer, in main.swift):
///   {"op": "work"}                             -> {"on": bool, "episodes": n, "lessons": [{"id","kind","ko","en","basisKo","basisEn","confidence","outside"}]}
///   ("outside": the lesson rests on a turn that read outside content; the page marks it.)
///   {"op": "workOn", "on": bool}               -> {"on": bool}
///   {"op": "workDelete", "id": 3}              -> {"removed": bool}
///   {"op": "workClear", "confirm": "모두"}      -> {"cleared": true}   (every episode and lesson)
/// Nil for any other op (ArisMemoryRoute answers 400). `audit`: the line for actions.log, never a lesson's words.
enum ArisWorkRoute {
    static func handle(_ object: [String: Any], store: ArisWorkStore) -> (status: Int, body: Data, audit: String?)? {
        switch object["op"] as? String {
        case "work":
            let episodes = Dictionary(store.episodes(tainted: true).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let rows = store.lessons().map { lesson -> [String: Any] in
                let latest = lesson.evidence.compactMap { episodes[$0] }.max { $0.at < $1.at }
                return ["id": lesson.id, "kind": lesson.kind.rawValue, "ko": ArisWorkWords.sentence(lesson, korean: true), "en": ArisWorkWords.sentence(lesson, korean: false),
                        "basisKo": ArisWorkWords.basis(lesson, latest: latest, korean: true), "basisEn": ArisWorkWords.basis(lesson, latest: latest, korean: false),
                        "confidence": lesson.confidence, "outside": lesson.outside]
            }
            return ok(["on": store.isOn, "episodes": store.count(), "lessons": rows], audit: nil)
        case "workOn":
            guard let on = object["on"] as? Bool else { return bad }
            store.isOn = on
            return ok(["on": store.isOn], audit: "work memory: \(on ? "on" : "off")")
        case "workDelete":
            guard let id = object["id"] as? Int, id > 0 else { return bad }
            let removed = store.deleteLesson(id: id)
            return ok(["removed": removed], audit: removed ? "work memory: deleted one lesson" : nil)
        case "workClear":
            guard object["confirm"] as? String == ArisMemoryRoute.clearWord else { return bad }
            return store.deleteAll() ? ok(["cleared": true], audit: "work memory: cleared all") : (500, Data("{}".utf8), "work memory: clear failed")
        default:
            return nil
        }
    }

    private static func ok(_ object: [String: Any], audit: String?) -> (status: Int, body: Data, audit: String?) {
        (200, (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), audit)
    }

    private static let bad: (status: Int, body: Data, audit: String?) = (400, Data("{}".utf8), nil)
}
