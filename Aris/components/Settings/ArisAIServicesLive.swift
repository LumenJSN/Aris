//
//  ArisAIServicesLive.swift
//  Aris
//
//  설정 › AI 서비스 wired to the app. It fills the page's state from where each thing really lives (the preferences
//  through ArisAIStore, the keys in the Keychain, aris-agent's API brains and connections, the Whisper models on disk
//  and ArisModelDownloader, ElevenLabs' and this Mac's voice lists), and carries out what the page asks for: a choice
//  becomes ArisAIStore's writes and nothing else. Keys go to the Keychain only (ElevenLabs' and TypeSafe's through
//  ArisKeychain, an API brain's through aris-agent, which never gives one back).
//

import AppKit
import AVFoundation
import Combine
import SwiftUI

@MainActor
final class ArisAIServicesLive {
    static let shared = ArisAIServicesLive()

    let model = ArisAIServicesModel()
    private let keys = ArisKeysModel.Actions.live
    private var toast: (String) -> Void = { ArisSettingsOverlay.shared.show($0) }
    /// The same toast with the red mark: something that did not happen.
    private var fail: (String) -> Void = { ArisSettingsOverlay.shared.show($0, tone: .bad) }

    private var started = false
    private var watching: Set<AnyCancellable> = []
    /// aris-agent's active API brain, as it last said.
    private var agentActive: String?
    /// A brain picked on the page that can't answer yet (no key, its tool not installed): shown, and stored only once it can,
    /// so the brain that works keeps answering meanwhile.
    private var pendingThink: String?
    /// The Whisper model in use before a download began: 취소 goes back to it.
    private var whisperBefore: String?
    private var player: AVPlayer?
    private var playerEnd: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private var preview: Task<Void, Never>?
    private var librarySearch: Task<Void, Never>?
    private var signInChecks: Task<Void, Never>?
    /// Takes "방금 확인했어요" away again.
    private var checkedSign: Task<Void, Never>?
    /// When 연결된 서비스 first waited for the AIs in use; its wait ends ArisAIServicesBuilder.servicesWait later at most.
    private var servicesAsked: Date?
    /// aris-agent answered the page at least once (its brains or its API list): told apart from "it never answers".
    private var agentAnswered = false
    /// The page's own wording (English on an English Mac), for a line made here from parts.
    private var w: ArisSettingsWording { .make(page: .ai, english: ArisUILanguage.english) }

    private static let transport: ArisAITransport = { request in
        guard let (data, response) = try? await URLSession.shared.data(for: request), let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        return (data, status)
    }

    private init() {
        model.perform = { [weak self] action in self?.perform(action) }
        model.performSheet = { [weak self] action in self?.perform(sheet: action) }
    }

    // MARK: - Reading

    /// The page opened: everything fresh. What is on this Mac shows at once; aris-agent and ElevenLabs fill in as they answer.
    func reload() async {
        start()
        pendingThink = nil
        model.state.ui = ArisAIUI(servicesOpen: model.state.ui.servicesOpen)
        model.drafts = [:]
        refreshLocal()
        loadSystemVoices()
        waitForServices()
        Task { await loadElevenVoices() }
        await reloadAgent()
    }

