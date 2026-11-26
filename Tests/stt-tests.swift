// jv-stt: who hears a turn. The pure pieces are tested with `swift test` (Tests/ArisCoreTests/ArisRecogniseTests,
// ArisHeardRepairTests); here, what they are joined to in the app: the stored choice and the settings page (the new
// engines, 자동, their keys), the word list's heard -> meant pairs, and the wiring in the app files the tests can't
// compile (read as text). Fixtures only: no provider is called, no key or Keychain is read, no sound.
import Foundation

func runSttTests() {
    sttStoreTests()
    sttPageTests()
    sttWordListTests()
    sttCoreSmokeTests()
    sttWiringTests()
}

private func sttPrefs(_ values: [String: Any]) -> (String) -> Any? { { values[$0] } }

private func sttStoreTests() {
    typealias Store = ArisAIStore
    check(Store.hearEngines == ["auto", "scribe", "soniox", "openai-stt", "whisper", "apple"], "stt store: the six choices, by the ids the turn reads (ArisHearEngine)")
    check(Store.read(sttPrefs([:]), facts: .init(hasElevenKey: true)).hear == "auto" && Store.read(sttPrefs([:]), facts: .init()).hear == "auto"
          && Store.read(sttPrefs(["arisCloudListening": true]), facts: .init(hasElevenKey: true)).hear == "auto",
          "stt store: nothing ever chosen reads as 자동 (Scribe first with its key, as before)")
    check(Store.read(sttPrefs(["arisCloudListening": false, "arisSpeechModel": "small"]), facts: .init(hasElevenKey: true)).hear == "whisper"
          && Store.read(sttPrefs(["arisCloudListening": false]), facts: .init(hasElevenKey: true)).hear == "apple",
          "stt store: the old Scribe switch turned off still keeps hearing on this Mac")
    for id in ["auto", "soniox", "openai-stt", "scribe", "whisper", "apple"] {
        let writes = Store.plan(.hear(id))
        var stored: [String: Any] = [:]
        for case .pref(let key, let value) in writes {
            switch value {
            case .text(let text): stored[key] = text
            case .flag(let flag): stored[key] = flag
            case .number(let number): stored[key] = number
            }
        }
        check(Store.read(sttPrefs(stored), facts: .init(hasElevenKey: true)).hear == id && ArisHearSource.migration(sttPrefs(stored), facts: .init(hasElevenKey: true)).isEmpty
              && ArisHearEngine.chosen(stored: stored["arisHearEngine"] as? String, cloudSwitch: stored["arisCloudListening"] as? Bool).rawValue == id,
              "stt store: picking \(id) is read back as \(id) by the page and by the turn, and the launch migration leaves it alone")
    }
    check(Store.plan(.hear("deepgram")).isEmpty, "stt store: an engine Aris has no client for writes nothing")
    check(ArisKeyFile.names.contains("soniox-key") && ArisKeyFile.names.contains("openai-key")
          && ArisAICatalogue.appKeys == ["elevenlabs": "elevenlabs-key", "soniox": "soniox-key", "openai-stt": "openai-key"]
          && ArisHearEngine.cloud.compactMap(\.keyName).allSatisfy(ArisKeyFile.names.contains),
          "stt keys: each cloud recogniser's key is one the app keeps in the Keychain (and redacts from diagnostics)")
}

