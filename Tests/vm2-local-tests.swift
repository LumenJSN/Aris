// What a VM run on a Mac with no AI found (2026-11-11): an English "add buy milk to my to-do list" needed an AI, and a
// routine of steps the app does by itself could not run without one and ticked the step that never ran. Here: every
// local intent in English (what matches, and the near-misses that must stay the AI's), a routine's step handed back to
// the app, and the account of a routine that stopped. Run by run.sh.
import Foundation

func runVM2LocalTests() {
    englishTodoTests()
    englishTodoGuardTests()
    englishTodoDateTests()
    englishTimerTests()
    englishLevelTests()
    englishMediaTests()
    englishAppTests()
    englishClockTests()
    englishLastThingTests()
    englishQuietAndDayTests()
    englishGuardTests()
    koreanStillLocalTests()
    #if !VM2_INTENTS_ONLY
    runVM2RoutineTests()
    #endif
}

private func read(_ said: String) -> ArisIntent { ArisIntent.guarded(ArisIntent.parse(said), said: said) }
private func isAsk(_ said: String) -> Bool { if case .ask = read(said) { return true } else { return false } }

private func englishTodoTests() {
    let adds: [(String, String)] = [
        ("add buy milk to my to-do list", "buy milk"), ("Add Buy Milk to my to-do list.", "Buy Milk"), ("add buy milk to my todo list", "buy milk"),
        ("add buy milk to my to-dos", "buy milk"), ("put call mom on my to-do list", "call mom"), ("add milk and eggs to the to do list", "milk and eggs"),
        ("add a to-do: buy milk", "buy milk"), ("add to-do buy milk", "buy milk"), ("new to-do: call mom", "call mom"), ("to-do: call mom", "call mom"),
        ("please add buy milk to my to-do list", "buy milk"), ("can you add buy milk to my to-do list", "buy milk"),
        ("add buy milk to my to-do list please", "buy milk"), ("add buy milk to my reminders", "buy milk"),
        ("remind me to call mom", "call mom"), ("remind me to call mom tomorrow at 5", "call mom tomorrow at 5"),
        ("add a reminder to call mom", "call mom"), ("set a reminder for the dentist", "the dentist"), ("Remind me to email Dr. Kim", "email Dr. Kim"),
    ]
    for (said, item) in adds {
        check(read(said) == .addTodo(item), "english to-do: \"\(said)\" adds “\(item)” without an AI")
    }
    let dones: [(String, String)] = [
        ("buy milk is done", "buy milk"), ("i finished buy milk", "buy milk"), ("I've finished Buy Milk", "Buy Milk"), ("i'm done with buy milk", "buy milk"),
        ("mark buy milk as done", "buy milk"), ("mark buy milk done", "buy milk"), ("check off buy milk", "buy milk"), ("tick buy milk off", "buy milk"),
        ("cross off buy milk", "buy milk"), ("check off buy milk on my to-do list", "buy milk"), ("I’m done with buy milk", "buy milk"),
    ]
    for (said, item) in dones {
        check(read(said) == .finishTodo(item), "english to-do: \"\(said)\" names “\(item)” as finished (ticked only when an open item is called exactly that)")
    }
    for said in ["show my to-do list", "what's on my to-do list", "what’s on my to-do list?", "what are my to-dos", "list my to-dos", "read my to-do list",
                 "do i have any to-dos", "what do i have to do today", "is there anything on my to-do list?", "show my reminders", "what's left on my to-do list",
                 "to-do list"] {
        check(read(said) == .listTodos, "english to-do: \"\(said)\" reads the list")
    }
}

private func englishTodoGuardTests() {
    // Near-misses: a sentence that only holds the words, goes on, asks, refuses, or takes something away.
    for said in ["add a note to my presentation about to-dos", "add buy milk to my to-do list and email it to mom", "add buy milk to my to-do list?",
                 "should i add buy milk to my to-do list", "don't add buy milk to my to-do list", "don’t add buy milk to my to-do list",
                 "can i add buy milk to my to-do list", "what should i add to my to-do list", "add something to do this weekend",
                 "make a to-do list for my trip", "add a to-do list widget to my desktop", "add a slide about reminders to my deck", "add a reminder",
                 "add cancel gym membership to my to-do list", "never add anything to my to-do list", "make a todo app in swift",
                 "create a reminder app for my phone", "add todo app to my dock"] {
        check(isAsk(said), "english to-do: \"\(said)\" is not a local add")
    }
    // A reminder for a time Aris's own to-do can't keep is the AI's to set up, never saved without it.
    for said in ["remind me in 10 minutes to call mom", "remind me to call mom every monday", "remind me to call mom when i get home",
                 "remind me to call mom in an hour", "set a reminder for 5pm", "remind me what i said yesterday", "remind me to stretch later"] {
        check(isAsk(said), "english to-do: \"\(said)\" is not a to-do Aris can keep by itself")
    }
    // Taking one away is never local, in either language.
    for said in ["remove buy milk from my to-do list", "delete buy milk from my to-dos", "clear my to-do list", "할 일에서 우유 사기 지워 줘"] {
        check(isAsk(said), "to-do: \"\(said)\" (a removal) goes to the AI and its card")
    }
    for said in ["is buy milk done", "did i finish buy milk", "i'm done", "we're done", "that is done", "check my mail", "mark this email as read",
                 "i'm not done with buy milk", "buy milk isn't done", "should i mark buy milk as done"] {
        check(isAsk(said), "english to-do: \"\(said)\" ticks nothing")
    }
    for said in ["show my to-do list and email it to mom", "what should be on my to-do list", "email my to-do list to mom",
                 "what do i have to do to reset my password"] {
        check(read(said) != .listTodos, "english to-do: \"\(said)\" asks for more than a reading")
    }
    check(read("open reminders") == .openApp("Reminders") && read("미리 알림 열어 줘") == .openApp("Reminders"), "to-do: opening Reminders is still opening the app")
    check(read("미리 알림에 우유 사기 추가해 줘") == .addTodo("우유 사기") && read("미리 알림 보여 줘") == .listTodos,
          "to-do: Reminders by its Korean name adds and reads too (the English “reminders” does)")
}

