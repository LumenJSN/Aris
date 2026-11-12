//
//  ArisAPIBrainSection.swift
//  Aris
//
//  AI 서비스 › 두뇌 › API 브레인: the minimal wiring for the API brains until the user picks a settings mockup. When 기본으로
//  답하는 AI is "API 키", the provider chosen here answers (OpenAI, Anthropic, Gemini API, OpenRouter, Groq, xAI,
//  Mistral, DeepSeek, or Ollama / LM Studio on this Mac). One row in ArisKeyRow's layout, built only from the page's own
//  parts (ArisMenuButton, ArisTextField, ArisSettingsButton, ArisChip): the provider, its key (a SecureField; it goes to
//  the agent once and lives only in the Keychain) or a local server's address, the quick and strong models, and 테스트.
//

import SwiftUI

@MainActor
final class ArisAPIBrainModel: ObservableObject {
    static let shared = ArisAPIBrainModel()

    @Published private(set) var list = ArisAPIBrainList()
    @Published private(set) var loaded = false
    @Published private(set) var reachable = true
    /// The provider shown (the active one, or the one the owner picked).
    @Published var selected = ""
    @Published var key = ""
    @Published var baseURL = ""
    @Published var quick = ""
    @Published var strong = ""
    @Published private(set) var models: [String] = []
    @Published var note: (ok: Bool, text: String)?
    @Published var busy = false
    var toast: (String) -> Void = { ArisSettingsOverlay.shared.show($0) }

    var preset: ArisAPIPresetRow? { list.presets.first { $0.id == selected } }
    var profile: ArisAPIProfileRow? { list.profiles.first { $0.id == selected } }
    var isActive: Bool { list.active == selected && !selected.isEmpty }

    func reload() async {
        let found = await ArisAgentClient.apiBrains()
        reachable = found != nil
        list = found ?? ArisAPIBrainList()
        loaded = true
        if selected.isEmpty || preset == nil { pick(list.active ?? list.presets.first?.id ?? "") }
    }

    /// Shows a provider: its saved models, or the preset's.
    func pick(_ id: String) {
        selected = id
        key = ""
        note = nil
        let saved = profile
        quick = saved?.quick ?? preset?.quick ?? ""
        strong = saved?.strong ?? preset?.strong ?? ""
        baseURL = saved?.baseURL ?? ""
        models = []
        Task { await loadModels() }
    }

    func loadModels() async {
        let id = selected
        guard !id.isEmpty else { return }
        let found = await ArisAgentClient.apiBrainModels(id)
        guard id == selected else { return }
        models = found
    }

    var modelOptions: [ArisSettingOption] {
        let all = models + [quick, strong].filter { !$0.isEmpty && !models.contains($0) }
        return all.map { ArisSettingOption(id: $0, title: $0) }
    }

    /// 저장: the key (when typed), the models, the address; it becomes the API brain that answers.
    func save() async {
        guard let preset else { return }
        busy = true
        defer { busy = false }
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if preset.needsKey, typed.isEmpty, profile?.hasKey != true {
            note = (false, "키를 붙여 넣어 주세요. 키 받는 곳: \(preset.keySource)")
            return
        }
        if let problem = await ArisAgentClient.saveAPIBrain(id: preset.id, key: typed.isEmpty ? nil : typed, quick: quick, strong: strong,
                                                            baseURL: preset.local ? baseURL : nil) {
            note = (false, problem)
            return
        }
        key = ""
        await reload()
        // An API brain can answer now: the status line and a new install's brain follow.
        await ArisBrainSetup.shared.refresh()
        await loadModels()
        toast("\(preset.title)를 API 브레인으로 저장했어요")
        await test()
    }

    func test() async {
        guard profile != nil else { note = (false, "먼저 저장해 주세요."); return }
        busy = true
        defer { busy = false }
        note = (true, "확인하는 중…")
        let result = await ArisAgentClient.testAPIBrain(selected, model: quick)
        note = (result.ok, result.ok ? "테스트 통과 · \(quick)" : result.message)
        await reload()
    }

    func remove() async {
        guard let preset else { return }
        if let problem = await ArisAgentClient.removeAPIBrain(preset.id) { return toast(problem) }
        await reload()
        await ArisBrainSetup.shared.refresh()
        pick(preset.id)
        toast("\(preset.title) 키를 키체인에서 지웠어요")
    }

    /// A dropdown's choice (ArisSettingKey.apiBrain).
    func choose(_ field: String, _ value: String) {
        switch field {
        case "provider": pick(value)
        case "quick": quick = value
        case "strong": strong = value
        default: break
        }
    }

