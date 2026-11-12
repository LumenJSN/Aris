//
//  ArisAIServicesSheetModel.swift
//  Aris
//
//  AI 서비스's three sheets as data (mockup ai-services-D-connect): 다른 AI 연결… (a provider Aris knows the address of,
//  or an OpenAI-compatible address of the user's own with its key and model), ElevenLabs' Voice Library, and 링크로
//  추가…. What was typed, what was found, and what each sheet shows for it. A connection is saved only after its model
//  list was fetched, or with 그래도 저장 and a typed model name. Foundation only (tested).
//

import Foundation

/// 다른 AI 연결… (or 연결 고치기), as it stands.
struct ArisAIConnectDraft: Equatable, Sendable {
    enum Load: Equatable, Sendable { case idle, loading, listed, failed }

    /// The connection being changed (aris-agent's id); nil: a new one.
    var editing: String?
    /// A provider Aris ships, picked from 바로 고르기 (its id); nil: an address of the user's own.
    var shipped: String?
    var name = ""
    var base = ""
    var key = ""
    var model = ""
    var models: [String] = []
    var load = Load.idle
    /// What is wrong, by field ("base", "key", "model"), or with the whole sheet ("form").
    var errors: [String: String] = [:]
    /// Saving now.
    var busy = false
}

struct ArisAILibraryState: Equatable, Sendable {
    var query = ArisAILibraryQuery()
    /// nil: loading.
    var voices: [ArisAILibraryVoice]?
    var failed = false
    /// Library voice ids added in this sitting.
    var added: Set<String> = []
    var adding: String?
}

struct ArisAILinkState: Equatable, Sendable {
    var text = ""
    var error: String?
    var found: ArisAIEleven.Found?
    var busy = false
}

enum ArisAISheet: Equatable, Sendable {
    case connect(ArisAIConnectDraft)
    case library(ArisAILibraryState)
    case link(ArisAILinkState)
}

/// What a sheet's control asks for.
enum ArisAISheetAction: Equatable, Sendable {
    case close
    case quick(String)
    case loadModels
    /// 연결 / 저장; `force`: 그래도 저장 after the list couldn't be had.
    case save(force: Bool)
    case useShipped
    case searchLibrary
    case filter(String, String)
    case addFromLibrary(String)
    case checkLink
    case addLink
}

enum ArisAIConnect {
    static let badBase = "http:// 또는 https://로 시작하는 주소예요"
    static let httpElsewhere = "http:// 주소는 이 Mac(localhost)만 돼요. 다른 곳은 https://로 적어 주세요"
    static let needsKey = "클라우드 주소는 API 키가 필요해요"
    static let needsModel = "모델 이름을 적어 주세요"
    static let loopback: Set<String> = ["127.0.0.1", "localhost", "::1"]

