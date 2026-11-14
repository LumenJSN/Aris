// Tests for settings › AI 서비스 (mockup ai-services-D): the one store for which AI thinks, which engine listens and
// which voice speaks (and that an update changes nothing a user had), the status rules (key, sign-in, model, not
// running), the page and its dropdowns as data, the voice lists and library as ElevenLabs answers them, and the user's
// own connections in aris-agent. Fixtures and fakes only: no provider is called, no Keychain read, no sound.
import Foundation

func runAIServicesTests() {
    aiStoreTests()
    aiStatusTests()
    aiAgentAnswerTests()
    aiPageTests()
    aiMenuTests()
    aiSheetTests()
    aiVoiceTests()
    aiEngineTests()
    aiServicesWaitTests()
    aiEnglishTests()
    #if !AI_QUICK
    aiConnectionTests()
    aiSettingsWindowTests()
    #endif
}

private let aiPresets = [
    ArisAIPreset(id: "openai", title: "OpenAI", needsKey: true, local: false, baseURL: "https://api.openai.com/v1", quick: "gpt-6-luna", strong: "gpt-6.1-sol"),
    ArisAIPreset(id: "anthropic", title: "Anthropic", needsKey: true, local: false, baseURL: "https://api.anthropic.com/v1", quick: "claude-haiku-4-5", strong: "claude-sonnet-4-5"),
    ArisAIPreset(id: "gemini", title: "Gemini API", needsKey: true, local: false, baseURL: "https://generativelanguage.googleapis.com/v1beta", quick: "gemini-flash-latest", strong: "gemini-pro-latest"),
    ArisAIPreset(id: "openrouter", title: "OpenRouter", needsKey: true, local: false, baseURL: "https://openrouter.ai/api/v1", quick: "openai/gpt-oss-120b", strong: "anthropic/claude-sonnet-4.5"),
    ArisAIPreset(id: "groq", title: "Groq", needsKey: true, local: false, baseURL: "https://api.groq.com/openai/v1", quick: "llama-3.3-70b-versatile", strong: "openai/gpt-oss-120b"),
    ArisAIPreset(id: "xai", title: "xAI", needsKey: true, local: false, baseURL: "https://api.x.ai/v1", quick: "grok-4-fast", strong: "grok-4"),
    ArisAIPreset(id: "ollama", title: "Ollama (이 Mac)", needsKey: false, local: true, baseURL: "http://127.0.0.1:11434/v1", quick: "qwen3:8b", strong: "qwen3:8b"),
    ArisAIPreset(id: "lmstudio", title: "LM Studio (이 Mac)", needsKey: false, local: true, baseURL: "http://127.0.0.1:1234/v1", quick: "", strong: ""),
]

private func aiState(_ change: (inout ArisAIServicesState) -> Void = { _ in }) -> ArisAIServicesState {
    var state = ArisAIServicesState()
    state.presets = aiPresets
    state.brainReady = ["claude": true, "codex": true, "antigravity": false]
    change(&state)
    return state
}

private func prefs(_ values: [String: Any]) -> (String) -> Any? { { values[$0] } }

// MARK: - The store

private func aiStoreTests() {
    // An install from before the page: only the old keys.
    let old: [String: Any] = ["arisBrain": "claude", "arisCloudListening": true, "arisSpeechModel": "small", "arisVoiceID": "voice123", "arisVoiceName": "Rachel",
                              "arisVoiceSpeed": 1.15, "arisLanguages": ["ko", "en", "ja"]]
    let withKey = ArisAIStore.read(prefs(old), facts: .init(hasElevenKey: true))
    check(withKey.think == "claude" && withKey.hear == "scribe" && withKey.whisperModel == "small" && withKey.speak == "eleven"
          && withKey.elevenVoiceID == "voice123" && withKey.elevenVoiceName == "Rachel" && withKey.speed == 1.15 && withKey.languages == ["ko", "en", "ja"]
          && withKey.elevenModel == "eleven_v4_turbo" && withKey.systemVoice.isEmpty,
          "ai store: an existing user's brain, voice, speed, languages and listening read exactly as the earlier build used them (ElevenLabs key)")
    let noKey = ArisAIStore.read(prefs(old), facts: .init())
    check(noKey.hear == "whisper" && noKey.speak == "macos" && noKey.elevenVoiceID == "voice123" && noKey.speed == 1.15,
          "ai store: without an ElevenLabs key the same preferences read as what really listened and spoke (Whisper, the Mac's voice)")
    check(ArisAIStore.read(prefs(["arisCloudListening": false]), facts: .init(hasElevenKey: true)).hear == "apple"
          && ArisAIStore.read(prefs(["arisCloudListening": false]), facts: .init(hasElevenKey: true, whisperLargeInstalled: true)).hear == "whisper"
          && ArisAIStore.read(prefs(["arisSpeechModel": "later"]), facts: .init(whisperLargeInstalled: true)).whisperModel == "large"
          && ArisAIStore.read(prefs(["arisSpeechModel": "later"]), facts: .init()).whisperModel == nil,
          "ai store: Scribe switched off reads as Whisper once a model is on this Mac (the large one a Mac already has counts), else Apple's recognition")
    let fresh = ArisAIStore.read(prefs([:]), facts: .init())
    check(fresh.think == "codex" && fresh.hear == "apple" && fresh.speak == "macos" && fresh.elevenVoiceID == ArisElevenLabs.voiceID && fresh.elevenVoiceName == "Geaun"
          && fresh.speed == 1 && fresh.languages == ["ko", "en"], "ai store: nothing stored reads as the preferences' own defaults")
    check(ArisAIStore.read(prefs(["arisBrain": "api"]), facts: .init(apiActive: "groq")).think == "api:groq"
          && ArisAIStore.read(prefs(["arisBrain": "api"]), facts: .init()).think == "api:"
          && ArisAIStore.read(prefs(["arisBrain": "antigravity"]), facts: .init()).think == "antigravity"
          && ArisAIStore.read(prefs(["arisBrain": "nonsense"]), facts: .init()).think == "codex",
          "ai store: the API brain reads as aris-agent's active provider; Antigravity stays Antigravity; a name that is no brain is the default")
    let explicit = ArisAIStore.read(prefs(old.merging(["arisHearEngine": "apple", "arisCloudListening": false, "arisSpeakEngine": "macos", "arisVoiceModel": "eleven_flash_v2_5",
                                                       "arisSystemVoice": "com.apple.voice.premium.ko-KR.Yuna"]) { $1 }), facts: .init(hasElevenKey: true))
    check(explicit.hear == "apple" && explicit.speak == "macos" && explicit.elevenModel == "eleven_flash_v2_5" && explicit.systemVoice.hasSuffix("Yuna")
          && explicit.elevenVoiceID == "voice123",
          "ai store: a choice made on the page is read back over what the old preferences imply, and the ElevenLabs voice is kept for later")
    check(ArisAIStore.read(prefs(["arisHearEngine": "whisper", "arisCloudListening": true, "arisSpeechModel": "small"]), facts: .init(hasElevenKey: true)).hear == "scribe"
          && ArisAIStore.read(prefs(["arisHearEngine": "scribe", "arisCloudListening": false, "arisSpeechModel": "small"]), facts: .init(hasElevenKey: true)).hear == "whisper"
          && ArisAIStore.read(prefs(["arisHearEngine": "apple", "arisCloudListening": false, "arisSpeechModel": "small"]), facts: .init(hasElevenKey: true)).hear == "apple",
          "ai store: the old Scribe switch flipped elsewhere wins over a pick it contradicts, so the page never shows an engine that isn't listening")
    check(ArisAIStore.read(prefs(["arisHearEngine": "deepgram", "arisSpeakEngine": "kokoro", "arisVoiceModel": "tts-1"]), facts: .init()).hear == "apple"
          && ArisAIStore.read(prefs(["arisSpeakEngine": "kokoro"]), facts: .init(hasElevenKey: true)).speak == "eleven"
          && ArisAIStore.read(prefs(["arisVoiceModel": "tts-1"]), facts: .init()).elevenModel == "eleven_v4_turbo",
          "ai store: a stored engine or model Aris doesn't have is not a choice")

    check(ArisAIStore.plan(.think("claude")) == [.pref("arisBrain", .text("claude"))]
          && ArisAIStore.plan(.think("api:groq")) == [.activate("groq"), .pref("arisBrain", .text("api"))]
          && ArisAIStore.plan(.think("api:")).isEmpty && ArisAIStore.plan(.think("siri")).isEmpty,
          "ai store: choosing who thinks writes the brain (an API brain: its provider to aris-agent first), and nothing for a name that is no brain")
    check(ArisAIStore.plan(.hear("scribe")) == [.pref("arisHearEngine", .text("scribe")), .pref("arisCloudListening", .flag(true))]
          && ArisAIStore.plan(.hear("whisper")) == [.pref("arisHearEngine", .text("whisper")), .pref("arisCloudListening", .flag(false))]
          && ArisAIStore.plan(.hear("deepgram")).isEmpty,
          "ai store: choosing who listens keeps the old Scribe switch in step (the engine reads it), and an engine Aris doesn't have writes nothing")
    let voiceWrites = ArisAIStore.plan(.elevenVoice(id: "v9", name: "지영"))
    check(voiceWrites == [.pref("arisVoiceID", .text("v9")), .pref("arisVoiceName", .text("지영"))]
          && ArisAIStore.plan(.speak("macos")) == [.pref("arisSpeakEngine", .text("macos"))] && ArisAIStore.plan(.speak("kokoro")).isEmpty
          && ArisAIStore.plan(.elevenModel("eleven_multilingual_v2")) == [.pref("arisVoiceModel", .text("eleven_multilingual_v2"))]
          && ArisAIStore.plan(.systemVoice("")) == [.pref("arisSystemVoice", .text(""))]
          && ArisAIStore.plan(.whisperModel("large")) == [.pref("arisSpeechModel", .text("large"))] && ArisAIStore.plan(.whisperModel("huge")).isEmpty
          && ArisAIStore.plan(.speed(1.15)) == [.pref("arisVoiceSpeed", .number(1.15))] && ArisAIStore.plan(.speed(3)).isEmpty,
          "ai store: a voice, model or speed change writes only its own preference")
    check(ArisAIStore.plan(.thinkModel(provider: "api:openai", model: "gpt-6-astra")) == [.models(id: "openai", quick: nil, strong: "gpt-6-astra")]
          && ArisAIStore.plan(.thinkModel(provider: "claude", model: "opus")).isEmpty,
          "ai store: an API brain's model goes to aris-agent with its quick model kept; a subscription has no model to store")
    let allKeys = [ArisAIChange.think("claude"), .hear("apple"), .speak("eleven"), .elevenVoice(id: "a", name: "b"), .elevenModel("eleven_v4_turbo"), .systemVoice("x"),
                   .whisperModel("small"), .speed(1)].flatMap(ArisAIStore.plan).compactMap { write -> String? in if case .pref(let key, _) = write { return key }; return nil }
    check(!allKeys.contains("arisLanguages") && Set(allKeys).count == allKeys.count,
          "ai store: no change on this page writes the languages, and no two changes write the same preference")
    check(ArisAIStore.applying(.hear("whisper"), to: withKey).hear == "whisper" && ArisAIStore.applying(.hear("deepgram"), to: withKey) == withKey
          && ArisAIStore.applying(.elevenVoice(id: "v9", name: "지영"), to: withKey).elevenVoiceName == "지영"
          && ArisAIStore.applying(.elevenVoice(id: "v9", name: "지영"), to: withKey).think == "claude",
          "ai store: the page shows a change at once, and a change that can't be made changes nothing")
    check(ArisAIPrefKey.voiceModel == ArisElevenLabs.modelKey && ArisAIStore.voiceModels == ArisElevenLabs.models && ArisAIStore.defaultVoiceID == ArisElevenLabs.voiceID
          && ArisAIStore.defaultVoiceModel == ArisElevenLabs.modelID && ArisAIPrefKey.brain == "arisBrain" && ArisAIPrefKey.speechModel == "arisSpeechModel",
          "ai store: the store's keys and defaults are the engines' own")
}

