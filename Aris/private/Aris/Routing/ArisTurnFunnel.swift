//
//  ArisTurnFunnel.swift
//  Aris
//
//  Every turn converges on answer(); this is its funnel as data (ARCHITECTURE.md 3.1, migration step 3). Handlers are
//  asked in order whether they claim the request, the first claim wins, and the brain claims whatever is left. A
//  handler only claims: what a claim does is the host's (ArisController+TurnRuns), so the order and the claims are
//  pure and the golden table (tests/funnel-tests.swift) checks them, while doing it stays in the app with AppKit.
//

import Foundation

/// What the funnel needs from the app: the request read further, the lookups a claim needs, and the claim done.
@MainActor
protocol ArisTurnHost: AnyObject {
    /// The files given to Aris taken in, the hand-off looked up, and what the words settle (ArisTurnRequest.Heard.make).
    func hear(_ request: ArisTurnRequest) async -> ArisTurnRequest.Heard
    /// The router asked about their words (its answer from the pause when the hearing asked early).
    func routed(_ words: String) async -> ArisTurnRequest.Routed
    /// "큐에이봇 팀원 지워 줘", with the teammates' list read first.
    func teammateRemoval(_ words: String) async -> ArisTeamRemoval?
    /// The teammate the words call by name with their task, with the list read first.
    func teammateCalled(_ words: String) async -> ArisJobSpec?
    /// The one open to-do the words name exactly.
    func finishable(_ item: String) async -> ArisTodoFinishable?
    /// Where this Mac has the app of that name.
    func application(_ name: String) -> URL?
    /// Does the claim; the reply to remember, or nil when the turn ended inside it (failed, stopped, said already).
    func run(_ claim: ArisTurnClaim, _ request: ArisTurnRequest) async -> String?
}

/// What a handler claims a turn for, with what it found in the words.
enum ArisTurnClaim {
    case practice
    case madeCard(yes: Bool)
    case done
    case skillLink(String)
    case removeTeammate(ArisTeamRemoval)
    case makeTeammate(ArisTeamMaking.Request)
    case handOff(ArisBrainHandOff)
    case teammate(ArisJobSpec)
    case currency(ArisCurrencyAsk)
    case memoryImport(ArisMemoryImportWords.Asked)
    /// "모델 오퍼스로 바꿔", "이번엔 깊게 생각해": the 대화 model or effort (ArisModelVoice).
    case modelChange(ArisModelVoiceCommand)
    case timerLeft
    case listTodos
    case addTodo(String)
    case finishTodo(ArisTodoFinishable)
    case brief
    case dayEnd
    case undo
    case readAgain
    case saveAnswer(ArisSaveAnswer)
    case arrange(app: String, count: Int)
    case media(ArisIntent.Media)
    case whatsPlaying
    case control(ArisControl)
    /// The time, the date, the timer, Aris's own mute and quiet hours, an app this Mac has opened.
    case onMac(ArisIntent)
    /// "해 놔", "끝나면 알려줘", or several steps on websites: a background job.
    case background(browser: Bool)
    case screen
    case brain

    /// The branch as the golden table and the log name it.
    var branch: String {
        switch self {
        case .practice: return "practice"
        case .madeCard: return "madeCard"
        case .done: return "done"
        case .skillLink: return "skillLink"
        case .removeTeammate: return "removeTeammate"
        case .makeTeammate: return "makeTeammate"
        case .handOff: return "handOff"
        case .teammate: return "teammate"
        case .currency: return "currency"
        case .memoryImport: return "memoryImport"
        case .modelChange: return "modelChange"
        case .timerLeft: return "timerLeft"
        case .listTodos: return "listTodos"
        case .addTodo: return "addTodo"
        case .finishTodo: return "finishTodo"
        case .brief: return "brief"
        case .dayEnd: return "dayEnd"
        case .undo: return "undo"
        case .readAgain: return "readAgain"
        case .saveAnswer: return "saveAnswer"
        case .arrange: return "arrange"
        case .media: return "media"
        case .whatsPlaying: return "whatsPlaying"
        case .control: return "control"
        case .onMac: return "onMac"
        case .background: return "background"
        case .screen: return "screen"
        case .brain: return "brain"
        }
    }

    /// Whether a claim found after the turn was stopped is still done: only the practice turn and the done words,
    /// which answer() always ran before its first look-up.
    var runsWhenStopped: Bool {
        switch self {
        case .practice, .done: return true
        default: return false
        }
    }
}

/// One step of the funnel.
@MainActor
protocol ArisTurnHandler {
    /// How the golden table names the branch.
    var name: String { get }
    /// How far the request must be read before this handler can claim it.
    var needs: ArisTurnRequest.Stage { get }
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim?
}

extension ArisTurnHandler {
    var needs: ArisTurnRequest.Stage { .read }
}

