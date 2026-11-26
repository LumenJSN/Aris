//
//  ArisAPIRouterCall.swift
//  aris-agent
//
//  The quick understanding on an API brain the user connected (설정 › AI 서비스 › 짧은 명령 빨리 알아듣기; the app side is
//  ArisRouterModels): POST /api-brains {"op": "route", "id" | "auto", "system", "user", "schema", "timeout"}. The app
//  sends the same questions it puts to TypeSafe's Jev, as one system prompt and a JSON schema; the key never leaves
//  this process. One small, fast model per provider (`router` on the profile overrides it), the provider's JSON mode
//  where it has one, thinking off where that is a switch, no stream, and one shared connection pool so a turn after
//  the first doesn't pay a new TLS handshake. Whatever goes wrong (no profile, a refusal, a cut or malformed answer, a
//  slow one) is said back as an error: the app then goes on with its keyword rules, exactly as when Jev fails. Nothing
//  of the words is logged here.
//

import Foundation

enum ArisAPIRouterCall {
    /// The small model per provider, checked on the providers' own model pages on 2026-11-19
    /// (platform.claude.com/docs/en/models/overview, developers.openai.com/api/docs/models/gpt-6-luna,
    /// ai.google.dev/gemini-api/docs/models: 2.5 Flash-Lite is still served and thinks only when asked).
    static let defaults: [String: String] = ["openai": "gpt-6-luna", "anthropic": "claude-haiku-5-5", "gemini": "gemini-2.5-flash-lite"]

    /// USD per million tokens (input, output), standard tier, the same pages on the same day.
    static let prices: [String: (input: Double, output: Double)] = [
        "gpt-6-luna": (0.10, 0.50), "claude-haiku-5-5": (0.10, 0.50), "gemini-2.5-flash-lite": (0.10, 0.40),
    ]

    /// Tokens one routing call takes (the app's prompt with about 120 apps, and four short answers): for 자동's pick.
    static let typicalInput = 2_000.0
    static let typicalOutput = 80.0
    /// A cap on the answer: four choices with their confidences fit in well under this.
    static let maxTokens = 300
    /// The longest question taken (the prompt is a few thousand characters; the words a sentence or two).
    static let maxSystem = 60_000
    static let maxUser = 4_000

    static func model(for profile: ArisAPIProfile) -> String { profile.router ?? defaults[profile.id] ?? profile.quick }

    /// What one call costs on `model`, when Aris knows its price.
    static func cost(_ model: String) -> Double? {
        prices[model].map { ($0.input * typicalInput + $0.output * typicalOutput) / 1_000_000 }
    }

    /// 자동: the connected profile (a keyed provider with its key) whose router model costs least per call; one whose
    /// price Aris doesn't know (DeepSeek's chat model) comes after every priced one, by its id, and is still taken
    /// (tenth VM run, item 7: with only DeepSeek connected 자동 silently fell to the keyword rules). Never a local
    /// server (it costs nothing but may take seconds to load its model) and never the owner's own connection (its
    /// server is unknown): those are asked only when he picks them.
    static func cheapest(_ brains: ArisAPIBrains, hasKey: (String) -> Bool) -> ArisAPIProfile? {
        brains.profiles
            .filter { profile in profile.preset?.needsKey == true && ArisAPIPreset.all.contains { $0.id == profile.id } && hasKey(profile.id) }
            .min { (cost(model(for: $0)) ?? .infinity, $0.id) < (cost(model(for: $1)) ?? .infinity, $1.id) }
    }

    /// One call's time limit (seconds): the app's "timeout" for a small routing model whose price is known, its
    /// "chatTimeout" for any other model (a chat model needs seconds, not 600 ms: ArisRouterPatience in the app).
    static func limit(_ object: [String: Any], model: String) -> TimeInterval {
        let small = (object["timeout"] as? NSNumber)?.doubleValue ?? 0.6
        let asked = cost(model) != nil ? small : (object["chatTimeout"] as? NSNumber)?.doubleValue ?? small
        return min(max(asked, 0.1), 5)
    }

    // MARK: - The request

    /// How a provider is asked for JSON.
    enum Mode: Equatable {
        /// A JSON schema the answer must follow (strict: OpenAI's own constrained decoding).
        case schema(strict: Bool)
        /// Any JSON object (DeepSeek's only JSON mode).
        case object
        /// No JSON mode: the strict parser alone (a user's own connection, whose server is unknown).
        case none
    }