private func englishTodoDateTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    let thursday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 10))!
    func due(_ text: String) -> String {
        let parsed = ArisTodoDate.parse(text, now: thursday, calendar: calendar)
        let formatter = DateFormatter()
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE M/d HH:mm"
        return parsed.text + " | " + (parsed.due.map(formatter.string) ?? "-")
    }
    check(due("call mom tomorrow at 5") == "call mom | Fri 11/13 17:00" && due("call mom at 5") == "call mom | Thu 11/12 17:00",
          "english due: “tomorrow at 5” is tomorrow at five in the afternoon, as “내일 5시에” is")
    check(due("dentist on friday at 9:30 am") == "dentist | Fri 11/13 09:30" && due("report by next monday") == "report | Mon 11/16 23:59"
          && due("submit by 6pm") == "submit | Thu 11/12 18:00" && due("buy milk today") == "buy milk | Thu 11/12 23:59",
          "english due: a weekday, next week's day, “by 6pm” and “today”")
    check(due("buy milk") == "buy milk | -" && due("buy 2 tickets for tomorrow's game") == "buy 2 tickets for tomorrow's game | -"
          && due("meet at 5 guys") == "meet at 5 guys | -" && due("watch Friday Night Lights") == "watch Friday Night Lights | -",
          "english due: words that only look like a day or a time stay in the title")
    check(due("내일 3시에 우유 사기") == "우유 사기 | Fri 11/13 15:00", "english due: the Korean forms read as before")
}

private func englishTimerTests() {
    let sets: [(String, Int)] = [("set a timer for 2 minutes", 120), ("set a 1 minute timer", 60), ("timer 5 minutes", 300), ("start a 10 minute timer", 600),
                                 ("set a timer for 1 hour and 30 minutes", 5_400), ("set a timer for 90 seconds", 90), ("set a timer for an hour", 3_600),
                                 ("set a timer for half an hour", 1_800), ("set a timer for five minutes", 300), ("set a timer for twenty five minutes", 1_500),
                                 ("can you set a timer for 3 minutes please", 180), ("Aris, set a timer for five minutes please", 300)]
    for (said, seconds) in sets {
        check(read(said) == .timer(seconds: seconds, focus: false), "english timer: \"\(said)\" sets \(seconds) seconds")
    }
    check(read("focus for 25 minutes") == .timer(seconds: 1_500, focus: true) && read("start a pomodoro") == .pomodoro, "english timer: a focus session and a pomodoro")
    for said in ["cancel the timer", "stop the timer", "turn off the timer", "end the timer", "clear the timer"] {
        check(read(said) == .cancelTimer, "english timer: \"\(said)\" cancels it")
    }
    check(read("pause the timer") == .pauseTimer && read("resume the timer") == .resumeTimer && read("continue the timer") == .resumeTimer
          && read("unpause the timer") == .resumeTimer, "english timer: paused and resumed")
    for said in ["add 5 minutes to the timer", "5 more minutes on the timer", "five more minutes on the timer", "extend the timer by 5 minutes",
                 "another 5 minutes on the timer"] {
        check(read(said) == .addTime(300), "english timer: \"\(said)\" adds five minutes")
    }
    for said in ["how much time is left on the timer", "how long is left on the timer?", "time left on the timer", "how much longer on the timer"] {
        check(read(said) == .timerLeft, "english timer: \"\(said)\" is answered from the timer")
    }
    for said in ["did you set a timer for 5 minutes", "should i set a timer for 5 minutes", "don't set a timer for 5 minutes", "dont set a timer for 5 minutes",
                 "set a timer for 5 minutes and then play music", "set a timer for 5 minutes, then open safari", "when the timer ends play music",
                 "is the timer running", "how long should i set the timer for", "what's a pomodoro timer", "do i need to set a timer for 5 minutes",
                 "set a timer for 5 minutes also open safari"] {
        check(isAsk(said), "english timer: \"\(said)\" sets, stops and changes nothing")
    }
}

private func englishLevelTests() {
    let volumes: [(String, ArisIntent.Level)] = [("volume up", .up), ("turn the volume up", .up), ("turn up the volume", .up), ("louder", .up),
                                                 ("volume down", .down), ("turn down the volume", .down), ("quieter", .down), ("set the volume to 50", .set(50)),
                                                 ("volume to 30 percent", .set(30)), ("set the volume to fifty percent", .set(50)), ("max volume", .set(100)),
                                                 ("turn the sound down", .down), ("turn up the sound", .up), ("sound to 30", .set(30)), ("mute the volume", .mute)]
    for (said, level) in volumes {
        check(read(said) == .volume(level), "english volume: \"\(said)\"")
    }
    let lights: [(String, ArisIntent.Level)] = [("brightness up", .up), ("turn up the brightness", .up), ("make the screen brighter", .up), ("brighter", .up),
                                                ("lower the brightness", .down), ("set brightness to 70", .set(70)), ("dim the screen", .down),
                                                ("brighten the display", .up), ("화면 밝게 해 줘", .up), ("화면 어둡게", .down)]
    for (said, level) in lights {
        check(read(said) == .brightness(level), "brightness: \"\(said)\"")
    }
    for said in ["turn the volume up and open safari", "is the volume up", "what does that sound like", "send this sound file to 3 people",
                 "turn the lights down", "dim the lights", "dim the screen and open safari", "should i dim the screen", "화면 밝게 하면 눈에 안 좋아?",
                 "turn the sound down when the call starts", "the sound is too low on this video, fix the file"] {
        check(isAsk(said), "level: \"\(said)\" moves nothing")
    }
}

private func englishMediaTests() {
    let medias: [(String, ArisIntent.Media)] = [("play music", .play), ("play some music", .play), ("play", .play), ("resume the music", .play), ("unpause", .play),
                                                ("pause", .pause), ("pause the music", .pause), ("stop the music", .pause), ("stop playing", .pause),
                                                ("stop", .pause), ("please stop", .pause), ("next song", .next), ("skip this song", .next), ("skip", .next),
                                                ("next", .next), ("next please", .next), ("previous song", .previous), ("go back a song", .previous),
                                                ("previous", .previous)]
    for (said, media) in medias {
        check(read(said) == .media(media), "english music: \"\(said)\"")
    }
    check(read("what's playing") == .whatsPlaying && read("what song is this") == .whatsPlaying, "english music: what is playing is read, never asked of an AI")
    for said in ["play despacito", "play some jazz on spotify", "stop the build", "stop sending me emails", "pause the music, set a timer for 5 minutes",
                 "don't stop the music", "should i skip this song", "stop the music and open safari", "next week's schedule", "skip the meeting tomorrow"] {
        check(read(said) != .media(.play) && read(said) != .media(.pause) || isAsk(said), "english music: \"\(said)\" is not the play button")
    }
    for said in ["stop the build", "stop sending me emails", "pause the music, set a timer for 5 minutes", "don't stop the music", "should i skip this song",
                 "stop the music and open safari"] {
        check(isAsk(said), "english music: \"\(said)\" goes to the AI")
    }
}

