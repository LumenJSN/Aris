//
//  ArisAIServicesPageModel.swift
//  Aris
//
//  The AI 서비스 page as data (mockup ai-services-D): a card per job (생각, 듣기, 말하기) with its rows, the row that
//  appears only when something is missing or coming in (a key, a sign-in, a model to download, a server that isn't
//  running), the quiet lines under the cards, and every dropdown's items. A plain function of ArisAIServicesState, so
//  the views only draw and the tests read the page without a window. Foundation only (tested).
//

import Foundation

enum ArisAIMenuKind: Hashable, Sendable {
    case provider(ArisAIJob)
    case model(ArisAIJob)
    case voice
    /// 같은 회사로 맞추기.
    case both
    /// A connection's 고치기 / 지우기.
    case connectionMore(String)
    /// A sheet's own dropdown (the connection's model, a library filter): its items come from the sheet.
    case sheet(String)
}

/// A field on the page that is typed into.
enum ArisAIField: Hashable, Sendable {
    /// The model name of an API brain whose list couldn't be had (its id).
    case model(String)
}

/// What a control on the page asks for.
enum ArisAIAction: Equatable, Sendable {
    case pick(ArisAIMenuKind, String)
    case openKey(String), cancelKey(String), saveKey(holder: String, key: String)
    /// 로그인: the brain's own sign-in in Terminal. 다시 확인: asks a local server for its models again.
    case signIn(String), recheck(String)
    /// 다시 확인 for an AI that isn't installed: asks aris-agent again which ones are on this Mac.
    case recheckBrains
    case download(String), cancelDownload, cancelAsk, retryDownload
    case openJev, cancelJev, saveJev(String), clearJev
    /// 미리 듣기: the chosen voice says a line (again: stops).
    case preview
    /// A voice's sample in the menu or a sheet (its id; `url`: where the sample is).
    case sample(id: String, url: String?)
    case commit(ArisAIField, String)
    case removeKey(String)
    case toggleServices
}

/// A dropdown's button: the choice, small warn text after it, and a thin bar while a model
/// comes in.
struct ArisAISelectFace: Equatable, Sendable {
    var label: String
    /// What the button says instead when `label` doesn't fit it (English runs longer: "큰 모델" for "큰 모델 받는 중").
    var short: String?
    var tail: String?
    var bar: Int?
    var enabled = true
}

enum ArisAIControl: Equatable, Sendable {
    case select(ArisAIMenuKind, ArisAISelectFace)
    /// A name that can't be changed (one model).
    case fixed(String)
    case field(ArisAIField, text: String, placeholder: String)
}

struct ArisAIRow: Equatable, Sendable {
    /// An SF Symbol; nil for a row under the card's first.
    var icon: String?
    var title: String
    var desc = ""
    /// After the description, in the warn colour ("키 필요").
    var warn: String?
    var control: ArisAIControl
    /// 말하기 › 목소리: 미리 듣기 beside the dropdown (false: greyed).
    var preview: Bool?
}

/// The row under a card's rows when something is missing or in progress.
enum ArisAINeed: Equatable, Sendable {
    case button(message: String, title: String, ArisAIAction)
    case keyField(holder: String, placeholder: String, hint: String, error: String?)
    /// "큰 모델은 630 MB를 받아야 해요. 받을까요?" with 받기 and 취소.
    case ask(message: String, model: String)
    case progress(label: String, percent: Int)
    /// A download that failed: 다시 받기 and 취소.
    case failed(message: String)
    case message(String)
    /// The message again, and "방금 확인했어요" where 다시 확인 was: the check ran, and this is still its answer.
    case checked(message: String, note: String)
}

struct ArisAICard: Equatable, Sendable {
    let job: ArisAIJob
    var rows: [ArisAIRow]
    var need: ArisAINeed?
}

/// 짧은 명령 빨리 알아듣기 (TypeSafe Jev), one optional line under the 생각 card.
enum ArisAIJevLine: Equatable, Sendable {
    case off
    case on(masked: String)
    case editing(error: String?)
}

struct ArisAISavedKey: Equatable, Sendable {
    let holder: String
    let name: String
    /// "••••••••a91c" when the app holds the key; nil when aris-agent does (it never gives one back).
    let masked: String?
}

/// The sign-in of the subscription that answers, one line under the 생각 card: for when it was signed out.
struct ArisAILoginLine: Equatable, Sendable {
    let brain: String
    let title: String
    let desc: String
}

