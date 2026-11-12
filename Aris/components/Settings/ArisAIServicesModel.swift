//
//  ArisAIServicesModel.swift
//  Aris
//
//  설정 › AI 서비스 (the owner's pick: mockup ai-services-D): which AI thinks, which engine listens, which voice speaks,
//  and the user's own connections, as plain values. One store for those choices (ArisAIStore): it reads them from the
//  preferences earlier builds already wrote (the brain, Scribe on or off, the Whisper model, the voice), so an update
//  changes nothing a user had, and it turns a change into the few writes that make it. The page and, later, a spoken
//  "change my voice" on a confirm card both go through it. Foundation only (tested).
//

import Foundation

enum ArisAIJob: String, CaseIterable, Equatable, Sendable {
    case think, hear, speak

    var title: String {
        switch self {
        case .think: "생각"
        case .hear: "듣기"
        case .speak: "말하기"
        }
    }
}

/// What a service is missing before it can work.
enum ArisAILack: Equatable, Sendable {
    case key, model, notRunning
    /// Its key is saved but has never answered: kept, and not counted as working until a check or a turn gets an answer.
    case check
    /// Its tool isn't on this Mac (Claude Code, Codex, Antigravity). aris-agent can only tell whether a tool is
    /// installed, never whether it is signed in, so "needs a sign-in" is not a state the page can claim.
    case install
    /// Aris has no engine for it yet: listed, never chosen.
    case soon

    var word: String {
        switch self {
        case .key: "키 필요"
        case .install: "설치 필요"
        case .model: "모델 받기 필요"
        case .notRunning: "실행 중이 아니에요"
        case .check: "확인 필요"
        case .soon: "준비 중"
        }
    }
}

struct ArisAIProvider: Equatable, Identifiable, Sendable {
    enum Group: Equatable, Sendable { case subscription, apiKey, onMac, cloud, connection }

    let id: String
    let job: ArisAIJob
    let name: String
    /// The line under its name in the menu.
    let note: String
    let group: Group
    /// Whose API key it needs ("elevenlabs", or an API brain's id); nil: none.
    var keyHolder: String?
    /// Aris can really use it. False: shown as 준비 중.
    var built = true

    var local: Bool { group == .onMac }
}

/// One API brain provider as aris-agent lists it (ArisAPIPreset), or a connection the user added.
struct ArisAIPreset: Equatable, Sendable {
    let id: String
    let title: String
    let needsKey: Bool
    let local: Bool
    let baseURL: String
    let quick: String
    let strong: String
    var keySource = ""
    /// The user's own connection (다른 AI 연결…), not one Aris ships.
    var custom = false
}

/// What is saved for a provider (never its key).
struct ArisAIProfile: Equatable, Sendable {
    let id: String
    let quick: String
    let strong: String
    let hasKey: Bool
    /// Its key is saved and has never answered (the helper's check failed, or was never made).
    var unchecked = false
}

/// The models a provider answered with.
enum ArisAIModelList: Equatable, Sendable {
    case loading
    case listed([String])
    /// Its list couldn't be had (a local server that isn't running, an address that doesn't answer).
    case unreachable
}

struct ArisAIVoice: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    var desc = ""
    /// Small trailing text (프리미엄, 고급).
    var tail = ""
    /// The account's own voice (ElevenLabs: cloned, designed or added from the library).
    var own = false
    var preview: String?
}

enum ArisAIVoiceList: Equatable, Sendable {
    case loading, failed
    case loaded([ArisAIVoice])

    var voices: [ArisAIVoice] { if case .loaded(let list) = self { return list }; return [] }
}

/// How the read of the AIs in use stands, for 연결된 서비스's first rows. The same three states as the 사용량 tab's own
/// read (ArisUsageRead, where the usage model has it): the page takes the state, whoever works it out.
enum ArisAIServicesRead: Equatable, Sendable, CaseIterable {
    /// No read has ended yet.
    case waiting
    /// aris-agent answered: what is listed is all there is.
    case answered
    /// aris-agent didn't answer in time.
    case unanswered
}

/// A Whisper model coming in (ArisModelDownload, as the page needs it).
struct ArisAIDownload: Equatable, Sendable {
    enum Phase: Equatable, Sendable { case running, waiting, paused, failed }
    let model: String
    let percent: Int
    var phase = Phase.running
}

// MARK: - The stored choices

