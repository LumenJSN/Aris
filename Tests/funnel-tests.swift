// The answer() funnel (ARCHITECTURE.md 3.1, migration step 3): which branch takes a turn, as a golden table.
//
// Each row is a sentence, the moment it is said in (a conversation open, the new-teammate card up, a teammate or an
// open to-do of that name) and the branch that takes it. `legacyBranch` is the chain answer() ran before the funnel,
// transcribed line by line from ArisController.swift at ce0683cd with its lookups stubbed (no router key, no files,
// no circled shots); the table is what it gave.

import Foundation

struct FunnelWorld {
    var conversation = false
    var afterQuestion = false
    var cardUp = false
    var teammates: [ArisTeammate] = []
    /// The open to-dos "<…> 다 했어" can name exactly.
    var open: Set<String> = []
    /// The apps this Mac has.
    var apps: Set<String> = ["Safari", "Notes", "Calculator", "Microsoft Excel", "KakaoTalk", "TextEdit", "Music"]

    static let plain = FunnelWorld()
    static let talking = FunnelWorld(conversation: true)
    static let card = FunnelWorld(cardUp: true)
    static let team = FunnelWorld(teammates: [ArisTeammate(id: "mate-codi", name: "코디", role: "문서 정리 담당", look: .standard, brain: "antigravity",
                                                           memoryFile: "teammates/mate-codi.md")])
    static let todo = FunnelWorld(open: ["우유 사기"])
}