private func englishAppTests() {
    let opens: [(String, String)] = [("open safari", "Safari"), ("launch slack", "Slack"), ("open the calculator", "Calculator"), ("start xcode", "Xcode"),
                                     ("open safari please", "Safari"), ("can you open safari", "Safari"), ("could you open safari?", "Safari"),
                                     ("please open safari", "Safari"), ("open the safari app", "Safari"), ("open settings", "System Settings"),
                                     ("switch to finder", "Finder"), ("open app store", "App Store"), ("i need you to open safari", "Safari")]
    for (said, app) in opens {
        check(read(said) == .openApp(app), "english app: \"\(said)\" opens \(app)")
    }
    for said in ["open the file on my desktop", "open safari and go to apple.com", "open safari, go to apple.com", "open a new tab with my mail",
                 "don't open safari", "should i open safari", "is safari open", "open the door for me in the game", "open safari then slack",
                 "open my notes about the meeting"] {
        check(isAsk(said), "english app: \"\(said)\" is more than opening an app")
    }
    check(read("open 4 excel windows in a grid") == .arrange(app: "Microsoft Excel", count: 4) && read("put 2 safari windows side by side") == .arrange(app: "Safari", count: 2)
          && read("tile 3 finder windows") == .arrange(app: "Finder", count: 3), "english windows: a few windows of an app in a grid, as “엑셀 4개 켜서 4등분”")
    check(isAsk("open 20 safari windows in a grid") && isAsk("open 4 windows of excel") && isAsk("should i tile 3 finder windows"),
          "english windows: too many, or not that sentence, is the AI's")
}

private func englishClockTests() {
    for said in ["what time is it", "what's the time", "what’s the time?", "what time is it now", "tell me the time", "do you have the time", "current time",
                 "hey aris, what's the time", "can you tell me the time"] {
        check(read(said) == .tellTime, "english time: \"\(said)\"")
    }
    for said in ["what's the date", "what's the date today", "what day is it", "what day is it today?", "what's today's date", "tell me the date",
                 "today's date", "what day is today"] {
        check(read(said) == .tellDate, "english date: \"\(said)\"")
    }
    for said in ["what time is it in london", "what time is the meeting", "what's the time difference between seoul and tokyo", "do you have time to help me",
                 "the time machine backup failed", "what's the date of the meeting", "what day is the meeting", "tell me the date of the next holiday",
                 "what time should i leave", "put the date in the file name"] {
        check(isAsk(said), "english time and date: \"\(said)\" asks something else")
    }
}

private func englishLastThingTests() {
    for said in ["undo", "undo that", "undo the last thing", "take that back", "revert that", "please undo that", "undo the last one"] {
        check(read(said) == .undo, "english undo: \"\(said)\" is the last thing Aris did")
    }
    for said in ["undo the last email", "undo my changes in the document", "don't undo that", "take that back to the store", "should i undo that",
                 "undo that and send it again"] {
        check(isAsk(said), "english undo: \"\(said)\" is not a bare undo")
    }
    for said in ["read it", "read it again", "read that again", "read it out loud", "read the whole thing", "say that again", "repeat that",
                 "can you read that again", "read the answer"] {
        check(read(said) == .readAgain, "english read: \"\(said)\" reads the last answer")
    }
    for said in ["read it to mom", "read this email", "read that article again", "say that again in french", "repeat that in korean", "repeat after me",
                 "read my messages"] {
        check(isAsk(said), "english read: \"\(said)\" names something else to read")
    }
    for said in ["save the answer", "save the answer to a file", "save that answer as notes.txt", "save this to a file"] {
        if case .saveAnswer = read(said) { check(true, "english save: \"\(said)\" saves the last answer on its card") } else { check(false, "english save: \"\(said)\" saves the last answer on its card") }
    }
    check(isAsk("save the file") && isAsk("save the answer?") && isAsk("should i save the answer"), "english save: anything else is not the last answer's save")
}

private func englishQuietAndDayTests() {
    for said in ["mute", "be quiet", "stop talking", "shut up", "mute yourself", "quiet", "please be quiet", "stop speaking"] {
        check(read(said) == .arisMute(true), "english mute: \"\(said)\" mutes Aris")
    }
    for said in ["unmute", "you can talk again", "unmute yourself", "you can speak"] {
        check(read(said) == .arisMute(false), "english mute: \"\(said)\" lets it speak again")
    }
    for said in ["stop talking about that", "be quiet about the surprise", "quiet music please", "shut up and listen to this question about taxes",
                 "don't mute", "should i mute you"] {
        check(read(said) != .arisMute(true) && read(said) != .arisMute(false), "english mute: \"\(said)\" is not the mute")
    }
    for said in ["wrap up my day", "what did you do today", "end of day summary", "daily summary", "close out my day", "end my day"] {
        check(read(said) == .dayEnd, "english day-end: \"\(said)\"")
    }
    for said in ["wrap up my day and email it to mom", "wrap up the meeting", "end my day's meeting early", "what did you do today at the gym with mom"] {
        check(read(said) != .dayEnd, "english day-end: \"\(said)\" asks for something else")
    }
    for said in ["give me my briefing", "morning briefing", "brief me", "daily brief"] {
        check(read(said) == .brief, "english brief: \"\(said)\"")
    }
    check(isAsk("give me a brief summary of this") && isAsk("be brief") && isAsk("brief me on the meeting"), "english brief: a brief of something else is the AI's")
    // A routine named in a sentence is the agent's, whole, in either language (never a local act on a word in it).
    for said in ["run my morning routine", "make a test routine: set a 1 minute timer, tell me the time", "add open safari to my morning routine"] {
        check(isAsk(said), "english routine: \"\(said)\" reaches the agent whole")
    }
}

