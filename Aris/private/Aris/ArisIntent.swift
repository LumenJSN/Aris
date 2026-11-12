//
//  ArisIntent.swift
//  Aris
//
//  What a spoken command means. Everyday requests (music, volume, brightness,
//  opening an app, a few windows in a grid, the time and date) are handled on the
//  Mac right away; anything else is a question for Claude.
//

import Foundation

enum ArisIntent: Equatable {
    enum Media: Equatable {
        case play, pause, next, previous

        /// What Aris says after the player answered: done, or plainly not (never "틀게요" when it failed).
        func reply(done: Bool, korean: Bool) -> String {
            if done { return ArisIntent.media(self).acknowledgement(korean: korean) ?? "" }
            switch self {
            case .play: return korean ? "음악을 틀지 못했어요." : "Couldn't play the music."
            case .pause: return korean ? "음악을 멈추지 못했어요." : "Couldn't pause the music."
            case .next: return korean ? "다음 곡으로 넘기지 못했어요." : "Couldn't skip to the next song."
            case .previous: return korean ? "이전 곡으로 가지 못했어요." : "Couldn't go back to the previous song."
            }
        }
    }
    enum Level: Equatable { case up, down, set(Int), mute }

    /// The app's name as macOS knows it (e.g. "Safari"), not yet checked to exist.
    case openApp(String)
    /// `count` new windows of the app, laid out in a grid ("엑셀 4개 켜서 4등분").
    case arrange(app: String, count: Int)
    case media(Media)
    case volume(Level)
    case brightness(Level)
    case tellTime
    case tellDate
    /// The morning brief, again (ArisBrief).
    case brief
    /// "오늘 정리해 줘", "wrap up my day": the day-end summary (ArisDayEnd).
    case dayEnd
    /// "할 일 추가해 우유 사기": onto the to-do list (ArisTodoList).
    case addTodo(String)
    /// "우유 사기 다 했어": ticked off, if it names one item (else it's a question for the AI).
    case finishTodo(String)
    /// "할 일 뭐 있어": read out from the list itself.
    case listTodos
    /// "타이머 25분", "25분 집중", "뽀모도로": a countdown in the notch (ArisTimerModel); `focus` for a focus session.
    case timer(seconds: Int, focus: Bool)
    /// "뽀모도로": focus and breaks in turn until cancelled.
    case pomodoro
    case cancelTimer
    case pauseTimer
    case resumeTimer
    /// "타이머 5분 추가".
    case addTime(Int)
    /// "얼마나 남았어": answered from the timer itself.
    case timerLeft
    /// "방금 거 취소해", "되돌려", "undo that": the last thing Aris did that can be undone (ArisActivity).
    case undo
    /// "읽어줘", "다 읽어줘", "read it": the last answer read whole (only its short part was said).
    case readAgain
    /// "방금 답을 … orlando.txt 파일로 저장해 줘": the last answer written by Aris on the user's card (ArisSaveAnswer).
    case saveAnswer(ArisSaveAnswer)
    /// "지금 무슨 노래야?", "what's playing": answered from what is playing now, never the AI.
    case whatsPlaying
    /// "조용히 해 줘", "음소거" (true) or "이제 말해도 돼", "unmute" (false): Aris's own voice and chimes (ArisQuietPhrase).
    case arisMute(Bool)
    /// "방해 금지 시간을 밤 11시부터 아침 8시로 바꿔 줘", "set quiet hours from 10 pm to 7 am": the night hours of quiet
    /// time, as they are stored ("23-8", "22:30-6:00", "off": ArisQuietHoursAsk).
    case quietHours(String)
    case ask(String)

