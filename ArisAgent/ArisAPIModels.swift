//
//  ArisAPIModels.swift
//  aris-agent
//
//  Which models an API brain's provider offers (its list endpoint where it has one, else the preset's curated list),
//  what each can likely do (images, function calls), and the smoke check that records which models were tested with
//  Aris (cleanroom spec 14, §3.10): a short streamed answer, and one function call with the right argv (never run).
//

import Foundation

struct ArisAPIModel: Equatable, Sendable {
    let id: String
    var vision: Bool?
    var tools: Bool?
}

enum ArisAPIModels {
    /// The list request for a provider (nil when it has none).
    static func listRequest(profile: ArisAPIProfile, key: String?, strictOrigin: Bool = true) -> URLRequest? {
        guard let preset = profile.preset, let url = URL(string: profile.base + "/models") else { return nil }
        if strictOrigin { guard preset.allows(url) else { return nil } }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "GET"
        for (name, value) in preset.headers { request.setValue(value, forHTTPHeaderField: name) }
        ArisAPIDialects.authorize(&request, dialect: preset.dialect, key: key)
        return request
    }

    /// The models in a list answer, in the provider's order (chat models only where the provider says).
    static func parse(_ data: Data, dialect: ArisAPIDialect) -> [ArisAPIModel]? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch dialect {
        case .openAIChat, .anthropic:
            guard let list = object["data"] as? [[String: Any]] else { return nil }
            return list.compactMap { item in
                guard let id = item["id"] as? String, !id.isEmpty, id.count <= 200 else { return nil }
                // OpenRouter says what each takes and does.
                let modalities = (item["architecture"] as? [String: Any])?["input_modalities"] as? [String]
                let parameters = item["supported_parameters"] as? [String]
                return ArisAPIModel(id: id, vision: modalities.map { $0.contains("image") }, tools: parameters.map { $0.contains("tools") })
            }
        case .gemini:
            guard let list = object["models"] as? [[String: Any]] else { return nil }
            return list.compactMap { item in
                guard let name = item["name"] as? String, (item["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent") else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
                return id.isEmpty ? nil : ArisAPIModel(id: id, vision: true, tools: true)
            }
        }
    }

    /// What a model can likely do, from what the provider listed and its name; the profile can say otherwise.
    static func capabilities(preset: ArisAPIPreset, model: ArisAPIModel) -> (vision: Bool, tools: Bool) {
        let name = model.id.lowercased()
        let visionWords = ["vision", "-vl", "vl-", "llava", "gpt-4o", "gpt-5", "gpt-6", "gemini", "claude", "grok-4", "pixtral", "gemma3", "qwen2.5vl", "llama-4"]
        let vision = model.vision ?? (preset.vision || visionWords.contains { name.contains($0) })
        let tools = model.tools ?? !(name.contains("embed") || name.contains("whisper") || name.contains("tts") || name.contains("guard"))
        return (vision, tools)
    }

    /// The models for settings: the provider's list, or the curated one when it can't be had. Off the caller's queue.
    /// The list is read as it arrives and given up past 8 MiB (ArisAPIStreamTask's cap on a whole body).
    static func fetch(profile: ArisAPIProfile, key: String?, strictOrigin: Bool = true,
                      done: @escaping (_ models: [ArisAPIModel], _ fromProvider: Bool) -> Void) {
        let curated = (profile.preset?.curated ?? []).map { ArisAPIModel(id: $0) }
        guard let preset = profile.preset, let request = listRequest(profile: profile, key: key, strictOrigin: strictOrigin),
              !preset.needsKey || key != nil else { return done(curated, false) }
        let holder = ArisAPIOneShotHolder()
        var body: String?
        let task = ArisAPIStreamTask(request: request, totalTimeout: 10, idleTimeout: 10, queue: DispatchQueue(label: "com.lumenjsn.aris.api-models"),
                                     onEvents: { events in body = events.first { $0.name == "json" }?.data ?? body },
                                     onDone: { error in
            holder.task = nil
            guard error == nil, let data = body?.data(using: .utf8), let models = parse(data, dialect: preset.dialect), !models.isEmpty else {
                return done(curated, false)
            }
            done(Array(models.prefix(500)), true)
        })
        holder.task = task
        task.start()
    }
}

/// The smoke check behind Settings' 테스트 and the "tested with" list. Nothing it asks for is ever run.
enum ArisAPISmoke {
    struct Outcome: Equatable {
        var passed: [String] = []
        var failed: [String] = []
        var message = ""
        var ok: Bool { failed.isEmpty && !passed.isEmpty }
    }

    static let timeout: TimeInterval = 30

    /// Runs the probes in order, waiting (off any runner's queue). `ask` is ArisAPIOneShot.askNow (the tests pass a fake).
    static func run(profile: ArisAPIProfile, model: String, key: String?,
                    ask: (ArisAPIProfile, String, String, String, [ArisAPIFunction], TimeInterval, String?) -> Result<(text: String, calls: [ArisAPIToolCall]), ArisAPIError>
                        = { ArisAPIOneShot.askNow(profile: $0, model: $1, system: $2, user: $3, functions: $4, timeout: $5, key: $6) }) -> Outcome {
        var outcome = Outcome()
        switch ask(profile, model, "You are a test. Answer in one short Korean sentence.", "안녕이라고 한 문장으로 인사해 주세요.", [], timeout, key) {
        case .success(let answer) where !answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            outcome.passed.append("stream")
        case .success:
            outcome.failed.append("stream")
            outcome.message = "빈 답이 왔어요."
        case .failure(let error):
            outcome.failed.append("stream")
            outcome.message = message(error)
            return outcome
        }
        guard profile.callsTools else { return outcome }
        let timer = ArisAPICatalog.entry("timer").map { [$0.function] } ?? []
        switch ask(profile, model, "You are a test. Use the timer function when asked; don't answer in words.", "1분 타이머 맞춰 줘.", timer, timeout, key) {
        case .success(let answer) where answer.calls.contains(where: { ArisAPICatalog.argv(name: $0.name, arguments: $0.arguments) == ["timer", "1"] }):
            outcome.passed.append("tool")
        case .success:
            outcome.failed.append("tool")
            outcome.message = "도구를 제대로 부르지 못했어요. 이 모델은 글로 명령을 주고받는 방식(텍스트 릴레이)으로 써요."
        case .failure(let error):
            outcome.failed.append("tool")
            outcome.message = error.kind == .noTools ? "이 모델은 도구를 못 써서 텍스트 릴레이로 써요." : message(error)
        }
        return outcome
    }

    static func message(_ error: ArisAPIError) -> String {
        switch error.kind {
        case .auth: return "키가 맞지 않아요."
        case .quota: return "사용 한도나 크레딧이 부족해요."
        case .rate, .overloaded: return "지금 요청이 많아요. 잠시 뒤에 다시 해 주세요."
        case .network, .timeout: return "서버에 닿지 못했어요."
        case .unsupported: return "이 모델을 쓸 수 없어요: \(String(error.message.prefix(120)))"
        default: return String(error.message.prefix(120))
        }
    }
}