// MARK: - Status

private func aiStatusTests() {
    let state = aiState {
        $0.profiles = [ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true), ArisAIProfile(id: "xai", quick: "grok-4-fast", strong: "grok-4", hasKey: false)]
        $0.models = ["ollama": .listed(["qwen3:8b"]), "lmstudio": .unreachable]
    }
    func lack(_ job: ArisAIJob, _ id: String, _ s: ArisAIServicesState? = nil) -> ArisAILack? {
        ArisAICatalogue.provider(job, id, in: s ?? state).flatMap { ArisAICatalogue.lack($0, in: s ?? state) }
    }
    check(lack(.think, "claude") == nil && lack(.think, "antigravity") == .install && lack(.think, "codex", aiState { $0.brainReady = [:] }) == nil,
          "ai status: a subscription whose tool isn't on this Mac needs installing (aris-agent can't see a sign-in); before it has answered nothing is claimed")
    check(lack(.think, "api:openai") == nil && lack(.think, "api:groq") == .key && lack(.think, "api:xai") == .key,
          "ai status: an API brain needs its key (a saved profile without one too)")
    check(lack(.think, "api:ollama") == nil && lack(.think, "api:lmstudio") == .notRunning,
          "ai status: a local server whose model list can't be had is not running")
    check(lack(.hear, "scribe") == .key && lack(.speak, "eleven") == .key && lack(.hear, "scribe", aiState { $0.elevenKey = "••••a91c" }) == nil,
          "ai status: Scribe and the ElevenLabs voice need the one ElevenLabs key")
    check(lack(.hear, "whisper") == .model && lack(.hear, "whisper", aiState { $0.whisperInstalled = ["small"] }) == nil
          && lack(.hear, "whisper", aiState { $0.whisperInstalled = ["small"]; $0.choices.whisperModel = "large" }) == .model
          && lack(.hear, "apple") == nil && lack(.speak, "macos") == nil,
          "ai status: Whisper needs its picked model on this Mac; Apple's recognition and the Mac's voices need nothing")
    check([("openai-stt", ArisAIJob.hear), ("groq-stt", .hear), ("deepgram", .hear), ("fish-stt", .hear), ("kokoro", .speak), ("fish-tts", .speak), ("openai-tts", .speak)]
            .allSatisfy { lack($0.1, $0.0) == .soon },
          "ai status: a service Aris has no engine for is listed as 준비 중, never as working")
    check(ArisAILack.key.word == "키 필요" && ArisAILack.install.word == "설치 필요" && ArisAILack.model.word == "모델 받기 필요" && ArisAILack.notRunning.word == "실행 중이 아니에요",
          "ai status: the four states read as the mockup writes them")

    let ids = ArisAICatalogue.providers(.think, in: state).map(\.id)
    check(ids == ["claude", "codex", "antigravity", "api:openai", "api:anthropic", "api:gemini", "api:groq", "api:xai", "api:ollama", "api:lmstudio"],
          "ai providers: 생각 lists the three subscriptions, the four API brains of the mockup and any other the user saved, then the local servers")
    let custom = aiState {
        $0.presets.append(ArisAIPreset(id: "conn-0a1b2c3d", title: "내 서버", needsKey: true, local: false, baseURL: "https://llm.example.com/v1", quick: "m", strong: "m", custom: true))
        $0.choices.think = "api:openrouter"
    }
    let withCustom = ArisAICatalogue.providers(.think, in: custom)
    check(withCustom.last?.id == "api:conn-0a1b2c3d" && withCustom.last?.group == .connection && withCustom.contains { $0.id == "api:openrouter" }
          && ArisAICatalogue.apiName(aiPresets[6]) == "Ollama",
          "ai providers: the user's own connections come last, the API brain in use is always listed, and a local server's name drops “(이 Mac)”")
    check(ArisAICatalogue.current(.think, in: aiState { $0.choices.think = "api:gone" }).name == "gone" && ArisAICatalogue.current(.think, in: aiState { $0.choices.think = "api:" }).name == "API 키",
          "ai providers: a stored API brain that is no longer there still shows, as missing its key")
}