private func sttPageTests() {
    func state(_ change: (inout ArisAIServicesState) -> Void) -> ArisAIServicesState { var s = ArisAIServicesState(); change(&s); return s }
    func lack(_ id: String, _ s: ArisAIServicesState) -> ArisAILack? { ArisAICatalogue.provider(.hear, id, in: s).flatMap { ArisAICatalogue.lack($0, in: s) } }
    let bare = state { $0.choices.hear = "soniox" }
    check(lack("soniox", bare) == .key && lack("openai-stt", bare) == .key && lack("auto", bare) == nil
          && lack("soniox", state { $0.hearKeys = ["soniox": "••••1234"] }) == nil && lack("openai-stt", state { $0.hearKeys = ["openai-stt": "••••1234"] }) == nil,
          "stt status: Soniox and OpenAI each need their own key; 자동 never needs one")
    let card = ArisAIServicesBuilder.page(bare).hear
    check(card.rows[0].warn == "키 필요" && card.rows[1].control == .fixed("stt-rt-v6")
          && card.need == .button(message: "Soniox API 키가 필요해요", title: "API 키 추가", .openKey("soniox")),
          "stt page: an engine without its key says so in a plain line, with the button that takes the key")
    let open = ArisAIServicesBuilder.page(state { $0.choices.hear = "openai-stt"; $0.ui.keyOpen = ["openai-stt"] }).hear
    check(open.need == .keyField(holder: "openai-stt", placeholder: "OpenAI API 키", hint: "키체인에 저장해요 · 듣기에만 써요", error: nil) && open.rows[1].control == .fixed("gpt-transcribe"),
          "stt page: the key field says where the key is kept and that only listening uses it")
    check(ArisAIServicesBuilder.page(state { $0.choices.hear = "scribe"; $0.elevenKey = "x" }).hear.rows[1].control == .fixed("Scribe v3 Live"),
          "stt page: Scribe is named by the model that listens now")

    let autoNone = ArisAIServicesBuilder.page(state { $0.choices.hear = "auto" }).hear
    check(autoNone.rows[0].desc == "자동 · 이 Mac에 머물러요" && autoNone.rows[1].control == .fixed("Apple") && autoNone.rows[1].desc == ArisAIServicesBuilder.autoNoCloud
          && autoNone.need == nil,
          "stt page: 자동 with no cloud key stays on this Mac and says in one line how to add a better recogniser")
    let autoAll = ArisAIServicesBuilder.page(state { $0.choices.hear = "auto"; $0.elevenKey = "x"; $0.hearKeys = ["soniox": "y", "openai-stt": "z"]; $0.whisperInstalled = ["small"] }).hear
    check(autoAll.rows[0].desc == "자동 · 음성이 Mac 밖으로 나가요" && autoAll.rows[1].control == .fixed("ElevenLabs Scribe → Soniox → OpenAI → Whisper") && autoAll.rows[1].desc.isEmpty,
          "stt page: 자동 shows the order it tries the recognisers in, the Mac's own last")
    check(ArisAIServicesBuilder.autoHears(state { $0.hearKeys = ["openai-stt": "z"] }) == ["OpenAI"], "stt page: only recognisers with a key are in 자동's order")

    let menu = ArisAIServicesBuilder.menu(.provider(.hear), state { $0.choices.hear = "auto"; $0.hearKeys = ["soniox": "y"] })
    let groups = menu.entries.compactMap { entry -> String? in if case .group(let title) = entry { return title }; return nil }
    func item(_ id: String) -> ArisAIMenuItem? { menu.items.first { $0.id == id } }
    check(menu.items.map(\.id) == ["auto", "apple", "whisper", "scribe", "soniox", "openai-stt"]
          && groups == ["추천", "이 Mac에서 · 이 Mac에 머물러요", "클라우드 · 음성이 Mac 밖으로 나가요"],
          "stt menu: 자동 first, then this Mac's engines, then the cloud's")
    check(item("auto")?.checked == true && item("soniox")?.tail == nil && item("soniox")?.disabled == false && item("openai-stt")?.tail == "키 필요"
          && item("openai-stt")?.disabled == false && item("scribe")?.tail == "키 필요" && item("deepgram") == nil,
          "stt menu: an engine without its key shows 키 필요 and can still be picked (the card then asks for the key)")
    check(ArisAIServicesBuilder.change(.provider(.hear), picked: "soniox", in: bare) == .hear("soniox")
          && ArisAIServicesBuilder.change(.provider(.hear), picked: "auto", in: bare) == .hear("auto")
          && ArisAIServicesBuilder.change(.provider(.hear), picked: "deepgram", in: bare) == nil,
          "stt menu: picking an engine stores it; one Aris can't use stores nothing")
    let saved = ArisAIServicesBuilder.page(state { $0.elevenKey = "••••a"; $0.hearKeys = ["soniox": "••••b", "openai-stt": "••••c"] }).savedKeys
    check(saved.map(\.holder) == ["elevenlabs", "soniox", "openai-stt"] && saved.map(\.name) == ["ElevenLabs", "Soniox", "OpenAI · 듣기"] && saved.allSatisfy { $0.masked != nil },
          "stt page: the recognisers' keys are listed with the saved keys, where they can be taken out again")
    check(ArisAIServicesBuilder.page(state { $0.choices.hear = "soniox"; $0.hearKeys = ["soniox": "y"]; $0.whisperInstalled = ["small"] }).voiceLine == "안 되면 이 Mac의 Whisper로 들어요"
          && ArisAIServicesBuilder.page(state { $0.choices.hear = "auto" }).voiceLine == nil,
          "stt page: under a cloud recogniser the line names what this Mac falls back to")

    let rows = ArisSettingsBuilder.sections(part: "talk.hear", ArisSettingsSnapshot()).flatMap(\.rows)
    check(rows.map(\.id) == ["ai.hear", "hear.mic", "voice.languages", "hear.repair", "hear.words"], "stt settings: 듣기 has the engine, the microphone, the languages, the repair switch and the word list")
    var on = ArisSettingsSnapshot()
    on.hearRepair = true
    let repair = ArisSettingsBuilder.sections(part: "talk.hear", on).flatMap(\.rows).first { $0.id == "hear.repair" }
    check(repair?.title == "들은 말 다듬기" && repair?.control == .toggle(.hearRepair, true), "stt settings: 들은 말 다듬기 is its own switch")
}