struct ArisAIPage: Equatable, Sendable {
    var think: ArisAICard
    var thinkLine: String?
    var login: ArisAILoginLine?
    var jev: ArisAIJevLine
    var hear: ArisAICard
    var speak: ArisAICard
    var voiceLine: String?
    var savedKeys: [ArisAISavedKey]
}

struct ArisAIMenuItem: Equatable, Identifiable, Sendable {
    enum Trailing: Equatable, Sendable {
        case play(url: String?)
        case more
    }

    let id: String
    var title: String
    var subtitle: String?
    /// After the subtitle, in the mono face (a model's id).
    var code: String?
    var tail: String?
    var checked = false
    var disabled = false
    /// A plain action (라이브러리에서 찾기): no check mark.
    var action = false
    var trailing: Trailing?
}

struct ArisAIMenu: Equatable, Sendable {
    enum Entry: Equatable, Sendable {
        case group(String)
        case separator
        case item(ArisAIMenuItem)
        case note(String)
    }

    /// The search field's placeholder (a long voice list); nil: no field.
    var search: String?
    var entries: [Entry] = []
    var foot: [ArisAIMenuItem] = []
    /// Where the list came from, small under the foot.
    var source: String?
    /// A settings row's menu (the measured settings select's radio list): the chosen item is lit in glass and has no
    /// check. The AI 서비스 page's menus mark theirs with the check.
    var radio = false

    var items: [ArisAIMenuItem] { entries.compactMap { if case .item(let item) = $0 { return item }; return nil } }

    /// A settings row's choices as this menu's items (every page's menus are this one menu): each option, its line
    /// under it, the chosen one lit.
    static func choices(_ options: [ArisSettingOption], selected: String) -> ArisAIMenu {
        ArisAIMenu(entries: options.map { .item(ArisAIMenuItem(id: $0.id, title: $0.title, subtitle: $0.detail, checked: $0.id == selected)) }, radio: true)
    }

    /// The menu with only the items that match what is typed in its search (their title, line or id, whatever the
    /// case); nothing typed: as it is. Used for the long plain lists (a provider's models).
    func filtered(by query: String) -> ArisAIMenu {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return self }
        var next = self
        next.entries = items.filter { [$0.title, $0.subtitle ?? "", $0.code ?? ""].joined(separator: " ").lowercased().contains(needle) }.map { .item($0) }
        if next.entries.isEmpty { next.entries = [.note("찾는 것이 없어요")] }
        return next
    }
}

enum ArisAIServicesBuilder {
    // MARK: 연결된 서비스

    static let servicesWaitingRow = "ai.service.loading"

    /// 연결된 서비스's rows for how the read of the AIs in use stands. While it waits, "서비스를 확인하는 중…" stays; once
    /// it has ended with no AI listed, that line becomes one that says none is connected and how to connect one, or
    /// that aris-agent didn't answer (QA VM: on a Mac with no Claude or Codex it stayed on the waiting line for ever,
    /// because an empty list was read as "still checking"). A real list is never replaced.
    static func serviceRows(_ rows: [ArisSettingItem], read: ArisAIServicesRead) -> [ArisSettingItem] {
        guard read != .waiting else { return rows }
        return rows.map { row in
            guard row.id == servicesWaitingRow else { return row }
            return read == .answered
                ? ArisSettingItem(id: "ai.service.none", icon: .none, title: "연결된 AI가 없어요",
                                  desc: "Claude Code, Codex, Antigravity 중 하나를 설치하고 로그인하면 여기와 사이드 노치 사용량 탭에 나와요.", control: .none, indexed: false)
                : ArisSettingItem(id: "ai.service.unread", icon: .none, title: "연결된 AI를 확인하지 못했어요",
                                  desc: "Aris 에이전트가 답하지 않았어요. 잠시 뒤에 이 페이지를 다시 열어 주세요.", control: .none, indexed: false)
        }
    }

    /// The longest 연결된 서비스 waits where the usage model doesn't say how its read stands: one read of every service
    /// by aris-agent, and its second look for Antigravity 15 s later.
    static let servicesWait: TimeInterval = 20

    /// The read's state worked out from what the page can see, for a usage model that only publishes its list: ended at
    /// once when aris-agent says none of the three AIs is on this Mac, else after `servicesWait` (answered when
    /// aris-agent is reachable, unanswered when it isn't). With a list, the state doesn't matter.
    static func servicesRead(listed: Int, brainReady: [String: Bool], agentReachable: Bool, waited: TimeInterval) -> ArisAIServicesRead {
        if listed > 0 { return .answered }
        if ArisAIStore.brains.allSatisfy({ brainReady[$0] == false }) { return .answered }
        guard waited >= servicesWait else { return .waiting }
        return agentReachable ? .answered : .unanswered
    }