enum ArisAIPrefKey {
    // Written by earlier builds: never renamed.
    static let brain = "arisBrain"
    static let cloudListening = "arisCloudListening"
    static let speechModel = "arisSpeechModel"
    static let voiceID = "arisVoiceID"
    static let voiceName = "arisVoiceName"
    static let voiceSpeed = "arisVoiceSpeed"
    static let languages = "arisLanguages"
    // New with this page. Absent: what the earlier build did (ArisAIStore.read).
    static let hearEngine = "arisHearEngine"
    static let speakEngine = "arisSpeakEngine"
    static let voiceModel = "arisVoiceModel"
    static let systemVoice = "arisSystemVoice"
}

struct ArisAIChoices: Equatable, Sendable {
    /// "claude", "codex", "antigravity", or "api:<id>" (an API brain or a connection, by aris-agent's id). "" on the
    /// page: nobody chose an AI and none is ready on this Mac (ArisBrainChoice.shown), so none is shown as chosen.
    var think = "codex"
    /// "apple", "whisper" or "scribe".
    var hear = "apple"
    /// "small" or "large"; nil: none picked.
    var whisperModel: String?
    /// "macos" or "eleven".
    var speak = "macos"
    var elevenVoiceID = ArisAIStore.defaultVoiceID
    var elevenVoiceName = ArisAIStore.defaultVoiceName
    var elevenModel = ArisAIStore.defaultVoiceModel
    /// A macOS voice's identifier; "": the best voice of each language, as before.
    var systemVoice = ""
    var speed = 1.0
    var languages = ArisLanguages.defaults
}

/// One thing the user (or Aris, on a confirm card) changes.
enum ArisAIChange: Equatable, Sendable {
    case think(String)
    /// The model an API brain or connection answers with (`provider`: "api:<id>").
    case thinkModel(provider: String, model: String)
    case hear(String)
    case whisperModel(String)
    case speak(String)
    case elevenVoice(id: String, name: String)
    case elevenModel(String)
    case systemVoice(String)
    case speed(Double)
}

enum ArisAIValue: Equatable, Sendable {
    case text(String), flag(Bool), number(Double)
}

/// One write a change is made of: a preference, or a word to aris-agent (it keeps the API brains).
enum ArisAIWrite: Equatable, Sendable {
    case pref(String, ArisAIValue)
    /// The API brain that answers from now on.
    case activate(String)
    /// An API brain's models (`quick` nil: kept).
    case models(id: String, quick: String?, strong: String)
}

enum ArisAIStore {
    static let defaultVoiceID = "k5siOxi4qsPS2kASoRt7"
    static let defaultVoiceName = "Geaun"
    static let defaultVoiceModel = "eleven_v4_turbo"
    /// The speeds the page offers; anything else stored is kept as it is.
    static let speedRange: ClosedRange<Double> = 0.7...1.2

    static let brains = ["claude", "codex", "antigravity"]
    static let hearEngines = ["apple", "whisper", "scribe"]
    static let speakEngines = ["macos", "eleven"]
    static let whisperModels = ["small", "large"]
    static let voiceModels = ["eleven_flash_v2_5", "eleven_v4_turbo", "eleven_multilingual_v2"]

    /// What else decides a choice that was never stored: how the earlier build behaved.
    struct Facts: Equatable, Sendable {
        /// aris-agent's active API brain (its id), when it has one.
        var apiActive: String?
        var hasElevenKey = false
        var whisperLargeInstalled = false
        /// The languages listened in while none are stored (ArisLanguages.starting: the Mac's own).
        var languages = ArisLanguages.defaults
    }