@MainActor
enum ArisTurnFunnel {
    /// The order is answer()'s chain: the practice turn, the card's answer and the done words before anything is looked
    /// up; then who the words are for (a skill link, a teammate removed or made, a hand-off, a teammate called); then
    /// Aris's own requests; then background work, the screen, and the brain.
    static let handlers: [any ArisTurnHandler] = [
        ArisPracticeHandler(), ArisMadeCardHandler(), ArisDoneHandler(),
        ArisSkillLinkHandler(), ArisTeammateRemovalHandler(), ArisTeammateMakingHandler(), ArisCalledHandler(),
        ArisCurrencyHandler(), ArisMemoryImportHandler(), ArisModelVoiceHandler(),
        ArisTimerLeftHandler(), ArisListTodosHandler(), ArisAddTodoHandler(), ArisFinishTodoHandler(),
        ArisBriefHandler(), ArisDayEndHandler(), ArisUndoHandler(), ArisReadAgainHandler(), ArisSaveAnswerHandler(),
        ArisArrangeHandler(), ArisMediaHandler(), ArisWhatsPlayingHandler(), ArisControlHandler(), ArisOnMacHandler(),
        ArisBackgroundHandler(), ArisScreenHandler(), ArisBrainHandler(),
    ]

    /// The first claim, with the request as far as it was read for it; nil when the turn was stopped first.
    static func claim(_ request: ArisTurnRequest, host: any ArisTurnHost) async -> (claim: ArisTurnClaim, request: ArisTurnRequest, by: String)? {
        var request = request
        for handler in handlers {
            if handler.needs >= .heard, request.heard == nil { request.heard = await host.hear(request) }
            if handler.needs == .read, request.reading == nil, let heard = request.heard {
                let routed = heard.asksRouter(hasApp: { host.application($0) != nil }) ? await host.routed(heard.unmarked) : nil
                request.reading = .make(heard, routed: routed)
            }
            // Stopped or replaced while the router or a list was asked: this turn does nothing more (audit turn-2).
            if handler.needs == .read, Task.isCancelled { return nil }
            guard let claim = await handler.claims(request, host) else { continue }
            guard claim.runsWhenStopped || !Task.isCancelled else { return nil }
            return (claim, request, handler.name)
        }
        return nil
    }
}

// MARK: - The handlers, in order

struct ArisPracticeHandler: ArisTurnHandler {
    let name = "practice"
    var needs: ArisTurnRequest.Stage { .said }
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? { request.context.practice ? .practice : nil }
}

/// "응" or "아니" while the new-teammate card is up answers it first, on every path (BUG-25c reopened).
struct ArisMadeCardHandler: ArisTurnHandler {
    let name = "madeCard"
    var needs: ArisTurnRequest.Stage { .heard }
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? { request.heard?.madeAnswer.map { .madeCard(yes: $0) } }
}

/// "됐어", "고마워" in a conversation just end it ("괜찮아" right after Aris asked something answers it).
struct ArisDoneHandler: ArisTurnHandler {
    let name = "done"
    var needs: ArisTurnRequest.Stage { .heard }
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? { request.heard?.done == true ? .done : nil }
}

/// "이 링크 스킬 추가해줘 <link>": Aris does it itself, no brain.
struct ArisSkillLinkHandler: ArisTurnHandler {
    let name = "skillLink"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, heard.plain else { return nil }
        return ArisSkillIntent.link(in: heard.unmarked).map { .skillLink($0) }
    }
}

/// "큐에이봇 팀원 지워 줘": asked with the settings' 빼기 card (BUG-26).
struct ArisTeammateRemovalHandler: ArisTurnHandler {
    let name = "removeTeammate"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, heard.plain else { return nil }
        return await host.teammateRemoval(heard.unmarked).map { .removeTeammate($0) }
    }
}

/// "문서 정리하는 팀원 하나 만들어줘, 이름은 코디".
struct ArisTeammateMakingHandler: ArisTurnHandler {
    let name = "makeTeammate"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, heard.plain else { return nil }
        return ArisTeamMaking.parse(heard.unmarked).map { .makeTeammate($0) }
    }
}

/// A hand-off ("아니 그냥 클로드 시켜") or a teammate called by name with its task ("코디, 이거 정리해 줘"). A teammate
/// called with a task goes the way it always did, with its files, even when the words also say a hand-off.
struct ArisCalledHandler: ArisTurnHandler {
    let name = "called"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, heard.plain else { return nil }
        let called = await host.teammateCalled(heard.unmarked)
        if let handOff = heard.handOff, !(called != nil && handOff.task != nil) { return .handOff(handOff) }
        return called.map { .teammate($0.asking(heard.whole)) }
    }
}

/// "100 위안 캐나다 달러로 얼마야": read and answered here, never the router's or a brain's.
struct ArisCurrencyHandler: ArisTurnHandler {
    let name = "currency"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? { request.heard?.fx.map { .currency($0) } }
}

/// "다른 AI에서 기억 가져올래": the import opens in Settings › 기억.
struct ArisMemoryImportHandler: ArisTurnHandler {
    let name = "memoryImport"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        request.heard.flatMap { ArisMemoryImportWords.asked($0.unmarked) }.map { .memoryImport($0) }
    }
}