private func englishGuardTests() {
    // The one guard every local action passes, whoever picked it (the router's second guess too).
    let timer = ArisIntent.timer(seconds: 300, focus: false)
    for said in ["did you set a timer for 5 minutes", "is it ok to set a timer for 5 minutes", "do you think a 5 minute timer helps",
                 "i shouldn't set a timer for 5 minutes", "no need to set a timer for 5 minutes", "how do i set a timer for 5 minutes",
                 "what if i set a timer for 5 minutes", "can i set a timer for 5 minutes", "set a timer for 5 minutes?"] {
        if case .ask = ArisIntent.guarded(timer, said: said) { check(true, "english guard: \"\(said)\" is held back") } else { check(false, "english guard: \"\(said)\" is held back") }
    }
    for said in ["set a timer for 5 minutes", "can you set a timer for 5 minutes?", "could you set a timer for 5 minutes", "please set a timer for 5 minutes"] {
        check(ArisIntent.guarded(timer, said: said) == timer, "english guard: \"\(said)\" is a request")
    }
    check(ArisIntentScope.goesOn("pause the music, set a timer for 5 minutes") && ArisIntentScope.goesOn("open safari also open slack")
          && ArisIntentScope.goesOn("set a timer for 5 minutes when it ends play music"), "english scope: a comma and a new verb, “also”, “when it ends” go on")
    check(!ArisIntentScope.goesOn("aris, set a timer for 5 minutes") && !ArisIntentScope.goesOn("ok, open safari") && !ArisIntentScope.goesOn("set a timer for 1 hour and 30 minutes")
          && !ArisIntentScope.goesOn("turn the volume up a bit, please"), "english scope: a name, an ok or a please with a comma joins nothing on")
    check(ArisEnglishAsk.core("can you open safari please") == "open safari" && ArisEnglishAsk.core("hey aris, please undo that") == "undo that"
          && ArisEnglishAsk.core("open safari") == "open safari", "english: what only makes a request polite is not part of it")
    check(ArisEnglishAsk.digits("set a timer for five minutes") == "set a timer for 5 minutes" && ArisEnglishAsk.digits("an hour and a half timer") == "90 minutes timer"
          && ArisEnglishAsk.digits("forty-five more minutes") == "45 more minutes" && ArisEnglishAsk.digits("play one more song") == "play one more song"
          && ArisEnglishAsk.digits("set a second timer for 5 minutes") == "set a second timer for 5 minutes",
          "english: a number in words is digits only right before a unit")
}

private func koreanStillLocalTests() {
    // The Korean forms read as they did.
    check(read("할 일 추가해 우유 사기") == .addTodo("우유 사기") && read("우유 사기 다 했어") == .finishTodo("우유 사기") && read("할 일 뭐 있어") == .listTodos,
          "korean: the to-do forms are as before")
    check(read("타이머 5분") == .timer(seconds: 300, focus: false) && read("타이머 꺼 줘") == .cancelTimer && read("타이머 5분 추가") == .addTime(300)
          && read("타이머 얼마나 남았어") == .timerLeft, "korean: the timer forms are as before")
    check(read("볼륨 50") == .volume(.set(50)) && read("밝기 올려") == .brightness(.up) && read("음악 꺼 줘") == .media(.pause) && read("다음 곡") == .media(.next)
          && read("멈춰") == .media(.pause), "korean: volume, brightness and music are as before")
    check(read("사파리 열어 줘") == .openApp("Safari") && read("지금 몇 시야") == .tellTime && read("오늘 며칠이야") == .tellDate && read("되돌려 줘") == .undo
          && read("읽어줘") == .readAgain && read("조용히 해 줘") == .arisMute(true) && read("오늘 정리해 줘") == .dayEnd && read("브리핑 해줘") == .brief,
          "korean: apps, the clock, undo, reading, the mute, the day-end and the brief are as before")
    check(isAsk("카톡 켜서 엄마한테 문자 보내") && isAsk("5분 타이머 맞춰야 할까?") && isAsk("할 일 추가하지 마") && isAsk("볼륨 크게 들으면 귀에 안 좋아?"),
          "korean: what went to the AI still does")
}

#if !VM2_INTENTS_ONLY
// MARK: - A routine's local steps, and the account of one that stopped (bug 2)

private func vm2Routine(_ name: String, _ steps: [String], own: Bool = true) -> ArisRoutine {
    let at = Date(timeIntervalSince1970: 1_800_000_000)
    return ArisRoutine(id: UUID(), name: name, steps: steps, own: own, created: at, changed: at)
}

/// Feeds the run each step's last line; the effects in order and the run at the end.
private func vm2Feed(_ run: ArisRoutineRun, _ replies: [ArisAgentReply], answers: [String: ArisRoutineRun.CardAnswer] = [:]) -> (run: ArisRoutineRun, effects: [ArisRoutineRun.Effect]) {
    var now = run
    var effects: [ArisRoutineRun.Effect] = []
    for reply in replies {
        let taken = now.taking(reply, answers: answers)
        now = taken.run
        effects.append(taken.effect)
    }
    return (now, effects)
}

private let vm2NoAI = ArisBrainTrouble(brain: nil, missing: .any)
private let vm2Test = vm2Routine("test", ["set a 1 minute timer", "tell me the time"])
private let vm2Mixed = vm2Routine("mix", ["set a 1 minute timer", "check my mail", "tell me the time"])

func runVM2RoutineTests() {
    routineStepWireTests()
    routineStepRuleTests()
    routineStepEndTests()
    routineLocalRunTests()
    routineStopAccountTests()
    routineStopButtonTests()
    routineStopChipTests()
    routineStepByWordsTests()
    whyNotAfterTheAIsOwnRefusalTests()
}

private func routineStepWireTests() {
    let step = ArisRoutineLocalStep(id: "A1", words: "set a 1 minute timer")
    let line = String(data: step.line, encoding: .utf8) ?? ""
    check(line.hasSuffix("\n") && ArisRoutineLocalStep.parse(line: String(line.dropLast())) == step, "routine step: the offer is one JSON line the app reads back whole")
    check(ArisAgentReply.parse(String(line.dropLast())) == nil && ArisFix.parse(line: String(line.dropLast())) == nil,
          "routine step: an offer is no reply and no fix (an app that doesn't know it shows nothing for it)")
    for bad in [#"{"status":"set a 1 minute timer · 1/2"}"#, #"{"localStep":{"id":"","words":"x"}}"#, #"{"localStep":{"id":"A1","words":"  "}}"#,
                #"{"localStep":{"id":"A1"}}"#, #"{"answer":"the \"localStep\" line"}"#, "{\"localStep\":{\"id\":\"A1\",\"words\":\"" + String(repeating: "x", count: 201) + "\"}}"] {
        check(ArisRoutineLocalStep.parse(line: bad) == nil, "routine step: \(bad.prefix(48)) is not an offer")
    }
    for outcome in [ArisRoutineLocalOutcome.notLocal, .done("Timer set."), .failed("I couldn't add it.")] {
        check(ArisRoutineLocalOutcome.parse(outcome.json) == outcome, "routine step: the app's answer \(outcome) reads back as sent")
    }
    check(ArisRoutineLocalOutcome.parse(["ok": true, "reply": "x"]) == nil && ArisRoutineLocalOutcome.parse(["local": true, "ok": true]) == nil
          && ArisRoutineLocalOutcome.parse(["local": true, "reply": "x"]) == nil && ArisRoutineLocalOutcome.parse(["local": "yes"]) == nil,
          "routine step: an answer that doesn't say whether it was done is no answer")
    // Who is offered a step, and what the answer is to the run.
    check(ArisRoutineHandBack.offers(own: true, appTakesSteps: true) && !ArisRoutineHandBack.offers(own: false, appTakesSteps: true)
          && !ArisRoutineHandBack.offers(own: true, appTakesSteps: false),
          "routine step: only a step of his own words is offered, and only to an app that answers offers (a step an AI worded stays behind the gates)")
    check(ArisRoutineHandBack.reply(.notLocal) == nil && ArisRoutineHandBack.reply(.done("Timer set.")) == .answer("Timer set.")
          && ArisRoutineHandBack.reply(.failed("I couldn't open Slack.")) == .failure("I couldn't open Slack."),
          "routine step: not the app's own asks the AI; done is the step's answer; tried and not done is its failure")
}