/// answer()'s chain before the funnel (ArisController.swift ce0683cd, lines 867-1099), the branch it took.
func legacyBranch(_ said: String, _ world: FunnelWorld) -> String {
    let heard = said
    let shots = false
    let handOff = shots ? nil : ArisBrainHandOff.parse(ArisPendingFiles.words(of: heard), teammates: world.teammates)
    let named = handOff == nil ? ArisBrain.pick(from: heard) : nil
    let whole = named?.request ?? heard
    let unmarked = ArisPendingFiles.words(of: whole)
    let text = whole
    let brain = named?.brain ?? .claude
    let asksSessions = handOff == nil && !shots && ClaudeSessionsContext.asks(unmarked)
    let madeAnswer = !shots && named == nil ? ArisTeamMadeAnswer.reply(unmarked, cardUp: world.cardUp) : nil
    if !shots, madeAnswer == nil, world.conversation, ArisFollowUp.isDone(ArisPendingFiles.words(of: text), afterQuestion: world.afterQuestion) {
        return "done"
    }
    let fx = !shots && named == nil && madeAnswer == nil ? ArisCurrencyRead.parse(unmarked, home: "KRW") : nil
    var intent = named == nil ? ArisGestureTurn.intent(unmarked: unmarked, marked: text, hasShots: shots) : .ask(text)
    // No router key: the router answers nothing, the tier stays quick.
    let browserWork = false
    _ = brain
    if named == nil, !shots { intent = ArisIntent.guarded(intent, said: unmarked) }
    let plain = !shots && named == nil && madeAnswer == nil
    let link = plain ? ArisSkillIntent.link(in: unmarked) : nil
    let removal: ArisTeamRemoval? = plain && link == nil ? {
        guard ArisTeamRemoval.parse(unmarked, teammates: world.teammates + [.claudeCode]) != nil || unmarked.contains("팀원")
                || unmarked.range(of: #"(?i)\bteammate\b"#, options: .regularExpression) != nil else { return nil }
        return ArisTeamRemoval.parse(unmarked, teammates: world.teammates)
    }() : nil
    let making = plain && link == nil && removal == nil ? ArisTeamMaking.parse(unmarked) : nil
    let called = plain && link == nil && removal == nil && making == nil ? ArisTeamRouting.directJob(unmarked, teammates: world.teammates) : nil
    var finishing = false
    if case .finishTodo(let item) = intent { finishing = world.open.contains(item) }
    let handing = plain && link == nil && removal == nil && making == nil ? handOff.flatMap { called != nil && $0.task != nil ? nil : $0 } : nil
    if madeAnswer != nil { return "madeCard" }
    if link != nil { return "skillLink" }
    if removal != nil { return "removeTeammate" }
    if making != nil { return "makeTeammate" }
    if handing != nil { return "handOff" }
    if called != nil { return "teammate" }
    if fx != nil { return "currency" }
    if ArisMemoryImportWords.asked(unmarked) != nil { return "memoryImport" }
    if plain, ArisModelVoice.parse(unmarked) != nil { return "modelChange" }
    if case .timerLeft = intent { return "timerLeft" }
    if case .listTodos = intent { return "listTodos" }
    if case .addTodo = intent { return "addTodo" }
    if finishing { return "finishTodo" }
    if case .brief = intent { return "brief" }
    if case .dayEnd = intent { return "dayEnd" }
    if case .undo = intent { return "undo" }
    if case .readAgain = intent { return "readAgain" }
    if case .saveAnswer = intent { return "saveAnswer" }
    if case .arrange = intent { return "arrange" }
    if case .media = intent { return "media" }
    if case .whatsPlaying = intent { return "whatsPlaying" }
    if ArisControl(intent) != nil { return "control" }
    switch intent {
    case .tellTime, .tellDate, .arisMute, .quietHours: return "onMac"
    case .openApp(let name): if world.apps.contains(name) { return "onMac" }
    default: if ArisTimerChange.plan(intent, running: false, paused: false, korean: true) != nil { return "onMac" }
    }
    if !shots, ArisHandoff.isHandoff(unmarked) || browserWork { return "background" }
    if !shots, !asksSessions, ArisDeixis.refersToScreen(text) || ArisDeixis.refersToClipboard(unmarked) { return "screen" }
    return "brain"
}

/// One row of the golden table: the words, the moment, the branch that takes them.
struct FunnelRow {
    let said: String
    let world: FunnelWorld
    let branch: String
    /// The branch before the local-intent fixes, for a row whose route changed on purpose.
    let was: String?

    init(_ said: String, _ branch: String, _ world: FunnelWorld = .plain, was: String? = nil) {
        self.said = said
        self.world = world
        self.branch = branch
        self.was = was
    }
}

/// The golden table: every branch, Korean and English, and the sentences the audit found taken by a keyword.
let funnelGolden: [FunnelRow] = [
    // The new-teammate card and the done words.
    FunnelRow("응", "madeCard", .card), FunnelRow("아니", "madeCard", .card), FunnelRow("응", "brain"),
    FunnelRow("됐어", "done", .talking), FunnelRow("고마워", "done", .talking), FunnelRow("thanks", "done", .talking), FunnelRow("됐어", "brain"),
    // Skills, teammates, hand-offs.
    FunnelRow("이 링크 스킬 추가해줘 https://github.com/foo/bar", "skillLink"),
    FunnelRow("코디 팀원 지워 줘", "removeTeammate", .team),
    FunnelRow("문서 정리하는 팀원 하나 만들어줘, 이름은 코디", "makeTeammate"),
    FunnelRow("아니 그냥 클로드 시켜", "handOff"), FunnelRow("이거 코덱스한테 맡겨", "handOff"),
    FunnelRow("코디, 이 문서 정리해 줘", "teammate", .team),
    // Currency, memory import.
    FunnelRow("100 위안 캐나다 달러로 얼마야", "currency"), FunnelRow("다른 AI에서 기억 가져올래", "memoryImport"),
    // jv-models: the conversation's model or effort, said.
    FunnelRow("모델 오퍼스로 바꿔", "modelChange"), FunnelRow("always use sonnet", "modelChange"), FunnelRow("이번엔 깊게 생각해", "modelChange"),
    // The timer.
    FunnelRow("타이머 얼마나 남았어", "timerLeft"), FunnelRow("how much time is left on the timer", "timerLeft"),
    FunnelRow("타이머 5분", "onMac"), FunnelRow("5분 타이머 맞춰 줘", "onMac"), FunnelRow("set a timer for 10 minutes", "onMac"),
    FunnelRow("25분 집중", "onMac"), FunnelRow("타이머 꺼", "onMac"), FunnelRow("뽀모도로 시작", "onMac"),
    FunnelRow("타이머 1.5시간", "onMac"), FunnelRow("한 시간 반 타이머", "onMac"), FunnelRow("timer for 90 seconds", "onMac"),
    FunnelRow("set a timer for an hour and a half", "onMac"), FunnelRow("5분 타이머 맞춰야 할까?", "brain"),
    // To-dos.
    FunnelRow("할 일 뭐 있어", "listTodos"), FunnelRow("what's on my to-do list", "listTodos"),
    FunnelRow("할 일 추가해 우유 사기", "addTodo"), FunnelRow("우유 사기 할 일에 추가해 줘", "addTodo"),
    FunnelRow("add buy milk to my to-do list", "addTodo"), FunnelRow("remind me to call mom", "addTodo"),
    FunnelRow("우유 사기 다 했어", "finishTodo", .todo), FunnelRow("빵 사기 다 했어", "brain", .todo),
    FunnelRow("할 일 앱 추천해줘", "brain"), FunnelRow("오늘 할 일 정리하는 팁 알려줘", "brain"),
    // The brief, the day's end, undo, reading again, saving.
    FunnelRow("브리핑 해줘", "brief"), FunnelRow("morning briefing", "brief"), FunnelRow("오늘 정리해 줘", "dayEnd"),
    FunnelRow("방금 거 취소해", "undo"), FunnelRow("undo that", "undo"), FunnelRow("다 읽어줘", "readAgain"), FunnelRow("read it all", "readAgain"),
    FunnelRow("방금 답을 orlando.txt 파일로 저장해 줘", "saveAnswer"),
    // Windows, music, what's playing.
    FunnelRow("엑셀 4개 켜서 4등분", "arrange"), FunnelRow("open 4 excel windows in a grid", "arrange"),
    FunnelRow("노래 꺼줘", "media"), FunnelRow("다음 곡", "media"), FunnelRow("pause the music", "media"), FunnelRow("next song", "media"),
    FunnelRow("노래 틀어 줘", "media"), FunnelRow("유튜브에서 아이유 노래 틀어줘", "brain"),
    FunnelRow("지금 무슨 노래야?", "whatsPlaying"), FunnelRow("what's playing", "whatsPlaying"),
    // Volume and brightness.
    FunnelRow("볼륨 올려", "control"), FunnelRow("볼륨 50", "control"), FunnelRow("소리 좀 줄여", "control"), FunnelRow("볼륨 낮춰 줘", "control"),
    FunnelRow("아리스, 볼륨 좀 올려 줄래?", "control"), FunnelRow("화면 밝게 해 줘", "control"), FunnelRow("밝기 낮춰", "control"),
    FunnelRow("turn the sound down", "control"), FunnelRow("louder", "control"), FunnelRow("set the volume to 30", "control"),
    FunnelRow("볼륨 조금 줄여", "control"), FunnelRow("볼륨 10 줄여", "control"), FunnelRow("turn the volume down a bit", "control"),
    FunnelRow("볼륨 크게 들으면 귀에 안 좋아?", "brain"), FunnelRow("밝기 조절하는 단축키 뭐야", "brain"),
    // The time, the date, apps, Aris's own mute.
    FunnelRow("지금 몇 시야", "onMac"), FunnelRow("오늘 며칠이야", "onMac"), FunnelRow("what time is it", "onMac"),
    FunnelRow("사파리 열어 줘", "onMac"), FunnelRow("open safari", "onMac"), FunnelRow("포토샵 열어 줘", "brain"), FunnelRow("조용히 해 줘", "onMac"),
    // Background work, the screen, the brain.
    FunnelRow("보고서 조사해서 정리해 놔", "background"), FunnelRow("let me know when you're done with the summary", "background"), FunnelRow("이 화면 뭐야", "screen"), FunnelRow("what's on my screen", "screen"),
    FunnelRow("오늘 날씨 어때", "brain"), FunnelRow("파이썬으로 피보나치 함수 짜 줘", "brain"), FunnelRow("what's the capital of france", "brain"),
    FunnelRow("메모 앱 열고 어제 회의 내용 정리해 줘", "brain"),
    // The audit's hijacks (intent-3): a keyword inside a longer sentence, a story, a question about something else.
    // Changed on purpose by the whole-utterance rule (and the to-do question): `was` is the branch before.
    FunnelRow("아이가 소리를 너무 크게 내서 조용히 시키는 법", "brain", was: "control"),
    FunnelRow("엄마가 소리 좀 낮춰 달래", "brain", was: "control"),
    FunnelRow("어제 볼륨 최대로 했다가 귀 아팠어", "brain", was: "control"),
    FunnelRow("louder music makes me happy", "brain", was: "control"),
    FunnelRow("타이머 10분짜리 영상 찾아줘", "brain", was: "onMac"),
    FunnelRow("my timer app shows 5 minutes", "brain", was: "onMac"),
    FunnelRow("할 일 목록에 넣어둔 거 뭐야", "listTodos", was: "addTodo"),
    FunnelRow("회의 끝나고 다음 곡 작업 시작해야 해", "brain", was: "media"),
    FunnelRow("스킵 버튼이 안 눌려", "brain", was: "media"),
    FunnelRow("the next song on this album is my favorite", "brain", was: "media"),
    FunnelRow("재생 목록 정리해 줘", "brain"),
    // Joined on, or asking: already the AI's.
    FunnelRow("내 친구가 볼륨 올려서 시끄러웠어", "brain"),
    FunnelRow("어제 5분 동안 타이머 맞춰 놓고 공부했어", "brain"),
    FunnelRow("이 노래 재생 시간이 얼마나 돼", "brain"),
    FunnelRow("i turned the volume up and my speaker broke", "brain"),
    FunnelRow("pause for a moment and think about this", "screen"),
    FunnelRow("the volume of a sphere formula", "brain"),
    FunnelRow("피곤해서 집중이 안 돼", "brain"),
]

/// The funnel's host with the moment's lists: no router key (the router is never answered), nothing done.
@MainActor
final class FunnelStubHost: ArisTurnHost {
    let world: FunnelWorld
    var routerAsked: [String] = []
    init(_ world: FunnelWorld) { self.world = world }

    func hear(_ request: ArisTurnRequest) async -> ArisTurnRequest.Heard {
        let handOff = request.gesture?.hasShots == true ? nil : ArisBrainHandOff.parse(ArisPendingFiles.words(of: request.said), teammates: world.teammates)
        return .make(heard: request.said, gesture: request.gesture, handOff: handOff,
                     moment: .init(conversationOpen: world.conversation, afterQuestion: world.afterQuestion, teammateCardUp: world.cardUp))
    }
    func routed(_ words: String) async -> ArisTurnRequest.Routed {
        routerAsked.append(words)
        return ArisTurnRequest.Routed(intent: nil, tier: .quick, browserWork: false)
    }
    func teammateRemoval(_ words: String) async -> ArisTeamRemoval? {
        guard ArisTeamRemoval.parse(words, teammates: world.teammates + [.claudeCode]) != nil || words.contains("팀원")
                || words.range(of: #"(?i)\bteammate\b"#, options: .regularExpression) != nil else { return nil }
        return ArisTeamRemoval.parse(words, teammates: world.teammates)
    }
    func teammateCalled(_ words: String) async -> ArisJobSpec? { ArisTeamRouting.directJob(words, teammates: world.teammates) }
    func finishable(_ item: String) async -> ArisTodoFinishable? {
        world.open.contains(item) ? .reminder(ArisTodoItem(id: "t1", title: item, notes: nil, due: nil, hasTime: false, listID: "l", listName: "할 일", colorHex: "#ffffff")) : nil
    }
    func application(_ name: String) -> URL? { world.apps.contains(name) ? URL(fileURLWithPath: "/Applications/\(name).app") : nil }
    func run(_ claim: ArisTurnClaim, _ request: ArisTurnRequest) async -> String? { claim.branch }
}

/// The branch the funnel gives these words in this moment.
@MainActor
func funnelBranch(_ said: String, _ world: FunnelWorld, practice: Bool = false) async -> (branch: String, router: [String]) {
    let host = FunnelStubHost(world)
    let request = ArisTurnRequest(said: said, origin: .key, context: .init(practice: practice))
    let found = await ArisTurnFunnel.claim(request, host: host)
    return (found?.claim.branch ?? "none", host.routerAsked)
}

private final class FunnelFlag: @unchecked Sendable { var done = false }

func funnelGoldenTests() {
    // The old chain, transcribed, gives every row's branch before the fixes (it reads the same matchers, so it moves
    // with them: only the rows marked `was` may differ, and those are exactly the routes the fixes changed).
    for row in funnelGolden where row.was == nil {
        let legacy = legacyBranch(row.said, row.world)
        check(legacy == row.branch, "funnel golden (chain): “\(row.said)” -> \(row.branch) (was \(legacy))")
    }
    check(funnelGolden.filter { $0.was != nil }.map(\.said).count == 10, "funnel golden: ten routes changed on purpose, each listed with what it was")
    let flag = FunnelFlag()
    Task { @MainActor in
        for row in funnelGolden {
            let found = await funnelBranch(row.said, row.world)
            check(found.branch == row.branch, "funnel golden: “\(row.said)” -> \(row.branch) (got \(found.branch))")
        }
        // The practice turn is the first handler; the done words and the card's answer never ask the router.
        check(await funnelBranch("지금 몇 시야", .plain, practice: true).branch == "practice", "funnel: the practice turn comes first")
        let done = await funnelBranch("됐어", .talking)
        check(done.branch == "done" && done.router.isEmpty, "funnel: the done words end the turn before the router is asked")
        check(await funnelBranch("응", .card).router.isEmpty, "funnel: the card's answer never asks the router")
        let asked = await funnelBranch("오늘 날씨 어때", .plain)
        check(asked.branch == "brain" && asked.router == ["오늘 날씨 어때"], "funnel: words left to the AI ask the router once")
        check(await funnelBranch("지금 몇 시야", .plain).router.isEmpty, "funnel: a matched request never asks the router")
        check(ArisTurnFunnel.handlers.last is ArisBrainHandler && ArisTurnFunnel.handlers.first is ArisPracticeHandler,
              "funnel: the practice turn first, the brain last")
        flag.done = true
    }
    while !flag.done { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
}

func funnelSourceTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("..")
    func source(_ path: String) -> String { (try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? "" }
    let controller = source("Aris/private/Aris/ArisController.swift")
    let funnel = source("Aris/private/Aris/Routing/ArisController+Funnel.swift")
    check(!controller.contains("func answer(") && funnel.contains("guard let found = await ArisTurnFunnel.claim(request, host: self) else { return }"),
          "funnel wiring: answer() builds the request and walks the funnel")
    let runs = source("Aris/private/Aris/Routing/ArisController+TurnRuns.swift")
    check(runs.contains("func run(_ claim: ArisTurnClaim, _ request: ArisTurnRequest) async -> String?"), "funnel wiring: the claims are done in the app")
}

// MARK: - The local intents' fixes (audit intent-3, timers, levels, to-dos, tier, helper token, read-back)

func funnelWholeCommandTests() {
    for said in ["엄마가 소리 좀 낮춰 달래", "아이가 소리를 너무 크게 내서 조용히 시키는 법", "어제 볼륨 최대로 했다가 귀 아팠어", "louder music makes me happy",
                 "타이머 10분짜리 영상 찾아줘", "my timer app shows 5 minutes", "타이머 몇 분 남았는지 친구한테 문자 보내 줘",
                 "회의 끝나고 다음 곡 작업 시작해야 해", "스킵 버튼이 안 눌려", "the next song on this album is my favorite", "밝기 때문에 눈이 아파 밝기 낮춰야 하나"] {
        check(ArisIntent.parse(said) == .ask(said), "whole command: “\(said)” is the AI's, not a local action (was \(ArisIntent.parse(said)))")
    }
    check(ArisIntent.guarded(.media(.next), said: "회의 끝나고 다음 곡 작업 시작해야 해") == .ask("회의 끝나고 다음 곡 작업 시작해야 해")
          && ArisIntent.guarded(.volume(.up), said: "엄마가 소리 좀 낮춰 달래") == .ask("엄마가 소리 좀 낮춰 달래"),
          "whole command: the router's guess passes the same rule")
    let kept: [(String, ArisIntent)] = [
        ("아리스, 볼륨 좀 올려 줄래?", .volume(.up)), ("볼륨 낮춰 줘", .volume(.down)), ("소리 좀 줄여", .volume(.down)), ("볼륨 50", .volume(.set(50))),
        ("볼륨 30으로 맞춰 줘", .volume(.set(30))), ("louder", .volume(.up)), ("set the volume to 30", .volume(.set(30))), ("turn the sound down", .volume(.down)),
        ("밝기 낮춰", .brightness(.down)), ("화면 밝게 해 줘", .brightness(.up)), ("밝기 최대로", .brightness(.set(100))),
        ("타이머 5분", .timer(seconds: 300, focus: false)), ("5분 타이머 맞춰 줘", .timer(seconds: 300, focus: false)),
        ("set a timer for 10 minutes", .timer(seconds: 600, focus: false)), ("25분 집중", .timer(seconds: 1_500, focus: true)), ("타이머 꺼", .cancelTimer),
        ("타이머 5분 추가", .addTime(300)), ("타이머 얼마나 남았어", .timerLeft), ("how much time is left on the timer", .timerLeft), ("뽀모도로 시작", .pomodoro),
        ("노래 꺼줘", .media(.pause)), ("다음 곡", .media(.next)), ("pause the music", .media(.pause)), ("next song", .media(.next)), ("노래 틀어 줘", .media(.play)),
        ("이 곡 넘겨", .media(.next)), ("play", .media(.play)),
    ]
    for (said, intent) in kept { check(ArisIntent.parse(said) == intent, "whole command: “\(said)” is still \(intent) (got \(ArisIntent.parse(said)))") }
}

func funnelTimerTests() {
    let lengths: [(String, Int)] = [("타이머 1.5시간", 5_400), ("한 시간 반 타이머", 5_400), ("1시간 30분 타이머", 5_400), ("타이머 한시간반", 5_400),
                                    ("5분 반 타이머 맞춰 줘", 330), ("2.5분 타이머", 150), ("timer for 90 seconds", 90), ("set a timer for an hour and a half", 5_400),
                                    ("set a timer for 1.5 hours", 5_400), ("두 시간 반 타이머", 9_000)]
    for (said, seconds) in lengths {
        check(ArisIntent.parse(said) == .timer(seconds: seconds, focus: false), "timer: “\(said)” is \(seconds) s (got \(ArisIntent.parse(said)))")
    }
    check(ArisIntent.parse("타이머 30초 추가") == .addTime(30), "timer: added time reads its length too")
}

func funnelLevelTests() {
    let levels: [(String, ArisIntent)] = [
        ("볼륨 10 줄여", .volume(.change(.by(-10)))), ("볼륨 조금 줄여", .volume(.change(.steps(-0.5)))), ("소리 살짝 키워 줘", .volume(.change(.steps(0.5)))),
        ("볼륨 반으로 줄여", .volume(.change(.scaled(0.5)))), ("볼륨 많이 올려", .volume(.change(.steps(2)))), ("볼륨 두 칸 올려", .volume(.change(.steps(2)))),
        ("turn the volume down a bit", .volume(.change(.steps(-0.5)))), ("turn the volume up by 20", .volume(.change(.by(20)))),
        ("밝기 조금 올려", .brightness(.change(.steps(0.5)))), ("밝기 20 낮춰", .brightness(.change(.by(-20)))), ("볼륨 30으로 올려", .volume(.set(30))),
    ]
    for (said, intent) in levels { check(ArisIntent.parse(said) == intent, "level: “\(said)” is \(intent) (got \(ArisIntent.parse(said)))") }
    check(ArisControl.target(.change(.by(-10)), current: 50, step: 6) == 40 && ArisControl.target(.change(.scaled(0.5)), current: 60, step: 6) == 30
          && ArisControl.target(.set(30), current: 60, step: 6) == nil && ArisControl.target(.up, current: 60, step: 6) == nil,
          "level: a relative change is resolved from the level now; up, down and mute keep the device's own step")
}

func funnelTodoTests() {
    check(ArisIntent.parse("할 일 목록에 넣어둔 거 뭐야") == .listTodos && ArisIntent.parse("할 일에 뭐 적어 놨어") == .listTodos
          && ArisIntent.parse("what did i put on my to-do list") == .listTodos,
          "to-do: a question about the list reads it")
    for said in ["할 일에 우유 넣어 놨나", "할 일에 뭐 넣어 둘까", "할 일 목록에 넣어둔 거 몇 개야"] {
        if case .addTodo = ArisIntent.parse(said) { check(false, "to-do: “\(said)” adds nothing") } else { check(true, "to-do: “\(said)” adds nothing") }
    }
    check(ArisIntent.parse("우유 사기 할 일에 추가해 줘") == .addTodo("우유 사기") && ArisIntent.parse("할 일 추가해 우유 사기") == .addTodo("우유 사기")
          && ArisIntent.parse("할 일에 우유 사기 넣어 줘") == .addTodo("우유 사기"),
          "to-do: an instruction still adds one")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check(ArisTodoDate.parse("오늘의 집 앱 정리", now: now) == ("오늘의 집 앱 정리", nil) && ArisTodoDate.parse("watch Tomorrow Never Dies", now: now).due == nil
          && ArisTodoDate.parse("watch Tomorrow Never Dies", now: now).text == "watch Tomorrow Never Dies"
          && ArisTodoDate.parse("‘내일의 나’ 읽기", now: now).text == "‘내일의 나’ 읽기" && ArisTodoDate.parse("\"Today\" 노래 듣기", now: now).due == nil,
          "to-do: a date word that is part of the name stays in it")
    let dated = ArisTodoDate.parse("내일 우유 사기", now: now), english = ArisTodoDate.parse("buy milk tomorrow", now: now)
    check(dated.text == "우유 사기" && dated.due != nil && english.text == "buy milk" && english.due != nil && ArisTodoDate.parse("내일까지 보고서", now: now).due != nil,
          "to-do: a date word that is a date is the due date")
}

func funnelHelperAndReadBackTests() {
    let missing = ArisAgentCopy.notSetUp(helperInstalled: true, english: false), english = ArisAgentCopy.notSetUp(helperInstalled: true, english: true)
    check(!missing.contains("개발용") && missing.contains("다시 시작") && !english.contains("developer build") && english.contains("Restart"),
          "helper token: a missing key says the helper hasn't made it, not that this is a developer build")
    check(ArisAgentCopy.notSetUp(helperInstalled: false, english: false) == ArisPrerequisites.full(.helper, english: false),
          "helper token: with no helper inside the app the line is as before")
    check(ArisIntent.timer(seconds: 300, focus: false).acknowledgement(korean: false) == "Timer set for 5 minutes."
          && ArisIntent.timer(seconds: 90, focus: true).acknowledgement(korean: false) == "Focus for 1 minute 30 seconds."
          && ArisIntent.addTime(30).acknowledgement(korean: false) == "Added 30 seconds to the timer."
          && ArisIntent.timer(seconds: 5_400, focus: false).acknowledgement(korean: true) == "1시간 30분 타이머 맞췄어요.",
          "read-back: the timer's line names its length, in English too")
    check(ArisControl.volume(.up).reply(changed: true, korean: true, level: 44) == "볼륨을 44로 올렸어요."
          && ArisControl.volume(.change(.by(-10))).reply(changed: true, korean: true, level: 40) == "볼륨을 40으로 낮췄어요."
          && ArisControl.volume(.up).reply(changed: true, korean: false, level: 44) == "Volume up to 44."
          && ArisControl.volume(.mute).reply(changed: true, korean: true, level: nil, muted: true) == "소리를 껐어요."
          && ArisControl.volume(.mute).reply(changed: true, korean: false, level: nil, muted: false) == "Sound back on."
          && ArisControl.brightness(.change(.steps(0.5))).reply(changed: true, korean: true, level: 58) == "밝기를 58로 올렸어요.",
          "read-back: a volume or brightness change says where it went; mute says which way")
    check(ArisIntent.openApp("TextEdit").acknowledgement(korean: true) == "텍스트 편집기를 열었어요." && ArisIntent.openApp("Safari").acknowledgement(korean: false) == "Opened Safari.",
          "read-back: opening an app says it was opened, by the name the user sees")
}

func funnelTierTests() {
    for said in ["오늘 날씨 어때", "what's the capital of france", "17 곱하기 23은?"] {
        check(ArisTurnRequest.Routed.withoutRouter(said).tier == .quick, "tier: without the router “\(said)” is quick")
    }
    for said in ["프로젝트 어떻게 되고 있어", "이 화면 설명해 줘", "report.pdf 요약해 줘", "알아봐 줘 다음 주 올랜도 날씨",
                 "이번 주 회의록을 정리해서 팀원들한테 보낼 메일 초안을 세 가지 버전으로 써 주고 제목도 붙여 줘"] {
        check(ArisTurnRequest.Routed.withoutRouter(said).tier == .work, "tier: without the router “\(said)” is work")
    }
    let controller = (try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Aris/private/Aris/ArisController.swift"), encoding: .utf8)) ?? ""
    // jv-router: with no model to ask (no Jev key and no API profile: the keyword rules) the words' own tier, as before.
    check(controller.contains("if route == .rules { return (nil, unrouted.tier, false) }")
          && controller.contains("return (nil, unrouted.tier, false)\n        }"), "tier: routeNow (and the early request with it) reads the words without the key")
}

func funnelBrainTurnStateTests() {
    var state = ArisBrainTurnState()
    state.answered(allow: false, unanswered: true, stopped: false, waiting: ["mail"])
    check(state.cardUnanswered && !state.cardDeclined && state.holdsAnswer && state.declinedTools == ["mail"], "brain turn: an unanswered card holds the answer")
    state.answered(allow: true, unanswered: false, stopped: false, waiting: [])
    check(state.cardApproved && state.declinedTools.isEmpty, "brain turn: a later yes clears the steps a no dropped")
    var stopped = ArisBrainTurnState()
    stopped.answered(allow: true, unanswered: false, stopped: true, waiting: [])
    check(!stopped.cardApproved, "brain turn: 그래도 하기 on the check's stopped card approves nothing")
    let fresh = ArisBrainTurnState()
    check(!fresh.untrustedTurn && !fresh.holdsAnswer && fresh.turnId == nil && fresh.declinedTools.isEmpty, "brain turn: every turn starts clean")
}

func runFunnelTests() {
    funnelBrainTurnStateTests()
    funnelTierTests()
    funnelGoldenTests()
    funnelSourceTests()
    funnelWholeCommandTests()
    funnelTimerTests()
    funnelLevelTests()
    funnelTodoTests()
    funnelHelperAndReadBackTests()
}