    /// The choices as stored. `pref`: a preference's value by its key. Nothing is written: an existing user's brain,
    /// voice, speed, languages and listening are exactly what they were.
    static func read(_ pref: (String) -> Any?, facts: Facts) -> ArisAIChoices {
        var choices = ArisAIChoices()
        let brain = pref(ArisAIPrefKey.brain) as? String ?? "codex"
        choices.think = brain == "api" ? "api:" + (facts.apiActive ?? "") : brains.contains(brain) ? brain : "codex"

        let model = (pref(ArisAIPrefKey.speechModel) as? String).flatMap { whisperModels.contains($0) ? $0 : nil }
        choices.whisperModel = model ?? (facts.whisperLargeInstalled ? "large" : nil)
        let cloud = pref(ArisAIPrefKey.cloudListening) as? Bool
        if let stored = pref(ArisAIPrefKey.hearEngine) as? String, hearEngines.contains(stored), cloud == nil || cloud == (stored == "scribe") {
            choices.hear = stored
        } else {
            // Before the page (or after the old Scribe switch on 목소리 · 언어 was flipped since): Scribe listens when its
            // switch is on and a key is there; else Whisper once a model is in, else Apple's recognition.
            choices.hear = (cloud ?? true) && facts.hasElevenKey ? "scribe" : choices.whisperModel != nil ? "whisper" : "apple"
        }

        if let stored = pref(ArisAIPrefKey.speakEngine) as? String, speakEngines.contains(stored) {
            choices.speak = stored
        } else {
            // Before the page: ElevenLabs spoke whenever its key was there.
            choices.speak = facts.hasElevenKey ? "eleven" : "macos"
        }
        choices.elevenVoiceID = pref(ArisAIPrefKey.voiceID) as? String ?? defaultVoiceID
        choices.elevenVoiceName = pref(ArisAIPrefKey.voiceName) as? String ?? defaultVoiceName
        choices.elevenModel = (pref(ArisAIPrefKey.voiceModel) as? String).flatMap { voiceModels.contains($0) ? $0 : nil } ?? defaultVoiceModel
        choices.systemVoice = pref(ArisAIPrefKey.systemVoice) as? String ?? ""
        choices.speed = pref(ArisAIPrefKey.voiceSpeed) as? Double ?? 1.0
        choices.languages = pref(ArisAIPrefKey.languages) as? [String] ?? facts.languages
        return choices
    }

    /// The writes that make `change`, and nothing else: a change to the voice never touches the brain. Empty when the
    /// change isn't one Aris can make (an engine it doesn't have, a speed out of range).
    static func plan(_ change: ArisAIChange) -> [ArisAIWrite] {
        switch change {
        case .think(let id):
            if brains.contains(id) { return [.pref(ArisAIPrefKey.brain, .text(id))] }
            guard let api = apiID(id) else { return [] }
            return [.activate(api), .pref(ArisAIPrefKey.brain, .text("api"))]
        case .thinkModel(let provider, let model):
            guard let api = apiID(provider), !model.isEmpty else { return [] }
            return [.models(id: api, quick: nil, strong: model)]
        case .hear(let id):
            guard hearEngines.contains(id) else { return [] }
            // Scribe listens exactly while its old switch is on.
            return [.pref(ArisAIPrefKey.hearEngine, .text(id)), .pref(ArisAIPrefKey.cloudListening, .flag(id == "scribe"))]
        case .whisperModel(let model):
            guard whisperModels.contains(model) else { return [] }
            return [.pref(ArisAIPrefKey.speechModel, .text(model))]
        case .speak(let id):
            guard speakEngines.contains(id) else { return [] }
            return [.pref(ArisAIPrefKey.speakEngine, .text(id))]
        case .elevenVoice(let id, let name):
            guard !id.isEmpty else { return [] }
            return [.pref(ArisAIPrefKey.voiceID, .text(id)), .pref(ArisAIPrefKey.voiceName, .text(name))]
        case .elevenModel(let model):
            guard voiceModels.contains(model) else { return [] }
            return [.pref(ArisAIPrefKey.voiceModel, .text(model))]
        case .systemVoice(let identifier):
            return [.pref(ArisAIPrefKey.systemVoice, .text(identifier))]
        case .speed(let speed):
            guard speedRange.contains(speed) else { return [] }
            return [.pref(ArisAIPrefKey.voiceSpeed, .number(speed))]
        }
    }

    /// `choices` after `change` (what the page shows at once, before the writes land).
    static func applying(_ change: ArisAIChange, to choices: ArisAIChoices) -> ArisAIChoices {
        guard !plan(change).isEmpty else { return choices }
        var next = choices
        switch change {
        case .think(let id): next.think = id
        case .thinkModel: break
        case .hear(let id): next.hear = id
        case .whisperModel(let model): next.whisperModel = model
        case .speak(let id): next.speak = id
        case .elevenVoice(let id, let name): (next.elevenVoiceID, next.elevenVoiceName) = (id, name)
        case .elevenModel(let model): next.elevenModel = model
        case .systemVoice(let identifier): next.systemVoice = identifier
        case .speed(let speed): next.speed = speed
        }
        return next
    }