    /// The address as aris-agent will keep it and whether it is this Mac, or what is wrong with it (aris-agent checks
    /// again: ArisAPIConnection.checkBase).
    static func checkBase(_ text: String) -> Result<(base: String, local: Bool), ArisAIConnectProblem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 200, !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return .failure(.init(text: badBase)) }
        let local = loopback.contains(host)
        guard scheme == "https" || local else { return .failure(.init(text: httpElsewhere)) }
        return .success((trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed, local))
    }

    /// What must be fixed before the address is asked for its models (불러오기) or saved; empty: go ahead.
    static func problems(_ draft: ArisAIConnectDraft, saving: Bool) -> [String: String] {
        switch checkBase(draft.base) {
        case .failure(let problem): return ["base": problem.text]
        case .success(let checked):
            // A connection being changed keeps its saved key (aris-agent uses it only for the same host).
            if !checked.local, draft.key.trimmingCharacters(in: .whitespaces).isEmpty, draft.editing == nil { return ["key": needsKey] }
            if saving, draft.model.trimmingCharacters(in: .whitespaces).isEmpty { return ["model": needsModel] }
            return [:]
        }
    }

    /// The draft after the address answered (or didn't) with its models.
    static func loaded(_ draft: ArisAIConnectDraft, models: [String]?) -> ArisAIConnectDraft {
        var next = draft
        next.errors = [:]
        guard let models, !models.isEmpty else {
            next.load = .failed
            next.models = []
            return next
        }
        next.load = .listed
        next.models = models
        if !models.contains(next.model) { next.model = models[0] }
        return next
    }

    /// The draft for changing a saved connection.
    static func editing(_ preset: ArisAIPreset, model: String) -> ArisAIConnectDraft {
        ArisAIConnectDraft(editing: preset.id, name: preset.title, base: preset.baseURL, model: model)
    }

    // MARK: What the sheet shows

    struct Field: Equatable, Sendable {
        let id: String
        let label: String
        let placeholder: String
        var secure = false
        var mono = false
        var error: String?
    }

    enum ModelControl: Equatable, Sendable {
        /// Fetched: a dropdown.
        case select(String)
        /// The list couldn't be had: typed.
        case field
        /// Not fetched yet (불러오면 골라요), or being fetched.
        case waiting(String)
    }

    enum Body: Equatable, Sendable {
        /// A provider Aris ships: a line about it, and its key field unless a key is saved or it needs none.
        case shipped(note: String, key: Field?, saved: Bool)
        case custom(fields: [Field], model: ModelControl, hint: String, hintTone: Tone)
    }

    enum Tone: Equatable, Sendable { case plain, ok, bad }

    struct View: Equatable, Sendable {
        let title: String
        let meta: String
        /// 바로 고르기: (id, name, picked). None while a connection is being changed.
        let quick: [QuickPick]
        let body: Body
        /// 그래도 저장 is offered.
        let force: Bool
        let primary: String
        let primaryEnabled: Bool
        var error: String?
    }

    struct QuickPick: Equatable, Sendable {
        let id: String
        let name: String
        let picked: Bool
    }

    static func view(_ draft: ArisAIConnectDraft, in state: ArisAIServicesState) -> View {
        let quick = draft.editing != nil ? [] : ArisAICatalogue.quickAPI.compactMap { id in
            state.preset(id).map { QuickPick(id: id, name: ArisAICatalogue.apiName($0), picked: draft.shipped == id) }
        }
        if let id = draft.shipped, let preset = state.preset(id) {
            let name = ArisAICatalogue.apiName(preset)
            let saved = state.profile(id)?.hasKey == true
            let note = preset.local ? "\(ArisParticle.attach(name, .eulReul)) 이 Mac에서 바로 써요"
                : ArisAICatalogue.listedAPI.contains(id) ? "\(ArisParticle.attach(name, .eunNeun)) 목록에 이미 있어요"
                : "\(ArisParticle.attach(name, .eunNeun)) Aris가 주소를 알고 있어요 · API 키만 넣으면 돼요"
            let key = preset.needsKey && !saved ? Field(id: "key", label: "API 키", placeholder: "\(name) API 키", secure: true, error: draft.errors["key"]) : nil
            return View(title: "다른 AI 연결", meta: "생각에 써요 · OpenAI 호환 주소", quick: quick, body: .shipped(note: note, key: key, saved: preset.needsKey && saved),
                        force: false, primary: "\(name) 쓰기", primaryEnabled: !draft.busy, error: draft.errors["form"])
        }
        let local = (try? checkBase(draft.base).get())?.local ?? false
        let keyHint = draft.editing != nil && draft.key.isEmpty ? "저장된 키를 그대로 써요" : local ? "이 Mac 서버는 없어도 돼요" : "클라우드 주소는 꼭 필요해요"
        let fields = [
            Field(id: "name", label: "이름", placeholder: "없어도 돼요"),
            Field(id: "base", label: "주소", placeholder: "https://example.com/v1", mono: true, error: draft.errors["base"]),
            Field(id: "key", label: "API 키", placeholder: keyHint, secure: true, error: draft.errors["key"]),
        ]
        let model: ModelControl
        let hint: String
        let tone: Tone
        switch draft.load {
        case .listed:
            (model, hint, tone) = (.select(draft.model), "연결됐어요 · 모델 \(draft.models.count)개", .ok)
        case .failed:
            (model, hint, tone) = (.field, draft.errors["model"] ?? "목록을 못 불러왔어요 · 주소를 확인하거나 모델 이름을 적어요", .bad)
        case .loading:
            (model, hint, tone) = (.waiting("불러오는 중…"), asks(draft.base), .plain)
        case .idle:
            (model, hint, tone) = (.waiting("불러오면 골라요"), asks(draft.base), .plain)
        }
        return View(title: draft.editing == nil ? "다른 AI 연결" : "연결 고치기", meta: "생각에 써요 · OpenAI 호환 주소", quick: quick,
                    body: .custom(fields: fields, model: model, hint: hint, hintTone: tone), force: draft.load == .failed,
                    primary: draft.editing == nil ? "연결" : "저장", primaryEnabled: draft.load == .listed && !draft.busy, error: draft.errors["form"])
    }

    /// Which address 불러오기 will ask, under the model field.
    private static func asks(_ base: String) -> String {
        let typed = base.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? "주소를 적으면 그 주소의 /models로 확인해요" : "\(typed)/models로 확인해요"
    }

    /// The library sheet's row for a voice: 추가, or 추가됨 once it is in the account.
    static func isAdded(_ voice: ArisAILibraryVoice, in library: ArisAILibraryState, account: [ArisAIVoice]) -> Bool {
        library.added.contains(voice.id) || account.contains { $0.id == voice.id }
    }
}

struct ArisAIConnectProblem: Error, Equatable, Sendable {
    let text: String
}