private func sttWordListTests() {
    let text = "# 내 단어\nNotion\n로션 -> 노션\n깃 허브 → GitHub\n"
    check(ArisVocabulary.words(from: text) == ["Notion", "노션", "GitHub"], "stt words: a pair's written form is a word the recognisers are told to expect")
    check(ArisVocabulary.own(file: text, learned: ["Vercel", "notion"]) == ["Notion", "노션", "GitHub", "Vercel"], "stt words: learned words follow the owner's, each once")
    check(ArisHeardFix.corrected(ArisHeardPairs.applied("깃 허브 열고 로션 정리해줘", pairs: ArisHeardPairs.entries(from: text).pairs)) == "GitHub 열고 노션 정리해줘",
          "stt words: the owner's pairs are put right in what was heard")
}

private func sttCoreSmokeTests() {
    let plan = ArisHearPlan.make(choice: .auto, keys: [.scribe, .openai], resting: [.scribe])
    check(plan.cloud == [.openai] && plan.live == nil && plan.notes.count == 1, "stt plan: a resting engine is skipped and said; OpenAI reads the recording (nothing streams)")
    let hints = ArisHearHints.build(.init(owner: "민준", words: ["깃허브"], lessons: ["출근 준비"], runningApps: ["Xcode"], installedApps: (1...99).map { "App \($0)" }), bounds: .scribe)
    check(hints.count == 50 && Array(hints.prefix(6)) == ["Aris", "아리스", "민준", "깃허브", "출근 준비", "Xcode"], "stt hints: names first, apps fill what is left, within Scribe's 50")
    let context = ArisHeardRepair.Context(hints: ["GitHub"], readings: [])
    check(ArisHeardRepair.settle(raw: "깃허브에 올려줘", reply: #"{"text":"GitHub에 올려줘"}"#, context: context).repaired
          && !ArisHeardRepair.settle(raw: "깃허브에 올려줘", reply: #"{"text":"네, 올렸습니다"}"#, context: context).repaired,
          "stt repair: a respelled term is taken, an answer is thrown away")
}

private func sttWiringTests() {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../Aris/private/Aris").standardized
    func source(_ name: String) -> String { (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "" }
    let scribe = source("ArisController+Scribe.swift"), hear = source("ArisController+Hear.swift"), controller = source("ArisController.swift")
    check(scribe.contains("let plan = ArisHearSetup.plan()") && scribe.contains("for note in plan.notes { log.notice(") && scribe.contains("guard let engine = plan.live"),
          "stt wiring: the turn's live recogniser comes from the plan, and why a chosen one isn't listening is logged")
    check(scribe.contains("ArisHearSetup.note(scribe.engine, answered: heard != nil)") && scribe.contains("liveFailed = scribe.engine"),
          "stt wiring: no answer counts against that engine and hands the turn on")
    let best = controller.range(of: "private func bestTranscript(").map { String(controller[$0.lowerBound...].prefix(1800)) } ?? ""
    let fallbackAt = best.range(of: "await cloudFallback(recording)")?.lowerBound, whisperAt = best.range(of: "whisperWithinBudget(recording")?.lowerBound
    check(fallbackAt != nil && whisperAt != nil && fallbackAt! < whisperAt!, "stt wiring: the other cloud engines read the recording before Whisper and Apple's live words")
    check(hear.contains("ArisHearPlan.fallbackTime(spent: .now - start)") && hear.contains("gave no answer: \\(engine.logName, privacy: .public) reads the recording"),
          "stt wiring: every fallback is inside the plan's limit and is a line in the log")
    let listen = controller.range(of: "func secondListen(").map { String(controller[$0.lowerBound...].prefix(700)) } ?? ""
    check(listen.contains("budgeted ? await repairedWords(fixed, apple: apple) : fixed"), "stt wiring: a talk turn's words are repaired; dictation keeps its own polish")
    check(hear.contains("guard ArisHearSetup.repairOn") && hear.contains("\"op\": \"route\"") && hear.contains("repair: \\(words.count, privacy: .public) characters, \\(outcome.note, privacy: .public)"),
          "stt wiring: the repair goes through the fast model aris-agent already calls, and logs lengths and the outcome, never the words")
    let clients = [source("Hearing/ArisSoniox.swift"), source("Hearing/ArisOpenAITranscribe.swift"), source("ArisScribe.swift"), hear, scribe, source("Hearing/ArisHearSetup.swift")]
    check(clients.allSatisfy { !$0.isEmpty } && clients.allSatisfy { text in
        text.components(separatedBy: "\n").filter { $0.contains("log.") || $0.contains("print(") }.allSatisfy { !$0.contains("key") || $0.contains("no key") }
    }, "stt wiring: no log line of a recogniser names a key's value")
    check(source("Hearing/ArisSoniox.swift").contains("forHTTPHeaderField: \"Authorization\"") && !source("Hearing/ArisSoniox.swift").contains("api_key"),
          "stt wiring: Soniox's key goes with the connection, never in the start message")
}