private func routineStepRuleTests() {
    let local: [(String, ArisIntent)] = [
        ("set a 1 minute timer", .timer(seconds: 60, focus: false)), ("tell me the time", .tellTime), ("what's the date", .tellDate),
        ("set the volume to 30", .volume(.set(30))), ("dim the screen", .brightness(.down)), ("pause the music", .media(.pause)),
        ("open safari", .openApp("Safari")), ("add buy milk to my to-do list", .addTodo("buy milk")), ("mute", .arisMute(true)),
        ("cancel the timer", .cancelTimer), ("타이머 5분", .timer(seconds: 300, focus: false)), ("음악 꺼 줘", .media(.pause)), ("지금 몇 시야", .tellTime),
        ("할 일 추가해 우유 사기", .addTodo("우유 사기")), ("what's playing", .whatsPlaying), ("mark buy milk as done", .finishTodo("buy milk")),
    ]
    for (words, intent) in local {
        check(ArisRoutineStepRule.act(for: words) == intent, "routine step: “\(words)” is done by the app, as when typed")
    }
    // The AI's, as before: anything the typed path would not have done by itself, with the same guards.
    for words in ["check my mail", "tell me today's schedule", "what's the weather", "should i set a 1 minute timer", "don't set a timer",
                  "set a 1 minute timer and then email mom", "open safari, go to apple.com", "set a 1 minute timer?", "did you set a timer for 5 minutes",
                  "run my morning routine", "출근 루틴 해 줘", "GPT한테 물어봐, 타이머 5분 맞춰", "send mom a message saying i'm late", "delete the files on my desktop",
                  "remove buy milk from my to-do list", "", "   ", String(repeating: "open safari ", count: 20)] {
        check(ArisRoutineStepRule.act(for: words) == nil, "routine step: “\(words.prefix(44))” is not the app's own (the AI's turn and its gates, as before)")
    }
    // Local when typed, but the notch's own card or reading: inside a routine these stay the AI's turn.
    for words in ["show my to-do list", "undo that", "wrap up my day", "read it", "give me my briefing", "save the answer to a file",
                  "open 4 excel windows in a grid", "오늘 정리해 줘", "되돌려 줘", "할 일 뭐 있어"] {
        check(ArisRoutineStepRule.act(for: words) == nil, "routine step: “\(words)” keeps its own card or reading, so a routine leaves it to the AI")
    }
    check(ArisRoutineStepRule.act(for: "stop") == nil && ArisRoutineStepRule.act(for: "됐어") == nil,
          "routine step: a word that ends a conversation when typed does nothing as a step")
}

private func routineStepEndTests() {
    let quiet = ArisIntent.volume(.set(30))
    check(ArisRoutineStepRule.ended(quiet, reply: "Volume set to 30.", korean: false) == .done("Volume set to 30."),
          "routine step: a volume that moved is done")
    let cannot = ArisControl.volume(.set(30)).reply(changed: false, korean: false)
    check(ArisRoutineStepRule.ended(quiet, reply: cannot, korean: false) == .failed(cannot), "routine step: a sound output the Mac can't set is a step that did not happen")
    let top = ArisControl.limitReply(.top, korean: false)
    check(ArisRoutineStepRule.ended(.volume(.up), reply: top, korean: false) == .done(top), "routine step: “already at its highest” is a true answer, not a failure")
    let dark = ArisControl.brightness(.down).reply(changed: false, korean: true)
    check(ArisRoutineStepRule.ended(.brightness(.down), reply: dark, korean: true) == .failed(dark), "routine step: a display the Mac can't dim is not done")
    let unopened = ArisLocalReply.appNotOpened("Slack", korean: false)
    check(ArisRoutineStepRule.ended(.openApp("Slack"), reply: unopened, korean: false) == .failed(unopened)
          && ArisRoutineStepRule.ended(.openApp("Slack"), reply: "Opening Slack.", korean: false) == .done("Opening Slack."),
          "routine step: an app macOS did not open is not done; one it opened is")
    let none = ArisLocalReply.noTimer(korean: false)
    check(ArisRoutineStepRule.ended(.cancelTimer, reply: none, korean: false) == .done(none) && ArisRoutineStepRule.ended(.tellTime, reply: "It's 2:12 PM.", korean: false) == .done("It's 2:12 PM."),
          "routine step: “no timer is running” and the time are the step's answer")
    check(ArisRoutineStepRule.added(.saved(title: "buy milk"), korean: false) == .done("Added to your to-dos: buy milk"),
          "routine step: a to-do that was saved is done")
    guard case .failed(let noAccess) = ArisRoutineStepRule.added(.noAccess, korean: false) else { return check(false, "routine step: a to-do Reminders did not take is not done") }
    check(ArisAppFix.fix(forLine: noAccess) == .pane(.reminders), "routine step: a to-do that needs Reminders access is not done, and its line still earns the Reminders button")
    check(ArisRoutineStepRule.added(.failed(why: nil), korean: false) == .failed("I couldn't add it to your to-dos.")
          && ArisRoutineStepRule.added(.noTitle, korean: true) == .failed("넣을 할 일을 못 알아들었어요. 다시 말해 주세요."),
          "routine step: a to-do that named nothing, or that Reminders refused, is not done")
    check(ArisRoutineStepRule.played(.pause, done: true, korean: false) == .done("Paused.") && ArisRoutineStepRule.played(.play, done: false, korean: false) == .failed("Couldn't play the music."),
          "routine step: the player's own answer decides whether the music step is done")
}