    // MARK: Words

    static let stays = "이 Mac에 머물러요"
    static func leaves(_ job: ArisAIJob) -> String {
        switch job {
        case .think: "대화가 Mac 밖으로 나가요"
        case .hear: "음성이 Mac 밖으로 나가요"
        case .speak: "답이 Mac 밖으로 나가요"
        }
    }

    /// A model id as the menus name it, with what it's like; an id Aris doesn't know is shown as it is.
    static let knownModels: [String: (label: String, trait: String)] = [
        "claude-haiku-4-5": ("Haiku", "빠르고 싸요"), "claude-sonnet-4-5": ("Sonnet", "빠르고 똑똑해요"), "claude-opus-5-5": ("Opus", "가장 똑똑해요 · 비싸요"),
        "gpt-6-luna": ("Luna", "빠르고 싸요"), "gpt-6.1-sol": ("Sol", "빠르고 똑똑해요"), "gpt-6-astra": ("Astra", "가장 똑똑해요 · 비싸요"),
        "gemini-flash-latest": ("Flash", "빠르고 싸요"), "gemini-pro-latest": ("Pro", "똑똑해요"),
        "llama-3.3-70b-versatile": ("Llama 3.3", "아주 빨라요"), "openai/gpt-oss-120b": ("GPT-OSS", "더 똑똑해요"),
    ]

    static func modelLabel(_ id: String) -> String { knownModels[id]?.label ?? id }

    /// What a subscription answers with: Aris picks the model by how big the request is (ArisBrain.model(tier:)).
    static let subscriptionModels: [String: (label: String, desc: String)] = [
        "claude": ("Sonnet", "빠른 답은 Haiku, 큰 일은 Sonnet이 해요"),
        "codex": ("Sol", "빠른 답은 Luna, 큰 일은 Sol이 해요"),
        "antigravity": ("Gemini Flash", "빠른 답은 가볍게, 큰 일은 깊이 생각해요"),
    ]

    /// The two Whisper models and every line the page says about each (whole sentences: each has its English).
    struct WhisperWords: Equatable, Sendable {
        let id: String
        let label: String
        let trait: String
        let size: String
        let ask: String
        let coming: String
        let paused: String
        let failed: String
        let done: String
    }

    static let whisperModels = [
        WhisperWords(id: "small", label: "작은 모델", trait: "가볍고 빨라요", size: "약 220 MB", ask: "작은 모델은 약 220 MB를 받아야 해요. 받을까요?",
                     coming: "작은 모델 받는 중", paused: "작은 모델 받기를 잠시 멈췄어요", failed: "작은 모델을 받지 못했어요", done: "작은 모델을 받았어요"),
        WhisperWords(id: "large", label: "큰 모델", trait: "더 정확해요", size: "630 MB", ask: "큰 모델은 630 MB를 받아야 해요. 받을까요?",
                     coming: "큰 모델 받는 중", paused: "큰 모델 받기를 잠시 멈췄어요", failed: "큰 모델을 받지 못했어요", done: "큰 모델을 받았어요"),
    ]

    static let voiceModels: [(id: String, label: String, trait: String)] = [
        ("eleven_flash_v2_5", "Flash v2.5", "가장 빨리 말을 시작해요"), ("eleven_v4_turbo", "v4 Turbo", "빠르고 자연스러워요"),
        ("eleven_v4", "v4", "가장 자연스러워요 · 말 시작이 조금 늦어요"),
        ("eleven_multilingual_v2", "Multilingual v2", "고르고 차분해요 · 조금 느려요"),
    ]

    static func whisper(_ id: String) -> WhisperWords {
        whisperModels.first { $0.id == id } ?? whisperModels[0]
    }

    // MARK: Page

    static func page(_ state: ArisAIServicesState) -> ArisAIPage {
        ArisAIPage(think: thinkCard(state), thinkLine: thinkFallback(state), login: login(state), jev: jev(state), hear: hearCard(state), speak: speakCard(state),
                   voiceLine: voiceFallback(state), savedKeys: savedKeys(state))
    }