    /// "api:openai" → "openai"; nil for anything else (and for "api:" with no id).
    static func apiID(_ provider: String) -> String? {
        guard provider.hasPrefix("api:") else { return nil }
        let id = String(provider.dropFirst(4))
        return id.isEmpty ? nil : id
    }
}

// MARK: - What the page shows

/// Which field of the page is open, and what was wrong with what was typed. Nothing here is stored.
struct ArisAIUI: Equatable, Sendable {
    /// The key field open under a card, by key holder.
    var keyOpen: Set<String> = []
    var keyError: [String: String] = [:]
    var jevOpen = false
    var jevError: String?
    /// The Whisper model whose download the page is asking about.
    var asking: String?
    /// The voice sample playing ("": the main 미리 듣기).
    var playing: String?
    /// 연결된 서비스 is folded open.
    var servicesOpen = false
    /// What 다시 확인 has just asked about again (ArisAIServicesBuilder.brainsChecked, or a local server's provider
    /// id): its row says so for a few seconds.
    var checked: String?
}

/// Everything the page is a function of: the stored choices, what the services say, and the open fields.
struct ArisAIServicesState: Equatable, Sendable {
    var choices = ArisAIChoices()
    /// The brain stored under the one shown (`choices.think`) while that one can't answer yet: it was picked on the
    /// page but still needs its key or a sign-in, and is stored only once it can answer. "": nothing is stored under
    /// it (a new Mac with no AI). Nil: the one shown is the one stored.
    var thinkStored: String?
    /// Whether Claude Code, Codex and Antigravity are installed on this Mac, as aris-agent says (missing: it hasn't
    /// answered yet, and nothing is called missing).
    var brainReady: [String: Bool] = [:]
    /// aris-agent answered (it keeps the API brains).
    var agentReachable = true
    var presets: [ArisAIPreset] = []
    var profiles: [ArisAIProfile] = []
    /// By API brain id.
    var models: [String: ArisAIModelList] = [:]
    /// The ElevenLabs and TypeSafe keys as they may be shown ("••••••••a91c"); nil: none saved.
    var elevenKey: String?
    var jevKey: String?
    /// Whisper models on this Mac ("small", "large").
    var whisperInstalled: Set<String> = []
    var download: ArisAIDownload?
    /// By speaking engine ("eleven", "macos").
    var voices: [String: ArisAIVoiceList] = [:]
    /// How the read of the AIs in use stands (연결된 서비스's first rows): an empty list alone never means "still checking".
    var servicesRead = ArisAIServicesRead.waiting
    var ui = ArisAIUI()

    func preset(_ id: String) -> ArisAIPreset? { presets.first { $0.id == id } }
    func profile(_ id: String) -> ArisAIProfile? { profiles.first { $0.id == id } }
    var connections: [ArisAIPreset] { presets.filter(\.custom) }
}

enum ArisAICatalogue {
    /// The API brains the 생각 menu always lists; the others (OpenRouter, DeepSeek, xAI, Mistral) join once saved.
    static let listedAPI = ["openai", "anthropic", "gemini", "groq"]
    /// 다른 AI 연결…'s quick picks, in order: providers Aris knows the address of.
    static let quickAPI = ["openrouter", "deepseek", "groq", "xai", "mistral", "ollama", "lmstudio"]

    static let subscriptions = [
        ArisAIProvider(id: "claude", job: .think, name: "Claude", note: "Claude Code로 답해요", group: .subscription),
        ArisAIProvider(id: "codex", job: .think, name: "ChatGPT", note: "Codex로 답해요", group: .subscription),
        ArisAIProvider(id: "antigravity", job: .think, name: "Gemini", note: "Antigravity로 답해요", group: .subscription),
    ]