    /// The words as the matchers read them: lowercased, end marks off, "좀" (please) dropped, numbers as digits
    /// ("오십", "five minutes"), a curly apostrophe as a plain one ("what’s the time").
    static func phrase(of spoken: String) -> String {
        let plain = spoken.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: CharacterSet(charactersIn: ".!?。 "))
        return ArisEnglishAsk.digits(ArisNumbers.normalize(plain.replacingOccurrences(of: "좀 ", with: "")))
    }

    /// The time of `date` as Korean says it (ArisKoreanClock): "밤 12시 32분", "저녁 8시 41분".
    static func koreanClock(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ArisKoreanClock.phrase(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// Only reads, never acts: these may answer a question.
    var isReadOnly: Bool {
        switch self {
        case .tellTime, .tellDate, .brief, .dayEnd, .listTodos, .readAgain, .timerLeft, .whatsPlaying, .ask: return true
        default: return false
        }
    }

    /// The one guard every local action passes, whoever picked it (this parser, the router's second guess): a question,
    /// a request for advice or a "don't" is the AI's, never a local action (QA live on b9c766bc: "5분 타이머 맞춰야 할까?"
    /// set a timer through the router).
    static func guarded(_ intent: ArisIntent, said: String) -> ArisIntent {
        let spoken = said.trimmingCharacters(in: .whitespacesAndNewlines)
        let phrase = phrase(of: spoken)
        // A sentence naming a routine ("퇴근 루틴 만들어 줘: 음악 꺼 줘") is the agent's, whole: never a local act on a word in it.
        if ArisRoutineWords.mentions(spoken) { if case .ask = intent { return intent } else { return .ask(spoken) } }
        // A request that goes on after this act ("메모 앱 열고 어제 회의 내용 정리해 줘") is the AI's, whole (audit intent-1).
        if intent.isOneAct, ArisIntentScope.goesOn(phrase) { return .ask(spoken) }
        guard !intent.isReadOnly, holdsBack(spoken, phrase: phrase) else { return intent.resolved(said: spoken) }
        return .ask(spoken)
    }

    /// What this act is done to, when it takes words: a to-do's item, the app to open.
    var argument: String? {
        switch self {
        case .addTodo(let item), .finishTodo(let item): return item
        case .openApp(let name): return name
        default: return nil
        }
    }

    /// An act on something that only points back ("add that to my to-dos", "그거 할 일에 추가해 줘", "open it") is the
    /// AI's, whole: it has the conversation the word points into (ArisPointsBack; third VM run, bug A).
    func resolved(said spoken: String) -> ArisIntent {
        guard let argument, ArisPointsBack.only(argument) else { return self }
        return .ask(spoken)
    }

    /// One act and nothing after it: opening an app, the music, the volume, the brightness, the timer. (Laying windows
    /// out, a to-do's own words and a save carry an "and" of their own.)
    var isOneAct: Bool {
        switch self {
        case .openApp, .media, .volume, .brightness, .timer, .pomodoro, .cancelTimer, .pauseTimer, .resumeTimer, .addTime, .arisMute: return true
        case .quietHours: return true
        default: return false
        }
    }

    static func parse(_ text: String) -> ArisIntent {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "좀" (please, a bit) sits anywhere: "노래 좀 꺼줘" is "노래 꺼줘".
        let phrase = phrase(of: spoken)
        let found = match(spoken, phrase: phrase)
        // Cut down to its first act, the rest of the request would never be done (audit intent-1).
        return found.isOneAct && ArisIntentScope.goesOn(phrase) ? .ask(spoken) : found.resolved(said: spoken)
    }

    private static func match(_ spoken: String, phrase: String) -> ArisIntent {
        if phrase.isEmpty { return .ask("") }
        if asksWhatsPlaying(phrase) { return .whatsPlaying }
        // "매일 저녁 8시에 할 일 알려 줘": a schedule for the brain's 예약 추가 card, before any local matcher (QA BUG-45).
        if isRecurring(phrase) { return .ask(spoken) }
        // A routine ("출근 루틴 해 줘", "… 루틴 만들어 줘: 음악 꺼 줘"): the agent's, before any local matcher takes a word of it.
        if ArisRoutineWords.mentions(spoken) { return .ask(spoken) }
        if asksTime(phrase) { return .tellTime }
        if asksDate(phrase) { return .tellDate }
        if asksForBrief(phrase) { return .brief }
        if ArisDayEndAsk.asks(phrase) { return .dayEnd }
        // One guard before every local action (QA BUG-58 audit: "5분 타이머 맞춰야 할까?" set a real timer, "할 일 추가하지
        // 마" added one): a question, a request for advice or a "don't" goes to the AI; only the read-only answers below
        // may still answer it.
        if holdsBack(spoken, phrase: phrase) {
            if asksForTodos(phrase) { return .listTodos }
            if asksToReadAgain(phrase) { return .readAgain }
            if case .timerLeft? = timer(in: phrase) { return .timerLeft }
            return .ask(spoken)
        }
        if let item = todoToAdd(spoken) { return item.isEmpty ? .ask(spoken) : .addTodo(item) }
        if let item = todoDone(spoken) { return .finishTodo(item) }
        if asksForTodos(phrase) { return .listTodos }
        if asksToReadAgain(phrase) { return .readAgain }
        // Before the question words: it names the last answer and a save, never a brain's turn (QA BUG-20b).
        if let save = ArisSaveAnswer.parse(spoken) { return .saveAnswer(save) }
        // "조용히 해 줘", "음소거", "이제 말해도 돼": Aris's own mute, before the Mac's volume takes "음소거" (ArisQuietPhrase).
        // "방해 금지 시간을 밤 11시부터 아침 8시로": quiet hours, before the mute and the timer take its words.
        if let hours = ArisQuietHoursAsk.parse(phrase) { return .quietHours(hours) }
        if let mute = ArisQuietPhrase.parse(phrase) { return .arisMute(mute) }
        // "how much time is left on the timer" asks, and is answered from the timer itself (read-only, as with a "?").
        if case .timerLeft? = timer(in: phrase) { return .timerLeft }
        // "볼륨 크게 들으면 귀에 안 좋아?" names the volume but asks about it.
        if contains(phrase, any: questionWords) { return .ask(spoken) }
        if let timer = timer(in: phrase) { return timer }
        if asksUndo(phrase) { return .undo }
        // "엑셀 4개 켜서 4등분" also has 켜 and 열어: windows in a grid, or (unclear, too many) a question.
        if contains(phrase, any: splitWords) {
            return arrangement(in: phrase).map { .arrange(app: $0.app, count: $0.count) } ?? .ask(spoken)
        }
        // "open 4 excel windows in a grid": the English of the same.
        if let grid = ArisEnglishAsk.arrangement(phrase) {
            return (1...maxWindows).contains(grid.count) ? .arrange(app: canonical(grid.app), count: grid.count) : .ask(spoken)
        }
        if let media = media(in: phrase) {
            // "YouTube에서 아이유 노래 틀어줘" names what to play: the AI finds it, the play button would just resume.
            return media == .play && playsSomethingNamed(phrase) ? .ask(spoken) : .media(media)
        }
        if let level = level(in: phrase, subjects: volumeWords, up: volumeUp, down: volumeDown, mute: true) { return .volume(level) }
        if let level = level(in: phrase, subjects: brightnessWords, up: brightnessUp, down: brightnessDown, mute: false) { return .brightness(level) }
        // The sound and the screen without the words "volume" or "brightness": only as a whole sentence.
        if let level = ArisEnglishAsk.soundLevel(phrase) { return .volume(level) }
        if let level = ArisEnglishAsk.screenLevel(phrase) ?? koreanScreenLevel(phrase) { return .brightness(level) }
        if let app = appName(in: phrase) { return .openApp(app) }
        return .ask(spoken)
    }

    /// "할 일 뭐 남았어", "할 일 보여 줘": the list, read-only.
    private static func asksForTodos(_ phrase: String) -> Bool {
        contains(phrase, any: todoWords) && contains(phrase, any: ["뭐", "알려", "보여", "읽어", "있어", "남았", "목록", "what", "what's", "show", "read", "list", "tell",
                                                                    "any", "anything", "left", "remaining", "have"])
            // Only the question: "오늘 할 일 목록 메일로 보내 줘" asks for more than a reading (audit intent-2).
            && ArisIntentScope.isOnly(phrase, about: todoWords, with: todoSmall)
    }

    private static let todoWords = ["할 일", "할일", "투두", "미리 알림", "미리알림", "리마인더", "todo", "to-do", "todos", "to-dos", "to do list", "reminders",
                                    "what do i have to do", "what do i need to do"]
    private static let todoSmall = sentenceSmall + ["오늘", "오늘의", "내일", "이번", "주", "내", "나", "남은", "남았", "남았어", "남았는지", "남았지", "남았니", "남았나",
                                                    "뭐", "뭐가", "뭐지", "있어", "있는지", "있나", "있니", "있지", "보여", "읽어", "목록", "리스트", "을", "를", "에", "다", "전부",
                                                    "what", "what's", "whats", "is", "are", "on", "my", "the", "list", "show", "me", "read", "left", "today",
                                                    "do", "i", "have", "for", "tell", "any", "there", "all", "of", "anything", "remaining", "still", "open",
                                                    "out", "loud", "got", "i've", "can", "could", "you", "in", "items"]
    /// Small words any of these questions may carry: Aris's name, "지금", "알려 줘", a sentence ending.
    private static let sentenceSmall = ["아리스", "aris", "지금", "현재", "야", "이야", "예요", "이에요", "에요", "지", "이지", "죠", "이죠", "인지", "니", "이니", "냐", "이냐",
                                        "인가", "인가요", "알려", "말해", "줘", "주세요", "줄래", "좀", "요", "이", "가", "은", "는", "now", "right", "please", "hey"]

    /// A question, a request for advice, or a "don't": never taken as a local action (QA BUG-58 audit).
    static let negations = ["지 마", "지마", "지 말", "지말", "말고", "말아", "안 돼", "안돼", "하지 않", "don't", "dont", "do not", "never", "shouldn't", "no need to"]
    static let asking = ["할까", "해야 돼", "해야돼", "해야 할까", "해야할까", "해야 하나", "해야하나", "하는 게 좋", "하는게 좋", "는 게 나을", "는게 나을",
                         "추천", "좋을까", "만한", "어떨까", "어때", "should i", "should we", "shall i", "would it be better", "is it better", "recommend", "suggest",
                         "do i need to", "do i have to", "is it ok", "is it okay", "how do i", "how can i", "how to", "what if", "good idea", "do you think",
                         "wondering", "whether"]
    /// "볼륨 좀 올려줄래?", "다음 곡 틀어줄래?", "can you …?": a polite request, not a question.
    private static let politeRequest = #"(줄래|줄래요|주실래요|주시겠어요|주실 수 있어요|줄 수 있어|줄수있어|해 줄래|해줄래)$|^(can|could|will|would) you\b"#
    static func holdsBack(_ spoken: String, phrase: String) -> Bool {
        if contains(phrase, any: negations) || contains(phrase, any: asking) { return true }
        // "did you set a timer", "is the volume up": a question said without its mark.
        if ArisEnglishAsk.opensAsQuestion(phrase) { return true }
        guard spoken.contains("?") || spoken.contains("？") else { return false }
        return phrase.range(of: politeRequest, options: .regularExpression) == nil
    }

    // MARK: - Undo

    /// Said alone, these can only mean the last thing.
    private static let bareUndo: Set = ["되돌려", "되돌려줘", "되돌려 줘", "되돌려 주세요", "되돌려주세요",
                                        "undo", "undo that", "undo it", "undo this", "undo the last thing", "undo my last action", "undo the last one",
                                        "undo last", "take that back", "take it back", "revert that", "revert it"]

    /// "방금 거 / 방금 한 거 / 방금 그거" + 취소 or 되돌려, "되돌려" alone, "undo that": the last thing Aris did. Anything
    /// that names what to cancel ("방금 보낸 메일 취소해", "방금 만든 일정 취소해") is a request to the AI, and the timer
    /// is the timer (checked first).
    private static func asksUndo(_ phrase: String) -> Bool {
        // "취소하지 마", "되돌리지 마", "don't undo": the opposite.
        if contains(phrase, any: ["지 마", "지마", "지 말", "지말", "말아", "말고", "안 돼", "안돼", "지 않", "지않", "안 해", "안해", "필요 없", "필요없", "don't", "do not", "never"]) { return false }
        if bareUndo.contains(phrase) || bareUndo.contains(ArisEnglishAsk.core(phrase)) { return true }
        // 되돌려, 되돌리기, 실행 취소: undo, unless it's about a song (QA BUG-42: "방금 만든 거 되돌려 줘" went to the previous track).
        if saysUndo(phrase) { return true }
        // Only a bare "방금 거", "방금 한 거", "그거": the last thing. A named one ("방금 예약한 거", "방금 추가한 거") may
        // not be the last thing Aris did: the AI does it (security review of 4d40bb80).
        let last = #"(?:방금\s*(?:한\s*)?(?:그\s*)?|^그\s*)[거꺼](?:를|도|는)?(?![가-힣])"#
        guard phrase.range(of: last, options: .regularExpression) != nil else { return false }
        return contains(phrase, any: ["취소", "되돌"])
    }

    // MARK: - What's playing

    private static let songWords = ["무슨 노래", "무슨 곡", "무슨 음악", "노래 제목", "곡 제목", "이 노래", "이 곡", "나오는 노래", "나오는 곡",
                                    "재생 중인 노래", "재생중인 노래", "재생 중인 곡", "듣고 있는 노래", "듣는 노래"]
    private static let songAsks = ["지금", "뭐", "무슨", "제목", "알려"]
    /// Words that make it a request about music, not a question about the song in the ears.
    private static let songNot = ["틀어", "꺼", "추천", "좋아", "찾아", "가사", "유튜브", "youtube", "만들", "불러", "다운"]
    private static let englishSong = #"^(?:hey\s+)?(?:what'?s|what is|which song is|what song is)\s+(?:playing|this song|this|the song|on)(?:\s+(?:now|right now|playing|called))*$|^what song(?: is)?(?: this| playing| on)?(?: now| right now)?$|^what am i listening to(?: right now| now)?$"#

    /// "지금 무슨 노래야?", "이 노래 뭐야", "지금 나오는 곡 제목 알려줘", "what's playing", "what song is this".
    static func asksWhatsPlaying(_ phrase: String) -> Bool {
        if phrase.range(of: englishSong, options: .regularExpression) != nil { return true }
        return contains(phrase, any: songWords) && contains(phrase, any: songAsks) && !contains(phrase, any: songNot)
            // Only the question: "지금 듣는 노래 플레이리스트에 추가해 줘" asks for more than its name (audit intent-2).
            && ArisIntentScope.isOnly(phrase, about: songWords, with: songSmall)
    }

    private static let songSmall = sentenceSmall + ["뭐", "뭐야", "뭐지", "뭔지", "무슨", "제목", "이거", "거", "거야", "꺼야", "노래", "곡", "음악", "누구", "누구야", "가수"]

    /// What Aris says about the song in the ears: its title and artist, whether it is playing or paused.
    static func nowPlayingLine(title: String, artist: String, playing: Bool, korean: Bool) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines), artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return korean ? "지금 재생 중인 음악이 없어요." : "Nothing is playing right now." }
        if korean {
            let who = artist.isEmpty ? "" : ", \(artist) 노래예요"
            let lead = playing ? "지금 나오는 곡은" : "멈춰 있는 곡은"
            return artist.isEmpty ? "\(lead) ‘\(title)’ 곡이에요." : "\(lead) ‘\(title)’\(who)."
        }
        let by = artist.isEmpty ? "" : " by \(artist)"
        return playing ? "Playing “\(title)”\(by)." : "Paused: “\(title)”\(by)."
    }

    // MARK: - Recurring requests

    static func isRecurring(_ text: String) -> Bool { ArisOwnData.isRecurring(text) }

    private static let musicNouns = ["곡", "노래", "음악", "track", "song", "music"]
    /// 되돌려 / 되돌리기 / 실행 취소 alone ("되돌려 줘", "실행 취소해"), or after "방금 <one word> 거" ("방금 만든 거 되돌려 줘").
    /// Anything longer names something else to change ("이 문장 원래대로 되돌려 써 줘") and is a request to the AI: an undo
    /// runs at once, so it is never guessed from a word inside a longer request.
    private static let undoAlone = #"^(?:방금\s*(?:\S+\s+)?[거꺼](?:를|을|는)?\s*)?(?:되돌려|되돌리기|되돌리자|실행\s*취소)(?:\s*(?:해|줘|해\s*줘|해\s*주세요|주세요|할래|하자))*[.!~ ]*$"#

    /// The words ask to undo the last thing, and name no song or music (QA BUG-42).
    static func saysUndo(_ text: String) -> Bool {
        let phrase = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.range(of: undoAlone, options: .regularExpression) != nil && !contains(phrase, any: musicNouns)
    }

    // MARK: - Reading the last answer

    /// "읽어줘", "다 읽어 줘", "전부 읽어", "끝까지 읽어줄래", "그거 다시 읽어 줘", "read it", "read it all", "read the whole
    /// thing": only words that can mean nothing but the last answer. Anything naming something else to read ("이 메일
    /// 읽어줘") is a request to the AI.
    static func asksToReadAgain(_ phrase: String) -> Bool {
        let korean = #"^(?:(?:그거|그것|그걸|그것도|방금\s*거|방금\s*꺼|방금\s*답|답|답변|대답|그\s*답|그\s*답변|나머지|나머지도|전체를|전부를)\s*)?(?:(?:다|전부|전체|전체를|끝까지|다시|마저|처음부터)\s*)*(?:다\s*)?읽어\s*(?:줘|줘요|줄래|줄래요|주세요|봐|봐줘|봐 줘)?$"#
        let english = #"^(?:read|read out)\s+(?:it|it all|all of it|everything|the whole thing|the whole answer|the full answer|the answer|your answer|the rest)(?:\s+(?:out|all|to me|out loud|aloud|again))*$|^(?:read|read out)\s+that\s+(?:again|once more)(?:\s+(?:out loud|aloud|to me))?$|^(?:say|repeat)\s+(?:that|it|the answer|your answer)(?:\s+(?:again|once more|one more time))?$"#
        return phrase.range(of: korean, options: .regularExpression) != nil || ArisEnglishAsk.core(phrase).range(of: english, options: .regularExpression) != nil
    }

    // MARK: - Vocabulary

    // Speech recognition often hears 곡 as 꼭 or 거.
    private static let nextWords = ["다음 곡", "다음곡", "다음 꼭", "다음꼭", "다음 거", "다음거", "다음 노래",
                                    "넘겨", "스킵", "next song", "next track", "skip"]
    private static let previousWords = ["이전 곡", "이전곡", "이전 노래", "앞 곡", "previous song", "previous track", "last song", "go back a song",
                                        "go back one song", "go back a track", "the song before"]
    private static let pauseWords = ["멈춰", "일시정지", "일시 정지", "노래 꺼", "음악 꺼", "pause", "stop the music", "stop music", "stop playing",
                                     "stop the song", "stop the track", "stop playback"]
    private static let playWords = ["노래 틀어", "음악 틀어", "재생", "play music", "resume", "play", "unpause", "continue the music", "continue playing"]

    private static let volumeWords = ["볼륨", "소리", "음량", "volume", "louder", "quieter", "mute", "음소거"]
    private static let volumeUp = ["키워", "올려", "크게", "높여", "up", "louder", "raise", "increase"]
    private static let volumeDown = ["줄여", "내려", "낮춰", "작게", "down", "lower", "quieter", "decrease"]

    private static let brightnessWords = ["밝기", "brightness", "brighter", "dimmer", "darker"]
    private static let brightnessUp = ["올려", "밝게", "높여", "up", "brighter", "increase", "raise"]
    private static let brightnessDown = ["낮춰", "내려", "어둡게", "줄여", "down", "dimmer", "darker", "decrease", "lower"]

    // Only "now" and "today": "회의 몇 시야" or "내일 무슨 요일" are questions for Claude.
    private static let timeWords = ["지금 몇 시", "지금 몇시", "what time is it", "what's the time", "whats the time", "what is the time", "what time", "the time",
                                    "current time"]
    /// What an English question about the time may carry besides ("tell me the time", "do you have the time").
    private static let timeSmall = ["쯤", "됐어", "됐지", "됐나", "tell", "me", "do", "you", "have", "know", "got", "can", "could", "give", "it", "is", "what's", "the"]
    private static let bareTimeQuestions: Set = ["몇 시야", "몇시야", "몇 시", "몇시"]
    private static let dateWords = ["오늘 며칠", "오늘 몇 일", "오늘 몇일", "오늘이 며칠", "오늘 무슨 요일", "오늘 날짜",
                                    "what day is it", "what's the date", "what is the date", "today's date", "todays date", "the date", "what day is today",
                                    "what's the day", "which day is it", "day of the week"]
    private static let dateSmall = ["뭐", "뭐야", "today", "tell", "me", "what's", "whats", "what", "is", "it", "the", "do", "you", "know", "can", "could", "give"]

    /// Words that make a sentence a question even when it names a command.
    private static let questionWords = ["어디", "뭐가", "뭐야", "무엇", "왜", "어떻게", "어때", "안 좋", "괜찮",
                                        "where", "what", "why", "how", "which"]

    private static let openVerbs = ["열어", "켜", "실행", "띄워"]

    /// Words that ask for windows side by side or in a grid.
    private static let splitWords = ["등분", "반반", "나란히", "바둑판", "분할"]
    /// At most this many windows in one go (as aris-tools `new` allows).
    static let maxWindows = 9

    /// Korean (and casual) names for common apps.
    static let appAliases: [String: String] = [
        "사파리": "Safari", "크롬": "Google Chrome", "chrome": "Google Chrome", "스포티파이": "Spotify",
        "음악": "Music", "애플 뮤직": "Music", "메모": "Notes", "캘린더": "Calendar", "달력": "Calendar",
        "터미널": "Terminal", "워프": "Warp", "파인더": "Finder", "메일": "Mail", "메시지": "Messages",
        "카톡": "KakaoTalk", "카카오톡": "KakaoTalk", "디스코드": "Discord", "슬랙": "Slack", "노션": "Notion",
        "설정": "System Settings", "시스템 설정": "System Settings", "엑스코드": "Xcode", "피그마": "Figma",
        "브이에스코드": "Visual Studio Code", "vs code": "Visual Studio Code", "vscode": "Visual Studio Code",
        "사진": "Photos", "미리보기": "Preview", "계산기": "Calculator", "앱스토어": "App Store",
        "엑셀": "Microsoft Excel", "excel": "Microsoft Excel", "워드": "Microsoft Word", "word": "Microsoft Word",
        "파워포인트": "Microsoft PowerPoint", "피피티": "Microsoft PowerPoint", "powerpoint": "Microsoft PowerPoint",
        "텍스트 편집": "TextEdit", "텍스트 편집기": "TextEdit", "텍스트편집기": "TextEdit", "textedit": "TextEdit", "지도": "Maps",
        "미리 보기": "Preview", "미리 알림": "Reminders", "미리알림": "Reminders", "연락처": "Contacts", "단축어": "Shortcuts",
        "스티커": "Stickies", "키노트": "Keynote", "넘버스": "Numbers", "페이지스": "Pages",
        "settings": "System Settings", "system preferences": "System Settings", "imessage": "Messages", "facetime": "FaceTime",
        "kakaotalk": "KakaoTalk", "quicktime": "QuickTime Player", "garageband": "GarageBand", "iterm": "iTerm",
    ]

    /// How the Mac shows Apple's apps in Korean (the reply names the app as the user sees it: 텍스트 편집기, never "Textedit").
    static let koreanNames: [String: String] = [
        "TextEdit": "텍스트 편집기", "Notes": "메모", "Preview": "미리보기", "Calculator": "계산기", "Calendar": "캘린더", "Maps": "지도",
        "Photos": "사진", "Messages": "메시지", "Music": "음악", "Reminders": "미리 알림", "Contacts": "연락처",
        "System Settings": "시스템 설정", "Terminal": "터미널", "Mail": "메일", "Shortcuts": "단축어", "Stickies": "스티커",
    ]

    // MARK: - Matching

    /// Words that say "play" without naming anything ("노래 다시 틀어줘", "play music").
    private static let playFiller = ["아리스", "aris", "좀", "줘", "줄래", "주세요", "주라", "다시", "계속", "그냥", "음악", "노래", "곡", "틀어", "재생",
                                     "해", "하자", "play", "music", "some", "resume", "please", "the", "again", "unpause", "continue", "playing"]

    /// A request to play something in particular (a song, an artist, a source): more than the play words.
    static func playsSomethingNamed(_ text: String) -> Bool {
        let phrase = text.lowercased()
        guard contains(phrase, any: playWords) || phrase.contains("틀어") else { return false }
        if contains(phrase, any: ["유튜브", "youtube", "스포티파이", "spotify", "멜론", "애플 뮤직", "apple music", "에서 "]) { return true }
        var rest = phrase
        for word in playFiller.sorted(by: { $0.count > $1.count }) { rest = rest.replacingOccurrences(of: word, with: " ") }
        return rest.filter { $0.isLetter || $0.isNumber }.count >= 2
    }

    private static func media(in phrase: String) -> Media? {
        // Said alone ("next", "stop" as 멈춰), with or without a please.
        let bare = ArisEnglishAsk.core(phrase)
        if phrase == "다음" || bare == "next" || contains(phrase, any: nextWords) { return .next }
        if bare == "previous" || contains(phrase, any: previousWords) { return .previous }
        if bare == "stop" || bare == "stop it" || contains(phrase, any: pauseWords) { return .pause }
        if contains(phrase, any: playWords) { return .play }
        return nil
    }

    private static func level(in phrase: String, subjects: [String], up: [String], down: [String], mute: Bool) -> Level? {
        guard contains(phrase, any: subjects) else { return nil }
        if let number = firstNumber(in: phrase) { return .set(min(100, max(0, number))) }
        if contains(phrase, any: ["최대", "max", "maximum", "full"]) { return .set(100) }
        if contains(phrase, any: ["최소", "min", "minimum"]) { return .set(0) }
        if mute && contains(phrase, any: ["음소거", "mute", "소리 꺼", "볼륨 꺼"]) { return .mute }
        if contains(phrase, any: up) { return .up }
        if contains(phrase, any: down) { return .down }
        return nil
    }

    private static func asksTime(_ phrase: String) -> Bool {
        // Only the question: "지금 몇 시인지 슬랙에 올려 줘" asks for more than the time (audit intent-2).
        if contains(phrase, any: timeWords), ArisIntentScope.isOnly(phrase, about: timeWords, with: sentenceSmall + timeSmall) { return true }
        let bare = phrase.replacingOccurrences(of: "^(아리스|aris)[ ,]*", with: "", options: .regularExpression)
        return bareTimeQuestions.contains(bare)
    }

    /// "오늘 며칠이야", "오늘 날짜 알려 줘", "what's the date today": the date, and nothing else asked ("오늘 날짜로 폴더 하나
    /// 만들어 줘" is a request that only names it: audit intent-2).
    private static func asksDate(_ phrase: String) -> Bool {
        ArisIntentScope.isOnly(phrase, about: dateWords, with: sentenceSmall + dateSmall)
    }

    /// "브리핑 해줘", "오늘 브리핑", "아침 브리핑 보여 줘": the brief itself ("내일 회의 브리핑 자료 만들어 줘" and "이 문서
    /// 브리핑해 줘" ask the AI for something else: audit intent-2).
    private static func asksForBrief(_ phrase: String) -> Bool {
        ArisIntentScope.isOnly(phrase, about: ["브리핑", "briefing", "brief"],
                               with: ["아리스", "aris", "오늘", "오늘의", "아침", "모닝", "해", "줘", "주세요", "줄래", "보여", "들려", "알려", "다시", "한번", "한", "번",
                                      "시작", "좀", "부탁", "요", "morning", "the", "my", "today's", "todays", "daily", "give", "me", "show", "please",
                                      "start", "again", "a", "hey"])
    }

    private static func appName(in phrase: String) -> String? {
        // "open safari", "can you launch the calculator please": only an app's name after the verb (ArisEnglishAsk).
        if let name = ArisEnglishAsk.appToOpen(phrase) { return canonical(name) }
        guard let verb = openVerbs.compactMap({ phrase.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        // Only the request's ending may follow the verb: "카톡 켜서 엄마한테 …" goes on, so it is not "open KakaoTalk".
        guard ArisIntentScope.isRequestEnding(String(phrase[verb.upperBound...])) else { return nil }
        let name = phrase[..<verb.lowerBound]
            .replacingOccurrences(of: "좀", with: "")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : canonical(name)
    }

    /// The app (the words before the count) and how many windows: "N개", else "N등분", else 2 for 반반.
    private static func arrangement(in phrase: String) -> (app: String, count: Int)? {
        let count = number(in: phrase, before: "개") ?? number(in: phrase, before: "등분")
            ?? (contains(phrase, any: ["반반"]) ? 2 : nil)
        guard let count, (1...maxWindows).contains(count) else { return nil }
        let stops = ["창", "새"]
        let name = phrase.split(separator: " ")
            .prefix { word in !word.contains(where: \.isNumber) && !stops.contains(String(word))
                && !contains(String(word), any: splitWords + openVerbs) }
            .joined(separator: " ")
        let bare = name.replacingOccurrences(of: "(을|를)$", with: "", options: .regularExpression)
        return bare.isEmpty ? nil : (canonical(bare), count)
    }

    private static let timerWords = ["타이머", "뽀모도로", "집중", "timer", "pomodoro", "focus"]
    /// The timer by its own name (never bare 집중 or "focus", which are also a mode of the Mac and an everyday word).
    private static let timerNames = ["타이머", "뽀모도로", "timer", "pomodoro"]
    static let longestTimer = 24 * 3_600

    /// A timer to start or cancel; nil when the words aren't about one (or ask about one: "얼마나 남았어").
    private static func timer(in phrase: String) -> ArisIntent? {
        guard contains(phrase, any: timerWords) else { return nil }
        // A running timer is asked about or changed by its name: "집중 모드 꺼 줘" is the Mac's Focus, and "what's left to
        // focus on" no timer at all (audit intent-2). "집중 몇 분 남았어" still asks about the focus session.
        let named = contains(phrase, any: timerNames)
        if named || phrase.contains("집중"), !phrase.contains("모드"), contains(phrase, any: ["남았", "얼마", "left", "remaining", "how much longer"]) { return .timerLeft }
        if named {
            if contains(phrase, any: ["취소", "꺼", "그만", "stop", "cancel", "turn off", "end the timer", "end timer", "clear the timer", "dismiss the timer",
                                      "kill the timer", "get rid of the timer"]) { return .cancelTimer }
            if contains(phrase, any: ["멈춰", "일시정지", "일시 정지", "잠깐", "pause", "hold the timer", "freeze the timer"]) { return .pauseTimer }
            if contains(phrase, any: ["추가", "연장", "늘려", "더 해", "add", "more", "extend", "extra", "another"]) {
                return seconds(in: phrase).map { .addTime($0) }
            }
            // With a length it is a new timer ("타이머 다시 10분 맞춰 줘"); only without one do 다시 and 계속 resume.
            if seconds(in: phrase) == nil, contains(phrase, any: ["다시", "계속", "재개", "resume", "continue", "unpause", "keep going"]) { return .resumeTimer }
        } else if contains(phrase, any: ["취소", "꺼", "그만", "멈춰", "일시정지", "일시 정지", "모드", "stop", "cancel", "pause", "mode", "left"]) {
            return nil
        }
        if contains(phrase, any: ["뽀모도로", "pomodoro"]) && seconds(in: phrase) == nil { return .pomodoro }
        let focus = contains(phrase, any: ["집중", "뽀모도로", "pomodoro", "focus"])
        guard let seconds = seconds(in: phrase) else { return nil }
        return seconds <= longestTimer ? .timer(seconds: seconds, focus: focus) : nil
    }

    /// "1시간 30분", "30초", "5 minutes" in seconds; nil when no length is said.
    private static func seconds(in phrase: String) -> Int? {
        // "5 more minutes" is five minutes too.
        let units: [(String, Int)] = [("시간", 3_600), ("분", 60), ("초", 1), (#"(?:more\s+)?(?:hours?|hrs?)\b"#, 3_600),
                                      (#"(?:more\s+)?(?:minutes?|mins?)\b"#, 60), (#"(?:more\s+)?(?:seconds?|secs?)\b"#, 1)]
        let seconds = units.reduce(0) { total, unit in
            total + (phrase.range(of: "[0-9]+(?=\\s*\(unit.0))", options: .regularExpression).flatMap { Int(phrase[$0]) } ?? 0) * unit.1
        }
        return seconds > 0 ? seconds : nil
    }

    /// "1분 30초", "25분", "1시간".
    static func duration(_ seconds: Int) -> String {
        let parts = [(seconds / 3_600, "시간"), (seconds % 3_600 / 60, "분"), (seconds % 60, "초")].filter { $0.0 > 0 }
        return parts.map { "\($0.0)\($0.1)" }.joined(separator: " ")
    }

    /// Words that undo, cancel or take away, say no, or ask for advice: never a local add (QA BUG-58: "방금 추가한 할 일
    /// 되돌려 줘", "할 일 추가하지 마" and "할 일에 추가할 만한 거 추천해 줘" each added a to-do). Such words go to undo or
    /// to the AI.
    static let notAnAdd = ["되돌", "취소", "지워", "지우", "삭제", "빼", "없애", "제거", "지 마", "지마", "지 말", "지말", "말고", "말아", "안 돼", "안돼",
                           "추천", "좋을까", "만한", "어떤", "뭐가", "뭘", "무엇", "할까", "?",
                           "undo", "cancel", "remove", "delete", "don't", "do not", "should i", "recommend", "suggest"]

    /// The words around "할 일 추가해" / "할 일에 …넣어줘" / "… 할 일에 추가해줘": the item; nil when it isn't that, "" when
    /// nothing's named. Only a plain imperative add of something named: a past-tense modifier ("추가한 할 일", "넣은 거")
    /// or anything in `notAnAdd` isn't one.
    private static func todoToAdd(_ spoken: String) -> String? {
        koreanTodoToAdd(spoken) ?? ArisEnglishAsk.todoToAdd(spoken)
    }

    private static func koreanTodoToAdd(_ spoken: String) -> String? {
        let noun = #"(할\s?일|투두|to-?do|미리\s?알림|리마인더)\s*(목록|리스트)?\s*(에다가|에다|에|으로|로)?"#
        // A present imperative only: "추가해 줘", "넣어", "적어 둬", or a bare "추가" that ends the request (never 추가한, 추가할).
        let verb = #"(추가해\s?줘|추가해줄래|추가해\s?주세요|추가해\s?둬|추가해|추가(?![가-힣])|등록해\s?줘|등록해\s?주세요|등록해|등록(?![가-힣])|넣어\s?줘|넣어줄래|넣어\s?주세요|넣어\s?둬|넣어|넣기(?![가-힣])|적어\s?줘|적어줄래|적어\s?주세요|적어\s?둬|적어)"#
        let lowered = spoken.lowercased()
        guard !contains(lowered, any: notAnAdd) else { return nil }
        guard let nounRange = spoken.range(of: noun, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var rest = spoken
        rest.removeSubrange(nounRange)
        guard let verbRange = rest.range(of: verb, options: .regularExpression) else { return nil }
        rest.removeSubrange(verbRange)
        return rest.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// "<item> 다 했어 / 끝냈어 / 완료했어": the item; nil when nothing comes before.
    private static func todoDone(_ spoken: String) -> String? {
        let pattern = #"\s*(다\s?했어|끝냈어|끝났어|완료했어|완료)\s*[.!]?\s*$"#
        // "mark buy milk as done", "i finished buy milk": the English of the same (ArisEnglishAsk).
        guard let range = spoken.range(of: pattern, options: .regularExpression) else { return ArisEnglishAsk.todoDone(spoken) }
        let item = spoken[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return item.isEmpty ? nil : item
    }

    /// "화면 밝게 해 줘", "화면 어둡게": the screen's brightness asked for without the word 밝기, only as a whole sentence.
    private static func koreanScreenLevel(_ phrase: String) -> Level? {
        guard let found = phrase.range(of: #"^화면\s*(?:을\s*)?(?:더\s*)?(밝게|어둡게)\s*(?:해|해\s*줘|해\s*주세요|해줄래|해\s*줄래)?$"#, options: .regularExpression) else { return nil }
        return phrase[found].contains("밝게") ? .up : .down
    }

    private static func number(in phrase: String, before counter: String) -> Int? {
        phrase.range(of: "[0-9]+(?=\\s*\(counter))", options: .regularExpression).flatMap { Int(phrase[$0]) }
    }

    private static func canonical(_ name: String) -> String {
        // Any case ("textedit"): the app's own spelling, never "Textedit" (QA BUG-14).
        if let alias = appAliases[name] ?? appAliases[name.lowercased()] { return alias }
        return name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// Korean phrases match anywhere; English ones only as whole words ("display" is not "play").
    private static func contains(_ phrase: String, any words: [String]) -> Bool {
        words.contains { word in
            guard word.unicodeScalars.allSatisfy(\.isASCII) else { return phrase.contains(word) }
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            return phrase.range(of: pattern, options: .regularExpression) != nil
        }
    }

    /// The first number, written or spoken ("50", "오십으로").
    static func firstNumber(in phrase: String) -> Int? {
        let normalized = ArisNumbers.normalize(phrase)
        guard let range = normalized.range(of: "[0-9]+", options: .regularExpression) else { return nil }
        return Int(normalized[range])
    }
}

extension ArisIntent {
    /// The app as the reply names it: its Korean name on the Mac for Apple's apps (Korean), else as it is.
    static func displayName(_ app: String, korean: Bool) -> String { korean ? koreanNames[app] ?? app : app }

    /// What the reply says once the arrange is done (QA BUG-14: in the past tense); nil for anything else.
    func doneLine(korean: Bool) -> String? {
        guard case .arrange(let app, let count) = self else { return nil }
        let name = Self.displayName(app, korean: korean)
        if korean { return "\(name) 창 \(count)개를 나눴어요." }
        return "Put \(count) \(name) windows \(count == 2 ? "side by side" : "in a grid")."
    }

    /// Why an arrange failed, in the user's language (QA BUG-13): never aris-tools' or macOS's own English.
    static func arrangeFailure(_ raw: String, app: String, korean: Bool) -> String {
        let said = raw.lowercased(), name = displayName(app, korean: korean)
        if ["unable to find application", "didn't open", "isn't running", "no app is named", "can't find"].contains(where: said.contains) {
            return korean ? "\(name) 앱을 찾지 못했어요." : "I couldn't find \(name)."
        }
        if said.contains("accessibility") {
            return korean ? "시스템 설정 › 개인정보 보호 및 보안 › \(ArisFix.Pane.accessibility.title(english: false))에서 Aris를 켜 주세요."
                : "Turn on Aris in System Settings › Privacy & Security › \(ArisFix.Pane.accessibility.title(english: true))."
        }
        if said.contains("no windows") { return korean ? "\(name) 창이 열리지 않았어요." : "No \(name) windows opened." }
        if said.contains("took too long") { return korean ? "시간이 너무 오래 걸려서 멈췄어요." : "It took too long, so I stopped." }
        return korean ? "다시 한 번 해 주세요." : "Please try again."
    }
}

extension ArisIntent {
    /// What Aris says after doing an everyday request itself; nil for questions.
    func acknowledgement(korean: Bool, now: Date = Date()) -> String? {
        switch self {
        case .media(let media):
            switch media {
            case .play: return korean ? "음악 틀게요." : "Playing."
            case .pause: return korean ? "음악 멈출게요." : "Paused."
            case .next: return korean ? "다음 곡으로 넘길게요." : "Next song."
            case .previous: return korean ? "이전 곡으로 갈게요." : "Previous song."
            }
        case .volume(let level): return Self.acknowledge(level, korean: korean, subject: korean ? "볼륨" : "Volume")
        case .brightness(let level): return Self.acknowledge(level, korean: korean, subject: korean ? "밝기" : "Brightness")
        case .openApp(let name): return korean ? "\(name) 열게요." : "Opening \(name)."
        case .arrange(let app, let count):
            let name = Self.displayName(app, korean: korean)
            if korean { return "\(name) 창 \(count)개를 띄워서 나눌게요." }
            return "Opening \(count) \(name) windows \(count == 2 ? "side by side" : "in a grid")."
        case .tellTime:
            let time = korean ? Self.koreanClock(now) : Self.format(now, "h:mm a", korean: false)
            return korean ? "지금 \(time)이에요." : "It's \(time)."
        case .tellDate:
            let date = Self.format(now, korean ? "M월 d일 EEEE" : "EEEE, MMMM d", korean: korean)
            return korean ? "오늘은 \(date)이에요." : "Today is \(date)."
        case .addTodo(let item): return korean ? "할 일에 넣었어요: \(item)" : "Added to your to-dos: \(item)"
        case .finishTodo(let item): return korean ? "체크했어요: \(item)" : "Ticked off: \(item)"
        case .timer(let seconds, let focus):
            let length = Self.duration(seconds)
            if korean { return focus ? "\(length) 집중 시작할게요." : "\(length) 타이머 맞췄어요." }
            return focus ? "Focus for \(seconds / 60) minutes." : "Timer set."
        case .cancelTimer: return korean ? "타이머 껐어요." : "Timer cancelled."
        case .pomodoro: return korean ? "뽀모도로 시작할게요. 25분 집중이에요." : "Pomodoro: 25 minutes of focus."
        case .pauseTimer: return korean ? "타이머 잠깐 멈췄어요." : "Timer paused."
        case .resumeTimer: return korean ? "타이머 다시 갈게요." : "Timer resumed."
        case .addTime(let seconds): return korean ? "\(Self.duration(seconds)) 늘렸어요." : "Added \(seconds / 60) minutes."
        case .timerLeft, .listTodos: return nil
        case .ask, .brief, .dayEnd, .undo, .readAgain, .saveAnswer, .whatsPlaying, .arisMute, .quietHours: return nil
        }
    }

    private static func format(_ date: Date, _ pattern: String, korean: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: korean ? "ko_KR" : "en_US")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    private static func acknowledge(_ level: Level, korean: Bool, subject: String) -> String {
        switch level {
        case .up: return korean ? "\(subject) 올렸어요." : "\(subject) up."
        case .down: return korean ? "\(subject) 낮췄어요." : "\(subject) down."
        case .set(let value): return korean ? "\(subject) \(value)으로 맞췄어요." : "\(subject) set to \(value)."
        case .mute: return korean ? "음소거를 바꿨어요." : "Toggled mute."
        }
    }
}