    /// The card's first row: the job, who does it and whether it stays on this Mac (or what it's missing), and the
    /// dropdown that changes it.
    private static func providerRow(_ job: ArisAIJob, _ state: ArisAIServicesState) -> ArisAIRow {
        let provider = ArisAICatalogue.current(job, in: state)
        let lack = ArisAICatalogue.lack(provider, in: state)
        let symbol = job == .think ? "brain" : job == .hear ? "mic" : "speaker.wave.2"
        let name = provider.group == .connection ? ["내 연결", provider.name].joined(separator: " · ") : provider.name
        let place = provider.local || isLocalAddress(provider, state) ? stays : leaves(job)
        return ArisAIRow(icon: symbol, title: job.title, desc: lack == nil ? "\(name) · \(place)" : name, warn: lack?.word,
                         control: .select(.provider(job), ArisAISelectFace(label: provider.name)))
    }

    /// A connection to a server on this Mac keeps the conversation here.
    private static func isLocalAddress(_ provider: ArisAIProvider, _ state: ArisAIServicesState) -> Bool {
        guard provider.group == .connection, let id = ArisAIStore.apiID(provider.id), let preset = state.preset(id) else { return false }
        return preset.local
    }

    /// What the 생각 card says when no AI is chosen, and when none can answer.
    static let noBrainChosen = "고른 AI가 없어요"
    static let chooseBrain = "AI 고르기"
    static let noBrainHow = "아직 답할 수 있는 AI가 없어요. 위에서 Claude, ChatGPT, Gemini나 API 키로 쓰는 AI를 하나 골라 주세요."
    static let noBrainAnswers = "아직 답할 수 있는 AI가 없어요"

    private static func thinkCard(_ state: ArisAIServicesState) -> ArisAICard {
        // Nobody chose an AI and none is ready here (VM run 2026-11-11, bug 4: the card showed ChatGPT, ticked, on a
        // Mac with no AI): the card names none, and its dropdown is where one is chosen.
        guard !state.choices.think.isEmpty else {
            let row = ArisAIRow(icon: "brain", title: ArisAIJob.think.title, desc: noBrainChosen, control: .select(.provider(.think), ArisAISelectFace(label: chooseBrain)))
            return ArisAICard(job: .think, rows: [row], need: .message(noBrainHow))
        }
        let provider = ArisAICatalogue.current(.think, in: state)
        var rows = [providerRow(.think, state)]
        if let model = thinkModelRow(provider, state) { rows.append(model) }
        return ArisAICard(job: .think, rows: rows, need: thinkNeed(provider, state))
    }

    private static func thinkModelRow(_ provider: ArisAIProvider, _ state: ArisAIServicesState) -> ArisAIRow? {
        if let fixed = subscriptionModels[provider.id] {
            return ArisAIRow(title: "모델", desc: fixed.desc, control: .fixed(fixed.label))
        }
        guard let id = ArisAIStore.apiID(provider.id), let preset = state.preset(id), ArisAICatalogue.lack(provider, in: state) != .key else { return nil }
        let chosen = state.profile(id)?.strong ?? preset.strong
        switch state.models[id] {
        case .listed(let list) where !list.isEmpty:
            return ArisAIRow(title: "모델", desc: knownModels[chosen]?.trait ?? "", control: .select(.model(.think), ArisAISelectFace(label: modelLabel(chosen.isEmpty ? list[0] : chosen))))
        case .loading, nil:
            return ArisAIRow(title: "모델", desc: "목록을 불러오는 중이에요", control: .select(.model(.think), ArisAISelectFace(label: chosen.isEmpty ? "불러오는 중…" : modelLabel(chosen), enabled: false)))
        default:
            // No list (a server that doesn't answer, or has none): the name is typed.
            return ArisAIRow(title: "모델", desc: preset.local && !preset.custom ? "\(provider.name)에 불러온 모델" : "목록을 못 불러와서 직접 적어요",
                             control: .field(.model(id), text: chosen, placeholder: "모델 이름"))
        }
    }

    /// Under a provider whose saved key has never answered.
    static let keyUnanswered = "이 키로는 아직 답을 받지 못했어요"

    /// `ui.checked` after 다시 확인 asked aris-agent which AIs are on this Mac.
    static let brainsChecked = "brains"
    static let checkedNote = "방금 확인했어요"
    /// How long the note stays before 다시 확인 is back, in seconds.
    static let checkedShows = 4.0

    /// 다시 확인 under a message, or (for a few seconds after it was pressed and found the same) that it was checked
    /// just now: pressing it used to change nothing on screen (VM run 2026-11-11).
    private static func recheck(_ message: String, _ action: ArisAIAction, checked: String, _ state: ArisAIServicesState) -> ArisAINeed {
        state.ui.checked == checked ? .checked(message: message, note: checkedNote) : .button(message: message, title: "다시 확인", action)
    }