    static let hear = [
        ArisAIProvider(id: "apple", job: .hear, name: "Apple 받아쓰기", note: "말하는 대로 글자가 떠요", group: .onMac),
        ArisAIProvider(id: "whisper", job: .hear, name: "Whisper", note: "말을 마치면 한 번에 적어요", group: .onMac),
        ArisAIProvider(id: "scribe", job: .hear, name: "ElevenLabs Scribe", note: "말하는 대로 글자가 떠요", group: .cloud, keyHolder: "elevenlabs"),
        ArisAIProvider(id: "openai-stt", job: .hear, name: "OpenAI", note: "gpt-4o-transcribe", group: .cloud, built: false),
        ArisAIProvider(id: "groq-stt", job: .hear, name: "Groq", note: "whisper-large-v3 · 아주 빨라요", group: .cloud, built: false),
        ArisAIProvider(id: "deepgram", job: .hear, name: "Deepgram", note: "말하는 대로 글자가 떠요", group: .cloud, built: false),
        ArisAIProvider(id: "fish-stt", job: .hear, name: "Fish Audio", note: "말을 마치면 한 번에 적어요", group: .cloud, built: false),
    ]

    static let speak = [
        ArisAIProvider(id: "macos", job: .speak, name: "macOS 목소리", note: "설치된 음성 중에서 골라요", group: .onMac),
        ArisAIProvider(id: "kokoro", job: .speak, name: "Kokoro", note: "이 Mac에서 말해요 · 영어만", group: .onMac, built: false),
        ArisAIProvider(id: "eleven", job: .speak, name: "ElevenLabs", note: "가장 자연스러워요", group: .cloud, keyHolder: "elevenlabs"),
        ArisAIProvider(id: "fish-tts", job: .speak, name: "Fish Audio", note: "복제한 목소리도 써요", group: .cloud, built: false),
        ArisAIProvider(id: "openai-tts", job: .speak, name: "OpenAI", note: "gpt-4o-mini-tts", group: .cloud, built: false),
    ]

    /// Companies that both listen and speak (같은 회사로 맞추기): the name, and the two engines (nil: not built yet).
    static let both: [(id: String, name: String, hear: String?, speak: String?)] = [
        ("elevenlabs", "ElevenLabs", "scribe", "eleven"), ("openai", "OpenAI", nil, nil), ("fish", "Fish Audio", nil, nil),
    ]

    /// A key holder's name ("ElevenLabs API 키").
    static func keyName(_ holder: String, in state: ArisAIServicesState) -> String {
        switch holder {
        case "elevenlabs": "ElevenLabs"
        case "typesafe": "TypeSafe"
        default: state.preset(holder).map(apiName) ?? holder
        }
    }

    /// The jobs a holder's one key serves ("듣기 · 말하기에 같이 써요").
    static func keyJobs(_ holder: String) -> String { holder == "elevenlabs" ? "듣기 · 말하기에 같이 써요" : "생각에 써요" }

    /// "Ollama (이 Mac)" → "Ollama": the menu's group already says where it runs.
    static func apiName(_ preset: ArisAIPreset) -> String {
        preset.title.replacingOccurrences(of: " (이 Mac)", with: "")
    }

    private static func apiNote(_ preset: ArisAIPreset) -> String {
        if preset.local { return "이 Mac의 \(apiName(preset))" }
        return preset.id == "groq" ? "아주 빠른 오픈 모델" : "API 키로 답해요"
    }

    static func api(_ preset: ArisAIPreset) -> ArisAIProvider {
        ArisAIProvider(id: "api:" + preset.id, job: .think, name: apiName(preset), note: preset.custom ? preset.baseURL : apiNote(preset),
                       group: preset.custom ? .connection : preset.local ? .onMac : .apiKey, keyHolder: preset.needsKey ? preset.id : nil)
    }

    /// Every service that can do `job`, in menu order. 생각: the three subscriptions, the API brains the menu lists (and
    /// any other the user saved or is using), the local servers, then the user's own connections.
    static func providers(_ job: ArisAIJob, in state: ArisAIServicesState) -> [ArisAIProvider] {
        switch job {
        case .hear: return hear
        case .speak: return speak
        case .think:
            let shipped = state.presets.filter { !$0.custom }
            let chosen = ArisAIStore.apiID(state.choices.think)
            let keyed = shipped.filter { !$0.local && (listedAPI.contains($0.id) || state.profile($0.id) != nil || $0.id == chosen) }
            return subscriptions + keyed.map(api) + shipped.filter(\.local).map(api) + state.connections.map(api)
        }
    }

    static func provider(_ job: ArisAIJob, _ id: String, in state: ArisAIServicesState) -> ArisAIProvider? {
        providers(job, in: state).first { $0.id == id }
    }