    static func mode(_ preset: ArisAPIPreset) -> Mode {
        switch preset.dialect {
        case .anthropic, .gemini: return .schema(strict: true)
        case .openAIChat:
            if preset.id == "openai" { return .schema(strict: true) }
            if preset.id == "deepseek" { return .object }
            return ArisAPIPreset.all.contains { $0.id == preset.id } ? .schema(strict: false) : .none
        }
    }

    /// The body of one routing request (pure, for the tests).
    static func body(preset: ArisAPIPreset, model: String, system: String, user: String, schema: [String: Any]) -> [String: Any] {
        switch preset.dialect {
        case .openAIChat:
            var body: [String: Any] = ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
            body[preset.id == "openai" ? "max_completion_tokens" : "max_tokens"] = maxTokens
            switch mode(preset) {
            case .schema(let strict):
                body["response_format"] = ["type": "json_schema", "json_schema": ["name": "aris_route", "strict": strict, "schema": schema]]
            case .object: body["response_format"] = ["type": "json_object"]
            case .none: break
            }
            // GPT-6 Luna answers without reasoning first (reasoning_effort none, on its model page); another model may
            // not take "none", so only the default gets it.
            if preset.id == "openai", model == defaults["openai"] { body["reasoning_effort"] = "none" }
            // DeepSeek's models think unless told not to (both take it off).
            if ArisAPIPreset.isDeepSeek(preset: preset.id, base: preset.baseURL) { body["thinking"] = ["type": "disabled"] }
            return body
        case .anthropic:
            var body: [String: Any] = [
                "model": model, "max_tokens": maxTokens,
                "system": [["type": "text", "text": system, "cache_control": ["type": "ephemeral"]]],
                "messages": [["role": "user", "content": [["type": "text", "text": user]]]],
                "output_config": ["format": ["type": "json_schema", "schema": schema]],
            ]
            // Haiku takes thinking off (Haiku 5.5 at its default medium effort); Opus 5.5 and Sonnet 5.5 refuse it, so
            // they are left to think, and are usually too slow for the router's time limit anyway.
            if model.contains("haiku") { body["thinking"] = ["type": "disabled"] }
            return body
        case .gemini:
            return ["contents": [["role": "user", "parts": [["text": user]]]], "systemInstruction": ["parts": [["text": system]]],
                    "generationConfig": ["maxOutputTokens": maxTokens, "responseMimeType": "application/json",
                                         "responseSchema": ArisAPIDialects.geminiSchema(schema)]]
        }
    }