    private static func thinkNeed(_ provider: ArisAIProvider, _ state: ArisAIServicesState) -> ArisAINeed? {
        switch ArisAICatalogue.lack(provider, in: state) {
        case .install:
            // How to get it (the same words the first-run guide's page uses), and 다시 확인 once it is installed.
            guard let brain = ArisBrain(rawValue: provider.id) else { return nil }
            return recheck(ArisSettingsBuilder.brainHow(brain), .recheckBrains, checked: brainsChecked, state)
        case .key:
            guard let holder = provider.keyHolder, state.preset(holder) != nil else {
                return state.agentReachable ? .message("API 키로 답할 서비스를 골라 주세요") : .message("Aris 에이전트가 답하지 않아요")
            }
            return keyNeed(holder, state)
        case .notRunning:
            return recheck("\(ArisParticle.attach(provider.name, .iGa)) 실행 중이 아니에요", .recheck(provider.id), checked: provider.id, state)
        case .check:
            // The key is kept (he may be offline); 다시 확인 tries it again.
            return recheck(keyUnanswered, .recheck(provider.id), checked: provider.id, state)
        default:
            return nil
        }
    }

    /// The key a card is waiting for: a line and API 키 추가, or (opened) the field with where the key is kept.
    private static func keyNeed(_ holder: String, _ state: ArisAIServicesState) -> ArisAINeed {
        let name = ArisAICatalogue.keyName(holder, in: state)
        guard state.ui.keyOpen.contains(holder) else {
            return .button(message: "\(name) API 키가 필요해요", title: "API 키 추가", .openKey(holder))
        }
        return .keyField(holder: holder, placeholder: "\(name) API 키", hint: ["키체인에 저장해요", ArisAICatalogue.keyJobs(holder)].joined(separator: " · "), error: state.ui.keyError[holder])
    }

    private static func hearCard(_ state: ArisAIServicesState) -> ArisAICard {
        let provider = ArisAICatalogue.current(.hear, in: state)
        var rows = [providerRow(.hear, state)]
        var need: ArisAINeed?
        switch provider.id {
        case "whisper":
            let model = whisper(ArisAICatalogue.whisperModel(in: state))
            let coming = state.download
            let shown = coming.map { whisper($0.model) } ?? model
            var face = ArisAISelectFace(label: shown.label)
            if let coming, coming.phase != .failed { face = ArisAISelectFace(label: shown.coming, short: shown.label, tail: "\(coming.percent)%", bar: coming.percent) }
            rows.append(ArisAIRow(title: "모델", desc: "\(shown.trait) · \(shown.size)", control: .select(.model(.hear), face)))
            need = whisperNeed(model.id, state)
        case "scribe":
            rows.append(ArisAIRow(title: "모델", control: .fixed("Scribe v2 Realtime")))
            if state.elevenKey == nil { need = keyNeed("elevenlabs", state) }
        default: break
        }
        return ArisAICard(job: .hear, rows: rows, need: need)
    }

    /// Whisper's model: the question before a download, the bar while it comes in, or that one is needed.
    private static func whisperNeed(_ chosen: String, _ state: ArisAIServicesState) -> ArisAINeed? {
        if let coming = state.download {
            let words = whisper(coming.model)
            switch coming.phase {
            case .running: return .progress(label: words.coming, percent: coming.percent)
            case .waiting: return .progress(label: "인터넷이 돌아오면 이어서 받을게요", percent: coming.percent)
            case .paused: return .progress(label: words.paused, percent: coming.percent)
            case .failed: return .failed(message: words.failed)
            }
        }
        let asked = state.ui.asking ?? (state.whisperInstalled.contains(chosen) ? nil : chosen)
        guard let asked, !state.whisperInstalled.contains(asked) else { return nil }
        return .ask(message: whisper(asked).ask, model: asked)
    }