private func routineLocalRunTests() {
    // The VM's routine: two steps the app does itself. Each answer comes from the app (ArisRoutineHandBack.reply), no AI.
    let start = ArisRoutineRun(routine: vm2Test, korean: false)
    check(start.startStatus == .status("set a 1 minute timer · 1/2"), "local routine: the notch shows the first step, counted")
    let timer = ArisRoutineHandBack.reply(.done("Timer set."))!, time = ArisRoutineHandBack.reply(.done("It's 2:12 PM."))!
    let ran = vm2Feed(start, [timer, time])
    check(ran.effects == [.next(step: "tell me the time", status: .status("tell me the time · 2/2")),
                          .finish(.answer("Ran the “test” routine through, all 2 steps.\n\n### 1. set a 1 minute timer\nTimer set.\n\n### 2. tell me the time\nIt's 2:12 PM."))],
          "local routine: “set a 1 minute timer, tell me the time” runs both steps in order with no AI, and the account has each step's own line")
    check(!ArisRoutineAccount.stoppedShort(ran.run.outcomes) && ArisRoutineAccount.failureLine(ran.run.outcomes) == nil, "local routine: a run that went through marks no step as failed")
    // A local step that did not happen stops the routine there, like any step.
    let unopened = ArisLocalReply.appNotOpened("Slack", korean: false)
    let opens = ArisRoutineRun(routine: vm2Routine("work", ["set a 1 minute timer", "open slack", "tell me the time"]), korean: false)
    let stopped = vm2Feed(opens, [timer, ArisRoutineHandBack.reply(.failed(unopened))!])
    check(stopped.effects.last == .finish(.answer("The “work” routine stopped at step 2: I couldn't open Slack.\n\n### 1. set a 1 minute timer\nTimer set.\n\n### 2. open slack\nNot done.\n\n### Not run\n- 3. tell me the time")),
          "local routine: a local step that did not happen stops the routine, and the later steps are not started")
    // The app never said how the step ended: not done, and never asked of the AI instead (the app may have done it).
    let silent = vm2Feed(start, [.failure(ArisRoutineHandBack.noWord(korean: false))])
    check(silent.effects == [.finish(.failure("The “test” routine stopped at step 1: The Aris app didn't say whether it did this step.\n\n### 1. set a 1 minute timer\nNot done.\n\n### Not run\n- 2. tell me the time"))],
          "local routine: a step the app never answered for stops the routine")
}

private func routineStopAccountTests() {
    let noAI = vm2NoAI.line(korean: false)
    // Local step, then an AI step on a Mac with no AI, then a step never reached.
    let mixed = vm2Feed(ArisRoutineRun(routine: vm2Mixed, korean: false), [.answer("Timer set."), .failure(noAI)])
    let account = "The “mix” routine stopped at step 2: No AI is ready on this Mac. Connect one in Settings › AI services.\n\n### 1. set a 1 minute timer\nTimer set.\n\n### 2. check my mail\nNot done.\n\n### Not run\n- 3. tell me the time"
    check(mixed.effects.last == .finish(.answer(account)), "routine stop: with no AI the local step is done, the AI step stops the routine, and the account says where, why, what was done and what was not")
    check(ArisRoutineAccount.stoppedShort(mixed.run.outcomes) && ArisRoutineAccount.failureLine(mixed.run.outcomes) == noAI,
          "routine stop: the step that stopped it is marked failed, and its failure line is kept for the button")
    // The first step is the AI's and there is none: nothing was done, and the turn says the routine stopped (never the bare line).
    let first = vm2Feed(ArisRoutineRun(routine: vm2Routine("mail", ["check my mail", "tell me the time"]), korean: false), [.failure(noAI)])
    check(first.effects == [.finish(.failure("The “mail” routine stopped at step 1: No AI is ready on this Mac. Connect one in Settings › AI services.\n\n### 1. check my mail\nNot done.\n\n### Not run\n- 2. tell me the time"))],
          "routine stop: a first step with no AI says the routine stopped at step 1 and lists what was not done")
    let korean = vm2Feed(ArisRoutineRun(routine: vm2Routine("test", ["메일 확인해 줘", "지금 몇 시야"]), korean: true), [.failure(vm2NoAI.line(korean: true))])
    check(korean.effects == [.finish(.failure("‘test’ 루틴은 1단계에서 멈췄어요: 지금 쓸 수 있는 AI가 없어요. 설정 › AI 서비스에서 AI를 하나 연결해 주세요.\n\n### 1. 메일 확인해 줘\n하지 못했어요.\n\n### 하지 않은 단계\n- 2. 지금 몇 시야"))],
          "routine stop: the same in Korean")
    // Every way a routine stops leaves its last step unfinished; a run to the end does not.
    let stops: [ArisRoutineRun.Outcome] = [.failed("x"), .declined("no"), .unanswered(""), .handedOut]
    check(stops.allSatisfy { ArisRoutineAccount.stoppedShort([.done("a"), $0]) } && !ArisRoutineAccount.stoppedShort([.done("a"), .done("b")]) && !ArisRoutineAccount.stoppedShort([]),
          "routine stop: a step that failed, was refused, went unanswered or is a teammate's did not finish")
    check(ArisRoutineAccount.failureLine([.done("a"), .declined("no")]) == nil, "routine stop: his own no earns no button")
    // "<one AI> isn't installed" on a Mac with no AI at all is told as that.
    let codex = ArisBrainTrouble(brain: .codex, missing: .program)
    check(ArisRoutineAccount.truer(.failure(codex.line(korean: false))) { false } == .failure(noAI)
          && ArisRoutineAccount.truer(.failure(codex.line(korean: true))) { false } == .failure(vm2NoAI.line(korean: true)),
          "routine stop: a step that blames one AI on a Mac where none can answer says no AI is ready, in the line's own language")
    check(ArisRoutineAccount.truer(.failure(codex.line(korean: false))) { true } == .failure(codex.line(korean: false))
          && ArisRoutineAccount.truer(.failure("Codex가 답하지 않았어요.")) { false } == .failure("Codex가 답하지 않았어요.")
          && ArisRoutineAccount.truer(.answer(codex.line(korean: false))) { false } == .answer(codex.line(korean: false)),
          "routine stop: with another AI ready, or for any other line, the failure is passed on as it came")
}

private func routineStopButtonTests() {
    // The button the failure earned goes out with the account, though the account is no longer the failure's own line.
    let noAI = vm2NoAI.line(korean: false)
    let earned = ArisBrainFix.fix(forLine: noAI) { _ in nil }
    check(earned == .settings(.brain), "routine stop: “no AI is ready” earns Settings › AI services")
    final class Stream {}
    func closing(_ reply: ArisAgentReply, noting fix: ArisFix?) -> ArisFix? {
        let turns = ArisFixTurns(), stream = Stream(), began = Date(timeIntervalSince1970: 1_800_000_000)
        turns.began(stream, task: false, now: began)
        if let fix { turns.note(fix, now: began.addingTimeInterval(1)) }
        return turns.closing(reply, on: stream, dropped: [], now: began.addingTimeInterval(2)) { _ in nil }
    }
    let stoppedLater = ArisRoutineAccount.reply(vm2Mixed, outcomes: [.done("Timer set."), .failed(noAI)], korean: false)
    let stoppedFirst = ArisRoutineAccount.reply(vm2Mixed, outcomes: [.failed(noAI)], korean: false)
    check(closing(stoppedLater, noting: earned) == .settings(.brain) && closing(stoppedFirst, noting: earned) == .settings(.brain),
          "routine stop: the Settings › AI services button is under the account, at the first step and at a later one")
    check(closing(stoppedFirst, noting: nil) == nil, "routine stop: the account's own words earn nothing by themselves (the button is the noted one)")
    // "Try again" would run the finished steps a second time: only when nothing was done.
    let slow = ArisBrainFailure.slowLine(brain: .codex, korean: false)
    let retry = ArisBrainFix.fix(forLine: slow) { _ in nil }
    check(retry == .retry, "routine stop: a slow AI earns “try again”")
    check(closing(ArisRoutineAccount.reply(vm2Mixed, outcomes: [.failed(slow)], korean: false), noting: retry) == .retry
          && closing(ArisRoutineAccount.reply(vm2Mixed, outcomes: [.done("Timer set."), .failed(slow)], korean: false), noting: retry) == nil,
          "routine stop: “try again” shows when the first step failed, never after steps that were already done")
}