/// "모델 오퍼스로 바꿔", "always use sonnet", "이번엔 깊게 생각해": a whole short command only, from the user's own plain words.
struct ArisModelVoiceHandler: ArisTurnHandler {
    let name = "modelChange"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        request.heard.flatMap { $0.plain ? ArisModelVoice.parse($0.unmarked) : nil }.map { .modelChange($0) }
    }
}

struct ArisTimerLeftHandler: ArisTurnHandler {
    let name = "timerLeft"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .timerLeft? = request.reading?.intent { return .timerLeft }
        return nil
    }
}

struct ArisListTodosHandler: ArisTurnHandler {
    let name = "listTodos"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .listTodos? = request.reading?.intent { return .listTodos }
        return nil
    }
}

struct ArisAddTodoHandler: ArisTurnHandler {
    let name = "addTodo"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .addTodo(let item)? = request.reading?.intent { return .addTodo(item) }
        return nil
    }
}

/// "<…> 다 했어": only an open item those words name exactly is ticked here; anything looser is the AI's (audit intent-2).
struct ArisFinishTodoHandler: ArisTurnHandler {
    let name = "finishTodo"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard case .finishTodo(let item)? = request.reading?.intent else { return nil }
        return await host.finishable(item).map { .finishTodo($0) }
    }
}

struct ArisBriefHandler: ArisTurnHandler {
    let name = "brief"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .brief? = request.reading?.intent { return .brief }
        return nil
    }
}

struct ArisDayEndHandler: ArisTurnHandler {
    let name = "dayEnd"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .dayEnd? = request.reading?.intent { return .dayEnd }
        return nil
    }
}

struct ArisUndoHandler: ArisTurnHandler {
    let name = "undo"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .undo? = request.reading?.intent { return .undo }
        return nil
    }
}

struct ArisReadAgainHandler: ArisTurnHandler {
    let name = "readAgain"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .readAgain? = request.reading?.intent { return .readAgain }
        return nil
    }
}

struct ArisSaveAnswerHandler: ArisTurnHandler {
    let name = "saveAnswer"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .saveAnswer(let save)? = request.reading?.intent { return .saveAnswer(save) }
        return nil
    }
}

struct ArisArrangeHandler: ArisTurnHandler {
    let name = "arrange"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .arrange(let app, let count)? = request.reading?.intent { return .arrange(app: app, count: count) }
        return nil
    }
}

struct ArisMediaHandler: ArisTurnHandler {
    let name = "media"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .media(let media)? = request.reading?.intent { return .media(media) }
        return nil
    }
}

/// "지금 무슨 노래야?": from what is playing, here (never the AI).
struct ArisWhatsPlayingHandler: ArisTurnHandler {
    let name = "whatsPlaying"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        if case .whatsPlaying? = request.reading?.intent { return .whatsPlaying }
        return nil
    }
}

/// Volume and brightness.
struct ArisControlHandler: ArisTurnHandler {
    let name = "control"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        request.reading.flatMap { ArisControl($0.intent) }.map { .control($0) }
    }
}

/// The time, the date, the timer, Aris's own mute and quiet hours, and opening an app this Mac has.
struct ArisOnMacHandler: ArisTurnHandler {
    let name = "onMac"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let intent = request.reading?.intent else { return nil }
        switch intent {
        case .tellTime, .tellDate, .arisMute, .quietHours: return .onMac(intent)
        case .openApp(let name): return host.application(name) != nil ? .onMac(intent) : nil
        default: return ArisTimerChange.plan(intent, running: false, paused: false, korean: true) != nil ? .onMac(intent) : nil
        }
    }
}

/// "해 놔", "끝나면 알려줘", or several steps on websites (for Aside): the work goes to the background.
struct ArisBackgroundHandler: ArisTurnHandler {
    let name = "background"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, let reading = request.reading, !heard.shots else { return nil }
        return ArisHandoff.isHandoff(heard.unmarked) || reading.browserWork ? .background(browser: reading.browserWork) : nil
    }
}

/// "이거 뭐야", "이 화면": a look at the screen (never for a question about the sessions).
struct ArisScreenHandler: ArisTurnHandler {
    let name = "screen"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? {
        guard let heard = request.heard, !heard.shots, !heard.asksSessions else { return nil }
        return ArisDeixis.refersToScreen(heard.text) || ArisDeixis.refersToClipboard(heard.unmarked) ? .screen : nil
    }
}

/// Whatever is left.
struct ArisBrainHandler: ArisTurnHandler {
    let name = "brain"
    func claims(_ request: ArisTurnRequest, _ host: any ArisTurnHost) async -> ArisTurnClaim? { .brain }
}

extension ArisJobSpec {
    /// The same job with `request` as what it is asked: the user's words and the files they gave with them.
    func asking(_ request: String) -> ArisJobSpec {
        ArisJobSpec(title: title, prompt: request.trimmingCharacters(in: .whitespacesAndNewlines), assignee: assignee, cwd: cwd, appHint: appHint,
                    brain: brain)
    }
}