    private static func speakCard(_ state: ArisAIServicesState) -> ArisAICard {
        let provider = ArisAICatalogue.current(.speak, in: state)
        var rows = [providerRow(.speak, state)]
        var need: ArisAINeed?
        if provider.id == "eleven" {
            let model = voiceModels.first { $0.id == state.choices.elevenModel } ?? voiceModels[1]
            rows.append(ArisAIRow(title: "모델", desc: model.trait, control: .select(.model(.speak), ArisAISelectFace(label: model.label))))
            let hasKey = state.elevenKey != nil
            if !hasKey { need = keyNeed("elevenlabs", state) }
            let voice = state.voices["eleven"]?.voices.first { $0.id == state.choices.elevenVoiceID }
            rows.append(ArisAIRow(icon: "person", title: "목소리", desc: hasKey ? voice?.desc ?? "" : "키를 넣으면 골라요",
                                  control: .select(.voice, ArisAISelectFace(label: voice?.name ?? state.choices.elevenVoiceName, enabled: hasKey)), preview: hasKey))
        } else {
            let voice = state.voices["macos"]?.voices.first { $0.id == state.choices.systemVoice && !$0.id.isEmpty }
            rows.append(ArisAIRow(icon: "person", title: "목소리", desc: voice?.desc ?? "언어마다 가장 좋은 목소리를 써요",
                                  control: .select(.voice, ArisAISelectFace(label: voice?.name ?? "자동", tail: voice.flatMap { $0.tail.isEmpty ? nil : $0.tail })),
                                  preview: true))
        }
        return ArisAICard(job: .speak, rows: rows, need: need)
    }

    /// The subscription that answers and is on this Mac (or not yet asked about) keeps its sign-in at hand: aris-agent
    /// can't see a sign-out, so the line is always there rather than claimed as a state.
    private static func login(_ state: ArisAIServicesState) -> ArisAILoginLine? {
        let provider = ArisAICatalogue.current(.think, in: state)
        guard provider.group == .subscription, ArisAICatalogue.lack(provider, in: state) == nil, let brain = ArisBrain(rawValue: provider.id),
              let command = ArisSettingsBuilder.brainCommand(brain) else { return nil }
        return ArisAILoginLine(brain: provider.id, title: "\(provider.name) 로그인", desc: "로그인이 풀렸을 때 눌러요. 터미널에서 \(command) 명령을 열어 줘요.")
    }

    private static func jev(_ state: ArisAIServicesState) -> ArisAIJevLine {
        if let masked = state.jevKey, !state.ui.jevOpen { return .on(masked: masked) }
        return state.ui.jevOpen ? .editing(error: state.ui.jevError) : .off
    }

    /// Keys that can be taken out again: ElevenLabs' (the app holds it), and each API brain's (aris-agent holds those).
    private static func savedKeys(_ state: ArisAIServicesState) -> [ArisAISavedKey] {
        var keys: [ArisAISavedKey] = []
        if let masked = state.elevenKey { keys.append(ArisAISavedKey(holder: "elevenlabs", name: "ElevenLabs", masked: masked)) }
        for preset in state.presets where preset.needsKey && !preset.custom && state.profile(preset.id)?.hasKey == true {
            keys.append(ArisAISavedKey(holder: preset.id, name: ArisAICatalogue.apiName(preset), masked: nil))
        }
        return keys
    }

    // MARK: The quiet lines

    /// The brain stored under a pick that can't answer yet, when it really can answer a question asked now; nil when
    /// nothing is stored there or what is stored lacks its tool, its key or its server.
    private static func answeringMeanwhile(_ stored: String, _ state: ArisAIServicesState) -> ArisAIProvider? {
        guard !stored.isEmpty else { return nil }
        var kept = state
        kept.choices.think = stored
        let provider = ArisAICatalogue.current(.think, in: kept)
        return ArisAICatalogue.lack(provider, in: kept) == nil ? provider : nil
    }

    /// Who answers when the chosen AI can't (aris-agent's own rule, ArisBrain.fallback: Gemini for ChatGPT, ChatGPT for
    /// the others), named only when it is set up here.
    private static func thinkFallback(_ state: ArisAIServicesState) -> String? {
        let now = state.choices.think
        // No AI chosen: the card itself says so.
        guard !now.isEmpty else { return nil }
        if let stored = state.thinkStored, stored != now {
            // Picked, but not able to answer yet: the brain that works goes on answering until it can. When none does
            // (nothing stored, or the stored one can't answer either), the line says so instead of naming one.
            guard let answering = answeringMeanwhile(stored, state) else { return noBrainAnswers }
            return "쓸 수 있게 될 때까지 \(ArisParticle.attach(answering.name, .euroRo)) 생각해요"
        }
        let other = now == "codex" ? "antigravity" : "codex"
        guard state.brainReady[other] == true else { return nil }
        return other == "codex" ? "안 되면 ChatGPT로 생각해요" : "안 되면 Gemini로 생각해요"
    }