private func routineStopChipTests() {
    // What the notch's tags show: the step that did not finish never gets a tick.
    let asked = ArisSession().listening().hearing("run my test routine").thinking()
    let running = asked.working("set a 1 minute timer · 1/2")
    // Before: the turn failed and the tag was ticked.
    check(running.failing("No AI is ready on this Mac.").tags.isEmpty, "routine chip: without the agent's mark, a step that was running when the turn failed is not ticked either (vm3 bug C)")
    let stopped = running.stepFailed(nil).failing("The “test” routine stopped at step 1: …")
    check(stopped.tags.count == 1 && stopped.tags[0].failed && stopped.tags[0].label == "set a 1 minute timer · 1/2",
          "routine chip: the step the routine stopped on is marked failed, not ticked")
    let second = running.working("check my mail · 2/3").stepFailed(nil).answering("The “mix” routine stopped at step 2: …")
    check(second.tags.map(\.failed) == [false, true] && second.tags.allSatisfy(\.done), "routine chip: the step that was done keeps its tick, the one that stopped the routine gets none")
    let through = running.working("tell me the time · 2/2").answering("Ran the “test” routine through, all 2 steps.")
    check(through.tags.map(\.failed) == [false, false] && through.tags.count == 2, "routine chip: a routine that ran through ticks every step")
    // The agent sends that mark as its own line just before the account.
    check(ArisAgentReply.parse(String(String(data: ArisAgentReply.stepFailed(nil).line, encoding: .utf8)!.dropLast())) == .stepFailed(nil),
          "routine chip: the mark for “the step running now” reads back as sent")
}

// MARK: - A routine's step named by its words (upgrade run)

private func routineStepByWordsTests() {
    let steps = ["check the weather in orlando", "tell me today's schedule", "open Notes"]
    for words in ["the open notes step", "open notes", "the Open Notes step", "opening notes", "the notes one", "notes", "that open notes step"] {
        check(ArisRoutineStepPick.index(of: words, in: steps) == 2, "routine step by words: “\(words)” is step 3 (“open Notes”)")
    }
    check(ArisRoutineStepPick.index(of: "the weather step", in: steps) == 0 && ArisRoutineStepPick.index(of: "checking the weather", in: steps) == 0
          && ArisRoutineStepPick.index(of: "the schedule one", in: steps) == 1, "routine step by words: any step is found by the words only it holds")
    check(ArisRoutineStepPick.index(of: "step 3", in: steps) == 2 && ArisRoutineStepPick.index(of: "the last step", in: steps) == 2
          && ArisRoutineStepPick.index(of: "the second step", in: steps) == 1 && ArisRoutineStepPick.index(of: "#1", in: steps) == 0,
          "routine step by words: a number, an ordinal and “last” still name a step")
    let korean = ["메일 확인해 줘", "오늘 일정 알려 줘", "메모 열어 줘"]
    check(ArisRoutineStepPick.index(of: "메일 확인하는 거", in: korean) == 0 && ArisRoutineStepPick.index(of: "메모 여는 거", in: korean) == 2
          && ArisRoutineStepPick.index(of: "일정 알려 주는 단계", in: korean) == 1 && ArisRoutineStepPick.index(of: "메모", in: korean) == 2,
          "routine step by words: the same in Korean, whatever the verb's form")
    // Words that fit two steps find both, and the answer lists them and asks.
    let twice = ["open Notes", "check my mail", "open Notes and write today's date"]
    check(ArisRoutineStepPick.matches(of: "the open notes step", in: twice) == [0, 2] && ArisRoutineStepPick.index(of: "the open notes step", in: twice) == nil,
          "routine step by words: words that fit two steps pick neither")
    let routine = vm2Routine("morning", twice)
    check(ArisRoutineCopy.whichOf(routine, steps: [0, 2], korean: false)
          == "2 steps of the “morning” routine match that. Say which by its number, like “remove step 1 from my morning routine”.\n\n1. open Notes\n3. open Notes and write today's date",
          "routine step by words: two matches are listed with their numbers, and he is asked which")
    check(ArisRoutineCopy.whichOf(routine, steps: [0, 2], korean: true).hasPrefix("‘morning’ 루틴에 그 말에 맞는 단계가 2개 있어요.")
          && ArisRoutineCopy.whichOf(routine, steps: [0, 2], korean: true).hasSuffix("1. open Notes\n3. open Notes and write today's date"), "routine step by words: the same in Korean")
    check(ArisRoutineStepPick.matches(of: "slack", in: steps).isEmpty && ArisRoutineStepPick.matches(of: "the step", in: steps).isEmpty
          && ArisRoutineStepPick.matches(of: "step 9", in: steps).isEmpty && ArisRoutineStepPick.matches(of: "", in: steps).isEmpty,
          "routine step by words: words no step holds, or that only point, find none")
    // The whole sentence, as he says it.
    let morning = vm2Routine("morning", steps)
    check(ArisRoutineIntent.parse("remove the open notes step from my morning routine", routines: [morning]) == .dropStep(morning, words: "the open notes step"),
          "routine step by words: “remove the open notes step from my morning routine” asks to drop that step")
}

// MARK: - "why not?" after the AI's own refusal (upgrade run, bug 4)

private final class VM2WhyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    var time: Date { lock.withLock { now } }
    func pass(_ seconds: TimeInterval) { lock.withLock { now = now.addingTimeInterval(seconds) } }
}

private final class VM2WhyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var text: String? { lock.withLock { stored } }
    func set(_ text: String) { lock.withLock { stored = text } }
}

/// A why-desk over an empty activity log in a temp folder, with a turn the way /ask runs one and a why-question after.
private final class VM2WhyRig {
    let clock = VM2WhyClock()
    let desk: ArisWhyDesk
    private var streams = 0