private func aiAgentAnswerTests() {
    let object = (try? JSONSerialization.jsonObject(with: Data(#"""
    {"presets":[{"id":"openai","title":"OpenAI","needsKey":true,"local":false,"baseURL":"https://api.openai.com/v1","quick":"gpt-6-luna","strong":"gpt-6.1-sol","keySource":"platform.openai.com"},
                {"id":"ollama","title":"Ollama (이 Mac)","needsKey":false,"local":true,"baseURL":"http://127.0.0.1:11434/v1","quick":"qwen3:8b","strong":"qwen3:8b"},
                {"title":"no id"}],
     "profiles":[{"id":"openai","quick":"gpt-6-luna","strong":"gpt-6-astra","hasKey":true,"vision":true,"tools":true},{"id":"conn-0a1b2c3d","quick":"m","strong":"m","hasKey":true}],
     "connections":[{"id":"conn-0a1b2c3d","name":"내 서버","base":"https://llm.example.com/v1","local":false,"hasKey":true,"model":"m"},{"id":"openai","name":"가짜","base":"https://evil.example"}],
     "active":"conn-0a1b2c3d","tested":[]}
    """#.utf8))) as? [String: Any] ?? [:]
    let list = ArisAIAgentAnswers.list(object)
    check(list.presets.map(\.id) == ["openai", "ollama", "conn-0a1b2c3d"] && list.presets[2] == ArisAIPreset(id: "conn-0a1b2c3d", title: "내 서버", needsKey: true, local: false, baseURL: "https://llm.example.com/v1", quick: "m", strong: "m", custom: true)
          && list.presets[1].local && !list.presets[1].needsKey && list.profiles.first == ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6-astra", hasKey: true)
          && list.active == "conn-0a1b2c3d" && list.problem == nil,
          "ai agent: its list reads as the shipped providers, then the user's connections as providers of their own (one that takes a shipped id is dropped)")
    check(ArisAIAgentAnswers.list(["problem": "키체인을 읽지 못했어요"]).problem == "키체인을 읽지 못했어요" && ArisAIAgentAnswers.list([:]).presets.isEmpty, "ai agent: a list it can't use carries what it said")
    func models(_ json: String, _ preset: ArisAIPreset) -> ArisAIModelList {
        ArisAIAgentAnswers.models((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:], preset: preset)
    }
    check(models(#"{"models":[{"id":"a","vision":true},{"id":"b"},{"id":""}],"fromProvider":true}"#, list.presets[0]) == .listed(["a", "b"])
          && models(#"{"models":[{"id":"gpt-6-luna"}],"fromProvider":false}"#, list.presets[0]) == .listed(["gpt-6-luna"])
          && models(#"{"models":[{"id":"qwen3:8b"}],"fromProvider":false}"#, list.presets[1]) == .unreachable
          && models(#"{"models":[],"fromProvider":false}"#, list.presets[2]) == .unreachable && models("{}", list.presets[0]) == .unreachable,
          "ai agent: a provider's own model list is used as it is; without it a shipped provider offers the models Aris knows, and a local server or a connection counts as not answering")
}

// MARK: - The page

private func aiPageTests() {
    // Nothing set up: no AI, no key, no model.
    let empty = ArisAIServicesBuilder.page(aiState { $0.brainReady = ["claude": false, "codex": false, "antigravity": false] })
    check(empty.think.rows.count == 2 && empty.think.rows[0].title == "생각" && empty.think.rows[0].desc == "ChatGPT" && empty.think.rows[0].warn == "설치 필요"
          && empty.think.need == .button(message: ArisSettingsBuilder.brainHow(.codex), title: "다시 확인", .recheckBrains) && empty.thinkLine == nil && empty.login == nil,
          "ai page: a brain whose tool isn't installed says 설치 필요, how to get it, and 다시 확인; no sign-in or fallback is offered for what isn't there")
    check(empty.hear.rows.map(\.title) == ["듣기"] && empty.hear.rows[0].desc == "Apple 받아쓰기 · 이 Mac에 머물러요" && empty.hear.need == nil
          && empty.speak.rows.map(\.title) == ["말하기", "목소리"] && empty.speak.rows[0].desc == "macOS 목소리 · 이 Mac에 머물러요"
          && empty.speak.rows[1].control == .select(.voice, ArisAISelectFace(label: "자동")) && empty.speak.rows[1].preview == true
          && empty.voiceLine == nil && empty.jev == .off && empty.savedKeys.isEmpty,
          "ai page: a new install listens with Apple's recognition and speaks with the Mac's best voice, all on this Mac")

    // Claude, Scribe and an ElevenLabs voice.
    let claude = ArisAIServicesBuilder.page(aiState {
        $0.choices = ArisAIChoices(think: "claude", hear: "scribe", whisperModel: "small", speak: "eleven", elevenVoiceID: "v1", elevenVoiceName: "Geaun")
        $0.elevenKey = "••••••••9c1e"
        $0.jevKey = "••••••••77aa"
        $0.whisperInstalled = ["small"]
        $0.voices["eleven"] = .loaded([ArisAIVoice(id: "v1", name: "Geaun", desc: "female · korean", own: true)])
    })
    check(claude.think.rows[0].desc == "Claude · 대화가 Mac 밖으로 나가요" && claude.think.rows[0].warn == nil
          && claude.think.rows[1] == ArisAIRow(title: "모델", desc: "빠른 답은 Haiku, 큰 일은 Sonnet이 해요", control: .fixed("Sonnet")) && claude.think.need == nil
          && claude.thinkLine == "안 되면 ChatGPT로 생각해요"
          && claude.login == ArisAILoginLine(brain: "claude", title: "Claude 로그인", desc: "로그인이 풀렸을 때 눌러요. 터미널에서 claude 명령을 열어 줘요."),
          "ai page: Claude answers with the models Aris picks itself (shown, not a dropdown), ChatGPT is named as the one that takes over, and Claude's own sign-in is one press away")
    check(claude.hear.rows[0].desc == "ElevenLabs Scribe · 음성이 Mac 밖으로 나가요" && claude.hear.rows[1].control == .fixed("Scribe v2 Realtime") && claude.hear.need == nil
          && claude.speak.rows.map(\.title) == ["말하기", "모델", "목소리"] && claude.speak.rows[1].control == .select(.model(.speak), ArisAISelectFace(label: "v4 Turbo"))
          && claude.speak.rows[2].desc == "female · korean" && claude.speak.rows[2].control == .select(.voice, ArisAISelectFace(label: "Geaun"))
          && claude.voiceLine == "안 되면 이 Mac의 Whisper로 듣고 macOS 목소리로 말해요" && claude.jev == .on(masked: "••••••••77aa")
          && claude.savedKeys == [ArisAISavedKey(holder: "elevenlabs", name: "ElevenLabs", masked: "••••••••9c1e")],
          "ai page: Scribe and the ElevenLabs voice with their key; the line under them names what this Mac falls back to")
    check(ArisAIServicesBuilder.page(aiState { $0.choices.hear = "scribe"; $0.elevenKey = "x" }).voiceLine == "안 되면 이 Mac의 Apple 받아쓰기로 들어요"
          && ArisAIServicesBuilder.page(aiState { $0.choices.speak = "eleven"; $0.elevenKey = "x" }).voiceLine == "안 되면 이 Mac의 macOS 목소리로 말해요"
          && ArisAIServicesBuilder.page(aiState { $0.choices.think = "codex"; $0.brainReady["antigravity"] = true }).thinkLine == "안 되면 Gemini로 생각해요",
          "ai page: the fallback lines name only what would really take over")

    var pending = aiState { $0.choices.think = "api:groq"; $0.thinkStored = "claude" }
    pending.ui.keyOpen = ["groq"]
    check(ArisAIServicesBuilder.page(pending).thinkLine == "쓸 수 있게 될 때까지 Claude로 생각해요" && ArisAIServicesBuilder.page(pending).think.rows[0].warn == "키 필요",
          "ai page: a brain picked before it can answer is shown with what it needs, and the line says who answers until then")

    // Keys.
    let needsKey = aiState { $0.choices.speak = "eleven"; $0.choices.hear = "scribe" }
    let closed = ArisAIServicesBuilder.page(needsKey)
    check(closed.speak.rows[0].warn == "키 필요" && closed.speak.need == .button(message: "ElevenLabs API 키가 필요해요", title: "API 키 추가", .openKey("elevenlabs"))
          && closed.hear.need == closed.speak.need && closed.speak.rows[2].desc == "키를 넣으면 골라요" && closed.speak.rows[2].preview == false
          && closed.speak.rows[2].control == .select(.voice, ArisAISelectFace(label: "Geaun", enabled: false)),
          "ai page: without the ElevenLabs key both cards ask for it, and the voice can't be picked or played yet")
    var open = needsKey
    open.ui.keyOpen = ["elevenlabs"]
    open.ui.keyError["elevenlabs"] = "키가 너무 짧아요."
    check(ArisAIServicesBuilder.page(open).speak.need == .keyField(holder: "elevenlabs", placeholder: "ElevenLabs API 키", hint: "키체인에 저장해요 · 듣기 · 말하기에 같이 써요", error: "키가 너무 짧아요."),
          "ai page: the key field says where the key is kept and what it serves, or what was wrong with the paste")
    let groq = ArisAIServicesBuilder.page(aiState { $0.choices.think = "api:groq" })
    check(groq.think.rows.count == 1 && groq.think.rows[0].warn == "키 필요" && groq.think.need == .button(message: "Groq API 키가 필요해요", title: "API 키 추가", .openKey("groq")),
          "ai page: an API brain without its key shows no model yet, only the key it needs")

    // An API brain and a connection.
    let api = aiState {
        $0.choices.think = "api:openai"
        $0.profiles = [ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true)]
        $0.models["openai"] = .listed(["gpt-6-luna", "gpt-6.1-sol", "gpt-6-astra"])
    }
    let apiPage = ArisAIServicesBuilder.page(api)
    check(apiPage.think.rows[1] == ArisAIRow(title: "모델", desc: "빠르고 똑똑해요", control: .select(.model(.think), ArisAISelectFace(label: "Sol"))) && apiPage.think.need == nil
          && apiPage.savedKeys == [ArisAISavedKey(holder: "openai", name: "OpenAI", masked: nil)],
          "ai page: an API brain with its key shows the model that answers, from the provider's own list; its key can be taken out again")
    let connection = aiState {
        $0.presets.append(ArisAIPreset(id: "conn-0a1b2c3d", title: "내 서버", needsKey: false, local: true, baseURL: "http://localhost:8000/v1", quick: "my-model", strong: "my-model", custom: true))
        $0.profiles = [ArisAIProfile(id: "conn-0a1b2c3d", quick: "my-model", strong: "my-model", hasKey: false)]
        $0.choices.think = "api:conn-0a1b2c3d"
        $0.models["conn-0a1b2c3d"] = .unreachable
    }
    let connectionPage = ArisAIServicesBuilder.page(connection)
    check(connectionPage.think.rows[0].desc == "내 연결 · 내 서버" && connectionPage.think.rows[0].warn == "실행 중이 아니에요"
          && connectionPage.think.rows[1] == ArisAIRow(title: "모델", desc: "목록을 못 불러와서 직접 적어요", control: .field(.model("conn-0a1b2c3d"), text: "my-model", placeholder: "모델 이름"))
          && connectionPage.think.need == .button(message: "내 서버가 실행 중이 아니에요", title: "다시 확인", .recheck("api:conn-0a1b2c3d")),
          "ai page: a connection whose list can't be had takes a typed model name, and one on this Mac that doesn't answer offers 다시 확인")
    var answering = connection
    answering.models["conn-0a1b2c3d"] = .listed(["my-model", "other"])
    check(ArisAIServicesBuilder.page(answering).think.rows[0].desc == "내 연결 · 내 서버 · 이 Mac에 머물러요"
          && ArisAIServicesBuilder.page(answering).think.rows[1].control == .select(.model(.think), ArisAISelectFace(label: "my-model")),
          "ai page: a connection to this Mac keeps the conversation here, and its fetched models are a dropdown")
    check(ArisAIServicesBuilder.page(aiState { $0.choices.think = "api:lmstudio"; $0.models["lmstudio"] = .unreachable }).think.rows[1].desc == "LM Studio에 불러온 모델"
          && ArisAIServicesBuilder.page(aiState { $0.choices.think = "api:ollama" }).think.rows[1].control == .select(.model(.think), ArisAISelectFace(label: "qwen3:8b", enabled: false)),
          "ai page: LM Studio's model is typed when it doesn't answer; a list still loading is a greyed dropdown")

    // Whisper: asked first, then a bar with 취소.
    let whisper = aiState { $0.choices.hear = "whisper"; $0.choices.whisperModel = "small"; $0.whisperInstalled = ["small"] }
    check(ArisAIServicesBuilder.page(whisper).hear.rows[1] == ArisAIRow(title: "모델", desc: "가볍고 빨라요 · 약 220 MB", control: .select(.model(.hear), ArisAISelectFace(label: "작은 모델")))
          && ArisAIServicesBuilder.page(whisper).hear.need == nil, "ai page: Whisper with its model on this Mac asks for nothing")
    var asking = whisper
    asking.ui.asking = "large"
    check(ArisAIServicesBuilder.page(asking).hear.need == .ask(message: "큰 모델은 630 MB를 받아야 해요. 받을까요?", model: "large")
          && ArisAIServicesBuilder.page(asking).hear.rows[1].control == .select(.model(.hear), ArisAISelectFace(label: "작은 모델")),
          "ai page: the large Whisper model asks first (630 MB 받을까요?), and nothing changes until 받기")
    var coming = whisper
    coming.download = ArisAIDownload(model: "large", percent: 42)
    check(ArisAIServicesBuilder.page(coming).hear.need == .progress(label: "큰 모델 받는 중", percent: 42)
          && ArisAIServicesBuilder.page(coming).hear.rows[1].control == .select(.model(.hear), ArisAISelectFace(label: "큰 모델 받는 중", short: "큰 모델", tail: "42%", bar: 42)),
          "ai page: a model coming in shows its bar and percent in the row and in the dropdown's button")
    coming.download = ArisAIDownload(model: "large", percent: 42, phase: .waiting)
    let waiting = ArisAIServicesBuilder.page(coming).hear.need
    coming.download = ArisAIDownload(model: "large", percent: 42, phase: .failed)
    check(waiting == .progress(label: "인터넷이 돌아오면 이어서 받을게요", percent: 42) && ArisAIServicesBuilder.page(coming).hear.need == .failed(message: "큰 모델을 받지 못했어요"),
          "ai page: a download waiting for the network says so; one that failed offers 다시 받기")
    let noModel = ArisAIServicesBuilder.page(aiState { $0.choices.hear = "whisper" })
    check(noModel.hear.rows[0].warn == "모델 받기 필요" && noModel.hear.need == .ask(message: "작은 모델은 약 220 MB를 받아야 해요. 받을까요?", model: "small"),
          "ai page: Whisper chosen with no model on this Mac says 모델 받기 필요 and asks about the small one")

    var jev = aiState()
    jev.ui.jevOpen = true
    jev.ui.jevError = "키를 붙여 넣어 주세요."
    check(ArisAIServicesBuilder.page(jev).jev == .editing(error: "키를 붙여 넣어 주세요."), "ai page: the Jev line opens into its key field, with what was wrong")
    let mac = ArisAIServicesBuilder.page(aiState {
        $0.choices.systemVoice = "yuna.premium"
        $0.voices["macos"] = .loaded([ArisAIVoice(id: "yuna.premium", name: "유나", desc: "여성 · 한국어(대한민국)", tail: "프리미엄")])
    })
    check(mac.speak.rows[1].control == .select(.voice, ArisAISelectFace(label: "유나", tail: "프리미엄")) && mac.speak.rows[1].desc == "여성 · 한국어(대한민국)",
          "ai page: a picked macOS voice shows its name, what it is and its quality")
}

// MARK: - Menus

private func aiMenuTests() {
    let state = aiState {
        $0.choices = ArisAIChoices(think: "claude", hear: "whisper", whisperModel: "small", speak: "eleven", elevenVoiceID: "v2", elevenVoiceName: "지영")
        $0.elevenKey = "x"
        $0.whisperInstalled = ["small"]
        $0.profiles = [ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true)]
        $0.models = ["openai": .listed(["gpt-6-luna", "gpt-6.1-sol", "ft:custom"]), "ollama": .unreachable, "lmstudio": .unreachable]
        $0.presets.append(ArisAIPreset(id: "conn-0a1b2c3d", title: "내 서버", needsKey: true, local: false, baseURL: "https://llm.example.com/v1", quick: "m", strong: "m", custom: true))
        $0.profiles.append(ArisAIProfile(id: "conn-0a1b2c3d", quick: "m", strong: "m", hasKey: true))
    }
    let think = ArisAIServicesBuilder.menu(.provider(.think), state)
    let groups = think.entries.compactMap { entry -> String? in if case .group(let title) = entry { return title }; return nil }
    check(groups == ["구독 · 대화가 Mac 밖으로 나가요", "API 키 · 대화가 Mac 밖으로 나가요", "이 Mac에서 · 이 Mac에 머물러요", "내 연결"]
          && think.entries.filter { $0 == .separator }.count == 3 && think.foot.map(\.title) == ["다른 AI 연결…"],
          "ai menu: 생각 groups its services by how they are reached, the user's connections last, and ends in 다른 AI 연결…")
    func item(_ menu: ArisAIMenu, _ id: String) -> ArisAIMenuItem? { menu.items.first { $0.id == id } }
    check(item(think, "claude")?.checked == true && item(think, "claude")?.subtitle == "Claude Code로 답해요" && item(think, "antigravity")?.tail == "설치 필요"
          && item(think, "api:groq")?.tail == "키 필요" && item(think, "api:openai")?.tail == nil && item(think, "api:lmstudio")?.tail == "실행 중이 아니에요"
          && item(think, "api:conn-0a1b2c3d")?.trailing == .more && item(think, "api:conn-0a1b2c3d")?.subtitle == "https://llm.example.com/v1"
          && think.items.allSatisfy { !$0.disabled },
          "ai menu: each service carries what it is missing as small text; a connection has its 더 보기; every 생각 service can be picked")
    let hear = ArisAIServicesBuilder.menu(.provider(.hear), state)
    check(hear.items.map(\.id) == ["apple", "whisper", "scribe", "openai-stt", "groq-stt", "deepgram", "fish-stt"] && item(hear, "whisper")?.checked == true
          && item(hear, "deepgram")?.disabled == true && item(hear, "deepgram")?.tail == "준비 중" && item(hear, "scribe")?.disabled == false && hear.foot.isEmpty,
          "ai menu: 듣기 lists this Mac's engines then the cloud's; the ones Aris has no engine for are greyed 준비 중")
    let speak = ArisAIServicesBuilder.menu(.provider(.speak), state)
    check(speak.items.map(\.id) == ["macos", "kokoro", "eleven", "fish-tts", "openai-tts"] && speak.items.filter(\.disabled).map(\.id) == ["kokoro", "fish-tts", "openai-tts"],
          "ai menu: 말하기 offers the Mac's voices and ElevenLabs; Kokoro, Fish Audio and OpenAI are listed as 준비 중")
    let both = ArisAIServicesBuilder.menu(.both, state)
    check(both.items.map(\.title) == ["ElevenLabs", "OpenAI", "Fish Audio"] && both.items.map(\.disabled) == [false, true, true],
          "ai menu: 같은 회사로 맞추기 can set both to ElevenLabs today")

    var onAPI = state
    onAPI.choices.think = "api:openai"
    let models = ArisAIServicesBuilder.menu(.model(.think), onAPI)
    check(models.items.map(\.title) == ["Luna", "Sol · 기본", "ft:custom"] && item(models, "gpt-6.1-sol")?.checked == true && item(models, "gpt-6.1-sol")?.code == "gpt-6.1-sol"
          && item(models, "ft:custom")?.subtitle == nil && models.search == nil,
          "ai menu: an API brain's models are the provider's own list; the ones Aris knows get a short name, the id under it")
    onAPI.models["openai"] = .listed((1...40).map { "model-\($0)" })
    check(ArisAIServicesBuilder.menu(.model(.think), onAPI).search == "모델 찾기", "ai menu: a long model list gets a search field")
    check(ArisAIServicesBuilder.menu(.model(.think), onAPI, query: " MODEL-4 ").items.map(\.id) == ["model-4", "model-40"]
          && ArisAIServicesBuilder.menu(.model(.think), onAPI, query: "없는 모델").entries == [.note("찾는 것이 없어요")]
          && ArisAIMenu(entries: [.item(ArisAIMenuItem(id: "a", title: "qwen3-coder")), .item(ArisAIMenuItem(id: "b", title: "deepseek-chat"))]).filtered(by: "deep").items.map(\.id) == ["b"],
          "ai menu: the model search narrows the list by what is typed, whatever the case")
    let whisper = ArisAIServicesBuilder.menu(.model(.hear), state)
    check(whisper.items.map(\.title) == ["작은 모델 · 기본", "큰 모델"] && whisper.items.map(\.tail) == [nil, "630 MB"] && whisper.items[0].checked,
          "ai menu: a Whisper model that isn't on this Mac shows its size")
    check(ArisAIServicesBuilder.menu(.model(.speak), state).items.map(\.title) == ["Flash v2.5", "v4 Turbo · 기본", "v4", "Multilingual v2"],
          "ai menu: ElevenLabs' four models, v4 Turbo the default")

    var voices = state
    voices.voices["eleven"] = .loaded([ArisAIVoice(id: "v1", name: "Alex", desc: "male · korean", own: true, preview: "https://x/p.mp3"), ArisAIVoice(id: "v2", name: "지영", desc: "female", own: true),
                                       ArisAIVoice(id: "v3", name: "Rachel", desc: "female · american"), ArisAIVoice(id: "v4", name: "Adam", desc: "male · american")])
    let voiceMenu = ArisAIServicesBuilder.menu(.voice, voices)
    let voiceGroups = voiceMenu.entries.compactMap { entry -> String? in if case .group(let title) = entry { return title }; return nil }
    check(voiceGroups == ["내 목소리 · 2", "기본 목소리 · 2"] && item(voiceMenu, "v2")?.checked == true && item(voiceMenu, "v1")?.trailing == .play(url: "https://x/p.mp3")
          && voiceMenu.foot.map(\.title) == ["라이브러리에서 찾기", "링크로 추가…"] && voiceMenu.source == "ElevenLabs에서 불러옴" && voiceMenu.search == nil,
          "ai menu: ElevenLabs voices are the account's own then its stock ones, each with a sample; the library and a link add more")
    let found = ArisAIServicesBuilder.menu(.voice, voices, query: "  AMERICAN ")
    check(found.items.map(\.id) == ["v3", "v4"] && found.entries.first == .group("기본 목소리 · 2") && ArisAIServicesBuilder.menu(.voice, voices, query: "없는").entries == [.note("찾는 목소리가 없어요")],
          "ai menu: the voice search matches names and descriptions, whatever the case")
    voices.voices["eleven"] = .loaded((1...11).map { ArisAIVoice(id: "v\($0)", name: "Voice \($0)") })
    check(ArisAIServicesBuilder.menu(.voice, voices).search == "목소리 찾기", "ai menu: more than ten voices get a search field")
    voices.voices["eleven"] = .failed
    check(ArisAIServicesBuilder.menu(.voice, voices).entries == [.note("목소리 목록을 못 받았어요")] && ArisAIServicesBuilder.menu(.voice, state).entries == [.note("목소리를 불러오는 중…")],
          "ai menu: a voice list that is loading or failed says so instead of showing none")
    var mac = state
    mac.choices.speak = "macos"
    mac.voices["macos"] = .loaded([ArisAIVoice(id: "yuna", name: "유나", desc: "여성 · 한국어", tail: "프리미엄")])
    let macMenu = ArisAIServicesBuilder.menu(.voice, mac)
    check(macMenu.items.map(\.title) == ["자동", "유나"] && macMenu.items[0].checked && macMenu.items[1].tail == "프리미엄" && macMenu.foot.isEmpty && macMenu.source == "이 Mac에서 불러옴",
          "ai menu: the Mac's voices follow 자동 (the best voice of each language, as before)")

    check(ArisAIServicesBuilder.change(.provider(.think), picked: "api:groq", in: state) == .think("api:groq")
          && ArisAIServicesBuilder.change(.provider(.hear), picked: "deepgram", in: state) == nil
          && ArisAIServicesBuilder.change(.provider(.speak), picked: "macos", in: state) == .speak("macos")
          && ArisAIServicesBuilder.change(.model(.hear), picked: "large", in: state) == .whisperModel("large")
          && ArisAIServicesBuilder.change(.model(.think), picked: "gpt-6-astra", in: onAPI) == .thinkModel(provider: "api:openai", model: "gpt-6-astra")
          && ArisAIServicesBuilder.change(.voice, picked: "yuna", in: mac) == .systemVoice("yuna")
          && ArisAIServicesBuilder.change(.voice, picked: "nobody", in: state) == nil,
          "ai menu: a pick becomes the store's change; 준비 중 and a voice that isn't in the list change nothing")
}

// MARK: - Sheets

private func aiSheetTests() {
    func base(_ text: String) -> String? { (try? ArisAIConnect.checkBase(text).get())?.base }
    func problem(_ text: String) -> String? { if case .failure(let problem) = ArisAIConnect.checkBase(text) { return problem.text }; return nil }
    check(base(" https://openrouter.ai/api/v1/ ") == "https://openrouter.ai/api/v1" && base("http://localhost:8000/v1") != nil && (try? ArisAIConnect.checkBase("http://127.0.0.1:1234/v1").get())?.local == true
          && problem("llm.example.com") == ArisAIConnect.badBase && problem("http://llm.example.com/v1") == ArisAIConnect.httpElsewhere
          && base("https://user:pw@llm.example.com") == nil && base("https://llm.example.com/v1?x=1") == nil,
          "ai connect: an address is https anywhere or http on this Mac, and what is wrong is said in words")
    check(ArisAIConnect.problems(ArisAIConnectDraft(base: "nope"), saving: false) == ["base": ArisAIConnect.badBase]
          && ArisAIConnect.problems(ArisAIConnectDraft(base: "https://llm.example.com/v1"), saving: false) == ["key": ArisAIConnect.needsKey]
          && ArisAIConnect.problems(ArisAIConnectDraft(editing: "conn-0a1b2c3d", base: "https://llm.example.com/v1"), saving: false).isEmpty
          && ArisAIConnect.problems(ArisAIConnectDraft(base: "http://localhost:8000/v1"), saving: false).isEmpty
          && ArisAIConnect.problems(ArisAIConnectDraft(base: "http://localhost:8000/v1"), saving: true) == ["model": ArisAIConnect.needsModel]
          && ArisAIConnect.problems(ArisAIConnectDraft(base: "http://localhost:8000/v1", model: "kokoro"), saving: true).isEmpty,
          "ai connect: a cloud address needs its key before it is asked (a saved connection keeps its own), this Mac's needs none, and saving needs a model")
    let draft = ArisAIConnectDraft(base: "https://llm.example.com/v1", key: "sk-x", model: "gone")
    let listed = ArisAIConnect.loaded(draft, models: ["a", "b"]), failed = ArisAIConnect.loaded(draft, models: [])
    check(listed.load == .listed && listed.model == "a" && ArisAIConnect.loaded(ArisAIConnectDraft(model: "b"), models: ["a", "b"]).model == "b"
          && failed.load == .failed && failed.model == "gone" && ArisAIConnect.loaded(draft, models: nil).load == .failed,
          "ai connect: fetched models become the dropdown (the typed one kept when it is among them); no list leaves the name to be typed")
    let state = aiState { $0.profiles = [ArisAIProfile(id: "groq", quick: "a", strong: "b", hasKey: true)] }
    let fresh = ArisAIConnect.view(ArisAIConnectDraft(), in: state)
    check(fresh.title == "다른 AI 연결" && fresh.meta == "생각에 써요 · OpenAI 호환 주소" && fresh.quick.map(\.name) == ["OpenRouter", "Groq", "xAI", "Ollama", "LM Studio"]
          && fresh.primary == "연결" && !fresh.primaryEnabled && !fresh.force,
          "ai connect: a new connection offers the providers Aris knows the address of, and can't be saved before its models were fetched")
    if case .custom(let fields, let model, let hint, let tone) = fresh.body {
        check(fields.map(\.label) == ["이름", "주소", "API 키"] && fields[2].placeholder == "클라우드 주소는 꼭 필요해요" && model == .waiting("불러오면 골라요") && hint == "주소를 적으면 그 주소의 /models로 확인해요" && tone == .plain,
              "ai connect: the three fields and a model dropdown that waits for 불러오기")
    } else { check(false, "ai connect: the three fields and a model dropdown that waits for 불러오기") }
    let listedView = ArisAIConnect.view(listed, in: state), failedView = ArisAIConnect.view(failed, in: state)
    if case .custom(_, let model, let hint, let tone) = listedView.body, case .custom(_, let typed, let failedHint, let failedTone) = failedView.body {
        check(model == .select("a") && hint == "연결됐어요 · 모델 2개" && tone == .ok && listedView.primaryEnabled && typed == .field && failedTone == .bad
              && failedHint == "목록을 못 불러왔어요 · 주소를 확인하거나 모델 이름을 적어요" && failedView.force && !failedView.primaryEnabled,
              "ai connect: a fetched list enables 연결; a failed one offers the typed name and 그래도 저장")
    } else { check(false, "ai connect: a fetched list enables 연결; a failed one offers the typed name and 그래도 저장") }
    let local = ArisAIConnect.view(ArisAIConnectDraft(base: "http://localhost:8000/v1"), in: state)
    if case .custom(let fields, _, let hint, _) = local.body {
        check(fields[2].placeholder == "이 Mac 서버는 없어도 돼요" && hint == "http://localhost:8000/v1/models로 확인해요", "ai connect: this Mac's server says its key isn't needed, and which address will be asked")
    } else { check(false, "ai connect: this Mac's server says its key isn't needed") }
    let editing = ArisAIConnect.view(ArisAIConnect.editing(ArisAIPreset(id: "conn-0a1b2c3d", title: "내 서버", needsKey: true, local: false, baseURL: "https://llm.example.com/v1", quick: "m", strong: "m", custom: true), model: "m"), in: state)
    if case .custom(let fields, _, _, _) = editing.body {
        check(editing.title == "연결 고치기" && editing.quick.isEmpty && editing.primary == "저장" && fields[2].placeholder == "저장된 키를 그대로 써요", "ai connect: changing a connection keeps its saved key unless a new one is typed")
    } else { check(false, "ai connect: changing a connection keeps its saved key") }
    let groq = ArisAIConnect.view(ArisAIConnectDraft(shipped: "groq"), in: state), router = ArisAIConnect.view(ArisAIConnectDraft(shipped: "openrouter"), in: state)
    let ollama = ArisAIConnect.view(ArisAIConnectDraft(shipped: "ollama"), in: state)
    check(groq.body == .shipped(note: "Groq는 목록에 이미 있어요", key: nil, saved: true) && groq.primary == "Groq 쓰기" && groq.quick.first { $0.picked }?.id == "groq"
          && router.body == .shipped(note: "OpenRouter는 Aris가 주소를 알고 있어요 · API 키만 넣으면 돼요", key: .init(id: "key", label: "API 키", placeholder: "OpenRouter API 키", secure: true), saved: false)
          && ollama.body == .shipped(note: "Ollama를 이 Mac에서 바로 써요", key: nil, saved: false) && ollama.primary == "Ollama 쓰기",
          "ai connect: a provider Aris ships is used as it is (its saved key, or a field for one); nothing is copied into a connection")
    let voice = ArisAILibraryVoice(id: "lib1", owner: "o", name: "하늘", desc: "", preview: nil)
    check(ArisAIConnect.isAdded(voice, in: ArisAILibraryState(added: ["lib1"]), account: []) && ArisAIConnect.isAdded(voice, in: ArisAILibraryState(), account: [ArisAIVoice(id: "lib1", name: "하늘")])
          && !ArisAIConnect.isAdded(voice, in: ArisAILibraryState(), account: []), "ai library: a voice just added, or already in the account, reads 추가됨")
}

// MARK: - Voices

private func aiVoiceTests() {
    let account = Data(#"""
    {"voices":[{"voice_id":"premade0000000000001","name":"Rachel","category":"premade","labels":{"gender":"female","accent":"american"},"preview_url":"https://cdn.example/rachel.mp3"},
               {"voice_id":"cloned00000000000002","name":"Alex","category":"cloned","labels":{"gender":"male"}},
               {"name":"no id"}]}
    """#.utf8)
    let voices = ArisAIEleven.voices(from: account) ?? []
    check(voices.map(\.name) == ["Alex", "Rachel"] && voices[0].own && !voices[1].own && voices[1].desc == "female · american" && voices[1].preview == "https://cdn.example/rachel.mp3",
          "ai voices: the account's list (GET /v1/voices) reads as its own voices first, each with what ElevenLabs says about it and its sample")
    check(ArisAIEleven.voices(from: Data("<html>".utf8)) == nil, "ai voices: an answer that isn't a voice list is no list")
    let list = ArisAIEleven.voicesRequest(key: "k-test")
    check(list?.url?.absoluteString == "https://api.elevenlabs.io/v1/voices" && list?.value(forHTTPHeaderField: "xi-api-key") == "k-test", "ai voices: the list request carries the key to ElevenLabs only")

    let library = ArisAIEleven.libraryRequest(key: "k-test", ArisAILibraryQuery(search: " 차분한 ", language: "ko", gender: "female", use: "conversational"))
    let items = URLComponents(url: library?.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems ?? []
    check(library?.url?.path == "/v1/shared-voices" && items.contains(URLQueryItem(name: "search", value: "차분한")) && items.contains(URLQueryItem(name: "language", value: "ko"))
          && items.contains(URLQueryItem(name: "gender", value: "female")) && items.contains(URLQueryItem(name: "use_cases", value: "conversational"))
          && URLComponents(url: ArisAIEleven.libraryRequest(key: "k", ArisAILibraryQuery())?.url ?? URL(fileURLWithPath: "/"), resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "page_size", value: "30")],
          "ai voices: the library is searched with what was typed and the three filters, and with none of them when nothing is set")
    let shared = Data(#"""
    {"voices":[{"public_owner_id":"owner000000000000001","voice_id":"shared00000000000001","name":"하늘","gender":"female","language":"ko","use_case":"narrative_story","descriptive":"calm","preview_url":"https://cdn.example/h.mp3"},
               {"public_owner_id":"../etc","voice_id":"shared00000000000002","name":"bad owner"},
               {"voice_id":"shared00000000000003","name":"no owner"}],"has_more":false}
    """#.utf8)
    let found = ArisAIEleven.library(from: shared) ?? []
    check(found == [ArisAILibraryVoice(id: "shared00000000000001", owner: "owner000000000000001", name: "하늘", desc: "calm · 여성 · 한국어 · 내레이션", preview: "https://cdn.example/h.mp3")],
          "ai voices: a library voice reads with its owner (추가 needs it); one whose ids aren't plain ids is left out")
    let add = ArisAIEleven.addRequest(key: "k-test", voice: found[0])
    check(add?.url?.path == "/v1/voices/add/owner000000000000001/shared00000000000001" && add?.httpMethod == "POST"
          && ((try? JSONSerialization.jsonObject(with: add?.httpBody ?? Data())) as? [String: String]) == ["new_name": "하늘"]
          && ArisAIEleven.addedID(from: Data(#"{"voice_id":"mine0000000000000009"}"#.utf8)) == "mine0000000000000009",
          "ai voices: 추가 posts the voice to the account under its own name and reads back its new id")

    check(ArisAIEleven.voiceID(fromLink: "https://elevenlabs.io/app/voice-library?voiceId=k5siOxi4qsPS2kASoRt7") == "k5siOxi4qsPS2kASoRt7"
          && ArisAIEleven.voiceID(fromLink: "  k5siOxi4qsPS2kASoRt7 ") == "k5siOxi4qsPS2kASoRt7"
          && ArisAIEleven.voiceID(fromLink: "https://elevenlabs.io/voice-lab/voice/k5siOxi4qsPS2kASoRt7?x=1") == "k5siOxi4qsPS2kASoRt7"
          && ArisAIEleven.voiceID(fromLink: "https://example.com/hello") == nil && ArisAIEleven.voiceID(fromLink: "short") == nil
          && ArisAIEleven.voiceID(fromLink: "../../v1/user") == nil && ArisAIEleven.voiceRequest(key: "k", id: "../user") == nil,
          "ai voices: a share link or a bare id gives the voice id; anything else gives none, and only a plain id ever goes into a path")

    // The calls, against a transport that answers from fixtures.
    final class Calls: @unchecked Sendable { var paths: [String] = [] }
    let calls = Calls()
    let single = Data(#"{"voice_id":"cloned00000000000002","name":"Alex","category":"cloned","labels":{"gender":"male"}}"#.utf8)
    func transport(mine: Bool) -> ArisAITransport {
        { request in
            let path = request.url?.path ?? ""
            calls.paths.append((request.httpMethod ?? "GET") + " " + path)
            if path == "/v1/voices" { return (account, 200) }
            if path.hasPrefix("/v1/voices/add/") { return (Data(#"{"voice_id":"mine0000000000000009"}"#.utf8), 200) }
            if path.hasPrefix("/v1/voices/") { return mine ? (single, 200) : (Data(), 404) }
            if path == "/v1/shared-voices" { return (shared, 200) }
            return nil
        }
    }
    let done = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var loaded: [ArisAIVoice]?, mine: ArisAIEleven.Found?, other: ArisAIEleven.Found?, none: ArisAIEleven.Found?, added: String?, refused: [ArisAIVoice]?
    Task {
        loaded = await ArisAIEleven.loadVoices(key: "k", transport: transport(mine: true))
        mine = await ArisAIEleven.find(key: "k", id: "cloned00000000000002", transport: transport(mine: true))
        other = await ArisAIEleven.find(key: "k", id: "shared00000000000001", transport: transport(mine: false))
        none = await ArisAIEleven.find(key: "k", id: "nobody00000000000000", transport: transport(mine: false))
        added = await ArisAIEleven.add(key: "k", voice: found[0], transport: transport(mine: false))
        refused = await ArisAIEleven.loadVoices(key: "k", transport: { _ in (Data("{}".utf8), 401) })
        done.signal()
    }
    done.wait()
    check(loaded?.count == 2 && refused == nil, "ai voices: the list loads through the transport it is given; a refused key is no list")
    if case .mine(let voice)? = mine { check(voice.name == "Alex" && voice.own, "ai voices: a link to a voice the account already has finds it there") } else { check(false, "ai voices: a link to a voice the account already has finds it there") }
    check(other == .shared(found[0]) && none == nil && added == "mine0000000000000009"
          && calls.paths.contains("GET /v1/voices/shared00000000000001") && calls.paths.contains("POST /v1/voices/add/owner000000000000001/shared00000000000001"),
          "ai voices: a link to a library voice finds it there and 추가 adds it; an id that is neither finds nothing")

    let system = ArisAISystemVoices.list([
        ArisAISystemVoice(identifier: "com.apple.voice.compact.en-US.Samantha", name: "Samantha", language: "en-US", quality: 1, gender: 2),
        ArisAISystemVoice(identifier: "com.apple.eloquence.ko-KR.Eddy", name: "Eddy", language: "ko-KR", quality: 1, gender: 1),
        ArisAISystemVoice(identifier: "com.apple.voice.compact.ko-KR.Yuna", name: "유나", language: "ko-KR", quality: 1, gender: 2),
        ArisAISystemVoice(identifier: "com.apple.voice.premium.ko-KR.Yuna", name: "유나", language: "ko-KR", quality: 3, gender: 2),
        ArisAISystemVoice(identifier: "com.apple.voice.enhanced.ja-JP.Kyoko", name: "Kyoko", language: "ja-JP", quality: 2, gender: 0),
    ], languages: ["ko", "en"])
    check(system.map(\.id) == ["com.apple.voice.premium.ko-KR.Yuna", "com.apple.voice.compact.ko-KR.Yuna", "com.apple.voice.compact.en-US.Samantha", "com.apple.voice.enhanced.ja-JP.Kyoko", "com.apple.eloquence.ko-KR.Eddy"]
          && system[0].tail == "프리미엄" && system[0].desc.hasPrefix("여성 · 한국어") && system[3].tail == "고급" && !system[3].desc.contains("여성") && system[1].tail.isEmpty,
          "ai voices: the Mac's voices list Aris's languages first, the better voices of each first, the robotic ones last")
    check(ArisAILibraryQuery().setting("gender", "male").gender == "male" && ArisAILibraryQuery(language: "ko").value("language") == "ko"
          && ArisAILibraryQuery.options("use").first?.title == "모든 쓰임", "ai voices: the library's filters read and set by name")
}

// MARK: - The engines' hooks

private func aiEngineTests() {
    let voices = [ArisSpeech.Voice(identifier: "ko.compact", language: "ko-KR", quality: 1), ArisSpeech.Voice(identifier: "ko.premium", language: "ko-KR", quality: 3),
                  ArisSpeech.Voice(identifier: "en.samantha", language: "en-US", quality: 1)]
    check(ArisSpeech.pickVoice(from: voices, language: "ko-KR", preferred: "ko.compact") == "ko.compact"
          && ArisSpeech.pickVoice(from: voices, language: "en-US", preferred: "ko.compact") == "en.samantha"
          && ArisSpeech.pickVoice(from: voices, language: "ko-KR", preferred: "gone") == "ko.premium"
          && ArisSpeech.pickVoice(from: voices, language: "ko-KR") == "ko.premium",
          "ai engines: the picked macOS voice speaks its own language; another language, or a voice no longer installed, gets the best voice as before")
    check(ArisElevenLabs.model(stored: nil) == "eleven_v4_turbo" && ArisElevenLabs.model(stored: "eleven_flash_v2_5") == "eleven_flash_v2_5" && ArisElevenLabs.model(stored: "tts-1") == "eleven_v4_turbo",
          "ai engines: ElevenLabs speaks with the picked model, v4 Turbo when none (or one it doesn't have) is stored")
    let body = (try? JSONSerialization.jsonObject(with: ArisElevenLabs.request(text: "안녕", key: "k", model: "eleven_multilingual_v2").httpBody ?? Data())) as? [String: Any]
    check(body?["model_id"] as? String == "eleven_multilingual_v2", "ai engines: the speech request carries the picked model")
}

// MARK: - 연결된 서비스's wait

private func aiServicesWaitTests() {
    let waiting = [ArisSettingItem(id: "ai.service.loading", icon: .none, title: "서비스를 확인하는 중…", control: .none, indexed: false),
                   ArisSettingItem(id: "ai.mcp.composio", icon: .symbol("square.stack.3d.up"), title: "Composio", control: .custom("mcp.composio"))]
    let none = ArisAIServicesBuilder.serviceRows(waiting, read: .answered), unread = ArisAIServicesBuilder.serviceRows(waiting, read: .unanswered)
    check(ArisAIServicesBuilder.serviceRows(waiting, read: .waiting) == waiting && none.map(\.id) == ["ai.service.none", "ai.mcp.composio"]
          && none[0].title == "연결된 AI가 없어요" && none[0].desc?.contains("로그인") == true && none[0].desc?.contains("Claude Code") == true && none[1] == waiting[1],
          "ai services: once the read has ended with no AI, the checking line becomes one that says none is connected and how to connect one; the other rows are as they were")
    check(unread.map(\.id) == ["ai.service.unread", "ai.mcp.composio"] && unread[0].title == "연결된 AI를 확인하지 못했어요" && unread[0].desc?.contains("답하지 않았어요") == true,
          "ai services: a read aris-agent never answered says so, instead of waiting for ever or claiming there is none")
    let listed = [ArisSettingItem(id: "ai.service.claude", icon: .logo("claude"), title: "Claude", control: .chip("연결됨", tone: .ok), indexed: false)]
    check(ArisAIServicesRead.allCases.allSatisfy { ArisAIServicesBuilder.serviceRows(listed, read: $0) == listed }, "ai services: a real list is never replaced, however the read stands")
    let unknown: [String: Bool] = [:], missing = ["claude": false, "codex": false, "antigravity": false, "api": false], one = ["claude": true, "codex": false, "antigravity": false]
    func read(_ listed: Int, _ ready: [String: Bool], _ waited: TimeInterval, reachable: Bool = true) -> ArisAIServicesRead {
        ArisAIServicesBuilder.servicesRead(listed: listed, brainReady: ready, agentReachable: reachable, waited: waited)
    }
    check(ArisAIServicesBuilder.servicesWait == 20 && read(0, unknown, 3) == .waiting && read(0, one, 19.9) == .waiting && read(0, one, 20) == .answered
          && read(0, missing, 0) == .answered && read(1, unknown, 0) == .answered && read(0, unknown, 20, reachable: false) == .unanswered && read(0, unknown, 5, reachable: false) == .waiting,
          "ai services: where the usage model doesn't say how its read stands, the wait ends when a service is listed, at once when aris-agent says none of the three AIs is on this Mac, and after 20 seconds either way (unanswered when aris-agent never answered)")
}

// MARK: - English

/// Every string a page, a dropdown or the connect sheet puts on screen (names the user or a provider gave are data).
private func aiShown(_ page: ArisAIPage) -> [String] {
    var out: [String] = []
    for card in [page.think, page.hear, page.speak] {
        out.append(card.job.title)
        for row in card.rows {
            out += [row.title, row.desc] + [row.warn].compactMap { $0 }
            switch row.control {
            case .select(_, let face): out += [face.label] + [face.tail].compactMap { $0 }
            case .fixed(let name): out.append(name)
            case .field(_, _, let placeholder): out.append(placeholder)
            }
        }
        switch card.need {
        case .button(let message, let title, _)?: out += [message, title]
        case .keyField(_, let placeholder, let hint, let error)?: out += [placeholder, hint] + [error].compactMap { $0 }
        case .ask(let message, _)?, .failed(let message)?, .message(let message)?: out.append(message)
        case .progress(let label, _)?: out.append(label)
        case .checked(let message, let note)?: out += [message, note]
        case nil: break
        }
    }
    out += [page.thinkLine, page.voiceLine, page.login?.title, page.login?.desc].compactMap { $0 }
    return out.filter { !$0.isEmpty }
}

private func aiShown(_ menu: ArisAIMenu) -> [String] {
    var out = [menu.search, menu.source].compactMap { $0 }
    for entry in menu.entries {
        switch entry {
        case .group(let text), .note(let text): out.append(text)
        case .item(let item): out += [item.title, item.subtitle, item.tail].compactMap { $0 }
        case .separator: break
        }
    }
    return out + menu.foot.map(\.title)
}

private func aiShown(_ view: ArisAIConnect.View) -> [String] {
    var out = [view.title, view.meta, view.primary] + [view.error].compactMap { $0 }
    switch view.body {
    case .shipped(let note, let key, _): out += [note] + (key.map { [$0.label, $0.placeholder] + [$0.error].compactMap { $0 } } ?? [])
    case .custom(let fields, let model, let hint, _):
        out += fields.flatMap { [$0.label, $0.placeholder] + [$0.error].compactMap { $0 } } + [hint]
        if case .waiting(let text) = model { out.append(text) }
    }
    return out
}

private func aiHangul(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
}

private func aiEnglishTests() {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let pairs = ArisSettingsCopy.pairs(catalog: (try? Data(contentsOf: root.appendingPathComponent("Aris/components/Settings/Settings.xcstrings"))) ?? Data())
    ArisSettingsCopy.install(pairs)
    defer { ArisSettingsCopy.install([:]) }
    let english = ArisSettingsWording.make(page: .ai, english: true), korean = ArisSettingsWording.make(page: .ai, english: false)
    check(ArisSettingsCopy.translatedPages.contains(.ai) && english.pageEnglish && !korean.pageEnglish, "ai in English: AI 서비스 is one of the pages drawn in English on an English Mac")

    // The states between them reach every line the page, its dropdowns and the connect sheet can build.
    let connection = ArisAIPreset(id: "conn-0a1b2c3d", title: "My server", needsKey: false, local: true, baseURL: "http://localhost:8000/v1", quick: "m", strong: "m", custom: true)
    let voicesList = [ArisAIVoice(id: "v1", name: "Alex", desc: "male · korean", own: true), ArisAIVoice(id: "v2", name: "Rachel", desc: "female · american")]
    let macList = ArisAISystemVoices.list([ArisAISystemVoice(identifier: "ko.premium", name: "Yuna", language: "ko-KR", quality: 3, gender: 2),
                                           ArisAISystemVoice(identifier: "en.enhanced", name: "Samantha", language: "en-US", quality: 2, gender: 0)], languages: ["ko", "en"], english: true)
    var states: [ArisAIServicesState] = []
    for think in ["claude", "codex", "antigravity", "api:openai", "api:groq", "api:ollama", "api:lmstudio", "api:conn-0a1b2c3d", "api:", "api:gone"] {
        for hear in ["apple", "whisper", "scribe"] {
            for (speak, key) in [("macos", false), ("eleven", false), ("eleven", true), ("macos", true)] {
                states.append(aiState {
                    $0.presets.append(connection)
                    $0.profiles = [ArisAIProfile(id: "openai", quick: "gpt-6-luna", strong: "gpt-6.1-sol", hasKey: true), ArisAIProfile(id: "conn-0a1b2c3d", quick: "m", strong: "m", hasKey: false)]
                    $0.models = ["openai": .listed(["gpt-6-luna", "gpt-6.1-sol", "x"]), "ollama": key ? .unreachable : .listed(["qwen3:8b"]), "lmstudio": .unreachable,
                                 "conn-0a1b2c3d": key ? .listed(["m", "n"]) : .unreachable]
                    $0.choices = ArisAIChoices(think: think, hear: hear, whisperModel: key ? "small" : nil, speak: speak, elevenVoiceID: "v1", elevenVoiceName: "Alex",
                                               systemVoice: key ? "ko.premium" : "")
                    $0.brainReady = key ? ["claude": true, "codex": true, "antigravity": true] : ["claude": false, "codex": false, "antigravity": false]
                    $0.elevenKey = key ? "••••a91c" : nil
                    $0.whisperInstalled = key ? ["small"] : []
                    $0.voices = ["macos": .loaded(macList), "eleven": key ? .loaded(voicesList) : .failed]
                    $0.thinkStored = key ? nil : "claude"
                    if !key { $0.ui.keyOpen = ["elevenlabs", "groq"]; $0.ui.keyError["elevenlabs"] = ArisKeyFile.Problem.tooShort.message }
                    if key && hear == "whisper" { $0.ui.asking = "large" }
                })
            }
        }
    }
    for phase in [ArisAIDownload.Phase.running, .waiting, .paused, .failed] {
        for model in ["small", "large"] { states.append(aiState { $0.choices.hear = "whisper"; $0.download = ArisAIDownload(model: model, percent: 42, phase: phase) }) }
    }
    states.append(aiState { $0.choices.think = "api:"; $0.agentReachable = false })
    states.append(aiState { $0.choices.speak = "eleven"; $0.elevenKey = "x" })
    var lines: [String] = []
    for state in states {
        lines += aiShown(ArisAIServicesBuilder.page(state))
        for kind in [ArisAIMenuKind.provider(.think), .provider(.hear), .provider(.speak), .model(.think), .model(.hear), .model(.speak), .voice, .both, .connectionMore("conn-0a1b2c3d")] {
            lines += aiShown(ArisAIServicesBuilder.menu(kind, state)) + aiShown(ArisAIServicesBuilder.menu(kind, state, query: "zzz"))
        }
    }
    let state = states[0]
    var drafts = [ArisAIConnectDraft(), ArisAIConnectDraft(base: "http://localhost:8000/v1"), ArisAIConnect.editing(connection, model: "m"),
                  ArisAIConnect.loaded(ArisAIConnectDraft(base: "https://x.example/v1", key: "k"), models: ["a"]), ArisAIConnect.loaded(ArisAIConnectDraft(base: "https://x.example/v1", key: "k"), models: nil)]
    drafts += ArisAICatalogue.quickAPI.map { ArisAIConnectDraft(shipped: $0) }
    for bad in ["nope", "http://x.example/v1", "https://x.example/v1"] {
        var draft = ArisAIConnectDraft(base: bad)
        draft.errors = ArisAIConnect.problems(draft, saving: true)
        drafts.append(draft)
    }
    var loading = ArisAIConnectDraft(base: "https://x.example/v1", key: "k"), modelless = ArisAIConnect.loaded(ArisAIConnectDraft(base: "http://localhost:8000/v1"), models: nil)
    loading.load = .loading
    modelless.errors = ArisAIConnect.problems(modelless, saving: true)
    for draft in drafts + [loading, modelless] { lines += aiShown(ArisAIConnect.view(draft, in: state)) }
    lines += ArisAISettledLines.all + ["filter"].flatMap { _ in ["language", "gender", "use"].flatMap { ArisAILibraryQuery.options($0).map(\.title) } }
    let left = Set(lines.filter { aiHangul(english.dotted($0)) && $0 != "한국어" }).sorted()
    check(lines.count > 2_000 && left.isEmpty, "ai in English: nothing the page, its dropdowns or the connect sheet can show is left in Korean" + (left.isEmpty ? "" : " (\(left.prefix(6)))"))
    check(Set(lines.map { korean.dotted($0) }) == Set(lines), "ai in English: in Korean every line is drawn exactly as written")

    check(english.dotted("Claude · 대화가 Mac 밖으로 나가요") == "Claude · The conversation leaves this Mac" && english.dotted("내 연결 · My server · 이 Mac에 머물러요") == "My connections · My server · Stays on this Mac"
          && english.dotted("female · korean · calm") == "female · korean · calm" && english.dotted("작은 모델 · 기본") == "Small model · default"
          && english.dotted("키체인에 저장해요 · 듣기 · 말하기에 같이 써요") == "Kept in the Keychain · used for listening and speaking"
          && english.dotted("구독 · 대화가 Mac 밖으로 나가요") == "Subscription · leaves this Mac" && english.dotted("클라우드 · 답이 Mac 밖으로 나가요") == "Cloud · the answer leaves this Mac",
          "ai in English: a line is said as a whole when the catalog has it, else part by part, and a name or a voice's own words stay as they are")
    check(english("키 필요") == "Needs a key" && english("설치 필요") == "Not installed" && english("모델 받기 필요") == "Needs a model" && english("실행 중이 아니에요") == "Not running"
          && english("준비 중") == "Coming" && english("지우기") == "Clear" && english("API 키 추가") == "Add API key" && english("없음") == "None",
          "ai in English: the states and the earlier wording picks (Clear, API key, None)")
    check(english("Ollama가 실행 중이 아니에요") == "Ollama isn't running" && english("LM Studio가 실행 중이 아니에요") == "LM Studio isn't running" && english("내 서버가 실행 중이 아니에요") == "내 서버 isn't running"
          && english("Groq API 키가 필요해요") == "Groq needs an API key" && english("쓸 수 있게 될 때까지 Claude로 생각해요") == "Until it can be used, Claude thinks"
          && english("쓸 수 있게 될 때까지 Gemini API로 생각해요") == "Until it can be used, Gemini API thinks" && english("큰 모델은 630 MB를 받아야 해요. 받을까요?") == "The large model is a 630 MB download. Download it?"
          && english("연결됐어요 · 모델 12개") == "Connected · 12 models" && english("https://x.example/v1/models로 확인해요") == "Checked at https://x.example/v1/models",
          "ai in English: a name or a number keeps its place, whichever particle the Korean took")
    let toasts: [String: String?] = ["My server를 연결했어요": "Connected My server", "Groq을 고쳤어요": "Changed Groq", "My server를 지웠어요": "Removed My server", "목소리를 Rachel로 바꿨어요": "Changed the voice to Rachel",
                  "듣기와 말하기를 ElevenLabs로 맞췄어요": "Listening and speaking both use ElevenLabs now", "Rachel 목소리를 추가했어요": "Added the voice Rachel",
                  "ElevenLabs API 키를 저장했어요": "Saved the ElevenLabs API key", "Groq 키를 키체인에서 지웠어요": nil, "큰 모델을 받았어요": "Downloaded the large model",
                  "TypeSafe 키를 키체인에서 지웠어요": nil, ArisSettingsBuilder.loginToast(opened: true, brain: .claude): "Terminal is open. Sign in there",
                  ArisSettingsBuilder.loginToast(opened: false, brain: .codex): "Codex isn't installed on this Mac. Install it first"]
    let wrong = toasts.filter { toast in
        let said: String = english(toast.key)
        return aiHangul(said) || (toast.value != nil && said != toast.value)
    }.map(\.key)
    check(wrong.isEmpty, "ai in English: what the page says when something is done is English, the name as it is" + (wrong.isEmpty ? "" : " (\(wrong.prefix(3)))"))
    let shared = Data(#"{"voices":[{"public_owner_id":"owner000000000000001","voice_id":"shared00000000000001","name":"Sky","gender":"female","language":"ko","use_case":"narrative_story","descriptive":"calm"}]}"#.utf8)
    check(ArisAIEleven.library(from: shared, english: true)?.first?.desc == "calm · female · Korean · narrative story" && ArisAIEleven.library(from: shared)?.first?.desc == "calm · 여성 · 한국어 · 내레이션"
          && macList.map(\.desc) == ["female · Korean (South Korea)", "English (United States)"] && macList.map { english.dotted($0.tail) } == ["Premium", "Enhanced"],
          "ai in English: a library voice and a Mac voice are described in English (ElevenLabs' own words, the language by its English name)")
    let rows = english.sections(ArisSettingsBuilder.sections(.ai, ArisSettingsSnapshot()))
    let serviceRows = rows.first { $0.id == "ai.services" }?.rows ?? []
    let none = ArisAIServicesBuilder.serviceRows(serviceRows, read: .answered).map(english.row).first { $0.id == "ai.service.none" }
    let unread = ArisAIServicesBuilder.serviceRows(serviceRows, read: .unanswered).map(english.row).first { $0.id == "ai.service.unread" }
    check(rows.map(\.heading) == ["Thinking", "Voice", "Connected services", nil] && none?.title == "No AI is connected" && none?.desc?.hasPrefix("Install Claude Code, Codex or Antigravity") == true
          && unread?.title == "Couldn't check the connected AIs" && unread?.desc == "Aris's helper didn't answer. Open this page again in a moment."
          && english.of(.ai, ArisSettingsPage.ai.subtitle) == "Choose what thinks, listens and speaks",
          "ai in English: the page's headings, its line beside the title and 연결된 서비스's own lines are English")
}

/// The lines the views and the live page hold themselves that take a value (each literal is checked by the file scan in
/// fix-leftovers-tests; here with real values in).
private enum ArisAISettledLines {
    static let all = ["OpenRouter 쓰기", "Rachel 더 보기", "Rachel 미리 듣기", "Rachel 그만 듣기", "ElevenLabs API 키", "이 Mac의 Ollama", "LM Studio에 불러온 모델"]
}

// MARK: - The user's own connections (aris-agent)

#if !AI_QUICK
/// The page in the settings window: its rows in the search, and the three names in the notch preview.
private func aiSettingsWindowTests() {
    let rows = ArisSettingsBuilder.sections(.ai, ArisSettingsSnapshot())
    check(rows.map(\.id) == ["ai.think", "ai.voice", "ai.services", "ai.more"] && rows[0].rows.map(\.id) == ["ai.brain", "ai.jev"] && rows[1].rows.map(\.id) == ["ai.hear", "ai.speak"],
          "ai settings: the page's sections are 생각, 음성, 연결된 서비스 and the two rows it had")
    let shown = ArisSettingsBuilder.searchable(ArisSettingsSnapshot())
    func first(_ query: String) -> String? { ArisSettingsIndex.search(query, among: shown).first?.id }
    check(first("듣기") == "ai.hear" && first("위스퍼") == "ai.hear" && first("Apple 받아쓰기") == "ai.hear" && first("짧은 명령") == "ai.jev" && first("TypeSafe") == "ai.jev"
          && first("OpenRouter") == "ai.brain" && first("다른 AI 연결") == "ai.brain" && first("ChatGPT") == "ai.brain" && first("라이브러리") == "ai.speak" && first("Composio") == "ai.mcp.composio"
          && ArisSettingsIndex.search("ElevenLabs", among: shown).contains { $0.id == "ai.speak" } && ArisSettingsIndex.search("ElevenLabs", among: shown).contains { $0.id == "ai.hear" },
          "ai settings: the search finds 생각, Jev, 듣기 and 말하기 by their names and by the services in them")
    check(ArisSettingsIndex.entry("ai.apiBrain") == nil && ArisSettingsIndex.entry("ai.key.elevenlabs-key") == nil && ArisSettingsIndex.entry("ai.add") == nil,
          "ai settings: the rows the page no longer draws are out of the search")
}

private func aiConnectionTests() {
    check(ArisAPIConnection.checkBase(" https://openrouter.ai/api/v1/ ") == "https://openrouter.ai/api/v1" && ArisAPIConnection.checkBase("http://localhost:8000/v1") == "http://localhost:8000/v1"
          && ArisAPIConnection.checkBase("http://192.168.0.9:8000/v1") == nil && ArisAPIConnection.checkBase("http://llm.example.com/v1") == nil
          && ArisAPIConnection.checkBase("https://user:pw@llm.example.com/v1") == nil && ArisAPIConnection.checkBase("https://llm.example.com/v1?key=1") == nil
          && ArisAPIConnection.checkBase("ftp://llm.example.com") == nil && ArisAPIConnection.checkBase("llm.example.com") == nil,
          "ai connections: an address is https anywhere or http on this Mac only, with no user, password or query")
    check(ArisAPIConnection.isID("conn-0a1b2c3d") && !ArisAPIConnection.isID("openai") && !ArisAPIConnection.isID("conn-XYZ") && ArisAPIConnection.isID(ArisAPIConnection.newID())
          && ArisAPIConnection.checkName("  내 서버 ") == "내 서버" && ArisAPIConnection.checkName("") == nil && ArisAPIConnection.checkName(String(repeating: "a", count: 41)) == nil,
          "ai connections: an id can never be a shipped provider's, and a name is one short line")

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aris-ai-conn-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder); ArisAPICustomPresets.set([]) }
    let secrets = ArisMCPMemorySecrets(), signing = ArisMCPMemorySecrets()
    let store = ArisAPIStore(file: folder.appendingPathComponent("api-brains.json"), signing: signing)
    var changed = 0
    var asked: [URLRequest] = []
    var answer: Data? = Data(#"{"object":"list","data":[{"id":"deepseek-chat"},{"id":"deepseek-reasoner"},{"id":""}]}"#.utf8)
    func send(_ body: [String: Any]) -> (status: String, object: [String: Any]) {
        var out: (String, [String: Any]) = ("", [:])
        ArisAPIRoutes.settings(body, store: store, secrets: secrets, changed: { changed += 1 }, smoke: { _, _, _ in ArisAPISmoke.Outcome() }) { status, data in
            out = (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        return out
    }
    func route(_ body: [String: Any]) -> (status: String, object: [String: Any]) {
        var out: (String, [String: Any]) = ("", [:])
        ArisAPIConnectionRoutes.settings(body, store: store, secrets: secrets, changed: { changed += 1 }, fetch: { request, done in asked.append(request); done(answer) }) { status, data in
            out = (status, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        return out
    }

    // An old file (no connections) is signed exactly as before.
    _ = store.update { $0.saving(ArisAPIProfile(id: "groq", quick: "a", strong: "b", baseURL: nil, vision: nil, tools: nil)) }
    check(!((try? String(contentsOf: store.file, encoding: .utf8)) ?? "connections").contains("connections") && store.load().profile("groq") != nil,
          "ai connections: a list with no connection is written and signed as it always was")

    let probe = route(["op": "probe", "base": "https://api.example.com/v1/", "key": "sk-test-1234567890abcdef"])
    check(probe.status == "200 OK" && probe.object["ok"] as? Bool == true && probe.object["models"] as? [String] == ["deepseek-chat", "deepseek-reasoner"]
          && asked.last?.url?.absoluteString == "https://api.example.com/v1/models" && asked.last?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-1234567890abcdef"
          && store.load().connections == nil,
          "ai connections: 불러오기 asks the address's /models with the typed key and lists its models; nothing is saved")
    let before = asked.count
    check(route(["op": "probe", "base": "https://api.example.com/v1"]).object["error"] as? String == ArisAPIConnectionRoutes.needsKeyLine
          && route(["op": "probe", "base": "http://api.example.com/v1", "key": "sk-test-1234567890abcdef"]).status.hasPrefix("400") && asked.count == before,
          "ai connections: a cloud address without a key, or over plain http, is refused before anything is sent")
    answer = nil
    let down = route(["op": "probe", "base": "http://localhost:8000/v1", "key": "ignored-on-this-mac"])
    check(down.object["ok"] as? Bool == false && (down.object["models"] as? [String])?.isEmpty == true && asked.last?.value(forHTTPHeaderField: "Authorization") == nil,
          "ai connections: a server that doesn't answer is “couldn't list” (the name can be typed), and this Mac's server is never sent a key")

    let connect = route(["op": "connect", "name": "DeepSeek 직접", "base": "https://api.example.com/v1/", "key": "sk-test-1234567890abcdef", "model": "deepseek-chat", "activate": true])
    let id = connect.object["id"] as? String ?? ""
    let saved = store.load()
    check(connect.status == "200 OK" && ArisAPIConnection.isID(id) && saved.connections == [ArisAPIConnection(id: id, name: "DeepSeek 직접", base: "https://api.example.com/v1")]
          && saved.active == id && saved.profile(id)?.strong == "deepseek-chat" && secrets.secret(for: id) == "sk-test-1234567890abcdef" && changed == 1
          && !((try? String(contentsOf: store.file, encoding: .utf8)) ?? "sk-test").contains("sk-test"),
          "ai connections: 연결 saves the name and address in the signed list, the key only in the Keychain, and makes it the brain that answers")
    let preset = ArisAPIPreset.named(id)
    check(preset?.dialect == .openAIChat && preset?.needsKey == true && preset?.allows(URL(string: "https://api.example.com/v1/chat/completions")!) == true
          && preset?.allows(URL(string: "http://api.example.com/v1/chat/completions")!) == false && preset?.allows(URL(string: "https://evil.example.com/v1/chat/completions")!) == false
          && saved.profile(id)?.base == "https://api.example.com/v1" && saved.profile(id)?.isValid == true && ArisAPIHelper.resolve(id, store: store)?.id == id,
          "ai connections: a connection is a provider like the shipped ones, and its key may only go over https to its own host")
    let listed = send(["op": "list"]).object["connections"] as? [[String: Any]] ?? []
    check(listed.count == 1 && listed[0]["name"] as? String == "DeepSeek 직접" && listed[0]["hasKey"] as? Bool == true && listed[0]["local"] as? Bool == false
          && listed[0]["model"] as? String == "deepseek-chat" && listed[0]["key"] == nil,
          "ai connections: settings hears each connection's name, address and whether a key is saved, never the key")
    check(send(["op": "save", "id": id, "strong": "deepseek-reasoner"]).status == "200 OK" && store.load().profile(id)?.strong == "deepseek-reasoner" && store.load().profile(id)?.quick == "deepseek-chat",
          "ai connections: a connection's model is changed the way a shipped provider's is")

    // Changing it: the saved key stays with its host.
    answer = Data(#"{"data":[{"id":"m1"}]}"#.utf8)
    check(route(["op": "probe", "id": id, "base": "https://api.example.com/v2"]).object["ok"] as? Bool == true && asked.last?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-1234567890abcdef"
          && route(["op": "probe", "id": id, "base": "https://other.example.com/v1"]).object["error"] as? String == ArisAPIConnectionRoutes.needsKeyLine
          && route(["op": "connect", "id": id, "base": "https://other.example.com/v1", "model": "m1"]).status.hasPrefix("400") && secrets.secret(for: id) == "sk-test-1234567890abcdef",
          "ai connections: while a connection is changed its saved key is used only for the same host; another host needs the key typed again")
    check(route(["op": "connect", "id": id, "name": "", "base": "https://api.example.com/v2", "model": "m1"]).status == "200 OK"
          && store.load().connections == [ArisAPIConnection(id: id, name: "api.example.com", base: "https://api.example.com/v2")] && store.load().profile(id)?.quick == "m1",
          "ai connections: a change keeps the id and the key; no name is the host's")
    check(route(["op": "connect", "base": "https://api.example.com/v1", "key": "sk-test-1234567890abcdef", "model": ""]).status.hasPrefix("400")
          && route(["op": "connect", "id": "conn-ffffffff", "base": "https://api.example.com/v1", "key": "sk-test-1234567890abcdef", "model": "m"]).status.hasPrefix("400")
          && route(["op": "connect", "base": "https://api.example.com/v1", "key": "has space in it", "model": "m"]).status.hasPrefix("400") && store.load().connections?.count == 1,
          "ai connections: no model, an unknown id or a key that can't be one saves nothing")

    // A second process (the API brain's helper) knows the connection from the signed list alone.
    ArisAPICustomPresets.set([])
    check(ArisAPIPreset.named(id) == nil && ArisAPIHelper.resolve(id, store: store)?.base == "https://api.example.com/v2" && ArisAPIPreset.named(id) != nil,
          "ai connections: reading the signed list is what makes a connection a known provider")
    let text = (try? String(contentsOf: store.file, encoding: .utf8)) ?? ""
    try? text.replacingOccurrences(of: "api.example.com", with: "evil.example.com").write(to: store.file, atomically: true, encoding: .utf8)
    check(store.load() == .empty && store.tampered && ArisAPIPreset.named(id) == nil,
          "ai connections: a list changed outside Aris (a connection pointed at another host) is no connection at all")
    try? text.write(to: store.file, atomically: true, encoding: .utf8)

    let gone = route(["op": "disconnect", "id": id])
    check(gone.status == "200 OK" && store.load().connections == nil && store.load().profile(id) == nil && store.load().active == nil && secrets.secret(for: id) == nil
          && ArisAPIPreset.named(id) == nil && store.load().profile("groq") != nil && route(["op": "disconnect", "id": "groq"]).status.hasPrefix("400"),
          "ai connections: 지우기 takes the connection, its model and its key away, and leaves the shipped providers alone")
    check(route(["op": "nonsense"]).status.hasPrefix("400") && send(["op": "nonsense"]).status.hasPrefix("400"), "ai connections: an unknown op is refused")
}
#endif