    /// What listens and speaks when the cloud can't: Whisper once a model is on this Mac (else Apple's recognition),
    /// and a macOS voice.
    private static func voiceFallback(_ state: ArisAIServicesState) -> String? {
        let hearOff = state.choices.hear == "scribe", speakOff = state.choices.speak == "eleven"
        let whisper = !state.whisperInstalled.isEmpty
        switch (hearOff, speakOff) {
        case (true, true): return whisper ? "안 되면 이 Mac의 Whisper로 듣고 macOS 목소리로 말해요" : "안 되면 이 Mac의 Apple 받아쓰기로 듣고 macOS 목소리로 말해요"
        case (true, false): return whisper ? "안 되면 이 Mac의 Whisper로 들어요" : "안 되면 이 Mac의 Apple 받아쓰기로 들어요"
        case (false, true): return "안 되면 이 Mac의 macOS 목소리로 말해요"
        case (false, false): return nil
        }
    }

    // MARK: Menus

    /// A dropdown's items. `query`: what is typed in the voice menu's search.
    static func menu(_ kind: ArisAIMenuKind, _ state: ArisAIServicesState, query: String = "") -> ArisAIMenu {
        switch kind {
        case .provider(let job): return providerMenu(job, state)
        case .model(let job): return modelMenu(job, state).filtered(by: query)
        case .voice: return voiceMenu(state, query: query)
        case .both:
            return ArisAIMenu(entries: ArisAICatalogue.both.map { company in
                .item(ArisAIMenuItem(id: company.id, title: company.name, subtitle: "듣기와 말하기를 둘 다 이 회사로",
                                     tail: company.hear == nil ? ArisAILack.soon.word : nil, disabled: company.hear == nil))
            })
        case .connectionMore(let id):
            return ArisAIMenu(entries: [.item(ArisAIMenuItem(id: "edit:" + id, title: "고치기", action: true)),
                                        .item(ArisAIMenuItem(id: "remove:" + id, title: "지우기", action: true))])
        case .sheet: return ArisAIMenu()
        }
    }

    private static func item(_ provider: ArisAIProvider, _ state: ArisAIServicesState, chosen: String) -> ArisAIMenuItem {
        let lack = ArisAICatalogue.lack(provider, in: state)
        return ArisAIMenuItem(id: provider.id, title: provider.name, subtitle: provider.note, tail: lack?.word, checked: provider.id == chosen,
                              disabled: lack == .soon, trailing: provider.group == .connection ? .more : nil)
    }

    /// Two parts of one line, each with its own English ("구독 · 대화가 Mac 밖으로 나가요").
    private static func dots(_ first: String, _ second: String) -> String { [first, second].joined(separator: " · ") }

    private static func providerMenu(_ job: ArisAIJob, _ state: ArisAIServicesState) -> ArisAIMenu {
        let all = ArisAICatalogue.providers(job, in: state)
        // 생각 with no AI chosen: nothing is ticked.
        let chosen = ArisAICatalogue.current(job, in: state).id
        let groups: [(ArisAIProvider.Group, String)] = job == .think
            ? [(.subscription, dots("구독", leaves(job))), (.apiKey, dots("API 키", leaves(job))), (.onMac, dots("이 Mac에서", stays)), (.connection, "내 연결")]
            : [(.onMac, dots("이 Mac에서", stays)), (.cloud, dots("클라우드", leaves(job)))]
        var entries: [ArisAIMenu.Entry] = []
        for (group, title) in groups {
            let members = all.filter { $0.group == group }
            guard !members.isEmpty else { continue }
            if !entries.isEmpty { entries.append(.separator) }
            entries.append(.group(title))
            entries += members.map { .item(item($0, state, chosen: chosen)) }
        }
        // Only 생각 can use another address today (the API brain speaks OpenAI's chat protocol).
        let foot = job == .think ? [ArisAIMenuItem(id: "connect", title: "다른 AI 연결…", action: true)] : []
        return ArisAIMenu(entries: entries, foot: foot)
    }