    /// The service doing `job` now. A stored id that is no longer there (an API brain removed) still shows by its id.
    static func current(_ job: ArisAIJob, in state: ArisAIServicesState) -> ArisAIProvider {
        let id = job == .think ? state.choices.think : job == .hear ? state.choices.hear : state.choices.speak
        if let found = provider(job, id, in: state) { return found }
        let name = ArisAIStore.apiID(id) ?? (id == "api:" ? "API 키" : id)
        return ArisAIProvider(id: id, job: job, name: name, note: "", group: .apiKey, keyHolder: ArisAIStore.apiID(id))
    }

    /// What `provider` is missing; nil when it can work now.
    static func lack(_ provider: ArisAIProvider, in state: ArisAIServicesState) -> ArisAILack? {
        guard provider.built else { return .soon }
        switch provider.id {
        case "claude", "codex", "antigravity":
            return state.brainReady[provider.id] == false ? .install : nil
        case "scribe", "eleven":
            return state.elevenKey == nil ? .key : nil
        case "whisper":
            return state.whisperInstalled.contains(whisperModel(in: state)) ? nil : .model
        default: break
        }
        guard let id = ArisAIStore.apiID(provider.id) else { return provider.id == "api:" ? .key : nil }
        guard let preset = state.preset(id) else { return .key }
        if preset.needsKey {
            guard let profile = state.profile(id), profile.hasKey else { return .key }
            return profile.unchecked ? .check : nil
        }
        return state.models[id] == .unreachable ? .notRunning : nil
    }

    /// The Whisper model in use: the pick, else the large one a Mac already has, else the small one.
    static func whisperModel(in state: ArisAIServicesState) -> String {
        state.choices.whisperModel ?? (state.whisperInstalled.contains("large") ? "large" : "small")
    }
}

// MARK: - What aris-agent says

/// aris-agent's answers about the API brains (POST /api-brains: ArisAPIRoutes, ArisAPIConnections), read into the
/// page's values. It keeps the profiles and the keys; a key never comes back, only whether one is saved.
enum ArisAIAgentAnswers {
    struct List: Equatable, Sendable {
        var presets: [ArisAIPreset] = []
        var profiles: [ArisAIProfile] = []
        /// The API brain that answers (its id).
        var active: String?
        /// The agent's list can't be used right now (changed outside Aris, or the Keychain is locked): what it said.
        var problem: String?
    }

    /// {"presets", "profiles", "connections", "active"?, "problem"?}: the shipped providers, then the user's own
    /// connections as providers of their own.
    static func list(_ object: [String: Any]) -> List {
        var list = List(active: object["active"] as? String, problem: object["problem"] as? String)
        list.presets = (object["presets"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String, let title = row["title"] as? String, !id.isEmpty else { return nil }
            let needsKey = row["needsKey"] as? Bool ?? true
            return ArisAIPreset(id: id, title: title, needsKey: needsKey, local: row["local"] as? Bool ?? !needsKey, baseURL: row["baseURL"] as? String ?? "",
                                quick: row["quick"] as? String ?? "", strong: row["strong"] as? String ?? "", keySource: row["keySource"] as? String ?? "")
        }
        list.profiles = (object["profiles"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ArisAIProfile(id: id, quick: row["quick"] as? String ?? "", strong: row["strong"] as? String ?? "", hasKey: row["hasKey"] as? Bool ?? false, unchecked: row["unchecked"] as? Bool ?? false)
        }
        for row in object["connections"] as? [[String: Any]] ?? [] {
            guard let id = row["id"] as? String, let name = row["name"] as? String, let base = row["base"] as? String, !list.presets.contains(where: { $0.id == id }) else { continue }
            let local = row["local"] as? Bool ?? false
            let model = row["model"] as? String ?? ""
            list.presets.append(ArisAIPreset(id: id, title: name, needsKey: !local, local: local, baseURL: base, quick: model, strong: model, custom: true))
        }
        return list
    }

    /// {"models": [{"id"}], "fromProvider"}: the provider's own list; when it couldn't be had, a shipped provider with a
    /// key still offers the models Aris knows for it, and a server on this Mac or a connection is taken as not answering.
    static func models(_ object: [String: Any], preset: ArisAIPreset) -> ArisAIModelList {
        let ids = (object["models"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
        if object["fromProvider"] as? Bool == true, !ids.isEmpty { return .listed(ids) }
        return preset.local || preset.custom || ids.isEmpty ? .unreachable : .listed(ids)
    }
}