    /// The chip: on when this provider answers and has what it needs.
    var status: (text: String, tone: ArisChipTone) {
        guard let profile else { return ("없음", .plain) }
        if preset?.needsKey == true, !profile.hasKey { return ("키 없음", .plain) }
        return isActive ? ("켜짐", .ok) : ("저장됨", .plain)
    }
}

/// The API brain's row (`.keyrow` layout): the provider and its key or address, the two models, and what the test said.
struct ArisAPIBrainRow: View {
    @Environment(\.arisPalette) private var palette
    @Environment(\.arisWords) private var w
    @ObservedObject var model: ArisAPIBrainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "key").font(.system(size: 16.5, weight: .medium)).foregroundStyle(palette.icon).frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(w("API 브레인")).font(.system(size: 14, weight: .medium)).tracking(-0.07).foregroundStyle(palette.title)
                        ArisChip(text: model.status.text, tone: model.status.tone)
                    }
                    Text(w("기본으로 답하는 AI를 ‘API 키’로 고르면 여기서 저장한 서비스가 답해요. 화면 보기, 할 일, 메시지 같은 기능은 그대로 쓰고, 보내거나 바꾸는 일은 똑같이 카드로 물어봐요."))
                        .font(.system(size: 12)).foregroundStyle(palette.desc).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.profile != nil {
                    HStack(spacing: 8) {
                        ArisSettingsButton(title: model.busy ? "확인 중…" : "테스트", small: true, enabled: !model.busy) { Task { await model.test() } }
                        ArisSettingsButton(title: "지우기", kind: .danger, small: true) { Task { await model.remove() } }
                    }
                }
            }
            detail.padding(.leading, 32)
        }
        .padding(ArisSettingsMetrics.rowInset)
        .task { if !model.loaded { await model.reload() } }
    }

    @ViewBuilder
    private var detail: some View {
        if !model.reachable {
            Text(w("Aris 에이전트가 답하지 않아요.")).font(.system(size: 12)).foregroundStyle(palette.red).padding(.top, 8)
        } else if let preset = model.preset {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ArisMenuButton(key: .apiBrain("provider"), title: "서비스", options: model.list.presets.map { ArisSettingOption(id: $0.id, title: $0.title) },
                                   selected: model.selected)
                    if preset.local {
                        ArisTextField(placeholder: preset.baseURL, text: $model.baseURL) { Task { await model.save() } }
                            .accessibilityLabel(w("\(preset.title) 주소"))
                    } else {
                        ArisTextField(placeholder: model.profile?.hasKey == true ? "키체인에 저장됨 · 바꾸려면 새 키 붙여 넣기" : "API 키 붙여 넣기",
                                      text: $model.key, secure: true) { Task { await model.save() } }
                            .accessibilityLabel(w("\(preset.title) API 키"))
                    }
                    ArisSettingsButton(title: model.busy ? "저장 중…" : "저장", kind: .primary, enabled: !model.busy) { Task { await model.save() } }
                }
                HStack(spacing: 8) {
                    ArisMenuButton(key: .apiBrain("quick"), title: "빠른 답 모델", options: model.modelOptions, selected: model.quick)
                    ArisMenuButton(key: .apiBrain("strong"), title: "큰 일 모델", options: model.modelOptions, selected: model.strong)
                }
                Text(line(preset)).font(.system(size: 12)).foregroundStyle(model.note.map { $0.ok ? palette.desc : palette.red } ?? palette.desc)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)
        } else {
            Text(w(model.loaded ? "API 브레인을 불러오지 못했어요." : "불러오는 중…")).font(.system(size: 12)).foregroundStyle(palette.desc).padding(.top, 8)
        }
    }

    /// The line under the fields, each part in the page's wording (the agent's own lines are looked up as they come).
    private func line(_ preset: ArisAPIPresetRow) -> String {
        if let problem = model.list.problem { return w(problem) }
        if let note = model.note { return w(note.text) }
        let tested = model.list.tested.contains(preset.id + "/" + model.quick) ? w(" · 테스트 통과") : ""
        if preset.local { return w("이 Mac의 서버를 써요 (비워 두면 \(preset.baseURL)). 키는 필요 없어요.") + tested }
        if model.profile?.hasKey == true { return w("키체인에 저장됨 · 왼쪽은 빠른 답, 오른쪽은 큰 일에 써요") + tested }
        return w("키 받는 곳: \(w(preset.keySource)). 키는 키체인에만 저장되고 AI나 로그에 보이지 않아요.")
    }
}