    private static func modelMenu(_ job: ArisAIJob, _ state: ArisAIServicesState) -> ArisAIMenu {
        switch job {
        case .think:
            guard let id = ArisAIStore.apiID(state.choices.think), let preset = state.preset(id), case .listed(let list)? = state.models[id] else { return ArisAIMenu() }
            let chosen = state.profile(id)?.strong ?? preset.strong
            return ArisAIMenu(search: list.count > 10 ? "모델 찾기" : nil, entries: list.map { model in
                let known = knownModels[model]
                return .item(ArisAIMenuItem(id: model, title: (known?.label ?? model) + (model == preset.strong && known != nil ? " · 기본" : ""),
                                            subtitle: known?.trait, code: known == nil ? nil : model, checked: model == chosen))
            })
        case .hear:
            let chosen = ArisAICatalogue.whisperModel(in: state)
            return ArisAIMenu(entries: whisperModels.map { model in
                .item(ArisAIMenuItem(id: model.id, title: model.label + (model.id == "small" ? " · 기본" : ""), subtitle: model.trait,
                                     tail: state.whisperInstalled.contains(model.id) ? nil : model.size, checked: model.id == chosen))
            })
        case .speak:
            return ArisAIMenu(entries: voiceModels.map { model in
                .item(ArisAIMenuItem(id: model.id, title: model.label + (model.id == ArisAIStore.defaultVoiceModel ? " · 기본" : ""), subtitle: model.trait,
                                     code: model.id, checked: model.id == state.choices.elevenModel))
            })
        }
    }

    /// The voices of the engine that speaks, as its service lists them: ElevenLabs' own voices then its stock ones (and
    /// the library and a link to add more), or the voices installed on this Mac after 자동.
    private static func voiceMenu(_ state: ArisAIServicesState, query: String) -> ArisAIMenu {
        let eleven = state.choices.speak == "eleven"
        let list = state.voices[eleven ? "eleven" : "macos"] ?? .loading
        let chosen = eleven ? state.choices.elevenVoiceID : state.choices.systemVoice
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let hit = { (voice: ArisAIVoice) in needle.isEmpty || (voice.name + " " + voice.desc).lowercased().contains(needle) }
        var menu = ArisAIMenu(search: list.voices.count > 10 ? "목소리 찾기" : nil)
        func section(_ title: String, _ voices: [ArisAIVoice]) {
            let found = voices.filter(hit)
            guard !found.isEmpty else { return }
            if !menu.entries.isEmpty { menu.entries.append(.separator) }
            menu.entries.append(.group("\(title) · \(found.count)"))
            menu.entries += found.map { voice in
                .item(ArisAIMenuItem(id: voice.id, title: voice.name, subtitle: voice.desc.isEmpty ? nil : voice.desc, tail: voice.tail.isEmpty ? nil : voice.tail,
                                     checked: voice.id == chosen, trailing: .play(url: voice.preview)))
            }
        }
        switch list {
        case .loading: menu.entries = [.note("목소리를 불러오는 중…")]
        case .failed: menu.entries = [.note("목소리 목록을 못 받았어요")]
        case .loaded(let voices):
            if eleven {
                section("내 목소리", voices.filter(\.own))
                section("기본 목소리", voices.filter { !$0.own })
            } else {
                if needle.isEmpty {
                    menu.entries.append(.item(ArisAIMenuItem(id: "", title: "자동", subtitle: "언어마다 가장 좋은 목소리를 써요", checked: chosen.isEmpty)))
                }
                section("설치됨", voices)
            }
            if menu.entries.isEmpty { menu.entries = [.note("찾는 목소리가 없어요")] }
        }
        if eleven {
            menu.foot = [ArisAIMenuItem(id: "library", title: "라이브러리에서 찾기", action: true), ArisAIMenuItem(id: "link", title: "링크로 추가…", action: true)]
            menu.source = "ElevenLabs에서 불러옴"
        } else {
            menu.source = "이 Mac에서 불러옴"
        }
        return menu
    }

    // MARK: Picking

    /// What picking `id` in a menu changes; nil when it isn't a stored choice (an action in the foot, 준비 중).
    static func change(_ kind: ArisAIMenuKind, picked id: String, in state: ArisAIServicesState) -> ArisAIChange? {
        switch kind {
        case .provider(let job):
            guard let provider = ArisAICatalogue.provider(job, id, in: state), provider.built else { return nil }
            switch job {
            case .think: return .think(id)
            case .hear: return .hear(id)
            case .speak: return .speak(id)
            }
        case .model(.think): return .thinkModel(provider: state.choices.think, model: id)
        case .model(.hear): return .whisperModel(id)
        case .model(.speak): return .elevenModel(id)
        case .voice:
            if state.choices.speak != "eleven" { return .systemVoice(id) }
            guard let voice = state.voices["eleven"]?.voices.first(where: { $0.id == id }) else { return nil }
            return .elevenVoice(id: voice.id, name: voice.name)
        case .both, .connectionMore, .sheet: return nil
        }
    }
}