    init() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-vm2-why-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let clock = clock
        desk = ArisWhyDesk(tools: "/x/aris-tools", log: folder.appendingPathComponent("activity.jsonl"), memories: { [] }, clock: { clock.time })
    }

    func turn(_ request: String, brain: ArisBrain? = .claude, answer: String, during: (ArisWhyDesk, String) -> Void = { _, _ in }) {
        streams += 1
        let stream = "vm2-\(streams)"
        _ = desk.turn(ArisWhyStart(request: request), context: nil, caller: .init(), on: stream) { _ in }
        if let brain { desk.asking(brain, instead: brain, on: stream) }
        clock.pass(1)
        during(desk, stream)
        desk.heard(.answer(answer), on: stream)
        clock.pass(1)
    }

    /// The answer from the record, or nil when the question was left to the AI.
    func why(_ question: String, after heard: String, reply: String) -> String? {
        streams += 1
        let done = DispatchSemaphore(value: 0)
        let box = VM2WhyBox()
        let context = "now: Wednesday, 2026-11-11 10:00 (Asia/Seoul)\nfront app: Finder\nrecent:\n- user: \(heard)\n  you: \(reply)"
        let taken = desk.turn(ArisWhyStart(request: question), context: context, caller: .init(), on: "vm2-\(streams)") { text in
            box.set(text)
            done.signal()
        }
        guard taken else {
            desk.heard(.answer("(the AI's answer)"), on: "vm2-\(streams)")
            return nil
        }
        return done.wait(timeout: .now() + 5) == .success ? box.text : "(no answer in time)"
    }
}

private func vm2Lead(_ answer: String?) -> String? {
    answer?.components(separatedBy: "\n").first.map { $0.replacingOccurrences(of: "<say>", with: "").replacingOccurrences(of: "</say>", with: "") }
}

private func whyNotAfterTheAIsOwnRefusalTests() {
    // The VM's turn: the AI refused in its own words; no command was tried, so the gate saw nothing.
    let refusedByAI = "I can't pay bills or make payments — that's something Aris won't do."
    let rig = VM2WhyRig()
    rig.turn("pay my phone bill", answer: refusedByAI)
    let answer = rig.why("why not?", after: "pay my phone bill", reply: refusedByAI)
    check(answer != nil, "why not: after a request the AI turned down itself, “why not?” is answered from the record, not by the AI")
    check(vm2Lead(answer) == "Aris's rules didn't refuse that. Claude answered in its own words, and no command was tried. Your request does have a word about paying, and Aris never pays, orders, subscribes or moves money.",
          "why not: it says Aris's rules refused nothing, who answered, that nothing was tried, and the money rule their words point at")
    let copy = ArisWhyCopy(korean: false)
    check(answer?.contains("- " + copy.label(copy.requestLabel, "“pay my phone bill”")) == true && answer?.contains("- " + copy.label(copy.insteadLabel, "That part is yours to do.")) == true
          && answer?.contains("Nothing was refused by Aris's gate. Your request has a word about paying: Aris never pays, orders, subscribes or moves money.") == true,
          "why not: the list has the request, the rule in plain words and what he can do instead")
    check(answer?.contains("I don't know") == false && answer?.contains("that wasn't done:") == false, "why not: nothing is guessed, and no gate refusal is claimed")
    // Korean, and a request with no rule known: only that Aris did not refuse it and the AI answered in its own words.
    let korean = VM2WhyRig()
    korean.turn("휴대폰 요금 결제해 줘", answer: "결제는 제가 할 수 없어요.")
    check(vm2Lead(korean.why("왜 안 돼?", after: "휴대폰 요금 결제해 줘", reply: "결제는 제가 할 수 없어요."))
          == "Aris의 규칙이 막은 건 아니에요. Claude가 자기 말로 답한 거예요, 실행하려던 명령도 없었고요. 다만 요청에 돈을 내는 말이 있는데, 돈이 드는 일은 할 수 없어요.",
          "why not: the same in Korean, with the gate's own money line")
    let plain = VM2WhyRig()
    plain.turn("book me a table at the italian place", answer: "I can't book tables.")
    let unknown = plain.why("why can't you?", after: "book me a table at the italian place", reply: "I can't book tables.")
    check(vm2Lead(unknown) == "Aris's rules didn't refuse that. Claude answered in its own words, and no command was tried.",
          "why not: where no rule is known it says only that Aris did not refuse it and the AI answered in its own words")
    check(unknown?.contains(copy.label(copy.insteadLabel, "")) == false && unknown?.contains(copy.ruleNothing) == true, "why not: and offers nothing it does not know")
    // A question he asked is about what the AI said: still the AI's to answer (as is a bare “why?”).
    let asked = VM2WhyRig()
    asked.turn("can i use while instead of for here?", answer: "Not here.")
    check(asked.why("why not?", after: "can i use while instead of for here?", reply: "Not here.") == nil, "why not: after a question he asked, “why not?” is about the AI's answer and goes to the AI")
    asked.turn("book me a table at the italian place", answer: "I can't book tables.")
    check(asked.why("why?", after: "book me a table at the italian place", reply: "I can't book tables.") == nil, "why not: a bare “why?” with no card and no refusal is the AI's, as before")
    // A turn that ran something or showed a card is not this case.
    check(ArisWhyDeclined.asksAQuestion("is it ok to pay later?") && ArisWhyDeclined.asksAQuestion("for 문 대신 while 써도 돼?") && ArisWhyDeclined.asksAQuestion("while 써도 돼")
          && !ArisWhyDeclined.asksAQuestion("pay my phone bill") && !ArisWhyDeclined.asksAQuestion("can you pay my phone bill?") && !ArisWhyDeclined.asksAQuestion("요금 내 줄래?"),
          "why not: a question is told from a request, and “can you …?” is a request")
    check(ArisWhyDeclined.readsAsMoney("pay my phone bill") && ArisWhyDeclined.readsAsMoney("buy me the new album") && ArisWhyDeclined.readsAsMoney("엄마한테 5만원 송금해 줘")
          && !ArisWhyDeclined.readsAsMoney("find my payment history") && !ArisWhyDeclined.readsAsMoney("open my mail") && !ArisWhyDeclined.readsAsMoney("book me a table"),
          "why not: money is read with the gate's own word lists (a word that only looks something up is not paying)")
    check(ArisWhyDeclined.lead(brain: nil, ranNothing: true, rule: nil, korean: false) == "Aris's rules didn't refuse that. Aris answered it itself, without an AI."
          && ArisWhyDeclined.lead(brain: "Claude", ranNothing: false, rule: nil, korean: false) == "Aris's rules didn't refuse that. Claude answered in its own words.",
          "why not: “no command was tried” is said only when none was")
}
#endif