    /// The whole request, or nil when the profile's address or model can't be used. `testServer`: the tests' base.
    static func request(profile: ArisAPIProfile, model: String, key: String?, system: String, user: String, schema: [String: Any],
                        timeout: TimeInterval, strictOrigin: Bool = true, testServer: String? = nil) -> URLRequest? {
        guard let preset = profile.preset, ArisAPIRoutes.checkModel(model) == model, !model.isEmpty else { return nil }
        let path: String
        switch preset.dialect {
        case .openAIChat: path = "/chat/completions"
        case .anthropic: path = "/messages"
        case .gemini:
            guard let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) else { return nil }
            path = "/models/\(escaped):generateContent"
        }
        guard let url = URL(string: (testServer ?? profile.base) + path), let scheme = url.scheme, ["https", "http"].contains(scheme),
              let data = try? JSONSerialization.data(withJSONObject: body(preset: preset, model: model, system: system, user: user, schema: schema)) else { return nil }
        // The key goes only to its provider's own host over https (a local server: this Mac only).
        if strictOrigin { guard preset.allows(url) else { return nil } }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in preset.headers { request.setValue(value, forHTTPHeaderField: name) }
        ArisAPIDialects.authorize(&request, dialect: preset.dialect, key: key)
        return request
    }

    // MARK: - The reply

    enum Outcome: Equatable {
        case text(String)
        /// The provider declined (a refusal, a safety stop).
        case refused
        case failed(ArisAPIError.Kind, String)
    }

    /// A 200 body read into the answer's text, a refusal, or why it's no answer (cut at the cap, empty, not JSON).
    static func read(_ data: Data, dialect: ArisAPIDialect) -> Outcome {
        guard data.count <= 1_000_000, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .failed(.malformed, "the reply isn't JSON")
        }
        let text: String
        switch dialect {
        case .openAIChat:
            guard let choice = (object["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else {
                return .failed(.malformed, "no choice in the reply")
            }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty { return .refused }
            switch choice["finish_reason"] as? String {
            case "content_filter": return .refused
            case "length": return .failed(.malformed, "the answer was cut")
            default: break
            }
            text = message["content"] as? String ?? ""
        case .anthropic:
            switch object["stop_reason"] as? String {
            case "refusal": return .refused
            case "max_tokens": return .failed(.malformed, "the answer was cut")
            default: break
            }
            text = (object["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .gemini:
            if (object["promptFeedback"] as? [String: Any])?["blockReason"] != nil { return .refused }
            guard let candidate = (object["candidates"] as? [[String: Any]])?.first else { return .failed(.malformed, "no candidate in the reply") }
            switch candidate["finishReason"] as? String {
            case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": return .refused
            case "MAX_TOKENS": return .failed(.malformed, "the answer was cut")
            default: break
            }
            let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }.joined()
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .failed(.malformed, "the answer was empty") : .text(trimmed)
    }

    /// The outcome of one sent request: its data, its HTTP status (0: none), and the transport's error.
    static func outcome(data: Data?, status: Int, error: Error?, dialect: ArisAPIDialect, key: String?) -> Outcome {
        if let error {
            let timedOut = (error as? URLError)?.code == .timedOut
            return .failed(timedOut ? .timeout : .network, timedOut ? "no answer in time" : "the provider couldn't be reached")
        }
        guard status == 200 else {
            let failure = ArisAPIError.http(status: status, body: data ?? Data(), headers: [:])
            // The app logs this line: never the key's visible tail or a request id (ArisProviderWords).
            return .failed(failure.kind, ArisProviderWords.loggable(ArisAPISecrets.redacted(failure.message, secrets: [key].compactMap { $0 })))
        }
        return read(data ?? Data(), dialect: dialect)
    }

    // MARK: - The route

    typealias Send = (URLRequest, TimeInterval, @escaping (Data?, Int, Error?) -> Void) -> Void

    /// One pool for every routing call: its connection stays open between turns (an ephemeral session per request,
    /// as the streamed brain uses, would pay the TLS handshake every time). No cache, no cookies.
    private static let session: URLSession = {
        let configuration = ArisNoStore.configuration()
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    static let live: Send = { request, timeout, done in
        var request = request
        request.timeoutInterval = timeout
        session.dataTask(with: request) { data, response, error in
            done(data, (response as? HTTPURLResponse)?.statusCode ?? 0, error)
        }.resume()
    }

    /// The route op. `reply` is called once; a request on the network answers off the caller's queue.
    static func route(_ object: [String: Any], store: ArisAPIStore, secrets: ArisMCPSecretStore, strictOrigin: Bool = true,
                      testServer: String? = nil, send: @escaping Send = live, reply: @escaping (String, Data) -> Void) {
        let answer = { (body: [String: Any]) in reply("200 OK", ArisAPIRoutes.json(body)) }
        guard let system = object["system"] as? String, let user = object["user"] as? String, let schema = object["schema"] as? [String: Any],
              !user.isEmpty, system.count <= maxSystem, user.count <= maxUser, JSONSerialization.isValidJSONObject(schema) else {
            return reply("400 Bad Request", ArisAPIRoutes.json(["error": "그 질문은 받을 수 없어요."]))
        }
        let brains = store.load()
        let profile = object["auto"] as? Bool == true
            ? cheapest(brains, hasKey: { secrets.secret(for: $0) != nil })
            : (object["id"] as? String).flatMap(brains.profile)
        guard let profile, let preset = profile.preset else { return answer(["none": true]) }
        let key = preset.needsKey ? secrets.secret(for: profile.id) : nil
        guard !preset.needsKey || key != nil else { return answer(["none": true]) }
        let model = model(for: profile)
        let timeout = limit(object, model: model)
        guard let request = request(profile: profile, model: model, key: key, system: system, user: user, schema: schema, timeout: timeout,
                                    strictOrigin: strictOrigin, testServer: testServer) else {
            return answer(["error": "the provider's address or model isn't usable", "kind": ArisAPIError.Kind.unsupported.rawValue])
        }
        send(request, timeout) { data, status, error in
            switch outcome(data: data, status: status, error: error, dialect: preset.dialect, key: key) {
            case .text(let text): answer(["text": text, "profile": profile.id, "model": model])
            case .refused: answer(["error": "the provider declined", "kind": "refused", "profile": profile.id])
            case .failed(let kind, let message): answer(["error": message, "kind": kind.rawValue, "profile": profile.id])
            }
        }
    }
}