    /// 연결된 서비스 shows "서비스를 확인하는 중…" only while the read of the AIs in use is waiting (it used to wait for
    /// ever on a Mac with none). The usage model here publishes only its list, so the read's state is worked out
    /// (ArisAIServicesBuilder.servicesRead); where the model publishes its own read state, `settleServices` takes that.
    private func waitForServices() {
        guard servicesAsked == nil else { return settleServices() }
        servicesAsked = Date()
        ArisUsageModel.shared.$providers.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.settleServices() }
        }.store(in: &watching)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisAIServicesBuilder.servicesWait))
            self?.settleServices()
        }
    }

    private func settleServices() {
        guard model.state.servicesRead == .waiting, let asked = servicesAsked else { return }
        agentAnswered = agentAnswered || !model.state.presets.isEmpty || ArisBrainSetup.shared.ready != nil
        model.state.servicesRead = ArisAIServicesBuilder.servicesRead(listed: ArisUsageModel.shared.providers.count, brainReady: model.state.brainReady,
                                                                      agentReachable: agentAnswered, waited: Date().timeIntervalSince(asked))
    }

    private func start() {
        guard !started else { return }
        started = true
        let downloader = ArisModelDownloader.shared
        downloader.$state.combineLatest(downloader.$model).receive(on: DispatchQueue.main).sink { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshLocal() }
        }.store(in: &watching)
        ArisBrainSetup.shared.$ready.receive(on: DispatchQueue.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshChoices() }
        }.store(in: &watching)
        // A sign-in finished in Terminal, a voice installed in System Settings: read again when Aris comes forward.
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, ArisSettingsNav.shared.page == .ai else { return }
                self.refreshLocal()
                self.loadSystemVoices()
            }
        }.store(in: &watching)
    }

    /// The keys, the Whisper models and the download, then the choices that follow from them.
    private func refreshLocal() {
        model.state.elevenKey = ArisElevenLabs.loadKey().map(ArisKeyFile.masked)
        model.state.jevKey = ArisKeyFile.load(ArisRouter.keyName).map(ArisKeyFile.masked)
        model.state.whisperInstalled = Set(ArisSpeechModel.allCases.filter(ArisWhisper.installed).map(\.rawValue))
        let downloader = ArisModelDownloader.shared
        let percent = downloader.state.percent
        switch downloader.state {
        case .idle, .done: model.state.download = nil
        case .running: model.state.download = ArisAIDownload(model: downloader.model.rawValue, percent: percent)
        case .waiting: model.state.download = ArisAIDownload(model: downloader.model.rawValue, percent: percent, phase: .waiting)
        case .paused: model.state.download = ArisAIDownload(model: downloader.model.rawValue, percent: percent, phase: .paused)
        case .failed: model.state.download = ArisAIDownload(model: downloader.model.rawValue, percent: percent, phase: .failed)
        }
        if downloader.state == .done, whisperBefore != nil {
            whisperBefore = nil
            toast(ArisAIServicesBuilder.whisper(downloader.model.rawValue).done)
        }
        refreshChoices()
    }

    /// The stored choices (ArisAIStore), with a brain that is picked but can't answer yet shown in place of the stored one.
    private func refreshChoices() {
        let facts = ArisAIStore.Facts(apiActive: agentActive, hasElevenKey: model.state.elevenKey != nil, whisperLargeInstalled: model.state.whisperInstalled.contains("large"),
                                      languages: ArisLanguages.starting(system: ArisLanguages.macLanguages))
        var choices = ArisAIStore.read({ UserDefaults.standard.object(forKey: $0) }, facts: facts)
        if let ready = ArisBrainSetup.shared.ready {
            model.state.brainReady = Dictionary(uniqueKeysWithValues: ready.map { ($0.key.rawValue, $0.value) })
        }
        // Nothing stored and no AI ready here: the preference reads only its default, which nobody chose, so none is
        // shown as chosen (the rule 대화's 기본으로 답하는 AI follows). Nothing is stored or changed by this.
        choices.think = ArisBrainChoice.shown(choices.think, stored: ArisBrainSetup.stored, ready: ArisBrainSetup.shared.ready)
        model.state.thinkStored = nil
        if let pending = pendingThink {
            var shown = model.state
            shown.choices.think = pending
            if ArisAICatalogue.lack(ArisAICatalogue.current(.think, in: shown), in: shown) == nil {
                // It can answer now (the key was saved, the tool was installed): it becomes the brain.
                pendingThink = nil
                choices.think = pending
                Task { await self.store(.think(pending)) }
            } else if pending != choices.think {
                model.state.thinkStored = choices.think
                choices.think = pending
            }
        }
        model.state.choices = choices
        settleServices()
    }

    /// aris-agent's API brains and connections, then the model lists the page shows (the chosen brain's, and the local
    /// servers', whose list says whether they are running).
    private func reloadAgent() async {
        let found = await ArisAgentClient.aiProviders()
        model.state.agentReachable = found != nil
        if let found {
            model.state.presets = found.presets
            model.state.profiles = found.profiles
            agentActive = found.active
        }
        refreshChoices()
        let shown = ArisAIStore.apiID(model.state.choices.think)
        let wanted = model.state.presets.filter { $0.id == shown || ($0.local && !$0.custom) }
        await withTaskGroup(of: Void.self) { group in
            for preset in wanted { group.addTask { await self.loadModels(preset) } }
        }
    }

    private func loadModels(_ preset: ArisAIPreset) async {
        // A keyed provider with no key has no list to ask for.
        if preset.needsKey, model.state.profile(preset.id)?.hasKey != true { return }
        if model.state.models[preset.id] == nil { model.state.models[preset.id] = .loading }
        let found = await ArisAgentClient.aiModels(preset)
        model.state.models[preset.id] = found
        refreshChoices()
        // The brain in use has no model yet (LM Studio ships with none): its first listed one answers, as the row shows.
        if case .listed(let list) = found, let first = list.first, pendingThink == nil, model.state.choices.think == "api:" + preset.id,
           (model.state.profile(preset.id)?.strong ?? preset.strong).isEmpty {
            await store(.thinkModel(provider: "api:" + preset.id, model: first))
        }
    }

    private func loadElevenVoices() async {
        guard let key = ArisElevenLabs.loadKey() else { model.state.voices["eleven"] = nil; return }
        if model.state.voices["eleven"] == nil { model.state.voices["eleven"] = .loading }
        let voices = await ArisAIEleven.loadVoices(key: key, transport: Self.transport)
        model.state.voices["eleven"] = voices.map { .loaded($0) } ?? .failed
        // The saved name can be stale (a voice renamed in the account).
        let choices = model.state.choices
        if let match = voices?.first(where: { $0.id == choices.elevenVoiceID }), match.name != choices.elevenVoiceName {
            await store(.elevenVoice(id: match.id, name: match.name))
        }
    }

    private func loadSystemVoices() {
        let installed = AVSpeechSynthesisVoice.speechVoices().map {
            ArisAISystemVoice(identifier: $0.identifier, name: $0.name, language: $0.language, quality: $0.quality.rawValue, gender: $0.gender.rawValue)
        }
        model.state.voices["macos"] = .loaded(ArisAISystemVoices.list(installed, languages: model.state.choices.languages, english: w.pageEnglish))
    }

    // MARK: - Writing

    /// Makes a change through the one store: its writes, in order. False when aris-agent refused one (said in a toast).
    @discardableResult
    func store(_ change: ArisAIChange) async -> Bool {
        for write in ArisAIStore.plan(change) {
            switch write {
            case .pref(let key, let value):
                switch value {
                case .text(let text): UserDefaults.standard.set(text, forKey: key)
                case .flag(let on): UserDefaults.standard.set(on, forKey: key)
                case .number(let number): UserDefaults.standard.set(number, forKey: key)
                }
            case .activate(let id):
                // A provider never saved before is saved with its own models first.
                let problem = model.state.profile(id) == nil ? await ArisAgentClient.aiSave(id, activate: true) : await ArisAgentClient.aiActivate(id)
                if let problem { fail(problem); return false }
                agentActive = id
            case .models(let id, let quick, let strong):
                // A local server or a connection runs one model: quick answers use it too.
                let single = model.state.preset(id).map { $0.local || $0.custom } ?? false
                if let problem = await ArisAgentClient.aiSave(id, quick: single ? strong : quick, strong: strong, activate: false) { fail(problem); return false }
                if let found = await ArisAgentClient.aiProviders() { (model.state.presets, model.state.profiles) = (found.presets, found.profiles) }
            }
        }
        refreshChoices()
        return true
    }

    private func perform(_ action: ArisAIAction) {
        switch action {
        case .pick(let kind, let id): pick(kind, id)
        case .openKey(let holder):
            model.state.ui.keyOpen.insert(holder)
            model.state.ui.keyError[holder] = nil
        case .cancelKey(let holder):
            model.state.ui.keyOpen.remove(holder)
            model.state.ui.keyError[holder] = nil
            model.drafts["key:" + holder] = nil
        case .saveKey(let holder, let key): Task { await saveKey(holder, key) }
        case .signIn(let brain): signIn(brain)
        case .recheckBrains:
            Task {
                guard await ArisBrainSetup.shared.refresh() else { return fail(ArisAgentCopy.notAnswering) }
                showChecked(ArisAIServicesBuilder.brainsChecked)
            }
        case .recheck(let provider):
            guard let id = ArisAIStore.apiID(provider), let preset = model.state.preset(id) else { return }
            // A key that has never answered: the helper's check is made again, and what it found is read back.
            if model.state.profile(id)?.unchecked == true {
                Task {
                    await verify(id)
                    showChecked(provider)
                }
                return
            }
            model.state.models[id] = .loading
            Task {
                await loadModels(preset)
                showChecked(provider)
            }
        case .download(let name):
            guard let pick = ArisSpeechModel(rawValue: name) else { return }
            whisperBefore = UserDefaults.standard.string(forKey: ArisAIPrefKey.speechModel) ?? ""
            model.state.ui.asking = nil
            ArisModelDownloader.shared.choose(pick)
            ArisModelDownloader.shared.accept()
        case .cancelDownload:
            ArisModelDownloader.shared.cancel()
            // Back to the model that was listening (the downloader forgets the pick).
            if let before = whisperBefore, model.state.whisperInstalled.contains(before) { UserDefaults.standard.set(before, forKey: ArisAIPrefKey.speechModel) }
            whisperBefore = nil
            refreshLocal()
        case .cancelAsk:
            model.state.ui.asking = nil
            // No model on this Mac at all: Whisper can't listen, so Apple's recognition goes on doing it.
            if model.state.whisperInstalled.isEmpty, model.state.choices.hear == "whisper" { pick(.provider(.hear), "apple") }
        case .retryDownload: ArisModelDownloader.shared.retryNow()
        case .openJev:
            model.state.ui.jevOpen = true
            model.state.ui.jevError = nil
        case .cancelJev:
            model.state.ui.jevOpen = false
            model.state.ui.jevError = nil
            model.drafts["jev"] = nil
        case .saveJev(let key): saveJev(key)
        case .clearJev:
            Task {
                let problem = await keys.delete(ArisRouter.keyName)
                if problem == nil { ArisRouterKeyHealth.write(nil) }
                refreshLocal()
                if let problem { fail(problem) } else { toast("TypeSafe 키를 키체인에서 지웠어요") }
            }
        case .preview: togglePreview()
        case .sample(let id, let url): toggleSample(id, url)
        case .commit(.model(let id), let text):
            guard !text.isEmpty else { return }
            Task { await store(.thinkModel(provider: "api:" + id, model: text)) }
        case .removeKey(let holder): Task { await removeKey(holder) }
        case .toggleServices: model.state.ui.servicesOpen.toggle()
        }
    }

    /// 다시 확인 has had its answer: the row it sits in says "방금 확인했어요" in its place for a few seconds (when the
    /// answer is that the AI is there now, the row is gone and so is the note), then the button is back.
    private func showChecked(_ what: String) {
        checkedSign?.cancel()
        model.state.ui.checked = what
        checkedSign = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ArisAIServicesBuilder.checkedShows))
            guard !Task.isCancelled, let self, self.model.state.ui.checked == what else { return }
            self.model.state.ui.checked = nil
        }
    }

    /// A dropdown's item: a stored choice, or one of the menu's own actions.
    private func pick(_ kind: ArisAIMenuKind, _ id: String) {
        switch kind {
        case .provider(.think):
            if id == "connect" { model.sheet = .connect(ArisAIConnectDraft()); return }
            guard let provider = ArisAICatalogue.provider(.think, id, in: model.state) else { return }
            if let lack = ArisAICatalogue.lack(provider, in: model.state), ArisAIKeyChoice.waits(lack) {
                // It can't answer yet: shown with what it needs, and stored once it can (the working brain keeps answering).
                // A key saved earlier that has never answered waits too, and is checked now (second upgrade run, bug 2).
                pendingThink = id
                if lack == .key, let holder = provider.keyHolder { model.state.ui.keyOpen.insert(holder) }
                refreshChoices()
                if lack == .check, let api = ArisAIStore.apiID(id) { Task { await verify(api) } }
                return
            }
            pendingThink = nil
            Task {
                guard await store(.think(id)) else { return }
                if let api = ArisAIStore.apiID(id), let preset = model.state.preset(api) { await loadModels(preset) }
            }
        case .provider(let job):
            guard let change = ArisAIServicesBuilder.change(kind, picked: id, in: model.state) else { return }
            model.state.ui.asking = nil
            Task {
                await store(change)
                if job == .hear, id == "apple", UserDefaults.standard.string(forKey: ArisAIPrefKey.speechModel) == nil {
                    // Apple's recognition was chosen: the notch doesn't offer a Whisper model after the next turn.
                    UserDefaults.standard.set(ArisModelOffer.later, forKey: ArisAIPrefKey.speechModel)
                }
                if job == .hear, id == "whisper" { await ArisWhisper.shared.prepare() }
                if job == .speak { stopSounds() }
            }
        case .model(.hear):
            guard model.state.whisperInstalled.contains(id) else {
                // Not on this Mac: asked first (630 MB 받을까요?).
                model.state.ui.asking = id
                return
            }
            model.state.ui.asking = nil
            Task {
                await store(.whisperModel(id))
                await ArisWhisper.shared.prepare()
            }
        case .model, .voice:
            if kind == .voice, id == "library" { openLibrary(); return }
            if kind == .voice, id == "link" { model.sheet = .link(ArisAILinkState()); return }
            guard let change = ArisAIServicesBuilder.change(kind, picked: id, in: model.state) else { return }
            Task { await store(change) }
        case .both:
            guard let company = ArisAICatalogue.both.first(where: { $0.id == id }), let hear = company.hear, let speak = company.speak else { return }
            Task {
                await store(.hear(hear))
                await store(.speak(speak))
                toast("듣기와 말하기를 \(ArisParticle.attach(company.name, .euroRo)) 맞췄어요")
            }
        case .connectionMore(let connection):
            guard let preset = model.state.preset(connection) else { return }
            if id.hasPrefix("edit:") {
                model.sheet = .connect(ArisAIConnect.editing(preset, model: model.state.profile(connection)?.strong ?? preset.strong))
            } else if id.hasPrefix("remove:") {
                Task { await removeConnection(preset) }
            }
        case .sheet(let name):
            switch model.sheet {
            case .connect(var draft)? where name == "model":
                draft.model = id
                model.sheet = .connect(draft)
            case .library(var library)?:
                library.query = library.query.setting(name, id)
                library.voices = nil
                model.sheet = .library(library)
                Task { await loadLibrary() }
            default: break
            }
        }
    }

    // MARK: Keys

    private func saveKey(_ holder: String, _ raw: String) async {
        if holder == "elevenlabs" {
            switch ArisKeyFile.check(raw) {
            case .failure(let problem): model.state.ui.keyError[holder] = problem.message
            case .success(let key):
                if let failure = keys.save("elevenlabs-key", key) { model.state.ui.keyError[holder] = failure; return }
                closeKey(holder)
                refreshLocal()
                toast("ElevenLabs API 키를 저장했어요")
                await loadElevenVoices()
            }
            return
        }
        // An API brain's key goes to aris-agent once (it checks the shape and keeps it in the Keychain).
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { model.state.ui.keyError[holder] = ArisKeyFile.Problem.empty.message; return }
        // A key for the brain that answers now replaces its key; a key for a brain only picked doesn't make it the brain:
        // it becomes the brain once the check below gets its first answer (refreshChoices), and until then the working
        // brain goes on answering, as the page says (second upgrade run, bug 2: a made-up Groq key replaced DeepSeek).
        let becomesBrain = ArisAIKeyChoice.activatesOnSave(holder: holder, pending: pendingThink, think: model.state.choices.think)
        if let problem = await ArisAgentClient.aiSave(holder, key: key, activate: becomesBrain) { model.state.ui.keyError[holder] = problem; return }
        closeKey(holder)
        toast("\(ArisAICatalogue.keyName(holder, in: model.state)) API 키를 저장했어요")
        // The saved key makes a pending pick the brain (refreshChoices sees it can answer now).
        await reloadAgent()
        await ArisBrainSetup.shared.refresh()
        await verify(holder)
    }

    /// After a key or a connection is saved: aris-agent's own short check (one greeting, one tool call that is never
    /// run), as the earlier page ran on 저장. A key that doesn't work is said now, not at the next question.
    private func verify(_ id: String) async {
        let result = await ArisAgentClient.testAPIBrain(id, model: nil)
        // Whether the key answered decides if it counts as an AI (ArisBrainChoice.needsCheck): read back either way.
        await reloadAgent()
        await ArisBrainSetup.shared.refresh()
        guard !result.ok, !result.message.isEmpty else { return }
        // The name as it is, aris-agent's line in the page's wording.
        toast("\(ArisAICatalogue.keyName(id, in: model.state)): \(w(result.message))")
    }

    private func closeKey(_ holder: String) {
        model.state.ui.keyOpen.remove(holder)
        model.state.ui.keyError[holder] = nil
        model.drafts["key:" + holder] = nil
    }

    private func saveJev(_ raw: String) {
        switch ArisKeyFile.check(raw) {
        case .failure(let problem): model.state.ui.jevError = problem.message
        case .success(let key):
            if let failure = keys.save(ArisRouter.keyName, key) { model.state.ui.jevError = failure; return }
            model.state.ui.jevOpen = false
            model.state.ui.jevError = nil
            model.drafts["jev"] = nil
            refreshLocal()
            toast("TypeSafe API 키를 저장했어요")
            // A key counts once it answered (ArisRouterKeyHealth): checked now with one short request, so a key TypeSafe
            // refuses is said on the status line at once, never "Everything is working" (second upgrade run, bug 2).
            ArisRouterKeyHealth.write(.unchecked)
            Task.detached { _ = try? await ArisRouter.ask(ArisRouterKeyHealth.checkWords, apps: [], key: key) }
        }
    }

    private func removeKey(_ holder: String) async {
        if holder == "elevenlabs" {
            let problem = await keys.delete("elevenlabs-key")
            model.state.voices["eleven"] = nil
            refreshLocal()
            if let problem { fail(problem) } else { toast("ElevenLabs 키를 키체인에서 지웠어요") }
            return
        }
        let name = ArisAICatalogue.keyName(holder, in: model.state)
        if let problem = await ArisAgentClient.removeAPIBrain(holder) { fail(problem); return }
        model.state.models[holder] = nil
        await reloadAgent()
        // It may have been the brain: the Mac is back to having picked none, and one that can answer takes over.
        await ArisBrainSetup.shared.keyRemoved()
        toast("\(name) 키를 키체인에서 지웠어요")
    }

    /// 로그인: the brain's own sign-in opens in Terminal (or the toast says its tool isn't installed); Aris looks
    /// again a few times afterwards, and when it comes forward.
    private func signIn(_ brain: String) {
        signInChecks?.cancel()
        signInChecks = Task { [weak self] in
            let opened = await ArisAgentClient.loginBrain(brain)
            let said = ArisSettingsBuilder.loginToast(opened: opened, brain: ArisBrain.named(brain))
            if opened { self?.toast(said) } else { self?.fail(said) }
            guard opened else { return }
            for wait in [5, 10, 20, 40] {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                await ArisBrainSetup.shared.refresh()
            }
        }
    }

    // MARK: Sounds

    private func stopSounds() {
        preview?.cancel()
        ArisController.shared.speaker.stop()
        player?.pause()
        player = nil
        if let playerEnd { NotificationCenter.default.removeObserver(playerEnd) }
        playerEnd = nil
        synthesizer.stopSpeaking(at: .immediate)
        model.state.ui.playing = nil
    }

    /// 미리 듣기: Aris says a line as it will really speak (the chosen engine, voice, model and speed); again stops it.
    private func togglePreview() {
        let was = model.state.ui.playing == ""
        stopSounds()
        guard !was else { return }
        model.state.ui.playing = ""
        preview = Task { [weak self] in
            await ArisController.shared.speaker.speak(ArisVoiceSample.line, preview: true)
            guard !Task.isCancelled, let self, self.model.state.ui.playing == "" else { return }
            self.model.state.ui.playing = nil
        }
    }

    /// A voice's own sample: ElevenLabs' recording, or a macOS voice saying a short line. Nothing is charged.
    private func toggleSample(_ id: String, _ url: String?) {
        let was = model.state.ui.playing == id
        stopSounds()
        guard !was else { return }
        if let url, let address = URL(string: url), address.scheme == "https" {
            let item = AVPlayerItem(url: address)
            player = AVPlayer(playerItem: item)
            playerEnd = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if self?.model.state.ui.playing == id { self?.model.state.ui.playing = nil } }
            }
            player?.play()
            model.state.ui.playing = id
        } else if let voice = AVSpeechSynthesisVoice(identifier: id) {
            let utterance = AVSpeechUtterance(string: voice.language.hasPrefix("ko") ? ArisVoiceSample.line : "Hello, I'm Aris. This is how I sound.")
            utterance.voice = voice
            synthesizer.speak(utterance)
            model.state.ui.playing = id
            // A short line: the button goes back by itself.
            preview = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.model.state.ui.playing == id else { return }
                self.model.state.ui.playing = nil
            }
        }
    }

    // MARK: - Sheets

    private func perform(sheet action: ArisAISheetAction) {
        switch action {
        case .close:
            librarySearch?.cancel()
            stopSounds()
            model.menu = nil
            model.sheet = nil
        case .quick(let id):
            guard case .connect(let draft)? = model.sheet else { return }
            model.sheet = .connect(ArisAIConnectDraft(shipped: draft.shipped == id ? nil : id))
        case .loadModels: Task { await loadConnectionModels() }
        case .save(let force): Task { await saveConnection(force: force) }
        case .useShipped: Task { await useShipped() }
        case .searchLibrary:
            librarySearch?.cancel()
            librarySearch = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await self?.loadLibrary()
            }
        case .filter(let name, let value): pick(.sheet(name), value)
        case .addFromLibrary(let id): Task { await addFromLibrary(id) }
        case .checkLink: Task { await checkLink() }
        case .addLink: Task { await addLink() }
        }
    }

    private func connectDraft() -> ArisAIConnectDraft? {
        if case .connect(let draft)? = model.sheet { return draft }
        return nil
    }

    /// 불러오기: the address's own model list, through aris-agent (it holds a saved connection's key).
    private func loadConnectionModels() async {
        guard var draft = connectDraft(), draft.load != .loading else { return }
        let problems = ArisAIConnect.problems(draft, saving: false)
        guard problems.isEmpty, case .success(let checked) = ArisAIConnect.checkBase(draft.base) else {
            draft.errors = problems
            model.sheet = .connect(draft)
            return
        }
        draft.errors = [:]
        draft.load = .loading
        model.sheet = .connect(draft)
        let answer = await ArisAgentClient.aiProbe(base: checked.base, key: draft.key.trimmingCharacters(in: .whitespacesAndNewlines), editing: draft.editing)
        // The sheet may have been closed or changed meanwhile.
        guard var now = connectDraft(), now.base == draft.base, now.load == .loading else { return }
        switch answer {
        case .success(let models): now = ArisAIConnect.loaded(now, models: models)
        case .failure(let problem):
            now.load = .idle
            now.errors = ["form": problem.text]
        }
        model.sheet = .connect(now)
    }

    private func saveConnection(force: Bool) async {
        guard var draft = connectDraft(), !draft.busy, force || draft.load == .listed else { return }
        let problems = ArisAIConnect.problems(draft, saving: true)
        guard problems.isEmpty, case .success(let checked) = ArisAIConnect.checkBase(draft.base) else {
            draft.errors = problems
            model.sheet = .connect(draft)
            return
        }
        draft.busy = true
        draft.errors = [:]
        model.sheet = .connect(draft)
        let answer = await ArisAgentClient.aiConnect(id: draft.editing, name: draft.name, base: checked.base, key: draft.key.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     model: draft.model.trimmingCharacters(in: .whitespaces))
        switch answer {
        case .failure(let problem):
            guard var now = connectDraft() else { return }
            now.busy = false
            now.errors = ["form": problem.text]
            model.sheet = .connect(now)
        case .success(let id):
            // aris-agent made it the API brain that answers; the app's own brain follows.
            model.sheet = nil
            pendingThink = nil
            agentActive = id
            UserDefaults.standard.set("api", forKey: ArisAIPrefKey.brain)
            model.state.models[id] = nil
            await reloadAgent()
            await ArisBrainSetup.shared.refresh()
            let name = model.state.preset(id)?.title ?? draft.name
            let named = ArisParticle.attach(name, .eulReul)
            toast(draft.editing == nil ? "\(named) 연결했어요" : "\(named) 고쳤어요")
            await verify(id)
        }
    }

    /// A provider Aris ships, picked in the sheet: its key (when it needs one that isn't saved), and it becomes the brain.
    private func useShipped() async {
        guard var draft = connectDraft(), let id = draft.shipped, let preset = model.state.preset(id), !draft.busy else { return }
        var key: String?
        if preset.needsKey, model.state.profile(id)?.hasKey != true {
            let typed = draft.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !typed.isEmpty else {
                draft.errors = ["key": "API 키를 붙여 넣어 주세요"]
                model.sheet = .connect(draft)
                return
            }
            key = typed
        }
        draft.busy = true
        model.sheet = .connect(draft)
        if let problem = await ArisAgentClient.aiSave(id, key: key, activate: true) {
            guard var now = connectDraft() else { return }
            now.busy = false
            now.errors = [key == nil ? "form" : "key": problem]
            model.sheet = .connect(now)
            return
        }
        model.sheet = nil
        pendingThink = nil
        agentActive = id
        UserDefaults.standard.set("api", forKey: ArisAIPrefKey.brain)
        await reloadAgent()
        await ArisBrainSetup.shared.refresh()
        if key != nil { await verify(id) }
    }

    private func removeConnection(_ preset: ArisAIPreset) async {
        if let problem = await ArisAgentClient.aiDisconnect(preset.id) { fail(problem); return }
        if pendingThink == "api:" + preset.id { pendingThink = nil }
        model.state.models[preset.id] = nil
        await reloadAgent()
        // It may have been the brain: the Mac is back to having picked none, and one that can answer takes over.
        await ArisBrainSetup.shared.keyRemoved()
        toast("\(ArisParticle.attach(preset.title, .eulReul)) 지웠어요")
    }

    // MARK: The library and a link

    private func openLibrary() {
        model.sheet = .library(ArisAILibraryState())
        Task { await loadLibrary() }
    }

    private func loadLibrary() async {
        guard case .library(let asked)? = model.sheet, let key = ArisElevenLabs.loadKey() else { return }
        let voices = await ArisAIEleven.loadLibrary(key: key, asked.query, english: w.pageEnglish, transport: Self.transport)
        // Typed further meanwhile: that search's own answer is the one shown.
        guard case .library(var now)? = model.sheet, now.query == asked.query else { return }
        now.voices = voices ?? []
        now.failed = voices == nil
        model.sheet = .library(now)
    }

    private func addFromLibrary(_ id: String) async {
        guard case .library(var library)? = model.sheet, let voice = library.voices?.first(where: { $0.id == id }), let key = ArisElevenLabs.loadKey(), library.adding == nil else { return }
        library.adding = id
        model.sheet = .library(library)
        let added = await ArisAIEleven.add(key: key, voice: voice, transport: Self.transport)
        if case .library(var now)? = model.sheet {
            now.adding = nil
            if added != nil { now.added.insert(id) }
            model.sheet = .library(now)
        }
        guard let added else { fail("추가하지 못했어요. 이 요금제에서 쓸 수 없는 목소리일 수 있어요."); return }
        await use(voiceID: added, name: voice.name)
    }

    /// A voice just added: it joins 내 목소리 and becomes Aris's voice.
    private func use(voiceID: String, name: String) async {
        await store(.elevenVoice(id: voiceID, name: name))
        await loadElevenVoices()
        toast("\(name) 목소리를 추가했어요")
    }

    private func checkLink() async {
        guard case .link(var link)? = model.sheet, !link.busy else { return }
        guard let id = ArisAIEleven.voiceID(fromLink: link.text) else {
            link.error = "링크나 ID를 못 읽었어요"
            model.sheet = .link(link)
            return
        }
        guard let key = ArisElevenLabs.loadKey() else { return }
        link.busy = true
        link.error = nil
        model.sheet = .link(link)
        let found = await ArisAIEleven.find(key: key, id: id, english: w.pageEnglish, transport: Self.transport)
        guard case .link(var now)? = model.sheet else { return }
        now.busy = false
        now.found = found
        now.error = found == nil ? "이 목소리를 찾지 못했어요. 링크를 다시 확인해 주세요." : nil
        model.sheet = .link(now)
    }

    private func addLink() async {
        guard case .link(var link)? = model.sheet, let found = link.found, !link.busy else { return }
        switch found {
        case .mine(let voice):
            model.sheet = nil
            await store(.elevenVoice(id: voice.id, name: voice.name))
            toast("목소리를 \(ArisParticle.attach(voice.name, .euroRo)) 바꿨어요")
        case .shared(let voice):
            guard let key = ArisElevenLabs.loadKey() else { return }
            link.busy = true
            model.sheet = .link(link)
            guard let added = await ArisAIEleven.add(key: key, voice: voice, transport: Self.transport) else {
                if case .link(var now)? = model.sheet {
                    now.busy = false
                    now.error = "추가하지 못했어요. 이 요금제에서 쓸 수 없는 목소리일 수 있어요."
                    model.sheet = .link(now)
                }
                return
            }
            model.sheet = nil
            await use(voiceID: added, name: voice.name)
        }
    }
}
